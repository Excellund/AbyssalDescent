<#
.SYNOPSIS
Exercises a copied normal dev-* Windows export through its production Menu/Practice/Main.
.DESCRIPTION
Opt in through test_playtest_executable.ps1 -NativeRun. The supplied export is
never modified or started in place. A verified official Godot 4.6.2 template,
literal sidecar settings, editor preflight and separate TEMP profiles precede
native launch. Services are disabled; this does not test online behavior.

The external autoload injects keyboard controls and movement in headless mode
with Dummy audio, then explicitly retires the final scene and application cache.
This proves native startup/lifecycle, not GPU output, sound or ordinary OS exit.
The uncleared tutorial has no Continue checkpoint. Public/release versions and
debug presets are rejected before active native gameplay.
#>
param(
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][string]$GodotPath
)

$ErrorActionPreference = 'Stop'
$ExecutablePath = (Resolve-Path -LiteralPath $ExecutablePath).Path
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
if ($ExecutablePath -eq $GodotPath) { throw 'Supply a normal developer export and a separate Godot editor.' }

# Retain the existing packaged-scene checks before active native gameplay.
# This preflight rejects public versions, debug presets, and non-isolated data.
$package = & (Join-Path $PSScriptRoot 'test_playtest_executable.ps1') -ExecutablePath $ExecutablePath -GodotPath $GodotPath
if ($package.DebugRun -or $package.BuildVersion -notmatch '^dev-' -or $package.MainScene -ne 'res://scenes/Menu.tscn') {
    throw 'Native gameplay smoke requires a normal dev-* Menu build.'
}
$packageResult = Get-Content -LiteralPath $package.ResultPath -Raw | ConvertFrom-Json
if ($packageResult.engine -notmatch '^4\.6\.2') { throw 'Native smoke currently supports the verified Godot 4.6.2 release template.' }

# The official 4.6.2 template was independently tested with an inert package:
# external override.cfg and an absolute-path autoload run before its main scene.
# Match executable code, allowing only normal export metadata/PCK differences.
$templateCandidates = @(
    (Join-Path $env:APPDATA 'Godot/export_templates/4.6.2.stable/windows_release_x86_64.exe'),
    (Join-Path (Split-Path -Parent $GodotPath) 'editor_data/export_templates/4.6.2.stable/windows_release_x86_64.exe')
)
$template = $templateCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $template -or (Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash -ne '3B2D3F99BD640961AAD1A1A200F0F7233B7DE45B02801CE22D3224DC294D93D1') {
    throw 'Install the verified official Godot 4.6.2 Windows release template before native smoke.'
}

function Get-ExecutableCodeHash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { throw 'Expected a Windows PE executable.' }
        $stream.Position = 0x3c
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw 'Invalid PE header.' }
        $stream.Position = $peOffset + 6
        $sectionCount = $reader.ReadUInt16()
        $stream.Position = $peOffset + 20
        $optionalSize = $reader.ReadUInt16()
        $sectionTable = $peOffset + 24 + $optionalSize
        for ($index = 0; $index -lt $sectionCount; $index++) {
            $stream.Position = $sectionTable + 40 * $index
            $name = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(8)).TrimEnd([char]0)
            if ($name -ne '.text') { continue }
            $stream.Position = $sectionTable + 40 * $index + 16
            $size = $reader.ReadUInt32()
            $offset = $reader.ReadUInt32()
            if ($size -eq 0 -or ([long]$offset + $size) -gt $stream.Length) { throw 'Invalid executable code section.' }
            $stream.Position = $offset
            $bytes = $reader.ReadBytes([int]$size)
            $sha = [Security.Cryptography.SHA256]::Create()
            try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
            finally { $sha.Dispose() }
        }
        throw 'Executable has no code section.'
    } finally { $reader.Dispose(); $stream.Dispose() }
}
$templateCodeHash = Get-ExecutableCodeHash $template
if ((Get-ExecutableCodeHash $ExecutablePath) -ne $templateCodeHash) { throw 'Exported executable code does not match the verified native template.' }

