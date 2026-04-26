extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

const STATE_IDLE := 0
const STATE_TELEGRAPH := 1
const STATE_ATTACK := 2
const STATE_RECOVER := 3

const ATTACK_CHARGE := 0
const ATTACK_NOVA := 1
const ATTACK_CLEAVE := 2

@export var boss_max_health: int = 520
@export var move_speed: float = 124.0
@export var acceleration: float = 900.0
@export var deceleration: float = 1300.0
@export var preferred_distance: float = 210.0
@export var action_cooldown: float = 0.78

@export var charge_windup: float = 0.84
@export var charge_speed: float = 640.0
@export var charge_duration: float = 0.58
@export var charge_width: float = 40.0
@export var charge_damage: int = 28

@export var nova_windup: float = 0.9
@export var nova_radius: float = 172.0
@export var nova_damage: int = 34

@export var cleave_windup: float = 0.7
@export var cleave_range: float = 212.0
@export var cleave_arc_degrees: float = 132.0
@export var cleave_damage: int = 24

@export var recover_time: float = 0.5
@export var arena_size: Vector2 = Vector2(1260.0, 900.0)
@export var edge_soft_margin: float = 170.0
@export var edge_hard_margin: float = 105.0

var boss_state: int = STATE_IDLE
var state_time_left: float = 0.0
var cooldown_left: float = 0.35
var active_attack: int = ATTACK_CHARGE

var locked_direction: Vector2 = Vector2.RIGHT
var telegraph_alpha: float = 0.0
var charge_hit_applied: bool = false
var attack_afterglow_time_left: float = 0.0
var attack_afterglow_duration: float = 0.54
var impact_burst_time_left: float = 0.0
var impact_burst_duration: float = 0.2
var last_attack_for_fx: int = ATTACK_CHARGE


func _ready() -> void:
	# Apply boss-specific tuning to inherited health before base setup runs.
	max_health = boss_max_health
	super._ready()
	# Resize inherited collision shape so boss body and hitbox align.
	for child in get_children():
		if child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if shape_node.shape is CircleShape2D:
				(shape_node.shape as CircleShape2D).radius = 34.0
				break
	configure_health_bar_visuals(Vector2(-66.0, -74.0), Vector2(132.0, 12.0))


func _process_behavior(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return

	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)

	match boss_state:
		STATE_IDLE:
			_process_idle_state(delta)
		STATE_TELEGRAPH:
			_process_telegraph_state(delta)
		STATE_ATTACK:
			_process_attack_state(delta)
		STATE_RECOVER:
			_process_recover_state(delta)

	attack_afterglow_time_left = maxf(0.0, attack_afterglow_time_left - delta)
	impact_burst_time_left = maxf(0.0, impact_burst_time_left - delta)

	queue_redraw()


func _process_idle_state(delta: float) -> void:
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var desired_velocity := Vector2.ZERO
	var enrage_t: float = _get_enrage_ratio()
	var speed_mult: float = lerpf(1.0, 1.22, enrage_t)
	var inward_bias := _get_inward_edge_bias()
	var wall_pressure := inward_bias.length()

	if wall_pressure > 0.0:
		desired_velocity += inward_bias * move_speed * (0.95 + wall_pressure * 0.6)

	if distance > preferred_distance + 24.0:
		desired_velocity += to_target.normalized() * move_speed * speed_mult
	elif distance < preferred_distance - 36.0:
		var retreat_dir := -to_target.normalized()
		if _can_move_in_direction(retreat_dir, 22.0):
			desired_velocity += retreat_dir * (move_speed * 0.74 * speed_mult)
		else:
			# When pinned near map edges, strafe instead of backing into walls.
			var lateral := Vector2(-retreat_dir.y, retreat_dir.x)
			var left_clear := _can_move_in_direction(lateral, 18.0)
			var right_clear := _can_move_in_direction(-lateral, 18.0)
			if left_clear and not right_clear:
				desired_velocity += lateral * (move_speed * 0.62 * speed_mult)
			elif right_clear and not left_clear:
				desired_velocity += -lateral * (move_speed * 0.62 * speed_mult)
			elif left_clear and right_clear:
				desired_velocity += lateral * (move_speed * 0.62 * speed_mult)

	if wall_pressure > 0.62 and desired_velocity.length_squared() > 0.000001:
		desired_velocity = desired_velocity.normalized() * move_speed * speed_mult

	desired_velocity *= slow_speed_mult
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()

	if to_target.length_squared() > 0.000001:
		locked_direction = to_target.normalized()
		visual_facing_direction = locked_direction

	if cooldown_left <= 0.0 and wall_pressure < 0.65:
		_start_next_attack(distance)


