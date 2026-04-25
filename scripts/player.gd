extends CharacterBody2D

const HEALTH_STATE_SCRIPT := preload("res://scripts/health_state.gd")
const PLAYER_FEEDBACK_SCRIPT := preload("res://scripts/player_feedback.gd")
const UPGRADE_SYSTEM_SCRIPT := preload("res://scripts/upgrade_system.gd")

signal health_changed(current_health: int, max_health: int)
signal died

@export var max_speed: float = 220.0
@export var acceleration: float = 1400.0
@export var deceleration: float = 1800.0
@export var turn_boost: float = 1.25
@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.12
@export var dash_cooldown: float = 0.35
@export var max_health: int = 100
@export var attack_damage: int = 20
@export var attack_range: float = 74.0
@export var attack_arc_degrees: float = 130.0
@export var attack_cooldown: float = 0.28
@export var attack_lock_duration: float = 0.12

var dash_time_left: float = 0.0
var dash_cooldown_left: float = 0.0
var last_move_direction: Vector2 = Vector2.RIGHT
var dash_direction: Vector2 = Vector2.ZERO
var attack_cooldown_left: float = 0.0
var scene_restart_queued: bool = false
var health_state
var player_feedback
var upgrade_system
var attack_anim_time_left: float = 0.0
var attack_anim_duration: float = 0.12
var visual_facing_direction: Vector2 = Vector2.RIGHT
var attack_lock_time_left: float = 0.0
var attack_lock_direction: Vector2 = Vector2.RIGHT
var attack_combo_counter: int = 0
var reward_razor_wind: bool = false
var reward_execution_edge: bool = false
var reward_rupture_wave: bool = false
var razor_wind_stacks: int = 0
var execution_edge_stacks: int = 0
var rupture_wave_stacks: int = 0
var execution_every: int = 3
var execution_damage_mult: float = 2.6
var rupture_wave_radius: float = 82.0
var rupture_wave_damage_ratio: float = 0.44
var razor_wind_range_scale: float = 1.72
var razor_wind_arc_degrees: float = 24.0
var razor_wind_damage_ratio: float = 0.72

func _ready() -> void:
	died.connect(_restart_current_scene)
	upgrade_system = UPGRADE_SYSTEM_SCRIPT.new()
	add_child(upgrade_system)
	_create_health_state()
	_create_player_feedback()
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.visible = false
	queue_redraw()

func _physics_process(delta: float) -> void:
	var direction := _read_movement_direction()
	_update_last_move_direction(direction)
	_update_dash_cooldown(delta)
	_update_attack_cooldown(delta)
	_update_attack_lock(delta)
	_update_attack_animation(delta)
	_update_visual_facing_direction()
	_try_start_dash(direction)
	_try_attack()

	if _is_attack_locked():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _process_active_dash(delta):
		return

	_update_ground_movement(direction, delta)
	move_and_slide()

func _read_movement_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func _update_last_move_direction(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		last_move_direction = direction

func _update_dash_cooldown(delta: float) -> void:
	if dash_cooldown_left > 0.0:
		dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)

func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

func _try_start_dash(direction: Vector2) -> void:
	if _is_attack_locked():
		return
	if not Input.is_action_just_pressed("dash"):
		return
	if dash_cooldown_left > 0.0:
		return

	dash_direction = direction if direction != Vector2.ZERO else last_move_direction
	dash_time_left = dash_duration
	dash_cooldown_left = dash_cooldown

