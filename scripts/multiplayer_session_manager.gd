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
signal host_left

## Godot ENet convention: server/host peer is always assigned ID 1.
const HOST_PEER_ID: int = 1

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
var join_attempt_timeout_sec: float = 120.0
var local_join_attempt_timeout_sec: float = 120.0
var room_heartbeat_interval_sec: float = 20.0

## State for a single in-progress join attempt sequence.
class JoinAttemptState:
	var addresses: Array = []
	var port: int = 7777
	var index: int = -1
	var timer: Timer = null

	## Returns true when an attempt is still in progress.
	func is_active() -> bool:
		return index >= 0 and index < addresses.size()

	## Clear attempt state (but keep timer node alive).
	func reset() -> void:
		addresses.clear()
		index = -1
		if timer != null:
			timer.stop()


## Internal state
var _multiplayer: MultiplayerAPI
var _peer_timeout_timers: Dictionary = {}  ## peer_id -> Timer node
var _client_ping_elapsed_sec: float = 0.0
var _host_room_heartbeat_elapsed_sec: float = 0.0
var _room_heartbeat_in_flight: bool = false
var _room_heartbeat_failure_count: int = 0
var _room_heartbeat_retry_timer: float = 0.0
var _join: JoinAttemptState = JoinAttemptState.new()
var _upnp_mapped_port: int = 0
var _last_host_connectivity_warning: String = ""
var _host_public_ip: String = ""
var _host_local_ip: String = ""
var _upnp_discovery_result: int = -1
var _debug_log_file: String = "user://_multiplayer_debug.log"


func _ready() -> void:
	_multiplayer = get_tree().get_multiplayer()
	_debug_log("[SESSION_MGR] _ready() called")
	_debug_log("[SESSION_MGR] Log file location: user://_multiplayer_debug.log")
	print("[MultiplayerSessionManager] _ready() called. Connecting to MultiplayerAPI signals...")
	_multiplayer.peer_connected.connect(_on_peer_connected)
	print("[MultiplayerSessionManager] Connected: peer_connected signal")
	_debug_log("[SESSION_MGR] Connected peer_connected signal")
	_multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[MultiplayerSessionManager] Connected: peer_disconnected signal")
	_multiplayer.connected_to_server.connect(_on_connected_to_server)
	print("[MultiplayerSessionManager] Connected: connected_to_server signal")
	_debug_log("[SESSION_MGR] Hooked connected_to_server signal")
	_multiplayer.connection_failed.connect(_on_connection_failed)
	print("[MultiplayerSessionManager] Connected: connection_failed signal")
	_debug_log("[SESSION_MGR] Hooked connection_failed signal")
	_multiplayer.server_disconnected.connect(_on_server_disconnected)
	print("[MultiplayerSessionManager] Connected: server_disconnected signal")
	print("[MultiplayerSessionManager] === ALL SIGNALS CONNECTED ===")
	_join.timer = Timer.new()
	_join.timer.one_shot = true
	_join.timer.timeout.connect(_on_join_attempt_timeout)
	add_child(_join.timer)
	set_process(true)
	_debug_log("[SESSION_MGR] _ready() completed successfully")


func _process(delta: float) -> void:
	if not session_connected:
		return

	if is_host_peer:
		_process_host_room_heartbeat(delta)
		return

	if not _is_client_connected_to_host():
		return

	_client_ping_elapsed_sec += delta
	if _client_ping_elapsed_sec < ping_interval_sec:
		return

	_client_ping_elapsed_sec = 0.0
	_network_ping.rpc_id(HOST_PEER_ID)


