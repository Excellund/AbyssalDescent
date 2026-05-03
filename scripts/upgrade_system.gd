## Unified power application and stacking system
## Handles all upgrade and trial power effects + their scaling with stacks
## This is the most reusable system: can be called by player, test harness, console, etc.

extends Node

const DESCRIPTION_CAP_GUARD := preload("res://scripts/shared/description_cap_guard.gd")
const POWER_PARAMETER_MAPPER := preload("res://scripts/power_parameter_mapper.gd")

# Dependencies (injected)
var player_reference: Node = null
var game_state: Node = null  # GameStateManager instance
var power_registry: Node = null  # power_registry.gd instance
var upgrade_stacks: Dictionary = {}

# Track stacks for trial powers (upgrades don't track stacks for mechanics, but could)
var trial_power_stacks: Dictionary = {
	"razor_wind": 0,
	"execution_edge": 0,
	"rupture_wave": 0,
	"aegis_field": 0,
	"hunters_snare": 0,
	"phantom_step": 0,
	"reaper_step": 0,
	"static_wake": 0,
	"storm_crown": 0,
	"wraithstep": 0,
	"voidfire": 0,
	"dread_resonance": 0,
	"vow_shatter": 0,
	"eclipse_mark": 0,
	"fracture_field": 0
}

const UPGRADE_IDS := {
	"first_strike": true,
	"heavy_blow": true,
	"wide_arc": true,
	"long_reach": true,
	"fleet_foot": true,
	"blink_dash": true,
	"iron_skin": true,
	"battle_trance": true,
	"surge_step": true,
	"heartstone": true,
	"crushed_vow": true,
	"severing_edge": true,
	"apex_predator": true,
	"void_echo": true,
	"apex_momentum": true,
	"convergence_surge": true,
	"indomitable_spirit": true
}

const TRIAL_POWER_IDS := {
	"razor_wind": true,
	"execution_edge": true,
	"rupture_wave": true,
	"aegis_field": true,
	"hunters_snare": true,
	"phantom_step": true,
	"reaper_step": true,
	"static_wake": true,
	"storm_crown": true,
	"wraithstep": true,
	"voidfire": true,
	"dread_resonance": true,
	"vow_shatter": true,
	"eclipse_mark": true,
	"fracture_field": true
}


func _ready() -> void:
	# Register as singleton or get injected
	pass


## Apply an upgrade (stat boost) to the player
func apply_upgrade(upgrade_id: String) -> bool:
	var id := upgrade_id.strip_edges().to_lower()
	if not is_instance_valid(player_reference):
		return false
	
	if not _is_upgrade_id(id):
		return false
	
	var current_stacks := get_upgrade_stack_count(id)
	var stack_limit := _get_power_stack_limit(id)
	if stack_limit > 0 and current_stacks >= stack_limit:
		return false

	var preview := _build_upgrade_preview(id)
	if preview.is_empty():
		return false

	# Track after verifying this upgrade can apply.
	if is_instance_valid(game_state):
		game_state.add_upgrade(id)
	upgrade_stacks[id] = current_stacks + 1

	match id:
		"first_strike", "heavy_blow", "wide_arc", "long_reach", "fleet_foot", "blink_dash", "battle_trance", "surge_step", "apex_predator", "void_echo", "apex_momentum", "convergence_surge", "indomitable_spirit":
			player_reference.set(String(preview.get("property", "")), preview.get("next", player_reference.get(String(preview.get("property", "")))))
		"heartstone":
			var next_max := int(preview.get("next", player_reference.get_max_health()))
			var current_max: int = int(player_reference.get_max_health())
			var max_gain := maxi(0, next_max - current_max)
			var next_current: int = int(player_reference.get_current_health()) + max_gain
			player_reference.set_max_health_and_current(next_max, next_current)
		"iron_skin":
			player_reference.set("iron_skin_armor", int(preview.get("next", int(player_reference.get("iron_skin_armor")))))
			player_reference.set("iron_skin_stacks", int(player_reference.get("iron_skin_stacks")) + 1)
		"crushed_vow":
			player_reference.set("crushed_vow_bonus_damage", int(preview.get("next", int(player_reference.get("crushed_vow_bonus_damage")))))
		"severing_edge":
			player_reference.set("severing_edge_bonus_damage", int(preview.get("next", int(player_reference.get("severing_edge_bonus_damage")))))
		_:
			return false
	return true


