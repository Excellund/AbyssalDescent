extends RefCounted

const ENUMS := preload("res://scripts/shared/enums.gd")
const DEBUG_ENUMS := preload("res://scripts/shared/debug_enums.gd")

const DOOR_KIND_ENCOUNTER := ENUMS.DoorKind.ENCOUNTER
const DOOR_KIND_BOSS := ENUMS.DoorKind.BOSS
const DOOR_KIND_REST := ENUMS.DoorKind.REST
const ACTION_ENCOUNTER := ENUMS.EncounterAction.ENCOUNTER
const ACTION_BOSS := ENUMS.EncounterAction.BOSS
const ACTION_REST := ENUMS.EncounterAction.REST

const KEY_RUN_CLEARED := "run_cleared"
const KEY_OPEN_REWARD_MODE := "open_reward_mode"
const KEY_SPAWN_DOORS := "spawn_doors"
const KEY_PENDING_ROOM_REWARD := "pending_room_reward"
const KEY_ROOMS_CLEARED := "rooms_cleared"
const KEY_ROOM_DEPTH := "room_depth"
const KEY_BOSS_UNLOCKED := "boss_unlocked"

const KEY_USED := "used"
const KEY_DOOR := "door"

const KEY_LABEL := "label"
const KEY_COLOR := "color"
const KEY_KIND_ID := "kind_id"
const KEY_KIND := "kind"
const KEY_ICON := "icon"
const KEY_REWARD := "reward"
const KEY_PROFILE := "profile"
const KEY_POSITION := "position"
const KEY_ENCOUNTER_KEY := "encounter_key"

const KEY_ACTION_ID := "action_id"
const KEY_ACTION := "action"

const PROFILE_KEY_LABEL := "label"
const PROFILE_KEY_ROOM_SIZE := "room_size"
const PROFILE_KEY_STATIC_CAMERA := "static_camera"
const PROFILE_KEY_CHASER_COUNT := "chaser_count"
const PROFILE_KEY_CHARGER_COUNT := "charger_count"
const PROFILE_KEY_ARCHER_COUNT := "archer_count"
const PROFILE_KEY_SHIELDER_COUNT := "shielder_count"
const PROFILE_KEY_ENEMY_MUTATOR := "enemy_mutator"
const PROFILE_KEY_PLAYER_MUTATOR := "player_mutator"
const PROFILE_KEY_LURKER_COUNT := "lurker_count"
const PROFILE_KEY_RAM_COUNT := "ram_count"
const PROFILE_KEY_LANCER_COUNT := "lancer_count"
const PROFILE_KEY_OBJECTIVE_KIND := "objective_kind"
const PROFILE_KEY_OBJECTIVE_DURATION := "objective_duration"
const PROFILE_KEY_OBJECTIVE_SPAWN_INTERVAL := "objective_spawn_interval"
const PROFILE_KEY_OBJECTIVE_SPAWN_BATCH := "objective_spawn_batch"
const PROFILE_KEY_OBJECTIVE_TARGET_TYPE := "objective_target_type"
const PROFILE_KEY_OBJECTIVE_ZONE_RADIUS := "objective_zone_radius"
const PROFILE_KEY_OBJECTIVE_PROGRESS_GOAL := "objective_progress_goal"
const PROFILE_KEY_OBJECTIVE_PROGRESS_DECAY := "objective_progress_decay"
const PROFILE_KEY_OBJECTIVE_CONTEST_THRESHOLD := "objective_contest_threshold"

const MUTATOR_KEY_NAME := "name"
const MUTATOR_KEY_THEME_COLOR := "theme_color"
const MUTATOR_KEY_ICON_SHAPE_ID := "icon_shape_id"
const MUTATOR_KEY_BANNER_SUFFIX := "banner_suffix"
const MUTATOR_KEY_ENEMY_TINT := "enemy_tint"
const MUTATOR_KEY_PLAYER_DAMAGE_MULT := "player_damage_mult"
const MUTATOR_KEY_PLAYER_DAMAGE_RESIST := "player_damage_resist"
const MUTATOR_KEY_DURATION_ENCOUNTERS := "duration_encounters"
const MUTATOR_KEY_REMAINING_ENCOUNTERS := "remaining_encounters"
const MUTATOR_KEY_ID := "id"
const MUTATOR_KEY_SOURCE_ENCOUNTER := "source_encounter"
const MUTATOR_KEY_SOURCE_OBJECTIVE_KIND := "source_objective_kind"
const MUTATOR_KEY_TARGET_SCOPE := "target_scope"
const MUTATOR_KEY_EFFECTS := "effects"
const MUTATOR_KEY_STACK_POLICY := "stack_policy"
const MUTATOR_KEY_STACK_LIMIT := "stack_limit"
const MUTATOR_KEY_STACK_FALLOFF := "stack_falloff"
const MUTATOR_STAT_ENEMY_HEALTH_MULT := "enemy_health_mult"
const MUTATOR_STAT_CHASER_DAMAGE_MULT := "chaser_damage_mult"
const MUTATOR_STAT_CHASER_ATTACK_INTERVAL_MULT := "chaser_attack_interval_mult"
const MUTATOR_STAT_CHASER_SPEED_MULT := "chaser_speed_mult"
const MUTATOR_STAT_CHARGER_DAMAGE_MULT := "charger_damage_mult"
const MUTATOR_STAT_CHARGER_SPEED_MULT := "charger_speed_mult"
const MUTATOR_STAT_CHARGER_WINDUP_MULT := "charger_windup_mult"
const MUTATOR_STAT_ARCHER_WINDUP_MULT := "archer_windup_mult"
const MUTATOR_STAT_ARCHER_COOLDOWN_MULT := "archer_cooldown_mult"
const MUTATOR_STAT_ARCHER_PROJECTILE_DAMAGE_MULT := "archer_projectile_damage_mult"
const MUTATOR_STAT_SHIELDER_SLAM_DAMAGE_MULT := "shielder_slam_damage_mult"
const MUTATOR_STAT_SHIELDER_SLAM_WINDUP_MULT := "shielder_slam_windup_mult"
const MUTATOR_STAT_SHIELDER_SPEED_MULT := "shielder_speed_mult"