$nativeRoot = Join-Path ([IO.Path]::GetTempPath()) ('abyssal-native-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $nativeRoot | Out-Null
$copyPath = Join-Path $nativeRoot 'AbyssalNativeSmoke.exe'
$sourceHash = (Get-FileHash -LiteralPath $ExecutablePath -Algorithm SHA256).Hash
Copy-Item -LiteralPath $ExecutablePath -Destination $copyPath
if ((Get-FileHash -LiteralPath $copyPath -Algorithm SHA256).Hash -ne $sourceHash) { throw 'Temporary executable differs from the input export.' }
$probePath = Join-Path $nativeRoot 'native_playtest_probe.gd'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../scripts/tests/native_playtest_probe.gd') -Destination $probePath
$nonce = [guid]::NewGuid().ToString('N')
$expected = [ordered]@{}
foreach ($key in @('telemetry_upload_endpoint', 'telemetry_upload_api_key', 'leaderboard_submit_endpoint', 'leaderboard_rest_base_url', 'multiplayer_room_registry_endpoint', 'multiplayer_room_registry_api_key', 'update_feed_url', 'update_feed_token', 'update_release_page_url', 'project_settings_override')) {
    $expected['application/config/' + $key] = ''
}
$expected['application/config/multiplayer_public_ip_lookup_url'] = 'http://127.0.0.1:9/native-smoke-disabled'
$expected['application/config/multiplayer_tunnel_enabled'] = $false
$expected['application/config/use_custom_user_dir'] = $true
$expected['application/config/custom_user_dir_name'] = 'native-smoke-userdata'
$expected['application/config/native_smoke_nonce'] = $nonce
$expected['autoload/NativePlaytestProbe'] = '*' + $probePath.Replace('\', '/')
$utf8 = New-Object Text.UTF8Encoding($false)
$overrideLines = [Collections.Generic.List[string]]::new()
$overrideLines.Add('[application]')
foreach ($key in $expected.Keys) {
    if (-not $key.StartsWith('application/')) { continue }
    $value = $expected[$key]
    $literal = if ($value -is [bool]) { $value.ToString().ToLowerInvariant() } else { '"' + $value + '"' }
    $overrideLines.Add($key.Substring('application/'.Length) + '=' + $literal)
}
$overrideLines.Add('[autoload]')
$overrideLines.Add('NativePlaytestProbe="' + $expected['autoload/NativePlaytestProbe'] + '"')
[IO.File]::WriteAllText((Join-Path $nativeRoot 'override.cfg'), ($overrideLines -join "`n") + "`n", $utf8)
$overrideHash = (Get-FileHash -LiteralPath (Join-Path $nativeRoot 'override.cfg') -Algorithm SHA256).Hash
# Include the original package identities in the effective-settings preflight.
$expected['application/config/version'] = $package.BuildVersion
$expected['application/run/main_scene'] = 'res://scenes/Menu.tscn'
$expectedPath = Join-Path $nativeRoot 'expected.json'
[IO.File]::WriteAllText($expectedPath, ($expected | ConvertTo-Json), $utf8)
$preflightScript = Join-Path $nativeRoot 'preflight.gd'
[IO.File]::WriteAllText($preflightScript, @'
extends SceneTree
func _initialize() -> void:
    var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ABYSSAL_NATIVE_EXPECTED")))
    var errors: Array[String] = []
    var actual: Dictionary = {}
    for key: String in expected:
        actual[key] = ProjectSettings.get_setting(key)
        if actual[key] != expected[key]:
            errors.append("Effective native sidecar setting differs: " + key)
    var sandbox := OS.get_environment("ABYSSAL_NATIVE_ROOT").replace("\\", "/").trim_suffix("/").to_lower()
    var profile := OS.get_user_data_dir().replace("\\", "/")
    if not profile.to_lower().begins_with(sandbox + "/"):
        errors.append("Native sidecar profile is outside the temporary root")
    var output := FileAccess.open(OS.get_environment("ABYSSAL_NATIVE_RESULT"), FileAccess.WRITE)
    if output == null:
        quit(1)
        return
    output.store_string(JSON.stringify({"actual": actual, "failures": errors, "user_data": profile}, "  "))
    output.close()
    for error: String in errors:
        printerr("[FAIL] " + error)
    quit(0 if errors.is_empty() else 1)
'@, $utf8)

function Quote-NativeArgument([string]$Value) {
    '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}
function Invoke-IsolatedNativeStep([string]$Program, [string[]]$Arguments, [string]$Phase, [int]$TimeoutMs) {
    $resultPath = Join-Path $nativeRoot ($Phase + '-result.json')
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Program
    $info.Arguments = ($Arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' '
    $info.WorkingDirectory = $nativeRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME')) {
        # Preflight and native gameplay use different fresh profiles.
        $directory = Join-Path $nativeRoot ($Phase + '-' + $name.ToLowerInvariant())
        New-Item -ItemType Directory -Path $directory | Out-Null
        $info.EnvironmentVariables[$name] = $directory
    }
    $info.EnvironmentVariables['ABYSSAL_NATIVE_ROOT'] = $nativeRoot
    $info.EnvironmentVariables['ABYSSAL_NATIVE_COPY'] = $copyPath
    $info.EnvironmentVariables['ABYSSAL_NATIVE_RESULT'] = $resultPath
    $info.EnvironmentVariables['ABYSSAL_NATIVE_EXPECTED'] = $expectedPath
    $info.EnvironmentVariables['ABYSSAL_NATIVE_NONCE'] = $nonce
    $info.EnvironmentVariables['ABYSSAL_NATIVE_PHASE'] = $Phase
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Could not start isolated native validation.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutMs)
        if ($timedOut) {
            $process.Kill()
            $process.WaitForExit()
        }
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $nativeRoot ($Phase + '-console.log')), $output, $utf8)
        if ($timedOut) { throw "Native $Phase exceeded its timeout. Evidence: $nativeRoot" }
        # GUI export templates write engine diagnostics only to --log-file.
        $engineLog = Join-Path $nativeRoot ($Phase + '-engine.log')
        if (Test-Path -LiteralPath $engineLog) { $output += [IO.File]::ReadAllText($engineLog) }
        $errors = @($output -split '\r?\n' | Where-Object {
            $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|ERROR:|ObjectDB instances leaked at exit' -and
            $_ -notmatch 'ERROR: Failed to read the root certificate store\.'
        })
        if ($process.ExitCode -ne 0 -or $errors.Count -gt 0 -or -not (Test-Path -LiteralPath $resultPath)) {
            Write-Host $output
            throw "Native $Phase failed (exit $($process.ExitCode)). Evidence: $nativeRoot"
        }
        $parsed = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        if (@($parsed.failures).Count -gt 0) { throw "Native $Phase reported failed checks: $resultPath" }
        $warnings = @($output -split '\r?\n' | Where-Object { $_ -match 'ObjectDB instances leaked at exit|^ERROR: \d+ resources still in use at exit' } | Select-Object -Unique)
        $parsed | Add-Member -NotePropertyName shutdown_warnings -NotePropertyValue $warnings
        return $parsed
    } finally { $process.Dispose() }
}

