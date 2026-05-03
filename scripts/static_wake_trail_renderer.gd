extends Node2D

var trails: Array[Dictionary] = []
var max_lifetime: float = 1.0


func set_trails(trail_data: Array[Dictionary], lifetime: float) -> void:
	trails = trail_data
	max_lifetime = maxf(0.001, lifetime)
	queue_redraw()


func clear() -> void:
	trails = []
	queue_redraw()


func _process(_delta: float) -> void:
	if trails.is_empty():
		return
	queue_redraw()


func _draw() -> void:
	if trails.is_empty():
		return
	for trail_entry in trails:
		var trail_pos: Vector2 = trail_entry.get("pos", Vector2.ZERO)
		var trail_life: float = float(trail_entry.get("life", 0.0))
		var life_ratio := clampf(trail_life / max_lifetime, 0.0, 1.0)
		draw_circle(trail_pos, 10.0 * life_ratio, Color(0.96, 0.96, 0.36, 0.28 * life_ratio))
		draw_arc(trail_pos, 13.0 * life_ratio, 0.0, TAU, 14, Color(1.0, 1.0, 0.5, 0.42 * life_ratio), 1.2)