func _process_host_room_heartbeat(delta: float) -> void:
	if not session_connected or not is_host_peer:
		return
	if room_code.is_empty():
		return

	if _room_heartbeat_in_flight:
		return

	## Handle retry timer for failed heartbeats: attempt retry after 5 seconds
	if _room_heartbeat_failure_count > 0:
		_room_heartbeat_retry_timer += delta
		if _room_heartbeat_retry_timer < 5.0:
			return
		_room_heartbeat_retry_timer = 0.0
		_debug_log("[SESSION_MGR] Retrying failed room heartbeat (failure count: %d)" % _room_heartbeat_failure_count)
	else:
		_host_room_heartbeat_elapsed_sec += delta
		if _host_room_heartbeat_elapsed_sec < room_heartbeat_interval_sec:
			return
		_host_room_heartbeat_elapsed_sec = 0.0

	_room_heartbeat_in_flight = true
	_send_room_heartbeat()


func _send_room_heartbeat() -> void:
	var room_service = get_node_or_null("/root/MultiplayerRoomService")
	if room_service == null or not room_service.has_method("heartbeat_room_registration"):
		_room_heartbeat_in_flight = false
		_room_heartbeat_failure_count += 1
		return

	var heartbeat_result: Dictionary = await room_service.heartbeat_room_registration(room_code)
	if not bool(heartbeat_result.get("ok", false)):
		_room_heartbeat_failure_count += 1
		var error_msg := String(heartbeat_result.get("message", "unknown_error"))
		_debug_log(
			"[SESSION_MGR] Room heartbeat FAILED for %s (attempt %d): %s" % [
				room_code,
				_room_heartbeat_failure_count,
				error_msg
			]
		)
		print("[MultiplayerSessionManager] WARNING: Room heartbeat failed - players may not be able to join. Error: %s" % error_msg)
		if _room_heartbeat_failure_count >= 3:
			print("[MultiplayerSessionManager] CRITICAL: Room heartbeat failing repeatedly. Check network connection and room registry endpoint.")
	else:
		if _room_heartbeat_failure_count > 0:
			_debug_log("[SESSION_MGR] Room heartbeat recovered after %d failures" % _room_heartbeat_failure_count)
			print("[MultiplayerSessionManager] Room heartbeat recovered - players can join again.")
		_room_heartbeat_failure_count = 0

	_room_heartbeat_in_flight = false


## Check if ENet client is actually connected to host (for diagnostics)
func _is_client_actually_connected() -> bool:
	if not session_connected or is_host_peer:
		return false
	var peer := _multiplayer.multiplayer_peer
	if peer == null:
		return false
	if not peer is ENetMultiplayerPeer:
		return false
	var enet_peer := peer as ENetMultiplayerPeer
	var state := enet_peer.get_connection_status()
	_debug_log("[DIAG] ENet connection state: %d (0=DISCONNECTED, 2=CONNECTED)" % state)
	return state == MultiplayerPeer.CONNECTION_CONNECTED


## Create a new multiplayer room (host only).
## Returns: room_code for other players to join
func create_room() -> String:
	if has_active_session_state():
		leave_room()
	if has_active_session_state():
		push_error("Already connected to a session. Call leave_room() first.")
		return ""
	var registration := {
		"room_code": _generate_random_code(6).to_upper(),
		"session_id": "mp-session-%d-%s" % [Time.get_unix_time_from_system(), _generate_random_code(4)],
		"host_port": 7777,
		"transport_type": "direct_enet"
	}
	if not create_registered_room(registration):
		return ""
	return room_code

