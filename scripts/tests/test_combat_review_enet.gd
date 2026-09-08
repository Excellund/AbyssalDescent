extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Production RPC/broadcaster/receiver paths, with one deliberate lost packet.

class Shield extends "res://scripts/enemy_shielder.gd":
	var received_revisions: Array[int] = []
	var discard_revision: int = -1
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _apply_custom_network_runtime_state(state: Dictionary) -> void:
		var revision := int(state.get("q", -1))
		received_revisions.append(revision)
		if revision == discard_revision:
			discard_revision = -1
			return # Model one lost final-turn payload before applying it.
		super._apply_custom_network_runtime_state(state)

class IndicatorPlayer extends "res://scripts/tests/test_boss_combinations_enet.gd".Player:
	var received_shapes: Array[Polygon2D] = []
	func play_network_attack_indicator(direction: Vector2, reach: float, arc: float, color: Color, duration: float = 0.12, origin: Vector2 = Vector2.INF, inner: float = 0.0) -> void:
		super.play_network_attack_indicator(direction, reach, arc, color, duration, origin, inner)
		for child in player_feedback.get_children():
			if child is Polygon2D and not received_shapes.has(child):
				received_shapes.append(child)

var shield: Shield
const SHIELD_ID := 201
const STRIKE_ORIGIN := Vector2(211.25, -113.75)
const MOVED_POSITION := Vector2(500.0, 100.0)

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	for id in [1, client_id]:
		var actor := IndicatorPlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.position = Vector2(-180.0, 0.0) if id == 1 else Vector2(180.0, 0.0)
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
		actor.player_feedback._aux_sfx_player = null
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	shield = Shield.new()
	shield.name = "Shielder"
	circle(shield, 15.0)
	world.add_child(shield)
	shield.set_max_health_and_current(1000)
	shield.shield_facing = Vector2.LEFT
	shield.shield_target_facing = Vector2.LEFT
	shield.target = local_player if role == "host" else remote_player
	world.enemy_state_sync_broadcaster.register_enemy(shield, SHIELD_ID)
	for index in range(63):
		var target := Enemy.new()
		target.name = "Crowd_%d" % index
		world.add_child(target)
		target.position = Vector2(1000.0 + index * 25.0, 500.0)
		world.enemy_state_sync_broadcaster.register_enemy(target, 300 + index)
	world.active_room_enemy_count = 64

func _tick_broadcaster() -> void:
	# At 64 enemies the production scan is bounded to 28; cover one full scan.
	for index in range(3):
		world.enemy_state_sync_broadcaster.tick(0.25)

func _send_custom(custom: Dictionary) -> void:
	world._sync_enemy_states.rpc([{"enemy_id": SHIELD_ID, "runtime_state_delta": {"custom": custom}}], 64)

