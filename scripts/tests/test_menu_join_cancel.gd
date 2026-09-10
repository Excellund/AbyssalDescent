extends SceneTree
## Local delayed services exercise Menu lifetime without external room services.
const MENU := preload("res://scripts/menu_controller.gd")
class Resolver extends "res://scripts/multiplayer_room_service.gd":
	var pending: Array[Dictionary] = []
	func get_configuration_issues() -> PackedStringArray:
		return PackedStringArray()
	func resolve_room_code(code: String) -> Dictionary:
		var request := {"code": code, "done": false, "result": {}}
		pending.append(request)
		while not request.done:
			await get_tree().process_frame
		return request.result
class Manager extends "res://scripts/multiplayer_session_manager.gd":
	var starts := 0
	var next_start_succeeds := true
	var immediate_success := false
	func join_registered_room(_registration: Dictionary) -> bool:
		starts += 1
		_join_operation_generation += 1
		session_id = "fixture-join-%d" % starts
		room_code = "FIXTURE"
		_multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		_join.addresses = ["127.0.0.1"]
		_join.index = 0
		_join.timer.start(120.0)
		if immediate_success:
			session_connected = true
			local_peer_id = 2
			_join.reset()
			session_joined.emit(session_id)
		return next_start_succeeds
class Menu extends MENU:
	var probes: Array[Dictionary] = []
	var lobbies := 0
	var skip_failed_join := false
	func _ready() -> void:
		root_panel = Panel.new()
		add_child(root_panel)
		multiplayer_panel = _build_multiplayer_panel()
		add_child(multiplayer_panel)
	func _run_multiplayer_join_attempt(code: String, attempt: Dictionary) -> bool:
		if skip_failed_join:
			return false # Isolate duo's outer retry timer from the inner four retries.
		return await super._run_multiplayer_join_attempt(code, attempt)
	func _show_lobby_modal() -> void:
		lobbies += 1 # Stop at the real caller's accepted-lobby boundary.
	func _probe_tunnel_reachability(_address: String, _attempt: Dictionary = {}) -> bool:
		var probe := {"done": false, "ok": true}
		probes.append(probe)
		while not probe.done:
			await get_tree().process_frame
		return probe.ok
	func probe_native(address: String, attempt: Dictionary) -> bool:
		return await super._probe_tunnel_reachability(address, attempt)
