## Data-driven system for mapping power registry parameters to player properties
## Eliminates hardcoded match blocks in upgrade_system.gd
## Single source of truth for how power params become player state

extends RefCounted

## Maps trial power IDs to their parameter application rules
## Each entry specifies which parameters to apply and where (property name and type)
const TRIAL_POWER_PARAM_MAP := {
	"razor_wind": {
		"reward_flag": "reward_razor_wind",
		"stack_property": "razor_wind_stacks",
		"parameters": {
			"range_scale": {"property": "razor_wind_range_scale", "type": "float"},
			"damage_ratio": {"property": "razor_wind_damage_ratio", "type": "float"},
			"attack_cooldown": {"property": "attack_cooldown", "type": "float"}
		}
	},
	"execution_edge": {
		"reward_flag": "reward_execution_edge",
		"stack_property": "execution_edge_stacks",
		"parameters": {
			"every": {"property": "execution_every", "type": "int"},
			"damage_mult": {"property": "execution_damage_mult", "type": "float"},
			"attack_lock_duration": {"property": "attack_lock_duration", "type": "float"}
		}
	},
	"rupture_wave": {
		"reward_flag": "reward_rupture_wave",
		"stack_property": "rupture_wave_stacks",
		"parameters": {
			"radius": {"property": "rupture_wave_radius", "type": "float"},
			"damage_ratio": {"property": "rupture_wave_damage_ratio", "type": "float"}
		}
	},
	"aegis_retort": {
		"reward_flag": "reward_aegis_retort",
		"stack_property": "aegis_retort_stacks",
		"parameters": {
			"resist": {"property": "aegis_field_resist_ratio", "type": "float"},
			"duration": {"property": "aegis_field_resist_duration", "type": "float"},
			"radius": {"property": "aegis_field_pulse_radius", "type": "float"},
			"slow_duration": {"property": "aegis_field_slow_duration", "type": "float"},
			"slow_mult": {"property": "aegis_field_slow_mult", "type": "float"},
			"cooldown": {"property": "aegis_field_cooldown", "type": "float"}
		}
	},
	"hunters_snare": {
		"reward_flag": "reward_hunters_snare",
		"stack_property": "hunters_snare_stacks",
		"parameters": {
			"bonus_damage": {"property": "hunters_snare_bonus_damage", "type": "int"},
			"slow_duration": {"property": "hunters_snare_slow_duration", "type": "float"},
			"slow_mult": {"property": "hunters_snare_slow_mult", "type": "float"}
		}
	},
	"phantom_step": {
		"reward_flag": "reward_phantom_step",
		"stack_property": "phantom_step_stacks",
		"parameters": {
			"damage": {"property": "phantom_step_damage", "type": "int"},
			"slow_duration": {"property": "phantom_step_slow_duration", "type": "float"},
			"dash_cooldown": {"property": "dash_cooldown", "type": "float"}
		}
	},
	"apex_surge": {
		"reward_flag": "reward_apex_surge",
		"stack_property": "apex_surge_stacks",
		"parameters": {
			"weave_taut_range_mult": {"property": "apex_surge_weave_taut_range_mult", "type": "float"},
			"weave_taut_damage_mult": {"property": "apex_surge_weave_taut_damage_mult", "type": "float"}
		}
	},
	"static_wake": {
		"reward_flag": "reward_static_wake",
		"stack_property": "static_wake_stacks",
		"parameters": {
			"damage": {"property": "static_wake_damage", "type": "int"},
			"lifetime": {"property": "static_wake_lifetime", "type": "float"}
		}
	},
	"storm_crown": {
		"reward_flag": "reward_storm_crown",
		"stack_property": "storm_crown_stacks",
		"parameters": {
			"proc_every": {"property": "storm_crown_proc_every", "type": "int"},
			"chain_targets": {"property": "storm_crown_chain_targets", "type": "int"},
			"chain_radius": {"property": "storm_crown_chain_radius", "type": "float"},
			"damage_ratio": {"property": "storm_crown_damage_ratio", "type": "float"}
		}
	},
	"wraithstep": {
		"reward_flag": "reward_wraithstep",
		"stack_property": "wraithstep_stacks",
		"parameters": {
			"mark_duration": {"property": "wraithstep_mark_duration", "type": "float"},
			"dash_mark_radius": {"property": "wraithstep_dash_mark_radius", "type": "float"},
			"bonus_damage": {"property": "wraithstep_mark_bonus_damage", "type": "int"},
			"splash_radius": {"property": "wraithstep_mark_splash_radius", "type": "float"},
			"splash_ratio": {"property": "wraithstep_mark_splash_ratio", "type": "float"}
		}
	},
	"voidfire": {
		"reward_flag": "reward_voidfire",
		"stack_property": "voidfire_stacks",
		"parameters": {
			"heat_per_hit": {"property": "voidfire_heat_per_hit", "type": "float"},
			"heat_cap": {"property": "void_heat_cap", "type": "float"},
			"danger_zone_threshold": {"property": "voidfire_danger_zone_threshold", "type": "float"},
			"danger_zone_amp": {"property": "voidfire_danger_zone_amp", "type": "float"},
			"detonate_ratio": {"property": "voidfire_detonate_ratio", "type": "float"},
			"detonate_radius": {"property": "voidfire_detonate_radius", "type": "float"},
			"lockout_duration": {"property": "voidfire_lockout_duration", "type": "float"},
			"overheat_move_mult": {"property": "voidfire_overheat_move_mult", "type": "float"},
			"heat_decay_rate": {"property": "void_heat_decay_rate", "type": "float"},
			"danger_zone_heat_gain_mult": {"property": "voidfire_danger_zone_heat_gain_mult", "type": "float"},
			"reckless_heat_ratio": {"property": "voidfire_reckless_heat_ratio", "type": "float"},
			"reckless_heat_gain_mult": {"property": "voidfire_reckless_heat_gain_mult", "type": "float"},
			"danger_zone_decay_mult": {"property": "voidfire_danger_zone_decay_mult", "type": "float"},
			"reckless_decay_mult": {"property": "voidfire_reckless_decay_mult", "type": "float"}
		}
	},
	"oath_burst": {
		"reward_flag": "reward_oath_burst",
		"stack_property": "oath_burst_stacks",
		"parameters": {
			"pulse_radius": {"property": "oath_burst_pulse_radius", "type": "float"},
			"pulse_ratio": {"property": "oath_burst_pulse_ratio", "type": "float"}
		}
	},
	"vow_shatter": {
		"reward_flag": "reward_vow_shatter",
		"stack_property": "vow_shatter_stacks",
		"parameters": {
			"damage_mult": {"property": "vow_shatter_damage_mult", "type": "float"}
		}
	},
	"eclipse_mark": {
		"reward_flag": "reward_eclipse_mark",
		"stack_property": "eclipse_mark_stacks",
		"parameters": {
			"radius": {"property": "eclipse_mark_radius", "type": "float"},
			"mark_duration": {"property": "eclipse_mark_duration", "type": "float"},
			"bonus_ratio": {"property": "eclipse_mark_bonus_ratio", "type": "float"}
		}
	},
	"fault_line": {
		"reward_flag": "reward_fault_line",
		"stack_property": "fault_line_stacks",
		"parameters": {
			"radius": {"property": "fault_line_radius", "type": "float"},
			"damage_ratio": {"property": "fault_line_damage_ratio", "type": "float"},
			"slow_duration": {"property": "fault_line_slow_duration", "type": "float"}
		}
	}
}

