extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Separate host/joiner processes exercise the production enemy ability RPC.

const ALTERNATIVE_TEST := preload("res://scripts/tests/test_alternative_bosses.gd")
var bosses: Array = []
var boss: Node2D
var boss_index: int = 0

func _run() -> void:
	await super._run()
	if is_instance_valid(deadline_timer):
		deadline_timer.start(22.0)

class AlternativePlayer extends Player:
	var damage_contexts: Array[Dictionary] = []
	func _ready() -> void:
		super._ready()
		damage_taken.connect(func(_raw: int, _final: int, context: Dictionary): damage_contexts.append(context.duplicate(true)))

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	world.position = Vector2(40.0, -60.0)
	world.current_room_size = Vector2(1800.0, 1100.0)
	world.current_effective_room_size = world.current_room_size
	for id in [1, client_id]:
		var actor := AlternativePlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.set_max_health_and_current(500, 500)
		actor.arcana_motion.set_process(false)
		actor.returning_crescent.set_physics_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	for index in range(ALTERNATIVE_TEST.IDS.size()):
		var enemy := ALTERNATIVE_TEST.Alternative.new()
		enemy.boss_id = ALTERNATIVE_TEST.IDS[index]
		enemy.name = "AlternativeBoss%d" % index
		circle(enemy, 34.0)
		world.add_child(enemy)
		enemy.position = Vector2(-750.0, 350.0)
		enemy.target = local_player
		enemy.target_candidates = [local_player, local_player, remote_player]
		world.enemy_state_sync_broadcaster.register_enemy(enemy, 851 + index)
		enemy.set_physics_process(false)
		bosses.append(enemy)

func _reset_players() -> void:
	for actor_variant in [local_player, remote_player]:
		var actor := actor_variant as AlternativePlayer
		actor.discard_pending_combat_input()
		actor.set_max_health_and_current(500, 500)
		actor.set_combat_damage_enabled(true)
		actor._dash_damage_immune_left = 0.0
		actor._contact_damage_grace_left = 0.0
		actor.damage_contexts.clear()
	local_player.global_position = boss.global_position + Vector2(170.0, 10.0)
	remote_player.global_position = local_player.global_position

func _send_state(packet: Dictionary = {}, room_id: int = 7) -> Dictionary:
	var actual: Dictionary = boss.get_projectile_network_sync_state() if packet.is_empty() else packet
	world._sync_archer_projectile_states.rpc([{"enemy_id": 851 + boss_index, "payload": actual}], room_id)
	return actual

func _snapshot() -> Dictionary:
	return {
		"geometry": boss.get_attack_warning_geometry(), "id": boss.boss_id,
		"local_health": local_player.get_current_health(), "remote_health": remote_player.get_current_health(),
		"local_calls": (local_player as AlternativePlayer).damage_contexts.size(),
		"remote_calls": (remote_player as AlternativePlayer).damage_contexts.size(),
		"snapshot": boss._received_snapshot, "phase": boss.boss_state,
	}

