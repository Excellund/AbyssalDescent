## Centralized power registry and unified data structure
## All upgrades (stat boosts) and trial powers (combat abilities) are defined here
## This is the single source of truth for what powers exist and their metadata

extends Node

const DESCRIPTION_CAP_GUARD := preload("res://scripts/shared/description_cap_guard.gd")

# Power type constants
const POWER_TYPE_UPGRADE = "upgrade"  # Stat boosts: Swift Strike, Heavy Blow, etc
const POWER_TYPE_TRIAL = "trial_power"  # Combat abilities: Razor Wind, Execution Edge, Rupture Wave

# Damage modeling metadata
const DAMAGE_KIND_NONE = "none"
const DAMAGE_KIND_FLAT = "flat"
const DAMAGE_KIND_SCALING = "scaling"
const DAMAGE_KIND_HYBRID = "hybrid"

const DAMAGE_SCALE_SOURCE_NONE = "none"
const DAMAGE_SCALE_SOURCE_DAMAGE = "damage_stat"
const DAMAGE_SCALE_SOURCE_HIT = "hit_damage"

# Boss epitaph lines - displayed on boss defeat
const BOSS_EPITAPHS := {
	"warden": {
		"hexweaver": "Your chaos toppled the first pillar. The void approves.",
		"veilstrider": "The guardian never saw you coming.",
		"bastion": "Your walls didn't break. The Warden did.",
		"default": "A guardian falls."
	},
	"sovereign": {
		"hexweaver": "Order crumbles before true chaos.",
		"veilstrider": "You danced through infinity itself.",
		"bastion": "Not enough stone to hold the cosmos.",
		"default": "Sovereign's reign ends. Only Lacuna stands."
	},
	"lacuna": {
		"hexweaver": "The void answered your call. Now it's silent.",
		"veilstrider": "You stepped through the abyss and back. Impossible.",
		"bastion": "Unbreakable became broken. The irony is exquisite.",
		"default": "The Abyss itself breathes no more."
	}
}

const DAMAGE_MODEL_BY_POWER := {
	# Upgrades
	"first_strike": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X extra hit damage vs enemies above 80% HP"
	},
	"heavy_blow": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X to Damage stat"
	},
	# Trial powers
	"razor_wind": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage"
	},
	"execution_edge": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Hit damage multiplied every N swings"
	},
	"rupture_wave": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage in radius"
	},
	"hunters_snare": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X against slowed targets"
	},
	"phantom_step": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Y% dash-through damage"
	},
	"static_wake": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Y% wake pulse damage"
	},
	"storm_crown": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage on chain proc"
	},
	"wraithstep": {
		"kind": DAMAGE_KIND_HYBRID,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Flat marked-hit bonus + scaling splash/chain"
	},
	# Voidfire archetype
	"voidfire": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage on detonation burst"
	},
	"dread_resonance": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X per resonance stack on same target"
	},
	# Character-lore bridges
	"vow_shatter": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Hit damage multiplied after being hit"
	},
	"eclipse_mark": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% bonus damage on first hit vs marked enemy"
	},
	"fracture_field": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage along non-chaining fault lines from kill position"
	},
	# Boons
	"crushed_vow": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X flat damage on next hit after being hit"
	},
	"severing_edge": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X bonus damage on hits against enemies below 55% HP"
	},
	# Boss rewards
	"apex_predator": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Every hit builds cadence; every 4th hit detonates an impact burst and mauls nearby enemies"
	},
	"void_echo": {
		"kind": DAMAGE_KIND_HYBRID,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Kill zones pulse damage over time and amplify hits inside zone"
	},
	"apex_momentum": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Hit stacks convert into dash-finish momentum wave damage"
	},
	"convergence_surge": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Every N damaging hits, enter Convergence for ~1.6-2.0s and pulse around player for ~46%-63% damage"
	},
	"indomitable_spirit": {
		"kind": DAMAGE_KIND_HYBRID,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Taking damage banks Oath; damaging hits consume all bank for (45% + DR% + 1%*bank) of damage stat"
	}
}

