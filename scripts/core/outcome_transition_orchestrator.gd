extends RefCounted

const TRANSITION_BOSS_FIRST_CLEAR := "boss_first_clear"
const TRANSITION_BOSS_SECOND_CLEAR := "boss_second_clear"
const TRANSITION_BOSS_THIRD_CLEAR := "boss_third_clear"
const TRANSITION_BOSS_CLEAR := "boss_clear"
const TRANSITION_OUTCOME := "outcome"

const BOSS_CLEAR_HANDLER_FIRST := "finish_first_boss_clear"
const BOSS_CLEAR_HANDLER_SECOND := "finish_second_boss_clear"
const BOSS_CLEAR_HANDLER_THIRD := "finish_third_boss_clear"

func resolve_room_clear_transition(
	room_clear_outcome_coordinator: RefCounted,
	encounter_flow_system: Node,
	state: Dictionary
) -> Dictionary:
	var boss_transition := _resolve_boss_clear_transition(state)
	if not boss_transition.is_empty():
		return boss_transition
	if room_clear_outcome_coordinator == null or not is_instance_valid(encounter_flow_system):
		return {"ok": false}
	var resolve_input := _build_resolve_outcome_input(state)
	var outcome: Dictionary = room_clear_outcome_coordinator.resolve_outcome(
		encounter_flow_system,
		bool(resolve_input.get("in_boss_room", false)),
		int(resolve_input.get("pending_room_reward", 0)),
		int(resolve_input.get("rooms_cleared", 0)),
		int(resolve_input.get("room_depth", 0)),
		int(resolve_input.get("encounter_count", 0))
	)
	if outcome.is_empty():
		return {"ok": false}
	var outcome_state: Dictionary = room_clear_outcome_coordinator.process_outcome(_build_process_outcome_input(state, outcome))
	if not bool(outcome_state.get("ok", false)):
		return {"ok": false}
	return {
		"ok": true,
		"transition_kind": TRANSITION_OUTCOME,
		"should_tick_objective_mutators": true,
		"outcome_state": outcome_state
	}

func _resolve_boss_clear_transition(state: Dictionary) -> Dictionary:
	if bool(state.get("in_second_boss_room", false)):
		return _build_boss_clear_transition(TRANSITION_BOSS_SECOND_CLEAR)
	if bool(state.get("in_third_boss_room", false)):
		return _build_boss_clear_transition(TRANSITION_BOSS_THIRD_CLEAR)
	if bool(state.get("in_boss_room", false)) and not bool(state.get("first_boss_defeated", false)):
		return _build_boss_clear_transition(TRANSITION_BOSS_FIRST_CLEAR)
	return {}

func _build_boss_clear_transition(boss_transition_kind: String) -> Dictionary:
	var metadata := _build_boss_clear_metadata(boss_transition_kind)
	if metadata.is_empty():
		return {}
	return {
		"ok": true,
		"transition_kind": TRANSITION_BOSS_CLEAR,
		"should_tick_objective_mutators": false,
		"boss_clear": metadata
	}

func _build_boss_clear_metadata(boss_transition_kind: String) -> Dictionary:
	match boss_transition_kind:
		TRANSITION_BOSS_FIRST_CLEAR:
			return {
				"boss_stage": 1,
				"boss_id": "warden",
				"banner_title": "Warden Defeated",
				"reward_title": "Claim Warden's Power",
				"reward_mode": "boss",
				"epitaph_boss_id": "warden",
				"completion_handler": BOSS_CLEAR_HANDLER_FIRST
			}
		TRANSITION_BOSS_SECOND_CLEAR:
			return {
				"boss_stage": 2,
				"boss_id": "sovereign",
				"banner_title": "Sovereign Defeated",
				"reward_title": "Claim Sovereign's Power",
				"reward_mode": "boss",
				"epitaph_boss_id": "sovereign",
				"completion_handler": BOSS_CLEAR_HANDLER_SECOND
			}
		TRANSITION_BOSS_THIRD_CLEAR:
			return {
				"boss_stage": 3,
				"boss_id": "lacuna",
				"banner_title": "Run Complete",
				"reward_mode": "terminal",
				"completion_handler": BOSS_CLEAR_HANDLER_THIRD
			}
		_:
			return {}

func _build_resolve_outcome_input(state: Dictionary) -> Dictionary:
	return {
		"in_boss_room": bool(state.get("in_boss_room", false)),
		"pending_room_reward": int(state.get("pending_room_reward", 0)),
		"rooms_cleared": int(state.get("rooms_cleared", 0)),
		"room_depth": int(state.get("room_depth", 0)),
		"encounter_count": int(state.get("encounter_count", 0))
	}

func _build_process_outcome_input(state: Dictionary, outcome: Dictionary) -> Dictionary:
	return {
		"outcome": outcome,
		"in_boss_room": bool(state.get("in_boss_room", false)),
		"endless_mode": bool(state.get("endless_mode", false)),
		"endless_boss_defeated": bool(state.get("endless_boss_defeated", false)),
		"first_boss_defeated": bool(state.get("first_boss_defeated", false)),
		"second_boss_defeated": bool(state.get("second_boss_defeated", false)),
		"can_unlock_second": bool(state.get("can_unlock_second", false)),
		"can_unlock_third": bool(state.get("can_unlock_third", false)),
		"rooms_cleared": int(state.get("rooms_cleared", 0)),
		"room_depth": int(state.get("room_depth", 0)),
		"boss_unlocked": bool(state.get("boss_unlocked", false)),
		"pending_room_reward": int(state.get("pending_room_reward", 0)),
		"choosing_next_room": bool(state.get("choosing_next_room", false))
	}