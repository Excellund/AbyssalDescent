## Read-only current-run Oath projection. The award evaluator owns positive
## qualification; this helper adds explanations, never progress or unlocks.
extends RefCounted

const REGISTRY := preload("res://scripts/progression/oaths_registry.gd")
const EVALUATOR := preload("res://scripts/progression/oaths_evaluator.gd")
const META := preload("res://scripts/meta_progress_store.gd")
const TRACKER := preload("res://scripts/core/run_summary_tracker.gd")

const WHOLE_RUN_KEYS := [
	"win_single_arcana", "win_no_damage_taken", "win_no_primary_attack",
	"win_no_rest", "win_under_time_seconds", "win_no_catalysts", "win_no_dash",
	"win_modifier_loadout_no_rest",
]
const HOST_CONFIRMED_KEYS := [
	"boss_no_hit", "hold_zone_full_control", "win_bosses_no_hit", "win_under_time_seconds",
]

## evidence: is_joiner, profile_available. Missing evidence never certifies
## earlier actions. Inputs and the profile remain unchanged, including sparse
## profiles whose Meta getters would otherwise initialize their dictionaries.
static func presentation(summary: Dictionary, profile: Dictionary, evidence: Dictionary = {}) -> Array[Dictionary]:
	var profile_copy := profile.duplicate(true)
	var completed := META.get_completed_oath_ids(profile_copy)
	var actual: Array = EVALUATOR.evaluate_run(summary.duplicate(true), profile_copy.duplicate(true)).get("completed_oath_ids", [])
	var projected := summary.duplicate(true)
	projected["outcome"] = "clear"
	var on_clear: Array = EVALUATOR.evaluate_run(projected, profile_copy.duplicate(true)).get("completed_oath_ids", [])
	var rows: Array[Dictionary] = []
	var definitions := REGISTRY.get_all_definitions()
	for id: String in definitions:
		var definition: Dictionary = definitions[id]
		var key := String(definition.get("evaluator_key", ""))
		var params: Dictionary = definition.get("params", {})
		var unavailable := _setup_mismatch(definition, summary)
		var row := {
			"id": id, "label": String(definition.get("label", id)),
			"description": String(definition.get("description", "")),
			"state": "pending", "detail": "Requirement not yet recorded.",
			"relevant": unavailable.is_empty(),
		}
		if REGISTRY.is_completed(id, completed):
			_set_state(row, "earned", "Already earned on this profile.")
		elif not unavailable.is_empty():
			_set_state(row, "unavailable", unavailable)
		elif bool(summary.get("is_debug", false)):
			_set_state(row, "unavailable", "Debug runs do not earn Oaths.")
		elif not bool(evidence.get("profile_available", not profile.is_empty())):
			_set_state(row, "unverified", "Profile unavailable; completion cannot be confirmed.")
		elif bool(evidence.get("is_joiner", false)) and key in HOST_CONFIRMED_KEYS:
			_set_state(row, "unverified", "The host confirms this requirement at run end.")
		else:
			_add_progress(row, key, params, summary)
			var violation := _known_violation(key, params, summary)
			var minimum := TRACKER._oath_minimum_from_summary(summary)
			if minimum >= 0 and minimum < int(definition.get("minimum_bearing_tier", 0)):
				violation = "An earlier part of this run used a lower Bearing."
			var missing := _missing_evidence(definition, summary)
			if actual.has(id):
				_set_state(row, "achieved", "Condition achieved; recorded when this run ends.")
			elif not violation.is_empty():
				_set_state(row, "broken", violation)
			elif not missing.is_empty():
				_set_state(row, "unverified", missing)
			elif not EVALUATOR._is_clear(summary) and String(summary.get("outcome", "in_progress")) in ["death", "quit", "menu_exit", "host_left"] and key != "boss_no_hit" and key != "hold_zone_full_control":
				_set_state(row, "unavailable", "This run ended without a clear.")
			elif on_clear.has(id):
				_set_state(row, "on_track", "Requirement intact; clear this run to complete it.")
			elif key == "boss_no_hit":
				_set_state(row, "pending", "A qualifying boss defeat has not been recorded.")
			elif key == "hold_zone_full_control":
				_set_state(row, "pending", "Complete Hold the Line with full zone control.")
			elif key == "win_bosses_no_hit":
				_set_state(row, "pending", "Record all three qualifying boss defeats, then clear.")
			elif key == "win_single_arcana":
				_set_state(row, "pending", "Choose one Arcana, then clear. Upgrades are allowed.")
			else:
				_set_state(row, "unverified", "The recorded evidence does not yet verify this requirement.")
			if row.state == "unverified":
				# Restored zeroes do not describe unknown earlier history.
				row.erase("current")
				row.erase("target")
				row.erase("progress_text")
			elif row.state == "broken" and row.has("progress_text"):
				if (key in WHOLE_RUN_KEYS and not EVALUATOR._has_true_evidence(summary, "full_run_tracking_complete")) or (key == "win_no_dash" and not EVALUATOR._has_true_evidence(summary, "dash_tracking_complete")):
					row["progress_text"] += " (recorded portion)"
		rows.append(row)
	return rows

