param(
    [string]$GodotPath = "",
    [string]$OutputPath = "",
    [string]$BuildVersion = "",
    [switch]$DebugRun,
    [switch]$ValidateOnly,
    [switch]$Overwrite
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$desktopPlaytest = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'AbyssalDescent Playtest.exe'
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = $desktopPlaytest }
$BuildVersion = $BuildVersion.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($BuildVersion)) {
    $versionPrefix = if ($DebugRun) { 'dev-debug-' } else { 'dev-' }
    $BuildVersion = $versionPrefix + [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmssfff") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
}
if ($BuildVersion -notmatch '^dev-[a-z0-9][a-z0-9.-]{0,79}$') {
    throw "BuildVersion must begin with dev- and contain only letters, numbers, dots, and hyphens."
}
if (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectRoot $OutputPath
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
# Both playtest modes have one user-facing destination, authorized to replace.
# Custom output paths retain the explicit overwrite safeguard.
$isDesktopPlaytest = $OutputPath.Equals([IO.Path]::GetFullPath($desktopPlaytest), [StringComparison]::OrdinalIgnoreCase)
if ($isDesktopPlaytest) { $Overwrite = $true }
if ([IO.Path]::GetExtension($OutputPath) -ne ".exe") {
    throw "OutputPath must name a Windows .exe file."
}
if ((Test-Path -LiteralPath $OutputPath) -and -not $Overwrite) {
    throw "Output already exists: $OutputPath. Choose another name or explicitly pass -Overwrite."
}
if (-not (Test-Path -LiteralPath (Split-Path -Parent $OutputPath))) {
    throw "The output directory does not exist: $(Split-Path -Parent $OutputPath)"
}
if ($ValidateOnly) {
    [PSCustomObject]@{ BuildVersion = $BuildVersion; OutputPath = $OutputPath; Overwrite = $Overwrite.IsPresent; DebugRun = $DebugRun.IsPresent }
    return
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $settingsPath = Join-Path $projectRoot ".vscode/settings.json"
    if (Test-Path -LiteralPath $settingsPath) {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $GodotPath = [string]$settings.'godot.executablePath'
    }
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = $env:GODOT_EXE
}
if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw "Set -GodotPath, .vscode/settings.json godot.executablePath, or GODOT_EXE to a Godot executable."
}
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$engineVersion = (& $GodotPath --version | Select-Object -Last 1).Trim()
if ($LASTEXITCODE -ne 0 -or $engineVersion -notmatch '^(\d+\.\d+\.\d+\.[^.]+)\.') {
    throw "Could not determine the Godot export template version: $engineVersion"
}
$templateVersion = $Matches[1]
$templateRoots = @(
    (Join-Path $env:APPDATA "Godot/export_templates/$templateVersion"),
    (Join-Path (Split-Path -Parent $GodotPath) "editor_data/export_templates/$templateVersion")
)
$requiredTemplate = if ($DebugRun) { 'windows_debug_x86_64.exe' } else { 'windows_release_x86_64.exe' }
$templateRoot = $templateRoots | Where-Object {
    Test-Path -LiteralPath (Join-Path $_ $requiredTemplate)
} | Select-Object -First 1
if (-not $templateRoot) {
    throw "Install the Windows x86_64 export templates matching Godot $templateVersion."
}

# Import/export never runs the game. Use a fresh production copy, not the
# regression runner's fixture project, and keep editor state outside real saves.
$exportRoot = Join-Path ([IO.Path]::GetTempPath()) ("abyssal-playtest-export-" + [guid]::NewGuid().ToString("N"))
$stagingProject = Join-Path $exportRoot "project"
$verificationProject = Join-Path $exportRoot "verify"
New-Item -ItemType Directory -Path $stagingProject, $verificationProject | Out-Null
foreach ($folder in @("scripts", "scenes", "assets", "music", "sounds")) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $folder) -Destination $stagingProject -Recurse
}
foreach ($file in @("project.godot", "export_presets.cfg", "icon.svg", "icon.svg.import")) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $stagingProject
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$configPath = Join-Path $stagingProject "project.godot"
$config = Get-Content -LiteralPath $configPath -Raw
if ($DebugRun) {
    $config = [regex]::Replace($config, '(?m)^config/name="[^"]*"', 'config/name="AbyssalDescent - New Powers Debug"')
    $config = [regex]::Replace($config, '(?m)^run/main_scene="[^"]*"', 'run/main_scene="res://scenes/Main.tscn"')
    $config = [regex]::Replace($config, '(?m)^config/(use_custom_user_dir|custom_user_dir_name)=.*\r?\n', '')
    $config = $config.Replace('[application]', "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"AbyssalDescent Playtest Debug`"")
    $config = [regex]::Replace($config, '(?m)^config/(telemetry_upload_endpoint|telemetry_upload_api_key|multiplayer_room_registry_endpoint|multiplayer_room_registry_api_key|multiplayer_public_ip_lookup_url|update_feed_url|update_release_page_url)="[^"]*"', 'config/$1=""')
    $config = $config.Replace('config/multiplayer_tunnel_enabled=true', 'config/multiplayer_tunnel_enabled=false')
} else {
    $config = [regex]::Replace($config, '(?m)^run/main_scene="[^"]*"', 'run/main_scene="res://scenes/Menu.tscn"')
}
# The preset belongs to this artifact; never change the developer's source scene.
$scenePath = Join-Path $stagingProject 'scenes/Main.tscn'
$scene = Get-Content -LiteralPath $scenePath -Raw
$debugNodePattern = '(?ms)(\[node name="DebugSettings"[^\]]*\]\r?\n).*?(?=\[node |\z)'
if (-not [regex]::IsMatch($scene, $debugNodePattern)) { throw 'Main scene is missing its DebugSettings node.' }
$debugSettings = if ($DebugRun) {
@'
script = ExtResource("5_oxjlc")
enabled = true
skip_starting_boon_selection = true
apply_test_powers_on_start = true
start_bearing = 1
start_power_preset = 0
start_encounter = 0
end_screen_preview = 0
start_power_ids = PackedStringArray("blast_drive", "blast_drive", "blast_drive", "razor_orbit", "razor_orbit", "razor_orbit", "ruinous_impact", "ruinous_impact", "sovereigns_double", "sovereigns_double")

'@
} else {
@'
script = ExtResource("5_oxjlc")
enabled = false

'@
}
$scene = [regex]::Replace($scene, $debugNodePattern, ('$1' + $debugSettings + "`n"))
[IO.File]::WriteAllText($scenePath, $scene, $utf8)
$expectedSettings = @{}
foreach ($autoload in [regex]::Matches($config, '(?m)^(\w+)="(\*res://scripts/[^"]+)"')) {
    $expectedSettings["autoload/" + $autoload.Groups[1].Value] = $autoload.Groups[2].Value
}
if ($expectedSettings.Count -eq 0 -or $config -match 'validation_fixtures') {
    throw "The source project must contain its real production autoloads."
}
foreach ($key in @("config/name", "run/main_scene")) {
    $match = [regex]::Match($config, '(?m)^' + [regex]::Escape($key) + '="([^"]*)"')
    if (-not $match.Success) { throw "Missing application setting: $key" }
    $expectedSettings["application/" + $key] = $match.Groups[1].Value
}
$config = [regex]::Replace($config, '(?m)^config/version="[^"]*"', ('config/version="' + $BuildVersion + '"'))
$config = [regex]::Replace($config, '(?m)^config/update_feed_url="[^"]*"', 'config/update_feed_url=""')
$expectedSettings["application/config/version"] = $BuildVersion
$expectedSettings["application/config/update_feed_url"] = ""
if ($DebugRun) {
    $expectedSettings['application/config/use_custom_user_dir'] = $true
    $expectedSettings['application/config/custom_user_dir_name'] = 'AbyssalDescent Playtest Debug'
    foreach ($key in @('telemetry_upload_endpoint', 'telemetry_upload_api_key', 'multiplayer_room_registry_endpoint', 'multiplayer_room_registry_api_key', 'multiplayer_public_ip_lookup_url', 'update_release_page_url')) {
        $expectedSettings['application/config/' + $key] = ''
    }
    $expectedSettings['application/config/multiplayer_tunnel_enabled'] = $false
}
[IO.File]::WriteAllText($configPath, $config, $utf8)
$buildInfoPath = Join-Path $stagingProject "scripts/build_info.gd"
$buildInfo = Get-Content -LiteralPath $buildInfoPath -Raw
$buildInfo = [regex]::Replace($buildInfo, '(?m)^const GAME_VERSION := .*', ('const GAME_VERSION := "' + $BuildVersion + '"'))
[IO.File]::WriteAllText($buildInfoPath, $buildInfo, $utf8)
$presetPath = Join-Path $stagingProject "export_presets.cfg"
$preset = Get-Content -LiteralPath $presetPath -Raw
foreach ($kind in @("debug", "release")) {
    $templatePath = (Join-Path $templateRoot "windows_${kind}_x86_64.exe").Replace('\', '/')
    $preset = [regex]::Replace($preset, '(?m)^custom_template/' + $kind + '="[^"]*"', ('custom_template/' + $kind + '="' + $templatePath + '"'))
}
if ($preset -notmatch '(?m)^exclude_filter="[^"]*scripts/tests/\*') {
    throw "The Windows export preset must exclude scripts/tests/*."
}
$preset = [regex]::Replace($preset, '(?m)^debug/export_console_wrapper=\d+', 'debug/export_console_wrapper=0')
# Windows file metadata requires numbers; the game retains its unique dev build ID.
$preset = [regex]::Replace($preset, '(?m)^application/(file_version|product_version)="[^"]*"', 'application/$1="0.0.0.0"')
[IO.File]::WriteAllText($presetPath, $preset, $utf8)
[IO.File]::WriteAllText((Join-Path $verificationProject "expected.json"), ($expectedSettings | ConvertTo-Json), $utf8)
[IO.File]::WriteAllText((Join-Path $verificationProject "project.godot"), "config_version=5`n[application]`nconfig/name=`"AbyssalPackageVerification`"`n", $utf8)

# This empty project mounts the finished package as data. It never starts the
# exported executable, main scene, or any production autoload. project.binary's
# ECFG records contain length-prefixed setting names and serialized Variants.
[IO.File]::WriteAllText((Join-Path $verificationProject "verify_package.gd"), @'
extends SceneTree

var failure := false

func _initialize() -> void:
    var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://expected.json"))
    var arguments := OS.get_cmdline_user_args()
    if arguments.size() != 1 or not ProjectSettings.load_resource_pack(arguments[0]):
        push_error("Unable to mount the exported package")
        quit(1)
        return
    var config := FileAccess.open("res://project.binary", FileAccess.READ)
    if config == null or config.get_buffer(4).get_string_from_ascii() != "ECFG":
        push_error("Exported project.binary is missing or invalid")
        quit(1)
        return
    var actual: Dictionary = {}
    for index in config.get_32():
        var key := config.get_pascal_string()
        var value := config.get_buffer(config.get_32())
        # Only decode manifest primitives; input settings can contain Objects.
        if expected.has(key) or key.begins_with("autoload/"):
            actual[key] = bytes_to_var(value)
    config.close()
    if actual != expected:
        push_error("Exported application settings or autoloads differ from the production manifest")
        failure = true
    for key: String in expected:
        if key.begins_with("autoload/"):
            var path := str(expected[key]).trim_prefix("*")
            if not FileAccess.file_exists(path + "c"):
                push_error("Missing compiled production autoload: " + path)
                failure = true
    var build_info := load("res://scripts/build_info.gd") as Script
    if build_info == null or build_info.get_script_constant_map().get("GAME_VERSION") != expected["application/config/version"]:
        push_error("The exported BuildInfo version must match the requested dev build ID")
        failure = true
    _check_directory("res://")
    if not failure:
        print("[OK] Package verified: production autoloads, matching dev build ID, disabled update feed, no tests/fixtures")
    quit(1 if failure else 0)

func _check_directory(path: String) -> void:
    var directory := DirAccess.open(path)
    if directory == null:
        push_error("Cannot inspect package directory: " + path)
        failure = true
        return
    directory.include_hidden = true
    for entry in directory.get_files():
        var file_path := path.path_join(entry)
        if file_path.begins_with("res://scripts/tests/") or "validation_fixture" in file_path:
            push_error("Test or fixture included in package: " + file_path)
            failure = true
    for entry in directory.get_directories():
        _check_directory(path.path_join(entry))
'@, $utf8)

function Invoke-GodotExportStep {
    param([string]$Label, [string]$ProjectPath, [string[]]$Arguments)
    $consoleLog = Join-Path $exportRoot ($Label + "-console.log")
    $engineLog = Join-Path $exportRoot ($Label + ".log")
    $ErrorActionPreference = "Continue"
    & $GodotPath --headless --path $ProjectPath --log-file $engineLog @Arguments *> $consoleLog
    $stepExitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    $output = Get-Content -LiteralPath $consoleLog
    $errors = $output | Where-Object {
        $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|ERROR:' -and
        $_ -notmatch 'ERROR: Failed to read the root certificate store\.'
    }
    if ($stepExitCode -ne 0 -or $errors) {
        $output | Write-Output
        throw "$Label failed (exit $stepExitCode). See $consoleLog"
    }
    Write-Host "[PASS] $Label"
    $output | Where-Object { $_ -match '^\[OK\]' } | Write-Output
}

$previousEnvironment = @{}
$stagingExecutable = Join-Path $exportRoot "AbyssalDescent.exe"
try {
    foreach ($name in @("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
        $isolatedPath = Join-Path $exportRoot $name.ToLowerInvariant()
        New-Item -ItemType Directory -Path $isolatedPath | Out-Null
        [Environment]::SetEnvironmentVariable($name, $isolatedPath, "Process")
    }
    Write-Host "Exporting with Godot $engineVersion"
    Write-Host "Build version: $BuildVersion"
    Invoke-GodotExportStep -Label "import" -ProjectPath $stagingProject -Arguments @("--editor", "--import")
    $exportMode = if ($DebugRun) { 'export-debug' } else { 'export-release' }
    Invoke-GodotExportStep -Label $exportMode -ProjectPath $stagingProject -Arguments @("--$exportMode", "Windows Desktop", $stagingExecutable)
    Invoke-GodotExportStep -Label "verify-package" -ProjectPath $verificationProject -Arguments @("--script", "res://verify_package.gd", "--", $stagingExecutable)
    if ($isDesktopPlaytest) {
        # Replace only this exact game, after the next build is verified.
        foreach ($game in @(Get-Process -Name 'AbyssalDescent Playtest' -ErrorAction SilentlyContinue)) {
            if ($game.Path -ne $OutputPath) { continue }
            $null = $game.CloseMainWindow()
            if (-not $game.WaitForExit(3000)) {
                $game.Kill()
                if (-not $game.WaitForExit(3000)) { throw 'The previous desktop playtest could not be closed.' }
            }
        }
    }
    # Recheck after the build, and publish only a verified artifact.
    if ((Test-Path -LiteralPath $OutputPath) -and -not $Overwrite) {
        throw "Output appeared during export; preserved existing file: $OutputPath"
    }
    [IO.File]::Copy($stagingExecutable, $OutputPath, $Overwrite.IsPresent)
    $outputHash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash
    if ($outputHash -ne (Get-FileHash -LiteralPath $stagingExecutable -Algorithm SHA256).Hash) {
        throw "The output copy does not match the verified executable."
    }
    Write-Host "Playtest executable: $OutputPath"
    Write-Host "Build version: $BuildVersion"
    Write-Host "Size: $((Get-Item -LiteralPath $OutputPath).Length) bytes"
    Write-Host "SHA256: $outputHash"
    [PSCustomObject]@{ BuildVersion = $BuildVersion; OutputPath = $OutputPath; DebugRun = $DebugRun.IsPresent; SHA256 = $outputHash; StagingProject = $stagingProject }
} finally {
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], "Process")
    }
    Write-Host "Export logs and staging: $exportRoot"
}
