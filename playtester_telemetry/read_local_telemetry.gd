extends SceneTree
## Standalone decoder: no game autoloads, writes only to its disposable project.

const FIELDS := [
	"id", "run_id", "game_version", "run_provenance", "started_at_unix", "ended_at_unix",
	"duration_seconds", "character_id", "difficulty_tier", "outcome", "max_depth",
	"rooms_cleared", "is_debug", "is_multiplayer", "player_count", "run_mode",
	"damage_events", "room_entries", "reward_choices", "reward_offers", "door_choices",
	"death_event", "build_summary", "stats", "equipped_catalyst_ids", "ascension_rank",
	"ascension_loadout", "ascension_tracking_complete", "full_run_tracking_complete"
]
const IDENTITY_FIELDS := ["player_uuid", "player_name", "peers", "player_names"]

func _initialize() -> void:
	var file := FileAccess.open("res://input.save", FileAccess.READ)
	if file == null or file.get_length() < 4:
		_fail("Local telemetry is missing or incomplete")
		return
	# Object decoding is deliberately disabled, including for malformed saves.
	var decoded: Variant = file.get_var(false)
	file.close()
	if not decoded is Dictionary or not decoded.get("version") is int or decoded.get("version") != 1 or not decoded.get("runs") is Array:
		_fail("Expected version 1 local telemetry with a runs array")
		return
	var runs: Array[Dictionary] = []
	for entry in decoded.runs:
		if not entry is Dictionary:
			_fail("Local telemetry contains a non-object run")
			return
		var run: Dictionary = {}
		for field in FIELDS:
			if entry.has(field):
				run[field] = _without_identities(entry[field])
		# Stable opaque IDs retain duplicate detection without exposing raw run IDs.
		for field in ["id", "run_id"]:
			if not run.has(field):
				continue
			var identifier: Variant = run[field]
			if identifier == null:
				run.erase(field)
			elif identifier is String or identifier is int:
				var text := str(identifier)
				run[field] = text.sha256_text() if not text.is_empty() else ""
			else:
				_fail("Local telemetry contains an invalid run ID")
				return
		runs.append(run)
	var output := FileAccess.open("res://decoded.json", FileAccess.WRITE)
	if output == null:
		_fail("Cannot write temporary decoded telemetry")
		return
	output.store_string(JSON.stringify({"runs": runs}))
	output.close()
	quit(0)

## Returns independent containers while omitting identity fields at any depth.
func _without_identities(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			if key is String and not IDENTITY_FIELDS.has(key):
				result[key] = _without_identities(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(_without_identities(entry))
		return result
	return value

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