static func _set_state(row: Dictionary, state: String, detail: String) -> void:
	row["state"] = state
	row["detail"] = detail

## Relevance is launch applicability, not current success. A broken or older
## unverified attempt stays visible; other vessels/Bearings/setups do not.
static func _setup_mismatch(definition: Dictionary, summary: Dictionary) -> String:
	var tier := TRACKER._validated_oath_tier(summary.get("difficulty_tier"))
	if tier >= 0 and not REGISTRY.is_bearing_eligible(definition, tier):
		return "This Oath requires a different Bearing."
	var key := String(definition.get("evaluator_key", ""))
	var params: Dictionary = definition.get("params", {})
	if key == "win_with_character_at_bearing":
		var character: Variant = summary.get("character_id")
		if character is String and not character.strip_edges().is_empty() and character.strip_edges().to_lower() != String(params.get("character_id", "")):
			return "This Oath belongs to another vessel."
	if EVALUATOR._has_true_evidence(summary, "ascension_tracking_complete"):
		if key in ["ascension_rank_at_least", "win_no_catalysts"]:
			var rank: Variant = summary.get("ascension_rank")
			var needed := int(params.get("rank", params.get("minimum_ascension_rank", 1)))
			if _known_count(rank) and int(rank) < needed:
				return "This run started below the required Ascension rank."
		elif key == "win_modifier_loadout_no_rest" and _valid_ids(summary.get("ascension_loadout")) and not EVALUATOR._recorded_ids_include(summary.ascension_loadout, params.get("modifiers", [])):
			return "This run did not start with the required Ascension modifiers."
	if key == "win_no_catalysts" and EVALUATOR._has_true_evidence(summary, "catalyst_tracking_complete") and _valid_ids(summary.get("equipped_catalyst_ids")) and not summary.equipped_catalyst_ids.is_empty():
		return "This run started with Catalysts equipped."
	return ""

static func _known_violation(key: String, params: Dictionary, summary: Dictionary) -> String:
	match key:
		"win_no_primary_attack":
			if _positive(summary.get("primary_attacks_fired")):
				return "Attack has been used during this run."
		"win_no_dash":
			if _positive(summary.get("dashes_performed")):
				return "Dash has been used during this run."
		"win_no_rest", "win_modifier_loadout_no_rest":
			if _positive(summary.get("rest_count")):
				return "A Rest Site has been visited during this run."
		"win_no_damage_taken":
			var stats: Variant = summary.get("stats")
			if stats is Dictionary and _positive(stats.get("damage_taken_total")):
				return "Damage has been taken during this run."
		"win_under_time_seconds":
			var elapsed: Variant = summary.get("duration_seconds")
			if _known_count(elapsed) and int(elapsed) >= int(params.get("seconds", 0)):
				return "The time limit has been reached."
		"win_single_arcana":
			var progress := EVALUATOR._known_build_progress(summary, "arcana")
			if not progress.is_empty() and int(progress.unique_count) > 1:
				return "More than one Arcana has been chosen."
	return ""

