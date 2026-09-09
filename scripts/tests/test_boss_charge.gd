extends "res://scripts/tests/test_live_arena_edges.gd"
## Announced shape, actual motion and accepted contact checked together.

const CHARGE := preload("res://scripts/shared/committed_charge.gd")
const DIFFICULTY := preload("res://scripts/difficulty_config.gd")
const PROVIDER := preload("res://scripts/core/difficulty_scaling_provider.gd")

class Warden extends "res://scripts/enemy_boss.gd":
	var measured_steps := 0
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _physics_process(delta: float) -> void:
		super._physics_process(delta)
		measured_steps += 1
		if boss_state != ENEMY_STATE_ENUMS.BossState.ATTACK:
			set_physics_process(false)

class Lacuna extends "res://scripts/enemy_boss_3.gd":
	var measured_steps := 0
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _physics_process(delta: float) -> void:
		super._physics_process(delta)
		measured_steps += 1
		if boss_state != STATE_ATTACK:
			set_physics_process(false)

class Probe extends CharacterBody2D:
	var health_state := preload("res://scripts/health_state.gd").new()
	var attempts := 0
	var contexts: Array[Dictionary] = []
	var reject := false
	var on_hit: Callable
	func _ready() -> void:
		add_child(health_state)
		health_state.setup(10000)
		add_to_group("combat_players")
	func is_dead() -> bool:
		return health_state.is_dead()
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		attempts += 1
		contexts.append(context.duplicate(true))
		if not reject:
			health_state.take_damage(amount)
		if on_hit.is_valid():
			on_hit.call()

func _boss(kind: String, position: Vector2 = Vector2.ZERO) -> Variant:
	var boss: Variant = Warden.new() if kind == "warden" else Lacuna.new()
	_circle(boss, 20.0)
	room.add_child(boss)
	boss.global_position = position
	boss.arena_size = room.current_room_size
	boss.crowd_separation_strength = 0.0
	boss.target = actor
	boss.target_candidates = [actor]
	return boss

func _probe(position: Vector2, physical: bool = false) -> Probe:
	var probe := Probe.new()
	if physical:
		_circle(probe, 14.0)
	room.add_child(probe)
	probe.global_position = position
	return probe

func _start_warning(boss: Variant, kind: String) -> void:
	if kind == "lacuna":
		boss._attack_cycle_step = 0
		boss._last_attack = -1
	boss._start_next_attack(600.0, 0.0)
	_check(boss._charge_motion.stage == CHARGE.Stage.WARNING, kind + " creates committed geometry when selecting its real charge")

func _large_room() -> void:
	_setup()
	room.current_room_size = Vector2(4000.0, 2400.0)
	room.current_effective_room_size = room.current_room_size
	actor.global_position = Vector2(900.0, 0.0)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Boss charge fixture requires isolated user data")
		quit(1)
		return
	await _test_bearings_and_latched_enrage()
	await _test_capsule_and_attempts()
	await _test_terrain_and_cadence()
	await _test_body_blocking()
	await _test_lifecycle()
	await _test_compact_wire()
	await _test_real_physics_steps()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Boss committed charges: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_compact_wire() -> void:
	_large_room()
	var boss: Variant = _boss("lacuna")
	await physics_frame
	_start_warning(boss, "lacuna")
	var replica := CHARGE.new()
	replica.configure(boss, 40.0, 40.0, 44.0, 42.0)
	var warning: Array = boss._charge_motion.build_network_state()
	_check(warning.size() == 6 and var_to_bytes(warning).size() <= 64, "Warning geometry has a bounded compact wire representation")
	_check(replica.apply_network_state(warning) and replica.geometry() == boss.get_charge_warning_geometry(), "Compact warning reconstructs the exact host capsule")
	for malformed: Variant in [null, {}, [], [1, 0], [1, 0, "warning"], [1, 0, 3]]:
		_check(not replica.apply_network_state(malformed), "Malformed compact state is rejected")
	var old_geometry := replica.geometry()
	for bad_origin: Variant in [Vector2(NAN, 0.0), Vector2(0.0, INF), "not a vector"]:
		var invalid := warning.duplicate()
		invalid[0] = 100000
		invalid[3] = bad_origin
		_check(not replica.apply_network_state(invalid) and replica.geometry() == old_geometry, "Invalid high-sequence geometry cannot poison the accepted capsule")
	var wrong_room := warning.duplicate()
	wrong_room[0] = 100000
	wrong_room[1] += 1
	_check(not replica.apply_network_state(wrong_room), "Inner room identity is checked before sequence advancement")
	warning = boss._charge_motion.build_network_state()
	_check(replica.apply_network_state(warning), "A valid packet after invalid high sequence still applies")
	boss._enter_attack_state()
	var charge: Array = boss._charge_motion.build_network_state()
	_check(charge.size() == 3 and var_to_bytes(charge).size() <= 32, "Charge phase clears warning without repeating unused geometry")
	_check(replica.apply_network_state(charge) and replica.geometry().is_empty(), "Ordered charge transition removes the warning")
	_check(not replica.apply_network_state(warning) and replica.geometry().is_empty(), "Delayed warning cannot resurrect after charge begins")
	boss._charge_motion.cancel()
	var ended: Array = boss._charge_motion.build_network_state()
	_check(ended.size() == 3 and replica.apply_network_state(ended), "Cancellation keeps an explicit compact ordered state")
	_check(not replica.apply_network_state(charge) and replica.stage == CHARGE.Stage.NONE, "Late active phase cannot overwrite newer cancellation")
	_start_warning(boss, "lacuna")
	boss._charge_motion._wire_sequence = 2147483648
	_check(replica.apply_network_state(boss._charge_motion.build_network_state()), "Sequences retain order beyond signed 32-bit range")
	replica.tick_replica(CHARGE.LEASE_SECONDS + 0.01)
	_check(replica.geometry().is_empty(), "An otherwise valid warning expires without further packets")
	var retained_centers: Array[Vector2] = [Vector2(-90.0, 20.0), Vector2(30.0, -70.0)]
	boss._locked_null_ring_centers = retained_centers
	var sever_packet: Dictionary = boss.get_projectile_network_sync_state()
	_check(not sever_packet.has("locked_null_ring_centers"), "Sever excludes unrelated retained Null Ring centers from its packet")
	boss.active_attack = boss.ATTACK_NULL_RING
	var ring_packet: Dictionary = boss.get_projectile_network_sync_state()
	_check(ring_packet.get("locked_null_ring_centers") == boss._locked_null_ring_centers, "Null Ring still sends its full current center set")
	_clear()

