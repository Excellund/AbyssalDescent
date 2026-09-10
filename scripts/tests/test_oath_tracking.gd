extends SceneTree

const TRACKER := preload("res://scripts/core/run_summary_tracker.gd")
const RECORDER := preload("res://scripts/core/run_summary_recorder.gd")
const EVALUATOR := preload("res://scripts/progression/oaths_evaluator.gd")
const META := preload("res://scripts/meta_progress_store.gd")
const OBJECTIVES := preload("res://scripts/objective_runtime.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")

class TestContext extends Node:
	var meta_progress_profile: Dictionary = META._get_default_profile()
	var saves := 0
	func get_profile_uuid() -> String:
		return "oath-test-player"
	func get_profile_name_or_default() -> String:
		return "OathTest"
	func save_meta_progress() -> bool:
		saves += 1
		return true

class TestWorld extends Node:
	var context := TestContext.new()
	var current_player_profile: RefCounted = null
	var is_multiplayer := true
	var submitted: Dictionary = {}
	var player: Node2D
	var party: Array = []
	func _resolve_local_peer_id() -> int:
		return 2
	func _get_run_context() -> Node:
		return context
	func _enqueue_leaderboard_submission(summary: Dictionary) -> void:
		submitted = summary.duplicate(true)
	func _get_multiplayer_player_nodes() -> Array:
		return party

class TestPlayer extends Node2D:
	var dead := false
	func is_dead() -> bool:
		return dead

class CheckpointWorld extends "res://scripts/world_generator.gd":
	var context_accesses := 0
	func _ready() -> void:
		pass
	func _get_run_context() -> RUN_CONTEXT_SCRIPT:
		context_accesses += 1
		return null

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _completed(summary: Dictionary) -> Array:
	return EVALUATOR.evaluate_run(summary, META._get_default_profile()).get("completed_oath_ids", [])

func _forsworn_seed() -> Dictionary:
	return {"difficulty_tier": 3, "character_id": "bastion", "equipped_catalyst_ids": [], "ascension_tracking_complete": true}

func _ascension_seed() -> Dictionary:
	var seed := _forsworn_seed()
	seed["ascension_rank"] = 1
	seed["ascension_loadout"] = ["barren_road"]
	return seed

func _new_recorder(world: Node) -> RefCounted:
	var recorder := RECORDER.new(world)
	recorder.run_summary_tracker.reset_for_run(_forsworn_seed())
	return recorder

func _qualified_summary(overrides: Dictionary = {}) -> Dictionary:
	var tracker := TRACKER.new()
	tracker.reset_for_run(_forsworn_seed())
	var summary := tracker.build_summary({"outcome": "clear", "duration_seconds": 600})
	summary.merge(overrides, true)
	return summary

func _all_conditions_summary() -> Dictionary:
	return _qualified_summary({
		"duration_seconds": 479, "ascension_rank": 10,
		"ascension_loadout": ["glass_descent", "pilgrims_burden"],
		"boss_no_hit_ids": ["warden", "sovereign", "lacuna"], "hold_full_control_achieved": true,
		"build_summary": {"boons": [], "boss_rewards": [], "arcana": [{"id": "static_wake", "stacks": 3}]},
	})

func _snapshot_for_tracker(tracker: RefCounted) -> Dictionary:
	return JSON.parse_string(JSON.stringify({
		"tracker_checkpoint": tracker.build_checkpoint(), "current_difficulty_tier": tracker.difficulty_tier,
		"active_catalyst_ids": tracker.equipped_catalyst_ids,
		"tracker_boon_items": tracker.boon_items, "tracker_arcana_items": tracker.arcana_items,
		"tracker_boss_reward_items": tracker.boss_reward_items,
	}))

