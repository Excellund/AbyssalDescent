extends Node2D
## A discharged blast is a short world-space effect, independent of recoil and
## pending-input cancellation. Its geometry comes from the resolved attack.
const LIFETIME := 0.32
const MAX_HITS := 10
var life: float = LIFETIME
var direction: Vector2 = Vector2.RIGHT
var reach: float = 160.0
var arc_degrees: float = 70.0
var serial: int = 0
var hits: Array[Vector2] = []

func initialize(origin: Vector2, aim: Vector2, attack_reach: float, attack_arc: float, shot_serial: int) -> void:
	top_level = true
	global_position = origin
	direction = aim.normalized()
	reach = clampf(attack_reach, 1.0, 600.0)
	arc_degrees = clampf(attack_arc, 1.0, 180.0)
	serial = shot_serial
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 5
	queue_redraw()

func add_hit(position: Vector2) -> void:
	if hits.size() < MAX_HITS and position.is_finite():
		hits.append(position)
		queue_redraw()

func _process(delta: float) -> void:
	life = maxf(0.0, life - delta)
	if life <= 0.0:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var age := LIFETIME - life
	var fade := life / LIFETIME
	var half_arc := deg_to_rad(arc_degrees * 0.5)
	var angle := direction.angle()
	var orange := Color(1.0, 0.43, 0.10)
	var hot := Color(1.0, 0.90, 0.58)
	# The faint full contour marks the actual damage shape immediately; the
	# fast inner front supplies the impact without hiding enemy wind-ups.
	var contour := PackedVector2Array([Vector2.ZERO])
	for i in range(25):
		contour.append(Vector2.from_angle(angle - half_arc + 2.0 * half_arc * i / 24.0) * reach)
	draw_colored_polygon(contour, Color(orange, fade * 0.13))
	draw_arc(Vector2.ZERO, reach, angle - half_arc, angle + half_arc, 32, Color(orange, fade * 0.65), 1.5, true)
	for sign_value in [-1.0, 1.0]:
		draw_line(Vector2.ZERO, direction.rotated(half_arc * sign_value) * reach, Color(orange, fade * 0.38), 1.5, true)
	var front := reach * lerpf(0.22, 1.0, clampf(age / 0.075, 0.0, 1.0))
	draw_arc(Vector2.ZERO, front, angle - half_arc, angle + half_arc, 32, Color(hot, fade * 0.85), 3.5 * fade + 1.0, true)
	var flare := clampf(1.0 - age / 0.09, 0.0, 1.0)
	draw_circle(direction * 10.0, 14.0 * flare, Color(hot, flare * 0.75))
	for i in range(9):
		var ray := direction.rotated(half_arc * (float(i) / 8.0 * 1.8 - 0.9))
		var distance := reach * clampf(age * 3.4 + 0.15 + float(i % 3) * 0.09, 0.0, 1.0)
		draw_line(ray * maxf(0.0, distance - 12.0 * fade), ray * distance, Color(orange.lerp(hot, float(i % 2)), fade * 0.85), 2.0, true)
	for hit in hits:
		var point := to_local(hit)
		var radius := lerpf(5.0, 22.0, 1.0 - fade)
		draw_arc(point, radius * 0.7, 0.0, TAU, 16, Color(hot, fade * 0.75), 1.5, true)
		for i in range(5):
			var ray := Vector2.from_angle(float(i) * TAU / 5.0 + angle)
			draw_line(point + ray * radius * 0.55, point + ray * radius, Color(hot, fade), 2.0, true)
