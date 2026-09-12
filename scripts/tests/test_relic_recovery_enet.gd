extends "res://scripts/tests/test_relic_recovery.gd"
## Two real Main scenes and native chosen-door, cargo snapshot, health/death,
## reward and room-transition RPCs. Actor positions are staged on both copies.
var role := ""
var prefix := ""
var transport: ENetMultiplayerPeer
var client_id := 0
var last_sync_ms := 0

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _is_isolated() or args.size() != 4:
		quit(1)
		return
	role = args[1]
	prefix = args[3]
	_setup_recovery_world()
	transport = ENetMultiplayerPeer.new()
	if role == "host":
		transport.set_bind_ip("127.0.0.1")
		check(transport.create_server(int(args[2]), 1) == OK, "Host opens isolated loopback ENet")
	else:
		check(transport.create_client("127.0.0.1", int(args[2])) == OK, "Client connects through actual ENet")
	get_multiplayer().multiplayer_peer = transport
	_write("transport-" + role, true)
	if role == "host":
		_write("ready", true)
	if not await _until(func(): return _has("transport-host") and _has("transport-client"), 25.0):
		check(false, "Both transports finish startup")
		await _finish_enet()
		return
	check(await _until(func(): return transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and get_multiplayer().get_peers().size() == 1), "Both processes establish one real peer")
	MultiplayerSessionManager._multiplayer = get_multiplayer()
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = role == "host"
	MultiplayerSessionManager.local_peer_id = get_multiplayer().get_unique_id()
	MultiplayerSessionManager.connected_peers = {1: {}}
	for id in get_multiplayer().get_peers():
		MultiplayerSessionManager.connected_peers[id] = {}
	MultiplayerSessionManager.connected_peers[get_multiplayer().get_unique_id()] = {}
	client_id = int(get_multiplayer().get_peers()[0]) if role == "host" else get_multiplayer().get_unique_id()
	PlayerReplicationService.player_nodes.clear()
	PlayerReplicationService.local_peer_id = get_multiplayer().get_unique_id()
	PlayerReplicationService.multiplayer_session_manager = MultiplayerSessionManager
	world.player.player_id = get_multiplayer().get_unique_id()
	world.player.is_local_player = true
	PlayerReplicationService.register_player(world.player.player_id, world.player)
	world.is_multiplayer = true
	world._setup_multiplayer_remote_players()
	world.encounter_profile_builder.set_use_multiplayer_difficulty_config(true)
	world.encounter_profile_builder.set_multiplayer_party_size(2)
	await _barrier("built")
	check(world._get_multiplayer_player_nodes().size() == 2, "Native Main creates both party avatars")
	if role == "host":
		var profile: Dictionary = world.encounter_profile_builder.build_objective_profile(3, "relic_recovery")
		var door := CONTRACTS.objective_door_option(profile)
		world._choose_door(door)
		world._sync_chosen_door.rpc(door, world._build_progress_sync_state())
		_write("profile", profile)
	check(await _until(func(): return world.current_room_label == "Relic Recovery" and _has("profile")), "Native chosen-door RPC enters the same Recovery arena")
	var sites := CONTRACTS.profile_relic_positions(_read("profile"))
	check(world.objective_manager.relic_recovery.relics.size() == 3, "Both peers resolve all three offered relics")
	await _barrier("entered")
	world._signal_local_player_ready()
	check(await _until(func(): return not world.encounter_intro_grace_active), "Both owners Engage through real readiness RPCs")
	for actor in world._get_multiplayer_player_nodes():
		actor.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	world._get_player_for_peer(1).global_position = sites[0]
	world._get_player_for_peer(client_id).global_position = sites[0]
	await _barrier("simultaneous-position")
	if role == "client":
		var before: Dictionary = world.objective_manager.relic_recovery.snapshot()
		_tick_recovery()
		check(world.objective_manager.relic_recovery.snapshot() == before, "Replica runtime cannot grant a pickup from local proximity")
	await _barrier("replica-guard")
	await _host_step("pickup", func(): _tick_recovery())
	check(world.objective_manager.relic_recovery.carrier_has_relic(1) and not world.objective_manager.relic_recovery.carrier_has_relic(client_id), "Host tie-break reaches both peers with one canonical carrier")
	world._get_player_for_peer(1).global_position = Vector2(130, 70)
	world._get_player_for_peer(client_id).global_position = Vector2(-160, 60)
	await _barrier("death-position")
	if role == "host":
		world._get_player_for_peer(1).health_state.set_health(0)
	check(await _until(func(): return world._get_player_for_peer(1).is_dead()), "Actual host health/death transport marks the carrier fallen")
	await _host_step("drop", func(): _tick_recovery())
	check(not world.objective_manager.relic_recovery.carrier_has_relic(1) and world.objective_manager.relic_recovery.relics[0].position == Vector2(130, 70), "Both peers receive the death drop at its final position")
	world._get_player_for_peer(client_id).global_position = Vector2(130, 70)
	await _barrier("recover-position")
	await _host_step("recover", func(): _tick_recovery())
	check(world.objective_manager.relic_recovery.carrier_has_relic(client_id), "Living joining player recovers the fallen host's relic")
	world.hud.refresh(world._get_hud_state(), world.player)
	check(world.hud._status_obj_line2.text.contains("Carrying a relic") == (role == "client"), "HUD carrying instruction belongs only to the actual local cargo owner")
	world._get_player_for_peer(client_id).global_position = Vector2.ZERO
	await _barrier("deposit-position")
	await _host_step("deposit", func(): _tick_recovery())
	check(world.objective_manager.relic_recovery.delivered_count() == 1, "Joining player's deposit is shared exactly once")
	var accepted: Dictionary = world.objective_manager.relic_recovery.snapshot()
	if role == "host":
		world._sync_objective_state.rpc({"active_objective_kind": "relic_recovery", "relic_recovery": {}}, world.get_current_room_sync_id() - 1, 99999)
		world._sync_objective_state.rpc({"active_objective_kind": "relic_recovery", "relic_recovery": {}}, world.get_current_room_sync_id(), 0)
	await _barrier("stale-snapshots")
	check(world.objective_manager.relic_recovery.snapshot() == accepted, "Stale sequence and previous-room cargo snapshots are rejected")
	for index in [1, 2]:
		world._get_player_for_peer(client_id).global_position = sites[index]
		await _barrier("remaining-position-" + str(index))
		await _host_step("remaining-pickup-" + str(index), func(): _tick_recovery())
		check(world.objective_manager.relic_recovery.carrier_has_relic(client_id), "Living player carries remaining relic " + str(index))
		world._get_player_for_peer(client_id).global_position = Vector2.ZERO
		await _barrier("remaining-return-" + str(index))
		await _host_step("remaining-deposit-" + str(index), func(): _tick_recovery())
	check(await _until(func(): return world.reward_selection_ui.is_active()), "Actual final-deposit RPC opens Mission rewards on both owners")
	check(world.objective_manager.active_objective_kind.is_empty() and world.objective_manager.relic_recovery.relics.is_empty(), "Completion removes cargo on host and replica")
	check(world.reward_selection_ui.reward_selection_mode == ENUMS.RewardMode.MISSION, "Both peers receive the standard Mission reward mode")
	var clear_depth := world.room_depth
	await _host_step("completed-extra-tick", func(): _tick_recovery())
	check(world.room_depth == clear_depth, "Extra networked frame cannot advance cleared room again")
	world.reward_selection_ui.process_input(1.0)
	world.reward_selection_ui._confirm_choice(0)
	check(await _until(func(): return world.choosing_next_room), "Both normal Mission choices release the next-door phase")
	await _barrier("reward-claimed")
	await _test_carrier_disconnect()
	await _barrier("finished")
	await _finish_enet()

