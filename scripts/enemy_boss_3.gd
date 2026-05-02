extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

const STATE_STALK := 0
const STATE_WINDUP := 1
const STATE_ATTACK := 2
const STATE_RECOVER := 3

const ATTACK_SEVER := 0
const ATTACK_NULL_RING := 1
const ATTACK_ECHO_CROSS := 2

@export var boss_max_health: int = 2400
@export var move_speed: float = 174.0
@export var acceleration: float = 1040.0
@export var deceleration: float = 1460.0
@export var preferred_distance: float = 230.0
@export var action_cooldown: float = 0.34

@export var sever_windup: float = 0.78
@export var sever_speed: float = 760.0
@export var sever_duration: float = 0.2
@export var sever_width: float = 42.0
@export var sever_damage: int = 36
@export var sever_prediction_time: float = 0.52
@export var sever_prediction_speed_cap: float = 420.0

@export var null_ring_windup: float = 1.32
@export var null_ring_radius: float = 160.0
@export var null_ring_damage: int = 30
@export var null_ring_safe_radius: float = 96.0
@export var null_ring_pull_force: float = 680.0
@export var null_ring_prediction_speed_cap: float = 300.0
@export var null_ring_pull_delay: float = 0.56
@export var null_ring_pull_fx_duration: float = 0.26

@export var echo_cross_windup: float = 0.86
@export var echo_cross_length: float = 280.0
@export var echo_cross_width: float = 34.0
@export var echo_cross_damage: int = 34
@export var echo_cross_follow_delay: float = 0.26

@export var recover_time: float = 0.24
@export var arena_size: Vector2 = Vector2(1460.0, 1040.0)
@export var edge_soft_margin: float = 188.0
@export var edge_hard_margin: float = 118.0
@export var seam_duration: float = 4.0
@export var seam_tick_interval: float = 0.35
@export var seam_radius: float = 54.0
@export var seam_tick_damage: int = 8
@export var seam_spawn_limit_base: int = 4

var boss_state: int = STATE_STALK
var state_time_left: float = 0.0
var cooldown_left: float = 0.45
var active_attack: int = ATTACK_SEVER
var locked_direction: Vector2 = Vector2.RIGHT
var telegraph_alpha: float = 0.0
var _sever_hit_applied: bool = false
var _tracked_target_last_position: Vector2 = Vector2.ZERO
var _tracked_target_velocity: Vector2 = Vector2.ZERO
var _locked_null_ring_center: Vector2 = Vector2.ZERO
var _null_ring_pull_timer: float = 0.0
var _null_ring_pull_fx_time_left: float = 0.0
var _null_ring_pull_fx_center: Vector2 = Vector2.ZERO
var _echo_cross_angle: float = 0.0
var _echo_cross_smoothed_dir: Vector2 = Vector2.RIGHT
var _attack_cycle_step: int = 0
var _last_attack: int = -1
var _repeat_attack_streak: int = 0
var _edge_stall_time: float = 0.0
var attack_afterglow_time_left: float = 0.0
var attack_afterglow_duration: float = 0.52
var impact_burst_time_left: float = 0.0
var impact_burst_duration: float = 0.2
var last_attack_for_fx: int = ATTACK_SEVER
var seam_zones: Array[Dictionary] = []

func _ready() -> void:
	max_health = boss_max_health
	edge_escape_nudge_speed = 380.0
	super._ready()
	dread_resonance_visual_boss_emphasis = true
	for child in get_children():
		if child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if shape_node.shape is CircleShape2D:
				(shape_node.shape as CircleShape2D).radius = 40.0
				break
	configure_health_bar_visuals(Vector2(-78.0, -86.0), Vector2(156.0, 12.0))

func _get_transport_color() -> Color:
	return Color(0.34, 0.96, 0.78, 1.0)

func _process_behavior(delta: float) -> void:
	_process_seam_zones(delta)
	_update_target_tracking(delta)
	if not is_instance_valid(target):
		_clear_edge_escape_state()
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)
	match boss_state:
		STATE_STALK:
			_process_stalk_state(delta)
		STATE_WINDUP:
			_process_windup_state(delta)
		STATE_ATTACK:
			_process_attack_state(delta)
		STATE_RECOVER:
			_process_recover_state(delta)
	attack_afterglow_time_left = maxf(0.0, attack_afterglow_time_left - delta)
	impact_burst_time_left = maxf(0.0, impact_burst_time_left - delta)
	_null_ring_pull_fx_time_left = maxf(0.0, _null_ring_pull_fx_time_left - delta)
	_update_edge_escape_state(delta)
	queue_redraw()

func _update_target_tracking(delta: float) -> void:
	if not is_instance_valid(target) or delta <= 0.000001:
		_tracked_target_velocity = Vector2.ZERO
		return
	var current_target_position := target.global_position
	if _tracked_target_last_position == Vector2.ZERO:
		_tracked_target_last_position = current_target_position
		_tracked_target_velocity = Vector2.ZERO
		return
	var sampled_velocity := (current_target_position - _tracked_target_last_position) / delta
	# Smooth burst speed spikes from dash acceleration to prevent teleport-like prediction jumps.
	var blend := clampf(delta * 9.0, 0.0, 1.0)
	_tracked_target_velocity = _tracked_target_velocity.lerp(sampled_velocity, blend)
	_tracked_target_last_position = current_target_position

