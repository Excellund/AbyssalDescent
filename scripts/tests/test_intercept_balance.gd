extends "res://scripts/tests/test_biome_room_context.gd"

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	await _setup_context_world()
	for tier in range(4):
		world.encounter_profile_builder.set_difficulty_tier(tier)
		for depth in [1, 5, 12, 30]:
			var profile: Dictionary = world.encounter_profile_builder.build_objective_profile(depth, "intercept_run")
			var traversal := float(profile[CONTRACTS.PROFILE_KEY_OBJECTIVE_INTERCEPT_TRAVERSAL_TIME])
			check(traversal >= 24.0 and traversal <= 30.0, "All Bearings/depths retain a shorter bounded escort route")
			check(CONTRACTS.profile_objective_spawn_interval(profile) >= 1.8, "Deep Intercept authored waves retain breathing room")
			check(CONTRACTS.mutator_id(CONTRACTS.profile_player_mutator(profile)) == "node_shield", "Intercept retains its Node Shield reward")
	world.encounter_profile_builder.set_difficulty_tier(1)
	await _enter_context("hollow", "intercept_run")
	_start_context_combat()
	var manager := world.objective_manager
	var runtime := world.objective_runtime
	var blockers := _context_enemies()
	for enemy in blockers:
		enemy.global_position = Vector2(430, 280)
	world.player.global_position = manager.intercept_drone_position + Vector2(40, 0)
	check(manager.intercept_drone_radius == 64.0 and manager.intercept_escort_radius == 240.0, "Actual room uses the smaller blocking zone and original escort reach")
	var start_progress := manager.intercept_drone_progress
	runtime.update_intercept_run_objective_state(0.1)
	check(manager.intercept_drone_progress > start_progress, "A living escort advances the real drone on a clear path")
	blockers[0].global_position = manager.intercept_drone_position + Vector2(72, 0)
	start_progress = manager.intercept_drone_progress
	runtime.update_intercept_run_objective_state(0.1)
	check(manager.intercept_drone_progress > start_progress, "A foe just outside the smaller block zone no longer stalls the drone")
	blockers[0].global_position = manager.intercept_drone_position
	start_progress = manager.intercept_drone_progress
	runtime.update_intercept_run_objective_state(0.1)
	check(manager.intercept_drone_stalled and manager.intercept_drone_progress == start_progress, "A living blocker still stops the drone")
	blockers[0].global_position = Vector2(430, 280)
	world.player.global_position = Vector2(430, -280)
	runtime.update_intercept_run_objective_state(0.1)
	check(manager.intercept_drone_stalled and not manager.intercept_player_in_escort_zone, "Leaving escort range still stops progress")
	world._clear_all_enemies()
	await process_frame
	world.active_room_enemy_count = 0
	manager.spawn_timer = 3.0
	world.player.global_position = manager.intercept_drone_position
	runtime.update_intercept_run_objective_state(0.7)
	check(is_equal_approx(manager.spawn_timer, 2.3) and runtime._pending_objective_spawns.is_empty(), "Clearing the room earns its wave interval instead of a 0.6-second forced refill")
	check(manager.intercept_drone_progress > start_progress, "The earned gap permits meaningful escort progress")
	var clear_speed := manager.intercept_drone_speed
	var interval := manager.spawn_interval
	manager.time_left = 0.01
	runtime.update_intercept_run_objective_state(0.02)
	check(manager.overtime and is_equal_approx(manager.spawn_interval, interval * 0.85), "Overtime keeps a gentler 15-percent interval reduction")
	manager.spawn_timer = 100.0
	start_progress = manager.intercept_drone_progress
	runtime.update_intercept_run_objective_state(0.1)
	check(is_equal_approx(manager.intercept_drone_progress - start_progress, clear_speed * 1.4 * 0.1), "Overtime retains the helpful drone speed boost")
	await _dispose_context_world()
	print("[InterceptBalance] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
