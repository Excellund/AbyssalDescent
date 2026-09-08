extends SceneTree

const MODEL := preload("res://scripts/core/leaderboard_entry_model.gd")
const TELEMETRY := preload("res://scripts/run_telemetry_store.gd")
const QUEUE := preload("res://scripts/leaderboard_upload_queue.gd")
const HISTORY := preload("res://scripts/core/run_history_store.gd")

class IsolatedUploader extends "res://scripts/leaderboard_uploader.gd":
	var credential_reads := 0
	func _is_upload_enabled() -> bool:
		return true
	func _submit_endpoint() -> String:
		return "https://upload-must-not-run.invalid/rpc/submit_leaderboard_run"
	func _upload_api_key() -> String:
		credential_reads += 1
		return ""

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run_tests")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _release_clear() -> Dictionary:
	return {
		"run_id": "isolated-release-clear", "player_uuid": "isolated-player",
		"game_version": "0.7.0", "leaderboard_patch_key": "0.7",
		"outcome": "clear", "is_debug": false, "difficulty_tier": 1,
		"duration_seconds": 600, "character_id": "bastion",
	}

func _run_tests() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Upload regression tests require an isolated user directory")
		quit(1)
		return
	var release := _release_clear()
	_check(MODEL.is_submission_eligible(release), "Release clears remain leaderboard eligible")
	_check(TELEMETRY.is_upload_payload_eligible(release), "Release telemetry remains eligible")
	for version in ["dev", "dev-20260908-123456789-test", " DEV-CONTENT-1 ", "0.7.0-dev.1", "0.7.0-debug", ""]:
		var summary := release.duplicate(true)
		summary["game_version"] = version
		_check(not TELEMETRY.is_upload_payload_eligible(summary), "Telemetry excludes " + version)
		_check(not MODEL.is_submission_eligible(summary), "Leaderboard excludes " + version)
		_check(MODEL.build_submission_rpc_body(summary).is_empty(), "No submission payload for " + version)
	var missing_version := release.duplicate(true)
	missing_version.erase("game_version")
	_check(not MODEL.is_submission_eligible(missing_version), "Missing versions cannot inherit the current release version")
	var debug_clear := release.duplicate(true)
	debug_clear["is_debug"] = true
	_check(not MODEL.is_submission_eligible(debug_clear), "Debug clears remain ineligible on release builds")
	for outcome in ["death", "quit", "abandon"]:
		var summary := release.duplicate(true)
		summary["outcome"] = outcome
		_check(not MODEL.is_submission_eligible(summary), "Non-clear outcome remains ineligible: " + outcome)
	_test_queued_payloads(release)
	print("[OK] Dev upload eligibility: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_queued_payloads(release: Dictionary) -> void:
	QUEUE.save_queue(QUEUE._default_queue())
	var dev_summary := release.duplicate(true)
	dev_summary["run_id"] = "isolated-dev-clear"
	dev_summary["game_version"] = "dev-content-test"
	_check(HISTORY.append(dev_summary), "Dev summaries remain available in local history")
	var history_hash := FileAccess.get_sha256(HISTORY.STORAGE_PATH)
	var local_run_id := TELEMETRY.start_run({"game_version": "dev-content-test"})
	TELEMETRY.finish_run(local_run_id, "clear", {})
	_check(not TELEMETRY.get_run_by_id(local_run_id).is_empty(), "Dev event collection remains available locally")
	var uploader := IsolatedUploader.new()
	root.add_child(uploader)
	uploader._request = HTTPRequest.new()
	uploader.add_child(uploader._request)
	var queued_debug := release.duplicate(true)
	queued_debug["is_debug"] = true
	var queued_unversioned := release.duplicate(true)
	queued_unversioned.erase("game_version")
	for summary in [dev_summary, queued_debug, queued_unversioned, {"game_version": "dev"}, "malformed"]:
		QUEUE.save_queue({"version": QUEUE.QUEUE_VERSION, "pending": [{"id": "old-invalid-entry", "payload": {"p_run_summary": summary}}]})
		uploader._on_tick()
		_check(QUEUE.pending_count() == 0, "Previously queued invalid submissions are discarded")
		_check(uploader._active_entry_id.is_empty(), "Invalid queues never begin a request")
	_check(uploader.credential_reads == 0, "Invalid payloads are rejected before credentials or HTTP access")
	_check(FileAccess.get_sha256(HISTORY.STORAGE_PATH) == history_hash, "Discarding an upload preserves local history")
	QUEUE.enqueue({"p_run_summary": dev_summary})
	var release_payload := MODEL.build_submission_rpc_body(release)
	QUEUE.enqueue(release_payload)
	uploader._on_tick()
	var remaining := QUEUE.get_ready_entries(2)
	_check(remaining.size() == 1 and remaining[0]["payload"] == release_payload, "An old dev entry does not discard the following valid release")
	uploader.free()
