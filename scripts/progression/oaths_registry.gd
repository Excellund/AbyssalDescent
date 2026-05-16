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
const SPECIAL_OATH_DEFINITIONS := {
	"warden_no_hit": {
		"label": "Untouched by the Warden",
		"description": "Defeat the Warden without taking damage.",
		"evaluator_key": "boss_no_hit",
		"params": {"boss_id": "warden"},
		"reward_catalyst_id": "extra_arcana_slot",
		"reward_modifier_id": ""
	},
	"sovereign_no_hit": {
		"label": "Untouched by the Sovereign",
		"description": "Defeat the Sovereign without taking damage.",
		"evaluator_key": "boss_no_hit",
		"params": {"boss_id": "sovereign"},
		"reward_catalyst_id": "shop_reroll",
		"reward_modifier_id": ""
	},
	"lacuna_no_hit": {
		"label": "Untouched by Lacuna",
		"description": "Defeat Lacuna without taking damage.",
		"evaluator_key": "boss_no_hit",
		"params": {"boss_id": "lacuna"},
		"reward_catalyst_id": "door_reveal",
		"reward_modifier_id": ""
	},
	"empty_hand": {
		"label": "Oath of the Empty Hand",
		"description": "Clear a run without picking any boons.",
		"evaluator_key": "win_no_boons",
		"params": {},
		"reward_catalyst_id": "starting_arcana_pick",
		"reward_modifier_id": ""
	},
	"silent_arcana": {
		"label": "Oath of Silent Arcana",
		"description": "Clear a run without picking any arcana.",
		"evaluator_key": "win_no_arcana",
		"params": {},
		"reward_catalyst_id": "starting_boon_pick",
		"reward_modifier_id": ""
	},
	"singular_focus": {
		"label": "Oath of Singular Focus",
		"description": "Clear a run with only one arcana picked (any number of stacks).",
		"evaluator_key": "win_single_arcana",
		"params": {},
		"reward_catalyst_id": "extra_arcana_slot",
		"reward_modifier_id": ""
	},
	"unbroken_line": {
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
		"reward_catalyst_id": "personal_best_seed",
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
	"against_the_clock": {
		"label": "Against the Clock",
		"description": "Clear a run in under 8 minutes.",
		"evaluator_key": "win_under_time_seconds",
		"params": {"seconds": 480},
		"reward_catalyst_id": "starting_max_hp_bonus",
		"reward_modifier_id": ""
	},
	"the_unbroken_march": {
		"label": "Oath of the Unbroken March",
		"description": "Clear a run without visiting any rest sites.",
		"evaluator_key": "win_no_rest",
		"params": {},
		"reward_catalyst_id": "starting_boon_pick",
		"reward_modifier_id": ""
	},
	"flawless_run": {
		"label": "Oath of the Unscathed",
		"description": "Clear a run without taking any damage.",
		"evaluator_key": "win_no_damage_taken",
		"params": {},
		"reward_catalyst_id": "extra_arcana_slot",
		"reward_modifier_id": ""
	}
}

## Per-character × per-bearing clear oaths. Generated to avoid hand-maintenance
## as characters are added.
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
	var clears: Dictionary = _build_clear_oaths()
	for key in clears.keys():
		out[key] = clears[key]
	return out

static func get_oath_ids() -> Array[String]:
	var out: Array[String] = []
	for key in get_all_definitions().keys():
		out.append(String(key))
	return out

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