func _process_stalk_state(delta: float) -> void:
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var desired_velocity := Vector2.ZERO
	var inward_bias := _get_inward_edge_bias()
	var wall_pressure := inward_bias.length()
	var enrage_t := _get_enrage_ratio()
	var speed_mult := lerpf(1.0, 1.2, enrage_t)
	if wall_pressure > 0.0:
		desired_velocity += inward_bias * move_speed * (0.96 + wall_pressure * 0.58)
	if distance > preferred_distance + 18.0:
		desired_velocity += to_target.normalized() * move_speed * speed_mult
	elif distance < preferred_distance - 44.0:
		var retreat_dir := -to_target.normalized()
		if _can_move_in_direction(retreat_dir, 20.0):
			desired_velocity += retreat_dir * move_speed * 0.72 * speed_mult
		else:
			var lateral := Vector2(-retreat_dir.y, retreat_dir.x)
			desired_velocity += lateral * move_speed * 0.6 * (1.0 if int(get_instance_id()) % 2 == 0 else -1.0)
	if wall_pressure > 0.62 and desired_velocity.length_squared() > 0.000001:
		desired_velocity = desired_velocity.normalized() * move_speed * speed_mult
	desired_velocity *= slow_speed_mult
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()
	if to_target.length_squared() > 0.000001:
		locked_direction = to_target.normalized()
		visual_facing_direction = locked_direction
	var is_edge_stalled := wall_pressure > 0.56 and velocity.length() < move_speed * 0.18
	_edge_stall_time = _edge_stall_time + delta if is_edge_stalled else 0.0
	if wall_pressure >= 0.8:
		cooldown_left = minf(cooldown_left, 0.06)
	if cooldown_left <= 0.0 and (wall_pressure < 0.66 or _edge_stall_time >= 0.24):
		_start_next_attack(distance, wall_pressure)
	_maybe_trigger_edge_escape(wall_pressure, inward_bias, to_target, _edge_stall_time)

func _start_next_attack(distance_to_target: float, wall_pressure: float) -> void:
	var options: Array[int] = []
	if distance_to_target > 250.0 or wall_pressure > 0.76:
		options.append(ATTACK_SEVER)
	if distance_to_target < 220.0:
		options.append(ATTACK_NULL_RING)
	options.append(ATTACK_ECHO_CROSS)
	active_attack = options[_attack_cycle_step % options.size()]
	if active_attack == _last_attack:
		_repeat_attack_streak += 1
		if _repeat_attack_streak >= 2:
			active_attack = ATTACK_NULL_RING if active_attack != ATTACK_NULL_RING else ATTACK_ECHO_CROSS
			_repeat_attack_streak = 0
	else:
		_repeat_attack_streak = 0
	_last_attack = active_attack
	_attack_cycle_step += 1
	var to_target := target.global_position - global_position
	if to_target.length_squared() > 0.000001:
		locked_direction = to_target.normalized()
	visual_facing_direction = locked_direction
	boss_state = STATE_WINDUP
	state_time_left = _get_windup_time(active_attack)
	telegraph_alpha = 0.0
	_sever_hit_applied = false
	velocity = Vector2.ZERO
	if active_attack == ATTACK_NULL_RING:
		_locked_null_ring_center = _predict_target_position(null_ring_windup * 0.42, null_ring_prediction_speed_cap)
	elif active_attack == ATTACK_ECHO_CROSS:
		_echo_cross_smoothed_dir = locked_direction
		_echo_cross_angle = locked_direction.angle() + PI * 0.5

func _process_windup_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	if active_attack == ATTACK_SEVER:
		var to_predicted := _predict_target_position(sever_prediction_time, sever_prediction_speed_cap) - global_position
		if to_predicted.length_squared() > 0.000001:
			locked_direction = to_predicted.normalized()
			visual_facing_direction = locked_direction
	elif active_attack == ATTACK_NULL_RING:
		_locked_null_ring_center = _predict_target_position(null_ring_windup * 0.4, null_ring_prediction_speed_cap)
	elif active_attack == ATTACK_ECHO_CROSS and is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			var desired_dir := to_target.normalized()
			var delay := maxf(0.001, echo_cross_follow_delay)
			var follow_blend := clampf(delta / delay, 0.0, 1.0)
			_echo_cross_smoothed_dir = _echo_cross_smoothed_dir.slerp(desired_dir, follow_blend)
			if _echo_cross_smoothed_dir.length_squared() > 0.000001:
				locked_direction = _echo_cross_smoothed_dir.normalized()
			_echo_cross_angle = locked_direction.angle() + PI * 0.5
	state_time_left = maxf(0.0, state_time_left - delta)
	var windup := _get_windup_time(active_attack)
	telegraph_alpha = 1.0 if windup <= 0.0 else clampf(1.0 - (state_time_left / windup), 0.0, 1.0)
	if state_time_left <= 0.0:
		_enter_attack_state()

func _enter_attack_state() -> void:
	boss_state = STATE_ATTACK
	attack_anim_time_left = attack_anim_duration
	last_attack_for_fx = active_attack
	attack_afterglow_time_left = attack_afterglow_duration
	impact_burst_time_left = impact_burst_duration
	var enrage_t := _get_enrage_ratio()
	match active_attack:
		ATTACK_SEVER:
			state_time_left = sever_duration * lerpf(1.0, 0.84, enrage_t)
			velocity = locked_direction * sever_speed * lerpf(1.0, 1.16, enrage_t)
		ATTACK_NULL_RING:
			state_time_left = null_ring_pull_delay + 0.12
			velocity = Vector2.ZERO
			_null_ring_pull_timer = null_ring_pull_delay
		ATTACK_ECHO_CROSS:
			state_time_left = 0.08
			velocity = Vector2.ZERO
			_apply_echo_cross_hit()

