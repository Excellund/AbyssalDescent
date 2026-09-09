param(
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [switch]$DebugRun,
    [string]$GodotPath = ""
)

$ErrorActionPreference = 'Stop'
$ExecutablePath = (Resolve-Path -LiteralPath $ExecutablePath).Path
if ([IO.Path]::GetExtension($ExecutablePath) -ne '.exe') {
    throw 'ExecutablePath must name an exported Windows executable.'
}
if (-not $GodotPath) {
    $settingsPath = Join-Path $PSScriptRoot '../../.vscode/settings.json'
    if (Test-Path -LiteralPath $settingsPath) {
        $GodotPath = [string](Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json).'godot.executablePath'
    }
}
if (-not $GodotPath) { $GodotPath = $env:GODOT_EXE }
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Supply -GodotPath, configure .vscode/settings.json, or set GODOT_EXE.' }
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path

# Export templates ignore --script. Inspect the actual embedded package using
# the development engine and an external probe, then boot the debug EXE itself.
# Normal mode never opens Menu, which would run its network update check.
# All child processes receive fresh profile directories; the parent environment
# and the player's real settings, saves, and telemetry queues stay untouched.
$smokeRoot = Join-Path ([IO.Path]::GetTempPath()) ('abyssal-executable-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $smokeRoot | Out-Null
$probePath = Join-Path $smokeRoot 'executable_probe.gd'
$resultPath = Join-Path $smokeRoot 'result.json'
$logPath = Join-Path $smokeRoot 'engine.log'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($probePath, @'
extends SceneTree

var checks: int = 0
var failures: Array[String] = []
var debug_run: bool = false
var configured_main: String = ""
var result: Dictionary = {}

func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures.append(message)
        printerr("[FAIL] " + message)

func _initialize() -> void:
    print("[Smoke] Initializing external executable probe")
    debug_run = OS.get_environment("ABYSSAL_SMOKE_DEBUG") == "1"
    configured_main = str(ProjectSettings.get_setting("application/run/main_scene", ""))
    var sandbox: String = OS.get_environment("ABYSSAL_SMOKE_ROOT").replace("\\", "/").trim_suffix("/").to_lower()
    var user_data: String = OS.get_user_data_dir().replace("\\", "/")
    check(not sandbox.is_empty() and user_data.to_lower().begins_with(sandbox + "/"), "User data must be inside the temporary smoke profile")
    result = {"mode": "debug" if debug_run else "normal", "main_scene": configured_main, "user_data": user_data, "engine": Engine.get_version_info().string}
    # Capture package configuration before temporary runtime overrides. Normal
    # mode deliberately never enters Menu, where update/profile prompts live.
    check(FileAccess.file_exists("res://project.binary"), "The executable must load an exported package")
    check(str(ProjectSettings.get_setting("application/config/version", "")).begins_with("dev-"), "Smoke only developer playtest builds")
    result["build_version"] = ProjectSettings.get_setting("application/config/version", "")
    var network_keys: Array[String] = [
        "application/config/telemetry_upload_endpoint",
        "application/config/telemetry_upload_api_key",
        "application/config/multiplayer_room_registry_endpoint",
        "application/config/multiplayer_room_registry_api_key",
        "application/config/multiplayer_public_ip_lookup_url",
        "application/config/update_feed_url",
        "application/config/update_release_page_url",
    ]
    for key in network_keys:
        if debug_run:
            check(str(ProjectSettings.get_setting(key, "")).is_empty(), "Debug package network setting must be blank: " + key)
        ProjectSettings.set_setting(key, "")
    if debug_run:
        check(not bool(ProjectSettings.get_setting("application/config/multiplayer_tunnel_enabled", false)), "Debug package tunnels must be disabled")
        check(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)), "Debug package must use a separate profile")
        check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")) == "AbyssalDescent Playtest Debug", "Debug profile name must match the playtest profile")
    ProjectSettings.set_setting("application/config/multiplayer_tunnel_enabled", false)
    if not failures.is_empty():
        finish()
        return
    call_deferred("run_probe")

