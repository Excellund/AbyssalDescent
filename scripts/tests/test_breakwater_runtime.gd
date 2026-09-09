extends "res://scripts/tests/test_live_arena_edges.gd"
## Production charge, terrain queries and drawn capsule checked together.

const BREAKWATER := preload("res://scripts/enemy_breakwater.gd")
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

class Apex extends BREAKWATER:
	func _ready() -> void:
		super._ready()
		set_physics_process(false)

class Probe extends Node2D:
	var health_state := preload("res://scripts/health_state.gd").new()
	var player_id := 0
	var hit_count := 0
	func _ready() -> void:
		add_child(health_state)
		health_state.setup(100)
		add_to_group("combat_players")
	func get_current_health() -> int:
		return health_state.current_health
	func is_dead() -> bool:
		return health_state.current_health <= 0
	func take_damage(amount: int, _context: Dictionary = {}) -> void:
		health_state.take_damage(amount)
		hit_count += 1

func _apex(position: Vector2 = Vector2.ZERO) -> Apex:
	var boss := Apex.new()
	_circle(boss, 13.0)
	room.add_child(boss)
	boss.global_position = position
	boss.target = actor
	boss.target_candidates = [actor]
	return boss

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Breakwater runtime requires isolated user data")
		quit(1)
		return
	await _test_tracking_commit_and_miss()
	await _test_wall_punish()
	await _test_warning_matches_hits()
	await _test_cover_forecast()
	await _test_bounded_reset_and_removal()
	await _test_intro_and_destroyed_cover()
	await _test_range_and_zero_length_warning()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Breakwater runtime: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_tracking_commit_and_miss() -> void:
	_setup()
	actor.global_position = Vector2(200.0, 0.0)
	var boss := _apex()
	await physics_frame
	boss._begin_tracking()
	_check(boss.phase == BREAKWATER.Phase.TRACK and boss.charge_end == Vector2(380.0, 0.0), "Center charge initially forecasts target distance plus180 rather than an automatic wall collision")
	actor.global_position = Vector2(200.0, 90.0)
	boss._process_behavior(0.34)
	_check(boss.phase == BREAKWATER.Phase.TRACK and boss.charge_direction.y > 0.0, "The first .35 seconds visibly track the selected player")
	boss._process_behavior(0.01)
	_check(boss.phase == BREAKWATER.Phase.LOCK and is_equal_approx(boss.phase_left, 0.55), "Tracking ends with the complete fixed .55-second commitment warning")
	var locked_end := boss.charge_end
	var locked_direction := boss.charge_direction
	actor.global_position = Vector2(-400.0, 300.0)
	boss._process_behavior(0.54)
	_check(boss.phase == BREAKWATER.Phase.LOCK and boss.global_position == Vector2.ZERO and boss.charge_end == locked_end and boss.charge_direction == locked_direction, "Late target movement cannot turn or move the locked attack")
	boss._process_behavior(0.02)
	_check(boss.phase == BREAKWATER.Phase.CHARGE, "Charge starts after its locked warning expires")
	boss._process_behavior(2.0)
	_check(boss.global_position.distance_to(locked_end) < 0.01 and boss.phase == BREAKWATER.Phase.RECOVER and not boss.wall_recovery, "A frame hitch ends the finite missed charge at its forecast endpoint")
	_check(is_equal_approx(boss.phase_left, BREAKWATER.MISS_RECOVERY) and boss.velocity == Vector2.ZERO, "A miss has the complete harmless .55-second recovery")
	boss._process_behavior(0.54)
	_check(boss.phase == BREAKWATER.Phase.RECOVER and boss.global_position.distance_to(locked_end) < 0.01, "Recovery holds its stationary position through its full duration")
	boss._process_behavior(0.02)
	_check(boss.phase == BREAKWATER.Phase.SEEK and is_equal_approx(boss.phase_left, boss.attack_cooldown), "The unchanged between-attack cooldown starts after recovery")
	_clear()

