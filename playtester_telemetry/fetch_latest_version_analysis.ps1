<#
.SYNOPSIS
Read one build's telemetry or local JSON history and write an aggregate report.
.DESCRIPTION
From is inclusive and To is exclusive. Dates without offsets are interpreted as
UTC. LocalHistoryPath accepts run_history.json or a JSON object containing runs.
Local history does not contain reward offers or per-room damage events; missing
metrics are reported as unavailable, never inferred from a final build.
.EXAMPLE
.\fetch_latest_version_analysis.ps1 -Version 0.7.0 -From 2026-09-01 -To 2026-10-01
.EXAMPLE
.\fetch_latest_version_analysis.ps1 -Version dev-content-1 -LocalHistoryPath C:\Runs\run_history.json -OutputPath C:\Reports\content-1.json
#>
param(
    [string]$Version = '',
    [string]$From = '',
    [string]$To = '',
    [string]$OutputPath = '',
    [string]$LocalHistoryPath = '',
    [switch]$ValidateOnly,
    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'
$Version = $Version.Trim()
if ([string]::IsNullOrWhiteSpace($Version)) {
    throw 'Specify -Version explicitly so different game builds are not pooled.'
}
$dateStyles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
$fromDate = if ($From) { [DateTimeOffset]::Parse($From, [Globalization.CultureInfo]::InvariantCulture, $dateStyles) } else { [DateTimeOffset]::UtcNow.AddDays(-30) }
$toDate = if ($To) { [DateTimeOffset]::Parse($To, [Globalization.CultureInfo]::InvariantCulture, $dateStyles) } else { [DateTimeOffset]::UtcNow.AddSeconds(1) }
if ($fromDate -ge $toDate) { throw '-From must be earlier than the exclusive -To date.' }
$startUnix = $fromDate.ToUnixTimeSeconds()
$windowEndUnix = $toDate.ToUnixTimeSeconds()
if ($startUnix -ge $windowEndUnix) { throw 'The date window must cover at least one second.' }
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path ([IO.Path]::GetTempPath()) ('abyssal-balance-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
}
if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path (Get-Location).Path $OutputPath }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($OutputPath) -ne '.json') { throw '-OutputPath must name a JSON file.' }
if (-not (Test-Path -LiteralPath (Split-Path -Parent $OutputPath) -PathType Container)) { throw 'The output directory must already exist.' }
if ((Test-Path -LiteralPath $OutputPath) -and -not $Overwrite) { throw 'Output already exists. Choose another path or pass -Overwrite.' }
$sourceKind = 'supabase'
if ($LocalHistoryPath) {
    $LocalHistoryPath = (Resolve-Path -LiteralPath $LocalHistoryPath).Path
    if ([IO.Path]::GetExtension($LocalHistoryPath) -ne '.json') { throw '-LocalHistoryPath requires JSON history or exported JSON telemetry, not a binary .save file.' }
    if ($LocalHistoryPath -eq $OutputPath) { throw 'The analysis output must not overwrite its input history.' }
    $sourceKind = 'local_json'
}
if ($ValidateOnly) {
    [PSCustomObject]@{ Version = $Version; FromUtc = $fromDate.ToString('o'); ToExclusiveUtc = $toDate.ToString('o'); Source = $sourceKind; OutputPath = $OutputPath }
    return
}

