extends SceneTree

const STORE := preload("res://scripts/core/active_run_checkpoint_store.gd")
const CONTEXT := preload("res://scripts/run_context.gd")

class FaultStore extends "res://scripts/core/active_run_checkpoint_store.gd":
	var denied_read: String = ""
	var denied_write: String = ""
	var partial_write: String = ""
	var invalid_verification: String = ""
	var denied_remove: Array[String] = []
	var written_paths: Array[String] = []
	var recovery_reads_before_failure: int = -1
	var recovery_read_count: int = 0
	func _open_file(path: String, mode: int) -> FileAccess:
		if (mode == FileAccess.READ and path == denied_read) or (mode == FileAccess.WRITE and path == denied_write):
			return null
		return super._open_file(path, mode)
	func _write_record(path: String, payload: Dictionary) -> bool:
		written_paths.append(path)
		if path == partial_write:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(PackedByteArray([1, 2]))
			file.close()
			return false
		return super._write_record(path, payload)
	func _read_record(path: String) -> Dictionary:
		if path == _recovery_path():
			recovery_read_count += 1
			if recovery_reads_before_failure >= 0 and recovery_read_count > recovery_reads_before_failure:
				return {"status": READ_FAILED}
		if path == invalid_verification and written_paths.has(path):
			return {"status": INVALID}
		return super._read_record(path)
	func _remove_file(path: String) -> bool:
		return false if path in denied_remove else super._remove_file(path)

class Context extends "res://scripts/run_context.gd":
	var editor_mode: bool = false
	func _ready() -> void:
		pass
	func _is_editor_session() -> bool:
		return editor_mode

var checks: int = 0
var failures: Array[String] = []
var serial: int = 0
var paths: Array[String] = []
var before := {"version": 1, "room_depth": 4, "marker": "old", "vector": Vector2(15, 24), "color": Color.AQUA, "nested": [{"power": "razor_wind", "level": 2}]}
var after := {"version": 1, "room_depth": 5, "marker": "new", "doors": [{"pos": Vector2(240, 0)}]}

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _new_store() -> FaultStore:
	serial += 1
	var path := "user://checkpoint-case-%d.save" % serial
	paths.append(path)
	var store := FaultStore.new()
	store.save_path = path
	store.save_version = 1
	return store

func _payload(snapshot: Dictionary) -> Dictionary:
	return {"version": 1, "saved_at_unix": 123456, "editor_session": false, "snapshot": snapshot.duplicate(true)}

func _legacy_write(path: String, snapshot: Dictionary) -> void:
	# Exact v0.6.3 envelope and direct primary-only publication.
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(_payload(snapshot))
	file.close()

