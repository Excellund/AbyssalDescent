extends RefCounted
class_name EncounterRoomClearedOutcome

const ENUMS := preload("res://scripts/shared/enums.gd")

var run_cleared: bool = false
var open_reward_mode: int = ENUMS.RewardMode.NONE
var spawn_doors: bool = false
var pending_room_reward: int = ENUMS.RewardMode.NONE
var rooms_cleared: int = 0
var room_depth: int = 0
var boss_unlocked: bool = false

func to_dict() -> Dictionary:
	return {
		"run_cleared": run_cleared,
		"open_reward_mode": open_reward_mode,
		"spawn_doors": spawn_doors,
		"pending_room_reward": pending_room_reward,
		"rooms_cleared": rooms_cleared,
		"room_depth": room_depth,
		"boss_unlocked": boss_unlocked
	}
