extends "res://scripts/tests/test_relic_recovery.gd"
## Real Main Rest entry/claim, capped investment, ledger and native save lifecycle.
const REST := preload("res://scripts/core/rest_site_choice.gd")
const TIERS := preload("res://scripts/difficulty_config.gd")
var baseline_player: Dictionary = {}

func _run() -> void:
	if not _is_isolated():
		quit(1)
		return
	_setup_recovery_world()
	world._exit_encounter_intro_grace()
	baseline_player = world.player.build_run_snapshot()
	_test_eligible_offers()
	_test_choice_boundaries()
	_test_recovery_formula()
	await _test_rest_lifecycle()
	await _cleanup_recovery_world()
	print("[OK] Rest Site choice: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _fresh_player() -> void:
	world.player.apply_run_snapshot(baseline_player)
	world.player.active_character_id = "bastion"
	world.current_character_id = "bastion"
	world.player.set_physics_process(false)

func _test_eligible_offers() -> void:
	var registry: Node = world.power_registry_instance
	var state := REST.new()
	_fresh_player()
	var choices := state.begin(registry, world.player, world.rng, 42)
	check(choices.size() == 1 and choices[0].id == REST.RECOVER_ID, "No owned Boons keeps a usable Recover choice")
	check(String(choices[0].desc).contains("No health to restore"), "Full-health Recover states its actual zero healing")
	for id: String in registry.UPGRADE_POOL_IDS:
		_fresh_player()
		check(not REST.is_upgrade_eligible(registry, world.player, id), "Rest cannot teach an unowned Boon: " + id)
		var cap := int(registry.get_power_stack_limit(id))
		for level in range(1, cap + 1):
			world.player.apply_upgrade(id)
			check(REST.is_upgrade_eligible(registry, world.player, id) == (level < cap), "Rest follows actual Boon cap: %s level%d" % [id, level])
			choices = state.begin(registry, world.player, world.rng, 42)
			check(choices.size() == (2 if level < cap else 1), "Offer pool keeps Recover and eligible owned level only: %s level%d" % [id, level])
	for id: String in registry.TRIAL_POWER_POOL_IDS + registry.BOSS_REWARD_POOL_IDS:
		check(not REST.is_upgrade_eligible(registry, world.player, id), "Rest excludes Arcana and boss power: " + id)
	_fresh_player()
	world.player.apply_upgrade("wide_arc")
	world.player.active_character_id = "riftlancer"
	check(not REST.is_upgrade_eligible(registry, world.player, "wide_arc"), "Rest preserves Riftlancer's Wide Arc exclusion")
	_fresh_player()
	for id: String in registry.UPGRADE_POOL_IDS:
		world.player.apply_upgrade(id)
	for seed_value in 40:
		var roll := RandomNumberGenerator.new()
		roll.seed = seed_value
		choices = state.begin(registry, world.player, roll, 42)
		check(choices.size() == 3 and choices[0].id == REST.RECOVER_ID and choices[1].id != choices[2].id, "Each seeded visit has Recover plus two distinct owned upgrades")
		choices[1]["id"] = "forged"
		check(String(state.offers[1].id) != "forged", "Returned cards cannot change authoritative offered IDs")

func _test_choice_boundaries() -> void:
	_fresh_player()
	var registry: Node = world.power_registry_instance
	var state := REST.new()
	world.player.apply_upgrade("heavy_blow")
	world.player.health_state.set_health(50)
	state.begin(registry, world.player, world.rng, 42)
	check(not bool(state.resolve("heartstone", registry, world.player, 42).ok) and state.active, "Unowned or unoffered choice cannot spend a Rest")
	var before_damage: int = world.player.damage
	var result := state.resolve("heavy_blow", registry, world.player, 42)
	check(bool(result.ok) and world.player.get_upgrade_stack_count("heavy_blow") == 2 and world.player.damage == before_damage + 7, "Investment applies exactly one normal owned Boon level")
	check(world.player.get_current_health() == 50, "Investment forgoes ordinary Rest healing")
	check(not bool(state.resolve(REST.RECOVER_ID, registry, world.player, 42).ok) and not bool(state.resolve("heavy_blow", registry, world.player, 42).ok), "A resolved Rest cannot heal or upgrade twice")
	state.begin(registry, world.player, world.rng, 42)
	world.player.apply_upgrade("heavy_blow")
	check(not bool(state.resolve("heavy_blow", registry, world.player, 42).ok), "Claim rechecks a cap reached after offers were prepared")
	check(state.current_offers(registry, world.player, 42).size() == 1, "Invalidated card disappears without rolling a substitute")
	result = state.resolve(REST.RECOVER_ID, registry, world.player, 42)
	check(bool(result.ok) and int(result.restored_health) == 42 and world.player.get_current_health() == 92, "Recover remains available after investment is invalidated")
	state.begin(registry, world.player, world.rng, 42)
	world.player.health_state.current_health = 0
	check(not bool(state.resolve(REST.RECOVER_ID, registry, world.player, 42).ok) and world.player.get_current_health() == 0, "Fallen actors cannot be revived by a Rest claim")
	_fresh_player()

func _test_recovery_formula() -> void:
	var registry: Node = world.power_registry_instance
	for tier in 4:
		for tonic in [1.0, 1.35]:
			for health in [1, 70, 128, 130]:
				_fresh_player()
				world.current_difficulty_config = TIERS.get_tier_config(tier)
				world.current_difficulty_config["rest_heal_ratio_mult"] = float(world.current_difficulty_config.get("rest_heal_ratio_mult", 1.0)) * tonic
				world.player.health_state.set_health(health)
				var expected_amount := maxi(8, int(round(130.0 * world.rest_heal_ratio * float(TIERS.get_tier_config(tier).get("rest_heal_ratio_mult", 1.0)) * tonic)))
				check(world._get_rest_heal_amount(world.player) == expected_amount, "Recovery keeps the exact Bearing and Tonic formula")
				var state := REST.new()
				state.begin(registry, world.player, world.rng, expected_amount)
				var outcome := state.resolve(REST.RECOVER_ID, registry, world.player, expected_amount)
				check(bool(outcome.ok) and world.player.get_current_health() == mini(130, health + expected_amount), "Recovery heals the exact clamped amount across health/Bearing/Tonic matrix")
	world.current_difficulty_config = TIERS.get_tier_config(1)
	_fresh_player()

func _enter_rest_for_test() -> void:
	world.reward_selection_ui.close_selection()
	world._choose_door(CONTRACTS.rest_door_option())
	check(world.current_room_label == "Rest Site" and world.reward_selection_ui.reward_selection_mode == ENUMS.RewardMode.REST, "Actual Rest door opens the local Rest decision")
	check(world._rest_site_choice.active and not world.choosing_next_room and world.door_options.is_empty(), "Rest holds next doors until the decision is resolved")

func _claim_rest(id: String) -> void:
	var index := -1
	for option_index in world.reward_selection_ui.boon_choices.size():
		if String(world.reward_selection_ui.boon_choices[option_index].id) == id:
			index = option_index
	world.reward_selection_ui.process_input(1.0)
	world.reward_selection_ui._confirm_choice(index)
	check(index >= 0 and not world._rest_site_choice.active, "Actual card confirmation resolves offered Rest action " + id)

func _test_rest_lifecycle() -> void:
	_fresh_player()
	world.player.apply_upgrade("heavy_blow")
	world.run_summary_recorder.record_reward_choice_for_tracker({"id": "heavy_blow", "name": "Heavy Blow"}, ENUMS.RewardMode.BOON, world.room_depth)
	world.player.health_state.set_health(55)
	world._clear_all_enemies()
	world.choosing_next_room = false
	world._spawn_door_options()
	var before_checkpoint := RunContext.load_active_run()
	var rest_visits: int = world.run_summary_recorder.run_summary_tracker.rest_count
	_enter_rest_for_test()
	check(world.player.get_current_health() == 55, "Rest entry does not auto-heal before the player decides")
	check(world.run_summary_recorder.run_summary_tracker.rest_count == rest_visits + 1, "Entering a Rest still records one Oath-disqualifying visit")
	world._save_active_run_checkpoint()
	check(RunContext.load_active_run() == before_checkpoint, "Unresolved Rest cannot overwrite the previous between-room checkpoint")
	world._on_reward_selected({"id": "wardens_verdict"}, ENUMS.RewardMode.REST, false)
	check(world._rest_site_choice.active and world.player.get_upgrade_stack_count("wardens_verdict") == 0, "World rejects a fabricated unoffered boss power")
	_claim_rest("heavy_blow")
	check(world.choosing_next_room and not world.door_options.is_empty(), "Confirmed investment opens the normal next doors")
	check(world.player.get_upgrade_stack_count("heavy_blow") == 2 and world.player.get_current_health() == 55, "World investment upgrades without recovery")
	var tracker = world.run_summary_recorder.run_summary_tracker
	check(int(tracker.boon_items.heavy_blow.stacks) == 2 and not tracker.boon_items.has("rest_recover"), "Ledger records the actual extra Boon level without inventing a recovery Boon")
	var saved := RunContext.load_active_run()
	check(not saved.is_empty() and saved.door_options == world.door_options and saved.player_snapshot.upgrade_stacks.heavy_blow == 2, "Resolved investment is saved with exact doors and build")
	var saved_depth := world.room_depth
	world._on_reward_selected({"id": "heavy_blow"}, ENUMS.RewardMode.REST, false)
	check(world.room_depth == saved_depth and world.player.get_upgrade_stack_count("heavy_blow") == 2, "Repeated completion callback cannot grant again or advance depth")
	world.player.health_state.set_health(10)
	check(world._apply_active_run_snapshot(saved), "Production Continue restores the resolved investment checkpoint")
	check(world.player.get_current_health() == 55 and world.player.get_upgrade_stack_count("heavy_blow") == 2 and not world._rest_site_choice.active, "Continue restores health/build without replaying either Rest action")
	_enter_rest_for_test()
	_claim_rest(REST.RECOVER_ID)
	check(world.player.get_current_health() == 97, "Actual Recover card preserves base Delver healing")
	check(String(tracker.reward_timeline[-1].label) == "Recovered 42 health" and String(tracker.reward_timeline[-1].category) == "rest", "Healing appears accurately in the Rest ledger category")
	check(int(tracker.boon_items.heavy_blow.stacks) == 2 and not tracker.boon_items.has("rest_recover"), "Healing does not increase Boon count")
	saved = RunContext.load_active_run()
	world.player.health_state.set_health(8)
	check(world._apply_active_run_snapshot(saved) and world.player.get_current_health() == 97, "Continue after Recover preserves exactly the saved health")
	world._on_reward_selected({"id": REST.RECOVER_ID}, ENUMS.RewardMode.REST, false)
	check(world.player.get_current_health() == 97, "Old Recover callback cannot heal again after Continue")
	await process_frame