const UPGRADE_BALANCE := {
	"first_strike": {
		"kind": "add_int",
		"property": "first_strike_bonus_damage",
		"add": 16
	},
	"heavy_blow": {
		"kind": "add_int",
		"property": "damage",
		"add": 7
	},
	"wide_arc": {
		"kind": "add_clamp",
		"property": "attack_arc_degrees",
		"add": 28.0,
		"min": 60.0,
		"max": 280.0
	},
	"long_reach": {
		"kind": "add_float",
		"property": "attack_range",
		"add": 11.0
	},
	"fleet_foot": {
		"kind": "add_float",
		"property": "max_speed",
		"add": 17.0
	},
	"blink_dash": {
		"kind": "mul_min",
		"property": "dash_cooldown",
		"mult": 0.80,
		"min": 0.14
	},
	"iron_skin": {
		"kind": "add_int",
		"property": "iron_skin_armor",
		"add": 4,
		"stack_property": "iron_skin_stacks"
	},
	"battle_trance": {
		"kind": "add_float",
		"property": "battle_trance_move_speed_bonus",
		"add": 0.22
	},
	"surge_step": {
		"kind": "add_float",
		"property": "dash_speed",
		"add": 85.0
	},
	"heartstone": {
		"kind": "add_int",
		"property": "max_health",
		"add": 10
	},
	"crushed_vow": {
		"kind": "add_int",
		"property": "crushed_vow_bonus_damage",
		"add": 18
	},
	"severing_edge": {
		"kind": "add_int",
		"property": "severing_edge_bonus_damage",
		"add": 14
	}
}

const TRIAL_POWER_BALANCE := {
	"razor_wind": {
		"range_base": 1.25,
		"range_per_stack": 0.10,
		"damage_ratio_base": 0.6,
		"damage_ratio_per_stack": 0.12,
		"attack_cooldown_mult": 0.96,
		"attack_cooldown_min": 0.1
	},
	"execution_edge": {
		"every_base": 4,
		"every_floor": 2,
		"damage_mult_base": 2.2,
		"damage_mult_per_stack": 0.45,
		"attack_lock_mult": 0.94,
		"attack_lock_min": 0.08
	},
	"rupture_wave": {
		"radius_base": 72.0,
		"radius_per_stack": 10.0,
		"damage_ratio_base": 0.34,
		"damage_ratio_per_stack": 0.1,
		"damage_add": 2
	},
	"aegis_field": {
		"resist_base": 0.12,
		"resist_per_stack": 0.06,
		"resist_cap": 0.42,
		"resist_duration_base": 0.9,
		"resist_duration_per_stack": 0.2,
		"pulse_radius_base": 92.0,
		"pulse_radius_per_stack": 14.0,
		"slow_duration_base": 1.0,
		"slow_duration_per_stack": 0.18,
		"slow_mult_base": 0.7,
		"slow_mult_per_stack": -0.06,
		"slow_mult_min": 0.36,
		"cooldown_base": 3.0,
		"cooldown_per_stack": -0.2,
		"cooldown_min": 1.7
	},
	"hunters_snare": {
		"bonus_damage_base": 4,
		"bonus_damage_per_stack": 3,
		"slow_duration_base": 0.55,
		"slow_duration_per_stack": 0.12,
		"slow_mult_base": 0.72,
		"slow_mult_per_stack": -0.06,
		"slow_mult_min": 0.42
	},
	"phantom_step": {
		# Damage scales as a ratio of damage. Affected by all damage boons and objective mutators.
		"damage_ratio_base": 0.40,
		"damage_ratio_per_stack": 0.08,
		"slow_duration_base": 0.6,
		"slow_duration_per_stack": 0.15,
		"dash_cooldown_mult": 0.92,
		"dash_cooldown_min": 0.18
	},
	"reaper_step": {
		"range_mult_base": 1.36,
		"range_mult_per_stack": 0.12
	},
	"static_wake": {
		# Damage scales as a ratio of damage. Affected by all damage boons and objective mutators.
		"damage_ratio_base": 0.35,
		"damage_ratio_per_stack": 0.10,
		"lifetime_base": 1.6,
		"lifetime_per_stack": 0.35
	},
	"storm_crown": {
		"proc_every_base": 5,
		"proc_every_floor": 2,
		"chain_targets_base": 2,
		"chain_targets_per_stack": 1,
		"chain_targets_cap": 5,
		"chain_radius_base": 120.0,
		"chain_radius_per_stack": 12.0,
		"damage_ratio_base": 0.38,
		"damage_ratio_per_stack": 0.08,
		"damage_ratio_cap": 0.82
	},
	"voidfire": {
		"heat_per_hit": 10.0,
		"heat_cap": 110.0,
		"danger_zone_threshold": 68.0,
		"danger_zone_amp_base": 0.20,
		"danger_zone_amp_per_stack": 0.08,
		"detonate_ratio_base": 0.80,
		"detonate_ratio_per_stack": 0.15,
		"detonate_radius_base": 80.0,
		"detonate_radius_per_stack": 10.0,
		"lockout_base": 1.6,
		"lockout_per_stack": 0.0,
		"lockout_min": 0,
		"overheat_move_mult": 0.65,
		"heat_decay_rate": 10.0,
		"danger_zone_heat_gain_mult": 0.58,
		"reckless_heat_ratio": 0.93,
		"reckless_heat_gain_mult": 1.45,
		"danger_zone_decay_mult": 1.45,
		"reckless_decay_mult": 1.9
	},
	"dread_resonance": {
		"max_stacks": 3,
		"bonus_per_resonance_base": 10,
		"bonus_per_resonance_per_stack": 4
	},
	"vow_shatter": {
		"damage_mult_base": 1.8,
		"damage_mult_per_stack": 0.25
	},
	"eclipse_mark": {
		"radius_base": 110.0,
		"radius_per_stack": 14.0,
		"mark_duration_base": 1.4,
		"mark_duration_per_stack": 0.2,
		"bonus_ratio_base": 0.65,
		"bonus_ratio_per_stack": 0.12
	},
	"fracture_field": {
		"radius_base": 80.0,
		"radius_per_stack": 10.0,
		"damage_ratio_base": 0.50,
		"damage_ratio_per_stack": 0.10,
		"slow_duration_base": 0.6,
		"slow_duration_per_stack": 0.10
	},
	"wraithstep": {
		"mark_duration_base": 2.8,
		"mark_duration_per_stack": 0.55,
		"dash_mark_radius_base": 42.0,
		"dash_mark_radius_per_stack": 10.0,
		"bonus_damage_base": 14,
		"bonus_damage_per_stack": 8,
		"splash_radius_base": 52.0,
		"splash_radius_per_stack": 10.0,
		"splash_ratio_base": 0.55,
		"splash_ratio_per_stack": 0.12,
		"splash_ratio_cap": 0.95
	}
}