## Maps upgrade IDs to their property definitions
const UPGRADE_PARAM_MAP := {
	"shard_strike": {"property": "shard_strike_bonus_damage"},
	"cracking_arc": {"property": "attack_arc_degrees"},
	"fracture_reach": {"property": "attack_range"},
	"quarry_step": {"property": "max_speed"},
	"swift_reach": {"property": "dash_distance"},
	"relentless_surge": {"property": "dash_speed"},
	"sworn_blade": {"property": "sworn_blade_bonus_damage"},
	"iron_oath": {"properties": ["iron_skin_armor", "iron_skin_stacks"], "special": "iron_skin"},
	"vital_covenant": {"special": "heartstone"},
	"hammered_impact": {"property": "damage"},
	"battle_echo": {"property": "battle_trance_move_speed_bonus"},
	"resonant_edge": {"property": "resonant_edge_bonus_damage"},
	"apex_predator": {"property": "apex_predator_bonus_damage"},
	"void_echo": {"property": "void_echo_damage"},
	"apex_momentum": {"property": "apex_momentum_speed_bonus"},
	"convergence_surge": {"property": "convergence_surge_damage_ratio"},
	"indomitable_spirit": {"property": "indomitable_spirit_damage_reduction"}
}

## Applies precomputed power values to a player reference
## next_values should come from upgrade_system._build_trial_values()
## Returns true if all values were applied successfully
static func apply_trial_power_values(player_reference: Node, power_id: String, next_stack: int, next_values: Dictionary) -> bool:
	if not TRIAL_POWER_PARAM_MAP.has(power_id):
		return false
	
	var power_map: Dictionary = TRIAL_POWER_PARAM_MAP[power_id]
	
	# Set reward flag
	var reward_flag: String = power_map.get("reward_flag", "")
	if not reward_flag.is_empty():
		player_reference.set(reward_flag, true)
	
	# Set stack count
	var stack_property: String = power_map.get("stack_property", "")
	if not stack_property.is_empty():
		player_reference.set(stack_property, next_stack)
	
	# Apply each parameter value to its target property
	var parameters: Dictionary = power_map.get("parameters", {})
	for param_name: String in parameters:
		if not param_name in next_values:
			continue
		
		var param_def: Dictionary = parameters[param_name]
		var property_name: String = param_def.get("property", "")
		var param_type: String = param_def.get("type", "float")
		var param_value = next_values.get(param_name)
		
		if property_name.is_empty():
			continue
		
		# Cast to correct type
		var typed_value: Variant
		match param_type:
			"int":
				typed_value = int(param_value)
			"float":
				typed_value = float(param_value)
			_:
				typed_value = param_value
		
		player_reference.set(property_name, typed_value)
	
	return true

