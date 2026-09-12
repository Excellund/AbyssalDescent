extends "res://scripts/tests/test_relic_recovery_enet.gd"
## Native Main owners, actual provenance/door/health/build/reward RPCs and a
## real disconnect. Choice inputs are scripted; no Internet lobby is exercised.
const REST := preload("res://scripts/core/rest_site_choice.gd")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _is_isolated() or args.size() != 4:
		quit(1)
		return
	role = args[1]
	prefix = args[3]
	_setup_recovery_world()
	world._exit_encounter_intro_grace()
	if not await _connect_rest_party(int(args[2])):
		await _finish_enet()
		return
	world._apply_boon_to_player("heavy_blow")
	await _barrier("owned-boon")
	check(await _until(func(): return world._get_player_for_peer(1).get_upgrade_stack_count("heavy_blow") == 1 and world._get_player_for_peer(client_id).get_upgrade_stack_count("heavy_blow") == 1), "Both original owned Boons reach native build replicas")
	if role == "host":
		world._get_player_for_peer(1).health_state.set_health(60)
		world._get_player_for_peer(client_id).health_state.set_health(50)
	check(await _until(func(): return world._get_player_for_peer(1).get_current_health() == 60 and world._get_player_for_peer(client_id).get_current_health() == 50), "Host health staging reaches both real owners")
	await _enter_native_rest("first")
	var first_depth := world.room_depth
	var token: String = world._rest_visit_run
	check(world.reward_selection_ui.is_active() and world._rest_site_choice.active, "Both living owners receive a personal Rest choice")
	if role == "host":
		_claim_native_rest("heavy_blow")
	await _barrier("host-invested")
	check(not world.choosing_next_room and world.door_options.is_empty(), "Host investment waits for the joining owner's decision")
	if role == "client":
		check(world.reward_selection_ui.is_active() and world.player.get_current_health() == 50, "Host choice cannot consume or heal the joining player's Rest")
		_claim_native_rest(REST.RECOVER_ID)
	check(await _until(func(): return world.choosing_next_room and not world.door_options.is_empty()), "Different local Rest choices release the ordinary reward barrier")
	var results_arrived := await _until(func(): return world._get_player_for_peer(1).get_upgrade_stack_count("heavy_blow") == 2 and world._get_player_for_peer(client_id).get_current_health() == 92)
	_write("result-arrived-" + role, results_arrived)
	check(results_arrived, "Normal build and healing replication deliver each owner's chosen result")
	check(world._get_player_for_peer(1).get_current_health() == 60 and world._get_player_for_peer(client_id).get_upgrade_stack_count("heavy_blow") == 1, "Neither peer receives the other owner's Rest benefit")
	if role == "client":
		var timeline: Array = world.run_summary_recorder.run_summary_tracker.reward_timeline
		check(String(timeline[-1].label) == "Recovered 42 health" and String(timeline[-1].category) == "rest", "Joining owner records recovery as Rest, not a Boon")
	check(await _until(func(): return _has("result-arrived-host") and _has("result-arrived-client"), 12.0), "Both processes finish result inspection before the next visit")
	await _barrier("first-finished")
	await _enter_native_rest("second")
	if role == "host":
		world._sync_reward_phase_advance.rpc(false, ENUMS.RewardMode.REST)
		world._sync_rest_choice_advance.rpc("retired-run", world.room_depth)
		world._sync_rest_choice_advance.rpc(token, first_depth)
		world._sync_rest_choice_complete.rpc(client_id, token, world.room_depth)
	else:
		world._sync_rest_choice_complete.rpc(1, token, world.room_depth)
		world._sync_rest_choice_complete.rpc(client_id, "retired-run", world.room_depth)
		world._sync_rest_choice_complete.rpc(client_id, token, first_depth)
	await _barrier("stale-phase-probes")
	check(world._rest_site_choice.active and world.reward_selection_ui.is_active() and not world.choosing_next_room, "Previous-visit, retired-run, generic and spoofed completion messages cannot release this Rest")
	check(world._reward_phase_coordinator._phase_completed_peers.is_empty(), "Rejected packets cannot count a peer as ready")
	if role == "host":
		_claim_native_rest(REST.RECOVER_ID)
	await _barrier("before-late-death")
	if role == "host":
		world._get_player_for_peer(client_id).health_state.set_health(0)
	check(await _until(func(): return world._get_player_for_peer(client_id).is_dead()), "A late actual health/death RPC makes the pending owner a spectator")
	check(await _until(func(): return world.choosing_next_room), "Fallen pending owner automatically completes the Rest barrier without a click")
	if role == "client":
		check(not world.reward_selection_ui.is_active() and not world._rest_site_choice.active and world.player.get_current_health() == 0, "Late-death spectator modal closes without healing or investment")
	await _barrier("late-death-finished")
	await _enter_native_rest("spectator")
	if role == "client":
		check(not world.reward_selection_ui.is_active() and not world._rest_site_choice.active, "Already-fallen owner sees no claimable Rest cards")
	else:
		_claim_native_rest(REST.RECOVER_ID)
	check(await _until(func(): return world.choosing_next_room), "Entry-time spectator does not block the living owner's choice")
	await _barrier("spectator-finished")
	if role == "host":
		world._get_player_for_peer(client_id).revive_with_health(20)
		PlayerReplicationService.broadcast_player_revived(client_id, 20)
	check(await _until(func(): return not world._get_player_for_peer(client_id).is_dead()), "Native revival restores the joining owner before disconnect coverage")
	await _barrier("revived")
	await _enter_native_rest("disconnect")
	if role == "host":
		_claim_native_rest(REST.RECOVER_ID)
	await _barrier("disconnect-pending")
	if not MultiplayerSessionManager.peer_disconnected.is_connected(world._on_multiplayer_peer_disconnected):
		MultiplayerSessionManager.peer_disconnected.connect(world._on_multiplayer_peer_disconnected)
	if not get_multiplayer().peer_disconnected.is_connected(MultiplayerSessionManager._on_peer_disconnected):
		get_multiplayer().peer_disconnected.connect(MultiplayerSessionManager._on_peer_disconnected)
	if role == "client":
		MultiplayerSessionManager.session_connected = false
		transport.close()
		_write("rest-transport-closed", true)
	else:
		check(await _until(func(): return _has("rest-transport-closed") and not PlayerReplicationService.player_nodes.has(client_id)), "Actual disconnect removes the unconfirmed owner through production callbacks")
		check(await _until(func(): return world.choosing_next_room and not world.door_options.is_empty()), "Departure releases the completed host's ordinary next doors")
		_write("rest-disconnect-verified", true)
	check(await _until(func(): return _has("rest-disconnect-verified")), "Both processes retain the disconnect proof before teardown")
	await _barrier("finished")
	await _finish_enet()