const BOSS_REWARD_BALANCE := {
	"apex_predator": {
		"kind": "add_int",
		"property": "apex_predator_bonus_damage",
		"add": 34
	},
	"void_echo": {
		"kind": "add_int",
		"property": "void_echo_damage",
		"add": 52
	},
	"apex_momentum": {
		"kind": "add_float",
		"property": "apex_momentum_speed_bonus",
		"add": 0.09
	},
	"convergence_surge": {
		"kind": "add_float",
		"property": "convergence_surge_damage_ratio",
		"add": 0.22
	},
	"indomitable_spirit": {
		"kind": "add_float",
		"property": "indomitable_spirit_damage_reduction",
		"add": 0.14
	}
}

const UPGRADE_STACK_LIMITS := {
	"first_strike": 3,
	"heavy_blow": 3,
	"long_reach": 3,
	"iron_skin": 3,
	"battle_trance": 3,
	"surge_step": 3,
	"heartstone": 2,
	"crushed_vow": 3,
	"severing_edge": 3
}

const TRIAL_POWER_STACK_LIMITS := {}

const BOSS_REWARD_STACK_LIMITS := {
	"apex_predator": 2,
	"void_echo": 2,
	"apex_momentum": 2,
	"convergence_surge": 2,
	"indomitable_spirit": 2
}

# Unified power data structure
class Power:
	var id: String  # Unique identifier: "swift_strike", "razor_wind", etc
	var name: String  # Display name: "Swift Strike"
	var description: String  # Card text
	var power_type: String  # POWER_TYPE_UPGRADE or POWER_TYPE_TRIAL
	var stack_limit: int  # Max times this power can be taken (0 = unlimited)
	var metadata: Dictionary  # Additional fields: scaling params, effect ranges, etc
	
	func _init(p_id: String, p_name: String, p_desc: String, p_type: String, p_stack_limit: int = 0, p_metadata: Dictionary = {}) -> void:
		id = p_id
		name = p_name
		description = p_desc
		power_type = p_type
		stack_limit = p_stack_limit
		metadata = p_metadata.duplicate()
	
	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"desc": description,
			"type": power_type,
			"stack_limit": stack_limit,
			"metadata": metadata.duplicate(true)
		}


