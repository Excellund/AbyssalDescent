extends SceneTree
## Real alternate attack resolution, checked against independently classified tells.

const IDS: Array[String] = ["kilnheart", "glassweaver", "null_archivist"]
const STAGES := preload("res://scripts/shared/boss_stage_registry.gd")
const PHASE := preload("res://scripts/core/combat_phase_coordinator.gd")
const BASTION_SPEED: float = 188.0
const SLOWED_SPEED: float = BASTION_SPEED * 0.45
const BASE_DASH_DISTANCE: float = 175.0
const BASE_DASH_SPEED: float = 720.0

class Probe extends Node2D:
	var health: int = 1000
	var damage_contexts: Array[Dictionary] = []
	var player_feedback: Node = null
	func get_current_health() -> int:
		return health
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		health -= amount
		damage_contexts.append(context.duplicate(true))
	func reset() -> void:
		health = 1000
		damage_contexts.clear()

class Alternative extends "res://scripts/enemy_boss_alternative.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)

class PhysicalProbe extends CharacterBody2D:
	var health: int = 1000
	var player_feedback: Node = null
	func get_current_health() -> int:
		return health
	func take_damage(amount: int, _context: Dictionary = {}) -> void:
		health -= amount
	func _physics_process(_delta: float) -> void:
		velocity = Vector2.ZERO
		move_and_slide()

