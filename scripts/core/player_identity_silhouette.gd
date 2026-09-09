extends RefCounted
class_name PlayerIdentitySilhouette

## Stateless silhouette draw helpers for the per-character overlay rendered on
## top of the base player body. Each method is pure geometry — it reads only
## the arguments and writes only via the supplied CanvasItem's draw_* calls.

const ENEMY_BASE := preload("res://scripts/enemy_base.gd")


static func draw_default(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2) -> void:
	var tip := facing * (body_radius + 9.0)
	var base_center := facing * (body_radius - 1.5)
	var fin := 4.9
	var pointer := PackedVector2Array([tip, base_center + side * fin, base_center - side * fin])
	canvas.draw_colored_polygon(pointer, ENEMY_BASE.COLOR_PLAYER_POINTER)
	var eye_pos := facing * (body_radius * 0.34) + side * 1.8
	canvas.draw_circle(eye_pos, 2.0, ENEMY_BASE.COLOR_PLAYER_EYE)
	var wing_l := facing * (body_radius - 2.0) + side * 6.3
	var wing_r := facing * (body_radius - 2.0) - side * 6.3
	canvas.draw_line(wing_l, wing_l - facing * 6.0, ENEMY_BASE.COLOR_PLAYER_WING, 2.0)
	canvas.draw_line(wing_r, wing_r - facing * 6.0, ENEMY_BASE.COLOR_PLAYER_WING, 2.0)


static func draw_bastion(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2, player_core_color: Color, attack_phase: float = -1.0, dash_amount: float = 0.0, _dash_direction: Vector2 = Vector2.ZERO) -> void:
	var strike := _attack_extension(attack_phase)
	var brace := clampf(dash_amount, 0.0, 1.0)
	var shield_x := body_radius - 2.0 + strike * 4.0 + brace * 2.0
	var shield_width := 10.0 - brace * 1.5
	# A broad, dark-edged shield and squared shoulders remain distinct from
	# the circular collision core. Only these decorative pieces change pose.
	_polygon(canvas, facing, side, PackedVector2Array([
		Vector2(shield_x + 10.0, 0.0), Vector2(shield_x + 4.0, shield_width),
		Vector2(shield_x - 3.0, shield_width - 1.0), Vector2(shield_x - 5.0, 0.0),
		Vector2(shield_x - 3.0, -shield_width + 1.0), Vector2(shield_x + 4.0, -shield_width)
	]), Color(0.64, 0.79, 0.92, 0.98))
	_line(canvas, facing, side, Vector2(shield_x + 7.0, 0.0), Vector2(shield_x - 1.0, 0.0), Color(0.94, 0.98, 1.0), 2.0)
	for sign_value: float in [-1.0, 1.0]:
		var shoulder_y := sign_value * (body_radius - brace * 1.5)
		var shoulder_x := -2.0 + strike * 2.0 + brace * 3.0
		_polygon(canvas, facing, side, PackedVector2Array([
			Vector2(shoulder_x + 5.0, shoulder_y - 4.0), Vector2(shoulder_x + 4.0, shoulder_y + 4.0),
			Vector2(shoulder_x - 5.0, shoulder_y + 4.0), Vector2(shoulder_x - 6.0, shoulder_y - 3.0)
		]), player_core_color.lightened(0.15))
		_line(canvas, facing, side, Vector2(shoulder_x - 3.0, shoulder_y), Vector2(shoulder_x + 2.0, shoulder_y), Color(0.75, 0.88, 1.0, 0.7), 1.4)
	_line(canvas, facing, side, Vector2(2.0, -3.5), Vector2(2.0, 3.5), Color(1.0, 0.96, 0.86), 2.0)


static func draw_hexweaver(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2, attack_phase: float = -1.0, dash_amount: float = 0.0, _dash_direction: Vector2 = Vector2.ZERO) -> void:
	var release := -sin(clampf(attack_phase, 0.0, 1.0) * TAU) if attack_phase >= 0.0 else 0.0
	var glyph_radius := body_radius + 3.0 + release * 3.0 - clampf(dash_amount, 0.0, 1.0) * 3.0
	# Three discrete kites replace the decorative full ring. Existing passive
	# rings remain the source of readiness information around this silhouette.
	for angle: float in [PI, PI / 3.0, -PI / 3.0]:
		var radial := Vector2.RIGHT.rotated(angle)
		var across := radial.orthogonal()
		var center := radial * glyph_radius
		_polygon(canvas, facing, side, PackedVector2Array([
			center + radial * 5.0, center + across * 3.5,
			center - radial * 3.0, center - across * 3.5
		]), Color(0.85, 0.63, 1.0, 0.92))
		_line(canvas, facing, side, center - radial, center + radial * 3.0, Color(1.0, 0.92, 1.0), 1.3)
	_polygon(canvas, facing, side, PackedVector2Array([
		Vector2(body_radius + 9.0 + release * 2.0, 0.0), Vector2(body_radius - 1.0, 4.0),
		Vector2(body_radius - 5.0, 0.0), Vector2(body_radius - 1.0, -4.0)
	]), Color(0.98, 0.87, 1.0, 0.95))
	_line(canvas, facing, side, Vector2(2.0, -2.5), Vector2(5.0, 0.0), Color(1.0, 0.96, 1.0), 1.5)
	_line(canvas, facing, side, Vector2(5.0, 0.0), Vector2(2.0, 2.5), Color(1.0, 0.96, 1.0), 1.5)


