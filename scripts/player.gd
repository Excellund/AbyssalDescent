extends CharacterBody2D

const HEALTH_STATE_SCRIPT := preload("res://scripts/health_state.gd")
const PLAYER_FEEDBACK_SCRIPT := preload("res://scripts/player_feedback.gd")
const UPGRADE_SYSTEM_SCRIPT := preload("res://scripts/upgrade_system.gd")
const POWER_REGISTRY_SCRIPT := preload("res://scripts/power_registry.gd")
const ENEMY_BASE := preload("res://scripts/enemy_base.gd")
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const RUN_SNAPSHOT_VERSION := 1
const RUN_SNAPSHOT_PROPERTIES := [
	"max_speed",
	"dash_cooldown",
	"attack_damage",
	"attack_range",
	"attack_arc_degrees",
	"first_strike_bonus_damage",
	"attack_cooldown",
	"attack_lock_duration",
	"battle_trance_move_speed_bonus",
	"battle_trance_duration",
	"battle_trance_active_left",
	"iron_skin_armor",
	"iron_skin_stacks",
	"reward_razor_wind",
	"reward_execution_edge",
	"reward_rupture_wave",
	"reward_aegis_field",
	"reward_hunters_snare",
	"razor_wind_stacks",
	"execution_edge_stacks",
	"rupture_wave_stacks",
	"aegis_field_stacks",
	"hunters_snare_stacks",
	"execution_every",
	"execution_damage_mult",
	"rupture_wave_radius",
	"rupture_wave_damage_ratio",
	"razor_wind_range_scale",
	"razor_wind_arc_degrees",
	"razor_wind_damage_ratio",
	"aegis_field_resist_ratio",
	"aegis_field_resist_duration",
	"aegis_field_pulse_radius",
	"aegis_field_slow_duration",
	"aegis_field_slow_mult",
	"aegis_field_cooldown",
	"aegis_field_active_left",
	"aegis_field_cooldown_left",
	"hunters_snare_bonus_damage",
	"hunters_snare_slow_duration",
	"hunters_snare_slow_mult",
	"reward_phantom_step",
	"reward_void_dash",
	"reward_static_wake",
	"phantom_step_stacks",
	"void_dash_stacks",
	"static_wake_stacks",
	"phantom_step_damage",
	"phantom_step_slow_duration",
	"void_dash_range_mult",
	"static_wake_damage",
	"static_wake_lifetime",
	"reward_storm_crown",
	"reward_wraithstep",
	"storm_crown_stacks",
	"wraithstep_stacks",
	"storm_crown_proc_every",
	"storm_crown_chain_targets",
	"storm_crown_chain_radius",
	"storm_crown_damage_ratio",
	"wraithstep_mark_duration",
	"wraithstep_dash_mark_radius",
	"wraithstep_mark_bonus_damage",
	"wraithstep_mark_splash_radius",
	"wraithstep_mark_splash_ratio"
]

signal health_changed(current_health: int, max_health: int)
signal died
signal damage_taken(raw_amount: int, final_amount: int, damage_context: Dictionary)

@export var max_speed: float = 220.0
@export var acceleration: float = 1400.0
@export var deceleration: float = 1800.0
@export var turn_boost: float = 1.25
@export var dash_speed: float = 720.0
@export var dash_distance: float = 175.0
@export var dash_cooldown: float = 0.42
@export var dash_phase_release_duration: float = 0.1
@export var dash_overlap_clearance_duration: float = 0.08
@export var max_health: int = 100
@export var attack_damage: int = 20
@export var attack_range: float = 78.0
@export var attack_arc_degrees: float = 130.0
@export var attack_cooldown: float = 0.28
@export var attack_lock_duration: float = 0.12
@export var battle_trance_duration: float = 1.25

var dash_time_left: float = 0.0
var dash_remaining_distance: float = 0.0
var dash_cooldown_left: float = 0.0
var last_move_direction: Vector2 = Vector2.RIGHT
var dash_direction: Vector2 = Vector2.ZERO
var attack_cooldown_left: float = 0.0
var first_strike_bonus_damage: int = 0
var health_state
var player_feedback
var upgrade_system
var attack_anim_time_left: float = 0.0
var attack_anim_duration: float = 0.12
var visual_facing_direction: Vector2 = Vector2.RIGHT
var attack_lock_time_left: float = 0.0
var attack_lock_direction: Vector2 = Vector2.RIGHT
var battle_trance_move_speed_bonus: float = 0.0
var battle_trance_active_left: float = 0.0
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
var reward_aegis_field: bool = false
var reward_hunters_snare: bool = false
var razor_wind_stacks: int = 0
var execution_edge_stacks: int = 0
var rupture_wave_stacks: int = 0
var aegis_field_stacks: int = 0
var hunters_snare_stacks: int = 0
var execution_every: int = 3
var execution_damage_mult: float = 2.6
var rupture_wave_radius: float = 82.0
var rupture_wave_damage_ratio: float = 0.44
var razor_wind_range_scale: float = 1.35
var razor_wind_arc_degrees: float = 24.0
var razor_wind_damage_ratio: float = 0.72
var aegis_field_resist_ratio: float = 0.18
var aegis_field_resist_duration: float = 1.1
var aegis_field_pulse_radius: float = 108.0
var aegis_field_slow_duration: float = 1.18
var aegis_field_slow_mult: float = 0.64
var aegis_field_cooldown: float = 2.8
var aegis_field_active_left: float = 0.0
var aegis_field_cooldown_left: float = 0.0
var hunters_snare_bonus_damage: int = 7
var hunters_snare_slow_duration: float = 0.67
var hunters_snare_slow_mult: float = 0.66

# Dash archetype trial powers
var reward_phantom_step: bool = false
var reward_void_dash: bool = false
var reward_static_wake: bool = false
var reward_storm_crown: bool = false
var reward_wraithstep: bool = false
var phantom_step_stacks: int = 0
var void_dash_stacks: int = 0
var static_wake_stacks: int = 0
var storm_crown_stacks: int = 0
var wraithstep_stacks: int = 0
# Phantom Step: damage and slow duration scale with stacks
var phantom_step_damage: int = 10
var phantom_step_slow_duration: float = 0.7
# Void Dash: extra distance multiplier and kill-reset tracking
var void_dash_range_mult: float = 1.42
# Static Wake: trail damage and lifetime
var static_wake_damage: int = 8
var static_wake_lifetime: float = 1.6
# Storm Crown: attack cadence proc that chains from the struck target
var storm_crown_proc_every: int = 4
var storm_crown_chain_targets: int = 2
var storm_crown_chain_radius: float = 112.0
var storm_crown_damage_ratio: float = 0.52
# Wraithstep: dash marks targets; marked hits consume for cleave damage
var wraithstep_mark_duration: float = 2.4
var wraithstep_dash_mark_radius: float = 42.0
var wraithstep_mark_bonus_damage: int = 12
var wraithstep_mark_splash_radius: float = 52.0
var wraithstep_mark_splash_ratio: float = 0.48
# Runtime state for dash powers
var phantom_step_hit_ids: Dictionary = {}
var phantom_step_ghost_positions: Array[Dictionary] = []
var phantom_step_ghost_emit_cd: float = 0.0
var static_wake_trails: Array[Dictionary] = []
var static_wake_trail_emit_cooldown: float = 0.0
var void_dash_reset_pulse_left: float = 0.0
var void_dash_reset_pulse_duration: float = 0.28
var storm_crown_hit_counter: int = 0
var storm_crown_discharge_flash_left: float = 0.0
var storm_crown_discharge_flash_duration: float = 0.24
var wraithstep_marked_enemy_expiry: Dictionary = {}
var polar_shift_dash_lockout_left: float = 0.0
var polar_shift_dash_lockout_duration: float = 0.0

# Objective mutators
var active_objective_mutators: Array[Dictionary] = []
var objective_mutator_damage_resist: float = 0.0
var objective_mutator_damage_mult: float = 0.0
var objective_mutator_aura_phase: float = 0.0
var combo_relay_stacks: int = 0
var combo_relay_stack_timer: float = 0.0
var combo_relay_stack_window: float = 2.8
var combo_relay_max_stacks: int = 4
var combo_relay_damage_per_stack: float = 0.05
var combo_relay_speed_per_stack: float = 0.05
var incoming_damage_taken_mult: float = 1.0
var incoming_contact_damage_mult: float = 1.0
var last_damage_event: Dictionary = {}