func _ready() -> void:
	# No initialization needed; registry is purely static data
	pass


## Return all upgrades (stat boosts)
func get_upgrade_pool(player_reference: Node = null) -> Array[Dictionary]:
	var first_strike_desc := _get_upgrade_fallback_description("first_strike")
	var heavy_desc := _get_upgrade_fallback_description("heavy_blow")
	var wide_desc := _get_upgrade_fallback_description("wide_arc")
	var reach_desc := _get_upgrade_fallback_description("long_reach")
	var fleet_desc := _get_upgrade_fallback_description("fleet_foot")
	var blink_desc := _get_upgrade_fallback_description("blink_dash")
	var iron_desc := _get_upgrade_fallback_description("iron_skin")
	var trance_desc := _get_upgrade_fallback_description("battle_trance")
	var surge_desc := _get_upgrade_fallback_description("surge_step")
	var heartstone_desc := _get_upgrade_fallback_description("heartstone")
	var crushed_vow_desc := _get_upgrade_fallback_description("crushed_vow")
	var severing_edge_desc := _get_upgrade_fallback_description("severing_edge")
	if is_instance_valid(player_reference):
		first_strike_desc = String(player_reference.get_upgrade_card_desc("first_strike"))
		heavy_desc = String(player_reference.get_upgrade_card_desc("heavy_blow"))
		wide_desc = String(player_reference.get_upgrade_card_desc("wide_arc"))
		reach_desc = String(player_reference.get_upgrade_card_desc("long_reach"))
		fleet_desc = String(player_reference.get_upgrade_card_desc("fleet_foot"))
		blink_desc = String(player_reference.get_upgrade_card_desc("blink_dash"))
		iron_desc = String(player_reference.get_upgrade_card_desc("iron_skin"))
		trance_desc = String(player_reference.get_upgrade_card_desc("battle_trance"))
		surge_desc = String(player_reference.get_upgrade_card_desc("surge_step"))
		heartstone_desc = String(player_reference.get_upgrade_card_desc("heartstone"))
		crushed_vow_desc = String(player_reference.get_upgrade_card_desc("crushed_vow"))
		severing_edge_desc = String(player_reference.get_upgrade_card_desc("severing_edge"))
	return [
		Power.new("first_strike", "First Strike", first_strike_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("first_strike"), get_power_balance("first_strike")).to_dict(),
		Power.new("heavy_blow", "Heavy Blow", heavy_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("heavy_blow"), get_power_balance("heavy_blow")).to_dict(),
		Power.new("wide_arc", "Wide Arc", wide_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("wide_arc"), get_power_balance("wide_arc")).to_dict(),
		Power.new("long_reach", "Long Reach", reach_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("long_reach"), get_power_balance("long_reach")).to_dict(),
		Power.new("fleet_foot", "Fleet Foot", fleet_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("fleet_foot"), get_power_balance("fleet_foot")).to_dict(),
		Power.new("blink_dash", "Blink Dash", blink_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("blink_dash"), get_power_balance("blink_dash")).to_dict(),
		Power.new("iron_skin", "Iron Skin", iron_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("iron_skin"), get_power_balance("iron_skin")).to_dict(),
		Power.new("battle_trance", "Battle Trance", trance_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("battle_trance"), get_power_balance("battle_trance")).to_dict(),
		Power.new("surge_step", "Surge Step", surge_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("surge_step"), get_power_balance("surge_step")).to_dict(),
		Power.new("heartstone", "Heartstone", heartstone_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("heartstone"), get_power_balance("heartstone")).to_dict(),
		Power.new("crushed_vow", "Crushed Vow", crushed_vow_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("crushed_vow"), get_power_balance("crushed_vow")).to_dict(),
		Power.new("severing_edge", "Severing Edge", severing_edge_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("severing_edge"), get_power_balance("severing_edge")).to_dict(),
	]


