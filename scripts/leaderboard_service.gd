extends Node
class_name LeaderboardService

const LEADERBOARD_MODEL := preload("res://scripts/core/leaderboard_entry_model.gd")
const TELEMETRY_ENDPOINT_SETTING := "application/config/telemetry_upload_endpoint"
const TELEMETRY_API_KEY_SETTING := "application/config/telemetry_upload_api_key"
const LEADERBOARD_BASE_URL_SETTING := "application/config/leaderboard_rest_base_url"

func fetch_patch_options(current_patch_key: String, difficulty_tier: int = -1, limit: int = 24) -> Dictionary:
	var response := await _post_rpc("get_leaderboard_patch_keys", {
		"p_difficulty_tier": difficulty_tier,
		"p_limit": maxi(1, limit),
		"p_current_patch_key": current_patch_key.strip_edges().to_lower(),
	})
	if not bool(response.get("ok", false)):
		return {
			"ok": false,
			"error": String(response.get("error", "Unable to load patch list.")),
			"patches": [],
		}
	var rows := []
	var data: Array = response.get("data", []) as Array
	if data is Array:
		for row_variant in data:
			var row := row_variant as Dictionary
			var patch_key := String(row.get("patch_key", "")).strip_edges().to_lower()
			if patch_key.is_empty():
				continue
			rows.append({
				"patch_key": patch_key,
				"is_current": bool(row.get("is_current", false)),
				"is_archived": bool(row.get("is_archived", not bool(row.get("is_current", false)))),
			})
	if rows.is_empty() and not current_patch_key.strip_edges().is_empty():
		rows.append({
			"patch_key": current_patch_key.strip_edges().to_lower(),
			"is_current": true,
			"is_archived": false,
		})
	return {
		"ok": true,
		"patches": rows,
		"error": "",
	}

func fetch_top_entries(patch_key: String, difficulty_tier: int, board_mode: String, character_id: String = "", limit: int = 25, party_size: int = 1) -> Dictionary:
	var response := await _post_rpc("get_leaderboard_top", {
		"p_patch_key": patch_key.strip_edges().to_lower(),
		"p_difficulty_tier": difficulty_tier,
		"p_board_mode": board_mode.strip_edges().to_lower(),
		"p_character_id": character_id.strip_edges().to_lower(),
		"p_limit": maxi(1, limit),
		"p_party_size": clampi(party_size, 1, 4),
	})
	if not bool(response.get("ok", false)):
		return {
			"ok": false,
			"error": String(response.get("error", "Unable to load leaderboard.")),
			"entries": [],
		}
	var rows := []
	var data: Array = response.get("data", []) as Array
	if data is Array:
		for row_variant in data:
			rows.append(LEADERBOARD_MODEL.normalize_server_entry(row_variant as Dictionary))
	rows = LEADERBOARD_MODEL.sort_entries(rows)
	if rows.size() > limit:
		rows.resize(limit)
	return {
		"ok": true,
		"entries": rows,
		"error": "",
	}

func _post_rpc(rpc_name: String, body: Dictionary) -> Dictionary:
	var endpoint := _rpc_url(rpc_name)
	if endpoint.is_empty():
		return {
			"ok": false,
			"status_code": 0,
			"data": [],
			"error": "Leaderboard endpoint is not configured.",
		}
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var api_key := _upload_api_key()
	if not api_key.is_empty():
		headers.append("apikey: %s" % api_key)
		headers.append("Authorization: Bearer %s" % api_key)
	var request_error := request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if request_error != OK:
		remove_child(request)
		request.queue_free()
		return {
			"ok": false,
			"status_code": 0,
			"data": [],
			"error": "Request start failed.",
		}
	var completed: Array = await request.request_completed
	remove_child(request)
	request.queue_free()
	if completed.size() < 4:
		return {
			"ok": false,
			"status_code": 0,
			"data": [],
			"error": "Malformed HTTP response.",
		}
	var result := int(completed[0])
	var response_code := int(completed[1])
	var body_bytes := completed[3] as PackedByteArray
	var body_text := body_bytes.get_string_from_utf8()
	var parsed: Variant = []
	if not body_text.strip_edges().is_empty():
		var json := JSON.new()
		if json.parse(body_text) == OK:
			parsed = json.data
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		return {
			"ok": true,
			"status_code": response_code,
			"data": parsed,
			"error": "",
		}
	return {
		"ok": false,
		"status_code": response_code,
		"data": parsed,
		"error": "HTTP %d" % response_code,
	}

func _rpc_url(rpc_name: String) -> String:
	var base := _rest_base_url()
	if base.is_empty():
		return ""
	return "%s/rpc/%s" % [base.trim_suffix("/"), rpc_name.strip_edges()]

func _rest_base_url() -> String:
	var explicit := String(ProjectSettings.get_setting(LEADERBOARD_BASE_URL_SETTING, "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var telemetry_endpoint := String(ProjectSettings.get_setting(TELEMETRY_ENDPOINT_SETTING, "")).strip_edges()
	if telemetry_endpoint.is_empty():
		return ""
	var marker := "/rest/v1/"
	var idx := telemetry_endpoint.find(marker)
	if idx < 0:
		return ""
	return telemetry_endpoint.substr(0, idx + marker.length() - 1)

func _upload_api_key() -> String:
	return String(ProjectSettings.get_setting(TELEMETRY_API_KEY_SETTING, "")).strip_edges()