func _test_bearing_requirements() -> void:
	var summary := _all_conditions_summary()
	var definitions: Dictionary = EVALUATOR.OATHS_REGISTRY.get_all_definitions()
	var journey := ["forsworn_warden_no_hit", "forsworn_unbroken_line", "forsworn_singular_focus", "forsworn_unbroken_march"]
	var challenges := ["forsworn_sovereign_no_hit", "forsworn_lacuna_no_hit", "forsworn_grounded", "forsworn_closed_fist", "forsworn_against_the_clock"]
	_check(definitions.size() == 33, "Active roster contains 17 challenges and 16 character/Bearing clears")
	for id in definitions:
		var definition: Dictionary = definitions[id]
		var exact_clear: bool = String(id).begins_with("clear_")
		var minimum: int = int(definition.params.bearing_tier) if exact_clear else (0 if journey.has(id) else (1 if challenges.has(id) else 3))
		var stage := "bearing" if exact_clear else ("journey" if minimum == 0 else ("challenge" if minimum == 1 else "prestige"))
		_check(definition.get("minimum_bearing_tier", -1) == minimum and definition.get("progression_stage", "") == stage, "Oath declares its intended progression step: " + id)
		for tier in range(4):
			var candidate := summary.duplicate(true)
			candidate.difficulty_tier = tier
			candidate.oath_min_difficulty_tier = tier
			if exact_clear:
				candidate.character_id = definition.params.character_id
			var eligible: bool = tier == minimum if exact_clear else tier >= minimum
			_check(_completed(candidate).has(id) == eligible, "Oath uses its own bearing requirement: %s at %d" % [id, tier])
			_check(EVALUATOR.OATHS_REGISTRY.is_bearing_eligible(definition, tier) == eligible, "Menu and evaluator agree on bearing eligibility: %s at %d" % [id, tier])
	for tier in [-1, 4, 3.5, "3", null, true, [], {}, INF, NAN]:
		var invalid := summary.duplicate(true)
		invalid.difficulty_tier = tier
		_check(_completed(invalid).is_empty(), "A missing or malformed actual bearing cannot earn any Oath: " + str(tier))
	for minimum in [-1, 4, 3.5, "3", null, true, [], {}, INF, NAN]:
		var invalid := summary.duplicate(true)
		invalid.oath_min_difficulty_tier = minimum
		var completed := _completed(invalid)
		for id in definitions:
			if int(definitions[id].minimum_bearing_tier) > 0:
				_check(not completed.has(id), "Malformed minimum bearing cannot fall back to the older Forsworn flag: " + id)
		_check(completed.has("forsworn_warden_no_hit"), "Unknown difficulty history does not block unrestricted encounter evidence")
	var pilgrim := summary.duplicate(true)
	pilgrim.difficulty_tier = 0
	pilgrim.erase("oath_min_difficulty_tier")
	pilgrim.erase("oath_difficulty_verified")
	for id in journey:
		_check(_completed(pilgrim).has(id), "Approachable Oath is available on Pilgrim without higher-bearing proof: " + id)
	_check(_completed(pilgrim).has("clear_bastion_pilgrim"), "Pilgrim character clear needs no restricted-bearing proof")
	for id in definitions:
		if int(definitions[id].minimum_bearing_tier) > 0:
			_check(not _completed(pilgrim).has(id), "Pilgrim cannot earn restricted challenges or prestige: " + id)
	var legacy := summary.duplicate(true)
	legacy.erase("oath_min_difficulty_tier")
	_check(_completed(legacy) == _completed(summary), "Verified legacy Forsworn summaries preserve all prior eligibility")
	for proof in [false, null, 1, "true"]:
		legacy.oath_difficulty_verified = proof
		_check(not _completed(legacy).has("forsworn_grounded") and not _completed(legacy).has("forsworn_flawless_run"), "Unknown legacy history never inherits higher-bearing eligibility")
		_check(_completed(legacy).has("forsworn_singular_focus"), "Unrestricted challenges still use their separate full-run/action proof")
	var minimum_one := summary.duplicate(true)
	minimum_one.oath_min_difficulty_tier = 1
	minimum_one.oath_difficulty_verified = false
	_check(_completed(minimum_one).has("forsworn_grounded") and not _completed(minimum_one).has("forsworn_flawless_run"), "A run that used Delver qualifies for Delver+ but cannot earn Forsworn prestige")
	var contradictory := summary.duplicate(true)
	contradictory.difficulty_tier = 1
	contradictory.oath_min_difficulty_tier = 3
	_check(_completed(contradictory).has("forsworn_grounded") and _completed(contradictory).has("clear_bastion_delver") and not _completed(contradictory).has("forsworn_flawless_run"), "Mismatched valid difficulty evidence uses the lower actual bearing")
	var debug := summary.duplicate(true)
	debug.is_debug = true
	_check(_completed(debug).is_empty(), "Debug runs never grant any progression stage")
	var json_summary: Dictionary = JSON.parse_string(JSON.stringify(summary))
	_check(_completed(json_summary) == _completed(summary), "JSON numeric encoding retains valid bearing evidence")

