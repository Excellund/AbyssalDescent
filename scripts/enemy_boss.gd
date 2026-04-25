extends "res://scripts/enemy_base.gd"

const STATE_IDLE := 0
const STATE_TELEGRAPH := 1
const STATE_ATTACK := 2
const STATE_RECOVER := 3

const ATTACK_CHARGE := 0
const ATTACK_NOVA := 1
const ATTACK_CLEAVE := 2

@export var boss_max_health: int = 520
@export var move_speed: float = 110.0
@export var acceleration: float = 900.0
@export var deceleration: float = 1300.0
@export var preferred_distance: float = 210.0
@export var action_cooldown: float = 1.0

@export var charge_windup: float = 0.95
@export var charge_speed: float = 560.0
@export var charge_duration: float = 0.55
@export var charge_width: float = 40.0
@export var charge_damage: int = 24

@export var nova_windup: float = 1.05
@export var nova_radius: float = 160.0
@export var nova_damage: int = 30

@export var cleave_windup: float = 0.8
@export var cleave_range: float = 190.0
@export var cleave_arc_degrees: float = 120.0
@export var cleave_damage: int = 20

@export var recover_time: float = 0.7

var boss_state: int = STATE_IDLE
var state_time_left: float = 0.0
var cooldown_left: float = 0.35
var active_attack: int = ATTACK_CHARGE

var locked_direction: Vector2 = Vector2.RIGHT
var telegraph_alpha: float = 0.0
var charge_hit_applied: bool = false


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
	if health_bar != null:
		health_bar.custom_minimum_size = Vector2(132.0, 12.0)
		health_bar.position = Vector2(-66.0, -74.0)


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

	queue_redraw()


func _process_idle_state(delta: float) -> void:
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var desired_velocity := Vector2.ZERO

	if distance > preferred_distance + 24.0:
		desired_velocity = to_target.normalized() * move_speed
	elif distance < preferred_distance - 36.0:
		desired_velocity = -to_target.normalized() * (move_speed * 0.7)

	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()

	if to_target.length_squared() > 0.000001:
		locked_direction = to_target.normalized()
		visual_facing_direction = locked_direction

	if cooldown_left <= 0.0:
		_start_next_attack(distance)


func _start_next_attack(distance_to_target: float) -> void:
	if distance_to_target > 270.0:
		active_attack = ATTACK_CHARGE
	elif distance_to_target < 120.0:
		active_attack = ATTACK_NOVA if randf() < 0.68 else ATTACK_CLEAVE
	else:
		var roll := randf()
		if roll < 0.4:
			active_attack = ATTACK_CLEAVE
		elif roll < 0.72:
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
	match active_attack:
		ATTACK_CHARGE:
			state_time_left = charge_duration
			velocity = locked_direction * charge_speed
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
			velocity = locked_direction * charge_speed
			move_and_slide()
			_apply_charge_hit()
		_:
			velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
			move_and_slide()

	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		boss_state = STATE_RECOVER
		state_time_left = recover_time


func _process_recover_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		boss_state = STATE_IDLE
		cooldown_left = action_cooldown


func _apply_charge_hit() -> void:
	if charge_hit_applied:
		return
	if not target.has_method("take_damage"):
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider() == target:
			target.call("take_damage", charge_damage)
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
		target.call("take_damage", charge_damage)
		charge_hit_applied = true
		# Heavy impact feedback for charge
		if is_instance_valid(target):
			var feedback: Object = target.get("player_feedback") as Object
			if feedback != null and feedback.has_method("play_impact_heavy"):
				feedback.play_impact_heavy(target.global_position, charge_width * 1.5)


func _apply_nova_hit() -> void:
	if not target.has_method("take_damage"):
		return
	if global_position.distance_to(target.global_position) <= nova_radius:
		target.call("take_damage", nova_damage)
		# Heavy impact feedback for nova
		if is_instance_valid(target):
			var feedback: Object = target.get("player_feedback") as Object
			if feedback != null and feedback.has_method("play_impact_heavy"):
				feedback.play_impact_heavy(global_position, nova_radius * 0.9)


func _apply_cleave_hit() -> void:
	if not target.has_method("take_damage"):
		return
	if not _point_in_cone(target.global_position, global_position, locked_direction, cleave_range, cleave_arc_degrees):
		return
	target.call("take_damage", cleave_damage)
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


func _get_windup_time(attack_id: int) -> float:
	match attack_id:
		ATTACK_CHARGE:
			return charge_windup
		ATTACK_NOVA:
			return nova_windup
		ATTACK_CLEAVE:
			return cleave_windup
		_:
			return 0.7


func _draw() -> void:
	var pulse := _get_attack_pulse()
	var body_radius := 34.0 + pulse * 0.8
	var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var body_color := COLOR_BOSS_BODY
	var core_color := COLOR_BOSS_CORE

	if boss_state == STATE_TELEGRAPH:
		body_color = COLOR_BOSS_BODY_TELEGRAPH
		core_color = COLOR_BOSS_CORE_TELEGRAPH
	if boss_state == STATE_ATTACK:
		body_color = COLOR_BOSS_BODY_ATTACK
		core_color = COLOR_BOSS_CORE_ATTACK

	draw_circle(Vector2.ZERO, body_radius + 9.0, COLOR_BOSS_GLOW)
	_draw_common_body(body_radius, body_color, core_color, facing)

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