func _try_attack() -> void:
	if not Input.is_action_just_pressed("attack"):
		return
	if attack_cooldown_left > 0.0:
		return

	attack_cooldown_left = attack_cooldown
	attack_anim_time_left = attack_anim_duration
	player_feedback.play_attack_swing_sound()

	var attack_direction := _get_mouse_attack_direction()
	attack_combo_counter += 1
	var swing_color := Color(0.99, 0.96, 0.68, 0.72)
	var execution_proc := false
	if reward_execution_edge and attack_combo_counter % execution_every == 0:
		execution_proc = true
		swing_color = Color(1.0, 0.58, 0.3, 0.86)
	var melee_context: Dictionary = upgrade_system.build_melee_attack_context(attack_damage, attack_range, attack_arc_degrees, execution_proc, execution_damage_mult)
	attack_lock_time_left = attack_lock_duration
	attack_lock_direction = attack_direction
	visual_facing_direction = attack_direction
	velocity = Vector2.ZERO
	dash_time_left = 0.0
	if reward_razor_wind:
		swing_color = Color(0.58, 0.95, 0.86, 0.82) if not execution_proc else Color(1.0, 0.58, 0.3, 0.9)
	player_feedback.play_attack_swing_visual(attack_direction, float(melee_context["range"]), float(melee_context["arc_degrees"]), swing_color)
	if reward_razor_wind:
		var wind_context: Dictionary = upgrade_system.build_razor_wind_attack_context(melee_context, razor_wind_damage_ratio, razor_wind_range_scale, razor_wind_arc_degrees, attack_damage, attack_range)
		var wind_range := float(wind_context["range"])
		var wind_color := Color(0.56, 1.0, 0.86, 0.62) if not execution_proc else Color(1.0, 0.62, 0.34, 0.74)
		player_feedback.play_attack_swing_visual(attack_direction, wind_range, razor_wind_arc_degrees, wind_color, 0.14)
	if execution_proc:
		player_feedback.play_world_ring(global_position, 40.0, Color(1.0, 0.62, 0.34, 0.9), 0.16)
	if _perform_melee_attack(attack_direction, melee_context):
		player_feedback.play_impact_sound()

func _update_attack_lock(delta: float) -> void:
	if attack_lock_time_left > 0.0:
		attack_lock_time_left = maxf(0.0, attack_lock_time_left - delta)

func _is_attack_locked() -> bool:
	return attack_lock_time_left > 0.0

func _get_mouse_attack_direction() -> Vector2:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 0.000001:
		return to_mouse.normalized()
	if last_move_direction != Vector2.ZERO:
		return last_move_direction
	return Vector2.RIGHT

func _process_active_dash(delta: float) -> bool:
	if dash_time_left <= 0.0:
		return false

	dash_time_left = maxf(0.0, dash_time_left - delta)
	velocity = dash_direction * dash_speed
	move_and_slide()
	return true

func _update_ground_movement(direction: Vector2, delta: float) -> void:
	var target_velocity := direction * max_speed
	var applied_acceleration := _get_applied_acceleration(target_velocity)
	var move_rate := applied_acceleration if direction != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(target_velocity, move_rate * delta)

func _get_applied_acceleration(target_velocity: Vector2) -> float:
	if target_velocity == Vector2.ZERO:
		return acceleration
	if velocity.dot(target_velocity) < 0.0:
		return acceleration * turn_boost
	return acceleration

func _update_attack_animation(delta: float) -> void:
	if attack_anim_time_left > 0.0:
		attack_anim_time_left = maxf(0.0, attack_anim_time_left - delta)
		queue_redraw()

func _update_visual_facing_direction() -> void:
	if _is_attack_locked():
		if attack_lock_direction.length_squared() > 0.000001:
			visual_facing_direction = attack_lock_direction
		queue_redraw()
		return

	if velocity.length_squared() > 1.0:
		var move_facing := velocity.normalized()
		var blended_facing := visual_facing_direction.slerp(move_facing, 0.32)
		if blended_facing.length_squared() > 0.000001:
			visual_facing_direction = blended_facing.normalized()
		else:
			visual_facing_direction = move_facing
	queue_redraw()

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	var health_before := _get_current_health()
	health_state.take_damage(amount)
	if _get_current_health() < health_before:
		player_feedback.play_damage_flash()
		player_feedback.play_impact_sound()

func heal(amount: int) -> void:
	if amount <= 0:
		return
	health_state.heal(amount)

func is_dead() -> bool:
	return health_state.is_dead()

