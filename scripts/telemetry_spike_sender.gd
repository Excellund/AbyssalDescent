extends Node

signal probe_completed(success: bool, http_code: int, error_message: String, response_preview: String)

var _request: HTTPRequest

func begin_probe(config: Dictionary) -> void:
	var endpoint := String(config.get("endpoint", "")).strip_edges()
	if endpoint.is_empty():
		probe_completed.emit(false, 0, "missing_endpoint", "")
		return
	if is_instance_valid(_request):
		_request.queue_free()
	_request = HTTPRequest.new()
	add_child(_request)
	_request.timeout = clampf(float(config.get("timeout_seconds", 8.0)), 3.0, 20.0)
	_request.request_completed.connect(_on_request_completed, CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var api_key := String(config.get("api_key", "")).strip_edges()
	if not api_key.is_empty():
		headers.append("apikey: %s" % api_key)
		headers.append("Authorization: Bearer %s" % api_key)
		headers.append("Prefer: return=representation")
	var payload := {
		"probe_type": "telemetry_server_support",
		"client_unix": int(Time.get_unix_time_from_system()),
		"game_version": String(config.get("game_version", "dev")),
		"platform": OS.get_name(),
		"debug_build": OS.is_debug_build(),
		"run_summary": {
			"max_depth": 0,
			"rooms_cleared": 0,
			"outcome": "probe"
		}
	}
	var body := JSON.stringify(payload)
	var request_error := _request.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	if request_error != OK:
		probe_completed.emit(false, 0, "request_start_failed_%d" % request_error, "")
		_request.queue_free()
		_request = null

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var response_text := body.get_string_from_utf8()
	var response_preview := response_text
	if response_preview.length() > 300:
		response_preview = response_preview.substr(0, 300)
	var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	var error_message := "ok"
	if not success:
		error_message = "http_request_result_%d" % result
	probe_completed.emit(success, response_code, error_message, response_preview)
	if is_instance_valid(_request):
		_request.queue_free()
	_request = null
