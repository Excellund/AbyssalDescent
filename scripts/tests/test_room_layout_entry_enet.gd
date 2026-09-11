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
const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const BOSS_CATALOGUE := preload("res://scripts/shared/boss_catalogue.gd")
const DESCENT_BIOMES := ["shatterfield", "grinding_vault", "void_breach"]
const BIOME_OBSTACLE_COUNTS := {
	"crumble": 4, "haunt": 4, "shatterfield": 4,
	"grinding_vault": 6, "storm_reach": 2, "hollow": 3,
	"void_breach": 0, "the_maelstrom": 4, "convergence_end": 8
}
var audio_retirement := AUDIO_RETIREMENT.new()
var role: String
var prefix: String
var transport: ENetMultiplayerPeer
var world: WORLD
var failures: Array[String] = []
var checks := 0
var score_playback_id := 0
var cases := ["Apex Breakwater", "Serialized Cover", "Legacy Clear"]

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _music_playback_id() -> int:
	var music: Node = world.music_system
	if music.active_music_player_index < 0:
		return 0
	var active: AudioStreamPlayer = music.music_players[music.active_music_player_index]
	var playback: AudioStreamPlayback = active.get_stream_playback()
	return playback.get_instance_id() if active.playing and playback != null else 0

func _check_score_continuity(label: String) -> void:
	check(score_playback_id != 0 and _music_playback_id() == score_playback_id, label)