## Return all trial powers (combat abilities)
func get_trial_power_pool(player_reference: Node = null) -> Array[Dictionary]:
	var razor_desc := _get_trial_fallback_description("razor_wind")
	var execution_desc := _get_trial_fallback_description("execution_edge")
	var rupture_desc := _get_trial_fallback_description("rupture_wave")
	var aegis_desc := _get_trial_fallback_description("aegis_field")
	var snare_desc := _get_trial_fallback_description("hunters_snare")
	
	# Try to get dynamic descriptions from player stack counts
	if is_instance_valid(player_reference):
		razor_desc = String(player_reference.get_trial_power_card_desc("razor_wind"))
		execution_desc = String(player_reference.get_trial_power_card_desc("execution_edge"))
		rupture_desc = String(player_reference.get_trial_power_card_desc("rupture_wave"))
		aegis_desc = String(player_reference.get_trial_power_card_desc("aegis_field"))
		snare_desc = String(player_reference.get_trial_power_card_desc("hunters_snare"))
	
	var phantom_desc := _get_trial_fallback_description("phantom_step")
	var void_desc := _get_trial_fallback_description("reaper_step")
	var static_desc := _get_trial_fallback_description("static_wake")
	var storm_desc := _get_trial_fallback_description("storm_crown")
	var wraith_desc := _get_trial_fallback_description("wraithstep")
	var voidfire_desc := _get_trial_fallback_description("voidfire")
	var dread_desc := _get_trial_fallback_description("dread_resonance")
	var vow_desc := _get_trial_fallback_description("vow_shatter")
	var eclipse_desc := _get_trial_fallback_description("eclipse_mark")
	var fracture_desc := _get_trial_fallback_description("fracture_field")
	if is_instance_valid(player_reference):
		phantom_desc = String(player_reference.get_trial_power_card_desc("phantom_step"))
		void_desc = String(player_reference.get_trial_power_card_desc("reaper_step"))
		static_desc = String(player_reference.get_trial_power_card_desc("static_wake"))
		storm_desc = String(player_reference.get_trial_power_card_desc("storm_crown"))
		wraith_desc = String(player_reference.get_trial_power_card_desc("wraithstep"))
		voidfire_desc = String(player_reference.get_trial_power_card_desc("voidfire"))
		dread_desc = String(player_reference.get_trial_power_card_desc("dread_resonance"))
		vow_desc = String(player_reference.get_trial_power_card_desc("vow_shatter"))
		eclipse_desc = String(player_reference.get_trial_power_card_desc("eclipse_mark"))
		fracture_desc = String(player_reference.get_trial_power_card_desc("fracture_field"))

	return [
		Power.new("razor_wind", "Razor Wind", razor_desc, POWER_TYPE_TRIAL, get_power_stack_limit("razor_wind"), get_power_balance("razor_wind")).to_dict(),
		Power.new("execution_edge", "Execution Edge", execution_desc, POWER_TYPE_TRIAL, get_power_stack_limit("execution_edge"), get_power_balance("execution_edge")).to_dict(),
		Power.new("rupture_wave", "Rupture Wave", rupture_desc, POWER_TYPE_TRIAL, get_power_stack_limit("rupture_wave"), get_power_balance("rupture_wave")).to_dict(),
		Power.new("aegis_field", "Aegis Field", aegis_desc, POWER_TYPE_TRIAL, get_power_stack_limit("aegis_field"), get_power_balance("aegis_field")).to_dict(),
		Power.new("hunters_snare", "Hunter's Snare", snare_desc, POWER_TYPE_TRIAL, get_power_stack_limit("hunters_snare"), get_power_balance("hunters_snare")).to_dict(),
		Power.new("phantom_step", "Phantom Step", phantom_desc, POWER_TYPE_TRIAL, get_power_stack_limit("phantom_step"), get_power_balance("phantom_step")).to_dict(),
		Power.new("reaper_step", "Reaper Step", void_desc, POWER_TYPE_TRIAL, get_power_stack_limit("reaper_step"), get_power_balance("reaper_step")).to_dict(),
		Power.new("static_wake", "Static Wake", static_desc, POWER_TYPE_TRIAL, get_power_stack_limit("static_wake"), get_power_balance("static_wake")).to_dict(),
		Power.new("storm_crown", "Storm Crown", storm_desc, POWER_TYPE_TRIAL, get_power_stack_limit("storm_crown"), get_power_balance("storm_crown")).to_dict(),
		Power.new("wraithstep", "Wraithstep", wraith_desc, POWER_TYPE_TRIAL, get_power_stack_limit("wraithstep"), get_power_balance("wraithstep")).to_dict(),
		Power.new("voidfire", "Voidfire", voidfire_desc, POWER_TYPE_TRIAL, get_power_stack_limit("voidfire"), get_power_balance("voidfire")).to_dict(),
		Power.new("dread_resonance", "Dread Resonance", dread_desc, POWER_TYPE_TRIAL, get_power_stack_limit("dread_resonance"), get_power_balance("dread_resonance")).to_dict(),
		Power.new("vow_shatter", "Vow Shatter", vow_desc, POWER_TYPE_TRIAL, get_power_stack_limit("vow_shatter"), get_power_balance("vow_shatter")).to_dict(),
		Power.new("eclipse_mark", "Eclipse Mark", eclipse_desc, POWER_TYPE_TRIAL, get_power_stack_limit("eclipse_mark"), get_power_balance("eclipse_mark")).to_dict(),
		Power.new("fracture_field", "Fracture Field", fracture_desc, POWER_TYPE_TRIAL, get_power_stack_limit("fracture_field"), get_power_balance("fracture_field")).to_dict(),
	]


