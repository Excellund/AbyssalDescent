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
const PROFILE_KEY_SPECTRE_COUNT := "spectre_count"
const PROFILE_KEY_PYRE_COUNT := "pyre_count"
const PROFILE_KEY_TETHER_COUNT := "tether_count"
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
const MUTATOR_STAT_PYRE_FIELD_RADIUS_MULT := "pyre_field_radius_mult"
const MUTATOR_STAT_PYRE_FIELD_DURATION_MULT := "pyre_field_duration_mult"
const MUTATOR_STAT_SPECTRE_WINDUP_MULT := "spectre_windup_mult"
const MUTATOR_STAT_SPECTRE_STRIKE_DELAY_MULT := "spectre_strike_delay_mult"

const DEBUG_ENCOUNTER_NONE := DEBUG_ENUMS.Encounter.NONE

# These are now derived from the encounter registry. Keep them for backward compatibility.
# They are populated dynamically to stay in sync with _build_encounter_registry().
static var DEBUG_ENCOUNTER_MAP: Array[Dictionary]
static var DEBUG_ENCOUNTER_BY_KEY: Dictionary
static var DEBUG_ENCOUNTER_KEY_BY_ID: Dictionary
static var DEBUG_OBJECTIVE_DISPLAY_LABELS: Dictionary
static var DEBUG_ENCOUNTER_GLOSSARY_LABELS: Dictionary
static var ENCOUNTER_DOOR_PRESENTATION: Dictionary

static func _init_registry_derived_data() -> void:
	DEBUG_ENCOUNTER_MAP = _derive_debug_encounter_map()
	DEBUG_ENCOUNTER_BY_KEY = _derive_debug_encounter_index_by_key()
	DEBUG_ENCOUNTER_KEY_BY_ID = _derive_debug_encounter_key_by_id()
	DEBUG_OBJECTIVE_DISPLAY_LABELS = _derive_display_labels()
	DEBUG_ENCOUNTER_GLOSSARY_LABELS = _derive_glossary_labels()
	ENCOUNTER_DOOR_PRESENTATION = _derive_door_presentation()

const INTRO_ENCOUNTER_DOOR_KEYS := {
	"skirmish": true,
	"pursuit": true
}

const INTRO_ENCOUNTER_DOOR_COLOR := Color(0.34, 0.8, 1.0, 0.95)
const STANDARD_ENCOUNTER_DOOR_COLOR := Color(0.93, 0.62, 0.28, 0.95)

