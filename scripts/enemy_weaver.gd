extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const WEB_ZONE_SCRIPT := preload("res://scripts/web_zone.gd")

# Weaver — aggressive rusher. Closes to short range, halts, then fires a radial
# burst of 6 web projectiles outward from its own feet. Zones land in a ring
# around the Weaver's position. Threat: escape OUTWARD past the ring radius
# before the windup completes. Pairs with melee pressure that stops you running.

@export var seek_speed: float = 98.0
@export var acceleration: float = 900.0
@export var deceleration: float = 1300.0
@export var preferred_range: float = 140.0
@export var range_tolerance: float = 28.0
@export var trigger_range: float = 192.0
@export var windup_time: float = 1.1
@export var burst_count: int = 8
@export var projectile_speed: float = 198.0
@export var projectile_max_range: float = 172.0
@export var projectile_hit_radius: float = 12.0
@export var web_zone_radius: float = 48.0
@export var web_zone_duration: float = 2.6
@export var web_zone_tick_interval: float = 0.50
@export var web_zone_tick_damage: int = 5
@export var attack_cooldown: float = 5.2

enum WeaverState { SEEK, WINDUP, FIRE, RECOVER }

var attack_cooldown_left: float = 0.0
var weaver_state: int = WeaverState.SEEK
var state_time_left: float = 0.0
var _burst_angle_offset: float = 0.0
# Active projectiles during radial burst: each { "pos": Vector2, "dir": Vector2, "dist": float }
var _projectiles: Array[Dictionary] = []
var _projectile_sync_was_active: bool = false
var _gait_phase: float = 0.0

# World-space foot positions for IK-style leg animation
var _foot_world_pos: Array[Vector2] = []
var _foot_swing_start: Array[Vector2] = []
var _foot_swing_t: Array[float] = []
var _abdomen_world_pos: Vector2 = Vector2.ZERO
var _feet_initialized: bool = false

# Leg layout: [angle_from_facing_deg, rest_radius, group]
# Group A (0): front-left, second-right, third-left, back-right
# Group B (1): front-right, second-left, third-right, back-left
const LEG_DEFS: Array = [
	[ 50.0, 21.0, 0],  # Front-left   (A)
	[-50.0, 21.0, 1],  # Front-right  (B)
	[ 85.0, 25.0, 1],  # Second-left  (B)
	[-85.0, 25.0, 0],  # Second-right (A)
	[118.0, 25.0, 0],  # Third-left   (A)
	[-118.0,25.0, 1],  # Third-right  (B)
	[148.0, 21.0, 1],  # Back-left    (B)
	[-148.0,21.0, 0],  # Back-right   (A)
]
const _STRIDE_TRIGGER := 9.0   # px from ideal before foot triggers a step
const _SWING_SPEED := 6.5      # how fast swing_t 0→1 advances per second
const _LEG_ARC_OUT := 4.0      # outward lateral arc at peak of swing
const _ABDOMEN_DIST := 13.0    # how far abdomen trails behind cephalothorax
const _ABDOMEN_LAG_SPEED := 7.0


func _get_custom_network_runtime_state() -> Dictionary:
	return {
		"weaver_state": weaver_state,
		"state_time_left": state_time_left,
		"attack_cooldown_left": attack_cooldown_left,
		"burst_angle_offset": _burst_angle_offset
	}


func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	if custom_state.is_empty():
		return
	weaver_state = int(custom_state.get("weaver_state", weaver_state))
	state_time_left = float(custom_state.get("state_time_left", state_time_left))
	attack_cooldown_left = float(custom_state.get("attack_cooldown_left", attack_cooldown_left))
	_burst_angle_offset = float(custom_state.get("burst_angle_offset", _burst_angle_offset))


func _ready() -> void:
	super()
	max_health = 72
	crowd_separation_radius = 54.0
	crowd_separation_strength = 88.0


