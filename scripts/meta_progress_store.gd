## Persistent meta-progression: difficulty unlocks, milestones, and long-term player state
## Survives across version updates and active-run save changes
## Version envelope protects against data corruption and enables migration

extends RefCounted

const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")
const CHARACTER_REGISTRY := preload("res://scripts/character_registry.gd")

const META_PROGRESS_PATH := "user://meta_progress.save"
const META_PROGRESS_VERSION := 4

const CHARACTER_UNLOCK_CHAIN := [
	"bastion",
	"hexweaver",
	"veilstrider",
	"riftlancer"
]

## Endgame chase state (v3): see /memories/session/plan.md
## Ascension = stackable difficulty modifiers above Forsworn (per-character heat record).
## Oaths    = achievement-style goals evaluated off run summary; grant catalysts/modifiers.
## Catalysts = pre-run gameplay augments equipped per-character before a descent.

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
			"highest_unlocked_tier": BEARING_ENUMS.BearingTier.PILGRIM,
			"per_character": _default_per_character_difficulty_state()
		},
		"character_state": {
			"selected_character_id": CHARACTER_REGISTRY.get_default_character_id(),
			"unlocked_character_ids": [CHARACTER_REGISTRY.get_default_character_id()]
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
		},
		"ascension_state": {
			"per_character": {}
		},
		"oaths_state": {
			"completed_oath_ids": [],
			"progress": {},
			"claimed_reward_ids": []
		},
		"catalysts_state": {
			"unlocked_ids": [],
			"equipped_per_character": {}
		}
	}

static func _default_per_character_difficulty_state() -> Dictionary:
	var per_character: Dictionary = {}
	for character_id in CHARACTER_UNLOCK_CHAIN:
		if CHARACTER_REGISTRY.is_known_character_id(character_id):
			per_character[character_id] = {"highest_unlocked_tier": BEARING_ENUMS.BearingTier.PILGRIM}
	for character_id in CHARACTER_REGISTRY.get_launch_character_ids():
		if not per_character.has(character_id):
			per_character[character_id] = {"highest_unlocked_tier": BEARING_ENUMS.BearingTier.PILGRIM}
	return per_character

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
		if old_state.get("per_character") is Dictionary:
			migrated["difficulty_state"]["per_character"] = (old_state.get("per_character") as Dictionary).duplicate(true)

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
			unlocked = [CHARACTER_REGISTRY.get_default_character_id()]
		migrated["character_state"]["unlocked_character_ids"] = unlocked
		var selected: String = _normalize_character_id(old_character_state.get("selected_character_id", CHARACTER_REGISTRY.get_default_character_id()))
		if not unlocked.has(selected):
			selected = String(unlocked[0])
		migrated["character_state"]["selected_character_id"] = selected

	if "ascension_state" in old_payload and old_payload["ascension_state"] is Dictionary:
		migrated["ascension_state"] = (old_payload["ascension_state"] as Dictionary).duplicate(true)
		if not (migrated["ascension_state"].get("per_character") is Dictionary):
			migrated["ascension_state"]["per_character"] = {}

	if "oaths_state" in old_payload and old_payload["oaths_state"] is Dictionary:
		var old_oaths: Dictionary = old_payload["oaths_state"] as Dictionary
		var completed_raw: Variant = old_oaths.get("completed_oath_ids", [])
		var completed: Array = []
		if completed_raw is Array:
			for entry in completed_raw:
				completed.append(String(entry))
		migrated["oaths_state"]["completed_oath_ids"] = completed
		var progress_raw: Variant = old_oaths.get("progress", {})
		if progress_raw is Dictionary:
			migrated["oaths_state"]["progress"] = (progress_raw as Dictionary).duplicate(true)
		var claimed_raw: Variant = old_oaths.get("claimed_reward_ids", [])
		var claimed: Array = []
		if claimed_raw is Array:
			for entry in claimed_raw:
				claimed.append(String(entry))
		migrated["oaths_state"]["claimed_reward_ids"] = claimed

	if "catalysts_state" in old_payload and old_payload["catalysts_state"] is Dictionary:
		var old_cats: Dictionary = old_payload["catalysts_state"] as Dictionary
		var unlocked_cat_raw: Variant = old_cats.get("unlocked_ids", [])
		var unlocked_cats: Array = []
		if unlocked_cat_raw is Array:
			for entry in unlocked_cat_raw:
				unlocked_cats.append(String(entry))
		migrated["catalysts_state"]["unlocked_ids"] = unlocked_cats
		var equipped_raw: Variant = old_cats.get("equipped_per_character", {})
		if equipped_raw is Dictionary:
			var equipped_clean: Dictionary = {}
			for key in (equipped_raw as Dictionary).keys():
				var char_id: String = _normalize_character_id(key)
				if not CHARACTER_REGISTRY.is_known_character_id(char_id):
					continue
				var list_raw: Variant = (equipped_raw as Dictionary)[key]
				var list_clean: Array = []
				if list_raw is Array:
					for entry in list_raw:
						list_clean.append(String(entry))
				equipped_clean[char_id] = list_clean
			migrated["catalysts_state"]["equipped_per_character"] = equipped_clean

	if old_version < 4:
		var old_global_highest := int(migrated["difficulty_state"].get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM))
		var per_character_migrated: Dictionary = {}
		for character_id in CHARACTER_REGISTRY.get_launch_character_ids():
			per_character_migrated[character_id] = {"highest_unlocked_tier": old_global_highest}
		migrated["difficulty_state"]["per_character"] = per_character_migrated

	if "profile" in old_payload and old_payload["profile"] is Dictionary:
		migrated["profile"] = (old_payload["profile"] as Dictionary).duplicate(true)

	_ensure_difficulty_state_integrity(migrated)

	migrated["version"] = META_PROGRESS_VERSION
	return migrated

