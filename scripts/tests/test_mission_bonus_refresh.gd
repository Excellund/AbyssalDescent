extends "res://scripts/tests/test_power_snapshot.gd"
## Reuse actual Player/World setup and accepted Attack/Dash samples. Exercise
## refresh ordering and independent lifetimes without changing reward values.
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const SESSION := preload("res://scripts/core/run_session.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")
const HUD := preload("res://scripts/world_hud.gd")
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
	await _test_effective_cooldown_stats()
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

func _check_cooldown_stats(hud: Node, actor: Player, attack: float, dash: float, label: String) -> void:
	hud.refresh({"timer_visible_in_hud": false, "active_player_mutators": actor.get_active_objective_mutators()}, actor)
	var text: String = hud.stats_label.get_parsed_text()
	check(text.contains("Attack Speed: %.2fs" % attack) and text.contains("Dash Cooldown: %.2fs" % dash), label + ": real Stats displays both ordinary action intervals")
	check(is_equal_approx(actor.get_effective_attack_cooldown(), attack) and is_equal_approx(actor.get_effective_dash_cooldown(), dash), label + ": public cooldown values agree with the expected intervals")

func _check_accepted_cooldown_stats(hud: Node, actor: Player, attack: float, dash: float, label: String) -> void:
	var accepted := await _sample_action_cooldowns(actor)
	check(is_equal_approx(accepted.attack, attack) and is_equal_approx(accepted.dash, dash), label + ": accepted Attack and Dash use those same intervals")
	_check_cooldown_stats(hud, actor, attack, dash, label)

func _check_blast_cooldown_stats(hud: Node, actor: Player, attack: float, dash: float, label: String) -> void:
	actor.discard_pending_combat_input()
	actor.arcana_motion._refresh_capacity()
	var charges_before: int = actor.arcana_motion.blast_charges
	var attacks_before: int = actor.attack_combo_counter
	actor.arcana_motion.release_blast(1.0)
	check(actor.attack_combo_counter == attacks_before + 1 and actor.arcana_motion.blast_charges == charges_before - 1 and is_equal_approx(actor.attack_cooldown_left, attack), label + ": accepted Blast consumes one charge and uses the ordinary Attack interval")
	_check_cooldown_stats(hud, actor, attack, dash, label)
	actor.discard_pending_combat_input()