func _test_postgame_challenges() -> void:
	var summary := _all_conditions_summary()
	for id in ["unassisted_ascension", "forsworn_grounded", "forsworn_glass_pilgrimage"]:
		_check(_completed(summary).has(id), "Valid challenge evidence earns " + id)
		var death := summary.duplicate(true)
		death.outcome = "death"
		_check(not _completed(death).has(id), "New playstyle challenge requires a full clear: " + id)
	var altered := summary.duplicate(true)
	for rank in [0, -1, null, "1", 0.5, INF, NAN, true]:
		altered = summary.duplicate(true)
		altered.ascension_rank = rank
		_check(not _completed(altered).has("unassisted_ascension"), "Unassisted needs a real Ascension challenge, not the first ordinary Forsworn clear: " + str(rank))
	for rank in [1, 3, 10]:
		altered = summary.duplicate(true)
		altered.ascension_rank = rank
		_check(_completed(altered).has("unassisted_ascension"), "Unassisted remains achievable at any positive Ascension rank: " + str(rank))
	for proof in [false, null, "true", 1]:
		altered = summary.duplicate(true)
		altered.ascension_tracking_complete = proof
		_check(not _completed(altered).has("unassisted_ascension"), "Unassisted requires verified Ascension history")
	altered = summary.duplicate(true)
	altered.equipped_catalyst_ids = ["starting_max_hp_bonus"]
	_check(not _completed(altered).has("unassisted_ascension"), "Any equipped Catalyst disqualifies Unassisted")
	altered = summary.duplicate(true)
	altered.dashes_performed = 1
	_check(not _completed(altered).has("forsworn_grounded"), "One accepted Dash disqualifies Grounded")
	for loadout in [[], ["glass_descent"], ["pilgrims_burden"], ["hardened_foes", "relentless_tide"], ["glass_descent", "pilgrims_burden", null]]:
		altered = summary.duplicate(true)
		altered.ascension_loadout = loadout
		_check(not _completed(altered).has("forsworn_glass_pilgrimage"), "Glass Pilgrimage requires both exact, valid modifiers")
	altered = summary.duplicate(true)
	altered.rest_count = 1
	_check(not _completed(altered).has("forsworn_glass_pilgrimage"), "One Rest Site disqualifies Glass Pilgrimage")
	altered = summary.duplicate(true)
	altered.duration_seconds = 480
	_check(not _completed(altered).has("forsworn_against_the_clock"), "Against the Clock remains strictly under eight minutes")
	altered = summary.duplicate(true)
	altered.build_summary.arcana.append({"id": "storm_crown", "stacks": 1})
	_check(not _completed(altered).has("forsworn_singular_focus"), "A second distinct Arcana disqualifies Singular Focus")
	var profile := META._get_default_profile()
	var results := EVALUATOR.evaluate_run(summary, profile)
	_check(EVALUATOR.apply_results_to_profile(profile, results), "Postgame challenge completion and rewards persist")
	for catalyst in ["reward_choice_bonus", "starting_max_hp_bonus", "damage_reduction"]:
		_check(META.get_unlocked_catalyst_ids(profile).has(catalyst), "Challenge reward remains reachable: " + catalyst)
	_check(EVALUATOR.evaluate_run(summary, profile).completed_oath_ids.is_empty(), "Completed challenges are not awarded twice")
	_check(not EVALUATOR.apply_results_to_profile(profile, results), "Repeated reward application is idempotent")

func _test_negative_evidence() -> void:
	var summary := _all_conditions_summary()
	var negative_ids := ["forsworn_singular_focus", "forsworn_against_the_clock", "forsworn_unbroken_march", "forsworn_flawless_run", "forsworn_closed_fist", "unassisted_ascension", "forsworn_grounded", "forsworn_glass_pilgrimage"]
	for proof in [null, false, "true", 1]:
		var incomplete := summary.duplicate(true)
		incomplete.full_run_tracking_complete = proof
		for id in negative_ids:
			_check(not _completed(incomplete).has(id), "Unknown whole-run history cannot award " + id)
	for pair in [["dash_tracking_complete", "forsworn_grounded"], ["catalyst_tracking_complete", "unassisted_ascension"], ["ascension_tracking_complete", "forsworn_glass_pilgrimage"]]:
		var missing := summary.duplicate(true)
		missing.erase(pair[0])
		_check(not _completed(missing).has(pair[1]), "Missing specific history cannot award " + pair[1])
		missing[pair[0]] = "true"
		_check(not _completed(missing).has(pair[1]), "Non-Boolean history cannot award " + pair[1])
	for value in [null, "0", [], {}, -1, 0.5, INF, NAN, true]:
		for pair in [["dashes_performed", "forsworn_grounded"], ["primary_attacks_fired", "forsworn_closed_fist"], ["rest_count", "forsworn_unbroken_march"], ["duration_seconds", "forsworn_against_the_clock"]]:
			var malformed := summary.duplicate(true)
			malformed[pair[0]] = value
			_check(not _completed(malformed).has(pair[1]), "Missing or invalid count cannot satisfy " + pair[1])
		var damage := summary.duplicate(true)
		damage.stats.damage_taken_total = value
		_check(not _completed(damage).has("forsworn_flawless_run"), "Invalid damage total cannot mean no damage")
	for value in [null, "none", {}, ["unknown_catalyst"]]:
		var malformed := summary.duplicate(true)
		malformed.equipped_catalyst_ids = value
		_check(not _completed(malformed).has("unassisted_ascension"), "Missing/malformed equipment is not known empty equipment")
	for value in [null, {}, {"arcana": null}, {"arcana": [{"id": "static_wake"}]}, {"arcana": [{"id": "static_wake", "stacks": 0}]}]:
		var malformed := summary.duplicate(true)
		malformed.build_summary = value
		_check(not _completed(malformed).has("forsworn_singular_focus"), "Singular Focus requires a known valid build")
	var missing_stats := summary.duplicate(true)
	missing_stats.erase("stats")
	_check(not _completed(missing_stats).has("forsworn_flawless_run"), "Missing damage history cannot award Unscathed")
	var malformed_bosses := summary.duplicate(true)
	malformed_bosses.boss_no_hit_ids = ["warden", "sovereign", "lacuna", null]
	_check(not _completed(malformed_bosses).has("forsworn_three_crowns_no_hit"), "Malformed boss evidence cannot award Untouched Crowns")

