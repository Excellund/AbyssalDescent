## Centralized power registry and unified data structure
## All upgrades (stat boosts) and trial powers (combat abilities) are defined here
## This is the single source of truth for what powers exist and their metadata

extends Node

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
	}
}

const UPGRADE_BALANCE := {
	"first_strike": {
		"kind": "add_int",
		"property": "first_strike_bonus_damage",
		"add": 12
	},
	"heavy_blow": {
		"kind": "add_int",
		"property": "damage",
		"add": 8
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
		"add": 0.13
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

const UPGRADE_STACK_LIMITS := {
	"first_strike": 3,
	"long_reach": 3,
	"iron_skin": 3,
	"battle_trance": 3,
	"surge_step": 3,
	"heartstone": 2
}

const TRIAL_POWER_STACK_LIMITS := {}

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
	if is_instance_valid(player_reference):
		phantom_desc = String(player_reference.get_trial_power_card_desc("phantom_step"))
		void_desc = String(player_reference.get_trial_power_card_desc("reaper_step"))
		static_desc = String(player_reference.get_trial_power_card_desc("static_wake"))
		storm_desc = String(player_reference.get_trial_power_card_desc("storm_crown"))
		wraith_desc = String(player_reference.get_trial_power_card_desc("wraithstep"))

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


## Get all powers (upgrades + trial powers)
func get_all_powers(player_reference: Node = null) -> Array[Dictionary]:
	var all_powers: Array[Dictionary] = []
	all_powers.append_array(get_upgrade_pool(player_reference))
	all_powers.append_array(get_trial_power_pool(player_reference))
	return all_powers


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
	return {}


func get_power_stack_limit(power_id: String) -> int:
	var id := power_id.strip_edges().to_lower()
	if UPGRADE_STACK_LIMITS.has(id):
		return int(UPGRADE_STACK_LIMITS[id])
	if TRIAL_POWER_STACK_LIMITS.has(id):
		return int(TRIAL_POWER_STACK_LIMITS[id])
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
		_:
			return "Upgrade your stats."


func _get_trial_fallback_description(power_id: String) -> String:
	match power_id:
		"razor_wind":
			return "%sAttacks launch a piercing wind slash that deals % of hit damage." % [_damage_kind_bracket(power_id)]
		"execution_edge":
			return "%sEvery few swings become execution strikes that multiply hit damage." % [_damage_kind_bracket(power_id)]
		"rupture_wave":
			return "%sHits detonate a shockwave that deals % of hit damage." % [_damage_kind_bracket(power_id)]
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
			return "%sEvery few hits unleash chain lightning that deals % of hit damage." % [_damage_kind_bracket(power_id)]
		"wraithstep":
			return "%sDash marks enemies. Marked hits deal extra hit damage and trigger splash chains that deal a percentage of hit damage." % [_damage_kind_bracket(power_id)]
		_:
			return "Enhances this power."
