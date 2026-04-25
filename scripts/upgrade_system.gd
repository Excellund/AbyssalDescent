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
	"rupture_wave": 0
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
	"rupture_wave": true
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
			player_reference.set("dash_cooldown", maxf(0.12, float(player_reference.get("dash_cooldown")) * 0.85))
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
	if trial_power_stacks.has(id):
		return trial_power_stacks[id]
	return 0


## Get trial power description with next stack info from the current player state.
func get_trial_power_card_description(power_id: String) -> String:
	var id := power_id.strip_edges().to_lower()
	match id:
		"razor_wind":
			return "Attacks launch a forward wind slash with increased range and damage."
		"execution_edge":
			return "Periodic swings become execution strikes with heavy bonus damage."
		"rupture_wave":
			return "Hits detonate a rupture wave that damages nearby enemies."
		_:
			return "Enhances this power."


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