func _test_checkpoint_proofs_and_inventory() -> void:
	var tracker := TRACKER.new()
	tracker.reset_for_run(_ascension_seed())
	_add_arcana(tracker, "static_wake")
	tracker.begin_boss_engagement("warden")
	tracker.record_boss_defeat("warden")
	var snapshot := _snapshot_for_tracker(tracker)
	var world := TestWorld.new()
	var recorder := _new_recorder(world)
	recorder.run_summary_tracker.reset_for_run(_ascension_seed())
	recorder.restore_tracker_items_from_snapshot(snapshot)
	var restored := _completed(recorder.run_summary_tracker.build_summary({"outcome": "clear"}))
	for id in ["unassisted_ascension", "forsworn_grounded", "forsworn_singular_focus", "forsworn_warden_no_hit"]:
		_check(restored.has(id), "Complete serialized evidence survives production restore: " + id)
	for missing_key in ["oath_difficulty_verified", "oath_start_difficulty_tier"]:
		var legacy := snapshot.duplicate(true)
		legacy.tracker_checkpoint.erase("oath_min_difficulty_tier")
		legacy.tracker_checkpoint.erase(missing_key)
		recorder.run_summary_tracker.reset_for_run(_ascension_seed())
		recorder.restore_tracker_items_from_snapshot(legacy)
		var legacy_completed := _completed(recorder.run_summary_tracker.build_summary({"outcome": "clear"}))
		_check(not legacy_completed.has("forsworn_grounded") and not legacy_completed.has("forsworn_flawless_run"), "Missing legacy difficulty proof cannot reuse Forsworn menu settings")
		_check(legacy_completed.has("forsworn_warden_no_hit"), "Unrestricted encounter completion survives missing legacy bearing proof")
	for tier in [0, 1, 2]:
		var seed := _ascension_seed()
		seed.difficulty_tier = tier
		tracker.reset_for_run(seed)
		tracker.begin_boss_engagement("warden")
		tracker.record_boss_defeat("warden")
		recorder.run_summary_tracker.reset_for_run(_ascension_seed())
		recorder.restore_tracker_items_from_snapshot(_snapshot_for_tracker(tracker))
		var resumed_completed := _completed(recorder.run_summary_tracker.build_summary({"outcome": "clear"}))
		_check(not resumed_completed.has("forsworn_flawless_run"), "Easier saved runs cannot be promoted into Forsworn prestige")
		_check(resumed_completed.has("forsworn_grounded") == (tier >= 1), "Resumed challenges respect the lowest saved bearing")
		_check(resumed_completed.has("forsworn_warden_no_hit"), "Approachable encounter goals remain available after resume")
	for field in ["dash_tracking_complete", "dashes_performed", "catalyst_tracking_complete", "equipped_catalyst_ids"]:
		var legacy := snapshot.duplicate(true)
		legacy.tracker_checkpoint.erase(field)
		recorder.run_summary_tracker.reset_for_run(_ascension_seed())
		recorder.restore_tracker_items_from_snapshot(legacy)
		var id := "forsworn_grounded" if field in ["dash_tracking_complete", "dashes_performed"] else "unassisted_ascension"
		_check(not _completed(recorder.run_summary_tracker.build_summary({"outcome": "clear"})).has(id), "Missing saved action/loadout proof cannot award " + id)
	for invalid_inventory in ["missing", null, [], "invalid inventory", {"broken": null}]:
		var partial := snapshot.duplicate(true)
		if invalid_inventory is String and invalid_inventory == "missing":
			partial.erase("tracker_boss_reward_items")
		else:
			partial.tracker_boss_reward_items = invalid_inventory
		recorder.run_summary_tracker.reset_for_run(_ascension_seed())
		recorder.restore_tracker_items_from_snapshot(partial)
		_check(not recorder.run_summary_tracker.full_run_tracking_complete, "Malformed inventory remains incomplete history")
		var saved_again := _snapshot_for_tracker(recorder.run_summary_tracker)
		recorder.run_summary_tracker.reset_for_run(_ascension_seed())
		recorder.restore_tracker_items_from_snapshot(saved_again)
		_check(not _completed(recorder.run_summary_tracker.build_summary({"outcome": "clear"})).has("unassisted_ascension"), "Later checkpoints cannot repair missing original evidence")
	var mismatched_seed := _ascension_seed()
	mismatched_seed.equipped_catalyst_ids = ["starting_max_hp_bonus"]
	recorder.run_summary_tracker.reset_for_run(mismatched_seed)
	recorder.restore_tracker_items_from_snapshot(snapshot)
	_check(not recorder.run_summary_tracker.catalyst_tracking_complete, "Changed menu equipment cannot rewrite the saved loadout proof")
	world.context.free()
	world.free()

