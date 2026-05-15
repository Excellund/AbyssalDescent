extends Node2D

## Draws the Hold the Line control zone ring and progress arc.
## Reads display state from objective_manager each frame via get_control_overlay_state().
## Follows the overlay pattern used by lancer_zone_overlay.gd and lacuna_attack_overlay.gd:
## a lightweight, focused Node2D whose only job is to visualize one gameplay system.
##
## Instantiated and wired in world_generator._setup_objective_runtime_system().

var objective_manager  ## Set by world_generator after objective_manager is created.

func _ready() -> void:
	top_level = false
	z_as_relative = false
	z_index = -1
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(objective_manager):
		return
	var control_overlay: Dictionary = objective_manager.get_control_overlay_state()
	if not bool(control_overlay.get("should_draw", false)):
		return
	var overlay_mode := String(control_overlay.get("overlay_mode", "control"))
	var anchor := Vector2(control_overlay.get("anchor", Vector2.ZERO))
	var radius := float(control_overlay.get("radius", 0.0))

	if overlay_mode == "pulse_ring":
		var ring_time_left := float(control_overlay.get("ring_time_left", 0.0))
		var ring_duration := maxf(0.01, float(control_overlay.get("ring_duration", 0.65)))
		var ring_color := Color(control_overlay.get("ring_color", Color.WHITE))
		var t := clampf(1.0 - ring_time_left / ring_duration, 0.0, 1.0)
		var ring_radius := t * 520.0
		var alpha := (1.0 - t) * 0.82
		# Center origin burst — brief flash at the pulse source, fades by t=0.3
		var origin_t := clampf(1.0 - t / 0.28, 0.0, 1.0)
		if origin_t > 0.0:
			var bc := ring_color
			bc.a = origin_t * 0.32
			draw_circle(Vector2.ZERO, origin_t * 48.0, bc)
			draw_circle(Vector2.ZERO, origin_t * 20.0, Color(1.0, 1.0, 1.0, origin_t * 0.38))
		# Soft trailing bloom behind the leading edge
		var inner_c := ring_color
		inner_c.a = alpha * 0.20
		draw_arc(Vector2.ZERO, maxf(0.0, ring_radius - 28.0), 0.0, TAU, 56, inner_c, 14.0)
		# Main ring — theme color
		var ring_c := ring_color
		ring_c.a = alpha
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 56, ring_c, 3.5)
		# Sharp white leading edge on top
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 56, Color(1.0, 1.0, 1.0, alpha * 0.48), 1.4)
		return

	if overlay_mode == "sweep":
		var capture_progress := float(control_overlay.get("capture_progress", 0.0))
		var capture_goal := maxf(0.01, float(control_overlay.get("capture_goal", 2.0)))
		var capture_ratio := clampf(capture_progress / capture_goal, 0.0, 1.0)
		var is_capturing := capture_ratio > 0.0
		var fill_color := Color(0.94, 0.84, 0.28, 0.08)
		var ring_color := Color(0.94, 0.88, 0.42, 0.44)
		var capture_color := Color(0.68, 1.0, 0.62, 0.96)
		if is_capturing:
			fill_color = Color(0.62, 0.96, 0.52, 0.12)
		draw_circle(anchor, radius, fill_color)
		draw_arc(anchor, radius, 0.0, TAU, 72, ring_color, 3.0)
		if capture_ratio > 0.0:
			draw_arc(anchor, radius - 8.0, -PI * 0.5, -PI * 0.5 + TAU * capture_ratio, 64, capture_color, 6.0)
		var node_dot_color := Color(1.0, 0.96, 0.56, 0.88) if not is_capturing else Color(0.62, 1.0, 0.62, 0.94)
		draw_circle(anchor, 9.0, node_dot_color)
		return

	if overlay_mode == "intercept":
		var drone_progress := float(control_overlay.get("drone_progress", 0.0))
		var drone_pos := Vector2(control_overlay.get("drone_position", Vector2.ZERO))
		var drone_start := Vector2(control_overlay.get("drone_start", Vector2.ZERO))
		var drone_end := Vector2(control_overlay.get("drone_end", Vector2.ZERO))
		var drone_radius := float(control_overlay.get("drone_radius", 80.0))
		var escort_radius := float(control_overlay.get("escort_radius", 240.0))
		var stalled: bool = bool(control_overlay.get("stalled", false))
		var player_in_escort: bool = bool(control_overlay.get("player_in_escort_zone", true))
		var enemies_near := int(control_overlay.get("enemies_near", 0))
		var path_color := Color(0.62, 0.88, 1.0, 0.28)
		var drone_ring_color := Color(0.6, 0.92, 1.0, 0.44) if not stalled else Color(1.0, 0.6, 0.36, 0.6)
		var drone_dot_color := Color(0.8, 1.0, 1.0, 0.92) if not stalled else Color(1.0, 0.76, 0.44, 0.96)
		# Escort zone ring — glow + crisp edge; amber when player outside
		var escort_ring_alpha := 0.28 if player_in_escort else 0.55
		var escort_glow_alpha := 0.08 if player_in_escort else 0.18
		var escort_ring_color := Color(0.56, 1.0, 0.72, escort_ring_alpha) if player_in_escort else Color(1.0, 0.78, 0.32, escort_ring_alpha)
		var escort_glow_color := Color(0.56, 1.0, 0.72, escort_glow_alpha) if player_in_escort else Color(1.0, 0.78, 0.32, escort_glow_alpha)
		draw_arc(drone_pos, escort_radius + 6.0, 0.0, TAU, 72, escort_glow_color, 14.0)
		draw_arc(drone_pos, escort_radius, 0.0, TAU, 72, escort_ring_color, 2.0)
		# Path line
		draw_line(drone_start, drone_end, path_color, 3.0)
		# Progress fill on path
		if drone_progress > 0.0:
			var path_reached := drone_start.lerp(drone_end, drone_progress)
			draw_line(drone_start, path_reached, Color(0.62, 1.0, 0.72, 0.6), 4.0)
		# Drone zone ring (enemy clear radius)
		draw_arc(drone_pos, drone_radius, 0.0, TAU, 48, drone_ring_color, 2.0)
		draw_circle(drone_pos, 7.0, drone_dot_color)
		return

	var goal := maxf(0.01, float(control_overlay.get("goal", 0.0)))
	var progress := float(control_overlay.get("progress", 0.0))
	var progress_ratio := clampf(progress / goal, 0.0, 1.0)
	var player_inside := bool(control_overlay.get("player_inside", false))
	var contested := bool(control_overlay.get("contested", false))

	var fill_color := Color(0.32, 0.72, 0.96, 0.08)
	var ring_color := Color(0.46, 0.86, 1.0, 0.4)
	var progress_color := Color(0.98, 0.86, 0.42, 0.92)
	if player_inside and not contested:
		fill_color = Color(0.38, 0.92, 0.62, 0.1)
		ring_color = Color(0.56, 1.0, 0.74, 0.5)
		progress_color = Color(0.92, 1.0, 0.7, 0.98)
	elif contested:
		fill_color = Color(0.98, 0.46, 0.34, 0.08)
		ring_color = Color(1.0, 0.64, 0.44, 0.54)
		progress_color = Color(1.0, 0.8, 0.52, 0.94)

	draw_circle(anchor, radius, fill_color)
	draw_arc(anchor, radius, 0.0, TAU, 72, ring_color, 3.0)
	draw_arc(anchor, radius - 8.0, -PI * 0.5, -PI * 0.5 + TAU * progress_ratio, 64, progress_color, 6.0)
	draw_circle(anchor, 8.0, Color(1.0, 0.96, 0.72, 0.75))