func _check_score_location(act: int, depth: int, boss_chamber: bool, label: String) -> void:
	var normal := posmod(depth + act - 1, 3)
	check(world.music_system.get_normal_score_variant() == normal, label + ": normal variation follows the presented location")
	check(world.music_system.get_selected_score_variant() == (3 if boss_chamber else normal), label + ": selected variation matches the chamber")

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
	check(world.music_system.is_adaptive_score(), "Each real Main scene loads the adaptive Riot Depth score")
	score_playback_id = _music_playback_id()
	check(score_playback_id != 0, "Each peer starts one native synchronized score playback")
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
	_write("transport-started-" + role, true)
	if role == "host":
		_write("ready", true)
	# The wrapper launches the client after host readiness. Loading its real
	# Main scene can exceed a gameplay RPC's timeout on a busy machine; wait
	# for both transports before measuring connection and replication latency.
	var transports_started: bool = await _until(func(): return _has("transport-started-host") and _has("transport-started-client"), 25.0)
	check(transports_started, "Both native transports finish startup before configuring the session")
	if not transports_started:
		await _finish()
		return
	var connected: bool = await _until(func(): return transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	check(connected, "ENet becomes connected")
	if not connected:
		await _finish()
		return
	var peers_visible: bool = await _until(func(): return get_multiplayer().get_peers().size() == 1)
	check(peers_visible, "Both real peers are visible")
	if not peers_visible:
		await _finish()
		return
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
	await _test_intercept_living_escorts()
	await _test_biome_terrain()
	await _test_descent_flow()
	_write("finished-" + role, true)
	check(await _until(func(): return _has("finished-host") and _has("finished-client")), "Both peers finish before teardown")
	await _finish()

func _finish() -> void:
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

func _test_intercept_living_escorts() -> void:
	# The isolated autoload suppresses startup; wire its existing health/death
	# transport explicitly, then create both avatars through the native roster.
	PlayerReplicationService.multiplayer_session_manager = MultiplayerSessionManager
	world._setup_multiplayer_remote_players()
	check(world._get_multiplayer_player_nodes().size() == 2, "Both connected peers have the two native avatars for escort eligibility")
	var client_id := int(get_multiplayer().get_peers()[0]) if role == "host" else get_multiplayer().get_unique_id()
	for fallen_id in [client_id, 1]:
		var key := "escort-remote" if fallen_id == client_id else "escort-host"
		var offers: Array[Dictionary] = []
		if role == "host":
			offers.append(CONTRACTS.objective_door_option(world.encounter_profile_builder.build_objective_profile(5, "intercept_run")))
		await _offer_and_request(key, offers, "Intercept Run")
		world._signal_local_player_ready()
		check(await _until(func(): return not world.encounter_intro_grace_active), "Both owners Engage the real Intercept room through readiness RPCs: " + key)
		for actor in world._get_multiplayer_player_nodes():
			actor.set_physics_process(false)
		for enemy in _living():
			enemy.set_process(false)
			enemy.set_physics_process(false)
			enemy.global_position = Vector2(450, 300)
		world.enemy_spawner.set_process(false)
		# Positions and enemy locations are staged on both copies. Only the host
		# changes health or advances the objective; receivers use real RPCs.
		var fallen = world._get_player_for_peer(fallen_id)
		var living = world._get_player_for_peer(1 if fallen_id == client_id else client_id)
		var manager := world.objective_manager
		fallen.global_position = manager.intercept_drone_position
		living.global_position = Vector2(200, 0)
		await _barrier("positioned-" + key)
		if role == "host":
			fallen.health_state.set_health(0)
		check(await _until(func(): return fallen.is_dead() and not fallen.visible and world._count_alive_players() == 1), "Host health/death RPCs hide the same fallen avatar while retaining the living teammate: " + key)
		check(not world._run_outcome_coordinator.is_player_defeated(), "A single replicated death keeps the co-op encounter active: " + key)
		await _barrier("death-received-" + key)
		if role == "client":
			var replica_before := manager.serialize_sync_state()
			world.objective_runtime.update_intercept_run_objective_state(0.5)
			check(manager.serialize_sync_state() == replica_before, "Joining objective runtime cannot author escort progress: " + key)
		if role == "host":
			var before := manager.intercept_drone_progress
			world._process(0.1)
			check(manager.intercept_drone_progress == before, "Host does not advance for a fallen escort: " + key)
		await _check_escort_network_state(key + "-outside", true, false, "Stay close to the drone")
		living.global_position = manager.intercept_drone_position + Vector2(45, 0)
		await _barrier("living-near-" + key)
		if role == "host":
			var before := manager.intercept_drone_progress
			world._process(0.1)
			check(manager.intercept_drone_progress > before, "The host advances when either living teammate escorts: " + key)
		await _check_escort_network_state(key + "-moving", false, true, "Path clear — drone advancing")
		if role == "host":
			_living()[0].global_position = manager.intercept_drone_position
			var before := manager.intercept_drone_progress
			world._process(0.1)
			check(manager.intercept_drone_progress == before, "A live enemy still blocks the host drone: " + key)
		await _check_escort_network_state(key + "-blocked", true, true, "enemies blocking — clear the path")
		# Stage the next case with the existing host revive path and full health;
		# no local replica repair or fabricated alive-status packet is used.
		if role == "host":
			world._try_revive_fallen_multiplayer_players()
			for actor in world._get_multiplayer_player_nodes():
				actor.set_health(actor.health_state.max_health)
		check(await _until(func(): return world._count_alive_players() == 2), "Existing host revival reaches both peers before the next case: " + key)
		for actor in world._get_multiplayer_player_nodes():
			actor.set_physics_process(false)
		await _barrier("revived-" + key)

func _check_escort_network_state(key: String, stalled: bool, escorted: bool, hint: String) -> void:
	if role == "host":
		_write(key + "-progress", world.objective_manager.intercept_drone_progress)
	check(await _until(func(): return _has(key + "-progress")), "Host exposes expected progress for transport comparison: " + key)
	var expected_progress: float = _read(key + "-progress")
	check(await _until(func():
		if role == "host":
			world._sync_objective_state_tick(world.objective_state_sync_interval_sec)
		world._refresh_frame_ui()
		return world.objective_manager.intercept_drone_stalled == stalled and world.objective_manager.intercept_player_in_escort_zone == escorted and is_equal_approx(world.objective_manager.intercept_drone_progress, expected_progress) and world.hud._status_obj_line2.text.contains(hint)), "Existing objective RPC delivers matching stalled/progress/escort state and live HUD: " + key)
	_write("escort-checked-" + key + "-" + role, true)
	check(await _until(func():
		if role == "host":
			world._sync_objective_state_tick(world.objective_state_sync_interval_sec)
		return _has("escort-checked-" + key + "-host") and _has("escort-checked-" + key + "-client")), "Both peers inspect the same escort state before advancing: " + key)

func _living() -> Array[Node]:
	var out: Array[Node] = []
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
			out.append(enemy)
	return out

func _barrier(key: String) -> void:
	_write(key + "-" + role, true)
	check(await _until(func(): return _has(key + "-host") and _has(key + "-client")), "Both peers reach " + key)

## Stage the act only; the real host roster and chosen-door RPCs carry each
## biome's authored ordinary arena and enemy mix into the joiner's Main scene.
func _test_biome_terrain() -> void:
	var previous_first_boss: bool = world.first_boss_defeated
	var previous_second_boss: bool = world.second_boss_defeated
	var previous_reached_act: int = world.run_summary_recorder.run_summary_tracker.reached_act
	var previous_standard: String = world.run_session.last_standard_encounter_key
	var previous_objective: String = world.run_session.last_objective_kind
	var previous_announced_act: int = world._last_announced_act
	var previous_biomes: Array[String] = world.run_session.act_biome_ids.duplicate()
	for biome_id: String in BIOME_OBSTACLE_COUNTS:
		var stage := int(BIOMES.get_biome(biome_id).act)
		var key := "terrain-" + biome_id
		var roster: Array[String] = ["crumble", "grinding_vault", "void_breach"]
		roster[stage - 1] = biome_id
		world.first_boss_defeated = stage >= 2
		world.second_boss_defeated = stage >= 3
		# This independent roster is valid for every act and differs from each
		# host roster. Never place a biome in the wrong act to stage this test.
		world.run_session.act_biome_ids = ["haunt", "hollow", "the_maelstrom"]
		world.encounter_profile_builder.rng.seed = 196400 + stage if role == "host" else 863200 + stage
		await _barrier(key + "-staged")
		if role == "host":
			world._sync_act_biomes.rpc(PackedStringArray(roster))
		check(await _until(func(): return world.run_session.act_biome_ids == roster), "Native roster RPC installs all three valid act identities: " + biome_id)
		check(world.encounter_profile_builder.active_biome.get("id", "") == biome_id, "Builder receives the authoritative active biome: " + biome_id)
		check(world.renderer.environment_act == stage and world.renderer.environment_biome_id == biome_id, "Renderer receives the authoritative act and biome: " + biome_id)
		await _barrier(key + "-roster")
		if role == "host":
			var host_profile: Dictionary = world.encounter_profile_builder.build_debug_encounter_profile("crossfire", world.room_depth)
			var door := CONTRACTS.standard_encounter_door_option(host_profile)
			world._choose_door(door)
			world._sync_chosen_door.rpc(door, world._build_progress_sync_state())
			_write(key + "-choice", {"room": world.get_current_room_sync_id(), "profile": host_profile})
		check(await _until(func(): return _has(key + "-choice")), "Host dispatches the actual biome chosen-door RPC: " + biome_id)
		var expected: Dictionary = _read(key + "-choice")
		var profile: Dictionary = expected.profile
		var layout := CONTRACTS.profile_obstacle_layout(profile)
		var enemy_count := CONTRACTS.profile_total_enemy_count(profile)
		check(await _until(func(): return world.current_room_label == "Crossfire" and world.get_current_room_sync_id() == int(expected.room) and _living().size() == enemy_count), "Native room transition and spawn replication finish: " + biome_id)
		check(world.encounter_intro_grace_active and not world.choosing_next_room, "Biome encounter awaits play on both peers: " + biome_id)
		check(world.active_room_enemy_count == enemy_count, "Both peers retain the complete host enemy count: " + biome_id)
		for enemy_type: String in CONTRACTS._get_enemy_count_keys():
			var type_count := CONTRACTS._get_enemy_count(enemy_type, profile)
			if type_count <= 0:
				continue
			var actual_count := 0
			for enemy in _living():
				if enemy.get_script() == world.enemy_spawner.scripts.get(enemy_type):
					actual_count += 1
			check(actual_count == type_count, "Native enemies preserve host biome weighting for %s: %s" % [enemy_type, biome_id])
		check(world.current_room_size == CONTRACTS.profile_room_size(profile) and world.current_room_static_camera == CONTRACTS.profile_static_camera(profile), "Room dimensions and camera mode preserve the host profile: " + biome_id)
		check(layout.size() == int(BIOME_OBSTACLE_COUNTS[biome_id]), "Production builder chooses the biome's ordinary terrain family: " + biome_id)
		check(world.renderer.obstacle_layout == layout and world.enemy_spawner.obstacle_circles == layout, "Renderer and spawn geometry preserve exact host terrain despite independent RNG: " + biome_id)
		check(world._active_obstacle_nodes.size() == layout.size(), "Native collision body count matches the host terrain: " + biome_id)
		for index in mini(layout.size(), world._active_obstacle_nodes.size()):
			var body: StaticBody2D = world._active_obstacle_nodes[index]
			var shape := body.shape_owner_get_shape(body.get_shape_owners()[0], 0) as CircleShape2D
			check(body.global_position == layout[index].pos and is_equal_approx(shape.radius, float(layout[index].radius)), "Native collider preserves exact host position and radius: %s/%d" % [biome_id, index])
		check(world.renderer.environment_act == stage and world.renderer.environment_biome_id == biome_id, "Chosen-door entry retains authoritative biome presentation: " + biome_id)
		await _barrier(key + "-inspected")
	# Later-act terrain fixtures must not pre-credit the following descent test.
	world.first_boss_defeated = previous_first_boss
	world.second_boss_defeated = previous_second_boss
	world.run_summary_recorder.run_summary_tracker.reached_act = previous_reached_act
	world.run_session.last_standard_encounter_key = previous_standard
	world.run_session.last_objective_kind = previous_objective
	world._last_announced_act = previous_announced_act
	world.run_session.act_biome_ids = previous_biomes
	world._apply_active_biome(world._get_current_act())
	await _barrier("terrain-fixtures-restored")

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
	_check_score_location(1, 5, false, "Both peers enter the same normal variation")
	_check_score_continuity("Native chosen-door RPCs preserve the original score playback on each peer")
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
	var previous_room_id := world.get_current_room_sync_id()
	var previous_variant: int = world.music_system.get_selected_score_variant()
	var previous_normal: int = world.music_system.get_normal_score_variant()
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
	if role == "client":
		var expected_music: StringName = &"rest" if world.current_room_label == "Rest Site" else &"doors"
		check(world.music_system.music_context == expected_music, "Accepted door payload records the correct local context: " + key)
	check(world.music_system.get_selected_score_variant() == previous_variant and world.music_system.get_normal_score_variant() == previous_normal,
		"Door offers preserve the current room's music despite progress payloads: " + key)
	_check_score_continuity("Receiving door offers preserves each peer's native playback: " + key)
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
	# Rest does not advance the combat room ID. Encounters must advance it,
	# including consecutive choices with the same display label.
	var is_rest := CONTRACTS.door_option_kind_id(expected[0]) == ENUMS.DoorKind.REST
	check(await _until(func(): return (is_rest or world.get_current_room_sync_id() > previous_room_id) and world.current_room_label == expected_label), "Joiner request resolves through host authority and the new chosen door: " + key)
	await _barrier("entered-" + key)
	if role == "host":
		_write("score-location-" + key, {"act": world._get_room_presentation_act(), "depth": world.room_depth,
			"normal": world.music_system.get_normal_score_variant(), "selected": world.music_system.get_selected_score_variant()})
	check(await _until(func(): return _has("score-location-" + key)), "Host exposes its entered musical location for both peers: " + key)
	var score_location: Dictionary = _read("score-location-" + key)
	var is_boss := CONTRACTS.door_option_kind_id(expected[0]) == ENUMS.DoorKind.BOSS
	_check_score_location(int(score_location.act), int(score_location.depth), is_boss, "Replicated room " + key)
	check(world.music_system.get_normal_score_variant() == int(score_location.normal)
		and world.music_system.get_selected_score_variant() == int(score_location.selected), "Both peers select the host's exact room variation: " + key)
	_check_score_continuity("A new room changes musical variation without replacing either peer's playback: " + key)

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
	var entered_depth := world.room_depth
	_check_score_location(stage, entered_depth, true, "Boss entrance on each peer " + boss_key)
	_check_score_continuity("Boss entry RPCs keep each peer's synchronized score running: " + boss_key)
	await _barrier("boss-survey-" + boss_key)
	await _test_boss_greeting_ready(boss_key, stage)
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
	check(world.reward_selection_ui.epitaph_label.visible and world.reward_selection_ui.epitaph_label.get_parsed_text() == _defeat_caption(boss_key), "Existing reward RPC displays this boss's attributed defeat line on both peers: " + boss_key)
	world._sync_renderer()
	check(world._get_room_presentation_act() == stage and world._get_hud_state().display_act == stage, "Boss reward HUD keeps the chamber's original act: " + boss_key)
	check(world.renderer.environment_act == stage and world.renderer.environment_biome_id == DESCENT_BIOMES[stage - 1], "Boss rewards preserve the defeated chamber's visible environment: " + boss_key)
	check(not world.renderer.boss_entrance_active and world.music_system.music_context == &"reward", "Reward selection records its context while the entrance motif stays off: " + boss_key)
	_check_score_location(stage, entered_depth, true, "Boss rewards retain their defeated chamber on both peers " + boss_key)
	_check_score_continuity("Replicated boss clear preserves the existing music through rewards: " + boss_key)
	if role == "host":
		check(world.run_summary_recorder.run_summary_tracker.reached_act == stage, "Defeating a boss does not falsely count the following act as entered")
	await _barrier("boss-reward-" + boss_key)
	if role == "client":
		world.reward_selection_ui.close_selection()
		world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.BOSS, false)
	await _barrier("boss-reward-client-finished-" + boss_key)
	check(world.music_system.music_context == &"reward", "Music stays in rewards while the other peer is still choosing: " + boss_key)
	_check_score_location(stage, entered_depth, true, "Waiting for the other peer does not replace boss music " + boss_key)
	await _barrier("boss-reward-wait-inspected-" + boss_key)
	if role == "host":
		world.reward_selection_ui.close_selection()
		world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.BOSS, false)
	check(await _until(func():
		world.enemy_state_sync_receiver.flush_pending_door_syncs()
		return not world.reward_selection_ui.is_active() and world.choosing_next_room and not world.door_options.is_empty()), "Both real reward completions unlock host-generated routes: " + boss_key)
	check(world.music_system.music_context == &"doors", "Reward completion records door selection on host and joiner: " + boss_key)
	_check_score_location(stage, entered_depth, true, "Boss door choices preserve boss music after act advancement " + boss_key)
	_check_score_continuity("Co-op reward completion keeps the same music through door choices: " + boss_key)
	check(world._get_current_act() == stage + 1 and world._get_room_presentation_act() == stage, "Replicated progress advances while the old chamber remains: " + boss_key)
	await _barrier("boss-exits-" + boss_key)
	offers.clear()
	if role == "host":
		offers.append(CONTRACTS.rest_door_option())
	await _offer_and_request("rest-after-" + boss_key, offers, "Rest Site")
	world._sync_renderer()
	check(world.renderer.environment_act == stage + 1 and world.renderer.environment_biome_id == DESCENT_BIOMES[stage], "Actual next-room RPC reveals the following act and biome: " + boss_key)
	check(world.music_system.music_context == &"rest", "Actual next-act rest selects the next location's normal music on both peers")
	_check_score_location(stage + 1, world.room_depth, false, "Rest selects its new act and incremented depth on both peers")
	_check_score_continuity("Rest entry and deferred rest-door payloads preserve native score playback")
	check(world.run_summary_recorder.run_summary_tracker.reached_act == stage + 1, "Actual next-act entry advances reached_act on both peers")
	await _barrier("next-act-" + boss_key)