func _start_next_attack(distance_to_target: float) -> void:
	var enrage_t: float = _get_enrage_ratio()
	if distance_to_target > 270.0:
		active_attack = ATTACK_CHARGE
	elif distance_to_target < 120.0:
		active_attack = ATTACK_NOVA if randf() < lerpf(0.66, 0.8, enrage_t) else ATTACK_CLEAVE
	else:
		var roll := randf()
		if roll < lerpf(0.34, 0.24, enrage_t):
			active_attack = ATTACK_CLEAVE
		elif roll < lerpf(0.72, 0.82, enrage_t):
			active_attack = ATTACK_CHARGE
		else:
			active_attack = ATTACK_NOVA

	var to_target := target.global_position - global_position
	if to_target.length_squared() > 0.000001:
		locked_direction = to_target.normalized()
	visual_facing_direction = locked_direction

	boss_state = STATE_TELEGRAPH
	state_time_left = _get_windup_time(active_attack)
	telegraph_alpha = 0.0
	charge_hit_applied = false
	velocity = Vector2.ZERO


func _process_telegraph_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	var windup := _get_windup_time(active_attack)
	if windup > 0.0:
		telegraph_alpha = clampf(1.0 - (state_time_left / windup), 0.0, 1.0)
	else:
		telegraph_alpha = 1.0

	if state_time_left <= 0.0:
		_enter_attack_state()


func _enter_attack_state() -> void:
	boss_state = STATE_ATTACK
	attack_anim_time_left = attack_anim_duration
	last_attack_for_fx = active_attack
	attack_afterglow_time_left = attack_afterglow_duration
	impact_burst_time_left = impact_burst_duration
	var enrage_t: float = _get_enrage_ratio()
	match active_attack:
		ATTACK_CHARGE:
			state_time_left = charge_duration * lerpf(1.0, 0.84, enrage_t)
			velocity = locked_direction * charge_speed * lerpf(1.0, 1.18, enrage_t)
		ATTACK_NOVA:
			state_time_left = 0.05
			velocity = Vector2.ZERO
			_apply_nova_hit()
		ATTACK_CLEAVE:
			state_time_left = 0.06
			velocity = Vector2.ZERO
			_apply_cleave_hit()


func _process_attack_state(delta: float) -> void:
	match active_attack:
		ATTACK_CHARGE:
			velocity = locked_direction * charge_speed * lerpf(1.0, 1.18, _get_enrage_ratio())
			move_and_slide()
			_apply_charge_hit()
		_:
			velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
			move_and_slide()

	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		boss_state = STATE_RECOVER
		state_time_left = recover_time * lerpf(1.0, 0.72, _get_enrage_ratio())


