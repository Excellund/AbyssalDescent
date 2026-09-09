extends "res://scripts/tests/test_boss_combinations_enet.gd"

const BREAKWATER := preload("res://scripts/enemy_breakwater.gd")
const COMBINATIONS := preload("res://scripts/tests/test_breakwater_combinations.gd")
const BREAKWATER_ID := 701
var breakwater: COMBINATIONS.Breakwater
var locked_state: Dictionary = {}
var departed_registry: Node

class ChargePlayer extends Player:
	var damage_contexts: Array[Dictionary] = []
	func _ready() -> void:
		super._ready()
		damage_taken.connect(func(_raw: int, _final: int, context: Dictionary): damage_contexts.append(context.duplicate(true)))

func _run() -> void:
	super._run()
	get_multiplayer().peer_disconnected.connect(MultiplayerSessionManager._on_peer_disconnected)

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	world.position = Vector2(40.0, -60.0)
	world.current_room_size = Vector2(1800.0, 1100.0)
	world.current_effective_room_size = world.current_room_size
	for id in [1, client_id]:
		var actor := ChargePlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.position = Vector2.ZERO if id == 1 else Vector2(100.0, 0.0)
		actor.set_max_health_and_current(100, 100)
		actor.apply_upgrade("sovereigns_double")
		actor.apply_upgrade("ruinous_impact")
		actor.arcana_motion.set_process(false)
		actor.returning_crescent.set_physics_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	breakwater = COMBINATIONS.Breakwater.new()
	breakwater.name = "Breakwater"
	circle(breakwater, BREAKWATER.BODY_RADIUS)
	world.add_child(breakwater)
	breakwater.position = Vector2(-200.0, 0.0)
	breakwater.target = remote_player if role == "client" else local_player
	breakwater.target_candidates = [local_player, local_player, remote_player]
	world.enemy_state_sync_broadcaster.register_enemy(breakwater, BREAKWATER_ID)

func send_state(state: Dictionary = {}) -> Dictionary:
	var actual := breakwater.get_network_runtime_state() if state.is_empty() else state
	world._sync_enemy_states.rpc([{"enemy_id": BREAKWATER_ID, "health": breakwater.get_current_health(), "position": breakwater.global_position, "runtime_state_delta": actual}], 1)
	return actual

func lock_charge() -> void:
	breakwater._cancel_attack()
	breakwater.position = Vector2(-200.0, 0.0)
	breakwater.target = local_player
	breakwater._begin_tracking()
	breakwater._process_behavior(BREAKWATER.TRACK_TIME)
	check(breakwater.phase == BREAKWATER.Phase.LOCK, "Host locks a real finite charge")

