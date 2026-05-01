extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")
const MODE_STANDARD := "standard"
const MODE_ENDLESS := "endless"
const SETTINGS_STORE := preload("res://scripts/settings_store.gd")
const META_PROGRESS_STORE := preload("res://scripts/meta_progress_store.gd")
const TELEMETRY_UPLOADER_SCRIPT := preload("res://scripts/telemetry_uploader.gd")
const ACTIVE_RUN_SAVE_PATH := "user://active_run.save"
const ACTIVE_RUN_VERSION := 1
const AUDIO_VOLUME_MIN_DB := -80.0
const AUDIO_VOLUME_MAX_DB := 6.0
const DISPLAY_MODE_WINDOWED := SETTINGS_STORE.DISPLAY_MODE_WINDOWED
const DISPLAY_MODE_FULLSCREEN := SETTINGS_STORE.DISPLAY_MODE_FULLSCREEN
const DISPLAY_MODE_OPTIONS := [
	{"id": DISPLAY_MODE_FULLSCREEN, "label": "Borderless Fullscreen"},
	{"id": DISPLAY_MODE_WINDOWED, "label": "Windowed"}
]
const SUPPORTED_RESOLUTIONS := [
	{"width": 3840, "height": 2160, "label": "3840 x 2160"},
	{"width": 2560, "height": 1440, "label": "2560 x 1440"},
	{"width": 1920, "height": 1080, "label": "1920 x 1080"},
	{"width": 1600, "height": 900, "label": "1600 x 900"},
	{"width": 1280, "height": 720, "label": "1280 x 720"}
]

var run_mode: int = ENUMS.RunMode.STANDARD
var master_volume_db: float = 0.0
var music_volume_db: float = -20.0
var sfx_volume_db: float = 0.0
var base_viewport_width: int = 1920
var base_viewport_height: int = 1080
var display_mode: String = SETTINGS_STORE.DEFAULT_DISPLAY_MODE
var resolution_width: int = SETTINGS_STORE.DEFAULT_RESOLUTION_WIDTH
var resolution_height: int = SETTINGS_STORE.DEFAULT_RESOLUTION_HEIGHT
var telemetry_upload_enabled: bool = SETTINGS_STORE.DEFAULT_TELEMETRY_UPLOAD_ENABLED
var telemetry_consent_asked: bool = SETTINGS_STORE.DEFAULT_TELEMETRY_CONSENT_ASKED
var resume_saved_run_requested: bool = false
var telemetry_uploader

## Meta-progression state
var meta_progress_profile: Dictionary = {}
var current_difficulty_tier: int = META_PROGRESS_STORE.TIER_PILGRIM
var highest_unlocked_difficulty_tier: int = META_PROGRESS_STORE.TIER_PILGRIM
var just_unlocked_tier: int = -1  ## -1 means no new unlock, otherwise the newly unlocked tier

func _ready() -> void:
	base_viewport_width = int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
	base_viewport_height = int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	load_settings()
	load_meta_progress()
	_apply_master_volume()
	_apply_resolution()
	telemetry_uploader = TELEMETRY_UPLOADER_SCRIPT.new()
	add_child(telemetry_uploader)
	telemetry_uploader.initialize(self)

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

func load_settings() -> void:
	var loaded: Dictionary = SETTINGS_STORE.load_settings()
	master_volume_db = clampf(float(loaded.get("master_volume_db", master_volume_db)), AUDIO_VOLUME_MIN_DB, AUDIO_VOLUME_MAX_DB)
	music_volume_db = clampf(float(loaded.get("music_volume_db", music_volume_db)), AUDIO_VOLUME_MIN_DB, AUDIO_VOLUME_MAX_DB)
	sfx_volume_db = clampf(float(loaded.get("sfx_volume_db", sfx_volume_db)), AUDIO_VOLUME_MIN_DB, AUDIO_VOLUME_MAX_DB)
	display_mode = _normalize_display_mode(String(loaded.get("display_mode", display_mode)))
	var normalized := _normalize_resolution(
		int(loaded.get("resolution_width", resolution_width)),
		int(loaded.get("resolution_height", resolution_height))
	)
	resolution_width = int(normalized.get("width", resolution_width))
	resolution_height = int(normalized.get("height", resolution_height))
	telemetry_upload_enabled = bool(loaded.get("telemetry_upload_enabled", telemetry_upload_enabled))
	telemetry_consent_asked = bool(loaded.get("telemetry_consent_asked", telemetry_consent_asked))

func _persist_settings() -> void:
	SETTINGS_STORE.save_settings(master_volume_db, music_volume_db, sfx_volume_db, resolution_width, resolution_height, display_mode, telemetry_upload_enabled, telemetry_consent_asked)

func set_audio_settings(master_db: float, music_db: float, sfx_db: float, persist: bool = true) -> void:
	master_volume_db = clampf(master_db, AUDIO_VOLUME_MIN_DB, AUDIO_VOLUME_MAX_DB)
	music_volume_db = clampf(music_db, AUDIO_VOLUME_MIN_DB, AUDIO_VOLUME_MAX_DB)
	sfx_volume_db = clampf(sfx_db, AUDIO_VOLUME_MIN_DB, AUDIO_VOLUME_MAX_DB)
	_apply_master_volume()
	if persist:
		_persist_settings()

func set_resolution_settings(width: int, height: int, persist: bool = true) -> void:
	var normalized := _normalize_resolution(width, height)
	resolution_width = int(normalized.get("width", resolution_width))
	resolution_height = int(normalized.get("height", resolution_height))
	_apply_resolution()
	if persist:
		_persist_settings()

