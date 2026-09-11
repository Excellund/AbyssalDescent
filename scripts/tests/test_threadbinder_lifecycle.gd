extends "res://scripts/tests/test_shared_status_lifecycle.gd"
## A committed effigy survives modal input cancellation and live build updates.
## Combat lifecycle transitions clear it without recalling teammates' anchors.

class ObservedSeamlock extends "res://scripts/enemy_seamlock.gd":
	var last_player_action: Dictionary = {}
	func receive_committed_player_attack(owner_player: Node2D, action: Dictionary) -> void:
		last_player_action = action.duplicate(true)
		super.receive_committed_player_attack(owner_player, action)

func _run() -> void:
	await _test_effigy_modal_preservation()
	await _test_effigy_live_build_preservation()
	await _test_effigy_seamlock_guesses()
	await _test_effigy_shrinking_bounds()
	for remote_owner in [false, true]:
		for kind in ["death", "removal", "restore", "room_end", "character"]:
			await _test_effigy_explicit_cleanup(kind, remote_owner)
	await _test_effigy_scene_disposal()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[EffigyKeeperLifecycle] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _setup_effigy_arena() -> ObservedSeamlock:
	_setup()
	world.current_room_size = Vector2(1160, 860)
	world.current_effective_room_size = world.current_room_size
	EnemyReplicationService.bind_world(world)
	player.player_id = 1
	player.apply_character_package(player.CHARACTER_REGISTRY.get_character("threadbinder"))
	var seamlock := ObservedSeamlock.new()
	world.add_child(seamlock)
	seamlock.global_position = Vector2(-430, 240)
	seamlock.set_physics_process(false)
	return seamlock

func _stage_illusion(seamlock: ObservedSeamlock, point: Vector2) -> void:
	seamlock.seamlock_state = seamlock.ENEMY_STATE_ENUMS.SeamlockState.ILLUSION_PHASE
	seamlock._illusion_positions = [point]
	seamlock._illusion_shatter_times = [0.0]
	player.attack_cooldown_left = 0.0
	player.attack_lock_time_left = 0.0

func _test_effigy_seamlock_guesses() -> void:
	var seamlock := _setup_effigy_arena()
	_stage_illusion(seamlock, Vector2(50, 0))
	player._try_execute_attack(Vector2.RIGHT)
	_check(player.effigy_deployed and seamlock.arena_penalty_steps == 1, "The real deployment Attack guesses an illusion at the body before planting ahead")
	var first: Dictionary = player.combat_interactions.get_attack_start(seamlock.last_player_action)
	_check(first.origin == player.global_position, "Seamlock receives the deployment Attack's committed body origin")
	_stage_illusion(seamlock, Vector2(50, 0))
	player._try_execute_attack(Vector2.RIGHT)
	_check(seamlock.arena_penalty_steps == 1, "A later effigy Attack does not punish an illusion touched only by the body's old cone")
	seamlock._try_resolve_illusion_guess_from_attacking_player(player)
	_check(seamlock.arena_penalty_steps == 1, "Legacy body-animation polling cannot add a second Effigy guess")
	_stage_illusion(seamlock, player.effigy_position + Vector2(50, 0))
	player._try_execute_attack(Vector2.RIGHT)
	_check(seamlock.arena_penalty_steps == 2, "A real missed Attack from the effigy resolves the illusion that its visible cone touches")
	var accepted_action := seamlock.last_player_action.duplicate(true)
	player.global_position = Vector2(0, -240)
	player.visual_facing_direction = Vector2.LEFT
	seamlock.receive_committed_player_attack(player, accepted_action)
	_check(seamlock.arena_penalty_steps == 2, "Moving the body and changing live aim cannot replay an already resolved committed guess")
	player.apply_trial_power("blast_drive")
	_stage_illusion(seamlock, player.effigy_position + Vector2(175, 0))
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	var blast: Dictionary = player.combat_interactions.get_attack_start(seamlock.last_player_action)
	_check(String(seamlock.last_player_action.source) == "blast_drive" and float(blast.shapes.blast_drive.range) > player.attack_range, "The charged release keeps its actual Blast source and committed enlarged reach")
	_check(seamlock.arena_penalty_steps == 3, "Seamlock accepts the charged Blast's longer effigy cone rather than the base Attack range")
	seamlock._set_shared_arena_penalty_steps(0)
	var prior_action := seamlock.last_player_action.duplicate(true)
	world.pause_menu_controller.open()
	world.pause_menu_controller.close()
	seamlock.receive_committed_player_attack(player, prior_action)
	_check(seamlock.arena_penalty_steps == 0, "A retired pre-pause Attack cannot submit an illusion guess afterward")
	EnemyReplicationService.unbind_world(world)
	_cleanup()
	await process_frame

