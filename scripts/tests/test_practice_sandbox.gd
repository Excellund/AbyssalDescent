extends "res://scripts/tests/test_practice_vessels.gd"
## Staged real-actor integration; this is not an ordinary-input balance trace.
const CONFIG := preload("res://scripts/practice/practice_config.gd")
const DIFFICULTY := preload("res://scripts/difficulty_config.gd")

func _run() -> void:
	if not _is_isolated():
		quit(1)
		return
	_test_configuration_data()
	await _prepare_normal_checkpoint()
	_new_arena()
	await _start_default_attempt()
	await _test_atomic_drafts()
	await _test_complete_build()
	await _test_difficulty_and_floor()
	await _test_enemy_physics_and_terrain()
	await _test_complete_encounters()
	await _test_objective_conditions()
	_check_preserved("Full sandbox configuration, combat and terminal states")
	arena.request_menu()
	await process_frame
	await process_frame
	_check_preserved("Sandbox return to actual Menu")
	current_scene.queue_free()
	current_scene = null
	arena = null
	await process_frame
	await _test_normal_continue()
	await _cleanup_recovery_world()
	print("[OK] Practice sandbox: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_configuration_data() -> void:
	var defaults := CONFIG.defaults()
	check(CONFIG.validate(defaults).valid, "Default sandbox is a valid base Bastion/Warden encounter")
	var rows := CONFIG.catalogue(defaults)
	check(rows.characters.size() == 5 and rows.encounters.size() == 37 and not rows.has("enemies"), "Catalogue includes all5 Vessels and37 real encounter choices, including empty")
	check(rows.powers.size() == ARENA.POWERS.UPGRADE_POOL_IDS.size() + ARENA.POWERS.TRIAL_POWER_POOL_IDS.size() + ARENA.POWERS.BOSS_REWARD_POOL_IDS.size(), "Catalogue covers all three actual power pools")
	for row: Dictionary in rows.powers:
		check(not String(row.description).is_empty(), row.id + " has a real selection explanation")
		var configured := defaults.duplicate(true)
		configured.powers[row.id] = row.max_level
		if row.supports_prismatic:
			configured.prismatic = [row.id]
		check(CONFIG.validate(configured).valid, row.id + " permits its real maximum and supported Prismatic")
		configured.powers[row.id] = int(row.max_level) + 1
		check(not CONFIG.validate(configured).valid, row.id + " rejects levels beyond the real cap")
	var empty := defaults.duplicate(true)
	empty.encounter_id = "empty"
	check(CONFIG.validate(empty).valid, "An empty arena is a valid movement and build sandbox")
	for patch in [{"floor": 0}, {"floor": 26}, {"floor": {}}, {"bearing": 4}, {"bearing": {}}, {"character_id": "unknown"}, {"biome_id": "unknown"}, {"enemies": "invalid"}, {"enemies": [{"id": "chaser", "count": 33}]}, {"enemies": [{"id": "chaser", "count": 1}, {"id": "chaser", "count": 1}]}, {"enemies": [{"id": "unknown", "count": 1}]}, {"enemy_ai": 1}, {"invulnerable": "true"}, {"powers": []}, {"powers": {"heavy_blow": {}}}, {"prismatic": ["heavy_blow"]}, {"prismatic": ["static_wake"]}, {"ascension": ["hardened_foes"]}, {"catalysts": ["unknown"]}, {"character_id": "riftlancer", "powers": {"wide_arc": 1}}]:
		var invalid := defaults.duplicate(true)
		invalid.merge(patch, true)
		var before := invalid.duplicate(true)
		check(not CONFIG.validate(invalid).valid, "Invalid configuration is rejected: " + str(patch))
		CONFIG.catalogue(invalid)
		check(invalid == before, "Validation/catalogue never normalize the caller's malformed draft")
	rows.powers[0].description = "changed"
	rows.characters.clear()
	check(CONFIG.catalogue().characters.size() == 5 and CONFIG.catalogue().powers[0].description != "changed", "Catalogue returns detached nested data")
	check(CONFIG.act_for_floor(9) == 1 and CONFIG.act_for_floor(10) == 2 and CONFIG.act_for_floor(17) == 2 and CONFIG.act_for_floor(18) == 3 and CONFIG.act_for_floor(25) == 3, "Floors use normal act boundaries without inventing depth scaling")

func _apply(config: Dictionary) -> void:
	if arena.mode == "active":
		arena.request_pause()
	var previous := arena.attempt
	check(arena.request_config(config), "Editable mode accepts detached config")
	arena.request_apply()
	arena.request_apply()
	await process_frame
	await process_frame
	check(arena.mode == "active" and arena.attempt == previous + 1, "Apply atomically creates exactly one new attempt: " + arena.detail)
	if arena.mode == "error":
		push_error("Unable to continue sandbox fixture after failed configuration")
		quit(1)
		return
	check(arena.current_config == CONFIG.validate(config).config and arena.draft_config == arena.current_config, "Applied configuration exactly matches the validated draft")

func _test_atomic_drafts() -> void:
	var original := arena.player.get_instance_id()
	var configured := CONFIG.defaults()
	configured.character_id = "hexweaver"
	configured.powers = {"heavy_blow": 2, "static_wake": 3, "shatterwake": 1}
	configured.prismatic = ["static_wake"]
	configured.encounter_id = "crossfire"
	configured.biome_id = "storm_reach"
	configured.floor = 12
	configured.enemy_ai = false
	check(not arena.request_config(configured), "Live combat rejects stale editor changes")
	arena.request_pause()
	check(arena.request_config(configured), "Pause accepts a next attempt draft")
	configured.powers.heavy_blow = 3
	check(arena.draft_config.powers.heavy_blow == 2, "Draft input cannot mutate after submission")
	configured.powers.heavy_blow = 2
	var view := arena.presentation()
	view.draft_config.powers.clear()
	view.current_config.character_id = "threadbinder"
	check(arena.draft_config.powers.heavy_blow == 2 and arena.current_config.character_id == "bastion", "Presentation cannot mutate live or draft build state")
	arena.request_resume()
	check(arena.player.get_instance_id() == original and arena.current_config.character_id == "bastion" and arena.draft_config.character_id == "hexweaver", "Resume preserves live actor and pending edited configuration")
	arena.request_pause()
	var invalid := configured.duplicate(true)
	invalid.powers.heavy_blow = 99
	arena.request_config(invalid)
	arena.request_apply()
	check(not arena._transition_pending and arena.player.get_instance_id() == original and not arena.presentation().validation.valid, "Invalid build cannot retire or mutate the current actor")
	await _apply(configured)
	check(arena.player.get_max_health() == 75 and arena.player.damage == 42 and arena.player.iron_skin_armor == 0 and arena.player.get_upgrade_stack_count("shatterwake") == 1 and arena.player.has_trial_power_prismatic("static_wake"), "Full native-probe loadout uses real Hexweaver, Boon, Arcana and boss reward paths")
	check(arena.room_depth == 11 and arena.current_act == 2 and arena.environment.rules.rule_id == "storm_reach" and arena.active_room_enemy_count == ARENA.CONTRACTS.profile_total_enemy_count(arena.current_profile), "Floor, biome and actual Crossfire context commit together")
	var held := arena.player.get_instance_id()
	arena.request_configure()
	check(arena.mode == "setup" and arena.presentation().can_resume, "Configure retains a resumable paused attempt")
	arena.request_resume()
	check(arena.player.get_instance_id() == held and arena.mode == "active", "Leaving configuration resumes the same actor")

func _test_complete_build() -> void:
	var config := CONFIG.defaults()
	config.encounter_id = "empty"
	config.enemy_ai = false
	config.invulnerable = true
	for row: Dictionary in CONFIG.catalogue().powers:
		config.powers[row.id] = row.max_level
		if row.supports_prismatic:
			config.prismatic.append(row.id)
	await _apply(config)
	for row: Dictionary in CONFIG.catalogue().powers:
		var actual: int = arena.player.get_trial_power_stack_count(row.id) if row.category == "arcana" else arena.player.get_upgrade_stack_count(row.id)
		check(actual == row.max_level, row.id + " is applied through the actual owned-level store at its full cap")
		if row.supports_prismatic:
			check(arena.player.has_trial_power_prismatic(row.id), row.id + " applies its real Prismatic state")
	var hp := arena.player.get_current_health()
	arena.player.take_damage(999, {"source": "enemy_ability", "ability": "warden_nova"})
	check(arena.player.get_current_health() == hp and arena.player.combat_damage_enabled and not arena.presentation().has("damage_recap"), "Training immunity blocks damage without disabling player power processing or a Practice damage log")
	for _frame in 35:
		await physics_frame
	check(arena.mode == "active" and arena.presentation().enemy_count == 0 and arena.presentation().alive_count == 0, "Initially empty arena stays active without inventing victory")
	await _apply(CONFIG.defaults())
	check(arena.player.get_current_health() == 130 and arena.player.damage == 25 and arena.player.upgrade_system.upgrade_stacks.is_empty() and arena.player.upgrade_system.trial_power_stacks.is_empty() and not arena.player.practice_invulnerable, "Reset to defaults creates a clean actor without prior powers, Prismatic or immunity")

func _test_difficulty_and_floor() -> void:
	for tier in 4:
		var config := CONFIG.defaults()
		config.bearing = tier
		config.floor = 25
		config.enemy_ai = false
		config.catalysts = ["starting_max_hp_bonus", "damage_reduction"]
		if tier == 3:
			config.ascension = ["hardened_foes", "crowned_bosses", "pilgrims_burden"]
		await _apply(config)
		var expected := CONFIG.difficulty(config)
		var hp := int(round((130.0 + float(expected.player_starting_health_bonus)) * float(expected.get("player_max_health_mult", 1.0))))
		check(arena.player.get_max_health() == hp and arena.player.get_current_health() == hp, "Bearing/Catalyst/Ascension health follows normal addition-then-multiplication order")
		check(is_equal_approx(arena.player.incoming_damage_taken_mult, float(expected.player_damage_taken_mult)) and is_equal_approx(arena.player.incoming_contact_damage_mult, float(expected.enemy_contact_damage_mult)), "Bearing and applicable modifiers use exact normal incoming-damage factors")
		check(arena.boss.get_max_health() == int(round(1100.0 * float(expected.boss_difficulty_mult))), "Selected Warden uses real Bearing and Crowned Boss scaling")
		check(arena.current_act == 3 and arena.room_depth == 24 and arena.presentation().enemy_count == 1, "Late floor preserves chosen boss and normal depth context")

func _test_enemy_physics_and_terrain() -> void:
	var config := CONFIG.defaults()
	config.encounter_id = "breach"
	config.enemy_ai = false
	config.invulnerable = true
	config.powers = {"ruinous_impact": 1, "razor_orbit": 2}
	await _apply(config)
	var chaser: Node2D
	var keeper: Node2D
	for actor in arena.enemies:
		if actor.get_meta("practice_enemy_id") == "chaser":
			chaser = actor
		if actor.get_meta("practice_enemy_id") == "keeper":
			keeper = actor
		check(actor.is_physics_processing() and not actor.combat_ai_enabled, "AI-off retains transport/status/displacement for " + String(actor.get_meta("practice_enemy_id")))
	check(is_instance_valid(chaser) and is_instance_valid(keeper), "Real Breach includes its Keeper and vulnerable allies")
	chaser.apply_slow(0.1, 0.5)
	for _frame in 35:
		await physics_frame
	check(not chaser.is_spawn_transporting() and not chaser.is_slowed(), "AI-off transport and accepted Slow expiry keep running")
	check(not keeper._can_ward() and keeper.ward_targets.is_empty(), "AI-off Keeper cannot create autonomous wards")
	chaser.position = Vector2(-120, 0)
	var origin: Vector2 = chaser.position
	arena.player.boss_combinations.launch_enemy(chaser, Vector2.RIGHT * 450.0, 1)
	for _frame in 10:
		await physics_frame
	check(chaser.position.distance_to(origin) > 10.0, "AI-off processes real Ruinous displacement")
	var cover := arena.environment.cover
	if cover.has_brittle_cover():
		var row: Dictionary = cover.snapshot()[0]
		var column: StaticBody2D = arena.environment.bodies[row.id]
		arena.player.position = column.position - Vector2(50, 0)
		for index in 3:
			var action: Dictionary = INTERACTIONS.damage_context(arena.player.new_combat_action("melee"), "melee").interaction
			arena.request_brittle_cover_attack(action, arena.player.position, Vector2.RIGHT)
			arena.request_brittle_cover_attack(action, arena.player.position, Vector2.RIGHT)
			check(cover.contacts_left(row.id) == 2 - index, "Each accepted Attack contacts actual brittle cover only once")
		check(not column.is_in_group("arena_columns"), "Broken cover leaves collision and Orbit geometry")
	config.encounter_id = "apex_trial"
	await _apply(config)
	var seam: Node2D
	for actor in arena.enemies:
		if actor.get_meta("practice_enemy_id") == "seamlock":
			seam = actor
	check(is_instance_valid(seam), "Apex Seamlock preserves its real boss amid escorts")
	seam._set_shared_arena_penalty_steps(1)
	seam._update_arena_penalty_lerp(1.0)
	arena._refresh_effective_bounds()
	check(arena.current_effective_room_size.x < arena.current_room_size.x and arena.renderer.room_size == arena.current_effective_room_size and arena.environment.rules.room_size == arena.current_effective_room_size, "Real Seamlock penalty reaches physical bounds, rendering and biome context")

func _test_complete_encounters() -> void:
	for row: Dictionary in CONFIG.catalogue().encounters:
		var config := CONFIG.defaults()
		config.encounter_id = row.id
		config.floor = 18
		config.bearing = 3
		config.enemy_ai = false
		config.invulnerable = true
		config.ascension = ["hardened_foes", "relentless_tide", "specialist_pressure", "shrunken_arcana"]
		config.catalysts = ["wave_interval_bonus"]
		await _apply(config)
		check(arena.current_room_size == ARENA.CONTRACTS.profile_room_size(arena.current_profile), row.id + " uses actual encounter geometry")
		check(arena.environment.cover.live_layout() == ARENA.CONTRACTS.profile_obstacle_layout(arena.current_profile), row.id + " uses authored terrain")
		check(not arena.presentation().has("damage_recap") and arena.run_summary_recorder == null, row.id + " has no Practice recap or run recorder")
		check(is_equal_approx(arena.enemy_spawner.bearing_wave_interval_seconds, float(CONFIG.difficulty(config).wave_interval_seconds)), row.id + " applies actual cadence modifiers")
		if row.category == "mission":
			check(arena.objective_manager.active_objective_kind == row.id and arena.presentation().objective_state.active, row.id + " runs its real Mission state")
			check(arena.objective_overlay.objective_manager == arena.objective_manager, row.id + " draws the real objective overlay")
			check(arena.environment.rules.mode == "compact", row.id + " preserves compact biome mode")
		else:
			check(not arena.presentation().objective_state.active, row.id + " does not invent an objective")
		if row.category in ["boss", "apex"]:
			check(arena.environment.rules.mode == "assistance", row.id + " preserves boss/Apex biome assistance")
		if row.category == "trial":
			var actual := ARENA.CONTRACTS.profile_enemy_mutator(arena.current_profile)
			var expected := arena.encounter_profile_builder._scale_mutator_damage(arena.encounter_profile_builder.build_debug_mutator(String(row.id).trim_prefix("trial_")))
			check(actual == expected, row.id + " uses its exact selected mutator with normal damage scaling once")
		for actor in arena.enemies:
			check(EnemyReplicationService.enemy_nodes_by_id.get(actor.get_instance_id()) == actor and not actor.combat_ai_enabled, row.id + " spawn owns accepted-damage identity and AI option")
			for obstacle: Dictionary in arena.environment.cover.live_layout():
				check(actor.position.distance_to(obstacle.pos) >= float(obstacle.radius) + 13.0, row.id + " spawn clears authored terrain")
		var profile := arena.current_profile.duplicate(true)
		var old_environment: WeakRef = weakref(arena.environment)
		await _apply(config)
		check(arena.current_profile == profile and old_environment.get_ref() == null, row.id + " Retry repeats the same profile while retiring old effects")
		# Run a bounded real-clock slice to exercise initial objective callbacks.
		for _frame in 4:
			await physics_frame
	await _test_staggered_wave_completion()

func _test_staggered_wave_completion() -> void:
	var config := CONFIG.defaults()
	config.encounter_id = "gauntlet"
	config.bearing = 3
	config.enemy_ai = false
	config.invulnerable = true
	await _apply(config)
	arena.set_process(false)
	arena.enemy_spawner.set_process(false)
	check(not arena.enemy_spawner._pending_waves.is_empty(), "Gauntlet retains its real staggered waves")
	var planned := arena.active_room_enemy_count
	var initial := arena.enemies.size()
	check(planned > initial, "Planned count reserves enemies not yet spawned")
	for actor in arena.get_live_enemies():
		actor.health_state.set_health(0)
	check(arena.mode == "active" and arena.active_room_enemy_count == planned - initial, "Killing the first wave cannot complete a pending encounter")
	var timer: float = arena.enemy_spawner._wave_timer_remaining
	arena.request_pause()
	arena.enemy_spawner._process(60.0)
	check(arena.enemy_spawner._wave_timer_remaining == timer and arena.enemies.size() == initial, "Pause freezes native wave timers and births")
	arena.request_resume()
	while not arena.enemy_spawner._pending_waves.is_empty():
		arena.enemy_spawner._process(60.0)
		arena.enemy_spawner._process(60.0)
		for actor in arena.get_live_enemies():
			actor.health_state.set_health(0)
	check(arena.mode == "victory" and arena.active_room_enemy_count == 0 and arena.enemies.size() == planned, "Only the final actual wave death completes the encounter")
	arena.set_process(true)

func _test_objective_conditions() -> void:
	for kind in ["last_stand", "cut_the_signal", "hold_the_line", "circuit_sweep", "pulse_window", "intercept_run", "relic_recovery"]:
		var config := CONFIG.defaults()
		config.encounter_id = kind
		config.floor = 4
		config.enemy_ai = false
		config.invulnerable = true
		await _apply(config)
		arena.set_process(false)
		arena.player.set_physics_process(false)
		arena.enemy_spawner.set_process(false)
		var manager := arena.objective_manager
		for actor in arena.get_live_enemies():
			if actor != manager.hunt_target_enemy:
				actor.health_state.set_health(0)
		await process_frame
		check(arena.mode == "active", kind + " does not complete merely because ordinary foes died")
		var before := manager.get_hud_state()
		arena.request_pause()
		arena._process(30.0)
		check(manager.get_hud_state() == before, kind + " Pause freezes objective progress, timers and pending spawns")
		arena.request_resume()
		arena.player.set_physics_process(false)
		if kind in ["hold_the_line", "circuit_sweep", "intercept_run", "relic_recovery"]:
			check(not arena._get_biome_objective_exclusions().is_empty(), kind + " reserves the actual objective route from hazards")
		match kind:
			"last_stand", "pulse_window":
				manager.kills = manager.kill_target - 1
				manager.time_left = 0.0
				manager.overtime = true
				var target := arena.enemy_spawner.spawn_enemy_node_type("chaser")
				arena.active_room_enemy_count += 1
				target.health_state.set_health(0)
				arena._process(0.01)
			"cut_the_signal":
				manager.hunt_target_enemy.health_state.set_health(0)
			"hold_the_line":
				arena.player.position = manager.control_anchor
				manager.control_progress = manager.control_goal - 0.01
				arena._process(0.1)
			"circuit_sweep":
				for _node in 3:
					arena.player.position = manager.sweep_node_position
					manager.sweep_capture_progress = manager.sweep_capture_goal - 0.01
					arena._process(0.1)
			"intercept_run":
				arena.player.position = manager.intercept_drone_position
				manager.intercept_drone_progress = 0.99999
				arena._process(0.1)
			"relic_recovery":
				check(arena.current_profile.obstacle_layout.is_empty(), "Recovery retains its authored open pickup arena")
				for relic: Dictionary in manager.relic_recovery.relics:
					arena.player.position = relic.position
					arena._process(0.01)
					arena.player.position = manager.relic_recovery.receiver
					arena._process(0.01)
		check(arena.mode == "victory" and arena.active_room_enemy_count == 0 and arena.enemy_spawner._pending_waves.is_empty(), kind + " native condition completes only this Practice attempt and retires waves")
		check(arena.player.upgrade_system.upgrade_stacks.is_empty() and arena.player.upgrade_system.trial_power_stacks.is_empty(), kind + " completion grants no reward or Mission bonus")
		arena.set_process(true)
	_check_preserved("All actual Mission completion conditions")
