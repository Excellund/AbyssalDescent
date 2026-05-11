extends RefCounted

func build_progress_sync_state(state: Dictionary) -> Dictionary:
	return {
		"room_sync_id": int(state.get("room_sync_id", 0)),
		"rooms_cleared": int(state.get("rooms_cleared", 0)),
		"room_depth": int(state.get("room_depth", 0)),
		"phase_two_rooms_cleared": int(state.get("phase_two_rooms_cleared", 0)),
		"phase_three_rooms_cleared": int(state.get("phase_three_rooms_cleared", 0)),
		"boss_unlocked": bool(state.get("boss_unlocked", false)),
		"first_boss_defeated": bool(state.get("first_boss_defeated", false)),
		"second_boss_defeated": bool(state.get("second_boss_defeated", false)),
		"in_boss_room": bool(state.get("in_boss_room", false)),
		"in_second_boss_room": bool(state.get("in_second_boss_room", false)),
		"in_third_boss_room": bool(state.get("in_third_boss_room", false)),
		"choosing_next_room": bool(state.get("choosing_next_room", false))
	}

func sanitize_progress_sync_state(progress_state: Dictionary, context: Dictionary) -> Dictionary:
	if progress_state.is_empty():
		return {}
	var sanitized := progress_state.duplicate(true)
	var current_room_sync_id := int(context.get("current_room_sync_id", 0))
	var incoming_room_sync_id := int(sanitized.get("room_sync_id", current_room_sync_id))
	if bool(context.get("is_stale_room_sync_id", false)):
		sanitized["invalid"] = true
		return sanitized
	if bool(context.get("is_sync_id_too_far_ahead", false)):
		sanitized["invalid"] = true
		return sanitized
	var current_first_boss_defeated := bool(context.get("first_boss_defeated", false))
	var current_second_boss_defeated := bool(context.get("second_boss_defeated", false))
	var incoming_first_boss_defeated := bool(sanitized.get("first_boss_defeated", current_first_boss_defeated))
	var incoming_second_boss_defeated := bool(sanitized.get("second_boss_defeated", current_second_boss_defeated))
	if not incoming_first_boss_defeated:
		incoming_second_boss_defeated = false
	var second_boss_target_depth := int(context.get("second_boss_target_depth", 1))
	var third_boss_target_depth := int(context.get("third_boss_target_depth", second_boss_target_depth))
	var max_depth := second_boss_target_depth
	if incoming_second_boss_defeated:
		max_depth = third_boss_target_depth + 1
	elif incoming_first_boss_defeated:
		max_depth = third_boss_target_depth
	var current_room_depth := int(context.get("room_depth", 0))
	var incoming_room_depth := int(sanitized.get("room_depth", current_room_depth))
	incoming_room_depth = clampi(incoming_room_depth, 0, maxi(1, max_depth))
	var current_rooms_cleared := int(context.get("rooms_cleared", 0))
	if current_rooms_cleared <= 1 and incoming_room_depth > 3:
		sanitized["invalid"] = true
		return sanitized
	var awaiting_authoritative_door_choice := bool(context.get("awaiting_authoritative_door_choice", false))
	var is_authoritative := bool(context.get("is_authoritative", false))
	var is_remote_replica := bool(context.get("is_remote_replica", false))
	var is_joiner_initial_sync := is_authoritative or (is_remote_replica and current_rooms_cleared == 0)
	if incoming_room_depth > current_room_depth + 2 and not awaiting_authoritative_door_choice and not is_joiner_initial_sync:
		sanitized["invalid"] = true
		return sanitized
	var incoming_rooms_cleared := int(sanitized.get("rooms_cleared", current_rooms_cleared))
	incoming_rooms_cleared = clampi(incoming_rooms_cleared, 0, incoming_room_depth)
	var current_phase_two := int(context.get("phase_two_rooms_cleared", 0))
	var current_phase_three := int(context.get("phase_three_rooms_cleared", 0))
	var second_boss_encounter_count := int(context.get("second_boss_encounter_count", 0))
	var third_boss_encounter_count := int(context.get("third_boss_encounter_count", 0))
	var incoming_phase_two := int(sanitized.get("phase_two_rooms_cleared", current_phase_two))
	incoming_phase_two = clampi(incoming_phase_two, 0, maxi(0, second_boss_encounter_count))
	var incoming_phase_three := int(sanitized.get("phase_three_rooms_cleared", current_phase_three))
	incoming_phase_three = clampi(incoming_phase_three, 0, maxi(0, third_boss_encounter_count))
	sanitized["room_sync_id"] = incoming_room_sync_id
	sanitized["rooms_cleared"] = incoming_rooms_cleared
	sanitized["room_depth"] = incoming_room_depth
	sanitized["phase_two_rooms_cleared"] = incoming_phase_two
	sanitized["phase_three_rooms_cleared"] = incoming_phase_three
	sanitized["first_boss_defeated"] = incoming_first_boss_defeated
	sanitized["second_boss_defeated"] = incoming_second_boss_defeated
	sanitized.erase("invalid")
	return sanitized