func _test_bearings_and_latched_enrage() -> void:
	for kind in ["warden", "lacuna"]:
		for tier in range(4):
			for health_ratio in [1.0, 0.48, 0.15]:
				_large_room()
				room.current_difficulty_tier = tier
				room.current_difficulty_config = DIFFICULTY.get_tier_config(tier)
				room.difficulty_provider = PROVIDER.new(room)
				var boss: Variant = _boss(kind)
				room._apply_boss_difficulty_scaling(boss)
				boss.health_state.set_health(int(round(boss.max_health * health_ratio)))
				await physics_frame
				_start_warning(boss, kind)
				var announced := boss.get_charge_warning_geometry() as Dictionary
				var announced_speed: float = boss._charge_motion.speed
				var announced_duration: float = boss._charge_motion.duration
				var ratio: float = boss._get_enrage_ratio()
				var nominal_speed: float = (boss.charge_speed * lerpf(1.0, 1.18, ratio)) if kind == "warden" else (boss.sever_speed * lerpf(1.0, 1.16, ratio))
				var nominal_duration: float = (boss.charge_duration if kind == "warden" else boss.sever_duration) * lerpf(1.0, 0.84, ratio)
				_check(is_equal_approx(announced_speed, nominal_speed) and is_equal_approx(announced_duration, nominal_duration), "Bearing%d %s retains nominal speed/duration at health%.2f" % [tier, kind, health_ratio])
				boss.health_state.set_health(int(boss.max_health * 0.15))
				if kind == "warden":
					boss._process_telegraph_state(0.1)
				else:
					boss._process_windup_state(0.1)
				_check(boss._charge_motion.speed == announced_speed and boss._charge_motion.duration == announced_duration, "Damage during windup does not replace the announced charge tuning")
				boss._enter_attack_state()
				boss._process_attack_state(2.0)
				_check(boss.global_position.distance_to(announced["end"]) < 0.01 and absf(boss.global_position.x - announced_speed * announced_duration) < 0.01, "A hitch uses exactly the announced nominal travel across Bearings")
				_check(boss._charge_motion.stage == CHARGE.Stage.NONE and boss.get_collision_exceptions().is_empty(), "Natural charge completion restores collision ownership")
				_check(boss.boss_state == 3, "Completion enters the existing recovery state")
				boss.global_position = Vector2.ZERO
				_start_warning(boss, kind)
				_check(is_equal_approx(boss._charge_motion.speed, boss.charge_speed * 1.18 if kind == "warden" else boss.sever_speed * 1.16), "The next charge receives the new enrage speed")
				_clear()