var world: Node2D
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Alternative boss checks require a disposable validation project")
		quit(1)
		return
	world = Node2D.new()
	world.position = Vector2(76.0, -28.0)
	root.add_child(world)
	current_scene = world
	for id in IDS:
		await _test_geometry_and_damage(id)
		await _test_replica_and_cancellation(id)
	await _test_distinct_safe_zones()
	await _test_living_targets()
	await _test_party_ring_safe_pockets()
	await _test_pressure_sequences()
	await _test_arena_escape_routes()
	await _test_wall_walking_routes()
	await _test_halo_center_walking_escape()
	await _test_slam_physical_bystander()
	current_scene = null
	world.free()
	await process_frame
	print("[OK] Alternative bosses: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _boss(id: String, replica: bool = false) -> Alternative:
	var boss := Alternative.new()
	boss.boss_id = id
	boss.arena_size = STAGES.get_descriptor(IDS.find(id) + 1)["room_size"]
	var collision := CollisionShape2D.new()
	collision.shape = CircleShape2D.new()
	(collision.shape as CircleShape2D).radius = 34.0
	boss.add_child(collision)
	world.add_child(boss)
	boss.set_network_simulation_enabled(not replica)
	boss.set_physics_process(false)
	boss.global_position = Vector2(85.0, -45.0)
	return boss

static func warning_contains(shapes: Array, point: Vector2) -> bool:
	# Keep the test independent of the production shape predicate: compare the
	# committed warning descriptors against actual damage at safe and unsafe points.
	for shape_variant in shapes:
		var shape: Dictionary = shape_variant
		match String(shape.get("kind", "")):
			"circle":
				if point.distance_to(shape.center) <= float(shape.radius):
					return true
			"ring":
				var distance := point.distance_to(shape.center)
				if distance >= float(shape.inner_radius) and distance <= float(shape.radius):
					return true
			"lane":
				var start: Vector2 = shape.start
				var end: Vector2 = shape.end
				var segment := end - start
				var along := clampf((point - start).dot(segment) / maxf(segment.length_squared(), 0.00001), 0.0, 1.0)
				if point.distance_to(start + segment * along) <= float(shape.width):
					return true
	return false

static func sample_points(shapes: Array, origin: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for x in range(-420, 421, 105):
		for y in range(-280, 281, 70):
			points.append(origin + Vector2(x, y))
	for shape_variant in shapes:
		var shape: Dictionary = shape_variant
		match String(shape.get("kind", "")):
			"circle", "ring":
				var center: Vector2 = shape.center
				points.append(center)
				for offset in [-1.0, 1.0]:
					points.append(center + Vector2(float(shape.radius) + offset, 0.0))
					if shape.kind == "ring":
						points.append(center + Vector2(float(shape.inner_radius) + offset, 0.0))
			"lane":
				var start: Vector2 = shape.start
				var end: Vector2 = shape.end
				var direction := (end - start).normalized()
				var middle := (start + end) * 0.5
				points.append(middle)
				for offset in [-1.0, 1.0]:
					points.append(middle + direction.orthogonal() * (float(shape.width) + offset))
					points.append(end + direction * (float(shape.width) + offset))
	return points

func _prepare(boss: Alternative, probe: Probe, partner: Probe, kind: int) -> void:
	boss._cancel_attack()
	boss.global_position = Vector2(85.0, -45.0)
	probe.global_position = boss.global_position + Vector2(170.0, 10.0)
	partner.global_position = probe.global_position
	probe.reset()
	partner.reset()
	boss.target = probe
	boss.target_candidates = [probe, probe, partner]
	boss.begin_attack(kind)

func _test_geometry_and_damage(id: String) -> void:
	var boss := _boss(id)
	var probe := Probe.new()
	var partner := Probe.new()
	world.add_child(probe)
	world.add_child(partner)
	for kind in range(3):
		_prepare(boss, probe, partner, kind)
		var shapes := boss.get_attack_warning_geometry()
		_check(not shapes.is_empty() and boss.boss_state == boss.State.WARNING, "%s attack %d starts a visible warning" % [id, kind])
		var hits: int = 0
		var safe: int = 0
		for point in sample_points(shapes, boss.global_position):
			_prepare(boss, probe, partner, kind)
			probe.global_position = point
			partner.global_position = point
			_check(boss.get_attack_warning_geometry() == shapes, "%s attack %d keeps its committed tell after targets move" % [id, kind])
			boss._resolve_attack()
			var expected := warning_contains(shapes, point)
			var label := "%s attack %d at %s" % [id, kind, point]
			_check((probe.health < 1000) == expected and (partner.health < 1000) == expected, label + ": tell agrees with damage to both players")
			_check(probe.damage_contexts.size() == (1 if expected else 0) and partner.damage_contexts.size() == (1 if expected else 0), label + ": overlapping shapes and duplicate candidates hit once")
			var health_after := probe.health
			boss._resolve_attack()
			_check(probe.health == health_after, label + ": repeated resolution cannot hit again")
			if expected:
				hits += 1
			else:
				safe += 1
		_check(hits > 0 and safe > 0, "%s attack %d has a reachable damaging region and safe space" % [id, kind])
		_check(boss.boss_state == boss.State.RECOVER and boss.get_attack_warning_geometry().is_empty(), "%s attack %d enters recovery and removes its live warning" % [id, kind])
	boss.free()
	probe.free()
	partner.free()
	await process_frame

func _test_replica_and_cancellation(id: String) -> void:
	var host := _boss(id)
	var replica := _boss(id, true)
	replica.global_position += Vector2(-220.0, 80.0)
	var probe := Probe.new()
	var partner := Probe.new()
	world.add_child(probe)
	world.add_child(partner)
	for kind in range(3):
		_prepare(host, probe, partner, kind)
		var shapes := host.get_attack_warning_geometry()
		replica.target = probe
		replica.target_candidates = [probe, partner]
		var initial_packet := host.get_projectile_network_sync_state().duplicate(true)
		replica.apply_projectile_network_sync_state(initial_packet)
		_check(replica.get_attack_warning_geometry() == shapes, "%s attack %d replica uses host world geometry despite interpolated body" % [id, kind])
		for point in sample_points(shapes, host.global_position):
			probe.global_position = point
			replica._resolve_attack()
		_check(probe.health == 1000 and partner.health == 1000, "%s attack %d replica cannot deal damage" % [id, kind])
		host.state_time_left = 0.2
		var late_packet := host.get_projectile_network_sync_state().duplicate(true)
		replica.apply_projectile_network_sync_state(late_packet)
		replica.apply_projectile_network_sync_state(initial_packet)
		_check(is_equal_approx(replica.state_time_left, 0.2), "%s attack %d an older same-cast packet cannot rewind warning time" % [id, kind])
		replica._process_network_visuals(5.0)
		_check(replica.get_attack_warning_geometry().is_empty(), "%s attack %d replica warning expires without a final packet" % [id, kind])
		replica.apply_projectile_network_sync_state(late_packet)
		_check(replica.get_attack_warning_geometry().is_empty(), "%s attack %d repeated packet cannot resurrect an expired warning" % [id, kind])
		host._cancel_attack()
		host._resolve_attack()
		_check(host.get_attack_warning_geometry().is_empty() and probe.health == 1000, "%s attack %d cancellation removes the tell and damage" % [id, kind])
	_prepare(host, probe, partner, 0)
	host.health_state.current_health = 0
	host._resolve_attack()
	_check(probe.health == 1000 and partner.health == 1000, id + ": death cannot resolve a pending attack")
	host._process_behavior(0.01)
	_check(host.get_attack_warning_geometry().is_empty(), id + ": death clears the warning on the next behavior step")
	host.free()
	replica.free()
	probe.free()
	partner.free()
	await process_frame

func _test_distinct_safe_zones() -> void:
	var probe := Probe.new()
	var partner := Probe.new()
	world.add_child(probe)
	world.add_child(partner)
	var kilnheart := _boss("kilnheart")
	_prepare(kilnheart, probe, partner, 1)
	probe.global_position = kilnheart.global_position + Vector2(240.0, 0.0)
	partner.global_position = probe.global_position
	kilnheart._resolve_attack()
	kilnheart._process_behavior(kilnheart.state_time_left + 0.001)
	probe.global_position = kilnheart.global_position
	partner.global_position = kilnheart.global_position + Vector2(240.0, 0.0)
	kilnheart._resolve_attack()
	_check(probe.health == 1000 and partner.health < 1000, "Furnace Halo rewards moving inside the ring")
	kilnheart.free()
	var glassweaver := _boss("glassweaver")
	_prepare(glassweaver, probe, partner, 0)
	var aimed_position := probe.global_position
	probe.global_position = glassweaver._sequence_focus
	partner.global_position = aimed_position
	glassweaver._resolve_attack()
	_check(probe.health == 1000 and partner.health < 1000, "Split Loom threatens the original aim and preserves its visibly offset corridor")
	glassweaver.free()
	var archivist := _boss("null_archivist")
	_prepare(archivist, probe, partner, 0)
	var recorded_position := probe.global_position
	# Resolve Record after both players dodge, then advance the short sequence gap.
	probe.global_position += Vector2(0.0, -300.0)
	partner.global_position = probe.global_position
	archivist._resolve_attack()
	archivist._process_behavior(archivist.state_time_left + 0.001)
	var revision := archivist.get_attack_warning_geometry()
	_check(not revision.is_empty() and revision[0].center == recorded_position, "Revision returns to Record's earlier positions after targets move and recovery ends")
	probe.global_position = recorded_position
	partner.global_position = recorded_position + Vector2(180.0, 0.0)
	archivist._resolve_attack()
	_check(probe.health == 1000 and partner.health < 1000, "Revision reverses Record: its old center is safe while the surrounding band damages")
	archivist.free()
	probe.free()
	partner.free()
	await process_frame

func _test_living_targets() -> void:
	var boss := _boss("kilnheart")
	var dead := Probe.new()
	var living := Probe.new()
	world.add_child(dead)
	world.add_child(living)
	dead.health = 0
	dead.global_position = Vector2(-300.0, -150.0)
	living.global_position = Vector2(220.0, 100.0)
	boss.target = dead
	boss.target_candidates = [dead, living]
	boss.begin_attack(2)
	var shapes := boss.get_attack_warning_geometry()
	_check(shapes.size() == 1 and shapes[0].center == living.global_position, "Cinderfall marks only living party members when the previous target has died")
	boss._resolve_attack()
	_check(dead.health == 0 and dead.damage_contexts.is_empty() and living.health < 1000, "A dead partner is never damaged again while a living partner remains eligible")
	boss.begin_attack(0)
	living.health = 0
	boss._process_behavior(0.01)
	_check(boss.boss_state == boss.State.IDLE and boss.get_attack_warning_geometry().is_empty(), "Losing the last living target cancels the pending warning")
	boss.begin_attack(2)
	_check(boss.get_attack_warning_geometry().is_empty(), "A party with no living targets cannot start another attack")
	boss.free()
	dead.free()
	living.free()
	await process_frame

func _test_party_ring_safe_pockets() -> void:
	var probes: Array[Node2D] = []
	for index in range(4):
		var probe := Probe.new()
		world.add_child(probe)
		probes.append(probe)
	for id in ["glassweaver", "null_archivist"]:
		var boss := _boss(id)
		for offsets in [
			[Vector2.ZERO, Vector2(150.0, 0.0), Vector2(-75.0, 129.9), Vector2(-75.0, -129.9)],
			[Vector2(-520.0, 0.0), Vector2(520.0, 0.0)],
		]:
			boss._cancel_attack()
			var candidates: Array[Node2D] = []
			for index in range(offsets.size()):
				var probe := probes[index] as Probe
				probe.reset()
				probe.global_position = boss.global_position + offsets[index]
				candidates.append(probe)
			boss.target = candidates[0]
			boss.target_candidates = candidates
			if id == "null_archivist":
				boss.begin_attack(0)
				boss._resolve_attack()
				for candidate in candidates:
					(candidate as Probe).reset()
			boss.begin_attack(2 if id == "glassweaver" else 1)
			var shapes := boss.get_attack_warning_geometry()
			for candidate in candidates:
				_check(not warning_contains(shapes, candidate.global_position), "%s party rings preserve each marked center's safe pocket" % id)
			if offsets.size() == 2:
				_check(shapes.size() == 2, "%s keeps well-separated party rings independent" % id)
			var has_danger := false
			for point in sample_points(shapes, boss.global_position):
				if warning_contains(shapes, point):
					has_danger = true
					break
			_check(has_danger, "%s party rings retain a visible damaging outer region" % id)
			boss._resolve_attack()
			for candidate in candidates:
				_check((candidate as Probe).health == 1000, "%s ring overlap cannot damage a player in their marked safe pocket" % id)
		boss.free()
	for probe in probes:
		probe.free()
	await process_frame

func _test_pressure_sequences() -> void:
	var probe: Probe = Probe.new()
	var partner: Probe = Probe.new()
	world.add_child(probe)
	world.add_child(partner)
	for entry: Dictionary in [{"id": "kilnheart", "kind": 1}, {"id": "glassweaver", "kind": 0}, {"id": "glassweaver", "kind": 2}, {"id": "null_archivist", "kind": 0}]:
		var boss: Alternative = _boss(String(entry.id))
		_prepare(boss, probe, partner, int(entry.kind))
		var initial_serial: int = boss._attack_serial
		var original_aim: Vector2 = probe.global_position
		var initial_shapes: Array[Dictionary] = boss.get_attack_warning_geometry()
		var first_safe: Vector2 = boss.global_position + Vector2(210.0, 0.0)
		if boss.boss_id == "glassweaver":
			first_safe = boss._sequence_focus
		elif boss.boss_id == "null_archivist":
			first_safe = original_aim + Vector2(0.0, -132.0)
		_check(not warning_contains(initial_shapes, first_safe), String(entry.id) + ": the first sequence step offers its advertised escape")
		if int(entry.kind) != 2:
			_check(warning_contains(initial_shapes, original_aim), String(entry.id) + ": waiting at the original aim is no longer automatically safe")
		probe.global_position = first_safe
		partner.global_position = first_safe
		boss._process_behavior(boss.warning_duration - 0.01)
		_check(probe.health == 1000 and partner.health == 1000 and boss.boss_state == boss.State.WARNING, String(entry.id) + ": first warning cannot resolve damage early")
		boss._process_behavior(0.011)
		_check(probe.health == 1000 and boss.boss_state == boss.State.RECOVER, String(entry.id) + ": the first safe route survives actual timed resolution")
		var gap: float = boss.state_time_left
		boss._process_behavior(gap + 0.001)
		var followup: Array[Dictionary] = boss.get_attack_warning_geometry()
		_check(boss.boss_state == boss.State.WARNING and boss._attack_serial == initial_serial + 1 and is_equal_approx(boss.state_time_left, boss.warning_duration), String(entry.id) + ": a follow-up begins a fresh full warning and serial")
		_check(warning_contains(followup, first_safe), String(entry.id) + ": staying in the first safe position is threatened by the next warning")
		var escaped: Vector2 = _safe_endpoint(followup, first_safe, boss, SLOWED_SPEED * boss.warning_duration)
		_check(escaped.is_finite(), String(entry.id) + ": a Slowed Bastion can walk from the first escape into the follow-up safe area")
		if escaped.is_finite():
			partner.global_position = escaped
		boss._process_behavior(boss.warning_duration - 0.01)
		_check(probe.health == 1000 and partner.health == 1000, String(entry.id) + ": the follow-up deals no damage before its full warning")
		boss._process_behavior(0.011)
		_check(probe.health < 1000 and partner.health == 1000 and probe.damage_contexts.size() == 1, String(entry.id) + ": follow-up hits a stationary victim once and preserves the new safe route")
		_check(is_equal_approx(boss.state_time_left, boss.recover_time) and boss._pending_attack_kind == -1, String(entry.id) + ": the final cast grants the full original recovery")
		for cancel_reason: String in ["cancel", "death", "party_down"]:
			_prepare(boss, probe, partner, int(entry.kind))
			boss._resolve_attack()
			if cancel_reason == "cancel":
				boss._cancel_attack()
			elif cancel_reason == "death":
				boss.health_state.current_health = 0
			else:
				probe.health = 0
				partner.health = 0
			if cancel_reason != "cancel":
				boss._process_behavior(1.0)
			_check(boss._pending_attack_kind == -1 and boss.get_attack_warning_geometry().is_empty(), String(entry.id) + ": " + cancel_reason + " retires a queued follow-up")
			boss.health_state.current_health = boss.max_health
		boss.free()
	# A frozen native enemy retains both its sequence gap and warning. Pausing
	# does not cancel the committed event or silently consume its recovery.
	var paused_boss: Alternative = _boss("kilnheart")
	_prepare(paused_boss, probe, partner, 1)
	paused_boss._resolve_attack()
	var paused_gap: float = paused_boss.state_time_left
	var coordinator: RefCounted = PHASE.new()
	paused_boss.set_physics_process(true)
	coordinator.set_combat_paused(null, self, true)
	await create_timer(0.28).timeout
	_check(is_equal_approx(paused_boss.state_time_left, paused_gap) and paused_boss.get_attack_warning_geometry().is_empty(), "Native combat pause cannot advance a queued boss follow-up")
	coordinator.set_combat_paused(null, self, false)
	paused_boss.set_physics_process(false)
	paused_boss._process_behavior(paused_gap + 0.001)
	_check(paused_boss.boss_state == paused_boss.State.WARNING, "Resuming the paused sequence starts its full next warning")
	paused_boss.free()
	probe.free()
	partner.free()
	await process_frame

func _safe_endpoint(shapes: Array[Dictionary], start: Vector2, boss: Alternative, distance_budget: float) -> Vector2:
	var bounds: Rect2 = Rect2(world.global_position - boss.arena_size * 0.5, boss.arena_size)
	# Production boss entry clears ordinary-room cover. The remaining movement
	# constraints are these stage-specific walls and the solid boss body.
	var body_radius: float = float(boss.PROFILES[boss.boss_id]["radius"]) + Vector2(16.0, 16.0).length()
	for step: int in range(int(ceil(distance_budget / 6.0)) + 1):
		var distance: float = minf(distance_budget, float(step) * 6.0)
		for direction_index: int in range(64):
			var endpoint: Vector2 = start + Vector2.from_angle(TAU * float(direction_index) / 64.0) * distance
			if not bounds.has_point(endpoint):
				continue
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(boss.global_position, start, endpoint)
			if closest.distance_to(boss.global_position) < body_radius:
				continue
			var clear: bool = true
			for offset: Vector2 in [Vector2.ZERO, Vector2(14, 0), Vector2(-14, 0), Vector2(0, 14), Vector2(0, -14)]:
				if warning_contains(shapes, endpoint + offset):
					clear = false
					break
			if clear:
				return endpoint
	return Vector2.INF

func _test_arena_escape_routes() -> void:
	var probe: Probe = Probe.new()
	var partner: Probe = Probe.new()
	world.add_child(probe)
	world.add_child(partner)
	for id: String in IDS:
		var boss: Alternative = _boss(id)
		for kind: int in range(3):
			for normalized: Vector2 in [Vector2.ZERO, Vector2(0.72, 0), Vector2(0.84, 0.84), Vector2(-0.84, 0.84), Vector2(0.45, -0.45)]:
				_prepare(boss, probe, partner, kind)
				boss._cancel_attack()
				boss.global_position = world.global_position + Vector2(-220.0, 0.0)
				probe.global_position = world.global_position + normalized * boss.arena_size * 0.5
				partner.global_position = probe.global_position
				boss.begin_attack(kind)
				var shapes: Array[Dictionary] = boss.get_attack_warning_geometry()
				var budget: float = BASE_DASH_DISTANCE + SLOWED_SPEED * (boss.warning_duration - BASE_DASH_DISTANCE / BASE_DASH_SPEED)
				var escape: Vector2 = _safe_endpoint(shapes, probe.global_position, boss, budget)
				_check(escape.is_finite(), "%s attack %d at arena fraction %s has a wall/body-safe route with Slow and one normal Dash" % [id, kind, normalized])
				if not escape.is_finite():
					continue
				if id == "kilnheart" and kind == 0:
					var committed: Array[Dictionary] = shapes.duplicate(true)
					var origin: Vector2 = boss.global_position
					probe.global_position = origin
					partner.global_position = escape
					boss._process_behavior(boss.warning_duration * 0.5)
					_check(boss.global_position != origin and boss.global_position.distance_to(origin) <= 420.0, "Slam closes distance during its marked approach")
					_check(boss.get_attack_warning_geometry() == committed and probe.health == 1000 and partner.health == 1000, "Slam movement cannot drag its warning or deal contact damage along the approach")
				probe.global_position = escape
				partner.global_position = escape
				boss._resolve_attack()
				_check(probe.health == 1000 and partner.health == 1000, "%s attack %d actual damage preserves the independently chosen escape" % [id, kind])
		boss.free()
	# Baseline continual outward walking now remains inside Revision's reach.
	var archivist: Alternative = _boss("null_archivist")
	_prepare(archivist, probe, partner, 0)
	var recorded: Vector2 = probe.global_position
	var record_time: float = archivist.warning_duration
	probe.global_position += Vector2(0.0, -132.0)
	partner.global_position = probe.global_position
	archivist._resolve_attack()
	var sequence_gap: float = archivist.state_time_left
	archivist._process_behavior(sequence_gap + 0.001)
	var continual_escape: Vector2 = recorded + Vector2.DOWN * BASTION_SPEED * (record_time + sequence_gap + archivist.warning_duration)
	_check(warning_contains(archivist.get_attack_warning_geometry(), continual_escape), "Continuous baseline walking from Record's initial tell no longer outranges Revision")
	archivist.free()
	probe.free()
	partner.free()
	await process_frame

func _test_wall_walking_routes() -> void:
	var probe: Probe = Probe.new()
	var partner: Probe = Probe.new()
	world.add_child(probe)
	world.add_child(partner)
	for id: String in IDS:
		var boss: Alternative = _boss(id)
		var body_radius: float = float(boss.PROFILES[id]["radius"]) + Vector2(16, 16).length()
		var limit: Vector2 = boss.arena_size * 0.5 - Vector2(125, 125)
		for boss_offset: Vector2 in [Vector2.ZERO, limit, Vector2(-limit.x, limit.y), Vector2(limit.x, -limit.y), Vector2(-300, -395)]:
			for fraction: Vector2 in [Vector2(0.999, 0.999), Vector2(-0.999, 0.999), Vector2(0.999, -0.999), Vector2(-0.999, -0.999), Vector2(0.6, 0), Vector2(-0.6, 0)]:
				for kind: int in range(3):
					_prepare(boss, probe, partner, kind)
					boss._cancel_attack()
					boss.global_position = world.global_position + boss_offset.clamp(-limit, limit)
					probe.global_position = world.global_position + fraction * boss.arena_size * 0.5
					partner.global_position = probe.global_position
					if probe.global_position.distance_to(boss.global_position) < body_radius:
						continue
					if id == "null_archivist" and kind == 1:
						_test_revision_wall_sequence(boss, probe, partner, "boss%s player%s" % [boss_offset, fraction])
						continue
					boss.begin_attack(kind)
					var shapes: Array[Dictionary] = boss.get_attack_warning_geometry()
					if not warning_contains(shapes, probe.global_position):
						continue
					# Include the existing Attack lock and acceleration from rest.
					var walking_budget: float = BASTION_SPEED * (boss.warning_duration - 0.12) - 12.63
					var escape: Vector2 = _safe_endpoint(shapes, probe.global_position, boss, walking_budget)
					_check(escape.is_finite(), "%s %d boss%s player%s has a walking escape inside the real walls" % [id, kind, boss_offset, fraction])
		boss.free()
	probe.free()
	partner.free()
	await process_frame

func _test_revision_wall_sequence(boss: Alternative, probe: Probe, partner: Probe, label: String) -> void:
	# Revision is reachable only after Record. Capture the actual sampled wall
	# position, then follow a modest legal dodge instead of teleporting from an
	# unrelated mark made by the generic fixture setup.
	var recorded: Vector2 = probe.global_position
	boss.begin_attack(0)
	var record_shapes: Array[Dictionary] = boss.get_attack_warning_geometry()
	var record_budget: float = BASTION_SPEED * (boss.warning_duration - 0.12) - 12.63
	var first_escape: Vector2 = _safe_endpoint(record_shapes, recorded, boss, record_budget)
	_check(warning_contains(record_shapes, recorded) and first_escape.is_finite(), "Record " + label + " offers a walking dodge from its actual near-wall mark")
	if not first_escape.is_finite():
		return
	probe.global_position = first_escape
	partner.global_position = first_escape
	boss._process_behavior(boss.warning_duration)
	_check(probe.health == 1000 and partner.health == 1000, "Record " + label + " actual damage preserves the independently selected dodge")
	boss._process_behavior(boss.state_time_left + 0.001)
	var revision: Array[Dictionary] = boss.get_attack_warning_geometry()
	_check(boss.boss_state == boss.State.WARNING and boss.attack_kind == 1 and not warning_contains(revision, recorded), "Revision " + label + " follows Record and retains its promised shared safe center")
	var return_budget: float = SLOWED_SPEED * (boss.warning_duration - 0.12) - 3.0
	var return_point: Vector2 = _safe_endpoint(revision, first_escape, boss, return_budget)
	_check(return_point.is_finite(), "Revision " + label + " has a reachable return after the modest dodge, even with Slow")
	if not return_point.is_finite():
		return
	probe.global_position = return_point
	partner.global_position = return_point
	boss._process_behavior(boss.warning_duration)
	_check(probe.health == 1000 and partner.health == 1000, "Revision " + label + " actual damage preserves the independently selected return")

func _test_halo_center_walking_escape() -> void:
	var boss: Alternative = _boss("kilnheart")
	var probe: Probe = Probe.new()
	world.add_child(probe)
	boss.global_position = world.global_position + Vector2(505, 325)
	probe.global_position = world.global_position + Vector2(380, 200)
	boss.target = probe
	boss.target_candidates = [probe]
	boss.begin_attack(1)
	var shapes: Array[Dictionary] = boss.get_attack_warning_geometry()
	_check(warning_contains(shapes, probe.global_position), "Halo can begin with a player at its clamped center away from the boss body")
	var budget: float = BASTION_SPEED * (boss.warning_duration - 0.12) - 12.63
	var escape: Vector2 = _safe_endpoint(shapes, probe.global_position, boss, budget)
	_check(escape.is_finite(), "Halo OUT allows a walking escape from its clamped center after Attack lock and acceleration")
	boss.free()
	probe.free()
	await process_frame

func _test_slam_physical_bystander() -> void:
	var boss: Alternative = _boss("kilnheart")
	var aim: Probe = Probe.new()
	var bystander: PhysicalProbe = PhysicalProbe.new()
	var collider: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(32, 32)
	collider.shape = rectangle
	bystander.add_child(collider)
	world.add_child(aim)
	world.add_child(bystander)
	boss.global_position = world.global_position + Vector2(-400, 0)
	aim.global_position = world.global_position + Vector2(40, 0)
	bystander.global_position = world.global_position + Vector2(-220, 0)
	var initial_position: Vector2 = bystander.global_position
	var original_layer: int = boss.collision_layer
	boss.target = aim
	boss.target_candidates = [aim, bystander]
	boss.begin_attack(0)
	_check(not warning_contains(boss.get_attack_warning_geometry(), initial_position), "The native stationary bystander starts outside the committed Slam disk")
	_check(boss.collision_layer == 0, "Slam suppresses body blocking only during its approach")
	for frame: int in range(76):
		boss._process_behavior(1.0 / 60.0)
		await physics_frame
	_check(bystander.health == 1000 and bystander.global_position.distance_to(initial_position) < 0.1, "A real 32 by 32 collider is neither carried into Slam nor damaged along its path")
	_check(boss.collision_layer == original_layer, "Slam resolution restores the original body collision layer")
	boss.begin_attack(0)
	boss._cancel_attack()
	_check(boss.collision_layer == original_layer, "Cancelling an approaching Slam also restores its body collision layer")
	boss.free()
	aim.free()
	bystander.free()
	await process_frame