const DEBUG_ENCOUNTER_NONE := DEBUG_ENUMS.Encounter.NONE

const DEBUG_ENCOUNTER_MAP := [
	{"id": DEBUG_ENUMS.Encounter.NONE, "key": "none", "is_boss": false, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.REST_SITE, "key": "rest", "is_boss": false, "is_rest": true, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.SKIRMISH, "key": "skirmish", "is_boss": false, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.CROSSFIRE, "key": "crossfire", "is_boss": false, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.FORTRESS, "key": "fortress", "is_boss": false, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.ONSLAUGHT, "key": "onslaught", "is_boss": false, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.VANGUARD, "key": "vanguard", "is_boss": false, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.BLITZ, "key": "blitz", "is_boss": false, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.AMBUSH, "key": "ambush", "is_boss": false, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.SUPPRESSION, "key": "suppression", "is_boss": false, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.GAUNTLET, "key": "gauntlet", "is_boss": false, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.OBJECTIVE_LAST_STAND, "key": "last_stand", "is_boss": false, "is_rest": false, "is_objective": true},
	{"id": DEBUG_ENUMS.Encounter.OBJECTIVE_PRIORITY_TARGET, "key": "cut_the_signal", "is_boss": false, "is_rest": false, "is_objective": true},
	{"id": DEBUG_ENUMS.Encounter.OBJECTIVE_HOLD_THE_LINE, "key": "hold_the_line", "is_boss": false, "is_rest": false, "is_objective": true},
	{"id": DEBUG_ENUMS.Encounter.OBJECTIVE_RANDOM, "key": "random_objective", "is_boss": false, "is_rest": false, "is_objective": true},
	{"id": DEBUG_ENUMS.Encounter.TRIAL, "key": "trial", "is_boss": false, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.BOSS_1, "key": "warden", "is_boss": true, "is_rest": false, "is_objective": false},
	{"id": DEBUG_ENUMS.Encounter.BOSS_2, "key": "sovereign", "is_boss": true, "is_rest": false, "is_objective": false},
]

const ENCOUNTER_DOOR_PRESENTATION := {
	"skirmish": {
		"label": "Skirmish"
	},
	"pursuit": {
		"label": "Pursuit"
	},
	"crossfire": {
		"label": "Crossfire"
	},
	"onslaught": {
		"label": "Onslaught"
	},
	"fortress": {
		"label": "Fortress"
	},
	"blitz": {
		"label": "Blitz"
	},
	"suppression": {
		"label": "Suppression"
	},
	"vanguard": {
		"label": "Vanguard"
	},
	"ambush": {
		"label": "Ambush"
	},
	"gauntlet": {
		"label": "Gauntlet"
	},
	"rest": {
		"label": "Rest Site",
		"short_label": "Rest",
		"color": Color(0.66, 1.0, 0.76, 0.92),
		"icon": "rest",
		"kind": DOOR_KIND_REST,
		"reward": ENUMS.RewardMode.NONE,
		"prompt_name_suffix": ""
	},
	"trial": {
		"short_label": "Trial"
	},
	"warden": {
		"label": "Warden",
		"short_label": "Boss",
		"color": Color(0.96, 0.46, 0.18, 0.98),
		"icon": "boss",
		"kind": DOOR_KIND_BOSS,
		"reward": ENUMS.RewardMode.NONE,
		"prompt_name_suffix": " Gate"
	},
	"sovereign": {
		"label": "Sovereign",
		"short_label": "Boss",
		"color": Color(0.92, 0.28, 0.1, 0.98),
		"icon": "boss",
		"kind": DOOR_KIND_BOSS,
		"reward": ENUMS.RewardMode.NONE,
		"prompt_name_suffix": " Gate"
	}
}

const INTRO_ENCOUNTER_DOOR_KEYS := {
	"skirmish": true,
	"pursuit": true
}

const INTRO_ENCOUNTER_DOOR_COLOR := Color(0.34, 0.8, 1.0, 0.95)
const STANDARD_ENCOUNTER_DOOR_COLOR := Color(0.93, 0.62, 0.28, 0.95)

static func _door_kind_from_legacy(value: String) -> int:
	match value.to_lower():
		"boss":
			return DOOR_KIND_BOSS
		"rest":
			return DOOR_KIND_REST
		_:
			return DOOR_KIND_ENCOUNTER

static func _door_kind_to_legacy(value: int) -> String:
	match value:
		DOOR_KIND_BOSS:
			return "boss"
		DOOR_KIND_REST:
			return "rest"
		_:
			return "encounter"

static func normalize_door_kind(value: Variant) -> int:
	if value is int:
		var kind_int := int(value)
		if kind_int == DOOR_KIND_BOSS:
			return DOOR_KIND_BOSS
		if kind_int == DOOR_KIND_REST:
			return DOOR_KIND_REST
		return DOOR_KIND_ENCOUNTER
	return _door_kind_from_legacy(String(value))

static func _action_from_legacy(value: String) -> int:
	match value.to_lower():
		"boss":
			return ACTION_BOSS
		"rest":
			return ACTION_REST
		_:
			return ACTION_ENCOUNTER

static func _action_to_legacy(value: int) -> String:
	match value:
		ACTION_BOSS:
			return "boss"
		ACTION_REST:
			return "rest"
		_:
			return "encounter"

static func normalize_action(value: Variant) -> int:
	if value is int:
		var action_int := int(value)
		if action_int == ACTION_BOSS:
			return ACTION_BOSS
		if action_int == ACTION_REST:
			return ACTION_REST
		return ACTION_ENCOUNTER
	return _action_from_legacy(String(value))