func _test_effigy_shrinking_bounds() -> void:
	var seamlock := _setup_effigy_arena()
	player.global_position = Vector2(250, 0)
	player._try_execute_attack(Vector2.RIGHT)
	var anchor := player.effigy_position
	player.attack_cooldown_left = 0.0
	player.attack_lock_time_left = 0.0
	player._try_execute_attack(Vector2.RIGHT)
	var old_action := seamlock.last_player_action.duplicate(true)
	_check(player.combat_interactions.get_attack_start(old_action).origin == anchor, "The pending direct packet originally belongs to a real Attack from the deployed anchor")
	var count_before := player._effigy_attack_count
	seamlock._apply_arena_penalty()
	seamlock._update_arena_penalty_lerp(10.0)
	world._refresh_effective_room_bounds_from_seamlock_penalty()
	_check(player.get_attack_origin() == anchor and player.effigy_deployed, "A shrinking wall preserves a valid anchor with its complete placement footprint")
	seamlock._apply_arena_penalty()
	seamlock._apply_arena_penalty()
	seamlock._update_arena_penalty_lerp(10.0)
	world._refresh_effective_room_bounds_from_seamlock_penalty()
	_check(player.get_attack_origin() == player.global_position and not player.effigy_deployed, "The actual Seamlock shrink recalls an anchor that no longer fits the effective arena")
	_check(player._effigy_attack_count == count_before and player.get_effigy_network_state().deployed == false, "Bounds recall preserves Attack phase and exposes the clear through the existing shared snapshot")
	var enemy := _enemy()
	enemy.global_position = anchor + Vector2(45, 0)
	var health := enemy.get_current_health()
	DAMAGEABLE.apply_damage(enemy, player.damage, INTERACTIONS.damage_context(old_action, "melee", {"raw_amount": float(player.damage), "damage_coefficient": 1.0, "attack_origin": anchor}), 1)
	_check(enemy.get_current_health() == health, "Late direct damage cannot reuse the retired outside-arena origin")
	player.attack_cooldown_left = 0.0
	player.attack_lock_time_left = 0.0
	player._try_execute_attack(Vector2.LEFT)
	var replacement: Dictionary = player.combat_interactions.get_attack_start(seamlock.last_player_action)
	_check(player.effigy_deployed and replacement.origin == player.global_position, "The next real Attack plants again and remains at the body for deployment")
	_check(EnemyReplicationService.get_current_room_bounds().grow(-12.0).has_point(player.effigy_position), "The new anchor fits the current shrunken arena")
	seamlock._set_shared_arena_penalty_steps(0)
	seamlock._update_arena_penalty_lerp(10.0)
	world._refresh_effective_room_bounds_from_seamlock_penalty()
	_check(player._validate_effigy_hit(enemy, old_action, {"attack_origin": anchor}).is_empty(), "Restoring the arena size cannot reopen the retired Attack's origin")
	EnemyReplicationService.unbind_world(world)
	_cleanup()
	await process_frame

func _setup_effigy() -> void:
	_setup()
	player.player_id = 1
	player.apply_character_package(player.CHARACTER_REGISTRY.get_character("threadbinder"))
	player._try_execute_attack(Vector2.RIGHT)
	_check(player.effigy_deployed, "A real missed Attack establishes the lifecycle fixture's effigy")

