extends Node
## Core networking service for multiplayer sessions.
## Manages MultiplayerAPI setup, room creation/joining, peer tracking, and timeouts.
## Auto-load singleton. All multiplayer gameplay depends on this.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal session_created(session_id: String, room_code: String)
signal session_joined(session_id: String)
signal peer_timeout(peer_id: int)
signal connection_failed(reason: String)

## Public state
var session_connected: bool = false
var is_host_peer: bool = false
var local_peer_id: int = 0
var session_id: String = ""
var room_code: String = ""
var connected_peers: Dictionary = {}  ## peer_id -> { joined_at, last_ping }

## Configuration
var disconnect_timeout_sec: float = 30.0
var ping_interval_sec: float = 1.0

## Internal state
var _multiplayer: MultiplayerAPI
var _peer_timeout_timers: Dictionary = {}  ## peer_id -> Timer node


func _ready() -> void:
	_multiplayer = get_tree().get_multiplayer()
	_multiplayer.peer_connected.connect(_on_peer_connected)
	_multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_multiplayer.connected_to_server.connect(_on_connected_to_server)
	_multiplayer.connection_failed.connect(_on_connection_failed)
	_multiplayer.server_disconnected.connect(_on_server_disconnected)


## Create a new multiplayer room (host only).
## Returns: room_code for other players to join
func create_room() -> String:
	if session_connected:
		push_error("Already connected to a session. Call leave_room() first.")
		return ""
	var registration := {
		"room_code": _generate_random_code(6).to_upper(),
		"session_id": "mp-session-%d-%s" % [Time.get_unix_time_from_system(), _generate_random_code(4)],
		"host_port": 9999,
		"transport_type": "direct_enet"
	}
	if not create_registered_room(registration):
		return ""
	return room_code

func create_registered_room(room_registration: Dictionary) -> bool:
	if session_connected:
		push_error("Already connected to a session. Call leave_room() first.")
		return false

	var host_port := int(room_registration.get("host_port", 9999))
	var transport_type := String(room_registration.get("transport_type", "direct_enet"))
	if transport_type != "direct_enet":
		connection_failed.emit("Unsupported transport type: %s" % transport_type)
		return false

	var enet_peer := ENetMultiplayerPeer.new()
	var result := enet_peer.create_server(host_port)
	if result != OK:
		connection_failed.emit("Failed to create server: %s" % error_string(result))
		return false

	_multiplayer.multiplayer_peer = enet_peer
	session_connected = true
	is_host_peer = true
	local_peer_id = _multiplayer.get_unique_id()
	session_id = String(room_registration.get("session_id", "")).strip_edges()
	if session_id.is_empty():
		session_id = "mp-session-%d-%s" % [Time.get_unix_time_from_system(), _generate_random_code(4)]
	room_code = String(room_registration.get("room_code", "")).strip_edges().to_upper()
	if room_code.is_empty():
		room_code = _generate_random_code(6).to_upper()
	connected_peers[local_peer_id] = { "joined_at": Time.get_unix_time_from_system(), "last_ping": 0 }
	session_created.emit(session_id, room_code)
	print_debug("[MultiplayerSessionManager] Created room as host. Room code: %s" % room_code)
	return true


## Join an existing multiplayer room (client only).
func join_room(host_address: String = "127.0.0.1", host_port: int = 9999) -> bool:
	if session_connected:
		push_error("Already connected to a session. Call leave_room() first.")
		return false

	var enet_peer := ENetMultiplayerPeer.new()
	var result := enet_peer.create_client(host_address, host_port)
	if result != OK:
		connection_failed.emit("Failed to create client connection: %s" % error_string(result))
		return false
	
	_multiplayer.multiplayer_peer = enet_peer
	session_connected = true
	is_host_peer = false
	
	print_debug("[MultiplayerSessionManager] Connecting to host at %s:%d..." % [host_address, host_port])
	return true

func join_registered_room(room_registration: Dictionary) -> bool:
	var transport_type := String(room_registration.get("transport_type", "direct_enet"))
	if transport_type != "direct_enet":
		connection_failed.emit("Unsupported transport type: %s" % transport_type)
		return false
	var host_address := String(room_registration.get("host_address", "")).strip_edges()
	var host_port := int(room_registration.get("host_port", 9999))
	if host_address.is_empty():
		connection_failed.emit("Room registration is missing host address.")
		return false
	session_id = String(room_registration.get("session_id", "")).strip_edges()
	room_code = String(room_registration.get("room_code", "")).strip_edges().to_upper()
	return join_room(host_address, host_port)