func set_display_mode(mode: String, persist: bool = true) -> void:
	display_mode = _normalize_display_mode(mode)
	_apply_resolution()
	if persist:
		_persist_settings()

func is_telemetry_upload_enabled() -> bool:
	return telemetry_upload_enabled

func should_prompt_telemetry_consent() -> bool:
	return not telemetry_consent_asked

func set_telemetry_upload_enabled(enabled: bool, persist: bool = true, mark_asked: bool = true) -> void:
	telemetry_upload_enabled = enabled
	if mark_asked:
		telemetry_consent_asked = true
	if persist:
		_persist_settings()

func mark_telemetry_consent_asked(persist: bool = true) -> void:
	telemetry_consent_asked = true
	if persist:
		_persist_settings()

func enqueue_telemetry_payload(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	if telemetry_uploader == null:
		return
	if not telemetry_upload_enabled:
		return
	telemetry_uploader.enqueue_payload(payload)

func get_pending_telemetry_upload_count() -> int:
	if telemetry_uploader == null:
		return 0
	return int(telemetry_uploader.pending_count())

func get_display_mode_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for option in DISPLAY_MODE_OPTIONS:
		options.append(option.duplicate(true))
	return options

func is_windowed_mode() -> bool:
	return display_mode == DISPLAY_MODE_WINDOWED

func get_supported_resolution_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for option in _get_available_resolution_options():
		options.append(option.duplicate(true))
	return options

func _apply_master_volume() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus, master_volume_db)

func _apply_resolution() -> void:
	var window := get_window()
	if window == null:
		return
	var base_size := Vector2i.ZERO
	base_size.x = base_viewport_width
	base_size.y = base_viewport_height
	if window.content_scale_size != base_size:
		window.content_scale_size = base_size
	if display_mode == DISPLAY_MODE_FULLSCREEN:
		window.borderless = false
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	window.borderless = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen_index := window.current_screen
	var screen_size := DisplayServer.screen_get_size(screen_index)
	var max_w := maxi(640, screen_size.x - 80)
	var max_h := maxi(480, screen_size.y - 80)
	var new_size := Vector2i(mini(resolution_width, max_w), mini(resolution_height, max_h))
	window.size = new_size
	var screen_rect := DisplayServer.screen_get_usable_rect(screen_index)
	var offset_x := maxi(0, int(float(screen_rect.size.x - new_size.x) * 0.5))
	var offset_y := maxi(0, int(float(screen_rect.size.y - new_size.y) * 0.5))
	window.position = Vector2i(screen_rect.position.x + offset_x, screen_rect.position.y + offset_y)

func _get_available_resolution_options() -> Array[Dictionary]:
	var screen_index := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen_index)
	var options: Array[Dictionary] = []
	for option in SUPPORTED_RESOLUTIONS:
		var width := int(option.get("width", 0))
		var height := int(option.get("height", 0))
		if width <= screen_size.x and height <= screen_size.y:
			options.append(option)
	if options.is_empty():
		options.append(SUPPORTED_RESOLUTIONS[SUPPORTED_RESOLUTIONS.size() - 1])
	return options

func _normalize_resolution(width: int, height: int) -> Dictionary:
	var options := _get_available_resolution_options()
	for option in options:
		if int(option.get("width", 0)) == width and int(option.get("height", 0)) == height:
			return option
	return options[0]

func _normalize_display_mode(mode: String) -> String:
	if mode == DISPLAY_MODE_WINDOWED:
		return DISPLAY_MODE_WINDOWED
	return DISPLAY_MODE_FULLSCREEN

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


## Award permanent difficulty unlocks for a completed run on the current tier.
func award_run_clear_unlocks() -> int:
	var unlocked_tier := -1
	if not get_milestone("first_clear"):
		set_milestone("first_clear", true)
		if highest_unlocked_difficulty_tier < META_PROGRESS_STORE.TIER_DELVER and unlock_difficulty_tier(META_PROGRESS_STORE.TIER_DELVER):
			unlocked_tier = META_PROGRESS_STORE.TIER_DELVER
	if current_difficulty_tier == META_PROGRESS_STORE.TIER_DELVER and not get_milestone("first_clear_on_standard"):
		set_milestone("first_clear_on_standard", true)
		if highest_unlocked_difficulty_tier < META_PROGRESS_STORE.TIER_HARBINGER and unlock_difficulty_tier(META_PROGRESS_STORE.TIER_HARBINGER):
			unlocked_tier = META_PROGRESS_STORE.TIER_HARBINGER
	if current_difficulty_tier == META_PROGRESS_STORE.TIER_HARBINGER and not get_milestone("first_clear_on_veteran"):
		set_milestone("first_clear_on_veteran", true)
		if highest_unlocked_difficulty_tier < META_PROGRESS_STORE.TIER_FORSWORN and unlock_difficulty_tier(META_PROGRESS_STORE.TIER_FORSWORN):
			unlocked_tier = META_PROGRESS_STORE.TIER_FORSWORN
	return unlocked_tier


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


func set_last_run_outcome(outcome: String) -> void:
	META_PROGRESS_STORE.set_last_run_outcome(meta_progress_profile, outcome)
	save_meta_progress()


func get_last_run_outcome() -> String:
	return META_PROGRESS_STORE.get_last_run_outcome(meta_progress_profile)


## Set and save a milestone
func set_milestone(key: String, value: bool) -> void:
	META_PROGRESS_STORE.set_milestone(meta_progress_profile, key, value)
	save_meta_progress()


## Get a milestone
func get_milestone(key: String) -> bool:
	return META_PROGRESS_STORE.get_milestone(meta_progress_profile, key)