static func _missing_evidence(definition: Dictionary, summary: Dictionary) -> String:
	if not EVALUATOR._meets_bearing_requirement(definition, summary):
		return "Earlier Bearing history is unverified."
	var key := String(definition.get("evaluator_key", ""))
	if key in WHOLE_RUN_KEYS and not EVALUATOR._has_true_evidence(summary, "full_run_tracking_complete"):
		return "Earlier run history is incomplete; this requirement cannot be verified."
	if key == "win_no_dash" and not EVALUATOR._has_true_evidence(summary, "dash_tracking_complete"):
		return "Earlier Dash history is unverified."
	if key == "win_no_catalysts" and not EVALUATOR._has_true_evidence(summary, "catalyst_tracking_complete"):
		return "The run's Catalyst setup is unverified."
	if key in ["win_no_catalysts", "win_modifier_loadout_no_rest", "ascension_rank_at_least"] and not EVALUATOR._has_true_evidence(summary, "ascension_tracking_complete"):
		return "The run's Ascension setup is unverified."
	match key:
		"boss_no_hit", "win_bosses_no_hit":
			if not _valid_ids(summary.get("boss_no_hit_ids")):
				return "Boss encounter evidence is unavailable."
		"hold_zone_full_control":
			if not (summary.get("hold_full_control_achieved") is bool):
				return "Hold the Line evidence is unavailable."
		"win_single_arcana":
			if EVALUATOR._known_build_progress(summary, "arcana").is_empty():
				return "The local Arcana build is unverified."
		"win_no_primary_attack", "win_no_dash", "win_no_rest", "win_under_time_seconds":
			var field: String = {"win_no_primary_attack": "primary_attacks_fired", "win_no_dash": "dashes_performed", "win_no_rest": "rest_count", "win_under_time_seconds": "duration_seconds"}[key]
			if not _known_count(summary.get(field)):
				return "The required run counter is unavailable."
		"win_no_damage_taken":
			var stats: Variant = summary.get("stats")
			if not (stats is Dictionary) or not _known_count(stats.get("damage_taken_total")):
				return "Local damage evidence is unavailable."
	return ""

static func _add_progress(row: Dictionary, key: String, params: Dictionary, summary: Dictionary) -> void:
	var fields := {"win_no_primary_attack": "primary_attacks_fired", "win_no_dash": "dashes_performed", "win_no_rest": "rest_count", "win_modifier_loadout_no_rest": "rest_count", "win_under_time_seconds": "duration_seconds", "ascension_rank_at_least": "ascension_rank", "win_no_catalysts": "ascension_rank"}
	if fields.has(key) and _known_count(summary.get(fields[key])):
		row["current"] = int(summary[fields[key]])
		row["target"] = int(params.get("seconds", params.get("rank", params.get("minimum_ascension_rank", 0))))
		match key:
			"win_no_primary_attack":
				row["progress_text"] = "Attack actions: %d" % row.current
			"win_no_dash":
				row["progress_text"] = "Dash uses: %d" % row.current
			"win_no_rest", "win_modifier_loadout_no_rest":
				row["progress_text"] = "Rest visits: %d" % row.current
			"win_under_time_seconds":
				row["progress_text"] = "Elapsed: %s (must be under %s)" % [_clock_text(row.current), _clock_text(row.target)]
			"ascension_rank_at_least", "win_no_catalysts":
				row["progress_text"] = "Ascension rank: %d (requires %d+)" % [row.current, row.target]
	elif key == "win_no_damage_taken":
		var stats: Variant = summary.get("stats")
		if stats is Dictionary and _known_count(stats.get("damage_taken_total")):
			row["current"] = int(stats.damage_taken_total)
			row["target"] = 0
			row["progress_text"] = "Damage taken: %d" % row.current
	elif key == "win_single_arcana":
		var progress := EVALUATOR._known_build_progress(summary, "arcana")
		if not progress.is_empty():
			row["current"] = int(progress.unique_count)
			row["target"] = 1
			row["progress_text"] = "Unique Arcana: %d / 1" % row.current
	elif key == "win_bosses_no_hit" and _valid_ids(summary.get("boss_no_hit_ids")):
		var count := 0
		for id: String in params.get("boss_ids", []):
			if EVALUATOR._recorded_ids_include(summary.boss_no_hit_ids, [id]):
				count += 1
		row["current"] = count
		row["target"] = (params.get("boss_ids", []) as Array).size()
		row["progress_text"] = "Qualifying bosses: %d / %d" % [row.current, row.target]

static func _clock_text(seconds: int) -> String:
	return "%d:%02d" % [int(floor(float(seconds) / 60.0)), seconds % 60]

static func _known_count(value: Variant) -> bool:
	return EVALUATOR._recorded_count_at_least(value, 0)

static func _positive(value: Variant) -> bool:
	return _known_count(value) and int(value) > 0

static func _valid_ids(value: Variant) -> bool:
	if not (value is Array):
		return false
	for id in value:
		if not (id is String) or id.strip_edges().is_empty():
			return false
	return true