$allRuns = New-Object System.Collections.Generic.List[object]
$seen = @{}
if ($LocalHistoryPath) {
    $raw = Get-Content -LiteralPath $LocalHistoryPath -Raw | ConvertFrom-Json
    if ($null -eq $raw) { throw 'The local history contains no runs.' }
    if ($raw -is [System.Array]) { $candidates = @($raw) }
    elseif ($raw.PSObject.Properties['runs']) { $candidates = @($raw.runs) }
    elseif ($raw.PSObject.Properties['game_version']) { $candidates = @($raw) }
    else { throw 'Local JSON must be an array of run summaries or an object containing runs.' }
    foreach ($run in $candidates) {
        if ($run -isnot [PSCustomObject]) { throw 'Local run entries must be JSON objects.' }
        if ([bool]$run.is_debug -or [string]$run.game_version -cne $Version) { continue }
        $started = [int64]$run.started_at_unix
        if ($started -lt $startUnix -or $started -ge $windowEndUnix) { continue }
        if ([string]$run.outcome -in @('', 'in_progress', 'debug')) { continue }
        $runId = [string]$run.run_id
        if (-not $runId) { $runId = [string]$run.id }
        if ($runId -and $seen.ContainsKey($runId)) { continue }
        if ($runId) { $seen[$runId] = $true }
        $allRuns.Add($run)
    }
} else {
    # Reuse the client's publishable configuration without printing credentials.
    # The balance RPC is SELECT-only; no setup/reset SQL is executed here.
    $projectConfig = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../project.godot') -Raw
    $endpointMatch = [regex]::Match($projectConfig, '(?m)^config/telemetry_upload_endpoint="([^"]*)"')
    $keyMatch = [regex]::Match($projectConfig, '(?m)^config/telemetry_upload_api_key="([^"]*)"')
    $endpoint = $endpointMatch.Groups[1].Value
    $marker = '/rest/v1/'
    $markerIndex = $endpoint.IndexOf($marker)
    if ($markerIndex -lt 0 -or -not $keyMatch.Success -or -not $keyMatch.Groups[1].Value) {
        throw 'The project has no configured telemetry read endpoint/key. Use -LocalHistoryPath instead.'
    }
    $base = $endpoint.Substring(0, $markerIndex) + '/rest/v1/rpc'
    $key = $keyMatch.Groups[1].Value
    $headers = @{ apikey = $key; Authorization = "Bearer $key"; 'Content-Type' = 'application/json' }
    $endUnix = $windowEndUnix
    $batchIndex = 0
    while ($true) {
        $batchIndex++
        if ($batchIndex -gt 50) { throw 'Query exceeded 50 pages; narrow the date window to avoid an incomplete report.' }
        $payload = @{ p_start_unix = $startUnix; p_end_unix = $endUnix; p_include_debug = $false; p_game_version = $Version; p_max_runs = 5000 } | ConvertTo-Json -Compress
        $resp = Invoke-RestMethod -Method Post -Uri "$base/get_balance_runs_between" -Headers $headers -Body $payload -TimeoutSec 30
        $batch = @($resp | Where-Object { $null -ne $_ })
        if ($batch.Count -eq 0) { break }
        $minStarted = [int64]::MaxValue
        foreach ($run in $batch) {
            $started = [int64]$run.started_at_unix
            if ($started -lt $startUnix -or $started -ge $endUnix -or [string]$run.game_version -cne $Version -or [bool]$run.is_debug) {
                throw 'The telemetry RPC returned a run outside the requested scope.'
            }
            if ($started -lt $minStarted) { $minStarted = $started }
            $runId = [string]$run.run_id
            if (-not $runId) { throw 'The telemetry RPC returned a run without an ID.' }
            if (-not $seen.ContainsKey($runId)) {
                $seen[$runId] = $true
                if ([string]$run.outcome -notin @('', 'in_progress', 'debug')) { $allRuns.Add($run) }
            }
        }
        Write-Host "Batch ${batchIndex}: $($batch.Count) runs, $($allRuns.Count) completed unique runs"
        if ($batch.Count -lt 5000) { break }
        # Re-fetch the boundary second, deduplicating IDs. A timestamp-only RPC
        # cannot safely paginate 5000+ rows in one second; fail instead of skip.
        $nextEnd = $minStarted + 1
        if ($nextEnd -ge $endUnix) { throw 'Too many runs share a pagination timestamp; the server needs an ID cursor before this sample can be analyzed safely.' }
        $endUnix = $nextEnd
    }
}
$runs = $allRuns.ToArray()
if ($runs.Count -eq 0) { throw "No completed non-debug runs found for $Version in the requested UTC window." }
$coverage = [ordered]@{}
foreach ($field in @('damage_events', 'room_entries', 'reward_choices', 'reward_offers', 'door_choices', 'build_summary', 'equipped_catalyst_ids', 'ascension_rank', 'is_multiplayer', 'full_run_tracking_complete')) {
    $coverage[$field] = @($runs | Where-Object { $null -ne $_.PSObject.Properties[$field] }).Count
}
$limitations = New-Object System.Collections.Generic.List[string]
if ($runs.Count -lt 5) { $limitations.Add('Fewer than five runs: use individual playtest evidence, not numerical balance conclusions.') }
elseif ($runs.Count -lt 10) { $limitations.Add('Fewer than ten runs: treat aggregate patterns as tentative.') }
if ($Version -eq 'dev') { $limitations.Add('The version dev does not identify a patch. Compare dates and manual playtest notes; do not assume all dev runs used the same code.') }
if ($coverage.reward_offers -lt $runs.Count) { $limitations.Add('Some or all runs lack reward offers. Final build presence is not pick rate.') }
if ($coverage.room_entries -lt $runs.Count -or $coverage.damage_events -lt $runs.Count) { $limitations.Add('Some or all runs lack room/damage events. Encounter pressure and activity proxies are unavailable or partial.') }
$limitations.Add('Damage-event frequency measures damage received, not player activity or enjoyment.')
if ($sourceKind -eq 'supabase') { $limitations.Add('Remote telemetry currently omits Catalyst and Ascension loadouts; do not interpret missing fields as unequipped/default.') }
function Get-Percentile([double[]]$vals, [double]$p) {
    if ($null -eq $vals -or $vals.Count -eq 0) { return 0.0 }
    $sorted = $vals | Sort-Object
    if ($sorted.Count -eq 1) { return [double]$sorted[0] }
    $rank = ($sorted.Count - 1) * $p
    $lo = [math]::Floor($rank)
    $hi = [math]::Ceiling($rank)
    if ($lo -eq $hi) { return [double]$sorted[$lo] }
    $w = $rank - $lo
    return [double]$sorted[$lo] * (1 - $w) + [double]$sorted[$hi] * $w
}