# ===== ENCOUNTER REGISTRY (Centralized Single Source of Truth) =====
# All encounter metadata is defined here: debug IDs, display labels, door presentation,
# bearing definitions, and identity. This eliminates sync bugs when adding/changing encounters.
static func _build_encounter_registry() -> Array[Dictionary]:
	return [
		{
			"key": "none",
			"id": DEBUG_ENUMS.Encounter.NONE,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "None",
			"glossary_label": "",
		},
		{
			"key": "rest",
			"id": DEBUG_ENUMS.Encounter.REST_SITE,
			"is_boss": false, "is_rest": true, "is_objective": false,
			"display_label": "Rest Site",
			"glossary_label": "Rest Site",
			"door_presentation": {
				"label": "Rest Site",
				"short_label": "Rest",
				"color": Color(0.66, 1.0, 0.76, 0.92),
				"icon": "rest",
				"kind": DOOR_KIND_REST,
				"reward": ENUMS.RewardMode.NONE,
				"prompt_name_suffix": ""
			}
		},
		{
			"key": "skirmish",
			"id": DEBUG_ENUMS.Encounter.SKIRMISH,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "Skirmish",
			"glossary_label": "",
			"door_presentation": {
				"label": "Skirmish"
			},
			"bearing_label": ""
		},
		{
			"key": "crossfire",
			"id": DEBUG_ENUMS.Encounter.CROSSFIRE,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "Crossfire",
			"glossary_label": "",
			"door_presentation": {
				"label": "Crossfire"
			},
			"bearing_label": "Crossfire",
			"identity": "Ranged firing line with flanking disruption."
		},
		{
			"key": "fortress",
			"id": DEBUG_ENUMS.Encounter.FORTRESS,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "Fortress",
			"glossary_label": "",
			"door_presentation": {
				"label": "Fortress"
			},
			"bearing_label": "Fortress",
			"identity": "Defensive wall built around shielders."
		},
		{
			"key": "onslaught",
			"id": DEBUG_ENUMS.Encounter.ONSLAUGHT,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "Onslaught",
			"glossary_label": "",
			"door_presentation": {
				"label": "Onslaught"
			},
			"bearing_label": "Onslaught",
			"identity": "Melee flood: relentless close-range pressure."
		},
		{
			"key": "vanguard",
			"id": DEBUG_ENUMS.Encounter.VANGUARD,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "Vanguard",
			"glossary_label": "",
			"door_presentation": {
				"label": "Vanguard"
			},
			"bearing_label": "Vanguard",
			"identity": "Shielded advance and structured frontline push."
		},
		{
			"key": "blitz",
			"id": DEBUG_ENUMS.Encounter.BLITZ,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "Blitz",
			"glossary_label": "",
			"door_presentation": {
				"label": "Blitz"
			},
			"bearing_label": "Blitz",
			"identity": "Fast assault. Hesitation gets punished."
		},
		{
			"key": "ambush",
			"id": DEBUG_ENUMS.Encounter.AMBUSH,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "Ambush",
			"glossary_label": "",
			"door_presentation": {
				"label": "Ambush"
			},
			"bearing_label": "Ambush",
			"identity": "Predator pack that collapses escape routes."
		},
		{
			"key": "suppression",
			"id": DEBUG_ENUMS.Encounter.SUPPRESSION,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "Suppression",
			"glossary_label": "",
			"door_presentation": {
				"label": "Suppression"
			},
			"bearing_label": "Suppression",
			"identity": "Lancer zone saturation. Archers reinforce the denial field."
		},
		{
			"key": "convergence",
			"id": DEBUG_ENUMS.Encounter.CONVERGENCE,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "Convergence",
			"glossary_label": "",
			"door_presentation": {
				"label": "Convergence"
			},
			"bearing_label": "Convergence",
			"identity": "Spectres predict escape routes while pursuit pressure collapses the seam."
		},
		{
			"key": "gauntlet",
			"id": DEBUG_ENUMS.Encounter.GAUNTLET,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "Gauntlet",
			"glossary_label": "",
			"door_presentation": {
				"label": "Gauntlet"
			},
			"bearing_label": "Gauntlet",
			"identity": "Mixed-threat test of every enemy role."
		},
		{
			"key": "trial",
			"id": DEBUG_ENUMS.Encounter.TRIAL,
			"is_boss": false, "is_rest": false, "is_objective": false,
			"display_label": "Trial",
			"glossary_label": "Trial",
			"door_presentation": {
				"short_label": "Trial"
			}
		},
		{
			"key": "last_stand",
			"id": DEBUG_ENUMS.Encounter.OBJECTIVE_LAST_STAND,
			"is_boss": false, "is_rest": false, "is_objective": true,
			"display_label": "Objective - Last Stand",
			"glossary_label": "Last Stand"
		},
		{
			"key": "cut_the_signal",
			"id": DEBUG_ENUMS.Encounter.OBJECTIVE_PRIORITY_TARGET,
			"is_boss": false, "is_rest": false, "is_objective": true,
			"display_label": "Objective - Cut the Signal",
			"glossary_label": "Cut the Signal"
		},
		{
			"key": "hold_the_line",
			"id": DEBUG_ENUMS.Encounter.OBJECTIVE_HOLD_THE_LINE,
			"is_boss": false, "is_rest": false, "is_objective": true,
			"display_label": "Objective - Hold the Line",
			"glossary_label": "Hold the Line"
		},
		{
			"key": "random_objective",
			"id": DEBUG_ENUMS.Encounter.OBJECTIVE_RANDOM,
			"is_boss": false, "is_rest": false, "is_objective": true,
			"display_label": "Objective - Random",
			"glossary_label": ""
		},
		{
			"key": "warden",
			"id": DEBUG_ENUMS.Encounter.BOSS_1,
			"is_boss": true, "is_rest": false, "is_objective": false,
			"display_label": "Warden",
			"glossary_label": "Warden",
			"door_presentation": {
				"label": "Warden",
				"short_label": "Boss",
				"color": Color(0.96, 0.46, 0.18, 0.98),
				"icon": "boss",
				"kind": DOOR_KIND_BOSS,
				"reward": ENUMS.RewardMode.NONE,
				"prompt_name_suffix": " Gate"
			}
		},
		{
			"key": "sovereign",
			"id": DEBUG_ENUMS.Encounter.BOSS_2,
			"is_boss": true, "is_rest": false, "is_objective": false,
			"display_label": "Sovereign",
			"glossary_label": "Sovereign",
			"door_presentation": {
				"label": "Sovereign",
				"short_label": "Boss",
				"color": Color(0.92, 0.28, 0.1, 0.98),
				"icon": "boss",
				"kind": DOOR_KIND_BOSS,
				"reward": ENUMS.RewardMode.NONE,
				"prompt_name_suffix": " Gate"
			}
		},
		{
			"key": "lacuna",
			"id": DEBUG_ENUMS.Encounter.BOSS_3,
			"is_boss": true, "is_rest": false, "is_objective": false,
			"display_label": "Lacuna",
			"glossary_label": "Lacuna",
			"door_presentation": {
				"label": "Lacuna",
				"short_label": "Boss",
				"color": Color(0.34, 0.92, 0.74, 0.98),
				"icon": "boss",
				"kind": DOOR_KIND_BOSS,
				"reward": ENUMS.RewardMode.NONE,
				"prompt_name_suffix": " Gate"
			}
		},
	]

