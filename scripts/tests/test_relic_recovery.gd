extends "res://scripts/tests/test_descent_presentation.gd"
## Rules, ordinary offered doors, real Main lifecycle and isolated Continue.
const RECOVERY := preload("res://scripts/core/relic_recovery_state.gd")
const SESSION := preload("res://scripts/core/run_session.gd")
const HISTORY := preload("res://scripts/core/run_history_store.gd")
const POSITIONS: Array[Vector2] = [Vector2(-280, -170), Vector2(280, -170), Vector2(0, 260)]

func _run() -> void:
	if not _is_isolated():
		quit(1)
		return
	_test_carrying_rules()
	_test_snapshot_boundaries()
	_setup_recovery_world()
	_test_profiles()
	await _test_actual_room()
	await _cleanup_recovery_world()
	print("[OK] Relic Recovery: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _is_isolated() -> bool:
	return OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) and DirAccess.dir_exists_absolute("res://validation_fixtures")

func _setup_recovery_world() -> void:
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-relic-recovery")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "bastion"
	RunContext.current_difficulty_tier = 1
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	world = MAIN.instantiate() as WORLD
	world.name = "World"
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	world.run_session.act_biome_ids = ["shatterfield", "grinding_vault", "void_breach"]
	world.room_depth = 3
	world.rooms_cleared = 2

func _cleanup_recovery_world() -> void:
	paused = false
	if is_instance_valid(world):
		world.player.discard_pending_combat_input()
		current_scene = null
		world.queue_free()
		world = null
	await process_frame
	await process_frame
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	HISTORY.clear_all()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Relic fixture retires native audio in its isolated profile")

func _roster(id: int, at: Vector2, living: bool = true) -> Dictionary:
	return {"id": id, "position": at, "living": living}

func _test_carrying_rules() -> void:
	var recovery := RECOVERY.new()
	recovery.begin(POSITIONS)
	for _frame in 30:
		recovery.advance([_roster(1, Vector2.ZERO)])
	check(recovery.delivered_count() == 0, "Waiting at the receiver cannot recover remote relics")
	var outside := recovery.advance([_roster(1, POSITIONS[0] + Vector2(RECOVERY.PICKUP_RADIUS + 0.1, 0))])
	check(int(outside.first_pickups) == 0, "Pickup circle has an exact, bounded edge")
	var pickup := recovery.advance([_roster(8, POSITIONS[0]), _roster(2, POSITIONS[0])])
	check(int(pickup.first_pickups) == 1 and recovery.carrier_has_relic(2) and not recovery.carrier_has_relic(8), "Simultaneous pickup chooses one stable carrier by distance then ID")
	var full := recovery.advance([_roster(2, POSITIONS[1])])
	check(int(full.first_pickups) == 0 and int(recovery.relics[1].carrier_id) == 0, "A carrier cannot pick up a second relic")
	var dead := recovery.advance([_roster(2, Vector2(110, 50), false)])
	check(int(dead.drops) == 1 and int(recovery.relics[0].carrier_id) == 0 and recovery.relics[0].position == Vector2(110, 50), "Defeat drops cargo at the carrier's final reachable position")
	var reclaimed := recovery.advance([_roster(8, Vector2(110, 50)), _roster(2, Vector2(110, 50), false)])
	check(int(reclaimed.first_pickups) == 0 and recovery.carrier_has_relic(8), "Living teammate recovers dropped cargo without another reinforcement wave")
	recovery.advance([_roster(8, Vector2(175, 15))])
	var disconnected := recovery.advance([])
	check(int(disconnected.drops) == 1 and recovery.relics[0].position == Vector2(175, 15), "Disconnect drops cargo at the last observed position")
	recovery.advance([_roster(1, Vector2(175, 15))])
	var deposit := recovery.advance([_roster(1, Vector2(RECOVERY.RECEIVER_RADIUS, 0))])
	check(int(deposit.deposits) == 1 and recovery.delivered_count() == 1 and not recovery.carrier_has_relic(1), "Entering the receiver delivers cargo once and frees the carrying slot")
	for index in [1, 2]:
		var result := recovery.advance([_roster(1, POSITIONS[index])])
		check(int(result.first_pickups) == 1, "Each unopened relic awakens exactly once")
		result = recovery.advance([_roster(1, Vector2.ZERO)])
		check(bool(result.completed) == (index == 2), "Only the third deposit completes the shared objective")
	check(not bool(recovery.advance([_roster(1, Vector2.ZERO)]).completed), "Further ticks cannot repeat completion")
	recovery.reset()
	check(recovery.relics.is_empty() and not recovery.completed, "Room reset removes all cargo and completion state")
	recovery.begin(POSITIONS)
	recovery.advance([_roster(1, POSITIONS[0], false)])
	check(not recovery.carrier_has_relic(1), "A fallen player standing over a relic cannot collect it")
	recovery.advance([_roster(1, POSITIONS[0]), _roster(2, POSITIONS[1]), _roster(3, POSITIONS[2]), _roster(4, Vector2.ZERO)])
	check(recovery.carrier_has_relic(1) and recovery.carrier_has_relic(2) and recovery.carrier_has_relic(3) and not recovery.carrier_has_relic(4), "Four-player parties share exactly three uniquely carried relics")
	check(bool(recovery.advance([_roster(1, Vector2.ZERO), _roster(2, Vector2.ZERO), _roster(3, Vector2.ZERO)]).completed), "Simultaneous co-op deposits produce one shared completion")

