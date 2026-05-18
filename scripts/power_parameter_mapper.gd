## Data-driven system for mapping power registry parameters to player properties
## Eliminates hardcoded match blocks in upgrade_system.gd
## Single source of truth for how power params become player state

extends RefCounted

const POWER_REGISTRY := preload("res://scripts/power_registry.gd")
static var _power_registry_instance = null

static func _get_power_registry_instance():
	if _power_registry_instance == null or not is_instance_valid(_power_registry_instance):
		_power_registry_instance = POWER_REGISTRY.new()
	return _power_registry_instance

## Maps upgrade IDs to their property definitions
const UPGRADE_PARAM_MAP := {
	"first_strike": {"property": "first_strike_bonus_damage"},
	"heavy_blow": {"property": "damage"},
	"wide_arc": {"property": "attack_arc_degrees"},
	"long_reach": {"property": "attack_range"},
	"fleet_foot": {"property": "max_speed"},
	"blink_dash": {"property": "dash_cooldown"},
	"iron_skin": {"properties": ["iron_skin_armor", "iron_skin_stacks"], "special": "iron_skin"},
	"battle_trance": {"property": "battle_trance_move_speed_bonus"},
	"surge_step": {"property": "dash_speed"},
	"heartstone": {"special": "heartstone"},
	"bloodpact": {"property": "bloodpact_bonus_damage"},
	"severing_edge": {"property": "severing_edge_bonus_damage"},
	"wardens_verdict": {"property": "apex_predator_bonus_damage"},
	"lacuna_echo": {"property": "void_echo_damage"},
	"sovereign_tempo": {"property": "apex_momentum_speed_bonus"},
	"pillar_convergence": {"property": "convergence_surge_damage_ratio"},
	"unbroken_oath": {"property": "indomitable_spirit_damage_reduction"}
}

## Applies precomputed power values to a player reference
## next_values should come from upgrade_system._build_trial_values()
## Returns true if all values were applied successfully
static func apply_trial_power_values(player_reference: Node, power_id: String, next_stack: int, next_values: Dictionary) -> bool:
	var power_map: Dictionary = _get_power_registry_instance().get_trial_power_param_map(power_id)
	if power_map.is_empty():
		return false
	
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
		var coerced_value: Variant
		match param_type:
			"int":
				coerced_value = int(param_value)
			"float":
				coerced_value = float(param_value)
			_:
				coerced_value = param_value
		
		player_reference.set(property_name, coerced_value)
	
	return true

## Applies an upgrade to the player using registry balance definitions.
## Handles both simple property updates and special cases (heartstone healing, iron_skin tracking).
## Returns true if upgrade was successfully applied.
static func apply_upgrade_values(player_reference: Node, upgrade_id: String) -> bool:
	if not is_instance_valid(player_reference):
		return false
	
	var id := upgrade_id.strip_edges().to_lower()
	var registry := _get_power_registry_instance()
	
	# Get balance data from registry (checks UPGRADE_BALANCE and BOSS_REWARD_BALANCE)
	var balance_data: Dictionary = registry.get_power_balance(id)
	if balance_data.is_empty():
		return false
	
	var kind: String = balance_data.get("kind", "add_int")
	var property: String = balance_data.get("property", "")
	
	# Handle special cases first
	match id:
		"heartstone":
			# Special: heartstone heals the player proportionally to max health gain
			var next_max := int(balance_data.get("add", 0)) + int(player_reference.get_max_health())
			var current_max: int = int(player_reference.get_max_health())
			var max_gain := maxi(0, next_max - current_max)
			var next_current: int = int(player_reference.get_current_health()) + max_gain
			player_reference.set_max_health_and_current(next_max, next_current)
			return true
		
		"iron_skin":
			# Special: iron_skin increments stacks and applies armor via kind rules
			var current_armor: int = int(player_reference.get("iron_skin_armor"))
			var armor_add: int = int(balance_data.get("add", 0))
			var next_armor := current_armor + armor_add
			player_reference.set("iron_skin_armor", next_armor)
			player_reference.set("iron_skin_stacks", int(player_reference.get("iron_skin_stacks")) + 1)
			return true
	
	# Handle standard property-based upgrades using kind rules
	if property.is_empty():
		return false
	
	var current_value: Variant = player_reference.get(property)
	if current_value == null:
		return false
	
	var next_value: Variant
	match kind:
		"add_int":
			next_value = int(current_value) + int(balance_data.get("add", 0))
		"add_float":
			next_value = float(current_value) + float(balance_data.get("add", 0.0))
		"add_clamp":
			var added := float(current_value) + float(balance_data.get("add", 0.0))
			var min_val := float(balance_data.get("min", -INF))
			var max_val := float(balance_data.get("max", INF))
			next_value = clampf(added, min_val, max_val)
		"mul_min":
			var multiplied := float(current_value) * float(balance_data.get("mult", 1.0))
			var min_val := float(balance_data.get("min", 0.0))
			next_value = maxf(multiplied, min_val)
		_:
			return false
	
	player_reference.set(property, next_value)
	return true