func create_registered_room(room_registration: Dictionary) -> bool:
	if has_active_session_state():
		print("[MultiplayerSessionManager] WARNING: Existing session state detected before hosting. Cleaning up...")
		leave_room()
	if has_active_session_state():
		var msg = "Already connected to a session. Call leave_room() first."
		push_error(msg)
		print("[MultiplayerSessionManager] ERROR: %s" % msg)
		return false

	var host_port := int(room_registration.get("host_port", 7777))
	var transport_type := String(room_registration.get("transport_type", "direct_enet"))
	print("[MultiplayerSessionManager] Attempting to create host server on port %d with transport: %s" % [host_port, transport_type])
	_last_host_connectivity_warning = ""
	_room_heartbeat_failure_count = 0
	_room_heartbeat_retry_timer = 0.0
	
	if transport_type != "direct_enet":
		var msg = "Unsupported transport type: %s" % transport_type
		connection_failed.emit(msg)
		print("[MultiplayerSessionManager] ERROR: %s" % msg)
		return false

	var enet_peer := ENetMultiplayerPeer.new()
	print("[MultiplayerSessionManager] Created ENetMultiplayerPeer. Attempting create_server(port=%d)..." % host_port)
	var result := enet_peer.create_server(host_port)
	
	## Registered rooms must keep the advertised port stable.
	if result != OK:
		var msg = "Failed to create server on required port %d: %s" % [host_port, error_string(result)]
		connection_failed.emit(msg)
		print("[MultiplayerSessionManager] ERROR: %s" % msg)
		return false
	
	print("[MultiplayerSessionManager] ENet server created successfully on port %d" % host_port)
	var upnp_result := _try_open_upnp_port_mapping(host_port)
	if not bool(upnp_result.get("ok", false)):
		_last_host_connectivity_warning = String(upnp_result.get("message", ""))
		if not _last_host_connectivity_warning.is_empty():
			print("[MultiplayerSessionManager] WARNING: %s" % _last_host_connectivity_warning)
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
	_host_public_ip = String(room_registration.get("host_address", "")).strip_edges()
	_host_local_ip = _get_local_ip()
	connected_peers[local_peer_id] = { "joined_at": Time.get_unix_time_from_system(), "last_ping": 0 }
	session_created.emit(session_id, room_code)
	print("[MultiplayerSessionManager] Host session created successfully. Room code: %s | Session ID: %s | Local peer ID: %d | Port: %d | Local IP: %s | Public IP: %s" % [room_code, session_id, local_peer_id, host_port, _host_local_ip, _host_public_ip])
	return true


## Join an existing multiplayer room (client only).
func join_room(host_address: String = "127.0.0.1", host_port: int = 7777, allow_localhost_retry: bool = true) -> bool:
	if has_active_session_state():
		print("[MultiplayerSessionManager] WARNING: Existing session state detected before join. Cleaning up...")
		leave_room()
	if has_active_session_state():
		push_error("Already connected to a session. Call leave_room() first.")
		return false
	if session_id.is_empty():
		session_id = "mp-session-%d-%s" % [Time.get_unix_time_from_system(), _generate_random_code(4)]
	if room_code.is_empty():
		room_code = _generate_random_code(6).to_upper()

	var candidate_addresses: Array = [host_address]
	if allow_localhost_retry and host_address != "127.0.0.1" and host_address != "localhost":
		## Only add localhost fallback in editor/debug runs for same-machine testing.
		## Exported multiplayer joins should never silently retry localhost.
		if OS.is_debug_build():
			candidate_addresses = ["127.0.0.1", host_address]

	return _begin_join_attempts(candidate_addresses, host_port)

func join_registered_room(room_registration: Dictionary) -> bool:
	_debug_log("[JOIN] join_registered_room() called with registration: %s" % str(room_registration))
	var transport_type := String(room_registration.get("transport_type", "direct_enet"))
	if transport_type != "direct_enet":
		connection_failed.emit("Unsupported transport type: %s" % transport_type)
		return false
	var host_address := String(room_registration.get("host_address", "")).strip_edges()
	var host_port := int(room_registration.get("host_port", 7777))
	if host_address.is_empty():
		connection_failed.emit("Room registration is missing host address.")
		return false
	session_id = String(room_registration.get("session_id", "")).strip_edges()
	room_code = String(room_registration.get("room_code", "")).strip_edges().to_upper()
	_debug_log("[JOIN] Resolved: session_id=%s room_code=%s host=%s:%d" % [session_id, room_code, host_address, host_port])
	return join_room(host_address, host_port)