static func draw_veilstrider(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2, speed_t: float, attack_phase: float = -1.0, dash_amount: float = 0.0, dash_direction: Vector2 = Vector2.ZERO) -> void:
	var strike := _attack_extension(attack_phase)
	var dash := clampf(dash_amount, 0.0, 1.0)
	var blade_side := 4.5 - strike * 5.0
	_polygon(canvas, facing, side, PackedVector2Array([
		Vector2(body_radius + 12.0 + strike * 2.0, blade_side - strike * 3.0),
		Vector2(2.0, blade_side + 4.5), Vector2(-7.0, blade_side + 2.0),
		Vector2(body_radius - 1.0, blade_side - 2.0)
	]), Color(0.87, 1.0, 0.95, 0.97))
	var tail_forward := dash_direction.normalized() if dash > 0.0 and dash_direction.length_squared() > 0.0001 else facing
	var tail_side := tail_forward.orthogonal()
	var tail_length := 8.0 + clampf(speed_t, 0.0, 1.0) * 3.0 + dash * 5.0
	for sign_value: float in [-1.0, 1.0]:
		_polygon(canvas, tail_forward, tail_side, PackedVector2Array([
			Vector2(-body_radius + 4.0, sign_value * 4.0), Vector2(-body_radius + 1.0, sign_value * 10.0),
			Vector2(-body_radius - tail_length, sign_value * (7.0 - dash * 3.0))
		]), Color(0.32, 0.72, 0.59, 0.9))
	_line(canvas, facing, side, Vector2(4.0, -4.0), Vector2(4.0, -0.5), Color(0.95, 1.0, 0.97), 1.8)


static func draw_riftlancer(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2, speed_t: float, attack_phase: float = -1.0, dash_amount: float = 0.0, _dash_direction: Vector2 = Vector2.ZERO) -> void:
	var thrust := _attack_extension(attack_phase) * 6.0
	var dash := clampf(dash_amount, 0.0, 1.0)
	var tip_x := body_radius + 13.0 + thrust
	_line(canvas, facing, side, Vector2(-body_radius + 1.0 + thrust, 0.0), Vector2(tip_x - 3.0, 0.0), Color(0.78, 0.61, 0.28), 3.0)
	_polygon(canvas, facing, side, PackedVector2Array([
		Vector2(tip_x, 0.0), Vector2(tip_x - 10.0, 3.2),
		Vector2(tip_x - 7.0, 0.0), Vector2(tip_x - 10.0, -3.2)
	]), Color(1.0, 0.96, 0.74, 0.98))
	var crossbar_x := -body_radius + 4.0 + thrust * 0.35 + dash * 3.0
	var crossbar_width := 14.0 - dash * 3.0
	_polygon(canvas, facing, side, PackedVector2Array([
		Vector2(crossbar_x + 2.0, -crossbar_width), Vector2(crossbar_x + 4.0, -crossbar_width + 3.0),
		Vector2(crossbar_x + 1.0, 0.0), Vector2(crossbar_x + 4.0, crossbar_width - 3.0),
		Vector2(crossbar_x + 2.0, crossbar_width), Vector2(crossbar_x - 2.0, crossbar_width - 1.0),
		Vector2(crossbar_x - 2.0, -crossbar_width + 1.0)
	]), Color(0.9, 0.73, 0.3, 0.94))
	_line(canvas, facing, side, Vector2(crossbar_x + 1.0, -crossbar_width + 3.0), Vector2(crossbar_x + 1.0, crossbar_width - 3.0), Color(1.0, 0.93, 0.68), 1.3)
	var rear := -body_radius - 3.0 - clampf(speed_t, 0.0, 1.0) * 2.0
	_line(canvas, facing, side, Vector2(rear, -3.0), Vector2(rear, 3.0), Color(0.94, 0.8, 0.45, 0.7), 1.5)
	_line(canvas, facing, side, Vector2(3.0, -3.0), Vector2(3.0, 3.0), Color(1.0, 0.96, 0.8), 1.5)


static func _attack_extension(phase: float) -> float:
	return sin(clampf(phase, 0.0, 1.0) * PI) if phase >= 0.0 else 0.0


static func _polygon(canvas: CanvasItem, facing: Vector2, side: Vector2, points: PackedVector2Array, color: Color) -> void:
	var world_points := PackedVector2Array()
	for point in points:
		world_points.append(facing * point.x + side * point.y)
	canvas.draw_colored_polygon(world_points, color)
	world_points.append(world_points[0])
	canvas.draw_polyline(world_points, Color(0.035, 0.055, 0.075, 0.92), 1.4, true)


static func _line(canvas: CanvasItem, facing: Vector2, side: Vector2, start: Vector2, end: Vector2, color: Color, width: float) -> void:
	canvas.draw_line(facing * start.x + side * start.y, facing * end.x + side * end.y, color, width, true)
