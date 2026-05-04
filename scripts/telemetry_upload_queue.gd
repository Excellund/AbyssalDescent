extends RefCounted

const QUEUE_PATH := "user://telemetry_upload_queue.save"
const QUEUE_VERSION := 1

static func _default_queue() -> Dictionary:
	return {
		"version": QUEUE_VERSION,
		"pending": []
	}

static func _now_unix() -> int:
	return int(Time.get_unix_time_from_system())

static func _new_entry_id() -> String:
	var ticks := Time.get_ticks_usec()
	return "q-%s-%s" % [str(_now_unix()), str(ticks)]

static func load_queue() -> Dictionary:
	if not FileAccess.file_exists(QUEUE_PATH):
		return _default_queue()
	var file := FileAccess.open(QUEUE_PATH, FileAccess.READ)
	if file == null:
		return _default_queue()
	var raw: Variant = file.get_var()
	if not (raw is Dictionary):
		return _default_queue()
	var payload := raw as Dictionary
	if int(payload.get("version", -1)) != QUEUE_VERSION:
		return _default_queue()
	if not (payload.get("pending", []) is Array):
		return _default_queue()
	return payload

static func save_queue(queue_payload: Dictionary) -> bool:
	var file := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(queue_payload)
	return true

static func enqueue(payload: Dictionary) -> String:
	if payload.is_empty():
		return ""
	var queue_payload := load_queue()
	var pending := queue_payload.get("pending", []) as Array
	var entry_id := _new_entry_id()
	pending.append({
		"id": entry_id,
		"created_at_unix": _now_unix(),
		"attempt_count": 0,
		"next_retry_unix": 0,
		"last_error": "",
		"payload": payload.duplicate(true)
	})
	queue_payload["pending"] = pending
	save_queue(queue_payload)
	return entry_id

static func get_ready_entries(max_entries: int = 3) -> Array[Dictionary]:
	var queue_payload := load_queue()
	var pending := queue_payload.get("pending", []) as Array
	var now_unix := _now_unix()
	var ready: Array[Dictionary] = []
	for entry_variant in pending:
		var entry := entry_variant as Dictionary
		if int(entry.get("next_retry_unix", 0)) > now_unix:
			continue
		ready.append(entry.duplicate(true))
		if ready.size() >= maxi(1, max_entries):
			break
	return ready

static func _mutate_pending(mutator: Callable) -> void:
	var queue_payload := load_queue()
	var pending := queue_payload.get("pending", []) as Array
	mutator.callv([pending])
	queue_payload["pending"] = pending
	save_queue(queue_payload)

static func _find_pending_entry_index(pending: Array, entry_id: String) -> int:
	for index in range(pending.size()):
		var entry := pending[index] as Dictionary
		if String(entry.get("id", "")) == entry_id:
			return index
	return -1

static func mark_success(entry_id: String) -> void:
	if entry_id.is_empty():
		return
	_mutate_pending(func(pending: Array) -> void:
		var index := _find_pending_entry_index(pending, entry_id)
		if index >= 0:
			pending.remove_at(index)
	)

static func mark_failure(entry_id: String, attempt_count: int, next_retry_unix: int, error_message: String) -> void:
	if entry_id.is_empty():
		return
	_mutate_pending(func(pending: Array) -> void:
		var index := _find_pending_entry_index(pending, entry_id)
		if index < 0:
			return
		var entry := pending[index] as Dictionary
		entry["attempt_count"] = maxi(1, attempt_count)
		entry["next_retry_unix"] = maxi(_now_unix() + 5, next_retry_unix)
		entry["last_error"] = error_message
	)

static func pending_count() -> int:
	var queue_payload := load_queue()
	var pending := queue_payload.get("pending", []) as Array
	return pending.size()