## Gets the property name that should be set for a given trial power parameter
static func get_property_name(power_id: String, param_name: String) -> String:
	var power_map: Dictionary = _get_power_registry_instance().get_trial_power_param_map(power_id)
	if power_map.is_empty():
		return ""
	var parameters: Dictionary = power_map.get("parameters", {})
	if param_name in parameters:
		return parameters[param_name].get("property", "")
	return ""

## Gets all player properties that are affected by a trial power
static func get_affected_properties(power_id: String) -> Array[String]:
	var properties: Array[String] = []
	var power_map: Dictionary = _get_power_registry_instance().get_trial_power_param_map(power_id)
	if power_map.is_empty():
		return properties
	
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
	var power_map: Dictionary = _get_power_registry_instance().get_trial_power_param_map(power_id)
	if power_map.is_empty():
		return ""
	return power_map.get("reward_flag", "")

## Reads all current parameter values for a trial power from player_reference.
## Returns a Dictionary keyed by param name (same keys as build_trial_values output).
## Enables symmetric cur/next access without hardcoding player property names at call sites.
static func get_current_values(power_id: String, player_reference: Node) -> Dictionary:
	var power_map: Dictionary = _get_power_registry_instance().get_trial_power_param_map(power_id)
	if power_map.is_empty():
		return {}
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
	var power_map: Dictionary = _get_power_registry_instance().get_trial_power_param_map(power_id)
	if power_map.is_empty():
		return ""
	return power_map.get("stack_property", "")

## Collects all player properties needed for power snapshots
## Used to auto-generate or validate RUN_SNAPSHOT_PROPERTIES
static func get_all_snapshot_properties() -> Array[String]:
	var properties: Array[String] = []
	
	# Add all trial power properties
	for power_id: String in POWER_REGISTRY.TRIAL_POWER_POOL_IDS:
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
static func build_trial_values(power_id: String, stack_count: int, balance_data: Dictionary, player_reference: Node, is_prismatic: bool = false) -> Dictionary:
	var values := _build_trial_values_base(power_id, stack_count, balance_data, player_reference)
	if values.is_empty() or not is_prismatic:
		return values
	return _apply_prismatic_trial_values(power_id, values)