func _test_progression_compatibility() -> void:
	var legacy := META._get_default_profile()
	META.mark_oath_completed(legacy, "forsworn_unassisted")
	META.mark_oath_reward_claimed(legacy, "forsworn_unassisted")
	_check(not EVALUATOR.OATHS_REGISTRY.has_oath("forsworn_unassisted"), "The old unrestricted Unassisted record is retired")
	_check(not EVALUATOR.OATHS_REGISTRY.is_completed("unassisted_ascension", ["forsworn_unassisted"]), "A free early clear cannot become an Ascension prestige completion")
	var retired := ["empty_hand", "silent_arcana", "uncrowned", "hundredfold", "pilgrims_road", "crown_breaker", "many_paths", "honed_art", "warden_no_hit", "sovereign_no_hit", "lacuna_no_hit", "three_crowns_no_hit", "singular_focus", "unbroken_line", "against_the_clock", "the_unbroken_march", "flawless_run", "closed_fist"]
	var preserved := ["forsworn_warden_no_hit", "forsworn_grounded", "ascension_rank_1", "clear_bastion_forsworn", "clear_bastion_pilgrim", "clear_bastion_delver", "clear_bastion_harbinger"]
	for id in retired:
		_check(not EVALUATOR.OATHS_REGISTRY.has_oath(id), "Retired achievement stays out of the active roster: " + id)
	for id in retired + preserved:
		META.mark_oath_completed(legacy, id)
		META.mark_oath_reward_claimed(legacy, id)
	for id in preserved:
		_check(EVALUATOR.OATHS_REGISTRY.has_oath(id), "Existing earned challenges and lower-bearing clears retain their stable IDs: " + id)
	for catalyst in ["reward_choice_bonus", "rest_heal_bonus", "extra_arcana_slot", "starting_max_hp_bonus"]:
		META.unlock_catalyst(legacy, catalyst)
	META.set_equipped_catalyst_ids(legacy, "bastion", ["reward_choice_bonus", "rest_heal_bonus"])
	META.unlock_character_tier(legacy, "bastion", 3)
	var migrated := META._migrate_profile(legacy, 3)
	_check(META.is_oath_completed(migrated, "forsworn_unassisted") and META.is_oath_reward_claimed(migrated, "forsworn_unassisted"), "Earlier Unassisted history and reward claims remain intact")
	for id in retired + preserved:
		_check(META.is_oath_completed(migrated, id) and META.is_oath_reward_claimed(migrated, id), "Migration preserves historical completion without relabeling: " + id)
	_check(META.get_equipped_catalyst_ids(migrated, "bastion") == ["reward_choice_bonus", "rest_heal_bonus"], "Historical rewards and equipment survive the progression revision")
	_check(META.get_character_highest_unlocked_tier(migrated, "bastion") == 3, "Oath grouping leaves actual bearing progression intact")
	for id in EVALUATOR.OATHS_REGISTRY.get_oath_ids():
		_check(META.is_oath_completed(migrated, id) == preserved.has(id), "Changing eligibility preserves earned status without inventing new completions: " + id)
	var results := EVALUATOR.evaluate_run(_all_conditions_summary(), migrated)
	for pair in [["forsworn_warden_no_hit", "warden_no_hit"], ["forsworn_unbroken_line", "unbroken_line"], ["forsworn_singular_focus", "singular_focus"], ["forsworn_unbroken_march", "the_unbroken_march"]]:
		_check(EVALUATOR.OATHS_REGISTRY.is_completed(pair[0], [pair[1]]), "Original equivalent Any-Bearing achievement stays visibly complete: " + pair[0])
		_check(not results.completed_oath_ids.has(pair[0]), "Equivalent original achievement is not awarded again: " + pair[0])
	for pair in [["forsworn_sovereign_no_hit", "sovereign_no_hit"], ["forsworn_closed_fist", "closed_fist"], ["forsworn_flawless_run", "flawless_run"]]:
		_check(not EVALUATOR.OATHS_REGISTRY.is_completed(pair[0], [pair[1]]), "Old easy-bearing completion cannot satisfy a raised minimum: " + pair[0])
		_check(results.completed_oath_ids.has(pair[0]), "Raised-minimum challenge can still be earned from new qualifying evidence: " + pair[0])
	for id in preserved:
		_check(not results.completed_oath_ids.has(id), "Already-earned stable IDs are not awarded again: " + id)
	_check(not results.unlocked_catalyst_ids.has("reward_choice_bonus") and not results.unlocked_catalyst_ids.has("rest_heal_bonus"), "Previously earned rewards are not granted twice")
	_check(EVALUATOR.apply_results_to_profile(migrated, results), "New qualifying completions are recorded alongside historical progress")
	_check(META.is_oath_completed(migrated, "forsworn_warden_no_hit") and META.is_oath_completed(migrated, "warden_no_hit"), "Active and retired historical achievements retain separate identities")

