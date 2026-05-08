extends RefCounted
class_name RunHistoryStore

const STORAGE_PATH := "user://run_history.json"
const MAX_RECORDS := 100

## Append a run summary dict to local history and prune to cap.
## Returns true on success.
static func append(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	var records := load_all()
	var run_id := String(summary.get("run_id", "")).strip_edges()
	if not run_id.is_empty():
		for i in range(records.size() - 1, -1, -1):
			var existing := records[i] as Dictionary
			if String(existing.get("run_id", "")).strip_edges() == run_id:
				records.remove_at(i)
	records.push_front(summary.duplicate(true))
	if records.size() > MAX_RECORDS:
		records.resize(MAX_RECORDS)
	return _save(records)

## Load all records newest-first. Returns empty array on failure.
static func load_all() -> Array:
	if not FileAccess.file_exists(STORAGE_PATH):
		return []
	var file := FileAccess.open(STORAGE_PATH, FileAccess.READ)
	if file == null:
		return []
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		return []
	var data: Variant = json.data
	if not (data is Array):
		return []
	return data as Array

## Clear all local history. Returns true on success.
static func clear_all() -> bool:
	return _save([])

static func _save(records: Array) -> bool:
	var text := JSON.stringify(records)
	if text.is_empty():
		return false
	var file := FileAccess.open(STORAGE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[RunHistoryStore] Failed to open %s for writing" % STORAGE_PATH)
		return false
	file.store_string(text)
	return true