static func _build_trial_values_base(power_id: String, stack_count: int, balance_data: Dictionary, player_reference: Node) -> Dictionary:
	if balance_data.is_empty():
		return {}
	var data := balance_data
	match power_id:
		"razor_wind":
			var arc_value := float(data.get("arc_base", 24.0))
			var arc_match_at := int(data.get("arc_match_player_at_stack", 99))
			if stack_count >= arc_match_at and is_instance_valid(player_reference):
				arc_value = maxf(arc_value, float(player_reference.get("attack_arc_degrees")))
			return {
				"range_scale": float(data.get("range_base", 0.0)) + float(data.get("range_per_stack", 0.0)) * float(stack_count),
				"damage_ratio": float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count),
				"attack_cooldown": maxf(float(data.get("attack_cooldown_min", 0.0)), float(player_reference.get("attack_cooldown")) * float(data.get("attack_cooldown_mult", 1.0))),
				"arc_degrees": arc_value
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
		"aegis_field":
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
		"riftpunch":
			return {
				"bonus_damage": int(data.get("bonus_damage_base", 0)) + stack_count * int(data.get("bonus_damage_per_stack", 0)),
				"window_duration": float(data.get("window_base", 0.0)) + float(data.get("window_per_stack", 0.0)) * float(stack_count),
				"grace_duration": float(data.get("grace_base", 0.0)) + float(data.get("grace_per_stack", 0.0)) * float(stack_count)
			}
		"reaper_step":
			var reaper_chain_window := 0.0
			if stack_count >= int(data.get("chain_window_at_stack", 99)):
				reaper_chain_window = float(data.get("chain_window_duration", 0.0))
			var reaper_chain_grace := 0.0
			if stack_count >= int(data.get("chain_grace_at_stack", 99)):
				reaper_chain_grace = float(data.get("chain_grace_duration", 0.0))
			return {
				"range_mult": float(data.get("range_mult_base", 0.0)) + float(data.get("range_mult_per_stack", 0.0)) * float(stack_count),
				"chain_window": reaper_chain_window,
				"chain_grace": reaper_chain_grace
			}
		"static_wake":
			var wake_damage_ratio := float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count)
			return {
				"damage": int(ceil(float(player_reference.get("damage")) * wake_damage_ratio)),
				"lifetime": float(data.get("lifetime_base", 0.0)) + float(data.get("lifetime_per_stack", 0.0)) * float(stack_count),
				"trail_radius": float(data.get("trail_radius_base", 28.0)) + float(data.get("trail_radius_per_stack", 0.0)) * float(stack_count)
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
			var threshold_value: float
			if data.has("danger_zone_threshold_base"):
				var threshold_min := float(data.get("danger_zone_threshold_min", 0.0))
				threshold_value = maxf(threshold_min, float(data.get("danger_zone_threshold_base", 70.0)) + float(data.get("danger_zone_threshold_per_stack", 0.0)) * float(stack_count))
			else:
				threshold_value = float(data.get("danger_zone_threshold", 70.0))
			return {
				"heat_per_hit": float(data.get("heat_per_hit", 12.0)),
				"heat_cap": float(data.get("heat_cap", 100.0)),
				"danger_zone_threshold": threshold_value,
				"danger_zone_amp": float(data.get("danger_zone_amp", 0.0)),
				"detonate_ratio": float(data.get("detonate_ratio_base", 0.0)) + float(data.get("detonate_ratio_per_stack", 0.0)) * float(stack_count),
				"detonate_radius": float(data.get("detonate_radius_base", 0.0)) + float(data.get("detonate_radius_per_stack", 0.0)) * float(stack_count),
				"lockout_duration": float(data.get("lockout_duration", 0.0)),
				"overheat_move_mult": float(data.get("overheat_move_mult", 1.0)),
				"heat_decay_rate": float(data.get("heat_decay_rate", 8.0)),
				"danger_zone_heat_gain_mult": float(data.get("danger_zone_heat_gain_mult", 1.0)),
				"reckless_heat_ratio": float(data.get("reckless_heat_ratio", 0.9)),
				"reckless_heat_gain_mult": float(data.get("reckless_heat_gain_mult", 1.0)),
				"danger_zone_decay_mult": float(data.get("danger_zone_decay_mult", 1.0)),
				"reckless_decay_mult": float(data.get("reckless_decay_mult", 1.0))
			}
		"dread_resonance":
			return {
				"bonus_per_stack": int(data.get("bonus_per_stack_base", 0)) + stack_count * int(data.get("bonus_per_stack_per_level", 0)),
				"max_stacks": mini(int(data.get("max_stacks_cap", 12)), int(data.get("max_stacks_base", 6)) + stack_count * int(data.get("max_stacks_per_stack", 0)))
			}
		"bloodvow":
			return {
				"damage_mult": float(data.get("damage_mult_base", 1.0)) + float(data.get("damage_mult_per_stack", 0.0)) * float(stack_count),
				"low_hp_threshold": minf(float(data.get("threshold_cap", 0.6)), float(data.get("threshold_base", 0.3)) + float(data.get("threshold_per_stack", 0.1)) * float(stack_count))
			}
		"eclipse_mark":
			return {
				"radius": float(data.get("radius_base", 0.0)) + float(data.get("radius_per_stack", 0.0)) * float(stack_count),
				"mark_duration": float(data.get("mark_duration_base", 0.0)) + float(data.get("mark_duration_per_stack", 0.0)) * float(stack_count),
				"bonus_ratio": float(data.get("bonus_ratio_base", 0.0)) + float(data.get("bonus_ratio_per_stack", 0.0)) * float(stack_count)
			}
		"fracture_field":
			return {
				"radius": float(data.get("radius_base", 0.0)) + float(data.get("radius_per_stack", 0.0)) * float(stack_count),
				"damage_ratio": float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count),
				"slow_duration": float(data.get("slow_duration_base", 0.0)) + float(data.get("slow_duration_per_stack", 0.0)) * float(stack_count)
			}
		"farline_volley":
			return {
				"arc_per_stack": float(data.get("arc_per_stack_base", 0.0)) + float(data.get("arc_per_stack_per_stack", 0.0)) * float(stack_count),
				"bonus_per_stack": int(data.get("bonus_per_stack_base", 0)) + stack_count * int(data.get("bonus_per_stack_per_stack", 0)),
				"stack_cap": mini(int(data.get("stack_cap_max", 99)), int(data.get("stack_cap_base", 0)) + stack_count * int(data.get("stack_cap_per_stack", 0)))
			}
		"sigil_chain":
			return {
				"radius": float(data.get("radius_base", 0.0)) + float(data.get("radius_per_stack", 0.0)) * float(stack_count),
				"damage_ratio": float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count)
			}
		_:
			return {}


