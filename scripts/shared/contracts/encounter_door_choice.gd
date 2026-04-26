extends RefCounted
class_name EncounterDoorChoice

const ENUMS := preload("res://scripts/shared/enums.gd")

var action_id: int = ENUMS.EncounterAction.ENCOUNTER
var action: String = "encounter"
var profile: Dictionary = {}
var reward: int = ENUMS.RewardMode.NONE

func to_dict() -> Dictionary:
	return {
		"action_id": action_id,
		"action": action,
		"profile": profile,
		"reward": reward
	}