$preflight = Invoke-IsolatedNativeStep $GodotPath @('--headless', '--audio-driver', 'Dummy', '--main-pack', $copyPath, '--script', $preflightScript, '--log-file', (Join-Path $nativeRoot 'preflight-engine.log')) 'preflight' 35000
Write-Host '[PASS] Literal sidecar and effective service settings/profile verified before native launch'
if ((Get-FileHash -LiteralPath $copyPath -Algorithm SHA256).Hash -ne $sourceHash) { throw 'Temporary executable changed before native launch.' }
if ((Get-FileHash -LiteralPath (Join-Path $nativeRoot 'override.cfg') -Algorithm SHA256).Hash -ne $overrideHash) { throw 'Native sidecar changed after settings preflight.' }
$native = Invoke-IsolatedNativeStep $copyPath @('--headless', '--audio-driver', 'Dummy', '--max-fps', '60', '--log-file', (Join-Path $nativeRoot 'native-engine.log')) 'native' 55000
if ($native.nonce -ne $nonce -or @($native.stages)[-1] -ne 'completed' -or -not $native.native_template) { throw "Native driver did not complete the required flow: $nativeRoot" }
if ((Get-FileHash -LiteralPath $copyPath -Algorithm SHA256).Hash -ne $sourceHash -or (Get-FileHash -LiteralPath $ExecutablePath -Algorithm SHA256).Hash -ne $sourceHash) { throw 'Executable changed during native smoke.' }
Write-Host "[PASS] Actual normal executable: $($native.checks) checks; Menu, Practice configuration/restart/return, first descent, movement, return, reopen"
if (@($native.shutdown_warnings).Count) { Write-Warning "Native shutdown warnings retained: $nativeRoot" }
$report = [PSCustomObject]@{
    ExecutablePath = $ExecutablePath
    CopiedExecutablePath = $copyPath
    SHA256 = $sourceHash
    TemplateCodeSHA256 = $templateCodeHash
    BuildVersion = $package.BuildVersion
    PackageChecks = $package.Checks
    NativeChecks = $native.checks
    NativeStages = $native.stages
    ActualExecutableStarted = $true
    ExternalDriver = $true
    Controls = 'Injected Enter/Escape keyboard events; movement Input action; profile text set by driver'
    Headless = $true
    ApplicationCacheRetiredByDriver = $native.application_cache_retired_by_driver
    UserData = $native.user_data
    ResumeAvailable = $native.resume_available
    ShutdownWarnings = $native.shutdown_warnings
    EvidenceRoot = $nativeRoot
}
[IO.File]::WriteAllText((Join-Path $nativeRoot 'report.json'), ($report | ConvertTo-Json -Depth 6), $utf8)
$report
