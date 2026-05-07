extends RefCounted
class_name WorldMultiplayerSyncState

var pending_door_sync_payload: Dictionary = {}
var pending_chosen_door: Dictionary = {}
var pending_chosen_progress_state: Dictionary = {}
var awaiting_authoritative_door_choice: bool = false
var joiner_awaiting_initial_sync: bool = false
var pending_spawn_sync_payload: Dictionary = {}
var pending_objective_spawn_sync_payloads: Array[Dictionary] = []
var pending_boss_spawn_sync_payload: Dictionary = {}
var current_room_sync_id: int = 0
var last_applied_spawn_sync_id: int = 0
var last_objective_cleared_room_sync_id: int = 0
var last_room_clear_processed_sync_id: int = -1

func reset_for_new_run() -> void:
	pending_door_sync_payload.clear()
	pending_chosen_door.clear()
	pending_chosen_progress_state.clear()
	awaiting_authoritative_door_choice = false
	joiner_awaiting_initial_sync = false
	pending_spawn_sync_payload.clear()
	pending_objective_spawn_sync_payloads.clear()
	pending_boss_spawn_sync_payload.clear()
	current_room_sync_id = 0
	last_applied_spawn_sync_id = 0
	last_objective_cleared_room_sync_id = 0
	last_room_clear_processed_sync_id = -1

func clear_pending_spawn_payloads() -> void:
	pending_spawn_sync_payload.clear()
	pending_objective_spawn_sync_payloads.clear()
	pending_boss_spawn_sync_payload.clear()

func clear_pending_chosen_door_sync() -> void:
	pending_chosen_door.clear()
	pending_chosen_progress_state.clear()

func clear_authoritative_door_wait() -> void:
	awaiting_authoritative_door_choice = false

func begin_authoritative_door_wait() -> void:
	awaiting_authoritative_door_choice = true

func begin_next_room_sync() -> void:
	current_room_sync_id += 1
	pending_door_sync_payload.clear()
	clear_pending_spawn_payloads()

func begin_room_transition(should_clear_pending_spawn_payloads: bool) -> void:
	current_room_sync_id += 1
	clear_authoritative_door_wait()
	pending_door_sync_payload.clear()
	clear_pending_chosen_door_sync()
	if should_clear_pending_spawn_payloads:
		clear_pending_spawn_payloads()

func consume_pending_door_sync_payload() -> Dictionary:
	if pending_door_sync_payload.is_empty():
		return {}
	var payload := pending_door_sync_payload.duplicate(true) as Dictionary
	pending_door_sync_payload.clear()
	return payload

func consume_pending_chosen_door_sync() -> Dictionary:
	if pending_chosen_door.is_empty():
		return {}
	var payload := {
		"chosen_door": pending_chosen_door.duplicate(true),
		"progress_state": pending_chosen_progress_state.duplicate(true)
	}
	clear_pending_chosen_door_sync()
	return payload

func consume_pending_spawn_sync_payload() -> Dictionary:
	if pending_spawn_sync_payload.is_empty():
		return {}
	var payload := pending_spawn_sync_payload.duplicate(true) as Dictionary
	pending_spawn_sync_payload.clear()
	return payload

func has_pending_spawn_sync_payload() -> bool:
	return not pending_spawn_sync_payload.is_empty()

func peek_pending_spawn_sync_payload() -> Dictionary:
	return pending_spawn_sync_payload

func queue_pending_spawn_sync_payload_if_newer(payload: Dictionary, source_room_sync_id: int) -> void:
	var pending_sync_id := int(pending_spawn_sync_payload.get("room_sync_id", 0))
	if source_room_sync_id >= pending_sync_id:
		pending_spawn_sync_payload = payload

func consume_pending_boss_spawn_sync_payload() -> Dictionary:
	if pending_boss_spawn_sync_payload.is_empty():
		return {}
	var payload := pending_boss_spawn_sync_payload.duplicate(true) as Dictionary
	pending_boss_spawn_sync_payload.clear()
	return payload

func has_pending_boss_spawn_sync_payload() -> bool:
	return not pending_boss_spawn_sync_payload.is_empty()

func peek_pending_boss_spawn_sync_payload() -> Dictionary:
	return pending_boss_spawn_sync_payload

func queue_pending_boss_spawn_sync_payload_if_newer(payload: Dictionary, source_room_sync_id: int) -> void:
	var pending_sync_id := int(pending_boss_spawn_sync_payload.get("room_sync_id", 0))
	if source_room_sync_id >= pending_sync_id:
		pending_boss_spawn_sync_payload = payload

func apply_spawn_sync_id(source_room_sync_id: int) -> void:
	if source_room_sync_id <= 0:
		return
	last_applied_spawn_sync_id = maxi(last_applied_spawn_sync_id, source_room_sync_id)
	current_room_sync_id = maxi(current_room_sync_id, source_room_sync_id)

func is_current_room_clear_processed() -> bool:
	return last_room_clear_processed_sync_id == current_room_sync_id

func mark_current_room_clear_processed() -> void:
	last_room_clear_processed_sync_id = current_room_sync_id

func mark_objective_cleared_for_current_room() -> void:
	last_objective_cleared_room_sync_id = current_room_sync_id

func has_pending_objective_spawn_sync_payloads() -> bool:
	return not pending_objective_spawn_sync_payloads.is_empty()

func get_pending_objective_spawn_sync_payloads() -> Array[Dictionary]:
	return pending_objective_spawn_sync_payloads

func set_pending_objective_spawn_sync_payloads(payloads: Array[Dictionary]) -> void:
	pending_objective_spawn_sync_payloads = payloads

func enqueue_pending_objective_spawn_sync_payload(payload: Dictionary) -> void:
	pending_objective_spawn_sync_payloads.append(payload)

func clear_pending_objective_spawn_sync_payloads() -> void:
	pending_objective_spawn_sync_payloads.clear()