func _test_capsule_and_attempts() -> void:
	for kind in ["warden", "lacuna"]:
		for angle in [0.0, 0.71, 2.2]:
			_large_room()
			var direction := Vector2.RIGHT.rotated(angle)
			var side := direction.orthogonal()
			actor.global_position = direction * 900.0
			var boss: Variant = _boss(kind)
			await physics_frame
			_start_warning(boss, kind)
			var geometry: Dictionary = boss.get_charge_warning_geometry()
			var polygons: Array = boss.get_charge_warning_polygons()
			var length: float = geometry.origin.distance_to(geometry.end)
			var cases := [Vector2(length * 0.5, geometry.radius - 1.0), Vector2(length * 0.5, geometry.radius + 1.0), Vector2(-geometry.rear - geometry.radius + 1.0, 0.0), Vector2(-geometry.rear - geometry.radius - 1.0, 0.0), Vector2(length + geometry.front + geometry.radius - 1.0, 0.0), Vector2(length + geometry.front + geometry.radius + 1.0, 0.0)]
			var probes: Array[Probe] = []
			for index in range(cases.size()):
				var point: Vector2 = direction * cases[index].x + side * cases[index].y
				var probe := _probe(point)
				probes.append(probe)
				boss.target_candidates.append(probe)
				var inside := false
				for polygon in polygons:
					inside = inside or Geometry2D.is_point_in_polygon(point, polygon)
				_check(inside == (index % 2 == 0), "%s warning matches exact rear/side/front capsule case%d at%.2f" % [kind, index, angle])
			boss._enter_attack_state()
			boss._process_attack_state(2.0)
			for index in range(probes.size()):
				_check(probes[index].attempts == (1 if index % 2 == 0 else 0), "Long-step real damage matches the drawn contact capsule")
			_clear()
	# Preserve one attempted contact even if the target rejects its damage.
	for kind in ["warden", "lacuna"]:
		_large_room()
		var boss: Variant = _boss(kind)
		var probe := _probe(Vector2(55.0, 0.0))
		probe.reject = true
		boss.target_candidates.append(probe)
		await physics_frame
		_start_warning(boss, kind)
		boss._enter_attack_state()
		boss._process_attack_state(0.01)
		boss._process_attack_state(0.01)
		_check(probe.attempts == 1 and probe.health_state.current_health == 10000, "Rejected damage still consumes exactly one charge attempt")
		_check(probe.contexts[0].source == ("enemy_contact" if kind == "warden" else "enemy_ability"), "Existing contact/ability immunity category is preserved")
		if kind == "lacuna":
			_check(boss.seam_zones.size() == 1, "Lacuna keeps its one seam from the accepted contact attempt")
		_clear()

func _test_terrain_and_cadence() -> void:
	for kind in ["warden", "lacuna"]:
		for direction: Vector2 in SIDES:
			_setup()
			actor.global_position = _edge(direction)
			var boss: Variant = _boss(kind, _edge(direction) - direction * 45.0)
			await physics_frame
			_start_warning(boss, kind)
			var endpoint: Vector2 = boss.get_charge_warning_geometry().end
			_check(endpoint.distance_to(_edge(direction)) < 0.01, "Room boundary clips the announced center path")
			boss._enter_attack_state()
			var duration: float = boss._charge_motion.duration
			boss._process_attack_state(0.10)
			_check(boss.global_position.distance_to(endpoint) < 0.01 and boss._charge_motion.stage == CHARGE.Stage.CHARGE, "Early terrain impact stops motion while keeping the nominal attack window")
			_check(is_equal_approx(boss.state_time_left, duration - 0.10), "Terrain stop does not advance recovery or grant a new stun")
			boss._process_attack_state(duration)
			_check(boss.boss_state == 3 and boss.get_collision_exceptions().is_empty(), "Terrain completion uses normal recovery and clears exceptions")
			_clear()
		_large_room()
		var boss: Variant = _boss(kind)
		var cover := _thin_cover(Vector2(110.0, 0.0))
		await physics_frame
		_start_warning(boss, kind)
		var endpoint: Vector2 = boss.get_charge_warning_geometry().end
		_check(endpoint.x > 60.0 and endpoint.x < 80.0, "Thin physical cover clips the warning using the real boss body radius")
		cover.free()
		await physics_frame
		boss._enter_attack_state()
		boss._process_attack_state(2.0)
		_check(boss.global_position.distance_to(endpoint) < 0.01, "Destroyed cover cannot extend a committed path beyond its warning")
		_clear()