func _run_tests() -> void:
	_test_encounter_and_full_run_rules()
	_test_singular_focus_categories()
	_test_bearing_requirements()
	_test_postgame_challenges()
	_test_negative_evidence()
	_test_checkpoint_proofs_and_inventory()
	_test_progression_compatibility()
	_test_boss_damage_attribution()
	_test_checkpoint_evidence()
	_test_joiner_summary_and_persistence()
	_test_control_zone_participants()
	_test_coop_checkpoint_isolation()
	if _failures.is_empty():
		print("Oath tracking regression tests passed (%d checks)" % _checks)
	quit(0 if _failures.is_empty() else 1)

func _test_encounter_and_full_run_rules() -> void:
	var tracker := TRACKER.new()
	tracker.reset_for_run(_forsworn_seed())
	tracker.begin_boss_engagement("warden")
	_check(not _completed(tracker.build_summary({"outcome": "death"})).has("forsworn_warden_no_hit"), "An unfinished boss must not award no-hit")
	tracker.record_boss_defeat("warden")
	tracker.record_hold_full_control()
	var summary := tracker.build_summary({"outcome": "death"})
	var earned := _completed(summary)
	_check(earned.has("forsworn_warden_no_hit") and earned.has("forsworn_unbroken_line"), "Completed boss/Hold evidence must survive a later death")
	_check(not earned.has("forsworn_closed_fist") and not earned.has("forsworn_flawless_run"), "Whole-run Oaths still require a clear")
	summary["is_debug"] = true
	_check(_completed(summary).is_empty(), "Debug runs must not grant Oaths")
	tracker.reset_for_run(_forsworn_seed())
	tracker.record_boss_defeat("warden")
	_check(not _completed(tracker.build_summary({"outcome": "clear"})).has("forsworn_warden_no_hit"), "Defeat without engagement evidence must not grant boss no-hit")
	_check(not _completed(tracker.build_summary({"outcome": "clear"})).has("forsworn_unbroken_line"), "An unfinished Hold encounter must not award its Oath")
	tracker.begin_boss_engagement("warden")
	tracker.record_damage_taken(1)
	tracker.record_boss_defeat("warden")
	_check(not tracker.boss_no_hit_ids.has("warden"), "Damage during the boss fight disqualifies no-hit")
	tracker.begin_boss_engagement("sovereign")
	tracker.record_boss_defeat("sovereign")
	_check(tracker.boss_no_hit_ids.has("sovereign"), "Damage in a previous fight must not disqualify the next boss")

