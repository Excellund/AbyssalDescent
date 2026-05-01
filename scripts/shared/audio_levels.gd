extends Node

const DB_MIN := -80.0
const DB_MAX := 6.0
const MUTE_EPSILON_DB := 0.001
const MUSIC_FADE_FLOOR_DB := -60.0
const MENU_MUSIC_TRIM_DB := 0.0
const GAMEPLAY_MUSIC_TRIM_DB := -2.0

static func clamp_db(db: float) -> float:
	return clampf(db, DB_MIN, DB_MAX)

static func apply_trim_db(setting_db: float, trim_db: float) -> float:
	return clamp_db(setting_db + trim_db)

static func menu_music_db(setting_db: float) -> float:
	return apply_trim_db(setting_db, MENU_MUSIC_TRIM_DB)

static func gameplay_music_db(setting_db: float) -> float:
	return apply_trim_db(setting_db, GAMEPLAY_MUSIC_TRIM_DB)

static func is_muted_db(db: float) -> bool:
	return clamp_db(db) <= DB_MIN + MUTE_EPSILON_DB

static func crossfade_floor_db(target_db: float, floor_db: float = MUSIC_FADE_FLOOR_DB) -> float:
	return minf(floor_db, clamp_db(target_db))