static func normalize_reward_mode(value: Variant) -> int:
	if value is int:
		var mode_int := int(value)
		if mode_int == ENUMS.RewardMode.BOON:
			return ENUMS.RewardMode.BOON
		if mode_int == ENUMS.RewardMode.ARCANA:
			return ENUMS.RewardMode.ARCANA
		if mode_int == ENUMS.RewardMode.MISSION:
			return ENUMS.RewardMode.MISSION
		return ENUMS.RewardMode.NONE
	return ENUMS.reward_mode_from_legacy(String(value).to_lower())

static func debug_encounter_entry(encounter_key: String) -> Dictionary:
	var normalized := encounter_key.strip_edges().to_lower()
	for entry in DEBUG_ENCOUNTER_MAP:
		if String(entry.get("key", "")) == normalized:
			return entry
	return {}

static func canonicalize_debug_encounter_key(encounter_key: String) -> String:
	var entry := debug_encounter_entry(encounter_key)
	if entry.is_empty():
		return ""
	return String(entry.get("key", ""))

static func debug_encounter_key_from_id(encounter_id: int) -> String:
	for entry in DEBUG_ENCOUNTER_MAP:
		if int(entry.get("id", -1)) == encounter_id:
			return String(entry.get("key", ""))
	return ""

static func debug_encounter_is_objective(encounter_key: String) -> bool:
	var entry := debug_encounter_entry(encounter_key)
	if entry.is_empty():
		return false
	return bool(entry.get("is_objective", false))

static func _door_presentation(encounter_key: String) -> Dictionary:
	return ENCOUNTER_DOOR_PRESENTATION.get(encounter_key.strip_edges().to_lower(), {}) as Dictionary

static func _normalize_encounter_key(value: String, fallback: String = "unknown") -> String:
	var key := value.strip_edges().to_lower()
	if key.is_empty():
		return fallback
	for sep in [":", "-", "/", "."]:
		key = key.replace(sep, " ")
	for punct in ["'", "\""]:
		key = key.replace(punct, "")
	while key.find("  ") != -1:
		key = key.replace("  ", " ")
	key = key.strip_edges().replace(" ", "_")
	return key if not key.is_empty() else fallback

static func _profile_encounter_key(encounter_profile: Dictionary, fallback: String = "unknown") -> String:
	if encounter_profile.is_empty():
		return fallback
	return _normalize_encounter_key(profile_label(encounter_profile), fallback)

static func _objective_prompt_label(encounter_profile: Dictionary) -> String:
	return "Objective - %s" % profile_label(encounter_profile)

static func _objective_short_label(encounter_profile: Dictionary) -> String:
	return profile_label(encounter_profile)

static func _truncate_door_label(label: String, max_length: int = 20) -> String:
	if label.length() <= max_length:
		return label
	return label.substr(0, max_length) + "..."

static func profile(
	label: String,
	room_size: Vector2,
	static_camera: bool,
	chaser_count: int,
	charger_count: int,
	archer_count: int,
	shielder_count: int,
	enemy_mutator: Dictionary = {}
) -> Dictionary:
	var value := {
		PROFILE_KEY_LABEL: label,
		PROFILE_KEY_ROOM_SIZE: room_size,
		PROFILE_KEY_STATIC_CAMERA: static_camera,
		PROFILE_KEY_CHASER_COUNT: chaser_count,
		PROFILE_KEY_CHARGER_COUNT: charger_count,
		PROFILE_KEY_ARCHER_COUNT: archer_count,
		PROFILE_KEY_SHIELDER_COUNT: shielder_count,
	}
	if not enemy_mutator.is_empty():
		value[PROFILE_KEY_ENEMY_MUTATOR] = enemy_mutator
	return value

