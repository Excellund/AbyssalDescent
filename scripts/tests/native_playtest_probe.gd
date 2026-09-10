extends Node
## External sidecar driver only. Never registered in a delivered project.

const BLANK_SETTINGS := [
    "telemetry_upload_endpoint", "telemetry_upload_api_key",
    "leaderboard_submit_endpoint", "leaderboard_rest_base_url",
    "multiplayer_room_registry_endpoint", "multiplayer_room_registry_api_key",
    "update_feed_url", "update_feed_token", "update_release_page_url",
    "project_settings_override",
]
const BLOCKED_LOOKUP := "http://127.0.0.1:9/native-smoke-disabled"
var failures: Array[String] = []
var stages: Array[String] = []
var checks := 0
var finished := false
var result: Dictionary = {}
var retired_audio: Array[WeakRef] = []

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    if OS.get_environment("ABYSSAL_NATIVE_PHASE") == "preflight":
        return
    get_tree().node_added.connect(observe_audio)
    var sandbox := OS.get_environment("ABYSSAL_NATIVE_ROOT").replace("\\", "/").trim_suffix("/").to_lower()
    var executable := OS.get_executable_path().replace("\\", "/")
    var profile := OS.get_user_data_dir().replace("\\", "/")
    check(not sandbox.is_empty() and profile.to_lower().begins_with(sandbox + "/"), "Native profile is inside the temporary root")
    check(executable.to_lower() == OS.get_environment("ABYSSAL_NATIVE_COPY").replace("\\", "/").to_lower(), "The copied normal executable is running")
    check(not OS.has_feature("editor") and OS.has_feature("release") and not OS.has_feature("debug"), "Native release template, normal mode")
    check(str(ProjectSettings.get_setting("application/config/version", "")).begins_with("dev-"), "Active native smoke accepts developer builds only")
    check(ProjectSettings.get_setting("application/run/main_scene", "") == "res://scenes/Menu.tscn", "Packaged Menu remains the main scene")
    for key: String in BLANK_SETTINGS:
        check(str(ProjectSettings.get_setting("application/config/" + key, "")) == "", "Service setting disabled before startup: " + key)
    check(not bool(ProjectSettings.get_setting("application/config/multiplayer_tunnel_enabled", true)), "Tunnels are disabled before startup")
    check(ProjectSettings.get_setting("application/config/multiplayer_public_ip_lookup_url", "") == BLOCKED_LOOKUP, "Public-IP fallback cannot reach a remote host")
    result = {"executable": executable, "user_data": profile, "engine": Engine.get_version_info().string, "build_version": ProjectSettings.get_setting("application/config/version", ""), "nonce": OS.get_environment("ABYSSAL_NATIVE_NONCE"), "driver": "external sidecar autoload", "native_template": true, "headless": DisplayServer.get_name() == "headless"}
    if not failures.is_empty():
        finish()
        return
    call_deferred("exercise")

func check(condition: bool, message: String) -> bool:
    checks += 1
    if not condition:
        failures.append(message)
        printerr("[FAIL] " + message)
    return condition

func wait_for(predicate: Callable, label: String, seconds: float = 8.0) -> bool:
    var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
    while not predicate.call() and Time.get_ticks_msec() < deadline:
        await get_tree().process_frame
    return check(predicate.call(), label)

func current_menu() -> Node:
    var scene := get_tree().current_scene
    return scene if is_instance_valid(scene) and scene.scene_file_path == "res://scenes/Menu.tscn" else null

func current_world() -> Node:
    var scene := get_tree().current_scene
    return scene if is_instance_valid(scene) and scene.scene_file_path == "res://scenes/Main.tscn" else null

func visible_control(node: Node) -> bool:
    return is_instance_valid(node) and node is Control and node.is_visible_in_tree() and node.modulate.a >= 0.99

func find_button(node: Node, label: String) -> Button:
    if node is Button and node.text == label:
        return node
    for child in node.get_children():
        var found := find_button(child, label)
        if found != null:
            return found
    return null