static func _normalize_character_id(value: Variant) -> String:
	return String(value).strip_edges().to_lower()

static func _get_character_state(profile: Dictionary) -> Dictionary:
	if not ("character_state" in profile):
		profile["character_state"] = {
			"selected_character_id": CHARACTER_REGISTRY.get_default_character_id(),
			"unlocked_character_ids": [CHARACTER_REGISTRY.get_default_character_id()]
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
	var default_character_id := CHARACTER_REGISTRY.get_default_character_id()
	if not unlocked.has(default_character_id):
		unlocked.append(default_character_id)
	if unlocked.is_empty():
		unlocked = [default_character_id]
	state["unlocked_character_ids"] = unlocked
	return unlocked

static func get_next_character_unlock_for_clear(profile: Dictionary, cleared_character_id: String) -> String:
	var cleared: String = _normalize_character_id(cleared_character_id)
	if cleared.is_empty():
		return ""
	var chain_index := CHARACTER_UNLOCK_CHAIN.find(cleared)
	if chain_index < 0:
		return ""
	if chain_index + 1 >= CHARACTER_UNLOCK_CHAIN.size():
		return ""
	var next_character_id := String(CHARACTER_UNLOCK_CHAIN[chain_index + 1])
	if not CHARACTER_REGISTRY.is_known_character_id(next_character_id):
		return ""
	if is_character_unlocked(profile, next_character_id):
		return ""
	return next_character_id

static func unlock_next_character_for_clear(profile: Dictionary, cleared_character_id: String) -> String:
	var next_character_id := get_next_character_unlock_for_clear(profile, cleared_character_id)
	if next_character_id.is_empty():
		return ""
	if unlock_character(profile, next_character_id):
		return next_character_id
	return ""

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

static func _get_difficulty_state(profile: Dictionary) -> Dictionary:
	if not ("difficulty_state" in profile) or not (profile["difficulty_state"] is Dictionary):
		profile["difficulty_state"] = {
			"current_tier": BEARING_ENUMS.BearingTier.PILGRIM,
			"highest_unlocked_tier": BEARING_ENUMS.BearingTier.PILGRIM,
			"per_character": _default_per_character_difficulty_state()
		}
	var state := profile["difficulty_state"] as Dictionary
	if not (state.get("per_character") is Dictionary):
		state["per_character"] = _default_per_character_difficulty_state()
	_ensure_difficulty_state_integrity(profile)
	return state

static func _ensure_difficulty_state_integrity(profile: Dictionary) -> void:
	if not ("difficulty_state" in profile) or not (profile["difficulty_state"] is Dictionary):
		return
	var state := profile["difficulty_state"] as Dictionary
	if not (state.get("per_character") is Dictionary):
		state["per_character"] = _default_per_character_difficulty_state()
	var per_character := state["per_character"] as Dictionary
	for character_id in CHARACTER_REGISTRY.get_launch_character_ids():
		if not (per_character.get(character_id) is Dictionary):
			per_character[character_id] = {"highest_unlocked_tier": BEARING_ENUMS.BearingTier.PILGRIM}
		else:
			var entry := per_character[character_id] as Dictionary
			entry["highest_unlocked_tier"] = clampi(int(entry.get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM)), BEARING_ENUMS.BearingTier.PILGRIM, BEARING_ENUMS.BearingTier.FORSWORN)
	state["highest_unlocked_tier"] = _compute_global_highest_unlocked_tier(state)