func _connect_rest_party(port: int) -> bool:
	transport = ENetMultiplayerPeer.new()
	if role == "host":
		transport.set_bind_ip("127.0.0.1")
		check(transport.create_server(port, 1) == OK, "Host opens isolated native ENet")
	else:
		check(transport.create_client("127.0.0.1", port) == OK, "Joining process connects through native ENet")
	get_multiplayer().multiplayer_peer = transport
	_write("transport-" + role, true)
	if role == "host":
		_write("ready", true)
	if not await _until(func(): return _has("transport-host") and _has("transport-client"), 25.0):
		check(false, "Both native transports finish startup")
		return false
	if not await _until(func(): return transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and get_multiplayer().get_peers().size() == 1):
		check(false, "Both transports establish their peer")
		return false
	RunContext.multiplayer_session_id = "isolated-rest-" + prefix.sha256_text().left(12)
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
	for actor in world._get_multiplayer_player_nodes():
		actor.set_physics_process(false)
	world.run_summary_recorder._schedule_party_provenance(true)
	check(await _until(func(): return not GameStateReplicationService.get_current_run_sync_token().is_empty()), "Real provenance handshake binds the current shared run token")
	_write("run-token-" + role, GameStateReplicationService.get_current_run_sync_token())
	await _barrier("built")
	check(_read("run-token-host") == _read("run-token-client"), "Both processes share the same native current-run identity")
	return true

func _enter_native_rest(label: String) -> void:
	if role == "host":
		var door := CONTRACTS.rest_door_option()
		world._choose_door(door)
		world._sync_chosen_door.rpc(door, world._build_progress_sync_state())
		_write(label + "-rest-depth", world.room_depth)
	check(await _until(func(): return _has(label + "-rest-depth") and world.current_room_label == "Rest Site" and world.room_depth == int(_read(label + "-rest-depth")) and not world._reward_phase_coordinator.get_active_phase().is_empty()), "Native chosen-door transport enters Rest " + label)
	await _barrier(label + "-rest-entered")

func _claim_native_rest(id: String) -> void:
	var index := -1
	for option in world.reward_selection_ui.boon_choices.size():
		if String(world.reward_selection_ui.boon_choices[option].id) == id:
			index = option
	world.reward_selection_ui.process_input(1.0)
	world.reward_selection_ui._confirm_choice(index)
	check(index >= 0 and not world._rest_site_choice.active, "Actual card input resolves owner choice " + id)
