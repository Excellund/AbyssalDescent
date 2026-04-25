extends CharacterBody2D

const HEALTH_STATE_SCRIPT := preload("res://scripts/health_state.gd")
const PLAYER_FEEDBACK_SCRIPT := preload("res://scripts/player_feedback.gd")
const UPGRADE_SYSTEM_SCRIPT := preload("res://scripts/upgrade_system.gd")
const ENEMY_BASE := preload("res://scripts/enemy_base.gd")

signal health_changed(current_health: int, max_health: int)
signal died

@export var max_speed: float = 220.0
@export var acceleration: float = 1400.0
@export var deceleration: float = 1800.0
@export var turn_boost: float = 1.25
@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.12
@export var dash_cooldown: float = 0.35
@export var dash_phase_release_duration: float = 0.1
@export var dash_overlap_clearance_duration: float = 0.08
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
var dash_phasing_active: bool = false
var dash_phase_release_left: float = 0.0
var dash_enemy_exceptions: Dictionary = {}
var body_radius_cache: float = 14.0
var queued_attack_after_dash: bool = false
var queued_attack_direction: Vector2 = Vector2.RIGHT
var iron_skin_armor: int = 0
var iron_skin_stacks: int = 0
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
	body_radius_cache = _get_body_radius_for(self, 14.0)
	upgrade_system = UPGRADE_SYSTEM_SCRIPT.new()
	add_child(upgrade_system)
	upgrade_system.initialize(self, null, null)
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
	_update_dash_phase_state(delta)
	_update_attack_cooldown(delta)
	_update_attack_lock(delta)
	_update_attack_animation(delta)
	_update_visual_facing_direction()
	_try_start_dash(direction)
	_try_attack_input()

	if _is_attack_locked():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _process_active_dash(delta):
		return

	_try_consume_queued_attack()
	if _is_attack_locked():
		velocity = Vector2.ZERO
		move_and_slide()
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
	dash_phase_release_left = maxf(dash_phase_release_left, dash_phase_release_duration)
	_set_dash_phasing(true)

func _try_attack_input() -> void:
	if not Input.is_action_just_pressed("attack"):
		return
	if dash_time_left > 0.0:
		queued_attack_after_dash = true
		queued_attack_direction = _get_mouse_attack_direction()
		return
	_try_execute_attack(_get_mouse_attack_direction())

func _try_consume_queued_attack() -> void:
	if not queued_attack_after_dash:
		return
	if dash_time_left > 0.0:
		return
	if dash_phase_release_left > 0.0:
		return
	_try_execute_attack(queued_attack_direction)
	if attack_cooldown_left > 0.0 or _is_attack_locked():
		return
	queued_attack_after_dash = false

func _try_execute_attack(attack_direction: Vector2) -> void:
	if _is_attack_locked():
		return
	if attack_cooldown_left > 0.0:
		return
	queued_attack_after_dash = false

	attack_cooldown_left = attack_cooldown
	attack_anim_time_left = attack_anim_duration
	player_feedback.play_attack_swing_sound()

	attack_combo_counter += 1
	var swing_color := ENEMY_BASE.COLOR_SWING_DEFAULT
	var execution_proc := false
	if reward_execution_edge and attack_combo_counter % execution_every == 0:
		execution_proc = true
		swing_color = ENEMY_BASE.COLOR_EXECUTION_PROC
	var melee_context: Dictionary = upgrade_system.build_melee_attack_context(attack_damage, attack_range, attack_arc_degrees, execution_proc, execution_damage_mult)
	attack_lock_time_left = attack_lock_duration
	attack_lock_direction = attack_direction
	visual_facing_direction = attack_direction
	velocity = Vector2.ZERO
	if reward_razor_wind:
		swing_color = ENEMY_BASE.COLOR_SWING_RAZOR_WIND if not execution_proc else ENEMY_BASE.COLOR_EXECUTION_PROC_EXTENDED
	player_feedback.play_attack_swing_visual(attack_direction, float(melee_context["range"]), float(melee_context["arc_degrees"]), swing_color)
	if reward_razor_wind:
		var wind_context: Dictionary = upgrade_system.build_razor_wind_attack_context(melee_context, razor_wind_damage_ratio, razor_wind_range_scale, razor_wind_arc_degrees, attack_damage, attack_range)
		var wind_range := float(wind_context["range"])
		var wind_color := ENEMY_BASE.COLOR_SWING_RAZOR_WIND_EXTENDED if not execution_proc else ENEMY_BASE.COLOR_EXECUTION_WIND_EXTENDED
		player_feedback.play_attack_swing_visual(attack_direction, wind_range, razor_wind_arc_degrees, wind_color, 0.14)
	if execution_proc:
		player_feedback.play_world_ring(global_position, 40.0, ENEMY_BASE.COLOR_EXECUTION_RING, 0.16)
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

