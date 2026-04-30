extends RefCounted

const TELEMETRY_SAVE_PATH := "user://run_telemetry.save"
const TELEMETRY_VERSION := 1
const MAX_RUNS_STORED := 80
const MAX_DAMAGE_EVENTS_PER_RUN := 500

static func _default_store() -> Dictionary:
	return {
		"version": TELEMETRY_VERSION,
		"runs": []
	}

static func _now_unix() -> int:
	return int(Time.get_unix_time_from_system())

static func _current_game_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "dev"))

static func load_store() -> Dictionary:
	if not FileAccess.file_exists(TELEMETRY_SAVE_PATH):
		return _default_store()
	var file := FileAccess.open(TELEMETRY_SAVE_PATH, FileAccess.READ)
	if file == null:
		return _default_store()
	var payload_raw: Variant = file.get_var()
	if not (payload_raw is Dictionary):
		return _default_store()
	var payload := payload_raw as Dictionary
	if int(payload.get("version", -1)) != TELEMETRY_VERSION:
		return _default_store()
	if not (payload.get("runs", []) is Array):
		return _default_store()
	return payload

static func save_store(store: Dictionary) -> bool:
	var file := FileAccess.open(TELEMETRY_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(store)
	return true

static func _new_run_id() -> String:
	var ticks := Time.get_ticks_usec()
	var unix_time := _now_unix()
	return "%s-%s" % [str(unix_time), str(ticks)]

static func start_run(run_seed: Dictionary) -> String:
	var store := load_store()
	var runs := store.get("runs", []) as Array
	var run_id := _new_run_id()
	var run_entry := {
		"id": run_id,
		"started_at_unix": _now_unix(),
		"ended_at_unix": 0,
		"game_version": String(run_seed.get("game_version", _current_game_version())),
		"difficulty_tier": int(run_seed.get("difficulty_tier", 0)),
		"run_mode": int(run_seed.get("run_mode", 0)),
		"is_debug": bool(run_seed.get("is_debug", false)),
		"outcome": "in_progress",
		"max_depth": int(run_seed.get("start_depth", 0)),
		"rooms_cleared": int(run_seed.get("rooms_cleared", 0)),
		"damage_events": [],
		"reward_choices": [],
		"room_entries": [],
		"door_choices": [],
		"death_event": {}
	}
	runs.append(run_entry)
	while runs.size() > MAX_RUNS_STORED:
		runs.remove_at(0)
	store["runs"] = runs
	save_store(store)
	return run_id

static func _find_run_index(runs: Array, run_id: String) -> int:
	for index in range(runs.size()):
		var run_entry := runs[index] as Dictionary
		if String(run_entry.get("id", "")) == run_id:
			return index
	return -1

static func _mutate_run_entry(run_id: String, mutator: Callable) -> bool:
	var store := load_store()
	var runs := store.get("runs", []) as Array
	var run_index := _find_run_index(runs, run_id)
	if run_index < 0:
		return false
	var run_entry := (runs[run_index] as Dictionary).duplicate(true)
	mutator.callv([run_entry])
	runs[run_index] = run_entry
	store["runs"] = runs
	return save_store(store)

static func _append_limited_event(run_entry: Dictionary, key: String, event_data: Dictionary, max_events: int) -> void:
	var events := run_entry.get(key, []) as Array
	events.append(event_data)
	while events.size() > max_events:
		events.remove_at(0)
	run_entry[key] = events

static func append_damage_event(run_id: String, event_data: Dictionary) -> void:
	if run_id.is_empty():
		return
	_mutate_run_entry(run_id, func(run_entry: Dictionary) -> void:
		_append_limited_event(run_entry, "damage_events", event_data, MAX_DAMAGE_EVENTS_PER_RUN)
		run_entry["max_depth"] = maxi(int(run_entry.get("max_depth", 0)), int(event_data.get("room_depth", 0)))
	)

static func append_reward_choice(run_id: String, event_data: Dictionary) -> void:
	if run_id.is_empty():
		return
	_mutate_run_entry(run_id, func(run_entry: Dictionary) -> void:
		_append_limited_event(run_entry, "reward_choices", event_data, 180)
	)

static func append_room_entry(run_id: String, event_data: Dictionary) -> void:
	if run_id.is_empty():
		return
	_mutate_run_entry(run_id, func(run_entry: Dictionary) -> void:
		_append_limited_event(run_entry, "room_entries", event_data, 220)
		run_entry["max_depth"] = maxi(int(run_entry.get("max_depth", 0)), int(event_data.get("room_depth", 0)))
		run_entry["rooms_cleared"] = maxi(int(run_entry.get("rooms_cleared", 0)), int(event_data.get("rooms_cleared", 0)))
	)

static func append_door_choice(run_id: String, event_data: Dictionary) -> void:
	if run_id.is_empty():
		return
	_mutate_run_entry(run_id, func(run_entry: Dictionary) -> void:
		_append_limited_event(run_entry, "door_choices", event_data, 180)
	)

static func mark_run_debug(run_id: String) -> void:
	if run_id.is_empty():
		return
	_mutate_run_entry(run_id, func(run_entry: Dictionary) -> void:
		run_entry["is_debug"] = true
	)

static func finish_run(run_id: String, outcome: String, summary: Dictionary = {}) -> void:
	if run_id.is_empty():
		return
	_mutate_run_entry(run_id, func(run_entry: Dictionary) -> void:
		run_entry["ended_at_unix"] = _now_unix()
		run_entry["outcome"] = outcome
		run_entry["max_depth"] = maxi(int(run_entry.get("max_depth", 0)), int(summary.get("max_depth", 0)))
		run_entry["rooms_cleared"] = maxi(int(run_entry.get("rooms_cleared", 0)), int(summary.get("rooms_cleared", 0)))
		if summary.has("death_event"):
			run_entry["death_event"] = (summary.get("death_event", {}) as Dictionary).duplicate(true)
	)

static func get_recent_runs(max_runs: int = 10, max_age_days: int = 21, include_debug: bool = false, game_version: String = "") -> Array[Dictionary]:
	var store := load_store()
	var runs := store.get("runs", []) as Array
	var now_unix := _now_unix()
	var min_unix := now_unix - maxi(1, max_age_days) * 86400
	var resolved_version := game_version.strip_edges()
	if resolved_version.is_empty():
		resolved_version = _current_game_version()
	var filtered: Array[Dictionary] = []
	for index in range(runs.size() - 1, -1, -1):
		var run_entry := runs[index] as Dictionary
		var started_at := int(run_entry.get("started_at_unix", 0))
		if started_at < min_unix:
			continue
		if not include_debug and bool(run_entry.get("is_debug", false)):
			continue
		if String(run_entry.get("game_version", "")) != resolved_version:
			continue
		filtered.append(run_entry.duplicate(true))
		if filtered.size() >= maxi(1, max_runs):
			break
	return filtered

static func _increment_counter(counter: Dictionary, key: String, amount: int = 1) -> void:
	counter[key] = int(counter.get(key, 0)) + amount

static func build_balance_summary(max_runs: int = 10, max_age_days: int = 21, include_debug: bool = false, game_version: String = "") -> Dictionary:
	var recent_runs := get_recent_runs(max_runs, max_age_days, include_debug, game_version)
	var damage_by_source: Dictionary = {}
	var damage_by_ability: Dictionary = {}
	var damage_by_bearing: Dictionary = {}
	var reward_choices: Dictionary = {}
	var room_entries: Dictionary = {}
	var room_entries_by_bearing: Dictionary = {}
	var door_choices_by_bearing: Dictionary = {}
	var death_sources: Dictionary = {}
	var deaths_by_bearing: Dictionary = {}
	var outcomes: Dictionary = {}
	for run_entry in recent_runs:
		_increment_counter(outcomes, String(run_entry.get("outcome", "unknown")))
		for room_entry_variant in run_entry.get("room_entries", []):
			var room_entry := room_entry_variant as Dictionary
			var bearing_key := String(room_entry.get("bearing_key", room_entry.get("room_kind", "unknown")))
			var room_key := "%s|%s" % [String(room_entry.get("room_label", "Unknown")), String(room_entry.get("enemy_mutator", "none"))]
			_increment_counter(room_entries, room_key)
			_increment_counter(room_entries_by_bearing, bearing_key)
		for door_choice_variant in run_entry.get("door_choices", []):
			var door_choice := door_choice_variant as Dictionary
			var door_bearing_key := String(door_choice.get("bearing_key", "unknown"))
			_increment_counter(door_choices_by_bearing, door_bearing_key)
		for choice_variant in run_entry.get("reward_choices", []):
			var reward_entry := choice_variant as Dictionary
			var reward_key := "%s|%s" % [String(reward_entry.get("mode", "unknown")), String(reward_entry.get("choice_id", "unknown"))]
			_increment_counter(reward_choices, reward_key)
		for damage_variant in run_entry.get("damage_events", []):
			var damage_entry := damage_variant as Dictionary
			_increment_counter(damage_by_source, String(damage_entry.get("source", "unknown")))
			_increment_counter(damage_by_ability, String(damage_entry.get("ability", "unknown")))
			_increment_counter(damage_by_bearing, String(damage_entry.get("bearing_key", "unknown")))
		var death_event := run_entry.get("death_event", {}) as Dictionary
		if not death_event.is_empty():
			_increment_counter(death_sources, String(death_event.get("source", "unknown")))
			_increment_counter(deaths_by_bearing, String(death_event.get("bearing_key", "unknown")))
	return {
		"filters": {
			"max_runs": max_runs,
			"max_age_days": max_age_days,
			"include_debug": include_debug,
			"game_version": game_version if not game_version.strip_edges().is_empty() else _current_game_version()
		},
		"run_count": recent_runs.size(),
		"runs": recent_runs,
		"aggregate": {
			"outcomes": outcomes,
			"damage_by_source": damage_by_source,
			"damage_by_ability": damage_by_ability,
			"damage_by_bearing": damage_by_bearing,
			"death_sources": death_sources,
			"deaths_by_bearing": deaths_by_bearing,
			"reward_choices": reward_choices,
			"room_entries": room_entries,
			"room_entries_by_bearing": room_entries_by_bearing,
			"door_choices_by_bearing": door_choices_by_bearing
		}
	}
