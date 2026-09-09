extends "res://scripts/tests/test_boss_combinations_enet.gd"
## The same cluster is resolved through the joiner's actual damage/kill RPCs
## and the host's synchronous path. Production non-chaining rules must agree.

class ProcPlayer extends Player:
	var field_calls: int = 0
	var echo_calls: int = 0
	var kill_provenance: Array[Dictionary] = []
	func notify_enemy_killed(position: Vector2 = Vector2.INF) -> void:
		kill_provenance.append({"mask": DAMAGE.get_kill_proc_suppression(), "secondary": DAMAGE.is_launch_suppressed()})
		super.notify_enemy_killed(position)
	func _apply_void_echo(position: Vector2) -> void:
		echo_calls += 1
		super._apply_void_echo(position)
	func _apply_fracture_field(position: Vector2) -> void:
		field_calls += 1
		super._apply_fracture_field(position)

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	for id in [1, client_id]:
		var actor := ProcPlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.position = Vector2(-500.0, 0.0)
		actor.damage = 100
		actor.apply_trial_power("fracture_field")
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	for id in [101, 102, 103, 201, 202, 203, 301, 302, 303, 401, 402, 403, 501, 502, 503]:
		var target := Enemy.new()
		target.name = "Enemy_%d" % id
		circle(target, 13.0)
		world.add_child(target)
		# All three bodies overlap deliberately: every random fault-line angle
		# hits the survivors, keeping the regression independent of RNG.
		target.position = Vector2(float(id / 100) * 300.0, 0.0)
		target.health_state.setup(1000, 1000)
		if id % 100 <= 2:
			target.health_state.current_health = 10
		world.enemy_state_sync_broadcaster.register_enemy(target, id)

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	world.fixture_command.rpc_id(client_id, "kill", {"enemy": 101, "secondary": false})
	check(await until(func(): return world.kill_peers.size() >= 2), "Joiner's primary kill and its single Fracture kill reach the host")
	world.fixture_command.rpc_id(client_id, "inspect", {"key": "ordinary"})
	check(await until(func(): return results.has("ordinary")), "Joiner reports completed primary-kill callbacks")
	if results.has("ordinary"):
		var ordinary: Dictionary = results.ordinary
		check(ordinary.fields == 1 and enemy(103).get_current_health() == 958, "An ordinary joiner kill produces one non-chaining Fracture, dealing 42 damage to the survivor")
		check(ordinary.provenance == [{"mask": 0, "secondary": false}, {"mask": 1, "secondary": false}], "Fracture transports only its own restriction without changing the ordinary damage class")
		check(ordinary.scope == 0 and not ordinary.secondary_scope, "The joiner releases both scopes after ordinary kill callbacks")
	world.fixture_command.rpc_id(client_id, "kill", {"enemy": 201, "secondary": true})
	check(await until(func(): return world.kill_peers.size() >= 4), "A secondary initial kill retains its Fracture benefit and kill credit")
	world.fixture_command.rpc_id(client_id, "inspect", {"key": "secondary"})
	check(await until(func(): return results.has("secondary")), "Joiner reports completed secondary-kill callbacks")
	if results.has("secondary"):
		var secondary: Dictionary = results.secondary
		check(secondary.fields == 2 and enemy(203).get_current_health() == 958, "Secondary initial kills still produce exactly one non-chaining Fracture")
		check(secondary.provenance.slice(2) == [{"mask": 0, "secondary": true}, {"mask": 1, "secondary": true}], "Fracture restriction and inherited secondary classification survive both RPC directions independently")
		check(secondary.scope == 0 and not secondary.secondary_scope, "Secondary kill callbacks cannot leak suppression into later kills")
	check(world.kill_peers == [client_id, client_id, client_id, client_id], "Both kinds of descendant kills remain attributed to their actual owner")
	DAMAGE.apply_damage(enemy(301), 20, {"attack_type": "melee"}, 1)
	check((local_player as ProcPlayer).field_calls == 1 and enemy(303).get_current_health() == 958, "The host retains its identical single-field behavior")
	world.fixture_command.rpc_id(client_id, "lacuna_start")
	check(await until(func(): return world.kill_peers.size() >= 7), "New ordinary kill can start Lacuna after prior restricted kills")
	world.fixture_command.rpc_id(client_id, "lacuna_pulse")
	check(await until(func(): return world.kill_peers.size() >= 8), "Lacuna's deferred pulse kill reaches the host")
	world.fixture_command.rpc_id(client_id, "lacuna_inspect")
	check(await until(func(): return results.has("lacuna")), "Joiner reports its deferred-pulse callback state")
	local_player.reward_fracture_field = false
	local_player.apply_upgrade("lacuna_echo")
	local_player.apply_trial_power("eclipse_mark")
	DAMAGE.apply_damage(enemy(501), 20, {"attack_type": "melee"}, 1)
	local_player._eclipse_marked_enemies.clear()
	local_player._update_void_echo_zones(0.33)
	if results.has("lacuna"):
		var lacuna: Dictionary = results.lacuna
		check(lacuna.calls == 1 and is_equal_approx(float(lacuna.life), 2.07) and not lacuna.marked, "Joiner Lacuna pulse neither renews its zone nor reapplies Eclipse Mark")
		check(lacuna.provenance.slice(4) == [{"mask": 0, "secondary": false}, {"mask": 2, "secondary": false}], "Lacuna's deferred pulse carries its own narrow provenance")
		check(lacuna.scope == 0 and not lacuna.secondary_scope, "Deferred pulse notification releases its scope")
	check((local_player as ProcPlayer).echo_calls == 1 and is_equal_approx(float(local_player.void_echo_zones[0].life), 2.07) and not local_player._eclipse_marked_enemies.has(enemy(503).get_instance_id()), "Host Lacuna retains the same lifetime and mark restrictions")
	check(DAMAGE.get_kill_proc_suppression() == 0 and not DAMAGE.is_launch_suppressed(), "Host damage and nested kill callbacks leave no scope active")
	world.fixture_command.rpc_id(client_id, "finish")
	await until(func(): return results.has("finished"))
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"kill": DAMAGE.apply_damage(enemy(int(payload.enemy)), 20, {"attack_type": "melee" if not payload.secondary else "sovereigns_double", "secondary": payload.secondary})
		"inspect": world.fixture_result.rpc_id(1, payload.key, _local_proc_state())
		"lacuna_start":
			local_player.reward_fracture_field = false
			local_player.apply_upgrade("lacuna_echo")
			local_player.apply_trial_power("eclipse_mark")
			DAMAGE.apply_damage(enemy(401), 20, {"attack_type": "melee"})
		"lacuna_pulse":
			local_player._eclipse_marked_enemies.clear()
			local_player._update_void_echo_zones(0.33)
		"lacuna_inspect":
			var state := _local_proc_state()
			state["calls"] = (local_player as ProcPlayer).echo_calls
			state["life"] = local_player.void_echo_zones[0].life
			state["marked"] = local_player._eclipse_marked_enemies.has(enemy(403).get_instance_id())
			world.fixture_result.rpc_id(1, "lacuna", state)
		_: super.client_command(command, payload)

## Returns a fresh report; nested provenance entries are copied for RPC use.
func _local_proc_state() -> Dictionary:
	return {"fields": (local_player as ProcPlayer).field_calls, "provenance": (local_player as ProcPlayer).kill_provenance.duplicate(true), "scope": DAMAGE.get_kill_proc_suppression(), "secondary_scope": DAMAGE.is_launch_suppressed()}
