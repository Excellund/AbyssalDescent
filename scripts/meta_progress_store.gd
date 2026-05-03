## Persistent meta-progression: difficulty unlocks, milestones, and long-term player state
## Survives across version updates and active-run save changes
## Version envelope protects against data corruption and enables migration

extends RefCounted

const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")
const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")

const META_PROGRESS_PATH := "user://meta_progress.save"
const META_PROGRESS_VERSION := 2

const TIER_NAMES := {
	BEARING_ENUMS.BearingTier.PILGRIM: "Pilgrim",
	BEARING_ENUMS.BearingTier.DELVER: "Delver",
	BEARING_ENUMS.BearingTier.HARBINGER: "Harbinger",
	BEARING_ENUMS.BearingTier.FORSWORN: "Forsworn"
}

const TIER_DESCRIPTIONS := {
	BEARING_ENUMS.BearingTier.PILGRIM: "The descent as intended.",
	BEARING_ENUMS.BearingTier.DELVER: "Harder. Faster. Less forgiving.",
	BEARING_ENUMS.BearingTier.HARBINGER: "A serious test. Few survive it.",
	BEARING_ENUMS.BearingTier.FORSWORN: "Punishing in every way."
}

## Default profile for new players
static func _get_default_profile() -> Dictionary:
	return {
		"version": META_PROGRESS_VERSION,
		"created_at_unix": int(Time.get_unix_time_from_system()),
		"last_modified_unix": int(Time.get_unix_time_from_system()),
		"difficulty_state": {
			"current_tier": BEARING_ENUMS.BearingTier.PILGRIM,
			"highest_unlocked_tier": BEARING_ENUMS.BearingTier.PILGRIM
		},
		"character_state": {
			"selected_character_id": CHARACTER_REGISTRY.get_default_character_id(),
			"unlocked_character_ids": CHARACTER_REGISTRY.get_launch_character_ids()
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
			"best_depth": 0,
			"last_outcome": "none"
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

	if "difficulty_state" in old_payload:
		var old_state := old_payload["difficulty_state"] as Dictionary
		migrated["difficulty_state"]["current_tier"] = int(old_state.get("current_tier", BEARING_ENUMS.BearingTier.PILGRIM))
		migrated["difficulty_state"]["highest_unlocked_tier"] = int(old_state.get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM))

	if "milestones" in old_payload:
		var old_milestones := old_payload["milestones"] as Dictionary
		for key in migrated["milestones"].keys():
			if key in old_milestones:
				migrated["milestones"][key] = bool(old_milestones[key])

	if "run_stats" in old_payload:
		var old_stats := old_payload["run_stats"] as Dictionary
		for key in migrated["run_stats"].keys():
			if key in old_stats:
				migrated["run_stats"][key] = old_stats[key]

	if "character_state" in old_payload:
		var old_character_state: Dictionary = old_payload["character_state"] as Dictionary
		var unlocked_raw: Variant = old_character_state.get("unlocked_character_ids", [])
		var unlocked: Array[String] = []
		if unlocked_raw is Array:
			for id_value in unlocked_raw:
				var id: String = _normalize_character_id(id_value)
				if CHARACTER_REGISTRY.is_known_character_id(id) and not unlocked.has(id):
					unlocked.append(id)
		if unlocked.is_empty():
			unlocked = CHARACTER_REGISTRY.get_launch_character_ids()
		migrated["character_state"]["unlocked_character_ids"] = unlocked
		var selected: String = _normalize_character_id(old_character_state.get("selected_character_id", CHARACTER_REGISTRY.get_default_character_id()))
		if not unlocked.has(selected):
			selected = String(unlocked[0])
		migrated["character_state"]["selected_character_id"] = selected
	
	migrated["version"] = META_PROGRESS_VERSION
	return migrated

static func _normalize_character_id(value: Variant) -> String:
	return String(value).strip_edges().to_lower()

static func _get_character_state(profile: Dictionary) -> Dictionary:
	if not ("character_state" in profile):
		profile["character_state"] = {
			"selected_character_id": CHARACTER_REGISTRY.get_default_character_id(),
			"unlocked_character_ids": CHARACTER_REGISTRY.get_launch_character_ids()
		}
	return profile["character_state"] as Dictionary

static func get_unlocked_character_ids(profile: Dictionary) -> Array[String]:
	var state: Dictionary = _get_character_state(profile)
	var unlocked_raw: Variant = state.get("unlocked_character_ids", [])
	var unlocked: Array[String] = []
	if unlocked_raw is Array:
		for id_value in unlocked_raw:
			var id: String = _normalize_character_id(id_value)
			if CHARACTER_REGISTRY.is_known_character_id(id) and not unlocked.has(id):
				unlocked.append(id)
	var launch_ids: Array[String] = CHARACTER_REGISTRY.get_launch_character_ids()
	for launch_id in launch_ids:
		if not unlocked.has(launch_id):
			unlocked.append(launch_id)
	if unlocked.is_empty():
		unlocked = launch_ids
	state["unlocked_character_ids"] = unlocked
	return unlocked

static func is_character_unlocked(profile: Dictionary, character_id: String) -> bool:
	var normalized: String = _normalize_character_id(character_id)
	if normalized.is_empty():
		return false
	return get_unlocked_character_ids(profile).has(normalized)

static func unlock_character(profile: Dictionary, character_id: String) -> bool:
	var normalized: String = _normalize_character_id(character_id)
	if not CHARACTER_REGISTRY.is_known_character_id(normalized):
		return false
	var unlocked: Array[String] = get_unlocked_character_ids(profile)
	if unlocked.has(normalized):
		return false
	unlocked.append(normalized)
	var state: Dictionary = _get_character_state(profile)
	state["unlocked_character_ids"] = unlocked
	return true

static func get_selected_character_id(profile: Dictionary) -> String:
	var state: Dictionary = _get_character_state(profile)
	var unlocked: Array[String] = get_unlocked_character_ids(profile)
	var selected: String = _normalize_character_id(state.get("selected_character_id", CHARACTER_REGISTRY.get_default_character_id()))
	if unlocked.has(selected):
		return selected
	selected = String(unlocked[0])
	state["selected_character_id"] = selected
	return selected

static func set_selected_character_id(profile: Dictionary, character_id: String) -> bool:
	var normalized: String = _normalize_character_id(character_id)
	if normalized.is_empty():
		return false
	if not is_character_unlocked(profile, normalized):
		return false
	var state: Dictionary = _get_character_state(profile)
	state["selected_character_id"] = normalized
	return true

## Check if a tier is unlocked (i.e., highest_unlocked_tier >= tier)
static func is_tier_unlocked(profile: Dictionary, tier: int) -> bool:
	if not ("difficulty_state" in profile):
		return false
	var state := profile["difficulty_state"] as Dictionary
	var highest := int(state.get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM))
	return highest >= tier

