extends Node

const TELEMETRY_UPLOAD_QUEUE := preload("res://scripts/telemetry_upload_queue.gd")
const TELEMETRY_ENDPOINT_SETTING := "application/config/telemetry_upload_endpoint"
const TELEMETRY_API_KEY_SETTING := "application/config/telemetry_upload_api_key"

var _run_context
var _timer: Timer
var _request: HTTPRequest
var _active_entry_id: String = ""
var _active_attempt_count: int = 0

func initialize(run_context: Node) -> void:
	_run_context = run_context
	if _timer == null:
		_timer = Timer.new()
		_timer.wait_time = 10.0
		_timer.one_shot = false
		_timer.autostart = true
		_timer.timeout.connect(_on_tick)
		add_child(_timer)
	if _request == null:
		_request = HTTPRequest.new()
		_request.timeout = 8.0
		_request.request_completed.connect(_on_request_completed)
		add_child(_request)
	_on_tick()

func enqueue_payload(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	TELEMETRY_UPLOAD_QUEUE.enqueue(payload)
	_on_tick()

func pending_count() -> int:
	return TELEMETRY_UPLOAD_QUEUE.pending_count()

func _on_tick() -> void:
	if _request == null:
		return
	if _active_entry_id != "":
		return
	if not _is_upload_enabled():
		return
	var endpoint := _upload_endpoint()
	if endpoint.is_empty():
		return
	var entries := TELEMETRY_UPLOAD_QUEUE.get_ready_entries(1)
	if entries.is_empty():
		return
	var entry := entries[0]
	var entry_id := String(entry.get("id", ""))
	var payload := entry.get("payload", {}) as Dictionary
	var next_attempt := int(entry.get("attempt_count", 0)) + 1
	if entry_id.is_empty() or payload.is_empty():
		return
	if not _is_payload_uploadable(payload):
		TELEMETRY_UPLOAD_QUEUE.mark_success(entry_id)
		return
	var api_key := _upload_api_key()
	var headers := PackedStringArray(["Content-Type: application/json", "Prefer: return=minimal"])
	if not api_key.is_empty():
		headers.append("apikey: %s" % api_key)
		headers.append("Authorization: Bearer %s" % api_key)
	var body := JSON.stringify(payload)
	_active_entry_id = entry_id
	_active_attempt_count = next_attempt
	var request_error := _request.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	if request_error != OK:
		_mark_retry(entry_id, next_attempt, "request_start_failed_%d" % request_error)
		_active_entry_id = ""
		_active_attempt_count = 0

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _active_entry_id == "":
		return
	var entry_id := _active_entry_id
	var attempt_count := maxi(1, _active_attempt_count)
	_active_entry_id = ""
	_active_attempt_count = 0
	var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if success:
		TELEMETRY_UPLOAD_QUEUE.mark_success(entry_id)
		return
	var response_preview := body.get_string_from_utf8()
	if response_preview.length() > 120:
		response_preview = response_preview.substr(0, 120)
	var error_message := "http_result_%d_code_%d" % [result, response_code]
	if not response_preview.is_empty():
		error_message = "%s_%s" % [error_message, response_preview]
	_mark_retry(entry_id, attempt_count, error_message)

func _mark_retry(entry_id: String, attempt_count: int, error_message: String) -> void:
	var capped_attempt := mini(12, maxi(1, attempt_count))
	var jitter := randi_range(0, 4)
	var delay_seconds := mini(900, int(pow(2.0, float(capped_attempt))) + jitter)
	var next_retry_unix := int(Time.get_unix_time_from_system()) + delay_seconds
	TELEMETRY_UPLOAD_QUEUE.mark_failure(entry_id, capped_attempt, next_retry_unix, error_message)

func _is_upload_enabled() -> bool:
	if _run_context == null:
		return false
	return bool(_run_context.is_telemetry_upload_enabled())

func _upload_endpoint() -> String:
	return String(ProjectSettings.get_setting(TELEMETRY_ENDPOINT_SETTING, "")).strip_edges()

func _upload_api_key() -> String:
	return String(ProjectSettings.get_setting(TELEMETRY_API_KEY_SETTING, "")).strip_edges()

func _is_payload_uploadable(payload: Dictionary) -> bool:
	if bool(payload.get("is_debug", false)):
		return false
	var version := String(payload.get("game_version", "")).strip_edges().to_lower()
	if version.is_empty():
		return false
	if version == "dev":
		return false
	if version.contains("debug"):
		return false
	if version.contains("dev"):
		return false
	return true
