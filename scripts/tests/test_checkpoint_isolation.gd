extends SceneTree
## Exercise real death/checkpoint/summary APIs with an isolated on-disk solo save.

const HISTORY := preload("res://scripts/core/run_history_store.gd")
const RECORDER := preload("res://scripts/core/run_summary_recorder.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")

class Player extends "res://scripts/player.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _broadcast_cue_event(_event: String, _payload: Dictionary, _reliable: bool = false) -> void:
		pass # This fixture exercises host/joiner lifecycle without opening sockets.

class World extends "res://scripts/world_generator.gd":
	var fixture_peer: int = 1
	var shown_outcomes: Array[String] = []
	var broadcast_outcomes: Array[String] = []
	var submitted_summaries: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _exit_tree() -> void:
		pass
	func _resolve_local_peer_id() -> int:
		return fixture_peer
	func _show_defeat_feedback(_label: String, _depth: int, summary: Dictionary = {}) -> void:
		shown_outcomes.append(String(summary.get("outcome", "")))
	func _broadcast_run_outcome_if_needed(outcome: String, _tier: int, _label: String, _depth: int) -> void:
		broadcast_outcomes.append(outcome)
	func _enqueue_leaderboard_submission(summary: Dictionary) -> void:
		submitted_summaries.append(summary.duplicate(true))

var checks: int = 0
var failures: Array[String] = []
var world: World
var actors: Array[Player] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Checkpoint isolation requires a disposable project and user profile")
		quit(1)
		return
	for mode in ["solo", "host", "joiner"]:
		await _test_death(mode)
		await _test_clear_helper(mode)
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	HISTORY.clear_all()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await create_timer(0.1).timeout
	print("[OK] Checkpoint isolation: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _create_world() -> World:
	return World.new()

func _setup(mode: String) -> Dictionary:
	MultiplayerSessionManager.session_connected = false
	PlayerReplicationService.player_nodes.clear()
	HISTORY.clear_all()
	world = _create_world()
	root.add_child(world)
	current_scene = world
	world.is_multiplayer = mode != "solo"
	world.fixture_peer = 2 if mode == "joiner" else 1
	world.combat_phase_coordinator = preload("res://scripts/core/combat_phase_coordinator.gd").new()
	world.player_flow_coordinator = preload("res://scripts/core/player_flow_coordinator.gd").new()
	world.objective_lifecycle_coordinator = preload("res://scripts/core/objective_lifecycle_coordinator.gd").new()
	world.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(world)
	for id in ([1, 2] if world.is_multiplayer else [1]):
		var actor := Player.new()
		world.add_child(actor)
		actor.player_id = id
		actor.is_local_player = id == world.fixture_peer
		PlayerReplicationService.register_player(id, actor)
		actors.append(actor)
		if id == world.fixture_peer:
			world.player = actor
	MultiplayerSessionManager.session_connected = world.is_multiplayer
	MultiplayerSessionManager.is_host_peer = mode != "joiner"
	MultiplayerSessionManager.local_peer_id = world.fixture_peer
	MultiplayerSessionManager.connected_peers = {1: {}, 2: {}} if world.is_multiplayer else {1: {}}
	PlayerReplicationService.local_peer_id = world.fixture_peer
	world.run_summary_recorder = RECORDER.new(world)
	world.run_summary_recorder.mark_run_start()
	world.run_summary_recorder.initialize(false) # Local history remains real; uploads/progression stay disabled.
	var snapshot := {"version": 1, "marker": "suspended-solo-before-" + mode, "rooms_cleared": 7, "active_ascension_loadout": []}
	check(RunContext.save_active_run(snapshot) and RunContext.load_active_run() == snapshot, mode + ": fixture establishes a real resumable solo checkpoint")
	RunContext.request_resume_saved_run()
	return snapshot

func _fallen(actor: Player) -> void:
	actor._is_alive_state = false
	actor.health_state.current_health = 0

func _test_death(mode: String) -> void:
	var snapshot := _setup(mode)
	var initial_hash := FileAccess.get_sha256(RunContext._active_run_save_path())
	if world.is_multiplayer:
		_fallen(actors[0])
		world._on_player_died()
		check(not world._run_outcome_coordinator.is_player_defeated() and HISTORY.load_all().is_empty(), mode + ": one fallen ally does not end the run or write terminal history")
		check(RunContext.load_active_run() == snapshot, mode + ": an ally falling preserves the suspended solo checkpoint")
	for actor in actors:
		_fallen(actor)
	world._on_player_died()
	check(world._run_outcome_coordinator.is_player_defeated() and RunContext.get_last_run_outcome() == "death", mode + ": party defeat still records the terminal outcome")
	check(world.shown_outcomes == ["death"] and world.broadcast_outcomes == ["death"], mode + ": death presentation and outcome dispatch still occur once")
	var records := HISTORY.load_all()
	check(records.size() == 1 and String(records[0].get("outcome", "")) == "death", mode + ": production recorder retains one local death summary")
	if not records.is_empty():
		check(bool(records[0].is_multiplayer) == world.is_multiplayer and int(records[0].player_count) == actors.size(), mode + ": history retains the correct party context")
	if world.is_multiplayer:
		check(RunContext.load_active_run() == snapshot and FileAccess.get_sha256(RunContext._active_run_save_path()) == initial_hash, mode + ": party wipe preserves the separate solo checkpoint byte for byte")
		check(RunContext.consume_resume_saved_run_request(), mode + ": party wipe preserves the solo resume request")
	else:
		check(not RunContext.has_saved_run() and RunContext.load_active_run().is_empty(), "Solo defeat clears its own checkpoint")
		check(not RunContext.consume_resume_saved_run_request(), "Solo defeat clears its own resume request")
	world._on_player_died()
	check(HISTORY.load_all().size() == 1 and world.shown_outcomes.size() == 1, mode + ": duplicate death signals do not duplicate history or outcome UI")
	await _cleanup()

func _test_clear_helper(mode: String) -> void:
	var snapshot := _setup(mode)
	# Victory, abandon, retry and return-to-menu already share this helper.
	# Keep scene transitions out of the fixture while verifying their clear policy.
	world._clear_active_run_checkpoint()
	check(RunContext.has_saved_run() == world.is_multiplayer, mode + ": shared clear policy deletes only the current solo checkpoint")
	check(RunContext.consume_resume_saved_run_request() == world.is_multiplayer, mode + ": shared clear policy isolates the solo resume request")
	if world.is_multiplayer:
		check(RunContext.load_active_run() == snapshot, mode + ": shared clear policy retains the original solo payload")
	check(HISTORY.load_all().is_empty() and not world._run_outcome_coordinator.is_player_defeated(), mode + ": clearing a checkpoint does not invent a run outcome/history entry")
	await _cleanup()

func _cleanup() -> void:
	MultiplayerSessionManager.session_connected = false
	PlayerReplicationService.player_nodes.clear()
	for actor in actors:
		actor.upgrade_system.power_registry.free()
	actors.clear()
	current_scene = null
	world.free()
	world = null
	await process_frame