func press(button: Button, label: String) -> bool:
    if not check(visible_control(button) and not button.disabled, "Usable actual control: " + label):
        return false
    button.grab_focus()
    var activated := [false]
    button.pressed.connect(func(): activated[0] = true, CONNECT_ONE_SHOT)
    var press_event := InputEventKey.new()
    press_event.keycode = KEY_ENTER
    press_event.physical_keycode = KEY_ENTER
    press_event.pressed = true
    Input.parse_input_event(press_event)
    Input.flush_buffered_events()
    var release_event := InputEventKey.new()
    release_event.keycode = KEY_ENTER
    release_event.physical_keycode = KEY_ENTER
    Input.parse_input_event(release_event)
    Input.flush_buffered_events()
    return check(activated[0], "Keyboard activated actual control: " + label)

func press_escape() -> void:
    var press_event := InputEventKey.new()
    press_event.keycode = KEY_ESCAPE
    press_event.physical_keycode = KEY_ESCAPE
    press_event.pressed = true
    Input.parse_input_event(press_event)
    Input.flush_buffered_events()
    var release_event := InputEventKey.new()
    release_event.keycode = KEY_ESCAPE
    release_event.physical_keycode = KEY_ESCAPE
    Input.parse_input_event(release_event)
    Input.flush_buffered_events()

func menu_ready() -> bool:
    var menu := current_menu()
    return menu != null and visible_control(menu.get("root_panel")) and not menu.call("_is_profile_prompt_blocked") and not bool(menu.get("profile_name_prompt_layer").visible)

func exercise() -> void:
    if not await wait_for(func(): return current_menu() != null and visible_control(current_menu().get("telemetry_consent_layer")), "Fresh normal Menu displays telemetry choice"):
        finish()
        return
    var menu := current_menu()
    if not press(find_button(menu.get("telemetry_consent_layer"), "Not Now"), "Not Now"):
        finish()
        return
    if not await wait_for(func(): return visible_control(menu.get("profile_name_prompt_modal")), "Fresh profile prompt opens"):
        finish()
        return
    var modal: Node = menu.get("profile_name_prompt_modal")
    var name_input: LineEdit = modal.get("_name_input")
    name_input.text = "NativeSmoke"
    if not press(modal.get("_confirm_button"), "Profile confirmation"):
        finish()
        return
    modal = null
    if not await wait_for(menu_ready, "Normal Menu is ready after first-launch prompts"):
        finish()
        return
    var context := get_node("/root/RunContext")
    check(not context.call("is_telemetry_upload_enabled"), "Telemetry consent remains declined")
    check(context.call("get_profile_name") == "NativeSmoke", "Actual profile form persisted the isolated name")
    stages.append("fresh_menu")
    if not await begin_descent():
        finish()
        return
    var world := current_world()
    var player: Node2D = world.get("player")
    check(not bool(world.get("settings_enabled")), "Gameplay debug settings remain disabled")
    check(int(world.get("room_depth")) == 0 and int(world.get("current_difficulty_tier")) == 0, "Normal Pilgrim tutorial precedes depth one")
    check(str(world.get("current_character_id")) == "bastion", "Actual character control selected Bastion")
    check(bool(world.get("current_room_tutorial_active")), "Fresh profile enters its normal first-descent tutorial")
    result["first_room"] = world.get("current_room_label")
    result["first_main_instance"] = world.get_instance_id()
    var before := player.global_position
    Input.action_press("move_right")
    for frame in 12:
        await get_tree().physics_frame
    Input.action_release("move_right")
    check(player.global_position.distance_to(before) > 1.0, "Native gameplay advances player movement")
    stages.append("normal_main_movement")
    press_escape()
    var pause_menu: Node = world.get("pause_menu_controller")
    if not await wait_for(func(): return pause_menu.call("is_open") and visible_control(pause_menu.get("pause_menu_panel")), "Actual pause input opens the menu"):
        result["pause_diagnostic"] = {"open": pause_menu.call("is_open"), "paused": get_tree().paused, "defeat": world.get("defeat_screen").call("is_open"), "reward": world.get("reward_selection_ui").call("is_active")}
        finish()
        return
    if not press(find_button(pause_menu.get("pause_menu_panel"), "Back to Main Menu"), "Back to Main Menu"):
        finish()
        return
    world = null
    player = null
    pause_menu = null
    menu = null
    if not await wait_for(menu_ready, "Actual Back to Main Menu completes"):
        finish()
        return
    stages.append("returned_menu")
    result["resume_available"] = current_menu().call("_has_saved_run")
    # This first tutorial has no cleared-room checkpoint yet. Record that fact;
    # do not fabricate a Continue save just to satisfy the smoke fixture.
    if not check(not bool(result["resume_available"]), "Uncleared first tutorial has no completed-room checkpoint"):
        finish()
        return
    if not await begin_descent():
        finish()
        return
    check(current_world().get_instance_id() != int(result["first_main_instance"]), "Reopening creates a new production Main")
    stages.append("reopened_main")
    result["reopened_main_instance"] = current_world().get_instance_id()
    # Use the game's pause controls for the final transition too.
    var final_pause: Node = current_world().get("pause_menu_controller")
    press_escape()
    if not await wait_for(func(): return visible_control(final_pause.get("pause_menu_panel")), "Final pause menu settles"):
        finish()
        return
    press(find_button(final_pause.get("pause_menu_panel"), "Back to Main Menu"), "Final Back to Main Menu")
    final_pause = null
    if not await wait_for(menu_ready, "Final normal Menu settles before shutdown"):
        finish()
        return
    stages.append("completed")
    finish()