$outcomes = @{}
$durations = New-Object System.Collections.Generic.List[double]
$dpmVals = New-Object System.Collections.Generic.List[double]
$deathDepths = New-Object System.Collections.Generic.List[double]
$deathBySource = @{}
$deathByEncounter = @{}
$damageBySource = @{}
$entryByEncounter = @{}
$damageByEncounter = @{}
$arcanaPickCounts = @{}
$boonPickCounts = @{}
$arcanaOutcome = @{}
$holdLineDamage = [double]0
$holdLineShielder = [double]0
$charCounts = @{}
$charOutcomes = @{}
$charByBearing = @{}
$arcanaOfferCounts = @{}
$boonOfferCounts = @{}

foreach ($r in $runs) {
    $out = [string]$r.outcome
    if (-not $outcomes.ContainsKey($out)) { $outcomes[$out] = 0 }
    $outcomes[$out]++

    $duration = [double]$r.duration_seconds
    if ($duration -le 0) { $duration = [double]([int64]$r.ended_at_unix - [int64]$r.started_at_unix) }
    if ($duration -lt 1) { $duration = 1 }
    $durations.Add($duration) | Out-Null

    $damageEvents = @(); if ($r.damage_events -is [System.Array]) { $damageEvents = $r.damage_events }
    $dpm = ([double]$damageEvents.Count) / ($duration / 60.0)
    $dpmVals.Add($dpm) | Out-Null

    $roomEntries = @(); if ($r.room_entries -is [System.Array]) { $roomEntries = $r.room_entries }
    $objectiveByDepth = @{}
    foreach ($re in $roomEntries) {
        $ek = [string]$re.bearing_key; if ([string]::IsNullOrWhiteSpace($ek)) { $ek = 'unknown' }
        if (-not $entryByEncounter.ContainsKey($ek)) { $entryByEncounter[$ek] = 0 }
        $entryByEncounter[$ek]++
        $rd = [string]$re.room_depth
        $objectiveByDepth[$rd] = [string]$re.objective_kind
    }

    foreach ($d in $damageEvents) {
        $src = [string]$d.source; if ([string]::IsNullOrWhiteSpace($src)) { $src = 'unknown' }
        $amt = 0.0; if ($null -ne $d.final_amount) { $amt = [double]$d.final_amount }
        if (-not $damageBySource.ContainsKey($src)) { $damageBySource[$src] = 0.0 }
        $damageBySource[$src] += $amt

        $ek = [string]$d.bearing_key; if ([string]::IsNullOrWhiteSpace($ek)) { $ek = 'unknown' }
        if (-not $damageByEncounter.ContainsKey($ek)) { $damageByEncounter[$ek] = 0.0 }
        $damageByEncounter[$ek] += $amt

        $dd = [string]$d.room_depth
        $obj = ''; if ($objectiveByDepth.ContainsKey($dd)) { $obj = [string]$objectiveByDepth[$dd] }
        if ($obj -eq 'hold_the_line') {
            $holdLineDamage += $amt
            if ($src -eq 'enemy_shielder') { $holdLineShielder += $amt }
        }
    }

    if ($out -eq 'death' -and $null -ne $r.death_event) {
        $de = $r.death_event
        if ($null -ne $de.room_depth) { $deathDepths.Add([double]$de.room_depth) | Out-Null }
        elseif ($null -ne $r.max_depth) { $deathDepths.Add([double]$r.max_depth) | Out-Null }
        $ds = [string]$de.source; if ([string]::IsNullOrWhiteSpace($ds)) { $ds = 'unknown' }
        if (-not $deathBySource.ContainsKey($ds)) { $deathBySource[$ds] = 0 }
        $deathBySource[$ds]++
        $dk = [string]$de.bearing_key; if ([string]::IsNullOrWhiteSpace($dk)) { $dk = 'unknown' }
        if (-not $deathByEncounter.ContainsKey($dk)) { $deathByEncounter[$dk] = 0 }
        $deathByEncounter[$dk]++
    }

    $rewards = @(); if ($r.reward_choices -is [System.Array]) { $rewards = $r.reward_choices }
    $arcanaThisRun = @()
    foreach ($c in $rewards) {
        if ([bool]$c.skipped -or [string]::IsNullOrWhiteSpace([string]$c.choice_id)) { continue }
        $mode = [int]$c.mode
        $cid = [string]$c.choice_id
        if ($mode -eq 3) {
            if (-not $arcanaPickCounts.ContainsKey($cid)) { $arcanaPickCounts[$cid] = 0 }
            $arcanaPickCounts[$cid]++
            $arcanaThisRun += $c
        }
        elseif ($mode -eq 1) {
            if (-not $boonPickCounts.ContainsKey($cid)) { $boonPickCounts[$cid] = 0 }
            $boonPickCounts[$cid]++
        }
    }

    if ($arcanaThisRun.Count -gt 0) {
        $opening = $arcanaThisRun | Sort-Object { [int64]$_.unix_time } | Select-Object -First 1
        $openId = [string]$opening.choice_id
        if (-not $arcanaOutcome.ContainsKey($openId)) {
            $arcanaOutcome[$openId] = @{ runs = 0; clears = 0; deaths = 0; avgDepth = 0.0 }
        }
        $arcanaOutcome[$openId].runs++
        if ([string]$r.outcome -eq 'clear') { $arcanaOutcome[$openId].clears++ }
        if ([string]$r.outcome -eq 'death') { $arcanaOutcome[$openId].deaths++ }
        $arcanaOutcome[$openId].avgDepth += [double]$r.max_depth
    }

    # --- character aggregates ---
    $cid = [string]$r.character_id; if ([string]::IsNullOrWhiteSpace($cid)) { $cid = 'unknown' }
    if (-not $charCounts.ContainsKey($cid)) { $charCounts[$cid] = 0 }
    $charCounts[$cid]++
    if (-not $charOutcomes.ContainsKey($cid)) {
        $charOutcomes[$cid] = @{ runs = 0; clears = 0; deaths = 0; avgDepth = 0.0 }
    }
    $charOutcomes[$cid].runs++
    if ($out -eq 'clear') { $charOutcomes[$cid].clears++ }
    if ($out -eq 'death') { $charOutcomes[$cid].deaths++ }
    $charOutcomes[$cid].avgDepth += [double]$r.max_depth

    $tier = [string]$r.difficulty_tier
    $cbKey = "${cid}__${tier}"
    if (-not $charByBearing.ContainsKey($cbKey)) {
        $charByBearing[$cbKey] = @{ character = $cid; difficulty_tier = $tier; runs = 0; clears = 0; deaths = 0 }
    }
    $charByBearing[$cbKey].runs++
    if ($out -eq 'clear') { $charByBearing[$cbKey].clears++ }
    if ($out -eq 'death') { $charByBearing[$cbKey].deaths++ }

    # --- offer-side pick-rate aggregates ---
    # Each reward_offers entry is a presentation event: { mode, offers: [{choice_id, ...}, ...], ... }
    $offerEvents = @(); if ($r.reward_offers -is [System.Array]) { $offerEvents = $r.reward_offers }
    foreach ($o in $offerEvents) {
        $mode = [int]$o.mode
        $innerOffers = @(); if ($o.offers -is [System.Array]) { $innerOffers = $o.offers }
        foreach ($item in $innerOffers) {
            $oid = [string]$item.choice_id; if ([string]::IsNullOrWhiteSpace($oid)) { continue }
            if ($mode -eq 3) {
                if (-not $arcanaOfferCounts.ContainsKey($oid)) { $arcanaOfferCounts[$oid] = 0 }
                $arcanaOfferCounts[$oid]++
            } elseif ($mode -eq 1) {
                if (-not $boonOfferCounts.ContainsKey($oid)) { $boonOfferCounts[$oid] = 0 }
                $boonOfferCounts[$oid]++
            }
        }
    }
}

