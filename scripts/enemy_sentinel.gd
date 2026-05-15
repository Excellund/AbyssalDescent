extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

@export var move_speed: float = 28.0
@export var acceleration: float = 420.0
@export var deceleration: float = 800.0
@export var stop_distance: float = 80.0
@export var rotation_speed_deg_per_sec: float = 54.0
@export var cone_angle_degrees: float = 80.0
@export var cone_range: float = 180.0
@export var cone_tick_damage: int = 5
@export var cone_tick_interval: float = 0.36

var cone_direction_angle: float = 0.0
var cone_tick_left: float = 0.0


func _get_custom_network_runtime_state() -> Dictionary:
	return {"cone_direction_angle": cone_direction_angle}


func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	if custom_state.is_empty():
		return
	cone_direction_angle = float(custom_state.get("cone_direction_angle", cone_direction_angle))


func _ready() -> void:
	super()
	max_health = 80
	crowd_separation_radius = 48.0
	crowd_separation_strength = 72.0
	cone_direction_angle = fmod(float(get_instance_id()) * 1.618033, TAU)


func _process_behavior(delta: float) -> void:
	cone_direction_angle = fmod(cone_direction_angle + deg_to_rad(rotation_speed_deg_per_sec) * delta, TAU)
	cone_tick_left = maxf(0.0, cone_tick_left - delta)
	var desired := Vector2.ZERO
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length() > stop_distance:
			desired = to_target.normalized() * move_speed * slow_speed_mult
	velocity = velocity.move_toward(desired, (acceleration if desired != Vector2.ZERO else deceleration) * delta)
	move_and_slide()
	visual_facing_direction = Vector2(cos(cone_direction_angle), sin(cone_direction_angle))
	if network_simulation_enabled and cone_tick_left <= 0.0:
		cone_tick_left = cone_tick_interval
		if is_instance_valid(target):
			_try_cone_damage()
	queue_redraw()


func _try_cone_damage() -> void:
	var to_player := target.global_position - global_position
	var dist := to_player.length()
	if dist > cone_range:
		return
	var angle_to_player := atan2(to_player.y, to_player.x)
	var angle_diff := absf(wrapf(angle_to_player - cone_direction_angle, -PI, PI))
	if angle_diff <= deg_to_rad(cone_angle_degrees * 0.5):
		DAMAGEABLE.apply_damage(target, cone_tick_damage, {"source": "enemy_ability", "ability": "sentinel_cone"})


func _is_in_priority_attack_state() -> bool:
	return false


func get_projectile_network_sync_state() -> Dictionary:
	return {}


func apply_projectile_network_sync_state(_sync_state: Dictionary) -> void:
	pass


func _process_network_visuals(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var body_radius := 14.0
	var facing := Vector2(cos(cone_direction_angle), sin(cone_direction_angle))
	# Diamond frame — axis-aligned rhombus signals a planted emplacement, drawn behind body
	var diamond_r := body_radius + 8.5
	var frame_color := Color(COLOR_SENTINEL_CORE.r, COLOR_SENTINEL_CORE.g, COLOR_SENTINEL_CORE.b, 0.44)
	var dp_r := Vector2(diamond_r, 0.0)
	var dp_t := Vector2(0.0, -diamond_r)
	var dp_l := Vector2(-diamond_r, 0.0)
	var dp_b := Vector2(0.0, diamond_r)
	draw_line(dp_r, dp_t, frame_color, 1.8)
	draw_line(dp_t, dp_l, frame_color, 1.8)
	draw_line(dp_l, dp_b, frame_color, 1.8)
	draw_line(dp_b, dp_r, frame_color, 1.8)
	_draw_common_body(body_radius, COLOR_SENTINEL_BODY, COLOR_SENTINEL_CORE, facing)
	var half_angle := deg_to_rad(cone_angle_degrees * 0.5)
	var start_angle := cone_direction_angle - half_angle
	var end_angle := start_angle + deg_to_rad(cone_angle_degrees)
	var arc_steps := 20
	var cone_polygon: PackedVector2Array = [Vector2.ZERO]
	for p in range(arc_steps + 1):
		var a := start_angle + float(p) * deg_to_rad(cone_angle_degrees) / float(arc_steps)
		cone_polygon.append(Vector2(cos(a), sin(a)) * cone_range)
	draw_colored_polygon(cone_polygon, COLOR_SENTINEL_CONE_FILL)
	draw_line(Vector2.ZERO, Vector2(cos(start_angle), sin(start_angle)) * cone_range,
		COLOR_SENTINEL_CONE_OUTLINE, 1.8)
	draw_line(Vector2.ZERO, Vector2(cos(end_angle), sin(end_angle)) * cone_range,
		COLOR_SENTINEL_CONE_OUTLINE, 1.8)
	draw_arc(Vector2.ZERO, cone_range, start_angle, end_angle, 20, COLOR_SENTINEL_CONE_OUTLINE, 1.8)
