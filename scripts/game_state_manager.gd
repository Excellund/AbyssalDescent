## Central game progression state tracker
## Manages run progress: room clearing, depth tracking, boss gates, run completion
## Signals: emits events when state changes (room completed, boss unlocked, run completed)

extends Node

## Tier unlock chain: each entry fires when required_tier matches (or -1 = any tier).
## Adding a new tier requires only a new entry here.
const TIER_UNLOCK_CHAIN := [
	{"required_tier": -1, "milestone": "first_clear",             "unlocks_tier": 1},
	{"required_tier":  1, "milestone": "first_clear_on_standard", "unlocks_tier": 2},
	{"required_tier":  2, "milestone": "first_clear_on_veteran",  "unlocks_tier": 3},
]

# State
var rooms_cleared: int = 0
var room_depth: int = 0
var boss_unlocked: bool = false
var in_boss_room: bool = false
var run_cleared: bool = false
var encounter_count: int = 5  # Rooms to clear before boss unlocked

# Tracking
var upgrades_taken: Array[String] = []  # IDs of upgrades player has taken
var trial_powers_taken: Array[String] = []  # IDs of trial powers player has taken
var run_start_time: float = 0.0

# Signals
signal room_completed
signal boss_available  # Emitted when boss becomes available (after enough rooms cleared)
signal run_completed
signal milestone_achieved(milestone_key: String)  # Emitted when a milestone is achieved
signal tier_unlocked(tier: int)  # Emitted when a new difficulty tier is unlocked
signal upgrade_taken(upgrade_id: String)
signal trial_power_taken(power_id: String)


func _ready() -> void:
	run_start_time = Time.get_ticks_msec()


## Mark a room as cleared and check for progression milestones
func complete_room() -> void:
	rooms_cleared += 1
	room_depth += 1
	
	if rooms_cleared >= encounter_count and not boss_unlocked:
		boss_unlocked = true
		emit_signal("boss_available")
	
	emit_signal("room_completed")


## Enter boss room
func enter_boss_room() -> void:
	in_boss_room = true


## Mark run as complete
func complete_run() -> void:
	run_cleared = true
	emit_signal("run_completed")
	_check_and_award_unlocks()


## Check if run unlocked any new difficulty tiers
func _check_and_award_unlocks() -> void:
	var run_context := get_node_or_null("/root/RunContext")
	if run_context == null:
		return

	var current_tier: int = int(run_context.get_current_difficulty_tier())
	var highest_unlocked: int = int(run_context.get_highest_unlocked_difficulty_tier())

	for entry in TIER_UNLOCK_CHAIN:
		var required_tier: int = int(entry["required_tier"])
		if required_tier != -1 and current_tier != required_tier:
			continue
		var milestone: String = String(entry["milestone"])
		if run_context.get_milestone(milestone):
			continue
		var unlocks_tier: int = int(entry["unlocks_tier"])
		run_context.set_milestone(milestone, true)
		emit_signal("milestone_achieved", milestone)
		if highest_unlocked < unlocks_tier:
			run_context.unlock_difficulty_tier(unlocks_tier)
			emit_signal("tier_unlocked", unlocks_tier)



## Register an upgrade selection
func add_upgrade(upgrade_id: String) -> void:
	upgrades_taken.append(upgrade_id)
	emit_signal("upgrade_taken", upgrade_id)


## Register a trial power selection
func add_trial_power(power_id: String) -> void:
	trial_powers_taken.append(power_id)
	emit_signal("trial_power_taken", power_id)


## Get count of specific upgrade taken
func get_upgrade_stack_count(upgrade_id: String) -> int:
	var count := 0
	for id in upgrades_taken:
		if id == upgrade_id:
			count += 1
	return count


## Get count of specific trial power taken
func get_trial_power_stack_count(power_id: String) -> int:
	var count := 0
	for id in trial_powers_taken:
		if id == power_id:
			count += 1
	return count


## Reset state for new run
func reset() -> void:
	rooms_cleared = 0
	room_depth = 0
	boss_unlocked = false
	in_boss_room = false
	run_cleared = false
	upgrades_taken.clear()
	trial_powers_taken.clear()
	run_start_time = Time.get_ticks_msec()


## Get run duration in seconds
func get_run_duration_seconds() -> float:
	return (Time.get_ticks_msec() - run_start_time) / 1000.0


## Get summary of player's current selections
func get_run_summary() -> Dictionary:
	return {
		"rooms_cleared": rooms_cleared,
		"room_depth": room_depth,
		"boss_unlocked": boss_unlocked,
		"in_boss_room": in_boss_room,
		"run_cleared": run_cleared,
		"upgrades_taken": upgrades_taken.duplicate(),
		"trial_powers_taken": trial_powers_taken.duplicate(),
		"duration_seconds": get_run_duration_seconds()
	}