func _process_attack_state(delta: float) -> void:
	match active_attack:
		ATTACK_NULL_RING:
			if _null_ring_pull_timer > 0.0:
				_null_ring_pull_timer -= delta
				if _null_ring_pull_timer <= 0.0:
					_apply_null_ring_hit()
					_null_ring_pull_timer = -1.0
		ATTACK_SEVER:
			velocity = locked_direction * sever_speed * lerpf(1.0, 1.16, _get_enrage_ratio())
			move_and_slide()
			_apply_sever_hit()
		_:
			velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
			move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		boss_state = STATE_RECOVER
		state_time_left = recover_time * lerpf(1.0, 0.7, _get_enrage_ratio())

func _process_recover_state(delta: float) -> void:
	var inward_bias := _get_inward_edge_bias()
	velocity = velocity.move_toward(inward_bias * move_speed * 0.54, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		boss_state = STATE_STALK
		cooldown_left = action_cooldown * lerpf(1.0, 0.58, _get_enrage_ratio())

func _apply_sever_hit() -> void:
	if _sever_hit_applied or not is_instance_valid(target) or not DAMAGEABLE.can_take_damage(target):
		return
	var seg_start := global_position - locked_direction * 40.0
	var seg_end := global_position + locked_direction * 44.0
	if _distance_point_to_segment(target.global_position, seg_start, seg_end) <= sever_width:
		if DAMAGEABLE.apply_damage(target, sever_damage, {"source": "enemy_ability", "ability": "lacuna_sever"}):
			_sever_hit_applied = true
			_spawn_seam(target.global_position)

func _apply_null_ring_hit() -> void:
	if not is_instance_valid(target) or not DAMAGEABLE.can_take_damage(target):
		return
	var distance := target.global_position.distance_to(_locked_null_ring_center)
	if distance > null_ring_safe_radius and distance <= null_ring_radius:
		DAMAGEABLE.apply_damage(target, null_ring_damage, {"source": "enemy_ability", "ability": "lacuna_null_ring"})
	var to_center := _locked_null_ring_center - target.global_position
	if distance > 0.000001 and distance <= null_ring_radius:
		target.velocity += to_center.normalized() * null_ring_pull_force
	_null_ring_pull_fx_center = _locked_null_ring_center
	_null_ring_pull_fx_time_left = maxf(0.01, null_ring_pull_fx_duration)
	_spawn_seam(_locked_null_ring_center)

func _apply_echo_cross_hit() -> void:
	if is_instance_valid(target) and DAMAGEABLE.can_take_damage(target):
		var primary_dir := Vector2.RIGHT.rotated(_echo_cross_angle)
		var secondary_dir := primary_dir.orthogonal()
		var half_len := echo_cross_length * 0.5
		var hit_primary := _distance_point_to_segment(target.global_position, global_position - primary_dir * half_len, global_position + primary_dir * half_len) <= echo_cross_width
		var hit_secondary := _distance_point_to_segment(target.global_position, global_position - secondary_dir * half_len, global_position + secondary_dir * half_len) <= echo_cross_width
		if hit_primary or hit_secondary:
			DAMAGEABLE.apply_damage(target, echo_cross_damage, {"source": "enemy_ability", "ability": "lacuna_echo_cross"})
	var primary_dir := Vector2.RIGHT.rotated(_echo_cross_angle)
	var secondary_dir := primary_dir.orthogonal()
	var arm_reach := echo_cross_length * 0.5 - seam_radius * 0.5
	_spawn_seam(global_position + primary_dir * arm_reach)
	_spawn_seam(global_position - primary_dir * arm_reach)
	_spawn_seam(global_position + secondary_dir * arm_reach)
	_spawn_seam(global_position - secondary_dir * arm_reach)

func _spawn_seam(position: Vector2, duration_mult: float = 1.0, tick_interval_mult: float = 1.0) -> void:
	var clamped := _clamp_to_arena(position, seam_radius + 18.0)
	var seam_time := seam_duration * maxf(0.1, duration_mult)
	var seam_tick := seam_tick_interval * maxf(0.1, tick_interval_mult)
	seam_zones.append({
		"pos": clamped,
		"time_left": seam_time,
		"tick_left": seam_tick * 0.5,
		"tick_interval": seam_tick,
		"pulse": 0.0
	})
	var max_seams := seam_spawn_limit_base
	if _get_enrage_ratio() >= 0.52:
		max_seams += 1
	if _get_enrage_ratio() >= 0.84:
		max_seams += 1
	while seam_zones.size() > max_seams:
		seam_zones.remove_at(0)

func _process_seam_zones(delta: float) -> void:
	if seam_zones.is_empty():
		return
	var expired: Array[int] = []
	for i in range(seam_zones.size()):
		var seam := seam_zones[i] as Dictionary
		seam["time_left"] = float(seam.get("time_left", 0.0)) - delta
		seam["tick_left"] = float(seam.get("tick_left", 0.0)) - delta
		seam["pulse"] = maxf(0.0, float(seam.get("pulse", 0.0)) - delta)
		if float(seam.get("tick_left", 0.0)) <= 0.0:
			seam["tick_left"] = float(seam.get("tick_interval", seam_tick_interval))
			seam["pulse"] = 0.12
			if is_instance_valid(target):
				var seam_pos := seam.get("pos", Vector2.ZERO) as Vector2
				if seam_pos.distance_to(target.global_position) <= seam_radius:
					if DAMAGEABLE.can_take_damage(target):
						DAMAGEABLE.apply_damage(target, seam_tick_damage, {"source": "enemy_ability", "ability": "lacuna_seam_tick"})
		if float(seam.get("time_left", 0.0)) <= 0.0:
			expired.append(i)
	for idx in range(expired.size() - 1, -1, -1):
		seam_zones.remove_at(expired[idx])

func _predict_target_position(scale: float, speed_cap: float = 0.0) -> Vector2:
	if not is_instance_valid(target):
		return global_position
	var predicted_velocity := _tracked_target_velocity
	if speed_cap > 0.0 and predicted_velocity.length() > speed_cap:
		predicted_velocity = predicted_velocity.normalized() * speed_cap
	return _clamp_to_arena(target.global_position + predicted_velocity * scale, 36.0)

func _clamp_to_arena(position: Vector2, margin: float) -> Vector2:
	var half := arena_size * 0.5 - Vector2.ONE * margin
	return Vector2(clampf(position.x, -half.x, half.x), clampf(position.y, -half.y, half.y))

func _can_move_in_direction(direction: Vector2, probe_distance: float) -> bool:
	if direction.length_squared() <= 0.000001:
		return true
	return not test_move(global_transform, direction.normalized() * probe_distance)

func _distance_point_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var length_sq := segment.length_squared()
	if length_sq <= 0.000001:
		return point.distance_to(segment_start)
	var t := clampf((point - segment_start).dot(segment) / length_sq, 0.0, 1.0)
	return point.distance_to(segment_start + segment * t)

func _get_inward_edge_bias() -> Vector2:
	var half := arena_size * 0.5
	if half.x <= 0.0 or half.y <= 0.0:
		return Vector2.ZERO
	var x_to_edge := half.x - absf(global_position.x)
	var y_to_edge := half.y - absf(global_position.y)
	var x_pressure := clampf((edge_soft_margin - x_to_edge) / maxf(1.0, edge_soft_margin - edge_hard_margin), 0.0, 1.0)
	var y_pressure := clampf((edge_soft_margin - y_to_edge) / maxf(1.0, edge_soft_margin - edge_hard_margin), 0.0, 1.0)
	var bias := Vector2.ZERO
	if x_pressure > 0.0:
		bias.x = -signf(global_position.x) * x_pressure
	if y_pressure > 0.0:
		bias.y = -signf(global_position.y) * y_pressure
	if bias.length_squared() <= 0.000001:
		return Vector2.ZERO
	return bias.normalized() * maxf(x_pressure, y_pressure)

func _get_windup_time(attack_id: int) -> float:
	var enrage_t := _get_enrage_ratio()
	match attack_id:
		ATTACK_SEVER:
			return sever_windup * lerpf(1.0, 0.78, enrage_t)
		ATTACK_NULL_RING:
			return null_ring_windup * lerpf(1.0, 0.82, enrage_t)
		ATTACK_ECHO_CROSS:
			return echo_cross_windup * lerpf(1.0, 0.8, enrage_t)
		_:
			return 0.8

func _get_enrage_ratio() -> float:
	var health_ratio := float(_get_current_health()) / maxf(1.0, float(max_health))
	if health_ratio >= 0.72:
		return 0.0
	if health_ratio <= 0.18:
		return 1.0
	return clampf((0.72 - health_ratio) / 0.54, 0.0, 1.0)

func _draw() -> void:
	var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.RIGHT
	if is_spawn_transporting():
		_draw_spawn_transport_fx(40.0, facing)
		return
	_draw_seam_zones()
	var pulse := _get_attack_pulse()
	var body_radius := 46.0 + pulse * 1.2
	var body_color := Color(0.1, 0.6, 0.44, 1.0)
	var core_color := Color(0.74, 1.0, 0.9, 0.94)
	var threat_t := telegraph_alpha if boss_state == STATE_WINDUP else (1.0 if (boss_state == STATE_ATTACK and active_attack == ATTACK_NULL_RING and _null_ring_pull_timer > 0.0) else 0.0)
	var threat_pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.018)
	var enrage_t := _get_enrage_ratio()
	if boss_state == STATE_WINDUP:
		body_color = body_color.lerp(Color(0.24, 0.88, 0.68, 1.0), 0.55)
		core_color = core_color.lerp(Color(0.94, 1.0, 0.98, 1.0), 0.62)
	if boss_state == STATE_ATTACK:
		body_color = body_color.lerp(Color(0.22, 0.98, 0.74, 1.0), 0.72)
		core_color = core_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.78)
	if enrage_t > 0.0:
		body_color = body_color.lerp(Color(0.06, 0.86, 0.66, 1.0), enrage_t * 0.4)
		core_color = core_color.lerp(Color(0.92, 1.0, 0.98, 1.0), enrage_t * 0.5)
	if boss_state == STATE_WINDUP:
		var halo_radius := body_radius + 18.0 + threat_t * 10.0
		draw_circle(Vector2.ZERO, halo_radius, Color(0.24, 1.0, 0.82, 0.08 + threat_t * 0.1))
		draw_arc(Vector2.ZERO, halo_radius + 4.0, 0.0, TAU, 52, Color(0.84, 1.0, 0.94, 0.26 + threat_t * 0.24 + threat_pulse * 0.08), 2.6)
	_draw_lacuna_body(body_radius, body_color, core_color, facing, pulse, threat_t, enrage_t)
	_draw_slow_indicator(body_radius)
	_draw_attack_afterglow(facing)
	_draw_null_ring_pull_fx()
	_draw_attack_impact_burst(facing)
	if boss_state == STATE_WINDUP or (boss_state == STATE_ATTACK and active_attack == ATTACK_NULL_RING and _null_ring_pull_timer > 0.0):
		_draw_attack_telegraph()
		_draw_role_state_icon(facing, body_radius)