func apply_upgrade(boon_id: String) -> void:
	match boon_id:
		"swift_strike":
			attack_cooldown = maxf(0.08, attack_cooldown * 0.86)
		"heavy_blow":
			attack_damage += 8
		"wide_arc":
			attack_arc_degrees = clampf(attack_arc_degrees + 18.0, 60.0, 240.0)
		"long_reach":
			attack_range += 14.0
		"fleet_foot":
			max_speed += 18.0
		"blink_dash":
			dash_cooldown = maxf(0.12, dash_cooldown * 0.85)
		"iron_skin":
			if health_state != null:
				health_state.max_health += 20
				health_state.set_health(health_state.current_health + 20)
				max_health = health_state.max_health
		_:
			pass

func apply_trial_power(reward_id: String) -> void:
	match reward_id:
		"razor_wind":
			reward_razor_wind = true
			razor_wind_stacks += 1
			razor_wind_range_scale = 1.58 + 0.14 * float(razor_wind_stacks)
			razor_wind_damage_ratio = 0.6 + 0.12 * float(razor_wind_stacks)
			attack_cooldown = maxf(0.1, attack_cooldown * 0.96)
		"execution_edge":
			reward_execution_edge = true
			execution_edge_stacks += 1
			execution_every = maxi(2, 4 - execution_edge_stacks)
			execution_damage_mult = 2.2 + 0.45 * float(execution_edge_stacks)
			attack_lock_duration = maxf(0.08, attack_lock_duration * 0.94)
		"rupture_wave":
			reward_rupture_wave = true
			rupture_wave_stacks += 1
			rupture_wave_radius = 72.0 + 10.0 * float(rupture_wave_stacks)
			rupture_wave_damage_ratio = 0.34 + 0.1 * float(rupture_wave_stacks)
			attack_damage += 2
		_:
			pass

