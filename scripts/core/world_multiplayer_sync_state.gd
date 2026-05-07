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