func _process_recover_state(delta: float) -> void:
	var inward_bias := _get_inward_edge_bias()
	var recover_target := inward_bias * move_speed * 0.58
	velocity = velocity.move_toward(recover_target, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		boss_state = STATE_IDLE
		cooldown_left = action_cooldown * lerpf(1.0, 0.62, _get_enrage_ratio())


func _apply_charge_hit() -> void:
	if charge_hit_applied:
		return
	if not DAMAGEABLE.can_take_damage(target):
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() == target:
			DAMAGEABLE.apply_damage(target, charge_damage)
			charge_hit_applied = true
			# Heavy impact feedback for charge
			if is_instance_valid(target):
				var feedback: Object = target.get("player_feedback") as Object
				if feedback != null and feedback.has_method("play_impact_heavy"):
					feedback.play_impact_heavy(target.global_position, charge_width * 1.5)
			return

	var seg_start := global_position - locked_direction * 34.0
	var seg_end := global_position + locked_direction * 34.0
	if _distance_point_to_segment(target.global_position, seg_start, seg_end) <= charge_width:
		DAMAGEABLE.apply_damage(target, charge_damage)
		charge_hit_applied = true
		# Heavy impact feedback for charge
		if is_instance_valid(target):
			var feedback: Object = target.get("player_feedback") as Object
			if feedback != null and feedback.has_method("play_impact_heavy"):
				feedback.play_impact_heavy(target.global_position, charge_width * 1.5)


func _apply_nova_hit() -> void:
	if not DAMAGEABLE.can_take_damage(target):
		return
	if global_position.distance_to(target.global_position) <= nova_radius:
		DAMAGEABLE.apply_damage(target, nova_damage)
		# Heavy impact feedback for nova
		if is_instance_valid(target):
			var feedback: Object = target.get("player_feedback") as Object
			if feedback != null and feedback.has_method("play_impact_heavy"):
				feedback.play_impact_heavy(global_position, nova_radius * 0.9)


func _apply_cleave_hit() -> void:
	if not DAMAGEABLE.can_take_damage(target):
		return
	if not _point_in_cone(target.global_position, global_position, locked_direction, cleave_range, cleave_arc_degrees):
		return
	DAMAGEABLE.apply_damage(target, cleave_damage)
	# Heavy impact feedback for cleave
	if is_instance_valid(target):
		var feedback: Object = target.get("player_feedback") as Object
		if feedback != null and feedback.has_method("play_impact_heavy"):
			feedback.play_impact_heavy(global_position, cleave_range * 0.7)


func _point_in_cone(point: Vector2, origin: Vector2, forward: Vector2, radius: float, arc_degrees: float) -> bool:
	var to_point := point - origin
	if to_point.length() > radius:
		return false
	if to_point.length_squared() <= 0.000001:
		return true
	var dir := to_point.normalized()
	var fwd := forward.normalized()
	var dot_value := clampf(fwd.dot(dir), -1.0, 1.0)
	var angle := rad_to_deg(acos(dot_value))
	return angle <= arc_degrees * 0.5


func _distance_point_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var length_sq := segment.length_squared()
	if length_sq <= 0.000001:
		return point.distance_to(segment_start)
	var t := clampf((point - segment_start).dot(segment) / length_sq, 0.0, 1.0)
	var closest := segment_start + segment * t
	return point.distance_to(closest)


func _can_move_in_direction(direction: Vector2, probe_distance: float) -> bool:
	if direction.length_squared() <= 0.000001:
		return true
	var move_dir := direction.normalized()
	return not test_move(global_transform, move_dir * probe_distance)


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
	var enrage_t: float = _get_enrage_ratio()
	match attack_id:
		ATTACK_CHARGE:
			return charge_windup * lerpf(1.0, 0.82, enrage_t)
		ATTACK_NOVA:
			return nova_windup * lerpf(1.0, 0.84, enrage_t)
		ATTACK_CLEAVE:
			return cleave_windup * lerpf(1.0, 0.8, enrage_t)
		_:
			return 0.7


func _get_enrage_ratio() -> float:
	var health_ratio: float = float(_get_current_health()) / maxf(1.0, float(max_health))
	if health_ratio >= 0.7:
		return 0.0
	if health_ratio <= 0.25:
		return 1.0
	return clampf((0.7 - health_ratio) / 0.45, 0.0, 1.0)


func _draw() -> void:
	var pulse := _get_attack_pulse()
	var body_radius := 34.0 + pulse * 0.8
	var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var body_color := COLOR_BOSS_BODY
	var core_color := COLOR_BOSS_CORE
	var threat_t := telegraph_alpha if boss_state == STATE_TELEGRAPH else 0.0
	var threat_pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.016)
	var enrage_t: float = _get_enrage_ratio()

	if boss_state == STATE_TELEGRAPH:
		body_color = COLOR_BOSS_BODY_TELEGRAPH
		core_color = COLOR_BOSS_CORE_TELEGRAPH
	if boss_state == STATE_ATTACK:
		body_color = COLOR_BOSS_BODY_ATTACK
		core_color = COLOR_BOSS_CORE_ATTACK
	if enrage_t > 0.0:
		body_color = body_color.lerp(COLOR_BOSS_BODY_ATTACK, enrage_t * 0.35)
		core_color = core_color.lerp(COLOR_BOSS_CORE_ATTACK, enrage_t * 0.48)

	_draw_enrage_scaling_indicator(body_radius, facing, enrage_t)

	# Persistent menace halo during telegraph to imply severe punishment on mistakes.
	if boss_state == STATE_TELEGRAPH:
		var halo_radius := body_radius + 16.0 + threat_t * 8.0
		draw_circle(Vector2.ZERO, halo_radius, Color(1.0, 0.2, 0.08, 0.06 + threat_t * 0.1))
		draw_arc(Vector2.ZERO, halo_radius + 3.0, 0.0, TAU, 48, Color(1.0, 0.82, 0.45, 0.28 + threat_t * 0.26 + threat_pulse * 0.08), 2.6)

	draw_circle(Vector2.ZERO, body_radius + 9.0, COLOR_BOSS_GLOW)
	_draw_common_body(body_radius, body_color, core_color, facing)
	_draw_slow_indicator(body_radius)
	_draw_attack_afterglow(facing)
	_draw_attack_impact_burst(facing)

	if boss_state == STATE_TELEGRAPH:
		_draw_attack_telegraph()
		_draw_role_state_icon(facing, body_radius)

	if boss_state == STATE_ATTACK and active_attack == ATTACK_CHARGE:
		var line_end := locked_direction * 120.0
		draw_line(Vector2.ZERO, line_end, Color(COLOR_BOSS_CHARGE_LINE.r, COLOR_BOSS_CHARGE_LINE.g, COLOR_BOSS_CHARGE_LINE.b, 0.9), 8.0)


