extends Node2D
## Confirmed Burst damage launches a host-owned projectile. Replicas only draw
## bounded snapshots; no visual correction can create damage or a new action.

const REGISTRY := preload("res://scripts/shared/combat_interaction_registry.gd")
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const BODY_GEOMETRY := preload("res://scripts/enemy_launch_state.gd")
const ARENA_BOUNDARY := preload("res://scripts/shared/arena_boundary.gd")
const SPEED := 620.0
const RADIUS := 8.0
const MAX_RANGE := 528.0
const MAX_PROJECTILES := 32
const MAX_STEP := 8.0
const STATE_INTERVAL := 0.08
const REMOTE_LEASE := 0.35

class Projectile extends RefCounted:
	var id: int = 0
	var position: Vector2
	var direction: Vector2
	var travel_left: float = 0.0
	var raw_amount: float = 0.0
	var damage_coefficient: float = 0.0
	var remaining_targets: int = 1
	var interaction: Dictionary = {}
	var hit_ids: Dictionary = {}
	var target: WeakRef
	var kill_proc_suppression: int = 0
	var trail: Array[Vector2] = []
	var presentation_finished: bool = false

var player: CharacterBody2D
var projectiles: Array[Projectile] = []
var _next_id: int = 1
var _sequence: int = 0
var _received_sequence: int = -1
var _received_epoch: int = 0
var _discard_through: int = 0
var _highest_received_id: int = 0
var _generation: int = 0
var _state_left: float = 0.0
var _remote_lease: float = 0.0
var _identity: String = ""
var _shape := CircleShape2D.new()

func initialize(owner_player: CharacterBody2D) -> void:
	player = owner_player
	top_level = true
	global_position = Vector2.ZERO
	z_index = 5
	_shape.radius = RADIUS
	_identity = _current_identity()
	set_physics_process(false)

func _current_identity() -> String:
	return "%s:%d" % [REGISTRY.current_run(), REGISTRY.current_room()]

func _visible_allowed() -> bool:
	return is_instance_valid(player) and player.is_inside_tree() and not player.is_queued_for_deletion() and bool(player._is_alive_state) and not bool(player._combat_removed) and bool(player.combat_damage_enabled) and not bool(player.encounter_input_frozen)

func _authority() -> bool:
	return not MultiplayerSessionManager.is_remote_replica()

func launch(event: Dictionary) -> bool:
	if not _authority() or not _visible_allowed() or get_tree().paused or not bool(player.reward_spark_relay) or projectiles.size() >= MAX_PROJECTILES:
		return false
	var action: Dictionary = event.get("interaction", {})
	if not bool(event.get("shared", false)) or not REGISTRY.action_forms(action).has("Burst") or not player.combat_interactions.accepts_action(action) or not player.combat_interactions.has_reaction(action, "spark_relay"):
		return false
	var origin := player.global_position
	var target_position: Vector2 = event.get("position", Vector2.INF)
	if not origin.is_finite() or not target_position.is_finite():
		return false
	if _identity != _current_identity():
		cancel()
		_identity = _current_identity()
	var ratio := clampf(float(player.spark_relay_damage_ratio), 0.0, 1.0)
	var projectile := Projectile.new()
	projectile.position = origin
	projectile.travel_left = clampf(float(player.spark_relay_travel_range), 0.0, MAX_RANGE)
	var reference: Variant = event.get("target")
	var preferred: Node = reference.get_ref() if reference is WeakRef else null
	var target := _acquire_target(projectile, _geometry_exclusions(), preferred)
	if target == null:
		return false
	projectile.target = weakref(target)
	projectile.direction = origin.direction_to(target.global_position)
	if projectile.direction.is_zero_approx():
		projectile.direction = Vector2.RIGHT
	projectile.id = _next_id
	_next_id += 1
	projectile.raw_amount = float(event.get("raw_amount", 0.0)) * ratio
	projectile.damage_coefficient = float(event.get("damage_coefficient", 0.0)) * ratio
	projectile.remaining_targets = clampi(int(player.spark_relay_max_targets), 1, 3)
	projectile.interaction = action.duplicate(true)
	var context: Dictionary = event.get("context", {})
	projectile.kill_proc_suppression = DAMAGEABLE.sanitize_kill_proc_suppression(context.get("kill_proc_suppression", 0))
	projectiles.append(projectile)
	set_physics_process(true)
	_publish_state(true)
	queue_redraw()
	return true