## Gets the property name that should be set for a given trial power parameter
static func get_property_name(power_id: String, param_name: String) -> String:
	if not TRIAL_POWER_PARAM_MAP.has(power_id):
		return ""
	var power_map: Dictionary = TRIAL_POWER_PARAM_MAP[power_id]
	var parameters: Dictionary = power_map.get("parameters", {})
	if param_name in parameters:
		return parameters[param_name].get("property", "")
	return ""

## Gets all player properties that are affected by a trial power
static func get_affected_properties(power_id: String) -> Array[String]:
	var properties: Array[String] = []
	if not TRIAL_POWER_PARAM_MAP.has(power_id):
		return properties
	
	var power_map: Dictionary = TRIAL_POWER_PARAM_MAP[power_id]
	properties.append(power_map.get("reward_flag", ""))
	properties.append(power_map.get("stack_property", ""))
	
	var parameters: Dictionary = power_map.get("parameters", {})
	for param_name: String in parameters:
		var prop_name: String = parameters[param_name].get("property", "")
		if not prop_name.is_empty() and prop_name not in properties:
			properties.append(prop_name)
	
	return properties

## Gets the reward flag property name for a trial power (e.g. "reward_razor_wind")
static func get_reward_flag(power_id: String) -> String:
	if not TRIAL_POWER_PARAM_MAP.has(power_id):
		return ""
	return TRIAL_POWER_PARAM_MAP[power_id].get("reward_flag", "")

