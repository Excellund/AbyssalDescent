extends "res://scripts/tests/test_combat_pause.gd"
## Real EnemyBase death/free and Player input/cleanup; no saved profiles.

var partner: CharacterBody2D

func _run() -> void:
	_setup()
	world.enemy_spawner.initialize(world, player, world.rng, {}, Callable())
	player.set_physics_process(false)
	player.returning_crescent.set_physics_process(false)
	partner = CharacterBody2D.new()
	world.add_child(partner)
	world._disable_player_collision_pair(player, partner)
	await _test_surviving_and_departing_enemy()
	await _test_freed_enemy_cleanup()
	await _test_snapshot_and_death_cleanup()
	await _test_repeated_room_cleanup()
	_cleanup()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Dash collision lifecycle: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _foe() -> ENEMY:
	var foe := _enemy()
	foe.set_physics_process(false)
	return foe

func _accepted_dash() -> void:
	Input.action_release("dash")
	await process_frame
	await physics_frame
	await process_frame
	player._refresh_combat_input_release()
	player.dash_cooldown_left = 0.0
	player.attack_lock_time_left = 0.0
	Input.action_press("dash")
	player._try_start_dash(Vector2.LEFT)
	Input.action_release("dash")
	_check(player._is_dash_active() and player.dash_phasing_active, "Synthetic tap starts a real accepted dash")

func _finish_dash() -> void:
	for frame in range(50):
		await physics_frame
		player._physics_process(1.0 / 60.0)
	_check(not player._is_dash_active() and not player.dash_phasing_active and player._dash_damage_immune_left <= 0.0, "Normal dash completion retains its ordinary immunity duration")

func _check_only_partner(label: String) -> void:
	var exceptions := player.get_collision_exceptions()
	_check(exceptions.size() == 1 and exceptions.has(partner) and player.dash_enemy_exceptions.is_empty(), label)

func _test_surviving_and_departing_enemy() -> void:
	var foe := _foe()
	await _accepted_dash()
	_check(player.get_collision_exceptions().has(foe), "A living enemy's actual body is phased")
	player._sync_enemy_collision_exceptions()
	_check(player.get_collision_exceptions().size() == 2, "Repeated sync keeps one enemy exception plus the party peer")
	foe.remove_from_group("enemies")
	player._sync_enemy_collision_exceptions()
	_check_only_partner("Leaving the active enemy group removes that living body's exception")
	foe.add_to_group("enemies")
	player._sync_enemy_collision_exceptions()
	_check(player.get_collision_exceptions().has(foe), "Reentering the group reacquires the same living body")
	await _finish_dash()
	_check_only_partner("Ending dash before death clears the real live exception")
	foe.take_damage(100000)
	await process_frame
	_check_only_partner("Negative control: an enemy that dies after phasing leaves no stale handle")

func _test_freed_enemy_cleanup() -> void:
	for lethal in [true, false]:
		var foe := _foe()
		await _accepted_dash()
		var foe_id := foe.get_instance_id()
		if lethal:
			foe.take_damage(100000)
		else:
			foe.queue_free()
		await process_frame
		_check(not is_instance_id_valid(foe_id), "Enemy death or explicit room disposal actually frees the body")
		player._update_dash_phase_state(1.0 / 60.0)
		_check_only_partner("Active dash sync removes the freed target's physics handle")
		_check(player._is_dash_active(), "Pruning an enemy does not end the player's movement")
		await _finish_dash()
		_check_only_partner("Finished dash leaves no dead body handles")

func _test_snapshot_and_death_cleanup() -> void:
	var snapshot := player.build_run_snapshot()
	for mode in ["snapshot", "snapshot_stale_flag", "death"]:
		var foe := _foe()
		await _accepted_dash()
		foe.take_damage(100000)
		await process_frame
		if mode == "death":
			player.set_alive(false)
		else:
			if mode == "snapshot_stale_flag":
				player.dash_phasing_active = false
			player.apply_run_snapshot(snapshot)
		_check_only_partner("%s clears a freed enemy while preserving the party exception" % mode)
		_check(not player.dash_phasing_active and not player._is_dash_active(), "%s ends transient dash state" % mode)
		player.set_alive(true)

func _test_repeated_room_cleanup() -> void:
	var baseline := world.find_children("*", "", true, false).size()
	for room in range(5):
		world.combat_phase_coordinator.begin_combat_phase(player, self)
		for index in range(4):
			_foe()
		await _accepted_dash()
		_check(player.get_collision_exceptions().size() == 5, "Every room has exactly four enemy exceptions plus the same party peer")
		world._end_combat_phase()
		world._clear_all_enemies()
		await process_frame
		_check(get_nodes_in_group("enemies").is_empty(), "Production room cleanup frees all old enemies")
		await _finish_dash()
		_check_only_partner("Production transition and ordinary next ticks leave no accumulated handles")
		_check(world.find_children("*", "", true, false).size() == baseline, "Repeated rooms return to their live-node baseline")

