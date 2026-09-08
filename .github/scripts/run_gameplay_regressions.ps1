param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
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
    throw "Set -GodotPath, .vscode/settings.json godot.executablePath, or GODOT_EXE to a Godot 4.6 executable."
}
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path

# Keep imported resources, settings, save files, and logs outside the real project.
$validationId = [guid]::NewGuid().ToString("N")
$validationRoot = Join-Path ([IO.Path]::GetTempPath()) ("abyssal-validation-" + $validationId)
New-Item -ItemType Directory -Path $validationRoot | Out-Null
foreach ($folder in @("scripts", "scenes", "assets", "music", "sounds")) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $folder) -Destination $validationRoot -Recurse
}
New-Item -ItemType Directory -Path (Join-Path $validationRoot ".github") | Out-Null
Copy-Item -LiteralPath $PSScriptRoot -Destination (Join-Path $validationRoot ".github") -Recurse
foreach ($file in @("project.godot", "icon.svg", "icon.svg.import")) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $validationRoot
}

# Inherit real autoload scripts so every production method still compiles, while
# suppressing profile loads, upload queues, process polling, and session startup.
$fixtureRoot = Join-Path $validationRoot "validation_fixtures"
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$configPath = Join-Path $validationRoot "project.godot"
$config = Get-Content -LiteralPath $configPath -Raw
$autoloads = [regex]::Matches($config, '(?m)^(\w+)="\*(res://[^"]+)"')
foreach ($autoload in $autoloads) {
    $fixtureName = $autoload.Groups[1].Value + ".gd"
    $fixture = 'extends "' + $autoload.Groups[2].Value + '"' + @'


func _ready() -> void:
    set_process(false)
    set_physics_process(false)

func _process(_delta: float) -> void:
    pass

func _physics_process(_delta: float) -> void:
    pass
'@
    Set-Content -LiteralPath (Join-Path $fixtureRoot $fixtureName) -Value $fixture -Encoding utf8
    $replacement = $autoload.Groups[1].Value + '="*res://validation_fixtures/' + $fixtureName + '"'
    $config = $config.Replace($autoload.Value, $replacement)
}
$config = [regex]::Replace($config, '(?m)^config/name="[^"]*"', ('config/name="AbyssalValidation-' + $validationId + '"'))
$config = $config.Replace("[application]", "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"userdata`"")
$config = [regex]::Replace($config, '(?m)^config/(telemetry_upload_endpoint|telemetry_upload_api_key|multiplayer_room_registry_endpoint|multiplayer_room_registry_api_key|multiplayer_public_ip_lookup_url|update_feed_url|update_release_page_url)="[^"]*"', 'config/$1=""')
$config = $config.Replace("config/multiplayer_tunnel_enabled=true", "config/multiplayer_tunnel_enabled=false")
Set-Content -LiteralPath $configPath -Value $config -Encoding utf8

# Godot registers autoload identifiers after compiling the command-line entry
# script. Load the requested suite afterward, keeping its SceneTree API intact.
Set-Content -LiteralPath (Join-Path $validationRoot "validation_entry.gd") -Encoding utf8 -Value @'
extends SceneTree

func _initialize() -> void:
    call_deferred("_start_test")

func _start_test() -> void:
    var arguments := OS.get_cmdline_user_args()
    if arguments.is_empty():
        push_error("A test script path is required")
        quit(1)
        return
    var project_root := ProjectSettings.globalize_path("res://")
    if not OS.get_user_data_dir().begins_with(project_root):
        push_error("User data is not isolated inside the validation project")
        quit(1)
        return
    var test_script := load(arguments[0]) as Script
    if test_script == null or not test_script.can_instantiate():
        push_error("Test script did not compile: " + arguments[0])
        quit(1)
        return
    print("[IsolatedTest] " + arguments[0])
    set_script(test_script)
    call("_initialize")
'@

function Invoke-GodotCheck {
    param([string]$Label, [string[]]$Arguments)
    $consoleLog = Join-Path $validationRoot ($Label + "-console.log")
    $engineLog = Join-Path $validationRoot ($Label + ".log")
    # Windows PowerShell represents native stderr as error records. Read the
    # complete log and exit code instead of stopping at the first stderr line.
    $ErrorActionPreference = "Continue"
    & $GodotPath --headless --path $validationRoot --log-file $engineLog @Arguments *> $consoleLog
    $checkExitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    $output = Get-Content -LiteralPath $consoleLog
    $errors = $output | Where-Object {
        $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|ERROR:' -and
        $_ -notmatch 'ERROR: Failed to read the root certificate store\.'
    }
    if ($checkExitCode -ne 0 -or $errors) {
        $output | Write-Output
        throw "$Label failed (exit $checkExitCode). See $consoleLog"
    }
    Write-Host "[PASS] $Label"
    $output | Where-Object { $_ -match '^\[OK\]|^Power reward regressions:|^Oath tracking regression tests passed' } | Write-Output
}

$environmentNames = @("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME")
$previousEnvironment = @{}
try {
    foreach ($name in $environmentNames) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
        $isolatedPath = Join-Path $validationRoot $name.ToLowerInvariant()
        New-Item -ItemType Directory -Path $isolatedPath | Out-Null
        [Environment]::SetEnvironmentVariable($name, $isolatedPath, "Process")
    }
    Invoke-GodotCheck -Label "import" -Arguments @("--editor", "--import")
    $checks = @(
        "res://.github/scripts/validate_gdscript_compile.gd",
        "res://.github/scripts/validate_world_property_access.gd",
        "res://.github/scripts/validate_multiplayer_config_sync.gd",
        "res://scripts/tests/test_reward_input.gd",
        "res://scripts/tests/test_power_rewards.gd",
        "res://scripts/tests/test_oath_tracking.gd",
        "res://scripts/tests/test_catalyst_profile.gd",
        "res://scripts/tests/test_catalyst_rewards.gd",
        "res://scripts/tests/test_catalyst_runtime.gd"
    )
    foreach ($scriptPath in $checks) {
        $label = [IO.Path]::GetFileNameWithoutExtension($scriptPath)
        Invoke-GodotCheck -Label $label -Arguments @("--script", "res://validation_entry.gd", "--", $scriptPath)
    }
} finally {
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], "Process")
    }
    Write-Host "Validation logs: $validationRoot"
}
