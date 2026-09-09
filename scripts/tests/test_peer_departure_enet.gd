extends "res://scripts/tests/test_peer_departure.gd"
## Real ENet disconnect -> session manager -> production world lifecycle.

var transport: ENetMultiplayerPeer
var role: String
var prefix: String
var departed_id: int = 0
var departure_observed: bool = false
var departed_ref: WeakRef

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or args.size() != 4:
		push_error("Peer departure ENet requires an isolated profile, role, loopback port and report prefix")
		quit(1)
		return
	role = args[1]
	prefix = args[3]
	transport = ENetMultiplayerPeer.new()
	if role == "host":
		transport.set_bind_ip("127.0.0.1")
		check(transport.create_server(int(args[2]), 1) == OK, "Host binds the ephemeral loopback port")
	else:
		check(transport.create_client("127.0.0.1", int(args[2])) == OK, "Joiner creates the loopback connection")
	get_multiplayer().multiplayer_peer = transport
	if role == "host":
		await _host_run()
	else:
		await _client_run()
	await _finish_enet()

func _until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.02).timeout
	return false

func _host_run() -> void:
	var saved := _setup_departure()
	world.name = "World"
	MultiplayerSessionManager._multiplayer = get_multiplayer()
	# The base unit fixture uses peer 2; only expose real transport IDs to
	# stable services while waiting for this process's randomly assigned peer.
	MultiplayerSessionManager.connected_peers = {1: {}}
	get_multiplayer().peer_disconnected.connect(MultiplayerSessionManager._on_peer_disconnected)
	FileAccess.open(prefix + "-ready", FileAccess.WRITE).store_string("ready")
	check(await _until(func(): return not get_multiplayer().get_peers().is_empty()), "The separate joiner process establishes an ENet peer")
	if get_multiplayer().get_peers().is_empty():
		await _cleanup()
		return
	departed_id = get_multiplayer().get_peers()[0]
	var departed := actors[1]
	PlayerReplicationService.unregister_player(2)
	departed.player_id = departed_id
	PlayerReplicationService.register_player(departed_id, departed)
	MultiplayerSessionManager.connected_peers = {1: {}, departed_id: {}}
	departed_ref = weakref(departed)
	PlayerReplicationService._pending_cue_events_by_peer[departed_id] = [{"event": "returning_crescent_state"}]
	_fallen(world.player)
	world._on_player_died()
	check(not world._run_outcome_coordinator.is_player_defeated(), "The actual world waits while the remote ally is alive")
	MultiplayerSessionManager.peer_disconnected.connect(_observe_departure)
	FileAccess.open(prefix + "-disconnect", FileAccess.WRITE).store_string("disconnect")
	check(await _until(func(): return departure_observed), "Closing the remote ENet transport emits the real production disconnect path")
	await process_frame
	check(not is_instance_valid(departed_ref.get_ref()), "The departed avatar is freed after its disconnect frame")
	check(world._get_multiplayer_player_nodes() == [world.player] and not PlayerReplicationService._pending_cue_events_by_peer.has(departed_id), "The live disconnect removes the ghost roster entry and pending remote attacks")
	check(world._run_outcome_coordinator.is_player_defeated() and world.shown_outcomes == ["death"] and HISTORY.load_all().size() == 1, "Losing the last living ally reaches ordinary defeat and one history entry")
	check(RunContext.load_active_run() == saved and RunContext.consume_resume_saved_run_request(), "The live co-op disconnect preserves the separate solo checkpoint and resume request")
	await _cleanup()

func _observe_departure(peer_id: int) -> void:
	if peer_id != departed_id:
		return
	departure_observed = true
	var actor := departed_ref.get_ref() as Player
	check(is_instance_valid(actor) and actor.is_queued_for_deletion() and not actor.visible and not actor.combat_damage_enabled, "The disconnect callback immediately hides and disables the real remote actor")
	# The fixture Player creates an unparented registry; retire it before its
	# queued actor disappears so strict fixture teardown can check all objects.
	if is_instance_valid(actor):
		actor.upgrade_system.power_registry.free()
		actors.erase(actor)

func _client_run() -> void:
	check(await _until(func(): return transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "The joiner connects to the real host process")
	check(await _until(func(): return FileAccess.file_exists(prefix + "-disconnect")), "The host finishes arranging its live party state before departure")
	transport.close()
	check(transport.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED, "The joining player closes its actual ENet transport")
	await create_timer(0.2).timeout

func _finish_enet() -> void:
	transport.close()
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	MultiplayerSessionManager.session_connected = false
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	HISTORY.clear_all()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await create_timer(0.1).timeout
	FileAccess.open(prefix + "-" + role + ".json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}))
	print("[ENet] Peer departure %s: %d checks, %d failures" % [role, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