static func _compute_global_highest_unlocked_tier(state: Dictionary) -> int:
	if not (state.get("per_character") is Dictionary):
		return clampi(int(state.get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM)), BEARING_ENUMS.BearingTier.PILGRIM, BEARING_ENUMS.BearingTier.FORSWORN)
	var per_character := state["per_character"] as Dictionary
	var highest := BEARING_ENUMS.BearingTier.PILGRIM
	for character_id in per_character.keys():
		if not (per_character[character_id] is Dictionary):
			continue
		var entry := per_character[character_id] as Dictionary
		highest = maxi(highest, clampi(int(entry.get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM)), BEARING_ENUMS.BearingTier.PILGRIM, BEARING_ENUMS.BearingTier.FORSWORN))
	return highest

static func get_character_highest_unlocked_tier(profile: Dictionary, character_id: String) -> int:
	var normalized: String = _normalize_character_id(character_id)
	if normalized.is_empty() or not CHARACTER_REGISTRY.is_known_character_id(normalized):
		normalized = CHARACTER_REGISTRY.get_default_character_id()
	var state := _get_difficulty_state(profile)
	var per_character := state["per_character"] as Dictionary
	if not (per_character.get(normalized) is Dictionary):
		per_character[normalized] = {"highest_unlocked_tier": BEARING_ENUMS.BearingTier.PILGRIM}
	var record := per_character[normalized] as Dictionary
	return clampi(int(record.get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM)), BEARING_ENUMS.BearingTier.PILGRIM, BEARING_ENUMS.BearingTier.FORSWORN)

static func is_character_tier_unlocked(profile: Dictionary, character_id: String, tier: int) -> bool:
	var target_tier := clampi(tier, BEARING_ENUMS.BearingTier.PILGRIM, BEARING_ENUMS.BearingTier.FORSWORN)
	return get_character_highest_unlocked_tier(profile, character_id) >= target_tier

static func unlock_character_tier(profile: Dictionary, character_id: String, tier: int) -> bool:
	var normalized: String = _normalize_character_id(character_id)
	if normalized.is_empty() or not CHARACTER_REGISTRY.is_known_character_id(normalized):
		return false
	var target_tier := clampi(tier, BEARING_ENUMS.BearingTier.PILGRIM, BEARING_ENUMS.BearingTier.FORSWORN)
	var state := _get_difficulty_state(profile)
	var per_character := state["per_character"] as Dictionary
	if not (per_character.get(normalized) is Dictionary):
		per_character[normalized] = {"highest_unlocked_tier": BEARING_ENUMS.BearingTier.PILGRIM}
	var record := per_character[normalized] as Dictionary
	var highest_for_character := clampi(int(record.get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM)), BEARING_ENUMS.BearingTier.PILGRIM, BEARING_ENUMS.BearingTier.FORSWORN)
	if target_tier <= highest_for_character:
		return false
	record["highest_unlocked_tier"] = target_tier
	state["highest_unlocked_tier"] = _compute_global_highest_unlocked_tier(state)
	return true

static func set_current_tier_for_character(profile: Dictionary, character_id: String, tier: int) -> bool:
	if not is_character_tier_unlocked(profile, character_id, tier):
		return false
	var state := _get_difficulty_state(profile)
	state["current_tier"] = clampi(tier, BEARING_ENUMS.BearingTier.PILGRIM, BEARING_ENUMS.BearingTier.FORSWORN)
	return true

## Check if a tier is unlocked (i.e., highest_unlocked_tier >= tier)
static func is_tier_unlocked(profile: Dictionary, tier: int) -> bool:
	var state := _get_difficulty_state(profile)
	var highest := int(state.get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM))
	return highest >= tier

## Unlock a tier by raising highest_unlocked_tier if needed
static func unlock_tier(profile: Dictionary, tier: int) -> bool:
	var state := _get_difficulty_state(profile)
	var highest := int(state.get("highest_unlocked_tier", BEARING_ENUMS.BearingTier.PILGRIM))
	
	if tier > highest:
		state["highest_unlocked_tier"] = tier
		return true
	
	return false

## Set the currently selected difficulty (must be unlocked or same as current)
static func set_current_tier(profile: Dictionary, tier: int) -> bool:
	if not is_tier_unlocked(profile, tier):
		return false
	var state := _get_difficulty_state(profile)
	state["current_tier"] = tier
	return true

