## Oaths: achievement-style chase goals evaluated against the run summary.
## Completing an Oath grants a Catalyst (pre-run augment) and/or unlocks
## an Ascension modifier (see ascension_modifier_registry.gd::locked_by_oath_id).
##
## Oaths are pure data here. Evaluation logic lives in oaths_evaluator.gd.
## Each oath declares an evaluator_key plus optional params; the evaluator
## dispatches on that key against build_summary() output.

extends RefCounted

const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")
const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")

## Special / cross-cutting oaths. Per-character/per-bearing clear oaths are
## generated programmatically (see _build_clear_oaths()).
## Saved IDs remain stable even where their historical prefix names a Bearing.
## The declared minimum below, not the ID, determines current eligibility.
const JOURNEY_OATH_IDS := [
	"forsworn_warden_no_hit", "forsworn_unbroken_line",
	"forsworn_singular_focus", "forsworn_unbroken_march"
]
const CHALLENGE_OATH_IDS := [
	"forsworn_sovereign_no_hit", "forsworn_lacuna_no_hit",
	"forsworn_grounded", "forsworn_closed_fist", "forsworn_against_the_clock"
]
## These restored Any-Bearing goals exactly match their earlier versions.
## Earlier lower-Bearing completions cannot substitute for harder challenges.
const EQUIVALENT_JOURNEY_COMPLETIONS := {
	"forsworn_warden_no_hit": "warden_no_hit",
	"forsworn_unbroken_line": "unbroken_line",
	"forsworn_singular_focus": "singular_focus",
	"forsworn_unbroken_march": "the_unbroken_march"
}
const SPECIAL_OATH_DEFINITIONS := {
	"forsworn_warden_no_hit": {
		"label": "Untouched by the Warden",
		"description": "Defeat the Warden without taking damage.",
		"evaluator_key": "boss_no_hit",
		"params": {"boss_id": "warden"},
		"reward_catalyst_id": "extra_arcana_slot",
		"reward_modifier_id": ""
	},
	"forsworn_sovereign_no_hit": {
		"label": "Untouched by the Sovereign",
		"description": "Defeat the Sovereign without taking damage.",
		"evaluator_key": "boss_no_hit",
		"params": {"boss_id": "sovereign"},
		"reward_catalyst_id": "shop_reroll",
		"reward_modifier_id": ""
	},
	"forsworn_lacuna_no_hit": {
		"label": "Untouched by Lacuna",
		"description": "Defeat Lacuna without taking damage.",
		"evaluator_key": "boss_no_hit",
		"params": {"boss_id": "lacuna"},
		"reward_catalyst_id": "damage_reduction",
		"reward_modifier_id": ""
	},
	"forsworn_three_crowns_no_hit": {
		"label": "Untouched Crowns",
		"description": "Clear a run after defeating the Warden, Sovereign and Lacuna without taking damage during those fights. Damage in other encounters is allowed.",
		"evaluator_key": "win_bosses_no_hit",
		"params": {"boss_ids": ["warden", "sovereign", "lacuna"]},
		"reward_catalyst_id": "wave_interval_bonus",
		"reward_modifier_id": ""
	},
	"unassisted_ascension": {
		"label": "Unassisted",
		"description": "Clear at Ascension rank 1 or higher with no Catalysts equipped.",
		"evaluator_key": "win_no_catalysts",
		"params": {"minimum_ascension_rank": 1},
		"reward_catalyst_id": "reward_choice_bonus",
		"reward_modifier_id": ""
	},
	"forsworn_grounded": {
		"label": "Grounded",
		"description": "Clear a run without using Dash.",
		"evaluator_key": "win_no_dash",
		"params": {},
		"reward_catalyst_id": "starting_max_hp_bonus",
		"reward_modifier_id": ""
	},
	"forsworn_singular_focus": {
		"label": "Oath of Singular Focus",
		"description": "Clear a run with only one Arcana. You may upgrade it.",
		"evaluator_key": "win_single_arcana",
		"params": {},
		"reward_catalyst_id": "extra_arcana_slot",
		"reward_modifier_id": ""
	},
	"forsworn_glass_pilgrimage": {
		"label": "Glass Pilgrimage",
		"description": "Clear a run with Glass Descent and Pilgrim's Burden active, without visiting a Rest Site.",
		"evaluator_key": "win_modifier_loadout_no_rest",
		"params": {"modifiers": ["glass_descent", "pilgrims_burden"]},
		"reward_catalyst_id": "damage_reduction",
		"reward_modifier_id": ""
	},
	"forsworn_unbroken_line": {
		"label": "Oath of the Unbroken Line",
		"description": "Hold the Line at full zone control through the entire encounter.",
		"evaluator_key": "hold_zone_full_control",
		"params": {},
		"reward_catalyst_id": "starting_max_hp_bonus",
		"reward_modifier_id": ""
	},
	"ascension_rank_1": {
		"label": "First Ascension",
		"description": "Clear any run at Ascension rank 1 or higher.",
		"evaluator_key": "ascension_rank_at_least",
		"params": {"rank": 1},
		"reward_catalyst_id": "",
		"reward_modifier_id": "mutator_storm"
	},
	"ascension_rank_3": {
		"label": "Third Ascension",
		"description": "Clear any run at Ascension rank 3 or higher.",
		"evaluator_key": "ascension_rank_at_least",
		"params": {"rank": 3},
		"reward_catalyst_id": "wave_interval_bonus",
		"reward_modifier_id": "crowned_bosses"
	},
	"ascension_rank_5": {
		"label": "Fifth Ascension",
		"description": "Clear any run at Ascension rank 5 or higher.",
		"evaluator_key": "ascension_rank_at_least",
		"params": {"rank": 5},
		"reward_catalyst_id": "",
		"reward_modifier_id": "empty_vault"
	},
	"ascension_rank_10": {
		"label": "Pact of the Abyss",
		"description": "Clear any run at maximum Ascension rank.",
		"evaluator_key": "ascension_rank_at_least",
		"params": {"rank": 10},
		"reward_catalyst_id": "ascension_loadout_preset",
		"reward_modifier_id": ""
	},
	"forsworn_against_the_clock": {
		"label": "Against the Clock",
		"description": "Clear a run in under 8 minutes.",
		"evaluator_key": "win_under_time_seconds",
		"params": {"seconds": 480},
		"reward_catalyst_id": "starting_max_hp_bonus",
		"reward_modifier_id": ""
	},
	"forsworn_unbroken_march": {
		"label": "Oath of the Unbroken March",
		"description": "Clear a run without visiting any rest sites.",
		"evaluator_key": "win_no_rest",
		"params": {},
		"reward_catalyst_id": "rest_heal_bonus",
		"reward_modifier_id": ""
	},
	"forsworn_flawless_run": {
		"label": "Oath of the Unscathed",
		"description": "Clear a run without taking any damage.",
		"evaluator_key": "win_no_damage_taken",
		"params": {},
		"reward_catalyst_id": "extra_arcana_slot",
		"reward_modifier_id": ""
	},
	"forsworn_closed_fist": {
		"label": "Oath of the Closed Fist",
		"description": "Clear a run without using Attack.",
		"evaluator_key": "win_no_primary_attack",
		"params": {},
		"reward_catalyst_id": "shop_reroll",
		"reward_modifier_id": ""
	}
}

