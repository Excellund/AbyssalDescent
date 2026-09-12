extends "res://scripts/tests/test_biome_room_context.gd"
## Real mission entry and objective ticks verify breathing room, capture and exit.

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	await _setup_context_world()
	_test_profile_pressure()
	await _test_live_circuit()
	await _dispose_context_world()
	print("[CircuitSweepBalance] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_profile_pressure() -> void:
	var builder := world.encounter_profile_builder
	for tier in range(4):
		builder.set_difficulty_tier(tier)
		var prior_count := 0
		for depth in [1, 5, 12, 24]:
			var profile: Dictionary = builder._build_circuit_sweep_profile(depth)
			var count := CONTRACTS.profile_total_enemy_count(profile)
			check(count >= prior_count and count > 0, "Circuit keeps a growing opening roster on Bearing %d at depth %d" % [tier, depth])
			check(CONTRACTS.profile_objective_spawn_interval(profile) >= 1.25, "Later Circuit waves retain a travel interval on Bearing %d at depth %d" % [tier, depth])
			check(CONTRACTS.mutator_name(CONTRACTS.profile_enemy_mutator(profile)) == "Surge" and CONTRACTS.mutator_name(CONTRACTS.profile_player_mutator(profile)) == "Relay Boost", "Circuit retains its pressure identity and reward on Bearing %d at depth %d" % [tier, depth])
			prior_count = count
			print("[CircuitProfile] tier=%d depth=%d opening=%d interval=%.2f batch=%d" % [tier, depth, count, CONTRACTS.profile_objective_spawn_interval(profile), CONTRACTS.profile_objective_spawn_batch(profile)])
	builder.set_difficulty_tier(1)
	var early: Dictionary = builder._build_circuit_sweep_profile(5)
	check(CONTRACTS.profile_total_enemy_count(early) == 9 and CONTRACTS.profile_objective_spawn_batch(early) == 2, "Delver depth 5 opens with nine enemies and brings only two reinforcements")
	check(is_equal_approx(CONTRACTS.profile_objective_spawn_interval(early), 2.45), "Delver depth 5 leaves 2.45 seconds between waves")

func _test_live_circuit() -> void:
	await _enter_context("crumble", "circuit_sweep")
	world._exit_encounter_intro_grace()
	var manager := world.objective_manager
	var runtime := world.objective_runtime
	check(manager.sweep_node_count == 3 and runtime.get_pending_sweep_node_positions().size() == 2, "Real entry still creates three ordered capture nodes")
	check(is_equal_approx(manager.sweep_node_radius, 120.0), "Live capture ring gives the player a 120-pixel dodge radius")
	var reserved := world._get_biome_objective_exclusions()
	check(reserved.size() == 3 and reserved.all(func(region: Dictionary) -> bool: return is_equal_approx(float(region.radius), 120.0)), "The enlarged active and future nodes remain reserved from biome hazards")

	# Emptying the crowd must not silently replace the authored interval with a
	# half-second emergency refill. This is the principal pacing regression.
	world._clear_all_enemies()
	world.active_room_enemy_count = 0
	await process_frame
	manager.spawn_timer = manager.spawn_interval
	world.player.global_position = Vector2(360.0, 250.0)
	var interval := manager.spawn_interval
	runtime.update_circuit_sweep_objective_state(0.6)
	check(is_equal_approx(manager.spawn_timer, interval - 0.6) and world.active_room_enemy_count == 0, "Clearing pursuers earns the rest of the full wave interval")
	runtime.update_circuit_sweep_objective_state(interval - 0.61)
	check(world.active_room_enemy_count == 0, "Reinforcements do not arrive before their timer expires")
	runtime.update_circuit_sweep_objective_state(0.02)
	runtime._process_pending_objective_spawns(0.1)
	_freeze_context_actors()
	check(world.active_room_enemy_count == manager.spawn_batch and world.active_room_enemy_count > 0, "The next scheduled wave still arrives and uses the reduced batch")
	manager.spawn_timer = 100.0

	world.player.global_position = manager.sweep_node_position + Vector2(110.0, 0.0)
	runtime.update_circuit_sweep_objective_state(0.8)
	check(is_equal_approx(manager.sweep_capture_progress, 0.8), "The new outer 20 pixels actually capture, rather than merely drawing a larger ring")
	world.player.global_position = manager.sweep_node_position + Vector2(150.0, 0.0)
	runtime.update_circuit_sweep_objective_state(1.0)
	check(is_equal_approx(manager.sweep_capture_progress, 0.7), "A one-second dodge outside loses only a tenth of a second of capture")
	world.player.global_position = manager.sweep_node_position
	runtime.update_circuit_sweep_objective_state(manager.sweep_capture_goal - 0.7 + 0.01)
	check(manager.sweep_nodes_completed == 1 and is_zero_approx(manager.sweep_capture_progress), "Returning after a dodge completes only the current node")

	var ordinary_interval := manager.spawn_interval
	manager.time_left = 0.01
	world.player.global_position = Vector2(360.0, 250.0)
	runtime.update_circuit_sweep_objective_state(0.02)
	check(manager.overtime and manager.spawn_interval < ordinary_interval and manager.sweep_nodes_completed == 1, "The deadline still escalates to overtime without resetting earned nodes")
	manager.spawn_timer = 100.0
	for _node_index in range(2):
		world.player.global_position = manager.sweep_node_position
		runtime.update_circuit_sweep_objective_state(manager.sweep_capture_goal + 0.01)
	check(manager.active_objective_kind.is_empty() and world.active_room_enemy_count == 0, "Capturing the last node still clears the mission and remaining foes")
	check(world.reward_selection_ui.is_active(), "Circuit completion reaches the existing mission reward flow")
