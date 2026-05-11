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
	var goal := maxf(0.01, float(control_overlay.get("goal", 0.0)))
	var progress := float(control_overlay.get("progress", 0.0))
	var progress_ratio := clampf(progress / goal, 0.0, 1.0)
	var anchor := Vector2(control_overlay.get("anchor", Vector2.ZERO))
	var radius := float(control_overlay.get("radius", 0.0))
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