func _test_carrier_disconnect() -> void:
	if not MultiplayerSessionManager.peer_disconnected.is_connected(world._on_multiplayer_peer_disconnected):
		MultiplayerSessionManager.peer_disconnected.connect(world._on_multiplayer_peer_disconnected)
	if not get_multiplayer().peer_disconnected.is_connected(MultiplayerSessionManager._on_peer_disconnected):
		get_multiplayer().peer_disconnected.connect(MultiplayerSessionManager._on_peer_disconnected)
	if role == "host":
		var door := CONTRACTS.objective_door_option(world.encounter_profile_builder.build_objective_profile(4, "relic_recovery"))
		world._choose_door(door)
		world._sync_chosen_door.rpc(door, world._build_progress_sync_state())
		_write("disconnect-room", world.get_current_room_sync_id())
	check(await _until(func(): return _has("disconnect-room") and world.get_current_room_sync_id() == int(_read("disconnect-room")) and world.encounter_intro_grace_active), "Second Recovery room enters through the actual door transport")
	world._signal_local_player_ready()
	check(await _until(func(): return not world.encounter_intro_grace_active), "Both owners Engage the disconnect scenario")
	for actor in world._get_multiplayer_player_nodes():
		actor.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	check(not world._get_player_for_peer(1).is_dead(), "Normal room completion revived the host before the next retrieval")
	var site: Vector2 = world.objective_manager.relic_recovery.relics[0].position
	world._get_player_for_peer(client_id).global_position = site
	world._get_player_for_peer(1).global_position = Vector2.ZERO
	await _barrier("disconnect-pickup-position")
	await _host_step("disconnect-pickup", func(): _tick_recovery())
	check(world.objective_manager.relic_recovery.carrier_has_relic(client_id), "Joining player carries the relic before disconnecting")
	await _barrier("disconnect-now")
	if role == "client":
		MultiplayerSessionManager.session_connected = false
		transport.close()
		_write("transport-closed", true)
	else:
		check(await _until(func(): return _has("transport-closed") and not PlayerReplicationService.player_nodes.has(client_id)), "Actual ENet disconnect removes the departed avatar through production callbacks")
		_tick_recovery()
		check(int(world.objective_manager.relic_recovery.relics[0].carrier_id) == 0 and world.objective_manager.relic_recovery.relics[0].position == site, "Disconnect drops the relic at its last host-observed position")
		world.player.global_position = site
		_tick_recovery()
		check(world.objective_manager.relic_recovery.carrier_has_relic(1), "Remaining host can recover the disconnected player's cargo")
		_write("disconnect-verified", true)
	check(await _until(func(): return _has("disconnect-verified")), "Actual disconnect recovery completes before either process exits")

