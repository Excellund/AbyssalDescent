extends "res://scripts/tests/test_boss_combinations_enet.gd"
const CALLOUT_TEST := preload("res://scripts/tests/test_boss_callouts.gd")
const PARITY_TEST := preload("res://scripts/tests/test_boss_callout_parity.gd")
var callout_bosses: Array[Node2D] = []

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	for id in [1, client_id]:
		var actor := Player.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.position = Vector2(200, 60)
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
		actor.returning_crescent.set_physics_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else: remote_player = actor
	for family in range(CALLOUT_TEST.SCRIPTS.size()):
		var boss: Node2D = CALLOUT_TEST.SCRIPTS[family].new()
		boss.name = "CalloutBoss%d" % family
		circle(boss, 34.0)
		world.add_child(boss)
		boss.set("target", local_player)
		boss.set("target_candidates", [local_player, remote_player])
		world.enemy_state_sync_broadcaster.register_enemy(boss, 930 + family)
		boss.set_physics_process(false)
		callout_bosses.append(boss)

func _send(family: int, precise: bool = false) -> void:
	var boss := callout_bosses[family]
	if family == 2 or precise:
		world._sync_archer_projectile_states.rpc([{"enemy_id": 930 + family, "payload": boss.call("get_projectile_network_sync_state")}], 7)
	else:
		world._sync_enemy_states.rpc([{"enemy_id": 930 + family, "runtime_state_delta": {"custom": boss.call("_get_custom_network_runtime_state")}}], 1)

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	for family in range(callout_bosses.size()):
		var boss := callout_bosses[family]
		for move in range(CALLOUT_TEST.COUNTS[family]):
			CALLOUT_TEST.prepare(boss, family, move)
			var expected: String = boss.call("get_attack_callout")
			check(not expected.is_empty(), "Host committed move has a name")
			_send(family)
			var key := "%d_%d" % [family, move]
			world.fixture_command.rpc_id(client_id, "callout", {"key": key, "family": family, "expected": expected})
			check(await until(func(): return results.has(key)), "Joiner acknowledges " + key)
			if results.has(key): check(results[key].text == expected, "Received native state reproduces " + expected)
			CALLOUT_TEST.clear_move(boss, family)
			_send(family)
			var clear_key := key + "_clear"
			world.fixture_command.rpc_id(client_id, "callout", {"key": clear_key, "family": family, "expected": ""})
			check(await until(func(): return results.has(clear_key)), "Joiner acknowledges recovery")
			if results.has(clear_key): check(results[clear_key].text.is_empty(), "Native recovery clears move name")
	var sovereign := callout_bosses[1]
	PARITY_TEST.begin_echo_chain(sovereign)
	for leg in range(1, 4):
		await _exchange_followup(1, "echo_leg_%d" % leg, "Echo Dash / %d" % leg, client_id)
		sovereign.call("_process_attack_state", float(sovereign.get("echo_dash_duration")) + .001)
		if leg < 3:
			await _exchange_followup(1, "echo_retarget_%d" % (leg + 1), "Echo Dash / %d" % (leg + 1), client_id, float(sovereign.get("echo_dash_retarget_pause")) + .001)
			sovereign.call("_process_attack_state", float(sovereign.get("echo_dash_retarget_pause")) + .001)
	PARITY_TEST.begin_echo_chain(sovereign, true)
	await _exchange_followup(1, "reposition", "Reposition", client_id)
	var lacuna := callout_bosses[2]
	CALLOUT_TEST.prepare(lacuna, 2, 1)
	lacuna.call("_enter_attack_state")
	await _exchange_followup(2, "null_collapse", "Null Ring / COLLAPSE", client_id, float(lacuna.get("null_ring_pull_delay")) + .001)
	world.fixture_command.rpc_id(client_id, "finish_callouts")
	check(await until(func(): return results.has("finished")), "Joiner finishes")
	await finish()

func _exchange_followup(family: int, key: String, expected: String, client_id: int, expire_after: float = 0.0) -> void:
	check(callout_bosses[family].call("get_attack_callout") == expected, "Host native transition announces " + expected)
	_send(family, true)
	world.fixture_command.rpc_id(client_id, "followup_callout", {"key": key, "family": family, "expected": expected, "expire_after": expire_after})
	check(await until(func(): return results.has(key)), "Joiner acknowledges actual follow-up " + key)
	if results.has(key):
		check(results[key].text == expected and bool(results[key].expired), "Precise replication and bounded local expiry agree for " + expected)

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"followup_callout":
			var boss := callout_bosses[int(payload.family)]
			check(await until(func(): return boss.call("get_attack_callout") == payload.expected), "Precise native state delivers the actual follow-up warning")
			var text: String = boss.call("get_attack_callout")
			var expired := true
			if float(payload.expire_after) > 0.0:
				boss.call("_process_network_visuals", float(payload.expire_after))
				expired = boss.call("get_attack_callout").is_empty()
				check(expired, "Missing follow-up packets cannot leave the old warning announcement forever")
			check(not bool(boss.get("network_simulation_enabled")), "Follow-up presentation never grants damage authority")
			world.fixture_result.rpc_id(1, payload.key, {"text": text, "expired": expired})
		"callout":
			var boss := callout_bosses[int(payload.family)]
			check(await until(func(): return boss.call("get_attack_callout") == payload.expected), "Production replication delivers the expected callout")
			check(not bool(boss.get("network_simulation_enabled")), "Move names do not grant simulation authority")
			world.fixture_result.rpc_id(1, payload.key, {"text": boss.call("get_attack_callout")})
		"finish_callouts":
			local_player.visible = false
			remote_player.visible = false
			world.fixture_result.rpc_id(1, "finished", {})
			await create_timer(0.05).timeout
			await finish()
		_: super.client_command(command, payload)
