extends "res://scripts/enemy_base.gd"

# Ram — late-game charging enemy. Shares the Charger's charge archetype but has
# a distinct combat identity: instead of one large telegraphed charge, the Ram
# performs 2–3 rapid short charges in quick succession, pausing briefly between
# each to re-acquire the target. The multi-pass pattern forces the player to dodge
# multiple times per attack cycle rather than reacting once.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

const STATE_SEEK := 0
const STATE_WINDUP := 1
const STATE_CHARGE := 2
const STATE_CHARGE_PAUSE := 3
const STATE_RECOVER := 4

@export var seek_speed: float = 82.0
@export var acceleration: float = 900.0
@export var deceleration: float = 1200.0
@export var trigger_range: float = 170.0
@export var windup_time: float = 0.45
@export var charge_speed: float = 500.0
@export var charge_time: float = 0.16
@export var charge_pause_time: float = 0.1
@export var charge_count: int = 3
@export var recover_time: float = 0.85
@export var full_cooldown: float = 2.2
@export var charge_damage: int = 12
@export var path_width: float = 22.0

var ram_state: int = STATE_SEEK
var state_time_left: float = 0.0
var attack_cooldown_left: float = 0.0
var _charge_direction: Vector2 = Vector2.LEFT
var _charges_remaining: int = 0
var _charge_hit_applied: bool = false
var _charge_enemy_exceptions: Dictionary = {}

func _ready() -> void:
	super()
	# Override crowd separation for charging through enemy swarms
	crowd_separation_radius = 58.0
	crowd_separation_strength = 100.0

func _process_behavior(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)
	if ram_state != STATE_CHARGE and not _charge_enemy_exceptions.is_empty():
		_clear_charge_exceptions()
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return
	match ram_state:
		STATE_SEEK:
			_process_seek(delta)
		STATE_WINDUP:
			_process_windup(delta)
		STATE_CHARGE:
			_process_charge(delta)
		STATE_CHARGE_PAUSE:
			_process_charge_pause(delta)
		STATE_RECOVER:
			_process_recover(delta)

func _process_seek(delta: float) -> void:
	var to_target := target.global_position - global_position
	var desired := Vector2.ZERO
	if to_target.length() > 10.0:
		desired = to_target.normalized() * seek_speed * slow_speed_mult
	var move_rate := acceleration if desired != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired, move_rate * delta)
	move_and_slide()
	if attack_cooldown_left <= 0.0 and to_target.length() <= trigger_range:
		_enter_windup_state()

func _enter_windup_state() -> void:
	ram_state = STATE_WINDUP
	state_time_left = windup_time
	_charge_hit_applied = false
	_charges_remaining = charge_count
	var to_target := target.global_position - global_position
	if to_target.length_squared() > 0.000001:
		_charge_direction = to_target.normalized()
	visual_facing_direction = _charge_direction
	queue_redraw()

func _process_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			_charge_direction = to_target.normalized()
			visual_facing_direction = _charge_direction
	state_time_left = maxf(0.0, state_time_left - delta)
	queue_redraw()
	if state_time_left <= 0.0:
		_enter_charge_state()

func _enter_charge_state() -> void:
	ram_state = STATE_CHARGE
	state_time_left = charge_time
	_charge_hit_applied = false
	visual_facing_direction = _charge_direction
	velocity = _charge_direction * charge_speed
	_sync_charge_exceptions()
	queue_redraw()

func _process_charge(delta: float) -> void:
	_sync_charge_exceptions()
	velocity = _charge_direction * charge_speed
	move_and_slide()
	_try_apply_charge_hit()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		_charges_remaining -= 1
		if _charges_remaining > 0:
			_enter_charge_pause_state()
		else:
			_enter_recover_state()

func _enter_charge_pause_state() -> void:
	ram_state = STATE_CHARGE_PAUSE
	state_time_left = charge_pause_time
	velocity *= 0.18
	_clear_charge_exceptions()
	queue_redraw()