func _test_effigy_modal_preservation() -> void:
	_setup_effigy()
	var anchor := player.effigy_position
	var action := player.new_combat_action("melee")
	Input.action_press("attack")
	Input.action_press("dash")
	player.queued_attack_after_dash = true
	world.pause_menu_controller.open()
	_check(player.effigy_deployed and player.effigy_position == anchor, "Opening actual Pause preserves the committed effigy")
	_check(not player.queued_attack_after_dash and not player.combat_interactions.accepts_action(action), "Pause still cancels queued Attack input and retires its action epoch")
	await create_timer(0.12).timeout
	_check(player.effigy_deployed and player.effigy_position == anchor, "Paused frames cannot expire or recall the fixed effigy")
	world.build_detail_panel.open()
	world.pause_menu_controller.close()
	_check(player.effigy_deployed and not player.is_physics_processing(), "Nested Build Details preserves the effigy while the remaining modal freezes input")
	world.build_detail_panel.close()
	_check(player.effigy_deployed and player.is_physics_processing(), "Closing the final modal resumes the same deployed effigy")
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(player.effigy_deployed and player.effigy_position == anchor, "Focus loss cancels input without discarding the committed effigy")
	_check(player._combat_actions_awaiting_release.has(&"attack") and player._combat_actions_awaiting_release.has(&"dash"), "Still-held controls require release after modal and focus cancellation")
	Input.action_release("attack")
	Input.action_release("dash")
	player._refresh_combat_input_release()
	player.attack_cooldown_left = 0.0
	player.attack_lock_time_left = 0.0
	player._try_execute_attack(Vector2.LEFT)
	_check(player.effigy_deployed and player.effigy_position == anchor and player.get_attack_origin() == anchor, "The first new Attack after Pause reuses the preserved effigy rather than planting another")
	_cleanup()
	await process_frame

func _test_effigy_live_build_preservation() -> void:
	_setup_effigy()
	var anchor := player.effigy_position
	var action := player.new_combat_action("melee")
	var snapshot := player.build_network_build_snapshot()
	player.is_local_player = false
	player.apply_network_build_snapshot(snapshot)
	_check(player.effigy_deployed and player.effigy_position == anchor, "A remote owner's same-character live build update preserves the committed effigy")
	_check(player.combat_interactions.accepts_action(action), "Live build synchronization does not independently change the authenticated action epoch")
	player.is_local_player = true
	player.attack_cooldown_left = 0.0
	player.attack_lock_time_left = 0.0
	player._try_execute_attack(Vector2.LEFT)
	_check(player.effigy_deployed and player.effigy_position == anchor, "The next real Attack after live build synchronization retains its original fixed origin")
	_cleanup()
	await process_frame

func _test_effigy_explicit_cleanup(kind: String, remote_owner: bool) -> void:
	_setup_effigy()
	player.is_local_player = not remote_owner
	var snapshot := player.build_run_snapshot()
	match kind:
		"death": player.set_alive(false)
		"removal": player.set_combat_removed(true)
		"restore": player.apply_run_snapshot(snapshot)
		"room_end": phase.end_combat_phase(player, self)
		"character": player.apply_character_package(player.CHARACTER_REGISTRY.get_character("bastion"))
	var label := "%s %s" % ["remote owner" if remote_owner else "local owner", kind]
	_check(not player.effigy_deployed and player.get_attack_origin() == player.global_position, label + " removes the previous combat anchor and restores body origin")
	if kind == "restore":
		_check(player.active_character_id == "threadbinder" and player.passive_effigy_command, "Restore retains Effigy Keeper without reviving a temporary deployment")
	if kind == "character":
		_check(not player.passive_effigy_command, "Character change disables the previous delivery rule")
	_cleanup()
	await process_frame

func _test_effigy_scene_disposal() -> void:
	_setup_effigy()
	var old_player: WeakRef = weakref(player)
	var old_world: WeakRef = weakref(world)
	_cleanup()
	await process_frame
	_check(old_player.get_ref() == null and old_world.get_ref() == null, "Leaving the gameplay scene disposes the Keeper and its owner-parented effigy")
	_setup()
	player.apply_character_package(player.CHARACTER_REGISTRY.get_character("threadbinder"))
	_check(not player.effigy_deployed and player.get_attack_origin() == player.global_position, "Entering a fresh gameplay scene cannot inherit the previous scene's anchor")
	_cleanup()
	await process_frame