## Leave current session and disconnect.
func leave_room() -> void:
	if not has_active_session_state():
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
	_host_room_heartbeat_elapsed_sec = 0.0
	_room_heartbeat_in_flight = false
	_room_heartbeat_failure_count = 0
	_room_heartbeat_retry_timer = 0.0
	_join.reset()
	_release_upnp_port_mapping()
	
	_multiplayer.multiplayer_peer = null
	session_connected = false
	is_host_peer = false
	local_peer_id = 0
	session_id = ""
	room_code = ""
	print("[MultiplayerSessionManager] Left session.")


func get_last_host_connectivity_warning() -> String:
	return _last_host_connectivity_warning


func get_host_room_heartbeat_status() -> Dictionary:
	return {
		"is_connected": session_connected,
		"is_host": is_host_peer,
		"failure_count": _room_heartbeat_failure_count,
		"is_healthy": _room_heartbeat_failure_count == 0,
		"warning_message": _get_heartbeat_warning_message()
	}


func _get_heartbeat_warning_message() -> String:
	if _room_heartbeat_failure_count == 0:
		return ""
	if _room_heartbeat_failure_count == 1:
		return "⚠ Room registration unstable (1 failed heartbeat) - may affect joinability"
	if _room_heartbeat_failure_count < 3:
		return "⚠ Room registration at risk (%d failed heartbeats) - players may not be able to join" % _room_heartbeat_failure_count
	return "❌ Room registration critical (%d failed heartbeats) - room is likely unreachable. Check internet connection and room registry endpoint." % _room_heartbeat_failure_count


func get_connection_state_debug() -> String:
	var state = "=== CONNECTION STATE DEBUG ===\n"
	state += "session_connected: %s\n" % session_connected
	state += "is_host_peer: %s\n" % is_host_peer
	state += "local_peer_id: %d\n" % local_peer_id
	state += "session_id: %s\n" % session_id
	state += "room_code: %s\n" % room_code
	state += "connected_peers: %s\n" % str(connected_peers.keys())
	state += "multiplayerapi connected: %s\n" % (_multiplayer.is_server() or _multiplayer.is_client())
	state += "multiplayerapi is_server: %s\n" % _multiplayer.is_server()
	state += "multiplayerapi is_client: %s\n" % _multiplayer.is_client()
	
	if _multiplayer.multiplayer_peer != null:
		state += "multiplayer_peer: %s\n" % _multiplayer.multiplayer_peer.get_class()
		if _multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			var enet := _multiplayer.multiplayer_peer as ENetMultiplayerPeer
			state += "enet_status: %s\n" % enet.get_connection_status()
	else:
		state += "multiplayer_peer: null\n"
	
	return state


func get_host_diagnostic_report() -> String:
	var report := "=== MULTIPLAYER HOST DIAGNOSTICS ===\n"
	report += "Session connected: %s\n" % session_connected
	report += "Is host: %s\n" % is_host_peer
	report += "Local peer ID: %d\n" % local_peer_id
	report += "Room code: %s\n" % room_code
	report += "Host port: 7777\n"
	report += "Local IP: %s\n" % _host_local_ip
	report += "Public IP (registered): %s\n" % _host_public_ip
	report += "UPnP discovery result: %d (0=SUCCESS, 1=ERROR, 2=NOT_IMPLEM)\n" % _upnp_discovery_result
	report += "UPnP mapped port: %d\n" % _upnp_mapped_port
	report += "Room heartbeat failures: %d\n" % _room_heartbeat_failure_count
	if not _last_host_connectivity_warning.is_empty():
		report += "Connectivity warning: %s\n" % _last_host_connectivity_warning
	var hb_warning := _get_heartbeat_warning_message()
	if not hb_warning.is_empty():
		report += "Heartbeat status: %s\n" % hb_warning
	return report


## Creates a UPNP instance and runs discovery. Returns the UPNP object if a valid gateway
## was found, or null on failure. Stores the discovery result code for diagnostics.
func _create_upnp_with_gateway(timeout_msec: int = 2000) -> UPNP:
	var upnp := UPNP.new()
	var discover_result := upnp.discover(timeout_msec, 2, "InternetGatewayDevice")
	_upnp_discovery_result = discover_result
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		return null
	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return null
	return upnp


