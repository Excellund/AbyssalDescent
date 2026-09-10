extends SceneTree
## Native menu join/cancel callbacks over isolated loopback ENet. Only room
## discovery and the downstream lobby-opening boundary are fixture seams.

class LocalRooms extends "res://scripts/multiplayer_room_service.gd":
	var port := 7777
	var address := "127.0.0.1"
	func get_configuration_issues() -> PackedStringArray:
		return PackedStringArray()
	func resolve_room_code(code: String) -> Dictionary:
		return {"ok": true, "registration": {"transport_type": "direct_enet", "host_address": address, "host_port": port, "room_code": code, "session_id": "loopback-" + code}}

class TrackedSession extends "res://scripts/multiplayer_session_manager.gd":
	var registered_joins := 0
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func join_registered_room(registration: Dictionary) -> bool:
		registered_joins += 1
		return super.join_registered_room(registration)

class FixtureMenu extends "res://scripts/menu_controller.gd":
	var lobbies_opened := 0
	func _ready() -> void:
		root_panel = Panel.new()
		add_child(root_panel)
		multiplayer_panel = _build_multiplayer_panel()
		add_child(multiplayer_panel)
		lobby_modal_layer = Control.new()
		lobby_modal_layer.visible = false
		add_child(lobby_modal_layer)
	func _show_lobby_modal() -> void:
		# Observe the actual successful caller boundary without starting lobby
		# discovery, heartbeat or gameplay protocols against the raw ENet host.
		lobbies_opened += 1
		root_panel.visible = false
		multiplayer_panel.visible = false
		lobby_modal_layer.visible = true