func _inspect(client_id: int, key: String, options: Dictionary = {}) -> Dictionary:
	var payload := options.duplicate(true)
	payload["index"] = boss_index
	payload["key"] = key
	world.fixture_command.rpc_id(client_id, "inspect", payload)
	check(await until(func(): return results.has(key), 4.0), key + ": joiner replies")
	return results.get(key, {})

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	await physics_frame
	for index in range(bosses.size()):
		boss_index = index
		boss = bosses[index]
		boss.position = Vector2(-120.0, 0.0)
		for kind in range(3):
			_reset_players()
			boss._cancel_attack()
			boss.begin_attack(kind)
			var geometry: Array = boss.get_attack_warning_geometry()
			var label := "%s_%d" % [boss.boss_id, kind]
			var hit_position: Vector2 = Vector2.ZERO
			var safe_position: Vector2 = Vector2.ZERO
			for point in ALTERNATIVE_TEST.sample_points(geometry, boss.global_position):
				if ALTERNATIVE_TEST.warning_contains(geometry, point):
					hit_position = point
				else:
					safe_position = point
			var packet := _send_state()
			var packet_bytes := var_to_bytes([{"enemy_id": 851 + index, "payload": packet}]).size() + 15
			check(packet_bytes <= 1392, label + ": warning fits an uncached ENet packet")
			print("[ENet] ", label, " warning bytes=", packet_bytes)
			var received := await _inspect(client_id, label + "_warning", {"expected_geometry": geometry, "try_damage": hit_position})
			check(received.get("geometry", []) == geometry and received.get("id", "") == boss.boss_id, label + ": host identity and committed geometry arrive exactly")
			check(received.get("local_calls", -1) == 0 and received.get("remote_calls", -1) == 0, label + ": joiner cannot resolve boss damage")
			var quantized: Dictionary = world.enemy_state_sync_broadcaster._quantize_runtime_state_for_network(boss.get_network_runtime_state())
			world._sync_enemy_states.rpc([{"enemy_id": 851 + index, "runtime_state_delta": quantized}], 3)
			received = await _inspect(client_id, label + "_quantized_runtime")
			check(received.get("geometry", []) == geometry, label + ": quantized body state cannot move the exact committed warning")
			# Interpolation and later target movement cannot drag a committed warning.
			local_player.global_position = hit_position
			remote_player.global_position = safe_position
			boss._resolve_attack()
			check(local_player.get_current_health() < 500 and remote_player.get_current_health() == 500, label + ": host damages the marked region and preserves its safe zone")
			check((local_player as AlternativePlayer).damage_contexts.size() == 1, label + ": duplicated candidates produce one host hit")
			_send_state()
			received = await _inspect(client_id, label + "_resolved", {"expected_geometry": [], "health": {"host": local_player.get_current_health(), "joiner": 500}})
			check(received.get("local_calls", -1) == 0 and received.get("remote_calls", -1) == 0, label + ": health synchronization does not replay damage")
			_send_state(packet)
			received = await _inspect(client_id, label + "_stale")
			check(received.get("geometry", []).is_empty(), label + ": old warning cannot return after authoritative resolution")
			boss.begin_attack(kind)
			_send_state({}, 6)
			received = await _inspect(client_id, label + "_wrong_room")
			check(received.get("geometry", []).is_empty(), label + ": prior-room packets cannot create a warning")
			_send_state()
			received = await _inspect(client_id, label + "_expire", {"expected_geometry": boss.get_attack_warning_geometry(), "expire": true})
			check(received.get("geometry", []).is_empty(), label + ": lost final packet still expires the joiner warning")
			boss._cancel_attack()
		boss.position = Vector2(-750.0, 350.0)
	world.fixture_command.rpc_id(client_id, "finish")
	await until(func(): return results.has("finished"))
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"inspect":
			boss_index = int(payload.index)
			boss = bosses[boss_index]
			if payload.has("expected_geometry"):
				var matched := await until(func(): return boss.get_attack_warning_geometry() == payload.expected_geometry)
				check(matched, "Joiner receives the expected live warning state: " + String(payload.key))
				if not matched:
					print("[ENet] warning mismatch ", payload.key, " actual=", _snapshot(), " expected=", payload.expected_geometry)
			if payload.has("try_damage"):
				_reset_players()
				local_player.global_position = payload.try_damage
				remote_player.global_position = payload.try_damage
				boss._resolve_attack()
			if payload.has("health"):
				check(await until(func(): return local_player.get_current_health() == int(payload.health.joiner) and remote_player.get_current_health() == int(payload.health.host)), "Joiner receives authoritative player health")
			if bool(payload.get("expire", false)):
				boss._process_network_visuals(5.0)
			world.fixture_result.rpc_id(1, payload.key, _snapshot())
		"finish":
			world.fixture_result.rpc_id(1, "finished", {})
			await create_timer(0.1).timeout
			await finish()