## Unlock a tier by raising highest_unlocked_tier if needed
static func unlock_tier(profile: Dictionary, tier: int) -> bool:
	if not ("difficulty_state" in profile):
		return false
	
	var state := profile["difficulty_state"] as Dictionary
	var highest := int(state.get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM))
	
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
		return BEARING_ENUMS.BearingTier.PILGRIM
	var state := profile["difficulty_state"] as Dictionary
	return int(state.get("current_tier", BEARING_ENUMS.BearingTier.PILGRIM))

## Get highest unlocked tier
static func get_highest_unlocked_tier(profile: Dictionary) -> int:
	if not ("difficulty_state" in profile):
		return BEARING_ENUMS.BearingTier.PILGRIM
	var state := profile["difficulty_state"] as Dictionary
	return int(state.get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM))

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
		profile["run_stats"] = {"total_runs": 0, "total_clears": 0, "best_depth": 0, "last_outcome": "none"}
	var stats := profile["run_stats"] as Dictionary
	stats["total_runs"] = int(stats.get("total_runs", 0)) + 1

static func record_run_completion(profile: Dictionary, depth: int) -> void:
	if not ("run_stats" in profile):
		profile["run_stats"] = {"total_runs": 0, "total_clears": 0, "best_depth": 0, "last_outcome": "none"}
	var stats := profile["run_stats"] as Dictionary
	stats["total_clears"] = int(stats.get("total_clears", 0)) + 1
	stats["last_outcome"] = "clear"
	var best := int(stats.get("best_depth", 0))
	if depth > best:
		stats["best_depth"] = depth

static func set_last_run_outcome(profile: Dictionary, outcome: String) -> void:
	if not ("run_stats" in profile):
		profile["run_stats"] = {"total_runs": 0, "total_clears": 0, "best_depth": 0, "last_outcome": "none"}
	var stats := profile["run_stats"] as Dictionary
	stats["last_outcome"] = outcome

static func get_last_run_outcome(profile: Dictionary) -> String:
	if not ("run_stats" in profile):
		return "none"
	var stats := profile["run_stats"] as Dictionary
	return String(stats.get("last_outcome", "none"))

## Get run stats
static func get_run_stats(profile: Dictionary) -> Dictionary:
	if not ("run_stats" in profile):
		return {"total_runs": 0, "total_clears": 0, "best_depth": 0, "last_outcome": "none"}
	return (profile["run_stats"] as Dictionary).duplicate()