func _test_wall_punish() -> void:
	for direction: Vector2 in SIDES:
		_setup()
		actor.global_position = _edge(direction) - direction * 65.0
		var boss := _apex()
		await physics_frame
		boss._begin_tracking()
		boss._process_behavior(BREAKWATER.TRACK_TIME)
		_check(boss.charge_end.distance_to(_edge(direction)) < 0.01, "Baited %s charge forecasts the actual allowed-center boundary" % direction)
		var health := boss.get_current_health()
		_check(DAMAGEABLE.apply_damage(boss, 20, {"attack_type": "melee", "attack_origin": actor.global_position}), "Ordinary attacks remain accepted during commitment")
		_check(boss.get_current_health() == health - 20, "Breakwater has no hidden windup armor gate")
		actor.global_position = direction.rotated(PI * 0.5) * 150.0
		boss._process_behavior(BREAKWATER.LOCK_TIME)
		boss._process_behavior(2.0)
		_check(boss.phase == BREAKWATER.Phase.RECOVER and boss.wall_recovery and boss.global_position.distance_to(_edge(direction)) < 0.01, "Baited wall contact resolves exactly at the drawn endpoint")
		_check(is_equal_approx(boss.phase_left, BREAKWATER.WALL_RECOVERY) and boss._exceptions.is_empty(), "Wall impact provides1.8 seconds of harmless recovery and restores collision exceptions")
		var position := boss.global_position
		boss._process_behavior(1.79)
		_check(boss.phase == BREAKWATER.Phase.RECOVER and boss.global_position == position, "The longer punish window remains stationary until its last fraction")
		boss._process_behavior(0.02)
		_check(boss.phase == BREAKWATER.Phase.SEEK and boss._reset_inward, "After wall recovery the Apex first resets inward")
		_clear()

func _test_warning_matches_hits() -> void:
	for angle in [0.0, 0.65, 2.1]:
		_setup()
		room.current_room_size = Vector2(2600.0, 2000.0)
		room.current_effective_room_size = room.current_room_size
		actor.global_position = Vector2(-1100.0, -850.0)
		var boss := _apex(Vector2(-100.0, -100.0))
		var direction := Vector2.RIGHT.rotated(angle)
		var side := direction.rotated(PI * 0.5)
		boss.charge_origin = boss.global_position
		boss.charge_end = boss.charge_origin + direction * 400.0
		boss.charge_direction = direction
		boss._charge_bounds = EnemyReplicationService.get_current_room_bounds()
		boss.phase = BREAKWATER.Phase.LOCK
		var polygons := boss.get_warning_polygons()
		var cases := [
			{"along": 200.0, "side": 37.0, "hit": true},
			{"along": 200.0, "side": 39.0, "hit": false},
			{"along": -37.0, "side": 0.0, "hit": true},
			{"along": -39.0, "side": 0.0, "hit": false},
			{"along": 437.0, "side": 0.0, "hit": true},
			{"along": 439.0, "side": 0.0, "hit": false}
		]
		var probes: Array[Probe] = []
		for index in range(cases.size()):
			var entry: Dictionary = cases[index]
			var probe := Probe.new()
			probe.player_id = index + 10
			room.add_child(probe)
			probe.global_position = boss.charge_origin + direction * float(entry.along) + side * float(entry.side)
			probes.append(probe)
			var contained := false
			for polygon in polygons:
				contained = contained or Geometry2D.is_point_in_polygon(probe.global_position, polygon)
			_check(contained == bool(entry.hit), "Drawn capsule includes exactly the side/endcap case%d at angle%.2f" % [index, angle])
		await physics_frame
		boss._begin_charge()
		boss._process_behavior(1.0)
		for index in range(probes.size()):
			_check(probes[index].hit_count == (1 if bool(cases[index].hit) else 0), "Actual swept damage matches drawn case%d at angle%.2f without hidden body inflation" % [index, angle])
		boss._process_behavior(0.3)
		_check(probes.all(func(probe: Probe) -> bool: return probe.hit_count <= 1), "Recovery cannot apply another hit after a long charge frame")
		_clear()

func _test_cover_forecast() -> void:
	_setup()
	actor.global_position = Vector2(500.0, 0.0)
	var boss := _apex()
	_thin_cover(Vector2(300.0, 0.0))
	await physics_frame
	boss._begin_tracking()
	boss._process_behavior(BREAKWATER.TRACK_TIME)
	var endpoint := boss.charge_end
	_check(endpoint.x > 268.0 and endpoint.x < 271.0 and absf(endpoint.y) < 0.01, "A thin column wall clips the body-sized forecast before the room edge: %s" % endpoint)
	boss._process_behavior(BREAKWATER.LOCK_TIME)
	boss._process_behavior(2.0)
	_check(boss.global_position.distance_to(endpoint) < 0.2 and boss.wall_recovery, "Cover impact movement stops at its forecast center and earns the same punish window: %s versus %s, wall=%s" % [boss.global_position, endpoint, boss.wall_recovery])
	_clear()

