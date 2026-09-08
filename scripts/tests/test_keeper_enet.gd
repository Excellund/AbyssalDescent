extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Reuse the bounded two-process transport and production World RPC harness.

const KEEPER := preload("res://scripts/tests/test_keeper_runtime.gd")
var keeper: KEEPER.Keeper

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	for id in [1, client_id]:
		var actor := Player.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.position = Vector2(-500.0, 0.0)
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	for id in [101, 102, 103]:
		var target := Enemy.new()
		target.name = "Enemy_%d" % id
		circle(target, 13.0)
		world.add_child(target)
		target.position = Vector2(70.0 + (id - 101) * 55.0, 0.0)
		world.enemy_state_sync_broadcaster.register_enemy(target, id)
	keeper = KEEPER.Keeper.new()
	keeper.name = "Keeper"
	circle(keeper, 17.0)
	world.add_child(keeper)
	world.enemy_state_sync_broadcaster.register_enemy(keeper, 201)

func _sync_keeper(sequence: int) -> void:
	world._sync_enemy_states.rpc([{"enemy_id": 201, "health": keeper.get_current_health(), "position": keeper.position, "runtime_state_delta": keeper.get_network_runtime_state()}], sequence)

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	await physics_frame
	await process_frame
	keeper._update_wards(0.001)
	keeper._update_wards(0.61)
	check(keeper.ward_targets.size() == 2 and not keeper.ward_targets.has(enemy(103)), "Real host Keeper protects exactly two of three nearby allies")
	_sync_keeper(1)
	world.fixture_command.rpc_id(client_id, "inspect_links")
	check(await until(func(): return results.has("links")), "Joiner receives Keeper links through production enemy state RPC")
	if results.has("links"):
		check(results.links.ids == [101, 102] and results.links.multiplier == 1.0 and not results.links.authoritative, "Stable network IDs resolve visual allies without granting client ward authority")
	world.fixture_command.rpc_id(client_id, "protected_hit")
	check(await until(func(): return enemy(101).get_current_health() == 30), "Joiner requests 100 damage and the host applies exactly 70")
	check(world.damage_events.size() == 1 and world.damage_events[0].amount == 70 and world.damage_events[0].peer == client_id, "Host records actual mitigated damage for the authenticated joiner")
	check(EnemyReplicationService.killer_peer_for(101) == client_id, "Spoofed source context cannot steal the joiner's damage ownership")
	world.fixture_command.rpc_id(client_id, "protected_kill")
	check(await until(func(): return world.kill_peers.size() == 1), "Protected secondary kill crosses the real ownership notification path")
	check(world.damage_events.back().amount == 30 and world.damage_events.back().killed and world.kill_peers == [client_id], "Lethal protected hit credits only remaining health and the correct kill owner")
	keeper._update_wards(0.0)
	_sync_keeper(2)
	world.fixture_command.rpc_id(client_id, "inspect_death")
	check(await until(func(): return results.has("death")), "Joiner observes removal of a dead linked target")
	if results.has("death"):
		check(results.death.ids == [102] and results.death.local_damage_events == 0, "Remote ward visuals prune the dead ID without duplicating combat accounting")
	world.fixture_command.rpc_id(client_id, "push_keeper")
	check(await until(func(): return keeper.ward_targets.is_empty() and keeper.ward_rearm_left > 1.0), "Authenticated joiner push interrupts all host wards")
	_sync_keeper(3)
	world.fixture_command.rpc_id(client_id, "inspect_break")
	check(await until(func(): return results.has("break")), "Joiner receives the ward interruption state")
	if results.has("break"):
		check(results["break"].ids.is_empty() and results["break"].rearm > 1.0, "Both processes agree on broken links and rearm feedback")
	world.fixture_command.rpc_id(client_id, "finish")
	await until(func(): return results.has("finished"))
	await finish()

func _linked_ids() -> Array[int]:
	var ids: Array[int] = []
	for target in keeper.ward_targets:
		if is_instance_valid(target):
			ids.append(int(target.get_meta("network_enemy_id", 0)))
	ids.sort()
	return ids

func client_command(command: String, _payload: Dictionary) -> void:
	match command:
		"inspect_links":
			await until(func(): return keeper.ward_targets.size() == 2)
			world.fixture_result.rpc_id(1, "links", {"ids": _linked_ids(), "multiplier": keeper.get_ward_damage_multiplier_for(enemy(101)), "authoritative": keeper.network_simulation_enabled})
		"protected_hit":
			DAMAGE.apply_damage(enemy(101), 100, {"attack_type": "blast_drive", "source_peer_id": 1})
			check(enemy(101).get_current_health() == 100 and world.damage_events.is_empty(), "Joiner sends raw damage without changing health or stats locally")
		"protected_kill":
			DAMAGE.apply_damage(enemy(101), 100, {"attack_type": "sovereigns_double", "secondary": true})
		"inspect_death":
			await until(func(): return _linked_ids() == [102])
			world.fixture_result.rpc_id(1, "death", {"ids": _linked_ids(), "local_damage_events": world.damage_events.size()})
		"push_keeper":
			DAMAGE.apply_impulse(keeper, Vector2(200.0, 0.0))
		"inspect_break":
			await until(func(): return keeper.ward_targets.is_empty() and keeper.ward_rearm_left > 1.0)
			world.fixture_result.rpc_id(1, "break", {"ids": _linked_ids(), "rearm": keeper.ward_rearm_left})
		"finish":
			world.fixture_result.rpc_id(1, "finished", {})
			await create_timer(0.1).timeout
			await finish()
