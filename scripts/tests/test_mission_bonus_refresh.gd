extends "res://scripts/tests/test_power_snapshot.gd"
## Reuse actual Player/World setup and accepted Attack/Dash samples. Exercise
## refresh ordering and independent lifetimes without changing reward values.
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const SESSION := preload("res://scripts/core/run_session.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")
var retirement := AUDIO.new()
var mission_builder: MISSION_BUILDER

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	_setup("solo")
	world.run_session = SESSION.new()
	mission_builder = MISSION_BUILDER.new()
	world.add_child(mission_builder)
	_test_refresh_positions()
	await _test_reward_lifetimes_and_effects()
	_test_matching_and_duplicates()
	_test_stack_replace_and_cap()
	await _cleanup()
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	HISTORY.clear_all()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await retirement.wait_until_retired(self), "Mission fixture retires all native damage feedback audio")
	print("[OK] Mission bonus refresh: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _reset_bonuses() -> void:
	world.player.active_objective_mutators.clear()
	world.player._recalculate_objective_mutator_totals()

func _bonus_map() -> Dictionary:
	var result := {}
	for bonus in world.player.get_active_objective_mutators():
		result[CONTRACTS.mutator_id(bonus)] = bonus
	return result

func _test_refresh_positions() -> void:
	var definitions: Array[Dictionary] = [
		mission_builder._build_fortified_mutator(), mission_builder._build_overcharge_mutator(),
		mission_builder._build_hunters_focus_mutator(), mission_builder._build_relay_boost_mutator(),
		mission_builder._build_node_shield_mutator(), mission_builder._build_combo_relay_mutator()
	]
	for bonus_index in definitions.size():
		for position in 3:
			_reset_bonuses()
			var selected := definitions[bonus_index]
			var ordered: Array[Dictionary] = [definitions[(bonus_index + 1) % definitions.size()], definitions[(bonus_index + 2) % definitions.size()]]
			ordered.insert(position, selected)
			for definition in ordered:
				world.player.apply_objective_mutator(definition)
			world.player.tick_objective_mutators_for_encounter()
			var before := _bonus_map()
			var source_copy := selected.duplicate(true)
			world.player.apply_objective_mutator(selected)
			var after := _bonus_map()
			var id := CONTRACTS.mutator_id(selected)
			var label := "%s refresh in slot %d" % [id, position]
			check(after.size() == 3 and after.has(id), label + ": the newly claimed effect remains present exactly once")
			check(int(after.get(id, {}).get("remaining_encounters", 0)) == 3, label + ": its lifetime refreshes to the existing three clears")
			for other_id in before:
				if other_id != id:
					check(after.get(other_id, {}) == before[other_id], label + ": other bonus state and duration remain unchanged")
			check(selected == source_copy, label + ": applying does not mutate reward data")

func _claim_mission_bonus(bonus: Dictionary) -> void:
	var boons_before: int = world.player.get_upgrade_stack_count("first_strike")
	world._apply_mission_reward({
		"mission_upgrade": {"id": "first_strike", "name": "First Strike"},
		"mission_mutator": {"name": CONTRACTS.mutator_name(bonus), "full_data": bonus}
	})
	check(world.player.get_upgrade_stack_count("first_strike") == boons_before + 1, "Real Mission reward handoff still grants its permanent Boon once")

func _incoming_damage_sample() -> int:
	world.player.health_state.set_health(world.player.health_state.max_health)
	var before: int = world.player.health_state.current_health
	world.player.take_damage(40, {"source": "mission_fixture", "ability": "resistance_sample"})
	return before - world.player.health_state.current_health

func _test_reward_lifetimes_and_effects() -> void:
	_reset_bonuses()
	var baseline := await _sample_action_cooldowns(world.player)
	var base_damage := _incoming_damage_sample()
	_claim_mission_bonus(mission_builder._build_fortified_mutator())
	world.player.tick_objective_mutators_for_encounter()
	_claim_mission_bonus(mission_builder._build_overcharge_mutator())
	world.player.tick_objective_mutators_for_encounter()
	var before := _bonus_map()
	check(before.fortified.remaining_encounters == 1 and before.overcharge.remaining_encounters == 2, "Actual Fortified/Overcharge reward sequence produces independent remaining durations")
	_claim_mission_bonus(mission_builder._build_fortified_mutator())
	var after := _bonus_map()
	check(after.has("fortified") and after.has("overcharge") and after.size() == 2, "Re-earning Fortified alongside newer Overcharge retains both effects")
	check(int(after.get("fortified", {}).get("remaining_encounters", 0)) == 3 and after.overcharge == before.overcharge, "Mission reward refresh changes only Fortified's remaining clears")
	check(is_equal_approx(world.player.objective_mutator_damage_resist, 0.15) and _incoming_damage_sample() == int(ceil(float(base_damage) * 0.85)), "Refreshed Fortified still reduces real incoming damage by its existing 15 percent")
	check(is_equal_approx(world.player._shared_mission_damage_multiplier(), 1.0), "Fortified and Overcharge introduce no outgoing damage bonus")
	var charged := await _sample_action_cooldowns(world.player)
	check(is_equal_approx(charged.attack, baseline.attack * 0.8) and is_equal_approx(charged.dash, baseline.dash * 0.8), "Unchanged Overcharge still shortens accepted Attack and Dash cooldowns by 20 percent")
	for remaining in [2, 1, 0]:
		world.player.tick_objective_mutators_for_encounter()
		var active := _bonus_map()
		check(int(active.get("fortified", {}).get("remaining_encounters", 0)) == remaining, "Refreshed Fortified expires after exactly three later clears: %d" % remaining)
		check(active.has("overcharge") == (remaining == 2), "Refreshing Fortified never extends Overcharge's separate lifetime")
	var expired := await _sample_action_cooldowns(world.player)
	check(expired.attack == baseline.attack and expired.dash == baseline.dash and _incoming_damage_sample() == base_damage, "Expiration removes the actual cooldown and resistance benefits")
	world.player.apply_objective_mutator(mission_builder._build_hunters_focus_mutator())
	world.player.apply_objective_mutator(mission_builder._build_fortified_mutator())
	world.player.apply_objective_mutator(mission_builder._build_hunters_focus_mutator())
	check(is_equal_approx(world.player._shared_mission_damage_multiplier(), 1.25) and world.player._apply_objective_mutator_damage_mult(40) == 50, "Refreshing Hunter's Focus preserves its actual 25 percent outgoing damage bonus")

func _test_matching_and_duplicates() -> void:
	for matching_key in ["id", "icon_shape_id", "name"]:
		_reset_bonuses()
		var old := {"id": "old_id", "icon_shape_id": "old_icon", "name": "Old name", "duration_encounters": 2}
		var fresh := {"id": "fresh_id", "icon_shape_id": "fresh_icon", "name": "Fresh name", "duration_encounters": 3}
		fresh[matching_key] = old[matching_key]
		world.player.apply_objective_mutator(old)
		world.player.apply_objective_mutator(mission_builder._build_overcharge_mutator())
		world.player.apply_objective_mutator(fresh)
		var active := world.player.get_active_objective_mutators()
		check(active.size() == 2 and active[0].name == fresh.name and active[0].remaining_encounters == 3, "Refresh keeps existing legacy matching by " + matching_key)
	_reset_bonuses()
	var fortified := mission_builder._build_fortified_mutator()
	world.player.apply_objective_mutator(fortified)
	world.player.apply_objective_mutator(mission_builder._build_overcharge_mutator())
	# A legacy snapshot can contain duplicates; refresh retains its first slot.
	world.player.active_objective_mutators.append(world.player.active_objective_mutators[0].duplicate(true))
	world.player.apply_objective_mutator(fortified)
	check(world.player.active_objective_mutators.size() == 2 and is_equal_approx(world.player.objective_mutator_damage_resist, 0.15), "Refreshing duplicate legacy entries retains one refreshed bonus and the unrelated bonus")
	var before := world.player.get_active_objective_mutators()
	world.player.apply_objective_mutator({})
	check(world.player.get_active_objective_mutators() == before, "An empty reward does not alter existing bonuses")

func _test_stack_replace_and_cap() -> void:
	_reset_bonuses()
	var stack := {"id": "stack_case", "name": "Stack case", "stack_policy": "stack", "stack_limit": 2, "stack_falloff": 0.5, "player_damage_resist": 0.1, "duration_encounters": 3}
	world.player.apply_objective_mutator(stack)
	world.player.tick_objective_mutators_for_encounter()
	world.player.apply_objective_mutator(stack)
	world.player.tick_objective_mutators_for_encounter()
	world.player.apply_objective_mutator(stack)
	var stacked := world.player.get_active_objective_mutators()
	check(stacked.size() == 2 and stacked[0].remaining_encounters == 3 and stacked[1].remaining_encounters == 2, "Stack policy preserves its limit and replaces only the first matching stack at capacity")
	check(is_equal_approx(world.player.objective_mutator_damage_resist, 0.15), "Stack falloff remains unchanged")
	var replacement := stack.duplicate(true)
	replacement.stack_policy = "replace"
	world.player.apply_objective_mutator(replacement)
	check(world.player.active_objective_mutators.size() == 1 and is_equal_approx(world.player.objective_mutator_damage_resist, 0.1), "Replace policy continues removing all extra matching stacks")
	_reset_bonuses()
	for index in 9:
		world.player.apply_objective_mutator({"id": "cap_%d" % index, "duration_encounters": 3})
	var capped := _bonus_map()
	check(capped.size() == 8 and not capped.has("cap_0") and capped.has("cap_8"), "The existing eight-entry cap still drops the oldest entry")
	world.player.tick_objective_mutators_for_encounter()
	world.player.apply_objective_mutator({"id": "cap_1", "duration_encounters": 3})
	capped = _bonus_map()
	check(capped.size() == 8 and int(capped.get("cap_1", {}).get("remaining_encounters", 0)) == 3 and capped.cap_8.remaining_encounters == 2, "Refreshing the first entry at capacity retains all other entries and their durations")
	_reset_bonuses()
	world.player.apply_objective_mutator({"id": "short", "duration_encounters": 0})
	check(world.player.active_objective_mutators[0].remaining_encounters == 1, "Duration minimum remains one clear")
	world.player.tick_objective_mutators_for_encounter()
	check(world.player.active_objective_mutators.is_empty(), "A minimum-duration bonus expires on its next clear")
