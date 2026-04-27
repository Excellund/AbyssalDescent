extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")
const MODE_STANDARD := "standard"
const MODE_ENDLESS := "endless"
const SETTINGS_STORE := preload("res://scripts/settings_store.gd")
const META_PROGRESS_STORE := preload("res://scripts/meta_progress_store.gd")
const ACTIVE_RUN_SAVE_PATH := "user://active_run.save"
const ACTIVE_RUN_VERSION := 1

var run_mode: int = ENUMS.RunMode.STANDARD
var master_volume_db: float = 0.0
var music_volume_db: float = -46.0
var resume_saved_run_requested: bool = false

## Meta-progression state
var meta_progress_profile: Dictionary = {}
var current_difficulty_tier: int = META_PROGRESS_STORE.TIER_APPRENTICE
var highest_unlocked_difficulty_tier: int = META_PROGRESS_STORE.TIER_APPRENTICE
var just_unlocked_tier: int = -1  ## -1 means no new unlock, otherwise the newly unlocked tier

func _ready() -> void:
	load_audio_settings()
	load_meta_progress()
	_apply_master_volume()

func set_run_mode(mode: Variant) -> void:
	if mode is int:
		var mode_int := int(mode)
		run_mode = ENUMS.RunMode.ENDLESS if mode_int == ENUMS.RunMode.ENDLESS else ENUMS.RunMode.STANDARD
		return

	var mode_text := String(mode).to_lower()
	if mode_text == MODE_ENDLESS:
		run_mode = ENUMS.RunMode.ENDLESS
		return
	run_mode = ENUMS.RunMode.STANDARD

func is_endless_mode() -> bool:
	return run_mode == ENUMS.RunMode.ENDLESS

func load_audio_settings() -> void:
	var loaded: Dictionary = SETTINGS_STORE.load_settings()
	master_volume_db = float(loaded.get("master_volume_db", master_volume_db))
	music_volume_db = float(loaded.get("music_volume_db", music_volume_db))

func set_audio_settings(master_db: float, music_db: float, persist: bool = true) -> void:
	master_volume_db = clampf(master_db, -40.0, 6.0)
	music_volume_db = clampf(music_db, -60.0, -6.0)
	_apply_master_volume()
	if persist:
		SETTINGS_STORE.save_settings(master_volume_db, music_volume_db)

func _apply_master_volume() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus, master_volume_db)

func has_saved_run() -> bool:
	return FileAccess.file_exists(ACTIVE_RUN_SAVE_PATH)

func save_active_run(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		return false
	var file := FileAccess.open(ACTIVE_RUN_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	var payload := {
		"version": ACTIVE_RUN_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"snapshot": snapshot.duplicate(true)
	}
	file.store_var(payload)
	return true

func load_active_run() -> Dictionary:
	if not has_saved_run():
		return {}
	var file := FileAccess.open(ACTIVE_RUN_SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var payload_raw: Variant = file.get_var()
	if not (payload_raw is Dictionary):
		return {}
	var payload := payload_raw as Dictionary
	if int(payload.get("version", -1)) != ACTIVE_RUN_VERSION:
		return {}
	var snapshot_raw: Variant = payload.get("snapshot", {})
	if not (snapshot_raw is Dictionary):
		return {}
	return (snapshot_raw as Dictionary).duplicate(true)

func clear_active_run() -> void:
	if not has_saved_run():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ACTIVE_RUN_SAVE_PATH))

func request_resume_saved_run() -> void:
	resume_saved_run_requested = true

func consume_resume_saved_run_request() -> bool:
	if not resume_saved_run_requested:
		return false
	resume_saved_run_requested = false
	return true

func clear_resume_saved_run_request() -> void:
	resume_saved_run_requested = false


## Load meta-progression profile from disk
func load_meta_progress() -> void:
	meta_progress_profile = META_PROGRESS_STORE.load_meta_progress()
	current_difficulty_tier = META_PROGRESS_STORE.get_current_tier(meta_progress_profile)
	highest_unlocked_difficulty_tier = META_PROGRESS_STORE.get_highest_unlocked_tier(meta_progress_profile)
	just_unlocked_tier = -1


## Save meta-progression profile to disk
func save_meta_progress() -> bool:
	return META_PROGRESS_STORE.save_meta_progress(meta_progress_profile)


## Set the current difficulty tier (must be unlocked or same as current)
func set_difficulty_tier(tier: int) -> bool:
	if META_PROGRESS_STORE.set_current_tier(meta_progress_profile, tier):
		current_difficulty_tier = tier
		return save_meta_progress()
	return false


## Unlock a difficulty tier
func unlock_difficulty_tier(tier: int) -> bool:
	var was_unlocked := META_PROGRESS_STORE.is_tier_unlocked(meta_progress_profile, tier)
	if META_PROGRESS_STORE.unlock_tier(meta_progress_profile, tier):
		highest_unlocked_difficulty_tier = META_PROGRESS_STORE.get_highest_unlocked_tier(meta_progress_profile)
		if not was_unlocked:
			just_unlocked_tier = tier
		return save_meta_progress()
	return false


## Get current difficulty tier
func get_current_difficulty_tier() -> int:
	return current_difficulty_tier


## Get highest unlocked difficulty tier
func get_highest_unlocked_difficulty_tier() -> int:
	return highest_unlocked_difficulty_tier


## Check if a tier is unlocked
func is_difficulty_tier_unlocked(tier: int) -> bool:
	return META_PROGRESS_STORE.is_tier_unlocked(meta_progress_profile, tier)


## Get and clear any newly unlocked tier (returns -1 if none)
func consume_just_unlocked_tier() -> int:
	var result := just_unlocked_tier
	just_unlocked_tier = -1
	return result


## Record run statistics
func record_run_start() -> void:
	META_PROGRESS_STORE.record_run_attempt(meta_progress_profile)


func record_run_completion(depth: int) -> void:
	META_PROGRESS_STORE.record_run_completion(meta_progress_profile, depth)
	save_meta_progress()


## Set and save a milestone
func set_milestone(key: String, value: bool) -> void:
	META_PROGRESS_STORE.set_milestone(meta_progress_profile, key, value)
	save_meta_progress()


## Get a milestone
func get_milestone(key: String) -> bool:
	return META_PROGRESS_STORE.get_milestone(meta_progress_profile, key)