$durationArr = [double[]]$durations.ToArray()
$dpmArr = [double[]]$dpmVals.ToArray()
$q75Dur = Get-Percentile $durationArr 0.75
$q25Dpm = Get-Percentile $dpmArr 0.25
$longLow = 0
for ($i = 0; $i -lt $runs.Count; $i++) {
    if ($durationArr[$i] -gt $q75Dur -and $dpmArr[$i] -lt $q25Dpm) { $longLow++ }
}

$deathDepthArr = [double[]]$deathDepths.ToArray()
$deathMedian = Get-Percentile $deathDepthArr 0.5
$deathQ25 = Get-Percentile $deathDepthArr 0.25
$deathQ75 = Get-Percentile $deathDepthArr 0.75

$topDeaths = $deathBySource.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8
$topDamageSrc = $damageBySource.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8

$encPressure = @()
foreach ($k in $entryByEncounter.Keys) {
    $entries = [double]$entryByEncounter[$k]
    $dmg = 0.0; if ($damageByEncounter.ContainsKey($k)) { $dmg = [double]$damageByEncounter[$k] }
    $deaths = 0; if ($deathByEncounter.ContainsKey($k)) { $deaths = [int]$deathByEncounter[$k] }
    $encPressure += [PSCustomObject]@{
        encounter             = $k
        entries               = [int]$entries
        total_damage          = [math]::Round($dmg, 1)
        deaths                = $deaths
        damage_per_entry      = [math]::Round(($dmg / [math]::Max($entries, 1)), 2)
        deaths_per_100_entries = [math]::Round((100.0 * $deaths / [math]::Max($entries, 1)), 2)
    }
}
$encPressure = $encPressure | Sort-Object deaths_per_100_entries, damage_per_entry -Descending | Select-Object -First 10

