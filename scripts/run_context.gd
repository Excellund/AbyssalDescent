extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")
const MODE_STANDARD := "standard"
const MODE_ENDLESS := "endless"
const SETTINGS_STORE := preload("res://scripts/settings_store.gd")

var run_mode: int = ENUMS.RunMode.STANDARD
var master_volume_db: float = 0.0
var music_volume_db: float = -46.0

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