var checks := 0
var failures: Array[String] = []
var menu: Menu
var manager: Manager
var resolver: Resolver
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func _until(predicate: Callable, seconds: float = 2.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return false
func _launch(code: String, result: Dictionary) -> void:
	result["ok"] = await menu._join_multiplayer_room(code)
	result["done"] = true
func _resolve(index: int, tunnel: bool = false, ok: bool = true) -> void:
	resolver.pending[index].result = {"ok": ok, "registration": {"host_address": "wss://fixture.invalid" if tunnel else "127.0.0.1", "host_port": 1}, "message": "fixture failure"}
	resolver.pending[index].done = true
func _listeners() -> int:
	return manager.session_joined.get_connections().size() + manager.connection_failed.get_connections().size()
func _new_menu() -> void:
	menu = Menu.new()
	root.add_child(menu)
func _reset() -> void:
	if is_instance_valid(menu):
		menu._cancel_multiplayer_join_attempt()
		menu.queue_free()
	if manager.has_active_session_state():
		manager.leave_room()
	manager.next_start_succeeds = true
	manager.immediate_success = false
	await process_frame
	_new_menu()
func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	RunContext.telemetry_upload_enabled = false
	MultiplayerSessionManager.set_script(Manager)
	MultiplayerRoomService.set_script(Resolver)
	manager = root.get_node("MultiplayerSessionManager") as Manager
	resolver = root.get_node("MultiplayerRoomService") as Resolver
	manager.set_process(false)
	manager._multiplayer = get_multiplayer()
	get_multiplayer().multiplayer_peer = null
	manager._join.timer = Timer.new()
	manager._join.timer.one_shot = true
	manager.add_child(manager._join.timer)
	_new_menu()
	await _test_delayed_resolver()
	await _reset()
	await _test_delayed_probe()
	await _reset()
	await _test_waiter_and_replacement()
	await _reset()
	await _test_retry_backoff()
	await _reset()
	await _test_teardown()
	await _reset()
	await _test_native_probe_cancel()
	await _reset()
	await _test_prior_session_cleanup()
	await _reset()
	await _test_retry_reprobe()
	await _reset()
	await _test_normal_retry()
	await _reset()
	await _test_operation_replacement()
	await _reset()
	await _test_duo_cancellation()
	await _reset()
	await _test_terminal_failure()
	await _reset()
	await _test_duo_outer_backoff_and_success()
	menu._cancel_multiplayer_join_attempt()
	menu.queue_free()
	if manager.has_active_session_state(): manager.leave_room()
	await process_frame
	print("[MenuJoinCancel] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func _test_delayed_resolver() -> void:
	var start_count := manager.starts
	var old_index := resolver.pending.size()
	var old := {"done": false}
	_launch("OLD", old)
	check(resolver.pending.size() == old_index + 1 and menu.multiplayer_join_button.disabled, "Pending resolver belongs to a disabled active join")
	menu._show_root_panel(false)
	check(menu._multiplayer_join_attempt.is_empty() and not menu.multiplayer_join_button.disabled and _listeners() == 0, "Back cancels before a resolver finishes and immediately restores Join")
	var newer := {"done": false}
	_launch("NEW", newer)
	menu.multiplayer_status_label.text = "new attempt status"
	_resolve(old_index)
	check(await _until(func(): return old.done), "Canceled delayed resolver can return safely")
	check(not old.ok and manager.starts == start_count and menu.multiplayer_status_label.text == "new attempt status" and menu.multiplayer_join_button.disabled, "Old resolver cannot start transport, overwrite status, or enable the newer join")
	manager.immediate_success = true
	_resolve(old_index + 1)
	check(await _until(func(): return newer.done) and newer.ok and menu.lobbies == 1, "A new join succeeds immediately after Back")
	menu._show_root_panel(false)
	check(manager.session_connected and _listeners() == 0 and menu._multiplayer_join_attempt.is_empty(), "Root navigation preserves the accepted lobby session")
func _test_delayed_probe() -> void:
	var index := resolver.pending.size()
	var start_count := manager.starts
	var old := {"done": false}
	_launch("TUNNEL", old)
	_resolve(index, true)
	check(await _until(func(): return menu.probes.size() == 1), "Tunnel join reaches controlled delayed probe")
	menu._show_root_panel(false)
	var newer := {"done": false}
	_launch("NEW", newer)
	menu.multiplayer_status_label.text = "new lookup"
	menu.probes[0].done = true
	check(await _until(func(): return old.done), "Late canceled probe result is consumed")
	check(not old.ok and manager.starts == start_count and menu.multiplayer_status_label.text == "new lookup" and menu.multiplayer_join_button.disabled, "Old probe cannot start transport or alter its replacement's UI")
	menu._cancel_multiplayer_join_attempt()
	_resolve(index + 1)
	check(await _until(func(): return newer.done) and not newer.ok, "Replacement lookup also cancels cleanly")
func _test_waiter_and_replacement() -> void:
	var index := resolver.pending.size()
	var old := {"done": false}
	_launch("CONNECT", old)
	_resolve(index)
	check(await _until(func(): return _listeners() == 2), "Real menu waiter installs its two temporary callbacks")
	menu._show_root_panel(false)
	check(_listeners() == 0 and manager._multiplayer.multiplayer_peer == null and manager._join.timer.is_stopped() and not manager.has_active_session_state(), "Back immediately retires callbacks, owned transport, timer and session")
	var newer := {"done": false}
	manager.immediate_success = true
	_launch("REPLACEMENT", newer)
	_resolve(index + 1)
	check(await _until(func(): return newer.done and old.done), "Canceled waiter and replacement both settle")
	check(not old.ok and newer.ok and manager.session_connected and menu.lobbies == 1 and not menu.multiplayer_join_button.disabled, "Stale waiter cleanup cannot disconnect or change the accepted replacement")
	var accepted_peer: MultiplayerPeer = manager._multiplayer.multiplayer_peer
	menu.queue_free()
	await process_frame
	check(manager.session_connected and manager._multiplayer.multiplayer_peer == accepted_peer, "Menu teardown preserves an accepted lobby's peer")
func _test_retry_backoff() -> void:
	var index := resolver.pending.size()
	var start_count := manager.starts
	manager.next_start_succeeds = false
	var old := {"done": false}
	_launch("RETRY", old)
	_resolve(index)
	check(await _until(func(): return manager.starts == start_count + 1 and _listeners() == 0 and manager._multiplayer.multiplayer_peer == null), "Failed native start enters ordinary retry backoff after cleanup")
	menu._show_root_panel(false)
	manager.next_start_succeeds = true
	manager.immediate_success = true
	var newer := {"done": false}
	_launch("NEWER", newer)
	_resolve(index + 1)
	check(await _until(func(): return newer.done) and newer.ok, "Replacement can connect during old retry backoff")
	check(await _until(func(): return old.done, 4.0), "Canceled retry backoff settles when its timer returns")
	check(not old.ok and manager.starts == start_count + 2 and menu.lobbies == 1 and manager.session_connected, "Old backoff cannot retry, reopen lobby, or close the new connection")
func _test_teardown() -> void:
	var index := resolver.pending.size()
	var result := {"done": false}
	_launch("TEARDOWN", result)
	_resolve(index)
	check(await _until(func(): return _listeners() == 2), "Teardown case reaches pending native menu waiter")
	root.remove_child(menu)
	check(_listeners() == 0 and manager._multiplayer.multiplayer_peer == null and manager._join.timer.is_stopped(), "Tree exit immediately releases pending listeners, peer and join timer")
	check(await _until(func(): return result.done) and not result.ok, "Detached menu's waiter returns canceled without tree or stale UI access")
	menu.free()
func _test_native_probe_cancel() -> void:
	var server := TCPServer.new()
	check(server.listen(0, "127.0.0.1") == OK, "Probe fixture binds a private local HTTP listener")
	var port: int = server.get_local_port()
	var attempt := menu._begin_multiplayer_join_attempt()
	var result := {"done": false}
	_run_native_probe("ws://127.0.0.1:%d" % port, attempt, result)
	check(await _until(func(): return server.is_connection_available()), "Production HTTPRequest reaches only the owned loopback listener")
	var socket := server.take_connection()
	var request: HTTPRequest = attempt.get("probe")
	check(is_instance_valid(request), "Native pending probe is recorded as owned by the attempt")
	menu._show_root_panel(false)
	check(attempt.get("probe") == null and request.is_queued_for_deletion(), "Back cancels and retires the native HTTP request immediately")
	check(await _until(func(): return result.done) and not result.ok, "Canceled HTTP probe unblocks without receiving an HTTP response")
	socket.disconnect_from_host()
	server.stop()
func _run_native_probe(address: String, attempt: Dictionary, result: Dictionary) -> void:
	result["ok"] = await menu.probe_native(address, attempt)
	result["done"] = true
func _test_prior_session_cleanup() -> void:
	manager.join_registered_room({})
	var index := resolver.pending.size()
	var result := {"done": false}
	_launch("CLEANUP", result)
	check(manager._multiplayer.multiplayer_peer == null and resolver.pending.size() == index, "New join begins with existing prior-session cleanup delay")
	menu._show_root_panel(false)
	check(await _until(func(): return result.done), "Canceled prior-session cleanup returns after its existing timer")
	check(not result.ok and resolver.pending.size() == index and not manager.has_active_session_state() and not menu.multiplayer_join_button.disabled, "Old cleanup delay cannot resolve or start a canceled join")

func _test_retry_reprobe() -> void:
	var index := resolver.pending.size()
	var start_count := manager.starts
	manager.next_start_succeeds = false
	var old := {"done": false}
	_launch("REPROBE", old)
	_resolve(index, true)
	check(await _until(func(): return menu.probes.size() == 1), "First DNS probe is pending")
	menu.probes[0].done = true
	check(await _until(func(): return menu.probes.size() == 2, 4.0), "Existing failed-start retry reaches its second DNS probe")
	menu._show_root_panel(false)
	var newer := {"done": false}
	_launch("REPLACE-REPROBE", newer)
	menu.multiplayer_status_label.text = "replacement resolver"
	menu.probes[1].done = true
	check(await _until(func(): return old.done), "Canceled retry probe returns safely")
	check(not old.ok and manager.starts == start_count + 1 and menu.multiplayer_status_label.text == "replacement resolver" and menu.multiplayer_join_button.disabled, "Stale reprobe cannot initiate retry, overwrite status or enable its replacement")
	menu._cancel_multiplayer_join_attempt()
	_resolve(index + 1)
	check(await _until(func(): return newer.done), "Reprobe replacement retires on cancellation")

func _test_normal_retry() -> void:
	var index := resolver.pending.size()
	var start_count := manager.starts
	manager.next_start_succeeds = false
	var result := {"done": false}
	_launch("ORDINARY-RETRY", result)
	_resolve(index)
	check(await _until(func(): return manager.starts == start_count + 1), "Uncanceled failed start reaches ordinary backoff")
	manager.next_start_succeeds = true
	manager.immediate_success = true
	check(await _until(func(): return result.done, 4.0) and result.ok and manager.starts == start_count + 2 and menu.lobbies == 1, "An ordinary retry still connects and opens its accepted lobby once")
	check(_listeners() == 0 and menu._multiplayer_join_attempt.is_empty() and not menu.multiplayer_join_button.disabled, "Successful retry retires only pending menu ownership")

func _test_operation_replacement() -> void:
	for reuse_peer in [false, true]:
		if reuse_peer:
			await _reset()
		var index := resolver.pending.size()
		var result := {"done": false}
		_launch("OWNED", result)
		_resolve(index)
		check(await _until(func(): return _listeners() == 2), "Owned operation reaches pending waiter")
		var original_room := manager.session_id
		if reuse_peer:
			# Simulate a later owner retaining a peer object but changing operation.
			manager._join_operation_generation += 1
		else:
			manager.leave_room()
			manager.join_registered_room({})
		manager.session_id = original_room # Registrations reuse the same room ID.
		manager.session_connected = true
		manager.local_peer_id = 2
		var newer_peer: MultiplayerPeer = manager._multiplayer.multiplayer_peer
		var generation := manager.get_join_operation_generation()
		manager.session_joined.emit(original_room)
		check(await _until(func(): return result.done), "Waiter notices external operation replacement")
		check(not result.ok and menu.lobbies == 0 and _listeners() == 0 and menu._multiplayer_join_attempt.is_empty(), "Old waiter never accepts a newer operation's joined signal or opens its lobby")
		check(manager.session_connected and manager._multiplayer.multiplayer_peer == newer_peer and manager.get_join_operation_generation() == generation and not manager._join.timer.is_stopped(), "Stale cleanup preserves newer peer, timer and same-registration operation")
		var rejected: Dictionary = await menu._await_multiplayer_join_result(manager, 0.1, "127.0.0.1", 1, func(): return false)
		check(not rejected.ok and manager._multiplayer.multiplayer_peer == newer_peer and manager.session_connected and manager.get_join_operation_generation() == generation, "Rejected begin that starts no operation cannot claim or close an unrelated existing session")

func _launch_duo(result: Dictionary) -> void:
	await menu._run_duo_join_autostart()
	result["done"] = true

func _write_duo_code() -> void:
	var file := FileAccess.open(MENU.DUO_ROOM_CODE_PATH, FileAccess.WRITE)
	file.store_string("FIXTURE")
	file.close()

func _test_duo_cancellation() -> void:
	var initial_resolves := resolver.pending.size()
	var result := {"done": false}
	_launch_duo(result)
	menu._show_root_panel(false)
	_write_duo_code()
	check(await _until(func(): return result.done) and resolver.pending.size() == initial_resolves, "Back cancels duo file polling before a later room-code handoff")
	for phase in ["warm resolver", "warm probe", "join resolver"]:
		await _reset()
		var index := resolver.pending.size()
		var start_count := manager.starts
		var duo := {"done": false}
		_launch_duo(duo)
		check(resolver.pending.size() == index + 1, "Duo reaches warm resolver: " + phase)
		if phase != "warm resolver":
			_resolve(index, true)
			check(await _until(func(): return menu.probes.size() == 1), "Duo reaches its warm tunnel probe: " + phase)
			if phase == "join resolver":
				menu.probes[0].done = true
				check(await _until(func(): return resolver.pending.size() == index + 2), "Duo passes the same operation into its ordinary join caller")
		menu._show_root_panel(false)
		var newer := {"done": false}
		_launch("NEW-AFTER-DUO", newer)
		menu.multiplayer_status_label.text = "new manual join"
		match phase:
			"warm resolver": _resolve(index)
			"warm probe": menu.probes[0].done = true
			"join resolver": _resolve(index + 1)
		check(await _until(func(): return duo.done), "Canceled duo phase completes safely: " + phase)
		check(manager.starts == start_count and menu.lobbies == 0 and menu.multiplayer_status_label.text == "new manual join" and menu.multiplayer_join_button.disabled, "Duo cannot resurrect through a stale phase or forced lobby fallback: " + phase)
		menu._cancel_multiplayer_join_attempt()
		_resolve(resolver.pending.size() - 1)
		check(await _until(func(): return newer.done), "Manual replacement after duo can cancel cleanly")
func _test_terminal_failure() -> void:
	var index := resolver.pending.size()
	var start_count := manager.starts
	manager.next_start_succeeds = false
	var result := {"done": false}
	_launch("TERMINAL", result)
	_resolve(index)
	check(await _until(func(): return result.done, 11.0), "Ordinary failure finishes the existing four-attempt retry budget")
	check(not result.ok and manager.starts == start_count + 4 and menu.lobbies == 0, "Uncanceled failure retains four starts and never opens lobby")
	check(not manager.has_active_session_state() and manager._join.timer.is_stopped() and _listeners() == 0 and not menu.multiplayer_join_button.disabled and menu.multiplayer_status_label.text == "Unable to connect to the room host.", "Terminal failure preserves its feedback while retiring owned state and enabling retry")

func _test_duo_outer_backoff_and_success() -> void:
	_write_duo_code()
	var index := resolver.pending.size()
	var old := {"done": false}
	menu.skip_failed_join = true
	_launch_duo(old)
	_resolve(index)
	check(await _until(func(): return menu.probes.size() == 1), "Duo warm probe is staged before outer retry test")
	menu.probes[0].done = true
	await process_frame
	await process_frame
	check(not old.done and menu.multiplayer_status_label.text.contains("attempt 1/6"), "Failed inner result reaches the duo wrapper's existing retry wait")
	menu._show_root_panel(false)
	menu.skip_failed_join = false
	manager.immediate_success = true
	var newer := {"done": false}
	_launch("AFTER-DUO-BACKOFF", newer)
	_resolve(index + 1)
	check(await _until(func(): return newer.done) and newer.ok, "Manual join can succeed while canceled duo backoff waits")
	var accepted_peer: MultiplayerPeer = manager._multiplayer.multiplayer_peer
	check(await _until(func(): return old.done, 5.0), "Duo backoff returns after cancellation")
	check(menu.lobbies == 1 and manager._multiplayer.multiplayer_peer == accepted_peer and manager.session_connected and menu.probes.size() == 1, "Canceled duo backoff cannot reprobe, retry or replace a newer lobby")
	await _reset()
	index = resolver.pending.size()
	var joined := {"done": false}
	manager.immediate_success = true
	_launch_duo(joined)
	_resolve(index)
	check(await _until(func(): return menu.probes.size() == 1), "Uncanceled duo reaches warm probe")
	menu.probes[0].done = true
	check(await _until(func(): return resolver.pending.size() == index + 2), "Uncanceled duo reaches ordinary join resolver")
	_resolve(index + 1)
	check(await _until(func(): return joined.done) and menu.lobbies == 1 and manager.session_connected and menu._multiplayer_join_attempt.is_empty(), "Duo success still accepts exactly one lobby and releases pending ownership")