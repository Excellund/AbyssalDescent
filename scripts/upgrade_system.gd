## Unified power application and stacking system
## Handles all upgrade and trial power effects + their scaling with stacks
## This is the most reusable system: can be called by player, test harness, console, etc.

extends Node

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
	"wraithstep": 0
}

const UPGRADE_IDS := {
	"swift_strike": true,
	"heavy_blow": true,
	"wide_arc": true,
	"long_reach": true,
	"fleet_foot": true,
	"blink_dash": true,
	"iron_skin": true,
	"battle_trance": true,
	"surge_step": true,
	"kinetic_drive": true
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
	"wraithstep": true
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
		"swift_strike", "heavy_blow", "wide_arc", "long_reach", "fleet_foot", "blink_dash", "battle_trance", "surge_step", "kinetic_drive":
			player_reference.set(String(preview.get("property", "")), preview.get("next", player_reference.get(String(preview.get("property", "")))))
		"iron_skin":
			player_reference.set("iron_skin_armor", int(preview.get("next", int(player_reference.get("iron_skin_armor")))))
			player_reference.set("iron_skin_stacks", int(player_reference.get("iron_skin_stacks")) + 1)
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
	
	match id:
		"razor_wind":
			player_reference.set("reward_razor_wind", true)
			player_reference.set("razor_wind_stacks", next_stack)
			player_reference.set("razor_wind_range_scale", float(next_values.get("range_scale", player_reference.get("razor_wind_range_scale"))))
			player_reference.set("razor_wind_damage_ratio", float(next_values.get("damage_ratio", player_reference.get("razor_wind_damage_ratio"))))
			player_reference.set("attack_cooldown", float(next_values.get("attack_cooldown", player_reference.get("attack_cooldown"))))
		"execution_edge":
			player_reference.set("reward_execution_edge", true)
			player_reference.set("execution_edge_stacks", next_stack)
			player_reference.set("execution_every", int(next_values.get("every", player_reference.get("execution_every"))))
			player_reference.set("execution_damage_mult", float(next_values.get("damage_mult", player_reference.get("execution_damage_mult"))))
			player_reference.set("attack_lock_duration", float(next_values.get("attack_lock_duration", player_reference.get("attack_lock_duration"))))
		"rupture_wave":
			player_reference.set("reward_rupture_wave", true)
			player_reference.set("rupture_wave_stacks", next_stack)
			player_reference.set("rupture_wave_radius", float(next_values.get("radius", player_reference.get("rupture_wave_radius"))))
			player_reference.set("rupture_wave_damage_ratio", float(next_values.get("damage_ratio", player_reference.get("rupture_wave_damage_ratio"))))
			player_reference.set("attack_damage", int(next_values.get("attack_damage", player_reference.get("attack_damage"))))
		"aegis_field":
			player_reference.set("reward_aegis_field", true)
			player_reference.set("aegis_field_stacks", next_stack)
			player_reference.set("aegis_field_resist_ratio", float(next_values.get("resist", player_reference.get("aegis_field_resist_ratio"))))
			player_reference.set("aegis_field_resist_duration", float(next_values.get("duration", player_reference.get("aegis_field_resist_duration"))))
			player_reference.set("aegis_field_pulse_radius", float(next_values.get("radius", player_reference.get("aegis_field_pulse_radius"))))
			player_reference.set("aegis_field_slow_duration", float(next_values.get("slow_duration", player_reference.get("aegis_field_slow_duration"))))
			player_reference.set("aegis_field_slow_mult", float(next_values.get("slow_mult", player_reference.get("aegis_field_slow_mult"))))
			player_reference.set("aegis_field_cooldown", float(next_values.get("cooldown", player_reference.get("aegis_field_cooldown"))))
		"hunters_snare":
			player_reference.set("reward_hunters_snare", true)
			player_reference.set("hunters_snare_stacks", next_stack)
			player_reference.set("hunters_snare_bonus_damage", int(next_values.get("bonus_damage", player_reference.get("hunters_snare_bonus_damage"))))
			player_reference.set("hunters_snare_slow_duration", float(next_values.get("slow_duration", player_reference.get("hunters_snare_slow_duration"))))
			player_reference.set("hunters_snare_slow_mult", float(next_values.get("slow_mult", player_reference.get("hunters_snare_slow_mult"))))
		"phantom_step":
			player_reference.set("reward_phantom_step", true)
			player_reference.set("phantom_step_stacks", next_stack)
			player_reference.set("phantom_step_damage", int(next_values.get("damage", player_reference.get("phantom_step_damage"))))
			player_reference.set("phantom_step_slow_duration", float(next_values.get("slow_duration", player_reference.get("phantom_step_slow_duration"))))
			player_reference.set("dash_cooldown", float(next_values.get("dash_cooldown", player_reference.get("dash_cooldown"))))
		"reaper_step":
			player_reference.set("reward_void_dash", true)
			player_reference.set("void_dash_stacks", next_stack)
			player_reference.set("void_dash_range_mult", float(next_values.get("range_mult", player_reference.get("void_dash_range_mult"))))
		"static_wake":
			player_reference.set("reward_static_wake", true)
			player_reference.set("static_wake_stacks", next_stack)
			player_reference.set("static_wake_damage", int(next_values.get("damage", player_reference.get("static_wake_damage"))))
			player_reference.set("static_wake_lifetime", float(next_values.get("lifetime", player_reference.get("static_wake_lifetime"))))
		"storm_crown":
			player_reference.set("reward_storm_crown", true)
			player_reference.set("storm_crown_stacks", next_stack)
			player_reference.set("storm_crown_proc_every", int(next_values.get("proc_every", player_reference.get("storm_crown_proc_every"))))
			player_reference.set("storm_crown_chain_targets", int(next_values.get("chain_targets", player_reference.get("storm_crown_chain_targets"))))
			player_reference.set("storm_crown_chain_radius", float(next_values.get("chain_radius", player_reference.get("storm_crown_chain_radius"))))
			player_reference.set("storm_crown_damage_ratio", float(next_values.get("damage_ratio", player_reference.get("storm_crown_damage_ratio"))))
		"wraithstep":
			player_reference.set("reward_wraithstep", true)
			player_reference.set("wraithstep_stacks", next_stack)
			player_reference.set("wraithstep_mark_duration", float(next_values.get("mark_duration", player_reference.get("wraithstep_mark_duration"))))
			player_reference.set("wraithstep_dash_mark_radius", float(next_values.get("dash_mark_radius", player_reference.get("wraithstep_dash_mark_radius"))))
			player_reference.set("wraithstep_mark_bonus_damage", int(next_values.get("bonus_damage", player_reference.get("wraithstep_mark_bonus_damage"))))
			player_reference.set("wraithstep_mark_splash_radius", float(next_values.get("splash_radius", player_reference.get("wraithstep_mark_splash_radius"))))
			player_reference.set("wraithstep_mark_splash_ratio", float(next_values.get("splash_ratio", player_reference.get("wraithstep_mark_splash_ratio"))))
		_:
			return false
	return true


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
	if trial_power_stacks.has(id):
		return trial_power_stacks[id]
	return 0


func _get_power_balance_data(power_id: String) -> Dictionary:
	if power_registry != null and power_registry.has_method("get_power_balance"):
		return power_registry.call("get_power_balance", power_id) as Dictionary
	return {}


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
	var next_value: Variant = current_value
	match String(data.get("kind", "")):
		"mul_min":
			next_value = maxf(float(data.get("min", 0.0)), float(current_value) * float(data.get("mult", 1.0)))
		"add_int":
			next_value = int(current_value) + int(data.get("add", 0))
		"add_float":
			next_value = float(current_value) + float(data.get("add", 0.0))
		"add_clamp":
			next_value = clampf(float(current_value) + float(data.get("add", 0.0)), float(data.get("min", -INF)), float(data.get("max", INF)))
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
				"damage_ratio": float(data.get("damage_ratio_base", 0.0)) + float(data.get("damage_ratio_per_stack", 0.0)) * float(stack_count),
				"attack_damage": int(player_reference.get("attack_damage")) + int(data.get("attack_damage_add", 0))
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
			return {
				"damage": int(data.get("damage_base", 0)) + stack_count * int(data.get("damage_per_stack", 0)),
				"slow_duration": float(data.get("slow_duration_base", 0.0)) + float(data.get("slow_duration_per_stack", 0.0)) * float(stack_count),
				"dash_cooldown": maxf(float(data.get("dash_cooldown_min", 0.0)), float(player_reference.get("dash_cooldown")) * float(data.get("dash_cooldown_mult", 1.0)))
			}
		"reaper_step":
			return {
				"range_mult": float(data.get("range_mult_base", 0.0)) + float(data.get("range_mult_per_stack", 0.0)) * float(stack_count)
			}
		"static_wake":
			return {
				"damage": int(data.get("damage_base", 0)) + stack_count * int(data.get("damage_per_stack", 0)),
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
			return "[color=#c8daf0]Wind Slash:[/color] range [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color], damage [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color]." % [cur_range_scale, next_range_scale, cur_damage_ratio * 100.0, next_damage_ratio * 100.0]
		"execution_edge":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_every := int(next_values.get("every", 2))
			var next_mult := float(next_values.get("damage_mult", 1.0))
			var cur_every := int(player_reference.get("execution_every"))
			var cur_mult := float(player_reference.get("execution_damage_mult"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Every few swings builds to a devastating strike that deals massive bonus damage.[/color]\n[color=#9ab8d8]Initial:[/color] every [color=#7de882]%d[/color] swings for [color=#7de882]x%.2f[/color] damage." % [next_every, next_mult]
			return "[color=#c8daf0]Execution:[/color] every [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color] swings, damage [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color]." % [cur_every, next_every, cur_mult, next_mult]
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
				return "[color=#9ab8d8]Hits slow enemies, and striking slowed targets deals bonus damage.[/color]\n[color=#9ab8d8]Initial:[/color] slow [color=#7de882]%.2fs[/color] at [color=#7de882]%.0f%%[/color] speed, bonus [color=#7de882]+%d[/color] damage." % [next_duration, next_slow_mult * 100.0, next_bonus]
			return "[color=#c8daf0]Hunter's Snare:[/color] slow [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], speed [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color], bonus [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]." % [cur_duration, next_duration, cur_slow_mult * 100.0, next_slow_mult * 100.0, cur_bonus, next_bonus]
		"phantom_step":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_damage := int(next_values.get("damage", 0))
			var next_slow := float(next_values.get("slow_duration", 0.0))
			var cur_damage := int(player_reference.get("phantom_step_damage"))
			var cur_slow := float(player_reference.get("phantom_step_slow_duration"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Dashing through enemies deals damage and leaves them slowed in your wake.[/color]\n[color=#9ab8d8]Initial:[/color] hit damage [color=#7de882]%d[/color], slow for [color=#7de882]%.2fs[/color]." % [next_damage, next_slow]
			return "[color=#c8daf0]Phantom Step:[/color] damage [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], slow [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [cur_damage, next_damage, cur_slow, next_slow]
		"reaper_step":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_range := float(next_values.get("range_mult", 1.0))
			var cur_range := float(player_reference.get("void_dash_range_mult"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Kills fully refresh your dash, and each stack extends your dash.[/color]\n[color=#9ab8d8]Initial:[/color] range [color=#7de882]x%.2f[/color], kill refresh [color=#7de882]full[/color]." % [next_range]
			return "[color=#c8daf0]Reaper Step:[/color] range [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color], kill refresh [color=#7de882]full[/color]." % [cur_range, next_range]
		"static_wake":
			if next_values.is_empty():
				return "[color=#9ab8d8]Enhances this power.[/color]"
			var next_damage := int(next_values.get("damage", 0))
			var next_lifetime := float(next_values.get("lifetime", 0.0))
			var cur_damage := int(player_reference.get("static_wake_damage"))
			var cur_lifetime := float(player_reference.get("static_wake_lifetime"))
			if current_stack <= 0:
				return "[color=#9ab8d8]Leaves an electrified trail as you move that shocks any enemy who steps into it.[/color]\n[color=#9ab8d8]Initial:[/color] trail tick [color=#7de882]%d[/color] damage, lasts [color=#7de882]%.2fs[/color]." % [next_damage, next_lifetime]
			return "[color=#c8daf0]Static Wake:[/color] tick [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], trail [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [cur_damage, next_damage, cur_lifetime, next_lifetime]
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
				return "[color=#9ab8d8]Dash marks enemies. Marked hits deal bonus damage and chain splashes nearby.[/color]\n[color=#9ab8d8]Initial:[/color] mark [color=#7de882]%.2fs[/color], bonus [color=#7de882]+%d[/color], cleave [color=#7de882]%.0f%%[/color]." % [next_mark_duration, next_bonus_damage, next_splash_ratio * 100.0]
			return "[color=#c8daf0]Wraithstep:[/color] mark [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], bonus [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color], cleave [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color]." % [cur_mark_duration, next_mark_duration, cur_bonus_damage, next_bonus_damage, cur_splash_ratio * 100.0, next_splash_ratio * 100.0]
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
		"swift_strike":
			var cur_cd := float(cur_val)
			var next_cd := float(next_val)
			return "[color=#c8daf0]Attack cooldown:[/color] [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]" % [cur_cd, next_cd]
		"heavy_blow":
			return "[color=#c8daf0]Attack damage:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [int(cur_val), int(next_val)]
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
			var cur_lock := float(cur_val)
			var next_lock := float(next_val)
			return "[color=#c8daf0]Attack lock duration:[/color] [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]" % [cur_lock, next_lock]
		"surge_step":
			return "[color=#c8daf0]Dash speed:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [float(cur_val), float(next_val)]
		"kinetic_drive":
			var cur_accel := float(cur_val)
			var next_accel := float(next_val)
			var top_speed := maxf(1.0, float(player_reference.get("max_speed")))
			var cur_time_to_top := top_speed / maxf(1.0, cur_accel)
			var next_time_to_top := top_speed / maxf(1.0, next_accel)
			return "[color=#c8daf0]Acceleration:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]\n[color=#c8daf0]0->max speed:[/color] [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]" % [cur_accel, next_accel, cur_time_to_top, next_time_to_top]
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
func build_melee_attack_context(base_attack_damage: int, base_attack_range: float, base_attack_arc_degrees: float, execution_proc: bool, execution_damage_mult: float) -> Dictionary:
	var damage_mult := execution_damage_mult if execution_proc else 1.0
	return {
		"damage": maxi(1, int(round(float(base_attack_damage) * damage_mult))),
		"range": base_attack_range,
		"arc_degrees": base_attack_arc_degrees,
		"damage_mult": damage_mult,
		"execution_proc": execution_proc
	}


## Build the final Razor Wind attack context from the already-resolved melee context.
func build_razor_wind_attack_context(melee_context: Dictionary, razor_wind_damage_ratio: float, razor_wind_range_scale: float, razor_wind_arc_degrees: float, fallback_attack_damage: int, fallback_attack_range: float) -> Dictionary:
	var melee_damage := int(melee_context.get("damage", fallback_attack_damage))
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
	if is_instance_valid(game_state) and game_state.has_method("get_upgrade_stack_count"):
		return int(game_state.call("get_upgrade_stack_count", id))
	return int(upgrade_stacks.get(id, 0))


func _get_power_stack_limit(power_id: String) -> int:
	if power_registry != null and power_registry.has_method("get_power_stack_limit"):
		return int(power_registry.call("get_power_stack_limit", power_id))
	return 0

func _is_upgrade_id(power_id: String) -> bool:
	if power_registry != null and power_registry.has_method("is_upgrade"):
		return bool(power_registry.call("is_upgrade", power_id))
	return UPGRADE_IDS.has(power_id)

func _is_trial_power_id(power_id: String) -> bool:
	if power_registry != null and power_registry.has_method("is_trial_power"):
		return bool(power_registry.call("is_trial_power", power_id))
	return TRIAL_POWER_IDS.has(power_id)