func _process_charge_pause(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			_charge_direction = to_target.normalized()
			visual_facing_direction = _charge_direction
	state_time_left = maxf(0.0, state_time_left - delta)
	queue_redraw()
	if state_time_left <= 0.0:
		_enter_charge_state()

func _enter_recover_state() -> void:
	ram_state = STATE_RECOVER
	state_time_left = recover_time
	attack_cooldown_left = full_cooldown
	velocity *= 0.22
	_clear_charge_exceptions()
	queue_redraw()

func _process_recover(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		ram_state = STATE_SEEK

func _try_apply_charge_hit() -> void:
	if _charge_hit_applied:
		return
	if not is_instance_valid(target) or not DAMAGEABLE.can_take_damage(target):
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() == target:
			DAMAGEABLE.apply_damage(target, charge_damage, {"source": "enemy_contact", "ability": "ram_charge"})
			_charge_hit_applied = true
			attack_anim_time_left = attack_anim_duration
			queue_redraw()
			return
	if global_position.distance_to(target.global_position) <= path_width:
		DAMAGEABLE.apply_damage(target, charge_damage, {"source": "enemy_contact", "ability": "ram_charge"})
		_charge_hit_applied = true
		attack_anim_time_left = attack_anim_duration
		queue_redraw()

func _sync_charge_exceptions() -> void:
	var seen_ids: Dictionary = {}
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is PhysicsBody2D):
			continue
		var enemy_body := enemy_node as PhysicsBody2D
		if enemy_body == self:
			continue
		var enemy_id := enemy_body.get_instance_id()
		seen_ids[enemy_id] = true
		if _charge_enemy_exceptions.has(enemy_id):
			continue
		add_collision_exception_with(enemy_body)
		_charge_enemy_exceptions[enemy_id] = enemy_body
	for enemy_id in _charge_enemy_exceptions.keys():
		if seen_ids.has(enemy_id):
			continue
		var enemy_ref = _charge_enemy_exceptions[enemy_id]
		if is_instance_valid(enemy_ref):
			var existing: PhysicsBody2D = enemy_ref as PhysicsBody2D
			if existing != null:
				remove_collision_exception_with(existing)
		_charge_enemy_exceptions.erase(enemy_id)

func _clear_charge_exceptions() -> void:
	for enemy_id in _charge_enemy_exceptions.keys():
		var enemy_ref = _charge_enemy_exceptions[enemy_id]
		if is_instance_valid(enemy_ref):
			var enemy_body: PhysicsBody2D = enemy_ref as PhysicsBody2D
			if enemy_body != null:
				remove_collision_exception_with(enemy_body)
	_charge_enemy_exceptions.clear()

func _draw() -> void:
	var attack_pulse := _get_attack_pulse()
	var speed_t := clampf(velocity.length() / maxf(1.0, charge_speed), 0.0, 1.0)
	var body_radius := 15.0 + attack_pulse + speed_t * 1.5  # Larger base size for visibility
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT
	var side := Vector2(-facing.y, facing.x)

	# Persistent aggressive aura — always visible to distinguish from Chargers
	var aura_pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.009)
	var aura_alpha := 0.15 + aura_pulse * 0.1
	draw_circle(Vector2.ZERO, body_radius + 12.0, Color(1.0, 0.44, 0.08, aura_alpha))

	# Aggressive amber/gold body — signals raw power and multi-hit threat
	var body_color := COLOR_PALETTE.COLOR_RAM_BODY
	var core_color := COLOR_PALETTE.COLOR_RAM_CORE
	if ram_state == STATE_WINDUP or ram_state == STATE_CHARGE_PAUSE:
		body_color = COLOR_PALETTE.COLOR_RAM_BODY_WINDUP
		core_color = COLOR_PALETTE.COLOR_RAM_CORE_WINDUP
	elif ram_state == STATE_CHARGE:
		body_color = COLOR_PALETTE.COLOR_RAM_BODY_CHARGE
		core_color = COLOR_PALETTE.COLOR_RAM_CORE_CHARGE
	_draw_common_body(body_radius, body_color, core_color, facing)

	# Blunt forward horns — aggressive angular design signals multi-charge threat
	var horn_base := facing * (body_radius + 3.0)
	draw_line(horn_base + side * 5.5, horn_base + side * 5.5 + facing * 11.0, COLOR_PALETTE.COLOR_RAM_HORN, 3.6)
	draw_line(horn_base - side * 5.5, horn_base - side * 5.5 + facing * 11.0, COLOR_PALETTE.COLOR_RAM_HORN, 3.6)
	
	# Distinctive sharp spikes radiating outward — instantly recognizable silhouette
	for spike_i in range(4):
		var spike_angle := float(spike_i) * TAU / 4.0 + float(Time.get_ticks_msec()) * 0.001
		var spike_dir := Vector2.RIGHT.rotated(spike_angle)
		var spike_base := spike_dir * body_radius
		var spike_tip := spike_dir * (body_radius + 8.0)
		draw_line(spike_base, spike_tip, Color(1.0, 0.7, 0.2, 0.8), 2.0)

	# Pulsing charge glow during attack phases
	if ram_state == STATE_WINDUP or ram_state == STATE_CHARGE or ram_state == STATE_CHARGE_PAUSE:
		var pulse_t := float(Time.get_ticks_msec()) * 0.008
		var pulse_strength := 0.4 + 0.6 * sin(pulse_t)
		var glow_alpha := 0.12 + pulse_strength * 0.18
		draw_circle(Vector2.ZERO, body_radius + 9.0, Color(1.0, 0.44, 0.08, glow_alpha))

	# Show remaining charges as prominent pips so player can track incoming multi-charges
	if ram_state == STATE_CHARGE or ram_state == STATE_CHARGE_PAUSE:
		var pip_spacing := 7.0
		var pip_start := -side * (float(_charges_remaining - 1) * pip_spacing * 0.5)
		for i in range(_charges_remaining):
			var pip_pos := pip_start + side * float(i) * pip_spacing - facing * (body_radius + 12.0)
			# Pulsing pips show remaining charges
			var pip_pulse := 0.3 + 0.7 * sin(float(Time.get_ticks_msec()) * 0.015 + float(i) * 0.4)
			var pip_size := 3.0 + pip_pulse * 0.8
			var pip_alpha := 0.8 + pip_pulse * 0.2
			draw_circle(pip_pos, pip_size, Color(1.0, 0.92, 0.56, pip_alpha))
			draw_circle(pip_pos, pip_size - 0.8, Color(1.0, 0.96, 0.7, pip_alpha * 0.5))

	# Trajectory forecast during charges — prominent directional telegraph with multi-charge info
	if ram_state == STATE_WINDUP:
		var forecast_distance := charge_speed * charge_time
		var cone_alpha := 0.32
		var cone_width := body_radius + 16.0
		var cone_base_left := _charge_direction.rotated(0.45)
		var cone_base_right := _charge_direction.rotated(-0.45)
		
		# Wide aiming cone shows general direction
		draw_line(Vector2.ZERO, cone_base_left * cone_width, Color(1.0, 0.7, 0.2, cone_alpha), 2.8)
		draw_line(Vector2.ZERO, cone_base_right * cone_width, Color(1.0, 0.7, 0.2, cone_alpha), 2.8)
		
		# Primary directional line showing exact charge direction with full distance
		var line_alpha := 0.72
		var full_range_end := _charge_direction * forecast_distance
		draw_line(Vector2.ZERO, full_range_end, Color(1.0, 0.76, 0.3, line_alpha), 3.6)
		
		# Secondary fainter line shows max possible range (all 3 charges in a line)
		var max_range_end := _charge_direction * (forecast_distance * 1.8)
		var extended_alpha := 0.18
		draw_line(Vector2.ZERO, max_range_end, Color(1.0, 0.6, 0.2, extended_alpha), 2.0)
		
		# Charge count indicators — show 3 pips to communicate multi-charge threat
		var pip_spacing := 8.0
		var pip_start := -side * (float(charge_count - 1) * pip_spacing * 0.5)
		for i in range(charge_count):
			var pip_pos := pip_start + side * float(i) * pip_spacing - facing * (body_radius + 14.0)
			var pip_size := 3.0
			var pip_color := Color(1.0, 0.92, 0.56, 0.7)
			draw_circle(pip_pos, pip_size, pip_color)
			draw_circle(pip_pos, pip_size - 0.6, Color(1.0, 0.96, 0.7, 0.35))
		
		# Target impact zone circle at charge endpoint
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		var zone_alpha := 0.24 + pulse * 0.16
		draw_circle(full_range_end, path_width * 1.2, Color(1.0, 0.7, 0.2, zone_alpha))
		
		# Animated steps showing the charge path will be repeated
		for step_i in range(1, charge_count):
			var step_pos := _charge_direction * (forecast_distance * float(step_i) * 0.7)
			var step_alpha := 0.22 * (1.0 - float(step_i) / float(charge_count))
			draw_circle(step_pos, path_width * 0.8, Color(1.0, 0.7, 0.2, step_alpha))
	
	# Charging speed streaks — motion blur on active charges
	if ram_state == STATE_CHARGE and speed_t > 0.4:
		var streak_alpha := 0.14 + speed_t * 0.16
		draw_circle(-facing * (body_radius + 4.0), body_radius * 0.75, Color(0.96, 0.4, 0.08, streak_alpha * 0.7))
		draw_circle(-facing * (body_radius + 10.0), body_radius * 0.5, Color(0.8, 0.32, 0.06, streak_alpha * 0.35))

	_draw_slow_indicator(body_radius)