func _ready() -> void:
	body_radius_cache = _get_body_radius_for(self, 14.0)
	upgrade_system = UPGRADE_SYSTEM_SCRIPT.new()
	add_child(upgrade_system)
	upgrade_system.initialize(self, null, POWER_REGISTRY_SCRIPT.new())
	_create_health_state()
	_create_player_feedback()
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.visible = false
	queue_redraw()

func _physics_process(delta: float) -> void:
	objective_mutator_aura_phase += delta
	var direction := _read_movement_direction()
	_update_last_move_direction(direction)
	_update_dash_cooldown(delta)
	_update_dash_phase_state(delta)
	_update_attack_cooldown(delta)
	_update_attack_lock(delta)
	_update_battle_trance(delta)
	_update_attack_animation(delta)
	_update_visual_facing_direction()
	_update_aegis_field_state(delta)
	_update_static_wake_trails(delta)
	_update_void_dash_reset_pulse(delta)
	_update_polar_shift_dash_lockout(delta)
	_update_wraithstep_marks()
	_update_storm_crown_discharge(delta)
	_update_combo_relay_state(delta)
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
	if not active_objective_mutators.is_empty():
		queue_redraw()

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
	if polar_shift_dash_lockout_left > 0.0:
		return
	if not Input.is_action_just_pressed("dash"):
		return
	if dash_cooldown_left > 0.0:
		return

	dash_direction = direction if direction != Vector2.ZERO else last_move_direction
	var range_mult := void_dash_range_mult if reward_void_dash else 1.0
	dash_remaining_distance = dash_distance * range_mult
	var effective_dash_speed := maxf(1.0, dash_speed * range_mult)
	var effective_duration := dash_remaining_distance / effective_dash_speed
	dash_time_left = effective_duration
	dash_cooldown_left = dash_cooldown
	dash_phase_release_left = maxf(dash_phase_release_left, dash_phase_release_duration)
	phantom_step_hit_ids.clear()
	phantom_step_ghost_positions.clear()
	phantom_step_ghost_emit_cd = 0.0
	static_wake_trail_emit_cooldown = 0.0
	_set_dash_phasing(true)

func _try_attack_input() -> void:
	if not Input.is_action_just_pressed("attack"):
		return
	if _is_dash_active():
		queued_attack_after_dash = true
		queued_attack_direction = _get_mouse_attack_direction()
		return
	_try_execute_attack(_get_mouse_attack_direction())

func _try_consume_queued_attack() -> void:
	if not queued_attack_after_dash:
		return
	if _is_dash_active():
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

func _update_battle_trance(delta: float) -> void:
	if battle_trance_active_left <= 0.0:
		return
	battle_trance_active_left = maxf(0.0, battle_trance_active_left - delta)

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
	if dash_remaining_distance <= 0.0:
		return false

	var dash_start := global_position
	dash_time_left = maxf(0.0, dash_time_left - delta)
	var dash_speed_mult := void_dash_range_mult if reward_void_dash else 1.0
	var max_step := maxf(0.0, dash_speed * dash_speed_mult * delta)
	var desired_step := minf(dash_remaining_distance, max_step)
	if desired_step <= 0.0:
		dash_time_left = 0.0
		dash_remaining_distance = 0.0
		return false
	velocity = dash_direction * (desired_step / maxf(delta, 0.0001))
	move_and_slide()
	var dash_end := global_position
	var moved := dash_start.distance_to(dash_end)
	if moved <= 0.001:
		dash_time_left = 0.0
		dash_remaining_distance = 0.0
		velocity = Vector2.ZERO
		return false
	dash_remaining_distance = maxf(0.0, dash_remaining_distance - moved)
	if dash_remaining_distance <= 0.001:
		dash_time_left = 0.0
		dash_remaining_distance = 0.0
		# End dash with a small consistent carry velocity to avoid occasional hard-brake feel.
		velocity = dash_direction * minf(max_speed * 0.9, dash_speed * 0.22)

	if reward_phantom_step:
		_apply_phantom_step_during_dash()
		# Ghost afterimage emission
		phantom_step_ghost_emit_cd = maxf(0.0, phantom_step_ghost_emit_cd - delta)
		if phantom_step_ghost_emit_cd <= 0.0:
			phantom_step_ghost_positions.append({"pos": global_position, "life": 0.14})
			phantom_step_ghost_emit_cd = 0.03
		var gi := phantom_step_ghost_positions.size() - 1
		while gi >= 0:
			phantom_step_ghost_positions[gi]["life"] -= delta
			if float(phantom_step_ghost_positions[gi]["life"]) <= 0.0:
				phantom_step_ghost_positions.remove_at(gi)
			gi -= 1
		queue_redraw()

	if reward_static_wake:
		static_wake_trail_emit_cooldown = maxf(0.0, static_wake_trail_emit_cooldown - delta)
		if static_wake_trail_emit_cooldown <= 0.0:
			static_wake_trails.append({"pos": global_position, "life": static_wake_lifetime})
			static_wake_trail_emit_cooldown = 0.035
		queue_redraw()

	if reward_wraithstep:
		_apply_wraithstep_marks_during_dash(dash_start, dash_end)

	return true

func _update_dash_phase_state(delta: float) -> void:
	if _is_dash_active():
		dash_phase_release_left = maxf(dash_phase_release_left, dash_phase_release_duration)
	elif dash_phase_release_left > 0.0:
		dash_phase_release_left = maxf(0.0, dash_phase_release_left - delta)

	if not _is_dash_active() and not dash_phasing_active and _is_overlapping_enemy_body():
		dash_phase_release_left = maxf(dash_phase_release_left, dash_overlap_clearance_duration)

	var should_phase := _is_dash_active() or dash_phase_release_left > 0.0
	_set_dash_phasing(should_phase)
	if dash_phasing_active:
		_sync_enemy_collision_exceptions()

func _is_dash_active() -> bool:
	return dash_remaining_distance > 0.001

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
	var trance_speed_bonus := 0.0
	if battle_trance_active_left > 0.0:
		var trance_ratio := battle_trance_move_speed_bonus
		# Backward compatibility for snapshots that stored pre-percentage flat values.
		if trance_ratio > 2.0:
			trance_ratio = trance_ratio / maxf(1.0, max_speed)
		trance_ratio = clampf(trance_ratio, 0.0, 1.5)
		trance_speed_bonus = max_speed * trance_ratio
	var combo_relay_speed_bonus := max_speed * combo_relay_speed_per_stack * float(combo_relay_stacks)
	var target_velocity := direction * (max_speed + trance_speed_bonus + combo_relay_speed_bonus)
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

func _update_void_dash_reset_pulse(delta: float) -> void:
	if void_dash_reset_pulse_left <= 0.0:
		return
	void_dash_reset_pulse_left = maxf(0.0, void_dash_reset_pulse_left - delta)
	queue_redraw()

func _update_polar_shift_dash_lockout(delta: float) -> void:
	if polar_shift_dash_lockout_left <= 0.0:
		return
	polar_shift_dash_lockout_left = maxf(0.0, polar_shift_dash_lockout_left - delta)
	queue_redraw()

func _update_storm_crown_discharge(delta: float) -> void:
	if storm_crown_discharge_flash_left <= 0.0:
		return
	storm_crown_discharge_flash_left = maxf(0.0, storm_crown_discharge_flash_left - delta)
	queue_redraw()