func _draw_lacuna_body(body_radius: float, body_color: Color, core_color: Color, facing: Vector2, pulse: float, threat_t: float, enrage_t: float) -> void:
	var side := Vector2(-facing.y, facing.x)
	var time_s := float(Time.get_ticks_msec()) * 0.001
	var spin := time_s * (0.58 + enrage_t * 0.24)
	var gate_spin := -time_s * (0.32 + enrage_t * 0.18)
	var aura_color := Color(0.14, 0.84, 0.68, 0.14 + threat_t * 0.1 + enrage_t * 0.06)
	var shell_dark := body_color.lerp(Color(0.03, 0.16, 0.13, 1.0), 0.34)
	var shell_mid := body_color.lerp(Color(0.08, 0.36, 0.28, 1.0), 0.24)
	var shell_light := core_color.lerp(Color(0.72, 0.98, 0.9, 1.0), 0.24 + threat_t * 0.12)
	var rune_color := Color(0.86, 1.0, 0.95, 0.26 + threat_t * 0.18)

	draw_circle(Vector2.ZERO, body_radius + 13.0 + pulse * 1.1, aura_color)
	draw_circle(Vector2.ZERO, body_radius + 7.0 + pulse * 0.8, Color(0.2, 0.92, 0.74, 0.08 + threat_t * 0.06))

	var gate_radius := body_radius + 23.0
	for gate_i in range(4):
		var seg_start := gate_spin + float(gate_i) * TAU / 4.0 + 0.14
		var seg_len := 0.86
		draw_arc(Vector2.ZERO, gate_radius, seg_start, seg_start + seg_len, 18, Color(0.64, 1.0, 0.88, 0.34 + enrage_t * 0.14), 2.4)
		var tick_a := seg_start + seg_len * 0.5
		var tick_dir := Vector2.RIGHT.rotated(tick_a)
		draw_line(tick_dir * (gate_radius - 5.0), tick_dir * (gate_radius + 5.0), Color(0.92, 1.0, 0.97, 0.28 + threat_t * 0.16), 1.2)
	for brace_i in range(3):
		var brace_a := spin + float(brace_i) * TAU / 3.0
		var brace_dir := Vector2.RIGHT.rotated(brace_a)
		draw_line(brace_dir * (body_radius + 6.0), brace_dir * (gate_radius - 3.0), Color(0.46, 0.94, 0.8, 0.2 + enrage_t * 0.1), 1.4)

	var monolith_tip := facing * (body_radius + 11.0 + pulse * 1.6)
	var monolith_shoulder_left := facing * (body_radius * 0.34) + side * (body_radius * 0.78)
	var monolith_waist_left := -facing * (body_radius * 0.26) + side * (body_radius * 0.62)
	var monolith_base := -facing * (body_radius * 0.96)
	var monolith_waist_right := -facing * (body_radius * 0.26) - side * (body_radius * 0.62)
	var monolith_shoulder_right := facing * (body_radius * 0.34) - side * (body_radius * 0.78)
	var monolith := PackedVector2Array([
		monolith_tip,
		monolith_shoulder_left,
		monolith_waist_left,
		monolith_base,
		monolith_waist_right,
		monolith_shoulder_right
	])
	draw_colored_polygon(monolith, shell_dark)

	var inner_tip := facing * (body_radius + 3.0 + pulse * 0.8)
	var inner_left := facing * (body_radius * 0.2) + side * (body_radius * 0.56)
	var inner_base_left := -facing * (body_radius * 0.22) + side * (body_radius * 0.42)
	var inner_base := -facing * (body_radius * 0.74)
	var inner_base_right := -facing * (body_radius * 0.22) - side * (body_radius * 0.42)
	var inner_right := facing * (body_radius * 0.2) - side * (body_radius * 0.56)
	var inner_core := PackedVector2Array([
		inner_tip,
		inner_left,
		inner_base_left,
		inner_base,
		inner_base_right,
		inner_right
	])
	draw_colored_polygon(inner_core, shell_mid)

	var sanctum_center := -facing * (body_radius * 0.08)
	draw_circle(sanctum_center, body_radius * 0.38, Color(shell_light.r, shell_light.g, shell_light.b, 0.2 + threat_t * 0.08))
	draw_circle(sanctum_center, body_radius * 0.23, Color(0.9, 1.0, 0.97, 0.3 + threat_t * 0.12))

	var tri_r := body_radius * 0.3
	for tri_i in range(3):
		var a0 := spin * 0.74 + float(tri_i) * TAU / 3.0
		var a1 := a0 + TAU / 3.0
		var p0 := sanctum_center + Vector2.RIGHT.rotated(a0) * tri_r
		var p1 := sanctum_center + Vector2.RIGHT.rotated(a1) * tri_r
		draw_line(p0, p1, rune_color, 1.4)
		var midpoint := (p0 + p1) * 0.5
		draw_circle(midpoint, 1.3, Color(0.94, 1.0, 0.98, 0.3 + threat_t * 0.16))

	var pylon_dist := body_radius + 5.0
	for pylon_i in range(4):
		var pylon_angle := spin * 1.12 + float(pylon_i) * TAU / 4.0
		var pylon_dir := Vector2.RIGHT.rotated(pylon_angle)
		var pylon_side := Vector2(-pylon_dir.y, pylon_dir.x)
		var pylon_center := pylon_dir * pylon_dist
		var pylon_tip := pylon_center + pylon_dir * (8.0 + enrage_t * 3.0)
		var pylon_back := pylon_center - pylon_dir * 6.0
		var pylon_poly := PackedVector2Array([
			pylon_tip,
			pylon_back + pylon_side * 4.2,
			pylon_back - pylon_side * 4.2
		])
		draw_colored_polygon(pylon_poly, Color(0.78, 1.0, 0.92, 0.3 + threat_t * 0.12))
		draw_line(pylon_tip, pylon_back, Color(0.94, 1.0, 0.98, 0.26 + enrage_t * 0.12), 1.0)

	var mantle_left := PackedVector2Array([
		facing * (body_radius * 0.06) + side * (body_radius * 0.74),
		-facing * (body_radius * 0.24) + side * (body_radius + 10.0),
		-facing * (body_radius * 0.72) + side * (body_radius * 0.54)
	])
	var mantle_right := PackedVector2Array([
		facing * (body_radius * 0.06) - side * (body_radius * 0.74),
		-facing * (body_radius * 0.24) - side * (body_radius + 10.0),
		-facing * (body_radius * 0.72) - side * (body_radius * 0.54)
	])
	draw_colored_polygon(mantle_left, Color(shell_mid.r, shell_mid.g, shell_mid.b, 0.82))
	draw_colored_polygon(mantle_right, Color(shell_mid.r, shell_mid.g, shell_mid.b, 0.82))
	draw_line(mantle_left[0], mantle_left[1], Color(0.88, 1.0, 0.95, 0.2 + threat_t * 0.1), 1.3)
	draw_line(mantle_right[0], mantle_right[1], Color(0.88, 1.0, 0.95, 0.2 + threat_t * 0.1), 1.3)

	_draw_mutator_overlay(body_radius)
	_draw_dread_resonance_overlay(body_radius)
	_draw_damage_blocked_indicator(body_radius)

