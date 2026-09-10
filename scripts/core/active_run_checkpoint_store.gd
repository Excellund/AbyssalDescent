extends RefCounted
## Recover interrupted overwrites without reviving a primary cleared by an older
## build. Temporary files are never saves; a missing primary always means cleared.

const OK_STATUS := "ok"
const RECOVERED := "recovered"
const MISSING := "missing"
const CLEARED := "cleared"
const INVALID := "invalid"
const UNSUPPORTED := "unsupported"
const READ_FAILED := "read_failed"
const WRITE_FAILED := "write_failed"
const CLEAR_FAILED := "clear_failed"
const CLEANUP_FAILED := "cleanup_failed"

var save_path: String
var save_version: int
var last_status: String = MISSING

func _init(path: String = "", version: int = 1) -> void:
	save_path = path
	save_version = version

func has_saved_run() -> bool:
	return not load_snapshot().is_empty()

func load_snapshot() -> Dictionary:
	var record := _resolve_record()
	last_status = String(record.status)
	if last_status not in [OK_STATUS, CLEARED]:
		return {}
	var payload: Dictionary = record.payload
	if bool(record.get("recovered", false)):
		# Keep the only valid recovery copy until repair has been verified.
		if _write_record(save_path, payload):
			_retire_recovery()
		last_status = RECOVERED if record.status == OK_STATUS else CLEARED
	elif not _retire_recovery() and record.status == OK_STATUS:
		last_status = CLEANUP_FAILED
	return (payload.snapshot as Dictionary).duplicate(true)

func save_snapshot(snapshot: Dictionary, editor_session: bool = false) -> bool:
	last_status = WRITE_FAILED
	if snapshot.is_empty():
		return false
	var payload := {"version": save_version, "saved_at_unix": int(Time.get_unix_time_from_system()), "editor_session": editor_session, "snapshot": snapshot.duplicate(true)}
	if not _write_record(_temporary_path(), payload):
		return false
	var current := _resolve_record()
	if current.status in [READ_FAILED, UNSUPPORTED]:
		last_status = String(current.status)
		return false
	# A first save must neutralize any old recovery before creating its primary.
	# A resolved recovery is already verified: never reread and risk replacing
	# that sole good copy. An intact primary can safely prepare its own backup.
	var previous: Dictionary = current.get("payload", _cleared_record())
	if not bool(current.get("recovered", false)) and not _prepare_recovery(previous):
		return false
	# Godot's Windows rename removes an existing destination before moving.
	# Keep this directory entry present, with a verified recovery copy alongside.
	if not _write_record(save_path, payload):
		return false
	if not _retire_recovery():
		last_status = CLEANUP_FAILED
		return false
	last_status = OK_STATUS
	return true

func clear_snapshot() -> bool:
	# Older builds clear just this file. Its absence is authoritative even when
	# auxiliary cleanup fails, so never recreate it from an orphaned backup.
	if not _file_exists(save_path) or _remove_file(save_path):
		_retire_recovery()
		last_status = CLEARED
		return true
	# Some permissions allow writing but deny deletion. A compatible empty
	# snapshot suppresses recovery without depending on auxiliary-file removal.
	var cleared := _cleared_record()
	if _prepare_recovery(cleared) and _write_record(save_path, cleared):
		_retire_recovery()
		last_status = CLEARED
		return true
	var remaining := _resolve_record()
	if remaining.status in [MISSING, CLEARED]:
		last_status = CLEARED
		return true
	last_status = CLEAR_FAILED
	return false

func _resolve_record() -> Dictionary:
	var primary := _read_record(save_path)
	if primary.status == MISSING:
		_retire_recovery()
		return primary
	# A locked or future-format primary may contain newer data. Never replace it
	# with an older copy merely because this reader cannot inspect it.
	if primary.status != INVALID:
		return primary
	var recovery := _read_record(_recovery_path())
	# An invalid primary may leave this as the sole complete checkpoint. An
	# unreadable or future-format recovery is unknown, not permission to erase it.
	if recovery.status in [READ_FAILED, UNSUPPORTED]:
		return recovery
	if recovery.status in [OK_STATUS, CLEARED]:
		recovery["recovered"] = true
		return recovery
	return primary

func _prepare_recovery(payload: Dictionary) -> bool:
	var existing := _read_record(_recovery_path())
	if existing.status in [OK_STATUS, CLEARED] and existing.payload == payload:
		return true
	return _write_record(_recovery_path(), payload)

func _retire_recovery() -> bool:
	_remove_file(_temporary_path())
	if not _file_exists(_recovery_path()) or _remove_file(_recovery_path()):
		return true
	# A cleanup failure must not leave a long-lived older run as recovery.
	return _prepare_recovery(_cleared_record())

func _cleared_record() -> Dictionary:
	return {"version": save_version, "saved_at_unix": 0, "editor_session": false, "snapshot": {}, "cleared": true}

func _temporary_path() -> String:
	return save_path + ".tmp"

func _recovery_path() -> String:
	return save_path + ".bak"

func _file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)

func _open_file(path: String, mode: int) -> FileAccess:
	return FileAccess.open(path, mode)

func _remove_file(path: String) -> bool:
	return not _file_exists(path) or DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK

func _write_record(path: String, payload: Dictionary) -> bool:
	var file := _open_file(path, FileAccess.WRITE)
	if file == null:
		return false
	var stored := file.store_var(payload)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if not stored or write_error != OK:
		return false
	var verified := _read_record(path)
	return verified.status in [OK_STATUS, CLEARED] and verified.payload == payload

func _read_record(path: String) -> Dictionary:
	if not _file_exists(path):
		return {"status": MISSING}
	var file := _open_file(path, FileAccess.READ)
	if file == null:
		return {"status": READ_FAILED}
	# store_var prefixes its encoded Variant with a 32-bit byte count. Reject a
	# torn frame before decoding, and reject trailing data as an incomplete write.
	if file.get_length() < 4:
		file.close()
		return {"status": INVALID}
	var byte_count := file.get_32()
	if byte_count != file.get_length() - 4:
		file.close()
		return {"status": INVALID}
	file.seek(0)
	var raw: Variant = file.get_var()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return {"status": READ_FAILED}
	if not (raw is Dictionary) or not (raw.get("version") is int):
		return {"status": INVALID}
	if int(raw.version) != save_version:
		return {"status": UNSUPPORTED}
	if not (raw.get("snapshot") is Dictionary):
		return {"status": INVALID}
	if raw.snapshot.is_empty():
		if raw.get("cleared") is bool and raw.cleared:
			return {"status": CLEARED, "payload": raw}
		return {"status": INVALID}
	return {"status": OK_STATUS, "payload": raw}
