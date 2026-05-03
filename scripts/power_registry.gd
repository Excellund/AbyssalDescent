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

# Engine cluster identifiers — four hidden synergy families discoverable through play
const ENGINE_CLUSTER_FRACTURE = "fracture"       # Plant Shards → Link Constellation → fire burst
const ENGINE_CLUSTER_HUNT_WEAVE = "hunt_weave"   # Thread unique targets → Taut → Cascade
const ENGINE_CLUSTER_VOW_LEDGER = "vow_ledger"   # Bind Vow → Fulfill condition → collect payoff
const ENGINE_CLUSTER_ECHO_FORGE = "echo_forge"   # Generate Echoes → reach threshold → Forge fires

# Engine cluster metadata — design grammar for each hidden cluster
const ENGINE_CLUSTER_METADATA := {
	ENGINE_CLUSTER_FRACTURE: {
		"trigger": "Plant Shards via hits, dash, or kills. 3+ live Shards Link and fire a Constellation burst.",
		"opportunity_loss": "Shards expire after ~3.5s. Missing the Link just loses the burst.",
		"visual_key": "shard_cyan",
		"cross_links": [ENGINE_CLUSTER_HUNT_WEAVE, ENGINE_CLUSTER_ECHO_FORGE]
	},
	ENGINE_CLUSTER_HUNT_WEAVE: {
		"trigger": "Hit unique enemies within 2.5s to build Weave threads. 3 threads = Taut. Next kill fires Cascade.",
		"opportunity_loss": "Threads decay individually. Missing the kill while Taut just resets threads.",
		"visual_key": "thread_amber",
		"cross_links": [ENGINE_CLUSTER_FRACTURE, ENGINE_CLUSTER_VOW_LEDGER]
	},
	ENGINE_CLUSTER_VOW_LEDGER: {
		"trigger": "Taking damage binds a Vow. Fulfill it (hit, or meet condition) for a payoff.",
		"opportunity_loss": "Taking damage again before fulfilling resets the current Vow.",
		"visual_key": "vow_gold",
		"cross_links": [ENGINE_CLUSTER_ECHO_FORGE, ENGINE_CLUSTER_HUNT_WEAVE]
	},
	ENGINE_CLUSTER_ECHO_FORGE: {
		"trigger": "Combat events generate Echoes. Echoes accumulate and decay. At threshold the Forge fires an amplified burst.",
		"opportunity_loss": "Echoes decay over time. Slower combat = smaller or missed Forge.",
		"visual_key": "echo_violet",
		"cross_links": [ENGINE_CLUSTER_VOW_LEDGER, ENGINE_CLUSTER_FRACTURE]
	}
}

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
	# Boons — FRACTURE CONSTELLATIONS cluster
	"shard_strike": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X on first hit per target and on Shard-consumed hits"
	},
	"cracking_arc": {
		"kind": DAMAGE_KIND_NONE,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Arc stat only; Shard embeds on multi-hit swings (3+ enemies)"
	},
	"fracture_reach": {
		"kind": DAMAGE_KIND_NONE,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Range stat only; Shard chains on kill at max range"
	},
	# Boons — HUNT WEAVE cluster
	"quarry_step": {
		"kind": DAMAGE_KIND_NONE,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Speed stat only; extends Weave thread window"
	},
	"swift_reach": {
		"kind": DAMAGE_KIND_NONE,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Dash distance stat only; plants Weave thread on dash"
	},
	"relentless_surge": {
		"kind": DAMAGE_KIND_NONE,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Dash speed stat only; post-Cascade speed surge"
	},
	# Boons — VOW LEDGER cluster
	"sworn_blade": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X on next hit after being hit (Vow primed)"
	},
	"iron_oath": {
		"kind": DAMAGE_KIND_NONE,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Armor stat only; extra absorb while Vow is active"
	},
	"vital_covenant": {
		"kind": DAMAGE_KIND_NONE,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Max HP stat only; Vow binds on damage above 60% HP"
	},
	# Boons — ECHO FORGE cluster
	"hammered_impact": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X flat to Damage stat; every 5th hit emits 1 Echo"
	},
	"battle_echo": {
		"kind": DAMAGE_KIND_NONE,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Speed bonus while moving; hits-while-moving build Echo charge"
	},
	"resonant_edge": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X on hits vs enemies below 55% HP; kills emit 2 Echoes"
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
	"oath_burst": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Vow fulfill detonates a radial pulse at Y% of hit damage"
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
	"fault_line": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage along fault lines from kill position; auto-Shards enemies entering zone"
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
	# FRACTURE CONSTELLATIONS cluster
	"shard_strike": {
		"kind": "add_int",
		"property": "shard_strike_bonus_damage",
		"add": 20
	},
	"cracking_arc": {
		"kind": "add_clamp",
		"property": "attack_arc_degrees",
		"add": 28.0,
		"min": 60.0,
		"max": 280.0
	},
	"fracture_reach": {
		"kind": "add_float",
		"property": "attack_range",
		"add": 13.0
	},
	# HUNT WEAVE cluster
	"quarry_step": {
		"kind": "add_float",
		"property": "max_speed",
		"add": 20.0
	},
	"swift_reach": {
		"kind": "add_float",
		"property": "dash_distance",
		"add": 45.0
	},
	"relentless_surge": {
		"kind": "add_float",
		"property": "dash_speed",
		"add": 90.0
	},
	# VOW LEDGER cluster
	"sworn_blade": {
		"kind": "add_int",
		"property": "sworn_blade_bonus_damage",
		"add": 24
	},
	"iron_oath": {
		"kind": "add_int",
		"property": "iron_skin_armor",
		"add": 5,
		"stack_property": "iron_skin_stacks"
	},
	"vital_covenant": {
		"kind": "add_int",
		"property": "max_health",
		"add": 12
	},
	# ECHO FORGE cluster
	"hammered_impact": {
		"kind": "add_int",
		"property": "damage",
		"add": 8
	},
	"battle_echo": {
		"kind": "add_float",
		"property": "battle_trance_move_speed_bonus",
		"add": 0.22
	},
	"resonant_edge": {
		"kind": "add_int",
		"property": "resonant_edge_bonus_damage",
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
	"aegis_retort": {
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
	"apex_surge": {
		"weave_taut_range_mult_base": 1.20,
		"weave_taut_range_mult_per_stack": 0.07,
		"weave_taut_damage_mult_base": 0.18,
		"weave_taut_damage_mult_per_stack": 0.06
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
		"heat_per_hit": 11.0,
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
	"oath_burst": {
		"pulse_radius_base": 78.0,
		"pulse_radius_per_stack": 12.0,
		"pulse_ratio_base": 0.38,
		"pulse_ratio_per_stack": 0.08
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
	"fault_line": {
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
	# Fracture cluster boons
	"shard_strike": 3,
	"cracking_arc": 3,
	"fracture_reach": 3,
	# Hunt Weave cluster boons
	"quarry_step": 3,
	"swift_reach": 2,
	"relentless_surge": 3,
	# Vow Ledger cluster boons
	"sworn_blade": 3,
	"iron_oath": 3,
	"vital_covenant": 2,
	# Echo Forge cluster boons
	"hammered_impact": 3,
	"battle_echo": 3,
	"resonant_edge": 3
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


## Display names for all powers — single source of truth for UI labels
const POWER_DISPLAY_NAMES := {
	# Upgrades
	"shard_strike": "Shard Strike",
	"cracking_arc": "Cracking Arc",
	"fracture_reach": "Fracture Reach",
	"quarry_step": "Quarry Step",
	"swift_reach": "Swift Reach",
	"relentless_surge": "Relentless Surge",
	"sworn_blade": "Sworn Blade",
	"iron_oath": "Iron Oath",
	"vital_covenant": "Vital Covenant",
	"hammered_impact": "Hammered Impact",
	"battle_echo": "Battle Echo",
	"resonant_edge": "Resonant Edge",
	# Trial powers
	"razor_wind": "Razor Wind",
	"execution_edge": "Execution Edge",
	"rupture_wave": "Rupture Wave",
	"aegis_retort": "Aegis Retort",
	"hunters_snare": "Hunter's Snare",
	"phantom_step": "Phantom Step",
	"apex_surge": "Apex Surge",
	"static_wake": "Static Wake",
	"storm_crown": "Storm Crown",
	"wraithstep": "Wraithstep",
	"voidfire": "Voidfire",
	"oath_burst": "Oath Burst",
	"vow_shatter": "Vow Shatter",
	"eclipse_mark": "Eclipse Mark",
	"fault_line": "Fault Line",
	# Boss rewards
	"apex_predator": "Warden's Verdict",
	"void_echo": "Lacuna Echo",
	"apex_momentum": "Sovereign Tempo",
	"convergence_surge": "Pillar Convergence",
	"indomitable_spirit": "Unbroken Oath",
}

## Ordered pool membership arrays — define which IDs belong to each pool and in what order
const UPGRADE_POOL_IDS: Array[String] = [
	# Fracture cluster
	"shard_strike", "cracking_arc", "fracture_reach",
	# Hunt Weave cluster
	"quarry_step", "swift_reach", "relentless_surge",
	# Vow Ledger cluster
	"sworn_blade", "iron_oath", "vital_covenant",
	# Echo Forge cluster
	"hammered_impact", "battle_echo", "resonant_edge",
]

const TRIAL_POWER_POOL_IDS: Array[String] = [
	# Fracture cluster
	"wraithstep", "rupture_wave", "eclipse_mark", "fault_line",
	# Hunt Weave cluster
	"execution_edge", "hunters_snare", "phantom_step", "apex_surge",
	# Vow Ledger cluster
	"vow_shatter", "aegis_retort", "oath_burst",
	# Echo Forge cluster
	"razor_wind", "static_wake", "storm_crown", "voidfire",
]

const BOSS_REWARD_POOL_IDS: Array[String] = [
	"apex_predator", "void_echo", "apex_momentum", "convergence_surge", "indomitable_spirit",
]


func _ready() -> void:
	# No initialization needed; registry is purely static data
	pass


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
		else:
			if power_type == POWER_TYPE_TRIAL:
				desc = _get_trial_fallback_description(id)
			else:
				desc = _get_upgrade_fallback_description(id)
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
		"shard_strike": true,
		"hammered_impact": true,
		"fracture_reach": true,
		"quarry_step": true,
		"swift_reach": true,
		"battle_echo": true,
		"relentless_surge": true,
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


func _get_upgrade_fallback_description(upgrade_id: String) -> String:
	var data := get_power_balance(upgrade_id)
	match upgrade_id:
		"shard_strike":
			return "Enables Fracture Constellation. First hit on each target plants a Shard. Starter loop: hit 3 targets (2 in small packs) to trigger Constellation. Shard-consumed hits deal +%d damage." % [int(data.get("add", 0))]
		"cracking_arc":
			return "Attack arc +%.0f degrees. Hitting 3+ enemies in one swing plants Shards in each." % [float(data.get("add", 0.0))]
		"fracture_reach":
			return "Attack range +%.0f. Killing a Sharded enemy chains their Shard to 1 nearby enemy." % [float(data.get("add", 0.0))]
		"quarry_step":
			return "Move speed +%.0f. Weave modifier only: threads stay active 1s longer while 2+ threads are live (requires Swift Reach)." % [float(data.get("add", 0.0))]
		"swift_reach":
			return "Enables Hunt Weave. Dash distance +%.0f. Each dash plants a Weave thread on the nearest unchained target. Starter loop: seed threads, then kill while Taut for Cascade." % [float(data.get("add", 0.0))]
		"relentless_surge":
			return "Dash speed +%.0f. Weave modifier only: after a Cascade fires, dash speed surges for 1.5s (requires Swift Reach)." % [float(data.get("add", 0.0))]
		"sworn_blade":
			return "Enables Vow Ledger. After being hit, next attack deals +%d damage (Vow primed; consumes on hit). Starter loop: take one hit, strike back immediately." % [int(data.get("add", 0))]
		"iron_oath":
			return "Armor +%d. Vow modifier only: while a Vow is active, armor absorbs 1 extra damage per hit (requires Sworn Blade)." % [int(data.get("add", 0))]
		"vital_covenant":
			return "Max health +%d. Vow modifier only: taking damage above 60%% HP binds a Vow (requires Sworn Blade)." % [int(data.get("add", 0))]
		"hammered_impact":
			return "Enables Echo Forge. Damage +%d. Hits build Echoes; at threshold Forge bursts. Starter loop: stay aggressive, watch the orange ready cue, then cash out." % [int(data.get("add", 0))]
		"battle_echo":
			return "Hitting while moving grants +%.0f%% move speed. Echo modifier only: hits-while-moving build toward Echo generation (requires Hammered Impact)." % [float(data.get("add", 0.0)) * 100.0]
		"resonant_edge":
			return "Bonus damage on hits against enemies below 55%% HP: +%d. Echo modifier only: kills below that threshold emit 2 Echoes (requires Hammered Impact)." % [int(data.get("add", 0))]
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
		"aegis_retort":
			return "Taking damage triggers a guard pulse that slows nearby enemies, grants brief damage resistance, and binds a Vow."
		"hunters_snare":
			return "%sHits slow enemies. Striking slowed enemies deals extra hit damage." % [_damage_kind_bracket(power_id)]
		"phantom_step":
			return "%sDashing through enemies damages and slows them. Damage uses a percentage value." % [_damage_kind_bracket(power_id)]
		"apex_surge":
			return "While Weave is Taut (3+ threads), attack range and hit damage are amplified. Ends after Cascade fires."
		"static_wake":
			return "%sDashing leaves an electrified trail that burns enemies. Damage per pulse uses a percentage value." % [_damage_kind_bracket(power_id)]
		"storm_crown":
			return "%sEvery few hits unleash chain lightning that deals %% of hit damage." % [_damage_kind_bracket(power_id)]
		"wraithstep":
			return "%sDash marks enemies. Marked hits deal extra hit damage and trigger splash chains that deal a percentage of hit damage." % [_damage_kind_bracket(power_id)]
		"voidfire":
			var voidfire_desc := "Heat attacks. Danger Zone boosts hit damage. At cap, overheat detonates and briefly locks attacks."
			return DESCRIPTION_CAP_GUARD.assert_visible_cap(voidfire_desc, "voidfire", "fallback")
		"oath_burst":
			return "Fulfilling a Vow detonates a radial burst that deals a percentage of hit damage to all nearby enemies."
		"vow_shatter":
			return "%sTaking a hit primes a vow. Next attack multiplies damage and consumes it. Must be hit again to reload." % [_damage_kind_bracket(power_id)]
		"eclipse_mark":
			return "%sKilling an enemy marks all nearby enemies. First hit on each marked enemy deals amplified damage. Marks expire quickly." % [_damage_kind_bracket(power_id)]
		"fault_line":
			var fault_desc := "%sKills leave a fault zone. Enemies entering the zone are automatically Sharded and take pulse damage." % [_damage_kind_bracket(power_id)]
			return DESCRIPTION_CAP_GUARD.assert_visible_cap(fault_desc, "fault_line", "fallback")
		_:
			return "Enhances this power."