func cancel() -> void:
	_generation += 1
	var had_projectiles := not projectiles.is_empty()
	projectiles.clear()
	_remote_lease = 0.0
	_discard_through = maxi(_discard_through, _highest_received_id)
	set_physics_process(false)
	if had_projectiles and _authority() and is_instance_valid(player) and player.is_inside_tree():
		_publish_state(true)
	queue_redraw()

func _physics_process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if _identity != _current_identity():
		cancel()
		_identity = _current_identity()
		return
	if not _visible_allowed():
		cancel()
		return
	if get_tree().paused:
		return
	if projectiles.is_empty():
		return
	var authority := _authority()
	if not authority:
		_remote_lease -= delta
		if _remote_lease <= 0.0:
			cancel()
			return
	var exclusions := _geometry_exclusions()
	var generation := _generation
	var changed := false
	for projectile: Projectile in projectiles.duplicate():
		if projectile.presentation_finished:
			continue
		if authority and not player.combat_interactions.accepts_action(projectile.interaction):
			projectiles.erase(projectile)
			changed = true
			continue
		var distance := minf(SPEED * delta, projectile.travel_left)
		while distance > 0.000001 and projectile.remaining_targets > 0:
			if authority:
				var target: Node = projectile.target.get_ref() if projectile.target != null else null
				if not _target_valid(projectile, target):
					target = _acquire_target(projectile, exclusions)
					if target == null:
						projectile.travel_left = 0.0
						break
					projectile.target = weakref(target)
					changed = true
				var direction := projectile.position.direction_to((target as Node2D).global_position)
				if not direction.is_zero_approx():
					projectile.direction = direction
			var step := minf(MAX_STEP, distance)
			var start := projectile.position
			var motion := projectile.direction * step
			var wall := _wall_sweep(start, motion, exclusions)
			if bool(wall.get("outside", false)):
				projectile.travel_left = 0.0
				break
			var fraction := float(wall.get("fraction", 1.0))
			projectile.position += motion * fraction
			if authority:
				_apply_segment_hits(projectile, start, projectile.position, exclusions)
				if generation != _generation:
					return
			projectile.travel_left = maxf(0.0, projectile.travel_left - step * fraction)
			distance -= step
			if not wall.is_empty():
				projectile.travel_left = 0.0
				break
		projectile.trail.append(projectile.position)
		if projectile.trail.size() > 8:
			projectile.trail.pop_front()
		if projectile.travel_left <= 0.000001 or projectile.remaining_targets <= 0:
			if authority:
				projectiles.erase(projectile)
			else:
				projectile.presentation_finished = true
			changed = true
	if authority:
		_state_left -= delta
		if changed or _state_left <= 0.0:
			_publish_state(changed)
	if projectiles.is_empty():
		set_physics_process(false)
	queue_redraw()

