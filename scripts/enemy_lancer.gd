extends "res://scripts/enemy_base.gd"

# Lancer — area-denial ranged enemy. Fires a slow energy bolt that leaves a
# lingering hazard zone on landing. Forces the player to constantly reposition
# rather than holding a safe angle. Pairs well with melee pressure since the
# zones cut off escape routes.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

const STATE_STALK := 0
const STATE_WINDUP := 1
const STATE_FIRE := 2
const STATE_REPOSITION := 3

@export var seek_speed: float = 72.0
@export var acceleration: float = 740.0
@export var deceleration: float = 1100.0
@export var preferred_range: float = 260.0
@export var range_tolerance: float = 50.0
@export var trigger_range: float = 320.0
@export var windup_time: float = 0.70
@export var lead_distance: float = 96.0
@export var bolt_speed: float = 360.0
@export var bolt_max_range: float = 400.0
@export var bolt_hit_radius: float = 22.0
@export var zone_radius: float = 56.0
@export var zone_duration: float = 1.6
@export var zone_tick_interval: float = 0.30
@export var zone_tick_damage: int = 8
@export var attack_cooldown: float = 3.0
@export var reposition_duration: float = 0.52
@export var arena_size: Vector2 = Vector2(940.0, 700.0)

var lancer_state: int = STATE_STALK
var state_time_left: float = 0.0
var attack_cooldown_left: float = 0.0
var fire_direction: Vector2 = Vector2.LEFT

# Bolt tracking — one bolt in flight at a time.
var bolt: Node2D = null
var bolt_direction: Vector2 = Vector2.ZERO
var bolt_distance_traveled: float = 0.0
var bolt_travel_limit: float = 0.0
var bolt_predicted_impact_global: Vector2 = Vector2.ZERO
var locked_impact_global: Vector2 = Vector2.ZERO

# Hazard zones left on the arena floor.
# Each entry: { "pos": Vector2, "time_left": float, "tick_timer": float,
#               "spawn_flash": float, "tick_flash": float }
var zones: Array[Dictionary] = []

# Reposition direction locked at entry.
var _reposition_dir: Vector2 = Vector2.ZERO

func _ready() -> void:
	super()
	max_health = 85
	crowd_separation_radius = 58.0
	crowd_separation_strength = 96.0