func _process_behavior(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)
	_update_feet(delta)
	_process_projectiles(delta)
	match weaver_state:
		WeaverState.SEEK:
			_process_seek(delta)
		WeaverState.WINDUP:
			_process_windup(delta)
		WeaverState.FIRE:
			_process_fire(delta)
		WeaverState.RECOVER:
			_process_recover(delta)


func _process_seek(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	if dist > 1.0:
		visual_facing_direction = to_target.normalized()
	var desired := Vector2.ZERO
	if dist < preferred_range - range_tolerance:
		desired = -to_target.normalized() * seek_speed * slow_speed_mult
	elif dist > preferred_range + range_tolerance:
		desired = to_target.normalized() * seek_speed * slow_speed_mult
	velocity = velocity.move_toward(desired, (acceleration if desired != Vector2.ZERO else deceleration) * delta)
	move_and_slide()
	if attack_cooldown_left <= 0.0 and dist <= trigger_range:
		_enter_windup()


func _enter_windup() -> void:
	weaver_state = WeaverState.WINDUP
	state_time_left = windup_time
	# Random rotation so the burst pattern is never the same alignment
	_burst_angle_offset = randf() * TAU
	queue_redraw()


func _process_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length() > 1.0:
			visual_facing_direction = to_target.normalized()
	queue_redraw()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		_launch_burst()
		weaver_state = WeaverState.FIRE
		state_time_left = projectile_max_range / maxf(1.0, projectile_speed) + 0.3


func _launch_burst() -> void:
	_projectiles.clear()
	for i in range(burst_count):
		var angle := _burst_angle_offset + float(i) * TAU / float(burst_count)
		_projectiles.append({
			"pos": global_position,
			"dir": Vector2(cos(angle), sin(angle)),
			"dist": 0.0
		})


func _process_fire(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0 or _projectiles.is_empty():
		weaver_state = WeaverState.RECOVER
		state_time_left = 0.32


func _process_recover(delta: float) -> void:
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		weaver_state = WeaverState.SEEK
		attack_cooldown_left = attack_cooldown


func _process_projectiles(delta: float) -> void:
	if _projectiles.is_empty():
		return
	var i := _projectiles.size() - 1
	while i >= 0:
		var proj := _projectiles[i] as Dictionary
		var proj_pos := proj["pos"] as Vector2
		var proj_dir := proj["dir"] as Vector2
		var proj_dist := float(proj["dist"])
		var move_dist := projectile_speed * delta
		proj_pos += proj_dir * move_dist
		proj_dist += move_dist
		proj["pos"] = proj_pos
		proj["dist"] = proj_dist
		var hit := false
		if network_simulation_enabled and is_instance_valid(target):
			if proj_pos.distance_to(target.global_position) <= projectile_hit_radius:
				hit = true
		if proj_dist >= projectile_max_range or hit:
			if network_simulation_enabled:
				_spawn_web_zone(proj_pos)
			_projectiles.remove_at(i)
		i -= 1
	queue_redraw()


func _spawn_web_zone(world_pos: Vector2) -> void:
	if not is_instance_valid(get_parent()):
		return
	var zone := WEB_ZONE_SCRIPT.new()
	get_parent().add_child(zone)
	zone.global_position = world_pos
	zone.initialize(target, web_zone_radius, web_zone_duration, web_zone_tick_interval, web_zone_tick_damage)


func _init_feet() -> void:
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT
	_foot_world_pos.clear()
	_foot_swing_start.clear()
	_foot_swing_t.clear()
	for leg_def_variant in LEG_DEFS:
		var leg_def := leg_def_variant as Array
		var ideal := global_position + facing.rotated(deg_to_rad(float(leg_def[0]))) * float(leg_def[1])
		_foot_world_pos.append(ideal)
		_foot_swing_start.append(ideal)
		_foot_swing_t.append(0.0)
	_abdomen_world_pos = global_position - facing * _ABDOMEN_DIST
	_feet_initialized = true


func _update_feet(delta: float) -> void:
	if not _feet_initialized:
		if is_inside_tree():
			_init_feet()
		return
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT
	var speed := velocity.length()
	var moving := speed > 8.0
	if moving:
		_gait_phase = fmod(_gait_phase + delta * speed * 0.058, TAU)
	var phase_sin := sin(_gait_phase)
	for i in range(8):
		var leg_def := LEG_DEFS[i] as Array
		var ideal := global_position + facing.rotated(deg_to_rad(float(leg_def[0]))) * float(leg_def[1])
		var sw_t := _foot_swing_t[i]
		if sw_t > 0.0:
			# Advance swing toward planted
			sw_t = minf(1.0, sw_t + delta * _SWING_SPEED)
			_foot_swing_t[i] = sw_t
			# Arc outward in the leg's own direction at the midpoint
			var arc_dir := facing.rotated(deg_to_rad(float(leg_def[0])))
			var lateral := sin(sw_t * PI) * _LEG_ARC_OUT
			_foot_world_pos[i] = _foot_swing_start[i].lerp(ideal, sw_t) + arc_dir * lateral
			if sw_t >= 1.0:
				_foot_swing_t[i] = 0.0
				_foot_world_pos[i] = ideal
		else:
			# Check if this foot is far enough behind its ideal to trigger a step
			var group := int(leg_def[2])
			var dist := _foot_world_pos[i].distance_to(ideal)
			# Group A steps when phase_sin > 0, Group B when phase_sin < 0
			var group_active := (group == 0 and phase_sin > 0.10) or (group == 1 and phase_sin < -0.10)
			if moving and dist > _STRIDE_TRIGGER and group_active:
				_foot_swing_start[i] = _foot_world_pos[i]
				_foot_swing_t[i] = 0.01
	# Abdomen lags behind the front body
	var abdomen_target := global_position - facing * _ABDOMEN_DIST
	_abdomen_world_pos = _abdomen_world_pos.lerp(abdomen_target, minf(1.0, delta * _ABDOMEN_LAG_SPEED))
	queue_redraw()


func _is_in_priority_attack_state() -> bool:
	return weaver_state == WeaverState.WINDUP


func get_projectile_network_sync_state() -> Dictionary:
	if not network_simulation_enabled:
		return {}
	var active := not _projectiles.is_empty()
	if not active and not _projectile_sync_was_active:
		return {}
	var proj_payload: Array = []
	for proj in _projectiles:
		proj_payload.append({
			"pos": proj.get("pos", Vector2.ZERO),
			"dir": proj.get("dir", Vector2.ZERO)
		})
	_projectile_sync_was_active = active
	return {"active": active, "projectiles": proj_payload}


func apply_projectile_network_sync_state(sync_state: Dictionary) -> void:
	if network_simulation_enabled:
		return
	if sync_state.is_empty():
		return
	var active := bool(sync_state.get("active", false))
	if not active:
		if not _projectiles.is_empty():
			_projectiles.clear()
			queue_redraw()
		return
	var incoming: Array = sync_state.get("projectiles", []) as Array
	_projectiles.clear()
	for entry_variant in incoming:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		_projectiles.append({
			"pos": entry.get("pos", global_position) as Vector2,
			"dir": entry.get("dir", Vector2.ZERO) as Vector2,
			"dist": 0.0
		})
	queue_redraw()


func _process_network_visuals(delta: float) -> void:
	_update_feet(delta)
	if not _projectiles.is_empty():
		queue_redraw()


func _draw() -> void:
	var body_radius := 10.0
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT

	# Abdomen — larger rear body, lags behind the cephalothorax
	if _feet_initialized:
		var ab_local := to_local(_abdomen_world_pos)
		draw_circle(ab_local, 11.0,
			Color(COLOR_WEAVER_BODY.r * 0.80, COLOR_WEAVER_BODY.g * 0.80, COLOR_WEAVER_BODY.b * 0.80, 1.0))
		draw_circle(ab_local, 7.0, COLOR_WEAVER_CORE)
		draw_arc(ab_local, 9.5, 0.0, TAU, 24,
			Color(COLOR_WEAVER_BODY.r, COLOR_WEAVER_BODY.g, COLOR_WEAVER_BODY.b, 0.36), 1.4)

	# 8 legs with world-space foot tracking and IK-style 2-joint bends
	if _feet_initialized:
		for i in range(8):
			var foot_local := to_local(_foot_world_pos[i])
			var sw_t := _foot_swing_t[i]
			var foot_lift := sin(sw_t * PI) if sw_t > 0.0 else 0.0
			var leg_def_i := LEG_DEFS[i] as Array
			var leg_dir_local := facing.rotated(deg_to_rad(float(leg_def_i[0])))
			var root := leg_dir_local * body_radius
			# Knee: find midpoint, then offset outward using the perpendicular to the leg segment
			var mid := (root + foot_local) * 0.5
			var leg_vec := foot_local - root
			var perp: Vector2
			if leg_vec.length_squared() > 1.0:
				perp = Vector2(-leg_vec.y, leg_vec.x).normalized()
				if perp.dot(mid) < 0.0:
					perp = -perp
			else:
				perp = leg_dir_local.rotated(PI * 0.5)
			var knee := mid + perp * (5.0 + foot_lift * 3.5)
			var leg_alpha := lerpf(0.88, 0.42, foot_lift)
			var lc := Color(COLOR_WEAVER_BODY.r * 0.72, COLOR_WEAVER_BODY.g * 0.72, COLOR_WEAVER_BODY.b * 0.72, leg_alpha)
			draw_line(root, knee, lc, 2.5)
			draw_line(knee, foot_local, lc, 2.5)
			# Foot dot shrinks and dims at the peak of the swing arc
			var foot_r := lerpf(3.5, 1.0, foot_lift)
			draw_circle(foot_local, foot_r,
				Color(COLOR_WEAVER_CORE.r, COLOR_WEAVER_CORE.g, COLOR_WEAVER_CORE.b, lerpf(0.90, 0.18, foot_lift)))

	# Cephalothorax — front body, drawn over legs
	_draw_common_body(body_radius, COLOR_WEAVER_BODY, COLOR_WEAVER_CORE, facing)

	# Windup telegraph — radial lines grow to show where burst fires
	if weaver_state == WeaverState.WINDUP:
		var t := 1.0 - clampf(state_time_left / maxf(0.001, windup_time), 0.0, 1.0)
		for i in range(burst_count):
			var angle := _burst_angle_offset + float(i) * TAU / float(burst_count)
			var line_end := Vector2(cos(angle), sin(angle)) * (body_radius + 5.0 + t * 24.0)
			draw_line(Vector2.ZERO, line_end,
				Color(COLOR_WEAVER_CORE.r, COLOR_WEAVER_CORE.g, COLOR_WEAVER_CORE.b, 0.18 + t * 0.46), 1.5)
		draw_arc(Vector2.ZERO, body_radius + 4.5 + t * 6.0, 0.0, TAU, 24,
			Color(COLOR_WEAVER_CORE.r, COLOR_WEAVER_CORE.g, COLOR_WEAVER_CORE.b, 0.3 * t), 2.0)

	# Active burst projectiles
	for proj_variant in _projectiles:
		var proj := proj_variant as Dictionary
		var proj_local := to_local(proj["pos"] as Vector2)
		draw_circle(proj_local, projectile_hit_radius * 0.9,
			Color(COLOR_WEAVER_PROJECTILE.r, COLOR_WEAVER_PROJECTILE.g, COLOR_WEAVER_PROJECTILE.b, 0.22))
		draw_circle(proj_local, projectile_hit_radius * 0.5, COLOR_WEAVER_PROJECTILE)
