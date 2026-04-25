extends "res://scripts/enemy_base.gd"

const STATE_SEEK := 0
const STATE_WINDUP := 1
const STATE_FIRE := 2
const STATE_RECOVER := 3

@export var seek_speed: float = 78.0
@export var acceleration: float = 800.0
@export var deceleration: float = 1200.0
@export var preferred_range: float = 220.0
@export var range_tolerance: float = 40.0
@export var trigger_range: float = 300.0
@export var windup_time: float = 0.6
@export var projectile_speed: float = 280.0
@export var projectile_damage: int = 14
@export var attack_cooldown: float = 2.2
@export var fire_interval: float = 0.22

var attack_cooldown_left: float = 0.0
var archer_state: int = STATE_SEEK
var archer_state_time_left: float = 0.0
var arrow_direction: Vector2 = Vector2.LEFT
var projectiles: Array[Node2D] = []
var projectile_directions: Dictionary = {}
var fire_time_left: float = 0.0
var arrows_fired: int = 0

func _process_behavior(delta: float) -> void:
	_update_attack_cooldown(delta)
	_process_projectiles(delta)
	_process_state_machine(delta)

func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_left > 0.0:
		attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)

func _process_state_machine(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		move_and_slide()
		return

	if archer_state == STATE_SEEK:
		_process_seek_state(delta)
		return

	if archer_state == STATE_WINDUP:
		_process_windup_state(delta)
		return

	if archer_state == STATE_FIRE:
		_process_fire_state(delta)
		return

	_process_recover_state(delta)

func _process_seek_state(delta: float) -> void:
	var to_target := target.global_position - global_position
	var dist_to_target := to_target.length()
	
	# Maintain preferred range
	var desired_direction := to_target.normalized()
	var speed_multiplier := 1.0
	if dist_to_target < preferred_range - range_tolerance:
		desired_direction = -desired_direction  # Back away
		speed_multiplier = 0.6
	elif dist_to_target > preferred_range + range_tolerance:
		speed_multiplier = 1.0
	else:
		speed_multiplier = 0.0  # At ideal range, hold position
	
	var desired_velocity := desired_direction * seek_speed * speed_multiplier
	var move_rate := acceleration if desired_velocity != Vector2.ZERO else deceleration
	velocity = velocity.move_toward(desired_velocity, move_rate * delta)
	move_and_slide()
	
	if attack_cooldown_left <= 0.0 and dist_to_target <= trigger_range:
		_enter_windup_state()

func _process_windup_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	archer_state_time_left = maxf(0.0, archer_state_time_left - delta)
	
	# Draw telegraph line during windup
	queue_redraw()
	
	if archer_state_time_left <= 0.0:
		_enter_fire_state()

func _process_fire_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	
	fire_time_left = maxf(0.0, fire_time_left - delta)
	if fire_time_left <= 0.0 and arrows_fired < 3:
		_fire_arrow()
		fire_time_left = fire_interval
		arrows_fired += 1
	
	archer_state_time_left = maxf(0.0, archer_state_time_left - delta)
	if archer_state_time_left <= 0.0:
		_enter_recover_state()

func _process_recover_state(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	archer_state_time_left = maxf(0.0, archer_state_time_left - delta)
	if archer_state_time_left <= 0.0:
		archer_state = STATE_SEEK
		attack_cooldown_left = attack_cooldown

func _enter_windup_state() -> void:
	archer_state = STATE_WINDUP
	archer_state_time_left = windup_time
	var to_target := target.global_position - global_position
	if to_target.length_squared() > 0.000001:
		arrow_direction = to_target.normalized()
	visual_facing_direction = arrow_direction

func _enter_fire_state() -> void:
	archer_state = STATE_FIRE
	archer_state_time_left = fire_interval * 3.5
	fire_time_left = 0.0
	arrows_fired = 0

func _enter_recover_state() -> void:
	archer_state = STATE_RECOVER
	archer_state_time_left = 0.4

func _fire_arrow() -> void:
	var projectile := Node2D.new()
	projectile.global_position = global_position + arrow_direction * 20.0
	get_parent().add_child(projectile)
	projectiles.append(projectile)
	projectile_directions[projectile.get_instance_id()] = arrow_direction
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _process_projectiles(delta: float) -> void:
	var completed_projectiles: Array[Node2D] = []
	
	for projectile in projectiles:
		if not is_instance_valid(projectile):
			projectile_directions.erase(projectile.get_instance_id())
			completed_projectiles.append(projectile)
			continue

		var projectile_direction: Vector2 = projectile_directions.get(projectile.get_instance_id(), arrow_direction)
		
		# Move projectile
		var old_position := projectile.global_position
		projectile.global_position += projectile_direction * projectile_speed * delta
		
		# Check for environmental collision using raycast
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(old_position, projectile.global_position)
		query.collide_with_areas = false
		var result := space_state.intersect_ray(query)
		if result:
			var collider: Object = result.get("collider", null)
			if collider is Node and (collider as Node).is_in_group("enemies"):
				continue
			# Hit something in the environment, despawn
			projectile.queue_free()
			completed_projectiles.append(projectile)
			continue
		
		# Check hit on player
		if is_instance_valid(target):
			var dist_to_player := projectile.global_position.distance_to(target.global_position)
			if dist_to_player < 28.0:
				if target.has_method("take_damage"):
					target.call("take_damage", projectile_damage)
				projectile.queue_free()
				completed_projectiles.append(projectile)
				continue
		
		# Remove if too far away
		if projectile.global_position.distance_to(global_position) > 1200.0:
			projectile.queue_free()
			projectile_directions.erase(projectile.get_instance_id())
			completed_projectiles.append(projectile)
	
	for projectile in completed_projectiles:
		projectile_directions.erase(projectile.get_instance_id())
		projectiles.erase(projectile)

func _draw() -> void:
	var body_radius := 13.0
	var body_color := COLOR_ARCHER_BODY
	var core_color := COLOR_ARCHER_CORE
	_draw_common_body(body_radius, body_color, core_color, visual_facing_direction)
	
	# Draw telegraph during windup
	if archer_state == STATE_WINDUP:
		var windup_phase := 1.0 - (archer_state_time_left / windup_time) if windup_time > 0.0 else 1.0
		var line_length := 400.0
		var line_end := arrow_direction * line_length
		var bracket_size := 20.0
		var side := Vector2(-arrow_direction.y, arrow_direction.x)
		var aim_pos := arrow_direction * 100.0
		
		# Background aim guide (subtle inner line)
		draw_line(Vector2.ZERO, line_end * 0.8, Color(COLOR_ARCHER_AIM.r, COLOR_ARCHER_AIM.g, COLOR_ARCHER_AIM.b, 0.3), 1.0)
		
		# Main aiming line (thicker, more prominent)
		draw_line(Vector2.ZERO, line_end, COLOR_ARCHER_AIM, 2.2)
		
		# Pulsing impact zone bracket (gets brighter as shot prepares)
		var bracket_pulse := 0.6 + 0.4 * sin(windup_phase * PI * 2.0)
		var bracket_alpha := COLOR_ARCHER_AIM_BRACKET.a * bracket_pulse
		draw_line(aim_pos - side * bracket_size, aim_pos + side * bracket_size, Color(COLOR_ARCHER_AIM_BRACKET.r, COLOR_ARCHER_AIM_BRACKET.g, COLOR_ARCHER_AIM_BRACKET.b, bracket_alpha), 2.0)
		
		# Corner accent marks for target box
		var corner_len := 8.0
		draw_line(aim_pos + side * bracket_size - arrow_direction * corner_len, aim_pos + side * bracket_size, Color(COLOR_ARCHER_AIM.r, COLOR_ARCHER_AIM.g, COLOR_ARCHER_AIM.b, 0.7), 1.4)
		draw_line(aim_pos - side * bracket_size - arrow_direction * corner_len, aim_pos - side * bracket_size, Color(COLOR_ARCHER_AIM.r, COLOR_ARCHER_AIM.g, COLOR_ARCHER_AIM.b, 0.7), 1.4)
	
	# Draw projectiles
	for projectile in projectiles:
		if is_instance_valid(projectile):
			var offset := projectile.global_position - global_position
			draw_circle(offset, 4.0, COLOR_ARCHER_PROJECTILE)
			draw_circle(offset, 2.2, Color(1.0, 0.92, 0.6, 0.9))