func _try_open_upnp_port_mapping(port: int) -> Dictionary:
	if port <= 0:
		return {
			"ok": false,
			"message": "Invalid host port for automatic router mapping."
		}
	print("[MultiplayerSessionManager] Attempting UPnP discovery...")
	var upnp := _create_upnp_with_gateway(2000)
	print("[MultiplayerSessionManager] UPnP discovery result: %d (0=SUCCESS, 1=ERROR, 2=NOT_IMPLEM)" % _upnp_discovery_result)
	if upnp == null:
		if _upnp_discovery_result != UPNP.UPNP_RESULT_SUCCESS:
			return {
				"ok": false,
				"message": "UPnP discovery failed (result=%d). Router may not support UPnP or is disabled. Manual port forwarding required: forward UDP %d to this host." % [_upnp_discovery_result, port]
			}
		return {
			"ok": false,
			"message": "UPnP gateway validation failed. Router UPnP may be misconfigured. Manual port forwarding required: forward UDP %d to this host." % [port]
		}
	print("[MultiplayerSessionManager] UPnP gateway found, attempting port mapping for UDP %d..." % port)
	var add_result := upnp.add_port_mapping(port, port, "godot-2026", "UDP", 0)
	print("[MultiplayerSessionManager] UPnP port mapping result: %d (0=SUCCESS, 1=ERROR, 2=NOT_IMPLEM)" % add_result)
	if add_result != UPNP.UPNP_RESULT_SUCCESS:
		return {
			"ok": false,
			"message": "Router rejected UDP %d mapping (result=%d). Manual port forwarding required: forward UDP %d to this host." % [port, add_result, port]
		}
	_upnp_mapped_port = port
	print("[MultiplayerSessionManager] UPnP port mapping succeeded for UDP %d" % port)
	return {
		"ok": true,
		"message": ""
	}


func _release_upnp_port_mapping() -> void:
	if _upnp_mapped_port <= 0:
		return
	var upnp := _create_upnp_with_gateway(1000)
	if upnp != null:
		upnp.delete_port_mapping(_upnp_mapped_port, "UDP")
	_upnp_mapped_port = 0


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


func has_active_session_state() -> bool:
	if session_connected:
		return true
	if _multiplayer != null and _multiplayer.multiplayer_peer != null:
		return true
	if not connected_peers.is_empty():
		return true
	if not session_id.is_empty() or not room_code.is_empty():
		return true
	return false


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
	_debug_log("[SIGNAL] _on_peer_connected() FIRED for peer %d" % peer_id)
	if peer_id == _multiplayer.get_unique_id():
		print("[MultiplayerSessionManager] Ignoring self-connection event")
		return  ## Ignore self-connection events
	
	connected_peers[peer_id] = { "joined_at": Time.get_unix_time_from_system(), "last_ping": 0 }
	connected_peers[peer_id]["last_ping"] = Time.get_unix_time_from_system()
	print("[MultiplayerSessionManager] Peer %d connected. Total peers now: %s" % [peer_id, connected_peers.keys()])
	_debug_log("[HOST] Peer %d connected" % peer_id)
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
	if session_id.is_empty():
		session_id = "mp-session-%d-%s" % [Time.get_unix_time_from_system(), _generate_random_code(4)]
	if room_code.is_empty():
		room_code = _generate_random_code(6).to_upper()
	session_connected = true
	is_host_peer = false
	_debug_log("[SIGNAL] === _on_connected_to_server() FIRED ===")
	_debug_log("[STATE] session_id='%s' room_code='%s'" % [session_id, room_code])
	push_error("[MULTIPLAYER DEBUG] === CLIENT CONNECTED TO SERVER === (This should print visibly)")
	print("[MultiplayerSessionManager] === CLIENT CONNECTED TO SERVER ===")
	_join.reset()
	local_peer_id = _multiplayer.get_unique_id()
	push_error("[MULTIPLAYER DEBUG] Client connected as peer %d" % local_peer_id)
	print("[MultiplayerSessionManager] Client connected to server as peer %d" % local_peer_id)
	_debug_log("[CLIENT] Connected as peer %d" % local_peer_id)
	
	## Client must initialize host in connected_peers.
	## In Godot ENet multiplayer, the server/host is always assigned peer ID 1.
	if not is_host_peer:
		connected_peers[local_peer_id] = { "joined_at": Time.get_unix_time_from_system(), "last_ping": 0 }
		var host_peer_id := HOST_PEER_ID
		connected_peers[host_peer_id] = { "joined_at": Time.get_unix_time_from_system(), "last_ping": 0 }
		print("[MultiplayerSessionManager] Client initialized connected_peers: %s" % [connected_peers.keys()])
		_client_ping_elapsed_sec = ping_interval_sec
	
	print("[MultiplayerSessionManager] Client about to emit session_joined with session_id='%s'" % session_id)
	_debug_log("[CLIENT] About to emit session_joined with session_id='%s'" % session_id)
	
	if session_id.is_empty():
		_debug_log("[ERROR] session_id is EMPTY! Cannot emit valid signal!")
		push_error("[MULTIPLAYER DEBUG] ERROR: session_id is empty - signal will have empty string!")
	
	push_error("[MULTIPLAYER DEBUG] About to emit session_joined signal with session_id: %s" % session_id)
	session_joined.emit(session_id)
	_debug_log("[CLIENT] session_joined signal emitted successfully with session_id='%s'" % session_id)
	push_error("[MULTIPLAYER DEBUG] session_joined signal emitted successfully")
	print("[MultiplayerSessionManager] Client successfully emitted session_joined signal")