func _defeat_caption(boss_id: String) -> String:
	return "%s: \"%s\"" % [String(BOSS_CATALOGUE.NAMES[boss_id]), BOSS_CATALOGUE.get_defeat_line(boss_id)]

func _test_boss_greeting_ready(boss_key: String, stage: int) -> void:
	var hud: Node = world.hud
	var room_id := world.get_current_room_sync_id()
	var greeting := "\"%s\"" % BOSS_CATALOGUE.get_greeting(boss_key)
	check(hud.boss_intro_visible and hud.room_banner_persistent_visible and hud.room_banner_subtitle_label.text == greeting, "Actual replicated boss survey displays the catalogue greeting: " + boss_key)
	# The previous chamber's completion message must not end this new survey.
	if role == "host":
		world._broadcast_all_players_ready.rpc(room_id - 1)
	await _barrier("boss-stale-ready-" + boss_key)
	check(world.encounter_intro_grace_active and hud.boss_intro_visible, "Old-room readiness cannot dismiss the current boss greeting: " + boss_key)
	if role == "client":
		world._signal_local_player_ready()
		check(world._local_player_ready and not hud.boss_intro_visible and hud.room_banner_title_label.text == "Ready" and hud.room_banner_subtitle_label.text == "Waiting for allies...", "Ready replaces dialogue synchronously without a forced greeting delay: " + boss_key)
	await _barrier("boss-client-ready-" + boss_key)
	if role == "host":
		var client_id := int(get_multiplayer().get_peers()[0])
		check(await _until(func(): return bool(world._encounter_ready_peers.get(client_id, false))), "Host receives the joining player's real readiness RPC: " + boss_key)
		check(not world._local_player_ready and hud.boss_intro_visible, "Unready host retains its own greeting while its ally waits: " + boss_key)
	else:
		check(hud.room_banner_persistent_visible and hud.room_banner_subtitle_label.text == "Waiting for allies...", "Co-op waiting retains priority over the boss greeting: " + boss_key)
	check(world.encounter_intro_grace_active, "One ready ally cannot start the boss encounter alone: " + boss_key)
	await _barrier("boss-wait-inspected-" + boss_key)
	if role == "host":
		world._signal_local_player_ready()
		check(not world.encounter_intro_grace_active, "Final readiness ends the survey immediately in the same call: " + boss_key)
	check(await _until(func(): return not world.encounter_intro_grace_active), "Existing readiness RPC ends the boss survey on both peers: " + boss_key)
	check(not hud.boss_intro_visible and is_zero_approx(hud.room_banner_title_label.modulate.a) and is_zero_approx(hud.room_banner_subtitle_label.modulate.a), "Boss greeting is fully hidden before active combat resumes: " + boss_key)
	# Drive the native first windup without simulating an entire combat. Its
	# authoritative state still reaches the observer through the real sender.
	var boss: Node = _living()[0]
	boss.set_physics_process(false)
	await _barrier("boss-warning-ready-" + boss_key)
	if role == "host":
		boss._start_next_attack(180.0, 0.0)
		if stage == 1:
			boss._process_telegraph_state(0.05)
		else:
			boss._process_windup_state(0.05)
		world.enemy_state_sync_broadcaster.tick(0.25)
		world.enemy_state_sync_broadcaster.tick(0.25)
		# Sovereign and Lacuna carry full attack warnings on the separate
		# native projectile channel, also normally pumped by World._process.
		world._sync_archer_projectile_state_tick(0.05)
	check(await _until(func(): return boss._is_in_priority_attack_state() and float(boss.telegraph_alpha) > 0.0), "Native first boss warning reaches both actual peers: " + boss_key)
	check(not hud.boss_intro_visible and is_zero_approx(hud.room_banner_title_label.modulate.a) and is_zero_approx(hud.room_banner_subtitle_label.modulate.a), "First live warning has no greeting or replacement banner over it: " + boss_key)
	if role == "host":
		world._broadcast_all_players_ready.rpc(room_id)
		world._broadcast_all_players_ready.rpc(room_id - 1)
		world._broadcast_all_players_ready(room_id)
	await _barrier("boss-duplicate-ready-" + boss_key)
	check(not world.encounter_intro_grace_active and not hud.boss_intro_visible, "Duplicate and stale room-ready messages cannot resurrect boss dialogue: " + boss_key)