## Reads all current parameter values for a trial power from player_reference.
## Returns a Dictionary keyed by param name (same keys as build_trial_values output).
## Enables symmetric cur/next access without hardcoding player property names at call sites.
static func get_current_values(power_id: String, player_reference: Node) -> Dictionary:
	if not TRIAL_POWER_PARAM_MAP.has(power_id):
		return {}
	var power_map: Dictionary = TRIAL_POWER_PARAM_MAP[power_id]
	var parameters: Dictionary = power_map.get("parameters", {})
	var result: Dictionary = {}
	for param_name: String in parameters:
		var param_def: Dictionary = parameters[param_name]
		var property_name: String = param_def.get("property", "")
		if property_name.is_empty():
			continue
		var raw_value: Variant = player_reference.get(property_name)
		if raw_value == null:
			continue
		match param_def.get("type", "float"):
			"int":
				result[param_name] = int(raw_value)
			"float":
				result[param_name] = float(raw_value)
			_:
				result[param_name] = raw_value
	return result

## Gets the stack count property name for a trial power (e.g. "razor_wind_stacks")
static func get_stack_property(power_id: String) -> String:
	if not TRIAL_POWER_PARAM_MAP.has(power_id):
		return ""
	return TRIAL_POWER_PARAM_MAP[power_id].get("stack_property", "")

## Collects all player properties needed for power snapshots
## Used to auto-generate or validate RUN_SNAPSHOT_PROPERTIES
static func get_all_snapshot_properties() -> Array[String]:
	var properties: Array[String] = []
	
	# Add all trial power properties
	for power_id: String in TRIAL_POWER_PARAM_MAP.keys():
		for prop in get_affected_properties(power_id):
			if not prop.is_empty() and prop not in properties:
				properties.append(prop)
	
	# Add all upgrade properties
	for upgrade_id: String in UPGRADE_PARAM_MAP.keys():
		var upgrade_map: Dictionary = UPGRADE_PARAM_MAP[upgrade_id]
		if "property" in upgrade_map:
			var prop: String = upgrade_map.get("property", "")
			if not prop.is_empty() and prop not in properties:
				properties.append(prop)
		elif "properties" in upgrade_map:
			for prop: String in upgrade_map.get("properties", []):
				if not prop.is_empty() and prop not in properties:
					properties.append(prop)
	
	# Add base player properties that are always snapshotted
	var base_properties := [
		"max_speed", "dash_cooldown", "damage", "attack_range", "attack_arc_degrees",
		"attack_cooldown", "attack_lock_duration", "max_health"
	]
	for prop in base_properties:
		if prop not in properties:
			properties.append(prop)
	
	return properties

