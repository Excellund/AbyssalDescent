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
var retired_audio: Array[WeakRef] = []

func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures.append(message)
        printerr("[FAIL] " + message)

func _initialize() -> void:
    print("[Smoke] Initializing external executable probe")
    node_added.connect(observe_audio)
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
    check((root.get_node_or_null("DebugPlaytestBootstrap") != null) == debug_run, "Character-access bootstrap must exist only in the debug artifact")
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
    check(not bool(settings.get("autostart_from_menu")), "Debug playtest must allow returning to the character-selection Menu")
    check(bool(settings.get("skip_starting_boon_selection")), "Debug scene must enter a room without a starting reward screen")
    check(int(settings.get("start_bearing")) == 1, "Debug scene must select Delver")
    var context: Node = root.get_node("RunContext")
    var available: Array = context.get_unlocked_character_ids()
    for character_id: String in ["bastion", "hexweaver", "veilstrider", "riftlancer"]:
        check(available.has(character_id), "Debug profile must expose character selection: " + character_id)
    root.add_child(world)
    print("[Smoke] Packaged gameplay startup finished")
    current_scene = world
    check(await wait_until(func(): return is_instance_valid(world.get("player")) and get_nodes_in_group("enemies").size() >= 5), "Debug startup must finish spawning its initial encounter")
    var player: Node = world.get("player")
    check(is_instance_valid(player) and player.is_inside_tree(), "Debug startup must create a live player")
    if is_instance_valid(player):
        var levels: Dictionary = {"static_wake_stacks": 1, "storm_crown_stacks": 2, "hunters_snare_stacks": 1, "sovereigns_double_stacks": 1}
        result["powers"] = {}
        for property: String in levels:
            result["powers"][property] = player.get(property)
            check(int(player.get(property)) == int(levels[property]), "Live player power level: " + property)
        check(bool(player.get("reward_static_wake")) and bool(player.get("reward_storm_crown")) and bool(player.get("reward_hunters_snare")), "The live player must have dash ribbons, electric chains and a deliberate Slow source")
        check(not bool(player.get("reward_returning_crescent")) and not bool(player.get("reward_blast_drive")) and not bool(player.get("reward_razor_orbit")) and int(player.get("ruinous_impact_stacks")) == 0, "The focused electricity preset must not add unrelated damage or motion powers")
    check(int(world.get("current_difficulty_tier")) == 1, "Live run must use Delver")
    check(str(world.get("current_character_id")) == "bastion", "Fresh debug run must use Bastion")
    check(not bool(world.get("is_multiplayer")), "Debug run must be local")
    check(str(world.get("current_room_label")) == "Undertow", "Electricity debug startup must enter the standard Undertow encounter")
    check(int(world.get("room_depth")) == 10, "Electricity debug startup must begin at its configured depth")
    # The normal biome roll can change this encounter's population (The
    # Crumble increases three Chasers to four). Resolve the same live builder
    # configuration without consuming the run's future layout/random choices.
    var saved_rng_state: int = world.rng.state
    var resolved_profile: Dictionary = world._build_debug_encounter_profile("undertow", int(world.room_depth))
    resolved_profile = world._apply_debug_mutator_override(resolved_profile)
    world.rng.state = saved_rng_state
    var expected_enemy_types: Dictionary = {}
    for enemy_type: String in world.enemy_spawner.scripts:
        var expected_count: int = world.enemy_spawner._profile_count_for_enemy_type(resolved_profile, enemy_type)
        if expected_count > 0:
            var enemy_script: Script = world.enemy_spawner.scripts[enemy_type]
            expected_enemy_types[enemy_script.resource_path] = expected_count
    var enemies: Array[Node] = get_nodes_in_group("enemies")
    var enemy_types: Dictionary = {}
    result["biome_id"] = world.encounter_profile_builder.active_biome.get("id", "")
    result["biome_enemy_weights"] = world.encounter_profile_builder.active_biome.get("enemy_weight_overrides", {})
    result["expected_enemy_types"] = expected_enemy_types
    result["enemy_instances"] = []
    var current_room_actors: bool = true
    for enemy: Node in enemies:
        var path: String = enemy.get_script().resource_path
        enemy_types[path] = int(enemy_types.get(path, 0)) + 1
        result["enemy_instances"].append({"script": path, "queued_for_deletion": enemy.is_queued_for_deletion(), "path": str(enemy.get_path())})
        current_room_actors = current_room_actors and not enemy.is_queued_for_deletion() and enemy.get_parent() == world
    result["enemy_types"] = enemy_types
    check(current_room_actors, "Initial enemies must belong to the current room and not await deletion")
    check(not expected_enemy_types.is_empty() and enemy_types == expected_enemy_types and enemies.size() == int(world.active_room_enemy_count), "Debug Undertow live roster must exactly match the resolved Delver/biome profile")
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
    # Use the actual Abandon -> Menu -> character/Bearing buttons. Directly
    # replacing Main missed the debug Menu immediately relaunching gameplay.
    # Onboarding is unrelated to selection; satisfy it in this disposable profile.
    context.telemetry_consent_asked = true
    context.set_profile_name("SmokePilot", false)
    recorder = null
    player = null
    settings = null
    for character_id: String in ["hexweaver", "veilstrider", "riftlancer", "bastion"]:
        world.pause_menu_controller.open()
        world.pause_menu_controller.abandon_run_requested.emit()
        world = null
        var menu_ready: bool = await wait_until(func(): return menu_is_interactive())
        check(menu_ready, "Abandon must leave an interactive Menu instead of autostarting: " + character_id)
        if not menu_ready:
            result["scene_after_abandon"] = current_scene.scene_file_path if is_instance_valid(current_scene) else ""
            await clear_current_scene()
            finish()
            return
        check(not current_scene._has_saved_run(), "Abandon must clear the debug checkpoint")
        check(current_scene.primary_run_button.text == "Begin Descent", "Menu must offer a fresh descent")
        current_scene.primary_run_button.pressed.emit()
        var selector_ready: bool = await wait_until(func(): return current_scene.character_selector_panel.is_visible_in_tree() and current_scene.character_selector_panel.modulate.a >= 0.99)
        check(selector_ready, "Begin Descent must open the actual character selector")
        if not selector_ready:
            await clear_current_scene()
            finish()
            return
        var character_index: int = current_scene.character_ids.find(character_id)
        check(character_index >= 0, "Character selector must contain: " + character_id)
        if character_index < 0:
            await clear_current_scene()
            finish()
            return
        var character_button: Button = current_scene.character_buttons[character_index]
        check(character_button.is_visible_in_tree() and not character_button.disabled, "Character button must be usable: " + character_id)
        character_button.pressed.emit()
        character_button = null
        var bearing_ready: bool = await wait_until(func(): return current_scene.difficulty_selector_panel.is_visible_in_tree() and current_scene.difficulty_selector_panel.modulate.a >= 0.99 and not current_scene.difficulty_tier_buttons[0].disabled)
        check(bearing_ready, "Choosing a character must open the actual Bearing selector")
        if not bearing_ready:
            await clear_current_scene()
            finish()
            return
        # Only character access is granted. Use the available Pilgrim button;
        # the debug scene must still apply its Delver encounter override.
        current_scene.difficulty_tier_buttons[0].pressed.emit()
        var gameplay_ready: bool = await wait_until(func(): return is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/Main.tscn" and is_instance_valid(current_scene.get("player")))
        check(gameplay_ready, "Actual character/Bearing buttons must start Main")
        if not gameplay_ready:
            await clear_current_scene()
            finish()
            return
        world = current_scene
        player = world.get("player")
        check(str(world.get("current_character_id")) == character_id and str(player.get("active_character_id")) == character_id, "New gameplay scene must apply the selected character: " + character_id)
        check(int(world.get("current_difficulty_tier")) == 1 and str(world.get("current_room_label")) == "Undertow" and int(world.get("room_depth")) == 10, "Character switching must retain the electricity encounter preset")
        check(int(player.get("static_wake_stacks")) == 1 and int(player.get("storm_crown_stacks")) == 2 and int(player.get("hunters_snare_stacks")) == 1 and int(player.get("sovereigns_double_stacks")) == 1, "Character switching must retain the focused electricity kit")
        player = null
    world = null
    await clear_current_scene()
    packed = null
    finish()

func menu_is_interactive() -> bool:
    if not is_instance_valid(current_scene) or current_scene.scene_file_path != "res://scenes/Menu.tscn":
        return false
    return current_scene.primary_run_button.is_visible_in_tree() and not current_scene.primary_run_button.disabled and current_scene.root_panel.modulate.a >= 0.99 and not current_scene._is_profile_prompt_blocked() and not current_scene.profile_name_prompt_layer.visible

func wait_until(predicate: Callable, timeout_seconds: float = 5.0) -> bool:
    var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
    while not predicate.call():
        if Time.get_ticks_msec() >= deadline:
            return false
        await process_frame
    return true

func clear_current_scene() -> void:
    paused = true
    if is_instance_valid(current_scene):
        current_scene.queue_free()
        current_scene = null
    await process_frame
    await process_frame
    # Main's mapper cache intentionally lives for the application lifetime.
    # Retire it only after the final scene, matching other isolated fixtures.
    check(await wait_until(func(): return audio_has_retired()), "Native audio playback must retire after scene teardown")
    var mapper: Script = load("res://scripts/power_parameter_mapper.gd")
    if is_instance_valid(mapper._power_registry_instance):
        mapper._power_registry_instance.free()
        mapper._power_registry_instance = null

func observe_audio(node: Node) -> void:
    if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
        node.tree_exiting.connect(capture_audio.bind(node))

func capture_audio(node: Node) -> void:
    if bool(node.call("has_stream_playback")):
        retired_audio.append(weakref(node.call("get_stream_playback")))

func audio_has_retired() -> bool:
    for playback: WeakRef in retired_audio:
        if playback.get_ref() != null:
            return false
    return true

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
