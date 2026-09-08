extends "res://scripts/tests/test_arcana_motion.gd"
## Real Input action edges, accepted attacks and player/controller update paths.

func _run() -> void:
	for character_id in CHARACTER.get_launch_character_ids():
		await _test_held_queue(character_id, false)
		await _test_held_queue(character_id, true)
	await _test_released_queue()
	await _test_delayed_success_timer()
	await _test_short_post_attack_hold()
	await _test_failed_attack()
	await _test_queue_cancellation()
	await _test_synchronous_cancellation()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Queued Arcana input: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _clear_input_edges() -> void:
	# Keep buttons held; only advance the synthetic press beyond its input frame.
	await process_frame
	await physics_frame
	await process_frame

func _simulate(duration: float) -> void:
	var remaining := duration
	while remaining > 0.00001:
		await physics_frame
		var delta := minf(1.0 / 60.0, remaining)
		player._physics_process(delta)
		remaining -= delta

func _simulate_until_attack(maximum: float = 1.0) -> void:
	var elapsed := 0.0
	while player.attack_combo_counter == 0 and elapsed < maximum:
		await physics_frame
		player._physics_process(1.0 / 60.0)
		elapsed += 1.0 / 60.0

func _queue_attack_during_dash() -> void:
	await _release_actions()
	_start_dash()
	await _clear_input_edges()
	Input.action_press("attack")
	player._try_attack_input()
	_check(player.queued_attack_after_dash and player.attack_combo_counter == 0, "Attack press during a successful dash queues one deliberate strike")
	_check(player.arcana_motion.charge_hold < 0.0, "A queued request cannot charge before its strike executes")
	await _clear_input_edges()

func _cleanup_queue_world() -> void:
	await _release_actions()
	player.discard_pending_combat_input()
	_free_world()

func _test_held_queue(character_id: String, orbit: bool) -> void:
	_make_world(character_id, orbit)
	player.apply_trial_power("blast_drive")
	if orbit:
		player.apply_trial_power("razor_orbit")
		var target := _enemy(Vector2(150.0, 60.0))
		(player.arcana_motion as AimMotion).aimed_anchor = target
	await _queue_attack_during_dash()
	await _simulate_until_attack(0.50)
	_check(player.attack_combo_counter == 1, "%s queued strike executes promptly after dash%s" % [character_id, " into Orbit" if orbit else ""])
	_check(player.arcana_motion.charge_hold >= 0.0 and player.arcana_motion.charge_hold <= 0.017, "%s held queued strike starts Blast time at its actual successful attack" % character_id)
	if orbit:
		_check(player.arcana_motion.motion == MOTION.Motion.ORBIT and player.attack_lock_time_left == 0.0, "%s queued strike works during Orbit without stopping its movement" % character_id)
	await _simulate(0.66)
	_check(player.blast_releases == 0 and player.attack_combo_counter == 1, "Holding a queued strike never repeats attacks or releases Blast automatically")
	_check(is_equal_approx(player.arcana_motion.charge_hold, MOTION.FULL_CHARGE_TIME), "Held queued attack can reach full Blast charge")
	_check(player._dash_damage_immune_left <= 0.0, "Queued attack and charge do not extend dash immunity")
	Input.action_release("attack")
	player.arcana_motion.tick(0.01)
	_check(player.blast_releases == 1 and player.attack_combo_counter == 2, "Releasing a fully held queued attack launches exactly one deliberate Blast")
	_check(player.arcana_motion.motion == MOTION.Motion.RECOIL and player.arcana_motion.anchor == null, "Queued Blast releases into recoil and cleanly detaches any Orbit")
	_check(player._dash_damage_immune_left <= 0.0, "Queued Blast recoil adds no dash immunity")
	await _clear_input_edges()
	await _simulate(0.4)
	_check(player.blast_releases == 1 and player.attack_combo_counter == 2, "Released queued gesture produces no extra attack or Blast")
	await _cleanup_queue_world()

