## Unified power application and stacking system
## Handles all upgrade and trial power effects + their scaling with stacks
## This is the most reusable system: can be called by player, test harness, console, etc.

extends Node

# Dependencies (injected)
var player_reference: Node = null
var game_state: Node = null  # GameStateManager instance
var power_registry: Node = null  # power_registry.gd instance

# Track stacks for trial powers (upgrades don't track stacks for mechanics, but could)
var trial_power_stacks: Dictionary = {
	"razor_wind": 0,
	"execution_edge": 0,
	"rupture_wave": 0,
	"phantom_step": 0,
	"reaper_step": 0,
	"static_wake": 0
}

const UPGRADE_IDS := {
	"swift_strike": true,
	"heavy_blow": true,
	"wide_arc": true,
	"long_reach": true,
	"fleet_foot": true,
	"blink_dash": true,
	"iron_skin": true
}

const TRIAL_POWER_IDS := {
	"razor_wind": true,
	"execution_edge": true,
	"rupture_wave": true,
	"phantom_step": true,
	"reaper_step": true,
	"static_wake": true
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
	
	# Track in game state
	if is_instance_valid(game_state):
		game_state.add_upgrade(id)
	
	match id:
		"swift_strike":
			player_reference.set("attack_cooldown", maxf(0.08, float(player_reference.get("attack_cooldown")) * 0.86))
		"heavy_blow":
			player_reference.set("attack_damage", int(player_reference.get("attack_damage")) + 8)
		"wide_arc":
			var next_arc := clampf(float(player_reference.get("attack_arc_degrees")) + 18.0, 60.0, 240.0)
			player_reference.set("attack_arc_degrees", next_arc)
		"long_reach":
			player_reference.set("attack_range", float(player_reference.get("attack_range")) + 14.0)
		"fleet_foot":
			player_reference.set("max_speed", float(player_reference.get("max_speed")) + 18.0)
		"blink_dash":
			player_reference.set("dash_cooldown", maxf(0.18, float(player_reference.get("dash_cooldown")) * 0.85))
		"iron_skin":
			var current_armor := int(player_reference.get("iron_skin_armor"))
			player_reference.set("iron_skin_armor", current_armor + 3)
			var current_stacks := int(player_reference.get("iron_skin_stacks"))
			player_reference.set("iron_skin_stacks", current_stacks + 1)
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
	
	match id:
		"razor_wind":
			player_reference.set("reward_razor_wind", true)
			var razor_stacks := int(player_reference.get("razor_wind_stacks")) + 1
			player_reference.set("razor_wind_stacks", razor_stacks)
			player_reference.set("razor_wind_range_scale", 1.58 + 0.14 * float(razor_stacks))
			player_reference.set("razor_wind_damage_ratio", 0.6 + 0.12 * float(razor_stacks))
			player_reference.set("attack_cooldown", maxf(0.1, float(player_reference.get("attack_cooldown")) * 0.96))
		"execution_edge":
			player_reference.set("reward_execution_edge", true)
			var execution_stacks := int(player_reference.get("execution_edge_stacks")) + 1
			player_reference.set("execution_edge_stacks", execution_stacks)
			player_reference.set("execution_every", maxi(2, 4 - execution_stacks))
			player_reference.set("execution_damage_mult", 2.2 + 0.45 * float(execution_stacks))
			player_reference.set("attack_lock_duration", maxf(0.08, float(player_reference.get("attack_lock_duration")) * 0.94))
		"rupture_wave":
			player_reference.set("reward_rupture_wave", true)
			var rupture_stacks := int(player_reference.get("rupture_wave_stacks")) + 1
			player_reference.set("rupture_wave_stacks", rupture_stacks)
			player_reference.set("rupture_wave_radius", 72.0 + 10.0 * float(rupture_stacks))
			player_reference.set("rupture_wave_damage_ratio", 0.34 + 0.1 * float(rupture_stacks))
			player_reference.set("attack_damage", int(player_reference.get("attack_damage")) + 2)
		"phantom_step":
			player_reference.set("reward_phantom_step", true)
			var ph_stacks := int(player_reference.get("phantom_step_stacks")) + 1
			player_reference.set("phantom_step_stacks", ph_stacks)
			player_reference.set("phantom_step_damage", 8 + ph_stacks * 4)
			player_reference.set("phantom_step_slow_duration", 0.6 + float(ph_stacks) * 0.15)
			player_reference.set("dash_cooldown", maxf(0.18, float(player_reference.get("dash_cooldown")) * 0.92))
		"reaper_step":
			player_reference.set("reward_void_dash", true)
			var vd_stacks := int(player_reference.get("void_dash_stacks")) + 1
			player_reference.set("void_dash_stacks", vd_stacks)
			player_reference.set("void_dash_range_mult", 1.36 + float(vd_stacks) * 0.12)
			player_reference.set("void_dash_cooldown_reduction", float(vd_stacks) * 0.06)
		"static_wake":
			player_reference.set("reward_static_wake", true)
			var sw_stacks := int(player_reference.get("static_wake_stacks")) + 1
			player_reference.set("static_wake_stacks", sw_stacks)
			player_reference.set("static_wake_damage", 6 + sw_stacks * 3)
			player_reference.set("static_wake_lifetime", 1.2 + float(sw_stacks) * 0.25)
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
			"phantom_step":
				return int(player_reference.get("phantom_step_stacks"))
			"reaper_step":
				return int(player_reference.get("void_dash_stacks"))
			"static_wake":
				return int(player_reference.get("static_wake_stacks"))
	if trial_power_stacks.has(id):
		return trial_power_stacks[id]
	return 0


## Get trial power description with next stack info from the current player state.
func get_trial_power_card_description(power_id: String) -> String:
	var id := power_id.strip_edges().to_lower()
	var current_stack := get_trial_power_stack_count(id)
	var next_stack := current_stack + 1
	match id:
		"razor_wind":
			var next_range_scale := 1.58 + 0.14 * float(next_stack)
			var next_damage_ratio := 0.6 + 0.12 * float(next_stack)
			if current_stack <= 0:
				return "[color=#9ab8d8]Each swing fires a slicing projectile that travels through enemies at range.[/color]\n[color=#9ab8d8]Initial:[/color] range [color=#7de882]x%.2f[/color], damage [color=#7de882]%.0f%%[/color] of hit." % [next_range_scale, next_damage_ratio * 100.0]
			return "[color=#c8daf0]Wind Slash:[/color] range [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color], damage [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color]." % [maxf(1.58, next_range_scale - 0.14), next_range_scale, maxf(60.0, (next_damage_ratio - 0.12) * 100.0), next_damage_ratio * 100.0]
		"execution_edge":
			var next_every := maxi(2, 4 - next_stack)
			var next_mult := 2.2 + 0.45 * float(next_stack)
			if current_stack <= 0:
				return "[color=#9ab8d8]Every few swings builds to a devastating strike that deals massive bonus damage.[/color]\n[color=#9ab8d8]Initial:[/color] every [color=#7de882]%d[/color] swings for [color=#7de882]x%.2f[/color] damage." % [next_every, next_mult]
			var cur_every := maxi(2, 4 - maxi(0, next_stack - 1))
			var cur_mult := 2.2 + 0.45 * float(maxi(0, next_stack - 1))
			return "[color=#c8daf0]Execution:[/color] every [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color] swings, damage [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color]." % [cur_every, next_every, cur_mult, next_mult]
		"rupture_wave":
			var next_radius := 72.0 + 10.0 * float(next_stack)
			var next_ratio := 0.34 + 0.1 * float(next_stack)
			if current_stack <= 0:
				return "[color=#9ab8d8]Your hits send a shockwave rippling outward, damaging all nearby enemies.[/color]\n[color=#9ab8d8]Initial:[/color] radius [color=#7de882]%.0f[/color], damage [color=#7de882]%.0f%%[/color] of hit." % [next_radius, next_ratio * 100.0]
			var cur_radius := 72.0 + 10.0 * float(maxi(0, next_stack - 1))
			var cur_ratio := 0.34 + 0.1 * float(maxi(0, next_stack - 1))
			return "[color=#c8daf0]Rupture:[/color] radius [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color], damage [color=#e8c96a]%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f%%[/color]." % [cur_radius, next_radius, cur_ratio * 100.0, next_ratio * 100.0]
		"phantom_step":
			var next_damage := 8 + next_stack * 4
			var next_slow := 0.6 + float(next_stack) * 0.15
			if current_stack <= 0:
				return "[color=#9ab8d8]Dashing through enemies deals damage and leaves them slowed in your wake.[/color]\n[color=#9ab8d8]Initial:[/color] hit damage [color=#7de882]%d[/color], slow for [color=#7de882]%.2fs[/color]." % [next_damage, next_slow]
			var cur_damage := 8 + maxi(0, next_stack - 1) * 4
			var cur_slow := 0.6 + float(maxi(0, next_stack - 1)) * 0.15
			return "[color=#c8daf0]Phantom Step:[/color] damage [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], slow [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [cur_damage, next_damage, cur_slow, next_slow]
		"reaper_step":
			var next_range := 1.36 + float(next_stack) * 0.12
			var next_cd_trim := float(next_stack) * 0.06
			if current_stack <= 0:
				return "[color=#9ab8d8]Dash kills instantly reset your dash cooldown, and each stack extends your dash and trims base cooldown.[/color]\n[color=#9ab8d8]Initial:[/color] range [color=#7de882]x%.2f[/color], base cooldown trim [color=#7de882]%.2fs[/color], kill reset [color=#7de882]full[/color]." % [next_range, next_cd_trim]
			var cur_range := 1.36 + float(maxi(0, next_stack - 1)) * 0.12
			var cur_cd_trim := float(maxi(0, next_stack - 1)) * 0.06
			return "[color=#c8daf0]Reaper Step:[/color] range [color=#e8c96a]x%.2f[/color] [color=#8899aa]->[/color] [color=#7de882]x%.2f[/color], base trim [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color], kill reset [color=#7de882]full[/color]." % [cur_range, next_range, cur_cd_trim, next_cd_trim]
		"static_wake":
			var next_damage := 6 + next_stack * 3
			var next_lifetime := 1.2 + float(next_stack) * 0.25
			if current_stack <= 0:
				return "[color=#9ab8d8]Leaves an electrified trail as you move that shocks any enemy who steps into it.[/color]\n[color=#9ab8d8]Initial:[/color] trail tick [color=#7de882]%d[/color] damage, lasts [color=#7de882]%.2fs[/color]." % [next_damage, next_lifetime]
			var cur_damage := 6 + maxi(0, next_stack - 1) * 3
			var cur_lifetime := 1.2 + float(maxi(0, next_stack - 1)) * 0.25
			return "[color=#c8daf0]Static Wake:[/color] tick [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color], trail [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]." % [cur_damage, next_damage, cur_lifetime, next_lifetime]
		_:
			return "[color=#9ab8d8]Enhances this power.[/color]"


func get_upgrade_card_description(upgrade_id: String) -> String:
	if not is_instance_valid(player_reference):
		return "[color=#c8daf0]Upgrade your stats.[/color]"
	var id := upgrade_id.strip_edges().to_lower()
	match id:
		"swift_strike":
			var cur_cd := float(player_reference.get("attack_cooldown"))
			var next_cd := maxf(0.08, cur_cd * 0.86)
			return "[color=#c8daf0]Attack cooldown:[/color] [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]" % [cur_cd, next_cd]
		"heavy_blow":
			var cur_dmg := int(player_reference.get("attack_damage"))
			return "[color=#c8daf0]Attack damage:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [cur_dmg, cur_dmg + 8]
		"wide_arc":
			var cur_arc := float(player_reference.get("attack_arc_degrees"))
			var next_arc := clampf(cur_arc + 18.0, 60.0, 240.0)
			return "[color=#c8daf0]Attack arc:[/color] [color=#e8c96a]%.0f°[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f°[/color]" % [cur_arc, next_arc]
		"long_reach":
			var cur_range := float(player_reference.get("attack_range"))
			return "[color=#c8daf0]Attack range:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [cur_range, cur_range + 14.0]
		"fleet_foot":
			var cur_speed := float(player_reference.get("max_speed"))
			return "[color=#c8daf0]Move speed:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [cur_speed, cur_speed + 18.0]
		"blink_dash":
			var cur_dash_cd := float(player_reference.get("dash_cooldown"))
			var next_dash_cd := maxf(0.18, cur_dash_cd * 0.85)
			return "[color=#c8daf0]Dash cooldown:[/color] [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]" % [cur_dash_cd, next_dash_cd]
		"iron_skin":
			var cur_armor := int(player_reference.get("iron_skin_armor"))
			return "[color=#c8daf0]Armor:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [cur_armor, cur_armor + 3]
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
	for key in trial_power_stacks.keys():
		trial_power_stacks[key] = 0
	
	if is_instance_valid(game_state):
		game_state.reset()


## Initialize with dependencies
func initialize(player: Node, state: Node, registry: Node) -> void:
	player_reference = player
	game_state = state
	power_registry = registry

func _is_upgrade_id(power_id: String) -> bool:
	if power_registry != null and power_registry.has_method("is_upgrade"):
		return bool(power_registry.call("is_upgrade", power_id))
	return UPGRADE_IDS.has(power_id)

func _is_trial_power_id(power_id: String) -> bool:
	if power_registry != null and power_registry.has_method("is_trial_power"):
		return bool(power_registry.call("is_trial_power", power_id))
	return TRIAL_POWER_IDS.has(power_id)