func _geometry_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = []
	for group in ["combat_players", "enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is CollisionObject2D:
				exclusions.append(node.get_rid())
	return exclusions

func _target_valid(projectile: Projectile, target: Node) -> bool:
	if not is_instance_valid(target) or not (target is CharacterBody2D) or not target.is_inside_tree() or target.is_queued_for_deletion() or not target.is_in_group("enemies") or DAMAGEABLE._read_target_health(target) <= 0 or projectile.hit_ids.has(target.get_instance_id()):
		return false
	var body := target as CharacterBody2D
	return body.global_position.is_finite() and projectile.position.distance_to(body.global_position) <= projectile.travel_left + RADIUS + BODY_GEOMETRY.body_radius(body)

func _acquire_target(projectile: Projectile, exclusions: Array[RID], preferred: Node = null) -> CharacterBody2D:
	var candidates: Array[CharacterBody2D] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if _target_valid(projectile, node):
			candidates.append(node as CharacterBody2D)
	candidates.sort_custom(func(a: CharacterBody2D, b: CharacterBody2D) -> bool:
		if a == preferred or b == preferred:
			return a == preferred
		var a_distance := projectile.position.distance_squared_to(a.global_position)
		var b_distance := projectile.position.distance_squared_to(b.global_position)
		return a.get_instance_id() < b.get_instance_id() if is_equal_approx(a_distance, b_distance) else a_distance < b_distance)
	for candidate in candidates:
		# Reserve the actual swept bolt width, not just a center-line ray. Target
		# acquisition never grants a route through cover or outside this room.
		var motion := candidate.global_position - projectile.position
		var contact_distance := maxf(0.0, motion.length() - RADIUS - BODY_GEOMETRY.body_radius(candidate))
		if _wall_sweep(projectile.position, motion.normalized() * contact_distance, exclusions).is_empty():
			return candidate
	return null

func _wall_sweep(start: Vector2, motion: Vector2, exclusions: Array[RID]) -> Dictionary:
	var boundary := ARENA_BOUNDARY.sweep(start, motion, EnemyReplicationService.get_current_room_bounds())
	if bool(boundary.get("outside", false)):
		return boundary
	var boundary_fraction := float(boundary.get("fraction", 1.0))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0.0, start)
	query.exclude = exclusions
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = false
	var space := get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return {"fraction": 0.0}
	query.motion = motion * boundary_fraction
	var fractions := space.cast_motion(query)
	if fractions.size() >= 2 and fractions[0] < 1.0:
		return {"fraction": clampf(fractions[0], 0.0, 1.0) * boundary_fraction}
	return boundary

