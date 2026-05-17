extends Node2D

const VISUAL_MATH := preload("res://scripts/shared/visual_math.gd")

var seam_radius: float = 54.0
var seam_duration: float = 4.0
var seam_zones: Array[Dictionary] = []

func _ready() -> void:
	top_level = false
	z_as_relative = false
	z_index = -1
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE

func set_seam_state(incoming_zones: Array[Dictionary], incoming_radius: float, incoming_duration: float) -> void:
	seam_radius = incoming_radius
	seam_duration = maxf(0.001, incoming_duration)
	seam_zones.clear()
	for zone_variant in incoming_zones:
		if not (zone_variant is Dictionary):
			continue
		var src := zone_variant as Dictionary
		seam_zones.append({
			"pos": src.get("pos", Vector2.ZERO) as Vector2,
			"time_left": float(src.get("time_left", 0.0)),
			"pulse": float(src.get("pulse", 0.0))
		})
	queue_redraw()

func clear_seams() -> void:
	if seam_zones.is_empty():
		return
	seam_zones.clear()
	queue_redraw()

func _process(_delta: float) -> void:
	if not seam_zones.is_empty():
		queue_redraw()

func _draw() -> void:
	if seam_zones.is_empty():
		return
	for seam_variant in seam_zones:
		var seam := seam_variant as Dictionary
		var seam_pos := seam.get("pos", Vector2.ZERO) as Vector2
		var draw_pos := Vector2(roundf(seam_pos.x), roundf(seam_pos.y))
		var time_left := float(seam.get("time_left", 0.0))
		var lifetime_ratio := 1.0 - clampf(time_left / seam_duration, 0.0, 1.0)
		var fade := VISUAL_MATH.late_fade(lifetime_ratio, 0.90, 3.0)
		var draw_scale := clampf(time_left / 0.4, 0.0, 1.0)
		var draw_r := seam_radius * draw_scale
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.016 + seam_pos.x * 0.02)
		var tick_pulse := clampf(float(seam.get("pulse", 0.0)) / 0.12, 0.0, 1.0)
		draw_circle(draw_pos, draw_r + 8.0 * draw_scale, Color(0.14, 0.82, 0.62, (0.06 + tick_pulse * 0.08) * fade))
		draw_circle(draw_pos, draw_r, Color(0.14, 0.94, 0.72, (0.16 + tick_pulse * 0.1) * fade))
		draw_arc(draw_pos, draw_r + 6.0 * draw_scale, 0.0, TAU, 32, Color(0.62, 0.94, 0.82, (0.14 + tick_pulse * 0.18) * fade), 2.0)
		draw_arc(draw_pos, (seam_radius - 2.0 + pulse * 2.0) * draw_scale, 0.0, TAU, 36, Color(0.76, 1.0, 0.92, (0.48 + tick_pulse * 0.44) * fade), 3.0)
		draw_arc(draw_pos, draw_r * 0.62, 0.0, TAU, 26, Color(0.2, 0.88, 0.74, 0.2 * fade), 1.4)
		draw_circle(draw_pos, draw_r * 0.22, Color(0.84, 1.0, 0.95, (0.18 + tick_pulse * 0.46) * fade))
		var seam_axis := Vector2.RIGHT.rotated(seam_pos.angle() + pulse * 0.45)
		var seam_cross := seam_axis.orthogonal()
		draw_line(draw_pos - seam_axis * (draw_r * 0.72), draw_pos - seam_axis * (draw_r * 0.16), Color(0.94, 1.0, 0.98, (0.22 + tick_pulse * 0.34) * fade), 1.8)
		draw_line(draw_pos + seam_axis * (draw_r * 0.16), draw_pos + seam_axis * (draw_r * 0.72), Color(0.94, 1.0, 0.98, (0.22 + tick_pulse * 0.34) * fade), 1.8)
		draw_line(draw_pos - seam_cross * (draw_r * 0.3), draw_pos + seam_cross * (draw_r * 0.3), Color(0.7, 1.0, 0.88, (0.12 + tick_pulse * 0.22) * fade), 1.2)
		if tick_pulse > 0.0:
			for spoke_i in range(6):
				var spoke_angle := float(spoke_i) * TAU / 6.0 + pulse * 0.5
				var spoke_dir := Vector2.RIGHT.rotated(spoke_angle)
				var spoke_start := draw_pos + spoke_dir * (draw_r * 0.38)
				var spoke_end := draw_pos + spoke_dir * (draw_r + (6.0 + tick_pulse * 8.0) * draw_scale)
				draw_line(spoke_start, spoke_end, Color(0.92, 1.0, 0.98, (0.34 + tick_pulse * 0.4) * fade), 1.8)
