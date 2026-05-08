extends RefCounted
class_name RunSummaryWithProfile

const RUN_SUMMARY_MODEL := preload("res://scripts/core/run_summary_model.gd")
const PLAYER_PROFILE_SCRIPT := preload("res://scripts/core/player_profile.gd")

var summary: Dictionary = {}
var player_profile: RefCounted = null

static func create(run_summary: Dictionary, profile: RefCounted = null) -> RunSummaryWithProfile:
	var wrapped := RunSummaryWithProfile.new()
	wrapped.summary = run_summary.duplicate(true)
	wrapped.player_profile = profile
	if profile != null and profile.is_valid():
		wrapped.summary["player_profile_id"] = profile.player_id
		wrapped.summary["display_name"] = profile.profile_name
	return wrapped

func get_summary_dict() -> Dictionary:
	return summary.duplicate(true)

func get_player_id() -> String:
	if player_profile != null:
		return player_profile.player_id
	return String(summary.get("player_profile_id", ""))

func get_display_name() -> String:
	if player_profile != null:
		return player_profile.profile_name
	return String(summary.get("display_name", "Player"))

func get_character_id() -> String:
	return String(summary.get("character_id", ""))

func get_character_name() -> String:
	return String(summary.get("character_name", ""))

func get_difficulty_label() -> String:
	return String(summary.get("difficulty_label", "Pilgrim"))

func get_outcome() -> String:
	return String(summary.get("outcome", "unknown"))

func get_max_depth() -> int:
	return int(summary.get("max_depth", 0))

func get_rooms_cleared() -> int:
	return int(summary.get("rooms_cleared", 0))

func get_duration_seconds() -> int:
	return int(summary.get("duration_seconds", 0))

func get_stats() -> Dictionary:
	return (summary.get("stats", {}) as Dictionary).duplicate(true)

func get_damage_dealt() -> int:
	var stats := get_stats()
	return int(stats.get("damage_dealt_total", 0))

func get_damage_taken() -> int:
	var stats := get_stats()
	return int(stats.get("damage_taken_total", 0))

func get_enemies_killed() -> int:
	var stats := get_stats()
	return int(stats.get("enemies_killed", 0))

func get_bosses_defeated() -> int:
	var stats := get_stats()
	return int(stats.get("bosses_defeated", 0))

func get_build_summary() -> Dictionary:
	return (summary.get("build_summary", {}) as Dictionary).duplicate(true)

func get_arcana_list() -> Array:
	var build := get_build_summary()
	return build.get("arcana", []) as Array

func get_boons_list() -> Array:
	var build := get_build_summary()
	return build.get("boons", []) as Array

func get_boss_rewards_list() -> Array:
	var build := get_build_summary()
	return build.get("boss_rewards", []) as Array

func get_reward_timeline() -> Array:
	return (summary.get("reward_timeline", []) as Array).duplicate(true)

func get_started_at_unix() -> int:
	return int(summary.get("started_at_unix", 0))

func get_ended_at_unix() -> int:
	return int(summary.get("ended_at_unix", 0))

func get_leaderboard_patch_key() -> String:
	return String(summary.get("leaderboard_patch_key", "dev"))