func get_objective_upgrade_pool(player_reference: Node = null) -> Array[Dictionary]:
	var pool := get_upgrade_pool(player_reference)
	var favored_ids := {
		"first_strike": true,
		"heavy_blow": true,
		"long_reach": true,
		"fleet_foot": true,
		"blink_dash": true,
		"battle_trance": true,
		"surge_step": true,
	}
	var favored: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	for entry in pool:
		if favored_ids.has(String(entry.get("id", ""))):
			favored.append(entry)
		else:
			fallback.append(entry)
	favored.append_array(fallback)
	return favored


## Return boss-exclusive reward pool
func get_boss_reward_pool(player_reference: Node = null) -> Array[Dictionary]:
	var apex_pred_desc := _get_upgrade_fallback_description("apex_predator")
	var void_echo_desc := _get_upgrade_fallback_description("void_echo")
	var apex_mom_desc := _get_upgrade_fallback_description("apex_momentum")
	var conv_surge_desc := _get_upgrade_fallback_description("convergence_surge")
	var indom_desc := _get_upgrade_fallback_description("indomitable_spirit")
	if is_instance_valid(player_reference):
		apex_pred_desc = String(player_reference.get_upgrade_card_desc("apex_predator"))
		void_echo_desc = String(player_reference.get_upgrade_card_desc("void_echo"))
		apex_mom_desc = String(player_reference.get_upgrade_card_desc("apex_momentum"))
		conv_surge_desc = String(player_reference.get_upgrade_card_desc("convergence_surge"))
		indom_desc = String(player_reference.get_upgrade_card_desc("indomitable_spirit"))
	return [
		Power.new("apex_predator", "Warden's Verdict", apex_pred_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("apex_predator"), get_power_balance("apex_predator")).to_dict(),
		Power.new("void_echo", "Lacuna Echo", void_echo_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("void_echo"), get_power_balance("void_echo")).to_dict(),
		Power.new("apex_momentum", "Sovereign Tempo", apex_mom_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("apex_momentum"), get_power_balance("apex_momentum")).to_dict(),
		Power.new("convergence_surge", "Pillar Convergence", conv_surge_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("convergence_surge"), get_power_balance("convergence_surge")).to_dict(),
		Power.new("indomitable_spirit", "Unbroken Oath", indom_desc, POWER_TYPE_UPGRADE, get_power_stack_limit("indomitable_spirit"), get_power_balance("indomitable_spirit")).to_dict(),
	]


## Get all powers (upgrades + trial powers)
func get_all_powers(player_reference: Node = null) -> Array[Dictionary]:
	var all_powers: Array[Dictionary] = []
	all_powers.append_array(get_upgrade_pool(player_reference))
	all_powers.append_array(get_boss_reward_pool(player_reference))
	all_powers.append_array(get_trial_power_pool(player_reference))
	return all_powers


## Get boss epitaph line for a defeated boss
func get_boss_epitaph(boss_id: String, character_id: String = "") -> String:
	var boss_key := boss_id.strip_edges().to_lower()
	if not BOSS_EPITAPHS.has(boss_key):
		return ""
	var epitaph_dict: Variant = BOSS_EPITAPHS[boss_key]
	if epitaph_dict is Dictionary:
		var char_key := character_id.strip_edges().to_lower()
		if not char_key.is_empty() and epitaph_dict.has(char_key):
			return String(epitaph_dict[char_key])
		if epitaph_dict.has("default"):
			return String(epitaph_dict["default"])
		return ""
	return String(epitaph_dict)