func _test_singular_focus_categories() -> void:
	var tracker := TRACKER.new()
	tracker.reset_for_run(_forsworn_seed())
	tracker.record_reward_choice({"id": "sovereigns_double", "name": "Sovereign's Double"}, ENUMS.RewardMode.BOSS, 8)
	var earned := _completed(tracker.build_summary({"outcome": "clear"}))
	_check(not earned.has("forsworn_singular_focus"), "Singular Focus still needs one Arcana")
	tracker.record_reward_choice({"id": "static_wake", "name": "Static Wake"}, ENUMS.RewardMode.ARCANA, 9)
	tracker.record_reward_choice({"id": "static_wake", "name": "Static Wake"}, ENUMS.RewardMode.ARCANA, 10)
	earned = _completed(tracker.build_summary({"outcome": "clear"}))
	_check(earned.has("forsworn_singular_focus"), "One Arcana and its upgrades preserve Singular Focus alongside boss rewards")
	tracker.record_reward_choice({"id": "heartstone", "name": "Heartstone"}, ENUMS.RewardMode.MISSION, 11)
	earned = _completed(tracker.build_summary({"outcome": "clear"}))
	_check(earned.has("forsworn_singular_focus"), "Mission rewards preserve Singular Focus")
	tracker.record_reward_choice({"id": "razor_wind", "name": "Razor Wind"}, ENUMS.RewardMode.ARCANA, 12)
	_check(not _completed(tracker.build_summary({"outcome": "clear"})).has("forsworn_singular_focus"), "A second distinct Arcana disqualifies Singular Focus")
	tracker.reset_for_run(_forsworn_seed())
	tracker.record_reward_choice({"id": "heartstone", "name": "Heartstone"}, ENUMS.RewardMode.MISSION, 1)
	_add_arcana(tracker, "static_wake")
	earned = _completed(tracker.build_summary({"outcome": "clear"}))
	_check(earned.has("forsworn_singular_focus"), "Mission rewards do not add a second Arcana")
	var world := TestWorld.new()
	var recorder := _new_recorder(world)
	recorder.restore_tracker_items_from_snapshot({
		"tracker_checkpoint": tracker.build_checkpoint(),
		"tracker_boon_items": tracker.boon_items,
		"tracker_arcana_items": tracker.arcana_items,
		"tracker_boss_reward_items": tracker.boss_reward_items,
	})
	var resumed := _completed(recorder.run_summary_tracker.build_summary({"outcome": "clear"}))
	_check(resumed.has("forsworn_singular_focus"), "Production snapshot restore preserves Singular Focus with Mission rewards")
	world.context.free()
	world.free()

func _test_boss_damage_attribution() -> void:
	var tracker := TRACKER.new()
	tracker.reset_for_run(_forsworn_seed())
	tracker.begin_boss_engagement("warden", [1, 2])
	tracker.record_damage_taken(2, 1)
	tracker.record_boss_defeat("warden")
	_check(tracker.get_boss_no_hit_ids_for_peer(1).is_empty(), "The player who took damage must fail boss no-hit")
	_check(tracker.get_boss_no_hit_ids_for_peer(2).has("warden"), "A teammate's damage must not disqualify an untouched player")
	_check(tracker.get_boss_no_hit_ids_for_peer(3).is_empty(), "A player absent from the boss engagement must not earn no-hit")
	tracker.begin_boss_engagement("sovereign", [1, 2])
	tracker.record_damage_taken(1, 2)
	tracker.record_boss_defeat("sovereign")
	_check(tracker.get_boss_no_hit_ids_for_peer(1).has("sovereign"), "Peer boss damage must reset for the next encounter")
	_check(not tracker.get_boss_no_hit_ids_for_peer(2).has("sovereign"), "Joined player damage must disqualify that player's current fight")

func _add_arcana(tracker: RefCounted, id: String) -> void:
	tracker.record_reward_choice({"id": id, "name": id.capitalize()}, ENUMS.RewardMode.ARCANA, 1)

func _test_checkpoint_evidence() -> void:
	var tracker := TRACKER.new()
	tracker.reset_for_run(_forsworn_seed())
	tracker.record_primary_attack_fired()
	tracker.record_rest_visit(1)
	tracker.record_damage_taken(1)
	tracker.begin_boss_engagement("warden")
	tracker.record_boss_defeat("warden")
	tracker.record_hold_full_control()
	var restored := TRACKER.new()
	restored.reset_for_run(_forsworn_seed())
	restored.restore_checkpoint(tracker.build_checkpoint())
	var earned := _completed(restored.build_summary({"outcome": "clear"}))
	_check(not earned.has("forsworn_closed_fist") and not earned.has("forsworn_flawless_run") and not earned.has("forsworn_unbroken_march"), "Resume must retain attacks, damage and rest visits")
	_check(earned.has("forsworn_warden_no_hit") and earned.has("forsworn_unbroken_line"), "Resume must retain completed encounter evidence")
	var world := TestWorld.new()
	var recorder := _new_recorder(world)
	recorder.run_started_at_msec = 1
	recorder._run_finished_at_msec = 1001
	recorder.restore_tracker_items_from_snapshot({"tracker_checkpoint": tracker.build_checkpoint(), "run_elapsed_seconds": 480})
	_check(recorder.get_run_elapsed_seconds() == 481, "Resume must retain elapsed time for Against the Clock")
	recorder.restore_tracker_items_from_snapshot({"tracker_boon_items": {"test": {"id": "test", "name": "Test", "stacks": 1}}})
	earned = _completed(recorder.run_summary_tracker.build_summary({"outcome": "clear"}))
	_check(not earned.has("forsworn_closed_fist") and not earned.has("forsworn_flawless_run") and not earned.has("forsworn_unbroken_march") and not earned.has("forsworn_against_the_clock"), "Legacy snapshots must not treat missing history as zero usage")
	_check(recorder.run_summary_tracker.boon_items.has("test"), "Legacy snapshots must retain the known build")
	world.context.free()
	world.free()