func snapshot() -> Dictionary:
	return {"phase": breakwater.phase, "origin": breakwater.charge_origin, "end": breakwater.charge_end, "warnings": breakwater.get_warning_polygons(), "local_health": local_player.get_current_health(), "remote_health": remote_player.get_current_health(), "local_damage_calls": (local_player as ChargePlayer).damage_contexts.size(), "remote_damage_calls": (remote_player as ChargePlayer).damage_contexts.size(), "authority": breakwater.network_simulation_enabled, "health": breakwater.get_current_health()}

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	MultiplayerSessionManager.peer_disconnected.connect(world._on_multiplayer_peer_disconnected)
	departed_registry = remote_player.upgrade_system.power_registry
	await physics_frame
	lock_charge()
	locked_state = send_state()
	world.fixture_command.rpc_id(client_id, "inspect_lock", {"origin": breakwater.charge_origin, "end": breakwater.charge_end})
	check(await until(func(): return results.has("lock")), "Joiner receives the locked capsule through production enemy state RPC")
	if results.has("lock"):
		check(results.lock.warnings == breakwater.get_warning_polygons(), "Translated host and replica draw exactly the same world-space warning capsule")
		check(not results.lock.authority and results.lock.local_health == 100 and results.lock.remote_health == 100 and results.lock.local_damage_calls == 0, "Explicit replica advance cannot originate charge damage")
	breakwater._process_behavior(BREAKWATER.LOCK_TIME)
	breakwater._process_behavior(0.65)
	breakwater._apply_charge_hits(breakwater.charge_origin, breakwater.global_position)
	check(local_player.get_current_health() == 84 and remote_player.get_current_health() == 84 and breakwater._hit_players.size() == 2, "One swept host charge hits each living participant once despite duplicate target candidates")
	for actor_variant in [local_player, remote_player]:
		var actor := actor_variant as ChargePlayer
		check(actor.damage_contexts.size() == 1 and actor.damage_contexts[0].ability == "breakwater_charge" and actor.damage_contexts[0].final_amount == 16, "Each host hit retains Breakwater ability and damage attribution")
	world.fixture_command.rpc_id(client_id, "inspect_health", {"key": "first_health", "local": 84, "remote": 84})
	check(await until(func(): return results.has("first_health")), "Host-authored damage reaches both joiner player nodes")
	if results.has("first_health"):
		check(results.first_health.local_damage_calls == 0 and results.first_health.remote_damage_calls == 0, "Health replication does not invoke player damage again")
	# Deliberately drop the final phase; the previous lock lease expires safely.
	world.fixture_command.rpc_id(client_id, "expire")
	check(await until(func(): return results.has("expired")), "Joiner can expire a lost final packet locally")
	send_state(locked_state)
	world.fixture_command.rpc_id(client_id, "inspect_expired")
	check(await until(func(): return results.has("duplicate")), "Duplicate active packet arrives after lease expiry")
	if results.has("duplicate"):
		check(results.duplicate.warnings.is_empty() and results.duplicate.phase == BREAKWATER.Phase.SEEK, "An old/equal inner sequence cannot resurrect the expired warning")
	var wrong_room := locked_state.duplicate(true)
	wrong_room.custom.q += 100
	wrong_room.custom.r -= 1
	send_state(wrong_room)
	world.fixture_command.rpc_id(client_id, "inspect_packet", {"key": "wrong_room"})
	check(await until(func(): return results.has("wrong_room")), "Wrong-room packet reaches the replica")
	if results.has("wrong_room"):
		check(results.wrong_room.warnings.is_empty(), "A packet from a retired room cannot restore a charge warning")
	var invalid_geometry := locked_state.duplicate(true)
	invalid_geometry.custom.q += 101
	invalid_geometry.custom.o = Vector2.INF
	send_state(invalid_geometry)
	world.fixture_command.rpc_id(client_id, "inspect_packet", {"key": "invalid_geometry"})
	check(await until(func(): return results.has("invalid_geometry")), "Nonfinite geometry packet reaches the replica")
	if results.has("invalid_geometry"):
		check(results.invalid_geometry.warnings.is_empty() and results.invalid_geometry.origin.is_finite(), "Nonfinite geometry cannot create a warning or poison its last finite origin")
	lock_charge()
	send_state()
	world.fixture_command.rpc_id(client_id, "inspect_packet", {"key": "next_lock"})
	check(await until(func(): return results.has("next_lock")), "The next valid lock reaches the replica")
	if results.has("next_lock"):
		check(results.next_lock.phase == BREAKWATER.Phase.LOCK and not results.next_lock.warnings.is_empty(), "Rejected higher sequence packets cannot suppress the next valid charge")
	var locked_origin := breakwater.charge_origin
	var locked_end := breakwater.charge_end
	local_player.position = Vector2(0.0, BREAKWATER.PATH_RADIUS + 0.25)
	remote_player.position = Vector2(100.0, BREAKWATER.PATH_RADIUS)
	# Player physics is disabled; expire its prior contact grace between scenarios.
	local_player._contact_damage_grace_left = 0.0
	remote_player._contact_damage_grace_left = 0.0
	breakwater._process_behavior(BREAKWATER.LOCK_TIME)
	breakwater._process_behavior(0.65)
	check(local_player.get_current_health() == 84 and remote_player.get_current_health() == 68, "Charge checks player centers: just outside the drawn radius is safe while its exact edge is hit")
	check(breakwater.charge_origin == locked_origin and breakwater.charge_end == locked_end, "Moving the chase target after lock cannot rotate or stretch the charge")
	# Real client-side Double and Crescent damage enter the existing host path.
	world.fixture_command.rpc_id(client_id, "double")
	check(await until(func(): return breakwater.get_current_health() == 889), "Client Double echo deals its existing reduced damage to the authoritative Apex")
	check(not breakwater.get_launch_state().active and world.damage_events.size() == 1 and world.damage_events[0].peer == client_id, "Secondary Double keeps owner accounting and cannot arm Ruinous")
	send_state()
	world.fixture_command.rpc_id(client_id, "crescent")
	check(await until(func(): return breakwater.get_current_health() == 871), "Both returning blade legs deal exactly one 9-damage hit to the host Apex")
	check(not breakwater.get_launch_state().active and world.damage_events.size() == 3 and breakwater.hits.all(func(hit: Dictionary) -> bool: return bool(hit.get("secondary", false))), "Crescent and Double preserve secondary classification without recursive launches")
	world.fixture_command.rpc_id(client_id, "primary")
	check(await until(func(): return breakwater.get_current_health() == 851), "Client primary hit still enters the normal Apex damage path")
	var origin := breakwater.global_position
	check(breakwater.get_launch_state().compression, "Host resolves Ruinous as Apex compression")
	breakwater.get_launch_state().step(breakwater, 0.17)
	check(breakwater.global_position == origin and breakwater.get_current_health() == 831 and not breakwater.get_launch_state().active, "One host compression burst deals damage without displacement or recursion")
	# Lock onto the remote participant, then remove that participant after a
	# real disconnect; the lane must stay committed and hit no departed actor.
	local_player.position = Vector2(-500.0, 300.0)
	remote_player.position = Vector2(100.0, 0.0)
	breakwater._cancel_attack()
	breakwater.position = Vector2(-200.0, 0.0)
	breakwater.target = remote_player
	breakwater._begin_tracking()
	breakwater._process_behavior(BREAKWATER.TRACK_TIME)
	locked_end = breakwater.charge_end
	world.fixture_command.rpc_id(client_id, "disconnect")
	check(await until(func(): return not MultiplayerSessionManager.connected_peers.has(client_id) and not is_instance_valid(remote_player)), "Target participant disconnects over the real transport")
	breakwater._process_behavior(BREAKWATER.LOCK_TIME)
	breakwater._process_behavior(1.0)
	check(breakwater.charge_end == locked_end and not is_instance_valid(remote_player) and local_player.get_current_health() == 84, "Locked charge neither retargets nor damages a departed participant")
	if is_instance_valid(departed_registry):
		departed_registry.free()
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"inspect_lock":
			check(await until(func(): return breakwater.phase == BREAKWATER.Phase.LOCK), "Replica receives lock phase")
			check(breakwater.charge_origin == payload.origin and breakwater.charge_end == payload.end, "Replica preserves exact finite endpoints")
			breakwater._process_behavior(2.0)
			breakwater._apply_charge_hits(breakwater.charge_origin, breakwater.charge_end)
			world.fixture_result.rpc_id(1, "lock", snapshot())
		"inspect_health":
			check(await until(func(): return local_player.get_current_health() == int(payload.local) and remote_player.get_current_health() == int(payload.remote)), "Authoritative player health reaches the joiner")
			world.fixture_result.rpc_id(1, payload.key, snapshot())
		"expire":
			breakwater._process_network_visuals(BREAKWATER.REMOTE_LEASE + 0.05)
			world.fixture_result.rpc_id(1, "expired", snapshot())
		"inspect_expired": world.fixture_result.rpc_id(1, "duplicate", snapshot())
		"inspect_packet": world.fixture_result.rpc_id(1, payload.key, snapshot())
		"double":
			local_player.global_position = breakwater.global_position + Vector2(-300.0, 200.0)
			local_player.boss_combinations.create_shade(breakwater.global_position - Vector2(60.0, 0.0))
			local_player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "range": 78.0, "arc_degrees": 130.0})
		"crescent":
			check(await until(func(): return breakwater.get_current_health() == 889), "Crescent uses the host's latest Apex position and health")
			local_player.apply_trial_power("returning_crescent")
			local_player.global_position = breakwater.global_position - Vector2(100.0, 0.0)
			local_player.returning_crescent.try_launch(Vector2.RIGHT)
			for _index in range(100):
				local_player.returning_crescent.tick(0.01)
		"primary": DAMAGE.apply_damage(breakwater, 20, {"attack_type": "melee"})
		"disconnect":
			world.process_mode = Node.PROCESS_MODE_DISABLED
			world.hide()
			await create_timer(0.05).timeout
			peer.disconnect_peer(1)
			await create_timer(0.2).timeout
			await finish()
