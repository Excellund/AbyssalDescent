extends "res://scripts/tests/test_relic_recovery_live_combat.gd"
## Two registered, bounded pilots. A defeat/timeout is retained evidence, not a
## reason to reroll. Only ordinary inputs change the run after bootstrap.

const RUNS := [{"seed": 12092026, "rest": "recover"}, {"seed": 12092027, "rest": "invest"}]
const MAX_RUN_FRAMES := 21600
const REWARD_PRIORITY := ["razor_wind", "rupture_wave", "execution_edge", "hunters_snare", "returning_crescent", "heavy_blow", "iron_skin", "heartstone", "long_reach", "severing_edge", "first_strike", "blink_dash"]
var run_receipts: Array[Dictionary] = []
var events: Array[Dictionary] = []
var rest_policy := "recover"
var selected_door: Dictionary = {}
var last_room_signature := ""
var visited_recovery := false
var visited_rest := false
var run_start_frame := 0
var door_selection_frames := 0

class SeededWorld:
	extends "res://scripts/world_generator.gd"
	var fixture_seed := 0
	func _initialize_bootstrap_context() -> void:
		super._initialize_bootstrap_context()
		rng.seed = fixture_seed

func _run() -> void:
	if not _is_isolated() or DisplayServer.get_name() != "headless":
		push_error("Ordinary progression evidence requires an isolated headless project")
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	for config in RUNS:
		await _run_registered_pilot(config)
		FileAccess.open("res://ordinary_first_act.json", FileAccess.WRITE).store_string(JSON.stringify({"registered_runs": RUNS, "runs": run_receipts, "checks": checks, "failures": failures}, "\t"))
	print("[OK] Ordinary first-act evidence: %d checks, %d invariant failures, %d registered attempts" % [checks, failures.size(), run_receipts.size()])
	quit(0 if failures.is_empty() else 1)

func _setup_ordinary_world(run_seed: int) -> void:
	seed(run_seed)
	ProjectSettings.set_setting("application/config/version", "dev-ordinary-first-act")
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
	# Preserve every authored exported property while substituting the seed-only
	# subclass. Main's children, bootstrap, choices and frame loops remain real.
	var exported: Dictionary = {}
	for property in world.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
			exported[String(property.name)] = world.get(property.name)
	world.set_script(SeededWorld)
	for property_name in exported:
		world.set(property_name, exported[property_name])
	world.set("fixture_seed", run_seed)
	world.name = "World"
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	check(world.room_depth == 0 and world.rooms_cleared == 0 and world.reward_selection_ui.pending_initial_boon, "Registered pilot begins at the real starting draft")
	check(world.player.max_health == 130 and world.player.get_current_health() == 130 and world.player.damage == 25 and is_equal_approx(world.player.max_speed, 188.0), "Pilot begins with ordinary Delver Bastion stats")
	check(world.player.get_active_objective_mutators().is_empty() and RunContext.get_active_catalyst_ids().is_empty(), "Pilot has no initial Mission effects or Catalysts")
	world.player.primary_attack_fired.connect(func(): attacks += 1)
	world.player.normal_dash_started.connect(func(): dashes += 1)
	world.player.damage_taken.connect(func(_raw: int, accepted: int, _context: Dictionary): accepted_health_loss += accepted)

func _run_registered_pilot(config: Dictionary) -> void:
	rest_policy = String(config.rest)
	events.clear()
	selected_door.clear()
	last_room_signature = ""
	visited_recovery = false
	visited_rest = false
	attacks = 0
	dashes = 0
	enemy_hits = 0
	enemy_kills = 0
	accepted_health_loss = 0
	enemies_seen.clear()
	aim_samples = 0
	aim_checks = 0
	aim_mismatches = 0
	disabled_damage_frames = 0
	door_selection_frames = 0
	_setup_ordinary_world(int(config.seed))
	run_start_frame = Engine.get_physics_frames()
	var outcome := "time_limit"
	for frame in MAX_RUN_FRAMES:
		if world.player.is_dead():
			outcome = "defeated"
			break
		_record_room_entry()
		if world.reward_selection_ui.is_active():
			await _choose_ordinary_reward()
			if world.first_boss_defeated:
				outcome = "first_act_cleared"
				break
		elif world.choosing_next_room:
			_drive_offered_door(frame)
		else:
			_observe_enemies()
			if not world.encounter_intro_grace_active and not world.player.combat_damage_enabled:
				disabled_damage_frames += 1
			_drive_controls(_objective_destination(), frame)
		await physics_frame
		if frame % 600 == 0:
			print("[ORDINARY] seed=%d policy=%s %.1fs room=%s depth=%d HP=%d enemies=%d" % [int(config.seed), rest_policy, _elapsed(), world.current_room_label, world.room_depth, world.player.get_current_health(), world.active_room_enemy_count])
	_release_controls()
	check(disabled_damage_frames == 0, "Every active combat frame keeps damage enabled")
	check(aim_mismatches == 0, "Ordinary pointer aiming reaches the real Attack path")
	var result := {"seed": config.seed, "rest_policy": rest_policy, "outcome": outcome, "elapsed_seconds": _elapsed(), "ending": _state(), "visited_recovery": visited_recovery, "visited_rest": visited_rest, "attacks": attacks, "dashes": dashes, "enemy_hits": enemy_hits, "enemy_kills": enemy_kills, "damage_taken": accepted_health_loss, "aim_samples": aim_samples, "aim_mismatches": aim_mismatches, "disabled_damage_frames": disabled_damage_frames, "events": events.duplicate(true)}
	run_receipts.append(result)
	print("[ORDINARY RESULT] seed=%d outcome=%s %.2fs depth=%d HP=%d Recovery=%s Rest=%s" % [int(config.seed), outcome, _elapsed(), world.room_depth, world.player.get_current_health(), visited_recovery, visited_rest])
	await _cleanup_recovery_world()

