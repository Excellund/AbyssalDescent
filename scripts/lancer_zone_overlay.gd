extends Node2D

var zone_radius: float = 56.0
var zone_duration: float = 1.6
var zone_tick_interval: float = 0.3
var zones: Array[Dictionary] = []
var bolt_active: bool = false
var bolt_position_local: Vector2 = Vector2.ZERO
var bolt_direction_local: Vector2 = Vector2.ZERO
var bolt_predicted_impact_local: Vector2 = Vector2.ZERO
var bolt_travel_t: float = 0.0

func _ready() -> void:
	top_level = false
	z_as_relative = false
	z_index = -1
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE

func set_zone_state(incoming_zones: Array[Dictionary], incoming_zone_radius: float, incoming_zone_duration: float, incoming_zone_tick_interval: float) -> void:
	zone_radius = incoming_zone_radius
	zone_duration = maxf(0.001, incoming_zone_duration)
	zone_tick_interval = maxf(0.001, incoming_zone_tick_interval)
	zones.clear()
	for zone_variant in incoming_zones:
		if not (zone_variant is Dictionary):
			continue
		var src := zone_variant as Dictionary
		var local_pos := src.get("pos_local", Vector2.ZERO) as Vector2
		if src.has("pos"):
			local_pos = src.get("pos", local_pos) as Vector2
		zones.append({
			"zone_id": int(src.get("zone_id", -1)),
			"pos_local": local_pos,
			"time_left": float(src.get("time_left", 0.0)),
			"tick_timer": float(src.get("tick_timer", zone_tick_interval)),
			"spawn_flash": float(src.get("spawn_flash", 0.0)),
			"tick_flash": float(src.get("tick_flash", 0.0))
		})
	queue_redraw()

func clear_zones() -> void:
	if zones.is_empty():
		if not bolt_active:
			return
	zones.clear()
	bolt_active = false
	queue_redraw()

func set_bolt_state(active: bool, position_local: Vector2, direction_local: Vector2, predicted_impact_local: Vector2, travel_t: float) -> void:
	bolt_active = active
	if not active:
		queue_redraw()
		return
	bolt_position_local = position_local
	bolt_direction_local = direction_local
	bolt_predicted_impact_local = predicted_impact_local
	bolt_travel_t = clampf(travel_t, 0.0, 1.0)
	queue_redraw()

func _process(_delta: float) -> void:
	if not zones.is_empty() or bolt_active:
		queue_redraw()

func _draw() -> void:
	if zones.is_empty() and not bolt_active:
		return
	for zone_variant in zones:
		var z := zone_variant as Dictionary
		var z_local := z.get("pos_local", Vector2.ZERO) as Vector2
		var z_draw := Vector2(roundf(z_local.x), roundf(z_local.y))
		var z_t := clampf(float(z.get("time_left", 0.0)) / zone_duration, 0.0, 1.0)
		var spawn_flash := float(z.get("spawn_flash", 0.0))
		var tick_flash := float(z.get("tick_flash", 0.0))
		var tick_progress := 1.0 - clampf(float(z.get("tick_timer", zone_tick_interval)) / zone_tick_interval, 0.0, 1.0)

		draw_circle(z_draw, zone_radius, Color(0.62, 0.3, 0.9, 0.16 * z_t + tick_flash * 0.62))
		draw_arc(z_draw, zone_radius, 0.0, TAU, 44, Color(0.82, 0.52, 1.0, 0.56 * z_t + tick_flash * 0.66), 3.0)
		draw_arc(z_draw, zone_radius - 6.0, 0.0, TAU, 44, Color(0.98, 0.84, 1.0, 0.20 * z_t + tick_flash * 0.42), 1.8)

		var tick_start := -PI * 0.5
		var tick_end := tick_start + TAU * tick_progress
		draw_arc(z_draw, zone_radius + 7.0, tick_start, tick_end, 36, Color(1.0, 0.94, 1.0, 0.58 * z_t), 2.0)

		draw_circle(z_draw, 6.0 + tick_flash * 2.2, Color(0.98, 0.86, 1.0, 0.52 * z_t + tick_flash * 0.72))

		if spawn_flash > 0.0:
			var impact_t := clampf(spawn_flash / 0.24, 0.0, 1.0)
			var impact_r := zone_radius * (1.1 + (1.0 - impact_t) * 0.5)
			draw_arc(z_draw, impact_r, 0.0, TAU, 44, Color(1.0, 0.84, 1.0, 0.75 * impact_t), 3.2)

	if bolt_active:
		var b_local := Vector2(roundf(bolt_position_local.x), roundf(bolt_position_local.y))
		var predicted_local := Vector2(roundf(bolt_predicted_impact_local.x), roundf(bolt_predicted_impact_local.y))
		var b_dir := bolt_direction_local.normalized() if bolt_direction_local.length_squared() > 0.000001 else Vector2.RIGHT
		draw_arc(predicted_local, zone_radius, 0.0, TAU, 40, Color(0.86, 0.58, 1.0, 0.16 + (1.0 - bolt_travel_t) * 0.18), 1.8)
		draw_circle(predicted_local, 4.5, Color(1.0, 0.86, 1.0, 0.2))
		draw_line(b_local - b_dir * 18.0, b_local, Color(0.72, 0.44, 0.96, 0.42 + bolt_travel_t * 0.14), 7.0)
		draw_line(b_local - b_dir * 12.0, b_local, Color(0.98, 0.86, 1.0, 0.54), 3.2)
		draw_circle(b_local, 8.5, Color(0.82, 0.52, 1.0, 0.42))
		draw_circle(b_local, 5.2, Color(0.96, 0.76, 1.0, 0.92))
		draw_circle(b_local, 2.5, Color(1.0, 0.98, 1.0, 0.98))
