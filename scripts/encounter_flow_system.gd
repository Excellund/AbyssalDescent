extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

func advance_room_progress(rooms_cleared: int, room_depth: int, encounter_count: int) -> Dictionary:
	var next_rooms_cleared := rooms_cleared + 1
	var next_room_depth := room_depth + 1
	return {
		"rooms_cleared": next_rooms_cleared,
		"room_depth": next_room_depth,
		"boss_unlocked": next_rooms_cleared >= encounter_count
	}

func resolve_room_cleared(in_boss_room: bool, pending_room_reward: int, rooms_cleared: int, room_depth: int, encounter_count: int) -> Dictionary:
	if in_boss_room:
		return ENCOUNTER_CONTRACTS.room_cleared_outcome(
			true,
			ENUMS.RewardMode.NONE,
			false,
			pending_room_reward,
			rooms_cleared,
			room_depth,
			rooms_cleared >= encounter_count
		)

	var progress := advance_room_progress(rooms_cleared, room_depth, encounter_count)
	var reward_mode: int = ENCOUNTER_CONTRACTS.normalize_reward_mode(pending_room_reward)
	if reward_mode == ENUMS.RewardMode.BOON:
		return ENCOUNTER_CONTRACTS.room_cleared_outcome(
			false,
			ENUMS.RewardMode.BOON,
			false,
			ENUMS.RewardMode.NONE,
			int(progress["rooms_cleared"]),
			int(progress["room_depth"]),
			bool(progress["boss_unlocked"])
		)
	if reward_mode == ENUMS.RewardMode.ARCANA or reward_mode == ENUMS.RewardMode.HARD:
		return ENCOUNTER_CONTRACTS.room_cleared_outcome(
			false,
			ENUMS.RewardMode.ARCANA,
			false,
			ENUMS.RewardMode.NONE,
			int(progress["rooms_cleared"]),
			int(progress["room_depth"]),
			bool(progress["boss_unlocked"])
		)

	return ENCOUNTER_CONTRACTS.room_cleared_outcome(
		false,
		ENUMS.RewardMode.NONE,
		true,
		ENUMS.RewardMode.NONE,
		int(progress["rooms_cleared"]),
		int(progress["room_depth"]),
		bool(progress["boss_unlocked"])
	)

func build_door_options(boss_unlocked: bool, _room_depth: int, door_distance_from_center: float, route_options: Array[Dictionary]) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if boss_unlocked:
		var boss_option := ENCOUNTER_CONTRACTS.door_option(
			"Boss",
			Color(0.95, 0.18, 0.22, 0.98),
			ENUMS.DoorKind.BOSS,
			"boss",
			ENUMS.RewardMode.NONE,
			{}
		)
		ENCOUNTER_CONTRACTS.door_option_set_position(boss_option, Vector2(0.0, -40.0))
		options.append(boss_option)
		return options

	var positions := [Vector2(-door_distance_from_center, -40.0), Vector2(door_distance_from_center, -40.0)]
	for i in range(mini(route_options.size(), positions.size())):
		var option := ENCOUNTER_CONTRACTS.normalize_door_option(route_options[i])
		ENCOUNTER_CONTRACTS.door_option_set_position(option, positions[i])
		options.append(option)
	return options

func find_used_door(player_position: Vector2, door_options: Array[Dictionary], door_use_radius: float) -> Dictionary:
	for door in door_options:
		var door_pos: Vector2 = ENCOUNTER_CONTRACTS.door_option_get_position(door)
		if player_position.distance_to(door_pos) > door_use_radius:
			continue
		return ENCOUNTER_CONTRACTS.door_use_result(true, door)
	return ENCOUNTER_CONTRACTS.door_use_result(false, {})

func resolve_chosen_door(door: Dictionary) -> Dictionary:
	var kind: int = ENCOUNTER_CONTRACTS.door_option_kind_id(door)
	if kind == ENUMS.DoorKind.BOSS:
		return ENCOUNTER_CONTRACTS.door_choice(ENCOUNTER_CONTRACTS.ACTION_BOSS, {})
	if kind == ENUMS.DoorKind.REST:
		return ENCOUNTER_CONTRACTS.door_choice(ENCOUNTER_CONTRACTS.ACTION_REST, {})
	var reward_mode: int = ENCOUNTER_CONTRACTS.door_option_reward_mode(door)
	return ENCOUNTER_CONTRACTS.door_choice(ENCOUNTER_CONTRACTS.ACTION_ENCOUNTER, ENCOUNTER_CONTRACTS.door_option_profile(door), reward_mode)
