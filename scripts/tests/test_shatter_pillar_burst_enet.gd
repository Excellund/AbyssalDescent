extends "res://scripts/tests/test_brittle_cover_enet.gd"
## Existing native request/cover/health transport, including replay rejection.

var shard_enemy_id := 0
var shard_enemy: Node2D
var player_health_before := 0

func _destroy_and_release_anchor() -> void:
	if role == "host":
		_write("shard-enemy", int(_living()[0].get_meta("network_enemy_id", 0)))
	await _barrier("shard-enemy-id")
	shard_enemy_id = int(_read("shard-enemy"))
	shard_enemy = EnemyReplicationService.enemy_nodes_by_id.get(shard_enemy_id)
	check(is_instance_valid(shard_enemy), "The same native shard target exists on both peers")
	shard_enemy.set_max_health_and_current(500, 500)
	shard_enemy.spawn_transport_time_left = 0.0
	shard_enemy.position = world._arena_cover_bodies[2].position + Vector2(0, 120)
	player_health_before = world.player.get_current_health()
	await _barrier("shard-enemy-positioned")
	await super._destroy_and_release_anchor()
	check(world._biome_rules.shard_bursts.size() == 1, "Confirmed cover break creates one HELP Burst visual on each peer; duplicate states do not replay it")
	check(world.player.get_current_health() == player_health_before, "Both player owners are safe inside the foe-only shard Burst")
	if role == "host":
		check(shard_enemy.get_current_health() == 440, "Third client Attack deals one authoritative 60-damage shard Burst")
	else:
		check(shard_enemy.get_current_health() == 500, "Replica cover visuals cannot independently damage an enemy")
	await _barrier("shard-local-damage-checked")
	if role == "host":
		world._sync_enemy_states.rpc([{"enemy_id": shard_enemy_id, "health": shard_enemy.get_current_health(), "position": shard_enemy.position}], world.active_room_enemy_count)
	await _barrier("shard-health-sent")
	check(await _until(func(): return shard_enemy.get_current_health() == 440), "Ordinary native health replication delivers exactly the host result")
	world._tick_biome_rules(1.0)
	check(world._biome_rules.shard_bursts.is_empty() and shard_enemy.get_current_health() == 440, "Cosmetic expiry neither repeats damage nor leaves a stale HELP marker")
	if role == "host":
		world._sync_brittle_cover_state.rpc(world._cover_state_payload())
	else:
		_swing()
	await _barrier("shard-expired-replay")
	check(world._biome_rules.shard_bursts.is_empty() and shard_enemy.get_current_health() == 440, "Duplicate cover state and new rubble Attack cannot resurrect an expired Burst")

func _pulse_state_roundtrip() -> void:
	await super._pulse_state_roundtrip()
	check(world._biome_rules.shard_bursts.is_empty(), "Native room transition clears all old shard effects")