func _process_behavior(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

	_process_bolt(delta)
	_process_zones(delta)

	match lancer_state:
		STATE_STALK:
			_process_stalk(delta)
		STATE_WINDUP:
			_process_windup(delta)
		STATE_FIRE:
			_process_fire_state(delta)
		STATE_REPOSITION:
			_process_reposition(delta)

# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------

func _process_stalk(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()
	var desired_dir := to_target.normalized()
	var speed_mult := 1.0

	if dist < preferred_range - range_tolerance:
		desired_dir = -desired_dir
		speed_mult = 0.6
	elif dist > preferred_range + range_tolerance:
		speed_mult = 1.0
	else:
		speed_mult = 0.0

	var desired := desired_dir * seek_speed * speed_mult * slow_speed_mult
	velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()

	if attack_cooldown_left <= 0.0 and dist <= trigger_range and bolt == null:
		_enter_windup()

func _enter_windup() -> void:
	lancer_state = STATE_WINDUP
	state_time_left = windup_time
	if is_instance_valid(target):
		var aim_point := _get_facing_lead_point()
		locked_impact_global = aim_point
		var to_target := aim_point - global_position
		if to_target.length_squared() > 0.000001:
			fire_direction = to_target.normalized()
	else:
		locked_impact_global = global_position + fire_direction * 120.0
	visual_facing_direction = fire_direction
	queue_redraw()

func _get_facing_lead_point() -> Vector2:
	if not is_instance_valid(target):
		return global_position + fire_direction * 120.0

	var facing_dir := Vector2.RIGHT.rotated(target.global_rotation)
	var raw_facing: Variant = target.get("visual_facing_direction")
	if raw_facing is Vector2 and (raw_facing as Vector2).length_squared() > 0.000001:
		facing_dir = (raw_facing as Vector2).normalized()

	var aim_point := target.global_position + facing_dir.normalized() * lead_distance

	# Keep prediction inside arena bounds so shot planning and telegraph remain sane.
	var half := arena_size * 0.5
	aim_point.x = clampf(aim_point.x, -half.x, half.x)
	aim_point.y = clampf(aim_point.y, -half.y, half.y)
	return aim_point

func _process_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	queue_redraw()
	if state_time_left <= 0.0:
		_fire_bolt()

func _fire_bolt() -> void:
	lancer_state = STATE_FIRE
	state_time_left = 0.12

	var fire_origin := global_position + fire_direction * 22.0
	var to_locked_impact := locked_impact_global - fire_origin
	if to_locked_impact.length_squared() > 0.000001:
		bolt_direction = to_locked_impact.normalized()
	else:
		bolt_direction = fire_direction
	var desired_travel := to_locked_impact.length()
	var wall_travel_limit := _compute_wall_limited_travel(fire_origin, bolt_direction)
	bolt_travel_limit = minf(minf(desired_travel, wall_travel_limit), bolt_max_range)
	bolt_predicted_impact_global = fire_origin + bolt_direction * bolt_travel_limit

	bolt = Node2D.new()
	bolt.global_position = fire_origin
	get_parent().add_child(bolt)
	bolt_distance_traveled = 0.0
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _process_fire_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		_enter_reposition()

func _enter_reposition() -> void:
	lancer_state = STATE_REPOSITION
	state_time_left = reposition_duration
	# Strafe 90° from player — pick the side that moves away from room centre.
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 0.000001:
			var left_strafe := Vector2(-to_target.y, to_target.x).normalized()
			var right_strafe := Vector2(to_target.y, -to_target.x).normalized()
			var center_dir := -global_position.normalized()
			_reposition_dir = left_strafe if left_strafe.dot(center_dir) > right_strafe.dot(center_dir) else right_strafe
			return
	_reposition_dir = Vector2.RIGHT.rotated(randf() * TAU)

func _process_reposition(delta: float) -> void:
	var desired := _reposition_dir * seek_speed * 1.3 * slow_speed_mult
	velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		lancer_state = STATE_STALK
		attack_cooldown_left = attack_cooldown

# ---------------------------------------------------------------------------
# Bolt movement
# ---------------------------------------------------------------------------

func _process_bolt(delta: float) -> void:
	if bolt == null or not is_instance_valid(bolt):
		bolt = null
		return

	var move := bolt_direction * bolt_speed * delta
	bolt.global_position += move
	bolt_distance_traveled += move.length()
	queue_redraw()

	# Check player hit.
	if is_instance_valid(target):
		if bolt.global_position.distance_to(target.global_position) <= bolt_hit_radius:
			_land_bolt(bolt.global_position)
			return

	# Check arena walls.
	var half := arena_size * 0.5
	if absf(bolt.global_position.x) > half.x or absf(bolt.global_position.y) > half.y:
		_land_bolt(bolt.global_position)
		return

	# Hit max range.
	if bolt_distance_traveled >= bolt_travel_limit:
		_land_bolt(bolt.global_position)

func _compute_wall_limited_travel(start_pos: Vector2, direction: Vector2) -> float:
	if direction.length_squared() <= 0.000001:
		return 0.0

	var dir := direction.normalized()
	var half := arena_size * 0.5
	var hit_t := INF

	if dir.x > 0.000001:
		hit_t = minf(hit_t, (half.x - start_pos.x) / dir.x)
	elif dir.x < -0.000001:
		hit_t = minf(hit_t, (-half.x - start_pos.x) / dir.x)

	if dir.y > 0.000001:
		hit_t = minf(hit_t, (half.y - start_pos.y) / dir.y)
	elif dir.y < -0.000001:
		hit_t = minf(hit_t, (-half.y - start_pos.y) / dir.y)

	if not is_finite(hit_t):
		return bolt_max_range

	return clampf(hit_t, 0.0, bolt_max_range)

func _land_bolt(land_pos: Vector2) -> void:
	if is_instance_valid(bolt):
		bolt.queue_free()
	bolt = null

	# Clamp landing position inside arena.
	var half := arena_size * 0.5
	var clamped := Vector2(
		clampf(land_pos.x, -half.x + zone_radius, half.x - zone_radius),
		clampf(land_pos.y, -half.y + zone_radius, half.y - zone_radius)
	)

	var zone: Dictionary = {}
	zone["pos"] = clamped
	zone["time_left"] = zone_duration
	zone["tick_timer"] = zone_tick_interval * 0.5
	zone["spawn_flash"] = 0.24
	zone["tick_flash"] = 0.0
	zones.append(zone)
	queue_redraw()

# ---------------------------------------------------------------------------
# Hazard zones
# ---------------------------------------------------------------------------

func _process_zones(delta: float) -> void:
	if zones.is_empty():
		return

	var expired: Array[int] = []
	for i in range(zones.size()):
		var z: Dictionary = zones[i]
		z["time_left"] = float(z["time_left"]) - delta
		z["tick_timer"] = float(z["tick_timer"]) - delta
		z["spawn_flash"] = maxf(0.0, float(z.get("spawn_flash", 0.0)) - delta)
		z["tick_flash"] = maxf(0.0, float(z.get("tick_flash", 0.0)) - delta)

		if float(z["tick_timer"]) <= 0.0:
			z["tick_timer"] = zone_tick_interval
			z["tick_flash"] = 0.12
			if is_instance_valid(target):
				if (z["pos"] as Vector2).distance_to(target.global_position) <= zone_radius:
					if DAMAGEABLE.can_take_damage(target):
						DAMAGEABLE.apply_damage(target, zone_tick_damage)

		if float(z["time_left"]) <= 0.0:
			expired.append(i)

	# Remove expired zones in reverse order.
	for i in range(expired.size() - 1, -1, -1):
		zones.remove_at(expired[i])

	if not zones.is_empty():
		queue_redraw()

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var body_radius := 13.0
	var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.LEFT
	var t := float(Time.get_ticks_msec()) * 0.001

	# Body colors shift during windup to signal danger.
	var body_color := Color(0.44, 0.34, 0.78, 0.96)
	var core_color := Color(0.82, 0.72, 1.0, 0.88)
	if lancer_state == STATE_WINDUP:
		body_color = Color(0.72, 0.48, 1.0, 0.96)
		core_color = Color(0.96, 0.88, 1.0, 0.94)
	elif lancer_state == STATE_FIRE:
		body_color = Color(0.58, 0.38, 0.86, 0.96)
		core_color = Color(1.0, 0.78, 1.0, 0.96)
	elif lancer_state == STATE_REPOSITION:
		body_color = Color(0.34, 0.56, 0.84, 0.96)
		core_color = Color(0.82, 0.94, 1.0, 0.92)

	_draw_common_body(body_radius, body_color, core_color, facing)

	# Side prongs — communicate "area projector" role.
	var side := Vector2(-facing.y, facing.x)
	var prong_color := Color(0.78, 0.62, 1.0, 0.52)
	if lancer_state == STATE_WINDUP:
		prong_color = Color(1.0, 0.82, 1.0, 0.72)
	var prong_tip_l := facing * (body_radius * 0.4) + side * (body_radius + 9.0)
	var prong_tip_r := facing * (body_radius * 0.4) - side * (body_radius + 9.0)
	var prong_base_l := -facing * (body_radius * 0.3) + side * (body_radius * 0.6)
	var prong_base_r := -facing * (body_radius * 0.3) - side * (body_radius * 0.6)
	draw_line(prong_base_l, prong_tip_l, prong_color, 2.2)
	draw_line(prong_base_r, prong_tip_r, prong_color, 2.2)
	draw_circle(prong_tip_l, 2.8, Color(prong_color.r, prong_color.g, prong_color.b, prong_color.a * 0.8))
	draw_circle(prong_tip_r, 2.8, Color(prong_color.r, prong_color.g, prong_color.b, prong_color.a * 0.8))

	# Windup telegraph — explicit lane + locked impact reticle + countdown.
	if lancer_state == STATE_WINDUP and windup_time > 0.0:
		var phase := clampf(1.0 - state_time_left / windup_time, 0.0, 1.0)
		var charge_size := 6.0 + phase * 14.0
		var pulse := 0.5 + 0.5 * sin(t * 12.0)
		var preview_origin := fire_direction * 22.0
		var lane_end := locked_impact_global - global_position

		draw_circle(Vector2.ZERO, charge_size + pulse * 2.0, Color(0.88, 0.66, 1.0, 0.24 + phase * 0.2))
		draw_circle(Vector2.ZERO, charge_size * 0.6, Color(1.0, 0.9, 1.0, 0.5 + phase * 0.3))
		draw_arc(Vector2.ZERO, charge_size + 5.0, 0.0, TAU, 28, Color(0.78, 0.52, 1.0, 0.66 + phase * 0.28), 2.2)

		var lane_side := Vector2(-fire_direction.y, fire_direction.x)
		var lane_half := 11.0
		var lane := PackedVector2Array([
			preview_origin + lane_side * lane_half,
			lane_end + lane_side * lane_half,
			lane_end - lane_side * lane_half,
			preview_origin - lane_side * lane_half
		])
		draw_colored_polygon(lane, Color(0.78, 0.52, 1.0, 0.09 + phase * 0.08))
		draw_line(preview_origin + lane_side * lane_half, lane_end + lane_side * lane_half, Color(1.0, 0.86, 1.0, 0.36 + phase * 0.2), 1.8)
		draw_line(preview_origin - lane_side * lane_half, lane_end - lane_side * lane_half, Color(1.0, 0.86, 1.0, 0.36 + phase * 0.2), 1.8)
		draw_line(preview_origin, lane_end, Color(1.0, 0.96, 1.0, 0.3 + phase * 0.32), 1.6)

		draw_arc(lane_end, zone_radius, 0.0, TAU, 44, Color(0.86, 0.58, 1.0, 0.28 + phase * 0.32), 2.6)
		draw_circle(lane_end, 8.0 + pulse * 2.5, Color(1.0, 0.82, 1.0, 0.22 + phase * 0.2))
		var sweep_start := -PI * 0.5
		var sweep_end := sweep_start + TAU * phase
		draw_arc(lane_end, zone_radius + 8.0, sweep_start, sweep_end, 36, Color(1.0, 0.92, 1.0, 0.7), 2.6)

	# Hazard zones — clearer lifetime + tick rhythm.
	for z in zones:
		var z_pos: Vector2 = z["pos"] as Vector2
		var z_local := z_pos - global_position
		var z_t := clampf(float(z["time_left"]) / zone_duration, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(t * 4.8 + z_pos.x * 0.08)
		var spawn_flash := float(z.get("spawn_flash", 0.0))
		var tick_flash := float(z.get("tick_flash", 0.0))
		var tick_progress := 1.0 - clampf(float(z["tick_timer"]) / zone_tick_interval, 0.0, 1.0)

		draw_circle(z_local, zone_radius, Color(0.62, 0.3, 0.9, 0.13 * z_t + pulse * 0.05 + tick_flash * 0.9))
		draw_arc(z_local, zone_radius, 0.0, TAU, 44, Color(0.82, 0.52, 1.0, 0.58 * z_t + tick_flash * 0.8), 3.0)
		draw_arc(z_local, zone_radius - 6.0, 0.0, TAU, 44, Color(0.98, 0.84, 1.0, 0.22 * z_t + tick_flash * 0.55), 1.8)

		var tick_start := -PI * 0.5
		var tick_end := tick_start + TAU * tick_progress
		draw_arc(z_local, zone_radius + 7.0, tick_start, tick_end, 36, Color(1.0, 0.94, 1.0, 0.62 * z_t), 2.0)

		draw_circle(z_local, 5.0 + pulse * 2.0 + tick_flash * 2.8, Color(0.98, 0.86, 1.0, 0.56 * z_t + tick_flash * 0.9))

		if spawn_flash > 0.0:
			var impact_t := clampf(spawn_flash / 0.24, 0.0, 1.0)
			var impact_r := zone_radius * (1.1 + (1.0 - impact_t) * 0.5)
			draw_arc(z_local, impact_r, 0.0, TAU, 44, Color(1.0, 0.84, 1.0, 0.75 * impact_t), 3.2)

	# Bolt in flight.
	if bolt != null and is_instance_valid(bolt):
		var b_local := bolt.global_position - global_position
		var travel_t := clampf(bolt_distance_traveled / maxf(0.001, bolt_travel_limit), 0.0, 1.0)
		var bolt_pulse := 0.5 + 0.5 * sin(t * 20.0)

		var predicted_local := bolt_predicted_impact_global - global_position
		draw_arc(predicted_local, zone_radius, 0.0, TAU, 40, Color(0.86, 0.58, 1.0, 0.16 + (1.0 - travel_t) * 0.18), 1.8)
		draw_circle(predicted_local, 4.0 + bolt_pulse * 1.6, Color(1.0, 0.86, 1.0, 0.2))

		draw_line(b_local - bolt_direction * 18.0, b_local, Color(0.72, 0.44, 0.96, 0.42 + travel_t * 0.14), 7.0)
		draw_line(b_local - bolt_direction * 12.0, b_local, Color(0.98, 0.86, 1.0, 0.54), 3.2)
		draw_circle(b_local, 8.2 + bolt_pulse * 1.8, Color(0.82, 0.52, 1.0, 0.42))
		draw_circle(b_local, 5.2, Color(0.96, 0.76, 1.0, 0.92))
		draw_circle(b_local, 2.5, Color(1.0, 0.98, 1.0, 0.98))

	_draw_slow_indicator(body_radius)
