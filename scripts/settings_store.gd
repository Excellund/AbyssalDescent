extends RefCounted

const SETTINGS_PATH := "user://settings.cfg"
const AUDIO_SECTION := "audio"
const MASTER_KEY := "master_volume_db"
const MUSIC_KEY := "music_volume_db"
const DEFAULT_MASTER_VOLUME_DB := 0.0
const DEFAULT_MUSIC_VOLUME_DB := -20.0

static func load_settings() -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	if err != OK:
		return {
			"master_volume_db": DEFAULT_MASTER_VOLUME_DB,
			"music_volume_db": DEFAULT_MUSIC_VOLUME_DB
		}
	return {
		"master_volume_db": float(config.get_value(AUDIO_SECTION, MASTER_KEY, DEFAULT_MASTER_VOLUME_DB)),
		"music_volume_db": float(config.get_value(AUDIO_SECTION, MUSIC_KEY, DEFAULT_MUSIC_VOLUME_DB))
	}

static func save_settings(master_volume_db: float, music_volume_db: float) -> void:
	var config := ConfigFile.new()
	config.set_value(AUDIO_SECTION, MASTER_KEY, master_volume_db)
	config.set_value(AUDIO_SECTION, MUSIC_KEY, music_volume_db)
	config.save(SETTINGS_PATH)