static var _encounter_registry_cache: Array[Dictionary] = []

static func _get_encounter_registry() -> Array[Dictionary]:
	if _encounter_registry_cache.is_empty():
		_encounter_registry_cache = _build_encounter_registry()
	return _encounter_registry_cache

static func _ensure_registry_initialized() -> void:
	if DEBUG_ENCOUNTER_MAP.is_empty():
		_init_registry_derived_data()

static func _derive_debug_encounter_map() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _get_encounter_registry():
		result.append({
			"id": entry.get("id", 0),
			"key": entry.get("key", ""),
			"is_boss": entry.get("is_boss", false),
			"is_rest": entry.get("is_rest", false),
			"is_objective": entry.get("is_objective", false),
		})
	return result

static func _derive_debug_encounter_index_by_key() -> Dictionary:
	var result := {}
	for entry in DEBUG_ENCOUNTER_MAP:
		var encounter_key := String((entry as Dictionary).get("key", ""))
		if encounter_key.is_empty():
			continue
		result[encounter_key] = entry
	return result

static func _derive_debug_encounter_key_by_id() -> Dictionary:
	var result := {}
	for entry in DEBUG_ENCOUNTER_MAP:
		var encounter_id := int((entry as Dictionary).get("id", -1))
		if encounter_id < 0:
			continue
		result[encounter_id] = String((entry as Dictionary).get("key", ""))
	return result

static func _derive_door_presentation() -> Dictionary:
	var result := {}
	for entry in _get_encounter_registry():
		var key: String = entry.get("key", "")
		if not key.is_empty():
			var presentation = entry.get("door_presentation", {})
			if presentation is Dictionary and not (presentation as Dictionary).is_empty():
				result[key] = presentation
	return result

static func _derive_glossary_labels() -> Dictionary:
	var result := {}
	for entry in _get_encounter_registry():
		var key: String = entry.get("key", "")
		var label: String = entry.get("glossary_label", "")
		if not key.is_empty() and not label.is_empty():
			result[key] = label
	return result