func _update_aegis_field_state(delta: float) -> void:
	if aegis_field_active_left > 0.0:
		aegis_field_active_left = maxf(0.0, aegis_field_active_left - delta)
		queue_redraw()
	if aegis_field_cooldown_left > 0.0:
		aegis_field_cooldown_left = maxf(0.0, aegis_field_cooldown_left - delta)

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
	var raw_amount := amount
	var reduced := maxi(1, amount - iron_skin_armor)
	var total_resist := objective_mutator_damage_resist
	if reward_aegis_field and aegis_field_active_left > 0.0:
		total_resist += aegis_field_resist_ratio
	total_resist = clampf(total_resist, 0.0, 0.92)
	reduced = int(ceil(float(reduced) * (1.0 - total_resist)))
	reduced = int(ceil(float(reduced) * incoming_damage_taken_mult))
	if String(damage_context.get("source", "")) == "enemy_contact":
		reduced = int(ceil(float(reduced) * incoming_contact_damage_mult))
	reduced = maxi(1, reduced)
	var health_before := _get_current_health()
	health_state.take_damage(reduced)
	if _get_current_health() < health_before:
		var context_copy := damage_context.duplicate(true)
		context_copy["source"] = String(context_copy.get("source", "unknown"))
		context_copy["ability"] = String(context_copy.get("ability", "unknown"))
		context_copy["raw_amount"] = raw_amount
		context_copy["final_amount"] = reduced
		context_copy["health_before"] = health_before
		context_copy["health_after"] = _get_current_health()
		context_copy["unix_time"] = int(Time.get_unix_time_from_system())
		last_damage_event = context_copy
		damage_taken.emit(raw_amount, reduced, context_copy)
		_trigger_aegis_field()
		player_feedback.play_damage_flash()
		player_feedback.play_impact_sound()

func get_last_damage_event() -> Dictionary:
	return last_damage_event.duplicate(true)

func set_incoming_damage_taken_mult(mult: float) -> void:
	incoming_damage_taken_mult = clampf(mult, 0.25, 4.0)

func set_incoming_contact_damage_mult(mult: float) -> void:
	incoming_contact_damage_mult = clampf(mult, 0.25, 4.0)

func heal(amount: int) -> void:
	if amount <= 0:
		return
	health_state.heal(amount)

func play_rest_site_heal_feedback() -> void:
	if player_feedback == null:
		return
	player_feedback.play_rest_site_heal(global_position)

func is_dead() -> bool:
	return health_state.is_dead()

func get_upgrade_stack_count(id: String) -> int:
	if is_instance_valid(upgrade_system):
		return int(upgrade_system.get_upgrade_stack_count(id))
	if id == "iron_skin":
		return iron_skin_stacks
	return 0

func apply_upgrade(boon_id: String) -> void:
	upgrade_system.apply_upgrade(boon_id)

func set_power_registry(registry: Node) -> void:
	if not is_instance_valid(upgrade_system):
		return
	upgrade_system.initialize(self, null, registry)

func build_run_snapshot() -> Dictionary:
	var properties: Dictionary = {}
	for property_name in RUN_SNAPSHOT_PROPERTIES:
		properties[property_name] = get(property_name)
	var trial_stacks: Dictionary = {}
	if is_instance_valid(upgrade_system):
		var raw_stacks: Variant = upgrade_system.get("trial_power_stacks")
		if raw_stacks is Dictionary:
			trial_stacks = (raw_stacks as Dictionary).duplicate(true)
	var upgrade_stacks: Dictionary = {}
	if is_instance_valid(upgrade_system):
		var raw_upgrade_stacks: Variant = upgrade_system.get("upgrade_stacks")
		if raw_upgrade_stacks is Dictionary:
			upgrade_stacks = (raw_upgrade_stacks as Dictionary).duplicate(true)
	return {
		"version": RUN_SNAPSHOT_VERSION,
		"current_health": _get_current_health(),
		"properties": properties,
		"active_objective_mutators": get_active_objective_mutators(),
		"trial_power_stacks": trial_stacks,
		"upgrade_stacks": upgrade_stacks
	}

func apply_run_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var properties := snapshot.get("properties", {}) as Dictionary
	for property_name in properties.keys():
		set(String(property_name), properties[property_name])
	var mutators := snapshot.get("active_objective_mutators", []) as Array
	active_objective_mutators.clear()
	for mutator_entry in mutators:
		if mutator_entry is Dictionary:
			active_objective_mutators.append((mutator_entry as Dictionary).duplicate(true))
	_recalculate_objective_mutator_totals()
	var trial_stacks := snapshot.get("trial_power_stacks", {}) as Dictionary
	if is_instance_valid(upgrade_system):
		upgrade_system.set("trial_power_stacks", trial_stacks.duplicate(true))
	var upgrade_stacks := snapshot.get("upgrade_stacks", {}) as Dictionary
	if is_instance_valid(upgrade_system):
		upgrade_system.set("upgrade_stacks", upgrade_stacks.duplicate(true))
	if is_instance_valid(health_state):
		health_state.max_health = max_health
		health_state.set_health(int(snapshot.get("current_health", max_health)))

	dash_time_left = 0.0
	dash_remaining_distance = 0.0
	dash_cooldown_left = 0.0
	attack_cooldown_left = 0.0
	attack_anim_time_left = 0.0
	attack_lock_time_left = 0.0
	dash_phase_release_left = 0.0
	dash_enemy_exceptions.clear()
	queued_attack_after_dash = false
	phantom_step_hit_ids.clear()
	phantom_step_ghost_positions.clear()
	static_wake_trails.clear()
	void_dash_reset_pulse_left = 0.0
	storm_crown_hit_counter = 0
	storm_crown_discharge_flash_left = 0.0
	wraithstep_marked_enemy_expiry.clear()
	combo_relay_stacks = 0
	combo_relay_stack_timer = 0.0
	_set_dash_phasing(false)
	velocity = Vector2.ZERO
	queue_redraw()

func apply_trial_power(reward_id: String) -> void:
	upgrade_system.apply_trial_power(reward_id)

func apply_objective_mutator(mutator_data: Dictionary) -> void:
	if mutator_data.is_empty():
		return
	var applied_mutator := mutator_data.duplicate(true)
	var default_duration := int(applied_mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_DURATION_ENCOUNTERS, 3))
	var duration := maxi(1, default_duration)
	applied_mutator[ENCOUNTER_CONTRACTS.MUTATOR_KEY_DURATION_ENCOUNTERS] = duration
	applied_mutator[ENCOUNTER_CONTRACTS.MUTATOR_KEY_REMAINING_ENCOUNTERS] = duration
	var policy := ENCOUNTER_CONTRACTS.mutator_stack_policy(applied_mutator)
	var stack_limit := ENCOUNTER_CONTRACTS.mutator_stack_limit(applied_mutator)
	var applied_id := ENCOUNTER_CONTRACTS.mutator_id(applied_mutator)
	var icon_shape := String(applied_mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID, ""))
	var mutator_name := String(applied_mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME, ""))
	var matching_indices: Array[int] = []
	for i in range(active_objective_mutators.size()):
		var existing := active_objective_mutators[i] as Dictionary
		var existing_id := ENCOUNTER_CONTRACTS.mutator_id(existing)
		var existing_icon := String(existing.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID, ""))
		var existing_name := String(existing.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME, ""))
		if (not applied_id.is_empty() and existing_id == applied_id) or (not icon_shape.is_empty() and existing_icon == icon_shape) or (not mutator_name.is_empty() and existing_name == mutator_name):
			matching_indices.append(i)
	if policy == "stack":
		if matching_indices.size() >= stack_limit and not matching_indices.is_empty():
			active_objective_mutators[matching_indices[0]] = applied_mutator
		else:
			active_objective_mutators.append(applied_mutator)
	else:
		if not matching_indices.is_empty():
			active_objective_mutators[matching_indices[0]] = applied_mutator
		else:
			active_objective_mutators.append(applied_mutator)
	if policy == "replace" and matching_indices.size() > 1:
		for i in range(matching_indices.size() - 1, 0, -1):
			active_objective_mutators.remove_at(matching_indices[i])
	if active_objective_mutators.size() > 8:
		active_objective_mutators = active_objective_mutators.slice(active_objective_mutators.size() - 8, active_objective_mutators.size())
	if policy == "refresh" and active_objective_mutators.size() > 1 and not applied_id.is_empty():
		for i in range(active_objective_mutators.size() - 2, -1, -1):
			var existing := active_objective_mutators[i] as Dictionary
			if ENCOUNTER_CONTRACTS.mutator_id(existing) == applied_id:
				active_objective_mutators.remove_at(i)
	if active_objective_mutators.is_empty():
		active_objective_mutators.append(applied_mutator)
	_recalculate_objective_mutator_totals()
	queue_redraw()

func tick_objective_mutators_for_encounter() -> void:
	if active_objective_mutators.is_empty():
		return
	for i in range(active_objective_mutators.size() - 1, -1, -1):
		var mutator := active_objective_mutators[i]
		var remaining := int(mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_REMAINING_ENCOUNTERS, 0))
		remaining -= 1
		if remaining < 0:
			active_objective_mutators.remove_at(i)
			continue
		mutator[ENCOUNTER_CONTRACTS.MUTATOR_KEY_REMAINING_ENCOUNTERS] = remaining
		active_objective_mutators[i] = mutator
	_recalculate_objective_mutator_totals()
	queue_redraw()