func _elapsed() -> float:
	return float(Engine.get_physics_frames() - run_start_frame) / Engine.physics_ticks_per_second

func _state() -> Dictionary:
	return {"seconds": _elapsed(), "room": world.current_room_label, "depth": world.room_depth, "clears": world.rooms_cleared, "health": world.player.get_current_health(), "max_health": world.player.get_max_health(), "build": world._get_active_player_powers().duplicate(true), "temporary_effects": world.player.get_active_objective_mutators()}

func _record_room_entry() -> void:
	var signature := "%s:%d:%d" % [world.current_room_label, world.room_depth, world.get_current_room_sync_id()]
	if signature == last_room_signature:
		return
	last_room_signature = signature
	selected_door.clear()
	visited_recovery = visited_recovery or world.objective_manager.active_objective_kind == "relic_recovery"
	visited_rest = visited_rest or world.current_room_label == "Rest Site"
	events.append({"event": "room_state", "state": _state()})

func _choose_ordinary_reward() -> void:
	_release_controls()
	var ui: Node = world.reward_selection_ui
	var index := 0
	if ui.reward_selection_mode == ENUMS.RewardMode.REST:
		if rest_policy == "invest" and ui.boon_choices.size() > 1:
			index = 1
	else:
		var best_rank := REWARD_PRIORITY.size()
		for candidate in ui.boon_choices.size():
			var rank := REWARD_PRIORITY.find(String(ui.boon_choices[candidate].get("id", "")))
			if rank >= 0 and rank < best_rank:
				best_rank = rank
				index = candidate
	var before := _state()
	var offers: Array = ui.boon_choices.duplicate(true)
	if offers.is_empty():
		check(false, "Ordinary reward has a selectable card")
		return
	for _frame in 90:
		await physics_frame
	var card: Control = ui.boon_card_panels[index]
	_move_pointer(card.get_global_transform_with_canvas() * (card.size * 0.5))
	await process_frame
	await process_frame
	check(ui.boon_hovered_index == index, "Actual pointer selects the chosen offered card")
	Input.action_press("attack")
	for _frame in 3:
		await physics_frame
	Input.action_release("attack")
	for _frame in 4:
		await process_frame
	check(not ui.is_active(), "Normal reward input resolves the offered card once")
	events.append({"event": "reward", "offers": offers, "chosen": offers[index], "before": before, "after": _state()})

func _drive_offered_door(frame: int) -> void:
	if selected_door.is_empty() and not world.door_options.is_empty():
		var best_score := -10000
		for door: Dictionary in world.door_options:
			var kind := CONTRACTS.door_option_kind_id(door)
			var key := CONTRACTS.door_option_encounter_key(door)
			var score := 0
			if key == "relic_recovery" and not visited_recovery: score = 100
			elif kind == ENUMS.DoorKind.REST and not visited_rest: score = 90
			elif kind == ENUMS.DoorKind.BOSS: score = 80
			elif CONTRACTS.door_option_reward_mode(door) == ENUMS.RewardMode.BOON: score = 50
			elif CONTRACTS.door_option_reward_mode(door) == ENUMS.RewardMode.MISSION: score = 20
			if score > best_score:
				best_score = score
				selected_door = door.duplicate(true)
		events.append({"event": "door_choice", "offers": world.door_options.duplicate(true), "chosen": selected_door.duplicate(true), "state": _state()})
	if selected_door.is_empty():
		_release_controls()
		return
	var destination := CONTRACTS.door_option_get_position(selected_door)
	_drive_controls(destination, frame)
	if world.player.global_position.distance_to(destination) <= world.door_use_radius - 10.0 and frame % 2 == 0:
		Input.action_press("interact")

func _objective_destination() -> Vector2:
	var manager: Node = world.objective_manager
	match manager.active_objective_kind:
		"relic_recovery":
			if not manager.relic_recovery.carrier_has_relic(maxi(1, world.player.player_id)):
				for relic in manager.relic_recovery.relics:
					if not bool(relic.delivered): return relic.position
		"circuit_sweep": return manager.sweep_node_position
		"hold_the_line": return manager.control_anchor
		"intercept_run": return manager.intercept_drone_position
	return Vector2.ZERO

func _release_controls() -> void:
	super._release_controls()
	Input.action_release("interact")