## Check if a power ID exists
func is_valid_power_id(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	for power in get_all_powers():
		if power["id"] == id:
			return true
	return false


## Check if a power ID is an upgrade
func is_upgrade(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	for power in get_upgrade_pool():
		if power["id"] == id:
			return true
	for power in get_boss_reward_pool():
		if power["id"] == id:
			return true
	return false


## Check if a power ID is a trial power
func is_trial_power(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	for power in get_trial_power_pool():
		if power["id"] == id:
			return true
	return false


## Get power by ID
func get_power(power_id: String) -> Dictionary:
	var id := power_id.strip_edges().to_lower()
	for power in get_all_powers():
		if power["id"] == id:
			return power.duplicate()
	return {}


func get_power_balance(power_id: String) -> Dictionary:
	var id := power_id.strip_edges().to_lower()
	if UPGRADE_BALANCE.has(id):
		return (UPGRADE_BALANCE[id] as Dictionary).duplicate(true)
	if TRIAL_POWER_BALANCE.has(id):
		return (TRIAL_POWER_BALANCE[id] as Dictionary).duplicate(true)
	if BOSS_REWARD_BALANCE.has(id):
		return (BOSS_REWARD_BALANCE[id] as Dictionary).duplicate(true)
	return {}


func get_power_stack_limit(power_id: String) -> int:
	var id := power_id.strip_edges().to_lower()
	if UPGRADE_STACK_LIMITS.has(id):
		return int(UPGRADE_STACK_LIMITS[id])
	if TRIAL_POWER_STACK_LIMITS.has(id):
		return int(TRIAL_POWER_STACK_LIMITS[id])
	if BOSS_REWARD_STACK_LIMITS.has(id):
		return int(BOSS_REWARD_STACK_LIMITS[id])
	return 0


func get_damage_model(power_id: String) -> Dictionary:
	var id := power_id.strip_edges().to_lower()
	if DAMAGE_MODEL_BY_POWER.has(id):
		return (DAMAGE_MODEL_BY_POWER[id] as Dictionary).duplicate(true)
	return {
		"kind": DAMAGE_KIND_NONE,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "No direct damage"
	}


func get_damage_model_label(power_id: String) -> String:
	var model := get_damage_model(power_id)
	match String(model.get("kind", DAMAGE_KIND_NONE)):
		DAMAGE_KIND_FLAT:
			return "Flat"
		DAMAGE_KIND_SCALING:
			return "Scaling"
		DAMAGE_KIND_HYBRID:
			return "Hybrid"
		_:
			return "None"


func _damage_kind_bracket(_power_id: String) -> String:
	return ""


func _get_upgrade_fallback_description(upgrade_id: String) -> String:
	var data := get_power_balance(upgrade_id)
	match upgrade_id:
		"first_strike":
			return "%sExtra hit damage versus enemies above 80%% HP: +%d." % [_damage_kind_bracket(upgrade_id), int(data.get("add", 0))]
		"heavy_blow":
			return "%sDamage +%d (to Damage stat)." % [_damage_kind_bracket(upgrade_id), int(data.get("add", 0))]
		"wide_arc":
			return "Attack arc +%.0f degrees." % [float(data.get("add", 0.0))]
		"long_reach":
			return "Attack range +%.0f." % [float(data.get("add", 0.0))]
		"fleet_foot":
			return "Move speed +%.0f." % [float(data.get("add", 0.0))]
		"blink_dash":
			return "Dash cooldown reduced by %.0f%%." % [(1.0 - float(data.get("mult", 1.0))) * 100.0]
		"iron_skin":
			return "Armor +%d." % [int(data.get("add", 0))]
		"battle_trance":
			return "Hitting an enemy grants +%.0f%% move speed for a short time." % [float(data.get("add", 0.0)) * 100.0]
		"surge_step":
			return "Dash speed +%.0f." % [float(data.get("add", 0.0))]
		"heartstone":
			return "Max health +%d." % [int(data.get("add", 0))]
		"crushed_vow":
			return "After being hit, next attack deals +%d damage (consumes on hit)." % [int(data.get("add", 0))]
		"severing_edge":
			return "Bonus damage on hits against enemies below 55%% HP: +%d." % [int(data.get("add", 0))]
		"apex_predator":
			return "Warden's Verdict: every hit builds predator cadence; every 4th hit triggers an impact burst and mauls nearby enemies (power +%d)." % [int(data.get("add", 0))]
		"void_echo":
			return "Lacuna Echo: kills create a void zone that pulses damage and empowers attacks inside it. Zone pulse kills do not spawn additional zones (%d power)." % [int(data.get("add", 0))]
		"apex_momentum":
			return "Sovereign Tempo: hits build tempo; dash end releases a momentum wave. Hitting enemies refunds dash cooldown (+%.0f%% stack speed)." % [float(data.get("add", 0.0)) * 100.0]
		"convergence_surge":
			return "Pillar Convergence: every 4 damaging hits, enter Convergence for ~1.6s and pulse around you. At higher stacks it triggers every 2 hits, lasts ~2.0s, and pulses faster (+%.0f%% window power)." % [float(data.get("add", 0.0)) * 100.0]
		"indomitable_spirit":
			var resist_percent := float(data.get("add", 0.0)) * 100.0
			var retaliation_base := 45.0 + resist_percent
			return "Unbroken Oath: gain %.0f%% DR. Taking damage banks Oath; damaging hits consume all bank for %.0f%% of damage stat + 1%% per banked damage." % [resist_percent, retaliation_base]
		_:
			return "Upgrade your stats."


func _get_trial_fallback_description(power_id: String) -> String:
	match power_id:
		"razor_wind":
			return "%sAttacks launch a piercing wind slash that deals %% of hit damage." % [_damage_kind_bracket(power_id)]
		"execution_edge":
			return "%sEvery few swings become execution strikes that multiply hit damage." % [_damage_kind_bracket(power_id)]
		"rupture_wave":
			return "%sHits detonate a shockwave that deals %% of hit damage." % [_damage_kind_bracket(power_id)]
		"aegis_field":
			return "Taking damage triggers a guard pulse that slows nearby enemies and grants brief damage resistance."
		"hunters_snare":
			return "%sHits slow enemies. Striking slowed enemies deals extra hit damage." % [_damage_kind_bracket(power_id)]
		"phantom_step":
			return "%sDashing through enemies damages and slows them. Damage uses a percentage value." % [_damage_kind_bracket(power_id)]
		"reaper_step":
			return "Dash range and dash speed scale together. Kills refresh dash cooldown."
		"static_wake":
			return "%sDashing leaves an electrified trail that burns enemies. Damage per pulse uses a percentage value." % [_damage_kind_bracket(power_id)]
		"storm_crown":
			return "%sEvery few hits unleash chain lightning that deals %% of hit damage." % [_damage_kind_bracket(power_id)]
		"wraithstep":
			return "%sDash marks enemies. Marked hits deal extra hit damage and trigger splash chains that deal a percentage of hit damage." % [_damage_kind_bracket(power_id)]
		"voidfire":
			var voidfire_desc := "Heat attacks. Danger Zone boosts hit damage. At cap, overheat detonates and briefly locks attacks."
			return DESCRIPTION_CAP_GUARD.assert_visible_cap(voidfire_desc, "voidfire", "fallback")
		"dread_resonance":
			var data := get_power_balance("dread_resonance")
			var max_stacks := int(data.get("max_stacks", 3))
			return "%sChain hits on one enemy build resonance up to %d stacks. Swapping targets resets to 1." % [_damage_kind_bracket(power_id), max_stacks]
		"vow_shatter":
			return "%sTaking a hit primes a vow. Next attack multiplies damage and consumes it. Must be hit again to reload." % [_damage_kind_bracket(power_id)]
		"eclipse_mark":
			return "%sKilling an enemy marks all nearby enemies. First hit on each marked enemy deals amplified damage. Marks expire quickly." % [_damage_kind_bracket(power_id)]
		"fracture_field":
			var fracture_desc := "%sKills rupture fault lines from the slain enemy, striking enemies along each line." % [_damage_kind_bracket(power_id)]
			return DESCRIPTION_CAP_GUARD.assert_visible_cap(fracture_desc, "fracture_field", "fallback")
		_:
			return "Enhances this power."