func get_active_objective_mutators() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mutator in active_objective_mutators:
		var copied := (mutator as Dictionary).duplicate(true)
		if ENCOUNTER_CONTRACTS.mutator_id(copied) == "combo_relay":
			copied["runtime_combo_relay_stacks"] = combo_relay_stacks
			copied["runtime_combo_relay_max_stacks"] = combo_relay_max_stacks
			copied["runtime_combo_relay_stack_timer"] = combo_relay_stack_timer
		result.append(copied)
	return result

func get_active_enemy_objective_mutators() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in active_objective_mutators:
		var mutator := entry as Dictionary
		if not ENCOUNTER_CONTRACTS.mutator_affects_scope(mutator, "enemy"):
			continue
		result.append(mutator.duplicate(true))
	return result

func _mutator_effect_or_legacy(mutator: Dictionary, effect_type: String, legacy_key: String) -> float:
	for effect in ENCOUNTER_CONTRACTS.mutator_effects(mutator):
		if String(effect.get("type", "")).strip_edges().to_lower() != effect_type:
			continue
		return float(effect.get("value", 0.0))
	return float(mutator.get(legacy_key, 0.0))

func _recalculate_objective_mutator_totals() -> void:
	objective_mutator_damage_resist = 0.0
	objective_mutator_damage_mult = 0.0
	var stacks_by_id: Dictionary = {}
	for entry in active_objective_mutators:
		var mutator := entry as Dictionary
		if not ENCOUNTER_CONTRACTS.mutator_affects_scope(mutator, "player"):
			continue
		var mutator_id := ENCOUNTER_CONTRACTS.mutator_id(mutator)
		var stack_index := int(stacks_by_id.get(mutator_id, 0))
		var stack_falloff := ENCOUNTER_CONTRACTS.mutator_stack_falloff(mutator)
		var stack_scale := pow(stack_falloff, float(stack_index))
		stacks_by_id[mutator_id] = stack_index + 1
		objective_mutator_damage_resist += _mutator_effect_or_legacy(mutator, "player_damage_resist", ENCOUNTER_CONTRACTS.MUTATOR_KEY_PLAYER_DAMAGE_RESIST) * stack_scale
		objective_mutator_damage_mult += _mutator_effect_or_legacy(mutator, "player_damage_mult", ENCOUNTER_CONTRACTS.MUTATOR_KEY_PLAYER_DAMAGE_MULT) * stack_scale
	objective_mutator_damage_resist = clampf(objective_mutator_damage_resist, 0.0, 0.85)

func _apply_objective_mutator_damage_mult(base_damage: int) -> int:
	var total_damage_mult := objective_mutator_damage_mult + combo_relay_damage_per_stack * float(combo_relay_stacks)
	if total_damage_mult <= 0.0:
		return base_damage
	return maxi(1, int(ceil(float(base_damage) * (1.0 + total_damage_mult))))

func _trigger_aegis_field() -> void:
	if not reward_aegis_field:
		return
	if aegis_field_cooldown_left > 0.0:
		return
	aegis_field_active_left = aegis_field_resist_duration
	aegis_field_cooldown_left = aegis_field_cooldown
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		var enemy_body := enemy_node as Node2D
		if global_position.distance_to(enemy_body.global_position) > aegis_field_pulse_radius:
			continue
		enemy_node.apply_slow(aegis_field_slow_duration, aegis_field_slow_mult)
	if player_feedback != null:
		player_feedback.play_world_ring(global_position, aegis_field_pulse_radius, Color(0.62, 0.98, 1.0, 0.92), 0.22)
		player_feedback.play_world_ring(global_position, aegis_field_pulse_radius * 0.64, Color(0.88, 1.0, 1.0, 0.78), 0.16)
	queue_redraw()

