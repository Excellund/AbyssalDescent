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
	await _test_backwash()
	_test_local_sound_setting()
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
	_check(boss.phase == BREAKWATER.Phase.BACKWASH and is_equal_approx(boss.phase_left, BREAKWATER.BACKWASH_TIME), "A missed charge gives a complete separate Backwash warning after its harmless recovery")
	boss._process_behavior(BREAKWATER.BACKWASH_TIME)
	_check(boss.phase == BREAKWATER.Phase.TIDE and not boss._backwash_pending, "The full brace warning releases a moving returning crest")
	boss._process_behavior(10.0)
	_check(boss.phase == BREAKWATER.Phase.RECOVER and is_equal_approx(boss.phase_left, BREAKWATER.TIDE_RECOVERY), "The finished tide grants its complete stationary punish window")
	boss._process_behavior(BREAKWATER.TIDE_RECOVERY)
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

func _test_backwash() -> void:
	_setup()
	var boss := _apex(Vector2(160.5, -30.25))
	boss.charge_direction = Vector2.RIGHT
	actor.global_position = Vector2(-400.0, -300.0)
	var probes: Array[Probe] = []
	for offset: Vector2 in [Vector2(-200.0, 0.0), Vector2(-200.0, 80.0), Vector2(-200.0, 231.0), Vector2(80.0, 80.0)]:
		var probe := Probe.new()
		probe.player_id = 10 + probes.size()
		room.add_child(probe)
		probe.global_position = boss.global_position + offset
		probes.append(probe)
	boss._enter_recovery(false)
	boss._process_behavior(BREAKWATER.MISS_RECOVERY)
	_check(boss.phase == BREAKWATER.Phase.BACKWASH and boss.get_attack_callout().begins_with("Return Tide"), "Actual miss recovery braces for the returning tide")
	var warning := boss.get_warning_polygons()
	for index in range(probes.size()):
		var drawn := false
		for polygon in warning:
			drawn = drawn or Geometry2D.is_point_in_polygon(probes[index].global_position, polygon)
		_check(drawn == (index == 1), "The full tide warning preserves the vacated ram lane, outer shore and calm side beyond the boss")
	boss._process_behavior(BREAKWATER.BACKWASH_TIME - 0.01)
	_check(probes.all(func(probe: Probe) -> bool: return probe.hit_count == 0), "Bracing deals no premature damage")
	boss._process_behavior(0.011)
	_check(boss.phase == BREAKWATER.Phase.TIDE and probes.all(func(probe: Probe) -> bool: return probe.hit_count == 0), "Warning expiry releases the wave without an instant full-area hit")
	boss._process_behavior(0.1)
	_check(probes[1].hit_count == 0, "A distant player remains unharmed until the traveling crest arrives")
	boss._process_behavior(10.0)
	for index in range(probes.size()):
		_check(probes[index].hit_count == (1 if index == 1 else 0), "A long-frame tide sweep hits only the warned lobe once")
	_check(boss.phase == BREAKWATER.Phase.RECOVER and boss.get_warning_polygons().is_empty(), "The tide completely retires into a stationary recovery")
	boss._begin_backwash()
	var packet := boss._get_custom_network_runtime_state()
	var replica := _apex(Vector2(220.0, 80.0))
	replica.set_network_simulation_enabled(false)
	replica._apply_custom_network_runtime_state(packet)
	_check(replica.get_warning_polygons() == boss.get_warning_polygons(), "Replica preserves exact committed wave path through body interpolation")
	replica._resolve_backwash()
	_check(replica.phase == BREAKWATER.Phase.BACKWASH, "A replica cannot release a wave by resolving its warning")
	boss._resolve_backwash()
	boss._process_behavior(0.3)
	var active := boss._get_custom_network_runtime_state()
	replica._apply_custom_network_runtime_state(active)
	_check(replica.get_warning_polygons() == boss.get_warning_polygons() and replica.phase == BREAKWATER.Phase.TIDE, "The actual moving crest has identical host and replica geometry")
	var progress := replica._tide_progress
	replica._process_network_visuals(0.1)
	_check(replica._tide_progress > progress, "Replica animation advances the committed crest without host damage authority")
	replica._process_network_visuals(BREAKWATER.REMOTE_LEASE + 0.01)
	replica._apply_custom_network_runtime_state(active)
	_check(replica.get_warning_polygons().is_empty(), "Expired tide cannot be resurrected by a duplicate packet")
	replica.free()
	for reason in ["authority", "cancel", "bounds", "party_down"]:
		boss._begin_backwash()
		boss._resolve_backwash()
		if reason == "authority":
			boss.set_network_simulation_enabled(false)
		elif reason == "cancel":
			boss._cancel_attack()
		elif reason == "bounds":
			room.current_effective_room_size += Vector2(10.0, 10.0)
			boss._process_behavior(0.01)
		else:
			actor.health_state.current_health = 0
			for probe in probes:
				probe.health_state.current_health = 0
			boss._process_behavior(0.01)
		_check(boss.get_warning_polygons().is_empty() and not boss._backwash_pending, reason + " retires active and pending tide")
		boss.set_network_simulation_enabled(true)
	_clear()
	await _test_tide_walking_routes()
	await _test_tide_curved_contact()
	await _test_tide_dash_crossing()

