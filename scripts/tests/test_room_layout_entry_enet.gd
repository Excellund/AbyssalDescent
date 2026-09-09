extends SceneTree
## Real Main room methods and existing chosen-door/enemy-spawn RPCs over loopback ENet.
const MAIN := preload("res://scenes/Main.tscn")
const WORLD := preload("res://scripts/world_generator.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const BREAKWATER := preload("res://scripts/enemy_breakwater.gd")
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