static func get_bearing_labels_from_registry() -> Array[String]:
	var labels: Array[String] = []
	for entry in _get_encounter_registry():
		var bearing_label: String = entry.get("bearing_label", "")
		if not bearing_label.is_empty() and not labels.has(bearing_label):
			labels.append(bearing_label)
	return labels

static func _derive_display_labels() -> Dictionary:
	var result := {}
	for entry in _get_encounter_registry():
		var key: String = entry.get("key", "")
		var label: String = entry.get("display_label", "")
		if not key.is_empty() and not label.is_empty():
			result[key] = label
	return result

# ===== END ENCOUNTER REGISTRY =====

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
	_ensure_registry_initialized()
	var normalized := encounter_key.strip_edges().to_lower()
	return DEBUG_ENCOUNTER_BY_KEY.get(normalized, {}) as Dictionary

static func debug_encounter_entries() -> Array[Dictionary]:
	_ensure_registry_initialized()
	var entries: Array[Dictionary] = []
	for entry in DEBUG_ENCOUNTER_MAP:
		entries.append((entry as Dictionary).duplicate(true))
	return entries

static func debug_encounter_display_name(encounter_key: String) -> String:
	_ensure_registry_initialized()
	var normalized := canonicalize_debug_encounter_key(encounter_key)
	if normalized.is_empty():
		return ""
	if normalized == "none":
		return "None"
	if DEBUG_OBJECTIVE_DISPLAY_LABELS.has(normalized):
		return String(DEBUG_OBJECTIVE_DISPLAY_LABELS.get(normalized, ""))
	if normalized == "trial":
		return "Trial"
	var presentation := _door_presentation(normalized)
	if not presentation.is_empty() and presentation.has("label"):
		return String(presentation.get("label", ""))
	return ""

static func debug_encounter_glossary_name(encounter_key: String) -> String:
	_ensure_registry_initialized()
	var normalized := canonicalize_debug_encounter_key(encounter_key)
	if normalized.is_empty() or normalized == "none" or normalized == "random_objective":
		return ""
	if DEBUG_ENCOUNTER_GLOSSARY_LABELS.has(normalized):
		return String(DEBUG_ENCOUNTER_GLOSSARY_LABELS.get(normalized, ""))
	var presentation := _door_presentation(normalized)
	if not presentation.is_empty() and presentation.has("label"):
		return String(presentation.get("label", ""))
	return ""

static func validate_encounter_sync(glossary_rows: Array[Dictionary]) -> Array[String]:
	_ensure_registry_initialized()
	var issues: Array[String] = []
	var ids_seen := {}
	var keys_seen := {}
	for entry in DEBUG_ENCOUNTER_MAP:
		var encounter_id := int(entry.get("id", -1))
		var encounter_key := String(entry.get("key", ""))
		if ids_seen.has(encounter_id):
			issues.append("Duplicate debug encounter id %d." % encounter_id)
		else:
			ids_seen[encounter_id] = true
		if encounter_key.is_empty():
			issues.append("Debug encounter entry with id %d has empty key." % encounter_id)
			continue
		if keys_seen.has(encounter_key):
			issues.append("Duplicate debug encounter key '%s'." % encounter_key)
		else:
			keys_seen[encounter_key] = true
		if debug_encounter_display_name(encounter_key).is_empty():
			issues.append("Debug encounter key '%s' is missing a display label mapping." % encounter_key)

	var glossary_names := {}
	for row in glossary_rows:
		var glossary_name := String((row as Dictionary).get("name", "")).strip_edges().to_lower()
		if not glossary_name.is_empty():
			glossary_names[glossary_name] = true

	for entry in DEBUG_ENCOUNTER_MAP:
		var encounter_key := String(entry.get("key", ""))
		var expected_glossary_name := debug_encounter_glossary_name(encounter_key)
		if expected_glossary_name.is_empty():
			continue
		if not glossary_names.has(expected_glossary_name.to_lower()):
			issues.append("Glossary is missing '%s' for debug encounter key '%s'." % [expected_glossary_name, encounter_key])

	return issues