func _test_bounded_reset_and_removal() -> void:
	_setup()
	actor.global_position = Vector2(520.0, 0.0)
	var boss := _apex(Vector2(580.0, 0.0))
	boss._enter_recovery(true)
	boss._process_behavior(BREAKWATER.WALL_RECOVERY)
	await physics_frame
	for _index in range(100):
		boss._process_behavior(STEP)
		if boss.phase != BREAKWATER.Phase.SEEK:
			break
	_check(boss.phase != BREAKWATER.Phase.SEEK, "Body blocking the inward reset cannot stall the Apex indefinitely")
	boss._cancel_attack()
	actor.set_combat_removed(true)
	_check(boss._living_players().is_empty(), "Removed co-op actors are excluded even if their health remains positive")
	actor.set_combat_removed(false)
	actor.set_physics_process(false)
	boss._begin_tracking()
	boss._lock_charge()
	boss._begin_charge()
	_check(not boss._exceptions.is_empty(), "The committed charge temporarily excludes combat bodies from movement collision")
	boss._cancel_attack()
	_check(boss._exceptions.is_empty() and boss.get_collision_exceptions().is_empty() and boss.get_warning_polygons().is_empty(), "Cancellation clears body exceptions and the owned warning immediately")
	_clear()

func _test_intro_and_destroyed_cover() -> void:
	_setup()
	actor.global_position = Vector2(500.0, 0.0)
	var boss := _apex()
	boss.target = null
	boss.target_candidates.clear()
	await physics_frame
	boss._process_behavior(5.0)
	_check(boss.phase == BREAKWATER.Phase.SEEK and boss.global_position == Vector2.ZERO and boss.get_warning_polygons().is_empty(), "Living combat players cannot bypass the encounter survey's cleared target assignment")
	boss._begin_tracking()
	_check(boss.phase == BREAKWATER.Phase.SEEK, "Direct acquisition also respects the encounter introduction")
	boss.target = actor
	boss.target_candidates = [actor]
	var cover := _thin_cover(Vector2(300.0, 0.0))
	await physics_frame
	boss._begin_tracking()
	boss._lock_charge()
	var endpoint := boss.charge_end
	cover.free()
	await physics_frame
	boss._process_behavior(BREAKWATER.LOCK_TIME)
	boss._process_behavior(2.0)
	_check(boss.global_position.distance_to(endpoint) < 0.01 and boss.phase == BREAKWATER.Phase.RECOVER, "Destroyed cover does not extend the committed warning endpoint")
	_check(not boss.wall_recovery and is_equal_approx(boss.phase_left, BREAKWATER.MISS_RECOVERY), "Destroyed cover cannot award a terrain impact or long punish window")
	_clear()

func _test_range_and_zero_length_warning() -> void:
	_setup()
	room.current_room_size = Vector2(3000.0, 2000.0)
	room.current_effective_room_size = room.current_room_size
	var boss := _apex()
	actor.global_position = Vector2(25.0, 0.0)
	boss._begin_tracking()
	_check(is_equal_approx(boss.charge_origin.distance_to(boss.charge_end), BREAKWATER.CHARGE_MIN_DISTANCE), "Very close targets still receive the finite minimum charge forecast")
	actor.global_position = Vector2(1200.0, 0.0)
	boss._aim_forecast()
	_check(is_equal_approx(boss.charge_origin.distance_to(boss.charge_end), BREAKWATER.CHARGE_DISTANCE), "Distant targets cannot extend the charge beyond its maximum travel")
	boss.charge_end = boss.charge_origin
	boss.phase = BREAKWATER.Phase.LOCK
	var warning := boss.get_warning_polygons()
	_check(warning.size() == 1 and Geometry2D.is_point_in_polygon(boss.charge_origin + Vector2(37.0, 0.0), warning[0]) and not Geometry2D.is_point_in_polygon(boss.charge_origin + Vector2(39.0, 0.0), warning[0]), "A zero-length wall-pinned charge still draws its exact contact circle")
	_check(not Geometry2D.triangulate_polygon(warning[0]).is_empty(), "The contact-only warning is a valid rendered polygon")
	_clear()