func _draw_seam_zones() -> void:
	for seam_variant in seam_zones:
		var seam := seam_variant as Dictionary
		var seam_pos := seam.get("pos", Vector2.ZERO) as Vector2
		var local_pos := seam_pos - global_position
		var time_left := float(seam.get("time_left", 0.0))
		var fade := clampf(time_left / maxf(0.001, seam_duration), 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.016 + seam_pos.x * 0.02)
		var tick_pulse := clampf(float(seam.get("pulse", 0.0)) / 0.12, 0.0, 1.0)
		draw_circle(local_pos, seam_radius, Color(0.14, 0.94, 0.72, (0.08 + tick_pulse * 0.06) * fade))
		draw_arc(local_pos, seam_radius - 2.0 + pulse * 2.0, 0.0, TAU, 36, Color(0.76, 1.0, 0.92, (0.34 + tick_pulse * 0.4) * fade), 2.2)
		draw_arc(local_pos, seam_radius * 0.62, 0.0, TAU, 26, Color(0.2, 0.88, 0.74, 0.2 * fade), 1.4)
		draw_circle(local_pos, seam_radius * 0.22, Color(0.84, 1.0, 0.95, (0.18 + tick_pulse * 0.46) * fade))
		var seam_axis := Vector2.RIGHT.rotated(seam_pos.angle() + pulse * 0.45)
		var seam_cross := seam_axis.orthogonal()
		draw_line(local_pos - seam_axis * (seam_radius * 0.72), local_pos - seam_axis * (seam_radius * 0.16), Color(0.94, 1.0, 0.98, (0.22 + tick_pulse * 0.34) * fade), 1.8)
		draw_line(local_pos + seam_axis * (seam_radius * 0.16), local_pos + seam_axis * (seam_radius * 0.72), Color(0.94, 1.0, 0.98, (0.22 + tick_pulse * 0.34) * fade), 1.8)
		draw_line(local_pos - seam_cross * (seam_radius * 0.3), local_pos + seam_cross * (seam_radius * 0.3), Color(0.7, 1.0, 0.88, (0.12 + tick_pulse * 0.22) * fade), 1.2)
		if tick_pulse > 0.0:
			for spoke_i in range(6):
				var spoke_angle := float(spoke_i) * TAU / 6.0 + pulse * 0.5
				var spoke_dir := Vector2.RIGHT.rotated(spoke_angle)
				var spoke_start := local_pos + spoke_dir * (seam_radius * 0.38)
				var spoke_end := local_pos + spoke_dir * (seam_radius + 6.0 + tick_pulse * 8.0)
				draw_line(spoke_start, spoke_end, Color(0.92, 1.0, 0.98, (0.34 + tick_pulse * 0.4) * fade), 1.8)

