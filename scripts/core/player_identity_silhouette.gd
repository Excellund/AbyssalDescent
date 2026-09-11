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
	var shield_offset := strike * 2.5 + brace
	var shield_tip := facing * (body_radius + 9.0 + shield_offset)
	var shield_mid := facing * (body_radius + 1.5 + shield_offset)
	var shield_w := 6.0 - brace * 0.6
	# Keep the round core dominant. The compact shield shifts with the strike;
	# rounded shoulder accents sit inside its rim instead of adding armor blocks.
	var shield := PackedVector2Array([
		shield_tip,
		shield_mid + side * shield_w,
		facing * (body_radius - 3.0 + shield_offset) + side * 4.6,
		facing * (body_radius - 3.0 + shield_offset) - side * 4.6,
		shield_mid - side * shield_w
	])
	canvas.draw_colored_polygon(shield, Color(0.78, 0.88, 0.98, 0.94))
	canvas.draw_line(shield_mid - facing * 1.5, shield_tip - facing * 2.0, Color(0.98, 1.0, 1.0, 0.8), 1.2, true)
	var visor_center := facing * (body_radius * 0.32 + strike * 0.5)
	canvas.draw_line(visor_center - side * 3.0, visor_center + side * 3.0, Color(1.0, 0.96, 0.86, 0.9), 1.8, true)
	var shoulder_color := Color(player_core_color.r, player_core_color.g, player_core_color.b, 0.78)
	for sign_value: float in [-1.0, 1.0]:
		var shoulder := side * sign_value * (body_radius - 1.0 - brace * 0.8) + facing * (-1.2 + strike * 1.4)
		canvas.draw_circle(shoulder, 2.7, shoulder_color)


static func draw_hexweaver(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2, attack_phase: float = -1.0, dash_amount: float = 0.0, _dash_direction: Vector2 = Vector2.ZERO) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	var release := -sin(clampf(attack_phase, 0.0, 1.0) * TAU) if attack_phase >= 0.0 else 0.0
	var contraction := release * 1.8 - clampf(dash_amount, 0.0, 1.0) * 1.2
	var sigil_r := body_radius + 6.8 + contraction
	# Light orbiting marks preserve the original airy outline. Their attack
	# contraction is deliberately small beside the existing body pulse.
	canvas.draw_arc(Vector2.ZERO, sigil_r, 0.0, TAU, 40, Color(0.96, 0.74, 1.0, 0.30), 1.2, true)
	var forward_tip := facing * (body_radius + 9.0 + release)
	var forward_base := facing * (body_radius + 2.0)
	var forward_glyph := PackedVector2Array([
		forward_tip, forward_base + side * 2.8, forward_base - side * 2.8
	])
	canvas.draw_colored_polygon(forward_glyph, Color(1.0, 0.9, 1.0, 0.9))
	for i in range(3):
		var angle := t * 0.9 + TAU * float(i) / 3.0
		var radial := Vector2.RIGHT.rotated(angle)
		var pivot := radial * (body_radius + 4.0 + contraction)
		var glyph_side := radial.orthogonal() * 1.9
		var glyph := PackedVector2Array([pivot + radial * 2.8, pivot + glyph_side, pivot - glyph_side])
		canvas.draw_colored_polygon(glyph, Color(1.0, 0.84, 1.0, 0.74))
	var eye_center := facing * (body_radius * 0.3)
	canvas.draw_circle(eye_center - side * 1.4, 1.4, Color(0.98, 0.92, 1.0, 0.86))
	canvas.draw_circle(eye_center + side * 1.4, 1.4, Color(0.98, 0.92, 1.0, 0.86))
	var rune_back := -facing * (body_radius - 1.0)
	canvas.draw_line(rune_back - side * 3.5, rune_back + side * 3.5, Color(0.86, 0.72, 1.0, 0.62), 1.2, true)


static func draw_veilstrider(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2, speed_t: float, attack_phase: float = -1.0, dash_amount: float = 0.0, dash_direction: Vector2 = Vector2.ZERO) -> void:
	var strike := _attack_extension(attack_phase)
	var dash := clampf(dash_amount, 0.0, 1.0)
	var blade_tip := facing * (body_radius + 11.0 + strike * 1.8) - side * strike * 1.5
	var blade_mid := facing * (body_radius + 0.8)
	var blade_w := 3.2 - dash * 0.4
	var blade := PackedVector2Array([
		blade_tip, blade_mid + side * blade_w,
		facing * (body_radius - 4.0), blade_mid - side * blade_w
	])
	canvas.draw_colored_polygon(blade, Color(0.88, 1.0, 0.94, 0.94))
	var slit_eye := facing * (body_radius * 0.34) + side * 1.9
	canvas.draw_line(slit_eye - side * 2.4, slit_eye + side * 0.9, Color(0.9, 1.0, 0.94, 0.9), 1.7, true)
	# Fine trailing strokes follow actual dash travel without filling in a cape.
	var tail_facing := dash_direction.normalized() if dash > 0.0 and dash_direction.length_squared() > 0.0001 else facing
	var tail_side := tail_facing.orthogonal()
	var trail_len := 6.0 + clampf(speed_t, 0.0, 1.0) * 3.0 + dash * 2.0
	for sign_value: float in [-1.0, 1.0]:
		var tail := -tail_facing * (body_radius - 1.4) + tail_side * sign_value * (5.5 - dash)
		canvas.draw_line(tail, tail - tail_facing * trail_len + tail_side * sign_value * (1.5 - dash), Color(0.64, 1.0, 0.82, 0.56), 1.5, true)


