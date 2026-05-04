extends RefCounted

const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

func resolve_outcome(
	encounter_flow_system: Node,
	in_boss_room: bool,
	pending_room_reward: int,
	rooms_cleared: int,
	room_depth: int,
	encounter_count: int
) -> Dictionary:
	if not is_instance_valid(encounter_flow_system):
		return {}
	var raw_outcome: Variant = encounter_flow_system.resolve_room_cleared(in_boss_room, pending_room_reward, rooms_cleared, room_depth, encounter_count)
	return ENCOUNTER_CONTRACTS.normalize_room_cleared_outcome(raw_outcome)

func process_outcome(state: Dictionary) -> Dictionary:
	var outcome: Dictionary = state.get("outcome", {}) as Dictionary
	if outcome.is_empty():
		return {"ok": false}

	var in_boss_room := bool(state.get("in_boss_room", false))
	var endless_mode := bool(state.get("endless_mode", false))
	var endless_boss_defeated := bool(state.get("endless_boss_defeated", false))
	var first_boss_defeated := bool(state.get("first_boss_defeated", false))
	var second_boss_defeated := bool(state.get("second_boss_defeated", false))
	var can_unlock_second := bool(state.get("can_unlock_second", false))
	var can_unlock_third := bool(state.get("can_unlock_third", false))

	var next_run_cleared := ENCOUNTER_CONTRACTS.outcome_run_cleared(outcome)
	var next_in_boss_room := in_boss_room
	var next_endless_boss_defeated := endless_boss_defeated
	var next_rooms_cleared := int(state.get("rooms_cleared", 0))
	var next_room_depth := int(state.get("room_depth", 0))
	var next_boss_unlocked := bool(state.get("boss_unlocked", false))
	var next_pending_room_reward := int(state.get("pending_room_reward", ENUMS.RewardMode.NONE))
	var next_choosing_next_room := bool(state.get("choosing_next_room", false))
	var open_reward_mode := ENUMS.RewardMode.NONE
	var spawn_doors := false
	var phase_two_increment := 0
	var phase_three_increment := 0
	var show_endless_boss_banner := false

	if next_run_cleared and endless_mode and in_boss_room:
		next_run_cleared = false
		next_in_boss_room = false
		next_endless_boss_defeated = true
		next_rooms_cleared += 1
		next_room_depth += 1
		next_boss_unlocked = false
		next_pending_room_reward = ENUMS.RewardMode.NONE
		spawn_doors = true
		show_endless_boss_banner = true
	else:
		if next_run_cleared:
			next_choosing_next_room = false
		else:
			next_rooms_cleared = ENCOUNTER_CONTRACTS.outcome_rooms_cleared(outcome)
			next_room_depth = ENCOUNTER_CONTRACTS.outcome_room_depth(outcome)
			if second_boss_defeated:
				phase_three_increment = 1
				next_boss_unlocked = can_unlock_third
			elif first_boss_defeated:
				phase_two_increment = 1
				next_boss_unlocked = can_unlock_second
			else:
				next_boss_unlocked = ENCOUNTER_CONTRACTS.outcome_boss_unlocked(outcome)
			if endless_mode and endless_boss_defeated:
				next_boss_unlocked = false
			next_pending_room_reward = ENCOUNTER_CONTRACTS.outcome_pending_room_reward(outcome)
			open_reward_mode = ENCOUNTER_CONTRACTS.outcome_open_reward_mode(outcome)
			if open_reward_mode == ENUMS.RewardMode.NONE and ENCOUNTER_CONTRACTS.outcome_spawn_doors(outcome):
				spawn_doors = true

	return {
		"ok": true,
		"run_cleared": next_run_cleared,
		"in_boss_room": next_in_boss_room,
		"endless_boss_defeated": next_endless_boss_defeated,
		"rooms_cleared": next_rooms_cleared,
		"room_depth": next_room_depth,
		"boss_unlocked": next_boss_unlocked,
		"pending_room_reward": next_pending_room_reward,
		"choosing_next_room": next_choosing_next_room,
		"open_reward_mode": open_reward_mode,
		"spawn_doors": spawn_doors,
		"phase_two_increment": phase_two_increment,
		"phase_three_increment": phase_three_increment,
		"show_endless_boss_banner": show_endless_boss_banner,
		"terminal_run_cleared": next_run_cleared
	}
