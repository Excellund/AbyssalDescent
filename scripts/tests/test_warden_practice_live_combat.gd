extends "res://scripts/tests/test_warden_practice.gd"
## Deterministic ordinary-input smoke, not a claim of human balance acceptance.

func _run() -> void:
	if not _is_isolated() or DisplayServer.get_name() != "headless":
		push_error("Practice combat smoke requires the disposable headless helper")
		quit(1)
		return
	await _prepare_normal_checkpoint()
	seed(12092026)
	_new_arena()
	arena.rng.seed = 12092026
	await _start_default_attempt()
	var attacks := [0]
	var dashes := [0]
	var accepted_loss := [0]
	var observed_attacks: Dictionary = {}
	var travel := 0.0
	var previous: Vector2 = arena.player.position
	var frames := 0
	var damage_disabled := 0
	arena.player.primary_attack_fired.connect(func(): attacks[0] += 1)
	arena.player.normal_dash_started.connect(func(): dashes[0] += 1)
	arena.player.damage_taken.connect(func(_raw: int, applied: int, _context: Dictionary): accepted_loss[0] += applied)
	check(arena.player._get_current_health() == 130 and arena.player.damage == 25 and arena.boss.get_current_health() == 1100, "Live drill starts at unchanged base Bastion and Warden health/damage")
	for frame in 1800:
		if arena.mode != "active":
			break
		_release_practice_controls()
		var toward: Vector2 = arena.boss.global_position - arena.player.global_position
		var distance := toward.length()
		var movement := toward if distance > 68.0 else Vector2.ZERO
		if distance < 42.0:
			movement = -toward
		if absf(movement.x) > 5.0:
			Input.action_press("move_right" if movement.x > 0.0 else "move_left")
		if absf(movement.y) > 5.0:
			Input.action_press("move_down" if movement.y > 0.0 else "move_up")
		var motion := InputEventMouseMotion.new()
		motion.position = root.get_screen_transform() * (arena.player.get_global_transform_with_canvas() * arena.player.to_local(arena.boss.global_position))
		motion.global_position = motion.position
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		if frame % 2 == 0 and distance < 96.0:
			Input.action_press("attack")
		if frame % 120 == 0:
			Input.action_press("dash")
		if not arena.player.combat_damage_enabled:
			damage_disabled += 1
		observed_attacks[int(arena.boss.active_attack)] = true
		await physics_frame
		travel += previous.distance_to(arena.player.position)
		previous = arena.player.position
		frames += 1
	_release_practice_controls()
	check(attacks[0] > 0 and arena.damage_dealt > 0 and arena.boss.get_current_health() < 1100, "Ordinary mouse-aimed Attack deals accepted damage to the active Warden")
	check(accepted_loss[0] > 0 and arena.player._get_current_health() < 130, "The unmodified Warden deals real accepted damage to Bastion")
	check(dashes[0] > 0 and travel > 250.0, "Ordinary movement and Dash operate in the real bounded arena")
	check(damage_disabled == 0 and arena.player.get_upgrade_stack_count("iron_skin") == 0, "Live simulation grants no powers and never suppresses incoming combat damage")
	check(observed_attacks.size() >= 2, "Actual Warden decision logic exercises multiple attack patterns")
	check(not arena.presentation().has("damage_recap"), "Live Practice no longer records or presents a recent damage log")
	_check_preserved("Active Warden combat")
	var receipt := {"seed": 12092026, "frames": frames, "simulation_seconds": float(frames) / Engine.physics_ticks_per_second, "outcome": arena.mode, "attacks": attacks[0], "dashes": dashes[0], "damage_dealt": arena.damage_dealt, "accepted_incoming_damage": accepted_loss[0], "health_lost": 130 - arena.player._get_current_health(), "boss_health": arena.boss.get_current_health(), "player_health": arena.player._get_current_health(), "travel": travel, "attack_patterns": observed_attacks.keys(), "damage_disabled_frames": damage_disabled, "scope": "Actual standalone Practice; base Bastion and Warden. Only ordinary Attack, movement and Dash controls. No actor-health overrides, grants, teleports, idle enemies or disabled damage. Accepted incoming damage includes overkill; health_lost is actual loss. Scripted smoke, not human balance acceptance."}
	arena.request_menu()
	await process_frame
	await process_frame
	_check_preserved("Live combat return")
	current_scene.queue_free()
	current_scene = null
	arena = null
	await process_frame
	await _cleanup_recovery_world()
	receipt["checks"] = checks
	receipt["failures"] = failures
	FileAccess.open("res://warden_practice_live_combat.json", FileAccess.WRITE).store_string(JSON.stringify(receipt, "\t"))
	print("[OK] Warden Practice live combat: %d checks, %d failures; %d frames, %d damage dealt, %d health lost" % [checks, failures.size(), frames, receipt.damage_dealt, receipt.health_lost])
	quit(0 if failures.is_empty() else 1)
