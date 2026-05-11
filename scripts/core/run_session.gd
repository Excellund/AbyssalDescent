extends RefCounted
class_name RunSession

var boons_taken: Array[String] = []
var arcana_rewards_taken: Array[String] = []
var boss_rewards_taken: Array[String] = []
var rooms_cleared: int = 0
var room_depth: int = 0
var phase_two_rooms_cleared: int = 0
var phase_three_rooms_cleared: int = 0

func reset_for_new_run() -> void:
	boons_taken.clear()
	arcana_rewards_taken.clear()
	boss_rewards_taken.clear()
	set_progression_counters(0, 0, 0, 0)

func record_boon(name: String) -> void:
	boons_taken.append(name)

func record_arcana(name: String) -> void:
	arcana_rewards_taken.append(name)

func record_boss_reward(name: String) -> void:
	boss_rewards_taken.append(name)

func get_boons_taken_snapshot() -> Array[String]:
	return boons_taken.duplicate()

func get_arcana_rewards_taken_snapshot() -> Array[String]:
	return arcana_rewards_taken.duplicate()

func get_boss_rewards_taken_snapshot() -> Array[String]:
	return boss_rewards_taken.duplicate()

func restore_rewards_from_snapshot(boons: Array[String], arcana_rewards: Array[String], boss_rewards: Array[String]) -> void:
	boons_taken = boons.duplicate()
	arcana_rewards_taken = arcana_rewards.duplicate()
	boss_rewards_taken = boss_rewards.duplicate()

func set_progression_counters(next_rooms_cleared: int, next_room_depth: int, next_phase_two_rooms_cleared: int, next_phase_three_rooms_cleared: int) -> void:
	rooms_cleared = next_rooms_cleared
	room_depth = next_room_depth
	phase_two_rooms_cleared = next_phase_two_rooms_cleared
	phase_three_rooms_cleared = next_phase_three_rooms_cleared

func apply_progression_increments(rooms_delta: int, room_depth_delta: int, phase_two_delta: int, phase_three_delta: int) -> void:
	rooms_cleared += rooms_delta
	room_depth += room_depth_delta
	phase_two_rooms_cleared += phase_two_delta
	phase_three_rooms_cleared += phase_three_delta

func get_progression_state() -> Dictionary:
	return {
		"rooms_cleared": rooms_cleared,
		"room_depth": room_depth,
		"phase_two_rooms_cleared": phase_two_rooms_cleared,
		"phase_three_rooms_cleared": phase_three_rooms_cleared,
	}
