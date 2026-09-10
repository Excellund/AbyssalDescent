extends SceneTree
## Real Main room methods and existing chosen-door/enemy-spawn RPCs over loopback ENet.
const MAIN := preload("res://scenes/Main.tscn")
const WORLD := preload("res://scripts/world_generator.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const BREAKWATER := preload("res://scripts/enemy_breakwater.gd")
const HISTORY := preload("res://scripts/core/run_history_store.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
const DESCENT_BIOMES := ["shatterfield", "grinding_vault", "void_breach"]
var audio_retirement := AUDIO_RETIREMENT.new()
var role: String
var prefix: String
var transport: ENetMultiplayerPeer
var world: WORLD
var failures: Array[String] = []
var checks := 0
var cases := ["Apex Breakwater", "Serialized Cover", "Legacy Clear"]

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _until(predicate: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func _write(key: String, value: Variant) -> void:
	var file := FileAccess.open(prefix + "-" + key, FileAccess.WRITE)
	file.store_var(value)
	file.close()

func _read(key: String) -> Variant:
	return FileAccess.open(prefix + "-" + key, FileAccess.READ).get_var()

func _has(key: String) -> bool:
	return FileAccess.file_exists(prefix + "-" + key)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or args.size() != 4:
		quit(1)
		return
	role = args[1]
	prefix = args[3]
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-room-layout-enet")
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
	var profiles := PROFILE.new()
	var profile := profiles.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	profiles.save_profile(profile)
	world = MAIN.instantiate() as WORLD
	world.name = "World"
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	var ui: Node = world.reward_selection_ui
	var choice: Dictionary = ui.boon_choices.front().duplicate(true)
	ui.close_selection()
	ui.reward_selected.emit(choice, ENUMS.RewardMode.ARCANA, true)
	world.set_process(false)
	world.set_physics_process(false)
	transport = ENetMultiplayerPeer.new()
	if role == "host":
		transport.set_bind_ip("127.0.0.1")
		check(transport.create_server(int(args[2]), 1) == OK, "Host binds actual isolated loopback ENet")
	else:
		check(transport.create_client("127.0.0.1", int(args[2])) == OK, "Joiner connects on actual separate ENet process")
	get_multiplayer().multiplayer_peer = transport
	if role == "host":
		_write("ready", true)
	check(await _until(func(): return transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "ENet becomes connected")
	check(await _until(func(): return get_multiplayer().get_peers().size() == 1), "Both real peers are visible")
	MultiplayerSessionManager._multiplayer = get_multiplayer()
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = role == "host"
	MultiplayerSessionManager.local_peer_id = get_multiplayer().get_unique_id()
	MultiplayerSessionManager.connected_peers = {1: {}}
	for id in get_multiplayer().get_peers():
		MultiplayerSessionManager.connected_peers[id] = {}
	MultiplayerSessionManager.connected_peers[get_multiplayer().get_unique_id()] = {}
	PlayerReplicationService.player_nodes.clear()
	PlayerReplicationService.local_peer_id = get_multiplayer().get_unique_id()
	world.player.player_id = get_multiplayer().get_unique_id()
	world.player.is_local_player = true
	PlayerReplicationService.register_player(world.player.player_id, world.player)
	world.is_multiplayer = true
	world.encounter_profile_builder.set_use_multiplayer_difficulty_config(true)
	world.encounter_profile_builder.set_multiplayer_party_size(2)
	_write("built-" + role, true)
	check(await _until(func(): return _has("built-host") and _has("built-client")), "Both actual Main instances are initialized before profile RPCs")
	for index in cases.size():
		var key := str(index)
		if role == "host":
			var encounter: Dictionary
			if index == 0:
				encounter = world.encounter_profile_builder.build_debug_encounter_profile("apex_breakwater", 8)
			else:
				encounter = CONTRACTS.profile(cases[index], Vector2(1160, 860), true, 2, 0, 0, 0)
				if index == 1:
					encounter["obstacle_layout"] = [{"pos": Vector2(-170, -90), "radius": 28.0}, {"pos": Vector2(210, 100), "radius": 36.0, "type": "boulder"}]
			var door := CONTRACTS.standard_encounter_door_option(encounter)
			world._choose_door(door)
			var state := world._build_progress_sync_state()
			world._sync_chosen_door.rpc(door, state)
			_write("case-" + key, {"room": world.get_current_room_sync_id(), "layout": CONTRACTS.profile_obstacle_layout(encounter), "count": CONTRACTS.profile_total_enemy_count(encounter)})
		else:
			check(await _until(func(): return _has("case-" + key)), "Host dispatches native chosen-door RPC " + key)
		var expected: Dictionary = _read("case-" + key)
		check(await _until(func(): return world.current_room_label == cases[index] and world.get_current_room_sync_id() == int(expected.room) and _living().size() == int(expected.count)), "Real room RPC and spawn replication enter " + cases[index])
		check(world.encounter_intro_grace_active and not world.choosing_next_room, "Declared encounter remains awaiting play rather than clearing before combat")
		check(world.active_room_enemy_count == int(expected.count), "World count matches the host-declared actual spawn count")
		check(world.renderer.obstacle_layout == expected.layout and world.enemy_spawner.obstacle_circles == expected.layout, "Host geometry survives actual room RPC into renderer/spawner")
		check(world._active_obstacle_nodes.size() == expected.layout.size(), "Same number of real collision bodies exists after native transition")
		for obstacle_index in expected.layout.size():
			check(world._active_obstacle_nodes[obstacle_index].global_position == expected.layout[obstacle_index].pos, "Real collision body preserves exact host world position")
		if index == 0:
			check(_living().size() == 1 and _living()[0].get_script() == BREAKWATER, "Exactly one real Breakwater exists on host and joiner")
		_write("checked-" + role + "-" + key, true)
		check(await _until(func(): return _has("checked-host-" + key) and _has("checked-client-" + key)), "Both peers inspect the same room before advancing")
	await _test_descent_flow()
	_write("finished-" + role, true)
	check(await _until(func(): return _has("finished-host") and _has("finished-client")), "Both peers finish before teardown")
	MultiplayerSessionManager.session_connected = false
	PlayerReplicationService.player_nodes.clear()
	EnemyReplicationService.unbind_world(world)
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame
	transport.close()
	get_multiplayer().multiplayer_peer = null
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	for _frame in range(8):
		await process_frame
	check(await audio_retirement.wait_until_retired(self), "Native scene audio retires before the ENet process exits")
	var file := FileAccess.open(prefix + "-" + role + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"role": role, "checks": checks, "failures": failures}, "\t"))
	file.close()
	print("[ENet] %s: %d checks, %d failures" % [role, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _living() -> Array[Node]:
	var out: Array[Node] = []
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
			out.append(enemy)
	return out

func _barrier(key: String) -> void:
	_write(key + "-" + role, true)
	check(await _until(func(): return _has(key + "-host") and _has(key + "-client")), "Both peers reach " + key)

## Deliberately stage offers and depth; exercise actual production transport for
## every selection, spawn, ready signal, reward completion and final outcome.
## This is a loopback flow fixture, not lobby discovery or a combat playthrough.
func _test_descent_flow() -> void:
	world._clear_all_enemies()
	world._set_progression_counters(4, 5, 0, 0)
	world.run_session.act_biome_ids = ["haunt", "hollow", "convergence_end"]
	world.run_session.act_boss_ids = ["warden", "sovereign", "lacuna"]
	var replica_standard_before: String = world.run_session.last_standard_encounter_key
	var replica_objective_before: String = world.run_session.last_objective_kind
	await _barrier("descent-staged")
	if role == "host":
		world._sync_act_biomes.rpc(PackedStringArray(DESCENT_BIOMES))
	check(await _until(func(): return world.run_session.act_biome_ids == DESCENT_BIOMES), "Host biome roster replaces the independently staged roster through its real RPC")
	check(world.renderer.environment_act == 1 and world.renderer.environment_biome_id == "shatterfield", "Both renderers apply the authoritative Shatterfield environment")
	await _barrier("biomes-received")
	var offers: Array[Dictionary] = []
	if role == "host":
		# Resolve the mirrored pilot with the production builder, then transmit
		# that exact profile; the replica must never roll its own geometry.
		var room: Dictionary = {}
		for seed_value in range(64):
			world.encounter_profile_builder.rng.seed = seed_value
			room = world.encounter_profile_builder.build_debug_encounter_profile("crossfire", 5)
			if CONTRACTS.profile_obstacle_layout(room)[0].pos.x > 0.0:
				break
		offers = [CONTRACTS.standard_encounter_door_option(room), CONTRACTS.objective_door_option(world.encounter_profile_builder.build_debug_encounter_profile("hold_the_line", 5))]
	await _offer_and_request("shatterfield", offers, "Crossfire")
	var chosen: Dictionary = _read("offers-shatterfield")[0]
	var layout := CONTRACTS.profile_obstacle_layout(CONTRACTS.door_option_profile(chosen))
	check(layout.size() == 4 and layout[0].pos == Vector2(240.0, -150.0), "Chosen Shatterfield Crossfire carries the mirrored four-column pilot")
	check(world.renderer.obstacle_layout == layout and world.enemy_spawner.obstacle_circles == layout, "Both visible and spawn-safe geometry equal the transmitted choice")
	check(world._active_obstacle_nodes.size() == 4, "Four native collision bodies are created on each peer")
	for index in layout.size():
		var body: StaticBody2D = world._active_obstacle_nodes[index]
		var shape := body.shape_owner_get_shape(body.get_shape_owners()[0], 0) as CircleShape2D
		check(body.global_position == layout[index].pos and is_equal_approx(shape.radius, 28.0), "Native collision position and radius match the selected Shatterfield formation")
	check(world.run_session.last_standard_encounter_key == ("crossfire" if role == "host" else replica_standard_before), "Only authoritative entry advances standard history")
	check(world.run_session.last_objective_kind == replica_objective_before, "The declined mission never advances objective history")
	check(world.music_system.music_context == &"combat", "The selected standard encounter uses combat music on both peers")
	if role == "host":
		var history_before: String = world.run_session.last_standard_encounter_key
		var alternatives: Array[Dictionary] = world._roll_route_options(world._build_route_context(5))
		for option in alternatives:
			if CONTRACTS.door_option_reward_mode(option) == ENUMS.RewardMode.BOON:
				check(CONTRACTS.profile_encounter_key(CONTRACTS.door_option_profile(option)) != "crossfire", "Actual next-route generation avoids the entered standard identity")
		check(world.run_session.last_standard_encounter_key == history_before, "Generating and declining alternatives leaves host history intact")
	await _barrier("crossfire-inspected")
	offers = []
	if role == "host":
		offers = [CONTRACTS.objective_door_option(world.encounter_profile_builder.build_debug_encounter_profile("hold_the_line", 5))]
	await _offer_and_request("mission", offers, "Hold the Line")
	check(world.run_session.last_objective_kind == ("hold_the_line" if role == "host" else replica_objective_before), "Only authoritative mission entry advances objective history")
	check(world.run_session.last_standard_encounter_key == ("crossfire" if role == "host" else replica_standard_before), "Entering a mission preserves independent standard history")
	# The intervening encounter clears are intentionally staged. All three boss
	# deaths below use native health/death signals and the existing clear path.
	world.objective_manager.reset()
	await _barrier("mission-inspected")
	for stage in range(1, 4):
		await _test_boss_descent(stage)
	await _test_final_summary()

func _offer_and_request(key: String, host_offers: Array[Dictionary], expected_label: String) -> void:
	var standard_before: String = world.run_session.last_standard_encounter_key
	var objective_before: String = world.run_session.last_objective_kind
	# Stage the between-room state for skipped ordinary encounters. The real
	# renderer correctly suppresses doors while a declared encounter is live.
	world._clear_all_enemies()
	world.active_room_enemy_count = 0
	world.encounter_intro_grace_active = false
	if role == "host":
		for index in host_offers.size():
			CONTRACTS.door_option_set_position(host_offers[index], Vector2(260.0 * (2 * index - 1), -220.0))
		world.door_options = host_offers.duplicate(true)
		world.choosing_next_room = true
		world._sync_door_options.rpc(world.door_options, true, world.boss_unlocked, world._build_progress_sync_state())
		_write("offers-" + key, host_offers)
	check(await _until(func(): return _has("offers-" + key)), "Host dispatches authoritative " + key + " offers")
	var expected: Array = _read("offers-" + key)
	check(await _until(func():
		world.enemy_state_sync_receiver.flush_pending_door_syncs()
		return world.choosing_next_room and world.door_options == expected), "Both peers receive exactly the same " + key + " offers")
	world._sync_renderer()
	check(world.renderer.door_options == expected, "The real renderer receives the same positioned doors and payoff data: " + key)
	check(world.run_session.last_standard_encounter_key == standard_before and world.run_session.last_objective_kind == objective_before, "Receiving offers never advances entered history: " + key)
	for option in world.door_options:
		var preview := CONTRACTS.door_reward_preview_text(option)
		var mode := CONTRACTS.door_option_reward_mode(option)
		if mode == ENUMS.RewardMode.MISSION:
			var bonus := CONTRACTS.profile_player_mutator(CONTRACTS.door_option_profile(option))
			check(preview == "Boon + %s (%d rooms)" % [CONTRACTS.mutator_name(bonus), int(bonus.duration_encounters)], "Replicated mission payoff names the actual fixed bonus and duration")
		elif CONTRACTS.door_option_kind_id(option) == ENUMS.DoorKind.BOSS:
			check(preview == ("Complete the descent" if CONTRACTS.door_option_encounter_key(option) == "lacuna" else "Boss power"), "Replicated boss payoff matches this exact boss")
		elif CONTRACTS.door_option_kind_id(option) == ENUMS.DoorKind.REST:
			check(preview == "Restore health", "Replicated rest payoff promises its actual benefit")
		else:
			check(preview == "Boon", "Replicated standard payoff preserves the Boon category")
	await _barrier("offers-inspected-" + key)
	if role == "client":
		world._request_use_door.rpc_id(1, world.door_options[0].duplicate(true))
	check(await _until(func(): return world.current_room_label == expected_label), "Joiner request resolves through host authority and chosen-door RPC: " + key)
	await _barrier("entered-" + key)

func _test_boss_descent(stage: int) -> void:
	var boss_key: String = ["warden", "sovereign", "lacuna"][stage - 1]
	var label: String = ["Boss Chamber: The Warden", "Abyss Core: Sovereign", "Silent Threshold: Lacuna"][stage - 1]
	var offers: Array[Dictionary] = []
	if role == "host":
		offers.append(CONTRACTS.boss_door_option(boss_key))
	await _offer_and_request(boss_key, offers, label)
	check(await _until(func(): return _living().size() == 1), "Native boss spawn reaches both peers: " + boss_key)
	world._sync_renderer()
	check(world.renderer.environment_act == stage and world.renderer.environment_biome_id == DESCENT_BIOMES[stage - 1], "Boss uses its own act and biome on both peers: " + boss_key)
	check(world.encounter_intro_grace_active and world.renderer.boss_entrance_active and world.renderer.boss_entrance_key == boss_key, "Boss motif appears during the actual replicated survey: " + boss_key)
	check(world.music_system.music_context == &"boss", "Boss entry selects boss music on both peers: " + boss_key)
	await _barrier("boss-survey-" + boss_key)
	world._signal_local_player_ready()
	check(await _until(func(): return not world.encounter_intro_grace_active), "Existing readiness RPC ends the boss survey on both peers: " + boss_key)
	world._sync_renderer()
	check(not world.renderer.boss_entrance_active, "Boss decoration cannot remain over combat warnings: " + boss_key)
	await _barrier("boss-combat-" + boss_key)
	if role == "host":
		if stage == 3:
			# Distinct per-peer metrics travel with the complete shared run summary.
			world.run_summary_recorder.record_damage_dealt(111, 1)
			world.run_summary_recorder.record_damage_dealt(777, get_multiplayer().get_peers()[0])
		_living()[0].health_state.take_damage(1000000)
		world._update_encounter_state()
	if stage == 3:
		check(await _until(func(): return world._run_outcome_coordinator.is_run_cleared()), "Native final boss death delivers victory through the existing outcome RPC")
		return
	check(await _until(func(): return world.reward_selection_ui.is_active()), "Native boss death opens rewards on both peers: " + boss_key)
	world._sync_renderer()
	check(world._get_room_presentation_act() == stage and world._get_hud_state().display_act == stage, "Boss reward HUD keeps the chamber's original act: " + boss_key)
	check(world.renderer.environment_act == stage and world.renderer.environment_biome_id == DESCENT_BIOMES[stage - 1], "Boss rewards preserve the defeated chamber's visible environment: " + boss_key)
	check(not world.renderer.boss_entrance_active and world.music_system.music_context == &"reward", "Reward selection keeps the motif off and enters quiet music: " + boss_key)
	if role == "host":
		check(world.run_summary_recorder.run_summary_tracker.reached_act == stage, "Defeating a boss does not falsely count the following act as entered")
	await _barrier("boss-reward-" + boss_key)
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.BOSS, false)
	check(await _until(func():
		world.enemy_state_sync_receiver.flush_pending_door_syncs()
		return not world.reward_selection_ui.is_active() and world.choosing_next_room and not world.door_options.is_empty()), "Both real reward completions unlock host-generated routes: " + boss_key)
	check(world._get_current_act() == stage + 1 and world._get_room_presentation_act() == stage, "Replicated progress advances while the old chamber remains: " + boss_key)
	await _barrier("boss-exits-" + boss_key)
	offers.clear()
	if role == "host":
		offers.append(CONTRACTS.rest_door_option())
	await _offer_and_request("rest-after-" + boss_key, offers, "Rest Site")
	world._sync_renderer()
	check(world.renderer.environment_act == stage + 1 and world.renderer.environment_biome_id == DESCENT_BIOMES[stage], "Actual next-room RPC reveals the following act and biome: " + boss_key)
	check(world.music_system.music_context == &"rest", "Actual next-act rest enters its quiet music context on both peers")
	check(world.run_summary_recorder.run_summary_tracker.reached_act == stage + 1, "Actual next-act entry advances reached_act on both peers")
	await _barrier("next-act-" + boss_key)

func _test_final_summary() -> void:
	var summary: Dictionary = world.run_summary_recorder.latest_run_summary
	check(summary.get("reached_act", 0) == 3 and summary.get("defeated_boss_ids", []) == ["warden", "sovereign", "lacuna"], "Full final summary carries the reached act and exact defeated boss IDs through outcome transport")
	check(summary.get("outcome", "") == "clear" and summary.get("is_multiplayer", false), "Native outcome receiver preserves the complete multiplayer clear summary")
	check(int(summary.get("stats", {}).get("damage_dealt_total", 0)) == (111 if role == "host" else 777), "Final results use this peer's stats while preserving shared descent facts")
	if role == "client":
		check(world.run_summary_recorder.run_summary_tracker.defeated_boss_ids.is_empty(), "Replica final boss credits come from the host summary, not local completion guesses")
	check(world.victory_screen.is_open(), "The actual shared result screen is displayed on both peers")
	var saved: Array = HISTORY.load_all()
	check(not saved.is_empty() and saved.back().get("reached_act", 0) == 3 and saved.back().get("defeated_boss_ids", []) == ["warden", "sovereign", "lacuna"], "Both isolated history files retain transported descent facts")
	await _barrier("final-summary-inspected")
