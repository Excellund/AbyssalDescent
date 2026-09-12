extends "res://scripts/tests/test_boss_atmosphere.gd"
## Real Apex door, native player movement, two settled seams and staggered echoes.
const MIRRORLINE := preload("res://scripts/enemy_mirrorline.gd")
const STEP := 1.0 / 60.0
var output_directory := ""
var frames: Array[Dictionary] = []
var encounter_stats: Dictionary = {}
var horizontal_action := "move_right"

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-mirrorline-stage2")
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
	output_directory = ProjectSettings.globalize_path("res://mirrorline_stage2_frames")
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
	var encounter := world.encounter_profile_builder.build_debug_encounter_profile("apex_mirrorline", 5)
	world._choose_door(CONTRACTS.apex_trial_door_option(encounter, "Apex Mirrorline", Color(0.78, 0.92, 1.0)))
	world.player.set_physics_process(false)
	world.enemy_spawner.set_process(false)
	world.enemy_spawner.set_physics_process(false)
	var boss: MIRRORLINE
	for enemy: Node in get_nodes_in_group("enemies"):
		if not enemy.is_queued_for_deletion() and enemy.get_script().resource_path == "res://scripts/enemy_mirrorline.gd":
			boss = enemy
			enemy.set_physics_process(false)
	check(is_instance_valid(boss), "Actual Apex door spawns production Mirrorline")
	if not is_instance_valid(boss):
		await _dispose_world()
		quit(1)
		return
	world._signal_local_player_ready()
	boss._update_spawn_transport(float(boss.spawn_transport_time_left) + 0.01)
	world._apply_camera_bounds_for_room(world.current_effective_room_size)
	world._update_camera_mode()
	world.player_camera.set_physics_process(false)
	world.player_camera.global_position = boss.arena_center_world
	world.player_camera.zoom = world.player_camera.target_zoom
	world.player_camera.force_update_scroll()
	boss.target = world.player
	boss.target_candidates = [world.player]
	# Native positions give a horizontal target normal, keeping the two seam
	# distances readable. No boss timings, damage, speed or health are overridden.
	var center := boss.arena_center_world
	var bounds := EnemyReplicationService.get_current_room_bounds()
	var toward_open_floor := bounds.get_center() - center
	var horizontal_sign := -1.0 if toward_open_floor.x < 0.0 else 1.0
	var vertical_sign := -1.0 if toward_open_floor.y < 0.0 else 1.0
	horizontal_action = "move_left" if horizontal_sign < 0.0 else "move_right"
	var vertical_action := "move_up" if vertical_sign < 0.0 else "move_down"
	boss.global_position = center + Vector2(220.0 * horizontal_sign, -42.0 * vertical_sign)
	world.player.global_position = center + Vector2(42.0 * horizontal_sign, 42.0 * vertical_sign)
	boss._enter_telegraph()
	check(is_equal_approx(boss._telegraph_total, boss.telegraph_duration) and boss._active_axes().size() == 1, "Stage one retains its production single seam and warning duration")
	boss._process_behavior(0.4)
	await _capture_mirror("stage1_warning", boss)
	boss.take_damage(int(ceil(float(boss.health_state.max_health) * 0.5)))
	check(boss._twin_pending and not boss._twin_active and boss._active_axes().size() == 1, "Native half-health damage queues the twin without inserting it into the current warning")
	boss._enter_telegraph()
	check(boss._twin_active and boss._active_axes().size() == 2 and is_equal_approx(boss._telegraph_total, boss.telegraph_duration + 0.30), "Next native warning introduces both seams with the added settled time")
	encounter_stats = {"base_warning": boss.telegraph_duration, "twin_warning": boss._telegraph_total, "rotation_time": boss.telegraph_duration * (1.0 - boss.telegraph_settle_fraction), "echo_speed": boss.echo_speed_cap, "echo_damage": boss.echo_damage, "max_health": boss.health_state.max_health, "player_speed": world.player.max_speed, "room_bounds": EnemyReplicationService.get_current_room_bounds()}
	var health_before: int = world.player.get_current_health()
	var walking_start := world.player.global_position
	world.player.velocity = Vector2.ZERO
	world.player.attack_lock_time_left = 0.12
	world.player.dash_cooldown_left = 10.0
	_walk(boss, 24, vertical_action)
	await _capture_mirror("stage2_rotating", boss)
	_walk(boss, 24, vertical_action)
	check(boss._state == MIRRORLINE.STATE_TELEGRAPH and boss._axis_normal.is_equal_approx(boss._axis_target_normal) and boss._axis_origin.is_equal_approx(boss._axis_target_origin), "Both seams settle at the unchanged rotation deadline while the warning continues")
	var committed_normal := boss._axis_normal
	var committed_origin := boss._axis_origin
	await _capture_mirror("stage2_settled", boss)
	_walk(boss, 42, vertical_action)
	check(boss._state == MIRRORLINE.STATE_TELEGRAPH and boss._active_echoes.is_empty() and boss._axis_normal.is_equal_approx(committed_normal) and boss._axis_origin.is_equal_approx(committed_origin), "Added warning remains harmless and fixed while the native player repositions")
	await _capture_mirror("stage2_last_warning", boss)
	var warning_snapshot := boss.get_network_runtime_state().duplicate(true)
	var warning_player_position := world.player.global_position
	for index in range(30):
		if boss._state != MIRRORLINE.STATE_TELEGRAPH:
			break
		_walk(boss, 1, vertical_action)
	check(boss._state == MIRRORLINE.STATE_REFLECT and boss._next_echo_id == 1 and boss._active_echoes.size() == 1, "Reflect begins with exactly one primary-axis echo")
	check(world.player.global_position.distance_to(walking_start) > 200.0 and world.player.dash_cooldown_left > 0.0 and world.player.get_current_health() == health_before, "Real player input walks away from the intersection through the full warning with Dash unavailable")
	if not boss._active_echoes.is_empty():
		var first_velocity: Vector2 = boss._active_echoes[0]["velocity"]
		check(absf(first_velocity.normalized().dot(boss._axis_normal)) > 0.999, "First native echo follows the first seam's normal")
	await _capture_mirror("stage2_first_echo", boss)
	var reflect_snapshot := boss.get_network_runtime_state().duplicate(true)
	var reflect_player_position := world.player.global_position
	for index in range(30):
		if boss._next_echo_id >= 2:
			break
		_walk(boss, 1, vertical_action)
	check(boss._next_echo_id == 2 and boss._active_echoes.size() == 2, "Second native echo is delayed by the alternating beat")
	if boss._active_echoes.size() == 2:
		var twin_velocity: Vector2 = boss._active_echoes[1]["velocity"]
		check(absf(twin_velocity.normalized().dot(boss._twin_axis_normal())) > 0.999, "Delayed echo follows the perpendicular twin seam")
	await _capture_mirror("stage2_twin_echo", boss)
	# Spawn-anchored seams can reflect a player outside the floor. Capture the
	# subsequent flight as well, once that native twin has crossed into the room.
	_walk(boss, 24, vertical_action)
	await _capture_mirror("stage2_crossing_echoes", boss)
	for index in range(120):
		if boss._state != MIRRORLINE.STATE_REFLECT:
			break
		_walk(boss, 1, vertical_action)
	check(boss._state == MIRRORLINE.STATE_COOLDOWN and boss._next_echo_id == 8 and is_equal_approx(boss._state_time_left, boss.cooldown_duration + 0.25), "Four echoes per seam finish before the extended native recovery")
	check(world.player.get_current_health() == health_before and world.player.dash_cooldown_left > 0.0, "A deliberate walking route survives the actual staggered barrage with Dash unavailable")
	check(boss.get_attack_callout().is_empty(), "Recovery retires the active attack callout")
	await _capture_mirror("stage2_recovery", boss)
	await _capture_replica_expiry(boss, warning_snapshot, reflect_snapshot, warning_player_position, reflect_player_position)
	await _dispose_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Main encounter audio retires on disposal")
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "encounter": encounter_stats, "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	print("[OK] Mirrorline Main: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _walk(boss: MIRRORLINE, count: int, vertical_action: String) -> void:
	Input.action_press(horizontal_action)
	Input.action_press(vertical_action)
	for index in range(count):
		world.player._physics_process(STEP)
		boss._process_behavior(STEP)
	Input.action_release(horizontal_action)
	Input.action_release(vertical_action)

