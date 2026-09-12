extends "res://scripts/tests/test_relic_recovery.gd"
## Bounded live-combat smoke. Setup selects an early room; after entry the
## ordinary Main/actor frame loops own all combat, movement and retrieval.
var receipt: Dictionary = {}
var elapsed := 0.0
var attacks := 0
var dashes := 0
var enemy_hits := 0
var enemy_kills := 0
var accepted_health_loss := 0
var enemies_seen: Dictionary = {}
var greatest_enemy_movement := 0.0
var travel_distance := 0.0
var latest_position := Vector2.ZERO
var largest_position_step := 0.0
var observed_deliveries := 0
var aim_checks := 0
var aim_samples := 0
var aim_mismatches := 0
var disabled_damage_frames := 0

func _run() -> void:
	if not _is_isolated() or DisplayServer.get_name() != "headless":
		push_error("Live combat smoke requires the isolated headless helper; native root windows read the OS cursor")
		quit(1)
		return
	seed(12092026)
	_setup_recovery_world()
	world.encounter_profile_builder.rng.seed = 12092026
	var profile := _enter_recovery()
	var player := world.player
	var sites := CONTRACTS.profile_relic_positions(profile)
	var start_depth: int = world.room_depth
	var start_clears: int = world.rooms_cleared
	check(player.max_health == 130 and player._get_current_health() == 130 and player.damage == 25 and is_equal_approx(player.max_speed, 188.0), "Live smoke starts with ordinary Bastion health, damage and movement")
	check(not world.get_node("DebugSettings").enabled and player.get_active_objective_mutators().is_empty(), "Live smoke has no debug grants or Mission benefits before completion")
	player.primary_attack_fired.connect(func(): attacks += 1)
	player.normal_dash_started.connect(func(): dashes += 1)
	player.damage_taken.connect(func(_raw: int, accepted: int, _context: Dictionary): accepted_health_loss += accepted)
	latest_position = player.global_position
	world.set_process(true)
	world.set_physics_process(true)
	player.set_physics_process(true)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(true)
	# Movement answers the ordinary survey gate; do not bypass its readiness.
	Input.action_press("move_right")
	for _frame in 4:
		await physics_frame
		await process_frame
	Input.action_release("move_right")
	check(not world.encounter_intro_grace_active and player.combat_damage_enabled and not player.encounter_input_frozen, "Ordinary movement starts the live encounter with combat damage enabled")
	var start_frame := Engine.get_physics_frames()
	for frame in 5400:
		if player._get_current_health() <= 0 or world.reward_selection_ui.is_active():
			break
		if not player.combat_damage_enabled:
			disabled_damage_frames += 1
		_observe_enemies()
		var recovery: RefCounted = world.objective_manager.relic_recovery
		observed_deliveries = maxi(observed_deliveries, recovery.delivered_count())
		var destination := Vector2.ZERO
		if not recovery.carrier_has_relic(maxi(1, player.player_id)):
			for relic in recovery.relics:
				if not bool(relic.delivered):
					destination = relic.position
					break
		_drive_controls(destination, frame)
		await physics_frame
		elapsed = float(Engine.get_physics_frames() - start_frame) / Engine.physics_ticks_per_second
		var step := latest_position.distance_to(player.global_position)
		travel_distance += step
		largest_position_step = maxf(largest_position_step, step)
		latest_position = player.global_position
		if frame % 300 == 0:
			print("[LIVE] %.1fs HP=%d enemies=%d delivered=%d attacks=%d hits=%d" % [elapsed, player._get_current_health(), world.active_room_enemy_count, observed_deliveries, attacks, enemy_hits])
	_release_controls()
	var completed: bool = world.reward_selection_ui.is_active() and world.reward_selection_ui.reward_selection_mode == ENUMS.RewardMode.MISSION
	check(completed and player._get_current_health() > 0, "Ordinary controls complete Recovery alive and open the actual Mission reward")
	check(world.room_depth == start_depth + 1 and world.rooms_cleared == start_clears + 1, "Live final deposit advances the run exactly once")
	check(attacks > 0 and enemy_hits > 0 and enemy_kills > 0 and dashes > 0, "Ordinary Attack hits and defeats active enemies and ordinary Dash is exercised")
	check(enemies_seen.size() >= 9 and greatest_enemy_movement > 80.0, "Normal spawning creates all three reinforcement pairs and active enemies move toward Bastion")
	check(disabled_damage_frames == 0, "Combat damage stays enabled for every live encounter frame")
	check(travel_distance > 1400.0 and largest_position_step < 40.0, "All relic retrieval occurs through continuous collision-based walking and Dash")
	check(aim_checks > 0 and aim_mismatches == 0, "Every synthetic mouse aim reaches the ordinary Attack aiming path")
	receipt = {"scope": "Actual Main, Delver depth 3, base Bastion; initial Arcana skipped. No actor health/stat grants, teleports, disabled damage or idle enemies. Automated nearest-enemy combat and sequential recovery is a viability smoke, not human balance acceptance.", "completed": completed, "elapsed_seconds": elapsed, "starting_health": 130, "ending_health": player._get_current_health(), "accepted_health_loss": accepted_health_loss, "attacks": attacks, "dashes": dashes, "enemy_hits": enemy_hits, "enemy_kills": enemy_kills, "enemies_seen": enemies_seen.size(), "greatest_enemy_movement": greatest_enemy_movement, "travel_distance": travel_distance, "largest_position_step": largest_position_step, "relic_sites": sites}
	if completed:
		var selection: Dictionary = world.reward_selection_ui.boon_choices.front().duplicate(true)
		var chosen_id := String(selection.get("id", ""))
		# Give the real card's input guard its normal frame time, then press Attack.
		for _frame in 90:
			await physics_frame
		var card: Control = world.reward_selection_ui.boon_card_panels[0]
		_move_pointer(card.get_global_transform_with_canvas() * (card.size * 0.5))
		await process_frame
		await process_frame
		check(world.reward_selection_ui.boon_hovered_index == 0, "Ordinary pointer movement selects the visible first Mission card")
		Input.action_press("attack")
		for _frame in 3:
			await physics_frame
		Input.action_release("attack")
		for _frame in 4:
			await process_frame
		check(not chosen_id.is_empty() and player.get_upgrade_stack_count(chosen_id) == 1, "Normal reward input grants the selected permanent Mission Boon")
		check(player.get_active_objective_mutators().size() == 1 and world.choosing_next_room, "Normal Mission reward adds Fortified and opens the next doors")
		receipt["reward_boon"] = chosen_id
		receipt["next_doors_open"] = world.choosing_next_room
	await _cleanup_recovery_world()
	receipt["checks"] = checks
	receipt["aim_samples"] = aim_samples
	receipt["aim_mismatches"] = aim_mismatches
	receipt["disabled_damage_frames"] = disabled_damage_frames
	receipt["failures"] = failures
	FileAccess.open("res://relic_recovery_live_combat.json", FileAccess.WRITE).store_string(JSON.stringify(receipt, "\t"))
	print("[OK] Relic Recovery live combat: %d checks, %d failures; %.1fs, HP %d, %d attacks, %d enemy hits" % [checks, failures.size(), elapsed, receipt.ending_health, attacks, enemy_hits])
	quit(0 if failures.is_empty() else 1)