$topArcana = $arcanaPickCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
$topBoon = $boonPickCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10

$arcanaEffect = @()
foreach ($k in $arcanaOutcome.Keys) {
    $v = $arcanaOutcome[$k]
    $runsN = [double]$v.runs
    $arcanaEffect += [PSCustomObject]@{
        arcana         = $k
        runs           = [int]$v.runs
        clear_rate_pct = [math]::Round((100.0 * $v.clears / [math]::Max($runsN, 1)), 2)
        death_rate_pct = [math]::Round((100.0 * $v.deaths / [math]::Max($runsN, 1)), 2)
        avg_max_depth  = [math]::Round(($v.avgDepth / [math]::Max($runsN, 1)), 2)
    }
}
$arcanaEffect = $arcanaEffect | Sort-Object -Property @{ Expression = 'runs'; Descending = $true }, @{ Expression = 'clear_rate_pct'; Descending = $true } | Select-Object -First 10

# --- character popularity ---
$charPopularity = @()
foreach ($k in $charOutcomes.Keys) {
    $v = $charOutcomes[$k]
    $n = [double]$v.runs
    $charPopularity += [PSCustomObject]@{
        character      = $k
        runs           = [int]$v.runs
        clear_rate_pct = [math]::Round((100.0 * $v.clears / [math]::Max($n, 1)), 2)
        death_rate_pct = [math]::Round((100.0 * $v.deaths / [math]::Max($n, 1)), 2)
        avg_max_depth  = [math]::Round(($v.avgDepth / [math]::Max($n, 1)), 2)
    }
}
$charPopularity = $charPopularity | Sort-Object runs -Descending