func _capture_replica_expiry(host: MIRRORLINE, warning: Dictionary, reflect: Dictionary, warning_position: Vector2, reflect_position: Vector2) -> void:
	host.hide()
	var remote := MIRRORLINE.new()
	remote.set_network_simulation_enabled(false)
	remote.telegraph_duration = host.telegraph_duration
	remote.reflect_duration = host.reflect_duration
	remote.cooldown_duration = host.cooldown_duration
	remote.echo_lifetime = host.echo_lifetime
	world.add_child(remote)
	remote.set_physics_process(false)
	remote.global_position = host.global_position
	remote.target = world.player
	remote.target_candidates = [world.player]
	remote.set_max_health_and_current(host.get_max_health(), host.get_current_health())
	world.player.global_position = warning_position
	remote.apply_network_runtime_state(warning)
	check(not remote.network_simulation_enabled and remote._visible_attack_state() == MIRRORLINE.STATE_TELEGRAPH and not remote.get_attack_callout().is_empty(), "Replica first renders the actual compact warning snapshot")
	await _capture_mirror("replica_warning_live", remote)
	var received_sequence := remote._mirror_received_sequence
	var created_echoes := remote._next_echo_id
	remote._process_network_visuals(remote._state_time_left + 0.05)
	check(remote._visible_attack_state() == MIRRORLINE.STATE_COOLDOWN and remote.get_attack_callout().is_empty(), "Without new packets the expired replica warning draws dormant seams without ghosts or callout")
	check(not remote.network_simulation_enabled and remote._state == MIRRORLINE.STATE_TELEGRAPH and remote._state_time_left == 0.0 and remote._mirror_received_sequence == received_sequence and remote._next_echo_id == created_echoes and remote._active_echoes.is_empty(), "Warning expiry does not authorize a new phase or fire an echo")
	await _capture_mirror("replica_warning_expired", remote)
	world.player.global_position = reflect_position
	remote.apply_network_runtime_state(reflect)
	remote._process_network_visuals(0.35)
	check(remote._visible_attack_state() == MIRRORLINE.STATE_REFLECT and not remote.get_attack_callout().is_empty() and remote._active_echoes.size() == 1, "Replica first renders the live reflect snapshot and its one authorized echo")
	await _capture_mirror("replica_reflect_live", remote)
	received_sequence = remote._mirror_received_sequence
	var health_before: int = world.player.get_current_health()
	remote._process_network_visuals(remote._state_time_left + 0.05)
	check(remote._visible_attack_state() == MIRRORLINE.STATE_COOLDOWN and remote.get_attack_callout().is_empty(), "Without new packets the expired replica reflect no longer paints a lethal seam")
	check(not remote.network_simulation_enabled and remote._state == MIRRORLINE.STATE_REFLECT and remote._state_time_left == 0.0 and remote._mirror_received_sequence == received_sequence and remote._next_echo_id == created_echoes and remote._active_echoes.size() <= 1 and world.player.get_current_health() == health_before, "Reflect expiry keeps remote authority and never creates extra echoes or damage")
	await _capture_mirror("replica_reflect_expired", remote)
	remote._process_network_visuals(remote.echo_lifetime)
	check(remote._active_echoes.is_empty(), "The remaining authorized replica echo expires on its own lifetime")

func _capture_mirror(frame_name: String, boss: MIRRORLINE) -> void:
	world._sync_renderer()
	world.hud.refresh(world._get_hud_state(), world.player)
	boss.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(frame_name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Captured native Mirrorline: " + frame_name)
	frames.append({"name": frame_name, "path": path, "state": boss._state, "visible_state": boss._visible_attack_state(), "authority": boss.network_simulation_enabled, "time_left": boss._state_time_left, "callout": boss.get_attack_callout(), "echoes": boss._active_echoes.size(), "player_position": world.player.global_position, "player_health": world.player.get_current_health(), "dash_cooldown": world.player.dash_cooldown_left})
