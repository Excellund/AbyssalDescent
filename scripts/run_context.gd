extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")
const MODE_STANDARD := "standard"
const MODE_ENDLESS := "endless"
const SETTINGS_STORE := preload("res://scripts/settings_store.gd")
const ACTIVE_RUN_SAVE_PATH := "user://active_run.save"
const ACTIVE_RUN_VERSION := 1

var run_mode: int = ENUMS.RunMode.STANDARD
var master_volume_db: float = 0.0
var music_volume_db: float = -46.0
var resume_saved_run_requested: bool = false

func _ready() -> void:
	load_audio_settings()
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
