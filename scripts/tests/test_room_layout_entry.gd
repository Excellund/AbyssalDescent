extends SceneTree
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
var audio_retirement := AUDIO_RETIREMENT.new()
## Exercise the production room-entry boundary, including clear and serialized layouts.
const MAIN := preload("res://scenes/Main.tscn")
const WORLD := preload("res://scripts/world_generator.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const BREAKWATER := preload("res://scripts/enemy_breakwater.gd")
const OBJECTIVE := preload("res://scripts/objective_manager.gd")
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
var checks := 0
var failures: Array[String] = []
var world: WORLD

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-room-layout-entry")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "veilstrider"
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	for input in [{}, {"obstacle_layout": null}, {"obstacle_layout": "legacy"}, {"obstacle_layout": []}]:
		var empty := CONTRACTS.profile_obstacle_layout(input)
		check(empty.is_typed() and empty.get_typed_builtin() == TYPE_DICTIONARY and empty.is_empty(), "Missing or non-array optional layout resolves to typed empty geometry")
	var first := {"pos": Vector2(10, 20), "radius": 28.0}
	var second := {"pos": Vector2(-50, 60), "radius": 36.0, "type": "boulder"}
	var mixed := [first, null, 7, "legacy", second]
	var valid := CONTRACTS.profile_obstacle_layout({"obstacle_layout": mixed})
	check(valid == [first, second] and mixed.size() == 5, "Optional malformed entries cannot discard or mutate valid obstacle dictionaries")
	for tier in range(4):
		# Each tier starts a fresh run. The prior case's deliberately partial
		# doorway codec record is not a complete resumable run snapshot.
		RunContext.clear_active_run()
		RunContext.current_difficulty_tier = tier
		world = MAIN.instantiate() as WORLD
		world.get_node("DebugSettings").enabled = false
		root.add_child(world)
		current_scene = world
		var ui: Node = world.reward_selection_ui
		var choice: Dictionary = ui.boon_choices.front().duplicate(true)
		ui.close_selection()
		ui.reward_selected.emit(choice, ENUMS.RewardMode.ARCANA, true)
		var apex := world.encounter_profile_builder.build_debug_encounter_profile("apex_breakwater", 8)
		_enter(apex, "Actual builder Breakwater Bearing%d" % tier)
		check(world.active_room_enemy_count == 1 and _living_enemies() == 1, "Breakwater actual spawn equals its declared one enemy on Bearing%d" % tier)
		check(world.renderer.obstacle_layout.is_empty() and world.enemy_spawner.obstacle_circles.is_empty() and world._active_obstacle_nodes.is_empty(), "Breakwater remains obstacle-free on Bearing%d" % tier)
		check(_only_breakwater_alive() and not world.choosing_next_room and not world.reward_selection_ui.is_active(), "A real live Breakwater cannot masquerade as a cleared room before its death")
		# Real binary checkpoint preserves the offered door through RunContext's codec.
		var door := CONTRACTS.standard_encounter_door_option(apex)
		check(RunContext.save_active_run({"door_options": [door]}), "Disposable real checkpoint stores offered Breakwater door")
		var loaded := RunContext.load_active_run()
		_enter(CONTRACTS.door_option_profile(loaded.door_options[0]), "Checkpoint Breakwater Bearing%d" % tier)
		check(world.active_room_enemy_count == 1 and _living_enemies() == 1, "Restored Breakwater still actually spawns once")
		check(_only_breakwater_alive() and not world.choosing_next_room, "Disk-restored room contains the real undefeated Apex")
		var ordinary := CONTRACTS.profile("Skirmish", Vector2(1160, 860), true, 2, 0, 0, 0)
		_enter(ordinary, "Legacy missing obstacle layout")
		check(world.active_room_enemy_count == 2 and _living_enemies() == 2, "Absent optional layout still spawns the declared ordinary enemies")
		ordinary["obstacle_layout"] = [{"pos": Vector2(-190, -70), "radius": 28.0}, {"pos": Vector2(200, 100), "radius": 36.0, "type": "boulder"}]
		_enter(bytes_to_var(var_to_bytes(ordinary)) as Dictionary, "Serialized untyped nonempty layout")
		check(world.renderer.obstacle_layout == ordinary.obstacle_layout and world.enemy_spawner.obstacle_circles == ordinary.obstacle_layout, "Serialized valid geometry reaches renderer and spawner exactly")
		check(world._active_obstacle_nodes.size() == 2 and world._active_obstacle_nodes[0].global_position == Vector2(-190, -70) and world._active_obstacle_nodes[1].global_position == Vector2(200, 100), "Actual column bodies retain both world positions")
		check(_living_enemies() == 2, "Serialized ordinary profile spawns its actual two enemies")
		if tier == 1:
			await _test_objective_survey_hints()
			await _test_intercept_living_escorts()
		current_scene = null
		world.queue_free()
		world = null
		await process_frame
		await process_frame
	RunContext.clear_active_run()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	var pending_audio := audio_retirement.pending_count()
	check(await audio_retirement.wait_until_retired(self), "AudioServer releases native playback from every deleted room owner")
	print("[AudioRetirement] pending before barrier=%d, after=%d" % [pending_audio, audio_retirement.pending_count()])
	print("[RoomLayoutEntry] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _enter(profile: Dictionary, label: String) -> void:
	world._clear_all_enemies()
	world.active_room_enemy_count = -1
	world.encounter_intro_grace_active = false
	world._begin_room(profile)
	check(world.encounter_intro_grace_active, label + " reaches the end of actual World._begin_room")

func _test_objective_survey_hints() -> void:
	# Drive actual World frames explicitly; keep actors fixed for deterministic
	# proximity states while ordinary HUD/banner time continues to pass.
	world.set_process(false)
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	for action in ["attack", "dash", "move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
	var hints := {
		"hold_the_line": "Hold the zone uncontested",
		"intercept_run": "Stay near the drone; clear its path",
		"circuit_sweep": "Reach the active node to begin"
	}
	for kind: String in hints:
		_enter(world.encounter_profile_builder.build_objective_profile(5, kind), kind + " survey")
		world.enemy_spawner.set_process(false)
		var enemies: Array[Node2D] = []
		for enemy in get_nodes_in_group("enemies"):
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
				enemy.set_process(false)
				enemy.set_physics_process(false)
				enemy.global_position = world.current_room_size * 0.5 - Vector2(40, 40)
				enemies.append(enemy)
		world._refresh_frame_ui()
		var manager := world.objective_manager
		var frozen_state := manager.serialize_sync_state()
		check(world.hud._status_obj_line2.is_visible_in_tree() and world.hud._status_obj_line2.text == hints[kind], "Actual Main survey shows its existing objective card instruction: " + kind)
		_check_replica_objective_hint(frozen_state, String(hints[kind]), kind)
		for _step in range(4):
			world._process(0.8)
			await create_timer(0.8).timeout
		world._refresh_frame_ui()
		check(world.encounter_intro_grace_active and manager.serialize_sync_state() == frozen_state, "More than three seconds of survey never advances objective timers, progress or spawning: " + kind)
		check(world.hud._status_obj_line2.is_visible_in_tree() and world.hud._status_obj_line2.text == hints[kind] and is_zero_approx(world.hud.room_banner_title_label.modulate.a), "Objective instruction remains visible after the ordinary entry banner fades: " + kind)
		world._exit_encounter_intro_grace()
		match kind:
			"hold_the_line":
				world.player.global_position = manager.control_anchor
				world._process(0.25)
				check(manager.control_progress > 0.0 and world.hud._status_obj_line2.text == "Zone stable — keep pressure inside", "Engage restores actual uncontested Hold progress and live guidance")
				world.player.global_position = manager.control_anchor + Vector2(manager.control_radius + 45.0, 0)
				world._process(0.25)
				check(not manager.control_player_inside and world.hud._status_obj_line2.text == "Re-enter the zone before decay", "Leaving the live Hold zone restores the existing return instruction")
				world.player.global_position = manager.control_anchor
				for enemy in enemies:
					enemy.global_position = manager.control_anchor
				world._process(0.25)
				check(manager.control_contested and world.hud._status_obj_line2.text.begins_with("Contested — clear "), "Actual enemies restore the contested Hold guidance after survey")
			"intercept_run":
				world.player.global_position = Vector2.ZERO
				world._process(0.1)
				check(manager.intercept_drone_stalled and world.hud._status_obj_line2.text == "Stay close to the drone", "Engage shows the actual outside-escort Intercept state")
				world.player.global_position = manager.intercept_drone_position + Vector2(45, 0)
				world._process(0.1)
				check(manager.intercept_drone_progress > 0.0 and world.hud._status_obj_line2.text == "Path clear — drone advancing", "The drone is described as advancing only when the actual live objective advances")
				var progress_before := manager.intercept_drone_progress
				enemies[0].global_position = manager.intercept_drone_position
				world._process(0.1)
				check(manager.intercept_drone_progress == progress_before and world.hud._status_obj_line2.text.contains("enemies blocking — clear the path"), "An actual nearby enemy restores blocking guidance and stops the live drone")
			"circuit_sweep":
				world.player.global_position = manager.sweep_node_position
				world._process(0.1)
				check(manager.sweep_capture_progress > 0.0 and world.hud._status_obj_line2.text == "Stay in the ring to capture", "Circuit keeps its existing capture guidance after Engage")
		_enter(CONTRACTS.profile("Skirmish", Vector2(1160, 860), true, 2, 0, 0, 0), "Ordinary room after " + kind)
		world._refresh_frame_ui()
		check(world.objective_manager.active_objective_kind.is_empty() and not world.hud._status_obj_line2.visible, "The next nonobjective room cannot retain the survey instruction: " + kind)

func _test_intercept_living_escorts() -> void:
	# Stage two actual avatars without opening a network session. Death follows
	# the real health signal and World lifecycle; objective fields retain the
	# existing authoritative frame and serialization paths.
	var previous_registry := PlayerReplicationService.player_nodes.duplicate()
	var previous_peer_id := PlayerReplicationService.local_peer_id
	var previous_player_id := world.player.player_id
	var remote = PLAYER_SCENE.instantiate()
	remote.player_id = 2
	remote.is_local_player = false
	world.add_child(remote)
	remote.died.connect(world._on_player_died)
	world.player.player_id = 1
	PlayerReplicationService.local_peer_id = 1
	PlayerReplicationService.player_nodes.clear()
	PlayerReplicationService.register_player(1, world.player)
	PlayerReplicationService.register_player(2, remote)
	for fallen_host in [true, false]:
		var label := "fallen host" if fallen_host else "fallen remote"
		world.player.revive_with_health(world.player.health_state.max_health)
		remote.revive_with_health(remote.health_state.max_health)
		# Enter locally before staging the party, so this disconnected fixture
		# creates native enemies without waiting for multiplayer room readiness.
		world.is_multiplayer = false
		_enter(world.encounter_profile_builder.build_objective_profile(5, "intercept_run"), "Co-op Intercept: " + label)
		world._exit_encounter_intro_grace()
		world.is_multiplayer = true
		world.player.set_physics_process(false)
		remote.set_physics_process(false)
		world.enemy_spawner.set_process(false)
		var enemies: Array[Node2D] = []
		for enemy in get_nodes_in_group("enemies"):
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
				enemy.set_process(false)
				enemy.set_physics_process(false)
				enemy.global_position = world.current_room_size * 0.5 - Vector2(40, 40)
				enemies.append(enemy)
		# Room replacement retires old enemy nodes at the end of the frame.
		await process_frame
		await process_frame
		var manager := world.objective_manager
		var fallen = world.player if fallen_host else remote
		var living = remote if fallen_host else world.player
		fallen.global_position = manager.intercept_drone_position
		living.global_position = Vector2(200, 0)
		fallen.set_health(0)
		check(fallen.is_dead() and not fallen.visible and world._count_alive_players() == 1 and not world._run_outcome_coordinator.is_player_defeated(), "Actual co-op death hides only the fallen avatar and keeps the encounter active: " + label)
		var progress_before := manager.intercept_drone_progress
		world._process(0.1)
		check(living.global_position.distance_to(manager.intercept_drone_position) > manager.intercept_escort_radius and not manager.intercept_player_in_escort_zone and manager.intercept_drone_stalled and manager.intercept_drone_progress == progress_before, "An invisible fallen avatar cannot escort while the living teammate is outside: " + label)
		check(world.hud._status_obj_line2.text == "Stay close to the drone", "Live Intercept guidance requests a living escort: " + label)
		_check_replica_objective_hint(manager.serialize_sync_state(), "Stay close to the drone", "live Intercept with " + label)
		living.global_position = manager.intercept_drone_position + Vector2(45, 0)
		world._process(0.1)
		check(manager.intercept_player_in_escort_zone and not manager.intercept_drone_stalled and manager.intercept_drone_progress > progress_before and world.hud._status_obj_line2.text == "Path clear — drone advancing", "Either living teammate resumes the drone while the other remains fallen: " + label)
		progress_before = manager.intercept_drone_progress
		enemies[0].global_position = manager.intercept_drone_position
		world._process(0.1)
		check(manager.intercept_player_in_escort_zone and manager.intercept_drone_stalled and manager.intercept_drone_progress == progress_before and world.hud._status_obj_line2.text.contains("enemies blocking — clear the path"), "A live enemy still blocks the drone with a living escort present: " + label)
	world.player.revive_with_health(world.player.health_state.max_health)
	world.player.set_physics_process(false)
	world.is_multiplayer = false
	world.player.player_id = previous_player_id
	PlayerReplicationService.unregister_player(1)
	PlayerReplicationService.unregister_player(2)
	PlayerReplicationService.player_nodes = previous_registry
	PlayerReplicationService.local_peer_id = previous_peer_id
	remote.queue_free()
	await process_frame

func _check_replica_objective_hint(sync_state: Dictionary, expected: String, kind: String) -> void:
	# Stage only the existing native objective codec and HUD path. Transport is
	# covered by the ENet room-entry fixture; this adds no test or production RPC.
	var authoritative := world.objective_manager
	var replica := OBJECTIVE.new()
	replica.apply_sync_state(bytes_to_var(var_to_bytes(sync_state)))
	world.objective_manager = replica
	world._refresh_frame_ui()
	check(world.hud._status_obj_line2.is_visible_in_tree() and world.hud._status_obj_line2.text == expected, "Serialized replica objective state uses the same objective card instruction: " + kind)
	world.objective_manager = authoritative
	replica.free()
	world._refresh_frame_ui()

func _living_enemies() -> int:
	var count := 0
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
			count += 1
	return count

func _only_breakwater_alive() -> bool:
	if _living_enemies() != 1:
		return false
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
			return enemy.get_script() == BREAKWATER
	return false