func _test_final_summary() -> void:
	var summary: Dictionary = world.run_summary_recorder.latest_run_summary
	check(summary.get("reached_act", 0) == 3 and summary.get("defeated_boss_ids", []) == ["warden", "sovereign", "lacuna"], "Full final summary carries the reached act and exact defeated boss IDs through outcome transport")
	check(summary.get("outcome", "") == "clear" and summary.get("is_multiplayer", false), "Native outcome receiver preserves the complete multiplayer clear summary")
	check(int(summary.get("stats", {}).get("damage_dealt_total", 0)) == (111 if role == "host" else 777), "Final results use this peer's stats while preserving shared descent facts")
	if role == "client":
		check(world.run_summary_recorder.run_summary_tracker.defeated_boss_ids.is_empty(), "Replica final boss credits come from the host summary, not local completion guesses")
	check(world.victory_screen.is_open(), "The actual shared result screen is displayed on both peers")
	check(world.victory_screen._results_screen._subtitle_label.text == _defeat_caption("lacuna"), "Final result subtitle attributes Lacuna's defeat line from the transported boss summary on both peers")
	var saved: Array = HISTORY.load_all()
	check(not saved.is_empty() and saved.back().get("reached_act", 0) == 3 and saved.back().get("defeated_boss_ids", []) == ["warden", "sovereign", "lacuna"], "Both isolated history files retain transported descent facts")
	await _barrier("final-summary-inspected")
