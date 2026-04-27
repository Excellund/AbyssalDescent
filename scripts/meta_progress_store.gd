## Persistent meta-progression: difficulty unlocks, milestones, and long-term player state
## Survives across version updates and active-run save changes
## Version envelope protects against data corruption and enables migration

extends RefCounted

const META_PROGRESS_PATH := "user://meta_progress.save"
const META_PROGRESS_VERSION := 1

const TIER_APPRENTICE := 0
const TIER_STANDARD := 1
const TIER_VETERAN := 2
const TIER_TORMENT := 3

const TIER_NAMES := {
	TIER_APPRENTICE: "Apprentice",
	TIER_STANDARD: "Standard",
	TIER_VETERAN: "Veteran",
	TIER_TORMENT: "Torment"
}

const TIER_DESCRIPTIONS := {
	TIER_APPRENTICE: "Learn the basics—fewer threats, gentler pacing.",
	TIER_STANDARD: "The intended experience—master the systems.",
	TIER_VETERAN: "Challenge unlocked—increased pressure and complexity.",
	TIER_TORMENT: "Extreme test—all systems at maximum intensity."
}

## Default profile for new players
static func _get_default_profile() -> Dictionary:
	return {
		"version": META_PROGRESS_VERSION,
		"created_at_unix": int(Time.get_unix_time_from_system()),
		"last_modified_unix": int(Time.get_unix_time_from_system()),
		"difficulty_state": {
			"current_tier": TIER_APPRENTICE,
			"highest_unlocked_tier": TIER_APPRENTICE
		},
		"milestones": {
			"first_clear": false,
			"first_clear_on_standard": false,
			"first_clear_on_veteran": false,
			"first_clear_on_torment": false,
			"depth_20_reached": false,
			"depth_50_reached": false
		},
		"run_stats": {
			"total_runs": 0,
			"total_clears": 0,
			"best_depth": 0
		}
	}

## Load profile from disk; if missing or corrupted, return default
static func load_meta_progress() -> Dictionary:
	if not FileAccess.file_exists(META_PROGRESS_PATH):
		return _get_default_profile()
	
	var file := FileAccess.open(META_PROGRESS_PATH, FileAccess.READ)
	if file == null:
		return _get_default_profile()
	
	var payload_raw: Variant = file.get_var()
	if not (payload_raw is Dictionary):
		return _get_default_profile()
	
	var payload := payload_raw as Dictionary
	var version := int(payload.get("version", -1))
	
	if version != META_PROGRESS_VERSION:
		return _migrate_profile(payload, version)
	
	return payload

## Save profile to disk with version envelope
static func save_meta_progress(profile: Dictionary) -> bool:
	if profile.is_empty():
		return false
	
	profile["last_modified_unix"] = int(Time.get_unix_time_from_system())
	var file := FileAccess.open(META_PROGRESS_PATH, FileAccess.WRITE)
	if file == null:
		return false
	
	file.store_var(profile)
	return true

## Migrate from older profile version to current version
## Strategy: preserve unlocks and milestones, drop unknown fields
static func _migrate_profile(old_payload: Dictionary, old_version: int) -> Dictionary:
	var migrated := _get_default_profile()
	
	if old_version < 0 or old_version > META_PROGRESS_VERSION:
		return migrated
	
	if old_version == 0:
		## Version 0 (nonexistent) -> version 1: preserve any difficulty_state and milestones
		if "difficulty_state" in old_payload:
			var old_state := old_payload["difficulty_state"] as Dictionary
			migrated["difficulty_state"]["current_tier"] = int(old_state.get("current_tier", TIER_APPRENTICE))
			migrated["difficulty_state"]["highest_unlocked_tier"] = int(old_state.get("highest_unlocked_tier", TIER_APPRENTICE))
		
		if "milestones" in old_payload:
			var old_milestones := old_payload["milestones"] as Dictionary
			for key in migrated["milestones"].keys():
				if key in old_milestones:
					migrated["milestones"][key] = bool(old_milestones[key])
	
	migrated["version"] = META_PROGRESS_VERSION
	return migrated

## Check if a tier is unlocked (i.e., highest_unlocked_tier >= tier)
static func is_tier_unlocked(profile: Dictionary, tier: int) -> bool:
	if not ("difficulty_state" in profile):
		return false
	var state := profile["difficulty_state"] as Dictionary
	var highest := int(state.get("highest_unlocked_tier", TIER_APPRENTICE))
	return highest >= tier

## Unlock a tier by raising highest_unlocked_tier if needed
static func unlock_tier(profile: Dictionary, tier: int) -> bool:
	if not ("difficulty_state" in profile):
		return false
	
	var state := profile["difficulty_state"] as Dictionary
	var highest := int(state.get("highest_unlocked_tier", TIER_APPRENTICE))
	
	if tier > highest:
		state["highest_unlocked_tier"] = tier
		return true
	
	return false

## Set the currently selected difficulty (must be unlocked or same as current)
static func set_current_tier(profile: Dictionary, tier: int) -> bool:
	if not is_tier_unlocked(profile, tier):
		return false
	
	var state := profile["difficulty_state"] as Dictionary
	state["current_tier"] = tier
	return true

## Get current selected tier
static func get_current_tier(profile: Dictionary) -> int:
	if not ("difficulty_state" in profile):
		return TIER_APPRENTICE
	var state := profile["difficulty_state"] as Dictionary
	return int(state.get("current_tier", TIER_APPRENTICE))

## Get highest unlocked tier
static func get_highest_unlocked_tier(profile: Dictionary) -> int:
	if not ("difficulty_state" in profile):
		return TIER_APPRENTICE
	var state := profile["difficulty_state"] as Dictionary
	return int(state.get("highest_unlocked_tier", TIER_APPRENTICE))

## Set a milestone flag
static func set_milestone(profile: Dictionary, milestone_key: String, value: bool) -> void:
	if not ("milestones" in profile):
		profile["milestones"] = {}
	var milestones := profile["milestones"] as Dictionary
	milestones[milestone_key] = value

## Get a milestone flag
static func get_milestone(profile: Dictionary, milestone_key: String) -> bool:
	if not ("milestones" in profile):
		return false
	var milestones := profile["milestones"] as Dictionary
	return bool(milestones.get(milestone_key, false))

## Update run stats
static func record_run_attempt(profile: Dictionary) -> void:
	if not ("run_stats" in profile):
		profile["run_stats"] = {"total_runs": 0, "total_clears": 0, "best_depth": 0}
	var stats := profile["run_stats"] as Dictionary
	stats["total_runs"] = int(stats.get("total_runs", 0)) + 1

static func record_run_completion(profile: Dictionary, depth: int) -> void:
	if not ("run_stats" in profile):
		profile["run_stats"] = {"total_runs": 0, "total_clears": 0, "best_depth": 0}
	var stats := profile["run_stats"] as Dictionary
	stats["total_clears"] = int(stats.get("total_clears", 0)) + 1
	var best := int(stats.get("best_depth", 0))
	if depth > best:
		stats["best_depth"] = depth

## Get run stats
static func get_run_stats(profile: Dictionary) -> Dictionary:
	if not ("run_stats" in profile):
		return {"total_runs": 0, "total_clears": 0, "best_depth": 0}
	return (profile["run_stats"] as Dictionary).duplicate()
