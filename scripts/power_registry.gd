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
		"riftlancer": "You pinned brute force to a single line and broke it where it stood.",
		"default": "A guardian falls."
	},
	"sovereign": {
		"hexweaver": "Order crumbles before true chaos.",
		"veilstrider": "You danced through infinity itself.",
		"bastion": "Not enough stone to hold the cosmos.",
		"riftlancer": "You found the one true vector in a throne of false geometry.",
		"default": "Sovereign's reign ends. Only Lacuna stands."
	},
	"lacuna": {
		"hexweaver": "The void answered your call. Now it's silent.",
		"veilstrider": "You stepped through the abyss and back. Impossible.",
		"bastion": "Unbreakable became broken. The irony is exquisite.",
		"riftlancer": "Even the missing beat held long enough for your harpoon to land.",
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
	"riftpunch": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X bonus damage on first melee hit after dashing; grants brief contact grace"
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
	"wardens_verdict": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Each hit deals escalating bonus damage; the 4th hit detonates a burst on nearby enemies"
	},
	"lacuna_echo": {
		"kind": DAMAGE_KIND_HYBRID,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Kill zones pulse damage over time and amplify hits inside zone"
	},
	"sovereign_tempo": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Hit stacks convert into dash-finish momentum wave damage"
	},
	"pillar_convergence": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Every N damaging hits, enter Convergence for ~1.6-2.0s and pulse around player for ~46%-63% damage"
	},
	"unbroken_oath": {
		"kind": DAMAGE_KIND_HYBRID,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Single-target hits trickle Oath; multihits scale exponentially. Fill bar to prime next-hit sword strike"
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

## Arcana stacking philosophy:
## L1 is a partial taste of the power. L2 is the headline upgrade. L3 is the ceiling/mastery payoff.
## Each stack should move at least one number knob and (where possible) one structural knob
## (cadence floor, cap relax, arc widening, etc). Stack caps prevent runaway snowball.
const TRIAL_POWER_BALANCE := {
	"razor_wind": {
		"range_base": 1.20,
		"range_per_stack": 0.10,
		"damage_ratio_base": 0.50,
		"damage_ratio_per_stack": 0.20,
		"attack_cooldown_mult": 0.96,
		"attack_cooldown_min": 0.1,
		"arc_base": 24.0,
		"arc_match_player_at_stack": 2
	},
	"execution_edge": {
		"every_base": 4,
		"every_floor": 1,
		"damage_mult_base": 1.9,
		"damage_mult_per_stack": 0.20,
		"attack_lock_mult": 0.94,
		"attack_lock_min": 0.08
	},
	"rupture_wave": {
		"radius_base": 70.0,
		"radius_per_stack": 14.0,
		"damage_ratio_base": 0.30,
		"damage_ratio_per_stack": 0.15,
		"damage_add": 2,
		# L2 unlock: hits also slow. L3 unlock: chain wave from farthest hit.
		"slow_at_stack": 2,
		"slow_duration": 0.4,
		"slow_mult": 0.75,
		"chain_at_stack": 3,
		"chain_damage_ratio": 0.6,
		"chain_radius_ratio": 0.7
	},
	"aegis_field": {
		"resist_base": 0.16,
		"resist_per_stack": 0.08,
		"resist_cap": 0.42,
		"resist_duration_base": 0.8,
		"resist_duration_per_stack": 0.25,
		"pulse_radius_base": 88.0,
		"pulse_radius_per_stack": 18.0,
		"slow_duration_base": 0.9,
		"slow_duration_per_stack": 0.22,
		"slow_mult_base": 0.74,
		"slow_mult_per_stack": -0.08,
		"slow_mult_min": 0.36,
		"cooldown_base": 3.2,
		"cooldown_per_stack": -0.30,
		"cooldown_min": 1.5
	},
	"hunters_snare": {
		"bonus_damage_base": 4,
		"bonus_damage_per_stack": 4,
		"slow_duration_base": 0.6,
		"slow_duration_per_stack": 0.16,
		"slow_mult_base": 0.72,
		"slow_mult_per_stack": -0.06,
		"slow_mult_min": 0.42
	},
	"phantom_step": {
		# Damage scales as a ratio of damage. Affected by all damage boons and objective mutators.
		"damage_ratio_base": 0.40,
		"damage_ratio_per_stack": 0.16,
		"slow_duration_base": 0.6,
		"slow_duration_per_stack": 0.24,
		"dash_cooldown_mult": 0.86,
		"dash_cooldown_min": 0.16
	},
	"riftpunch": {
		# Flat bonus damage on the first melee hit after a dash, inside the window.
		# Grace duration is contact-damage immunity granted on the empowered hit so the player can disengage.
		"bonus_damage_base": 24,
		"bonus_damage_per_stack": 18,
		"window_base": 0.9,
		"window_per_stack": 0.15,
		"grace_base": 0.4,
		"grace_per_stack": 0.08
	},
	"reaper_step": {
		"range_mult_base": 1.40,
		"range_mult_per_stack": 0.22,
		# L2 unlock: chain window grants stored dash on subsequent kills.
		# L3 unlock: chain-window kills extend post-dash grace.
		"chain_window_at_stack": 2,
		"chain_window_duration": 1.5,
		"chain_grace_at_stack": 3,
		"chain_grace_duration": 0.4
	},
	"static_wake": {
		# Damage scales as a ratio of damage. Affected by all damage boons and objective mutators.
		"damage_ratio_base": 0.30,
		"damage_ratio_per_stack": 0.15,
		"lifetime_base": 1.5,
		"lifetime_per_stack": 0.50,
		# L2 unlock: trail damage radius widens. L3 unlock: trail also slows.
		"trail_radius_base": 28.0,
		"trail_radius_per_stack": 6.0,
		"slow_at_stack": 3,
		"slow_duration": 0.3,
		"slow_mult": 0.8
	},
	"storm_crown": {
		"proc_every_base": 5,
		"proc_every_floor": 2,
		"chain_targets_base": 2,
		"chain_targets_per_stack": 1,
		"chain_targets_cap": 5,
		"chain_radius_base": 110.0,
		"chain_radius_per_stack": 18.0,
		"damage_ratio_base": 0.34,
		"damage_ratio_per_stack": 0.12,
		"damage_ratio_cap": 0.82
	},
	"voidfire": {
		"heat_per_hit": 11.0,
		"heat_cap": 110.0,
		"danger_zone_threshold_base": 72.0,
		"danger_zone_threshold_per_stack": -8.0,
		"danger_zone_threshold_min": 40.0,
		"danger_zone_amp_base": 0.15,
		"danger_zone_amp_per_stack": 0.18,
		"detonate_ratio_base": 1.2,
		"detonate_ratio_per_stack": 0.30,
		"detonate_radius_base": 80.0,
		"detonate_radius_per_stack": 10.0,
		"lockout_base": 1.6,
		"lockout_per_stack": 0.0,
		"lockout_min": 0,
		"overheat_move_mult": 0.65,
		"heat_decay_rate": 10.0,
		"danger_zone_heat_gain_mult": 0.64,
		"reckless_heat_ratio": 0.93,
		"reckless_heat_gain_mult": 1.45,
		"danger_zone_decay_mult": 1.35,
		"reckless_decay_mult": 1.9
	},
	"dread_resonance": {
		"max_stacks_base": 2,
		"max_stacks_per_stack": 1,
		"max_stacks_cap": 6,
		"bonus_per_resonance_base": 8,
		"bonus_per_resonance_per_stack": 5
	},
	"vow_shatter": {
		"damage_mult_base": 1.7,
		"damage_mult_per_stack": 0.40
	},
	"eclipse_mark": {
		"radius_base": 100.0,
		"radius_per_stack": 18.0,
		"mark_duration_base": 1.3,
		"mark_duration_per_stack": 0.30,
		"bonus_ratio_base": 0.55,
		"bonus_ratio_per_stack": 0.20
	},
	"fracture_field": {
		"radius_base": 80.0,
		"radius_per_stack": 14.0,
		"damage_ratio_base": 0.40,
		"damage_ratio_per_stack": 0.20,
		"slow_duration_base": 0.5,
		"slow_duration_per_stack": 0.15
	},
	"wraithstep": {
		"mark_duration_base": 2.6,
		"mark_duration_per_stack": 0.7,
		"dash_mark_radius_base": 46.0,
		"dash_mark_radius_per_stack": 14.0,
		"bonus_damage_base": 12,
		"bonus_damage_per_stack": 12,
		"splash_radius_base": 56.0,
		"splash_radius_per_stack": 14.0,
		"splash_ratio_base": 0.55,
		"splash_ratio_per_stack": 0.15,
		"splash_ratio_cap": 0.98
	}
}

const BOSS_REWARD_BALANCE := {
	"wardens_verdict": {
		"kind": "add_int",
		"property": "apex_predator_bonus_damage",
		"add": 34
	},
	"lacuna_echo": {
		"kind": "add_int",
		"property": "void_echo_damage",
		"add": 52
	},
	"sovereign_tempo": {
		"kind": "add_float",
		"property": "apex_momentum_speed_bonus",
		"add": 0.09
	},
	"pillar_convergence": {
		"kind": "add_float",
		"property": "convergence_surge_damage_ratio",
		"add": 0.22
	},
	"unbroken_oath": {
		"kind": "add_float",
		"property": "indomitable_spirit_damage_reduction",
		"add": 0.12
	}
}

const UPGRADE_STACK_LIMITS := {
	"first_strike": 3,
	"heavy_blow": 3,
	"wide_arc": 3,
	"long_reach": 3,
	"fleet_foot": 3,
	"blink_dash": 3,
	"iron_skin": 3,
	"battle_trance": 3,
	"surge_step": 3,
	"heartstone": 2,
	"crushed_vow": 3,
	"severing_edge": 3
}

## Stack caps prevent runaway snowball after the per-stack reshape.
## Most arcana cap at 3; aegis_field & dread_resonance cap at 4 (their natural ceilings
## are built into resist_cap and max_stacks_cap respectively).
const TRIAL_POWER_STACK_LIMITS := {
	"razor_wind": 3,
	"execution_edge": 3,
	"rupture_wave": 3,
	"aegis_field": 4,
	"hunters_snare": 3,
	"phantom_step": 3,
	"riftpunch": 3,
	"reaper_step": 3,
	"static_wake": 3,
	"storm_crown": 3,
	"wraithstep": 3,
	"voidfire": 3,
	"dread_resonance": 4,
	"vow_shatter": 3,
	"eclipse_mark": 3,
	"fracture_field": 3
}

const BOSS_REWARD_STACK_LIMITS := {
	"wardens_verdict": 2,
	"lacuna_echo": 2,
	"sovereign_tempo": 2,
	"pillar_convergence": 2,
	"unbroken_oath": 2
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


## Display names for all powers — single source of truth for UI labels
const POWER_DISPLAY_NAMES := {
	# Upgrades
	"first_strike": "First Strike",
	"heavy_blow": "Heavy Blow",
	"wide_arc": "Wide Arc",
	"long_reach": "Long Reach",
	"fleet_foot": "Fleet Foot",
	"blink_dash": "Blink Dash",
	"iron_skin": "Iron Skin",
	"battle_trance": "Battle Trance",
	"surge_step": "Surge Step",
	"heartstone": "Heartstone",
	"crushed_vow": "Crushed Vow",
	"severing_edge": "Severing Edge",
	# Trial powers
	"razor_wind": "Razor Wind",
	"execution_edge": "Execution Edge",
	"rupture_wave": "Rupture Wave",
	"aegis_field": "Aegis Field",
	"hunters_snare": "Hunter's Snare",
	"phantom_step": "Phantom Step",
	"riftpunch": "Riftpunch",
	"reaper_step": "Reaper Step",
	"static_wake": "Static Wake",
	"storm_crown": "Storm Crown",
	"wraithstep": "Wraithstep",
	"voidfire": "Voidfire",
	"dread_resonance": "Dread Resonance",
	"vow_shatter": "Vow Shatter",
	"eclipse_mark": "Eclipse Mark",
	"fracture_field": "Fracture Field",
	# Boss rewards
	"wardens_verdict": "Warden's Verdict",
	"lacuna_echo": "Lacuna Echo",
	"sovereign_tempo": "Sovereign Tempo",
	"pillar_convergence": "Pillar Convergence",
	"unbroken_oath": "Unbroken Oath",
}

## Ordered pool membership arrays — define which IDs belong to each pool and in what order
const UPGRADE_POOL_IDS: Array[String] = [
	"first_strike", "heavy_blow", "wide_arc", "long_reach", "fleet_foot",
	"blink_dash", "iron_skin", "battle_trance", "surge_step", "heartstone",
	"crushed_vow", "severing_edge",
]

const TRIAL_POWER_POOL_IDS: Array[String] = [
	"razor_wind", "execution_edge", "rupture_wave", "aegis_field", "hunters_snare",
	"phantom_step", "riftpunch", "reaper_step", "static_wake", "storm_crown", "wraithstep",
	"voidfire", "dread_resonance", "vow_shatter", "eclipse_mark", "fracture_field",
]

const BOSS_REWARD_POOL_IDS: Array[String] = [
	"wardens_verdict", "lacuna_echo", "sovereign_tempo", "pillar_convergence", "unbroken_oath",
]


## Worst-case maximum picks the run can offer per pool. If the sum of stack limits
## ever drops below these, the reward UI can run out of legal cards.
const MAX_BOON_PICKS_PER_RUN := 21
const MAX_BOSS_REWARD_PICKS_PER_RUN := 2
const MAX_ARCANA_PICKS_PER_RUN := 21


func _ready() -> void:
	_assert_pool_capacities()


func _assert_pool_capacities() -> void:
	var boon_capacity := _sum_pool_capacity(UPGRADE_POOL_IDS, UPGRADE_STACK_LIMITS)
	var boss_capacity := _sum_pool_capacity(BOSS_REWARD_POOL_IDS, BOSS_REWARD_STACK_LIMITS)
	var arcana_capacity := _sum_pool_capacity(TRIAL_POWER_POOL_IDS, TRIAL_POWER_STACK_LIMITS)
	assert(boon_capacity >= MAX_BOON_PICKS_PER_RUN, "Boon pool capacity %d < max picks %d - players can run out of cards" % [boon_capacity, MAX_BOON_PICKS_PER_RUN])
	assert(boss_capacity >= MAX_BOSS_REWARD_PICKS_PER_RUN, "Boss reward pool capacity %d < max picks %d - players can run out of cards" % [boss_capacity, MAX_BOSS_REWARD_PICKS_PER_RUN])
	assert(arcana_capacity >= MAX_ARCANA_PICKS_PER_RUN, "Arcana pool capacity %d < max picks %d - players can run out of cards" % [arcana_capacity, MAX_ARCANA_PICKS_PER_RUN])
	for id in UPGRADE_POOL_IDS:
		assert(UPGRADE_STACK_LIMITS.has(id), "Boon '%s' is in UPGRADE_POOL_IDS but missing UPGRADE_STACK_LIMITS entry" % id)
	for id in TRIAL_POWER_POOL_IDS:
		assert(TRIAL_POWER_STACK_LIMITS.has(id), "Arcana '%s' is in TRIAL_POWER_POOL_IDS but missing TRIAL_POWER_STACK_LIMITS entry" % id)
	for id in BOSS_REWARD_POOL_IDS:
		assert(BOSS_REWARD_STACK_LIMITS.has(id), "Boss reward '%s' is in BOSS_REWARD_POOL_IDS but missing BOSS_REWARD_STACK_LIMITS entry" % id)


func _sum_pool_capacity(pool_ids: Array, limits: Dictionary) -> int:
	var total := 0
	for id in pool_ids:
		total += int(limits.get(id, 0))
	return total


func _build_power_pool(ids: Array, power_type: String, player_reference: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in ids:
		var display_name := String(POWER_DISPLAY_NAMES.get(id, id))
		var desc: String
		if is_instance_valid(player_reference):
			if power_type == POWER_TYPE_TRIAL:
				desc = String(player_reference.get_trial_power_card_desc(id))
			else:
				desc = String(player_reference.get_upgrade_card_desc(id))
		result.append(Power.new(id, display_name, desc, power_type, get_power_stack_limit(id), get_power_balance(id)).to_dict())
	return result


## Return all upgrades (stat boosts)
func get_upgrade_pool(player_reference: Node = null) -> Array[Dictionary]:
	return _build_power_pool(UPGRADE_POOL_IDS, POWER_TYPE_UPGRADE, player_reference)


## Return all trial powers (combat abilities)
func get_trial_power_pool(player_reference: Node = null) -> Array[Dictionary]:
	return _build_power_pool(TRIAL_POWER_POOL_IDS, POWER_TYPE_TRIAL, player_reference)


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
	return _build_power_pool(BOSS_REWARD_POOL_IDS, POWER_TYPE_UPGRADE, player_reference)


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
	return POWER_DISPLAY_NAMES.has(power_id.strip_edges().to_lower())


## Check if a power ID is an upgrade
func is_upgrade(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	return UPGRADE_POOL_IDS.has(id) or BOSS_REWARD_POOL_IDS.has(id)


## Check if a power ID is a trial power
func is_trial_power(power_id: String) -> bool:
	return TRIAL_POWER_POOL_IDS.has(power_id.strip_edges().to_lower())


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
