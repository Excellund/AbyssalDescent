extends RefCounted
## One fixed, host-owned attack path; replicas own only leased geometry.

const BOUNDARY := preload("res://scripts/shared/arena_boundary.gd")
const LEASE_SECONDS := 0.35
enum Stage { NONE, WARNING, CHARGE }

var body: CharacterBody2D
var stage: Stage = Stage.NONE
var origin := Vector2.ZERO
var endpoint := Vector2.ZERO
var direction := Vector2.RIGHT
var speed := 0.0
var duration := 0.0
var time_left := 0.0
var rear := 0.0
var front := 0.0
var radius := 0.0
var blocked := false
var generation := 0
var _shape := CircleShape2D.new()
var _bounds := Rect2()
var _exceptions: Dictionary = {}
var _wire_sequence := 0
var _received_sequence := -1
var _lease := 0.0

func configure(owner_body: CharacterBody2D, body_radius: float, rear_offset: float, front_offset: float, hit_radius: float) -> void:
	body = owner_body
	_shape.radius = body_radius
	rear = rear_offset
	front = front_offset
	radius = hit_radius

func prepare(next_speed: float, next_duration: float, aim: Vector2) -> void:
	cancel()
	speed = maxf(0.0, next_speed)
	duration = maxf(0.0, next_duration)
	time_left = duration
	stage = Stage.WARNING
	_bounds = EnemyReplicationService.get_current_room_bounds()
	update_warning(body.global_position, aim)

func update_warning(next_origin: Vector2, aim: Vector2) -> void:
	if stage != Stage.WARNING:
		return
	if not next_origin.is_finite() or not aim.is_finite():
		cancel()
		return
	origin = next_origin
	direction = aim.normalized() if aim.length_squared() > 0.000001 else Vector2.RIGHT
	var contact := _terrain_sweep(origin, direction * speed * duration)
	if bool(contact.get("outside", false)):
		cancel()
		return
	endpoint = contact.get("position", origin + direction * speed * duration)

func begin() -> bool:
	if stage != Stage.WARNING or _bounds != EnemyReplicationService.get_current_room_bounds():
		cancel()
		return false
	stage = Stage.CHARGE
	time_left = duration
	blocked = false
	_sync_exceptions()
	return true

func advance(delta: float) -> Dictionary:
	if stage != Stage.CHARGE or not is_instance_valid(body) or not is_finite(delta) or delta <= 0.0:
		return {}
	var current_bounds := EnemyReplicationService.get_current_room_bounds()
	if _bounds != current_bounds:
		var reposition := BOUNDARY.sweep(body.global_position, Vector2.ZERO, current_bounds)
		if bool(reposition.get("outside", false)):
			body.global_position = reposition["position"]
		body.velocity = Vector2.ZERO
		cancel()
		return {"cancelled": true}
	var outside := BOUNDARY.sweep(body.global_position, Vector2.ZERO, _bounds)
	if bool(outside.get("outside", false)):
		body.global_position = outside["position"]
		body.velocity = Vector2.ZERO
		cancel()
		return {"cancelled": true}
	_sync_exceptions()
	var start := body.global_position
	var active_delta := minf(delta, time_left)
	var remaining := maxf(0.0, (endpoint - start).dot(direction))
	if not blocked and remaining > 0.00001:
		var travel := direction * minf(speed * active_delta, remaining)
		var boundary := BOUNDARY.sweep(start, travel, _bounds)
		var collision := body.move_and_collide(travel * float(boundary.get("fraction", 1.0)))
		blocked = collision != null or not boundary.is_empty()
		body.velocity = direction * speed if not blocked else Vector2.ZERO
	else:
		body.velocity = Vector2.ZERO
	time_left = maxf(0.0, time_left - active_delta)
	if time_left < 0.000001:
		time_left = 0.0
	return {"start": start, "finish": body.global_position, "finished": time_left <= 0.0, "generation": generation}

func cancel() -> void:
	generation += 1
	_clear_exceptions()
	stage = Stage.NONE
	time_left = 0.0
	blocked = false
	_lease = 0.0

func geometry() -> Dictionary:
	if stage != Stage.WARNING:
		return {}
	return {"origin": origin, "end": endpoint, "direction": direction, "rear": rear, "front": front, "radius": radius}

func warning_polygons() -> Array[PackedVector2Array]:
	if stage != Stage.WARNING:
		return []
	return Geometry2D.offset_polyline(PackedVector2Array([origin - direction * rear, endpoint + direction * front]), radius, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)

func contains_contact(point: Vector2, start: Vector2, finish: Vector2) -> bool:
	return Geometry2D.get_closest_point_to_segment(point, start - direction * rear, finish + direction * front).distance_squared_to(point) <= radius * radius

