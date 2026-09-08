extends "res://scripts/tests/test_boss_combinations.gd"
## Exercise production attacks and physics state, with autonomous input disabled.

class OriginEnemy extends "res://scripts/enemy_base.gd":
	var hits: Array[Dictionary] = []
	func _ready() -> void:
		set_physics_process(false)
		max_health = 10000
		_create_health_state()
		add_to_group("enemies")
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		var before := get_current_health()
		super.take_damage(amount, context)
		if get_current_health() < before:
			var hit := context.duplicate(true)
			hit["applied"] = before - get_current_health()
			hits.append(hit)

class Shield extends "res://scripts/enemy_shielder.gd":
	var origins: Array = []
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		origins.append(context.get("attack_origin", Vector2.INF))
		super.take_damage(amount, context)

class CombatActor extends CharacterBody2D:
	var player_id: int = 2

func _run() -> void:
	await _test_actual_attack_flanks()
	await _test_owner_fallback()
	await _test_effect_epicenters()
	await _test_farline_burst_origin()
	await _test_empowered_geometry()
	await _test_snapshot_collision_cleanup()
	print("[HitOrigins] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _origin_enemy(position: Vector2) -> OriginEnemy:
	var enemy := OriginEnemy.new()
	_add_circle(enemy, 13.0)
	world.add_child(enemy)
	enemy.global_position = position
	return enemy

func _shield() -> Shield:
	var shield := Shield.new()
	_add_circle(shield, 13.0)
	world.add_child(shield)
	shield.set_max_health_and_current(10000)
	shield.shield_facing = Vector2.RIGHT
	return shield

func _test_actual_attack_flanks() -> void:
	for attack in ["melee", "blast_drive", "razor_wind", "farline_volley_burst"]:
		_make_world()
		var shield := _shield()
		var decoy := Node2D.new()
		world.add_child(decoy)
		shield.target = decoy
		await _settle()
		var distance := 120.0 if attack == "razor_wind" else 60.0
		for side in [-1.0, 1.0]:
			player.position = Vector2(distance * side, 0.0)
			decoy.position = -player.position
			shield.set_max_health_and_current(10000)
			var direction := Vector2(-side, 0.0)
			match attack:
				"melee":
					player._perform_melee_attack(direction, {"damage": 100, "range": 78.0, "arc_degrees": 130.0})
				"blast_drive":
					player.damage = 40
					player.perform_motion_blast(direction, 1.0)
				"razor_wind":
					player._apply_razor_wind(direction, {"damage": 100, "range": 160.0, "arc_degrees": 130.0})
				"farline_volley_burst":
					player._apply_farline_volley_dash_burst(100)
			var applied := 10000 - shield.get_current_health()
			_check(applied == 100 if side < 0.0 else applied > 0 and applied < 100, "%s resolves %s damage from the attacker, independently of the opposite AI target" % [attack, "rear" if side < 0.0 else "front"])
			_check(not shield.origins.is_empty() and shield.origins.back() == player.global_position, "%s carries its actual world origin" % attack)
		_free_world()

func _test_owner_fallback() -> void:
	_make_world()
	var shield := _shield()
	shield.set_meta("network_enemy_id", 987)
	var ally := CombatActor.new()
	world.add_child(ally)
	ally.add_to_group("combat_players")
	ally.position = Vector2(100.0, 0.0)
	player.position = Vector2(-100.0, 0.0)
	shield.target = ally
	await _settle()
	for bad_origin in [null, Vector2.INF, Vector2(NAN, 0.0), "not a position"]:
		var supplied := {"source_peer_id": 2}
		if bad_origin != null:
			supplied["attack_origin"] = bad_origin
		var supplied_hash := supplied.hash()
		var before := shield.get_current_health()
		DAMAGEABLE.apply_damage(shield, 100, supplied, 1)
		_check(before - shield.get_current_health() == 100 and shield.origins.back() == player.global_position, "Missing or invalid origins resolve from the authenticated actor")
		_check(supplied.hash() == supplied_hash, "Origin resolution does not mutate caller context")
		_check(EnemyReplicationService.killer_peer_for(987) == 1, "Spoofed context peer cannot redirect ownership")
	var explicit := {"attack_origin": ally.global_position, "secondary": true}
	var before := shield.get_current_health()
	DAMAGEABLE.apply_damage(shield, 100, explicit, 1)
	_check(before - shield.get_current_health() < 100 and shield.origins.back() == ally.global_position, "Explicit effect origins survive independently of their owning player's position")
	_check(EnemyReplicationService.killer_peer_for(987) == 1 and explicit.secondary, "Secondary geometry does not change owner or caller metadata")
	DAMAGEABLE.apply_damage(shield, 100, {"is_ground_attack": true, "attack_origin": ally.global_position}, 1)
	_check(shield.get_current_health() == before - int(100.0 * (1.0 - shield.shield_damage_reduction)) - 100, "Existing ground attacks still bypass directional defense")
	player.remove_from_group("combat_players")
	ally.remove_from_group("combat_players")
	before = shield.get_current_health()
	DAMAGEABLE.apply_damage(shield, 100, {"attack_origin": Vector2.INF}, 1)
	_check(before - shield.get_current_health() == 100, "Unknown origins never borrow the enemy's AI target")
	EnemyReplicationService.clear_state()
	_free_world()

func _expect_origin(enemy: OriginEnemy, origin: Vector2, label: String) -> void:
	_check(not enemy.hits.is_empty(), label + " applies real damage")
	if not enemy.hits.is_empty():
		_check(enemy.hits.back().get("attack_origin") == origin, label + " uses its own origin")
		enemy.hits.clear()

func _test_effect_epicenters() -> void:
	_make_world()
	player.position = Vector2(-500.0, 300.0)
	var enemy := _origin_enemy(Vector2(30.0, 0.0))
	await _settle()
	player._apply_wraithstep_splash(Vector2.ZERO, 100, -1)
	_expect_origin(enemy, Vector2.ZERO, "Wraithstep splash")
	player.wraithstep_marked_enemy_expiry[enemy.get_instance_id()] = {"node": enemy}
	player._apply_wraithstep_chain(Vector2.ZERO, -1, 100)
	_expect_origin(enemy, Vector2.ZERO, "Wraithstep chain")
	player.reward_storm_crown = true
	player.storm_crown_proc_every = 1
	player.storm_crown_chain_targets = 2
	var chained := _origin_enemy(Vector2(60.0, 0.0))
	player._apply_storm_crown_hit(Vector2.ZERO, -1, 100)
	_expect_origin(enemy, Vector2.ZERO, "Storm Crown first hop")
	_expect_origin(chained, enemy.global_position, "Storm Crown next hop")
	chained.free()
	player.static_wake_trails = [{"pos": Vector2(15.0, 0.0), "life": 1.0}]
	player.static_wake_damage = 100
	player._update_static_wake_trails(0.1)
	_expect_origin(enemy, Vector2(15.0, 0.0), "Static Wake")
	player._fire_overcharge_discharge(Vector2(10.0, 0.0))
	_expect_origin(enemy, Vector2(10.0, 0.0), "Overcharge")
	player.position = Vector2.ZERO
	player.phantom_step_damage = 100
	player._apply_phantom_step_during_dash()
	_expect_origin(enemy, Vector2.ZERO, "Phantom Step")
	_free_world()

func _test_farline_burst_origin() -> void:
	_make_world()
	var origin := Vector2(200.0, 100.0)
	player.position = origin
	var first := _origin_enemy(origin + Vector2(30.0, 0.0))
	var second := _origin_enemy(origin + Vector2(60.0, 0.0))
	await _settle()
	# Damage and kill listeners run synchronously. Subsequent targets still
	# belong to the initial burst even when a listener moves its owner.
	first.damage_received.connect(func(_amount: int, _remaining: int) -> void:
		player.position = Vector2(900.0, 900.0)
	)
	player._apply_farline_volley_dash_burst(100)
	_check(player.global_position != origin, "Farline test moves the player inside the first damage callback")
	_check(first.hits.size() == 1 and second.hits.size() == 1, "Farline still hits both enemies inside the original burst")
	for enemy in [first, second]:
		if not enemy.hits.is_empty():
			var hit: Dictionary = enemy.hits[0]
			_check(hit.get("attack_origin") == origin, "Every Farline hit uses the fixed burst origin")
			_check(hit.get("attack_type") == "farline_volley_burst" and not bool(hit.get("secondary", true)), "Farline retains its existing primary proc classification")
	_free_world()

func _test_empowered_geometry() -> void:
	_make_world()
	var distant := _origin_enemy(Vector2(113.0, 0.0))
	var wide := _origin_enemy(Vector2.RIGHT.rotated(deg_to_rad(83.0)) * 99.0)
	await _settle()
	player._try_execute_attack(Vector2.RIGHT)
	_check(distant.hits.is_empty() and wide.hits.is_empty(), "Ordinary melee cannot reach empowered-only targets")
	for child in player.player_feedback.get_children():
		if child is Polygon2D:
			child.free()
	player.attack_cooldown_left = 0.0
	player.attack_lock_time_left = 0.0
	player._indomitable_spirit_primed = true
	player.indomitable_spirit_damage_reduction = 0.2
	player.passive_iron_retort = true
	player.iron_retort_brace_ready = true
	player._try_execute_attack(Vector2.RIGHT)
	_check(distant.hits.any(func(hit: Dictionary) -> bool: return hit.get("attack_type") == "melee"), "Primed melee hits beyond its ordinary reach")
	_check(wide.hits.any(func(hit: Dictionary) -> bool: return hit.get("attack_type") == "melee"), "Braced melee hits beyond its ordinary angle")
	var matched := false
	for child in player.player_feedback.get_children():
		if child is Polygon2D:
			var polygon := child as Polygon2D
			if polygon.polygon.size() > 2 and polygon.polygon[0] == Vector2.ZERO:
				var edge := polygon.polygon[1]
				if is_equal_approx(edge.length(), player.attack_range * 1.35) and is_equal_approx(absf(edge.angle()), deg_to_rad((player.attack_arc_degrees + 24.0) * 0.5)):
					matched = true
	_check(matched, "Visible melee geometry includes the same empowered reach and arc as damage")
	_free_world()

func _test_snapshot_collision_cleanup() -> void:
	_make_world()
	var enemy := _enemy(Vector2(30.0, 0.0))
	await _settle()
	var snapshot := player.build_run_snapshot()
	for stale_flag in [false, true]:
		player._set_dash_phasing(true)
		_check(player.get_collision_exceptions().has(enemy), "Dash establishes a real physics collision exception")
		if stale_flag:
			player.dash_phasing_active = false
		player.apply_run_snapshot(snapshot)
		_check(player.get_collision_exceptions().is_empty() and player.dash_enemy_exceptions.is_empty(), "Snapshot clears physics exceptions even if the phase flag is already false")
		_check(not player.dash_phasing_active, "Snapshot ends transient dash phasing")
	_free_world()
