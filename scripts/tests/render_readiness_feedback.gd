extends SceneTree
## Actual Main/HUD/camera. Co-op roster is staged locally for screenshots;
## native two-process ready transport is covered by input_room_transition_enet.
const MAIN := preload("res://scenes/Main.tscn")
const WORLD := preload("res://scripts/world_generator.gd")
const PLAYER := preload("res://scenes/Player.tscn")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")
var world: WORLD
var ally: Node2D
var checks := 0
var failures: Array[String] = []
var frames: Array[Dictionary] = []
var retirement := AUDIO.new()
var folder := ""

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _settle(count: int = 5) -> void:
	for _frame in count:
		await process_frame

func _enter(multiplayer_mode: bool) -> void:
	MultiplayerSessionManager.session_connected = false
	world.is_multiplayer = multiplayer_mode
	ally.visible = multiplayer_mode
	world._clear_all_enemies()
	world._begin_room(CONTRACTS.profile("Crossfire", Vector2(1160, 860), true, 2, 0, 0, 0))
	world.player.position = Vector2(-60, 100)
	ally.position = Vector2(60, 100)
	for actor in world._get_multiplayer_player_nodes():
		actor.set_process(false)
		actor.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_process(false)
		enemy.set_physics_process(false)
	world.enemy_spawner.set_process(false)
	world._update_camera_mode()
	world._refresh_frame_ui()

func _capture(key: String, size: Vector2i, expected_hint: String) -> void:
	await _settle()
	world._refresh_frame_ui()
	await _settle()
	var hint: Label = world.hud._status_hint_label
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(size))
	check(hint.visible == not expected_hint.is_empty(), key + ": survey hint visibility matches phase")
	if not expected_hint.is_empty():
		check(hint.text == expected_hint, key + ": actual Main HUD uses the selected readiness instruction")
		check(world.hud.status_panel.get_global_rect().grow(1.0).encloses(hint.get_global_rect()), key + ": complete hint stays inside the actual HUD panel")
		check(viewport_rect.grow(1.0).encloses(hint.get_global_rect()), key + ": hint stays within viewport")
		var width: float = hint.get_theme_font("font").get_string_size(hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, hint.get_theme_font_size("font_size")).x
		check(width <= hint.size.x + 1.0, key + ": wording fits without clipping")
	if key == "ready":
		check(world.hud.room_banner_persistent_visible and world.hud.room_banner_title_label.text == "Ready" and world.hud.room_banner_subtitle_label.text == "Waiting for allies...", "Persistent banner agrees with the ready HUD")
		check(viewport_rect.grow(1.0).encloses(world.hud.room_banner_subtitle_label.get_global_rect()), "Waiting banner remains inside the viewport")
		check(world.encounter_intro_grace_active and world.player.encounter_input_frozen and world.enemy_spawner.wave_timer_paused, "Ready screenshot preserves frozen survey mechanics")
	if key == "engaged":
		check(not world.encounter_intro_grace_active and not world.player.encounter_input_frozen and not world.hud.room_banner_persistent_visible, "Engage removes local waiting state")
	await RenderingServer.frame_post_draw
	var filename := "%s_%d.png" % [key, size.x]
	var picture := root.get_texture().get_image()
	check(picture.get_size() == size and picture.save_png(folder.path_join(filename)) == OK, "Captured native viewport " + filename)
	var rect: Rect2 = hint.get_global_rect()
	frames.append({"file": filename, "size": [size.x, size.y], "state": key,
		"hint": expected_hint, "hint_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "bastion"
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	var choice: Dictionary = world.reward_selection_ui.boon_choices.front().duplicate(true)
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_selected.emit(choice, ENUMS.RewardMode.ARCANA, true)
	world.set_process(false)
	world.set_physics_process(false)
	world.player.player_id = 1
	world.player.is_local_player = true
	ally = PLAYER.instantiate()
	ally.player_id = 2
	ally.is_local_player = false
	world.add_child(ally)
	PlayerReplicationService.player_nodes.clear()
	PlayerReplicationService.local_peer_id = 1
	PlayerReplicationService.register_player(1, world.player)
	PlayerReplicationService.register_player(2, ally)
	world._disable_player_collision_pair(world.player, ally)
	world._bind_camera_to_local_player()
	folder = project_path.path_join("readiness_feedback_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	for size in [Vector2i(960, 720), Vector2i(1280, 720)]:
		root.size = size
		root.content_scale_size = size
		await _settle()
		_enter(false)
		await _capture("solo", size, "Move or Attack to engage")
		_enter(true)
		await _capture("unready", size, "Move or Attack when ready")
		# A locally staged living ally keeps the normal host ready action waiting.
		# No lobby or remote acknowledgement is fabricated for the screenshot.
		MultiplayerSessionManager.is_host_peer = true
		MultiplayerSessionManager.session_connected = true
		MultiplayerSessionManager.local_peer_id = 1
		Input.action_press("move_right")
		world._update_encounter_intro_grace()
		Input.action_release("move_right")
		await _capture("ready", size, "Ready — waiting for allies")
		MultiplayerSessionManager.session_connected = false
		# Local presentation of the existing all-ready exit; actual transport and
		# both owners' inputs are checked separately by the ENet fixture.
		world._exit_encounter_intro_grace()
		await _capture("engaged", size, "")
	PlayerReplicationService.player_nodes.clear()
	current_scene = null
	world.queue_free()
	await _settle()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await retirement.wait_until_retired(self), "Native audio retires before manifest publication")
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	print("[OK] Readiness feedback frames: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
