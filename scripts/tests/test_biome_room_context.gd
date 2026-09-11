extends "res://scripts/tests/test_descent_presentation.gd"
## Real door entry keeps authored arenas while every combat category gets the
## correct biome mode. Controller unit/ENet fixtures cover hostile packets.

const RULES := preload("res://scripts/core/biome_rule_controller.gd")
const BOSSES := preload("res://scripts/shared/boss_catalogue.gd")
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const COMPACT_KEYS := ["last_stand", "cut_the_signal", "hold_the_line", "circuit_sweep", "pulse_window", "intercept_run", "trial", "breach", "undertow"]
const APEX_KEYS := ["apex_trial", "apex_mirrorline", "apex_toll", "apex_breakwater"]
const PLAYER_FOOTPRINT := 22.63

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	await _setup_context_world()
	await _test_real_room_matrix()
	await _test_real_boss_matrix()
	await _test_live_objectives_and_bounds()
	await _test_environmental_ownership()
	await _test_context_lifecycle()
	await _dispose_context_world()
	print("[BiomeRoomContext] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _setup_context_world() -> void:
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-biome-room-context")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "bastion"
	RunContext.current_difficulty_tier = 1
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.set_physics_process(false)
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	_freeze_context_actors()
	await process_frame

func _freeze_context_actors() -> void:
	world.player.set_physics_process(false)
	world.enemy_spawner.set_process(false)
	world.enemy_spawner.set_physics_process(false)
	for enemy in _context_enemies():
		enemy.set_physics_process(false)
		enemy.set_process(false)
		enemy.set("spawn_transport_time_left", 0.0)
		enemy.queue_redraw()

func _context_enemies() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for enemy in get_nodes_in_group("enemies"):
		if enemy is Node2D and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			result.append(enemy)
	return result

func _enter_context(biome_id: String, key: String) -> Dictionary:
	world.reward_selection_ui.close_selection()
	world.player.set_alive(true)
	world.player.set_health(world.player.get_max_health())
	world.player._update_external_slow(10.0)
	world.room_depth = 5
	world.first_boss_defeated = false
	world.second_boss_defeated = false
	world.run_session.act_biome_ids = [biome_id, biome_id, biome_id]
	world._apply_active_biome(1)
	world.encounter_profile_builder.rng.seed = 91741
	var profile: Dictionary = world.encounter_profile_builder.build_debug_encounter_profile(key, 5)
	var door: Dictionary
	if APEX_KEYS.has(key):
		door = CONTRACTS.apex_trial_door_option(profile, CONTRACTS.profile_label(profile), Color.WHITE)
	elif key == "trial":
		door = CONTRACTS.trial_door_option(profile, CONTRACTS.mutator_name(CONTRACTS.profile_enemy_mutator(profile)), Color.WHITE)
	elif CONTRACTS.debug_encounter_is_objective(key):
		door = CONTRACTS.objective_door_option(profile)
	else:
		door = CONTRACTS.standard_encounter_door_option(profile)
	world._choose_door(door)
	_freeze_context_actors()
	world._sync_renderer()
	world.hud.refresh(world._get_hud_state(), world.player)
	await process_frame
	return profile

func _enter_context_boss(biome_id: String, id: String) -> Node2D:
	world.reward_selection_ui.close_selection()
	world.player.set_alive(true)
	world.player.set_health(world.player.get_max_health())
	world.player._update_external_slow(10.0)
	var stage := BOSSES.stage_for_id(id)
	world.first_boss_defeated = stage >= 2
	world.second_boss_defeated = stage >= 3
	world.run_session.act_biome_ids = [biome_id, biome_id, biome_id]
	world.run_session.act_boss_ids = BOSSES.normalize_roster(BOSSES.DEFAULT_IDS)
	world.run_session.act_boss_ids[stage - 1] = id
	world._choose_door(CONTRACTS.boss_door_option(BOSSES.DEFAULT_IDS[stage - 1]))
	_freeze_context_actors()
	world._sync_renderer()
	world.hud.refresh(world._get_hud_state(), world.player)
	await process_frame
	for enemy in _context_enemies():
		if String(enemy.get_meta("boss_id", "")) == id:
			return enemy
	return null

func _start_context_combat() -> void:
	world._signal_local_player_ready()
	_freeze_context_actors()
	check(not world.encounter_intro_grace_active and world.player.combat_damage_enabled, "Real readiness starts biome combat without an extra delay")

func _context_phase(requested: String) -> Dictionary:
	for _step in range(8):
		var state: Dictionary = world._biome_rules.snapshot()
		if String(state.phase) == requested:
			return state
		world._tick_biome_rules(20.0)
	check(false, "Live world reaches biome phase " + requested)
	return world._biome_rules.snapshot()

func _sample_shape(geometry: Dictionary) -> Vector2:
	var half := world.current_effective_room_size * .5
	for x in range(int(-half.x + 25), int(half.x - 25), 15):
		for y in range(int(-half.y + 25), int(half.y - 25), 15):
			var point := Vector2(x, y)
			if RULES.geometry_contains(geometry, point):
				return point
	check(false, "Committed biome shape has an actual point inside the room")
	return Vector2.ZERO

func _required_objective_disks() -> Array[Dictionary]:
	# Read actual objective state, independently of the production exclusion
	# extractor, including the route's future positions.
	var manager: Node = world.objective_manager
	var result: Array[Dictionary] = []
	match String(manager.active_objective_kind):
		"hold_the_line":
			result.append({"center": manager.control_anchor, "radius": manager.control_radius})
		"circuit_sweep":
			result.append({"center": manager.sweep_node_position, "radius": manager.sweep_node_radius})
			for point: Vector2 in world.objective_runtime._sweep_pending_node_positions:
				result.append({"center": point, "radius": manager.sweep_node_radius})
		"intercept_run":
			for step in range(17):
				result.append({"center": (manager.intercept_start as Vector2).lerp(manager.intercept_end, float(step) / 16.0), "radius": manager.intercept_drone_radius})
	return result

func _check_objective_clearance(state: Dictionary, label: String) -> void:
	if String(state.mode) == "assistance":
		return
	var clear := true
	for disk in _required_objective_disks():
		clear = clear and not RULES.geometry_contains(state.shape, disk.center, PLAYER_FOOTPRINT)
		for sample in range(32):
			var point: Vector2 = disk.center + Vector2.from_angle(TAU * float(sample) / 32.0) * float(disk.radius)
			clear = clear and not RULES.geometry_contains(state.shape, point, PLAYER_FOOTPRINT)
	check(clear, label + ": current/future mandatory objective space fits a real player footprint outside the warning")

func _check_assistance_player_safe(state: Dictionary, label: String) -> void:
	world.player.global_position = _sample_shape(state.shape)
	world.player._update_external_slow(10.0)
	var before := world.player.get_current_health()
	_context_phase("active")
	world._tick_biome_rules(.1)
	check(world.player.get_current_health() == before and world.player.external_slow_left == 0.0, label + ": assistance cannot damage or Slow a real player inside its full impact area")

func _test_real_room_matrix() -> void:
	for biome_id: String in BIOMES.BIOME_DEFINITIONS:
		for key: String in ["crossfire"] + COMPACT_KEYS + APEX_KEYS:
			var profile := await _enter_context(biome_id, key)
			var label := biome_id + "/" + key
			var layout := CONTRACTS.profile_obstacle_layout(profile)
			check(world.renderer.obstacle_layout == layout and world._active_obstacle_nodes.size() == layout.size(), label + ": real door keeps the authored visual and physical arena")
			check(world.door_options.is_empty() and not world.choosing_next_room and is_instance_valid(world._biome_rules), label + ": chosen route installs its own room controller")
			var initial: Dictionary = world._biome_rules.snapshot()
			check(initial.id == biome_id and not world._get_biome_rule_hint().is_empty(), label + ": entered biome has a persistent contextual rule hint")
			var expected := "assistance" if APEX_KEYS.has(key) else ("ordinary" if key == "crossfire" else "compact")
			check(initial.mode == expected or (expected == "compact" and initial.mode == "assistance"), label + ": room category selects ordinary, compact or objective-safe assistance")
			check(not bool(initial.fragments) if biome_id != "shatterfield" or key == "crossfire" else bool(initial.fragments), label + ": Shatter fragments are selected only from entry cover availability")
			_start_context_combat()
			if biome_id == "shatterfield" and key == "crossfire":
				for cover_id in [2, 3]:
					for _contact in range(3): world._arena_cover.apply_contact(cover_id)
				world._refresh_arena_cover_geometry()
				world._tick_biome_rules(20.0)
				check(world._biome_rules.phase == "idle" and not world._biome_rules.snapshot().fragments, "Breaking the original Shatterfield cover never starts a new fragment hazard")
				continue
			var warning := _context_phase("warning")
			check(not (warning.shape as Dictionary).is_empty(), label + ": every entered combat biome commits a visible event")
			_check_objective_clearance(warning, label)
			if warning.mode == "assistance": _check_assistance_player_safe(warning, label)

func _test_real_boss_matrix() -> void:
	for biome_id: String in BIOMES.BIOME_DEFINITIONS:
		for id: String in BOSSES.NAMES:
			var boss := await _enter_context_boss(biome_id, id)
			check(is_instance_valid(boss), biome_id + "/" + id + ": real selected boss door creates the native boss")
			check(world._biome_rules.snapshot().mode == "assistance" and world._active_obstacle_nodes.is_empty(), biome_id + "/" + id + ": assistance preserves the authored open boss arena")
			_start_context_combat()
			var warning := _context_phase("warning")
			_check_assistance_player_safe(warning, biome_id + "/" + id)

func _test_live_objectives_and_bounds() -> void:
	await _enter_context("crumble", "circuit_sweep")
	_start_context_combat()
	var warning := _context_phase("warning")
	_check_objective_clearance(warning, "Circuit before capture")
	world.player.global_position = world.objective_manager.sweep_node_position
	world.objective_runtime.update_circuit_sweep_objective_state(world.objective_manager.sweep_capture_goal + .01)
	world._tick_biome_rules(.01)
	check(world.objective_manager.sweep_nodes_completed == 1, "A real Circuit capture advances to its reserved future node")
	_check_objective_clearance(world._biome_rules.snapshot(), "Circuit after capture")
	await _enter_context("storm_reach", "hold_the_line")
	_start_context_combat()
	warning = _context_phase("warning")
	if warning.mode == "compact":
		world.objective_manager.control_anchor = _sample_shape(warning.shape)
		world._tick_biome_rules(.01)
		check(world._biome_rules.phase == "recovery" and world._biome_rules.shape.is_empty(), "A changed required control zone cancels the committed hazard instead of moving it")
		var replacement := _context_phase("warning")
		check(is_equal_approx(float(replacement.left), float(replacement.duration)), "Replacement objective-compatible event begins with its complete warning")
		_check_objective_clearance(replacement, "Relocated control zone")
	await _enter_context("hollow", "apex_trial")
	_start_context_combat()
	_context_phase("warning")
	var original_bounds := world.current_effective_room_size
	for enemy in _context_enemies():
		if enemy.get("_arena_penalty_applied_steps") != null:
			enemy.set("_arena_penalty_applied_steps", 2.0)
	world._refresh_effective_room_bounds_from_seamlock_penalty()
	world._tick_biome_rules(.01)
	check(world.current_effective_room_size.x < original_bounds.x and world._biome_rules.snapshot().bounds_size == world.current_effective_room_size, "Live native Seamlock shrink reaches the biome controller's actual bounds")
	check(world._biome_rules.phase == "recovery" and world._biome_rules.shape.is_empty(), "Live shrink retires the old committed warning before any impact")
	# Exercise the separate door path directly from an active Mission.
	await _enter_context("haunt", "hold_the_line")
	await _enter_context_boss("haunt", "warden")
	check(String(world.objective_manager.active_objective_kind).is_empty(), "Mission-to-boss entry clears the preceding objective state")
	await _enter_context("storm_reach", "crossfire")
	check(world._biome_rules.snapshot().mode == "ordinary" and world._biome_rules.room_size == world.current_effective_room_size, "Boss-to-ordinary entry restores the normal rule and fresh room bounds")
	await _enter_context("hollow", "intercept_run")
	_start_context_combat()
	# Force the valid no-placement path while its native entry banner is still
	# visible; later HUD refresh must replace the former hostile instruction.
	world.objective_manager.intercept_drone_radius = world.current_effective_room_size.length()
	world.hud.room_banner_tween.custom_step(.3)
	_context_phase("warning")
	world.hud.refresh(world._get_hud_state(), world.player)
	check(world._biome_rules.mode == "assistance" and world.hud.room_banner_subtitle_label.modulate.a > 0.0 and world.hud.room_banner_subtitle_label.text == world._get_biome_rule_hint(), "A live biome entry banner immediately adopts safe assistance wording after placement fallback")

func _test_environmental_ownership() -> void:
	await _enter_context("storm_reach", "pulse_window")
	world.player.apply_upgrade("edict_of_the_court")
	world.player.apply_upgrade("lacuna_echo")
	world.player.apply_trial_power("stormbrand")
	_start_context_combat()
	var warning := _context_phase("warning")
	var point := _sample_shape(warning.shape)
	var enemy := preload("res://scripts/enemy_chaser.gd").new()
	enemy.max_health = 1
	world.add_child(enemy)
	enemy.global_position = point
	enemy.set_physics_process(false)
	enemy.spawn_transport_time_left = 0.0
	enemy.died.connect(func(): world._on_room_enemy_died(point))
	var witness := preload("res://scripts/enemy_chaser.gd").new()
	witness.max_health = 10000
	world.add_child(witness)
	witness.global_position = point
	witness.set_physics_process(false)
	witness.spawn_transport_time_left = 0.0
	var previous := DAMAGEABLE.begin_interaction_scope(world.player.new_combat_action("melee"))
	_context_phase("active")
	DAMAGEABLE.end_interaction_scope(previous)
	check(world.player.void_echo_zones.is_empty() and witness.get_current_health() == 9950, "Host environmental Kill cannot create a player's Lacuna or Edict even inside an existing Attack scope")
	check(DAMAGEABLE.status_snapshot(witness, world.player.player_id).mark_ratio == 0.0, "Biome lightning is environmental damage and cannot grant the player's Stormbrand Mark")
	await process_frame

func _test_context_lifecycle() -> void:
	await _enter_context("crumble", "pulse_window")
	_start_context_combat()
	var warning := _context_phase("warning")
	world.pause_menu_controller.open()
	world._tick_biome_rules(20.0)
	check(world._biome_rules.phase == "warning" and world._biome_rules.phase_left == warning.left, "Real Pause freezes a committed compact event")
	world.pause_menu_controller.close()
	world.combat_phase_coordinator.end_combat_phase(world.player, self)
	world._tick_biome_rules(20.0)
	check(world._biome_rules.phase == "warning" and world._biome_rules.phase_left == warning.left, "Reward/death combat shutdown cannot resolve the pending impact")
	world._enter_rest_site()
	check(world._biome_rules.rule_id.is_empty() and world._get_biome_rule_hint().is_empty(), "A real noncombat Rest route clears the preceding biome event and hint")

func _dispose_context_world() -> void:
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after the room matrix")
