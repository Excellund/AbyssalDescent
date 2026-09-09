param([string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$reader = Join-Path $projectRoot 'playtester_telemetry/read_local_telemetry.ps1'
$analyzer = Join-Path $projectRoot 'playtester_telemetry/fetch_latest_version_analysis.ps1'
if (-not $GodotPath) {
    $GodotPath = [string](Get-Content -LiteralPath (Join-Path $projectRoot '.vscode/settings.json') -Raw | ConvertFrom-Json).'godot.executablePath'
}
if (-not $GodotPath) { $GodotPath = $env:GODOT_EXE }
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Supply an existing -GodotPath.' }
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('abyssal-local-telemetry-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:checks = 0
# This suite never permits the analyzer to fall through to its remote RPC.
function Invoke-RestMethod { throw 'Unexpected network request in local telemetry regression.' }
function Assert-Check([bool]$Condition, [string]$Message) {
    $script:checks++
    if (-not $Condition) { throw "FAIL: $Message (fixtures: $testRoot)" }
}
function Assert-Rejected([scriptblock]$Operation, [string]$Reason, [string]$Message) {
    $failure = ''
    try { & $Operation | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-Check ($failure -match $Reason) "$Message; actual rejection: $failure"
}
$environmentNames = @('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME')
$originalEnvironment = @{}
foreach ($name in $environmentNames) { $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
function Assert-Environment([string]$Context) {
    foreach ($name in $environmentNames) {
        Assert-Check ([Environment]::GetEnvironmentVariable($name, 'Process') -ceq $originalEnvironment[$name]) "$Context restores $name"
    }
}
function New-Run([string]$Id, [long]$Started) {
    return [ordered]@{
        run_id = $Id; id = "database-$Id"; game_version = 'dev-local-fixture'
        player_uuid = 'private-uuid-fixture'; player_name = 'private-name-fixture'
        peers = @{ '1' = 'private-peer-fixture' }; player_names = @('private-party-fixture')
        unrecognized_field = 'private-unlisted-fixture'
        started_at_unix = $Started; ended_at_unix = $Started + 60; duration_seconds = 60
        character_id = 'bastion'; difficulty_tier = 3; outcome = 'clear'; max_depth = 8; rooms_cleared = 2
        is_debug = $false; is_multiplayer = $false; player_count = 1; run_mode = 'descent'
        equipped_catalyst_ids = @('damage_reduction'); ascension_rank = 2; ascension_loadout = @('pursuit')
        ascension_tracking_complete = $true; full_run_tracking_complete = $true
        damage_events = @(
            @{ source = 'enemy_charger'; final_amount = 10; bearing_key = 'crossfire'; room_depth = 1 },
            @{ source = 'enemy_shielder'; final_amount = 30; bearing_key = 'hold_the_line'; room_depth = 2; player_name = 'private-nested-damage' },
            @{ source = 'enemy_chaser'; final_amount = 10; bearing_key = 'hold_the_line'; room_depth = 2 }
        )
        room_entries = @(@{ bearing_key = 'crossfire'; room_depth = 1; objective_kind = 'combat' }, @{ bearing_key = 'hold_the_line'; room_depth = 2; objective_kind = 'hold_the_line' })
        reward_choices = @(@{ mode = 3; choice_id = 'blast_drive'; skipped = $false; unix_time = $Started + 1 }, @{ mode = 1; choice_id = 'armor'; skipped = $false; unix_time = $Started + 2 })
        reward_offers = @(
            @{ mode = 3; offers = @(@{ choice_id = 'blast_drive' }, @{ choice_id = 'razor_orbit' }, @{ choice_id = 'returning_crescent'; peers = @('private-nested-offer') }) },
            @{ mode = 1; offers = @(@{ choice_id = 'armor' }) }
        )
        door_choices = @(@{ bearing_key = 'crossfire'; room_depth = 1 })
        build_summary = @{ arcana = @(@{ id = 'blast_drive'; stacks = 2 }); boons = @(@{ id = 'armor'; stacks = 1 }); boss_rewards = @(@{ id = 'sovereigns_double'; stacks = 1 }) }
        stats = @{ kills = 11; nested = @(@{ player_names = @('private-nested-stats'); legitimate_metric = 7 }); player_uuid = 'private-nested-uuid' }
    }
}
function New-Provenance {
    return [ordered]@{ origin_known = $true; is_debug = $false; versions = @('dev-local-fixture'); origin_version = 'dev-local-fixture' }
}
$start = [DateTimeOffset]::Parse('2026-09-08T00:00:00Z').ToUnixTimeSeconds()
$first = New-Run 'private-first-run' $start
$first.run_provenance = New-Provenance
$second = New-Run 'private-second-run' ($start + 86399)
$second.Remove('run_id')
$second.duration_seconds = 120
$second.ended_at_unix = $second.started_at_unix + 120
$second.outcome = 'death'
$second.damage_events = @(@{ source = 'enemy_shielder'; final_amount = 20; bearing_key = 'hold_the_line'; room_depth = 2 })
$second.room_entries = @(@{ bearing_key = 'hold_the_line'; room_depth = 2; objective_kind = 'hold_the_line' })
$second.reward_choices = @(@{ mode = 3; choice_id = 'razor_orbit'; skipped = $false; unix_time = $second.started_at_unix + 1 }, @{ mode = 3; choice_id = 'returning_crescent'; skipped = $true })
$second.death_event = @{ source = 'enemy_shielder'; bearing_key = 'hold_the_line'; room_depth = 2 }
$fixtureRuns = New-Object System.Collections.Generic.List[object]
foreach ($run in @($first, $second, $first, $second)) { $fixtureRuns.Add($run) }
# Each exclusion has a distinctive ID and would change all the rich aggregates.
foreach ($kind in @('other-version', 'version-case', 'debug', 'unfinished', 'debug-outcome', 'empty-outcome', 'before', 'exclusive-end')) {
    $run = New-Run "private-$kind" ($start + 10)
    switch ($kind) {
        'other-version' { $run.game_version = 'dev-other-fixture' }
        'version-case' { $run.game_version = 'DEV-local-fixture' }
        'debug' { $run.is_debug = $true }
        'unfinished' { $run.outcome = 'in_progress' }
        'debug-outcome' { $run.outcome = 'debug' }
        'empty-outcome' { $run.outcome = '' }
        'before' { $run.started_at_unix = $start - 1 }
        'exclusive-end' { $run.started_at_unix = $start + 86400 }
    }
    $fixtureRuns.Add($run)
}
$badProvenanceKinds = @('mixed', 'debug', 'unknown', 'missing-debug', 'missing-known', 'null', 'non-object', 'string-known', 'string-debug', 'empty-versions', 'scalar-version', 'other-origin', 'version-case', 'origin-case')
foreach ($kind in $badProvenanceKinds) {
    $run = New-Run "private-provenance-$kind" ($start + 20)
    $evidence = New-Provenance
    switch ($kind) {
        'mixed' { $evidence.versions = @('dev-local-fixture', '0.8.0') }
        'debug' { $evidence.is_debug = $true }
        'unknown' { $evidence.origin_known = $false }
        'missing-debug' { $evidence.Remove('is_debug') }
        'missing-known' { $evidence.Remove('origin_known') }
        'null' { $evidence = $null }
        'non-object' { $evidence = @('dev-local-fixture') }
        'string-known' { $evidence.origin_known = 'true' }
        'string-debug' { $evidence.is_debug = 'false' }
        'empty-versions' { $evidence.versions = @() }
        'scalar-version' { $evidence.versions = 'dev-local-fixture' }
        'other-origin' { $evidence.origin_version = '0.8.0' }
        'version-case' { $evidence.versions = @('DEV-local-fixture') }
        'origin-case' { $evidence.origin_version = 'DEV-local-fixture' }
    }
    $run.run_provenance = $evidence
    $fixtureRuns.Add($run)
}

# Godot itself serializes the fixtures with FileAccess.store_var, exactly as the
# real telemetry store does. This minimal project contains no game/autoload code.
$fixtureJson = Join-Path $testRoot 'fixture.json'
@{ runs = $fixtureRuns.ToArray() } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixtureJson -Encoding utf8
Set-Content -LiteralPath (Join-Path $testRoot 'project.godot') -Encoding utf8 -Value 'config_version=5'
$writer = @'
extends SceneTree
func _initialize() -> void:
    var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
    if not payload is Dictionary or not payload.get("runs") is Array:
        quit(2)
        return
    _save("valid.save", {"version": 1, "runs": payload.runs})
    _save("empty.save", {"version": 1, "runs": []})
    _save("wrong-version.save", {"version": 2, "runs": payload.runs})
    _save("string-version.save", {"version": "1", "runs": payload.runs})
    _save("missing-version.save", {"runs": payload.runs})
    _save("wrong-root.save", payload.runs)
    _save("wrong-runs.save", {"version": 1, "runs": {"not": "an array"}})
    _save("nonobject-run.save", {"version": 1, "runs": [payload.runs[0], true]})
    _save("numeric-id.save", {"version": 1, "runs": [{"id": 42, "run_id": null}]})
    _save("object-id.save", {"version": 1, "runs": [{"run_id": {"invalid": true}}]})
    quit(0)
func _save(path: String, value: Variant) -> void:
    var output := FileAccess.open("res://" + path, FileAccess.WRITE)
    output.store_var(value, false)
    output.close()
'@
Set-Content -LiteralPath (Join-Path $testRoot 'write_fixtures.gd') -Value $writer -Encoding utf8
$process = $null
try {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $testRoot, 'Process') }
    $process = Start-Process -FilePath $GodotPath -ArgumentList @('--headless', '--path', ('"' + $testRoot + '"'), '--script', 'res://write_fixtures.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'writer.stdout.log') -RedirectStandardError (Join-Path $testRoot 'writer.stderr.log')
    if (-not $process.WaitForExit(30000)) { $process.Kill(); $process.WaitForExit(); throw 'Synthetic save generation timed out.' }
    Assert-Check ($process.ExitCode -eq 0) 'Godot writes actual binary telemetry fixtures'
} finally {
    if ($null -ne $process) { $process.Dispose() }
    foreach ($name in $environmentNames) {
        $previous = if ($null -eq $originalEnvironment[$name]) { [NullString]::Value } else { $originalEnvironment[$name] }
        [Environment]::SetEnvironmentVariable($name, $previous, 'Process')
    }
}
Assert-Environment 'Fixture writer'
$savePath = Join-Path $testRoot 'valid.save'
[IO.File]::WriteAllBytes((Join-Path $testRoot 'truncated.save'), [byte[]]@(1, 2, 3))
[IO.File]::WriteAllBytes((Join-Path $testRoot 'malformed.save'), [byte[]]@(4, 0, 0, 0, 255, 255, 255, 255))
$sourcePaths = @($reader, $analyzer, (Join-Path $projectRoot 'playtester_telemetry/read_local_telemetry.gd'), (Join-Path $projectRoot 'playtester_telemetry/latest_version_balance_report.json'), $fixtureJson, $savePath)
$sourceHashes = @{}
foreach ($path in $sourcePaths) { $sourceHashes[$path] = (Get-FileHash -LiteralPath $path).Hash }

$decoded = & $reader -Path $savePath -GodotPath $GodotPath
Assert-Environment 'Successful decoder'
Assert-Check ($decoded.runs.Count -eq $fixtureRuns.Count) 'Decoder preserves complete candidate set for explicit analyzer filtering'
$decodedText = $decoded | ConvertTo-Json -Depth 30
Assert-Check ($decodedText -notmatch 'private-|"(?:player_uuid|player_name|player_names|peers|unrecognized_field)"') 'Decoded rows recursively omit identities and raw run IDs'
Assert-Check ($decoded.runs[0].run_id -cmatch '^[0-9a-f]{64}$' -and $decoded.runs[0].id -cmatch '^[0-9a-f]{64}$') 'Both run ID forms become opaque hashes'
Assert-Check ($decoded.runs[0].run_id -ceq $decoded.runs[2].run_id -and $decoded.runs[1].id -ceq $decoded.runs[3].id) 'Hashing preserves both duplicate ID forms'
Assert-Check ($decoded.runs[0].run_id -cne $decoded.runs[1].id) 'Distinct run IDs remain distinct'
$row = $decoded.runs[0]
Assert-Check ($row.damage_events.Count -eq 3 -and $row.damage_events[1].final_amount -eq 30 -and $row.room_entries[1].objective_kind -eq 'hold_the_line') 'Damage and room event detail survives binary decoding'
Assert-Check ($row.reward_choices.Count -eq 2 -and $row.reward_offers[0].offers.Count -eq 3 -and $row.door_choices[0].bearing_key -eq 'crossfire') 'Choice, offer, and route arrays survive decoding'
Assert-Check ($row.stats.kills -eq 11 -and $row.stats.nested[0].legitimate_metric -eq 7 -and $row.build_summary.arcana[0].stacks -eq 2) 'Nested legitimate stats and build information survive privacy stripping'
Assert-Check ($row.ascension_rank -eq 2 -and $row.equipped_catalyst_ids[0] -eq 'damage_reduction' -and $row.full_run_tracking_complete) 'Loadouts and tracking coverage survive decoding'
Assert-Check ($row.run_provenance.origin_known -is [bool] -and $row.run_provenance.versions -is [Array] -and $row.run_provenance.versions.Count -eq 1) 'Saved origin evidence retains its exact boolean and array types'
$numeric = & $reader -Path (Join-Path $testRoot 'numeric-id.save') -GodotPath $GodotPath
Assert-Check ($numeric.runs[0].id -cmatch '^[0-9a-f]{64}$' -and -not $numeric.runs[0].PSObject.Properties['run_id']) 'Numeric IDs are hashed and null IDs remain absent without aborting the decoder'

$reportPath = Join-Path $testRoot 'report.json'
$analysisArgs = @{ Version = 'dev-local-fixture'; From = '2026-09-08'; To = '2026-09-09'; LocalTelemetryPath = $savePath; GodotPath = $GodotPath }
& $analyzer @analysisArgs -OutputPath $reportPath
Assert-Environment 'Successful end-to-end analysis'
$reportText = Get-Content -LiteralPath $reportPath -Raw
$report = $reportText | ConvertFrom-Json
Assert-Check ($report.source -eq 'local_telemetry' -and $report.game_version -ceq 'dev-local-fixture') 'Report identifies selected local source and exact version'
Assert-Check ($report.run_count -eq 2 -and $report.outcomes.clear -eq 1 -and $report.outcomes.death -eq 1) 'Exact version, UTC window, debug, completion, provenance and ID filters select only expected runs'
Assert-Check ($report.sample.first_started_at_utc -eq '2026-09-08T00:00:00.0000000+00:00' -and $report.sample.last_ended_at_utc -eq '2026-09-09T00:01:59.0000000+00:00') 'Start boundary is inclusive and completed runs may end after the exclusive start-time window'
Assert-Check ($report.window.to_exclusive_utc -eq '2026-09-09T00:00:00.0000000+00:00' -and -not $report.window.include_debug -and $report.sample.median_duration_seconds -eq 90) 'Window and elapsed-duration accounting remain explicit'
Assert-Check ($report.sample.excluded_local_provenance_rows -eq $badProvenanceKinds.Count) 'Every explicitly incompatible origin is excluded and counted'
Assert-Check ($report.sample.field_coverage_runs.run_provenance -eq 1 -and @($report.limitations | Where-Object { $_ -match 'legacy runs lack saved origin evidence' }).Count -eq 1) 'Legacy rows remain usable with missing provenance disclosed'
Assert-Check (@($report.limitations | Where-Object { $_ -match ('Excluded ' + $badProvenanceKinds.Count + ' local rows') }).Count -eq 1) 'Excluded provenance has a visible report limitation'
foreach ($field in @('damage_events', 'room_entries', 'reward_choices', 'reward_offers', 'door_choices', 'build_summary', 'equipped_catalyst_ids', 'ascension_rank', 'is_multiplayer', 'full_run_tracking_complete')) {
    Assert-Check ($report.sample.field_coverage_runs.$field -eq 2) "Rich field coverage is retained: $field"
}
$hold = @($report.encounter_pressure | Where-Object encounter -eq 'hold_the_line')[0]
Assert-Check ($hold.entries -eq 2 -and $hold.total_damage -eq 60 -and $hold.damage_per_entry -eq 30 -and $hold.deaths -eq 1) 'Encounter pressure uses actual room entries and their detailed damage'
$damage = @($report.top_damage_sources | Where-Object source -eq 'enemy_shielder')[0]
Assert-Check ($damage.total_damage -eq 50 -and $report.shielder.hold_line_damage_share_pct -eq 83.33 -and $report.shielder.death_count -eq 1) 'Damage-source and Hold the Line shares use preserved events'
Assert-Check ($report.death_timing.median_depth -eq 2 -and $null -ne $report.boredom_proxy) 'Death event depth and activity proxy are available for rich telemetry'
$blast = @($report.arcana_pick_rates | Where-Object arcana -eq 'blast_drive')[0]
Assert-Check ($blast.offers -eq 2 -and $blast.picks -eq 1 -and $blast.pick_rate_pct -eq 50) 'Offer-based Arcana rate counts presentations and choices separately'
Assert-Check ($report.never_picked_arcana -contains 'returning_crescent' -and @($report.top_arcana_picks | Where-Object arcana -eq 'returning_crescent').Count -eq 0) 'Skipped reward choices are not counted as picks'
$build = @($report.final_build_presence | Where-Object power -eq 'blast_drive')[0]
Assert-Check ($build.runs -eq 2 -and $report.catalyst_usage[0].runs -eq 2 -and $report.cohorts[0].ascension_rank -eq '2') 'Final builds, Catalyst and Ascension cohorts remain separate from choice rates'
Assert-Check ($reportText -notmatch 'private-|"(?:run_id|player_uuid|player_name|player_names|peers)"' -and -not $reportText.Contains($decoded.runs[0].run_id)) 'Aggregate report omits raw and hashed participant/run identifiers'

$reportHash = (Get-FileHash -LiteralPath $reportPath).Hash
Assert-Rejected { & $analyzer @analysisArgs -OutputPath $reportPath } 'Output already exists' 'An existing report needs explicit overwrite'
Assert-Check ((Get-FileHash -LiteralPath $reportPath).Hash -eq $reportHash) 'Rejected overwrite preserves existing report bytes'
& $analyzer @analysisArgs -OutputPath $reportPath -Overwrite
Assert-Check ((Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json).run_count -eq 2) 'Explicit report overwrite succeeds'
Assert-Rejected { & $analyzer @analysisArgs -OutputPath $savePath -Overwrite } 'must name a JSON file|must not overwrite its input' 'Output cannot overwrite the source binary save'
Assert-Rejected { & $analyzer @analysisArgs -LocalHistoryPath $fixtureJson -OutputPath (Join-Path $testRoot 'mutually-exclusive.json') } 'Choose either' 'Local telemetry and local JSON inputs are mutually exclusive'
Assert-Rejected { & $analyzer -Version 'dev-local-fixture' -LocalHistoryPath $fixtureJson -OutputPath $fixtureJson -Overwrite } 'must not overwrite its input history' 'JSON source is protected even with overwrite authorization'
Assert-Rejected { & $reader -Path $fixtureJson -GodotPath $GodotPath } 'local run_telemetry.save' 'Reader rejects JSON pretending to be a binary telemetry save'

foreach ($name in @('truncated', 'malformed', 'wrong-version', 'string-version', 'missing-version', 'wrong-root', 'wrong-runs', 'nonobject-run', 'object-id')) {
    $badPath = Join-Path $testRoot ($name + '.save')
    $badHash = (Get-FileHash -LiteralPath $badPath).Hash
    $rejectionTimer = [Diagnostics.Stopwatch]::StartNew()
    Assert-Rejected { & $reader -Path $badPath -GodotPath $GodotPath } 'could not be decoded' "Reject malformed binary schema: $name"
    $rejectionTimer.Stop()
    Assert-Check ($rejectionTimer.ElapsedMilliseconds -lt 15000) "Malformed $name exits promptly instead of stalling until the 30-second subprocess timeout"
    Assert-Environment "Rejected $name"
    Assert-Check ((Get-FileHash -LiteralPath $badPath).Hash -eq $badHash) "Rejecting $name never repairs or rewrites source data"
}
$emptyOutput = Join-Path $testRoot 'empty-report.json'
Assert-Rejected { & $analyzer -Version 'dev-local-fixture' -From '2026-09-08' -To '2026-09-09' -LocalTelemetryPath (Join-Path $testRoot 'empty.save') -GodotPath $GodotPath -OutputPath $emptyOutput } 'No completed non-debug runs' 'Empty valid saves cannot produce a misleading report'
Assert-Check (-not (Test-Path -LiteralPath $emptyOutput)) 'Empty sample failure leaves no output'
$malformedOutput = Join-Path $testRoot 'malformed-report.json'
Assert-Rejected { & $analyzer -Version 'dev-local-fixture' -From '2026-09-08' -To '2026-09-09' -LocalTelemetryPath (Join-Path $testRoot 'nonobject-run.save') -GodotPath $GodotPath -OutputPath $malformedOutput } 'could not be decoded' 'End-to-end analysis rejects the entire malformed sample'
Assert-Check (-not (Test-Path -LiteralPath $malformedOutput)) 'Malformed sample cannot publish a partial report'

# Child-script command mocks exercise bounded timeout/failure cleanup without a
# real 30-second wait or runaway process. They are scoped to this invocation.
$launchState = [PSCustomObject]@{ Calls = 0; Throw = $true; WaitMs = 0; Killed = $false; Disposed = $false }
function Start-Process {
    param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, $RedirectStandardOutput, $RedirectStandardError)
    $launchState.Calls++
    Assert-Check ($WindowStyle -eq 'Hidden' -and $ArgumentList -contains '--headless') 'Decoder launch is hidden and headless'
    foreach ($name in $environmentNames) {
        Assert-Check ([Environment]::GetEnvironmentVariable($name, 'Process') -eq (Split-Path -Parent $RedirectStandardOutput)) "Decoder isolates $name before launch"
    }
    $decoderProject = Split-Path -Parent $RedirectStandardOutput
    Assert-Check ((Get-Content -LiteralPath (Join-Path $decoderProject 'project.godot') -Raw).Trim() -eq 'config_version=5' -and -not (Test-Path -LiteralPath (Join-Path $decoderProject 'autoload'))) 'Decoder subprocess has only a standalone project with no game startup'
    Assert-Check ((Get-FileHash -LiteralPath (Join-Path $decoderProject 'input.save')).Hash -eq $sourceHashes[$savePath]) 'Subprocess reads an identical disposable copy of the selected save'
    if ($launchState.Throw) { throw 'Synthetic launch failure' }
    $fake = [PSCustomObject]@{ State = $launchState }
    $fake | Add-Member ScriptMethod WaitForExit { param($Milliseconds) $this.State.WaitMs = $Milliseconds; return $false }
    $fake | Add-Member ScriptMethod Kill { $this.State.Killed = $true }
    $fake | Add-Member ScriptMethod Dispose { $this.State.Disposed = $true }
    return $fake
}
$validateOutput = Join-Path $testRoot 'validate-only.json'
$configuration = & $analyzer @analysisArgs -OutputPath $validateOutput -ValidateOnly
Assert-Check ($launchState.Calls -eq 0 -and $configuration.Source -eq 'local_telemetry' -and -not (Test-Path -LiteralPath $validateOutput)) 'ValidateOnly validates paths without launching Godot or creating a report'
Assert-Environment 'ValidateOnly'
Assert-Rejected { & $reader -Path $savePath -GodotPath $GodotPath } 'Synthetic launch failure' 'Decoder surfaces a failed process launch'
Assert-Environment 'Failed process launch'
$launchState.Throw = $false
Assert-Rejected { & $reader -Path $savePath -GodotPath $GodotPath } 'exceeded 30 seconds' 'Decoder rejects a timed-out subprocess'
Assert-Check ($launchState.WaitMs -eq 30000 -and $launchState.Killed -and $launchState.Disposed) 'Timeout is bounded, terminates the subprocess and disposes its handle'
Assert-Environment 'Timed-out subprocess'
Remove-Item Function:\Start-Process
foreach ($path in $sourcePaths) { Assert-Check ((Get-FileHash -LiteralPath $path).Hash -eq $sourceHashes[$path]) "Input/source/historical report remains untouched: $([IO.Path]::GetFileName($path))" }
Write-Host "LocalTelemetryAnalysis: $script:checks checks passed"
Write-Host "Fixtures and report: $testRoot"
