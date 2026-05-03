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

# Track stacks for trial powers as backup when player_reference is unavailable
var trial_power_stacks: Dictionary = {}


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
		"shard_strike", "hammered_impact", "cracking_arc", "fracture_reach", "quarry_step", "swift_reach", "battle_echo", "relentless_surge", "apex_predator", "void_echo", "apex_momentum", "convergence_surge", "indomitable_spirit":
			player_reference.set(String(preview.get("property", "")), preview.get("next", player_reference.get(String(preview.get("property", "")))))
		"vital_covenant":
			var next_max := int(preview.get("next", player_reference.get_max_health()))
			var current_max: int = int(player_reference.get_max_health())
			var max_gain := maxi(0, next_max - current_max)
			var next_current: int = int(player_reference.get_current_health()) + max_gain
			player_reference.set_max_health_and_current(next_max, next_current)
		"iron_oath":
			player_reference.set("iron_skin_armor", int(preview.get("next", int(player_reference.get("iron_skin_armor")))))
			player_reference.set("iron_skin_stacks", int(player_reference.get("iron_skin_stacks")) + 1)
		"sworn_blade":
			player_reference.set("sworn_blade_bonus_damage", int(preview.get("next", int(player_reference.get("sworn_blade_bonus_damage")))))
		"resonant_edge":
			player_reference.set("resonant_edge_bonus_damage", int(preview.get("next", int(player_reference.get("resonant_edge_bonus_damage")))))
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
	var next_values := POWER_PARAMETER_MAPPER.build_trial_values(id, next_stack, _get_power_balance_data(id), player_reference)
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
		var stack_property := POWER_PARAMETER_MAPPER.get_stack_property(id)
		if not stack_property.is_empty():
			return int(player_reference.get(stack_property))
	if trial_power_stacks.has(id):
		return trial_power_stacks[id]
	return 0


func get_trial_runtime_values(power_id: String) -> Dictionary:
	var id := power_id.strip_edges().to_lower()
	if id.is_empty():
		return {}
	var stack_count := get_trial_power_stack_count(id)
	return POWER_PARAMETER_MAPPER.build_trial_values(id, stack_count, _get_power_balance_data(id), player_reference)


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


