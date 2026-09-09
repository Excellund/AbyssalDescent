extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Real player health and floor-zone state over two isolated loopback processes.

class HazardPlayer extends Player:
	var damage_events: Array[Dictionary] = []
	var health_updates: Array[int] = []
	func _ready() -> void:
		super._ready()
		damage_taken.connect(func(_raw: int, _final: int, context: Dictionary) -> void: damage_events.append(context.duplicate(true)))
		health_changed.connect(func(health: int, _maximum: int) -> void:
			if health < 100:
				health_updates.append(health)
		)

class Lancer extends "res://scripts/enemy_lancer.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)

var lancer: Lancer
const LANCER_ID := 501

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	world.position = Vector2(140.0, -90.0)
	for id in [1, client_id]:
		var actor := HazardPlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.position = Vector2.ZERO if id == 1 else Vector2(10.0, 0.0)
		actor.set_max_health_and_current(100, 100)
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	lancer = Lancer.new()
	lancer.name = "Lancer"
	circle(lancer, 15.0)
	world.add_child(lancer)
	lancer.position = Vector2(-200.0, 70.0)
	lancer.target = local_player
	lancer.target_candidates = [local_player, local_player, remote_player]
	world.enemy_state_sync_broadcaster.register_enemy(lancer, LANCER_ID)

func _send_zones() -> void:
	world._sync_archer_projectile_state_tick(0.2)

func _snapshot() -> Dictionary:
	var local := local_player as HazardPlayer
	var remote := remote_player as HazardPlayer
	return {"local_health": local.get_current_health(), "remote_health": remote.get_current_health(), "local_events": local.damage_events.duplicate(true), "remote_events": remote.damage_events.duplicate(true), "local_updates": local.health_updates.duplicate(), "remote_updates": remote.health_updates.duplicate(), "zones": lancer.zones.size(), "authority": lancer.network_simulation_enabled}

func _inspect(key: String, expected_local: int, expected_remote: int, expected_zones: int = -1) -> Dictionary:
	world.fixture_command.rpc_id(joiner_id, "inspect", {"key": key, "local": expected_local, "remote": expected_remote, "zones": expected_zones})
	check(await until(func(): return results.has(key)), "Joiner reports its received health for " + key)
	return results.get(key, {})

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	check(lancer.network_simulation_enabled, "Host Lancer retains combat authority")
	lancer._land_bolt(world.to_global(Vector2.ZERO))
	_send_zones()
	world.fixture_command.rpc_id(client_id, "probe_replica")
	check(await until(func(): return results.has("replica")), "Joiner receives the real Lancer floor-zone RPC")
	if results.has("replica"):
		var received: Dictionary = results.replica
		check(not received.authority and received.local_health == 100 and received.remote_health == 100, "A replica zone cannot originate damage even when explicitly advanced with damage enabled")
		check(received.local_events.is_empty() and received.remote_events.is_empty(), "Replica advancement invokes no player damage events")
	check(local_player.get_current_health() == 100 and remote_player.get_current_health() == 100, "Replica advancement cannot change authoritative health")
	lancer._process_zones(lancer.zone_tick_interval * 0.5)
	check(local_player.get_current_health() == 92 and remote_player.get_current_health() == 92, "One real floor-zone tick damages both host and joiner players exactly once")
	var first := await _inspect("first_tick", 92, 92)
	if not first.is_empty():
		check(first.local_updates == [92] and first.remote_updates == [92], "Both clients' player nodes receive one host-authored health update")
		check(first.local_events.is_empty() and first.remote_events.is_empty(), "Health replication does not replay the hazard's damage method")
	for actor_variant in [local_player, remote_player]:
		var actor := actor_variant as HazardPlayer
		check(actor.damage_events.size() == 1 and actor.damage_events[0].ability == "lancer_zone_tick" and actor.damage_events[0].final_amount == 8, "Host damage keeps the existing amount and ability attribution for each player")
	lancer.target = remote_player
	local_player.position = Vector2(lancer.zone_radius + 20.0, 0.0)
	lancer.zones[0]["tick_timer"] = 0.0
	lancer._process_zones(0.01)
	check(local_player.get_current_health() == 92 and remote_player.get_current_health() == 84, "Changing chase target preserves radius checks and only damages the player still inside")
	var switched := await _inspect("target_switch", 84, 92)
	if not switched.is_empty():
		check(switched.local_updates == [92, 84] and switched.remote_updates == [92], "Target switching adds one correctly attributed health update")
	lancer.zones[0]["time_left"] = 0.01
	lancer.zones[0]["tick_timer"] = 0.1
	lancer._process_zones(0.2)
	_send_zones()
	check(local_player.get_current_health() == 92 and remote_player.get_current_health() == 84 and lancer.zones.is_empty(), "A hitch cannot damage players on a tick scheduled after expiry")
	var expired := await _inspect("expired", 84, 92, 0)
	if not expired.is_empty():
		check(expired.local_updates == [92, 84] and expired.remote_updates == [92], "Expired-zone replication adds no delayed damage")
	local_player.position = Vector2.ZERO
	lancer.target = null
	lancer._land_bolt(world.to_global(Vector2.ZERO))
	lancer.zones[0]["time_left"] = 0.2
	lancer.zones[0]["tick_timer"] = 0.1
	lancer._process_zones(0.4)
	check(local_player.get_current_health() == 84 and remote_player.get_current_health() == 76, "A legitimate pre-expiry tick survives a hitch and missing chase target")
	var hitch := await _inspect("valid_hitch", 76, 84)
	if not hitch.is_empty():
		check(hitch.local_updates == [92, 84, 76] and hitch.remote_updates == [92, 84], "The legitimate hitch tick reaches each owner once")
		check(hitch.local_events.is_empty() and hitch.remote_events.is_empty(), "Joiner still has no locally authored hazard damage after all phases")
	check((local_player as HazardPlayer).damage_events.size() == 2 and (remote_player as HazardPlayer).damage_events.size() == 3, "Host authored exactly the expected two and three accepted ticks")
	world.fixture_command.rpc_id(client_id, "finish")
	await until(func(): return results.has("finished"))
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"probe_replica":
			check(await until(func(): return lancer.zones.size() == 1), "Joiner receives host-authored zone geometry")
			lancer._process_zones(0.2, true)
			world.fixture_result.rpc_id(1, "replica", _snapshot())
		"inspect":
			check(await until(func(): return local_player.get_current_health() == int(payload.local) and remote_player.get_current_health() == int(payload.remote) and (int(payload.zones) < 0 or lancer.zones.size() == int(payload.zones))), "Production health and zone state reach the joiner: " + String(payload.key))
			world.fixture_result.rpc_id(1, payload.key, _snapshot())
		_:
			super.client_command(command, payload)
