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
var join_attempt_timeout_sec: float = 1.5

## Internal state
var _multiplayer: MultiplayerAPI
var _peer_timeout_timers: Dictionary = {}  ## peer_id -> Timer node
var _client_ping_elapsed_sec: float = 0.0
var _join_attempt_addresses: Array = []
var _join_attempt_port: int = 9999
var _join_attempt_index: int = -1
var _join_attempt_timer: Timer


func _ready() -> void:
	_multiplayer = get_tree().get_multiplayer()
	print("[MultiplayerSessionManager] _ready() called. Connecting to MultiplayerAPI signals...")
	_multiplayer.peer_connected.connect(_on_peer_connected)
	print("[MultiplayerSessionManager] Connected: peer_connected signal")
	_multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[MultiplayerSessionManager] Connected: peer_disconnected signal")
	_multiplayer.connected_to_server.connect(_on_connected_to_server)
	print("[MultiplayerSessionManager] Connected: connected_to_server signal")
	_multiplayer.connection_failed.connect(_on_connection_failed)
	print("[MultiplayerSessionManager] Connected: connection_failed signal")
	_multiplayer.server_disconnected.connect(_on_server_disconnected)
	print("[MultiplayerSessionManager] Connected: server_disconnected signal")
	print("[MultiplayerSessionManager] === ALL SIGNALS CONNECTED ===")
	_join_attempt_timer = Timer.new()
	_join_attempt_timer.one_shot = true
	_join_attempt_timer.timeout.connect(_on_join_attempt_timeout)
	add_child(_join_attempt_timer)
	set_process(true)


func _process(delta: float) -> void:
	if not session_connected or is_host_peer:
		return
	if not _is_client_connected_to_host():
		return

	_client_ping_elapsed_sec += delta
	if _client_ping_elapsed_sec < ping_interval_sec:
		return

	_client_ping_elapsed_sec = 0.0
	_network_ping.rpc_id(1)


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
		var msg = "Already connected to a session. Call leave_room() first."
		push_error(msg)
		print("[MultiplayerSessionManager] ERROR: %s" % msg)
		return false

	var host_port := int(room_registration.get("host_port", 9999))
	var transport_type := String(room_registration.get("transport_type", "direct_enet"))
	print("[MultiplayerSessionManager] Attempting to create host server on port %d with transport: %s" % [host_port, transport_type])
	
	if transport_type != "direct_enet":
		var msg = "Unsupported transport type: %s" % transport_type
		connection_failed.emit(msg)
		print("[MultiplayerSessionManager] ERROR: %s" % msg)
		return false

	var enet_peer := ENetMultiplayerPeer.new()
	print("[MultiplayerSessionManager] Created ENetMultiplayerPeer. Attempting create_server(port=%d)..." % host_port)
	var result := enet_peer.create_server(host_port)
	
	## If port is in use, try alternative ports
	if result != OK:
		print("[MultiplayerSessionManager] Port %d failed (%s). Trying alternative ports..." % [host_port, error_string(result)])
		for alt_port in [9998, 9997, 9996, 9995, 8888, 7777]:
			print("[MultiplayerSessionManager] Trying port %d..." % alt_port)
			enet_peer = ENetMultiplayerPeer.new()
			result = enet_peer.create_server(alt_port)
			if result == OK:
				print("[MultiplayerSessionManager] Success! Using port %d instead of %d" % [alt_port, host_port])
				host_port = alt_port
				break
	
	if result != OK:
		var msg = "Failed to create server on port %d and all alternative ports: %s" % [host_port, error_string(result)]
		connection_failed.emit(msg)
		print("[MultiplayerSessionManager] ERROR: %s" % msg)
		return false
	
	print("[MultiplayerSessionManager] ENet server created successfully on port %d" % host_port)
	_multiplayer.multiplayer_peer = enet_peer
	print("[MultiplayerSessionManager] Assigned ENet peer to MultiplayerAPI")
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
	print("[MultiplayerSessionManager] Host session created successfully. Room code: %s | Session ID: %s | Local peer ID: %d | Port: %d" % [room_code, session_id, local_peer_id, host_port])
	return true