func _test_effective_cooldown_stats() -> void:
	_reset_bonuses()
	var hud := HUD.new()
	world.add_child(hud)
	hud.setup(6)
	var actor := world.player
	var overcharge := mission_builder._build_overcharge_mutator()
	for character_id in CHARACTER.get_launch_character_ids():
		actor.apply_character_package(CHARACTER.get_character(character_id))
		var base_attack: float = actor.attack_cooldown
		var base_dash: float = actor.dash_cooldown
		await _check_accepted_cooldown_stats(hud, actor, base_attack, base_dash, character_id + " baseline")
		actor.apply_objective_mutator(overcharge)
		await _check_accepted_cooldown_stats(hud, actor, base_attack * 0.8, base_dash * 0.8, character_id + " Overcharge")
		check(is_equal_approx(actor.attack_cooldown, base_attack) and is_equal_approx(actor.dash_cooldown, base_dash), character_id + ": temporary bonus does not rewrite the underlying cooldown properties")
		_reset_bonuses()

	# Explicit saved values catch applying the multiplier twice or baking it into
	# permanent stats. The HUD must track the live bonus across a real disk resume.
	world.current_character_id = "veilstrider"
	actor.apply_character_package(CHARACTER.get_character("veilstrider"))
	actor.attack_cooldown = 0.37
	actor.dash_cooldown = 0.51
	actor.apply_trial_power("blast_drive")
	actor.apply_objective_mutator(overcharge)
	actor.tick_objective_mutators_for_encounter()
	actor.attack_cooldown_left = 0.09
	actor.dash_cooldown_left = 0.12
	_check_cooldown_stats(hud, actor, 0.296, 0.408, "Partly elapsed cooldowns")
	actor.apply_objective_mutator(overcharge)
	check(is_equal_approx(actor.attack_cooldown_left, 0.09) and is_equal_approx(actor.dash_cooldown_left, 0.12) and _bonus_map().overcharge.remaining_encounters == 3, "Refreshing Overcharge changes only its lifetime, preserving current action timers")
	await _check_accepted_cooldown_stats(hud, actor, 0.296, 0.408, "Refreshed Overcharge")
	_check_blast_cooldown_stats(hud, actor, 0.296, 0.408, "Refreshed Overcharge")
	actor.tick_objective_mutators_for_encounter()
	world._save_active_run_checkpoint()
	var saved := RunContext.load_active_run()
	check(not saved.is_empty() and is_equal_approx(float(saved.player_snapshot.properties.attack_cooldown), 0.37) and is_equal_approx(float(saved.player_snapshot.properties.dash_cooldown), 0.51), "Disk checkpoint keeps raw cooldown properties without the temporary multiplier")
	actor = _replace_player(saved)
	check(_bonus_map().overcharge.remaining_encounters == 2, "Disk resume retains the remaining Overcharge lifetime")
	await _check_accepted_cooldown_stats(hud, actor, 0.296, 0.408, "Resumed Overcharge")
	actor.apply_run_snapshot(saved.player_snapshot)
	_check_cooldown_stats(hud, actor, 0.296, 0.408, "Repeated snapshot restore")
	_check_blast_cooldown_stats(hud, actor, 0.296, 0.408, "Resumed Overcharge")
	for remaining in [1, 0]:
		actor.tick_objective_mutators_for_encounter()
		var attack := 0.296 if remaining > 0 else 0.37
		var dash := 0.408 if remaining > 0 else 0.51
		await _check_accepted_cooldown_stats(hud, actor, attack, dash, "Resumed bonus remaining %d" % remaining)
	check(actor.get_active_objective_mutators().is_empty(), "Restored Overcharge expires after exactly its two remaining clears")
	actor.arcana_motion.tick(100.0)
	_check_blast_cooldown_stats(hud, actor, 0.37, 0.51, "Expired Overcharge")

	# Preserve the existing floors, including explicit legacy/snapshot values.
	for charged in [false, true]:
		_reset_bonuses()
		if charged:
			actor.apply_objective_mutator(overcharge)
		actor.attack_cooldown = 0.04
		actor.dash_cooldown = -0.02
		await _check_accepted_cooldown_stats(hud, actor, 0.05, 0.0, "Existing cooldown floors, Overcharge %s" % charged)
		actor.arcana_motion.tick(100.0)
		_check_blast_cooldown_stats(hud, actor, 0.05, 0.0, "Existing Blast cooldown floor, Overcharge %s" % charged)

	actor.attack_cooldown = 0.37
	actor.dash_cooldown = 0.51
	actor.attack_cooldown_left = 0.08
	actor.dash_cooldown_left = 0.17
	actor._refund_shared_dash(0.06)
	check(is_equal_approx(actor.dash_cooldown_left, 0.11), "Existing shared Dash refund changes only the remaining timer")
	_check_cooldown_stats(hud, actor, 0.296, 0.408, "Refunded current Dash")
	actor._refund_shared_dash(1.0)
	check(is_zero_approx(actor.dash_cooldown_left), "Existing Dash refunds retain the zero floor")

	# Veilstep's surge is a one-shot free Dash, not a change to ordinary Stats.
	Input.action_release("dash")
	await process_frame
	await physics_frame
	await process_frame
	actor.discard_pending_combat_input()
	actor._refresh_combat_input_release()
	actor.attack_lock_time_left = 0.0
	actor.dash_cooldown_left = 0.0
	actor.veilstep_rhythm_surge_ready = true
	actor.veilstep_rhythm_surge_window_left = actor.veilstep_rhythm_surge_duration
	Input.action_press("dash")
	actor._try_start_dash(Vector2.RIGHT)
	Input.action_release("dash")
	check(actor.passive_veilstep_rhythm and actor.veilstep_rhythm_empowered_dash_active and actor._is_dash_active() and is_zero_approx(actor.dash_cooldown_left), "Accepted empowered Veilstep Dash keeps its zero-cooldown exception while Overcharge is active")
	_check_cooldown_stats(hud, actor, 0.296, 0.408, "Empowered Veilstep Dash")
	actor.discard_pending_combat_input()
	_reset_bonuses()