$charByBearingArr = @()
foreach ($k in $charByBearing.Keys) {
    $v = $charByBearing[$k]
    $n = [double]$v.runs
    $charByBearingArr += [PSCustomObject]@{
        character      = $v.character
        difficulty_tier = $v.difficulty_tier
        runs           = [int]$v.runs
        clear_rate_pct = [math]::Round((100.0 * $v.clears / [math]::Max($n, 1)), 2)
        death_rate_pct = [math]::Round((100.0 * $v.deaths / [math]::Max($n, 1)), 2)
    }
}
$charByBearingArr = $charByBearingArr | Sort-Object character, difficulty_tier

# --- pick rates (pick / offer) ---
$allArcanaIds = ($arcanaPickCounts.Keys + $arcanaOfferCounts.Keys) | Sort-Object -Unique
$arcanaPickRates = @()
foreach ($id in $allArcanaIds) {
    $picks  = if ($arcanaPickCounts.ContainsKey($id))  { [int]$arcanaPickCounts[$id] }  else { 0 }
    $offers = if ($arcanaOfferCounts.ContainsKey($id)) { [int]$arcanaOfferCounts[$id] } else { 0 }
    $rate   = if ($offers -gt 0) { [math]::Round((100.0 * $picks / $offers), 2) } else { $null }
    $arcanaPickRates += [PSCustomObject]@{
        arcana        = $id
        offers        = $offers
        picks         = $picks
        pick_rate_pct = $rate
    }
}
$arcanaPickRates = $arcanaPickRates | Sort-Object picks -Descending

