extends Node2D

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const VISUAL_MATH := preload("res://scripts/shared/visual_math.gd")

var target: Node2D
var radius: float = 64.0
var current_radius: float = 0.0
var duration: float = 3.6
var tick_interval: float = 0.50
var tick_damage: int = 6
var time_left: float = 0.0
var tick_left: float = 0.0
var spawn_flash_left: float = 0.18
var tick_flash_left: float = 0.0
var expansion_duration: float = 0.50


func initialize(target_node: Node2D, zone_radius: float, zone_duration: float, zone_tick_interval: float, zone_tick_damage: int) -> void:
	target = target_node
	radius = zone_radius
	current_radius = radius * 0.28
	duration = zone_duration
	tick_interval = zone_tick_interval
	tick_damage = zone_tick_damage
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
				DAMAGEABLE.apply_damage(target, tick_damage, {"source": "enemy_ability", "ability": "weaver_web"})
	if time_left <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	# Holds near full opacity for most of the zone's life, then fades sharply at the end
	var lifetime_ratio := 1.0 - clampf(time_left / maxf(0.001, duration), 0.0, 1.0)
	var fade := VISUAL_MATH.late_fade(lifetime_ratio, 0.75, 2.4)
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.009)
	var spawn_boost := spawn_flash_left / 0.18
	var tick_boost := tick_flash_left / 0.1
	draw_circle(Vector2.ZERO, current_radius, Color(0.42, 0.12, 0.62, (0.08 + spawn_boost * 0.06) * fade))
	draw_circle(Vector2.ZERO, current_radius * 0.68, Color(0.56, 0.2, 0.82, (0.06 + pulse * 0.04) * fade))
	draw_arc(Vector2.ZERO, maxf(0.0, current_radius - 4.0 + pulse * 3.0), 0.0, TAU, 36,
		Color(0.72, 0.42, 0.96, (0.32 + tick_boost * 0.28) * fade), 2.2)
	var strand_count := 5
	for strand_i in range(strand_count):
		var a := float(strand_i) * TAU / float(strand_count)
		var inner := Vector2(cos(a), sin(a)) * current_radius * 0.28
		var outer := Vector2(cos(a), sin(a)) * current_radius * 0.88
		draw_line(inner, outer, Color(0.64, 0.32, 0.88, (0.16 + pulse * 0.08) * fade), 1.2)
	for ring_i in range(3):
		var r := current_radius * (0.28 + float(ring_i) * 0.22)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(0.58, 0.28, 0.84, (0.07 + pulse * 0.04) * fade), 1.0)
