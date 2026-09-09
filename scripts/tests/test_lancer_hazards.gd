extends "res://scripts/tests/test_drifter_replication.gd"

class Lancer extends "res://scripts/enemy_lancer.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)

func _run() -> void:
	world = Node2D.new()
	root.add_child(world)
	_test_shared_hazard()
	_test_tick_lifetime()
	_test_world_origin_and_replica()
	_test_actual_player_exclusions()
	world.free()
	await process_frame
	print("[OK] Lancer hazards: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _lancer() -> Lancer:
	var enemy := Lancer.new()
	world.add_child(enemy)
	return enemy

func _target_at(position: Vector2 = Vector2.ZERO) -> TestTarget:
	var player := TestTarget.new()
	world.add_child(player)
	player.position = position
	return player

func _zone(life: float = 1.0, tick: float = 0.0, position: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"zone_id": 1, "pos_local": position, "time_left": life, "tick_timer": tick, "spawn_flash": 0.0, "tick_flash": 0.0}

func _test_shared_hazard() -> void:
	var enemy := _lancer()
	var first := _target_at()
	var second := _target_at(Vector2(10.0, 0.0))
	var outside := _target_at(Vector2(enemy.zone_radius + 1.0, 0.0))
	enemy.target = first
	enemy.target_candidates = [first, first, second, outside]
	enemy.zones.append(_zone())
	enemy._process_zones(0.01)
	_check(first.hits == 1 and second.hits == 1, "A floor zone hits both living players, without duplicating the chase target")
	_check(outside.hits == 0, "A player outside the unchanged radius remains safe")
	_check(first.last_context.get("ability") == "lancer_zone_tick", "Damage keeps its existing ability attribution")
	enemy.target = null
	enemy.zones[0]["tick_timer"] = 0.0
	enemy._process_zones(0.01)
	_check(first.hits == 2 and second.hits == 2, "A hazard stays effective while the Lancer has no chase target")
	second.health_state.current_health = 0
	enemy.zones[0]["tick_timer"] = 0.0
	enemy._process_zones(0.01)
	_check(first.hits == 3 and second.hits == 2, "Dead players are removed from damage candidates")
	enemy.target_candidates.clear()
	enemy.target = first
	enemy.zones[0]["tick_timer"] = 0.0
	enemy._process_zones(0.01)
	_check(first.hits == 4, "Solo target fallback remains supported")
	first.free()
	second.free()
	outside.free()
	enemy.free()

func _test_tick_lifetime() -> void:
	var enemy := _lancer()
	var player := _target_at()
	enemy.target = player
	var cases := [
		[1.0, 0.1, 0.05, 0],
		[1.0, 0.1, 0.1, 1],
		[0.01, 0.1, 0.2, 0],
		[0.2, 0.1, 0.4, 1],
		[0.1, 0.1, 0.4, 0],
		[0.0, 0.0, 0.2, 0],
		[0.1, -0.1, 0.4, 1]
	]
	for index in range(cases.size()):
		var data: Array = cases[index]
		player.hits = 0
		enemy.zones = [_zone(float(data[0]), float(data[1]))]
		enemy._process_zones(float(data[2]))
		_check(player.hits == int(data[3]), "Tick/lifetime case %d respects time when the hazard exists" % index)
		_check(enemy.zones.is_empty() == (float(data[2]) >= float(data[0])), "Tick/lifetime case %d removes expired zones" % index)
	player.free()
	enemy.free()

func _test_world_origin_and_replica() -> void:
	world.position = Vector2(200.0, -150.0)
	var enemy := _lancer()
	var player := _target_at(Vector2(30.0, -60.0))
	enemy.target = player
	enemy.position = Vector2(-300.0, 50.0)
	enemy.zones.append(_zone(1.0, 0.0, player.position))
	enemy._process_zones(0.01)
	_check(player.hits == 1, "Zone damage uses its fixed floor position under a translated arena")
	enemy.set_network_simulation_enabled(false)
	enemy.zones[0]["tick_timer"] = 0.0
	enemy._process_zones(0.01, true)
	_check(player.hits == 1, "A replica cannot damage players even if its caller requests damage")
	_check(float(enemy.zones[0]["time_left"]) < 0.99, "Replica hazards still advance their visual lifetime")
	enemy.set_network_simulation_enabled(true)
	enemy.zones[0]["tick_timer"] = 0.0
	enemy._process_zones(0.01, false)
	_check(player.hits == 1, "Explicit visual-only advancement never deals damage")
	player.free()
	enemy.free()
	world.position = Vector2.ZERO

func _test_actual_player_exclusions() -> void:
	var enemy := _lancer()
	var player := RingPlayer.new()
	world.add_child(player)
	enemy.target = player
	enemy.target_candidates = [player]
	player._combat_removed = true
	enemy.zones.append(_zone())
	enemy._process_zones(0.01)
	_check(player.get_current_health() == player.max_health, "A removed real player remains safe even while still referenced as the chase target")
	player._combat_removed = false
	enemy.zones[0]["tick_timer"] = 0.0
	enemy._process_zones(0.01)
	_check(player.get_current_health() == player.max_health - enemy.zone_tick_damage, "A living real player receives the existing zone damage")
	player.free()
	enemy.free()