func _draw_role_state_icon(facing: Vector2, body_radius: float) -> void:
	var icon_alpha := 0.36 + telegraph_alpha * 0.58
	match active_attack:
		ATTACK_SEVER:
			var tip := facing * (body_radius + 18.0)
			var base := facing * (body_radius + 4.0)
			var side := Vector2(-facing.y, facing.x)
			draw_colored_polygon(PackedVector2Array([tip, base + side * 5.6, base - side * 5.6]), Color(0.9, 1.0, 0.96, icon_alpha))
		ATTACK_NULL_RING:
			draw_arc(Vector2.ZERO, body_radius + 12.0, 0.0, TAU, 40, Color(0.88, 1.0, 0.96, icon_alpha), 2.4)
			draw_line(Vector2(-6.0, 0.0), Vector2(6.0, 0.0), Color(0.9, 1.0, 0.96, icon_alpha * 0.9), 2.0)
			draw_line(Vector2(0.0, -6.0), Vector2(0.0, 6.0), Color(0.9, 1.0, 0.96, icon_alpha * 0.9), 2.0)
		ATTACK_ECHO_CROSS:
			var d0 := Vector2.RIGHT.rotated(_echo_cross_angle) * (body_radius + 12.0)
			var d1 := d0.orthogonal()
			draw_line(-d0, d0, Color(0.9, 1.0, 0.96, icon_alpha), 2.2)
			draw_line(-d1, d1, Color(0.9, 1.0, 0.96, icon_alpha), 2.2)

