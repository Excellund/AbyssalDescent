extends RefCounted
const ARENA_BOUNDARY := preload("res://scripts/shared/arena_boundary.gd")
## A bounded host-owned launch. Collision bursts use an explicit cause, never
## inferred speed, and the cooldown survives the end of an individual launch.

signal ended

var active: bool = false
var cooldown_left: float = 0.0
var remaining: float = 0.0
var launch_velocity: Vector2
var compression: bool = false
var source_peer_id: int = 0
var owner_id: int = 0
var _burst: Callable

func arm(impulse: Vector2, immovable: bool, peer_id: int, source_owner_id: int, on_burst: Callable) -> bool:
	if active or cooldown_left > 0.0 or not impulse.is_finite():
		return false
	active = true
	compression = immovable
	remaining = 0.16 if compression else 0.32
	cooldown_left = 1.10
	launch_velocity = impulse.limit_length(750.0)
	source_peer_id = peer_id
	owner_id = source_owner_id
	_burst = on_burst
	return true

func cancel() -> void:
	var was_active := active
	active = false
	_burst = Callable()
	launch_velocity = Vector2.ZERO
	if was_active:
		ended.emit()

## Returns true only when launch movement replaces normal enemy movement.
func step(enemy: CharacterBody2D, delta: float) -> bool:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if not active:
		return false
	if not is_instance_valid(enemy) or int(enemy.get_current_health()) <= 0:
		cancel()
		return false
	# A hitch must not carry an enemy beyond this launch's remaining duration.
	var movement_delta := minf(maxf(0.0, delta), maxf(0.0, remaining))
	remaining = maxf(0.0, remaining - movement_delta)
	if compression:
		if remaining <= 0.0:
			_impact(enemy.global_position)
		return false # Never interrupt a boss/Apex telegraph.
	# Short collision steps keep the burst at the first contact even during a
	# hitch, including enemies whose crowd masks exclude physical collisions.
	var motion := launch_velocity * movement_delta
	var steps := maxi(1, int(ceil(motion.length() / 16.0)))
	var step_motion := motion / float(steps)
	for _index in range(steps):
		var start := enemy.global_position
		var boundary := ARENA_BOUNDARY.sweep(start, step_motion, EnemyReplicationService.get_current_room_bounds())
		if bool(boundary.get("outside", false)):
			enemy.global_position = boundary["position"]
			enemy.velocity = Vector2.ZERO
			cancel() # A shrinking room is not a player-caused collision.
			return true
		var collision := enemy.move_and_collide(step_motion * float(boundary.get("fraction", 1.0)))
		enemy.velocity = launch_velocity
		var hit_player := collision != null and collision.get_collider() is Node and (collision.get_collider() as Node).is_in_group("combat_players")
		var impact := not hit_player and (collision != null or not boundary.is_empty())
		if not impact:
			for node in enemy.get_tree().get_nodes_in_group("enemies"):
				if node == enemy or not (node is CharacterBody2D) or node.is_queued_for_deletion():
					continue
				if int(node.get_current_health()) <= 0:
					continue
				var other := node as CharacterBody2D
				var closest := Geometry2D.get_closest_point_to_segment(other.global_position, start, enemy.global_position)
				if closest.distance_to(other.global_position) <= body_radius(enemy) + body_radius(other):
					impact = true
					break
		if impact:
			enemy.velocity = Vector2.ZERO
			_impact(enemy.global_position)
			return true
		if hit_player:
			cancel()
			enemy.velocity = Vector2.ZERO
			return true
	if remaining <= 0.0:
		cancel()
		enemy.velocity = Vector2.ZERO
	return true

func _impact(position: Vector2) -> void:
	var callback := _burst
	cancel() # Clear before damage; death callbacks may re-enter the player.
	if callback.is_valid():
		callback.call(position)

static func body_radius(body: CollisionObject2D) -> float:
	var radius := 13.0
	for shape_owner_id in body.get_shape_owners():
		for i in range(body.shape_owner_get_shape_count(shape_owner_id)):
			var shape := body.shape_owner_get_shape(shape_owner_id, i)
			if shape is CircleShape2D:
				radius = maxf(radius, (shape as CircleShape2D).radius)
			elif shape is CapsuleShape2D:
				radius = maxf(radius, (shape as CapsuleShape2D).radius)
	return radius
