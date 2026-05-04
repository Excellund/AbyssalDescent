extends RefCounted

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

var encounter_flow_system: Node

func set_encounter_flow_system(flow_system: Node) -> void:
	encounter_flow_system = flow_system

func build_route_state(
	choosing_next_room: bool,
	door_options: Array[Dictionary],
	boss_unlocked: bool,
	first_boss_defeated: bool,
	second_boss_defeated: bool,
	room_depth: int,
	door_distance_from_center: float,
	route_options: Array[Dictionary],
	show_second_boss: bool,
	show_third_boss: bool
) -> Dictionary:
	if not is_instance_valid(encounter_flow_system):
		return {
			"ok": false,
			"choosing_next_room": choosing_next_room,
			"door_options": door_options,
			"boss_unlocked": boss_unlocked
		}

	if choosing_next_room and not door_options.is_empty():
		return {
			"ok": false,
			"choosing_next_room": choosing_next_room,
			"door_options": door_options,
			"boss_unlocked": boss_unlocked
		}

	var show_boss_door := boss_unlocked
	var boss_encounter_key := "warden"
	if second_boss_defeated:
		show_boss_door = show_third_boss
		boss_encounter_key = "lacuna"
	elif first_boss_defeated:
		show_boss_door = show_second_boss
		boss_encounter_key = "sovereign"

	var next_door_options: Array[Dictionary] = encounter_flow_system.build_door_options(
		show_boss_door,
		room_depth,
		door_distance_from_center,
		route_options,
		boss_encounter_key
	)

	return {
		"ok": true,
		"choosing_next_room": true,
		"door_options": next_door_options,
		"boss_unlocked": show_boss_door
	}

func find_used_door(player_position: Vector2, door_options: Array[Dictionary], door_use_radius: float) -> Dictionary:
	if not is_instance_valid(encounter_flow_system):
		return {}
	var raw_result: Variant = encounter_flow_system.find_used_door(player_position, door_options, door_use_radius)
	var result: Dictionary = ENCOUNTER_CONTRACTS.normalize_door_use_result(raw_result)
	if not ENCOUNTER_CONTRACTS.door_use_is_used(result):
		return {}
	return ENCOUNTER_CONTRACTS.door_use_get_door(result)

func resolve_choice(door: Dictionary) -> Dictionary:
	if not is_instance_valid(encounter_flow_system):
		return {}
	var raw_choice: Variant = encounter_flow_system.resolve_chosen_door(door)
	return ENCOUNTER_CONTRACTS.normalize_door_choice(raw_choice)
