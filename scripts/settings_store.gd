extends RefCounted

const SETTINGS_PATH := "user://settings.cfg"
const AUDIO_SECTION := "audio"
const DISPLAY_SECTION := "display"
const MASTER_KEY := "master_volume_db"
const MUSIC_KEY := "music_volume_db"
const SFX_KEY := "sfx_volume_db"
const DISPLAY_MODE_KEY := "display_mode"
const RESOLUTION_WIDTH_KEY := "resolution_width"
const RESOLUTION_HEIGHT_KEY := "resolution_height"
const TELEMETRY_SECTION := "telemetry"
const TELEMETRY_UPLOAD_ENABLED_KEY := "upload_enabled"
const TELEMETRY_CONSENT_ASKED_KEY := "consent_asked"
const UPDATE_SECTION := "update"
const SKIPPED_VERSION_KEY := "skipped_version"
const DEFAULT_MASTER_VOLUME_DB := 0.0
const DEFAULT_MUSIC_VOLUME_DB := -20.0
const DEFAULT_SFX_VOLUME_DB := 0.0
const DISPLAY_MODE_WINDOWED := "windowed"
const DISPLAY_MODE_FULLSCREEN := "fullscreen"
const DEFAULT_DISPLAY_MODE := DISPLAY_MODE_FULLSCREEN
const DEFAULT_RESOLUTION_WIDTH := 1920
const DEFAULT_RESOLUTION_HEIGHT := 1080
const DEFAULT_TELEMETRY_UPLOAD_ENABLED := false
const DEFAULT_TELEMETRY_CONSENT_ASKED := false
const DEFAULT_SKIPPED_UPDATE_VERSION := ""

static func load_settings() -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	if err != OK:
		return {
			"master_volume_db": DEFAULT_MASTER_VOLUME_DB,
			"music_volume_db": DEFAULT_MUSIC_VOLUME_DB,
			"sfx_volume_db": DEFAULT_SFX_VOLUME_DB,
			"display_mode": DEFAULT_DISPLAY_MODE,
			"resolution_width": DEFAULT_RESOLUTION_WIDTH,
			"resolution_height": DEFAULT_RESOLUTION_HEIGHT,
			"telemetry_upload_enabled": DEFAULT_TELEMETRY_UPLOAD_ENABLED,
			"telemetry_consent_asked": DEFAULT_TELEMETRY_CONSENT_ASKED,
			"skipped_update_version": DEFAULT_SKIPPED_UPDATE_VERSION
		}
	return {
		"master_volume_db": float(config.get_value(AUDIO_SECTION, MASTER_KEY, DEFAULT_MASTER_VOLUME_DB)),
		"music_volume_db": float(config.get_value(AUDIO_SECTION, MUSIC_KEY, DEFAULT_MUSIC_VOLUME_DB)),
		"sfx_volume_db": float(config.get_value(AUDIO_SECTION, SFX_KEY, DEFAULT_SFX_VOLUME_DB)),
		"display_mode": String(config.get_value(DISPLAY_SECTION, DISPLAY_MODE_KEY, DEFAULT_DISPLAY_MODE)),
		"resolution_width": int(config.get_value(DISPLAY_SECTION, RESOLUTION_WIDTH_KEY, DEFAULT_RESOLUTION_WIDTH)),
		"resolution_height": int(config.get_value(DISPLAY_SECTION, RESOLUTION_HEIGHT_KEY, DEFAULT_RESOLUTION_HEIGHT)),
		"telemetry_upload_enabled": bool(config.get_value(TELEMETRY_SECTION, TELEMETRY_UPLOAD_ENABLED_KEY, DEFAULT_TELEMETRY_UPLOAD_ENABLED)),
		"telemetry_consent_asked": bool(config.get_value(TELEMETRY_SECTION, TELEMETRY_CONSENT_ASKED_KEY, DEFAULT_TELEMETRY_CONSENT_ASKED)),
		"skipped_update_version": String(config.get_value(UPDATE_SECTION, SKIPPED_VERSION_KEY, DEFAULT_SKIPPED_UPDATE_VERSION))
	}

static func save_settings(master_volume_db: float, music_volume_db: float, sfx_volume_db: float, resolution_width: int = DEFAULT_RESOLUTION_WIDTH, resolution_height: int = DEFAULT_RESOLUTION_HEIGHT, display_mode: String = DEFAULT_DISPLAY_MODE, telemetry_upload_enabled: bool = DEFAULT_TELEMETRY_UPLOAD_ENABLED, telemetry_consent_asked: bool = DEFAULT_TELEMETRY_CONSENT_ASKED, skipped_update_version: String = DEFAULT_SKIPPED_UPDATE_VERSION) -> void:
	var config := ConfigFile.new()
	config.set_value(AUDIO_SECTION, MASTER_KEY, master_volume_db)
	config.set_value(AUDIO_SECTION, MUSIC_KEY, music_volume_db)
	config.set_value(AUDIO_SECTION, SFX_KEY, sfx_volume_db)
	config.set_value(DISPLAY_SECTION, RESOLUTION_WIDTH_KEY, resolution_width)
	config.set_value(DISPLAY_SECTION, RESOLUTION_HEIGHT_KEY, resolution_height)
	config.set_value(DISPLAY_SECTION, DISPLAY_MODE_KEY, display_mode)
	config.set_value(TELEMETRY_SECTION, TELEMETRY_UPLOAD_ENABLED_KEY, telemetry_upload_enabled)
	config.set_value(TELEMETRY_SECTION, TELEMETRY_CONSENT_ASKED_KEY, telemetry_consent_asked)
	config.set_value(UPDATE_SECTION, SKIPPED_VERSION_KEY, skipped_update_version)
	config.save(SETTINGS_PATH)
