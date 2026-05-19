extends RefCounted

class_name EncounterRouteState

var ok: bool = false
var choosing_next_room: bool = false
var door_options: Array[Dictionary] = []
var boss_unlocked: bool = false

func _init(
	ok_value: bool = false,
	choosing_next_room_value: bool = false,
	door_options_value: Array = [],
	boss_unlocked_value: bool = false
):
	ok = ok_value
	choosing_next_room = choosing_next_room_value
	door_options = _sanitize_door_options(door_options_value)
	boss_unlocked = boss_unlocked_value

static func from_values(
	ok_value: bool,
	choosing_next_room_value: bool,
	door_options_value: Array,
	boss_unlocked_value: bool
) -> EncounterRouteState:
	return EncounterRouteState.new(
		ok_value,
		choosing_next_room_value,
		door_options_value,
		boss_unlocked_value
	)

func to_dictionary() -> Dictionary:
	return {
		"ok": ok,
		"choosing_next_room": choosing_next_room,
		"door_options": door_options.duplicate(true),
		"boss_unlocked": boss_unlocked
	}

func _sanitize_door_options(value: Array) -> Array[Dictionary]:
	var sanitized: Array[Dictionary] = []
	for option in value:
		if option is Dictionary:
			sanitized.append((option as Dictionary).duplicate(true))
	return sanitized