$allBoonIds = ($boonPickCounts.Keys + $boonOfferCounts.Keys) | Sort-Object -Unique
$boonPickRates = @()
foreach ($id in $allBoonIds) {
    $picks  = if ($boonPickCounts.ContainsKey($id))  { [int]$boonPickCounts[$id] }  else { 0 }
    $offers = if ($boonOfferCounts.ContainsKey($id)) { [int]$boonOfferCounts[$id] } else { 0 }
    $rate   = if ($offers -gt 0) { [math]::Round((100.0 * $picks / $offers), 2) } else { $null }
    $boonPickRates += [PSCustomObject]@{
        boon          = $id
        offers        = $offers
        picks         = $picks
        pick_rate_pct = $rate
    }
}
$boonPickRates = $boonPickRates | Sort-Object picks -Descending

# arcana offered >=2 times but never picked
$neverPickedArcana = @($arcanaPickRates | Where-Object { $_.offers -ge 2 -and $_.picks -eq 0 } | ForEach-Object { $_.arcana })

$totalDeathN = 0; foreach ($v in $deathBySource.Values) { $totalDeathN += [int]$v }
$shielderDeathN = 0; if ($deathBySource.ContainsKey('enemy_shielder')) { $shielderDeathN = [int]$deathBySource['enemy_shielder'] }
$holdShare = 0.0; if ($holdLineDamage -gt 0) { $holdShare = 100.0 * $holdLineShielder / $holdLineDamage }

$buildCounts = @{}
$catalystCounts = @{}
foreach ($run in $runs) {
    foreach ($category in @('arcana', 'boons', 'boss_rewards')) {
        foreach ($item in @($run.build_summary.$category)) {
            if ($null -eq $item -or -not $item.id) { continue }
            $buildKey = $category + ':' + [string]$item.id
            if (-not $buildCounts.ContainsKey($buildKey)) { $buildCounts[$buildKey] = @{ category = $category; power = [string]$item.id; runs = 0 } }
            $buildCounts[$buildKey].runs++
        }
    }
    foreach ($catalyst in @($run.equipped_catalyst_ids | Sort-Object -Unique)) {
        if (-not $catalyst) { continue }
        if (-not $catalystCounts.ContainsKey([string]$catalyst)) { $catalystCounts[[string]$catalyst] = 0 }
        $catalystCounts[[string]$catalyst]++
    }
}
$cohorts = @($runs | Group-Object {
    $tier = if ($null -ne $_.difficulty_tier) { [string]$_.difficulty_tier } else { 'unknown' }
    $mode = if ($null -ne $_.run_mode) { [string]$_.run_mode } else { 'unknown' }
    $party = if ($null -ne $_.player_count) { [string]$_.player_count } else { 'unknown' }
    $rank = if ($null -ne $_.ascension_rank) { [string]$_.ascension_rank } else { 'unknown' }
    "${tier}|${mode}|${party}|${rank}"
} | ForEach-Object {
    $parts = $_.Name.Split('|')
    [ordered]@{ difficulty_tier = $parts[0]; run_mode = $parts[1]; player_count = $parts[2]; ascension_rank = $parts[3]; runs = $_.Count; outcomes = @($_.Group | Group-Object outcome | ForEach-Object { @{ outcome = $_.Name; runs = $_.Count } }) }
})
if ($cohorts.Count -gt 1) { $limitations.Add('The sample spans different difficulty/mode/party/Ascension cohorts. Pooled outcomes are descriptive, not a balance comparison.') }
$sampleStart = ($runs | Measure-Object started_at_unix -Minimum).Minimum
$sampleEnd = ($runs | Measure-Object ended_at_unix -Maximum).Maximum
$report = [ordered]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
    source = $sourceKind
    game_version = $Version
    # Retained for existing report readers; this is the explicitly chosen version.
    latest_version = $version
    window = [ordered]@{ from_utc = $fromDate.ToString('o'); to_exclusive_utc = $toDate.ToString('o'); include_debug = $false }
    sample = [ordered]@{
        first_started_at_utc = [DateTimeOffset]::FromUnixTimeSeconds([int64]$sampleStart).ToString('o')
        last_ended_at_utc = [DateTimeOffset]::FromUnixTimeSeconds([int64]$sampleEnd).ToString('o')
        median_duration_seconds = [math]::Round((Get-Percentile $durationArr 0.5), 2)
        field_coverage_runs = $coverage
    }
    cohorts = $cohorts
    limitations = @($limitations.ToArray())
    run_count = $runs.Count
    outcomes = $outcomes
    boredom_proxy = [ordered]@{
        q75_duration_seconds = [math]::Round($q75Dur, 2)
        q25_damage_events_per_min = [math]::Round($q25Dpm, 2)
        long_low_engagement_runs = $longLow
    }
    death_timing = [ordered]@{
        median_depth = [math]::Round($deathMedian, 2)
        q25_depth = [math]::Round($deathQ25, 2)
        q75_depth = [math]::Round($deathQ75, 2)
    }
    shielder = [ordered]@{
        death_count = $shielderDeathN
        death_share_pct = [math]::Round((100.0 * $shielderDeathN / [math]::Max($totalDeathN, 1)), 2)
        hold_line_damage_share_pct = [math]::Round($holdShare, 2)
    }
    top_death_sources = @($topDeaths | ForEach-Object { [ordered]@{ source = $_.Key; deaths = $_.Value } })
    top_damage_sources = @($topDamageSrc | ForEach-Object { [ordered]@{ source = $_.Key; total_damage = [math]::Round([double]$_.Value, 1) } })
    encounter_pressure = @($encPressure)
    top_arcana_picks = @($topArcana | ForEach-Object { [ordered]@{ arcana = $_.Key; picks = $_.Value } })
    arcana_outcomes = @($arcanaEffect)
    top_boon_picks = @($topBoon | ForEach-Object { [ordered]@{ boon = $_.Key; picks = $_.Value } })
    arcana_pick_rates = @($arcanaPickRates)
    boon_pick_rates = @($boonPickRates)
    never_picked_arcana = $neverPickedArcana
    character_popularity = @($charPopularity)
    character_by_bearing = @($charByBearingArr)
    final_build_presence = @($buildCounts.Values | Sort-Object -Property @{ Expression = { $_.runs }; Descending = $true }, @{ Expression = { $_.power }; Descending = $false })
    catalyst_usage = @($catalystCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { [ordered]@{ catalyst = $_.Key; runs = $_.Value } })
}