## Join an existing multiplayer room (client only).
func join_room(host_address: String = "127.0.0.1", host_port: int = 9999, allow_localhost_retry: bool = true) -> bool:
	if session_connected:
		push_error("Already connected to a session. Call leave_room() first.")
		return false

	var candidate_addresses: Array = [host_address]
	if allow_localhost_retry and host_address != "127.0.0.1" and host_address != "localhost":
		## In debug builds, prefer localhost first for same-machine testing speed.
		if OS.is_debug_build():
			candidate_addresses = ["127.0.0.1", host_address]
		else:
			candidate_addresses.append("127.0.0.1")

	return _begin_join_attempts(candidate_addresses, host_port)

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
	_client_ping_elapsed_sec = 0.0
	_join_attempt_addresses.clear()
	_join_attempt_index = -1
	if _join_attempt_timer != null:
		_join_attempt_timer.stop()
	
	_multiplayer.multiplayer_peer = null
	session_connected = false
	is_host_peer = false
	local_peer_id = 0
	session_id = ""
	room_code = ""
	print("[MultiplayerSessionManager] Left session.")


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
		var now_ts := Time.get_unix_time_from_system()
		connected_peers[caller_id]["last_ping"] = now_ts
		if caller_id in _peer_timeout_timers:
			var timer: Timer = _peer_timeout_timers[caller_id] as Timer
			if is_instance_valid(timer):
				timer.start(disconnect_timeout_sec)


## Internal: Triggered when peer connects to multiplayer session.
func _on_peer_connected(peer_id: int) -> void:
	if peer_id == _multiplayer.get_unique_id():
		print("[MultiplayerSessionManager] Ignoring self-connection event")
		return  ## Ignore self-connection events
	
	connected_peers[peer_id] = { "joined_at": Time.get_unix_time_from_system(), "last_ping": 0 }
	connected_peers[peer_id]["last_ping"] = Time.get_unix_time_from_system()
	print("[MultiplayerSessionManager] Peer %d connected. Total peers now: %s" % [peer_id, connected_peers.keys()])
	peer_connected.emit(peer_id)
	
	if is_host_peer:
		_set_up_timeout_timer_for_peer(peer_id)
		print("[MultiplayerSessionManager] Host set up timeout for peer %d" % peer_id)


## Internal: Triggered when peer disconnects from multiplayer session.
func _on_peer_disconnected(peer_id: int) -> void:
	connected_peers.erase(peer_id)
	peer_disconnected.emit(peer_id)
	print("[MultiplayerSessionManager] Peer %d disconnected." % peer_id)
	
	if peer_id in _peer_timeout_timers:
		var timer: Timer = _peer_timeout_timers[peer_id] as Timer
		if is_instance_valid(timer):
			timer.queue_free()
		_peer_timeout_timers.erase(peer_id)


## Internal: Triggered when client successfully connects to server.
func _on_connected_to_server() -> void:
	print("[MultiplayerSessionManager] === CLIENT CONNECTED TO SERVER ===")
	if _join_attempt_timer != null:
		_join_attempt_timer.stop()
	_join_attempt_addresses.clear()
	_join_attempt_index = -1
	local_peer_id = _multiplayer.get_unique_id()
	print("[MultiplayerSessionManager] Client connected to server as peer %d" % local_peer_id)
	
	## Client must initialize host (peer 1) in connected_peers
	if not is_host_peer:
		connected_peers[local_peer_id] = { "joined_at": Time.get_unix_time_from_system(), "last_ping": 0 }
		connected_peers[1] = { "joined_at": Time.get_unix_time_from_system(), "last_ping": 0 }  ## Host is always peer 1
		print("[MultiplayerSessionManager] Client initialized connected_peers: %s" % [connected_peers.keys()])
		_client_ping_elapsed_sec = ping_interval_sec
	
	session_joined.emit(session_id)
	print("[MultiplayerSessionManager] Client emitting session_joined signal. session_id=%s" % session_id)