## Get trial power description with next stack info from the current player state.
func get_trial_power_card_description(power_id: String) -> String:
	if not is_instance_valid(player_reference):
		return "[color=#9ab8d8]Enhances this power.[/color]"
	var id := power_id.strip_edges().to_lower()
	var current_stack := get_trial_power_stack_count(id)
	var next_stack := current_stack + 1
	var next_values := POWER_PARAMETER_MAPPER.build_trial_values(id, next_stack, _get_power_balance_data(id), player_reference)
	if next_values.is_empty():
		return "[color=#9ab8d8]Enhances this power.[/color]"
	var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
	match id:
		"razor_wind":
			var next_range_scale := float(next_values.get("range_scale", 1.0))
			var next_damage_ratio := float(next_values.get("damage_ratio", 0.0))
			var cur_range_scale := float(cur.get("range_scale", 1.0))
			var cur_damage_ratio := float(cur.get("damage_ratio", 0.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]Each swing fires a slicing projectile that travels through enemies at range.[/color]\n[color=#9ab8d8]Initial:[/color] range [color=#7de882]x%.2f[/color], damage [color=#7de882]%.0f%%[/color] of hit." % [next_range_scale, next_damage_ratio * 100.0]
			var razor_prefix := _damage_kind_prefix("razor_wind")
			return "%s[color=#c8daf0]Wind Slash:[/color] range [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color], damage [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color] of hit." % [razor_prefix, cur_range_scale, next_range_scale, cur_damage_ratio * 100.0, next_damage_ratio * 100.0]
		"execution_edge":
			var next_every := int(next_values.get("every", 2))
			var next_mult := float(next_values.get("damage_mult", 1.0))
			var cur_every := int(cur.get("every", 2))
			var cur_mult := float(cur.get("damage_mult", 1.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]Every few swings builds to a devastating strike that deals massive extra damage.[/color]\n[color=#9ab8d8]Initial:[/color] every [color=#7de882]%d[/color] swings for [color=#7de882]x%.2f[/color] damage." % [next_every, next_mult]
			var execution_prefix := _damage_kind_prefix("execution_edge")
			return "%s[color=#c8daf0]Execution:[/color] every [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color] swings, damage [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color] on hit." % [execution_prefix, cur_every, next_every, cur_mult, next_mult]
		"rupture_wave":
			var next_radius := float(next_values.get("radius", 0.0))
			var next_ratio := float(next_values.get("damage_ratio", 0.0))
			var cur_radius := float(cur.get("radius", 0.0))
			var cur_ratio := float(cur.get("damage_ratio", 0.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]Your hits send a shockwave rippling outward, damaging all nearby enemies.[/color]\n[color=#9ab8d8]Initial:[/color] radius [color=#7de882]%.0f[/color], damage [color=#7de882]%.0f%%[/color] of hit." % [next_radius, next_ratio * 100.0]
			return "[color=#c8daf0]Rupture:[/color] radius [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color], damage [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color]." % [cur_radius, next_radius, cur_ratio * 100.0, next_ratio * 100.0]
		"aegis_retort":
			var next_resist := float(next_values.get("resist", 0.0))
			var next_duration := float(next_values.get("duration", 0.0))
			var next_radius := float(next_values.get("radius", 0.0))
			var next_cooldown := float(next_values.get("cooldown", 0.0))
			var cur_resist := float(cur.get("resist", 0.0))
			var cur_duration := float(cur.get("duration", 0.0))
			var cur_radius := float(cur.get("radius", 0.0))
			var cur_cooldown := float(cur.get("cooldown", 0.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]Taking damage triggers a guard pulse: slows nearby enemies, grants brief resistance, and binds a Vow.[/color]\n[color=#9ab8d8]Initial:[/color] resist [color=#7de882]%.0f%%[/color] for [color=#7de882]%.2fs[/color], pulse radius [color=#7de882]%.0f[/color], cooldown [color=#7de882]%.2fs[/color]." % [next_resist * 100.0, next_duration, next_radius, next_cooldown]
			return "[color=#c8daf0]Aegis Retort:[/color] resist [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color], guard [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], pulse radius [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color], cooldown [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [cur_resist * 100.0, next_resist * 100.0, cur_duration, next_duration, cur_radius, next_radius, cur_cooldown, next_cooldown]
		"hunters_snare":
			var next_bonus := int(next_values.get("bonus_damage", 0))
			var next_duration := float(next_values.get("slow_duration", 0.0))
			var next_slow_mult := float(next_values.get("slow_mult", 1.0))
			var cur_bonus := int(cur.get("bonus_damage", 0))
			var cur_duration := float(cur.get("slow_duration", 0.0))
			var cur_slow_mult := float(cur.get("slow_mult", 1.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]Hits slow enemies, and striking slowed targets deals extra hit damage.[/color]\n[color=#9ab8d8]Initial:[/color] slow [color=#7de882]%.2fs[/color] at [color=#7de882]%.0f%%[/color] speed, extra hit damage [color=#7de882]+%d[/color]." % [next_duration, next_slow_mult * 100.0, next_bonus]
			var snare_prefix := _damage_kind_prefix("hunters_snare")
			return "%s[color=#c8daf0]Hunter's Snare:[/color] slow [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], speed [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color], extra hit damage [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]." % [snare_prefix, cur_duration, next_duration, cur_slow_mult * 100.0, next_slow_mult * 100.0, cur_bonus, next_bonus]
		"phantom_step":
			var phantom_prefix := _damage_kind_prefix("phantom_step")
			var next_damage := int(next_values.get("damage", 0))
			var next_slow := float(next_values.get("slow_duration", 0.0))
			var cur_damage := int(cur.get("damage", 0))
			var cur_slow := float(cur.get("slow_duration", 0.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]Dashing through enemies deals damage and leaves them slowed in your wake.[/color]\n[color=#9ab8d8]Initial:[/color] damage [color=#7de882]%d[/color], slow [color=#7de882]%.2fs[/color]." % [next_damage, next_slow]
			return "%s[color=#c8daf0]Phantom Step:[/color] damage [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], slow [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [phantom_prefix, cur_damage, next_damage, cur_slow, next_slow]
		"apex_surge":
			var next_weave_range := float(next_values.get("weave_taut_range_mult", 1.0))
			var next_weave_dmg := float(next_values.get("weave_taut_damage_mult", 0.0))
			var cur_weave_range := float(cur.get("weave_taut_range_mult", 1.0))
			var cur_weave_dmg := float(cur.get("weave_taut_damage_mult", 0.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]While Weave is Taut, attack range and hit damage are amplified.[/color]\n[color=#9ab8d8]Initial:[/color] range [color=#7de882]x%.2f[/color], bonus damage [color=#7de882]+%.0f%%[/color]." % [next_weave_range, next_weave_dmg * 100.0]
			return "[color=#c8daf0]Apex Surge (Taut):[/color] range [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color], bonus dmg [color=#e8c96a]+%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]+%.0f%%[/color]." % [cur_weave_range, next_weave_range, cur_weave_dmg * 100.0, next_weave_dmg * 100.0]
		"static_wake":
			var wake_prefix := _damage_kind_prefix("static_wake")
			var next_lifetime := float(next_values.get("lifetime", 0.0))
			var cur_lifetime := float(cur.get("lifetime", 0.0))
			var wake_data := _get_power_balance_data("static_wake")
			var wake_ratio_base := float(wake_data.get("damage_ratio_base", 0.0))
			var wake_ratio_per_stack := float(wake_data.get("damage_ratio_per_stack", 0.0))
			var cur_damage_ratio := wake_ratio_base + wake_ratio_per_stack * float(current_stack)
			var next_damage_ratio := wake_ratio_base + wake_ratio_per_stack * float(next_stack)
			if current_stack <= 0:
				return "[color=#9ab8d8]Leaves an electrified trail as you move that shocks any enemy who steps into it.[/color]\n[color=#9ab8d8]Initial:[/color] damage per pulse [color=#7de882]%.0f%%[/color] of damage stat, lasts [color=#7de882]%.2fs[/color]." % [next_damage_ratio * 100.0, next_lifetime]
			return "%s[color=#c8daf0]Static Wake:[/color] damage per pulse [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color] of damage stat, trail [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [wake_prefix, cur_damage_ratio * 100.0, next_damage_ratio * 100.0, cur_lifetime, next_lifetime]
		"storm_crown":
			var next_every := int(next_values.get("proc_every", 1))
			var next_targets := int(next_values.get("chain_targets", 1))
			var next_radius := float(next_values.get("chain_radius", 0.0))
			var next_ratio := float(next_values.get("damage_ratio", 0.0))
			var cur_every := int(cur.get("proc_every", 1))
			var cur_targets := int(cur.get("chain_targets", 1))
			var cur_radius := float(cur.get("chain_radius", 0.0))
			var cur_ratio := float(cur.get("damage_ratio", 0.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]Every few hits discharge chain lightning from your target to nearby foes.[/color]\n[color=#9ab8d8]Initial:[/color] every [color=#7de882]%d[/color] hits, chains to [color=#7de882]%d[/color] targets within [color=#7de882]%.0f[/color], for [color=#7de882]%.0f%%[/color] damage." % [next_every, next_targets, next_radius, next_ratio * 100.0]
			return "[color=#c8daf0]Storm Crown:[/color] proc [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], chains [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], radius [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color], damage [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color]." % [cur_every, next_every, cur_targets, next_targets, cur_radius, next_radius, cur_ratio * 100.0, next_ratio * 100.0]
		"wraithstep":
			var next_mark_duration := float(next_values.get("mark_duration", 0.0))
			var next_bonus_damage := int(next_values.get("bonus_damage", 0))
			var next_splash_ratio := float(next_values.get("splash_ratio", 0.0))
			var cur_mark_duration := float(cur.get("mark_duration", 0.0))
			var cur_bonus_damage := int(cur.get("bonus_damage", 0))
			var cur_splash_ratio := float(cur.get("splash_ratio", 0.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]Dash marks enemies. Marked hits deal extra hit damage and chain splashes nearby.[/color]\n[color=#9ab8d8]Initial:[/color] mark [color=#7de882]%.2fs[/color], marked-hit damage [color=#7de882]+%d[/color], cleave [color=#7de882]%.0f%%[/color]." % [next_mark_duration, next_bonus_damage, next_splash_ratio * 100.0]
			var wraith_prefix := _damage_kind_prefix("wraithstep")
			return "%s[color=#c8daf0]Wraithstep:[/color] mark [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], marked-hit damage [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color], cleave [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color] of hit." % [wraith_prefix, cur_mark_duration, next_mark_duration, cur_bonus_damage, next_bonus_damage, cur_splash_ratio * 100.0, next_splash_ratio * 100.0]
		"voidfire":
			var next_amp := float(next_values.get("danger_zone_amp", 0.0))
			var next_det_ratio := float(next_values.get("detonate_ratio", 0.0))
			var next_lockout := float(next_values.get("lockout_duration", 0.0))
			var cur_amp := float(cur.get("danger_zone_amp", 0.0))
			var cur_det_ratio := float(cur.get("detonate_ratio", 0.0))
			var cur_lockout := float(cur.get("lockout_duration", 0.0))
			if current_stack <= 0:
				var voidfire_initial := "[color=#9ab8d8]Heat attacks. Danger Zone boosts hit damage.[/color]\n[color=#9ab8d8]Initial:[/color] damage [color=#7de882]+%.0f%%[/color], detonate [color=#7de882]%.0f%%[/color], lockout [color=#7de882]%.2fs[/color]." % [next_amp * 100.0, next_det_ratio * 100.0, next_lockout]
				return DESCRIPTION_CAP_GUARD.assert_visible_cap(voidfire_initial, "voidfire", "reward_card")
			var voidfire_stack_desc := "[color=#c8daf0]Voidfire:[/color] damage [color=#e8c96a]+%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]+%.0f%%[/color], detonate [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color], lockout [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [cur_amp * 100.0, next_amp * 100.0, cur_det_ratio * 100.0, next_det_ratio * 100.0, cur_lockout, next_lockout]
			return DESCRIPTION_CAP_GUARD.assert_visible_cap(voidfire_stack_desc, "voidfire", "reward_card")
		"oath_burst":
			var next_pulse_radius := float(next_values.get("pulse_radius", 78.0))
			var next_pulse_ratio := float(next_values.get("pulse_ratio", 0.0))
			var cur_pulse_radius := float(cur.get("pulse_radius", 78.0))
			var cur_pulse_ratio := float(cur.get("pulse_ratio", 0.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]Fulfilling a Vow detonates a radial burst around you.[/color]\n[color=#9ab8d8]Initial:[/color] radius [color=#7de882]%.0f[/color], damage [color=#7de882]%.0f%%[/color] of hit." % [next_pulse_radius, next_pulse_ratio * 100.0]
			return "[color=#c8daf0]Oath Burst:[/color] radius [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color], damage [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color] of hit." % [cur_pulse_radius, next_pulse_radius, cur_pulse_ratio * 100.0, next_pulse_ratio * 100.0]
		"vow_shatter":
			var next_mult_vs := float(next_values.get("damage_mult", 1.0))
			var cur_mult_vs := float(cur.get("damage_mult", 1.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]Taking a hit primes a vow. Your next attack multiplies damage and consumes the vow.[/color]\n[color=#9ab8d8]Initial:[/color] primed hit damage [color=#7de882]x%.2f[/color]." % [next_mult_vs]
			return "[color=#c8daf0]Vow Shatter:[/color] primed hit damage [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color]." % [cur_mult_vs, next_mult_vs]
		"eclipse_mark":
			var next_radius_em := float(next_values.get("radius", 0.0))
			var next_dur_em := float(next_values.get("mark_duration", 0.0))
			var next_ratio_em := float(next_values.get("bonus_ratio", 0.0))
			var cur_radius_em := float(cur.get("radius", 0.0))
			var cur_dur_em := float(cur.get("mark_duration", 0.0))
			var cur_ratio_em := float(cur.get("bonus_ratio", 0.0))
			if current_stack <= 0:
				return "[color=#9ab8d8]Kills mark all nearby enemies. First hit on each marked enemy deals amplified damage. Marks expire quickly.[/color]\n[color=#9ab8d8]Initial:[/color] mark radius [color=#7de882]%.0f[/color], mark duration [color=#7de882]%.2fs[/color], bonus [color=#7de882]%.0f%%[/color] of hit." % [next_radius_em, next_dur_em, next_ratio_em * 100.0]
			return "[color=#c8daf0]Eclipse Mark:[/color] radius [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color], duration [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], bonus [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color] of hit." % [cur_radius_em, next_radius_em, cur_dur_em, next_dur_em, cur_ratio_em * 100.0, next_ratio_em * 100.0]
		"fault_line":
			var next_radius_ff := float(next_values.get("radius", 0.0))
			var next_ratio_ff := float(next_values.get("damage_ratio", 0.0))
			var next_slow_ff := float(next_values.get("slow_duration", 0.0))
			var cur_radius_ff := float(cur.get("radius", 0.0))
			var cur_ratio_ff := float(cur.get("damage_ratio", 0.0))
			var cur_slow_ff := float(cur.get("slow_duration", 0.0))
			if current_stack <= 0:
				var fault_initial := "[color=#9ab8d8]Kill makes a fault zone. Entrants are Sharded and pulsed.[/color]\n[color=#9ab8d8]Initial:[/color] r [color=#7de882]%.0f[/color], d [color=#7de882]%.0f%%[/color], s [color=#7de882]%.2fs[/color]." % [next_radius_ff, next_ratio_ff * 100.0, next_slow_ff]
				return DESCRIPTION_CAP_GUARD.assert_visible_cap(fault_initial, "fault_line", "reward_card")
			var fault_stack_desc := "[color=#c8daf0]Fault:[/color] r [color=#e8c96a]%.0f[/color][color=#8899aa]->[/color][color=#7de882]%.0f[/color], d [color=#e8c96a]%.0f%%[/color][color=#8899aa]->[/color][color=#7de882]%.0f%%[/color], s [color=#e8c96a]%.2f[/color][color=#8899aa]->[/color][color=#7de882]%.2fs[/color]." % [cur_radius_ff, next_radius_ff, cur_ratio_ff * 100.0, next_ratio_ff * 100.0, cur_slow_ff, next_slow_ff]
			return DESCRIPTION_CAP_GUARD.assert_visible_cap(fault_stack_desc, "fault_line", "reward_card")
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
		# FRACTURE CONSTELLATIONS cluster boons
		"shard_strike":
			return "[color=#9ab8d8]Shard-consumed hits crack harder.[/color] [color=#c8daf0]Bonus damage:[/color] [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]" % [int(cur_val), int(next_val)]
		"cracking_arc":
			return "[color=#9ab8d8]Wide swings that hit 3+ enemies Shard all of them.[/color] [color=#c8daf0]Arc:[/color] [color=#e8c96a]%.0f°[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f°[/color]" % [float(cur_val), float(next_val)]
		"fracture_reach":
			return "[color=#9ab8d8]Max-range kills chain Shards to nearby enemies.[/color] [color=#c8daf0]Range:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [float(cur_val), float(next_val)]
		# HUNT WEAVE cluster boons
		"quarry_step":
			return "[color=#9ab8d8]Weave threads hold longer before they decay.[/color] [color=#c8daf0]Move speed:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [float(cur_val), float(next_val)]
		"swift_reach":
			return "[color=#9ab8d8]Each dash plants a Weave thread on a fresh target.[/color] [color=#c8daf0]Dash distance:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [float(cur_val), float(next_val)]
		"relentless_surge":
			return "[color=#9ab8d8]Cascade detonations hit harder and wider.[/color] [color=#c8daf0]Dash speed:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [float(cur_val), float(next_val)]
		# VOW LEDGER cluster boons
		"sworn_blade":
			return "[color=#9ab8d8]Taking damage primes a Vow-finisher strike.[/color] [color=#c8daf0]Next-hit bonus:[/color] [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]" % [int(cur_val), int(next_val)]
		"iron_oath":
			return "[color=#9ab8d8]Active Vows harden your guard by +1 absorb per hit.[/color] [color=#c8daf0]Armor:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [int(cur_val), int(next_val)]
		"vital_covenant":
			var cur_max := int(cur_val)
			var next_max := int(next_val)
			return "[color=#9ab8d8]Damage taken above 60%% HP now binds a Vow.[/color] [color=#c8daf0]Max HP:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [cur_max, next_max]
		# ECHO FORGE cluster boons
		"hammered_impact":
			return "[color=#9ab8d8]Every 5th hit now emits an Echo charge.[/color] [color=#c8daf0]Damage:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [int(cur_val), int(next_val)]
		"battle_echo":
			var cur_speed_bonus := float(cur_val) * 100.0
			var next_speed_bonus := float(next_val) * 100.0
			var trance_duration := 1.25
			if player_reference.get("battle_trance_duration") != null:
				trance_duration = float(player_reference.get("battle_trance_duration"))
			return "[color=#9ab8d8]Moving hits build Echo charge toward Forge bursts.[/color] [color=#c8daf0]Move speed:[/color] [color=#e8c96a]+%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]+%.0f%%[/color] for [color=#7de882]%.2fs[/color]." % [cur_speed_bonus, next_speed_bonus, trance_duration]
		"resonant_edge":
			return "[color=#9ab8d8]Low-HP kills emit 2 Echoes to spike Forge tempo.[/color] [color=#c8daf0]Bonus vs <55%% HP:[/color] [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]" % [int(cur_val), int(next_val)]
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
	trial_power_stacks.clear()
	
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
	return false

func _is_trial_power_id(power_id: String) -> bool:
	if power_registry != null:
		return bool(power_registry.is_trial_power(power_id))
	return POWER_PARAMETER_MAPPER.TRIAL_POWER_PARAM_MAP.has(power_id)
