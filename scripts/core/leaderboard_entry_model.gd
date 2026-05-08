extends RefCounted
class_name LeaderboardEntryModel

const RUN_SUMMARY_MODEL := preload("res://scripts/core/run_summary_model.gd")

const BOARD_GLOBAL := "global"
const BOARD_PER_CHARACTER := "per_character"

static func normalize_run_summary(run_summary: Dictionary) -> Dictionary:
	var summary := RUN_SUMMARY_MODEL.create_summary(run_summary)
	summary["run_id"] = String(summary.get("run_id", "")).strip_edges()
	summary["outcome"] = String(summary.get("outcome", "unknown")).strip_edges().to_lower()
	summary["character_id"] = String(summary.get("character_id", "unknown")).strip_edges().to_lower()
	summary["character_name"] = String(summary.get("character_name", "Unknown")).strip_edges()
	summary["difficulty_tier"] = int(summary.get("difficulty_tier", 0))
	summary["duration_seconds"] = maxi(0, int(summary.get("duration_seconds", 0)))
	summary["started_at_unix"] = maxi(0, int(summary.get("started_at_unix", 0)))
	summary["ended_at_unix"] = maxi(0, int(summary.get("ended_at_unix", 0)))
	summary["player_uuid"] = String(summary.get("player_uuid", "")).strip_edges().to_lower()
	summary["player_name"] = String(summary.get("player_name", "Player")).strip_edges()
	summary["leaderboard_patch_key"] = String(summary.get("leaderboard_patch_key", "dev")).strip_edges().to_lower()
	summary["is_debug"] = bool(summary.get("is_debug", false))
	return summary

static func is_submission_eligible(run_summary: Dictionary) -> bool:
	var summary := normalize_run_summary(run_summary)
	if String(summary.get("outcome", "")) != "clear":
		return false
	if bool(summary.get("is_debug", false)):
		return false
	if String(summary.get("run_id", "")).is_empty():
		return false
	if String(summary.get("player_uuid", "")).is_empty():
		return false
	if int(summary.get("duration_seconds", 0)) <= 0:
		return false
	if int(summary.get("difficulty_tier", -1)) < 0 or int(summary.get("difficulty_tier", -1)) > 3:
		return false
	return true

static func build_submission_rpc_body(run_summary: Dictionary) -> Dictionary:
	if not is_submission_eligible(run_summary):
		return {}
	var summary := normalize_run_summary(run_summary)
	return {
		"p_run_summary": summary,
	}

static func normalize_server_entry(entry: Dictionary) -> Dictionary:
	return {
		"rank": maxi(1, int(entry.get("rank", 0))),
		"run_id": String(entry.get("run_id", "")).strip_edges(),
		"player_uuid": String(entry.get("player_uuid", "")).strip_edges().to_lower(),
		"player_name": String(entry.get("player_name", "Player")).strip_edges(),
		"character_id": String(entry.get("character_id", "unknown")).strip_edges().to_lower(),
		"character_name": String(entry.get("character_name", "Unknown")).strip_edges(),
		"difficulty_tier": int(entry.get("difficulty_tier", 0)),
		"duration_seconds": maxi(0, int(entry.get("duration_seconds", 0))),
		"leaderboard_patch_key": String(entry.get("leaderboard_patch_key", "dev")).strip_edges().to_lower(),
		"ended_at_unix": maxi(0, int(entry.get("ended_at_unix", 0))),
	}

static func sort_entries(entries: Array) -> Array:
	var sorted_entries := entries.duplicate(true)
	sorted_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_duration := int(a.get("duration_seconds", 0))
		var b_duration := int(b.get("duration_seconds", 0))
		if a_duration != b_duration:
			return a_duration < b_duration
		var a_ended := int(a.get("ended_at_unix", 0))
		var b_ended := int(b.get("ended_at_unix", 0))
		if a_ended != b_ended:
			return a_ended < b_ended
		return String(a.get("run_id", "")) < String(b.get("run_id", ""))
	)
	for i in range(sorted_entries.size()):
		var row := sorted_entries[i] as Dictionary
		row["rank"] = i + 1
		sorted_entries[i] = row
	return sorted_entries