func _draw_attack_telegraph() -> void:
	var alpha := 0.2 + telegraph_alpha * 0.72
	match active_attack:
		ATTACK_SEVER:
			var start := locked_direction * 28.0
			var end := start + locked_direction * (sever_speed * sever_duration * 0.7)
			draw_line(start, end, Color(0.2, 1.0, 0.82, alpha * 0.6), sever_width * 2.0)
			draw_line(start, end, Color(0.92, 1.0, 0.98, alpha), 3.6)
			var slash_side := Vector2(-locked_direction.y, locked_direction.x)
			draw_line(start + slash_side * (sever_width * 0.7), end + slash_side * (sever_width * 0.22), Color(0.84, 1.0, 0.95, alpha * 0.36), 1.6)
			draw_line(start - slash_side * (sever_width * 0.7), end - slash_side * (sever_width * 0.22), Color(0.84, 1.0, 0.95, alpha * 0.24), 1.2)
		ATTACK_NULL_RING:
			var local_center := _locked_null_ring_center - global_position
			var danger_mid := (null_ring_safe_radius + null_ring_radius) * 0.5
			draw_circle(local_center, null_ring_radius, Color(0.16, 0.96, 0.74, alpha * 0.14))
			draw_arc(local_center, null_ring_radius, 0.0, TAU, 60, Color(0.76, 1.0, 0.92, alpha), 3.2)
			draw_arc(local_center, danger_mid, 0.0, TAU, 54, Color(0.84, 1.0, 0.96, alpha * 0.6), 8.0)
			draw_circle(local_center, null_ring_safe_radius, Color(0.14, 0.94, 0.72, alpha * 0.08))
			draw_arc(local_center, null_ring_safe_radius, 0.0, TAU, 36, Color(0.76, 1.0, 0.92, alpha * 0.34), 2.2)
			draw_arc(local_center, null_ring_safe_radius * 0.62, 0.0, TAU, 26, Color(0.2, 0.88, 0.74, alpha * 0.2), 1.4)
			draw_circle(local_center, null_ring_safe_radius * 0.22, Color(0.84, 1.0, 0.95, alpha * 0.18))
			draw_line(local_center + Vector2(-null_ring_safe_radius * 0.4, 0.0), local_center + Vector2(null_ring_safe_radius * 0.4, 0.0), Color(0.84, 1.0, 0.95, alpha * 0.46), 1.6)
			draw_line(local_center + Vector2(0.0, -null_ring_safe_radius * 0.4), local_center + Vector2(0.0, null_ring_safe_radius * 0.4), Color(0.84, 1.0, 0.95, alpha * 0.46), 1.6)
			for spoke_i in range(6):
				var spoke_angle := telegraph_alpha * 0.4 + float(spoke_i) * TAU / 6.0
				var spoke_dir := Vector2.RIGHT.rotated(spoke_angle)
				var spoke_start := local_center + spoke_dir * (null_ring_safe_radius + 10.0)
				var spoke_end := local_center + spoke_dir * (null_ring_radius - 8.0)
				draw_line(spoke_start, spoke_end, Color(0.92, 1.0, 0.98, alpha * 0.22), 1.2)
			for seg_i in range(3):
				var seg_start := telegraph_alpha * 0.8 + float(seg_i) * TAU / 3.0
				draw_arc(local_center, null_ring_radius + 10.0, seg_start, seg_start + 0.52, 12, Color(0.82, 1.0, 0.94, alpha * 0.44), 1.8)
		ATTACK_ECHO_CROSS:
			var primary_dir := Vector2.RIGHT.rotated(_echo_cross_angle)
			var secondary_dir := primary_dir.orthogonal()
			var half_len := echo_cross_length * 0.5
			draw_line(-primary_dir * half_len, primary_dir * half_len, Color(0.18, 1.0, 0.8, alpha * 0.7), echo_cross_width * 1.5)
			draw_line(-secondary_dir * half_len, secondary_dir * half_len, Color(0.18, 1.0, 0.8, alpha * 0.7), echo_cross_width * 1.5)
			draw_line(-primary_dir * half_len, primary_dir * half_len, Color(0.92, 1.0, 0.98, alpha), 2.4)
			draw_line(-secondary_dir * half_len, secondary_dir * half_len, Color(0.92, 1.0, 0.98, alpha), 2.4)
			var echo_offset := (0.1 + telegraph_alpha * 0.18) * echo_cross_width
			draw_line(-primary_dir * half_len + secondary_dir * echo_offset, primary_dir * half_len + secondary_dir * echo_offset, Color(0.86, 1.0, 0.96, alpha * 0.26), 1.6)
			draw_line(-secondary_dir * half_len - primary_dir * echo_offset, secondary_dir * half_len - primary_dir * echo_offset, Color(0.86, 1.0, 0.96, alpha * 0.2), 1.4)