## Get current selected tier
static func get_current_tier(profile: Dictionary) -> int:
	var state := _get_difficulty_state(profile)
	return int(state.get("current_tier", BEARING_ENUMS.BearingTier.PILGRIM))

## Get highest unlocked tier
static func get_highest_unlocked_tier(profile: Dictionary) -> int:
	var state := _get_difficulty_state(profile)
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

## --- Ascension state (per-character) -------------------------------------------------

static func _get_ascension_state(profile: Dictionary) -> Dictionary:
	if not ("ascension_state" in profile) or not (profile["ascension_state"] is Dictionary):
		profile["ascension_state"] = {"per_character": {}}
	var state: Dictionary = profile["ascension_state"] as Dictionary
	if not (state.get("per_character") is Dictionary):
		state["per_character"] = {}
	return state

static func _get_ascension_record(profile: Dictionary, character_id: String) -> Dictionary:
	var normalized: String = _normalize_character_id(character_id)
	var state: Dictionary = _get_ascension_state(profile)
	var per_char: Dictionary = state["per_character"] as Dictionary
	if not (per_char.get(normalized) is Dictionary):
		per_char[normalized] = {
			"highest_completed_rank": 0,
			"current_loadout": [],
			"total_runs_at_rank": {}
		}
	return per_char[normalized] as Dictionary

static func get_ascension_highest_rank(profile: Dictionary, character_id: String) -> int:
	var record: Dictionary = _get_ascension_record(profile, character_id)
	return int(record.get("highest_completed_rank", 0))

static func record_ascension_clear(profile: Dictionary, character_id: String, rank: int) -> bool:
	if rank <= 0:
		return false
	var record: Dictionary = _get_ascension_record(profile, character_id)
	var current: int = int(record.get("highest_completed_rank", 0))
	if rank > current:
		record["highest_completed_rank"] = rank
		return true
	return false

static func record_forsworn_clear(profile: Dictionary, character_id: String) -> bool:
	var record: Dictionary = _get_ascension_record(profile, character_id)
	if bool(record.get("cleared_forsworn", false)):
		return false
	record["cleared_forsworn"] = true
	return true

static func has_cleared_forsworn(profile: Dictionary, character_id: String) -> bool:
	var record: Dictionary = _get_ascension_record(profile, character_id)
	return bool(record.get("cleared_forsworn", false))

static func get_ascension_loadout(profile: Dictionary, character_id: String) -> Array[String]:
	var record: Dictionary = _get_ascension_record(profile, character_id)
	var raw: Variant = record.get("current_loadout", [])
	var out: Array[String] = []
	if raw is Array:
		for entry in raw:
			out.append(String(entry))
	return out

static func set_ascension_loadout(profile: Dictionary, character_id: String, modifier_ids: Array) -> void:
	var record: Dictionary = _get_ascension_record(profile, character_id)
	var clean: Array = []
	for entry in modifier_ids:
		var id: String = String(entry).strip_edges()
		if id.is_empty() or clean.has(id):
			continue
		clean.append(id)
	record["current_loadout"] = clean

static func record_ascension_attempt(profile: Dictionary, character_id: String, rank: int) -> void:
	var record: Dictionary = _get_ascension_record(profile, character_id)
	var counts_raw: Variant = record.get("total_runs_at_rank", {})
	var counts: Dictionary = counts_raw if counts_raw is Dictionary else {}
	var key: String = str(rank)
	counts[key] = int(counts.get(key, 0)) + 1
	record["total_runs_at_rank"] = counts

## --- Oaths state ---------------------------------------------------------------------

static func _get_oaths_state(profile: Dictionary) -> Dictionary:
	if not ("oaths_state" in profile) or not (profile["oaths_state"] is Dictionary):
		profile["oaths_state"] = {
			"completed_oath_ids": [],
			"progress": {},
			"claimed_reward_ids": []
		}
	return profile["oaths_state"] as Dictionary

static func get_completed_oath_ids(profile: Dictionary) -> Array[String]:
	var state: Dictionary = _get_oaths_state(profile)
	var raw: Variant = state.get("completed_oath_ids", [])
	var out: Array[String] = []
	if raw is Array:
		for entry in raw:
			out.append(String(entry))
	return out

static func is_oath_completed(profile: Dictionary, oath_id: String) -> bool:
	return get_completed_oath_ids(profile).has(String(oath_id))