if ($coverage.damage_events -lt $runs.Count) {
    $report.boredom_proxy = $null
    $report.top_damage_sources = $null
    $report.shielder = $null
}
if ($coverage.room_entries -lt $runs.Count -or $coverage.damage_events -lt $runs.Count) { $report.encounter_pressure = $null }
if ($coverage.reward_choices -eq 0) {
    $report.top_arcana_picks = $null
    $report.top_boon_picks = $null
    $report.arcana_outcomes = $null
}
if ($coverage.reward_offers -lt $runs.Count -or $coverage.reward_choices -lt $runs.Count) {
    $report.arcana_pick_rates = $null
    $report.boon_pick_rates = $null
    $report.never_picked_arcana = $null
}
if ($deathDepths.Count -eq 0) { $report.death_timing = $null }
if ($coverage.equipped_catalyst_ids -eq 0) { $report.catalyst_usage = $null }
if ($coverage.build_summary -eq 0) { $report.final_build_presence = $null }
# Recheck after reading data; never clobber a report another invocation created.
$fileMode = if ($Overwrite) { [IO.FileMode]::Create } else { [IO.FileMode]::CreateNew }
$stream = [IO.File]::Open($OutputPath, $fileMode, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($report | ConvertTo-Json -Depth 12))
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }

Write-Host "VERSION=$version RUNS=$($runs.Count)"
Write-Host "REPORT_JSON=$OutputPath"
Write-Host 'TOP_DEATH_SOURCES:'
$topDeaths | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" }
Write-Host 'TOP_ARCANA:'
$topArcana | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" }