func _draw_role_state_icon(facing: Vector2, body_radius: float) -> void:
	var icon_alpha := 0.36 + telegraph_alpha * 0.58
	match active_attack:
		ATTACK_CHARGE:
			var side := Vector2(-facing.y, facing.x)
			var tip := facing * (body_radius + 14.0)
			var base := facing * (body_radius + 4.0)
			draw_colored_polygon(PackedVector2Array([tip, base + side * 5.4, base - side * 5.4]), Color(1.0, 0.88, 0.44, icon_alpha))
		ATTACK_NOVA:
			draw_arc(Vector2.ZERO, body_radius + 12.0, 0.0, TAU, 40, Color(1.0, 0.78, 0.36, icon_alpha), 2.4)
		ATTACK_CLEAVE:
			var half_arc := deg_to_rad(cleave_arc_degrees * 0.26)
			draw_arc(Vector2.ZERO, body_radius + 12.0, facing.angle() - half_arc, facing.angle() + half_arc, 18, Color(1.0, 0.84, 0.42, icon_alpha), 2.8)


func _draw_attack_telegraph() -> void:
	var alpha := 0.2 + telegraph_alpha * 0.7
	match active_attack:
		ATTACK_CHARGE:
			var length := charge_speed * charge_duration * 0.72
			var start := locked_direction * 24.0
			var end := start + locked_direction * length
			var charge_pulse := 0.5 + 0.5 * sin(telegraph_alpha * PI * 2.0)
			
			# Pulsing charge build-up glow
			draw_circle(Vector2.ZERO, (end - start).length() * 0.3, Color(COLOR_BOSS_CHARGE_LINE.r, COLOR_BOSS_CHARGE_LINE.g, COLOR_BOSS_CHARGE_LINE.b, alpha * charge_pulse * 0.2))
			
			# Outer charge line (wider, more dramatic)
			draw_line(start, end, Color(COLOR_BOSS_CHARGE_LINE.r, COLOR_BOSS_CHARGE_LINE.g, COLOR_BOSS_CHARGE_LINE.b, alpha * 0.6), charge_width * 2.5)
			
			# Inner bright core
			draw_line(start, end, Color(COLOR_BOSS_CHARGE_LINE_INNER.r, COLOR_BOSS_CHARGE_LINE_INNER.g, COLOR_BOSS_CHARGE_LINE_INNER.b, minf(1.0, alpha + 0.15)), 4.0)
			
			# Impact zone accent marks
			var side := Vector2(-locked_direction.y, locked_direction.x)
			var impact_width := 16.0
			draw_line(end + side * impact_width, end + side * impact_width - locked_direction * 14.0, Color(COLOR_BOSS_CHARGE_LINE_INNER.r, COLOR_BOSS_CHARGE_LINE_INNER.g, COLOR_BOSS_CHARGE_LINE_INNER.b, minf(1.0, alpha + 0.1)), 2.5)
			draw_line(end - side * impact_width, end - side * impact_width - locked_direction * 14.0, Color(COLOR_BOSS_CHARGE_LINE_INNER.r, COLOR_BOSS_CHARGE_LINE_INNER.g, COLOR_BOSS_CHARGE_LINE_INNER.b, minf(1.0, alpha + 0.1)), 2.5)
		
		ATTACK_NOVA:
			var nova_pulse := 0.5 + 0.5 * sin(telegraph_alpha * PI * 1.5)
			
			# Inner danger ring (closer threat)
			draw_arc(Vector2.ZERO, nova_radius * 0.5, 0.0, TAU, 40, Color(COLOR_BOSS_NOVA_RING.r, COLOR_BOSS_NOVA_RING.g, COLOR_BOSS_NOVA_RING.b, alpha * 0.7), 3.0)
			
			# Main explosion glow (pulsing intensity)
			draw_circle(Vector2.ZERO, nova_radius, Color(COLOR_BOSS_NOVA_GLOW.r, COLOR_BOSS_NOVA_GLOW.g, COLOR_BOSS_NOVA_GLOW.b, alpha * 0.25 * (0.7 + nova_pulse * 0.3)))
			
			# Outer nova ring (main danger zone)
			var nova_width := 4.0 + nova_pulse * 2.0
			draw_arc(Vector2.ZERO, nova_radius, 0.0, TAU, 56, Color(COLOR_BOSS_NOVA_RING.r, COLOR_BOSS_NOVA_RING.g, COLOR_BOSS_NOVA_RING.b, alpha), nova_width)
			
			# Secondary fading ring (aftermath indicator)
			draw_arc(Vector2.ZERO, nova_radius * 1.2, 0.0, TAU, 48, Color(COLOR_BOSS_NOVA_RING.r, COLOR_BOSS_NOVA_RING.g, COLOR_BOSS_NOVA_RING.b, alpha * 0.3), 2.0)
		
		ATTACK_CLEAVE:
			var half_arc := deg_to_rad(cleave_arc_degrees * 0.5)
			var points := PackedVector2Array([Vector2.ZERO])
			var segments := 26
			for i in range(segments + 1):
				var t := float(i) / float(segments)
				var angle := -half_arc + (half_arc * 2.0) * t
				points.append(locked_direction.rotated(angle) * cleave_range)
			
			# Main cleave fill (semi-transparent danger zone)
			draw_colored_polygon(points, Color(COLOR_BOSS_CLEAVE_FILL.r, COLOR_BOSS_CLEAVE_FILL.g, COLOR_BOSS_CLEAVE_FILL.b, alpha * 0.4))
			
			# Cleave outline (sharp edges)
			for i in range(segments):
				draw_line(points[i + 1], points[i + 2], Color(COLOR_BOSS_CLEAVE_OUTLINE.r, COLOR_BOSS_CLEAVE_OUTLINE.g, COLOR_BOSS_CLEAVE_OUTLINE.b, alpha * 0.9), 2.5)
			
			# Inner sweep lines (shows slash motion)
			var inner_radius := cleave_range * 0.4
			draw_line(Vector2.ZERO, locked_direction.rotated(-half_arc) * inner_radius, Color(COLOR_BOSS_CLEAVE_OUTLINE.r, COLOR_BOSS_CLEAVE_OUTLINE.g, COLOR_BOSS_CLEAVE_OUTLINE.b, alpha * 0.6), 1.5)
			draw_line(Vector2.ZERO, locked_direction.rotated(half_arc) * inner_radius, Color(COLOR_BOSS_CLEAVE_OUTLINE.r, COLOR_BOSS_CLEAVE_OUTLINE.g, COLOR_BOSS_CLEAVE_OUTLINE.b, alpha * 0.6), 1.5)