## A visible progression ladder for every vessel, preserving the original IDs
## and each Bearing's exact-clear requirement.
static func _build_clear_oaths() -> Dictionary:
	var out: Dictionary = {}
	for character_id in CHARACTER_REGISTRY.get_launch_character_ids():
		var character_def: Dictionary = CHARACTER_REGISTRY.get_character(character_id)
		var character_name: String = String(character_def.get("name", character_id.capitalize()))
		for tier in [
			BEARING_ENUMS.BearingTier.PILGRIM,
			BEARING_ENUMS.BearingTier.DELVER,
			BEARING_ENUMS.BearingTier.HARBINGER,
			BEARING_ENUMS.BearingTier.FORSWORN
		]:
			var tier_name: String = _bearing_label(tier)
			var oath_id: String = "clear_%s_%s" % [character_id, tier_name.to_lower()]
			out[oath_id] = {
				"minimum_bearing_tier": tier,
				"progression_stage": "bearing",
				"label": "%s clears %s" % [character_name, tier_name],
				"description": "Complete a run as %s on %s Bearing." % [character_name, tier_name],
				"evaluator_key": "win_with_character_at_bearing",
				"params": {"character_id": character_id, "bearing_tier": tier},
				"reward_catalyst_id": "",
				"reward_modifier_id": ""
			}
	return out