static func draw_riftlancer(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2, speed_t: float, attack_phase: float = -1.0, dash_amount: float = 0.0, _dash_direction: Vector2 = Vector2.ZERO) -> void:
	var thrust := _attack_extension(attack_phase) * 2.8
	var dash := clampf(dash_amount, 0.0, 1.0)
	var lance_tip := facing * (body_radius + 13.0 + thrust)
	var lance_base := facing * (body_radius + 1.4 + thrust)
	var lance := PackedVector2Array([
		lance_tip, lance_base + side * 2.2,
		facing * (body_radius - 5.2 + thrust), lance_base - side * 2.2
	])
	canvas.draw_colored_polygon(lance, Color(1.0, 0.96, 0.74, 0.95))
	# A short rear stroke gives the lance a counterweight while leaving the
	# circular body and bright center unobscured.
	var anchor := -facing * (body_radius - 1.8 - thrust * 0.25)
	var fin_out := 6.0 - dash * 0.8
	canvas.draw_line(anchor - side * fin_out, anchor + side * fin_out, Color(0.94, 0.78, 0.34, 0.82), 1.6, true)
	var eye := facing * (body_radius * 0.36)
	canvas.draw_circle(eye + side * 1.3, 1.45, Color(1.0, 0.95, 0.76, 0.9))
	canvas.draw_circle(eye - side * 1.3, 1.45, Color(1.0, 0.95, 0.76, 0.9))
	var wake_len := 4.5 + clampf(speed_t, 0.0, 1.0) * 3.2
	for sign_value: float in [-1.0, 1.0]:
		var wake := -facing * (body_radius - 2.0) + side * sign_value * 4.4
		canvas.draw_line(wake, wake - facing * wake_len + side * sign_value, Color(1.0, 0.86, 0.42, 0.5), 1.3, true)


static func draw_threadbinder(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2, speed_t: float, attack_phase: float = -1.0, dash_amount: float = 0.0, dash_direction: Vector2 = Vector2.ZERO) -> void:
	# The stable fifth-character draw entry now carries the Keeper's control bar.
	var command := _attack_extension(attack_phase)
	var dash := clampf(dash_amount, 0.0, 1.0)
	var speed := clampf(speed_t, 0.0, 1.0)
	var travel := dash_direction.normalized() if dash > 0.0 and dash_direction.length_squared() > 0.0001 else facing
	var travel_side := travel.orthogonal()
	var ivory := Color(1.0, 0.94, 0.81, 0.97)
	var thread_color := Color(1.0, 0.68, 0.59, 0.62)
	var bar_center := facing * (body_radius + 1.5 + command * 3.0)
	var bar_half_width := 10.0 - dash * 2.0
	# A single transverse control bar reads differently from a blade or lance.
	canvas.draw_line(bar_center - side * bar_half_width, bar_center + side * bar_half_width, ivory, 3.0, true)
	canvas.draw_line(bar_center - facing * 4.2, bar_center + facing * 5.2, ivory, 2.4, true)
	for sign_value: float in [-1.0, 1.0]:
		var start := bar_center + side * sign_value * (bar_half_width - 1.0)
		var finish := -travel * (body_radius + 7.0 + speed * 3.0 + dash * 5.0) + travel_side * sign_value * (7.0 - dash * 2.0)
		var bend := side * sign_value * (body_radius + 8.0 - dash * 3.0) - travel * 4.0
		var thread := PackedVector2Array()
		for index in range(13):
			thread.append(start.bezier_interpolate(bend, finish - travel * 3.0, finish, float(index) / 12.0))
		canvas.draw_polyline(thread, thread_color, 1.2, true)
		canvas.draw_circle(start, 1.8, ivory)
	# Two small mask eyes leave the player's bright core unobscured.
	var eye := facing * (body_radius * 0.4)
	canvas.draw_circle(eye - side * 2.3, 1.45, ivory)
	canvas.draw_circle(eye + side * 2.3, 1.45, ivory)


static func _attack_extension(phase: float) -> float:
	return sin(clampf(phase, 0.0, 1.0) * PI) if phase >= 0.0 else 0.0
