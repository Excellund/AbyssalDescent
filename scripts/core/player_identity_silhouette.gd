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


static func draw_bastion(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2, player_core_color: Color) -> void:
	var shield_tip := facing * (body_radius + 10.5)
	var shield_mid := facing * (body_radius + 1.8)
	var shield_w := 6.2
	var shield := PackedVector2Array([
		shield_tip,
		shield_mid + side * shield_w,
		facing * (body_radius - 3.0) + side * (shield_w - 1.4),
		facing * (body_radius - 3.0) - side * (shield_w - 1.4),
		shield_mid - side * shield_w
	])
	canvas.draw_colored_polygon(shield, Color(ENEMY_BASE.COLOR_PLAYER_POINTER.r, ENEMY_BASE.COLOR_PLAYER_POINTER.g, ENEMY_BASE.COLOR_PLAYER_POINTER.b, 0.94))
	var visor_center := facing * (body_radius * 0.32)
	canvas.draw_line(visor_center - side * 3.0, visor_center + side * 3.0, Color(1.0, 0.96, 0.86, 0.9), 1.8)
	var pauldron_l := side * (body_radius + 0.9) - facing * 1.2
	var pauldron_r := -side * (body_radius + 0.9) - facing * 1.2
	canvas.draw_circle(pauldron_l, 3.4, Color(player_core_color.r, player_core_color.g, player_core_color.b, 0.78))
	canvas.draw_circle(pauldron_r, 3.4, Color(player_core_color.r, player_core_color.g, player_core_color.b, 0.78))
	canvas.draw_arc(Vector2.ZERO, body_radius + 7.2, -0.92, 0.92, 28, Color(0.9, 0.94, 1.0, 0.5), 1.8)


static func draw_hexweaver(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	var sigil_r := body_radius + 7.6
	var sigil_pulse := 0.5 + 0.5 * sin(t * 4.6)
	canvas.draw_arc(Vector2.ZERO, sigil_r + sigil_pulse * 1.1, 0.0, TAU, 40, Color(0.96, 0.74, 1.0, 0.52), 1.8)
	var forward_tip := facing * (body_radius + 10.0)
	var forward_base := facing * (body_radius + 3.0)
	var forward_w := 3.2
	var forward_glyph := PackedVector2Array([
		forward_tip,
		forward_base + side * forward_w,
		forward_base - side * forward_w
	])
	canvas.draw_colored_polygon(forward_glyph, Color(1.0, 0.9, 1.0, 0.86))
	canvas.draw_line(forward_base - side * 1.4, forward_tip, Color(1.0, 0.98, 1.0, 0.88), 1.2)
	canvas.draw_line(forward_base + side * 1.4, forward_tip, Color(1.0, 0.98, 1.0, 0.88), 1.2)
	for i in range(3):
		var angle := t * 0.9 + TAU * float(i) / 3.0
		var pivot := Vector2(cos(angle), sin(angle)) * (body_radius + 4.8)
		var glyph_tip := pivot + Vector2.RIGHT.rotated(angle) * 3.3
		var glyph_side := Vector2(-sin(angle), cos(angle)) * 2.2
		var glyph := PackedVector2Array([glyph_tip, pivot + glyph_side, pivot - glyph_side])
		canvas.draw_colored_polygon(glyph, Color(1.0, 0.84, 1.0, 0.7))
	var eye_center := facing * (body_radius * 0.3)
	canvas.draw_circle(eye_center - side * 1.4, 1.4, Color(0.98, 0.92, 1.0, 0.86))
	canvas.draw_circle(eye_center + side * 1.4, 1.4, Color(0.98, 0.92, 1.0, 0.86))
	var focus_eye := facing * (body_radius * 0.52) + side * 0.7
	canvas.draw_circle(focus_eye, 1.25, Color(1.0, 0.96, 1.0, 0.95))
	var rune_back := -facing * (body_radius - 1.0)
	canvas.draw_line(rune_back - side * 4.0, rune_back + side * 4.0, Color(0.86, 0.72, 1.0, 0.62), 1.4)
	canvas.draw_line(rune_back - side * 2.2, rune_back + side * 2.2, Color(1.0, 0.88, 1.0, 0.72), 1.2)


static func draw_veilstrider(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2, speed_t: float) -> void:
	var blade_tip := facing * (body_radius + 12.0)
	var blade_mid := facing * (body_radius + 0.8)
	var blade_w := 3.6
	var blade := PackedVector2Array([
		blade_tip,
		blade_mid + side * blade_w,
		facing * (body_radius - 4.0),
		blade_mid - side * blade_w
	])
	canvas.draw_colored_polygon(blade, Color(0.88, 1.0, 0.94, 0.94))
	var slit_eye := facing * (body_radius * 0.34) + side * 1.9
	canvas.draw_line(slit_eye - side * 2.4, slit_eye + side * 0.9, Color(0.9, 1.0, 0.94, 0.9), 1.7)
	var trail_len := 7.2 + speed_t * 4.6
	var tail_l := -facing * (body_radius - 1.4) + side * 5.8
	var tail_r := -facing * (body_radius - 1.4) - side * 5.8
	canvas.draw_line(tail_l, tail_l - facing * trail_len + side * 1.8, Color(0.64, 1.0, 0.82, 0.64), 1.7)
	canvas.draw_line(tail_r, tail_r - facing * trail_len - side * 1.8, Color(0.64, 1.0, 0.82, 0.64), 1.7)


static func draw_riftlancer(canvas: CanvasItem, body_radius: float, facing: Vector2, side: Vector2, speed_t: float) -> void:
	var lance_tip := facing * (body_radius + 14.0)
	var lance_base := facing * (body_radius + 1.4)
	var lance_w := 2.2
	var lance := PackedVector2Array([
		lance_tip,
		lance_base + side * lance_w,
		facing * (body_radius - 5.2),
		lance_base - side * lance_w
	])
	canvas.draw_colored_polygon(lance, Color(1.0, 0.96, 0.74, 0.95))
	var anchor := -facing * (body_radius - 1.8)
	var fin_out := 6.4
	canvas.draw_line(anchor - side * fin_out, anchor + side * fin_out, Color(0.94, 0.78, 0.34, 0.86), 1.8)
	canvas.draw_line(anchor - side * (fin_out - 2.2), anchor + side * (fin_out - 2.2), Color(1.0, 0.9, 0.52, 0.7), 1.2)
	var eye := facing * (body_radius * 0.36)
	canvas.draw_circle(eye + side * 1.3, 1.45, Color(1.0, 0.95, 0.76, 0.9))
	canvas.draw_circle(eye - side * 1.3, 1.45, Color(1.0, 0.95, 0.76, 0.9))
	var wake_len := 5.6 + speed_t * 5.2
	var wake_l := -facing * (body_radius - 2.0) + side * 4.4
	var wake_r := -facing * (body_radius - 2.0) - side * 4.4
	canvas.draw_line(wake_l, wake_l - facing * wake_len + side * 1.0, Color(1.0, 0.86, 0.42, 0.62), 1.4)
	canvas.draw_line(wake_r, wake_r - facing * wake_len - side * 1.0, Color(1.0, 0.86, 0.42, 0.62), 1.4)
