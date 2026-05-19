extends RefCounted
class_name EncounterDoorUseResult

var used: bool = false
var door: Dictionary = {}

func _init(used_value: bool = false, door_value: Dictionary = {}):
	used = used_value
	door = door_value.duplicate(true) if used else {}

static func from_values(used_value: bool, door_value: Dictionary) -> EncounterDoorUseResult:
	return EncounterDoorUseResult.new(used_value, door_value)

func to_dict() -> Dictionary:
	return {
		"used": used,
		"door": door.duplicate(true) if used else {}
	}