func _draw_attack_afterglow(facing: Vector2) -> void:
	if attack_afterglow_time_left <= 0.0:
		return
	var t := clampf(attack_afterglow_time_left / maxf(attack_afterglow_duration, 0.001), 0.0, 1.0)
	var fade := t * t
	var _side := Vector2(-facing.y, facing.x)
	match last_attack_for_fx:
		ATTACK_CHARGE:
			var glow_len := 94.0 + 58.0 * t
			var tail_alpha := 0.24 * fade
			draw_line(-facing * 6.0, -facing * glow_len, Color(1.0, 0.66, 0.28, tail_alpha), 12.0)
			draw_line(-facing * 3.0, -facing * (glow_len * 0.82), Color(1.0, 0.9, 0.56, tail_alpha * 1.35), 4.0)
		ATTACK_NOVA:
			var ring_radius := nova_radius * (1.0 + (1.0 - t) * 0.45)
			draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 56, Color(1.0, 0.52, 0.2, 0.42 * fade), 5.0)
			draw_circle(Vector2.ZERO, ring_radius * 0.66, Color(1.0, 0.35, 0.12, 0.09 * fade))
		ATTACK_CLEAVE:
			var half_arc := deg_to_rad(cleave_arc_degrees * 0.5)
			var outer := cleave_range * (0.92 + (1.0 - t) * 0.22)
			var a0 := facing.angle() - half_arc
			var a1 := facing.angle() + half_arc
			draw_arc(Vector2.ZERO, outer, a0, a1, 28, Color(1.0, 0.7, 0.3, 0.4 * fade), 4.0)
			draw_line(Vector2.ZERO, facing.rotated(-half_arc) * (outer * 0.7), Color(1.0, 0.76, 0.42, 0.22 * fade), 2.2)
			draw_line(Vector2.ZERO, facing.rotated(half_arc) * (outer * 0.7), Color(1.0, 0.76, 0.42, 0.22 * fade), 2.2)


