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


func _ready() -> void:
	# Register as singleton or get injected
	pass


## Apply an upgrade (stat boost) to the player
func apply_upgrade(upgrade_id: String) -> bool:
	var id := upgrade_id.strip_edges().to_lower()
	if not is_instance_valid(player_reference):
		return false
	
	if not power_registry.is_upgrade(id):
		return false
	
	# Track in game state
	if is_instance_valid(game_state):
		game_state.add_upgrade(id)
	
	# Delegate specific upgrade effects to player
	if player_reference.has_method("apply_upgrade"):
		player_reference.call("apply_upgrade", id)
		return true
	
	return false


## Apply a trial power (combat ability) to the player
func apply_trial_power(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	if not is_instance_valid(player_reference):
		return false
	
	if not power_registry.is_trial_power(id):
		return false
	
	# Track in game state
	if is_instance_valid(game_state):
		game_state.add_trial_power(id)
	
	# Update local stack
	if trial_power_stacks.has(id):
		trial_power_stacks[id] += 1
	
	# Delegate specific trial power effects to player
	if player_reference.has_method("apply_trial_power"):
		player_reference.call("apply_trial_power", id)
		return true
	
	return false


## Apply any power (upgrade or trial power)
func apply_power(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	
	if power_registry.is_upgrade(id):
		return apply_upgrade(id)
	elif power_registry.is_trial_power(id):
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
	if trial_power_stacks.has(id):
		return trial_power_stacks[id]
	return 0


## Get trial power description with next stack info (delegates to player for accuracy)
func get_trial_power_card_description(power_id: String) -> String:
	var id := power_id.strip_edges().to_lower()
	if not is_instance_valid(player_reference):
		return "Enhances this power."
	
	if player_reference.has_method("get_trial_power_card_desc"):
		return String(player_reference.call("get_trial_power_card_desc", id))
	
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
