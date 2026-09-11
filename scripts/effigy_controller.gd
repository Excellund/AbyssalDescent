extends Node2D
## A fixed delivery point, never an actor, autonomous attacker or damage owner.

const PLACE_DISTANCE := 180.0
const FOOTPRINT := 12.0
const BOUNDARY := preload("res://scripts/shared/arena_boundary.gd")
var player: CharacterBody2D
var _shape := CircleShape2D.new()

func initialize(owner_player: CharacterBody2D) -> void:
	player = owner_player
	top_level = true
	global_position = Vector2.ZERO
	z_index = 3
	_shape.radius = FOOTPRINT
	process_mode = Node.PROCESS_MODE_ALWAYS

func placement(body_origin: Vector2, direction: Vector2) -> Vector2:
	var bounds: Rect2 = EnemyReplicationService.get_current_room_bounds()
	if bounds.has_area():
		bounds = bounds.grow(-FOOTPRINT)
	var start := body_origin
	if bounds.has_area():
		start = Vector2(clampf(start.x, bounds.position.x, bounds.end.x), clampf(start.y, bounds.position.y, bounds.end.y))
	var motion := direction.normalized() * PLACE_DISTANCE
	var boundary := BOUNDARY.sweep(start, motion, bounds)
	motion *= float(boundary.get("fraction", 1.0))
	var excluded: Array[RID] = [player.get_rid()]
	for group: String in ["combat_players", "enemies", "players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node is CollisionObject2D:
				excluded.append((node as CollisionObject2D).get_rid())
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0.0, start)
	query.exclude = excluded
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = false
	var space := get_world_2d().direct_space_state
	# A body overlapping solid geometry must first walk clear before planting.
	if not space.intersect_shape(query, 1).is_empty():
		return Vector2.INF
	query.motion = motion
	var fractions: PackedFloat32Array = space.cast_motion(query)
	var fraction := float(fractions[0]) if fractions.size() >= 2 else 1.0
	return start + motion * maxf(0.0, fraction - (0.005 if fraction < 1.0 else 0.0))

func _process(_delta: float) -> void:
	visible = is_instance_valid(player) and bool(player.effigy_deployed) and bool(player._is_alive_state) and not bool(player._combat_removed) and bool(player.combat_damage_enabled) and not bool(player.encounter_input_frozen) and not get_tree().paused
	if visible:
		queue_redraw()

func _draw() -> void:
	if not is_instance_valid(player) or not bool(player.effigy_deployed):
		return
	var center: Vector2 = player.effigy_position
	var direction: Vector2 = player._get_mouse_attack_direction() if player._is_local_control_owner() else player.visual_facing_direction
	var angle := direction.angle()
	var geometry: Dictionary = player._get_melee_attack_geometry({"range": player.attack_range, "arc_degrees": player.attack_arc_degrees})
	var radius := float(geometry.range)
	var half_arc := deg_to_rad(float(geometry.arc_degrees) * 0.5)
	var coral := Color(player.player_body_color, 0.82)
	var ivory := Color(player.player_core_color, 0.95)
	draw_line(player.global_position, center, Color(coral, 0.16), 1.0, true)
	draw_arc(center, radius, angle - half_arc, angle + half_arc, 28, Color(coral, 0.27), 1.3, true)
	for side: float in [-1.0, 1.0]:
		draw_line(center, center + Vector2.from_angle(angle + half_arc * side) * radius, Color(coral, 0.12), 1.0, true)
	draw_circle(center, 19.0, Color(coral, 0.13))
	draw_arc(center, 15.0, 0.0, TAU, 28, coral, 1.5, true)
	draw_circle(center + Vector2(0.0, -7.0), 4.0, ivory)
	draw_line(center + Vector2(0.0, -2.0), center + Vector2(0.0, 9.0), ivory, 3.0, true)
	draw_line(center + Vector2(-10.0, 0.0), center + Vector2(10.0, 0.0), ivory, 2.0, true)
	draw_line(center + Vector2(0.0, 7.0), center + Vector2(-6.0, 13.0), coral, 2.0, true)
	draw_line(center + Vector2(0.0, 7.0), center + Vector2(6.0, 13.0), coral, 2.0, true)