func apply_power_for_test(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	if id.is_empty():
		return false

	var hard_ids := {
		"razor_wind": true,
		"execution_edge": true,
		"rupture_wave": true,
		"aegis_field": true,
		"hunters_snare": true,
		"phantom_step": true,
		"reaper_step": true,
		"static_wake": true,
		"storm_crown": true,
		"wraithstep": true
	}
	if hard_ids.has(id):
		apply_trial_power(id)
		return true

	var boon_ids := {
		"first_strike": true,
		"heavy_blow": true,
		"wide_arc": true,
		"long_reach": true,
		"fleet_foot": true,
		"blink_dash": true,
		"iron_skin": true,
		"battle_trance": true,
		"surge_step": true,
		"heartstone": true
	}
	if boon_ids.has(id):
		apply_upgrade(id)
		return true

	return false

func get_trial_power_card_desc(reward_id: String) -> String:
	return upgrade_system.get_trial_power_card_description(reward_id)

func get_upgrade_card_desc(boon_id: String) -> String:
	return upgrade_system.get_upgrade_card_description(boon_id)

func get_trial_power_stack_count(reward_id: String) -> int:
	return upgrade_system.get_trial_power_stack_count(reward_id)

func _perform_melee_attack(attack_direction: Vector2, melee_context: Dictionary) -> bool:
	var did_hit := false
	var strike_damage := int(melee_context.get("damage", attack_damage))
	strike_damage = _apply_objective_mutator_damage_mult(strike_damage)
	var strike_range := float(melee_context.get("range", attack_range))
	var strike_arc_degrees := float(melee_context.get("arc_degrees", attack_arc_degrees))
	var max_angle_radians := deg_to_rad(strike_arc_degrees * 0.5)

	var melee_hit_enemy_ids: Dictionary = {}
	var rupture_triggered_enemy_ids: Dictionary = {}
	var rupture_hit_enemy_ids: Dictionary = {}

	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		if not DAMAGEABLE.can_take_damage(enemy_node):
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

		var final_strike_damage := strike_damage + _get_hunters_snare_bonus_damage(enemy_node)
		final_strike_damage += _get_first_strike_bonus_damage(enemy_node)
		final_strike_damage += _consume_wraithstep_mark(enemy_node, enemy_body.global_position, strike_damage)
		DAMAGEABLE.apply_damage(enemy_node, final_strike_damage)
		_apply_hunters_snare(enemy_node)
		melee_hit_enemy_ids[enemy_id] = true
		if reward_storm_crown:
			_apply_storm_crown_hit(enemy_body.global_position, enemy_id, final_strike_damage)
		if reward_rupture_wave and not rupture_triggered_enemy_ids.has(enemy_id):
			rupture_triggered_enemy_ids[enemy_id] = true
			_apply_rupture_wave(enemy_body.global_position, final_strike_damage, rupture_hit_enemy_ids)
		did_hit = true

	if reward_razor_wind:
		var wind_context: Dictionary = upgrade_system.build_razor_wind_attack_context(melee_context, razor_wind_damage_ratio, razor_wind_range_scale, razor_wind_arc_degrees, attack_damage, attack_range)
		var wind_damage := int(wind_context.get("damage", maxi(1, int(round(float(attack_damage) * razor_wind_damage_ratio)))))
		wind_damage = _apply_objective_mutator_damage_mult(wind_damage)
		wind_context["damage"] = wind_damage
		did_hit = _apply_razor_wind(attack_direction, wind_context, rupture_triggered_enemy_ids, rupture_hit_enemy_ids) or did_hit
	if did_hit:
		_trigger_battle_trance()

	return did_hit

func _apply_razor_wind(attack_direction: Vector2, wind_context: Dictionary, rupture_triggered_enemy_ids: Dictionary = {}, rupture_hit_enemy_ids: Dictionary = {}) -> bool:
	var did_hit := false
	var wind_range := float(wind_context.get("range", attack_range * razor_wind_range_scale))
	var wind_arc_degrees := float(wind_context.get("arc_degrees", razor_wind_arc_degrees))
	var wind_half_arc := deg_to_rad(wind_arc_degrees * 0.5)
	var wind_damage := int(wind_context.get("damage", maxi(1, int(round(float(attack_damage) * razor_wind_damage_ratio)))))
	var wind_hit_enemy_ids: Dictionary = {}
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		if not DAMAGEABLE.can_take_damage(enemy_node):
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
		var final_wind_damage := wind_damage + _get_hunters_snare_bonus_damage(enemy_node)
		final_wind_damage += _get_first_strike_bonus_damage(enemy_node)
		final_wind_damage += _consume_wraithstep_mark(enemy_node, enemy_body.global_position, wind_damage)
		DAMAGEABLE.apply_damage(enemy_node, final_wind_damage)
		_apply_hunters_snare(enemy_node)
		wind_hit_enemy_ids[enemy_id] = true
		if reward_storm_crown:
			_apply_storm_crown_hit(enemy_body.global_position, enemy_id, final_wind_damage)
		if reward_rupture_wave and not rupture_triggered_enemy_ids.has(enemy_id):
			rupture_triggered_enemy_ids[enemy_id] = true
			_apply_rupture_wave(enemy_body.global_position, final_wind_damage, rupture_hit_enemy_ids)
		did_hit = true
	return did_hit

func _get_hunters_snare_bonus_damage(enemy_node: Object) -> int:
	if not reward_hunters_snare:
		return 0
	if not is_instance_valid(enemy_node):
		return 0
	return hunters_snare_bonus_damage if bool(enemy_node.is_slowed()) else 0

func _apply_hunters_snare(enemy_node: Object) -> void:
	if not reward_hunters_snare:
		return
	if not is_instance_valid(enemy_node):
		return
	enemy_node.apply_slow(hunters_snare_slow_duration, hunters_snare_slow_mult)

func _trigger_battle_trance() -> void:
	if battle_trance_move_speed_bonus <= 0.0:
		return
	battle_trance_active_left = battle_trance_duration

func _get_first_strike_bonus_damage(enemy_node: Object) -> int:
	if first_strike_bonus_damage <= 0:
		return 0
	if not is_instance_valid(enemy_node):
		return 0
	var enemy_health_state: Variant = enemy_node.get("health_state")
	if enemy_health_state == null or not is_instance_valid(enemy_health_state):
		return 0
	var enemy_max := int(enemy_health_state.get("max_health"))
	if enemy_max <= 0:
		return 0
	var enemy_current := int(enemy_health_state.get("current_health"))
	if float(enemy_current) / float(enemy_max) >= 0.8:
		return first_strike_bonus_damage
	return 0

func clear_lingering_combat_effects() -> void:
	phantom_step_hit_ids.clear()
	phantom_step_ghost_positions.clear()
	phantom_step_ghost_emit_cd = 0.0
	static_wake_trails.clear()
	static_wake_trail_emit_cooldown = 0.0
	wraithstep_marked_enemy_expiry.clear()
	storm_crown_discharge_flash_left = 0.0
	void_dash_reset_pulse_left = 0.0
	queue_redraw()

func _apply_rupture_wave(epicenter: Vector2, source_damage: int, rupture_hit_enemy_ids: Dictionary = {}) -> void:
	var wave_damage := maxi(1, int(round(float(source_damage) * rupture_wave_damage_ratio)))
	wave_damage = _apply_objective_mutator_damage_mult(wave_damage)
	if player_feedback != null:
		player_feedback.play_world_ring(epicenter, rupture_wave_radius * 0.85, ENEMY_BASE.COLOR_RUPTURE_WAVE_RING, 0.2)
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		if not DAMAGEABLE.can_take_damage(enemy_node):
			continue
		var enemy_body := enemy_node as Node2D
		if enemy_body.global_position.distance_to(epicenter) > rupture_wave_radius:
			continue
		var enemy_id := enemy_body.get_instance_id()
		# Skip if this enemy already took rupture damage from a previous rupture in this swing
		if rupture_hit_enemy_ids.has(enemy_id):
			continue
		# Mark this enemy as hit by rupture, preventing chain damage
		rupture_hit_enemy_ids[enemy_id] = true
		DAMAGEABLE.apply_damage(enemy_node, wave_damage, {"is_ground_attack": true, "attack_type": "rupture_wave"})


func _update_wraithstep_marks() -> void:
	if wraithstep_marked_enemy_expiry.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for enemy_id in wraithstep_marked_enemy_expiry.keys():
		var entry := wraithstep_marked_enemy_expiry[enemy_id] as Dictionary
		if float(entry.get("expiry", 0.0)) <= now or not is_instance_valid(entry.get("node")):
			wraithstep_marked_enemy_expiry.erase(enemy_id)
	queue_redraw()


func _apply_wraithstep_marks_during_dash(dash_start: Vector2, dash_end: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var expiry := now + wraithstep_mark_duration
	var effective_mark_radius := wraithstep_dash_mark_radius + 12.0
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		if not DAMAGEABLE.can_take_damage(enemy_node):
			continue
		var enemy_body := enemy_node as Node2D
		var nearest := Geometry2D.get_closest_point_to_segment(enemy_body.global_position, dash_start, dash_end)
		if enemy_body.global_position.distance_to(nearest) > effective_mark_radius:
			continue
		var enemy_id := enemy_body.get_instance_id()
		var is_new_mark := not wraithstep_marked_enemy_expiry.has(enemy_id)
		wraithstep_marked_enemy_expiry[enemy_id] = {"expiry": expiry, "node": enemy_body}
		if is_new_mark and player_feedback != null:
			player_feedback.play_world_ring(enemy_body.global_position, 18.0, Color(0.72, 0.96, 1.0, 0.82), 0.18)
			player_feedback.play_world_ring(enemy_body.global_position, 30.0, Color(0.56, 0.88, 1.0, 0.42), 0.26)
	queue_redraw()


func _consume_wraithstep_mark(enemy_node: Object, hit_position: Vector2, base_damage: int) -> int:
	if not reward_wraithstep:
		return 0
	if not is_instance_valid(enemy_node):
		return 0
	var enemy_id := enemy_node.get_instance_id()
	if not wraithstep_marked_enemy_expiry.has(enemy_id):
		return 0
	wraithstep_marked_enemy_expiry.erase(enemy_id)
	var splash_source_damage := maxi(1, int(round(float(base_damage) * wraithstep_mark_splash_ratio)))
	var chain_damage_scale := minf(1.0, 0.72 + float(maxi(0, wraithstep_stacks - 1)) * 0.1)
	var chain_damage := maxi(1, int(round(float(splash_source_damage) * chain_damage_scale)))
	_apply_wraithstep_splash(hit_position, splash_source_damage, enemy_id)
	_apply_wraithstep_chain(hit_position, enemy_id, chain_damage)
	if player_feedback != null:
		# Tight core burst
		player_feedback.play_world_ring(hit_position, 16.0, Color(1.0, 1.0, 1.0, 0.92), 0.08)
		# Main cleave ring
		player_feedback.play_world_ring(hit_position, wraithstep_mark_splash_radius, Color(0.72, 0.96, 1.0, 0.86), 0.22)
		# Outer drift
		player_feedback.play_world_ring(hit_position, wraithstep_mark_splash_radius * 1.35, Color(0.48, 0.78, 1.0, 0.38), 0.32)
		# Inner fill ring for impact
		player_feedback.play_world_ring(hit_position, wraithstep_mark_splash_radius * 0.46, Color(0.88, 0.98, 1.0, 0.62), 0.12)
	queue_redraw()
	return wraithstep_mark_bonus_damage


func _apply_wraithstep_chain(chain_origin: Vector2, consumed_enemy_id: int, chain_damage: int) -> void:
	if wraithstep_marked_enemy_expiry.is_empty():
		return
	var propagated_ids: Dictionary = {consumed_enemy_id: true}
	var pending_epicenters: Array[Vector2] = [chain_origin]
	while not pending_epicenters.is_empty():
		var epicenter: Vector2 = pending_epicenters[0]
		pending_epicenters.remove_at(0)
		var triggered_in_wave: Array[Dictionary] = []
		for enemy_id in wraithstep_marked_enemy_expiry.keys():
			if propagated_ids.has(enemy_id):
				continue
			var entry := wraithstep_marked_enemy_expiry[enemy_id] as Dictionary
			var enemy_node: Variant = entry.get("node")
			if not is_instance_valid(enemy_node):
				continue
			var enemy_ref := enemy_node as Node2D
			if enemy_ref == null:
				continue
			if not DAMAGEABLE.can_take_damage(enemy_ref):
				continue
			if enemy_ref.global_position.distance_to(epicenter) > wraithstep_mark_splash_radius:
				continue
			triggered_in_wave.append({"id": int(enemy_id), "node": enemy_ref})

		for triggered_entry in triggered_in_wave:
			var triggered_enemy_id := int(triggered_entry["id"])
			var triggered_enemy := triggered_entry["node"] as Node2D
			wraithstep_marked_enemy_expiry.erase(triggered_enemy_id)
			propagated_ids[triggered_enemy_id] = true
			DAMAGEABLE.apply_damage(triggered_enemy, chain_damage)
			pending_epicenters.append(triggered_enemy.global_position)
			if player_feedback != null:
				player_feedback.play_wraithstep_chain_echo(epicenter, triggered_enemy.global_position)
				player_feedback.play_world_ring(triggered_enemy.global_position, wraithstep_mark_splash_radius * 0.5, Color(0.72, 0.94, 1.0, 0.64), 0.14)


func _apply_wraithstep_splash(epicenter: Vector2, splash_damage: int, excluded_enemy_id: int) -> void:
	var final_splash_damage := _apply_objective_mutator_damage_mult(splash_damage)
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		if not DAMAGEABLE.can_take_damage(enemy_node):
			continue
		var enemy_body := enemy_node as Node2D
		var enemy_id := enemy_body.get_instance_id()
		if enemy_id == excluded_enemy_id:
			continue
		if enemy_body.global_position.distance_to(epicenter) > wraithstep_mark_splash_radius:
			continue
		DAMAGEABLE.apply_damage(enemy_node, final_splash_damage)


func _apply_storm_crown_hit(source_position: Vector2, source_enemy_id: int, source_damage: int) -> void:
	if not reward_storm_crown:
		return
	storm_crown_hit_counter += 1
	if storm_crown_hit_counter % maxi(1, storm_crown_proc_every) != 0:
		return

	var chain_damage := maxi(1, int(round(float(source_damage) * storm_crown_damage_ratio)))
	chain_damage = _apply_objective_mutator_damage_mult(chain_damage)
	var chained_enemy_ids: Dictionary = {source_enemy_id: true}
	var remaining_chains := maxi(0, storm_crown_chain_targets)
	var chain_origin := source_position
	while remaining_chains > 0:
		var next_enemy: Node2D = null
		var next_enemy_id := -1
		var nearest_distance_sq := INF
		for enemy_node in get_tree().get_nodes_in_group("enemies"):
			if not (enemy_node is Node2D):
				continue
			if not DAMAGEABLE.can_take_damage(enemy_node):
				continue
			var enemy_body := enemy_node as Node2D
			var enemy_id := enemy_body.get_instance_id()
			if chained_enemy_ids.has(enemy_id):
				continue
			var dist_sq := chain_origin.distance_squared_to(enemy_body.global_position)
			if dist_sq > storm_crown_chain_radius * storm_crown_chain_radius:
				continue
			if dist_sq < nearest_distance_sq:
				nearest_distance_sq = dist_sq
				next_enemy = enemy_body
				next_enemy_id = enemy_id
		if next_enemy == null:
			break
		DAMAGEABLE.apply_damage(next_enemy, chain_damage)
		chained_enemy_ids[next_enemy_id] = true
		if player_feedback != null:
			player_feedback.play_chain_lightning(chain_origin, next_enemy.global_position)
			player_feedback.play_world_ring(next_enemy.global_position, 16.0, Color(1.0, 0.98, 0.72, 0.82), 0.1)
			player_feedback.play_world_ring(next_enemy.global_position, 28.0, Color(0.82, 0.94, 1.0, 0.46), 0.18)
		chain_origin = next_enemy.global_position
		remaining_chains -= 1
	if player_feedback != null:
		player_feedback.play_storm_crown_discharge(source_position)
	storm_crown_discharge_flash_left = storm_crown_discharge_flash_duration
	queue_redraw()


func _apply_phantom_step_during_dash() -> void:
	var hit_radius := 38.0 + float(phantom_step_stacks) * 5.0
	var phantom_damage := _apply_objective_mutator_damage_mult(phantom_step_damage)
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		if not DAMAGEABLE.can_take_damage(enemy_node):
			continue
		var enemy_body := enemy_node as Node2D
		var eid := enemy_body.get_instance_id()
		if phantom_step_hit_ids.has(eid):
			continue
		if global_position.distance_to(enemy_body.global_position) > hit_radius:
			continue
		DAMAGEABLE.apply_damage(enemy_node, phantom_damage)
		enemy_node.apply_slow(phantom_step_slow_duration, 0.36)
		phantom_step_hit_ids[eid] = true
		if player_feedback != null:
			# Concentric rings: outer (slow field) + inner (damage burst)
			player_feedback.play_world_ring(enemy_body.global_position, hit_radius * 0.82,
				Color(0.46, 1.0, 0.92, 0.9), 0.22)
			player_feedback.play_world_ring(enemy_body.global_position, hit_radius * 0.44,
				Color(0.8, 1.0, 0.98, 0.72), 0.14)


func _update_static_wake_trails(delta: float) -> void:
	if static_wake_trails.is_empty():
		return
	var i := static_wake_trails.size() - 1
	while i >= 0:
		static_wake_trails[i]["life"] -= delta
		if static_wake_trails[i]["life"] <= 0.0:
			static_wake_trails.remove_at(i)
		i -= 1

	for trail in static_wake_trails:
		var trail_pos: Vector2 = trail["pos"]
		for enemy_node in get_tree().get_nodes_in_group("enemies"):
			if not (enemy_node is Node2D):
				continue
			if not DAMAGEABLE.can_take_damage(enemy_node):
				continue
			var enemy_body := enemy_node as Node2D
			if enemy_body.global_position.distance_to(trail_pos) <= 28.0:
				var wake_tick_damage := maxi(1, int(round(float(static_wake_damage) * delta * 6.0)))
				wake_tick_damage = _apply_objective_mutator_damage_mult(wake_tick_damage)
				DAMAGEABLE.apply_damage(enemy_node, wake_tick_damage)

	queue_redraw()


func notify_enemy_killed() -> void:
	_trigger_combo_relay_kill()
	if not reward_void_dash:
		return
	var dash_was_active := dash_cooldown_left > 0.0
	if dash_was_active:
		dash_cooldown_left = 0.0
		void_dash_reset_pulse_left = void_dash_reset_pulse_duration
		if player_feedback != null:
			player_feedback.play_world_ring(global_position, 42.0, Color(0.92, 0.54, 1.0, 0.92), 0.18)
			player_feedback.play_world_ring(global_position, 26.0, Color(1.0, 0.82, 1.0, 0.72), 0.12)
		queue_redraw()

func _has_combo_relay_mutator_active() -> bool:
	for entry in active_objective_mutators:
		var mutator := entry as Dictionary
		if ENCOUNTER_CONTRACTS.mutator_id(mutator) == "combo_relay":
			return true
	return false

func _trigger_combo_relay_kill() -> void:
	if not _has_combo_relay_mutator_active():
		return
	combo_relay_stacks = mini(combo_relay_max_stacks, combo_relay_stacks + 1)
	combo_relay_stack_timer = combo_relay_stack_window
	if player_feedback != null:
		player_feedback.play_combo_relay_kill(global_position, combo_relay_stacks, combo_relay_max_stacks, Color(1.0, 0.82, 0.42, 0.92), 0.2)
	queue_redraw()

func _update_combo_relay_state(delta: float) -> void:
	if combo_relay_stacks <= 0:
		return
	if not _has_combo_relay_mutator_active():
		combo_relay_stacks = 0
		combo_relay_stack_timer = 0.0
		queue_redraw()
		return
	combo_relay_stack_timer = maxf(0.0, combo_relay_stack_timer - delta)
	if combo_relay_stack_timer > 0.0:
		return
	combo_relay_stacks = maxi(0, combo_relay_stacks - 1)
	if combo_relay_stacks > 0:
		combo_relay_stack_timer = combo_relay_stack_window * 0.6
	queue_redraw()

func apply_polar_shift_dash_lockout(duration: float) -> void:
	var applied_duration := maxf(0.0, duration)
	if applied_duration <= 0.0:
		return
	dash_time_left = 0.0
	dash_phase_release_left = 0.0
	queued_attack_after_dash = false
	_set_dash_phasing(false)
	polar_shift_dash_lockout_duration = maxf(polar_shift_dash_lockout_duration, applied_duration)
	polar_shift_dash_lockout_left = maxf(polar_shift_dash_lockout_left, applied_duration)
	if player_feedback != null:
		player_feedback.play_polar_shift_dash_lockout(global_position)
	queue_redraw()

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

	_draw_objective_mutator_aura(body_radius)

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
	_draw_trial_reward_state()

func _draw_objective_mutator_aura(body_radius: float) -> void:
	if active_objective_mutators.is_empty():
		return
	var aura_base := body_radius + 11.0
	for i in range(active_objective_mutators.size()):
		var mutator := active_objective_mutators[i]
		var color := mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_THEME_COLOR, Color(0.84, 0.88, 1.0, 1.0)) as Color
		var remaining := int(mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_REMAINING_ENCOUNTERS, 0))
		var pulse := 0.5 + 0.5 * sin(objective_mutator_aura_phase * (3.2 + float(i) * 0.45) + float(i) * 0.8)
		var ring_alpha := clampf(0.14 + pulse * 0.14, 0.08, 0.3)
		var ring_radius := aura_base + float(i) * 4.8 + pulse * 1.2
		var ring_color := Color(color.r, color.g, color.b, ring_alpha)
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 52, ring_color, 1.8)
		var pip_count := mini(remaining, 6)
		for pip in range(pip_count):
			var angle := -PI * 0.5 + TAU * (float(pip) / float(maxi(1, pip_count))) + objective_mutator_aura_phase * 0.4
			var pip_pos := Vector2(cos(angle), sin(angle)) * (ring_radius + 2.1)
			draw_circle(pip_pos, 1.25, Color(color.r, color.g, color.b, 0.55))