## Leave current session and disconnect.
func leave_room() -> void:
	if not session_connected:
		return
	if is_host_peer and not room_code.is_empty():
		var room_service = get_node_or_null("/root/MultiplayerRoomService")
		if room_service != null and room_service.has_method("close_room_registration"):
			room_service.close_room_registration(room_code)
	
	for timer in _peer_timeout_timers.values():
		if is_instance_valid(timer):
			timer.queue_free()
	_peer_timeout_timers.clear()
	connected_peers.clear()
	
	_multiplayer.multiplayer_peer = null
	session_connected = false
	is_host_peer = false
	local_peer_id = 0
	session_id = ""
	room_code = ""
	print_debug("[MultiplayerSessionManager] Left session.")


## Get current state snapshot.
func get_session_info() -> Dictionary:
	return {
		"is_connected": session_connected,
		"is_host": is_host_peer,
		"local_peer_id": local_peer_id,
		"session_id": session_id,
		"room_code": room_code,
		"connected_peer_count": connected_peers.size()
	}


## Query if this peer is the host.
func is_host() -> bool:
	return is_host_peer and session_connected


## Query if this peer is a client.
func is_client() -> bool:
	return not is_host_peer and session_connected

func is_session_connected() -> bool:
	return session_connected


## Get list of connected peer IDs (including self if host).
func get_peer_ids() -> Array:
	return connected_peers.keys()


## RPC method: Heartbeat ping from client to host (for timeout tracking).
@rpc("reliable", "any_peer")
func _network_ping() -> void:
	var caller_id := get_multiplayer().get_remote_sender_id()
	if is_host_peer and caller_id in connected_peers:
		connected_peers[caller_id]["last_ping"] = Time.get_unix_time_from_system()


## Internal: Triggered when peer connects to multiplayer session.
func _on_peer_connected(peer_id: int) -> void:
	if peer_id == _multiplayer.get_unique_id():
		return  ## Ignore self-connection events
	
	connected_peers[peer_id] = { "joined_at": Time.get_unix_time_from_system(), "last_ping": 0 }
	peer_connected.emit(peer_id)
	print_debug("[MultiplayerSessionManager] Peer %d connected." % peer_id)
	
	if is_host_peer:
		_set_up_timeout_timer_for_peer(peer_id)


## Internal: Triggered when peer disconnects from multiplayer session.
func _on_peer_disconnected(peer_id: int) -> void:
	connected_peers.erase(peer_id)
	peer_disconnected.emit(peer_id)
	print_debug("[MultiplayerSessionManager] Peer %d disconnected." % peer_id)
	
	if peer_id in _peer_timeout_timers:
		var timer: Timer = _peer_timeout_timers[peer_id] as Timer
		if is_instance_valid(timer):
			timer.queue_free()
		_peer_timeout_timers.erase(peer_id)


## Internal: Triggered when client successfully connects to server.
func _on_connected_to_server() -> void:
	local_peer_id = _multiplayer.get_unique_id()
	session_joined.emit(session_id)
	print_debug("[MultiplayerSessionManager] Connected to server as peer %d." % local_peer_id)


## Internal: Triggered when client fails to connect.
func _on_connection_failed() -> void:
	session_connected = false
	push_error("[MultiplayerSessionManager] Connection failed.")
	connection_failed.emit("Connection failed to server.")


## Internal: Triggered when server is shut down (only for clients).
func _on_server_disconnected() -> void:
	push_error("[MultiplayerSessionManager] Server disconnected.")
	leave_room()


## Internal: Set up a timeout timer for a peer (host only).
func _set_up_timeout_timer_for_peer(peer_id: int) -> void:
	if peer_id in _peer_timeout_timers:
		return  ## Already has a timer
	
	var timer := Timer.new()
	add_child(timer)
	timer.timeout.connect(_on_peer_timeout_timer_fired.bind(peer_id))
	timer.start(disconnect_timeout_sec)
	_peer_timeout_timers[peer_id] = timer


## Internal: Called when a peer's timeout timer fires (no ping received).
func _on_peer_timeout_timer_fired(peer_id: int) -> void:
	if peer_id not in connected_peers:
		return  ## Already disconnected
	
	push_error("[MultiplayerSessionManager] Peer %d timeout (no heartbeat)." % peer_id)
	peer_timeout.emit(peer_id)


## Internal: Generate a random alphanumeric code.
func _generate_random_code(length: int) -> String:
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var result := ""
	for i in range(length):
		result += chars[randi() % chars.length()]
	return result
