extends Node

const DB_MIN := -80.0
const DB_MAX := 6.0
const MUTE_EPSILON_DB := 0.001
const MUSIC_FADE_FLOOR_DB := -60.0

static func clamp_db(db: float) -> float:
	return clampf(db, DB_MIN, DB_MAX)

static func is_muted_db(db: float) -> bool:
	return clamp_db(db) <= DB_MIN + MUTE_EPSILON_DB

static func crossfade_floor_db(target_db: float, floor_db: float = MUSIC_FADE_FLOOR_DB) -> float:
	return minf(floor_db, clamp_db(target_db))
