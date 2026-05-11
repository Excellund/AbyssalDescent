extends RefCounted
class_name ProfanityFilter

signal check_complete(is_profane: bool)

const PROFANITY_API_URL := "https://vector.profanity.dev"
const REQUEST_TIMEOUT_SEC := 5.0

var _http_client: HTTPRequest = null
var _pending_check_name: String = ""
var _tree_owner: Node = null

func _init(tree_owner: Node = null) -> void:
	_tree_owner = tree_owner
	_http_client = HTTPRequest.new()
	if _tree_owner != null:
		_tree_owner.add_child(_http_client)

func check_profanity_async(text: String) -> void:
	if text.is_empty():
		check_complete.emit(false)
		return
	
	if _http_client.get_parent() == null and _tree_owner != null:
		_tree_owner.add_child(_http_client)
	
	_pending_check_name = text
	
	var json_body := JSON.stringify({"message": text})
	
	var error := _http_client.request(
		PROFANITY_API_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		json_body
	)
	
	if error != OK:
		push_error("[ProfanityFilter] Failed to start HTTP request: ", error)
		check_complete.emit(false)
		return
	
	if not _http_client.request_completed.is_connected(_on_request_completed):
		_http_client.request_completed.connect(_on_request_completed)
	
	# Timeout fallback
	if _tree_owner != null and _tree_owner.get_tree() != null:
		await _tree_owner.get_tree().create_timer(REQUEST_TIMEOUT_SEC).timeout
		if _pending_check_name != "":
			push_error("[ProfanityFilter] Profanity check timed out")
			_pending_check_name = ""
			check_complete.emit(false)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if _pending_check_name.is_empty():
		return
	
	_pending_check_name = ""
	
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("[ProfanityFilter] HTTP request failed: ", result)
		check_complete.emit(false)
		return
	
	if response_code != 200:
		push_error("[ProfanityFilter] API returned status code: ", response_code)
		check_complete.emit(false)
		return
	
	var body_text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(body_text) != OK:
		push_error("[ProfanityFilter] Failed to parse API response")
		check_complete.emit(false)
		return
	
	var data := json.data as Dictionary
	var is_profane := bool(data.get("isProfane", false))
	
	check_complete.emit(is_profane)