## Internal: Triggered when client fails to connect.
func _on_connection_failed() -> void:
	_debug_log("[SIGNAL] _on_connection_failed() FIRED - Connection failed!")
	if _join.is_active():
		if _join.index + 1 < _join.addresses.size():
			print("[MultiplayerSessionManager] Join attempt to %s failed. Trying next address..." % [str(_join.addresses[_join.index])])
			_advance_join_attempt()
			return

		## No more candidates; clear attempt state and emit terminal failure.
		_join.reset()

	if _multiplayer != null:
		_multiplayer.multiplayer_peer = null
	session_connected = false
	is_host_peer = false
	local_peer_id = 0
	push_error("[MultiplayerSessionManager] Connection failed.")
	connection_failed.emit("Connection failed to server.")


## Internal: Triggered when server is shut down (only for clients).
func _on_server_disconnected() -> void:
	push_error("[MultiplayerSessionManager] Server disconnected.")
	host_left.emit()
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
	_debug_log("[JOIN] _begin_join_attempts() called with addresses: %s port: %d" % [str(addresses), host_port])
	connected_peers.clear()
	local_peer_id = 0
	_join.addresses.clear()
	for candidate in addresses:
		var addr := String(candidate).strip_edges()
		if addr.is_empty():
			continue
		if not _join.addresses.has(addr):
			_join.addresses.append(addr)

	if _join.addresses.is_empty():
		connection_failed.emit("No valid host addresses to connect to.")
		_debug_log("[JOIN] ERROR: No valid addresses provided")
		return false

	_join.port = host_port
	_join.index = -1
	_debug_log("[JOIN] Starting join attempts with %d candidate addresses" % _join.addresses.size())
	return _advance_join_attempt()


