## Catalysts: pre-run gameplay augments equipped per-character before a descent.
## Each catalyst occupies one slot. Slots cap how many can stack on a single run.
## Catalysts are unlocked by completing Oaths (see oaths_registry.gd::reward_catalyst_id).
##
## Application: equipped catalysts are read at run boot and dispatched by
## scripts/encounter_flow_system.gd during run setup.
##
## Per the plan (see /memories/session/plan.md), catalysts are NOT cosmetic:
## every entry adjusts run mechanics. Player buffs are disclosed on the
## leaderboard alongside the ascension rank so a buffed clear is distinguishable.

extends RefCounted

const DEFAULT_SLOT_LIMIT := 2

## Catalyst categories drive the equip UI grouping.
const CATEGORY_REWARD := "reward"
const CATEGORY_PREP := "prep"
const CATEGORY_SURVIVAL := "survival"

const CATALYST_DEFINITIONS := {
	"extra_arcana_slot": {
		"label": "Extra Arcana Slot",
		"description": "Begin each run with one additional arcana stack capacity.",
		"category": CATEGORY_REWARD,
		"payload": {"arcana_capacity_add": 1}
	},
	"shop_reroll": {
		"label": "Shop Reroll",
		"description": "Once per encounter, reroll the offered reward choices.",
		"category": CATEGORY_REWARD,
		"payload": {"reward_rerolls_per_encounter_add": 1}
	},
	"damage_reduction": {
		"label": "Lacuna's Veil",
		"description": "Take 10% less damage from all sources.",
		"category": CATEGORY_SURVIVAL,
		"payload": {"player_damage_taken_mult": 0.90}
	},
	"reward_choice_bonus": {
		"label": "Draft Compass",
		"description": "Reward picks offer one additional option.",
		"category": CATEGORY_REWARD,
		"payload": {"reward_choice_count_add": 1}
	},
	"rest_heal_bonus": {
		"label": "Pilgrim's Tonic",
		"description": "Rest Sites heal 35% more.",
		"category": CATEGORY_SURVIVAL,
		"payload": {"rest_heal_ratio_mult": 1.35}
	},
	"starting_max_hp_bonus": {
		"label": "Iron Vigil",
		"description": "Begin each run with +20 maximum health.",
		"category": CATEGORY_SURVIVAL,
		"payload": {"starting_max_hp_add": 20}
	},
	"wave_interval_bonus": {
		"label": "Calm Before Surge",
		"description": "Waves arrive 12% slower.",
		"category": CATEGORY_SURVIVAL,
		"payload": {"wave_interval_mult": 1.12}
	},
	"ascension_loadout_preset": {
		"label": "Cinder Aegis",
		"description": "Enemy contact damage is reduced by 12%.",
		"category": CATEGORY_SURVIVAL,
		"payload": {"enemy_contact_damage_mult": 0.88}
	}
}

static func get_slot_limit() -> int:
	return DEFAULT_SLOT_LIMIT

static func get_catalyst_ids() -> Array[String]:
	var out: Array[String] = []
	for key in CATALYST_DEFINITIONS.keys():
		out.append(String(key))
	return out

static func has_catalyst(catalyst_id: String) -> bool:
	return CATALYST_DEFINITIONS.has(catalyst_id)

static func get_definition(catalyst_id: String) -> Dictionary:
	if not CATALYST_DEFINITIONS.has(catalyst_id):
		return {}
	return (CATALYST_DEFINITIONS[catalyst_id] as Dictionary).duplicate(true)

static func get_category(catalyst_id: String) -> String:
	if not CATALYST_DEFINITIONS.has(catalyst_id):
		return ""
	return String((CATALYST_DEFINITIONS[catalyst_id] as Dictionary).get("category", ""))

## Merge payloads from a list of catalyst ids. Same key conventions as
## ascension_modifier_registry.merge_loadout_payload(). Unknown ids are skipped.
static func merge_payloads(catalyst_ids: Array) -> Dictionary:
	var merged: Dictionary = {}
	for entry in catalyst_ids:
		var id: String = String(entry)
		if not CATALYST_DEFINITIONS.has(id):
			continue
		var payload: Dictionary = (CATALYST_DEFINITIONS[id] as Dictionary).get("payload", {}) as Dictionary
		for key in payload.keys():
			var key_str: String = String(key)
			var value: Variant = payload[key]
			if key_str.ends_with("_mult"):
				merged[key_str] = float(merged.get(key_str, 1.0)) * float(value)
			elif key_str.ends_with("_add"):
				merged[key_str] = float(merged.get(key_str, 0.0)) + float(value)
			else:
				merged[key_str] = value
	return merged