func _test_snapshot_boundaries() -> void:
	var host := RECOVERY.new()
	host.begin(POSITIONS)
	host.advance([_roster(41, POSITIONS[1])])
	var replica := RECOVERY.new()
	replica.apply_snapshot(host.snapshot())
	check(replica.snapshot() == host.snapshot(), "Snapshot includes exact relic identity, cargo owner and position")
	var copy := replica.snapshot()
	copy.relics[1].carrier_id = 99
	check(replica.carrier_has_relic(41), "Returned snapshot cannot mutate authoritative state")
	for malformed in [{}, {"relics": "bad"}, {"relics": []}, {"relics": [{}, {}, {}]}]:
		replica.apply_snapshot(malformed)
		check(replica.relics.is_empty(), "Missing or malformed optional state clears the old display")
	var duplicated := host.snapshot()
	duplicated.relics[0].carrier_id = 41
	replica.apply_snapshot(duplicated)
	check(replica.relics.is_empty(), "Malformed snapshot cannot give one player duplicate cargo")
	var bad_position := host.snapshot()
	bad_position.relics[2].position = Vector2(INF, 0)
	replica.apply_snapshot(bad_position)
	check(replica.relics.is_empty(), "Non-finite cargo positions cannot reach the renderer")

func _test_profiles() -> void:
	var builder: Node = world.encounter_profile_builder
	for tier in 4:
		builder.set_difficulty_tier(tier)
		for party in [1, 2, 4]:
			builder.set_use_multiplayer_difficulty_config(party > 1)
			builder.set_multiplayer_party_size(party)
			for depth in [2, 5, 12]:
				var profile: Dictionary = builder.build_objective_profile(depth, "relic_recovery")
				var sites := CONTRACTS.profile_relic_positions(profile)
				check(sites.size() == 3 and CONTRACTS.profile_obstacle_layout(profile).is_empty(), "Recovery profile has three unobstructed sites across Bearing/depth/party matrix")
				for site in sites:
					var half := CONTRACTS.profile_room_size(profile) * 0.5
					check(site.length() > 190 and absf(site.x) <= half.x - 80 and absf(site.y) <= half.y - 80, "Resolved relic site clears receiver, walls and entry slots")
				var serialized: Dictionary = bytes_to_var(var_to_bytes(profile))
				check(CONTRACTS.profile_relic_positions(CONTRACTS.normalize_profile(serialized)) == sites, "Door profile keeps the chosen relic layout through native serialization and normalization")
				var door := CONTRACTS.objective_door_option(profile)
				check(CONTRACTS.door_reward_preview_text(door) == "Boon + Fortified (3 rooms)", "Door promises the exact existing Mission reward")
	builder.set_difficulty_tier(1)
	builder.set_use_multiplayer_difficulty_config(false)
	builder.set_multiplayer_party_size(1)
	var offered := false
	for _sample in 100:
		var profile: Dictionary = builder.build_objective_profile(3)
		offered = offered or CONTRACTS.profile_objective_kind(profile) == "relic_recovery"
		check(CONTRACTS.profile_objective_kind(builder.build_objective_profile(3, "", "relic_recovery")) != "relic_recovery", "Existing entered-objective exclusion prevents immediate repetition")
	check(offered, "Relic Recovery appears in the ordinary eligible Mission pool")
	for _sample in 20:
		check(CONTRACTS.profile_objective_kind(builder.build_objective_profile(1)) != "relic_recovery", "Early objective generation preserves the introductory pool")
	var session := SESSION.new()
	session.record_encounter_entry(builder.build_objective_profile(3, "relic_recovery"))
	check(session.last_objective_kind == "relic_recovery", "Central objective registry makes entered-history tracking recognize Recovery")

func _enter_recovery() -> Dictionary:
	world._clear_all_enemies()
	world.reward_selection_ui.close_selection()
	var profile: Dictionary = world.encounter_profile_builder.build_objective_profile(3, "relic_recovery")
	world._choose_door(CONTRACTS.objective_door_option(profile))
	world.player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	world._sync_renderer()
	return profile

func _tick_recovery(delta: float = 0.06) -> void:
	world.objective_frame_coordinator.tick(world.objective_manager, world.objective_runtime, delta, world.encounter_intro_grace_active)