func _test_tide_walking_routes() -> void:
	# Slowest base character at 45% speed, with Attack lock and acceleration
	# reserved before moving. Find a straight body-safe route using independently
	# classified published polygons, including endpoints next to every corner.
	for size: Vector2 in [Vector2(1160, 860), Vector2(740, 540)]:
		_setup()
		room.current_room_size = size
		room.current_effective_room_size = size
		var bounds := EnemyReplicationService.get_current_room_bounds()
		var budget := 188.0 * 0.45 * (BREAKWATER.BACKWASH_TIME - 0.25)
		var boss := _apex()
		for at: Vector2 in [Vector2.ZERO, bounds.position + Vector2(40, 40), bounds.end - Vector2(40, 40), Vector2(bounds.end.x - 40, bounds.position.y + 40)]:
			for angle: float in [0.0, 0.6, 1.4, 2.6, 3.7, 4.8]:
				boss.global_position = at
				boss.charge_direction = Vector2.from_angle(angle)
				boss._begin_backwash()
				var geometry := boss.get_warning_polygons()
				for x in range(int(bounds.position.x + 26), int(bounds.end.x - 25), 55):
					for y in range(int(bounds.position.y + 26), int(bounds.end.y - 25), 55):
						var point := Vector2(x, y)
						if not _inside_tide_polygons(geometry, point) or point.distance_to(at) < 53.0:
							continue
						var escape := Vector2.INF
						for direction_index in range(48):
							var direction := Vector2.from_angle(TAU * direction_index / 48.0)
							for distance: float in [32.0, 64.0, 96.0, budget]:
								var candidate := point + direction * distance
								if not bounds.has_point(candidate) or _inside_tide_polygons(geometry, candidate):
									continue
								if Geometry2D.get_closest_point_to_segment(at, point, candidate).distance_to(at) < 53.0:
									continue
								escape = candidate
								break
							if escape.is_finite():
								break
						_check(escape.is_finite(), "Tide has a Slowed walking escape before release at %s / %s / %.2f / %s" % [size, at, angle, point])
		boss.free()
		_clear()
		await process_frame

func _inside_tide_polygons(polygons: Array[PackedVector2Array], point: Vector2) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false

func _test_tide_dash_crossing() -> void:
	_setup()
	var boss := _apex(Vector2(160.0, 0.0))
	boss.charge_direction = Vector2.RIGHT
	actor.global_position = Vector2(-80.0, 100.0)
	boss._begin_backwash()
	boss._resolve_backwash()
	boss._process_behavior(0.40)
	actor.dash_cooldown_left = 0.0
	actor._dash_damage_immune_left = 0.0
	actor.aim = Vector2.RIGHT
	Input.action_press("dash")
	actor._try_start_dash(Vector2.RIGHT)
	Input.action_release("dash")
	_check(actor.dash_time_left > 0.0, "The tide fixture starts the actual normal Dash through its input boundary")
	var health := actor.get_current_health()
	for frame in range(20):
		actor._physics_process(1.0 / 60.0)
		boss._process_behavior(1.0 / 60.0)
	_check(actor.get_current_health() == health and actor.global_position.x > -20.0, "A real moving normal Dash crosses the crest through existing contact immunity")
	_clear()
	await process_frame

func _test_local_sound_setting() -> void:
	_setup()
	var boss := _apex()
	# Headless skips the audio device; use the same real player and generated clip.
	if boss._sound == null:
		boss._sound = AudioStreamPlayer.new()
		boss._sound.stream = BREAKWATER._make_sound()
		boss._sound.volume_db = -19.0
		boss.add_child(boss._sound)
	var saved_volume := RunContext.sfx_volume_db
	for setting: float in [0.0, -24.0, -80.0]:
		RunContext.sfx_volume_db = setting
		boss._sound_left = 0.0
		boss._lock_charge()
		_check(is_equal_approx(boss._sound.volume_db, clampf(setting - 19.0, -80.0, 6.0)), "Breakwater warning follows this player's current SFX setting, including mute")
		boss._sound.stop()
	RunContext.sfx_volume_db = saved_volume
	_clear()

func _test_tide_curved_contact() -> void:
	_setup()
	var boss := _apex(Vector2(150.0, 0.0))
	var probe := Probe.new()
	probe.player_id = 21
	room.add_child(probe)
	actor.global_position = Vector2(-500.0, -350.0)
	for angle: float in [0.0, 0.63, 2.1]:
		boss.charge_direction = Vector2.from_angle(angle)
		boss._begin_backwash()
		boss._resolve_backwash()
		for progress: float in [55.0, 210.0]:
			boss._tide_progress = progress
			var geometry := boss.get_warning_polygons()
			for side: float in [-1.0, 1.0]:
				for across: float in [31.5, 32.5, 54.0, 89.0, 130.0, 191.0, 229.5, 230.5]:
					for offset: float in [-24.5, -23.5, 0.0, 23.5, 24.5]:
						# The test classifies the actual published polygon rather
						# than restating the production curved-distance predicate.
						var point := boss._tide_origin + boss._tide_direction * (progress + boss._tide_curve_offset(across) + offset) + boss._tide_direction.orthogonal() * side * across
						probe.global_position = point
						probe.health_state.current_health = 100
						probe.hit_count = 0
						boss._hit_players.clear()
						var painted := _inside_tide_polygons(geometry, point)
						boss._apply_tide_hits(progress, progress)
						boss._apply_tide_hits(progress, progress)
						_check(probe.hit_count == (1 if painted else 0), "Curved foam boundary matches authoritative contact exactly once, including wake/outer/front edges")
	_clear()
	await process_frame