func _update_dash_phase_state(delta: float) -> void:
	if dash_time_left > 0.0:
		dash_phase_release_left = maxf(dash_phase_release_left, dash_phase_release_duration)
	elif dash_phase_release_left > 0.0:
		dash_phase_release_left = maxf(0.0, dash_phase_release_left - delta)

	if dash_time_left <= 0.0 and not dash_phasing_active and _is_overlapping_enemy_body():
		dash_phase_release_left = maxf(dash_phase_release_left, dash_overlap_clearance_duration)

	var should_phase := dash_time_left > 0.0 or dash_phase_release_left > 0.0
	_set_dash_phasing(should_phase)
	if dash_phasing_active:
		_sync_enemy_collision_exceptions()

func _set_dash_phasing(enabled: bool) -> void:
	if enabled == dash_phasing_active:
		return
	dash_phasing_active = enabled
	if enabled:
		_sync_enemy_collision_exceptions()
		return
	_clear_enemy_collision_exceptions()

func _sync_enemy_collision_exceptions() -> void:
	var seen_ids: Dictionary = {}
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not (enemy is PhysicsBody2D):
			continue
		var enemy_body := enemy as PhysicsBody2D
		if enemy_body == self:
			continue
		var enemy_id := enemy_body.get_instance_id()
		seen_ids[enemy_id] = true
		if dash_enemy_exceptions.has(enemy_id):
			continue
		add_collision_exception_with(enemy_body)
		dash_enemy_exceptions[enemy_id] = enemy_body

	for enemy_id in dash_enemy_exceptions.keys():
		if seen_ids.has(enemy_id):
			continue
		var enemy_ref = dash_enemy_exceptions[enemy_id]
		if is_instance_valid(enemy_ref):
			var existing: PhysicsBody2D = enemy_ref as PhysicsBody2D
			if existing != null:
				remove_collision_exception_with(existing)
		dash_enemy_exceptions.erase(enemy_id)

func _clear_enemy_collision_exceptions() -> void:
	for enemy_id in dash_enemy_exceptions.keys():
		var enemy_ref = dash_enemy_exceptions[enemy_id]
		if is_instance_valid(enemy_ref):
			var enemy: PhysicsBody2D = enemy_ref as PhysicsBody2D
			if enemy != null:
				remove_collision_exception_with(enemy)
	dash_enemy_exceptions.clear()

func _is_overlapping_enemy_body() -> bool:
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		var enemy_body := enemy_node as Node2D
		var enemy_radius := _get_body_radius_for(enemy_body, 13.0)
		var combined_radius := body_radius_cache + enemy_radius
		if global_position.distance_to(enemy_body.global_position) < combined_radius - 0.5:
			return true
	return false

func _get_body_radius_for(node: Node, fallback: float) -> float:
	for child in node.get_children():
		if not (child is CollisionShape2D):
			continue
		var shape_node := child as CollisionShape2D
		if shape_node.shape is CircleShape2D:
			return maxf(1.0, (shape_node.shape as CircleShape2D).radius)
	return fallback

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

func take_damage(amount: int, damage_context: Dictionary = {}) -> void:
	if amount <= 0:
		return
	if dash_phasing_active and String(damage_context.get("source", "")) == "enemy_contact":
		return
	var reduced := maxi(1, amount - iron_skin_armor)
	var health_before := _get_current_health()
	health_state.take_damage(reduced)
	if _get_current_health() < health_before:
		player_feedback.play_damage_flash()
		player_feedback.play_impact_sound()

func heal(amount: int) -> void:
	if amount <= 0:
		return
	health_state.heal(amount)

func is_dead() -> bool:
	return health_state.is_dead()

func get_upgrade_stack_count(id: String) -> int:
	if id == "iron_skin":
		return iron_skin_stacks
	return 0