func _test_actual_room() -> void:
	var profile := _enter_recovery()
	var manager: Node = world.objective_manager
	var sites := CONTRACTS.profile_relic_positions(profile)
	world.player.global_position = sites[0]
	var survey: Dictionary = manager.relic_recovery.snapshot()
	_tick_recovery(4.0)
	check(manager.relic_recovery.snapshot() == survey, "Actual survey frame gate freezes pickup and objective state")
	world.hud.refresh(world._get_hud_state(), world.player)
	check(world.hud._status_obj_line2.text == "Carry relics to the central receiver", "Actual survey HUD explains retrieval before simulation starts")
	check(world._get_biome_objective_exclusions().size() == 4, "Receiver and three ground relics are excluded from compact biome hazards")
	check(var_to_bytes(manager.serialize_sync_state()).size() < 1100, "Recovery heartbeat leaves enough MTU room for the RPC envelope")
	world._exit_encounter_intro_grace()
	var base_speed: float = world.player.max_speed
	var base_damage: int = world.player.damage
	_tick_recovery()
	check(manager.relic_recovery.carrier_has_relic(maxi(1, world.player.player_id)), "Main runtime picks up the local living player's relic")
	check(world.player.max_speed == base_speed and world.player.damage == base_damage, "Carrying preserves movement and damage stats")
	check(world._get_biome_objective_exclusions().size() == 3, "Picked-up relic stops reserving its former ground site")
	world.hud.refresh(world._get_hud_state(), world.player)
	check(world.hud._status_obj_line2.text.contains("Carrying a relic"), "Actual owner HUD distinguishes carried cargo")
	var initial_count: int = world.active_room_enemy_count
	_tick_recovery()
	check(world.active_room_enemy_count == initial_count + 2, "First pickup spawns the two bounded reinforcements through the existing enemy spawner")
	var before_hit: Dictionary = manager.relic_recovery.snapshot()
	world.player.take_damage(4, {"source": "recovery_fixture", "ability": "ordinary_damage"})
	_tick_recovery()
	check(manager.relic_recovery.carrier_has_relic(maxi(1, world.player.player_id)) and manager.relic_recovery.relics[0].awakened == before_hit.relics[0].awakened, "Accepted ordinary damage neither drops cargo nor rearms reinforcements")
	var depth_before: int = world.room_depth
	var clears_before: int = world.rooms_cleared
	for index in 3:
		world.player.global_position = sites[index]
		_tick_recovery()
		world.player.global_position = Vector2.ZERO
		_tick_recovery()
	check(manager.active_objective_kind.is_empty() and manager.relic_recovery.relics.is_empty(), "Final deposit clears objective and its world markers")
	check(world.room_depth == depth_before + 1 and world.rooms_cleared == clears_before + 1, "Recovery advances ordinary run progress exactly once")
	check(world.reward_selection_ui.is_active() and world.reward_selection_ui.reward_selection_mode == ENUMS.RewardMode.MISSION, "Final deposit opens the existing Mission reward selection")
	_tick_recovery()
	check(world.room_depth == depth_before + 1, "A later objective frame cannot advance the completed room again")
	var selection: Dictionary = world.reward_selection_ui.boon_choices.front().duplicate(true)
	var chosen_id := String(selection.get("id", ""))
	world.reward_selection_ui.process_input(2.0)
	world.reward_selection_ui._confirm_choice(0)
	check(not chosen_id.is_empty() and world.player.get_upgrade_stack_count(chosen_id) == 1, "Claiming the actual Mission card grants one permanent Boon")
	check(world.player.get_active_objective_mutators().size() == 1, "Claiming the actual Mission card grants its existing temporary Fortified benefit")
	check(world.choosing_next_room and not world.door_options.is_empty(), "Reward resolution opens the normal next doors")
	var offered_door := CONTRACTS.objective_door_option(profile)
	CONTRACTS.door_option_set_position(offered_door, Vector2(200, -40))
	world.door_options = [offered_door]
	world._save_active_run_checkpoint()
	var saved: Dictionary = RunContext.load_active_run()
	check(saved.get("last_objective_kind") == "relic_recovery" and CONTRACTS.profile_relic_positions(saved.door_options[0].profile) == sites, "Isolated checkpoint retains entered history and exact offered relic positions")
	check(world._apply_active_run_snapshot(saved), "Production Continue restores the recovery checkpoint")
	check(world.objective_manager.relic_recovery.relics.is_empty() and world.choosing_next_room, "Continue between rooms does not resurrect delivered cargo")
	world._choose_door(world.door_options[0])
	check(world.objective_manager.relic_recovery.delivered_count() == 0 and world.objective_manager.relic_recovery.relics.size() == 3, "Entering a saved Recovery offer begins three fresh relics")
	world._clear_all_enemies()
	world._begin_room(world.encounter_profile_builder.build_skirmish_profile(3))
	check(world.objective_manager.relic_recovery.relics.is_empty(), "An ordinary next room removes all Recovery state")
	await process_frame