static func canonicalize_debug_encounter_key(encounter_key: String) -> String:
	var entry := debug_encounter_entry(encounter_key)
	if entry.is_empty():
		return ""
	return String(entry.get("key", ""))

static func debug_encounter_key_from_id(encounter_id: int) -> String:
	_ensure_registry_initialized()
	return String(DEBUG_ENCOUNTER_KEY_BY_ID.get(encounter_id, ""))

static func debug_encounter_is_objective(encounter_key: String) -> bool:
	var entry := debug_encounter_entry(encounter_key)
	if entry.is_empty():
		return false
	return bool(entry.get("is_objective", false))

static func _door_presentation(encounter_key: String) -> Dictionary:
	_ensure_registry_initialized()
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
	profile_set_specialist_counts(
		normalized,
		int(input.get(PROFILE_KEY_LURKER_COUNT, 0)),
		int(input.get(PROFILE_KEY_RAM_COUNT, 0)),
		int(input.get(PROFILE_KEY_LANCER_COUNT, 0)),
		int(input.get(PROFILE_KEY_SPECTRE_COUNT, 0)),
		int(input.get(PROFILE_KEY_PYRE_COUNT, 0)),
		int(input.get(PROFILE_KEY_TETHER_COUNT, 0))
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

# Enemy count metadata: list of all enemy types for data-driven access
static func _get_enemy_count_keys() -> Array[String]:
	return ["chaser", "charger", "archer", "shielder", "lurker", "ram", "lancer", "spectre", "pyre", "tether"]

static func _get_enemy_count_key_for_type(enemy_type: String) -> String:
	return "%s_count" % enemy_type.strip_edges().to_lower()

static func _get_enemy_count(enemy_type: String, profile_value: Dictionary) -> int:
	var key = _get_enemy_count_key_for_type(enemy_type)
	return int(profile_value.get(key, 0))

static func _set_enemy_count(enemy_type: String, count: int, profile_value: Dictionary) -> void:
	var key = _get_enemy_count_key_for_type(enemy_type)
	profile_value[key] = count

# Backward-compatible wrappers for individual enemy type getters
static func profile_chaser_count(profile_value: Dictionary) -> int:
	return _get_enemy_count("chaser", profile_value)

static func profile_charger_count(profile_value: Dictionary) -> int:
	return _get_enemy_count("charger", profile_value)

static func profile_archer_count(profile_value: Dictionary) -> int:
	return _get_enemy_count("archer", profile_value)

static func profile_shielder_count(profile_value: Dictionary) -> int:
	return _get_enemy_count("shielder", profile_value)

static func profile_lurker_count(profile_value: Dictionary) -> int:
	return _get_enemy_count("lurker", profile_value)

static func profile_ram_count(profile_value: Dictionary) -> int:
	return _get_enemy_count("ram", profile_value)

static func profile_lancer_count(profile_value: Dictionary) -> int:
	return _get_enemy_count("lancer", profile_value)

static func profile_spectre_count(profile_value: Dictionary) -> int:
	return _get_enemy_count("spectre", profile_value)

static func profile_pyre_count(profile_value: Dictionary) -> int:
	return _get_enemy_count("pyre", profile_value)

static func profile_tether_count(profile_value: Dictionary) -> int:
	return _get_enemy_count("tether", profile_value)

static func profile_enemy_mutator(profile_value: Dictionary) -> Dictionary:
	return profile_value.get(PROFILE_KEY_ENEMY_MUTATOR, {}) as Dictionary

static func profile_player_mutator(profile_value: Dictionary) -> Dictionary:
	return profile_value.get(PROFILE_KEY_PLAYER_MUTATOR, {}) as Dictionary

static func profile_set_room_size(profile_value: Dictionary, room_size: Vector2) -> void:
	profile_value[PROFILE_KEY_ROOM_SIZE] = room_size

static func profile_set_static_camera(profile_value: Dictionary, value: bool) -> void:
	profile_value[PROFILE_KEY_STATIC_CAMERA] = value

static func profile_set_counts(profile_value: Dictionary, chasers: int, chargers: int, archers: int, shielders: int) -> void:
	_set_enemy_count("chaser", chasers, profile_value)
	_set_enemy_count("charger", chargers, profile_value)
	_set_enemy_count("archer", archers, profile_value)
	_set_enemy_count("shielder", shielders, profile_value)

static func profile_set_specialist_counts(profile_value: Dictionary, lurkers: int, rams: int, lancers: int, spectres: int = 0, pyres: int = 0, tethers: int = 0) -> void:
	var specialist_counts = {"lurker": lurkers, "ram": rams, "lancer": lancers, "spectre": spectres, "pyre": pyres, "tether": tethers}
	for enemy_type: String in specialist_counts:
		_set_enemy_count(enemy_type, specialist_counts[enemy_type], profile_value)

static func profile_counts(chasers: int, chargers: int, archers: int, shielders: int, lurkers: int = 0, rams: int = 0, lancers: int = 0, spectres: int = 0, pyres: int = 0, tethers: int = 0) -> Dictionary:
	return {
		PROFILE_KEY_CHASER_COUNT: chasers,
		PROFILE_KEY_CHARGER_COUNT: chargers,
		PROFILE_KEY_ARCHER_COUNT: archers,
		PROFILE_KEY_SHIELDER_COUNT: shielders,
		PROFILE_KEY_LURKER_COUNT: lurkers,
		PROFILE_KEY_RAM_COUNT: rams,
		PROFILE_KEY_LANCER_COUNT: lancers,
		PROFILE_KEY_SPECTRE_COUNT: spectres,
		PROFILE_KEY_PYRE_COUNT: pyres,
		PROFILE_KEY_TETHER_COUNT: tethers
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
		profile_lancer_count(profile_value),
		profile_spectre_count(profile_value),
		profile_pyre_count(profile_value),
		profile_tether_count(profile_value)
	)

# Helper function: get all enemy counts as a dict indexed by enemy type
static func _get_all_enemy_counts(profile_value: Dictionary) -> Dictionary:
	var result := {}
	for enemy_type: String in _get_enemy_count_keys():
		result[enemy_type] = _get_enemy_count(enemy_type, profile_value)
	return result

# Helper function: set all enemy counts from a dict indexed by enemy type
static func _set_all_enemy_counts(profile_value: Dictionary, counts: Dictionary) -> void:
	for enemy_type: String in _get_enemy_count_keys():
		if counts.has(enemy_type):
			_set_enemy_count(enemy_type, int(counts[enemy_type]), profile_value)

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
		profile_count_from_counts(counts, PROFILE_KEY_LANCER_COUNT),
		profile_count_from_counts(counts, PROFILE_KEY_SPECTRE_COUNT),
		profile_count_from_counts(counts, PROFILE_KEY_PYRE_COUNT),
		profile_count_from_counts(counts, PROFILE_KEY_TETHER_COUNT)
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
	for enemy_type: String in _get_enemy_count_keys():
		var current = _get_enemy_count(enemy_type, modified)
		var scaled = profile_scale_count(current, pressure_mult)
		_set_enemy_count(enemy_type, scaled, modified)
	if minimum_total > 0:
		var current_total := profile_total_enemy_count(modified)
		if current_total < minimum_total:
			var delta := minimum_total - current_total
			_set_enemy_count("chaser", _get_enemy_count("chaser", modified) + delta, modified)
	return modified

static func profile_total_enemy_count(profile_value: Dictionary) -> int:
	var total := 0
	for enemy_type: String in _get_enemy_count_keys():
		total += _get_enemy_count(enemy_type, profile_value)
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
