extends RefCounted
class_name EncounterDoorUseResult

var used: bool = false
var door: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"used": used,
		"door": door
	}
