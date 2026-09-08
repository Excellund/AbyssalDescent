$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$analyzer = Join-Path $projectRoot 'playtester_telemetry/fetch_latest_version_analysis.ps1'
$exporter = Join-Path $PSScriptRoot 'export_playtest.ps1'
$debugLauncher = Join-Path $PSScriptRoot 'start_debug_playtest.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('abyssal-workflow-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:checks = 0
function Assert-Check([bool]$Condition, [string]$Message) {
    $script:checks++
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Assert-Rejected([scriptblock]$Operation, [string]$Message) {
    $rejected = $false
    try { & $Operation | Out-Null } catch { $rejected = $true }
    Assert-Check $rejected $Message
}
function New-Run([string]$Id, [long]$Started, [string]$Version = 'dev-fixture') {
    return [ordered]@{
        run_id = $Id; player_uuid = 'private-player-never-report'; player_name = 'private-name-never-report'
        game_version = $Version; started_at_unix = $Started; ended_at_unix = $Started + 900
        duration_seconds = 60; is_debug = $false; outcome = 'clear'; max_depth = 27
        character_id = 'bastion'; difficulty_tier = 1; player_count = 1
        equipped_catalyst_ids = @('damage_reduction')
        build_summary = @{ arcana = @(@{ id = 'phantom_step'; stacks = 2 }); boons = @(); boss_rewards = @() }
    }
}
$start = [DateTimeOffset]::Parse('2026-09-08T00:00:00Z').ToUnixTimeSeconds()
$first = New-Run 'first' ($start + 1)
$second = New-Run 'second' ($start + 2)
$second.duration_seconds = 120
$second.outcome = 'death'
$second.death_event = @{ room_depth = 10; source = 'enemy_chaser'; bearing_key = 'skirmish' }
$oldVersion = New-Run 'old-version' ($start + 3) '0.6.0'
$debug = New-Run 'debug' ($start + 4)
$debug.is_debug = $true
$inProgress = New-Run 'unfinished' ($start + 5)
$inProgress.outcome = 'in_progress'
$outside = New-Run 'outside' ($start + 86400)
$localPath = Join-Path $testRoot 'history.json'
@($first, $second, $first, $oldVersion, $debug, $inProgress, $outside) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $localPath
$inputHash = (Get-FileHash -LiteralPath $localPath).Hash
$trackedReport = Join-Path $projectRoot 'playtester_telemetry/latest_version_balance_report.json'
$trackedHash = (Get-FileHash -LiteralPath $trackedReport).Hash
$reportPath = Join-Path $testRoot 'local-report.json'
& $analyzer -Version 'dev-fixture' -From '2026-09-08' -To '2026-09-09' -LocalHistoryPath $localPath -OutputPath $reportPath
$reportText = Get-Content -LiteralPath $reportPath -Raw
$report = $reportText | ConvertFrom-Json
Assert-Check ($report.run_count -eq 2) 'Local version/date/debug/completion filters and ID deduplication'
Assert-Check ($report.outcomes.clear -eq 1 -and $report.outcomes.death -eq 1) 'Local outcomes'
Assert-Check ($report.sample.median_duration_seconds -eq 90) 'Explicit elapsed duration takes precedence over wall clock'
Assert-Check ($null -eq $report.arcana_pick_rates -and $null -eq $report.encounter_pressure -and $null -eq $report.boredom_proxy) 'Missing local event data is unavailable, not zero'
Assert-Check ($report.final_build_presence[0].runs -eq 2) 'Final builds are counted separately from picks'
Assert-Check ($report.catalyst_usage[0].runs -eq 2) 'Local equipped Catalyst cohort'
Assert-Check (-not $reportText.Contains('private-player-never-report') -and -not $reportText.Contains('private-name-never-report')) 'Reports omit personal identifiers'
Assert-Check ((Get-FileHash -LiteralPath $localPath).Hash -eq $inputHash) 'Input history is read-only'
Assert-Check ((Get-FileHash -LiteralPath $trackedReport).Hash -eq $trackedHash) 'The tracked legacy report is untouched'
Assert-Rejected { & $analyzer -Version 'dev-fixture' -LocalHistoryPath $localPath -OutputPath $localPath -Overwrite } 'Never overwrite input history'
Assert-Rejected { & $analyzer -Version 'dev-fixture' -LocalHistoryPath $localPath -OutputPath $reportPath } 'Do not overwrite a report implicitly'
Assert-Rejected { & $analyzer -ValidateOnly } 'An explicit build version is required'
Assert-Rejected { & $analyzer -Version 'dev-fixture' -From '2026-09-09' -To '2026-09-08' -ValidateOnly } 'Reject an inverted date range'
$config = & $analyzer -Version 'dev-fixture' -From '2026-09-08' -To '2026-09-09' -ValidateOnly
Assert-Check ($config.FromUtc -eq '2026-09-08T00:00:00.0000000+00:00') 'Date-only inputs use UTC'
Assert-Check ($config.OutputPath.StartsWith([IO.Path]::GetTempPath()) -and -not (Test-Path -LiteralPath $config.OutputPath)) 'Default reports use a unique temporary path; dry run writes nothing'

# Exercise the real read-RPC/report code with in-memory HTTP replies. The mock
# is scoped to this test invocation; it never sends data or contacts a server.
$rpcFixtureState = [PSCustomObject]@{ Calls = 0; BadRemote = $false }
function Invoke-RestMethod {
    param($Method, $Uri, $Headers, $Body, $TimeoutSec)
    $rpcFixtureState.Calls++
    Assert-Check ($Uri.EndsWith('/rpc/get_balance_runs_between') -and $Method -eq 'Post') 'Only the read RPC is used'
    $query = $Body | ConvertFrom-Json
    Assert-Check ($query.p_game_version -ceq '0.7.0' -and -not $query.p_include_debug) 'Remote version/debug scope is explicit'
    if ($rpcFixtureState.BadRemote) { return [PSCustomObject](New-Run 'wrong-version' ($start + 1) 'dev-fixture') }
    if ($rpcFixtureState.Calls -eq 1) {
        for ($index = 0; $index -lt 5000; $index++) {
            $run = New-Run "batch-$index" ($start + 20) '0.7.0'
            if ($index -eq 4999) { $run.started_at_unix = $start + 10 }
            [PSCustomObject]$run
        }
    } else {
        Assert-Check ($query.p_end_unix -eq $start + 11) 'Pagination overlaps the boundary second'
        [PSCustomObject](New-Run 'batch-4999' ($start + 10) '0.7.0')
        [PSCustomObject](New-Run 'boundary-peer' ($start + 10) '0.7.0')
        [PSCustomObject](New-Run 'older' ($start + 9) '0.7.0')
    }
}
$remotePath = Join-Path $testRoot 'remote-report.json'
& $analyzer -Version '0.7.0' -From '2026-09-08' -To '2026-09-09' -OutputPath $remotePath
$remoteReport = Get-Content -LiteralPath $remotePath -Raw | ConvertFrom-Json
Assert-Check ($remoteReport.run_count -eq 5002 -and $rpcFixtureState.Calls -eq 2) 'Remote pages preserve timestamp ties and deduplicate overlap'
$rpcFixtureState.BadRemote = $true
$invalidPath = Join-Path $testRoot 'invalid-report.json'
Assert-Rejected { & $analyzer -Version '0.7.0' -From '2026-09-08' -To '2026-09-09' -OutputPath $invalidPath } 'An out-of-scope RPC result fails instead of silently mixing builds'
Assert-Check (-not (Test-Path -LiteralPath $invalidPath)) 'Failed queries do not write misleading reports'

$exePath = Join-Path $testRoot 'unused.exe'
$export = & $exporter -OutputPath $exePath -BuildVersion 'dev-content-1' -ValidateOnly
Assert-Check ($export.BuildVersion -eq 'dev-content-1' -and -not (Test-Path -LiteralPath $exePath)) 'Export dry run preserves explicit build version and writes nothing'
$autoA = & $exporter -OutputPath $exePath -ValidateOnly
$autoB = & $exporter -OutputPath $exePath -ValidateOnly
Assert-Check ($autoA.BuildVersion -match '^dev-\d{8}-\d{9}-[a-f0-9]{8}$' -and $autoA.BuildVersion -ne $autoB.BuildVersion) 'Default build IDs are timestamped and unique'
Assert-Rejected { & $exporter -OutputPath $exePath -BuildVersion '0.7.0' -ValidateOnly } 'Playtest exports cannot masquerade as release builds'
Assert-Rejected { & $exporter -OutputPath $exePath -BuildVersion 'dev-unsafe"setting' -ValidateOnly } 'Build versions cannot inject project settings'
Assert-Rejected { & $exporter -OutputPath (Join-Path $testRoot 'bad.zip') -ValidateOnly } 'Export output must be an executable'

# Exercise the actual desktop-path policy without accessing that directory.
# The canonical target and its parent are simulated as existing; every real
# fixture lives under this test's temporary directory.
$desktopDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
$canonicalPlaytestPath = [IO.Path]::GetFullPath((Join-Path $desktopDirectory 'AbyssalDescent Playtest.exe'))
$desktopDirectory = [IO.Path]::GetFullPath($desktopDirectory)
$existingCustomExe = Join-Path $testRoot 'AbyssalDescent Playtest.exe'
Set-Content -LiteralPath $existingCustomExe -Value 'preserve this custom executable'
$existingCustomHash = (Get-FileHash -LiteralPath $existingCustomExe).Hash
$missingEngine = Join-Path $testRoot 'must-not-start-godot.exe'
$dryRunState = [PSCustomObject]@{ WriteCalls = 0; LaunchCalls = 0; DesktopChecks = 0 }
function Test-Path {
    param($Path, $LiteralPath)
    $candidate = if ($PSBoundParameters.ContainsKey('LiteralPath')) { [string]$LiteralPath } else { [string]$Path }
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        $absolute = [IO.Path]::GetFullPath($candidate)
        if ($absolute.Equals($canonicalPlaytestPath, [StringComparison]::OrdinalIgnoreCase) -or $absolute.Equals($desktopDirectory, [StringComparison]::OrdinalIgnoreCase)) {
            $dryRunState.DesktopChecks++
            return $true
        }
    }
    Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
}
function New-Item { $dryRunState.WriteCalls++; throw 'A validation-only workflow attempted to create files or directories.' }
function Copy-Item { $dryRunState.WriteCalls++; throw 'A validation-only workflow attempted to copy files.' }
function Set-Content { $dryRunState.WriteCalls++; throw 'A validation-only workflow attempted to write files.' }
function Start-Process { $dryRunState.LaunchCalls++; throw 'A validation-only workflow attempted to launch a process.' }