func begin_descent() -> bool:
    var menu := current_menu()
    if not press(menu.get("primary_run_button"), "Begin Descent"):
        return false
    if not await wait_for(func(): return visible_control(menu.get("character_selector_panel")), "Actual character selector opens"):
        return false
    var ids: Array = menu.get("character_ids")
    var buttons: Array = menu.get("character_buttons")
    var index := ids.find("bastion")
    if not check(index >= 0, "Bastion is offered to a fresh profile") or not press(buttons[index], "Bastion"):
        return false
    if not await wait_for(func(): return visible_control(menu.get("difficulty_selector_panel")), "Actual Bearing selector opens"):
        return false
    var tiers: Array = menu.get("difficulty_tier_buttons")
    if not press(tiers[0], "Pilgrim"):
        return false
    var initialized := await wait_for(func(): return current_world() != null and is_instance_valid(current_world().get("player")) and bool(current_world().get("current_room_tutorial_active")), "Production Main and tutorial player initialize")
    if not initialized:
        var scene := get_tree().current_scene
        result["startup_diagnostic"] = {"scene": scene.scene_file_path if is_instance_valid(scene) else "", "paused": get_tree().paused, "world_present": current_world() != null}
        if current_world() != null:
            result["startup_diagnostic"]["depth"] = current_world().get("room_depth")
            result["startup_diagnostic"]["player_present"] = is_instance_valid(current_world().get("player"))
            result["startup_diagnostic"]["tutorial_active"] = current_world().get("current_room_tutorial_active")
    return initialized

func finish() -> void:
    if finished:
        return
    finished = true
    Input.action_release("move_right")
    # Release coroutine locals before retiring the production scene and audio.
    call_deferred("shutdown")

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

func shutdown() -> void:
    get_tree().paused = false
    var scene := get_tree().current_scene
    get_tree().current_scene = null
    if is_instance_valid(scene):
        scene.queue_free()
    scene = null
    await get_tree().process_frame
    await get_tree().process_frame
    await wait_for(audio_has_retired, "Native scene audio retires before shutdown", 5.0)
    # Existing fixtures explicitly retire this application-lifetime Node cache
    # after the final scene. Record the same injected teardown boundary here.
    var mapper: Script = load("res://scripts/power_parameter_mapper.gd")
    result["application_cache_retired_by_driver"] = is_instance_valid(mapper._power_registry_instance)
    if is_instance_valid(mapper._power_registry_instance):
        mapper._power_registry_instance.free()
        mapper._power_registry_instance = null
    mapper = null
    result["checks"] = checks
    result["failures"] = failures
    result["stages"] = stages
    var file := FileAccess.open(OS.get_environment("ABYSSAL_NATIVE_RESULT"), FileAccess.WRITE)
    if file == null:
        printerr("[FAIL] Native smoke result could not be written")
        get_tree().quit(1)
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()
    if failures.is_empty():
        print("[PASS] Native normal Menu-to-run smoke: " + str(checks) + " checks")
    get_tree().quit(0 if failures.is_empty() else 1)
