extends Node

func advance_room_progress(rooms_cleared: int, room_depth: int, encounter_count: int) -> Dictionary:
	var next_rooms_cleared := rooms_cleared + 1
	var next_room_depth := room_depth + 1
	return {
		"rooms_cleared": next_rooms_cleared,
		"room_depth": next_room_depth,
		"boss_unlocked": next_rooms_cleared >= encounter_count
	}

func resolve_room_cleared(in_boss_room: bool, pending_room_reward: String, rooms_cleared: int, room_depth: int, encounter_count: int) -> Dictionary:
	if in_boss_room:
		return {
			"run_cleared": true,
			"open_reward_mode": "",
			"spawn_doors": false,
			"pending_room_reward": pending_room_reward,
			"rooms_cleared": rooms_cleared,
			"room_depth": room_depth,
			"boss_unlocked": rooms_cleared >= encounter_count
		}

	var progress := advance_room_progress(rooms_cleared, room_depth, encounter_count)
	var normalized_reward := pending_room_reward.strip_edges().to_lower()
	if normalized_reward == "boon":
		return {
			"run_cleared": false,
			"open_reward_mode": "boon",
			"spawn_doors": false,
			"pending_room_reward": "none",
			"rooms_cleared": int(progress["rooms_cleared"]),
			"room_depth": int(progress["room_depth"]),
			"boss_unlocked": bool(progress["boss_unlocked"])
		}
	if normalized_reward == "hard_reward":
		return {
			"run_cleared": false,
			"open_reward_mode": "hard_reward",
			"spawn_doors": false,
			"pending_room_reward": "none",
			"rooms_cleared": int(progress["rooms_cleared"]),
			"room_depth": int(progress["room_depth"]),
			"boss_unlocked": bool(progress["boss_unlocked"])
		}

	return {
		"run_cleared": false,
		"open_reward_mode": "",
		"spawn_doors": true,
		"pending_room_reward": "none",
		"rooms_cleared": int(progress["rooms_cleared"]),
		"room_depth": int(progress["room_depth"]),
		"boss_unlocked": bool(progress["boss_unlocked"])
	}

func build_door_options(boss_unlocked: bool, _room_depth: int, door_distance_from_center: float, route_options: Array[Dictionary]) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if boss_unlocked:
		options.append({
			"label": "Boss",
			"position": Vector2(0.0, -40.0),
			"color": Color(0.95, 0.18, 0.22, 0.98),
			"kind": "boss",
			"icon": "boss",
			"profile": {}
		})
		return options

	var positions := [Vector2(-door_distance_from_center, -40.0), Vector2(door_distance_from_center, -40.0)]
	for i in range(mini(route_options.size(), positions.size())):
		var option := route_options[i].duplicate(true)
		option["position"] = positions[i]
		options.append(option)
	return options

func find_used_door(player_position: Vector2, door_options: Array[Dictionary], door_use_radius: float) -> Dictionary:
	for door in door_options:
		var door_pos: Vector2 = door["position"]
		if player_position.distance_to(door_pos) > door_use_radius:
			continue
		return {
			"used": true,
			"door": door
		}
	return {
		"used": false,
		"door": {}
	}

func resolve_chosen_door(door: Dictionary) -> Dictionary:
	var kind := String(door.get("kind", "encounter"))
	if kind == "boss":
		return {"action": "boss"}
	if kind == "rest":
		return {"action": "rest"}
	return {
		"action": "encounter",
		"profile": door.get("profile", {}),
		"reward": String(door.get("reward", "none"))
	}
