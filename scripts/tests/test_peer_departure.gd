extends "res://scripts/tests/test_checkpoint_isolation.gd"

class DepartureWorld extends World:
	var door_advances: int = 0
	var retries: int = 0
	var initial_starts: Array[Dictionary] = []
	func _spawn_door_options() -> void:
		door_advances += 1 # Scene generation is outside this lifecycle fixture.
	func _start_initial_encounter_from_pending_profile() -> void:
		initial_starts.append(pending_initial_room_profile.duplicate(true))
		pending_initial_room_profile.clear()
	func _get_hud_state() -> Dictionary:
		return {}
	@rpc("reliable", "authority", "call_local")
	func _start_multiplayer_retry_run() -> void:
		retries += 1

class HUD extends Node:
	var banners: Array[String] = []
	func show_banner(title: String, _detail: String = "") -> void:
		banners.append(title)
	func show_persistent_banner(_title: String, _detail: String, _color: Color = Color.WHITE) -> void:
		pass
	func hide_persistent_banner() -> void:
		pass
	func refresh(_state: Dictionary, _player: Node) -> void:
		pass

class Enemy extends "res://scripts/enemy_base.gd":
	func _ready() -> void:
		_create_health_state()
		add_to_group("enemies")
		set_physics_process(false)

func _create_world() -> World:
	return DepartureWorld.new()

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Peer departure tests require an isolated user directory")
		quit(1)
		return
	await _test_actor_removal()
	await _test_last_living_ally_leaves()
	await _test_joiner_observer()
	await _test_replaced_peer_state()
	await _test_intro_and_reward_waits()
	await _test_retry_wait()
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	HISTORY.clear_all()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await create_timer(0.1).timeout
	print("[OK] Peer departure: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _setup_departure(mode: String = "host") -> Dictionary:
	var saved := _setup(mode)
	world.hud = HUD.new()
	world.add_child(world.hud)
	MultiplayerSessionManager.peer_disconnected.connect(world._on_multiplayer_peer_disconnected)
	return saved

func _disconnect(peer_id: int) -> void:
	MultiplayerSessionManager._on_peer_disconnected(peer_id)

func _test_actor_removal() -> void:
	var saved := _setup_departure()
	var departed := actors[1]
	var enemy := Enemy.new()
	world.add_child(enemy)
	enemy.target = departed
	enemy.set_target_candidates([departed])
	departed.apply_upgrade("ruinous_impact")
	departed.boss_combinations.launch_enemy(enemy, Vector2.RIGHT * 300.0, 2)
	var launch := enemy.get_launch_state()
	PlayerReplicationService._remote_position_samples[2] = {"last_pos": Vector2(900.0, 0.0)}
	PlayerReplicationService._pending_cue_events_by_peer[2] = [{"event": "returning_crescent_state"}]
	world._encounter_ready_peers[2] = true
	_disconnect(2)
	check(not PlayerReplicationService.player_nodes.has(2) and world._get_multiplayer_player_nodes() == [world.player], "A departed ally is removed from the existing party roster")
	check(departed.is_queued_for_deletion() and not departed.visible and not departed.combat_damage_enabled, "Departure hides and disables the avatar before deferred deletion")
	check(not launch.active, "Departure cancels the removed player's host-owned enemy launch")
	check(not PlayerReplicationService._remote_position_samples.has(2) and not PlayerReplicationService._pending_cue_events_by_peer.has(2), "Existing unregister clears stale movement and cue state")
	check(not world._encounter_ready_peers.has(2) and enemy.target == world.player and enemy.target_candidates == [world.player], "Readiness and enemy targets stop referencing the departed actor")
	check(world._count_alive_players() == 1 and not world._run_outcome_coordinator.is_player_defeated(), "A living remaining host continues the run")
	_fallen(world.player)
	world._on_player_died()
	check(world._run_outcome_coordinator.is_player_defeated() and HISTORY.load_all().size() == 1, "Remaining host death reaches the ordinary defeat/history path")
	check(RunContext.load_active_run() == saved, "Disconnect and later co-op defeat preserve an unrelated solo checkpoint")
	await _cleanup()

func _test_last_living_ally_leaves() -> void:
	_setup_departure()
	_fallen(world.player)
	world._on_player_died()
	check(not world._run_outcome_coordinator.is_player_defeated(), "A fallen host waits while its ally remains alive")
	_disconnect(2)
	check(world._run_outcome_coordinator.is_player_defeated() and world.shown_outcomes == ["death"], "Last living ally departure resolves ordinary defeat immediately")
	_disconnect(2)
	check(HISTORY.load_all().size() == 1 and world.shown_outcomes.size() == 1, "Repeated disconnect notification cannot duplicate terminal history")
	await _cleanup()

func _test_joiner_observer() -> void:
	_setup_departure("joiner")
	var other := Player.new()
	world.add_child(other)
	other.player_id = 3
	other.is_local_player = false
	actors.append(other)
	PlayerReplicationService.register_player(3, other)
	MultiplayerSessionManager.connected_peers[3] = {}
	_disconnect(3)
	check(not PlayerReplicationService.player_nodes.has(3) and PlayerReplicationService.player_nodes.has(1) and PlayerReplicationService.player_nodes.has(2), "A joiner removes another departing joiner while retaining host and self")
	check(other.is_queued_for_deletion() and world._count_alive_players() == 2, "Observer roster and liveness update without host-only RPCs")
	world._on_multiplayer_peer_disconnected(2)
	check(PlayerReplicationService.player_nodes.has(2) and not world.player.is_queued_for_deletion(), "A local-peer notification cannot remove the observer's own avatar")
	await _cleanup()

func _test_intro_and_reward_waits() -> void:
	_setup_departure()
	world.encounter_intro_grace_active = true
	world._encounter_ready_peers[1] = true
	world._local_player_ready = true
	world.player.encounter_input_frozen = true
	_disconnect(2)
	check(not world.encounter_intro_grace_active and not world.player.encounter_input_frozen, "An unready departed ally cannot strand a ready host in arena survey")
	await _cleanup()
	for host_complete in [false, true]:
		_setup_departure()
		world._reward_phase_coordinator.begin_phase(true, false, 1, world.hud)
		if host_complete:
			world._reward_phase_coordinator.register_peer_completion(true, 1, false, 1)
		_disconnect(2)
		check((world as DepartureWorld).door_advances == (1 if host_complete else 0), "Departure advances rewards only after every remaining player chose: " + str(host_complete))
		check(world._reward_phase_coordinator.get_active_phase().is_empty() == host_complete, "Reward completion retains the existing phase lifecycle")
		await _cleanup()
	_setup_departure()
	var initial_profile := {"kind": "initial-departure-fixture", "obstacle_layout": 3}
	world.pending_initial_room_profile = initial_profile.duplicate(true)
	world._reward_phase_coordinator.begin_phase(true, true, 1, world.hud)
	world._reward_phase_coordinator.register_peer_completion(true, 1, true, 1)
	_disconnect(2)
	check((world as DepartureWorld).initial_starts == [initial_profile], "A departing initial-reward waiter advances the existing host-selected first arena once")
	_disconnect(2)
	check((world as DepartureWorld).initial_starts.size() == 1, "Repeated departure cannot launch the first arena twice")
	await _cleanup()

func _test_replaced_peer_state() -> void:
	_setup_departure()
	PlayerReplicationService._remote_position_samples[2] = {"last_pos": Vector2(900.0, 0.0)}
	PlayerReplicationService._pending_cue_events_by_peer[2] = [{"event": "returning_crescent_state"}]
	PlayerReplicationService._outgoing_health_sequence_by_peer[2] = 91
	_disconnect(2)
	var replacement := Player.new()
	world.add_child(replacement)
	replacement.player_id = 2
	replacement.is_local_player = false
	replacement.position = Vector2(50.0, 30.0)
	actors.append(replacement)
	PlayerReplicationService.register_player(2, replacement)
	check(PlayerReplicationService.player_nodes[2] == replacement and PlayerReplicationService._remote_target_positions[2] == replacement.position, "A later actor using the same peer ID starts at its own position")
	check(not PlayerReplicationService._remote_position_samples.has(2) and not PlayerReplicationService._pending_cue_events_by_peer.has(2) and PlayerReplicationService._outgoing_health_sequence_by_peer[2] == 0, "Replacement registration cannot inherit the departed actor's samples, pending attacks, or health sequence")
	await _cleanup()

func _test_retry_wait() -> void:
	_setup_departure()
	world._run_outcome_coordinator.register_player_death(true)
	world._run_outcome_coordinator.register_retry_vote(1, [1, 2])
	_disconnect(2)
	check((world as DepartureWorld).retries == 1, "A departed non-voter no longer blocks the host's existing retry vote")
	await _cleanup()
