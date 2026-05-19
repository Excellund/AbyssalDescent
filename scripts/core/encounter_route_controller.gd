extends RefCounted

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const ENCOUNTER_ROUTE_STATE := preload("res://scripts/core/encounter_route_state.gd")
const ENCOUNTER_DOOR_USE_RESULT := preload("res://scripts/shared/contracts/encounter_door_use_result.gd")
const ENCOUNTER_DOOR_CHOICE := preload("res://scripts/shared/contracts/encounter_door_choice.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")

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
) -> ENCOUNTER_ROUTE_STATE:
	if not is_instance_valid(encounter_flow_system):
		return ENCOUNTER_ROUTE_STATE.from_values(false, choosing_next_room, door_options, boss_unlocked)

	if choosing_next_room and not door_options.is_empty():
		return ENCOUNTER_ROUTE_STATE.from_values(false, choosing_next_room, door_options, boss_unlocked)

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

	return ENCOUNTER_ROUTE_STATE.from_values(true, true, next_door_options, show_boss_door)

func find_used_door(player_position: Vector2, door_options: Array[Dictionary], door_use_radius: float) -> ENCOUNTER_DOOR_USE_RESULT:
	if not is_instance_valid(encounter_flow_system):
		return ENCOUNTER_DOOR_USE_RESULT.from_values(false, {})
	var raw_result: Variant = encounter_flow_system.find_used_door(player_position, door_options, door_use_radius)
	var result: Dictionary = ENCOUNTER_CONTRACTS.normalize_door_use_result(raw_result)
	return ENCOUNTER_DOOR_USE_RESULT.from_values(
		ENCOUNTER_CONTRACTS.door_use_is_used(result),
		ENCOUNTER_CONTRACTS.door_use_get_door(result)
	)

func resolve_choice(door: Dictionary) -> ENCOUNTER_DOOR_CHOICE:
	if not is_instance_valid(encounter_flow_system):
		return ENCOUNTER_DOOR_CHOICE.from_values(ENUMS.EncounterAction.ENCOUNTER, {}, ENUMS.RewardMode.NONE)
	var raw_choice: Variant = encounter_flow_system.resolve_chosen_door(door)
	var choice: Dictionary = ENCOUNTER_CONTRACTS.normalize_door_choice(raw_choice)
	return ENCOUNTER_DOOR_CHOICE.from_values(
		ENCOUNTER_CONTRACTS.door_choice_action_id(choice),
		ENCOUNTER_CONTRACTS.door_choice_profile(choice),
		ENCOUNTER_CONTRACTS.door_choice_reward_mode(choice)
	)