func build_network_state() -> Array:
	_wire_sequence += 1
	var state: Array = [_wire_sequence, EnemyReplicationService._current_room_sync_id(), stage]
	# Only the warning needs geometry. Existing boss fields own charge/recovery
	# body visuals; their compact phase cue simply clears any leased warning.
	if stage == Stage.WARNING:
		state.append_array([origin, endpoint, int(round(direction.angle() * 10000.0))])
	return state

func apply_network_state(value: Variant) -> bool:
	if not (value is Array):
		return false
	var state: Array = value
	if state.size() not in [3, 6] or not (state[0] is int) or not (state[1] is int) or not (state[2] is int):
		return false
	var sequence: int = state[0]
	var incoming_stage: int = state[2]
	if sequence <= _received_sequence or state[1] != EnemyReplicationService._current_room_sync_id() or incoming_stage < Stage.NONE or incoming_stage > Stage.CHARGE:
		return false
	if incoming_stage != Stage.WARNING:
		if state.size() != 3:
			return false
		_received_sequence = sequence
		stage = incoming_stage as Stage
		_lease = LEASE_SECONDS if incoming_stage == Stage.CHARGE else 0.0
		return true
	if state.size() != 6 or not (state[5] is int):
		return false
	var incoming_origin: Variant = state[3]
	var incoming_end: Variant = state[4]
	if not (incoming_origin is Vector2) or not (incoming_end is Vector2):
		return false
	if not incoming_origin.is_finite() or not incoming_end.is_finite():
		return false
	_received_sequence = sequence
	stage = incoming_stage as Stage
	origin = incoming_origin
	endpoint = incoming_end
	direction = Vector2.from_angle(float(state[5]) * 0.0001)
	# Derive nonzero path direction from the exact endpoints, avoiding angle
	# quantization changing the actual rounded contact caps.
	if origin.distance_squared_to(endpoint) > 0.000001:
		direction = origin.direction_to(endpoint)
	_lease = LEASE_SECONDS
	return true

func tick_replica(delta: float) -> void:
	_lease = maxf(0.0, _lease - maxf(0.0, delta))
	if _lease <= 0.0:
		stage = Stage.NONE

func _terrain_sweep(start: Vector2, motion: Vector2) -> Dictionary:
	var boundary := BOUNDARY.sweep(start, motion, EnemyReplicationService.get_current_room_bounds())
	if bool(boundary.get("outside", false)):
		return boundary
	var fraction := float(boundary.get("fraction", 1.0))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0.0, start)
	query.motion = motion * fraction
	query.margin = body.safe_margin
	query.collision_mask = body.collision_mask
	query.collide_with_areas = false
	var exclusions: Array[RID] = [body.get_rid()]
	for group in ["combat_players", "enemies"]:
		for node in body.get_tree().get_nodes_in_group(group):
			if node is CollisionObject2D:
				exclusions.append((node as CollisionObject2D).get_rid())
	query.exclude = exclusions
	var space := body.get_world_2d().direct_space_state
	var fractions := space.cast_motion(query)
	if fractions.size() >= 2 and fractions[0] < 1.0:
		var full_motion := query.motion
		var safe_fraction := fractions[0]
		var unsafe_fraction := fractions[1]
		for _index in range(3):
			var interval := unsafe_fraction - safe_fraction
			if interval * full_motion.length() <= 0.005:
				break
			query.transform.origin = start + full_motion * safe_fraction
			query.motion = full_motion * interval
			var refined := space.cast_motion(query)
			if refined.size() < 2 or refined[0] >= 1.0:
				break
			unsafe_fraction = safe_fraction + interval * refined[1]
			safe_fraction += interval * refined[0]
		return {"position": start + full_motion * safe_fraction, "fraction": fraction * safe_fraction}
	return boundary

func _sync_exceptions() -> void:
	for group in ["combat_players", "enemies"]:
		for node in body.get_tree().get_nodes_in_group(group):
			if node == body or not (node is PhysicsBody2D):
				continue
			var id: int = node.get_instance_id()
			if not _exceptions.has(id):
				body.add_collision_exception_with(node)
				_exceptions[id] = (node as PhysicsBody2D).get_rid()

func _clear_exceptions() -> void:
	if is_instance_valid(body):
		for other_rid: RID in _exceptions.values():
			# PhysicsServer keeps an exception RID after its Node is freed.
			# Remove the stored RID even when get_collision_exceptions returns null.
			PhysicsServer2D.body_remove_collision_exception(body.get_rid(), other_rid)
	_exceptions.clear()
