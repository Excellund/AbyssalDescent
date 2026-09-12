extends "res://scripts/tests/test_boss_atmosphere.gd"
## Native Main Apex route, biome/HUD, terrain bait, and a no-Dash walking answer.
const BREAKWATER := preload("res://scripts/enemy_breakwater.gd")
var output_directory := ""
var frames: Array[Dictionary] = []

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-breakwater-tide")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "bastion"
	RunContext.current_difficulty_tier = 1
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	output_directory = ProjectSettings.globalize_path("res://breakwater_main_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.set_physics_process(false)
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	world._clear_all_enemies()
	var encounter := world.encounter_profile_builder.build_debug_encounter_profile("apex_breakwater", 5)
	world._choose_door(CONTRACTS.apex_trial_door_option(encounter, "Apex Breakwater", Color(1.0, 0.66, 0.38)))
	world.player.set_physics_process(false)
	world.enemy_spawner.set_process(false)
	world.enemy_spawner.set_physics_process(false)
	var boss: BREAKWATER
	for enemy: Node in get_nodes_in_group("enemies"):
		if not enemy.is_queued_for_deletion() and enemy.get_script().resource_path == "res://scripts/enemy_breakwater.gd":
			boss = enemy
			enemy.set_physics_process(false)
	check(is_instance_valid(boss), "Native Apex door spawns the production Breakwater")
	if not is_instance_valid(boss):
		await _dispose_world()
		quit(1)
		return
	world._signal_local_player_ready()
	boss._update_spawn_transport(float(boss.spawn_transport_time_left) + 0.01)
	world._apply_camera_bounds_for_room(world.current_effective_room_size)
	world._update_camera_mode()
	world.player_camera.set_physics_process(false)
	world.player_camera.global_position = Vector2.ZERO
	world.player_camera.zoom = world.player_camera.target_zoom
	world.player_camera.force_update_scroll()
	boss.target = world.player
	boss.target_candidates = [world.player]
	var bounds := EnemyReplicationService.get_current_room_bounds()
	boss.global_position = Vector2(-180.0, 0.0)
	world.player.global_position = Vector2(bounds.end.x - 50.0, 0.0)
	boss._begin_tracking()
	boss._process_behavior(BREAKWATER.TRACK_TIME)
	world.player.global_position = Vector2(bounds.end.x - 90.0, 100.0)
	boss._process_behavior(BREAKWATER.LOCK_TIME)
	boss._process_behavior(2.0)
	check(boss.wall_recovery and not boss._backwash_pending and is_equal_approx(boss.phase_left, BREAKWATER.WALL_RECOVERY), "The actual open Apex boundary breaks the tide and awards full terrain recovery")
	await _capture_tide("main_wall_break", boss)
	boss._cancel_attack()
	boss.global_position = Vector2(-220.0, 0.0)
	world.player.global_position = Vector2(-20.0, 0.0)
	boss._begin_tracking()
	boss._process_behavior(BREAKWATER.TRACK_TIME)
	world.player.global_position = Vector2(-20.0, 90.0)
	boss._process_behavior(BREAKWATER.LOCK_TIME)
	boss._process_behavior(1.0)
	check(not boss.wall_recovery, "A center bait allows the brace instead of falsely awarding wall contact")
	boss._process_behavior(BREAKWATER.MISS_RECOVERY)
	await _capture_tide("main_brace", boss)
	world.player.max_speed = 188.0 * 0.45
	world.player.attack_lock_time_left = 0.12
	world.player.dash_cooldown_left = 10.0
	var health_before: int = world.player.get_current_health()
	Input.action_press("move_up")
	for index in range(72):
		world.player._physics_process(1.0 / 60.0)
		boss._process_behavior(1.0 / 60.0)
	Input.action_release("move_up")
	check(absf(world.player.global_position.y) < BREAKWATER.TIDE_WAKE_HALF_WIDTH and world.player.dash_cooldown_left > 0.0, "A Slowed-speed native player walks into the vacated lane with Dash unavailable")
	world.player.velocity = Vector2.ZERO
	boss._process_behavior(BREAKWATER.BACKWASH_TIME)
	boss._process_behavior(0.4)
	await _capture_tide("main_return_tide", boss)
	boss._process_behavior(10.0)
	check(world.player.get_current_health() == health_before and boss.phase == BREAKWATER.Phase.RECOVER and is_equal_approx(boss.phase_left, BREAKWATER.TIDE_RECOVERY), "The no-Dash walking route survives the actual wave and receives its full punish window")
	await _capture_tide("main_spent_tide", boss)
	await _capture_harbor_gate(boss, bounds)
	await _dispose_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Native Main audio retires after the Apex encounter")
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	print("[BreakwaterMain] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture_harbor_gate(boss: BREAKWATER, bounds: Rect2) -> void:
	# Retain the real Apex and advance its completed ram/tide into the next move.
	# The setup chooses an open shoreline; neither gap geometry nor damage is staged.
	world.player.global_position = Vector2(bounds.end.x - 180.0, 80.0)
	world.player.velocity = Vector2.ZERO
	world.player.max_speed = 188.0
	world.player.external_slow_left = 100.0
	world.player.external_slow_mult = 0.45
	world.player.dash_cooldown_left = 100.0
	boss.global_position = world.player.global_position + Vector2(70.0, 0.0)
	await physics_frame
	await process_frame
	boss._process_behavior(boss.phase_left)
	boss._process_behavior(boss.phase_left)
	check(boss.phase == BREAKWATER.Phase.GATE_BRACE and boss._gate_direction == Vector2.LEFT, "The real completed ram/tide alternates into Harbor Gate from the nearest shore")
	var committed_gaps := boss._gate_gaps.duplicate()
	var committed_origin := boss._gate_origin
	var committed_warning := boss.get_warning_polygons()
	var player_start := world.player.global_position
	var boss_start := boss.global_position
	var health_before: int = world.player.get_current_health()
	Input.action_press("move_up")
	for index in range(21):
		world.player._physics_process(1.0 / 60.0)
		boss._process_behavior(1.0 / 60.0)
	Input.action_release("move_up")
	check(world.player.global_position.distance_to(player_start) > 8.0 and world.player.dash_cooldown_left > 90.0 and not world.player._is_dash_active(), "A genuinely Slowed native player walks during the warning with Dash unavailable")
	check(boss._gate_gaps == committed_gaps and boss._gate_origin == committed_origin and boss.get_warning_polygons() == committed_warning, "The opening and shoreline remain fixed when the player moves after the tell")
	check(boss.global_position.distance_to(boss_start) > 30.0 and world.player.get_current_health() == health_before, "Breakwater visibly braces sideways without damaging the player")
	await _capture_tide("main_harbor_brace", boss)
	while boss.phase == BREAKWATER.Phase.GATE_BRACE:
		world.player._physics_process(1.0 / 60.0)
		boss._process_behavior(1.0 / 60.0)
	check(boss.phase == BREAKWATER.Phase.GATE and world.player.get_current_health() == health_before, "Releasing Harbor Gate does not damage the whole warned floor")
	var player_distance := (world.player.global_position - boss._gate_origin).dot(boss._gate_direction)
	while boss.phase == BREAKWATER.Phase.GATE and boss._gate_progress < player_distance:
		world.player._physics_process(1.0 / 60.0)
		boss._process_behavior(1.0 / 60.0)
	check(boss.phase == BREAKWATER.Phase.GATE and not boss.gate_contains_point(world.player.global_position, boss._gate_progress, boss._gate_progress), "The real moving crest crosses the player's unchanged calm opening")
	check(world.player.get_current_health() == health_before and world.player._dash_damage_immune_left == 0.0, "Holding the opening survives the crossing without Dash immunity")
	await _capture_tide("main_harbor_crossing", boss)
	while boss.phase == BREAKWATER.Phase.GATE:
		world.player._physics_process(1.0 / 60.0)
		boss._process_behavior(1.0 / 60.0)
	check(boss.phase == BREAKWATER.Phase.RECOVER and is_equal_approx(boss.phase_left, BREAKWATER.GATE_RECOVERY) and boss.get_warning_polygons().is_empty(), "The spent full-arena crest clears its warning and grants the complete recovery window")
	check(world.player.get_current_health() == health_before, "The actual Main slow-walking response survives the entire Harbor Gate")
	await _capture_tide("main_harbor_spent", boss)

func _capture_tide(frame_name: String, boss: BREAKWATER) -> void:
	world._sync_renderer()
	world.hud.refresh(world._get_hud_state(), world.player)
	boss.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(frame_name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Captured native Main tide: " + frame_name)
	frames.append({"name": frame_name, "path": path, "phase": boss.phase, "callout": boss.get_attack_callout(), "player_position": world.player.global_position, "player_health": world.player.get_current_health(), "dash_left": world.player.dash_cooldown_left, "camera_zoom": world.player_camera.zoom, "gate_origin": boss._gate_origin, "gate_direction": boss._gate_direction, "gate_gaps": boss._gate_gaps.duplicate(), "gate_progress": boss._gate_progress})