func _raw_write(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(value)
	file.close()

func _torn_primary(store: STORE) -> void:
	var file := FileAccess.open(store.save_path, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([2, 0]))
	file.close()

func _fresh_read(store: STORE) -> Dictionary:
	return STORE.new(store.save_path, 1).load_snapshot()

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Checkpoint durability requires disposable user data")
		quit(1)
		return
	_test_compatibility()
	_test_write_failures()
	_test_recovery_states()
	_test_clear_failures()
	_test_context_paths()
	for path in paths:
		for suffix in ["", ".tmp", ".bak"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("[OK] Active run checkpoint store: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_compatibility() -> void:
	var store := _new_store()
	check(not store.has_saved_run() and store.last_status == STORE.MISSING, "Absent primary is a validated missing save")
	_legacy_write(store.save_path, before)
	check(store.load_snapshot() == before and store.last_status == STORE.OK_STATUS, "Existing version-1 public checkpoints retain native Variant values")
	check(store.save_snapshot(after), "Modern publication succeeds over an existing public checkpoint")
	var file := FileAccess.open(store.save_path, FileAccess.READ)
	var legacy_read: Dictionary = file.get_var()
	file.close()
	check(legacy_read.version == 1 and legacy_read.snapshot == after, "Unchanged public get_var reader reads the newly published checkpoint")
	check(not FileAccess.file_exists(store._recovery_path()) and not FileAccess.file_exists(store._temporary_path()), "Successful save retires recovery and temporary files")
	_legacy_write(store.save_path, before)
	check(store.load_snapshot() == before, "Later public primary-only writes take priority")
	_legacy_write(store._recovery_path(), after)
	_legacy_write(store._temporary_path(), after)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.save_path))
	check(_fresh_read(store).is_empty(), "Public primary-only clear never resurrects leftover recovery or staging")
	check(not store.has_saved_run() and store.last_status == STORE.MISSING, "Temporary-only and backup-only files do not advertise Continue")
	for value in [123, {"version": 1, "snapshot": []}, {"version": 1, "snapshot": {}}]:
		_raw_write(store.save_path, value)
		check(not store.has_saved_run() and store.last_status == STORE.INVALID, "Malformed envelope cannot advertise a valid checkpoint")
	_raw_write(store.save_path, {"version": 999, "snapshot": before})
	_legacy_write(store._recovery_path(), before)
	var future_hash := FileAccess.get_sha256(store.save_path)
	check(store.load_snapshot().is_empty() and store.last_status == STORE.UNSUPPORTED and FileAccess.get_sha256(store.save_path) == future_hash, "Future-format primary is preserved without falling back or rewriting")

func _test_write_failures() -> void:
	for stage in ["stage_open", "stage_partial", "stage_verify", "backup_open", "backup_partial", "primary_open", "primary_partial", "primary_verify"]:
		var store := _new_store()
		_legacy_write(store.save_path, before)
		var original_hash := FileAccess.get_sha256(store.save_path)
		match stage:
			"stage_open": store.denied_write = store._temporary_path()
			"stage_partial": store.partial_write = store._temporary_path()
			"stage_verify": store.invalid_verification = store._temporary_path()
			"backup_open": store.denied_write = store._recovery_path()
			"backup_partial": store.partial_write = store._recovery_path()
			"primary_open": store.denied_write = store.save_path
			"primary_partial": store.partial_write = store.save_path
			"primary_verify": store.invalid_verification = store.save_path
		check(not store.save_snapshot(after), stage + ": injected operation failure is reported")
		var restored := _fresh_read(store)
		check(restored == (after if stage == "primary_verify" else before), stage + ": restart resolves a complete verified checkpoint")
		if stage not in ["primary_partial", "primary_verify"]:
			check(FileAccess.get_sha256(store.save_path) == original_hash, stage + ": prepublication failure keeps primary bytes unchanged")
	var locked := _new_store()
	_legacy_write(locked.save_path, after)
	_legacy_write(locked._recovery_path(), before)
	locked.denied_read = locked.save_path
	check(locked.load_snapshot().is_empty() and locked.last_status == STORE.READ_FAILED, "Unreadable primary is not mistaken for corrupt older data")
	check(not locked.save_snapshot(before) and _fresh_read(locked) == after, "A failed read cannot overwrite a possibly newer primary")
	for recovery_status in [STORE.READ_FAILED, STORE.UNSUPPORTED]:
		var unknown_recovery := _new_store()
		_torn_primary(unknown_recovery)
		_legacy_write(unknown_recovery._recovery_path(), before)
		if recovery_status == STORE.READ_FAILED:
			# Deny reads only: the regression was a destructive successful write.
			unknown_recovery.denied_read = unknown_recovery._recovery_path()
		else:
			_raw_write(unknown_recovery._recovery_path(), {"version": 999, "snapshot": before})
		var primary_hash := FileAccess.get_sha256(unknown_recovery.save_path)
		var recovery_hash := FileAccess.get_sha256(unknown_recovery._recovery_path())
		check(unknown_recovery.load_snapshot().is_empty() and unknown_recovery.last_status == recovery_status, recovery_status + ": unknown sole recovery status survives resolution of a torn primary")
		check(not unknown_recovery.save_snapshot(after) and unknown_recovery.last_status == recovery_status, recovery_status + ": saving refuses to replace an unknown sole recovery")
		check(FileAccess.get_sha256(unknown_recovery.save_path) == primary_hash and FileAccess.get_sha256(unknown_recovery._recovery_path()) == recovery_hash, recovery_status + ": failed save preserves both committed files byte for byte")
		check(not unknown_recovery.written_paths.has(unknown_recovery.save_path) and not unknown_recovery.written_paths.has(unknown_recovery._recovery_path()), recovery_status + ": no primary or recovery write is attempted")
		if recovery_status == STORE.READ_FAILED:
			check(_fresh_read(unknown_recovery) == before, "Releasing the read failure makes the untouched sole checkpoint recoverable again")
	var intermittent := _new_store()
	_torn_primary(intermittent)
	_legacy_write(intermittent._recovery_path(), before)
	var sole_copy_hash := FileAccess.get_sha256(intermittent._recovery_path())
	intermittent.recovery_reads_before_failure = 1
	intermittent.partial_write = intermittent._recovery_path()
	intermittent.denied_write = intermittent.save_path
	check(not intermittent.save_snapshot(after), "Publication may fail after the sole recovery was resolved")
	check(FileAccess.get_sha256(intermittent._recovery_path()) == sole_copy_hash and not intermittent.written_paths.has(intermittent._recovery_path()), "A verified sole recovery is never reread and rewritten when its next read would fail")
	check(_fresh_read(intermittent) == before, "A late read failure cannot destroy the only complete checkpoint")
	var first := _new_store()
	_legacy_write(first._recovery_path(), before)
	first.denied_remove = [first._recovery_path()]
	first.denied_write = first._recovery_path()
	check(not first.save_snapshot(after) and not FileAccess.file_exists(first.save_path), "First save aborts if stale recovery cannot be neutralized before primary creation")
	check(_fresh_read(first).is_empty(), "Failed first save cannot turn a baseline clear into an older resumable run")

func _test_recovery_states() -> void:
	var store := _new_store()
	_legacy_write(store.save_path, after)
	_legacy_write(store._recovery_path(), before)
	check(store.load_snapshot() == after and not FileAccess.file_exists(store._recovery_path()), "Valid primary wins and retires stale recovery on read")
	_torn_primary(store)
	_legacy_write(store._recovery_path(), before)
	check(store.load_snapshot() == before and store.last_status == STORE.RECOVERED, "Interrupted overwrite recovers only an existing invalid primary")
	check(not FileAccess.file_exists(store._recovery_path()) and _fresh_read(store) == before, "Verified repair retires recovery before a later public clear")
	_torn_primary(store)
	_legacy_write(store._recovery_path(), before)
	var backup_hash := FileAccess.get_sha256(store._recovery_path())
	store.denied_write = store._recovery_path()
	store.partial_write = store.save_path
	check(not store.save_snapshot(after) and FileAccess.get_sha256(store._recovery_path()) == backup_hash, "Matching sole recovery is never truncated during a later failed publication")
	check(_fresh_read(store) == before, "Only valid copy survives repeated publication failure")
	var cleanup := _new_store()
	_legacy_write(cleanup.save_path, before)
	cleanup.denied_remove = [cleanup._recovery_path(), cleanup._temporary_path()]
	check(cleanup.save_snapshot(after), "Deletion failure can retire recovery through a verified clear record")
	var retired := cleanup._read_record(cleanup._recovery_path())
	check(retired.status == STORE.CLEARED and _fresh_read(cleanup) == after, "Retired recovery contains no old run while valid primary stays authoritative")
	var unresolved := _new_store()
	_legacy_write(unresolved.save_path, after)
	_legacy_write(unresolved._recovery_path(), before)
	unresolved.denied_remove = [unresolved._recovery_path()]
	unresolved.denied_write = unresolved._recovery_path()
	check(unresolved.load_snapshot() == after and unresolved.last_status == STORE.CLEANUP_FAILED, "Unresolved recovery cleanup is reported without discarding the valid primary")

func _test_clear_failures() -> void:
	var store := _new_store()
	_legacy_write(store.save_path, before)
	_legacy_write(store._recovery_path(), after)
	store.denied_remove = [store._recovery_path(), store._temporary_path()]
	store.denied_write = store._recovery_path()
	check(store.clear_snapshot() and store.last_status == STORE.CLEARED and not FileAccess.file_exists(store.save_path), "Primary deletion durably clears even when all recovery cleanup is denied")
	check(_fresh_read(store).is_empty(), "A later process does not restore failed-clear leftovers")
	var tombstone := _new_store()
	_legacy_write(tombstone.save_path, before)
	tombstone.denied_remove = [tombstone.save_path, tombstone._recovery_path(), tombstone._temporary_path()]
	check(tombstone.clear_snapshot() and tombstone.last_status == STORE.CLEARED, "Denied deletion falls back to a verified compatible clear record")
	check(_fresh_read(tombstone).is_empty(), "Clear record suppresses leftover recovery after restart")
	var file := FileAccess.open(tombstone.save_path, FileAccess.READ)
	var legacy: Dictionary = file.get_var()
	file.close()
	check(legacy.snapshot.is_empty(), "Public reader sees no resumable run in a clear record")
	check(tombstone.save_snapshot(after) and _fresh_read(tombstone) == after, "New run safely replaces a prior clear record")
	var interrupted_clear := _new_store()
	_legacy_write(interrupted_clear.save_path, before)
	interrupted_clear.denied_remove = [interrupted_clear.save_path]
	interrupted_clear.partial_write = interrupted_clear.save_path
	check(interrupted_clear.clear_snapshot() and interrupted_clear.last_status == STORE.CLEARED, "A torn clear publication still suppresses the old run through its verified cleared recovery")
	check(_fresh_read(interrupted_clear).is_empty(), "Restart repairs a torn clear into an empty record instead of restoring the defeated run")
	var denied := _new_store()
	_legacy_write(denied.save_path, before)
	denied.denied_remove = [denied.save_path]
	denied.denied_write = denied.save_path
	check(not denied.clear_snapshot() and denied.last_status == STORE.CLEAR_FAILED, "Clear failure is explicit while a valid primary still exists")
	check(_fresh_read(denied) == before, "Writing only a recovery tombstone does not falsely claim a valid primary was cleared")

func _test_context_paths() -> void:
	var context := Context.new()
	root.add_child(context)
	context.clear_active_run()
	check(context.save_active_run(before), "RunContext delegates the normal path through checked persistence")
	context.editor_mode = true
	context.clear_active_run()
	check(context.save_active_run(after) and context.load_active_run() == after, "Editor checkpoint retains its separate existing filename")
	context.clear_active_run()
	context.editor_mode = false
	check(context.load_active_run() == before, "Clearing editor data cannot clear the normal checkpoint")
	check(context.clear_active_run() and not context.has_saved_run() and context.get_active_run_status() == STORE.MISSING, "Public RunContext API exposes validated availability and clear result")
	context.free()
