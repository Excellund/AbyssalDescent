extends SceneTree

const META := preload("res://scripts/meta_progress_store.gd")
const CATALYSTS := preload("res://scripts/progression/catalyst_registry.gd")
const EVALUATOR := preload("res://scripts/progression/oaths_evaluator.gd")
const SUMMARY_PANEL := preload("res://scripts/ui/run_summary/reward_summary_panel.gd")
const ASCENSION_PANEL := preload("res://scripts/ui/ascension/ascension_panel.gd")
const BUILD_PANEL := preload("res://scripts/build_detail_panel.gd")
const CAP := preload("res://scripts/shared/description_cap_guard.gd")

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _labels_in(node: Node) -> Array[String]:
	var labels: Array[String] = []
	if node is Label:
		labels.append(node.text)
	for child in node.get_children():
		labels.append_array(_labels_in(child))
	return labels

func _run() -> void:
	var ids := CATALYSTS.get_catalyst_ids()
	var profile := META._get_default_profile()
	META.set_equipped_catalyst_ids(profile, "bastion", ids)
	_check(META.get_equipped_catalyst_ids(profile, "bastion").is_empty(), "Locked Catalysts cannot be equipped")
	_check(not META.unlock_catalyst(profile, "unknown_catalyst"), "Unknown Catalyst cannot become an active unlock")
	var summary := {
		"outcome": "clear", "character_id": "bastion", "difficulty_tier": 3,
		"oath_difficulty_verified": true, "oath_min_difficulty_tier": 3, "full_run_tracking_complete": true,
		"ascension_rank": 10, "ascension_tracking_complete": true, "duration_seconds": 300,
		"equipped_catalyst_ids": [], "catalyst_tracking_complete": true,
		"dashes_performed": 0, "dash_tracking_complete": true,
		"boss_no_hit_ids": ["warden", "sovereign", "lacuna"],
		"defeated_boss_ids": ["warden", "sovereign", "lacuna"],
		"hold_full_control_achieved": true, "primary_attacks_fired": 0, "rest_count": 0,
		"stats": {"damage_taken_total": 0, "enemies_killed": 100},
		"build_summary": {"boons": [], "arcana": [], "boss_rewards": []}
	}
	var results := EVALUATOR.evaluate_run(summary, profile)
	var unlocked: Array = results.get("unlocked_catalyst_ids", [])
	_check(unlocked.size() == ids.size(), "All eight Catalyst rewards are reachable through Oaths")
	var summary_panel := SUMMARY_PANEL.new()
	for id in ids:
		var definition := CATALYSTS.get_definition(id)
		_check(unlocked.count(id) == 1, "Multiple Oaths grant " + id + " only once")
		var label := "Catalyst Unlocked: " + String(definition["label"])
		_check((results["labels"] as Array).count(label) == 1, "Results announce new " + id + " exactly once")
		var display := summary_panel._classify_unlock(label)
		_check(display["title"] == "Catalyst Unlocked" and display["detail"] == definition["label"], "Results display actual reward " + id)
		_check(CAP.visible_length(String(definition["description"])) <= 109, "Catalyst description fits for " + id)
	_check(summary_panel._classify_unlock("Oath fulfilled: Earlier run")["detail"] == "Earlier run", "Older run-history Oath labels still display correctly")
	summary_panel.free()
	_check(EVALUATOR.apply_results_to_profile(profile, results), "Oath rewards update profile")
	_check(META.save_meta_progress(profile), "Catalyst unlocks save to isolated profile")
	profile = META.load_meta_progress()
	_check(META.get_unlocked_catalyst_ids(profile).size() == ids.size(), "All Catalyst unlocks survive reload")
	var repeated := EVALUATOR.evaluate_run(summary, profile)
	_check((repeated["unlocked_catalyst_ids"] as Array).is_empty(), "Previously unlocked Catalysts are not announced again")
	for id in ids:
		META.set_equipped_catalyst_ids(profile, "bastion", [id])
		_check(META.save_meta_progress(profile), "Save equipped " + id)
		profile = META.load_meta_progress()
		_check(META.get_equipped_catalyst_ids(profile, "bastion") == [id], "Equipped " + id + " survives reload")
		_check(not CATALYSTS.merge_payloads(META.get_equipped_catalyst_ids(profile, "bastion")).is_empty(), "Reloaded " + id + " provides a runtime effect")
		_check(META.get_equipped_catalyst_ids(profile, "hexweaver").is_empty(), "Equipping " + id + " does not change another character")
	META.set_equipped_catalyst_ids(profile, "bastion", ids)
	_check(META.get_equipped_catalyst_ids(profile, "bastion").size() == 2, "Data layer enforces the two-slot limit")
	META.set_equipped_catalyst_ids(profile, "bastion", ["extra_arcana_slot", "extra_arcana_slot", "shop_reroll"])
	_check(META.get_equipped_catalyst_ids(profile, "bastion") == ["extra_arcana_slot", "shop_reroll"], "Duplicate selections do not consume a slot")
	var legacy := profile.duplicate(true)
	legacy["version"] = 3
	legacy = META._migrate_profile(legacy, 3)
	_check(META.get_equipped_catalyst_ids(legacy, "bastion") == ["extra_arcana_slot", "shop_reroll"], "Renamed Catalyst display names preserve old save IDs")
	var invalid := META._get_default_profile()
	invalid["catalysts_state"] = {
		"unlocked_ids": ["extra_arcana_slot", "shop_reroll", "starting_max_hp_bonus", "unknown"],
		"equipped_per_character": {"bastion": ["unknown", "damage_reduction", "extra_arcana_slot", "extra_arcana_slot", "shop_reroll", "starting_max_hp_bonus"]}
	}
	_check(META.get_equipped_catalyst_ids(invalid, "bastion") == ["extra_arcana_slot", "shop_reroll"], "Loaded equipment ignores unknown, locked, duplicate and excess entries")
	var selection := ASCENSION_PANEL.new()
	var banner := selection._build_catalyst_info_banner()
	_check(" ".join(_labels_in(banner)).contains("next descent"), "Catalyst setup explains when equipment takes effect")
	banner.free()
	for id in ids:
		var definition := CATALYSTS.get_definition(id)
		var card := selection._make_catalyst_card(id, definition, true, true, 1, 2)
		var labels := _labels_in(card)
		_check(labels.has(String(definition["label"])) and labels.has(String(definition["description"])), "Setup card uses current name and effect for " + id)
		card.free()
	selection.free()
	var build := BUILD_PANEL.new()
	root.add_child(build)
	build.setup()
	build.refresh("bastion", [], [], [], null, ["extra_arcana_slot", "shop_reroll"])
	await process_frame
	_check(build.catalyst_panel.visible, "Equipped Catalysts appear in build details")
	_check(build.catalyst_details.get_parsed_text().contains("Prismatic Arcana") and build.catalyst_details.get_parsed_text().contains("Reward Reroll"), "Build details explain both actual equipped effects")
	_check(build.catalyst_details.get_content_height() > 0 and build.catalyst_details.size.x <= 870.0, "Catalyst descriptions lay out within the build panel")
	build.refresh("bastion", [], [], [], null, [])
	_check(not build.catalyst_panel.visible, "No empty Catalyst section without equipped effects")
	build.power_registry_instance.free()
	build.free()
	await process_frame
	print("[OK] Catalyst profile regressions: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