static func _bearing_label(tier: int) -> String:
	match tier:
		BEARING_ENUMS.BearingTier.PILGRIM:
			return "Pilgrim"
		BEARING_ENUMS.BearingTier.DELVER:
			return "Delver"
		BEARING_ENUMS.BearingTier.HARBINGER:
			return "Harbinger"
		BEARING_ENUMS.BearingTier.FORSWORN:
			return "Forsworn"
		_:
			return "Unknown"

static func get_all_definitions() -> Dictionary:
	var out: Dictionary = SPECIAL_OATH_DEFINITIONS.duplicate(true)
	for oath_id in out:
		var tier := BEARING_ENUMS.BearingTier.FORSWORN
		var stage := "prestige"
		if JOURNEY_OATH_IDS.has(oath_id):
			tier = BEARING_ENUMS.BearingTier.PILGRIM
			stage = "journey"
		elif CHALLENGE_OATH_IDS.has(oath_id):
			tier = BEARING_ENUMS.BearingTier.DELVER
			stage = "challenge"
		out[oath_id]["minimum_bearing_tier"] = tier
		out[oath_id]["progression_stage"] = stage
	var clears: Dictionary = _build_clear_oaths()
	for key in clears.keys():
		out[key] = clears[key]
	return out

static func get_oath_ids() -> Array[String]:
	var out: Array[String] = []
	for key in get_all_definitions().keys():
		out.append(String(key))
	return out

## Menu eligibility describes the selected Bearing. Evaluation additionally
## checks the run's recorded difficulty history and the challenge evidence.
static func is_bearing_eligible(definition: Dictionary, tier: int) -> bool:
	if tier < BEARING_ENUMS.BearingTier.PILGRIM or tier > BEARING_ENUMS.BearingTier.FORSWORN:
		return false
	if tier < int(definition.get("minimum_bearing_tier", BEARING_ENUMS.BearingTier.FORSWORN)):
		return false
	if String(definition.get("evaluator_key", "")) == "win_with_character_at_bearing":
		return tier == int((definition.get("params", {}) as Dictionary).get("bearing_tier", -1))
	return true

static func is_completed(oath_id: String, completed_ids: Array) -> bool:
	if completed_ids.has(oath_id):
		return true
	return EQUIVALENT_JOURNEY_COMPLETIONS.has(oath_id) and completed_ids.has(EQUIVALENT_JOURNEY_COMPLETIONS[oath_id])

static func get_definition(oath_id: String) -> Dictionary:
	var defs: Dictionary = get_all_definitions()
	if not defs.has(oath_id):
		return {}
	return (defs[oath_id] as Dictionary).duplicate(true)

static func has_oath(oath_id: String) -> bool:
	return get_all_definitions().has(oath_id)

static func get_reward_catalyst_id(oath_id: String) -> String:
	var def: Dictionary = get_definition(oath_id)
	return String(def.get("reward_catalyst_id", ""))

static func get_reward_modifier_id(oath_id: String) -> String:
	var def: Dictionary = get_definition(oath_id)
	return String(def.get("reward_modifier_id", ""))
