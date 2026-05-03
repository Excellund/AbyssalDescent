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
	time_left = maxf(0.0, time_left - delta)
	tick_left = maxf(0.0, tick_left - delta)
	spawn_flash_left = maxf(0.0, spawn_flash_left - delta)
	tick_flash_left = maxf(0.0, tick_flash_left - delta)
	if current_radius < radius:
		current_radius = minf(radius, current_radius + (radius / maxf(0.001, expansion_duration)) * delta)
	if tick_left <= 0.0:
		tick_left = tick_interval
		tick_flash_left = 0.1
		if is_instance_valid(target) and global_position.distance_to(target.global_position) <= current_radius:
			if DAMAGEABLE.can_take_damage(target):
				DAMAGEABLE.apply_damage(target, tick_damage, {"source": "enemy_ability", "ability": "pyre_death_field"})
	if time_left <= 0.0:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var fade := clampf(time_left / maxf(0.001, duration), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.011)
	var spawn_boost := spawn_flash_left / 0.22
	var tick_boost := tick_flash_left / 0.1
	draw_circle(Vector2.ZERO, current_radius, Color(1.0, 0.36, 0.1, (0.1 + spawn_boost * 0.08) * fade))
	draw_circle(Vector2.ZERO, current_radius * 0.72, Color(1.0, 0.62, 0.18, (0.08 + pulse * 0.04) * fade))
	draw_arc(Vector2.ZERO, maxf(0.0, current_radius - 4.0 + pulse * 3.0), 0.0, TAU, 40, Color(1.0, 0.78, 0.36, (0.38 + tick_boost * 0.32) * fade), 2.4)
	for ring_i in range(3):
		var inner_radius := current_radius * (0.34 + float(ring_i) * 0.18)
		draw_arc(Vector2.ZERO, inner_radius, 0.0, TAU, 28, Color(0.98, 0.24, 0.08, (0.08 + pulse * 0.05) * fade), 1.2)