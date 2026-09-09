extends Node
## Service for syncing game state (room progression, boss status, encounter seed) across multiplayer peers.
## Host broadcasts authoritative state; clients receive and apply it.

signal room_depth_changed(new_depth: int)
signal room_cleared()
signal boss_unlocked()
signal boss_defeated()

## Reference to world_generator (populated by caller)
var world_generator: Node = null

## Internal state
var local_room_depth: int = 0
var local_rooms_cleared: int = 0
var local_boss_unlocked: bool = false

## Provenance uses the autoload path so announcements survive scene loading.
## Each recorder reset has a fresh token; a challenge binds both peers' tokens.
var _provenance_recorder: WeakRef
var _provenance_session: String = ""
var _local_run_token: String = ""
var _host_run_token: String = ""
var _previous_host_run_token: String = ""
var _peer_run_tokens: Dictionary = {}
var _retired_peer_run_tokens: Dictionary = {}


func _ready() -> void:
	set_process(false)  ## Only host needs to broadcast; clients listen via RPCs


## Initialize the service (called from world_generator).
func initialize(world_gen: Node) -> void:
	world_generator = world_gen


func bind_run_provenance(recorder_ref: WeakRef, token: String) -> void:
	var recorder = recorder_ref.get_ref()
	if not _is_current_recorder(recorder) or token != recorder._provenance_token or not _provenance_transport_ready():
		return
	var session := String(RunContext.get_multiplayer_session_id())
	if session != _provenance_session:
		_provenance_session = session
		_host_run_token = ""
		_previous_host_run_token = ""
		_peer_run_tokens.clear()
		_retired_peer_run_tokens.clear()
	if token != _local_run_token:
		_previous_host_run_token = _host_run_token
		for peer_id in _peer_run_tokens:
			_retired_peer_run_tokens[_peer_run_tokens[peer_id]] = true
		_peer_run_tokens.clear()
		_host_run_token = token if MultiplayerSessionManager.is_host() else ""
		_local_run_token = token
	_provenance_recorder = recorder_ref
	if not MultiplayerSessionManager.peer_connected.is_connected(_on_provenance_peer_connected):
		MultiplayerSessionManager.peer_connected.connect(_on_provenance_peer_connected)
	if MultiplayerSessionManager.is_host():
		for peer_id in MultiplayerSessionManager.get_peer_ids():
			_on_provenance_peer_connected(int(peer_id))
	elif not _host_run_token.is_empty():
		# Once bound, updates use the same reliable channel as gameplay and
		# need no new round trip before the host can see stricter evidence.
		_receive_run_provenance.rpc_id(1, _host_run_token, _local_run_token, recorder.run_summary_tracker.run_provenance.duplicate(true))
	else:
		_register_run_provenance.rpc_id(1, _local_run_token, _previous_host_run_token)


func _is_current_recorder(recorder: Variant) -> bool:
	return recorder != null and is_instance_valid(recorder._world) and recorder._world.is_inside_tree() and recorder._world.is_multiplayer and recorder._world.run_summary_recorder == recorder


func _active_provenance_recorder() -> Variant:
	var recorder = _provenance_recorder.get_ref() if _provenance_recorder != null else null
	if not _is_current_recorder(recorder) or recorder._provenance_token != _local_run_token:
		return null
	return recorder


func _provenance_transport_ready() -> bool:
	var peer := multiplayer.multiplayer_peer
	return MultiplayerSessionManager.is_session_connected() and peer != null and not peer is OfflineMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _on_provenance_peer_connected(peer_id: int) -> void:
	var recorder = _active_provenance_recorder()
	if recorder == null or not MultiplayerSessionManager.should_broadcast() or peer_id <= 1:
		return
	recorder.run_summary_tracker.expect_peer_provenance(peer_id)
	_request_provenance_registration.rpc_id(peer_id)


@rpc("authority", "call_remote", "reliable")
func _request_provenance_registration() -> void:
	if multiplayer.get_remote_sender_id() != 1 or _active_provenance_recorder() == null or not MultiplayerSessionManager.is_remote_replica():
		return
	_register_run_provenance.rpc_id(1, _local_run_token, _previous_host_run_token)


