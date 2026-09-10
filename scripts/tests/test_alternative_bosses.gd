extends SceneTree
## Real alternate attack resolution, checked against independently classified tells.

const IDS: Array[String] = ["kilnheart", "glassweaver", "null_archivist"]

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
	current_scene = null
	world.free()
	await process_frame
	print("[OK] Alternative bosses: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _boss(id: String, replica: bool = false) -> Alternative:
	var boss := Alternative.new()
	boss.boss_id = id
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
	probe.global_position = kilnheart.global_position
	partner.global_position = kilnheart.global_position + Vector2(240.0, 0.0)
	kilnheart._resolve_attack()
	_check(probe.health == 1000 and partner.health < 1000, "Furnace Halo rewards moving inside the ring")
	kilnheart.free()
	var glassweaver := _boss("glassweaver")
	_prepare(glassweaver, probe, partner, 0)
	var aimed_position := probe.global_position
	partner.global_position = aimed_position + (aimed_position - glassweaver.global_position).normalized().orthogonal() * 150.0
	glassweaver._resolve_attack()
	_check(probe.health == 1000 and partner.health < 1000, "Split Loom leaves its aimed center corridor safe between the two threads")
	glassweaver.free()
	var archivist := _boss("null_archivist")
	_prepare(archivist, probe, partner, 0)
	var recorded_position := probe.global_position
	# Resolve Record after both players dodge, then let the real recovery finish.
	probe.global_position += Vector2(0.0, -300.0)
	partner.global_position = probe.global_position
	archivist._resolve_attack()
	archivist._process_behavior(archivist.recover_time + 0.1)
	archivist.begin_attack(1)
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
			[Vector2(-330.0, 0.0), Vector2(330.0, 0.0)],
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