func run_probe() -> void:
    print("[Smoke] Checking packaged autoloads and gameplay scene")
    for singleton in ["RunContext", "Enums", "GameBalance", "ColorPalette", "MultiplayerSessionManager", "MultiplayerRoomService", "PlayerReplicationService", "GameStateReplicationService", "EnemyReplicationService"]:
        var node: Node = root.get_node_or_null(singleton)
        check(node != null, "Production autoload must initialize: " + singleton)
        if node != null:
            check(not "validation_fixture" in node.get_script().resource_path, "Autoload must use the production script: " + singleton)
    var expected_main: String = "res://scenes/Main.tscn" if debug_run else "res://scenes/Menu.tscn"
    check(configured_main == expected_main, "Packaged default scene must match the requested mode")
    check(ResourceLoader.exists(configured_main, "PackedScene"), "Packaged default scene must exist")
    var packed: PackedScene = load("res://scenes/Main.tscn") as PackedScene
    check(packed != null, "Packaged gameplay scene must load")
    if packed == null or not failures.is_empty():
        finish()
        return
    var world: Node = packed.instantiate()
    print("[Smoke] Packaged gameplay scene instantiated")
    var settings: Node = world.get_node_or_null("DebugSettings")
    check(settings != null, "Gameplay scene must contain DebugSettings")
    if settings != null:
        check(bool(settings.get("enabled")) == debug_run, "Gameplay debug settings must match the requested mode")
    if not debug_run or not failures.is_empty():
        world.free()
        finish()
        return
    check(bool(settings.get("apply_test_powers_on_start")), "Debug scene must apply its starting powers")
    check(bool(settings.get("skip_starting_boon_selection")), "Debug scene must enter a room without a starting reward screen")
    check(int(settings.get("start_bearing")) == 1, "Debug scene must select Delver")
    root.add_child(world)
    print("[Smoke] Packaged gameplay startup finished")
    current_scene = world
    for frame in 8:
        await process_frame
    var player: Node = world.get("player")
    check(is_instance_valid(player) and player.is_inside_tree(), "Debug startup must create a live player")
    if is_instance_valid(player):
        var levels: Dictionary = {"returning_crescent_stacks": 3, "blast_drive_stacks": 3, "razor_orbit_stacks": 3, "ruinous_impact_stacks": 2, "sovereigns_double_stacks": 2}
        result["powers"] = {}
        for property: String in levels:
            result["powers"][property] = player.get(property)
            check(int(player.get(property)) == int(levels[property]), "Live player power level: " + property)
        check(bool(player.get("reward_blast_drive")) and bool(player.get("reward_razor_orbit")), "Both motion Arcana must be enabled on the live player")
        check(bool(player.get("reward_returning_crescent")), "Returning Crescent must be enabled on the live player")
    check(int(world.get("current_difficulty_tier")) == 1, "Live run must use Delver")
    check(str(world.get("current_character_id")) == "bastion", "Fresh debug run must use Bastion")
    check(not bool(world.get("is_multiplayer")), "Debug run must be local")
    check(str(world.get("current_room_label")) == "Apex Breakwater", "Debug startup must enter Apex Breakwater")
    check(int(world.get("room_depth")) == 5, "Debug startup must use Breakwater's intended depth")
    var enemies: Array[Node] = get_nodes_in_group("enemies")
    check(enemies.size() == 1 and enemies[0].get_script().resource_path == "res://scripts/enemy_breakwater.gd", "Debug startup must spawn the actual Breakwater")
    enemies.clear()
    check(not bool(world.call("_is_reward_selection_active")), "Debug startup must bypass the starting reward screen")
    check(bool(world.call("_is_debug_boot_session")), "Live run must be identified as debug")
    var recorder: RefCounted = world.get("run_summary_recorder")
    check(recorder != null, "Debug run must initialize its recorder")
    if recorder != null:
        check(bool(recorder.get("_run_is_debug")), "Recorder must flag the run as debug")
        check(not bool(recorder.get("telemetry_enabled")), "Debug run must not collect telemetry")
    result["difficulty_tier"] = world.get("current_difficulty_tier")
    result["character_id"] = world.get("current_character_id")
    # Release the inspected tree before quitting so probe references cannot
    # create false leak reports while the engine unloads the package.
    paused = true
    recorder = null
    player = null
    settings = null
    packed = null
    world.queue_free()
    await process_frame
    await process_frame
    finish()

func finish() -> void:
    result["checks"] = checks
    result["failures"] = failures
    var file: FileAccess = FileAccess.open(OS.get_environment("ABYSSAL_SMOKE_RESULT"), FileAccess.WRITE)
    if file == null:
        printerr("[FAIL] Cannot write smoke result")
        quit(1)
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()
    if failures.is_empty():
        print("[PASS] Exported package smoke: " + str(checks) + " checks (" + result["mode"] + ")")
    quit(0 if failures.is_empty() else 1)
'@, $utf8)

function Quote-ProcessArgument([string]$Value) {
    # Windows CommandLineToArgvW escaping, including quoted paths and trailing slashes.
    '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}
function New-IsolatedProcessInfo([string]$FileName, [string[]]$Arguments) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $FileName
    $info.Arguments = ($Arguments | ForEach-Object { Quote-ProcessArgument $_ }) -join ' '
    $info.WorkingDirectory = $smokeRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME')) {
        $directory = Join-Path $smokeRoot $name.ToLowerInvariant()
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
        $info.EnvironmentVariables[$name] = $directory
    }
    $info.EnvironmentVariables['ABYSSAL_SMOKE_ROOT'] = $smokeRoot
    $info.EnvironmentVariables['ABYSSAL_SMOKE_RESULT'] = $resultPath
    $info.EnvironmentVariables['ABYSSAL_SMOKE_DEBUG'] = if ($DebugRun) { '1' } else { '0' }
    return $info
}

