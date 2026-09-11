extends Node2D

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

var target: Node2D
var radius: float = 94.0
var current_radius: float = 0.0
var duration: float = 6.0
var tick_interval: float = 0.4
var tick_damage: int = 7
var time_left: float = 0.0
var tick_left: float = 0.0
var spawn_flash_left: float = 0.22
var tick_flash_left: float = 0.0
var expansion_duration: float = 0.75

func initialize(target_node: Node2D, field_radius: float, field_duration: float, field_tick_interval: float, field_tick_damage: int) -> void:
	target = target_node
	radius = field_radius
	current_radius = radius * 0.38
	duration = field_duration
	tick_interval = field_tick_interval
	tick_damage = field_tick_damage
	time_left = duration
	tick_left = tick_interval * 0.5

func _ready() -> void:
	add_to_group("enemy_lingering_effects")
	z_as_relative = false
	z_index = -10
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if is_queued_for_deletion() or not is_finite(delta) or delta <= 0.0:
		return
	var previous_life := time_left
	var previous_tick := tick_left
	var active_delta := minf(delta, maxf(0.0, previous_life))
	time_left = maxf(0.0, time_left - delta)
	tick_left = maxf(0.0, tick_left - active_delta)
	spawn_flash_left = maxf(0.0, spawn_flash_left - delta)
	tick_flash_left = maxf(0.0, tick_flash_left - delta)
	if current_radius < radius:
		current_radius = minf(radius, current_radius + (radius / maxf(0.001, expansion_duration)) * active_delta)
	if tick_left <= 0.0 and previous_life > maxf(0.0, previous_tick):
		tick_left = tick_interval
		tick_flash_left = 0.1
		if is_instance_valid(target) and global_position.distance_to(target.global_position) <= current_radius:
			if DAMAGEABLE.can_take_damage(target):
				DAMAGEABLE.apply_damage(target, tick_damage, {"source": "enemy_ability", "ability": "pyre_death_field"})
	if time_left <= 0.0:
		# The last active tick and the danger presentation end together. Hiding
		# now also removes the previous draw commands before deferred deletion.
		hide()
		queue_free()
		return
	queue_redraw()

func get_visual_state() -> Dictionary:
	var active := time_left > 0.0 and not is_queued_for_deletion()
	var remaining_ratio := clampf(time_left / maxf(0.001, duration), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.011)
	var spawn_boost := clampf(spawn_flash_left / 0.22, 0.0, 1.0)
	var tick_boost := clampf(tick_flash_left / 0.1, 0.0, 1.0)
	var expiry_warning := active and time_left <= minf(0.8, duration)
	# Brightness communicates danger, not age. Only the inset clock shrinks;
	# the complete damaging footprint remains readable until the hard expiry.
	return {
		"active": active,
		"fill_alpha": (0.14 + spawn_boost * 0.07) if active else 0.0,
		"inner_alpha": (0.08 + pulse * 0.03) if active else 0.0,
		"boundary_alpha": clampf(0.72 + tick_boost * 0.2 + (pulse * 0.08 if expiry_warning else 0.0), 0.0, 1.0) if active else 0.0,
		"remaining_ratio": remaining_ratio,
		"expiry_warning": expiry_warning,
		"pulse": pulse,
	}

func _draw() -> void:
	var visual := get_visual_state()
	if not bool(visual["active"]):
		return
	var pulse := float(visual["pulse"])
	draw_circle(Vector2.ZERO, current_radius, Color(1.0, 0.36, 0.1, float(visual["fill_alpha"])))
	draw_circle(Vector2.ZERO, current_radius * 0.72, Color(1.0, 0.62, 0.18, float(visual["inner_alpha"])))
	draw_arc(Vector2.ZERO, current_radius, 0.0, TAU, 64, Color(1.0, 0.63, 0.22, float(visual["boundary_alpha"])), 2.6, true)
	var clock_end := -PI * 0.5 + TAU * float(visual["remaining_ratio"])
	draw_arc(Vector2.ZERO, maxf(0.0, current_radius - 7.0), -PI * 0.5, clock_end, 64, Color(1.0, 0.84, 0.48, 0.9), 2.0, true)
	for ring_i in range(3):
		var inner_radius := current_radius * (0.34 + float(ring_i) * 0.18)
		draw_arc(Vector2.ZERO, inner_radius, 0.0, TAU, 28, Color(0.98, 0.24, 0.08, 0.08 + pulse * 0.05), 1.2)