func _inspect(key: String, expected_revision: int, expected_deliveries: int = 1) -> Dictionary:
	world.fixture_command.rpc_id(joiner_id, "inspect_shield", {"key": key, "revision": expected_revision, "deliveries": expected_deliveries})
	check(await until(func(): return results.has(key)), "Joiner reports shield state for %s" % key)
	return results.get(key, {})

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	check(EnemyReplicationService.enemy_nodes_by_id.size() == 64, "Fixture exercises crowded-room filtering with 64 registered enemies")
	world.fixture_command.rpc_id(client_id, "rear_strike")
	check(await until(func(): return shield.get_current_health() == 900), "Joiner's rear strike deals full damage while Shielder targets the host in front")
	check(world.damage_events.size() == 1 and world.damage_events.back().amount == 100 and world.damage_events.back().peer == client_id, "Rear hit records the authenticated joiner and accepted health delta")
	check(EnemyReplicationService.killer_peer_for(SHIELD_ID) == client_id, "Spoofed host source context cannot steal hit ownership")
	local_player.position = Vector2(180.0, 0.0)
	remote_player.position = Vector2(-180.0, 0.0)
	world.fixture_command.rpc_id(client_id, "front_strike")
	check(await until(func(): return world.damage_events.size() == 2), "Front strike reaches the host through the authenticated damage RPC")
	var front_damage := 900 - shield.get_current_health()
	check(front_damage > 0 and front_damage < 100, "Shield mitigates the joiner's front strike even while its AI targets the host behind it")
	check(world.damage_events.back().peer == client_id and world.damage_events.back().amount == front_damage, "Host replaces a raw spoofed peer field before front-hit accounting")
	var before_ground := shield.get_current_health()
	world.fixture_command.rpc_id(client_id, "ground_strike")
	check(await until(func(): return shield.get_current_health() == before_ground - 100), "Ground damage still bypasses directional protection")
	check(world.damage_events.back().peer == client_id and world.damage_events.back().amount == 100, "Ground bypass preserves host accounting")

	shield.shield_facing = Vector2.from_angle(0.23789)
	shield.shield_target_facing = shield.shield_facing
	shield._update_shield_facing(0.0)
	var first_state := shield._get_custom_network_runtime_state()
	_tick_broadcaster()
	var first := await _inspect("first", first_state.q)
	if not first.is_empty():
		check(absf(float(first.angle) - 0.23789) <= 0.00006, "Integer shield angle survives real crowded broadcaster quantization precisely")
		check(not first.authority and first.slam_idle, "Idle replica receives orientation without local combat authority")
	check(shield.get_projectile_network_sync_state().is_empty(), "Idle shield orientation uses runtime state, not the legacy projectile channel")

	_send_custom({"q": int(first_state.q) - 1, "a": -12000})
	var replay := await _inspect("replay", int(first_state.q) - 1)
	if not replay.is_empty():
		check(replay.revision == first_state.q and absf(float(replay.angle) - 0.23789) <= 0.00006, "Old q cannot replay a different shield direction")
	_send_custom({"q": first_state.q, "a": 15000})
	var duplicate := await _inspect("duplicate", first_state.q, 2)
	if not duplicate.is_empty():
		check(duplicate.revision == first_state.q and absf(float(duplicate.angle) - 0.23789) <= 0.00006, "Duplicate q cannot overwrite the accepted shield direction")

	shield.shield_facing = Vector2.from_angle(-1.23456)
	shield.shield_target_facing = shield.shield_facing
	shield._update_shield_facing(0.21)
	var lost_state := shield._get_custom_network_runtime_state()
	world.fixture_command.rpc_id(client_id, "discard_revision", {"q": lost_state.q})
	check(await until(func(): return results.has("discard_ready")), "Joiner arms one deliberate dropped final-turn payload")
	_tick_broadcaster()
	var lost := await _inspect("lost", lost_state.q)
	if not lost.is_empty():
		check(lost.revision == first_state.q, "Lost final-turn payload leaves the previous accepted orientation intact")
	shield._update_shield_facing(0.21)
	var heartbeat := shield._get_custom_network_runtime_state()
	_tick_broadcaster()
	var recovered := await _inspect("heartbeat", heartbeat.q)
	if not recovered.is_empty():
		check(recovered.revision == heartbeat.q and absf(float(recovered.angle) + 1.23456) <= 0.00006, "Unchanged idle heartbeat repairs the dropped direction through the real broadcaster")

	world.fixture_command.rpc_id(client_id, "attack_indicator")
	var actor := remote_player as IndicatorPlayer
	check(await until(func(): return not actor.received_shapes.is_empty() and actor.global_position == MOVED_POSITION), "Real attack-indicator and movement RPCs arrive from the joiner")
	if not actor.received_shapes.is_empty():
		var shape := actor.received_shapes.back() as Polygon2D
		check(is_instance_valid(shape) and shape.global_position == STRIKE_ORIGIN, "Remote strike remains at its explicit fractional world origin after attacker movement")
		if is_instance_valid(shape):
			var minimum := INF
			var maximum := 0.0
			for point in shape.polygon:
				minimum = minf(minimum, point.length())
				maximum = maxf(maximum, point.length())
			check(is_equal_approx(minimum, 40.0) and is_equal_approx(maximum, 90.0), "Remote Razor Wind indicator preserves its hollow 40–90 pixel band")
	world.fixture_command.rpc_id(client_id, "finish")
	await until(func(): return results.has("finished"))
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"rear_strike":
			DAMAGE.apply_damage(shield, 100, {"attack_type": "melee", "attack_origin": Vector2(180.0, 0.0), "source_peer_id": 1}, 1)
			check(shield.get_current_health() == 1000 and world.damage_events.is_empty(), "Joiner routes rear damage without changing local health or statistics")
		"front_strike":
			local_player.position = Vector2(-180.0, 0.0)
			world.request_enemy_damage_from_client(SHIELD_ID, 100, {"attack_type": "melee", "attack_origin": local_player.position, "source_peer_id": 1})
		"ground_strike":
			DAMAGE.apply_damage(shield, 100, {"attack_type": "sovereigns_double", "secondary": true, "is_ground_attack": true, "attack_origin": Vector2(-180.0, 0.0)})
		"inspect_shield":
			check(await until(func(): return shield.received_revisions.count(int(payload.revision)) >= int(payload.deliveries)), "Production receiver delivers the requested custom shield revision, including duplicate packets")
			world.fixture_result.rpc_id(1, payload.key, {"revision": shield._remote_shield_revision, "angle": shield.shield_facing.angle(), "authority": shield.network_simulation_enabled, "slam_idle": shield.slam_state == 0})
		"discard_revision":
			shield.discard_revision = int(payload.q)
			world.fixture_result.rpc_id(1, "discard_ready", {})
		"attack_indicator":
			local_player.global_position = STRIKE_ORIGIN
			PlayerReplicationService.broadcast_attack_indicator(joiner_id, Vector2.RIGHT, 90.0, 80.0, Color.WHITE, 1.0, STRIKE_ORIGIN, 40.0)
			local_player.global_position = MOVED_POSITION
			PlayerReplicationService._sync_all_player_positions()
			check(local_player.global_position != STRIKE_ORIGIN, "Joiner moves away immediately after transmitting the strike origin")
		"finish":
			world.fixture_result.rpc_id(1, "finished", {})
			await create_timer(0.1).timeout
			await finish()
