## Centralized power registry and unified data structure
## All upgrades (stat boosts) and trial powers (combat abilities) are defined here
## This is the single source of truth for what powers exist and their metadata

extends Node

# Power type constants
const POWER_TYPE_UPGRADE = "upgrade"  # Stat boosts: Swift Strike, Heavy Blow, etc
const POWER_TYPE_TRIAL = "trial_power"  # Combat abilities: Razor Wind, Execution Edge, Rupture Wave

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
			"stack_limit": stack_limit
		}


func _ready() -> void:
	# No initialization needed; registry is purely static data
	pass


## Return all upgrades (stat boosts)
func get_upgrade_pool(player_reference: Node = null) -> Array[Dictionary]:
	var swift_desc := "Attack cooldown reduced by 14%."
	var heavy_desc := "Attack damage +8."
	var wide_desc := "Attack arc +18 degrees."
	var reach_desc := "Attack range +14."
	var fleet_desc := "Move speed +18."
	var blink_desc := "Dash cooldown reduced by 15%."
	var iron_desc := "-3 damage per hit."
	if is_instance_valid(player_reference) and player_reference.has_method("get_upgrade_card_desc"):
		swift_desc = String(player_reference.call("get_upgrade_card_desc", "swift_strike"))
		heavy_desc = String(player_reference.call("get_upgrade_card_desc", "heavy_blow"))
		wide_desc = String(player_reference.call("get_upgrade_card_desc", "wide_arc"))
		reach_desc = String(player_reference.call("get_upgrade_card_desc", "long_reach"))
		fleet_desc = String(player_reference.call("get_upgrade_card_desc", "fleet_foot"))
		blink_desc = String(player_reference.call("get_upgrade_card_desc", "blink_dash"))
		iron_desc = String(player_reference.call("get_upgrade_card_desc", "iron_skin"))
	return [
		Power.new("swift_strike", "Swift Strike", swift_desc, POWER_TYPE_UPGRADE, 0, {}).to_dict(),
		Power.new("heavy_blow", "Heavy Blow", heavy_desc, POWER_TYPE_UPGRADE, 0, {}).to_dict(),
		Power.new("wide_arc", "Wide Arc", wide_desc, POWER_TYPE_UPGRADE, 0, {}).to_dict(),
		Power.new("long_reach", "Long Reach", reach_desc, POWER_TYPE_UPGRADE, 0, {}).to_dict(),
		Power.new("fleet_foot", "Fleet Foot", fleet_desc, POWER_TYPE_UPGRADE, 0, {}).to_dict(),
		Power.new("blink_dash", "Blink Dash", blink_desc, POWER_TYPE_UPGRADE, 0, {}).to_dict(),
		Power.new("iron_skin", "Iron Skin", iron_desc, POWER_TYPE_UPGRADE, 3, {}).to_dict(),
	]


## Return all trial powers (combat abilities)
func get_trial_power_pool(player_reference: Node = null) -> Array[Dictionary]:
	var razor_desc := "Attacks launch a long-range piercing wind slash."
	var execution_desc := "Every 3rd swing is a huge execution strike."
	var rupture_desc := "Hits detonate a damaging shockwave."
	var aegis_desc := "Taking damage triggers a guard pulse that slows nearby enemies and grants brief damage resistance."
	var snare_desc := "Hits slow enemies. Striking slowed enemies deals bonus damage."
	
	# Try to get dynamic descriptions from player stack counts
	if is_instance_valid(player_reference) and player_reference.has_method("get_trial_power_card_desc"):
		razor_desc = String(player_reference.call("get_trial_power_card_desc", "razor_wind"))
		execution_desc = String(player_reference.call("get_trial_power_card_desc", "execution_edge"))
		rupture_desc = String(player_reference.call("get_trial_power_card_desc", "rupture_wave"))
		aegis_desc = String(player_reference.call("get_trial_power_card_desc", "aegis_field"))
		snare_desc = String(player_reference.call("get_trial_power_card_desc", "hunters_snare"))
	
	var phantom_desc := "Dashing through enemies damages and slows them."
	var void_desc := "Dash travels farther. Kills refresh dash cooldown."
	var static_desc := "Dashing leaves an electrified trail that burns enemies."
	if is_instance_valid(player_reference) and player_reference.has_method("get_trial_power_card_desc"):
		phantom_desc = String(player_reference.call("get_trial_power_card_desc", "phantom_step"))
		void_desc = String(player_reference.call("get_trial_power_card_desc", "reaper_step"))
		static_desc = String(player_reference.call("get_trial_power_card_desc", "static_wake"))

	return [
		Power.new("razor_wind", "Razor Wind", razor_desc, POWER_TYPE_TRIAL, 0, {}).to_dict(),
		Power.new("execution_edge", "Execution Edge", execution_desc, POWER_TYPE_TRIAL, 0, {}).to_dict(),
		Power.new("rupture_wave", "Rupture Wave", rupture_desc, POWER_TYPE_TRIAL, 0, {}).to_dict(),
		Power.new("aegis_field", "Aegis Field", aegis_desc, POWER_TYPE_TRIAL, 0, {}).to_dict(),
		Power.new("hunters_snare", "Hunter's Snare", snare_desc, POWER_TYPE_TRIAL, 0, {}).to_dict(),
		Power.new("phantom_step", "Phantom Step", phantom_desc, POWER_TYPE_TRIAL, 0, {}).to_dict(),
		Power.new("reaper_step", "Reaper Step", void_desc, POWER_TYPE_TRIAL, 0, {}).to_dict(),
		Power.new("static_wake", "Static Wake", static_desc, POWER_TYPE_TRIAL, 0, {}).to_dict(),
	]


func get_objective_upgrade_pool(player_reference: Node = null) -> Array[Dictionary]:
	var pool := get_upgrade_pool(player_reference)
	var favored_ids := {
		"swift_strike": true,
		"heavy_blow": true,
		"long_reach": true,
		"fleet_foot": true,
		"blink_dash": true,
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

