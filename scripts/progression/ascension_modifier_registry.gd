## Ascension modifiers: stackable difficulty levers applied above Forsworn.
## Each modifier carries a heat_cost and a payload that merges into the difficulty config
## at run-build time (see scripts/difficulty_config.gd::resolve_ascension_payload()).
##
## Identity rule: modifiers MUST tune existing systems (enemy stats, wave cadence,
## reward economy, mutator frequency). They MUST NOT change encounter signatures or
## introduce new content. See .github/skills/encounter-identity-balance.

extends RefCounted

## Payload merge semantics:
##   "*_mult" keys multiply against the resolved tier value
##   "*_add"  keys add to the resolved tier value
##   "*_set"  keys replace the resolved tier value (use sparingly)
const MODIFIER_DEFINITIONS := {
	"hardened_foes": {
		"label": "Hardened Foes",
		"description": "Enemies have +25% maximum health.",
		"heat_cost": 2,
		"payload": {"enemy_health_mult": 1.25},
		"locked_by_oath_id": ""
	},
	"sharper_blades": {
		"label": "Sharper Blades",
		"description": "Enemy contact damage +20%.",
		"heat_cost": 2,
		"payload": {"enemy_contact_damage_mult": 1.20},
		"locked_by_oath_id": ""
	},
	"relentless_tide": {
		"label": "Relentless Tide",
		"description": "Waves arrive 15% faster.",
		"heat_cost": 2,
		"payload": {"wave_interval_mult": 0.85},
		"locked_by_oath_id": ""
	},
	"thinned_choices": {
		"label": "Thinned Choices",
		"description": "Reward picks offer one fewer option.",
		"heat_cost": 1,
		"payload": {"reward_choice_count_add": -1},
		"locked_by_oath_id": ""
	},
	"barren_road": {
		"label": "Barren Road",
		"description": "Rest sites heal 50% less.",
		"heat_cost": 1,
		"payload": {"rest_heal_ratio_mult": 0.50},
		"locked_by_oath_id": ""
	},
	"mutator_storm": {
		"label": "Mutator Storm",
		"description": "Encounters apply mutators 50% more often.",
		"heat_cost": 2,
		"payload": {"mutator_frequency_mult": 1.50},
		"locked_by_oath_id": "ascension_rank_1"
	},
	"specialist_pressure": {
		"label": "Specialist Pressure",
		"description": "Specialist enemies appear sooner and hit harder.",
		"heat_cost": 2,
		"payload": {
			"specialist_enemy_depth_offset_add": -2,
			"specialist_enemy_pressure_mult": 1.20
		},
		"locked_by_oath_id": "ascension_rank_1"
	},
	"crowned_bosses": {
		"label": "Crowned Bosses",
		"description": "Bosses gain +20% damage and health.",
		"heat_cost": 3,
		"payload": {"boss_difficulty_mult": 1.20},
		"locked_by_oath_id": "ascension_rank_3"
	},
	"glass_descent": {
		"label": "Glass Descent",
		"description": "You take 25% more damage from all sources.",
		"heat_cost": 3,
		"payload": {"player_damage_taken_mult": 1.25},
		"locked_by_oath_id": "ascension_rank_3"
	},
	"empty_vault": {
		"label": "Empty Vault",
		"description": "No rest sites appear on the route.",
		"heat_cost": 3,
		"payload": {"rest_disabled_set": true},
		"locked_by_oath_id": "ascension_rank_5"
	},
	"shrunken_arcana": {
		"label": "Razor Sigils",
		"description": "Mutator-driven damage is increased by 35%.",
		"heat_cost": 2,
		"payload": {"mutator_damage_mult": 1.35},
		"locked_by_oath_id": "ascension_rank_5"
	},
	"pilgrims_burden": {
		"label": "Pilgrim's Burden",
		"description": "Begin each run with 25% less maximum health.",
		"heat_cost": 2,
		"payload": {"player_starting_health_bonus_add": -25},
		"locked_by_oath_id": "ascension_rank_5"
	}
}

## Soft cap for the chase. UI gates loadout heat cost at this rank.
const MAX_ASCENSION_RANK := 10

static func get_modifier_ids() -> Array[String]:
	var out: Array[String] = []
	for key in MODIFIER_DEFINITIONS.keys():
		out.append(String(key))
	return out

static func has_modifier(modifier_id: String) -> bool:
	return MODIFIER_DEFINITIONS.has(modifier_id)

static func get_definition(modifier_id: String) -> Dictionary:
	if not MODIFIER_DEFINITIONS.has(modifier_id):
		return {}
	return (MODIFIER_DEFINITIONS[modifier_id] as Dictionary).duplicate(true)

static func get_heat_cost(modifier_id: String) -> int:
	if not MODIFIER_DEFINITIONS.has(modifier_id):
		return 0
	return int((MODIFIER_DEFINITIONS[modifier_id] as Dictionary).get("heat_cost", 0))

static func get_locked_by_oath_id(modifier_id: String) -> String:
	if not MODIFIER_DEFINITIONS.has(modifier_id):
		return ""
	return String((MODIFIER_DEFINITIONS[modifier_id] as Dictionary).get("locked_by_oath_id", ""))

## Sum heat cost across a loadout (filters unknown ids).
static func compute_loadout_rank(modifier_ids: Array) -> int:
	var total: int = 0
	for entry in modifier_ids:
		var id: String = String(entry)
		if MODIFIER_DEFINITIONS.has(id):
			total += int((MODIFIER_DEFINITIONS[id] as Dictionary).get("heat_cost", 0))
	return total

## Merge all payloads in a loadout into a single dict for the difficulty resolver.
## Multiplicative keys multiply; additive keys add; set keys overwrite (last wins).
static func merge_loadout_payload(modifier_ids: Array) -> Dictionary:
	var merged: Dictionary = {}
	for entry in modifier_ids:
		var id: String = String(entry)
		if not MODIFIER_DEFINITIONS.has(id):
			continue
		var payload: Dictionary = (MODIFIER_DEFINITIONS[id] as Dictionary).get("payload", {}) as Dictionary
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