@rpc("any_peer", "call_remote", "reliable")
func _register_run_provenance(peer_token: String, previous_host_token: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var recorder = _active_provenance_recorder()
	if recorder == null or not MultiplayerSessionManager.should_broadcast() or sender <= 1 or not MultiplayerSessionManager.connected_peers.has(sender):
		return
	# A client already starting the next run must not bind to the old host
	# recorder. Conversely, the previous client's token cannot join a new run.
	if peer_token.length() != 32 or previous_host_token == _host_run_token or _retired_peer_run_tokens.has(peer_token):
		return
	_peer_run_tokens[sender] = peer_token
	recorder.run_summary_tracker.expect_peer_provenance(sender)
	_request_run_provenance.rpc_id(sender, _host_run_token, peer_token)


@rpc("authority", "call_remote", "reliable")
func _request_run_provenance(host_token: String, peer_token: String) -> void:
	var recorder = _active_provenance_recorder()
	if multiplayer.get_remote_sender_id() != 1 or recorder == null or not MultiplayerSessionManager.is_remote_replica() or peer_token != _local_run_token or host_token.length() != 32:
		return
	_host_run_token = host_token
	_receive_run_provenance.rpc_id(1, host_token, _local_run_token, recorder.run_summary_tracker.run_provenance.duplicate(true))


@rpc("any_peer", "call_remote", "reliable")
func _receive_run_provenance(host_token: String, peer_token: String, provenance: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var recorder = _active_provenance_recorder()
	if recorder == null or not MultiplayerSessionManager.should_broadcast() or sender <= 1 or not MultiplayerSessionManager.connected_peers.has(sender):
		return
	if host_token != _host_run_token or not _peer_run_tokens.has(sender) or peer_token != String(_peer_run_tokens[sender]):
		return
	# The transport supplies identity; the payload cannot claim another peer.
	recorder.run_summary_tracker.record_peer_provenance(sender, provenance)


## Called by world_generator when a new room is entered.
## Host broadcasts this to all peers.
func on_room_entered(depth: int) -> void:
	_broadcast_if_host(func(): _sync_room_entered.rpc(depth))


## Called by world_generator when a room is cleared.
## Host broadcasts this to all peers.
func on_room_cleared(new_depth: int, new_rooms_cleared: int) -> void:
	_broadcast_if_host(func(): _sync_room_cleared.rpc(new_depth, new_rooms_cleared))


## Called by world_generator when boss is unlocked.
func on_boss_unlocked() -> void:
	_broadcast_if_host(func(): _sync_boss_unlocked.rpc())


## Called by world_generator when boss is defeated (run clear).
func on_boss_defeated() -> void:
	_broadcast_if_host(func(): _sync_boss_defeated.rpc())


## Calls rpc_callable only when this peer should broadcast host RPCs.
func _broadcast_if_host(rpc_callable: Callable) -> void:
	if MultiplayerSessionManager.should_broadcast():
		rpc_callable.call()


## RPC: Sync room entry.
@rpc("reliable")
func _sync_room_entered(depth: int) -> void:
	local_room_depth = depth
	room_depth_changed.emit(depth)


## RPC: Sync room clear.
@rpc("reliable")
func _sync_room_cleared(new_depth: int, new_rooms_cleared: int) -> void:
	local_room_depth = new_depth
	local_rooms_cleared = new_rooms_cleared
	room_cleared.emit()
	print_debug("[GameStateReplication] Room cleared. Depth: %d, Rooms: %d" % [new_depth, new_rooms_cleared])


## RPC: Sync boss unlock.
@rpc("reliable")
func _sync_boss_unlocked() -> void:
	local_boss_unlocked = true
	boss_unlocked.emit()
	print_debug("[GameStateReplication] Boss unlocked")


## RPC: Sync boss defeat (run completion).
@rpc("reliable")
func _sync_boss_defeated() -> void:
	boss_defeated.emit()
	print_debug("[GameStateReplication] Boss defeated - run complete")


## Get current local state snapshot.
func get_state() -> Dictionary:
	return {
		"room_depth": local_room_depth,
		"rooms_cleared": local_rooms_cleared,
		"boss_unlocked": local_boss_unlocked
	}
