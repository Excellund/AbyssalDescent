extends SceneTree
## Real World callers and UI surfaces; only disk faults, scene transitions and
## network transport are controlled. Persistence stays in the runner's profile.

const STORE := preload("res://scripts/core/active_run_checkpoint_store.gd")
const HISTORY := preload("res://scripts/core/run_history_store.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
const BOOTSTRAP := preload("res://scripts/core/world_bootstrap_coordinator.gd")

class FaultStore extends "res://scripts/core/active_run_checkpoint_store.gd":
	var fail_io := false
	var fail_read := false
	var io_attempts := 0
	func _open_file(path: String, mode: int) -> FileAccess:
		io_attempts += 1
		if fail_io and mode == FileAccess.WRITE:
			return null
		if fail_read and mode == FileAccess.READ and path == save_path:
			return null
		return super._open_file(path, mode)
	func _remove_file(path: String) -> bool:
		io_attempts += 1
		return false if fail_io else super._remove_file(path)

class Player extends "res://scripts/player.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _broadcast_cue_event(_event: String, _payload: Dictionary, _reliable: bool = false) -> void:
		pass # This lifecycle fixture does not open sockets.

class Recorder extends "res://scripts/core/run_summary_recorder.gd":
	var initialize_calls := 0
	var reset_calls := 0
	var start_calls := 0
	var progression_calls := 0
	func _init(owner_world: Node) -> void:
		super(owner_world)
	func initialize(allow_collection: bool) -> void:
		initialize_calls += 1
		super.initialize(allow_collection)
	func reset_summary_tracker() -> void:
		reset_calls += 1
		super.reset_summary_tracker()
	func mark_run_start() -> void:
		start_calls += 1
		super.mark_run_start()
	func _apply_endgame_chase_progress(summary: Dictionary) -> void:
		progression_calls += 1
		super._apply_endgame_chase_progress(summary)

class HUD extends Node:
	func hide_boss_intro() -> void:
		pass
	var banners: Array[String] = []
	func show_banner(title: String, _detail: String = "", _color: Color = Color.WHITE) -> void:
		banners.append(title)
	func refresh(_state: Dictionary, _player: Node) -> void:
		pass

class World extends "res://scripts/world_generator.gd":
	var fixture_peer := 1
	var transitions: Array[String] = []
	var teardown_calls := 0
	var broadcast_outcomes: Array[String] = []
	var submitted_summaries: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _exit_tree() -> void:
		pass
	func _resolve_local_peer_id() -> int:
		return fixture_peer
	func _change_checkpoint_scene(path: String) -> void:
		transitions.append(path)
	func _teardown_multiplayer_session_for_menu_transition() -> void:
		teardown_calls += 1
		# Model the closed connection, which the real teardown establishes before
		# terminal persistence; no sockets or external scene transitions are used.
		MultiplayerSessionManager.session_connected = false
	func _broadcast_run_outcome_if_needed(outcome: String, _tier: int, _label: String, _depth: int) -> void:
		broadcast_outcomes.append(outcome)
	func _enqueue_leaderboard_submission(summary: Dictionary) -> void:
		submitted_summaries.append(summary.duplicate(true))

var checks := 0
var failures: Array[String] = []
var world: World
var actors: Array[Player] = []
var store: FaultStore
var original_store: RefCounted
var audio_retirement := AUDIO_RETIREMENT.new()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Checkpoint lifecycle requires a disposable project/profile")
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	# This fixture bypasses World._ready and its normal RewardSelectionUI.
	# Install that UI's actual bindings before injecting native Escape events.
	var input_setup := preload("res://scripts/reward_selection_ui.gd").new()
	input_setup._ensure_inspection_actions()
	input_setup.free()
	original_store = RunContext.active_run_checkpoint_store
	ProjectSettings.set_setting("application/config/version", "dev-checkpoint-lifecycle")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	for outcome in ["abandon", "death", "clear"]:
		await _test_history_outcome(outcome)
	for action in ["abandon", "death_menu", "victory_menu", "death_retry", "victory_retry"]:
		await _test_voluntary_failure(action)
	await _test_failed_checkpoint_write()
	for mode in ["solo", "host", "joiner"]:
		for outcome in ["death", "clear"]:
			await _test_terminal_outcome(mode, outcome)
	for mode in ["host", "joiner"]:
		for action in ["abandon", "death_menu", "victory_menu"]:
			await _test_coop_action(mode, action)
	for kind in ["missing", "invalid", "unsupported", "unsupported_envelope", "read_failed", "apply_failed"]:
		await _test_failed_requested_resume(kind)
	RunContext.active_run_checkpoint_store = original_store
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	RunContext.consume_run_retry()
	RunContext.remove_meta("checkpoint_menu_error")
	HISTORY.clear_all()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Lifecycle scenes retire native audio")
	print("[OK] Checkpoint lifecycle: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _setup(mode: String = "solo") -> void:
	MultiplayerSessionManager.session_connected = false
	PlayerReplicationService.player_nodes.clear()
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	HISTORY.clear_all()
	RunContext.consume_run_retry()
	RunContext.clear_resume_saved_run_request()
	RunContext.remove_meta("checkpoint_menu_error")
	RunContext.set_last_run_outcome("fixture-before")
	RunContext.active_ascension_loadout = []
	store = FaultStore.new()
	RunContext.active_run_checkpoint_store = store
	RunContext.clear_active_run()
	world = World.new()
	root.add_child(world)
	current_scene = world
	world.is_multiplayer = mode != "solo"
	world.fixture_peer = 2 if mode == "joiner" else 1
	world.current_room_label = "Checkpoint fixture"
	world.room_depth = 7
	world.combat_phase_coordinator = preload("res://scripts/core/combat_phase_coordinator.gd").new()
	world.player_flow_coordinator = preload("res://scripts/core/player_flow_coordinator.gd").new()
	world.objective_lifecycle_coordinator = preload("res://scripts/core/objective_lifecycle_coordinator.gd").new()
	world.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(world)
	world.hud = HUD.new()
	world.add_child(world.hud)
	for id in ([1, 2] if world.is_multiplayer else [1]):
		var actor := Player.new()
		world.add_child(actor)
		actor.player_id = id
		actor.is_local_player = id == world.fixture_peer
		PlayerReplicationService.register_player(id, actor)
		actors.append(actor)
		if actor.is_local_player:
			world.player = actor
	MultiplayerSessionManager.session_connected = world.is_multiplayer
	MultiplayerSessionManager.is_host_peer = mode != "joiner"
	MultiplayerSessionManager.local_peer_id = world.fixture_peer
	MultiplayerSessionManager.connected_peers = {1: {}, 2: {}} if world.is_multiplayer else {1: {}}
	PlayerReplicationService.local_peer_id = world.fixture_peer
	world.run_summary_recorder = Recorder.new(world)
	world.run_summary_recorder.mark_run_start()
	world.run_summary_recorder.initialize(false)
	world.pause_menu_controller = preload("res://scripts/pause_menu_controller.gd").new()
	world.add_child(world.pause_menu_controller)
	world.pause_menu_controller.initialize("/root/RunContext", Callable(), Callable())
	world.pause_menu_controller.pause_opened.connect(world._on_pause_menu_opened)
	world.pause_menu_controller.pause_closed.connect(world._on_pause_menu_closed)
	world.pause_menu_controller.abandon_run_requested.connect(world._on_pause_abandon_run_requested)
	world.defeat_screen = preload("res://scripts/defeat_screen.gd").new()
	world.add_child(world.defeat_screen)
	world.defeat_screen.back_to_main_menu_requested.connect(world._on_defeat_back_to_menu)
	world.defeat_screen.retry_run_requested.connect(world._on_defeat_retry_run)
	world.victory_screen = preload("res://scripts/victory_screen.gd").new()
	world.add_child(world.victory_screen)
	world.victory_screen.back_to_main_menu_requested.connect(world._on_victory_back_to_menu)
	world.victory_screen.retry_run_requested.connect(world._on_victory_retry_run)
	var saved := {"version": world.RUN_SNAPSHOT_VERSION, "marker": "suspended-solo-" + mode, "rooms_cleared": 7, "active_ascension_loadout": []}
	check(RunContext.save_active_run(saved), mode + ": real store establishes isolated checkpoint")
	RunContext.request_resume_saved_run()

func _open_action_surface(action: String) -> Node:
	if action == "abandon":
		world.pause_menu_controller.open()
		return world.pause_menu_controller
	var outcome := "death" if action.begins_with("death") else "clear"
	world._run_outcome_coordinator.apply_synced_outcome(outcome)
	world._run_summary_finish_run(outcome)
	world._set_combat_paused(true)
	if outcome == "death":
		world._show_defeat_feedback(world.current_room_label, world.room_depth, world._latest_run_summary())
		return world.defeat_screen
	world._show_victory_feedback(-1, world._latest_run_summary())
	return world.victory_screen

func _invoke(action: String, surface: Node) -> void:
	if action == "abandon":
		surface.abandon_run_requested.emit()
	elif action.ends_with("retry"):
		surface.retry_run_requested.emit()
	else:
		surface.back_to_main_menu_requested.emit()

func _notice_label(surface: Node) -> Label:
	if surface == world.pause_menu_controller:
		return surface.checkpoint_notice_label
	return surface._results_screen._checkpoint_notice_label

func _test_history_outcome(outcome: String) -> void:
	_setup()
	if outcome == "abandon":
		var surface := _open_action_surface("abandon")
		var abandon_button: Button = null
		for child in surface.pause_menu_panel.get_children():
			if child is Button and child.text == "Abandon Descent":
				abandon_button = child
		check(abandon_button != null, "History regression uses the actual Abandon Descent button")
		if abandon_button != null:
			abandon_button.pressed.emit()
		check(world.transitions == ["res://scenes/Menu.tscn"] and not RunContext.has_saved_run(), "Actual Abandon still clears its checkpoint and returns to Menu")
		check(RunContext.get_last_run_outcome() == "death", "Abandon preserves its existing progression context independently of the history label")
	else:
		_terminal(outcome)
	var records := HISTORY.load_all()
	check(records.size() == 1 and records[0].get("outcome") == outcome, outcome + ": actual World action and recorder persist their distinct outcome")
	var before_hash := FileAccess.get_sha256(HISTORY.STORAGE_PATH)
	var panel := preload("res://scripts/ui/run_history/run_history_panel.gd").new()
	root.add_child(panel)
	panel.size = Vector2(960, 720)
	panel._build_ui(null)
	panel.populate()
	await process_frame
	await process_frame
	var label: String = {"abandon": "Abandoned", "death": "Defeat", "clear": "Victory"}[outcome]
	check(panel._detail_content.get_child(0).text == label + " — " + String(records[0].get("character_name", "")), outcome + ": actual saved run reaches the matching History detail")
	if outcome == "abandon":
		check(panel._row_buttons[0].get_child(0).get_child(2).text == "Abandoned", "Actual abandoned run is also explicitly distinct in the History list")
	check(FileAccess.get_sha256(HISTORY.STORAGE_PATH) == before_hash, outcome + ": showing History preserves every stored result/stat field")
	panel.queue_free()
	await _cleanup()

func _test_voluntary_failure(action: String) -> void:
	_setup()
	var surface := _open_action_surface(action)
	var previous_outcome := RunContext.get_last_run_outcome()
	var previous_history := HISTORY.load_all()
	var previous_hash := FileAccess.get_sha256(store.save_path)
	RunContext.request_run_retry("veilstrider", 2)
	var previous_retry := RunContext._pending_run_retry.duplicate(true)
	store.fail_io = true
	_invoke(action, surface)
	check(world.transitions.is_empty() and current_scene == world and world.teardown_calls == 0, action + ": failed clear retains scene and session")
	check(surface.is_open() and not world.player.is_physics_processing(), action + ": failed clear retains pause/result surface and paused combat")
	check(HISTORY.load_all() == previous_history and RunContext.get_last_run_outcome() == previous_outcome, action + ": failed clear does not fabricate or replace an outcome")
	check(RunContext._pending_run_retry == previous_retry and RunContext.run_resume_request_state.resume_saved_run_requested, action + ": failed clear retains retry setup and resume request")
	check(FileAccess.get_sha256(store.save_path) == previous_hash, action + ": failed clear leaves checkpoint bytes intact")
	var notice := _notice_label(surface)
	check(notice.visible and not notice.text.is_empty() and notice.text == world._checkpoint_notice, action + ": actual UI displays the clear failure")
	if action == "abandon":
		# Opening and failing above happened synchronously, during the entrance
		# tween. A delayed old tween must not overwrite the new panel bounds.
		await create_timer(0.24).timeout
		var panel: Control = world.pause_menu_controller.pause_menu_panel
		check(panel.get_rect().size.y >= notice.get_rect().end.y and panel.get_global_rect().get_center().distance_to(root.get_visible_rect().get_center()) < 2.0, "Immediate failed Abandon remains centered with the full notice after the entrance tween")
	store.fail_io = false
	_invoke(action, surface)
	var expected_scene := "res://scenes/Main.tscn" if action.ends_with("retry") else "res://scenes/Menu.tscn"
	check(world.transitions == [expected_scene] and not RunContext.has_saved_run(), action + ": retrying the action after recovery clears and transitions once")
	check(not RunContext.run_resume_request_state.resume_saved_run_requested and world._checkpoint_notice.is_empty(), action + ": successful clear retires request and notice")
	if action.ends_with("retry"):
		check(RunContext._pending_run_retry.character_id == world.current_character_id and RunContext._pending_run_retry.difficulty_tier == world.current_difficulty_tier, action + ": retry setup changes only after successful clear")
	await _cleanup()

func _test_failed_checkpoint_write() -> void:
	_setup()
	var previous_hash := FileAccess.get_sha256(store.save_path)
	store.fail_io = true
	world._save_active_run_checkpoint()
	check(FileAccess.get_sha256(store.save_path) == previous_hash, "World failed checkpoint write preserves the last valid disk bytes")
	check(not world._checkpoint_notice.is_empty() and world.hud.banners.has("Progress not saved"), "World failed checkpoint write raises a HUD banner and persistent notice")
	check(world.transitions.is_empty() and HISTORY.load_all().is_empty(), "Failed checkpoint write does not transition or terminate the descent")
	world.pause_menu_controller.open()
	check(_notice_label(world.pause_menu_controller).visible and _notice_label(world.pause_menu_controller).text == world._checkpoint_notice, "Opening Pause later displays the earlier save failure")
	store.fail_io = false
	world.room_depth = 8
	world._save_active_run_checkpoint()
	var saved := RunContext.load_active_run()
	check(int(saved.get("room_depth", -1)) == 8 and FileAccess.get_sha256(store.save_path) != previous_hash, "Next successful World checkpoint publishes the new progress")
	check(world._checkpoint_notice.is_empty() and not _notice_label(world.pause_menu_controller).visible, "Successful checkpoint clears the persistent and visible save warning")
	await _cleanup()

func _terminal(outcome: String) -> void:
	if outcome == "death":
		for actor in actors:
			actor._is_alive_state = false
			actor.health_state.current_health = 0
		world._on_player_died()
	else:
		world._finish_third_boss_clear()

func _test_terminal_outcome(mode: String, outcome: String) -> void:
	_setup(mode)
	var original_hash := FileAccess.get_sha256(store.save_path)
	store.fail_io = true
	store.io_attempts = 0
	_terminal(outcome)
	var surface: Node = world.defeat_screen if outcome == "death" else world.victory_screen
	var initial_results: Node = surface._results_screen
	check(surface.is_open() and RunContext.get_last_run_outcome() == outcome, mode + "/" + outcome + ": terminal result still appears despite unavailable checkpoint writes")
	var authoritative_summary: Dictionary = {}
	if mode == "joiner" and outcome == "death":
		var recorder: Recorder = world.run_summary_recorder
		check(HISTORY.load_all().is_empty() and not recorder.telemetry_run_finished and recorder.progression_calls == 0 and world.submitted_summaries.is_empty(), "Joining provisional defeat displays without persisting incomplete attribution or awarding progress")
		_terminal(outcome)
		check(HISTORY.load_all().is_empty() and world.broadcast_outcomes == [outcome] and surface._results_screen == initial_results, "Repeated joining HP0 callback leaves one provisional result while awaiting the host")
		authoritative_summary = recorder.latest_run_summary.duplicate(true)
		authoritative_summary["run_id"] = "checkpoint-authoritative-death"
		authoritative_summary["stats"]["damage_taken_total"] = 999
		# Transport is controlled, but delivery enters the actual World handler.
		# A different host total proves the final record uses the local peer map.
		world._sync_run_outcome(outcome, -1, world.current_room_label, world.room_depth, authoritative_summary, {2: {"damage_taken_total": 73}})
		var attributed := HISTORY.load_all()
		check(attributed.size() == 1 and attributed[0].run_id == "checkpoint-authoritative-death-p2" and int(attributed[0].stats.damage_taken_total) == 73, "Authoritative World outcome persists the joining player's attributed result")
		check(recorder.progression_calls == 1 and world.submitted_summaries.size() == 1, "Authoritative joining result evaluates progression and submits once")
	check(HISTORY.load_all().size() == 1 and world.broadcast_outcomes == [outcome], mode + "/" + outcome + ": terminal history and outcome dispatch happen once")
	check(FileAccess.get_sha256(store.save_path) == original_hash and RunContext.run_resume_request_state.resume_saved_run_requested, mode + "/" + outcome + ": uncleared checkpoint and request remain intact")
	if mode == "solo":
		check(_notice_label(surface).visible and not world._checkpoint_notice.is_empty(), outcome + ": actual terminal screen explains failed clear")
		if outcome == "clear":
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.physical_keycode = KEY_ESCAPE
			escape.pressed = true
			Input.parse_input_event(escape)
			Input.flush_buffered_events()
			var release := InputEventKey.new()
			release.keycode = KEY_ESCAPE
			release.physical_keycode = KEY_ESCAPE
			Input.parse_input_event(release)
			Input.flush_buffered_events()
			check(surface.is_open() and not world.pause_menu_controller.is_open(), "Victory Escape cannot open Pause around a failed checkpoint clear")
	else:
		check(store.io_attempts == 0 and world._checkpoint_notice.is_empty(), mode + "/" + outcome + ": co-op never touches suspended solo checkpoint storage")
	_terminal(outcome)
	check(HISTORY.load_all().size() == 1 and world.broadcast_outcomes == [outcome] and surface._results_screen == initial_results, mode + "/" + outcome + ": repeated terminal callback cannot duplicate result/history")
	if not authoritative_summary.is_empty():
		var history_hash := FileAccess.get_sha256(HISTORY.STORAGE_PATH)
		world._sync_run_outcome(outcome, -1, world.current_room_label, world.room_depth, authoritative_summary, {2: {"damage_taken_total": 73}})
		check(FileAccess.get_sha256(HISTORY.STORAGE_PATH) == history_hash and world.run_summary_recorder.progression_calls == 1 and world.submitted_summaries.size() == 1 and surface._results_screen == initial_results, "Repeated authoritative delivery preserves history bytes and cannot duplicate progress, submission or the result surface")
	store.fail_io = false
	surface.back_to_main_menu_requested.emit()
	check(world.transitions == ["res://scenes/Menu.tscn"], mode + "/" + outcome + ": later menu action proceeds")
	check(RunContext.has_saved_run() == (mode != "solo"), mode + "/" + outcome + ": later action clears only its own solo checkpoint")
	await _cleanup()

func _test_coop_action(mode: String, action: String) -> void:
	_setup(mode)
	var surface := _open_action_surface(action)
	var awaiting_host := mode == "joiner" and action == "death_menu"
	var delayed_summary: Dictionary = world.run_summary_recorder.latest_run_summary.duplicate(true)
	if awaiting_host:
		check(HISTORY.load_all().is_empty() and world.run_summary_recorder.progression_calls == 0, "Joining defeat menu begins with a provisional result and no authoritative delivery")
	var original_hash := FileAccess.get_sha256(store.save_path)
	store.fail_io = true
	store.io_attempts = 0
	_invoke(action, surface)
	check(world.transitions == ["res://scenes/Menu.tscn"] and world.teardown_calls == 1, mode + "/" + action + ": actual co-op caller proceeds independently of solo storage faults")
	check(store.io_attempts == 0 and FileAccess.get_sha256(store.save_path) == original_hash and RunContext.run_resume_request_state.resume_saved_run_requested, mode + "/" + action + ": suspended solo bytes/request are unchanged")
	if awaiting_host:
		var records := HISTORY.load_all()
		check(records.size() == 1 and records[0].outcome == "death" and world.run_summary_recorder.progression_calls == 1 and world.submitted_summaries.size() == 1, "Actual joining defeat-menu caller persists once after teardown when the host outcome never arrives")
		var history_hash := FileAccess.get_sha256(HISTORY.STORAGE_PATH)
		world._run_summary_finish_run("death")
		world.run_summary_recorder.finalize_synced_run_summary_for_joiner(delayed_summary, "death")
		check(FileAccess.get_sha256(HISTORY.STORAGE_PATH) == history_hash and world.run_summary_recorder.progression_calls == 1 and world.submitted_summaries.size() == 1, "Repeated fallback or delayed host summary cannot rewrite the persisted menu result or duplicate progress")
	await _cleanup()

func _test_failed_requested_resume(kind: String) -> void:
	_setup()
	if kind == "missing":
		RunContext.clear_active_run()
	elif kind == "invalid":
		var file := FileAccess.open(store.save_path, FileAccess.WRITE)
		file.store_buffer(PackedByteArray([1, 2]))
		file.close()
	elif kind == "unsupported":
		RunContext.save_active_run({"version": world.RUN_SNAPSHOT_VERSION + 1, "marker": "future snapshot"})
	elif kind == "unsupported_envelope":
		var file := FileAccess.open(store.save_path, FileAccess.WRITE)
		file.store_var({"version": RunContext.ACTIVE_RUN_VERSION + 1, "snapshot": {"version": world.RUN_SNAPSHOT_VERSION}})
		file.close()
	elif kind == "read_failed":
		store.fail_read = true
	elif kind == "apply_failed":
		# The real snapshot service rejects an unavailable player before applying.
		world.player = null
	var original_hash := FileAccess.get_sha256(store.save_path) if FileAccess.file_exists(store.save_path) else ""
	RunContext.request_resume_saved_run()
	var recorder: Recorder = world.run_summary_recorder
	var calls_before := [recorder.initialize_calls, recorder.reset_calls, recorder.start_calls]
	var fallback_called := [false]
	var stages: Array[Callable] = [world._run_resume_flow, func(): fallback_called[0] = true; return false]
	var handled := BOOTSTRAP.new().run_first_success(stages)
	check(handled and not fallback_called[0] and not world._checkpoint_resume_error.is_empty(), kind + ": resume error handles bootstrap without falling through to new run")
	check([recorder.initialize_calls, recorder.reset_calls, recorder.start_calls] == calls_before and not world.current_room_tutorial_active, kind + ": failed requested resume creates no fresh recorder/tutorial")
	check(world.transitions.is_empty() and not world.is_processing(), kind + ": scene transition is deferred while gameplay is stopped")
	await process_frame
	check(world.transitions == ["res://scenes/Menu.tscn"] and not String(RunContext.get_meta("checkpoint_menu_error", "")).is_empty(), kind + ": deferred return delivers an actual menu error")
	check((FileAccess.get_sha256(store.save_path) if FileAccess.file_exists(store.save_path) else "") == original_hash and HISTORY.load_all().is_empty(), kind + ": failed restore preserves save bytes and produces no terminal history")
	await _cleanup()

func _cleanup() -> void:
	store.fail_io = false
	store.fail_read = false
	MultiplayerSessionManager.session_connected = false
	PlayerReplicationService.player_nodes.clear()
	for actor in actors:
		actor.upgrade_system.power_registry.free()
	actors.clear()
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame
