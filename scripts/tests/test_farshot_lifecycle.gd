extends "res://scripts/tests/test_rest_site_choice.gd"
## Real Player mapping, capped offers, Rest investment and encoded Continue.

func _run() -> void:
	if not _is_isolated():
		quit(1)
		return
	_setup_recovery_world()
	world._exit_encounter_intro_grace()
	baseline_player = world.player.build_run_snapshot()
	_test_registration_and_snapshots()
	await _test_farshot_continue()
	await _cleanup_recovery_world()
	print("[FarshotLifecycle] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_registration_and_snapshots() -> void:
	var registry: Node = world.power_registry_instance
	check(registry.UPGRADE_POOL_IDS.has("farshot") and registry.get_power_stack_limit("farshot") == 3, "Farshot joins ordinary Boon offers with cap three")
	var base_damage: int = world.player.damage
	check(world.player.farshot_bonus_damage == 0 and not REST.is_upgrade_eligible(registry, world.player, "farshot"), "Fresh player owns no Farshot and Rest cannot teach it")
	for level in range(1, 4):
		world.player.apply_upgrade("farshot")
		check(world.player.farshot_bonus_damage == level * 10 and world.player.damage == base_damage, "Normal acquisition adds only the conditional basis at level%d" % level)
		check(world.player.get_upgrade_stack_count("farshot") == level and REST.is_upgrade_eligible(registry, world.player, "farshot") == (level < 3), "Actual stack and Rest eligibility match level%d" % level)
		var text: String = world.player.get_power_current_desc("farshot")
		check(text.contains("+%d" % (level * 10)) and text.contains("160") and text.contains("body") and text.contains("when damage lands"), "Current description states the actual value, distance, body and timing")
		var snapshot: Dictionary = world.player.build_run_snapshot()
		world.player.farshot_bonus_damage = 999
		world.player.apply_run_snapshot(snapshot)
		check(world.player.farshot_bonus_damage == level * 10 and world.player.get_upgrade_stack_count("farshot") == level, "Run snapshot restores exact Farshot level%d" % level)
	world.player.apply_upgrade("farshot")
	check(world.player.farshot_bonus_damage == 30 and world.player.get_upgrade_stack_count("farshot") == 3, "A fourth pick cannot exceed either normal cap")
	var available: Array[Dictionary] = world.reward_selection_ui._roll_boon_choices(100, registry, world.player, world.rng)
	check(not available.any(func(choice: Dictionary): return choice.id == "farshot"), "Capped Farshot leaves the actual ordinary offer roll")
	var old_snapshot := baseline_player.duplicate(true)
	old_snapshot.properties.erase("farshot_bonus_damage")
	old_snapshot.upgrade_stacks.erase("farshot")
	world.player.apply_run_snapshot(old_snapshot)
	check(world.player.farshot_bonus_damage == 0 and world.player.get_upgrade_stack_count("farshot") == 0, "Legacy checkpoint clears Farshot from a reused player without requiring the new key")
	check(world.player.get_upgrade_card_desc("farshot").contains("+10"), "Old checkpoint receives a first-pick preview")
	world.player.apply_upgrade("farshot")
	var network_snapshot: Dictionary = world.player.build_network_build_snapshot()
	world.player.farshot_bonus_damage = 0
	world.player.apply_network_build_snapshot(network_snapshot)
	check(world.player.farshot_bonus_damage == 10 and world.player.get_upgrade_stack_count("farshot") == 1, "Existing network build snapshot carries the new property and stack")

func _test_farshot_continue() -> void:
	world.player.health_state.set_health(55)
	_enter_rest_for_test()
	check(world.reward_selection_ui.boon_choices.any(func(choice: Dictionary): return choice.id == "farshot"), "Actual Rest offers the owned uncapped Farshot")
	_claim_rest("farshot")
	check(world.player.farshot_bonus_damage == 20 and world.player.get_current_health() == 55, "Real Rest card invests one Farshot pick and forgoes healing")
	var saved := RunContext.load_active_run()
	check(not saved.is_empty() and int(saved.player_snapshot.properties.farshot_bonus_damage) == 20 and int(saved.player_snapshot.upgrade_stacks.farshot) == 2, "Encoded on-disk checkpoint preserves Farshot property and stack")
	world.player.farshot_bonus_damage = 999
	check(world._apply_active_run_snapshot(saved), "Production Continue accepts the Farshot Rest checkpoint")
	check(world.player.farshot_bonus_damage == 20 and world.player.get_upgrade_stack_count("farshot") == 2 and world.player.get_current_health() == 55, "Continue restores Farshot without repeating investment or healing")
	world._on_reward_selected({"id": "farshot"}, ENUMS.RewardMode.REST, false)
	check(world.player.farshot_bonus_damage == 20, "Retired Rest callback cannot grant another Farshot pick")
	_enter_rest_for_test()
	_claim_rest("farshot")
	check(world.player.farshot_bonus_damage == 30 and world.player.get_upgrade_stack_count("farshot") == 3, "A later Rest reaches the same ordinary cap")
	_enter_rest_for_test()
	check(world.reward_selection_ui.boon_choices.size() == 1 and world.reward_selection_ui.boon_choices[0].id == REST.RECOVER_ID, "Capped Farshot leaves useful Recover at the next Rest")
	_claim_rest(REST.RECOVER_ID)
	await process_frame