func _advance_join_attempt() -> bool:
	if _multiplayer != null:
		_multiplayer.multiplayer_peer = null
	session_connected = false
	is_host_peer = false

	_join.index += 1
	if _join.index < 0 or _join.index >= _join.addresses.size():
		_debug_log("[JOIN] No more addresses to try. Join failed.")
		return false

	var host_address := String(_join.addresses[_join.index])
	_debug_log("[JOIN] Creating ENet client for %s:%d (attempt %d/%d)" % [host_address, _join.port, _join.index + 1, _join.addresses.size()])
	var enet_peer := ENetMultiplayerPeer.new()
	print("[MultiplayerSessionManager] Attempting to create ENet client to %s:%d (attempt %d/%d)" % [host_address, _join.port, _join.index + 1, _join.addresses.size()])
	var result := enet_peer.create_client(host_address, _join.port)
	if result != OK:
		var error_msg := error_string(result)
		_debug_log("[JOIN] ENet create_client FAILED: %s (code %d)" % [error_msg, result])
		print("[MultiplayerSessionManager] ENet create_client FAILED for %s:%d with error: %s (code %d)" % [host_address, _join.port, error_msg, result])
		if host_address != "127.0.0.1" and host_address != "localhost":
			print("[MultiplayerSessionManager]   Internet address %s unreachable. Likely causes: DNS failed, host firewall blocked, router not forwarding UDP %d, CGNAT blocking, or ISP restrictions." % [host_address, _join.port])
		return _advance_join_attempt()

	_multiplayer.multiplayer_peer = enet_peer
	is_host_peer = false
	_debug_log("[JOIN] ENet client created successfully. Waiting for connection signal...")
	print("[MultiplayerSessionManager] ENet client created and waiting for connection to %s:%d. Timeout: %.0fs" % [host_address, _join.port, _get_join_timeout_for_address(host_address)])

	if _join.timer != null:
		var timeout_sec := _get_join_timeout_for_address(host_address)
		print("[MultiplayerSessionManager] Join timeout for %s:%d set to %.2fs" % [host_address, _join.port, timeout_sec])
		_join.timer.start(timeout_sec)
	return true


func _on_join_attempt_timeout() -> void:
	if not _join.is_active():
		return
	if _is_client_connected_to_host():
		return
	var timed_out_address := str(_join.addresses[_join.index]) if _join.is_active() else "unknown-host"
	print("[MultiplayerSessionManager] Join timeout at address %s:%d after %.1f seconds" % [timed_out_address, _join.port, join_attempt_timeout_sec])

	if _join.index + 1 < _join.addresses.size():
		print("[MultiplayerSessionManager] Join attempt to %s timed out. Trying next address..." % [str(_join.addresses[_join.index])])
		_advance_join_attempt()
		return

	## Final attempt timed out; fail and surface error.
	_join.reset()
	if _multiplayer != null:
		_multiplayer.multiplayer_peer = null
	session_connected = false
	is_host_peer = false
	local_peer_id = 0
	connection_failed.emit(
		"Connection timed out while joining room (%s:%d). Host must allow inbound UDP %d (port-forward or UPnP). If forwarding is configured and it still fails, host ISP may be behind CGNAT." % [timed_out_address, _join.port, _join.port]
	)


func _get_join_timeout_for_address(host_address: String) -> float:
	var normalized := host_address.strip_edges().to_lower()
	if normalized == "127.0.0.1" or normalized == "localhost":
		return local_join_attempt_timeout_sec
	return join_attempt_timeout_sec


## Internal: Generate a random alphanumeric code.
func _generate_random_code(length: int) -> String:
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var result := ""
	for i in range(length):
		result += chars[randi() % chars.length()]
	return result


## Internal: Get the local (LAN) IP address of this host.
func _get_local_ip() -> String:
	var local_ip := IP.get_local_addresses()
	for ip in local_ip:
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	## Fallback to first non-localhost IP
	for ip in local_ip:
		if not ip.begins_with("127."):
			return ip
	return "127.0.0.1"


## Internal: Write debug message to file for exported builds
func _debug_log(message: String) -> void:
	var timestamp = Time.get_ticks_msec() / 1000.0
	var line = "[%.3f] %s\n" % [timestamp, message]
	
	var file = FileAccess.open(_debug_log_file, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(_debug_log_file, FileAccess.WRITE)
	
	if file != null:
		file.seek_end()
		file.store_string(line)
	else:
		print("[MultiplayerSessionManager] WARNING: Could not open debug log file at %s" % _debug_log_file)
