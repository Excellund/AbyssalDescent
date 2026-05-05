extends Node

const ROOM_REGISTRY_ENDPOINT_SETTING := "application/config/multiplayer_room_registry_endpoint"
const ROOM_REGISTRY_API_KEY_SETTING := "application/config/multiplayer_room_registry_api_key"
const PUBLIC_IP_LOOKUP_URL_SETTING := "application/config/multiplayer_public_ip_lookup_url"
const DEFAULT_PUBLIC_IP_LOOKUP_URL := "https://api.ipify.org"
const TRANSPORT_TYPE_DIRECT_ENET := "direct_enet"

func is_configured() -> bool:
	return not _room_registry_endpoint().is_empty()

func get_configuration_issues() -> PackedStringArray:
	var issues := PackedStringArray()
	if _room_registry_endpoint().is_empty():
		issues.append("Room registry endpoint is missing in project settings.")
	if _room_registry_api_key().is_empty():
		issues.append("Room registry API key is missing in project settings.")
	return issues

func create_room_registration(host_port: int, provided_session_id: String = "") -> Dictionary:
	var endpoint := _room_registry_endpoint()
	if endpoint.is_empty():
		return {
			"ok": false,
			"message": "Room registry endpoint is not configured.",
			"error_kind": "missing_endpoint"
		}
	if _room_registry_api_key().is_empty():
		return {
			"ok": false,
			"message": "Room registry API key is not configured.",
			"error_kind": "missing_api_key"
		}

	var public_ip_result := await _discover_public_ip()
	if not bool(public_ip_result.get("ok", false)):
		return {
			"ok": false,
			"message": String(public_ip_result.get("message", "Unable to determine public host address.")),
			"error_kind": String(public_ip_result.get("error_kind", "public_ip_lookup_failed"))
		}

	var room_code := _generate_room_code()
	var session_id := provided_session_id.strip_edges()
	if session_id.is_empty():
		session_id = "mp-session-%d-%s" % [Time.get_unix_time_from_system(), _generate_room_code(4)]

	var payload := {
		"room_code": room_code,
		"session_id": session_id,
		"status": "open",
		"transport_type": TRANSPORT_TYPE_DIRECT_ENET,
		"host_address": String(public_ip_result.get("address", "")).strip_edges(),
		"host_port": host_port
	}

	var headers := _build_headers(true)
	var request_result := await _perform_request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if not bool(request_result.get("ok", false)):
		request_result["error_kind"] = String(request_result.get("error_kind", "room_registry_create_failed"))
		return request_result

	var rows := _normalize_response_rows(request_result.get("data", null))
	var registration := payload.duplicate(true)
	if not rows.is_empty() and rows[0] is Dictionary:
		registration = (rows[0] as Dictionary).duplicate(true)

	return {
		"ok": true,
		"room_code": room_code,
		"registration": registration,
		"message": "Room created successfully."
	}

func resolve_room_code(room_code: String) -> Dictionary:
	var normalized_room_code := room_code.strip_edges().to_upper()
	if normalized_room_code.is_empty():
		return {
			"ok": false,
			"message": "Room code is required."
		}

	var endpoint := _room_registry_endpoint()
	if endpoint.is_empty():
		return {
			"ok": false,
			"message": "Room registry endpoint is not configured.",
			"error_kind": "missing_endpoint"
		}
	if _room_registry_api_key().is_empty():
		return {
			"ok": false,
			"message": "Room registry API key is not configured.",
			"error_kind": "missing_api_key"
		}

	var url := "%s?select=room_code,session_id,status,transport_type,host_address,host_port&room_code=eq.%s&status=eq.open&limit=1" % [endpoint, normalized_room_code]
	var request_result := await _perform_request(url, _build_headers(false), HTTPClient.METHOD_GET)
	if not bool(request_result.get("ok", false)):
		request_result["error_kind"] = String(request_result.get("error_kind", "room_registry_lookup_failed"))
		return request_result

	var rows := _normalize_response_rows(request_result.get("data", null))
	if rows.is_empty() or not (rows[0] is Dictionary):
		return {
			"ok": false,
			"message": "Room code not found or no longer open.",
			"error_kind": "room_not_found"
		}

	return {
		"ok": true,
		"room_code": normalized_room_code,
		"registration": (rows[0] as Dictionary).duplicate(true),
		"message": "Room resolved successfully."
	}