$process = New-Object Diagnostics.Process
$process.StartInfo = New-IsolatedProcessInfo $GodotPath @('--headless', '--audio-driver', 'Dummy', '--main-pack', $ExecutablePath, '--log-file', $logPath, '--script', $probePath)
try {
    if (-not $process.Start()) { throw 'Could not start the exported executable.' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(35000)) {
        $process.Kill()
        $process.WaitForExit()
        throw "Exported package smoke exceeded 35 seconds. Logs: $smokeRoot"
    }
    $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $smokeRoot 'console.log'), $output, $utf8)
    $errors = $output -split '\r?\n' | Where-Object {
        $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|ERROR:' -and
        $_ -notmatch 'ERROR: Failed to read the root certificate store\.|^ERROR: \d+ resources still in use at exit'
    }
    if ($process.ExitCode -ne 0 -or $errors -or -not (Test-Path -LiteralPath $resultPath)) {
        $output | Write-Output
        throw "Exported package smoke failed (exit $($process.ExitCode)). Logs: $smokeRoot"
    }
} finally {
    $process.Dispose()
}
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if (@($result.failures).Count -ne 0) { throw "Exported executable checks failed. Result: $resultPath" }
$shutdownWarnings = @($output -split '\r?\n' | Where-Object { $_ -match 'ObjectDB instances leaked at exit|^ERROR: \d+ resources still in use at exit' })

# The package check above proves debug endpoints are blank before the real EXE
# is allowed to boot. --quit-after is supported by both export templates.
if ($DebugRun) {
    $reference = New-Object Diagnostics.Process
    $actualLog = Join-Path $smokeRoot 'actual-executable.log'
    $reference.StartInfo = New-IsolatedProcessInfo $ExecutablePath @('--headless', '--audio-driver', 'Dummy', '--log-file', $actualLog, '--quit-after', '8')
    try {
        $null = $reference.Start()
        $referenceOutput = $reference.StandardOutput.ReadToEndAsync()
        $referenceError = $reference.StandardError.ReadToEndAsync()
        if (-not $reference.WaitForExit(15000)) {
            $reference.Kill()
            $reference.WaitForExit()
            throw "Actual debug executable startup exceeded 15 seconds. Logs: $smokeRoot"
        }
        $actualOutput = $referenceOutput.GetAwaiter().GetResult() + $referenceError.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $smokeRoot 'actual-console.log'), $actualOutput, $utf8)
        $actualErrors = $actualOutput -split '\r?\n' | Where-Object {
            $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|ERROR:' -and
            $_ -notmatch 'ERROR: Failed to read the root certificate store\.|^ERROR: \d+ resources still in use at exit'
        }
        $shutdownWarnings += @($actualOutput -split '\r?\n' | Where-Object { $_ -match 'ObjectDB instances leaked at exit|^ERROR: \d+ resources still in use at exit' })
        if ($reference.ExitCode -ne 0 -or $actualErrors) { throw "Actual debug executable startup failed. Logs: $smokeRoot" }
    } finally { $reference.Dispose() }
}
Write-Host "[PASS] Exported package: $($result.checks) checks ($($result.mode)); $($result.build_version)"
if ($DebugRun) { Write-Host '[PASS] Actual debug executable started and exited in the isolated profile' }
if ($shutdownWarnings.Count) { Write-Warning "Production shutdown reports retained resources; startup checks passed. Details: $smokeRoot" }
$result | Add-Member -NotePropertyName actual_executable_started -NotePropertyValue $DebugRun.IsPresent
$result | Add-Member -NotePropertyName package_inspection_engine -NotePropertyValue $GodotPath
$result | Add-Member -NotePropertyName shutdown_warnings -NotePropertyValue @($shutdownWarnings | Select-Object -Unique)
[IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 6), $utf8)
[PSCustomObject]@{
    ExecutablePath = $ExecutablePath
    DebugRun = $DebugRun.IsPresent
    ActualExecutableStarted = $DebugRun.IsPresent
    Checks = $result.checks
    BuildVersion = $result.build_version
    MainScene = $result.main_scene
    Powers = $result.powers
    UserData = $result.user_data
    ShutdownWarnings = @($shutdownWarnings | Select-Object -Unique)
    ResultPath = $resultPath
    LogPath = $logPath
}
