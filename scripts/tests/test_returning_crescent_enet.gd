extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Real production damage and player-cue RPCs over two isolated loopback peers.

class CrescentEnemy extends Enemy:
	var received_hits: Array[Dictionary] = []
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		received_hits.append(context.duplicate(true))
		super.take_damage(amount, context)

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	for id in [1, client_id]:
		var actor := Player.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.position = Vector2(-300.0, -120.0) if id == 1 else Vector2.ZERO
		actor.damage = 100
		actor.apply_trial_power("returning_crescent")
		actor.apply_upgrade("ruinous_impact")
		actor.apply_upgrade("edict_of_the_court")
		if id != 1:
			actor.apply_trial_power("returning_crescent")
		actor.returning_crescent.set_physics_process(false)
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	for id in [101, 102, 103, 104]:
		var target := CrescentEnemy.new()
		target.name = "Enemy_%d" % id
		circle(target, 13.0)
		world.add_child(target)
		target.position = {101: Vector2(100.0, 0.0), 102: Vector2(100.0, 120.0), 103: Vector2(160.0, 120.0), 104: Vector2(-200.0, -120.0)}[id]
		target.health_state.setup(1000, 1000)
		if id == 102:
			target.health_state.current_health = 10
		world.enemy_state_sync_broadcaster.register_enemy(target, id)
	_begin_reward_run()

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	world.fixture_command.rpc_id(client_id, "outbound")
	check(await until(func(): return enemy(101).get_current_health() == 948 and remote_player.returning_crescent.blades.size() == 1), "Joiner outbound blade sends host-owned damage and its presentation through production RPCs")
	var events: Array = (enemy(101) as CrescentEnemy).received_hits
	check(events.size() == 1 and events[0].attack_type == "returning_crescent" and events[0].secondary, "Host receives one explicitly secondary outgoing hit")
	check(events.size() == 1 and events[0].source_peer_id == client_id and events[0].attack_origin.x < 100.0, "Outgoing hit keeps authenticated joiner ownership and real approach origin")
	var remote = remote_player.returning_crescent
	remote.tick(0.10)
	check(enemy(101).get_current_health() == 948 and world.damage_events.size() == 1, "Host replica prediction cannot duplicate joiner damage")
	check(not enemy(101).get_launch_state().active, "Crescent damage cannot arm Ruinous Impact")
	world.fixture_command.rpc_id(client_id, "return")
	check(await until(func(): return enemy(101).get_current_health() == 896 and remote.blades.is_empty()), "Returning hit and reliable blade removal both reach the host")
	check(events.size() == 2 and events[1].attack_origin.x > 100.0, "Return leg supplies its new approach origin over the actual damage RPC")
	check(world.damage_events.size() == 2 and world.damage_events.all(func(event: Dictionary) -> bool: return event.peer == client_id and event.amount == 52), "Host accounts both bounded legs exactly once for the joiner")
	world.fixture_command.rpc_id(client_id, "kill")
	check(await until(func(): return world.kill_peers.size() == 1 and enemy(103).is_slowed()), "A real blade kill activates the host's Edict Burst and survivor Slow")
	var edict_hits: Array = (enemy(103) as CrescentEnemy).received_hits.filter(func(context: Dictionary) -> bool: return String(context.get("attack_type", "")) == "edict_court")
	check(edict_hits.size() == 1 and world.kill_peers == [client_id] and not enemy(103).get_launch_state().active and enemy(103).velocity.is_zero_approx(), "One authenticated Edict Burst retains secondary kill ownership without Push or a second launch")
	world.fixture_command.rpc_id(client_id, "inspect_kill")
	check(await until(func(): return results.has("kill")), "Joiner reports the production kill-notification scope")
	if results.has("kill"):
		check(results.kill.scopes == [true] and results.kill.local_damage_events == 0, "Joiner receives secondary kill scope without recording authority-owned damage locally")
	local_player._try_execute_attack(Vector2.RIGHT)
	local_player.returning_crescent.tick(0.18)
	PlayerReplicationService._flush_pending_cue_events()
	check(enemy(104).get_current_health() == 955, "The host's deliberate attack launches its own correctly scaled blade")
	world.fixture_command.rpc_id(client_id, "inspect_host")
	check(await until(func(): return results.has("host")), "Joiner receives the host's blade through the same presentation channel")
	if results.has("host"):
		check(results.host.count == 1 and results.host.local_damage_events == 0, "Remote host blade is visible without client damage duplication")
	local_player.returning_crescent.cancel()
	remote.cancel()
	world._world_multiplayer_sync_state.current_room_sync_id = 8
	world.fixture_command.rpc_id(client_id, "stale_room")
	check(await until(func(): return results.has("stale_room")), "Delayed old-room state crosses the actual cue channel")
	await create_timer(0.1).timeout
	check(remote.blades.is_empty(), "Old-room packets cannot resurrect blades after room transition")
	world.fixture_command.rpc_id(client_id, "finish")
	await until(func(): return results.has("finished"))
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"outbound":
			check(await until(func(): return not REWARD_INTERACTIONS.current_run().is_empty()), "Native blade Attack starts with the real current run token")
			local_player._try_execute_attack(Vector2.RIGHT)
			local_player.returning_crescent.tick(0.18)
			PlayerReplicationService._flush_pending_cue_events()
			check(local_player.returning_crescent.blades.size() == 1 and enemy(101).get_current_health() == 1000, "Joiner launches on accepted deliberate attack while host retains enemy health authority")
		"return":
			local_player.returning_crescent.tick(0.6)
			PlayerReplicationService._flush_pending_cue_events()
			check(local_player.returning_crescent.blades.is_empty(), "Owner catches its blade and sends removal")
		"kill":
			local_player.position = Vector2(0.0, 120.0)
			local_player.attack_cooldown_left = 0.0
			local_player.attack_lock_time_left = 0.0
			local_player._try_execute_attack(Vector2.RIGHT)
			local_player.returning_crescent.tick(0.18)
			PlayerReplicationService._flush_pending_cue_events()
		"inspect_kill":
			await until(func(): return local_player.kill_scopes.size() == 1)
			local_player.returning_crescent.cancel()
			PlayerReplicationService._flush_pending_cue_events()
			world.fixture_result.rpc_id(1, "kill", {"scopes": local_player.kill_scopes, "local_damage_events": world.damage_events.size()})
		"inspect_host":
			await until(func(): return remote_player.returning_crescent.blades.size() == 1)
			remote_player.returning_crescent.tick(0.1)
			world.fixture_result.rpc_id(1, "host", {"count": remote_player.returning_crescent.blades.size(), "local_damage_events": world.damage_events.size()})
		"stale_room":
			local_player.returning_crescent.try_launch(Vector2.UP)
			PlayerReplicationService._flush_pending_cue_events()
			world.fixture_result.rpc_id(1, "stale_room", {})
		_:
			super.client_command(command, payload)