$normalDefault = & $exporter -GodotPath $missingEngine -ValidateOnly
$debugDefault = & $exporter -GodotPath $missingEngine -DebugRun -ValidateOnly
Assert-Check ($normalDefault.OutputPath -eq $canonicalPlaytestPath -and $debugDefault.OutputPath -eq $canonicalPlaytestPath) 'Normal and debug exports select the same canonical desktop executable'
Assert-Check ($normalDefault.Overwrite -eq $true -and $debugDefault.Overwrite -eq $true) 'Both default modes allow replacing an existing canonical playtest'
Assert-Check ($normalDefault.DebugRun -is [bool] -and -not $normalDefault.DebugRun -and $debugDefault.DebugRun -is [bool] -and $debugDefault.DebugRun) 'Dry runs expose the actual export mode as a boolean'
Assert-Check ($normalDefault.BuildVersion -match '^dev-\d{8}-\d{9}-[a-f0-9]{8}$' -and $debugDefault.BuildVersion -match '^dev-debug-\d{8}-\d{9}-[a-f0-9]{8}$') 'Generated build IDs distinguish normal and debug playtests'
$nextDebug = & $exporter -OutputPath $exePath -GodotPath $missingEngine -DebugRun -ValidateOnly
Assert-Check ($nextDebug.BuildVersion -ne $debugDefault.BuildVersion -and -not $nextDebug.Overwrite) 'Debug IDs remain unique and a custom path does not inherit overwrite permission'
foreach ($debugMode in @($false, $true)) {
    $explicitCanonical = & $exporter -OutputPath $canonicalPlaytestPath.ToUpperInvariant() -GodotPath $missingEngine -DebugRun:$debugMode -ValidateOnly
    Assert-Check ($explicitCanonical.Overwrite -eq $true -and $explicitCanonical.DebugRun -eq $debugMode) 'An explicitly supplied canonical path has the same case-insensitive overwrite policy'
    Assert-Rejected { & $exporter -OutputPath $existingCustomExe -GodotPath $missingEngine -DebugRun:$debugMode -ValidateOnly } 'An existing custom path stays protected even when its filename matches the desktop playtest'
    $explicitOverwrite = & $exporter -OutputPath $existingCustomExe -GodotPath $missingEngine -DebugRun:$debugMode -Overwrite -ValidateOnly
    Assert-Check ($explicitOverwrite.OutputPath -eq $existingCustomExe -and $explicitOverwrite.Overwrite -eq $true) 'Explicit overwrite permits validating an existing custom output'
}
$wrapperDefault = & $debugLauncher -GodotPath $missingEngine -ValidateOnly
Assert-Check ($wrapperDefault.OutputPath -eq $canonicalPlaytestPath -and $wrapperDefault.DebugRun -eq $true -and $wrapperDefault.Overwrite -eq $true) 'Debug launch wrapper uses the same canonical exporter defaults'
Assert-Check ($wrapperDefault.BuildVersion -match '^dev-debug-\d{8}-\d{9}-[a-f0-9]{8}$') 'Debug launch wrapper receives a debug build identifier'
$wrapperCustom = & $debugLauncher -OutputPath $exePath -BuildVersion 'dev-debug-explicit-fixture' -GodotPath $missingEngine -ValidateOnly
Assert-Check ($wrapperCustom.OutputPath -eq $exePath -and $wrapperCustom.BuildVersion -eq 'dev-debug-explicit-fixture' -and $wrapperCustom.DebugRun -eq $true) 'Debug launch wrapper forwards the requested output and explicit build version'
Assert-Rejected { & $debugLauncher -OutputPath $existingCustomExe -GodotPath $missingEngine -ValidateOnly } 'Debug launch wrapper cannot implicitly replace a custom executable'
Assert-Check ($dryRunState.DesktopChecks -gt 0 -and $dryRunState.WriteCalls -eq 0 -and $dryRunState.LaunchCalls -eq 0) 'Default, explicit, and wrapper dry runs never write files or launch a game'
Assert-Check (-not (Test-Path -LiteralPath $exePath) -and (Get-FileHash -LiteralPath $existingCustomExe).Hash -eq $existingCustomHash) 'Validation preserves both missing and existing custom executables'
Write-Host "[PASS] Playtest workflow: $script:checks checks"
Write-Host "Test artifacts: $testRoot"