func _test_body_blocking() -> void:
	for kind in ["warden", "lacuna"]:
		_large_room()
		var boss: Variant = _boss(kind)
		var blocker := _probe(Vector2(80.0, 18.0), true)
		var victim := _probe(Vector2(155.0, -60.0))
		var other_enemy := _enemy(Vector2(120.0, -16.0))
		boss.target_candidates.append_array([blocker, victim])
		await physics_frame
		_start_warning(boss, kind)
		var endpoint: Vector2 = boss.get_charge_warning_geometry().end
		boss._enter_attack_state()
		_check(boss.get_collision_exceptions().has(blocker) and boss.get_collision_exceptions().has(other_enemy), "Only charge motion excludes player and enemy body blocking")
		boss._process_attack_state(2.0)
		_check(boss.global_position.distance_to(endpoint) < 0.01 and absf(boss.global_position.y) < 0.01, "Player/enemy bodies cannot bend or shorten the committed charge")
		_check(victim.attempts == 0 and blocker.attempts == 1, "Body deflection cannot produce an off-lane hit")
		_check(boss.get_collision_exceptions().is_empty(), "Normal physics bodies collide again after charge completion")
		_clear()

func _test_lifecycle() -> void:
	for kind in ["warden", "lacuna"]:
		for clamp_first in [false, true]:
			_setup()
			actor.global_position = Vector2(575.0, 0.0)
			var boss: Variant = _boss(kind, Vector2(550.0, 0.0))
			await physics_frame
			_start_warning(boss, kind)
			boss._enter_attack_state()
			room.current_effective_room_size = Vector2(600.0, 500.0)
			if clamp_first:
				room._keep_enemies_inside_current_room(0.02)
			boss._process_attack_state(0.02)
			_check(boss.global_position.x <= 300.0 and boss.velocity == Vector2.ZERO and boss.get_collision_exceptions().is_empty(), "Room shrink cancels without a damaging teleport in either clamp order")
			_check(boss._charge_motion.stage == CHARGE.Stage.NONE, "Forced bounds change clears the pending charge")
			_clear()
		_large_room()
		var boss: Variant = _boss(kind)
		await physics_frame
		_start_warning(boss, kind)
		boss._enter_attack_state()
		var endpoint: Vector2 = boss._charge_motion.endpoint
		boss.target = null
		boss.target_candidates.clear()
		boss._process_behavior(2.0)
		_check(boss.global_position.distance_to(endpoint) < 0.01 and boss._charge_motion.stage == CHARGE.Stage.NONE, "Losing the selected target cannot strand an already committed attack")
		_clear()
		_large_room()
		boss = _boss(kind)
		var removed_body := _probe(Vector2(80.0, 18.0), true)
		await physics_frame
		_start_warning(boss, kind)
		boss._enter_attack_state()
		_check(boss.get_collision_exceptions().has(removed_body), "Charge registers the live combat body's physics exception")
		removed_body.free()
		boss._process_attack_state(2.0)
		_check(boss.get_collision_exceptions().is_empty(), "Charge removes PhysicsServer exception RIDs even after the target Node is freed")
		_clear()
		_large_room()
		boss = _boss(kind)
		var first := _probe(Vector2(20.0, 0.0))
		var second := _probe(Vector2(40.0, 0.0))
		boss.target_candidates.append_array([first, second])
		first.on_hit = func() -> void: boss.health_state.set_health(0)
		await physics_frame
		_start_warning(boss, kind)
		boss._enter_attack_state()
		boss._process_attack_state(0.1)
		_check(first.attempts == 1 and second.attempts == 0 and boss.get_collision_exceptions().is_empty(), "Synchronous death stops later damage and releases every body exception")
		if kind == "lacuna":
			_check(boss.seam_zones.is_empty(), "A cancelled hit iteration cannot create a post-death seam")
		_clear()

func _test_real_physics_steps() -> void:
	var prior_rate := Engine.physics_ticks_per_second
	for rate in [30, 60, 120]:
		Engine.physics_ticks_per_second = rate
		for kind in ["warden", "lacuna"]:
			_large_room()
			var boss: Variant = _boss(kind)
			await physics_frame
			await process_frame
			_start_warning(boss, kind)
			var endpoint: Vector2 = boss.get_charge_warning_geometry().end
			boss._enter_attack_state()
			boss.set_physics_process(true)
			while boss.is_physics_processing():
				await physics_frame
			_check(boss.global_position.distance_to(endpoint) < 0.01, "Inherited EnemyBase physics reaches the same exact endpoint at%dHz" % rate)
			_check(boss.measured_steps > 0 and boss.get_collision_exceptions().is_empty(), "Actual engine-driven completion clears collision ownership")
			_clear()
	Engine.physics_ticks_per_second = prior_rate
