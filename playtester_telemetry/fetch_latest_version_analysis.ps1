$ErrorActionPreference = 'Stop'

$base = 'https://aizoebowshcnqvuizava.supabase.co/rest/v1/rpc'
$key = 'sb_publishable_LiXb9xg1jvwUZYw1arDcag_YIzGTPGV'
$headers = @{ apikey = $key; Authorization = "Bearer $key"; 'Content-Type' = 'application/json' }

$latestBody = '{"p_include_debug":false,"p_game_version":"","p_max_age_days":3650}'
$latest = Invoke-RestMethod -Method Post -Uri "$base/get_latest_balance_run" -Headers $headers -Body $latestBody
if ($null -eq $latest -or [string]::IsNullOrWhiteSpace([string]$latest.game_version)) {
    throw 'Could not determine latest version'
}
$version = [string]$latest.game_version

$allRuns = New-Object System.Collections.Generic.List[object]
$seen = @{}
$endUnix = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 1)
$batchIndex = 0
while ($true) {
    $batchIndex++
    $payload = @{ p_start_unix = 0; p_end_unix = $endUnix; p_include_debug = $false; p_game_version = $version; p_max_runs = 5000 } | ConvertTo-Json -Compress
    $resp = Invoke-RestMethod -Method Post -Uri "$base/get_balance_runs_between" -Headers $headers -Body $payload
    $batch = @()
    if ($resp -is [System.Array]) { $batch = $resp }
    elseif ($null -ne $resp -and "$resp" -ne '') { $batch = @($resp) }
    $batchCount = $batch.Count
    if ($batchCount -eq 0) { break }

    $minStarted = [int64]::MaxValue
    foreach ($r in $batch) {
        $rid = [string]$r.run_id
        if (-not $seen.ContainsKey($rid)) {
            $seen[$rid] = $true
            $allRuns.Add($r) | Out-Null
        }
        $s = [int64]$r.started_at_unix
        if ($s -lt $minStarted) { $minStarted = $s }
    }

    Write-Host "Batch ${batchIndex}: $batchCount runs, total unique so far: $($allRuns.Count)"

    if ($batchCount -lt 5000) { break }
    if ($minStarted -le 1) { break }
    $endUnix = $minStarted - 1
    if ($batchIndex -ge 50) { break }
}

$runs = $allRuns.ToArray()
if ($runs.Count -eq 0) {
    throw "No runs found for latest version $version"
}

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

foreach ($r in $runs) {
    $out = [string]$r.outcome
    if (-not $outcomes.ContainsKey($out)) { $outcomes[$out] = 0 }
    $outcomes[$out]++

    $duration = [double]([int64]$r.ended_at_unix - [int64]$r.started_at_unix)
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
        $mode = [int]$c.mode
        $cid = [string]$c.choice_id
        if ([string]::IsNullOrWhiteSpace($cid)) { $cid = 'unknown' }
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

$totalDeathN = 0; foreach ($v in $deathBySource.Values) { $totalDeathN += [int]$v }
$shielderDeathN = 0; if ($deathBySource.ContainsKey('enemy_shielder')) { $shielderDeathN = [int]$deathBySource['enemy_shielder'] }
$holdShare = 0.0; if ($holdLineDamage -gt 0) { $holdShare = 100.0 * $holdLineShielder / $holdLineDamage }

$report = [ordered]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
    latest_version = $version
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
}

$outJson = 'c:\Mike\Godot Projects\godot-2026\playtester_telemetry\latest_version_balance_report.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $outJson -Encoding UTF8

Write-Host "VERSION=$version RUNS=$($runs.Count)"
Write-Host "REPORT_JSON=$outJson"
Write-Host 'TOP_DEATH_SOURCES:'
$topDeaths | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" }
Write-Host 'TOP_ARCANA:'
$topArcana | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" }