func _draw_attack_afterglow(facing: Vector2) -> void:
	if attack_afterglow_time_left <= 0.0:
		return
	var t := clampf(attack_afterglow_time_left / maxf(attack_afterglow_duration, 0.001), 0.0, 1.0)
	var fade := t * t
	match last_attack_for_fx:
		ATTACK_SEVER:
			var glow_len := 96.0 + 60.0 * t
			draw_line(-facing * 6.0, -facing * glow_len, Color(0.2, 1.0, 0.8, 0.24 * fade), 12.0)
			draw_line(-facing * 2.0, -facing * (glow_len * 0.82), Color(0.9, 1.0, 0.98, 0.32 * fade), 4.0)
		ATTACK_NULL_RING:
			var ring_radius := null_ring_radius * (1.0 + (1.0 - t) * 0.24)
			draw_arc(_locked_null_ring_center - global_position, ring_radius, 0.0, TAU, 56, Color(0.3, 1.0, 0.84, 0.42 * fade), 4.2)
		ATTACK_ECHO_CROSS:
			var primary_dir := Vector2.RIGHT.rotated(_echo_cross_angle)
			var secondary_dir := primary_dir.orthogonal()
			var half_len := echo_cross_length * 0.54
			draw_line(-primary_dir * half_len, primary_dir * half_len, Color(0.28, 1.0, 0.84, 0.24 * fade), 7.0)
			draw_line(-secondary_dir * half_len, secondary_dir * half_len, Color(0.28, 1.0, 0.84, 0.18 * fade), 5.0)

func _draw_null_ring_pull_fx() -> void:
	if _null_ring_pull_fx_time_left <= 0.0:
		return
	var duration := maxf(0.001, null_ring_pull_fx_duration)
	var t := clampf(_null_ring_pull_fx_time_left / duration, 0.0, 1.0)
	var collapse_t := 1.0 - t
	var collapse_curve := collapse_t * collapse_t
	var local_center := _null_ring_pull_fx_center - global_position
	var collapsed_radius := lerpf(null_ring_radius, null_ring_safe_radius * 0.72, collapse_curve)
	var core_radius := lerpf(null_ring_safe_radius, null_ring_safe_radius * 0.26, collapse_curve)
	var alpha := t

	draw_circle(local_center, collapsed_radius, Color(0.16, 0.98, 0.76, 0.1 * alpha))
	draw_arc(local_center, collapsed_radius, 0.0, TAU, 56, Color(0.82, 1.0, 0.95, 0.7 * alpha), 4.2)
	draw_arc(local_center, core_radius, 0.0, TAU, 42, Color(0.9, 1.0, 0.97, 0.52 * alpha), 2.4)
	for spoke_i in range(12):
		var a := float(spoke_i) * TAU / 12.0 + collapse_t * 0.8
		var d := Vector2.RIGHT.rotated(a)
		var outer := local_center + d * (collapsed_radius - 2.0)
		var inner := local_center + d * (core_radius + 4.0)
		draw_line(outer, inner, Color(0.94, 1.0, 0.98, 0.38 * alpha), 1.4)
	draw_circle(local_center, core_radius * 0.34, Color(0.94, 1.0, 0.98, 0.26 * alpha))

func _draw_attack_impact_burst(_facing: Vector2) -> void:
	if impact_burst_time_left <= 0.0:
		return
	var t := clampf(impact_burst_time_left / maxf(impact_burst_duration, 0.001), 0.0, 1.0)
	var radius := 42.0 + (1.0 - t) * 36.0
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 42, Color(0.92, 1.0, 0.98, 0.34 * t), 3.4)
	draw_circle(Vector2.ZERO, radius * 0.44, Color(0.26, 0.98, 0.8, 0.08 * t))
	if active_attack == ATTACK_ECHO_CROSS:
		var primary_dir := Vector2.RIGHT.rotated(_echo_cross_angle)
		var secondary_dir := primary_dir.orthogonal()
		var arm_reach := echo_cross_length * 0.5 - seam_radius * 0.5
		var burst_color := Color(0.92, 1.0, 0.98, 0.48 * t)
		var arm_positions := [
			primary_dir * arm_reach,
			-primary_dir * arm_reach,
			secondary_dir * arm_reach,
			-secondary_dir * arm_reach
		]
		for pos in arm_positions:
			var burst_radius := 18.0 + (1.0 - t) * 22.0
			draw_arc(pos, burst_radius, 0.0, TAU, 24, burst_color, 2.8)