## Apply a trial power (combat ability) to the player
func apply_trial_power(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	if not is_instance_valid(player_reference):
		return false
	
	if not _is_trial_power_id(id):
		return false
	
	# Track in game state
	if is_instance_valid(game_state):
		game_state.add_trial_power(id)
	
	# Update local stack
	if trial_power_stacks.has(id):
		trial_power_stacks[id] += 1

	var next_stack := get_trial_power_stack_count(id) + 1
	var next_values := _build_trial_values(id, next_stack)
	if next_values.is_empty():
		return false
	
	# Use data-driven mapper to apply all parameter values to player
	return POWER_PARAMETER_MAPPER.apply_trial_power_values(player_reference, id, next_stack, next_values)


## Apply any power (upgrade or trial power)
func apply_power(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	
	if _is_upgrade_id(id):
		return apply_upgrade(id)
	elif _is_trial_power_id(id):
		return apply_trial_power(id)
	
	return false


## Apply multiple powers at once
func apply_powers(power_ids: Array[String]) -> Dictionary:
	var applied: Array[String] = []
	var unknown: Array[String] = []
	
	for power_id in power_ids:
		var id := power_id.strip_edges().to_lower()
		if id.is_empty():
			continue
		
		if apply_power(id):
			applied.append(id)
		else:
			unknown.append(id)
	
	return {
		"applied": applied,
		"unknown": unknown,
		"total_applied": applied.size()
	}


## Get current stack count for a trial power
func get_trial_power_stack_count(power_id: String) -> int:
	var id := power_id.strip_edges().to_lower()
	if is_instance_valid(player_reference):
		match id:
			"razor_wind":
				return int(player_reference.get("razor_wind_stacks"))
			"execution_edge":
				return int(player_reference.get("execution_edge_stacks"))
			"rupture_wave":
				return int(player_reference.get("rupture_wave_stacks"))
			"aegis_field":
				return int(player_reference.get("aegis_field_stacks"))
			"hunters_snare":
				return int(player_reference.get("hunters_snare_stacks"))
			"phantom_step":
				return int(player_reference.get("phantom_step_stacks"))
			"reaper_step":
				return int(player_reference.get("void_dash_stacks"))
			"static_wake":
				return int(player_reference.get("static_wake_stacks"))
			"storm_crown":
				return int(player_reference.get("storm_crown_stacks"))
			"wraithstep":
				return int(player_reference.get("wraithstep_stacks"))
			"voidfire":
				return int(player_reference.get("voidfire_stacks"))
			"dread_resonance":
				return int(player_reference.get("dread_resonance_stacks"))
			"vow_shatter":
				return int(player_reference.get("vow_shatter_stacks"))
			"eclipse_mark":
				return int(player_reference.get("eclipse_mark_stacks"))
			"fracture_field":
				return int(player_reference.get("fracture_field_stacks"))
	if trial_power_stacks.has(id):
		return trial_power_stacks[id]
	return 0


func get_trial_runtime_values(power_id: String) -> Dictionary:
	var id := power_id.strip_edges().to_lower()
	if id.is_empty():
		return {}
	var stack_count := get_trial_power_stack_count(id)
	return _build_trial_values(id, stack_count)


func _get_power_balance_data(power_id: String) -> Dictionary:
	if power_registry != null:
		return power_registry.get_power_balance(power_id) as Dictionary
	return {}


func get_power_damage_model(power_id: String) -> Dictionary:
	if power_registry != null and power_registry.has_method("get_damage_model"):
		return power_registry.get_damage_model(power_id)
	return {
		"kind": "none",
		"scale_source": "none",
		"formula_note": "No direct damage"
	}


func _damage_kind_prefix(_power_id: String) -> String:
	return ""


func _variant_to_number(value: Variant, fallback: float = 0.0) -> float:
	if value is float:
		return value
	if value is int:
		return value
	if value is String:
		var text := String(value).strip_edges()
		if text.is_empty():
			return fallback
		return text.to_float()
	return fallback


func _build_upgrade_preview(upgrade_id: String) -> Dictionary:
	if not is_instance_valid(player_reference):
		return {}
	var data := _get_power_balance_data(upgrade_id)
	if data.is_empty():
		return {}
	var property_name := String(data.get("property", ""))
	if property_name.is_empty():
		return {}

	var current_value: Variant = player_reference.get(property_name)
	var current_number := _variant_to_number(current_value)
	var next_value: Variant = current_value
	match String(data.get("kind", "")):
		"mul_min":
			next_value = maxf(_variant_to_number(data.get("min", 0.0)), current_number * _variant_to_number(data.get("mult", 1.0), 1.0))
		"add_int":
			next_value = floori(current_number) + floori(_variant_to_number(data.get("add", 0.0)))
		"add_float":
			next_value = current_number + _variant_to_number(data.get("add", 0.0))
		"add_clamp":
			next_value = clampf(
				current_number + _variant_to_number(data.get("add", 0.0)),
				_variant_to_number(data.get("min", -INF), -INF),
				_variant_to_number(data.get("max", INF), INF)
			)
		_:
			return {}

	return {
		"property": property_name,
		"current": current_value,
		"next": next_value,
		"data": data
	}


func _build_trial_values(power_id: String, stack_count: int) -> Dictionary:
	if not is_instance_valid(player_reference):
		return {}
	var data := _get_power_balance_data(power_id)
	if data.is_empty():
		return {}

	match power_id:
		"razor_wind":
			# Damage scales as ratio of damage. Heavy Blow (+8 DMG) directly increases this output.
			return {
				"range_scale": float(data.get("range_base", 0.0)) + float(data.get("range_per_stack", 0.0)) * float(stack_count),
				"damage_ratio": float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count),
				"attack_cooldown": maxf(float(data.get("attack_cooldown_min", 0.0)), float(player_reference.get("attack_cooldown")) * float(data.get("attack_cooldown_mult", 1.0)))
			}
		"execution_edge":
			# Damage multiplier applies to the current melee damage. Heavy Blow boosts this indirectly.
			return {
				"every": maxi(int(data.get("every_floor", 1)), int(data.get("every_base", 1)) - stack_count),
				"damage_mult": float(data.get("damage_mult_base", 0.0)) + float(data.get("damage_mult_per_stack", 0.0)) * float(stack_count),
				"attack_lock_duration": maxf(float(data.get("attack_lock_min", 0.0)), float(player_reference.get("attack_lock_duration")) * float(data.get("attack_lock_mult", 1.0)))
			}
		"rupture_wave":
			# Damage scales as ratio of damage. Heavy Blow (+8 DMG) increases the shockwave output.
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
			# Damage scales as ratio of damage. Heavy Blow (+8 DMG) directly increases this output.
			# Objective mutators (Hunter's Focus, Fortified, Combo Relay) also apply to this damage.
			var damage_ratio := float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count)
			return {
				"damage": int(ceil(float(player_reference.get("damage")) * damage_ratio)),
				"slow_duration": float(data.get("slow_duration_base", 0.0)) + float(data.get("slow_duration_per_stack", 0.0)) * float(stack_count),
				"dash_cooldown": maxf(float(data.get("dash_cooldown_min", 0.0)), float(player_reference.get("dash_cooldown")) * float(data.get("dash_cooldown_mult", 1.0)))
			}
		"reaper_step":
			return {
				"range_mult": float(data.get("range_mult_base", 0.0)) + float(data.get("range_mult_per_stack", 0.0)) * float(stack_count)
			}
		"static_wake":
			# Damage scales as ratio of damage. Heavy Blow (+8 DMG) directly increases this output.
			# Objective mutators (Hunter's Focus, Fortified, Combo Relay) also apply to this damage.
			var damage_ratio := float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count)
			return {
				"damage": int(ceil(float(player_reference.get("damage")) * damage_ratio)),
				"lifetime": float(data.get("lifetime_base", 0.0)) + float(data.get("lifetime_per_stack", 0.0)) * float(stack_count)
			}
		"storm_crown":
			# Damage scales as ratio of damage. Heavy Blow (+8 DMG) increases chain damage output.
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
		"dread_resonance":
			return {
				"bonus_per_stack": int(data.get("bonus_per_resonance_base", 0)) + stack_count * int(data.get("bonus_per_resonance_per_stack", 0))
			}
		"vow_shatter":
			return {
				"damage_mult": float(data.get("damage_mult_base", 1.0)) + float(data.get("damage_mult_per_stack", 0.0)) * float(stack_count)
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
		_:
			return {}


## Get trial power description with next stack info from the current player state.
func get_trial_power_card_description(power_id: String) -> String:
	if not is_instance_valid(player_reference):
		return "[color=#9ab8d8]Enhances this power.[/color]"
	var id := power_id.strip_edges().to_lower()
	var current_stack := get_trial_power_stack_count(id)
	var next_stack := current_stack + 1
	var next_values := _build_trial_values(id, next_stack)
	match id:
		"razor_wind":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_range_scale := float(next_values.get("range_scale", 1.0))
			var next_damage_ratio := float(next_values.get("damage_ratio", 0.0))
			var cur_range_scale := float(player_reference.get("razor_wind_range_scale"))
			var cur_damage_ratio := float(player_reference.get("razor_wind_damage_ratio"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Each swing fires a slicing projectile that travels through enemies at range.[/color]\n[color=#9ab8d8]Initial:[/color] range [color=#7de882]x%.2f[/color], damage [color=#7de882]%.0f%%[/color] of hit." % [next_range_scale, next_damage_ratio * 100.0]
			var razor_prefix := _damage_kind_prefix("razor_wind")
			return "%s[color=#c8daf0]Wind Slash:[/color] range [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color], damage [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color] of hit." % [razor_prefix, cur_range_scale, next_range_scale, cur_damage_ratio * 100.0, next_damage_ratio * 100.0]
		"execution_edge":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_every := int(next_values.get("every", 2))
			var next_mult := float(next_values.get("damage_mult", 1.0))
			var cur_every := int(player_reference.get("execution_every"))
			var cur_mult := float(player_reference.get("execution_damage_mult"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Every few swings builds to a devastating strike that deals massive extra damage.[/color]\n[color=#9ab8d8]Initial:[/color] every [color=#7de882]%d[/color] swings for [color=#7de882]x%.2f[/color] damage." % [next_every, next_mult]
			var execution_prefix := _damage_kind_prefix("execution_edge")
			return "%s[color=#c8daf0]Execution:[/color] every [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color] swings, damage [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color] on hit." % [execution_prefix, cur_every, next_every, cur_mult, next_mult]
		"rupture_wave":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_radius := float(next_values.get("radius", 0.0))
			var next_ratio := float(next_values.get("damage_ratio", 0.0))
			var cur_radius := float(player_reference.get("rupture_wave_radius"))
			var cur_ratio := float(player_reference.get("rupture_wave_damage_ratio"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Your hits send a shockwave rippling outward, damaging all nearby enemies.[/color]\n[color=#9ab8d8]Initial:[/color] radius [color=#7de882]%.0f[/color], damage [color=#7de882]%.0f%%[/color] of hit." % [next_radius, next_ratio * 100.0]
			return "[color=#c8daf0]Rupture:[/color] radius [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color], damage [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color]." % [cur_radius, next_radius, cur_ratio * 100.0, next_ratio * 100.0]
		"aegis_field":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_resist := float(next_values.get("resist", 0.0))
			var next_duration := float(next_values.get("duration", 0.0))
			var next_radius := float(next_values.get("radius", 0.0))
			var next_cooldown := float(next_values.get("cooldown", 0.0))
			var cur_resist := float(player_reference.get("aegis_field_resist_ratio"))
			var cur_duration := float(player_reference.get("aegis_field_resist_duration"))
			var cur_radius := float(player_reference.get("aegis_field_pulse_radius"))
			var cur_cooldown := float(player_reference.get("aegis_field_cooldown"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Taking damage triggers a guard pulse that slows nearby enemies and grants brief damage resistance.[/color]\n[color=#9ab8d8]Initial:[/color] resist [color=#7de882]%.0f%%[/color] for [color=#7de882]%.2fs[/color], pulse radius [color=#7de882]%.0f[/color], cooldown [color=#7de882]%.2fs[/color]." % [next_resist * 100.0, next_duration, next_radius, next_cooldown]
			return "[color=#c8daf0]Aegis Field:[/color] resist [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color], guard [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], pulse radius [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color], cooldown [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [cur_resist * 100.0, next_resist * 100.0, cur_duration, next_duration, cur_radius, next_radius, cur_cooldown, next_cooldown]
		"hunters_snare":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_bonus := int(next_values.get("bonus_damage", 0))
			var next_duration := float(next_values.get("slow_duration", 0.0))
			var next_slow_mult := float(next_values.get("slow_mult", 1.0))
			var cur_bonus := int(player_reference.get("hunters_snare_bonus_damage"))
			var cur_duration := float(player_reference.get("hunters_snare_slow_duration"))
			var cur_slow_mult := float(player_reference.get("hunters_snare_slow_mult"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Hits slow enemies, and striking slowed targets deals extra hit damage.[/color]\n[color=#9ab8d8]Initial:[/color] slow [color=#7de882]%.2fs[/color] at [color=#7de882]%.0f%%[/color] speed, extra hit damage [color=#7de882]+%d[/color]." % [next_duration, next_slow_mult * 100.0, next_bonus]
			var snare_prefix := _damage_kind_prefix("hunters_snare")
			return "%s[color=#c8daf0]Hunter's Snare:[/color] slow [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], speed [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color], extra hit damage [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]." % [snare_prefix, cur_duration, next_duration, cur_slow_mult * 100.0, next_slow_mult * 100.0, cur_bonus, next_bonus]
		"phantom_step":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var phantom_prefix := _damage_kind_prefix("phantom_step")
			var next_damage := int(next_values.get("damage", 0))
			var next_slow := float(next_values.get("slow_duration", 0.0))
			var cur_damage := int(player_reference.get("phantom_step_damage"))
			var cur_slow := float(player_reference.get("phantom_step_slow_duration"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Dashing through enemies deals damage and leaves them slowed in your wake.[/color]\n[color=#9ab8d8]Initial:[/color] damage [color=#7de882]%d[/color], slow [color=#7de882]%.2fs[/color]." % [next_damage, next_slow]
			return "%s[color=#c8daf0]Phantom Step:[/color] damage [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], slow [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [phantom_prefix, cur_damage, next_damage, cur_slow, next_slow]
		"reaper_step":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_range := float(next_values.get("range_mult", 1.0))
			var cur_range := float(player_reference.get("void_dash_range_mult"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Kills fully refresh your dash. Each stack scales dash range and dash speed together.[/color]\n[color=#9ab8d8]Initial:[/color] range/speed [color=#7de882]x%.2f[/color], kill refresh [color=#7de882]full[/color]." % [next_range]
			return "[color=#c8daf0]Reaper Step:[/color] range/speed [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color], kill refresh [color=#7de882]full[/color]." % [cur_range, next_range]
		"static_wake":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var wake_prefix := _damage_kind_prefix("static_wake")
			var next_damage := int(next_values.get("damage", 0))
			var next_lifetime := float(next_values.get("lifetime", 0.0))
			var cur_damage := int(player_reference.get("static_wake_damage"))
			var cur_lifetime := float(player_reference.get("static_wake_lifetime"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Leaves an electrified trail as you move that shocks any enemy who steps into it.[/color]\n[color=#9ab8d8]Initial:[/color] damage per pulse [color=#7de882]%d[/color], lasts [color=#7de882]%.2fs[/color]." % [next_damage, next_lifetime]
			return "%s[color=#c8daf0]Static Wake:[/color] damage per pulse [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], trail [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [wake_prefix, cur_damage, next_damage, cur_lifetime, next_lifetime]
		"storm_crown":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_every := int(next_values.get("proc_every", 1))
			var next_targets := int(next_values.get("chain_targets", 1))
			var next_radius := float(next_values.get("chain_radius", 0.0))
			var next_ratio := float(next_values.get("damage_ratio", 0.0))
			var cur_every := int(player_reference.get("storm_crown_proc_every"))
			var cur_targets := int(player_reference.get("storm_crown_chain_targets"))
			var cur_radius := float(player_reference.get("storm_crown_chain_radius"))
			var cur_ratio := float(player_reference.get("storm_crown_damage_ratio"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Every few hits discharge chain lightning from your target to nearby foes.[/color]\n[color=#9ab8d8]Initial:[/color] every [color=#7de882]%d[/color] hits, chains to [color=#7de882]%d[/color] targets within [color=#7de882]%.0f[/color], for [color=#7de882]%.0f%%[/color] damage." % [next_every, next_targets, next_radius, next_ratio * 100.0]
			return "[color=#c8daf0]Storm Crown:[/color] proc [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], chains [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], radius [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color], damage [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color]." % [cur_every, next_every, cur_targets, next_targets, cur_radius, next_radius, cur_ratio * 100.0, next_ratio * 100.0]
		"wraithstep":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_mark_duration := float(next_values.get("mark_duration", 0.0))
			var next_bonus_damage := int(next_values.get("bonus_damage", 0))
			var next_splash_ratio := float(next_values.get("splash_ratio", 0.0))
			var cur_mark_duration := float(player_reference.get("wraithstep_mark_duration"))
			var cur_bonus_damage := int(player_reference.get("wraithstep_mark_bonus_damage"))
			var cur_splash_ratio := float(player_reference.get("wraithstep_mark_splash_ratio"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Dash marks enemies. Marked hits deal extra hit damage and chain splashes nearby.[/color]\n[color=#9ab8d8]Initial:[/color] mark [color=#7de882]%.2fs[/color], marked-hit damage [color=#7de882]+%d[/color], cleave [color=#7de882]%.0f%%[/color]." % [next_mark_duration, next_bonus_damage, next_splash_ratio * 100.0]
			var wraith_prefix := _damage_kind_prefix("wraithstep")
			return "%s[color=#c8daf0]Wraithstep:[/color] mark [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], marked-hit damage [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color], cleave [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color] of hit." % [wraith_prefix, cur_mark_duration, next_mark_duration, cur_bonus_damage, next_bonus_damage, cur_splash_ratio * 100.0, next_splash_ratio * 100.0]
		"voidfire":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_amp := float(next_values.get("danger_zone_amp", 0.0))
			var next_det_ratio := float(next_values.get("detonate_ratio", 0.0))
			var next_lockout := float(next_values.get("lockout_duration", 0.0))
			var cur_amp := float(player_reference.get("voidfire_danger_zone_amp"))
			var cur_det_ratio := float(player_reference.get("voidfire_detonate_ratio"))
			var cur_lockout := float(player_reference.get("voidfire_lockout_duration"))
			if current_stack <= 0:
				var voidfire_initial := "[color=#9ab8d8]Heat attacks. Danger Zone boosts hit damage.[/color]\n[color=#9ab8d8]Initial:[/color] damage [color=#7de882]+%.0f%%[/color], detonate [color=#7de882]%.0f%%[/color], lockout [color=#7de882]%.2fs[/color]." % [next_amp * 100.0, next_det_ratio * 100.0, next_lockout]
				return DESCRIPTION_CAP_GUARD.assert_visible_cap(voidfire_initial, "voidfire", "reward_card")
			var voidfire_stack_desc := "[color=#c8daf0]Voidfire:[/color] damage [color=#e8c96a]+%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]+%.0f%%[/color], detonate [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color], lockout [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [cur_amp * 100.0, next_amp * 100.0, cur_det_ratio * 100.0, next_det_ratio * 100.0, cur_lockout, next_lockout]
			return DESCRIPTION_CAP_GUARD.assert_visible_cap(voidfire_stack_desc, "voidfire", "reward_card")
		"dread_resonance":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_bonus := int(next_values.get("bonus_per_stack", 0))
			var cur_bonus_dr := int(player_reference.get("dread_resonance_bonus_per_stack"))
			var max_stacks_dr := int(player_reference.get("dread_resonance_max_stacks"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Chain hits on one enemy build resonance to [color=#e8c96a]%d[/color] stacks. Swapping targets resets to 1.[/color]\n[color=#9ab8d8]Initial:[/color] bonus per resonance stack [color=#7de882]+%d[/color]." % [max_stacks_dr, next_bonus]
			return "[color=#c8daf0]Dread Resonance:[/color] bonus per resonance stack [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color] (cap [color=#e8c96a]%d[/color])." % [cur_bonus_dr, next_bonus, max_stacks_dr]
		"vow_shatter":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_mult_vs := float(next_values.get("damage_mult", 1.0))
			var cur_mult_vs := float(player_reference.get("vow_shatter_damage_mult"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Taking a hit primes a vow. Your next attack multiplies damage and consumes the vow.[/color]\n[color=#9ab8d8]Initial:[/color] primed hit damage [color=#7de882]x%.2f[/color]." % [next_mult_vs]
			return "[color=#c8daf0]Vow Shatter:[/color] primed hit damage [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color]." % [cur_mult_vs, next_mult_vs]
		"eclipse_mark":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_radius_em := float(next_values.get("radius", 0.0))
			var next_dur_em := float(next_values.get("mark_duration", 0.0))
			var next_ratio_em := float(next_values.get("bonus_ratio", 0.0))
			var cur_radius_em := float(player_reference.get("eclipse_mark_radius"))
			var cur_dur_em := float(player_reference.get("eclipse_mark_duration"))
			var cur_ratio_em := float(player_reference.get("eclipse_mark_bonus_ratio"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Kills mark all nearby enemies. First hit on each marked enemy deals amplified damage. Marks expire quickly.[/color]\n[color=#9ab8d8]Initial:[/color] mark radius [color=#7de882]%.0f[/color], mark duration [color=#7de882]%.2fs[/color], bonus [color=#7de882]%.0f%%[/color] of hit." % [next_radius_em, next_dur_em, next_ratio_em * 100.0]
			return "[color=#c8daf0]Eclipse Mark:[/color] radius [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color], duration [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], bonus [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color] of hit." % [cur_radius_em, next_radius_em, cur_dur_em, next_dur_em, cur_ratio_em * 100.0, next_ratio_em * 100.0]
		"fracture_field":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_radius_ff := float(next_values.get("radius", 0.0))
			var next_ratio_ff := float(next_values.get("damage_ratio", 0.0))
			var next_slow_ff := float(next_values.get("slow_duration", 0.0))
			var cur_radius_ff := float(player_reference.get("fracture_field_radius"))
			var cur_ratio_ff := float(player_reference.get("fracture_field_damage_ratio"))
			var cur_slow_ff := float(player_reference.get("fracture_field_slow_duration"))
			if current_stack <= 0:
				var fracture_initial := "[color=#9ab8d8]Kill ruptures fault lines from the slain enemy.[/color]\n[color=#9ab8d8]Initial:[/color] length [color=#7de882]%.0f[/color], damage [color=#7de882]%.0f%%[/color], slow [color=#7de882]%.2fs[/color]." % [next_radius_ff, next_ratio_ff * 100.0, next_slow_ff]
				return DESCRIPTION_CAP_GUARD.assert_visible_cap(fracture_initial, "fracture_field", "reward_card")
			var fracture_stack_desc := "[color=#c8daf0]Fracture:[/color] length [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color], damage [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color], slow [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [cur_radius_ff, next_radius_ff, cur_ratio_ff * 100.0, next_ratio_ff * 100.0, cur_slow_ff, next_slow_ff]
			return DESCRIPTION_CAP_GUARD.assert_visible_cap(fracture_stack_desc, "fracture_field", "reward_card")
		_:
			return "[color=#9ab8d8]Enhances this power.[/color]"


func get_upgrade_card_description(upgrade_id: String) -> String:
	if not is_instance_valid(player_reference):
		return "[color=#c8daf0]Upgrade your stats.[/color]"
	var id := upgrade_id.strip_edges().to_lower()
	var preview := _build_upgrade_preview(id)
	if preview.is_empty():
		return "[color=#c8daf0]Upgrade your stats.[/color]"
	var cur_val: Variant = preview.get("current")
	var next_val: Variant = preview.get("next")
	match id:
		"first_strike":
			var cur_bonus := int(cur_val)
			var next_bonus := int(next_val)
			var first_strike_prefix := _damage_kind_prefix("first_strike")
			return "%s[color=#c8daf0]Extra hit damage vs enemies above 80%% HP:[/color] [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]" % [first_strike_prefix, cur_bonus, next_bonus]
		"heavy_blow":
			var heavy_blow_prefix := _damage_kind_prefix("heavy_blow")
			return "%s[color=#c8daf0]Damage:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [heavy_blow_prefix, int(cur_val), int(next_val)]
		"wide_arc":
			var cur_arc := float(cur_val)
			var next_arc := float(next_val)
			return "[color=#c8daf0]Attack arc:[/color] [color=#e8c96a]%.0f°[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f°[/color]" % [cur_arc, next_arc]
		"long_reach":
			return "[color=#c8daf0]Attack range:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [float(cur_val), float(next_val)]
		"fleet_foot":
			return "[color=#c8daf0]Move speed:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [float(cur_val), float(next_val)]
		"blink_dash":
			var cur_dash_cd := float(cur_val)
			var next_dash_cd := float(next_val)
			return "[color=#c8daf0]Dash cooldown:[/color] [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]" % [cur_dash_cd, next_dash_cd]
		"iron_skin":
			return "[color=#c8daf0]Armor:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [int(cur_val), int(next_val)]
		"battle_trance":
			var cur_speed_bonus := float(cur_val) * 100.0
			var next_speed_bonus := float(next_val) * 100.0
			var trance_duration := 1.25
			if player_reference.get("battle_trance_duration") != null:
				trance_duration = float(player_reference.get("battle_trance_duration"))
			return "[color=#c8daf0]On hit:[/color] gain [color=#e8c96a]+%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]+%.0f%%[/color] move speed for [color=#7de882]%.2fs[/color]." % [cur_speed_bonus, next_speed_bonus, trance_duration]
		"surge_step":
			return "[color=#c8daf0]Dash speed:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [float(cur_val), float(next_val)]
		"heartstone":
			var cur_max := int(cur_val)
			var next_max := int(next_val)
			return "[color=#c8daf0]Max HP:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [cur_max, next_max]
		"crushed_vow":
			return "[color=#c8daf0]After being hit, next attack bonus damage:[/color] [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]" % [int(cur_val), int(next_val)]
		"severing_edge":
			return "[color=#c8daf0]Bonus damage on hits against enemies below 55%% HP:[/color] [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]" % [int(cur_val), int(next_val)]
		"apex_predator":
			return "[color=#c8daf0]Warden's Verdict:[/color] every hit builds predator cadence; every 4th hit triggers a burst at impact and mauls nearby enemies. Predator power [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]." % [int(cur_val), int(next_val)]
		"void_echo":
			var cur_void_echo := int(cur_val)
			var next_void_echo := int(next_val)
			var cur_echo_radius := clampf(96.0 + float(cur_void_echo) * 1.05, 96.0, 260.0)
			var next_echo_radius := clampf(96.0 + float(next_void_echo) * 1.05, 96.0, 260.0)
			return "[color=#c8daf0]Lacuna Echo:[/color] kills create lingering void zones that pulse damage and empower hits inside them. Zone power [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], radius [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]." % [cur_void_echo, next_void_echo, cur_echo_radius, next_echo_radius]
		"apex_momentum":
			var cur_momentum := float(cur_val) * 100.0
			var next_momentum := float(next_val) * 100.0
			return "[color=#c8daf0]Sovereign Tempo:[/color] hits build tempo stacks; finishing a dash releases a momentum wave. Hitting enemies refunds dash cooldown based on stacks. Tempo per stack [color=#e8c96a]+%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]+%.0f%%[/color]." % [cur_momentum, next_momentum]
		"convergence_surge":
			var cur_ratio := float(cur_val)
			var next_ratio := float(next_val)
			var cur_hits_needed := maxi(2, 6 - int(round(cur_ratio * 8.0)))
			var next_hits_needed := maxi(2, 6 - int(round(next_ratio * 8.0)))
			var cur_window := 1.2 + cur_ratio * 1.8
			var next_window := 1.2 + next_ratio * 1.8
			var cur_pulse_every := maxf(0.14, 0.3 - cur_ratio * 0.25)
			var next_pulse_every := maxf(0.14, 0.3 - next_ratio * 0.25)
			return "[color=#c8daf0]Pillar Convergence:[/color] every [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color] damaging hits, you enter Convergence for [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], pulsing every [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [cur_hits_needed, next_hits_needed, cur_window, next_window, cur_pulse_every, next_pulse_every]
		"indomitable_spirit":
			var cur_resist := float(cur_val) * 100.0
			var next_resist := float(next_val) * 100.0
			var cur_base_ratio := 45.0 + cur_resist
			var next_base_ratio := 45.0 + next_resist
			return "[color=#c8daf0]Unbroken Oath:[/color] DR [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color]. Taking damage banks Oath; damaging hits consume all bank for bonus = [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color] of damage stat + [color=#e8c96a]1%% per banked damage[/color]." % [cur_resist, next_resist, cur_base_ratio, next_base_ratio]
		_:
			return "[color=#c8daf0]Upgrade your stats.[/color]"


## Get all power IDs the player currently has
func get_player_powers() -> Dictionary:
	if is_instance_valid(game_state):
		return {
			"upgrades": game_state.upgrades_taken.duplicate(),
			"trial_powers": game_state.trial_powers_taken.duplicate()
		}
	return {
		"upgrades": [],
		"trial_powers": []
	}


## Build the final melee attack context after all applicable power rules are considered.
func build_melee_attack_context(base_damage: int, base_attack_range: float, base_attack_arc_degrees: float, execution_proc: bool, execution_damage_mult: float) -> Dictionary:
	var damage_mult := execution_damage_mult if execution_proc else 1.0
	return {
		"damage": maxi(1, int(round(float(base_damage) * damage_mult))),
		"range": base_attack_range,
		"arc_degrees": base_attack_arc_degrees,
		"damage_mult": damage_mult,
		"execution_proc": execution_proc
	}


## Build the final Razor Wind attack context from the already-resolved melee context.
func build_razor_wind_attack_context(melee_context: Dictionary, razor_wind_damage_ratio: float, razor_wind_range_scale: float, razor_wind_arc_degrees: float, fallback_damage: int, fallback_attack_range: float) -> Dictionary:
	var melee_damage := int(melee_context.get("damage", fallback_damage))
	return {
		"damage": maxi(1, int(round(float(melee_damage) * razor_wind_damage_ratio))),
		"range": float(melee_context.get("range", fallback_attack_range)) * razor_wind_range_scale,
		"arc_degrees": razor_wind_arc_degrees,
		"source_damage": melee_damage,
		"execution_proc": bool(melee_context.get("execution_proc", false))
	}


## Reset for new run
func reset() -> void:
	upgrade_stacks.clear()
	for key in trial_power_stacks.keys():
		trial_power_stacks[key] = 0
	
	if is_instance_valid(game_state):
		game_state.reset()


## Initialize with dependencies
func initialize(player: Node, state: Node, registry: Node) -> void:
	player_reference = player
	game_state = state
	power_registry = registry


func get_upgrade_stack_count(upgrade_id: String) -> int:
	var id := upgrade_id.strip_edges().to_lower()
	if is_instance_valid(game_state):
		return int(game_state.get_upgrade_stack_count(id))
	return int(upgrade_stacks.get(id, 0))


func _get_power_stack_limit(power_id: String) -> int:
	if power_registry != null:
		return int(power_registry.get_power_stack_limit(power_id))
	return 0

func _is_upgrade_id(power_id: String) -> bool:
	if power_registry != null:
		return bool(power_registry.is_upgrade(power_id))
	return UPGRADE_IDS.has(power_id)

func _is_trial_power_id(power_id: String) -> bool:
	if power_registry != null:
		return bool(power_registry.is_trial_power(power_id))
	return TRIAL_POWER_IDS.has(power_id)