func close_room_registration(room_code: String) -> void:
	var normalized_room_code := room_code.strip_edges().to_upper()
	if normalized_room_code.is_empty():
		return
	var endpoint := _room_registry_endpoint()
	if endpoint.is_empty():
		return
	var url := "%s?room_code=eq.%s" % [endpoint, normalized_room_code]
	await _perform_request(url, _build_headers(false), HTTPClient.METHOD_PATCH, JSON.stringify({"status": "closed"}))

func _discover_public_ip() -> Dictionary:
	var lookup_url := String(ProjectSettings.get_setting(PUBLIC_IP_LOOKUP_URL_SETTING, DEFAULT_PUBLIC_IP_LOOKUP_URL)).strip_edges()
	if lookup_url.is_empty():
		lookup_url = DEFAULT_PUBLIC_IP_LOOKUP_URL
	var result := await _perform_request(lookup_url, PackedStringArray(), HTTPClient.METHOD_GET)
	if not bool(result.get("ok", false)):
		return result
	var address := String(result.get("response_text", "")).strip_edges()
	if address.is_empty():
		return {
			"ok": false,
			"message": "Public IP lookup returned an empty address.",
			"error_kind": "public_ip_lookup_empty"
		}
	return {
		"ok": true,
		"address": address,
		"message": "Public IP discovered."
	}

func _perform_request(url: String, headers: PackedStringArray, method: int, body: String = "") -> Dictionary:
	var request := HTTPRequest.new()
	add_child(request)
	request.timeout = 10.0
	var request_error := request.request(url, headers, method, body)
	if request_error != OK:
		request.queue_free()
		return {
			"ok": false,
			"message": "request_start_failed_%d" % request_error,
			"error_kind": "request_start_failed"
		}

	var result: Array = await request.request_completed
	request.queue_free()
	var http_result := int(result[0])
	var response_code := int(result[1])
	var response_body := result[3] as PackedByteArray
	var response_text := response_body.get_string_from_utf8()
	if http_result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var message := "http_result_%d_code_%d" % [http_result, response_code]
		if not response_text.strip_edges().is_empty():
			message = "%s_%s" % [message, response_text.substr(0, min(200, response_text.length()))]
		return {
			"ok": false,
			"message": message,
			"error_kind": "http_request_failed",
			"response_text": response_text
		}

	var parsed: Variant = response_text
	if not response_text.strip_edges().is_empty():
		var json := JSON.new()
		if json.parse(response_text) == OK:
			parsed = json.data

	return {
		"ok": true,
		"data": parsed,
		"response_text": response_text,
		"response_code": response_code
	}

func _normalize_response_rows(data: Variant) -> Array:
	if data is Array:
		return data as Array
	if data is Dictionary:
		return [data]
	return []

func _build_headers(include_return_representation: bool) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var api_key := _room_registry_api_key()
	if not api_key.is_empty():
		headers.append("apikey: %s" % api_key)
		headers.append("Authorization: Bearer %s" % api_key)
	if include_return_representation:
		headers.append("Prefer: return=representation")
	return headers

func _room_registry_endpoint() -> String:
	return String(ProjectSettings.get_setting(ROOM_REGISTRY_ENDPOINT_SETTING, "")).strip_edges()

func _room_registry_api_key() -> String:
	return String(ProjectSettings.get_setting(ROOM_REGISTRY_API_KEY_SETTING, "")).strip_edges()

func _generate_room_code(length: int = 6) -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var generated := ""
	for _index in range(maxi(4, length)):
		generated += chars[randi() % chars.length()]
	return generated