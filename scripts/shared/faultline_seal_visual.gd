extends Node2D
## A fuse marker, not an owned damage Field. Kept fixed in world space.
var radius := 76.0
var lifetime := 0.8
var remaining := 0.8

func _process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	queue_redraw()
	if remaining <= 0.0:
		queue_free()

func _draw() -> void:
	var progress := 1.0 - remaining / maxf(0.01, lifetime)
	var ink := Color(0.73, 0.64, 0.88, 0.75)
	draw_circle(Vector2.ZERO, radius, Color(0.42, 0.31, 0.56, 0.07))
	for i in range(4):
		var angle := PI * 0.25 + float(i) * PI * 0.5
		draw_arc(Vector2.ZERO, radius, angle - 0.18, angle + 0.18, 8, ink, 2.0, true)
	draw_arc(Vector2.ZERO, 19.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 32, Color(0.93, 0.81, 0.64, 0.9), 2.5, true)
	var lift := 9.0 + progress * 17.0
	var points := PackedVector2Array([Vector2(0, -lift - 19), Vector2(8, -lift), Vector2(0, -lift + 8), Vector2(-8, -lift)])
	draw_colored_polygon(points, Color(0.53, 0.44, 0.68, 0.6))
	points.append(points[0])
	draw_polyline(points, Color(0.9, 0.81, 1.0, 0.9), 1.8, true)
	draw_line(Vector2(-9, 0), Vector2(9, 0), ink, 2, true)
	draw_line(Vector2(0, -9), Vector2(0, 9), ink, 2, true)