func _test_joiner_summary_and_persistence() -> void:
	var world := TestWorld.new()
	var recorder := _new_recorder(world)
	recorder.run_summary_tracker.record_primary_attack_fired()
	var summary := _qualified_summary({"run_id": "oath-test-host", "outcome": "clear", "primary_attacks_fired": 0, "boss_no_hit_ids": [], "stats": {"damage_taken_total": 1}})
	var overrides := {2: {"boss_no_hit_ids": ["warden"]}}
	summary = recorder.summary_with_local_peer_overrides(summary, overrides)
	recorder.finalize_synced_run_summary_for_joiner(summary, "clear")
	_check(int(recorder.latest_run_summary.get("primary_attacks_fired", -1)) == 1, "Joined summary must retain its local attack count")
	_check(not META.is_oath_completed(world.context.meta_progress_profile, "forsworn_closed_fist"), "Host abstaining must not award Closed Fist to an attacking joiner")
	_check(META.is_oath_completed(world.context.meta_progress_profile, "forsworn_warden_no_hit"), "Joined peer boss evidence must reach persisted progress")
	_check(world.context.saves > 0, "Completed Oaths must invoke progression persistence")
	world.context.free()
	world.free()
	world = TestWorld.new()
	recorder = _new_recorder(world)
	recorder.finalize_synced_run_summary_for_joiner(_qualified_summary({"run_id": "oath-test-loss", "outcome": "death", "boss_no_hit_ids": ["warden"], "hold_full_control_achieved": true}), "death")
	_check(META.is_oath_completed(world.context.meta_progress_profile, "forsworn_warden_no_hit") and META.is_oath_completed(world.context.meta_progress_profile, "forsworn_unbroken_line"), "Later death must persist already completed encounter Oaths")
	world.context.free()
	world.free()
	world = TestWorld.new()
	recorder = _new_recorder(world)
	recorder.finalize_synced_run_summary_for_joiner(_qualified_summary({"run_id": "oath-test-idle", "outcome": "clear", "primary_attacks_fired": 50}), "clear")
	_check(META.is_oath_completed(world.context.meta_progress_profile, "forsworn_closed_fist"), "Host attacks must not disqualify an abstaining joiner")
	world.context.free()
	world.free()
	world = TestWorld.new()
	recorder = _new_recorder(world)
	recorder.initialize(false)
	recorder.finalize_synced_run_summary_for_joiner(_qualified_summary({"run_id": "oath-test-debug", "outcome": "clear", "boss_no_hit_ids": ["warden"], "ascension_rank": 5}), "clear")
	_check(world.context.saves == 0 and META.get_completed_oath_ids(world.context.meta_progress_profile).is_empty(), "Debug summaries must not persist Oaths or Ascension progress")
	world.context.free()
	world.free()

func _test_control_zone_participants() -> void:
	var world := TestWorld.new()
	var local := TestPlayer.new()
	var ally := TestPlayer.new()
	world.player = local
	world.party = [local, ally]
	root.add_child(world)
	world.add_child(local)
	world.add_child(ally)
	local.dead = true
	ally.position = Vector2(200, 0)
	var runtime := OBJECTIVES.new()
	runtime.world = world
	_check(not runtime._is_any_active_player_inside_control_zone(Vector2.ZERO, 50), "Fallen players must not hold or capture control zones")
	ally.position = Vector2.ZERO
	_check(runtime._is_any_active_player_inside_control_zone(Vector2.ZERO, 50), "A living ally can hold the shared objective zone")
	runtime.free()
	world.context.free()
	world.free()

func _test_coop_checkpoint_isolation() -> void:
	var world := CheckpointWorld.new()
	world.is_multiplayer = true
	world._save_active_run_checkpoint()
	world._clear_active_run_checkpoint()
	_check(world.context_accesses == 0, "Co-op checkpoints must not access or modify solo saves")
	world.is_multiplayer = false
	world._save_active_run_checkpoint()
	world._clear_active_run_checkpoint()
	_check(world.context_accesses == 2, "Solo checkpoint save and clear paths must remain available")
	world.free()