## Computes scaled parameter values for a trial power at a given stack count.
## balance_data should come from power_registry.get_power_balance(power_id).
## player_reference is required for player-stat-scaled formulas (e.g. phantom_step damage).
## Returns an empty Dictionary if power_id is unknown.
static func build_trial_values(power_id: String, stack_count: int, balance_data: Dictionary, player_reference: Node) -> Dictionary:
	if balance_data.is_empty():
		return {}
	var data := balance_data
	match power_id:
		"razor_wind":
			return {
				"range_scale": float(data.get("range_base", 0.0)) + float(data.get("range_per_stack", 0.0)) * float(stack_count),
				"damage_ratio": float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count),
				"attack_cooldown": maxf(float(data.get("attack_cooldown_min", 0.0)), float(player_reference.get("attack_cooldown")) * float(data.get("attack_cooldown_mult", 1.0)))
			}
		"execution_edge":
			return {
				"every": maxi(int(data.get("every_floor", 1)), int(data.get("every_base", 1)) - stack_count),
				"damage_mult": float(data.get("damage_mult_base", 0.0)) + float(data.get("damage_mult_per_stack", 0.0)) * float(stack_count),
				"attack_lock_duration": maxf(float(data.get("attack_lock_min", 0.0)), float(player_reference.get("attack_lock_duration")) * float(data.get("attack_lock_mult", 1.0)))
			}
		"rupture_wave":
			return {
				"radius": float(data.get("radius_base", 0.0)) + float(data.get("radius_per_stack", 0.0)) * float(stack_count),
				"damage_ratio": float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count)
			}
		"aegis_retort":
			return {
				"resist": minf(float(data.get("resist_cap", 1.0)), float(data.get("resist_base", 0.0)) + float(data.get("resist_per_stack", 0.0)) * float(stack_count)),
				"duration": float(data.get("resist_duration_base", 0.0)) + float(data.get("resist_duration_per_stack", 0.0)) * float(stack_count),
				"radius": float(data.get("pulse_radius_base", 0.0)) + float(data.get("pulse_radius_per_stack", 0.0)) * float(stack_count),
				"slow_duration": float(data.get("slow_duration_base", 0.0)) + float(data.get("slow_duration_per_stack", 0.0)) * float(stack_count),
				"slow_mult": maxf(float(data.get("slow_mult_min", 0.0)), float(data.get("slow_mult_base", 1.0)) + float(data.get("slow_mult_per_stack", 0.0)) * float(stack_count)),
				"cooldown": maxf(float(data.get("cooldown_min", 0.0)), float(data.get("cooldown_base", 0.0)) + float(data.get("cooldown_per_stack", 0.0)) * float(stack_count))
			}
		"hunters_snare":
			return {
				"bonus_damage": int(data.get("bonus_damage_base", 0)) + stack_count * int(data.get("bonus_damage_per_stack", 0)),
				"slow_duration": float(data.get("slow_duration_base", 0.0)) + float(data.get("slow_duration_per_stack", 0.0)) * float(stack_count),
				"slow_mult": maxf(float(data.get("slow_mult_min", 0.0)), float(data.get("slow_mult_base", 1.0)) + float(data.get("slow_mult_per_stack", 0.0)) * float(stack_count))
			}
		"phantom_step":
			var phantom_damage_ratio := float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count)
			return {
				"damage": int(ceil(float(player_reference.get("damage")) * phantom_damage_ratio)),
				"slow_duration": float(data.get("slow_duration_base", 0.0)) + float(data.get("slow_duration_per_stack", 0.0)) * float(stack_count),
				"dash_cooldown": maxf(float(data.get("dash_cooldown_min", 0.0)), float(player_reference.get("dash_cooldown")) * float(data.get("dash_cooldown_mult", 1.0)))
			}
		"apex_surge":
			return {
				"weave_taut_range_mult": float(data.get("weave_taut_range_mult_base", 1.0)) + float(data.get("weave_taut_range_mult_per_stack", 0.0)) * float(stack_count),
				"weave_taut_damage_mult": float(data.get("weave_taut_damage_mult_base", 0.0)) + float(data.get("weave_taut_damage_mult_per_stack", 0.0)) * float(stack_count)
			}
		"static_wake":
			var wake_damage_ratio := float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count)
			return {
				"damage": int(ceil(float(player_reference.get("damage")) * wake_damage_ratio)),
				"lifetime": float(data.get("lifetime_base", 0.0)) + float(data.get("lifetime_per_stack", 0.0)) * float(stack_count)
			}
		"storm_crown":
			return {
				"proc_every": maxi(int(data.get("proc_every_floor", 1)), int(data.get("proc_every_base", 1)) - stack_count),
				"chain_targets": mini(int(data.get("chain_targets_cap", 6)), int(data.get("chain_targets_base", 1)) + stack_count * int(data.get("chain_targets_per_stack", 0))),
				"chain_radius": float(data.get("chain_radius_base", 0.0)) + float(data.get("chain_radius_per_stack", 0.0)) * float(stack_count),
				"damage_ratio": minf(float(data.get("damage_ratio_cap", 1.0)), float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count))
			}
		"wraithstep":
			return {
				"mark_duration": float(data.get("mark_duration_base", 0.0)) + float(data.get("mark_duration_per_stack", 0.0)) * float(stack_count),
				"dash_mark_radius": float(data.get("dash_mark_radius_base", 0.0)) + float(data.get("dash_mark_radius_per_stack", 0.0)) * float(stack_count),
				"bonus_damage": int(data.get("bonus_damage_base", 0)) + stack_count * int(data.get("bonus_damage_per_stack", 0)),
				"splash_radius": float(data.get("splash_radius_base", 0.0)) + float(data.get("splash_radius_per_stack", 0.0)) * float(stack_count),
				"splash_ratio": minf(float(data.get("splash_ratio_cap", 1.0)), float(data.get("splash_ratio_base", 0.0)) + float(data.get("splash_ratio_per_stack", 0.0)) * float(stack_count))
			}
		"voidfire":
			return {
				"heat_per_hit": float(data.get("heat_per_hit", 12.0)),
				"heat_cap": float(data.get("heat_cap", 100.0)),
				"danger_zone_threshold": float(data.get("danger_zone_threshold", 70.0)),
				"danger_zone_amp": float(data.get("danger_zone_amp_base", 0.0)) + float(data.get("danger_zone_amp_per_stack", 0.0)) * float(stack_count),
				"detonate_ratio": float(data.get("detonate_ratio_base", 0.0)) + float(data.get("detonate_ratio_per_stack", 0.0)) * float(stack_count),
				"detonate_radius": float(data.get("detonate_radius_base", 0.0)) + float(data.get("detonate_radius_per_stack", 0.0)) * float(stack_count),
				"lockout_duration": maxf(float(data.get("lockout_min", 0.0)), float(data.get("lockout_base", 0.0)) + float(data.get("lockout_per_stack", 0.0)) * float(stack_count)),
				"overheat_move_mult": float(data.get("overheat_move_mult", 1.0)),
				"heat_decay_rate": float(data.get("heat_decay_rate", 8.0)),
				"danger_zone_heat_gain_mult": float(data.get("danger_zone_heat_gain_mult", 1.0)),
				"reckless_heat_ratio": float(data.get("reckless_heat_ratio", 0.9)),
				"reckless_heat_gain_mult": float(data.get("reckless_heat_gain_mult", 1.0)),
				"danger_zone_decay_mult": float(data.get("danger_zone_decay_mult", 1.0)),
				"reckless_decay_mult": float(data.get("reckless_decay_mult", 1.0))
			}
		"oath_burst":
			return {
				"pulse_radius": float(data.get("pulse_radius_base", 78.0)) + float(data.get("pulse_radius_per_stack", 0.0)) * float(stack_count),
				"pulse_ratio": minf(float(data.get("pulse_ratio_cap", 1.0)), float(data.get("pulse_ratio_base", 0.0)) + float(data.get("pulse_ratio_per_stack", 0.0)) * float(stack_count))
			}
		"eclipse_mark":
			return {
				"radius": float(data.get("radius_base", 0.0)) + float(data.get("radius_per_stack", 0.0)) * float(stack_count),
				"mark_duration": float(data.get("mark_duration_base", 0.0)) + float(data.get("mark_duration_per_stack", 0.0)) * float(stack_count),
				"bonus_ratio": float(data.get("bonus_ratio_base", 0.0)) + float(data.get("bonus_ratio_per_stack", 0.0)) * float(stack_count)
			}
		"fault_line":
			return {
				"radius": float(data.get("radius_base", 0.0)) + float(data.get("radius_per_stack", 0.0)) * float(stack_count),
				"damage_ratio": float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count),
				"slow_duration": float(data.get("slow_duration_base", 0.0)) + float(data.get("slow_duration_per_stack", 0.0)) * float(stack_count)
			}
		_:
			return {}