static func normalize_profile(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return profile("Encounter", Vector2.ZERO, true, 0, 0, 0, 0)
	var input := value as Dictionary
	var normalized := profile(
		String(input.get(PROFILE_KEY_LABEL, "Encounter")),
		input.get(PROFILE_KEY_ROOM_SIZE, Vector2.ZERO) as Vector2,
		bool(input.get(PROFILE_KEY_STATIC_CAMERA, true)),
		int(input.get(PROFILE_KEY_CHASER_COUNT, 0)),
		int(input.get(PROFILE_KEY_CHARGER_COUNT, 0)),
		int(input.get(PROFILE_KEY_ARCHER_COUNT, 0)),
		int(input.get(PROFILE_KEY_SHIELDER_COUNT, 0)),
		input.get(PROFILE_KEY_ENEMY_MUTATOR, {}) as Dictionary
	)
	var objective_kind := String(input.get(PROFILE_KEY_OBJECTIVE_KIND, ""))
	if not objective_kind.is_empty():
		normalized[PROFILE_KEY_OBJECTIVE_KIND] = objective_kind
		normalized[PROFILE_KEY_OBJECTIVE_DURATION] = float(input.get(PROFILE_KEY_OBJECTIVE_DURATION, 0.0))
		normalized[PROFILE_KEY_OBJECTIVE_SPAWN_INTERVAL] = float(input.get(PROFILE_KEY_OBJECTIVE_SPAWN_INTERVAL, 0.0))
		normalized[PROFILE_KEY_OBJECTIVE_SPAWN_BATCH] = int(input.get(PROFILE_KEY_OBJECTIVE_SPAWN_BATCH, 1))
		normalized[PROFILE_KEY_OBJECTIVE_TARGET_TYPE] = String(input.get(PROFILE_KEY_OBJECTIVE_TARGET_TYPE, ""))
		normalized[PROFILE_KEY_OBJECTIVE_ZONE_RADIUS] = float(input.get(PROFILE_KEY_OBJECTIVE_ZONE_RADIUS, 0.0))
		normalized[PROFILE_KEY_OBJECTIVE_PROGRESS_GOAL] = float(input.get(PROFILE_KEY_OBJECTIVE_PROGRESS_GOAL, 0.0))
		normalized[PROFILE_KEY_OBJECTIVE_PROGRESS_DECAY] = float(input.get(PROFILE_KEY_OBJECTIVE_PROGRESS_DECAY, 0.0))
		normalized[PROFILE_KEY_OBJECTIVE_CONTEST_THRESHOLD] = int(input.get(PROFILE_KEY_OBJECTIVE_CONTEST_THRESHOLD, 1))
	return normalized

static func profile_label(profile_value: Dictionary) -> String:
	return String(profile_value.get(PROFILE_KEY_LABEL, "Encounter"))

static func profile_room_size(profile_value: Dictionary) -> Vector2:
	return profile_value.get(PROFILE_KEY_ROOM_SIZE, Vector2.ZERO) as Vector2

static func profile_static_camera(profile_value: Dictionary) -> bool:
	return bool(profile_value.get(PROFILE_KEY_STATIC_CAMERA, true))

static func profile_chaser_count(profile_value: Dictionary) -> int:
	return int(profile_value.get(PROFILE_KEY_CHASER_COUNT, 0))

static func profile_charger_count(profile_value: Dictionary) -> int:
	return int(profile_value.get(PROFILE_KEY_CHARGER_COUNT, 0))

static func profile_archer_count(profile_value: Dictionary) -> int:
	return int(profile_value.get(PROFILE_KEY_ARCHER_COUNT, 0))

static func profile_shielder_count(profile_value: Dictionary) -> int:
	return int(profile_value.get(PROFILE_KEY_SHIELDER_COUNT, 0))

static func profile_lurker_count(profile_value: Dictionary) -> int:
	return int(profile_value.get(PROFILE_KEY_LURKER_COUNT, 0))

static func profile_ram_count(profile_value: Dictionary) -> int:
	return int(profile_value.get(PROFILE_KEY_RAM_COUNT, 0))

static func profile_lancer_count(profile_value: Dictionary) -> int:
	return int(profile_value.get(PROFILE_KEY_LANCER_COUNT, 0))

static func profile_enemy_mutator(profile_value: Dictionary) -> Dictionary:
	return profile_value.get(PROFILE_KEY_ENEMY_MUTATOR, {}) as Dictionary

static func profile_player_mutator(profile_value: Dictionary) -> Dictionary:
	return profile_value.get(PROFILE_KEY_PLAYER_MUTATOR, {}) as Dictionary

static func profile_set_room_size(profile_value: Dictionary, room_size: Vector2) -> void:
	profile_value[PROFILE_KEY_ROOM_SIZE] = room_size

static func profile_set_static_camera(profile_value: Dictionary, value: bool) -> void:
	profile_value[PROFILE_KEY_STATIC_CAMERA] = value

static func profile_set_counts(profile_value: Dictionary, chasers: int, chargers: int, archers: int, shielders: int) -> void:
	profile_value[PROFILE_KEY_CHASER_COUNT] = chasers
	profile_value[PROFILE_KEY_CHARGER_COUNT] = chargers
	profile_value[PROFILE_KEY_ARCHER_COUNT] = archers
	profile_value[PROFILE_KEY_SHIELDER_COUNT] = shielders

static func profile_set_specialist_counts(profile_value: Dictionary, lurkers: int, rams: int, lancers: int) -> void:
	profile_value[PROFILE_KEY_LURKER_COUNT] = lurkers
	profile_value[PROFILE_KEY_RAM_COUNT] = rams
	profile_value[PROFILE_KEY_LANCER_COUNT] = lancers

static func profile_counts(chasers: int, chargers: int, archers: int, shielders: int, lurkers: int = 0, rams: int = 0, lancers: int = 0) -> Dictionary:
	return {
		PROFILE_KEY_CHASER_COUNT: chasers,
		PROFILE_KEY_CHARGER_COUNT: chargers,
		PROFILE_KEY_ARCHER_COUNT: archers,
		PROFILE_KEY_SHIELDER_COUNT: shielders,
		PROFILE_KEY_LURKER_COUNT: lurkers,
		PROFILE_KEY_RAM_COUNT: rams,
		PROFILE_KEY_LANCER_COUNT: lancers
	}

static func profile_count_from_counts(counts: Dictionary, key: String) -> int:
	return int(counts.get(key, 0))

static func profile_counts_from_profile(profile_value: Dictionary) -> Dictionary:
	return profile_counts(
		profile_chaser_count(profile_value),
		profile_charger_count(profile_value),
		profile_archer_count(profile_value),
		profile_shielder_count(profile_value),
		profile_lurker_count(profile_value),
		profile_ram_count(profile_value),
		profile_lancer_count(profile_value)
	)

static func profile_set_counts_from_dict(profile_value: Dictionary, counts: Dictionary) -> void:
	profile_set_counts(
		profile_value,
		profile_count_from_counts(counts, PROFILE_KEY_CHASER_COUNT),
		profile_count_from_counts(counts, PROFILE_KEY_CHARGER_COUNT),
		profile_count_from_counts(counts, PROFILE_KEY_ARCHER_COUNT),
		profile_count_from_counts(counts, PROFILE_KEY_SHIELDER_COUNT)
	)
	profile_set_specialist_counts(
		profile_value,
		profile_count_from_counts(counts, PROFILE_KEY_LURKER_COUNT),
		profile_count_from_counts(counts, PROFILE_KEY_RAM_COUNT),
		profile_count_from_counts(counts, PROFILE_KEY_LANCER_COUNT)
	)

static func profile_with_counts(profile_value: Dictionary, counts: Dictionary) -> Dictionary:
	var modified := profile_value.duplicate(true)
	profile_set_counts_from_dict(modified, counts)
	return modified

static func profile_scale_count(count: int, pressure_mult: float, minimum: int = 0) -> int:
	var scaled := int(floor(float(maxi(0, count)) * pressure_mult))
	return maxi(minimum, scaled)

static func profile_scaled_counts(profile_value: Dictionary, pressure_mult: float = 1.0, minimum_total: int = 0) -> Dictionary:
	if profile_value.is_empty():
		return profile_value
	var modified := profile_value.duplicate(true)
	profile_set_counts(
		modified,
		profile_scale_count(profile_chaser_count(modified), pressure_mult),
		profile_scale_count(profile_charger_count(modified), pressure_mult),
		profile_scale_count(profile_archer_count(modified), pressure_mult),
		profile_scale_count(profile_shielder_count(modified), pressure_mult)
	)
	profile_set_specialist_counts(
		modified,
		profile_scale_count(profile_lurker_count(modified), pressure_mult),
		profile_scale_count(profile_ram_count(modified), pressure_mult),
		profile_scale_count(profile_lancer_count(modified), pressure_mult)
	)
	if minimum_total > 0:
		var current_total := profile_total_enemy_count(modified)
		if current_total < minimum_total:
			var delta := minimum_total - current_total
			modified[PROFILE_KEY_CHASER_COUNT] = profile_chaser_count(modified) + delta
	return modified

static func profile_total_enemy_count(profile_value: Dictionary) -> int:
	var total := 0
	total += profile_chaser_count(profile_value)
	total += profile_charger_count(profile_value)
	total += profile_archer_count(profile_value)
	total += profile_shielder_count(profile_value)
	total += profile_lurker_count(profile_value)
	total += profile_ram_count(profile_value)
	total += profile_lancer_count(profile_value)
	return total

static func profile_set_enemy_mutator(profile_value: Dictionary, enemy_mutator: Dictionary) -> void:
	if enemy_mutator.is_empty():
		profile_value.erase(PROFILE_KEY_ENEMY_MUTATOR)

	else:
		profile_value[PROFILE_KEY_ENEMY_MUTATOR] = enemy_mutator

static func profile_set_player_mutator(profile_value: Dictionary, player_mutator: Dictionary) -> void:
	if player_mutator.is_empty():
		profile_value.erase(PROFILE_KEY_PLAYER_MUTATOR)
	else:
		profile_value[PROFILE_KEY_PLAYER_MUTATOR] = player_mutator

static func profile_objective_kind(profile_value: Dictionary) -> String:
	return String(profile_value.get(PROFILE_KEY_OBJECTIVE_KIND, ""))

static func profile_objective_duration(profile_value: Dictionary) -> float:
	return float(profile_value.get(PROFILE_KEY_OBJECTIVE_DURATION, 0.0))

static func profile_objective_spawn_interval(profile_value: Dictionary) -> float:
	return float(profile_value.get(PROFILE_KEY_OBJECTIVE_SPAWN_INTERVAL, 0.0))

static func profile_objective_spawn_batch(profile_value: Dictionary) -> int:
	return int(profile_value.get(PROFILE_KEY_OBJECTIVE_SPAWN_BATCH, 1))

static func profile_objective_target_type(profile_value: Dictionary) -> String:
	return String(profile_value.get(PROFILE_KEY_OBJECTIVE_TARGET_TYPE, ""))

static func profile_objective_zone_radius(profile_value: Dictionary) -> float:
	return float(profile_value.get(PROFILE_KEY_OBJECTIVE_ZONE_RADIUS, 0.0))

static func profile_objective_progress_goal(profile_value: Dictionary) -> float:
	return float(profile_value.get(PROFILE_KEY_OBJECTIVE_PROGRESS_GOAL, 0.0))

static func profile_objective_progress_decay(profile_value: Dictionary) -> float:
	return float(profile_value.get(PROFILE_KEY_OBJECTIVE_PROGRESS_DECAY, 0.0))

static func profile_objective_contest_threshold(profile_value: Dictionary) -> int:
	return int(profile_value.get(PROFILE_KEY_OBJECTIVE_CONTEST_THRESHOLD, 1))

static func profile_set_survival_objective(profile_value: Dictionary, duration: float, spawn_interval: float, spawn_batch: int = 1) -> void:
	profile_value[PROFILE_KEY_OBJECTIVE_KIND] = "last_stand"
	profile_value[PROFILE_KEY_OBJECTIVE_DURATION] = maxf(1.0, duration)
	profile_value[PROFILE_KEY_OBJECTIVE_SPAWN_INTERVAL] = maxf(0.25, spawn_interval)
	profile_value[PROFILE_KEY_OBJECTIVE_SPAWN_BATCH] = maxi(1, spawn_batch)
	profile_value.erase(PROFILE_KEY_OBJECTIVE_TARGET_TYPE)
	profile_value.erase(PROFILE_KEY_OBJECTIVE_ZONE_RADIUS)
	profile_value.erase(PROFILE_KEY_OBJECTIVE_PROGRESS_GOAL)
	profile_value.erase(PROFILE_KEY_OBJECTIVE_PROGRESS_DECAY)
	profile_value.erase(PROFILE_KEY_OBJECTIVE_CONTEST_THRESHOLD)

static func profile_set_priority_target_objective(profile_value: Dictionary, target_type: String, duration: float, spawn_interval: float, spawn_batch: int = 1) -> void:
	profile_value[PROFILE_KEY_OBJECTIVE_KIND] = "cut_the_signal"
	profile_value[PROFILE_KEY_OBJECTIVE_TARGET_TYPE] = target_type.strip_edges().to_lower()
	profile_value[PROFILE_KEY_OBJECTIVE_DURATION] = maxf(1.0, duration)
	profile_value[PROFILE_KEY_OBJECTIVE_SPAWN_INTERVAL] = maxf(0.25, spawn_interval)
	profile_value[PROFILE_KEY_OBJECTIVE_SPAWN_BATCH] = maxi(1, spawn_batch)
	profile_value.erase(PROFILE_KEY_OBJECTIVE_ZONE_RADIUS)
	profile_value.erase(PROFILE_KEY_OBJECTIVE_PROGRESS_GOAL)
	profile_value.erase(PROFILE_KEY_OBJECTIVE_PROGRESS_DECAY)
	profile_value.erase(PROFILE_KEY_OBJECTIVE_CONTEST_THRESHOLD)

static func profile_set_control_objective(profile_value: Dictionary, duration: float, spawn_interval: float, spawn_batch: int, zone_radius: float, progress_goal: float, progress_decay: float, contest_threshold: int = 1) -> void:
	profile_value[PROFILE_KEY_OBJECTIVE_KIND] = "hold_the_line"
	profile_value[PROFILE_KEY_OBJECTIVE_DURATION] = maxf(1.0, duration)
	profile_value[PROFILE_KEY_OBJECTIVE_SPAWN_INTERVAL] = maxf(0.25, spawn_interval)
	profile_value[PROFILE_KEY_OBJECTIVE_SPAWN_BATCH] = maxi(1, spawn_batch)
	profile_value[PROFILE_KEY_OBJECTIVE_ZONE_RADIUS] = maxf(48.0, zone_radius)
	profile_value[PROFILE_KEY_OBJECTIVE_PROGRESS_GOAL] = maxf(1.0, progress_goal)
	profile_value[PROFILE_KEY_OBJECTIVE_PROGRESS_DECAY] = maxf(0.0, progress_decay)
	profile_value[PROFILE_KEY_OBJECTIVE_CONTEST_THRESHOLD] = maxi(0, contest_threshold)
	profile_value.erase(PROFILE_KEY_OBJECTIVE_TARGET_TYPE)

static func mutator_name(mutator: Dictionary) -> String:
	return String(mutator.get(MUTATOR_KEY_NAME, ""))

static func mutator_id(mutator: Dictionary) -> String:
	var id := String(mutator.get(MUTATOR_KEY_ID, "")).strip_edges()
	if not id.is_empty():
		return id
	var shape_id := mutator_icon_shape_id(mutator)
	if not shape_id.is_empty():
		return shape_id
	return mutator_name(mutator).to_lower().replace(" ", "_")

static func mutator_target_scope(mutator: Dictionary) -> String:
	var scope := String(mutator.get(MUTATOR_KEY_TARGET_SCOPE, "player")).strip_edges().to_lower()
	if scope == "enemy" or scope == "both":
		return scope
	return "player"

static func mutator_affects_scope(mutator: Dictionary, scope: String) -> bool:
	var normalized_scope := scope.strip_edges().to_lower()
	if normalized_scope.is_empty():
		return false
	var mutator_scope := mutator_target_scope(mutator)
	return mutator_scope == "both" or mutator_scope == normalized_scope

static func mutator_effects(mutator: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = mutator.get(MUTATOR_KEY_EFFECTS, [])
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				result.append((entry as Dictionary).duplicate(true))
	return result

static func mutator_effect_value(mutator: Dictionary, effect_type: String, default_value: float = 0.0) -> float:
	var normalized := effect_type.strip_edges().to_lower()
	if normalized.is_empty():
		return default_value
	for effect in mutator_effects(mutator):
		if String(effect.get("type", "")).strip_edges().to_lower() != normalized:
			continue
		return float(effect.get("value", default_value))
	return default_value

static func mutator_stack_policy(mutator: Dictionary) -> String:
	var policy := String(mutator.get(MUTATOR_KEY_STACK_POLICY, "refresh")).strip_edges().to_lower()
	if policy == "stack" or policy == "replace":
		return policy
	return "refresh"

static func mutator_stack_limit(mutator: Dictionary) -> int:
	return maxi(1, int(mutator.get(MUTATOR_KEY_STACK_LIMIT, 1)))

static func mutator_stack_falloff(mutator: Dictionary) -> float:
	return clampf(float(mutator.get(MUTATOR_KEY_STACK_FALLOFF, 1.0)), 0.0, 1.0)

static func mutator_theme_color(mutator: Dictionary, fallback: Color = Color(0.78, 0.9, 1.0, 0.92)) -> Color:
	return mutator.get(MUTATOR_KEY_THEME_COLOR, fallback) as Color

static func mutator_icon_shape_id(mutator: Dictionary) -> String:
	return String(mutator.get(MUTATOR_KEY_ICON_SHAPE_ID, ""))

static func mutator_banner_suffix(mutator: Dictionary) -> String:
	return String(mutator.get(MUTATOR_KEY_BANNER_SUFFIX, ""))

static func mutator_enemy_tint(mutator: Dictionary, fallback: Color = Color(1.0, 0.92, 0.92, 1.0)) -> Color:
	return mutator.get(MUTATOR_KEY_ENEMY_TINT, fallback) as Color

static func mutator_stat(mutator: Dictionary, stat_key: String, default_value: float = 1.0) -> float:
	return float(mutator.get(stat_key, default_value))

static func mutator_set_stat(mutator: Dictionary, stat_key: String, value: float) -> void:
	mutator[stat_key] = value

static func mutator_multiply_stat(mutator: Dictionary, stat_key: String, factor: float, default_value: float = 1.0) -> void:
	mutator_set_stat(mutator, stat_key, mutator_stat(mutator, stat_key, default_value) * factor)

static func room_cleared_outcome(
	run_cleared: bool,
	open_reward_mode: int,
	spawn_doors: bool,
	pending_room_reward: int,
	rooms_cleared: int,
	room_depth: int,
	boss_unlocked: bool
) -> Dictionary:
	return {
		KEY_RUN_CLEARED: run_cleared,
		KEY_OPEN_REWARD_MODE: normalize_reward_mode(open_reward_mode),
		KEY_SPAWN_DOORS: spawn_doors,
		KEY_PENDING_ROOM_REWARD: normalize_reward_mode(pending_room_reward),
		KEY_ROOMS_CLEARED: rooms_cleared,
		KEY_ROOM_DEPTH: room_depth,
		KEY_BOSS_UNLOCKED: boss_unlocked
	}

static func normalize_room_cleared_outcome(value: Variant) -> Dictionary:
	var outcome: Dictionary = {}
	if value is Dictionary:
		outcome = value as Dictionary
	elif value != null:
		outcome = value.to_dict() as Dictionary
	return room_cleared_outcome(
		bool(outcome.get(KEY_RUN_CLEARED, false)),
		int(outcome.get(KEY_OPEN_REWARD_MODE, ENUMS.RewardMode.NONE)),
		bool(outcome.get(KEY_SPAWN_DOORS, false)),
		int(outcome.get(KEY_PENDING_ROOM_REWARD, ENUMS.RewardMode.NONE)),
		int(outcome.get(KEY_ROOMS_CLEARED, 0)),
		int(outcome.get(KEY_ROOM_DEPTH, 0)),
		bool(outcome.get(KEY_BOSS_UNLOCKED, false))
	)

static func outcome_run_cleared(outcome: Dictionary) -> bool:
	return bool(outcome.get(KEY_RUN_CLEARED, false))

static func outcome_open_reward_mode(outcome: Dictionary) -> int:
	return int(outcome.get(KEY_OPEN_REWARD_MODE, ENUMS.RewardMode.NONE))

static func outcome_spawn_doors(outcome: Dictionary) -> bool:
	return bool(outcome.get(KEY_SPAWN_DOORS, false))

static func outcome_pending_room_reward(outcome: Dictionary) -> int:
	return int(outcome.get(KEY_PENDING_ROOM_REWARD, ENUMS.RewardMode.NONE))

static func outcome_rooms_cleared(outcome: Dictionary) -> int:
	return int(outcome.get(KEY_ROOMS_CLEARED, 0))

static func outcome_room_depth(outcome: Dictionary) -> int:
	return int(outcome.get(KEY_ROOM_DEPTH, 0))

static func outcome_boss_unlocked(outcome: Dictionary) -> bool:
	return bool(outcome.get(KEY_BOSS_UNLOCKED, false))

static func door_use_result(used: bool, door: Dictionary) -> Dictionary:
	return {
		KEY_USED: used,
		KEY_DOOR: door if used else {}
	}

static func normalize_door_use_result(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is Dictionary:
		result = value as Dictionary
	elif value != null:
		result = value.to_dict() as Dictionary
	var used := bool(result.get(KEY_USED, false))
	return door_use_result(used, result.get(KEY_DOOR, {}) as Dictionary)

static func door_use_is_used(result: Dictionary) -> bool:
	return bool(result.get(KEY_USED, false))

static func door_use_get_door(result: Dictionary) -> Dictionary:
	return result.get(KEY_DOOR, {}) as Dictionary

static func door_option(label: String, color: Color, kind: Variant, icon: String, reward_mode: int, room_profile: Dictionary, encounter_key: String = "") -> Dictionary:
	var kind_id := normalize_door_kind(kind)
	return {
		KEY_LABEL: label,
		KEY_COLOR: color,
		KEY_KIND_ID: kind_id,
		KEY_KIND: _door_kind_to_legacy(kind_id),
		KEY_ICON: icon,
		KEY_REWARD: normalize_reward_mode(reward_mode),
		KEY_PROFILE: room_profile,
		KEY_ENCOUNTER_KEY: encounter_key.strip_edges().to_lower()
	}

static func normalize_door_option(value: Variant) -> Dictionary:
	var option := value as Dictionary
	if option == null:
		option = {}
	return door_option(
		String(option.get(KEY_LABEL, "Encounter")),
		option.get(KEY_COLOR, Color(0.85, 0.9, 1.0, 0.95)) as Color,
		option.get(KEY_KIND_ID, option.get(KEY_KIND, DOOR_KIND_ENCOUNTER)),
		String(option.get(KEY_ICON, "easy")),
		int(option.get(KEY_REWARD, ENUMS.RewardMode.NONE)),
		option.get(KEY_PROFILE, {}) as Dictionary,
		String(option.get(KEY_ENCOUNTER_KEY, ""))
	)

static func rest_door_option() -> Dictionary:
	var presentation := _door_presentation("rest")
	return door_option(
		String(presentation.get("label", "Rest Site")),
		presentation.get("color", Color(0.66, 1.0, 0.76, 0.92)) as Color,
		presentation.get("kind", DOOR_KIND_REST),
		String(presentation.get("icon", "rest")),
		int(presentation.get("reward", ENUMS.RewardMode.NONE)),
		{},
		"rest"
	)

static func boss_door_option(encounter_key: String) -> Dictionary:
	var normalized_key := encounter_key.strip_edges().to_lower()
	var presentation := _door_presentation(normalized_key)
	if presentation.is_empty():
		presentation = _door_presentation("warden")
		normalized_key = "warden"
	return door_option(
		String(presentation.get("label", "Boss")),
		presentation.get("color", Color(0.95, 0.18, 0.22, 0.98)) as Color,
		presentation.get("kind", DOOR_KIND_BOSS),
		String(presentation.get("icon", "boss")),
		int(presentation.get("reward", ENUMS.RewardMode.NONE)),
		{},
		normalized_key
	)

static func objective_door_option(encounter_profile: Dictionary) -> Dictionary:
	return door_option(
		_objective_prompt_label(encounter_profile),
		Color(0.98, 0.78, 0.34, 0.96),
		DOOR_KIND_ENCOUNTER,
		"objective",
		ENUMS.RewardMode.MISSION,
		encounter_profile,
		String(encounter_profile.get(PROFILE_KEY_OBJECTIVE_KIND, "objective"))
	)

static func trial_door_option(encounter_profile: Dictionary, trial_mutator_name: String, color: Color) -> Dictionary:
	var trial_name := trial_mutator_name.strip_edges()
	if trial_name.is_empty():
		trial_name = mutator_name(profile_enemy_mutator(encounter_profile))
	if trial_name.is_empty():
		trial_name = "Trial"
	return door_option(
		trial_name,
		color,
		DOOR_KIND_ENCOUNTER,
		"trial",
		ENUMS.RewardMode.ARCANA,
		encounter_profile,
		"trial"
	)

static func intro_encounter_door_option(encounter_profile: Dictionary) -> Dictionary:
	var encounter_key := _profile_encounter_key(encounter_profile)
	var presentation := _door_presentation(encounter_key)
	var label := String(presentation.get("label", profile_label(encounter_profile)))
	return door_option(
		label,
		INTRO_ENCOUNTER_DOOR_COLOR,
		DOOR_KIND_ENCOUNTER,
		"easy",
		ENUMS.RewardMode.BOON,
		encounter_profile,
		encounter_key
	)

static func standard_encounter_door_option(encounter_profile: Dictionary) -> Dictionary:
	var encounter_key := _profile_encounter_key(encounter_profile)
	var presentation := _door_presentation(encounter_key)
	var label := String(presentation.get("label", profile_label(encounter_profile)))
	return door_option(
		label,
		STANDARD_ENCOUNTER_DOOR_COLOR,
		DOOR_KIND_ENCOUNTER,
		"easy" if INTRO_ENCOUNTER_DOOR_KEYS.has(encounter_key) else "hard",
		ENUMS.RewardMode.BOON,
		encounter_profile,
		encounter_key
	)

static func door_option_set_position(option: Dictionary, position: Vector2) -> void:
	option[KEY_POSITION] = position

static func door_option_get_position(option: Dictionary) -> Vector2:
	return option.get(KEY_POSITION, Vector2.ZERO) as Vector2

static func door_option_kind_id(option: Dictionary) -> int:
	return normalize_door_kind(option.get(KEY_KIND_ID, option.get(KEY_KIND, DOOR_KIND_ENCOUNTER)))

static func door_option_reward_mode(option: Dictionary) -> int:
	return normalize_reward_mode(option.get(KEY_REWARD, ENUMS.RewardMode.NONE))

static func door_option_profile(option: Dictionary) -> Dictionary:
	return option.get(KEY_PROFILE, {}) as Dictionary

static func door_option_encounter_key(option: Dictionary) -> String:
	return String(option.get(KEY_ENCOUNTER_KEY, "")).strip_edges().to_lower()

static func door_prompt_text(option: Dictionary) -> String:
	var normalized_option := normalize_door_option(option)
	var icon := String(normalized_option.get(KEY_ICON, ""))
	if icon == "trial":
		return String(normalized_option.get(KEY_LABEL, "Trial"))
	var room_profile := door_option_profile(normalized_option)
	var enemy_mutator := profile_enemy_mutator(room_profile)
	var mutator_label := mutator_name(enemy_mutator)
	var encounter_key := door_option_encounter_key(normalized_option)
	var presentation := _door_presentation(encounter_key)
	if not presentation.is_empty() and presentation.has("label"):
		var label := String(presentation.get("label", "Encounter"))
		if not mutator_label.is_empty():
			return "%s  |  Mutator: %s" % [label, mutator_label]
		return label
	if icon == "objective":
		return _objective_prompt_label(door_option_profile(normalized_option))
	var fallback_label := String(normalized_option.get(KEY_LABEL, "Encounter"))
	if not mutator_label.is_empty():
		return "%s  |  Mutator: %s" % [fallback_label, mutator_label]
	return fallback_label

static func door_prompt_name(option: Dictionary) -> String:
	var normalized_option := normalize_door_option(option)
	var prompt_text := door_prompt_text(normalized_option)
	var presentation := _door_presentation(door_option_encounter_key(normalized_option))
	var suffix := String(presentation.get("prompt_name_suffix", ""))
	return prompt_text + suffix

static func door_identity_label(option: Dictionary) -> String:
	var normalized_option := normalize_door_option(option)
	var icon := String(normalized_option.get(KEY_ICON, ""))
	if icon == "trial":
		var trial_mutator_name := mutator_name(profile_enemy_mutator(door_option_profile(normalized_option)))
		if not trial_mutator_name.is_empty():
			return _truncate_door_label(trial_mutator_name)
	if door_option_kind_id(normalized_option) == DOOR_KIND_BOSS:
		var boss_key := door_option_encounter_key(normalized_option)
		var boss_presentation := _door_presentation(boss_key)
		if not boss_presentation.is_empty() and boss_presentation.has("label"):
			return _truncate_door_label(String(boss_presentation.get("label", "Boss")))
		return _truncate_door_label(String(normalized_option.get(KEY_LABEL, "Boss")))
	var encounter_key := door_option_encounter_key(normalized_option)
	var presentation := _door_presentation(encounter_key)
	if not presentation.is_empty() and presentation.has("short_label"):
		return String(presentation.get("short_label", "Encounter"))
	if icon == "objective":
		return _objective_short_label(door_option_profile(normalized_option))
	return _truncate_door_label(String(normalized_option.get(KEY_LABEL, "Encounter")))

static func door_choice(action: Variant, room_profile: Dictionary, reward_mode: int = ENUMS.RewardMode.NONE) -> Dictionary:
	var action_id := normalize_action(action)
	return {
		KEY_ACTION_ID: action_id,
		KEY_ACTION: _action_to_legacy(action_id),
		KEY_PROFILE: room_profile if action_id == ACTION_ENCOUNTER else {},
		KEY_REWARD: normalize_reward_mode(reward_mode)
	}

static func normalize_door_choice(value: Variant) -> Dictionary:
	var choice: Dictionary = {}
	if value is Dictionary:
		choice = value as Dictionary
	elif value != null:
		choice = value.to_dict() as Dictionary
	return door_choice(
		choice.get(KEY_ACTION_ID, choice.get(KEY_ACTION, ACTION_ENCOUNTER)),
		choice.get(KEY_PROFILE, {}) as Dictionary,
		choice.get(KEY_REWARD, ENUMS.RewardMode.NONE)
	)

static func door_choice_action_id(choice: Dictionary) -> int:
	return normalize_action(choice.get(KEY_ACTION_ID, choice.get(KEY_ACTION, ACTION_ENCOUNTER)))

static func door_choice_profile(choice: Dictionary) -> Dictionary:
	return choice.get(KEY_PROFILE, {}) as Dictionary

static func door_choice_reward_mode(choice: Dictionary) -> int:
	return normalize_reward_mode(choice.get(KEY_REWARD, ENUMS.RewardMode.NONE))