static func _apply_prismatic_trial_values(power_id: String, values: Dictionary) -> Dictionary:
	var prismatic := values.duplicate(true)
	match power_id:
		"razor_wind":
			prismatic["range_scale"] = float(prismatic.get("range_scale", 1.0)) * 1.15
			prismatic["damage_ratio"] = float(prismatic.get("damage_ratio", 0.0)) * 1.3
			prismatic["attack_cooldown"] = maxf(0.06, float(prismatic.get("attack_cooldown", 0.0)) * 0.88)
			prismatic["arc_degrees"] = float(prismatic.get("arc_degrees", 0.0)) + 24.0
		"execution_edge":
			prismatic["every"] = maxi(1, int(prismatic.get("every", 1)) - 1)
			prismatic["damage_mult"] = float(prismatic.get("damage_mult", 1.0)) * 1.3
			prismatic["attack_lock_duration"] = maxf(0.05, float(prismatic.get("attack_lock_duration", 0.0)) * 0.9)
		"rupture_wave":
			prismatic["radius"] = float(prismatic.get("radius", 0.0)) * 1.2
			prismatic["damage_ratio"] = float(prismatic.get("damage_ratio", 0.0)) * 1.35
		"aegis_field":
			prismatic["resist"] = minf(0.60, float(prismatic.get("resist", 0.0)) + 0.08)
			prismatic["duration"] = float(prismatic.get("duration", 0.0)) * 1.25
			prismatic["radius"] = float(prismatic.get("radius", 0.0)) * 1.2
			prismatic["slow_duration"] = float(prismatic.get("slow_duration", 0.0)) * 1.25
			prismatic["slow_mult"] = maxf(0.25, float(prismatic.get("slow_mult", 1.0)) * 0.82)
			prismatic["cooldown"] = maxf(0.9, float(prismatic.get("cooldown", 0.0)) * 0.85)
		"hunters_snare":
			prismatic["bonus_damage"] = int(float(prismatic.get("bonus_damage", 0)) * 1.75)
			prismatic["slow_duration"] = float(prismatic.get("slow_duration", 0.0)) * 1.35
			prismatic["slow_mult"] = maxf(0.25, float(prismatic.get("slow_mult", 1.0)) * 0.72)
		"phantom_step":
			prismatic["damage"] = int(float(prismatic.get("damage", 0)) * 1.35)
			prismatic["slow_duration"] = float(prismatic.get("slow_duration", 0.0)) * 1.25
			prismatic["dash_cooldown"] = maxf(0.05, float(prismatic.get("dash_cooldown", 0.0)) * 0.85)
		"riftpunch":
			prismatic["bonus_damage"] = int(float(prismatic.get("bonus_damage", 0)) * 1.4)
			prismatic["window_duration"] = float(prismatic.get("window_duration", 0.0)) * 1.35
			prismatic["grace_duration"] = float(prismatic.get("grace_duration", 0.0)) * 1.5
		"reaper_step":
			prismatic["range_mult"] = float(prismatic.get("range_mult", 1.0)) * 1.18
			prismatic["chain_window"] = maxf(2.8, float(prismatic.get("chain_window", 0.0)))
			prismatic["chain_grace"] = maxf(0.75, float(prismatic.get("chain_grace", 0.0)))
		"static_wake":
			prismatic["damage"] = int(float(prismatic.get("damage", 0)) * 1.4)
			prismatic["lifetime"] = float(prismatic.get("lifetime", 0.0)) * 1.25
			prismatic["trail_radius"] = float(prismatic.get("trail_radius", 0.0)) * 1.2
		"storm_crown":
			prismatic["proc_every"] = maxi(1, int(prismatic.get("proc_every", 1)) - 1)
			prismatic["chain_targets"] = int(prismatic.get("chain_targets", 1)) + 2
			prismatic["chain_radius"] = float(prismatic.get("chain_radius", 0.0)) * 1.2
			prismatic["damage_ratio"] = float(prismatic.get("damage_ratio", 0.0)) * 1.35
		"wraithstep":
			prismatic["mark_duration"] = float(prismatic.get("mark_duration", 0.0)) * 1.3
			prismatic["dash_mark_radius"] = float(prismatic.get("dash_mark_radius", 0.0)) * 1.2
			prismatic["bonus_damage"] = int(float(prismatic.get("bonus_damage", 0)) * 1.5)
			prismatic["splash_radius"] = float(prismatic.get("splash_radius", 0.0)) * 1.2
			prismatic["splash_ratio"] = float(prismatic.get("splash_ratio", 0.0)) * 1.25
		"voidfire":
			prismatic["heat_per_hit"] = float(prismatic.get("heat_per_hit", 0.0)) * 1.25
			prismatic["danger_zone_amp"] = float(prismatic.get("danger_zone_amp", 0.0)) * 1.5
			prismatic["detonate_ratio"] = float(prismatic.get("detonate_ratio", 0.0)) * 1.3
			prismatic["detonate_radius"] = float(prismatic.get("detonate_radius", 0.0)) * 1.2
			prismatic["lockout_duration"] = maxf(0.06, float(prismatic.get("lockout_duration", 0.0)) * 0.6)
		"dread_resonance":
			prismatic["bonus_per_stack"] = int(prismatic.get("bonus_per_stack", 0)) + 1
			prismatic["max_stacks"] = int(prismatic.get("max_stacks", 0)) + 3
		"bloodvow":
			prismatic["damage_mult"] = float(prismatic.get("damage_mult", 1.0)) * 1.2
			prismatic["low_hp_threshold"] = minf(0.75, float(prismatic.get("low_hp_threshold", 0.0)) + 0.15)
		"eclipse_mark":
			prismatic["radius"] = float(prismatic.get("radius", 0.0)) * 1.2
			prismatic["mark_duration"] = float(prismatic.get("mark_duration", 0.0)) * 1.3
			prismatic["bonus_ratio"] = float(prismatic.get("bonus_ratio", 0.0)) * 1.45
		"fracture_field":
			prismatic["radius"] = float(prismatic.get("radius", 0.0)) * 1.22
			prismatic["damage_ratio"] = float(prismatic.get("damage_ratio", 0.0)) * 1.35
			prismatic["slow_duration"] = float(prismatic.get("slow_duration", 0.0)) * 1.25
		"farline_volley":
			prismatic["arc_per_stack"] = float(prismatic.get("arc_per_stack", 0.0)) * 1.4
			prismatic["bonus_per_stack"] = int(prismatic.get("bonus_per_stack", 0)) + 1
			prismatic["stack_cap"] = int(prismatic.get("stack_cap", 0)) + 3
		"sigil_chain":
			prismatic["radius"] = float(prismatic.get("radius", 0.0)) * 1.2
			prismatic["damage_ratio"] = float(prismatic.get("damage_ratio", 0.0)) * 1.5
		_:
			pass
	return prismatic
