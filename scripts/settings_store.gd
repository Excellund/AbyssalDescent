extends RefCounted

const SETTINGS_PATH := "user://settings.cfg"
const AUDIO_SECTION := "audio"
const DISPLAY_SECTION := "display"
const MASTER_KEY := "master_volume_db"
const MUSIC_KEY := "music_volume_db"
const DISPLAY_MODE_KEY := "display_mode"
const RESOLUTION_WIDTH_KEY := "resolution_width"
const RESOLUTION_HEIGHT_KEY := "resolution_height"
const DEFAULT_MASTER_VOLUME_DB := 0.0
const DEFAULT_MUSIC_VOLUME_DB := -20.0
const DISPLAY_MODE_WINDOWED := "windowed"
const DISPLAY_MODE_FULLSCREEN := "fullscreen"
const DEFAULT_DISPLAY_MODE := DISPLAY_MODE_FULLSCREEN
const DEFAULT_RESOLUTION_WIDTH := 1920
const DEFAULT_RESOLUTION_HEIGHT := 1080

static func load_settings() -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	if err != OK:
		return {
			"master_volume_db": DEFAULT_MASTER_VOLUME_DB,
			"music_volume_db": DEFAULT_MUSIC_VOLUME_DB,
			"display_mode": DEFAULT_DISPLAY_MODE,
			"resolution_width": DEFAULT_RESOLUTION_WIDTH,
			"resolution_height": DEFAULT_RESOLUTION_HEIGHT
		}
	return {
		"master_volume_db": float(config.get_value(AUDIO_SECTION, MASTER_KEY, DEFAULT_MASTER_VOLUME_DB)),
		"music_volume_db": float(config.get_value(AUDIO_SECTION, MUSIC_KEY, DEFAULT_MUSIC_VOLUME_DB)),
		"display_mode": String(config.get_value(DISPLAY_SECTION, DISPLAY_MODE_KEY, DEFAULT_DISPLAY_MODE)),
		"resolution_width": int(config.get_value(DISPLAY_SECTION, RESOLUTION_WIDTH_KEY, DEFAULT_RESOLUTION_WIDTH)),
		"resolution_height": int(config.get_value(DISPLAY_SECTION, RESOLUTION_HEIGHT_KEY, DEFAULT_RESOLUTION_HEIGHT))
	}

static func save_settings(master_volume_db: float, music_volume_db: float, resolution_width: int = DEFAULT_RESOLUTION_WIDTH, resolution_height: int = DEFAULT_RESOLUTION_HEIGHT, display_mode: String = DEFAULT_DISPLAY_MODE) -> void:
	var config := ConfigFile.new()
	config.set_value(AUDIO_SECTION, MASTER_KEY, master_volume_db)
	config.set_value(AUDIO_SECTION, MUSIC_KEY, music_volume_db)
	config.set_value(DISPLAY_SECTION, RESOLUTION_WIDTH_KEY, resolution_width)
	config.set_value(DISPLAY_SECTION, RESOLUTION_HEIGHT_KEY, resolution_height)
	config.set_value(DISPLAY_SECTION, DISPLAY_MODE_KEY, display_mode)
	config.save(SETTINGS_PATH)