func _until(predicate: Callable, seconds: float = 8.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if predicate.call():
			return true
		# Reproduce the production 20Hz heartbeat while this fixture holds the
		# rest of Main still. Unreliable state is intentionally retried.
		if role == "host" and is_instance_valid(world) and world.is_multiplayer and Time.get_ticks_msec() - last_sync_ms >= 50:
			world._sync_objective_state_tick(0.05)
			last_sync_ms = Time.get_ticks_msec()
		await process_frame
	return false

func _write(key: String, value: Variant) -> void:
	FileAccess.open(prefix + "-" + key, FileAccess.WRITE).store_var(value)

func _read(key: String) -> Variant:
	return FileAccess.open(prefix + "-" + key, FileAccess.READ).get_var()

func _has(key: String) -> bool:
	return FileAccess.file_exists(prefix + "-" + key)

func _barrier(key: String) -> void:
	_write(key + "-" + role, true)
	check(await _until(func(): return _has(key + "-host") and _has(key + "-client")), "Both peers reach " + key)

func _host_step(key: String, action: Callable) -> void:
	if role == "host":
		action.call()
		world._sync_objective_state_tick(0.1)
		_write(key + "-state", world.objective_manager.serialize_sync_state())
	check(await _until(func(): return _has(key + "-state")), "Host publishes " + key)
	var expected: Dictionary = _read(key + "-state")
	check(await _until(func(): return world.objective_manager.serialize_sync_state() == expected), "Real ordered objective RPC converges: " + key)
	await _barrier(key + "-received")

func _finish_enet() -> void:
	MultiplayerSessionManager.session_connected = false
	PlayerReplicationService.player_nodes.clear()
	EnemyReplicationService.unbind_world(world)
	await _cleanup_recovery_world()
	transport.close()
	get_multiplayer().multiplayer_peer = null
	FileAccess.open(prefix + "-" + role + ".json", FileAccess.WRITE).store_string(JSON.stringify({"role": role, "checks": checks, "failures": failures}, "\t"))
	print("[ENet] %s: %d checks, %d failures" % [role, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
