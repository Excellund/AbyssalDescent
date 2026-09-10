extends "res://scripts/tests/test_descent_presentation.gd"
## Production room, reward and Continue transitions, using disposable saves.

const BOSSES := preload("res://scripts/shared/boss_catalogue.gd")
const REGISTRY := preload("res://scripts/shared/boss_stage_registry.gd")
const ALTERNATIVE := preload("res://scripts/enemy_boss_alternative.gd")
const SESSION := preload("res://scripts/core/run_session.gd")
const FACTS := preload("res://scripts/ui/run_summary/run_result_facts.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Alternative boss selection requires disposable user data")
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-alternative-boss-selection")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "veilstrider"
	RunContext.current_difficulty_tier = 1
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	_test_roster()
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.set_physics_process(false)
	check(world.run_session.act_boss_ids.size() == 3, "Normal startup selects all three boss identities")
	var rolled := world.run_session.act_boss_ids.duplicate()
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	check(world.run_session.act_boss_ids == rolled, "Starting reward and room entry preserve the run's boss roll")
	world.run_session.act_biome_ids = ["shatterfield", "grinding_vault", "void_breach"]
	world.run_session.act_boss_ids = ["kilnheart", "glassweaver", "null_archivist"]
	_test_replica_spawn_reconstruction()
	_test_alternative_transition(1)
	_test_alternative_transition(2)
	world._clear_all_enemies()
	world._begin_boss_stage(3)
	check(world.get_active_boss_id() == "null_archivist", "Final boss telemetry uses the selected identity")
	world._clear_all_enemies()
	world._finish_third_boss_clear()
	var victories: Array = world._latest_run_summary().get("defeated_boss_ids", [])
	check(victories == ["kilnheart", "glassweaver", "null_archivist"], "Full clear records only the three bosses actually defeated")
	var result_line := FACTS.boss_line(world._latest_run_summary())
	check(result_line.contains("Kilnheart") and result_line.contains("Glassweaver") and result_line.contains("The Null Archivist") and not result_line.contains("Warden"), "Results display all alternative names without crediting originals")
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after the scene is released")
	print("[OK] Alternative boss selection: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_roster() -> void:
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 707
	second.seed = 707
	var seen: Dictionary = {}
	for sample in range(48):
		var ids := BOSSES.roll_roster(first)
		check(ids == BOSSES.roll_roster(second), "Identical RNG state reproduces a complete roster")
		for stage in range(1, 4):
			check(BOSSES.stage_for_id(ids[stage - 1]) == stage, "A boss never leaks into another stage")
			seen[ids[stage - 1]] = true
	check(seen.size() == 6, "Repeated seeded runs reach every original and alternative")
	var session := SESSION.new()
	session.act_boss_ids = ["kilnheart", "glassweaver", "null_archivist"]
	session.restore_descent_state({})
	check(session.act_boss_ids == ["warden", "sovereign", "lacuna"], "Legacy Continue keeps the original bosses instead of rerolling")
	session.restore_descent_state({"act_boss_ids": ["glassweaver", "glassweaver", false]})
	check(session.act_boss_ids == ["warden", "glassweaver", "lacuna"], "Malformed or wrong-stage save entries fall back independently")
	for stage in range(1, 4):
		var boss := REGISTRY.create_boss_node(stage, Vector2.ZERO)
		check(String(boss.get_meta("boss_id")) == BOSSES.DEFAULT_IDS[stage - 1] and not boss is ALTERNATIVE, "Existing registry callers still construct their original boss")
		boss.free()

func _test_alternative_transition(stage: int) -> void:
	var boss_id: String = BOSSES.ALTERNATIVE_IDS[stage - 1]
	world._clear_all_enemies()
	world.door_options = [CONTRACTS.boss_door_option(BOSSES.DEFAULT_IDS[stage - 1])]
	world._label_selected_boss_doors()
	var door: Dictionary = world.door_options[0]
	check(CONTRACTS.door_prompt_name(door) == String(BOSSES.NAMES[boss_id]) + " Gate", "Door prompt names the selected boss")
	check(CONTRACTS.door_identity_label(door) == BOSSES.NAMES[boss_id] and CONTRACTS.door_reward_preview_text(door) == "Boss power", "Door identity and reward preview agree")
	world._begin_boss_stage(stage)
	world._sync_renderer()
	check(world.current_room_label == REGISTRY.get_descriptor(stage, boss_id).room_label and world.renderer.boss_entrance_key == boss_id and world.renderer.boss_entrance_active, "Selected boss has its own room label and entrance motif")
	check(world.hud.room_banner_title_label.text == BOSSES.NAMES[boss_id], "Arena survey retains the selected boss's name")
	var boss: ALTERNATIVE
	for enemy in get_nodes_in_group("enemies"):
		if enemy is ALTERNATIVE and not enemy.is_queued_for_deletion():
			boss = enemy
	check(is_instance_valid(boss) and boss.boss_id == boss_id, "Host constructs the selected alternative before ready")
	if is_instance_valid(boss):
		var spawn_payload: Dictionary = world._build_boss_spawn_payload(boss, stage, int(boss.get_meta("network_enemy_id")))
		check(spawn_payload.boss_id == boss_id and spawn_payload.max_health == boss.get_max_health() and spawn_payload.has("runtime_state") and spawn_payload.has("projectile_state"), "Resync payload retains identity, scaled health and attack geometry")
	world._exit_encounter_intro_grace()
	world._clear_all_enemies()
	if stage == 1:
		world._finish_first_boss_clear()
	else:
		world._finish_second_boss_clear()
	check(world.last_defeated_boss_id == boss_id and world.reward_selection_ui.is_active(), "Alternative defeat opens the existing boss reward phase")
	check(world.hud.room_banner_title_label.text == String(BOSSES.NAMES[boss_id]) + " Defeated", "Defeat banner names the alternative")
	check(world.power_registry_instance.get_boss_epitaph(boss_id).length() > 0, "Alternative has a defeat epitaph")
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.BOSS, false)
	world._save_active_run_checkpoint()
	var snapshot: Dictionary = RunContext.load_active_run()
	check(snapshot.get("act_boss_ids") == ["kilnheart", "glassweaver", "null_archivist"], "Actual disk checkpoint stores the full roster")
	world.run_session.act_boss_ids = ["warden", "sovereign", "lacuna"]
	check(world._apply_active_run_snapshot(snapshot), "Continue accepts the alternative-boss checkpoint")
	check(world.run_session.act_boss_ids == ["kilnheart", "glassweaver", "null_archivist"] and world._get_room_presentation_act() == stage, "Continue preserves future selections and the cleared boss chamber")
	world._enter_rest_site()