func apply_upgrade(boon_id: String) -> void:
	upgrade_system.apply_upgrade(boon_id)

func apply_trial_power(reward_id: String) -> void:
	upgrade_system.apply_trial_power(reward_id)

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
	return upgrade_system.get_trial_power_card_description(reward_id)

func get_trial_power_stack_count(reward_id: String) -> int:
	return upgrade_system.get_trial_power_stack_count(reward_id)

func _perform_melee_attack(attack_direction: Vector2, melee_context: Dictionary) -> bool:
	var did_hit := false
	var strike_damage := int(melee_context.get("damage", attack_damage))
	var strike_range := float(melee_context.get("range", attack_range))
	var strike_arc_degrees := float(melee_context.get("arc_degrees", attack_arc_degrees))
	var max_angle_radians := deg_to_rad(strike_arc_degrees * 0.5)

	var melee_hit_enemy_ids: Dictionary = {}
	var rupture_triggered_enemy_ids: Dictionary = {}

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
		if absf(attack_direction.angle_to(to_enemy.normalized())) > max_angle_radians:
			continue

		enemy_node.call("take_damage", strike_damage)
		melee_hit_enemy_ids[enemy_id] = true
		if reward_rupture_wave and not rupture_triggered_enemy_ids.has(enemy_id):
			rupture_triggered_enemy_ids[enemy_id] = true
			_apply_rupture_wave(enemy_body.global_position, strike_damage)
		did_hit = true

	if reward_razor_wind:
		var wind_context: Dictionary = upgrade_system.build_razor_wind_attack_context(melee_context, razor_wind_damage_ratio, razor_wind_range_scale, razor_wind_arc_degrees, attack_damage, attack_range)
		did_hit = _apply_razor_wind(attack_direction, wind_context, rupture_triggered_enemy_ids) or did_hit

	return did_hit

func _apply_razor_wind(attack_direction: Vector2, wind_context: Dictionary, rupture_triggered_enemy_ids: Dictionary = {}) -> bool:
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
		if absf(attack_direction.angle_to(to_enemy.normalized())) > wind_half_arc:
			continue
		enemy_node.call("take_damage", wind_damage)
		wind_hit_enemy_ids[enemy_id] = true
		if reward_rupture_wave and not rupture_triggered_enemy_ids.has(enemy_id):
			rupture_triggered_enemy_ids[enemy_id] = true
			_apply_rupture_wave(enemy_body.global_position, wind_damage)
		did_hit = true
	return did_hit