func _observe_enemies() -> void:
	for enemy in get_nodes_in_group("enemies"):
		var id: int = enemy.get_instance_id()
		if not enemies_seen.has(id):
			enemies_seen[id] = enemy.global_position
			enemy.damage_received.connect(func(_amount: int, _remaining: int): enemy_hits += 1)
			enemy.died.connect(func(): enemy_kills += 1)
		greatest_enemy_movement = maxf(greatest_enemy_movement, Vector2(enemies_seen[id]).distance_to(enemy.global_position))

func _drive_controls(destination: Vector2, frame: int) -> void:
	_release_controls()
	var player := world.player
	var nearest: Node2D = null
	var nearest_distance := INF
	for enemy in get_nodes_in_group("enemies"):
		if enemy.get_current_health() <= 0 or enemy.is_spawn_transporting():
			continue
		var distance: float = player.global_position.distance_to(enemy.global_position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	var movement: Vector2 = destination - player.global_position
	# Clear the present wave before the next pickup, and fight while carrying.
	if nearest != null:
		var toward: Vector2 = nearest.global_position - player.global_position
		movement = toward if nearest_distance > 66.0 else Vector2.ZERO
		if nearest_distance < 38.0:
			movement = -toward
		_move_pointer(player.get_global_transform_with_canvas() * player.to_local(nearest.global_position))
		aim_samples += 1
		if player._get_mouse_attack_direction().dot(toward.normalized()) < 0.98:
			aim_mismatches += 1
		if nearest_distance <= 91.0 and frame % 2 == 0:
			if player._get_mouse_attack_direction().dot(toward.normalized()) > 0.98:
				aim_checks += 1
			Input.action_press("attack")
	if absf(movement.x) > 6.0:
		Input.action_press("move_right" if movement.x > 0 else "move_left")
	if absf(movement.y) > 6.0:
		Input.action_press("move_down" if movement.y > 0 else "move_up")
	if frame % 2 == 0 and ((nearest != null and nearest_distance < 34.0) or (nearest == null and movement.length() > 200.0)):
		Input.action_press("dash")

func _release_controls() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "attack", "dash"]:
		Input.action_release(action)

func _move_pointer(viewport_position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	# The headless root reads Input's emulated mouse. Native windows instead
	# read the desktop cursor, so this fixture refuses a native display driver.
	motion.position = root.get_screen_transform() * viewport_position
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