func _test_replica_spawn_reconstruction() -> void:
	# Use two non-default profiles: assigning boss_id after _ready would retain
	# Kilnheart's speed/damage even if the spawn then overwrote its health.
	for stage in [2, 3]:
		var boss_id: String = BOSSES.ALTERNATIVE_IDS[stage - 1]
		var descriptor := REGISTRY.get_descriptor(stage, boss_id)
		world._clear_all_enemies()
		world.current_room_size = descriptor.room_size
		world.current_room_label = descriptor.room_label
		var host_boss := REGISTRY.create_boss_node(stage, Vector2(241.5, 37.25), boss_id) as ALTERNATIVE
		world.add_child(host_boss)
		host_boss.arena_size = descriptor.room_size
		world._assign_enemy_target_candidates(host_boss)
		host_boss.set_max_health_and_current(3701, 1843)
		host_boss.begin_attack(1 if stage == 2 else 0)
		var committed := host_boss.get_attack_warning_geometry()
		check(not committed.is_empty(), "Host commits geometry before reconstruction: " + boss_id)
		var enemy_id: int = 8800 + stage
		var payload: Dictionary = world._build_boss_spawn_payload(host_boss, stage, enemy_id)
		host_boss.free()
		world._clear_all_enemies()

		world.is_multiplayer = true
		MultiplayerSessionManager.session_connected = true
		MultiplayerSessionManager.is_host_peer = false
		MultiplayerSessionManager.local_peer_id = 2
		MultiplayerSessionManager.connected_peers = {1: {}, 2: {}}
		world._world_multiplayer_sync_state.reset_for_new_run()
		world._world_multiplayer_sync_state.current_room_sync_id = 20 + stage
		world.current_room_label = "Replica foyer"
		world.first_boss_defeated = true
		world.second_boss_defeated = stage == 3
		world.in_boss_room = false
		world.in_second_boss_room = false
		world.in_third_boss_room = false
		world.choosing_next_room = true
		var depth: int = world._get_second_boss_target_depth() if stage == 2 else world._get_third_boss_target_depth()
		world._set_progression_counters(depth - 1, depth, world.second_boss_encounter_count, world.third_boss_encounter_count if stage == 3 else 0)
		world.run_session.act_boss_ids = ["kilnheart", "glassweaver", "null_archivist"]
		var progress: Dictionary = world._build_progress_sync_state()
		progress["room_sync_id"] = world.get_current_room_sync_id() + 1
		progress["in_second_boss_room"] = stage == 2
		progress["in_third_boss_room"] = stage == 3
		progress["choosing_next_room"] = false
		payload["room_sync_id"] = progress.room_sync_id
		world.run_session.act_boss_ids = ["warden", "sovereign", "lacuna"]
		world._sync_chosen_door(CONTRACTS.boss_door_option(BOSSES.DEFAULT_IDS[stage - 1]), progress)
		check(world.current_room_label == descriptor.room_label and world.get_active_boss_id() == boss_id, "Chosen-door handler applies host roster before constructing its room: " + boss_id)
		check(EnemyReplicationService.enemy_nodes_by_id.is_empty(), "Joiner room construction waits for the host boss spawn")
		check(world.enemy_state_sync_receiver.can_apply_boss_spawn_sync(payload), "Matching authoritative spawn passes the room gate")
		var stale := payload.duplicate(true)
		stale["room_sync_id"] = world.get_current_room_sync_id() - 1
		check(not world.enemy_state_sync_receiver.can_apply_boss_spawn_sync(stale), "A stale-room boss fails the receiver gate")
		world._sync_spawn_boss(stale)
		check(EnemyReplicationService.enemy_nodes_by_id.is_empty() and not world._world_multiplayer_sync_state.has_pending_boss_spawn_sync_payload(), "Stale RPC neither spawns nor queues a boss")
		world._sync_spawn_boss(payload)
		var replica := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as ALTERNATIVE
		check(is_instance_valid(replica), "Production spawn RPC reconstructs the selected alternative")
		if is_instance_valid(replica):
			check(replica.boss_id == boss_id and is_equal_approx(replica.move_speed, float(ALTERNATIVE.PROFILES[boss_id].speed)), "Identity is configured before ready, including its profile-specific speed")
			check(not replica.network_simulation_enabled, "Reconstructed boss uses replica-only simulation")
			check(replica.get_max_health() == 3701 and replica.get_current_health() == 1843, "Reconstruction restores scaled maximum and already-damaged current health")
			check(replica.get_attack_warning_geometry() == committed and replica.boss_state == ALTERNATIVE.State.WARNING and is_equal_approx(replica.state_time_left, float(payload.projectile_state.state_time_left)), "Reconstruction retains full committed geometry, phase and warning lifetime")
			check(is_zero_approx(replica.spawn_transport_time_left), "Active reconstruction does not replay transport over the committed warning")
			var original_instance := replica.get_instance_id()
			replica.set_health(1731)
			world._sync_spawn_boss(payload)
			check(EnemyReplicationService.enemy_nodes_by_id.size() == 1 and EnemyReplicationService.enemy_nodes_by_id[enemy_id].get_instance_id() == original_instance and replica.get_current_health() == 1731, "Duplicate spawn keeps one boss and never rewinds its current health")
		world._clear_all_enemies()
		world.is_multiplayer = false
		MultiplayerSessionManager.session_connected = false
		MultiplayerSessionManager.is_host_peer = true
		MultiplayerSessionManager.local_peer_id = 1
		MultiplayerSessionManager.connected_peers = {1: {}}
	world._reset_for_debug_jump()
	world._world_multiplayer_sync_state.reset_for_new_run()
	world._set_progression_counters(0, 0, 0, 0)