func _apply_rupture_wave(epicenter: Vector2, source_damage: int) -> void:
	var wave_damage := maxi(1, int(round(float(source_damage) * rupture_wave_damage_ratio)))
	if player_feedback != null:
		player_feedback.play_world_ring(epicenter, rupture_wave_radius * 0.85, ENEMY_BASE.COLOR_RUPTURE_WAVE_RING, 0.2)
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		if not enemy_node.has_method("take_damage"):
			continue
		var enemy_body := enemy_node as Node2D
		if enemy_body.global_position.distance_to(epicenter) > rupture_wave_radius:
			continue
		enemy_node.call("take_damage", wave_damage, {"is_ground_attack": true, "attack_type": "rupture_wave"})

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
	if dash_phasing_active:
		var t := float(Time.get_ticks_msec()) * 0.001
		var pulse := 0.5 + 0.5 * sin(t * 18.0)
		var phase_color := ENEMY_BASE.COLOR_PLAYER_DASH_PHASE
		phase_color.a = 0.24 + pulse * 0.22
		draw_arc(Vector2.ZERO, body_radius + 14.0 + pulse * 2.0, 0.0, TAU, 48, phase_color, 3.0)
		var streak_dir := dash_direction if dash_direction.length_squared() > 0.000001 else facing
		for i in range(3):
			var offset := -streak_dir * (8.0 + float(i) * 7.0)
			var alpha := 0.2 - float(i) * 0.05 + pulse * 0.06
			var streak_color := ENEMY_BASE.COLOR_PLAYER_DASH_STREAK
			streak_color.a = clampf(alpha, 0.04, 0.36)
			draw_circle(offset, body_radius * (1.0 - float(i) * 0.08), streak_color)

	draw_circle(Vector2.ZERO, body_radius + 8.0 + speed_t * 2.0, Color(ENEMY_BASE.COLOR_PLAYER_GLOW.r, ENEMY_BASE.COLOR_PLAYER_GLOW.g, ENEMY_BASE.COLOR_PLAYER_GLOW.b, 0.16 + aura * 0.18))
	draw_circle(Vector2.ZERO, body_radius + 3.4, ENEMY_BASE.COLOR_PLAYER_OUTER)
	draw_circle(Vector2.ZERO, body_radius, ENEMY_BASE.COLOR_PLAYER_BODY)
	draw_circle(Vector2.ZERO, body_radius * 0.74, ENEMY_BASE.COLOR_PLAYER_CORE)
	draw_circle(Vector2.ZERO, body_radius * 0.42, ENEMY_BASE.COLOR_PLAYER_LIGHT)

	if speed_t > 0.12:
		var arc_alpha := Color(ENEMY_BASE.COLOR_PLAYER_SPEED_ARC.r, ENEMY_BASE.COLOR_PLAYER_SPEED_ARC.g, ENEMY_BASE.COLOR_PLAYER_SPEED_ARC.b, 0.26 + speed_t * 0.25)
		draw_arc(Vector2.ZERO, body_radius + 6.5, -1.4, 1.4, 30, arc_alpha, 2.0)

	# Explicit state ring keeps player readable during dense enemy FX.
	if dash_phasing_active:
		draw_arc(Vector2.ZERO, body_radius + 10.5, 0.0, TAU, 40, Color(0.9, 1.0, 1.0, 0.8), 2.0)
	elif attack_anim_time_left > 0.0:
		draw_arc(Vector2.ZERO, body_radius + 9.0, -0.75, 0.75, 24, Color(1.0, 0.98, 0.78, 0.78), 2.2)

	var tip := facing * (body_radius + 9.0)
	var base_center := facing * (body_radius - 1.5)
	var fin := 4.9
	var pointer := PackedVector2Array([tip, base_center + side * fin, base_center - side * fin])
	draw_colored_polygon(pointer, ENEMY_BASE.COLOR_PLAYER_POINTER)

	var eye_pos := facing * (body_radius * 0.34) + side * 1.8
	draw_circle(eye_pos, 2.0, ENEMY_BASE.COLOR_PLAYER_EYE)

	var wing_l := facing * (body_radius - 2.0) + side * 6.3
	var wing_r := facing * (body_radius - 2.0) - side * 6.3
	draw_line(wing_l, wing_l - facing * 6.0, ENEMY_BASE.COLOR_PLAYER_WING, 2.0)
	draw_line(wing_r, wing_r - facing * 6.0, ENEMY_BASE.COLOR_PLAYER_WING, 2.0)
	_draw_hard_reward_state()

func _draw_hard_reward_state() -> void:
	var t := float(Time.get_ticks_msec()) * 0.001

	if reward_razor_wind:
		var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.RIGHT
		var side := Vector2(-facing.y, facing.x)
		var p0 := facing * 18.0
		var p1 := facing * 33.0 + side * 5.0
		var p2 := facing * 33.0 - side * 5.0
		draw_colored_polygon(PackedVector2Array([p0, p1, p2]), ENEMY_BASE.COLOR_RAZOR_WIND_TRIANGLE)
		draw_line(facing * 8.0, facing * 37.0, ENEMY_BASE.COLOR_RAZOR_WIND_LINE, 1.8)

	if reward_execution_edge:
		var modulo := attack_combo_counter % execution_every
		var pips_lit := modulo
		if pips_lit == 0 and attack_combo_counter > 0:
			pips_lit = execution_every
		for i in range(execution_every):
			var x := -10.0 + float(i) * 10.0
			var lit := i < pips_lit
			var c := ENEMY_BASE.COLOR_EXECUTION_PIP_LIT if lit else ENEMY_BASE.COLOR_EXECUTION_PIP_DARK
			draw_circle(Vector2(x, -30.0), 2.4, c)

	if reward_rupture_wave:
		var pulse := 0.5 + 0.5 * sin(t * 4.2)
		var rupture_color := ENEMY_BASE.COLOR_RUPTURE_WAVE_AURA
		rupture_color.a = 0.3 + pulse * 0.18
		draw_arc(Vector2.ZERO, 20.0 + pulse * 2.8, 0.0, TAU, 42, rupture_color, 1.8)