func _test_released_queue() -> void:
	_make_world()
	player.apply_trial_power("blast_drive")
	await _queue_attack_during_dash()
	Input.action_release("attack")
	await _clear_input_edges()
	await _simulate_until_attack()
	_check(player.attack_combo_counter == 1 and not player.queued_attack_after_dash, "A short attack tap during dash retains its one buffered strike")
	_check(player.arcana_motion.charge_hold < 0.0, "Releasing Attack during dash does not arm a later Blast")
	await _simulate(1.0)
	_check(player.blast_releases == 0 and player.attack_combo_counter == 1, "Released buffered tap never produces automatic follow-up attacks or blasts")
	await _cleanup_queue_world()

func _test_delayed_success_timer() -> void:
	_make_world()
	player.apply_trial_power("blast_drive")
	player.attack_cooldown_left = 0.90
	await _queue_attack_during_dash()
	await _simulate(0.70)
	_check(player.attack_combo_counter == 0 and player.arcana_motion.charge_hold < 0.0, "A held buffered attack waiting for cooldown cannot charge early")
	await _simulate_until_attack()
	_check(player.attack_combo_counter == 1 and player.arcana_motion.charge_hold >= 0.0 and player.arcana_motion.charge_hold <= 0.017, "Long pre-attack hold contributes no time toward Blast")
	await _cleanup_queue_world()

func _test_short_post_attack_hold() -> void:
	_make_world()
	player.apply_trial_power("blast_drive")
	await _queue_attack_during_dash()
	await _simulate_until_attack()
	await _simulate(0.20)
	Input.action_release("attack")
	player.arcana_motion.tick(0.01)
	_check(player.blast_releases == 0 and player.attack_combo_counter == 1, "Less than 0.25 seconds held after the successful strike remains an ordinary attack")
	await _cleanup_queue_world()

func _test_failed_attack() -> void:
	_make_world()
	player.apply_trial_power("blast_drive")
	await _queue_attack_during_dash()
	player._voidfire_lockout_left = 2.0
	await _simulate(1.0)
	_check(player.attack_combo_counter == 0 and player.arcana_motion.charge_hold < 0.0, "A queued strike rejected by overheat cannot arm Blast")
	Input.action_release("attack")
	player.arcana_motion.tick(0.01)
	_check(player.blast_releases == 0, "Releasing a rejected queued attack cannot fire")
	await _cleanup_queue_world()

func _test_queue_cancellation() -> void:
	for reason in ["modal", "focus", "death"]:
		_make_world()
		player.apply_trial_power("blast_drive")
		await _queue_attack_during_dash()
		match reason:
			"modal":
				player.encounter_input_frozen = true
				player.discard_pending_combat_input()
				player.encounter_input_frozen = false
			"focus":
				player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"death":
				player.set_alive(false)
				player.set_alive(true)
		await _simulate(0.80)
		_check(player.attack_combo_counter == 0 and player.arcana_motion.charge_hold < 0.0, "%s drops queued Attack and cannot rearm from a still-held button" % reason)
		Input.action_release("attack")
		player.arcana_motion.tick(0.01)
		_check(player.blast_releases == 0, "%s prevents a Blast on eventual release" % reason)
		await _release_actions()
		_ready_attack()
		_check(player.attack_combo_counter == 1 and player.arcana_motion.charge_hold >= 0.0, "%s permits a fresh deliberate Attack after release" % reason)
		await _cleanup_queue_world()

func _test_synchronous_cancellation() -> void:
	_make_world()
	player.apply_trial_power("blast_drive")
	await _queue_attack_during_dash()
	player.primary_attack_fired.connect(func():
		player.discard_pending_combat_input()
	)
	await _simulate_until_attack()
	_check(player.attack_combo_counter == 1 and player.arcana_motion.charge_hold < 0.0, "Cancellation during the accepted queued strike cannot rearm its held Blast afterward")
	Input.action_release("attack")
	player.arcana_motion.tick(0.01)
	_check(player.blast_releases == 0, "Synchronous input cancellation prevents a later queued Blast release")
	await _cleanup_queue_world()