func _draw_attack_impact_burst(facing: Vector2) -> void:
	if impact_burst_time_left <= 0.0:
		return
	var t := 1.0 - clampf(impact_burst_time_left / maxf(impact_burst_duration, 0.001), 0.0, 1.0)
	var burst_ease := 1.0 - pow(1.0 - t, 3.0)
	var burst_alpha := (1.0 - t) * (1.0 - t)
	var side := Vector2(-facing.y, facing.x)
	match last_attack_for_fx:
		ATTACK_CHARGE:
			var burst_center := facing * (30.0 + burst_ease * 32.0)
			var burst_r := 18.0 + burst_ease * 28.0
			draw_circle(burst_center, burst_r, Color(1.0, 0.62, 0.22, 0.26 * burst_alpha))
			draw_arc(burst_center, burst_r + 4.0, 0.0, TAU, 24, Color(1.0, 0.88, 0.5, 0.6 * burst_alpha), 3.0)
			draw_line(burst_center + side * 18.0, burst_center + side * 42.0, Color(1.0, 0.84, 0.46, 0.5 * burst_alpha), 2.2)
			draw_line(burst_center - side * 18.0, burst_center - side * 42.0, Color(1.0, 0.84, 0.46, 0.5 * burst_alpha), 2.2)
		ATTACK_NOVA:
			var nova_r := 44.0 + burst_ease * (nova_radius * 0.72)
			draw_circle(Vector2.ZERO, nova_r, Color(1.0, 0.46, 0.18, 0.2 * burst_alpha))
			draw_arc(Vector2.ZERO, nova_r, 0.0, TAU, 48, Color(1.0, 0.86, 0.5, 0.68 * burst_alpha), 4.0)
		ATTACK_CLEAVE:
			var half_arc := deg_to_rad(cleave_arc_degrees * 0.5)
			var r := 56.0 + burst_ease * (cleave_range * 0.62)
			draw_arc(Vector2.ZERO, r, facing.angle() - half_arc, facing.angle() + half_arc, 26, Color(1.0, 0.78, 0.36, 0.72 * burst_alpha), 4.2)
			draw_line(Vector2.ZERO, facing.rotated(-half_arc * 0.88) * r, Color(1.0, 0.86, 0.5, 0.42 * burst_alpha), 2.8)
			draw_line(Vector2.ZERO, facing.rotated(half_arc * 0.88) * r, Color(1.0, 0.86, 0.5, 0.42 * burst_alpha), 2.8)


func _draw_enrage_scaling_indicator(body_radius: float, facing: Vector2, enrage_t: float) -> void:
	if enrage_t <= 0.0:
		return

	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * (0.012 + enrage_t * 0.018))
	var side := Vector2(-facing.y, facing.x)
	var aura_radius := body_radius + 13.0 + enrage_t * 14.0
	var aura_alpha := 0.05 + enrage_t * 0.12 + pulse * 0.05

	# Always-on enrage aura so scaling is readable even out of telegraph windows.
	draw_circle(Vector2.ZERO, aura_radius, Color(1.0, 0.2, 0.08, aura_alpha))
	draw_arc(Vector2.ZERO, aura_radius + 2.0, 0.0, TAU, 42, Color(1.0, 0.78, 0.36, 0.2 + enrage_t * 0.35), 2.1 + enrage_t * 1.3)

	var tier: int = _get_enrage_tier(enrage_t)
	var pip_anchor := -facing * (body_radius + 18.0)
	for i in range(3):
		var offset := side * ((float(i) - 1.0) * 10.0)
		var pip_pos := pip_anchor + offset
		var lit: bool = i < tier
		var pip_color := Color(1.0, 0.42, 0.14, 0.88) if lit else Color(0.44, 0.2, 0.16, 0.45)
		draw_circle(pip_pos, 2.9, pip_color)
		if lit:
			draw_arc(pip_pos, 5.0, 0.0, TAU, 18, Color(1.0, 0.86, 0.54, 0.62), 1.4)


func _get_enrage_tier(enrage_t: float) -> int:
	if enrage_t >= 0.85:
		return 3
	if enrage_t >= 0.5:
		return 2
	if enrage_t > 0.0:
		return 1
	return 0