static func mark_oath_completed(profile: Dictionary, oath_id: String) -> bool:
	var id: String = String(oath_id).strip_edges()
	if id.is_empty():
		return false
	var state: Dictionary = _get_oaths_state(profile)
	var raw: Variant = state.get("completed_oath_ids", [])
	var list: Array = raw if raw is Array else []
	for entry in list:
		if String(entry) == id:
			return false
	list.append(id)
	state["completed_oath_ids"] = list
	return true

static func get_oath_progress(profile: Dictionary, oath_id: String) -> Dictionary:
	var state: Dictionary = _get_oaths_state(profile)
	var progress_raw: Variant = state.get("progress", {})
	if not (progress_raw is Dictionary):
		return {}
	var progress: Dictionary = progress_raw as Dictionary
	var entry: Variant = progress.get(oath_id, {})
	if entry is Dictionary:
		return (entry as Dictionary).duplicate(true)
	return {}

static func set_oath_progress(profile: Dictionary, oath_id: String, tracker: Dictionary) -> void:
	var state: Dictionary = _get_oaths_state(profile)
	var progress_raw: Variant = state.get("progress", {})
	var progress: Dictionary = progress_raw if progress_raw is Dictionary else {}
	progress[oath_id] = tracker.duplicate(true)
	state["progress"] = progress

static func mark_oath_reward_claimed(profile: Dictionary, oath_id: String) -> bool:
	var id: String = String(oath_id).strip_edges()
	if id.is_empty():
		return false
	var state: Dictionary = _get_oaths_state(profile)
	var raw: Variant = state.get("claimed_reward_ids", [])
	var list: Array = raw if raw is Array else []
	for entry in list:
		if String(entry) == id:
			return false
	list.append(id)
	state["claimed_reward_ids"] = list
	return true

static func is_oath_reward_claimed(profile: Dictionary, oath_id: String) -> bool:
	var state: Dictionary = _get_oaths_state(profile)
	var raw: Variant = state.get("claimed_reward_ids", [])
	if not (raw is Array):
		return false
	for entry in raw:
		if String(entry) == String(oath_id):
			return true
	return false

## --- Catalysts state -----------------------------------------------------------------

static func _get_catalysts_state(profile: Dictionary) -> Dictionary:
	if not ("catalysts_state" in profile) or not (profile["catalysts_state"] is Dictionary):
		profile["catalysts_state"] = {
			"unlocked_ids": [],
			"equipped_per_character": {}
		}
	return profile["catalysts_state"] as Dictionary

static func get_unlocked_catalyst_ids(profile: Dictionary) -> Array[String]:
	var state: Dictionary = _get_catalysts_state(profile)
	var raw: Variant = state.get("unlocked_ids", [])
	var out: Array[String] = []
	if raw is Array:
		for entry in raw:
			out.append(String(entry))
	return out

static func unlock_catalyst(profile: Dictionary, catalyst_id: String) -> bool:
	var id: String = String(catalyst_id).strip_edges()
	if id.is_empty():
		return false
	var state: Dictionary = _get_catalysts_state(profile)
	var raw: Variant = state.get("unlocked_ids", [])
	var list: Array = raw if raw is Array else []
	for entry in list:
		if String(entry) == id:
			return false
	list.append(id)
	state["unlocked_ids"] = list
	return true

static func get_equipped_catalyst_ids(profile: Dictionary, character_id: String) -> Array[String]:
	var state: Dictionary = _get_catalysts_state(profile)
	var equipped_raw: Variant = state.get("equipped_per_character", {})
	if not (equipped_raw is Dictionary):
		return []
	var normalized: String = _normalize_character_id(character_id)
	var raw: Variant = (equipped_raw as Dictionary).get(normalized, [])
	var out: Array[String] = []
	if raw is Array:
		for entry in raw:
			out.append(String(entry))
	return out

static func set_equipped_catalyst_ids(profile: Dictionary, character_id: String, catalyst_ids: Array) -> void:
	var normalized: String = _normalize_character_id(character_id)
	if not CHARACTER_REGISTRY.is_known_character_id(normalized):
		return
	var state: Dictionary = _get_catalysts_state(profile)
	var equipped_raw: Variant = state.get("equipped_per_character", {})
	var equipped: Dictionary = equipped_raw if equipped_raw is Dictionary else {}
	var unlocked: Array[String] = get_unlocked_catalyst_ids(profile)
	var clean: Array = []
	for entry in catalyst_ids:
		var id: String = String(entry).strip_edges()
		if id.is_empty() or clean.has(id):
			continue
		if not unlocked.has(id):
			continue
		clean.append(id)
	equipped[normalized] = clean
	state["equipped_per_character"] = equipped