var role: String
var prefix: String
var checks := 0
var failures: Array[String] = []
var expected_injected_failures: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _until(predicate: Callable, seconds: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func _write(key: String, value: Variant = true) -> void:
	var file := FileAccess.open(prefix + "-" + key, FileAccess.WRITE)
	file.store_var(value)
	file.close()

func _has(key: String) -> bool:
	return FileAccess.file_exists(prefix + "-" + key)

func _callbacks() -> int:
	return MultiplayerSessionManager.session_joined.get_connections().size() + MultiplayerSessionManager.connection_failed.get_connections().size()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or args.size() != 4:
		quit(1)
		return
	role = args[1]
	prefix = args[3]
	RunContext.telemetry_upload_enabled = false
	if role == "host":
		await _host(int(args[2]))
	else:
		await _client(int(args[2]))
	var report := FileAccess.open(prefix + "-" + role + ".json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "expected_injected_failures": expected_injected_failures}, "\t"))
	report.close()
	print("[ENet] Menu join cancellation %s: %d checks, %d failures" % [role, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _listen(port: int, polling: bool) -> ENetMultiplayerPeer:
	multiplayer_poll = polling
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	check(peer.create_server(port, 1) == OK, "Raw loopback host binds the isolated port")
	get_multiplayer().multiplayer_peer = peer
	return peer

func _host(port: int) -> void:
	var peer := _listen(port, true)
	_write("ready")
	check(await _until(func(): return _has("normal-done")), "Client completes ordinary native join success")
	for navigation in ["escape", "back"]:
		peer.close()
		get_multiplayer().multiplayer_peer = null
		peer = _listen(port, false)
		_write("pending-" + navigation)
		check(await _until(func(): return _has("rejoin-started-" + navigation)), "Client cancels the unpolled join and starts a fresh one: " + navigation)
		# Retire the intentionally unpolled half-open handshake. The new client
		# then completes its ordinary ENet retry/connected_to_server callback.
		peer.close()
		get_multiplayer().multiplayer_peer = null
		peer = _listen(port, true)
		check(await _until(func(): return _has("rejoin-done-" + navigation)), "Fresh join survives the canceled continuation: " + navigation)
	peer.close()
	get_multiplayer().multiplayer_peer = null
	peer = _listen(port, false)
	_write("timeout-ready")
	check(await _until(func(): return _has("timeout-done")), "Client completes short native waiter timeout and cleanup")
	peer.close()
	get_multiplayer().multiplayer_peer = null

func _open_form(menu: FixtureMenu) -> void:
	# Stage the settled form; Back/Escape still use their real UI handlers.
	menu.multiplayer_panel.visible = true
	menu.root_panel.visible = false
	menu.lobby_modal_layer.visible = false
	menu.multiplayer_status_label.text = ""

func _navigate_back(menu: FixtureMenu, navigation: String) -> void:
	if navigation == "escape":
		var event := InputEventAction.new()
		event.action = "ui_cancel"
		event.pressed = true
		menu._unhandled_input(event)
		return
	for node in menu.multiplayer_panel.find_children("*", "Button", true, false):
		if node.text == "Back":
			node.pressed.emit()
			return
	check(false, "Native multiplayer Back button exists")

func _client(port: int) -> void:
	MultiplayerRoomService.set_script(LocalRooms)
	MultiplayerRoomService.port = port
	var manager: Node = MultiplayerSessionManager
	manager.set_script(TrackedSession)
	manager.set_process(false)
	manager.set_physics_process(false)
	manager._multiplayer = get_multiplayer()
	manager._initialize_debug_log()
	manager._join.timer = Timer.new()
	manager._join.timer.one_shot = true
	manager.add_child(manager._join.timer)
	manager._join.timer.timeout.connect(manager._on_join_attempt_timeout)
	get_multiplayer().connected_to_server.connect(manager._on_connected_to_server)
	get_multiplayer().connection_failed.connect(manager._on_connection_failed)
	var menu := FixtureMenu.new()
	root.add_child(menu)
	var callbacks_before := _callbacks()
	_open_form(menu)
	await menu._join_multiplayer_room("NORMAL")
	check(manager.session_connected and manager.local_peer_id > 1 and menu.lobbies_opened == 1, "Native connected callback completes the real menu caller and opens its lobby boundary")
	check(manager.connected_peers.has(1) and manager.connected_peers.has(manager.local_peer_id) and not manager._join.is_active() and manager._join.timer.is_stopped(), "Normal success establishes both peer IDs and retires the native join timer")
	check(_callbacks() == callbacks_before, "Normal success removes both temporary waiter callbacks")
	menu._show_root_panel(false)
	check(manager.session_connected, "Navigation after accepted success cannot cancel the transferred session")
	manager.leave_room()
	_write("normal-done")
	for navigation in ["escape", "back"]:
		check(await _until(func(): return _has("pending-" + navigation)), "Raw host is unpolled for deterministic pending navigation: " + navigation)
		_open_form(menu)
		var lobbies_before := menu.lobbies_opened
		var joins_before: int = manager.registered_joins
		menu._join_multiplayer_room("CANCEL" + navigation.to_upper())
		check(await _until(func(): return manager._join.is_active() and get_multiplayer().multiplayer_peer != null and _callbacks() > callbacks_before), "Actual menu join owns a pending native transport and waiter: " + navigation)
		var canceled_peer = get_multiplayer().multiplayer_peer
		_navigate_back(menu, navigation)
		check(not manager.has_active_session_state() and get_multiplayer().multiplayer_peer == null and manager._join.timer.is_stopped() and not manager._join.is_active(), "Native navigation immediately retires its owned transport and timer: " + navigation)
		check(canceled_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED, "Cancellation closes even a retained reference to its former ENet peer: " + navigation)
		canceled_peer = null
		check(_callbacks() == callbacks_before and not menu.multiplayer_join_button.disabled, "Native navigation immediately releases both waiter listeners and Join button: " + navigation)
		if navigation == "escape":
			var status_after := menu.multiplayer_status_label.text
			await create_timer(0.35).timeout
			check(menu.root_panel.visible and not menu.multiplayer_panel.visible and not menu.lobby_modal_layer.visible and menu.lobbies_opened == lobbies_before, "Escape remains on the real root panel with no late lobby")
			check(menu.multiplayer_status_label.text == status_after and manager.registered_joins == joins_before + 1 and _callbacks() == callbacks_before and not manager.has_active_session_state(), "Canceled continuation cannot retry, rewrite UI or reacquire a peer")
		# Back starts its replacement join in the same frame, before the older
		# process_frame continuation can resume and attempt cleanup.
		_open_form(menu)
		var replacement_code := "CANCELBACK" if navigation == "back" else "FRESHESCAPE"
		menu._join_multiplayer_room(replacement_code)
		var replacement_peer = get_multiplayer().multiplayer_peer
		check(replacement_peer != null, "Replacement join acquires a fresh native peer: " + navigation)
		_write("rejoin-started-" + navigation)
		check(await _until(func(): return manager.session_connected and menu.lobbies_opened == lobbies_before + 1), "A new join completes after real cancellation: " + navigation)
		var final_status := menu.multiplayer_status_label.text
		await create_timer(0.35).timeout
		check(get_multiplayer().multiplayer_peer == replacement_peer and manager.session_connected and menu.lobby_modal_layer.visible, "Canceled continuation cannot disconnect the newer successful peer or hide its lobby: " + navigation)
		check(manager.registered_joins == joins_before + 2 and menu.lobbies_opened == lobbies_before + 1 and menu.multiplayer_status_label.text == final_status and _callbacks() == callbacks_before and manager._join.timer.is_stopped(), "Only the two intended attempts run; no late retry, lobby, UI or listener survives: " + navigation)
		if navigation == "back":
			menu.queue_free()
			await process_frame
			check(manager.session_connected and get_multiplayer().multiplayer_peer == replacement_peer and _callbacks() == callbacks_before, "Actual menu teardown preserves the accepted native session after ownership transfer")
			menu = FixtureMenu.new()
			root.add_child(menu)
		manager.leave_room()
		replacement_peer = null
		_write("rejoin-done-" + navigation)
	check(await _until(func(): return _has("timeout-ready")), "Raw host is unpolled for a short waiter timeout")
	_open_form(menu)
	# Development joins try localhost before the supplied address. Both are
	# loopback here; fire the actual timeout callback to advance the sequence.
	MultiplayerRoomService.address = "127.0.0.2"
	menu._join_multiplayer_room("FALLBACK")
	check(await _until(func(): return manager._join.is_active() and _callbacks() > callbacks_before), "Native candidate-address join begins with its initial peer")
	var initial_peer = get_multiplayer().multiplayer_peer
	var fallback_generation: int = manager.get_join_operation_generation()
	manager._on_join_attempt_timeout()
	var fallback_peer = get_multiplayer().multiplayer_peer
	check(manager._join.index == 1 and fallback_peer != null and fallback_peer != initial_peer and manager.get_join_operation_generation() == fallback_generation, "Existing timeout callback creates the next loopback peer within the same operation")
	_navigate_back(menu, "escape")
	check(not manager.has_active_session_state() and get_multiplayer().multiplayer_peer == null and manager._join.timer.is_stopped() and not manager._join.is_active(), "Cancel owns the replacement peer and timer within the same address sequence")
	check(fallback_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED and initial_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED and _callbacks() == callbacks_before, "Both candidate peers are closed and fallback retains no waiter listeners")
	initial_peer = null
	fallback_peer = null
	if manager.has_active_session_state():
		manager.leave_room() # Preserve teardown even when the regression fails.
	await process_frame
	MultiplayerRoomService.address = "127.0.0.1"
	_open_form(menu)
	menu._join_multiplayer_room("TERMINAL")
	check(await _until(func(): return manager._join.is_active() and _callbacks() > callbacks_before), "Native one-address join starts for terminal timeout cleanup")
	var terminal_peer = get_multiplayer().multiplayer_peer
	var terminal_generation: int = manager.get_join_operation_generation()
	var terminal_notice := {"reason": ""}
	manager.connection_failed.connect(func(reason: String): terminal_notice["reason"] = reason, CONNECT_ONE_SHOT)
	# This intentional synchronous timeout emits the existing failure diagnostic.
	# Restore error output before any await or assertion; unexpected failures and
	# the native error outcome are still checked by the fixture and its runner.
	var print_errors_before := Engine.print_error_messages
	Engine.print_error_messages = false
	manager._on_join_attempt_timeout()
	Engine.print_error_messages = print_errors_before
	var expected_terminal_reason := "Connection timed out while joining room (127.0.0.1:%d). Host must allow inbound UDP %d (port-forward or UPnP). If forwarding is configured and it still fails, host ISP may be behind CGNAT." % [port, port]
	check(get_multiplayer().multiplayer_peer == null and not manager.session_id.is_empty() and manager.get_join_operation_generation() == terminal_generation and String(terminal_notice["reason"]) == expected_terminal_reason, "Native terminal timeout reports its exact expected failure and releases the peer before caller-owned session metadata")
	expected_injected_failures.append({"phase": "native_terminal_timeout", "reason": String(terminal_notice["reason"])})
	print("[ExpectedJoinFailure] native_terminal_timeout: [JOIN DEBUG] connection_failed RECEIVED! reason=" + String(terminal_notice["reason"]))
	_navigate_back(menu, "escape")
	check(not manager.has_active_session_state() and manager.session_id.is_empty() and manager.room_code.is_empty() and manager._join.timer.is_stopped() and _callbacks() == callbacks_before, "Cancellation also clears same-attempt metadata after terminal peer release")
	check(terminal_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED, "Terminal cleanup closes the retained original transport")
	terminal_peer = null
	if manager.has_active_session_state():
		manager.leave_room()
	await process_frame
	_open_form(menu)
	var attempt := menu._begin_multiplayer_join_attempt()
	var timeout_started := Time.get_ticks_msec()
	var timed: Dictionary = await menu._await_multiplayer_join_result(manager, 0.1, "127.0.0.1", port, func(): return manager.join_room("127.0.0.1", port, false), attempt)
	check(not bool(timed.get("ok", true)) and not bool(timed.get("canceled", false)) and String(timed.get("reason", "")).begins_with("Connection timed out.") and Time.get_ticks_msec() - timeout_started >= 80 and _callbacks() == callbacks_before, "Native elapsed waiter timeout preserves failure result and disconnects temporary callbacks")
	expected_injected_failures.append({"phase": "menu_waiter_timeout", "timeout_seconds": 0.1, "reason": String(timed.get("reason", ""))})
	menu._finish_multiplayer_join_attempt(attempt, false)
	check(not manager.has_active_session_state() and get_multiplayer().multiplayer_peer == null and manager._join.timer.is_stopped(), "Owned timeout cleanup closes its transport and timer")
	menu.queue_free()
	await process_frame
	check(_callbacks() == callbacks_before, "Menu teardown retains no attempt listeners")
	_write("timeout-done")