func _apply_segment_hits(projectile: Projectile, start: Vector2, finish: Vector2, exclusions: Array[RID]) -> void:
	var candidates: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is CharacterBody2D) or node.is_queued_for_deletion() or DAMAGEABLE._read_target_health(node) <= 0 or projectile.hit_ids.has(node.get_instance_id()):
			continue
		var enemy := node as CharacterBody2D
		var closest := Geometry2D.get_closest_point_to_segment(enemy.global_position, start, finish)
		if closest.distance_to(enemy.global_position) > RADIUS + BODY_GEOMETRY.body_radius(enemy):
			continue
		var sight := PhysicsRayQueryParameters2D.create(closest, enemy.global_position, 0xFFFFFFFF, exclusions)
		if closest.distance_squared_to(enemy.global_position) > 0.000001 and not get_world_2d().direct_space_state.intersect_ray(sight).is_empty():
			continue
		candidates.append({"enemy": enemy, "distance": (enemy.global_position - start).dot(projectile.direction)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var generation := _generation
	for candidate: Dictionary in candidates:
		var enemy := candidate.enemy as CharacterBody2D
		if not is_instance_valid(enemy) or DAMAGEABLE._read_target_health(enemy) <= 0:
			continue
		projectile.hit_ids[enemy.get_instance_id()] = true
		projectile.remaining_targets -= 1
		var context := REGISTRY.damage_context(projectile.interaction, "spark_relay_projectile", {"secondary": true, "attack_origin": start, "damage_direction": projectile.direction, "raw_amount": projectile.raw_amount, "damage_coefficient": projectile.damage_coefficient, "kill_proc_suppression": projectile.kill_proc_suppression})
		DAMAGEABLE.apply_keyword_reaction_damage(enemy, int(round(projectile.raw_amount)), context, int(projectile.interaction.owner))
		if generation != _generation:
			return
		if not _visible_allowed():
			cancel()
			return
		if projectile.remaining_targets <= 0:
			return

func build_network_state() -> Dictionary:
	var states: Array = []
	for projectile: Projectile in projectiles:
		states.append([projectile.id, projectile.position.x, projectile.position.y, projectile.direction.x, projectile.direction.y, projectile.travel_left])
	return {"run": REGISTRY.current_run(), "room": REGISTRY.current_room(), "epoch": int(player.combat_interactions._accepted_epoch), "serial": _sequence, "highest": _next_id - 1, "projectiles": states}

func _publish_state(reliable: bool = false) -> void:
	_sequence += 1
	_state_left = STATE_INTERVAL
	if MultiplayerSessionManager.should_broadcast():
		PlayerReplicationService.broadcast_spark_relay_state(int(player.player_id), build_network_state(), reliable)

func apply_network_state(payload: Dictionary) -> void:
	if _authority() or not is_instance_valid(player) or payload.get("run") != REGISTRY.current_run() or payload.get("room") != REGISTRY.current_room():
		return
	for key in ["epoch", "serial", "highest"]:
		if not (payload.get(key) is int):
			return
	var epoch := int(payload.epoch)
	var serial := int(payload.serial)
	var highest := int(payload.highest)
	if epoch <= 0 or epoch < int(player.combat_interactions._accepted_epoch) or epoch < _received_epoch or (epoch == _received_epoch and serial <= _received_sequence) or highest < 0:
		return
	if player._is_local_control_owner() and epoch != int(player.combat_interactions._epoch):
		return
	var states: Variant = payload.get("projectiles")
	if not (states is Array) or states.size() > MAX_PROJECTILES:
		return
	var incoming: Array[Projectile] = []
	var ids: Dictionary = {}
	var previous: Dictionary = {}
	var discard_through := _discard_through if epoch == _received_epoch else 0
	if epoch == _received_epoch and _identity == _current_identity():
		for projectile: Projectile in projectiles:
			previous[projectile.id] = projectile
	for entry: Variant in states:
		if not (entry is Array) or entry.size() != 6 or not (entry[0] is int):
			return
		for index in range(1, 6):
			if not (entry[index] is float or entry[index] is int) or not is_finite(float(entry[index])):
				return
		var id := int(entry[0])
		var position_value := Vector2(float(entry[1]), float(entry[2]))
		var direction_value := Vector2(float(entry[3]), float(entry[4]))
		var travel := float(entry[5])
		if id <= 0 or id > highest or ids.has(id) or absf(position_value.x) > 100000.0 or absf(position_value.y) > 100000.0 or direction_value.length() < 0.99 or direction_value.length() > 1.01 or travel < 0.0 or travel > MAX_RANGE:
			return
		ids[id] = true
		if id <= discard_through:
			continue
		var projectile := Projectile.new()
		if previous.has(id):
			var prior: Projectile = previous[id]
			projectile.trail.assign(prior.trail)
			projectile.presentation_finished = prior.presentation_finished
		projectile.id = id
		projectile.position = position_value
		projectile.direction = direction_value.normalized()
		projectile.travel_left = travel
		incoming.append(projectile)
	_received_epoch = epoch
	_received_sequence = serial
	_highest_received_id = highest
	_discard_through = highest if states.is_empty() else discard_through
	_identity = _current_identity()
	if not _visible_allowed():
		cancel()
		return
	projectiles = incoming
	_remote_lease = REMOTE_LEASE
	set_physics_process(not projectiles.is_empty())
	queue_redraw()

func _draw() -> void:
	var accent := Color(0.88, 0.80, 0.55, 0.94)
	for projectile: Projectile in projectiles:
		if projectile.presentation_finished:
			continue
		for index in range(1, projectile.trail.size()):
			draw_line(projectile.trail[index - 1], projectile.trail[index], Color(accent, float(index) / float(projectile.trail.size()) * 0.35), 2.0, true)
		var center := projectile.position
		var back := center - projectile.direction * 12.0
		var normal := projectile.direction.orthogonal()
		draw_circle(center, RADIUS + 3.0, Color(accent, 0.10))
		draw_polyline(PackedVector2Array([back, center - projectile.direction * 5.0 + normal * 4.0, center + projectile.direction * 5.0, center - normal * 3.0]), accent, 2.2, true)
		draw_circle(center, 2.5, Color(1.0, 0.96, 0.81, 0.95))