## Internal: Triggered when client fails to connect.
func _on_connection_failed() -> void:
	if _join_attempt_index >= 0:
		if _join_attempt_index + 1 < _join_attempt_addresses.size():
			print("[MultiplayerSessionManager] Join attempt to %s failed. Trying next address..." % [str(_join_attempt_addresses[_join_attempt_index])])
			_advance_join_attempt()
			return

		## No more candidates; clear attempt state and emit terminal failure.
		_join_attempt_addresses.clear()
		_join_attempt_index = -1
		if _join_attempt_timer != null:
			_join_attempt_timer.stop()

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

	var now_ts := Time.get_unix_time_from_system()
	var last_ping_ts := float(connected_peers[peer_id].get("last_ping", 0.0))
	if (now_ts - last_ping_ts) < disconnect_timeout_sec:
		if peer_id in _peer_timeout_timers:
			var timer: Timer = _peer_timeout_timers[peer_id] as Timer
			if is_instance_valid(timer):
				timer.start(disconnect_timeout_sec)
		return
	
	push_error("[MultiplayerSessionManager] Peer %d timeout (no heartbeat)." % peer_id)
	peer_timeout.emit(peer_id)


func _is_client_connected_to_host() -> bool:
	if _multiplayer == null:
		return false
	var peer: MultiplayerPeer = _multiplayer.multiplayer_peer
	if peer == null:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _begin_join_attempts(addresses: Array, host_port: int) -> bool:
	_join_attempt_addresses.clear()
	for candidate in addresses:
		var addr := String(candidate).strip_edges()
		if addr.is_empty():
			continue
		if not _join_attempt_addresses.has(addr):
			_join_attempt_addresses.append(addr)

	if _join_attempt_addresses.is_empty():
		connection_failed.emit("No valid host addresses to connect to.")
		return false

	_join_attempt_port = host_port
	_join_attempt_index = -1
	return _advance_join_attempt()


func _advance_join_attempt() -> bool:
	if _multiplayer != null:
		_multiplayer.multiplayer_peer = null
	session_connected = false

	_join_attempt_index += 1
	if _join_attempt_index < 0 or _join_attempt_index >= _join_attempt_addresses.size():
		return false

	var host_address := String(_join_attempt_addresses[_join_attempt_index])
	var enet_peer := ENetMultiplayerPeer.new()
	var result := enet_peer.create_client(host_address, _join_attempt_port)
	if result != OK:
		print("[MultiplayerSessionManager] Failed to start join attempt to %s:%d (%s)" % [host_address, _join_attempt_port, error_string(result)])
		return _advance_join_attempt()

	_multiplayer.multiplayer_peer = enet_peer
	session_connected = true
	is_host_peer = false
	print("[MultiplayerSessionManager] Assigned ENet client peer to MultiplayerAPI. Connecting to %s:%d..." % [host_address, _join_attempt_port])

	if _join_attempt_timer != null:
		_join_attempt_timer.start(join_attempt_timeout_sec)
	return true


func _on_join_attempt_timeout() -> void:
	if _join_attempt_index < 0:
		return
	if _is_client_connected_to_host():
		return

	if _join_attempt_index + 1 < _join_attempt_addresses.size():
		print("[MultiplayerSessionManager] Join attempt to %s timed out. Trying next address..." % [str(_join_attempt_addresses[_join_attempt_index])])
		_advance_join_attempt()
		return

	## Final attempt timed out; fail and surface error.
	_join_attempt_addresses.clear()
	_join_attempt_index = -1
	if _multiplayer != null:
		_multiplayer.multiplayer_peer = null
	session_connected = false
	connection_failed.emit("Connection timed out while joining room.")


## Internal: Generate a random alphanumeric code.
func _generate_random_code(length: int) -> String:
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var result := ""
	for i in range(length):
		result += chars[randi() % chars.length()]
	return result