func apply_power_for_test(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	if id.is_empty():
		return false

	var hard_ids := {
		"razor_wind": true,
		"execution_edge": true,
		"rupture_wave": true
	}
	if hard_ids.has(id):
		apply_trial_power(id)
		return true

	var boon_ids := {
		"swift_strike": true,
		"heavy_blow": true,
		"wide_arc": true,
		"long_reach": true,
		"fleet_foot": true,
		"blink_dash": true,
		"iron_skin": true
	}
	if boon_ids.has(id):
		apply_upgrade(id)
		return true

	return false

func get_trial_power_card_desc(reward_id: String) -> String:
	match reward_id:
		"razor_wind":
			var next_stack := razor_wind_stacks + 1
			var next_range := 1.58 + 0.14 * float(next_stack)
			var next_damage := 0.6 + 0.12 * float(next_stack)
			return "Next: forward wind slash at %d%% range and %d%% damage." % [int(round(next_range * 100.0)), int(round(next_damage * 100.0))]
		"execution_edge":
			var next_stack := execution_edge_stacks + 1
			var next_every := maxi(2, 4 - next_stack)
			var next_mult := 2.2 + 0.45 * float(next_stack)
			return "Next: execution every %d swings, %d%% execution damage." % [next_every, int(round(next_mult * 100.0))]
		"rupture_wave":
			var next_stack := rupture_wave_stacks + 1
			var next_radius := 72.0 + 10.0 * float(next_stack)
			var next_wave_damage := 0.34 + 0.1 * float(next_stack)
			return "Next: rupture radius %d, wave deals %d%% of hit damage." % [int(round(next_radius)), int(round(next_wave_damage * 100.0))]
		_:
			return "Enhances this power."

func get_trial_power_stack_count(reward_id: String) -> int:
	match reward_id:
		"razor_wind":
			return razor_wind_stacks
		"execution_edge":
			return execution_edge_stacks
		"rupture_wave":
			return rupture_wave_stacks
		_:
			return 0

func _perform_melee_attack(attack_direction: Vector2, melee_context: Dictionary) -> bool:
	var did_hit := false
	var strike_damage := int(melee_context.get("damage", attack_damage))
	var strike_range := float(melee_context.get("range", attack_range))
	var strike_arc_degrees := float(melee_context.get("arc_degrees", attack_arc_degrees))
	var max_angle_radians := deg_to_rad(strike_arc_degrees * 0.5)

	var melee_hit_enemy_ids: Dictionary = {}

	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		if not enemy_node.has_method("take_damage"):
			continue

		var enemy_body := enemy_node as Node2D
		var enemy_id := enemy_body.get_instance_id()
		if melee_hit_enemy_ids.has(enemy_id):
			continue

		var to_enemy := enemy_body.global_position - global_position
		if to_enemy.length() > strike_range:
			continue
		if attack_direction.angle_to(to_enemy.normalized()) > max_angle_radians:
			continue

		enemy_node.call("take_damage", strike_damage)
		melee_hit_enemy_ids[enemy_id] = true
		if reward_rupture_wave:
			_apply_rupture_wave(enemy_body.global_position, strike_damage)
		did_hit = true

	if reward_razor_wind:
		var wind_context: Dictionary = upgrade_system.build_razor_wind_attack_context(melee_context, razor_wind_damage_ratio, razor_wind_range_scale, razor_wind_arc_degrees, attack_damage, attack_range)
		did_hit = _apply_razor_wind(attack_direction, wind_context) or did_hit

	return did_hit

func _apply_razor_wind(attack_direction: Vector2, wind_context: Dictionary) -> bool:
	var did_hit := false
	var wind_range := float(wind_context.get("range", attack_range * razor_wind_range_scale))
	var wind_arc_degrees := float(wind_context.get("arc_degrees", razor_wind_arc_degrees))
	var wind_half_arc := deg_to_rad(wind_arc_degrees * 0.5)
	var wind_damage := int(wind_context.get("damage", maxi(1, int(round(float(attack_damage) * razor_wind_damage_ratio)))))
	var wind_hit_enemy_ids: Dictionary = {}
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		if not enemy_node.has_method("take_damage"):
			continue
		var enemy_body := enemy_node as Node2D
		var enemy_id := enemy_body.get_instance_id()
		if wind_hit_enemy_ids.has(enemy_id):
			continue
		var to_enemy := enemy_body.global_position - global_position
		if to_enemy.length() > wind_range:
			continue
		if attack_direction.angle_to(to_enemy.normalized()) > wind_half_arc:
			continue
		enemy_node.call("take_damage", wind_damage)
		wind_hit_enemy_ids[enemy_id] = true
		if reward_rupture_wave:
			_apply_rupture_wave(enemy_body.global_position, wind_damage)
		did_hit = true
	return did_hit

func _apply_rupture_wave(epicenter: Vector2, source_damage: int) -> void:
	var wave_damage := maxi(1, int(round(float(source_damage) * rupture_wave_damage_ratio)))
	if player_feedback != null:
		player_feedback.play_world_ring(epicenter, rupture_wave_radius * 0.85, Color(0.44, 0.96, 1.0, 0.86), 0.2)
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		if not enemy_node.has_method("take_damage"):
			continue
		var enemy_body := enemy_node as Node2D
		if enemy_body.global_position.distance_to(epicenter) > rupture_wave_radius:
			continue
		enemy_node.call("take_damage", wave_damage)

func _restart_current_scene() -> void:
	if scene_restart_queued:
		return
	scene_restart_queued = true
	get_tree().call_deferred("reload_current_scene")

func _create_health_state() -> void:
	health_state = HEALTH_STATE_SCRIPT.new()
	health_state.health_changed.connect(_on_health_state_changed)
	health_state.died.connect(_on_health_state_died)
	add_child(health_state)
	health_state.setup(max_health)

func _create_player_feedback() -> void:
	player_feedback = PLAYER_FEEDBACK_SCRIPT.new()
	add_child(player_feedback)
	player_feedback.setup(max_health, _get_current_health())

func _on_health_state_changed(new_health: int, new_max_health: int) -> void:
	health_changed.emit(new_health, new_max_health)
	if player_feedback != null:
		player_feedback.update_health_bar(new_health, new_max_health)

func _on_health_state_died() -> void:
	died.emit()

func _get_current_health() -> int:
	if health_state == null:
		return max_health
	return health_state.current_health

func _draw() -> void:
	var attack_t := 1.0 - (attack_anim_time_left / attack_anim_duration) if attack_anim_duration > 0.0 else 1.0
	var attack_pulse := sin(attack_t * PI) * 1.9 if attack_anim_time_left > 0.0 else 0.0
	var speed_t := clampf(velocity.length() / maxf(1.0, max_speed), 0.0, 1.0)
	var body_radius := 14.0 + attack_pulse
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.RIGHT
	var side := Vector2(-facing.y, facing.x)
	var aura := 0.35 + speed_t * 0.5

	draw_circle(Vector2.ZERO, body_radius + 8.0 + speed_t * 2.0, Color(0.06, 0.24, 0.42, 0.16 + aura * 0.18))
	draw_circle(Vector2.ZERO, body_radius + 3.4, Color(0.03, 0.06, 0.09, 0.46))
	draw_circle(Vector2.ZERO, body_radius, Color(0.15, 0.76, 1.0, 1.0))
	draw_circle(Vector2.ZERO, body_radius * 0.74, Color(0.08, 0.45, 0.84, 1.0))
	draw_circle(Vector2.ZERO, body_radius * 0.42, Color(0.68, 0.92, 1.0, 0.9))

	if speed_t > 0.12:
		draw_arc(Vector2.ZERO, body_radius + 6.5, -1.4, 1.4, 30, Color(0.56, 0.89, 1.0, 0.26 + speed_t * 0.25), 2.0)

	var tip := facing * (body_radius + 9.0)
	var base_center := facing * (body_radius - 1.5)
	var fin := 4.9
	var pointer := PackedVector2Array([tip, base_center + side * fin, base_center - side * fin])
	draw_colored_polygon(pointer, Color(0.97, 0.99, 1.0, 0.98))

	var eye_pos := facing * (body_radius * 0.34) + side * 1.8
	draw_circle(eye_pos, 2.0, Color(0.98, 1.0, 1.0, 0.95))

	var wing_l := facing * (body_radius - 2.0) + side * 6.3
	var wing_r := facing * (body_radius - 2.0) - side * 6.3
	draw_line(wing_l, wing_l - facing * 6.0, Color(0.85, 0.96, 1.0, 0.72), 2.0)
	draw_line(wing_r, wing_r - facing * 6.0, Color(0.85, 0.96, 1.0, 0.72), 2.0)
	_draw_hard_reward_state()

func _draw_hard_reward_state() -> void:
	var t := float(Time.get_ticks_msec()) * 0.001

	if reward_razor_wind:
		var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.RIGHT
		var side := Vector2(-facing.y, facing.x)
		var p0 := facing * 18.0
		var p1 := facing * 33.0 + side * 5.0
		var p2 := facing * 33.0 - side * 5.0
		draw_colored_polygon(PackedVector2Array([p0, p1, p2]), Color(0.56, 1.0, 0.86, 0.8))
		draw_line(facing * 8.0, facing * 37.0, Color(0.86, 1.0, 0.93, 0.86), 1.8)

	if reward_execution_edge:
		var modulo := attack_combo_counter % execution_every
		var pips_lit := modulo
		if pips_lit == 0 and attack_combo_counter > 0:
			pips_lit = execution_every
		for i in range(execution_every):
			var x := -10.0 + float(i) * 10.0
			var lit := i < pips_lit
			var c := Color(1.0, 0.56, 0.26, 0.92) if lit else Color(0.48, 0.32, 0.25, 0.55)
			draw_circle(Vector2(x, -30.0), 2.4, c)

	if reward_rupture_wave:
		var pulse := 0.5 + 0.5 * sin(t * 4.2)
		draw_arc(Vector2.ZERO, 20.0 + pulse * 2.8, 0.0, TAU, 42, Color(0.46, 0.96, 1.0, 0.3 + pulse * 0.18), 1.8)