func _draw_trial_reward_state() -> void:
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
		var pip_y := -24.0
		for i in range(execution_every):
			var x := -10.0 + float(i) * 10.0
			var lit := i < pips_lit
			var c := ENEMY_BASE.COLOR_EXECUTION_PIP_LIT if lit else ENEMY_BASE.COLOR_EXECUTION_PIP_DARK
			var pip_pos := Vector2(x, pip_y)
			draw_circle(pip_pos, 3.4, Color(0.08, 0.08, 0.1, 0.46))
			draw_circle(pip_pos, 2.5, c)

	if reward_rupture_wave:
		var pulse := 0.5 + 0.5 * sin(t * 4.2)
		var rupture_color := ENEMY_BASE.COLOR_RUPTURE_WAVE_AURA
		rupture_color.a = 0.3 + pulse * 0.18
		draw_arc(Vector2.ZERO, 20.0 + pulse * 2.8, 0.0, TAU, 42, rupture_color, 1.8)

	if reward_aegis_field:
		var aegis_pulse := 0.5 + 0.5 * sin(t * 3.8 + 0.4)
		var aegis_radius := 22.0 + aegis_pulse * 3.0
		var aegis_alpha := 0.22 + aegis_pulse * 0.14
		if aegis_field_active_left > 0.0:
			aegis_radius = 24.0 + aegis_pulse * 4.0
			aegis_alpha = 0.44 + aegis_pulse * 0.2
		draw_arc(Vector2.ZERO, aegis_radius, 0.0, TAU, 48, Color(0.62, 0.98, 1.0, aegis_alpha), 2.2)
		draw_circle(Vector2.ZERO, aegis_radius * 0.62, Color(0.62, 0.98, 1.0, aegis_alpha * 0.18))

	# Dash archetype trial power visuals
	if reward_phantom_step:
		var ph_hit_radius := 38.0 + float(phantom_step_stacks) * 5.0
		if _is_dash_active():
			# Threat zone: filled disc + bright ring so players instantly read the hit window
			draw_circle(Vector2.ZERO, ph_hit_radius, Color(0.46, 1.0, 0.92, 0.07))
			draw_arc(Vector2.ZERO, ph_hit_radius, 0.0, TAU, 48,
				Color(0.46, 1.0, 0.92, 0.68), 2.4)
			# Ghost afterimages: player sees where they just were
			for ghost_entry: Dictionary in phantom_step_ghost_positions:
				var ghost_life_ratio: float = clampf(ghost_entry["life"] / 0.14, 0.0, 1.0)
				var local_gp: Vector2 = to_local(ghost_entry["pos"])
				draw_circle(local_gp, 14.0 * ghost_life_ratio, Color(0.46, 1.0, 0.92, 0.16 * ghost_life_ratio))
				draw_arc(local_gp, 15.0 * ghost_life_ratio, 0.0, TAU, 24,
					Color(0.46, 1.0, 0.92, 0.52 * ghost_life_ratio), 1.8)
		else:
			var pulse := 0.5 + 0.5 * sin(t * 6.0 + 1.0)
			var ph_color := Color(0.46, 1.0, 0.92, 0.22 + pulse * 0.14)
			draw_arc(Vector2.ZERO, 20.0 + pulse * 3.5, 0.0, TAU, 32, ph_color, 1.6)
			var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.RIGHT
			var side := Vector2(-facing.y, facing.x)
			draw_line(-facing * 8.0 + side * 4.0, -facing * 18.0 + side * 4.0, Color(0.46, 1.0, 0.92, 0.36 + pulse * 0.2), 1.4)
			draw_line(-facing * 8.0 - side * 4.0, -facing * 18.0 - side * 4.0, Color(0.46, 1.0, 0.92, 0.36 + pulse * 0.2), 1.4)

	if reward_void_dash and void_dash_reset_pulse_left > 0.0:
		var pulse_t := clampf(void_dash_reset_pulse_left / maxf(0.001, void_dash_reset_pulse_duration), 0.0, 1.0)
		var glow_t := 1.0 - pulse_t
		var reset_radius := 22.0 + glow_t * 34.0
		var glow_alpha := pulse_t * pulse_t
		var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.RIGHT
		var side := Vector2(-facing.y, facing.x)
		draw_circle(Vector2.ZERO, reset_radius * 0.82, Color(0.88, 0.56, 1.0, 0.2 * glow_alpha))
		draw_circle(Vector2.ZERO, reset_radius * 0.5, Color(1.0, 0.84, 1.0, 0.13 * glow_alpha))
		draw_arc(Vector2.ZERO, reset_radius, 0.0, TAU, 34, Color(1.0, 0.86, 1.0, 0.94 * glow_alpha), 3.2)
		draw_arc(Vector2.ZERO, reset_radius + 7.0, 0.0, TAU, 34, Color(0.88, 0.56, 1.0, 0.54 * glow_alpha), 2.1)
		draw_arc(Vector2.ZERO, reset_radius + 13.0, 0.0, TAU, 34, Color(0.76, 0.4, 0.98, 0.24 * glow_alpha), 1.4)
		draw_line(-facing * 10.0, facing * (18.0 + glow_t * 10.0), Color(1.0, 0.86, 1.0, 0.34 * glow_alpha), 1.8)
		draw_line(-side * 8.0, side * (15.0 + glow_t * 8.0), Color(0.9, 0.62, 1.0, 0.26 * glow_alpha), 1.6)

	if reward_static_wake:
		var pulse := 0.5 + 0.5 * sin(t * 9.0 + 2.0)
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 20, Color(0.96, 0.96, 0.36, 0.2 + pulse * 0.18), 1.4)
		for trail_entry in static_wake_trails:
			var trail_pos: Vector2 = trail_entry["pos"]
			var life_ratio: float = clampf(trail_entry["life"] / maxf(0.001, static_wake_lifetime), 0.0, 1.0)
			var local_pos := to_local(trail_pos)
			draw_circle(local_pos, 10.0 * life_ratio, Color(0.96, 0.96, 0.36, 0.28 * life_ratio))
			draw_arc(local_pos, 13.0 * life_ratio, 0.0, TAU, 14, Color(1.0, 1.0, 0.5, 0.42 * life_ratio), 1.2)

	if reward_storm_crown:
		var crown_pulse := 0.5 + 0.5 * sin(t * 7.8 + 0.9)
		var proc_ratio := 0.0
		if storm_crown_proc_every > 0:
			proc_ratio = float(storm_crown_hit_counter % storm_crown_proc_every) / float(storm_crown_proc_every)
		var charge := proc_ratio

		# Discharge pop
		if storm_crown_discharge_flash_left > 0.0:
			var flash_t := clampf(storm_crown_discharge_flash_left / maxf(0.001, storm_crown_discharge_flash_duration), 0.0, 1.0)
			var glow_t := 1.0 - flash_t
			var pop_r := 18.0 + glow_t * 20.0
			draw_circle(Vector2.ZERO, pop_r * 0.72, Color(0.98, 0.97, 0.6, 0.22 * flash_t))
			draw_arc(Vector2.ZERO, pop_r, 0.0, TAU, 36, Color(1.0, 0.98, 0.78, 0.92 * flash_t * flash_t), 3.4)
			draw_arc(Vector2.ZERO, pop_r + 9.0, 0.0, TAU, 36, Color(0.82, 0.94, 1.0, 0.48 * flash_t), 1.8)

		# Charge arc — fills clockwise from top, shifts yellow -> electric white at full
		var ring_r := 26.0 + crown_pulse * 1.4
		var charge_arc := TAU * charge
		var arc_r := lerpf(0.44, 1.0, charge)
		var arc_g := lerpf(0.62, 0.97, charge)
		var arc_b := lerpf(0.26, 0.72, charge)
		var arc_a := 0.28 + charge * 0.44 + crown_pulse * 0.1
		if charge_arc > 0.05:
			draw_arc(Vector2.ZERO, ring_r, -PI * 0.5, -PI * 0.5 + charge_arc, maxi(6, int(charge_arc / 0.1)), Color(arc_r, arc_g, arc_b, arc_a), 2.6 + charge * 0.8)

		# Crown ticks — 5 radial spikes, each lights up as charge passes their threshold
		var tick_count := 5
		for i in range(tick_count):
			var tick_angle := -PI * 0.5 + TAU * (float(i) / float(tick_count))
			var tick_threshold := float(i) / float(tick_count)
			var lit := charge >= tick_threshold
			var tick_inner := 28.0
			var tick_outer := tick_inner + (6.0 + charge * 7.0 if lit else 3.2)
			var tick_a := (0.32 + charge * 0.5 + crown_pulse * 0.18) if lit else 0.14
			var tick_c := Color(0.98, 0.96, 0.56, tick_a) if lit else Color(0.56, 0.62, 0.44, tick_a)
			draw_line(Vector2(cos(tick_angle), sin(tick_angle)) * tick_inner,
				Vector2(cos(tick_angle), sin(tick_angle)) * tick_outer, tick_c, 2.0)

		# Near-full shimmer
		if charge > 0.74:
			var shimmer_pulse := 0.5 + 0.5 * sin(t * 16.0 + 2.1)
			draw_arc(Vector2.ZERO, ring_r + 5.0, 0.0, TAU, 32, Color(1.0, 0.98, 0.76, 0.12 + shimmer_pulse * 0.2), 1.4)

	if reward_wraithstep:
		var mark_count := wraithstep_marked_enemy_expiry.size()
		var wraith_pulse := 0.5 + 0.5 * sin(t * 6.2 + 2.4)

		# Player passive ring — brighter when marks are active
		var passive_alpha := (0.28 + mark_count * 0.12 + wraith_pulse * 0.14) if mark_count > 0 else (0.12 + wraith_pulse * 0.06)
		draw_arc(Vector2.ZERO, 20.0 + wraith_pulse * 1.8, 0.0, TAU, 32, Color(0.72, 0.94, 1.0, clampf(passive_alpha, 0.0, 0.72)), 1.8)

		# Per-enemy mark glyphs drawn at world positions
		var now_t := Time.get_ticks_msec() / 1000.0
		for enemy_id in wraithstep_marked_enemy_expiry.keys():
			var entry := wraithstep_marked_enemy_expiry[enemy_id] as Dictionary
			var enemy_node: Variant = entry.get("node")
			if not is_instance_valid(enemy_node):
				continue
			var enemy_ref: Node2D = enemy_node as Node2D
			if enemy_ref == null:
				continue
			var local_ep := to_local(enemy_ref.global_position) + Vector2(0.0, -18.0)
			var expiry := float(entry.get("expiry", 0.0))
			var life_ratio := clampf((expiry - now_t) / maxf(0.001, wraithstep_mark_duration), 0.0, 1.0)
			var mark_pulse := 0.5 + 0.5 * sin(t * 9.0 + float(enemy_id & 0xFF) * 0.04)
			var mark_alpha := clampf((0.6 + mark_pulse * 0.3) * life_ratio, 0.0, 1.0)
			var mark_c := Color(0.68, 0.96, 1.0, mark_alpha)
			var mark_c_bright := Color(1.0, 1.0, 1.0, mark_alpha * 0.85)
			var r := 10.0 + mark_pulse * 1.2
			# Bracket arcs top/bottom
			draw_arc(local_ep, r, -PI * 0.28, PI * 0.28, 12, mark_c, 2.2)
			draw_arc(local_ep, r, PI * 0.72, PI * 1.28, 12, mark_c, 2.2)
			# Corner ticks
			var tick_dirs := PackedVector2Array([Vector2(0.7, -0.7), Vector2(-0.7, -0.7), Vector2(0.7, 0.7), Vector2(-0.7, 0.7)])
			for tick_dir: Vector2 in tick_dirs:
				var tp: Vector2 = local_ep + tick_dir * (r + 1.5)
				draw_line(tp, tp + tick_dir * 4.0, mark_c, 1.4)
			# Center dot
			draw_circle(local_ep, 1.8 + mark_pulse * 0.6, mark_c_bright)

	if polar_shift_dash_lockout_left > 0.0:
		var debuff_t := clampf(polar_shift_dash_lockout_left / maxf(0.001, polar_shift_dash_lockout_duration), 0.0, 1.0)
		var field_pulse := 0.5 + 0.5 * sin(t * 8.4 + 0.35)
		var fast_pulse := 0.5 + 0.5 * sin(t * 14.0 + 1.1)
		var spin := t * 1.4
		var field_radius := 24.0 + field_pulse * 2.2
		var sovereign_blue := Color(0.32, 0.78, 0.98, 1.0)
		var sovereign_orange := Color(1.0, 0.58, 0.28, 1.0)
		var sovereign_gold := Color(1.0, 0.88, 0.58, 1.0)
		# Dark tinted fill to visually separate the player from the cage
		draw_circle(Vector2.ZERO, field_radius + 8.0, Color(0.04, 0.12, 0.22, (0.22 + field_pulse * 0.08) * debuff_t))
		# Soft orange inner glow for heat/weight
		draw_circle(Vector2.ZERO, field_radius - 4.0, Color(0.82, 0.44, 0.14, (0.08 + field_pulse * 0.06) * debuff_t))
		# Primary rotating blue ring — thick and bright
		draw_arc(Vector2.ZERO, field_radius, spin, spin + TAU, 52, Color(sovereign_blue.r, sovereign_blue.g, sovereign_blue.b, (0.72 + field_pulse * 0.2) * debuff_t), 3.4)
		# Counter-rotating orange ring slightly outside
		draw_arc(Vector2.ZERO, field_radius + 6.0, -spin * 1.3, -spin * 1.3 + TAU, 60, Color(sovereign_orange.r, sovereign_orange.g, sovereign_orange.b, (0.38 + field_pulse * 0.18) * debuff_t), 2.2)
		# 4 bind spokes with bright gold tips
		for i in range(4):
			var angle := spin + TAU * float(i) / 4.0
			var bind_dir := Vector2.RIGHT.rotated(angle)
			var bind_color := sovereign_blue if i % 2 == 0 else sovereign_orange
			draw_line(bind_dir * 8.0, bind_dir * (field_radius + 7.0), Color(bind_color.r, bind_color.g, bind_color.b, (0.52 + field_pulse * 0.24) * debuff_t), 2.8)
			draw_circle(bind_dir * (field_radius + 7.0), 3.2 + fast_pulse * 0.6, Color(sovereign_gold.r, sovereign_gold.g, sovereign_gold.b, (0.72 + fast_pulse * 0.2) * debuff_t))
		# Countdown sweep ring — shows remaining duration
		var sweep_angle := -PI * 0.5 + (1.0 - debuff_t) * TAU
		draw_arc(Vector2.ZERO, field_radius + 12.0, -PI * 0.5, sweep_angle, 32, Color(0.94, 0.98, 1.0, (0.44 + field_pulse * 0.2) * debuff_t), 2.0)
