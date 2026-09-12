extends "res://scripts/tests/test_arcana_motion.gd"
## Accepted release input, real collision bodies and bounded ordinary movement.

func _input_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _clear_movement() -> void:
	for action in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		_input_action(action, false)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	for cause in ["release", "expiry", "anchor_loss"]:
		await _test_chosen_departure(cause)
	await _test_steering_and_dash()
	await _test_solid_exit()
	for reason in ["modal", "death", "disabled"]:
		await _test_escape_cancel(reason)
	_clear_movement()
	await _release_actions()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await create_timer(0.1).timeout
	print("[OK] Orbit escape: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_chosen_departure(cause: String) -> void:
	_make_world()
	player.apply_trial_power("razor_orbit")
	player.dash_direction = Vector2.RIGHT
	var target := _enemy(Vector2(0, 70))
	# The old rightward tangent hits this real column before its carry expires.
	_column(Vector2(45, 0), 15)
	await physics_frame
	await process_frame # PhysicsServer has now committed new body transforms.
	_input_action(&"dash", true)
	var motion := player.arcana_motion
	motion.start_orbit(target)
	_check(motion.tangent.dot(Vector2.RIGHT) > 0.99, cause + ": incoming tangent points at the nearby obstacle")
	# The player chooses LEFT on the very frame of release, rather than relying
	# on cached movement from any preceding circular step.
	_input_action(&"move_left", true)
	_check(motion._orbit_departure_direction().dot(Vector2.LEFT) > 0.99, cause + ": final warning previews fresh movement input")
	match cause:
		"release":
			_input_action(&"dash", false)
			motion.tick(0.01)
		"expiry":
			motion.orbit_elapsed = motion.orbit_limit - 0.005
			motion.process_movement(0.01, player._read_movement_direction())
		"anchor_loss":
			target.health_state.take_damage(10000)
			motion.process_movement(0.01, player._read_movement_direction())
	_check(motion.motion == MOTION.Motion.CARRY and motion._orbit_hint_direction.dot(Vector2.LEFT) > 0.99, cause + ": actual exit and first cue choose the safe direction before moving")
	_check(player.completed_movement_kinds == ["orbit"], cause + ": dismount completes the original Orbit exactly once")
	var before := player.global_position
	motion.process_movement(0.02, player._read_movement_direction())
	_check(player.global_position.x < before.x and absf(player.global_position.y - before.y) < 0.01, cause + ": first escape step reverses the dangerous tangent [before=%s after=%s input=%s mode=%s carry=%s]" % [before, player.global_position, player._read_movement_direction(), motion.motion, motion.carry_left])
	motion.process_movement(1.0, Vector2.LEFT)
	var expected_distance := minf(MOTION.ORBIT_SPEED, player.max_speed * 1.5) * 0.25
	_check(absf(player.global_position.distance_to(before) - expected_distance) < 0.01 and not motion.owns_movement(), cause + ": even a long frame caps escape at a quarter second")
	_check(player.completed_movement_kinds == ["orbit"] and motion.dash_hold < 0.0, cause + ": escape end grants no extra completion or held-button reacquisition")
	_check(player._dash_damage_immune_left == 0.0 and not player.dash_phasing_active and not player._is_dash_active(), cause + ": directional escape grants no Dash immunity, phasing or activation")
	_clear_movement()
	await _release_actions()
	_free_world()

func _test_steering_and_dash() -> void:
	_make_world()
	player.apply_trial_power("razor_orbit")
	var target := _enemy(Vector2(0, 70))
	player.dash_direction = Vector2.RIGHT
	await physics_frame
	await process_frame # PhysicsServer has now committed new body transforms.
	_input_action(&"dash", true)
	var motion := player.arcana_motion
	motion.start_orbit(target)
	_input_action(&"dash", false)
	motion.tick(0.01)
	_check(motion.tangent.dot(Vector2.RIGHT) > 0.99, "No movement input retains the original circular momentum")
	motion.process_movement(0.02, Vector2.RIGHT)
	var turn := player.global_position
	motion.process_movement(0.02, Vector2.UP)
	_check(player.global_position.y < turn.y and absf(player.global_position.x - turn.x) < 0.01, "Dismount responds to a new direction during its burst [turn=%s pos=%s mode=%s]" % [turn, player.global_position, motion.motion])
	_check(motion._orbit_hint_direction.dot(Vector2.UP) > 0.99, "Departure cue follows the steered direction")
	var coast := player.global_position
	motion.process_movement(0.02, Vector2.ZERO)
	_check(player.global_position.y < coast.y, "Releasing movement retains the last chosen momentum")
	var health := player.get_current_health()
	player.take_damage(7, {"source": "enemy_contact", "ability": "orbit_escape_probe"})
	_check(player.get_current_health() < health, "Enemy contact remains real during the escape")
	health = player.get_current_health()
	player.take_damage(11, {"source": "enemy_ability", "ability": "orbit_escape_probe"})
	_check(player.get_current_health() < health, "Enemy abilities remain real during the escape")
	await _release_actions()
	player.dash_cooldown_left = 0.0
	_input_action(&"dash", true)
	player._try_start_dash(Vector2.LEFT)
	_check(player._is_dash_active() and player.dash_direction == Vector2.LEFT and not motion.owns_movement(), "A fresh available Dash immediately interrupts the escape in the chosen direction")
	_check(player.completed_movement_kinds == ["orbit"], "Fresh Dash does not complete the departed Orbit twice")
	await _release_actions()
	_free_world()

func _test_solid_exit() -> void:
	_make_world()
	player.apply_trial_power("razor_orbit")
	var target := _enemy(Vector2(0, 70))
	_column(Vector2(-45, 0), 15)
	await physics_frame
	await process_frame # PhysicsServer has now committed new body transforms.
	var motion := player.arcana_motion
	motion.start_orbit(target)
	motion.detach(true, Vector2.LEFT)
	motion.process_movement(0.25, Vector2.LEFT)
	_check(player.global_position.x > -20.0 and not motion.owns_movement(), "A poorly chosen exit still stops at real cover instead of passing through it")
	await _release_actions()
	_free_world()

func _test_escape_cancel(reason: String) -> void:
	_make_world()
	player.apply_trial_power("razor_orbit")
	var target := _enemy(Vector2(0, 70))
	await physics_frame
	await process_frame # PhysicsServer has now committed new body transforms.
	var motion := player.arcana_motion
	motion.start_orbit(target)
	motion.detach(true, Vector2.LEFT)
	match reason:
		"modal": player.encounter_input_frozen = true
		"death": player.set_alive(false)
		"disabled": player.set_combat_damage_enabled(false)
	motion.tick(0.01)
	var before := player.global_position
	motion.process_movement(0.2, Vector2.LEFT)
	_check(player.global_position == before and not motion.owns_movement() and motion._orbit_hint_left == 0.0, reason + ": cancellation leaves no escape displacement or stale cue")
	_check(player.completed_movement_kinds == ["orbit"], reason + ": cancelled escape cannot repeat completion rewards")
	await _release_actions()
	_free_world()
