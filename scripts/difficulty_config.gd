## Centralized difficulty configuration
## Maps tier to scaling multipliers, pacing rules, and encounter generation parameters

extends RefCounted

const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")
const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")
const ASCENSION_REGISTRY := preload("res://scripts/progression/ascension_modifier_registry.gd")

## Maps merged ascension modifier payload keys onto base tier config keys.
## Format: ascension_key -> [base_config_key, op]. Any modifier key not listed
## here remains accessible via config["ascension"] for callers that want it
## raw (e.g. encounter builder reading enemy_health_mult, reward UI reading
## reward_choice_count_add, encounter flow reading rest_disabled_set).
const _ASCENSION_TO_CONFIG_MAPPING := {
	"enemy_contact_damage_mult": ["enemy_contact_damage_mult", "mul"],
	"wave_interval_mult": ["wave_interval_seconds", "mul"],
	"rest_heal_ratio_mult": ["rest_heal_ratio_mult", "mul"],
	"mutator_frequency_mult": ["mutator_frequency_mult", "mul"],
	"specialist_enemy_depth_offset_add": ["specialist_enemy_depth_offset", "add"],
	"specialist_enemy_pressure_mult": ["specialist_enemy_pressure_mult", "mul"],
	"boss_difficulty_mult": ["boss_difficulty_mult", "mul"],
	"player_damage_taken_mult": ["player_damage_taken_mult", "mul"],
	"mutator_damage_mult": ["mutator_damage_mult", "mul"],
	"player_starting_health_bonus_add": ["player_starting_health_bonus", "add"]
}

## ===== BASE ENCOUNTER GENERATION DEFINITIONS =====
## Shared across singleplayer and multiplayer modes (stored here as source of truth)
## Used by multiplayer config to inherit common structure without duplication

static func get_base_encounter_count_before_boss() -> int:
	return 8

static func get_base_progression_ranks() -> Dictionary:
	"""Returns progression rank for each bearing (used for scaling calculations)"""
	return {
		BEARING_ENUMS.BearingTier.PILGRIM: 0,
		BEARING_ENUMS.BearingTier.DELVER: 1,
		BEARING_ENUMS.BearingTier.HARBINGER: 2,
		BEARING_ENUMS.BearingTier.FORSWORN: 3
	}

## ===== UNIFIED BEARING DEFINITIONS =====
## Centralized source of truth for all bearing configurations (singleplayer + multiplayer).
## Includes base encounter generation fields, player affordances, and multiplayer-specific scaling.
## Singleplayer uses core fields; multiplayer adds co-op scaling per extra player.
static func _build_bearing_definitions() -> Dictionary:
	return {
		BEARING_ENUMS.BearingTier.PILGRIM: {
			"name": META_PROGRESS.TIER_NAMES[BEARING_ENUMS.BearingTier.PILGRIM],
			"description": META_PROGRESS.TIER_DESCRIPTIONS[BEARING_ENUMS.BearingTier.PILGRIM],
			"bearing_key": "Pilgrim",
			"difficulty_rank": 0,
			## === Encounter Generation (Singleplayer Base) ===
			"encounter_count_before_boss": get_base_encounter_count_before_boss(),
			"base_enemy_pressure_mult": 0.6,
			"wave_interval_seconds": 12.0,
			"depth_pressure_divisor": 1.5,
			"specialist_enemy_depth_offset": 3,
			"specialist_enemy_pressure_mult": 0.75,
			"boss_difficulty_mult": 0.75,
			## === Specialist Enemy Type Offsets (Multiplayer) ===
			"specialist_enemy_lurker_offset": 5,
			"specialist_enemy_ram_offset": 6,
			"specialist_enemy_lancer_offset": 7,
			"specialist_enemy_spectre_offset": 8,
			"specialist_enemy_pyre_offset": 9,
			"specialist_enemy_tether_offset": 10,
			## === Mutator and Encounter Complexity ===
			"mutator_frequency_mult": 0.5,
			"trial_encounter_frequency_mult": 0.7,
			"mutator_damage_mult": 0.8,
			## === Player Affordances ===
			"player_health_mult": 1.0,
			"player_starting_health_bonus": 35.0,
			"player_damage_taken_mult": 0.78,
			"enemy_contact_damage_mult": 1.0,
			"player_damage_dealt_mult": 1.0,
			"player_heal_mult": 1.0,
			"rest_heal_ratio_mult": 1.25,
			## === Multiplayer Co-op Scaling ===
			"coop_enemy_count_per_extra_player": 0.22,
			"coop_enemy_count_curve_power": 0.85,
			"coop_enemy_count_max_mult": 1.55,
			"coop_enemy_health_per_extra_player": 0.56,
			"coop_enemy_health_curve_power": 0.9,
			"coop_enemy_health_max_mult": 2.5,
			"coop_boss_health_per_extra_player": 1.0,
			"coop_boss_health_curve_power": 0.92,
			"coop_boss_health_max_mult": 3.4
		},
		BEARING_ENUMS.BearingTier.DELVER: {
			"name": META_PROGRESS.TIER_NAMES[BEARING_ENUMS.BearingTier.DELVER],
			"description": META_PROGRESS.TIER_DESCRIPTIONS[BEARING_ENUMS.BearingTier.DELVER],
			"bearing_key": "Delver",
			"difficulty_rank": 1,
			## === Encounter Generation (Singleplayer Base) ===
			"encounter_count_before_boss": get_base_encounter_count_before_boss(),
			"base_enemy_pressure_mult": 1.0,
			"wave_interval_seconds": 10.0,
			"depth_pressure_divisor": 1.0,
			"specialist_enemy_depth_offset": 0,
			"specialist_enemy_pressure_mult": 1.0,
			"boss_difficulty_mult": 1.0,
			## === Specialist Enemy Type Offsets (Multiplayer) ===
			"specialist_enemy_lurker_offset": 4,
			"specialist_enemy_ram_offset": 5,
			"specialist_enemy_lancer_offset": 6,
			"specialist_enemy_spectre_offset": 7,
			"specialist_enemy_pyre_offset": 8,
			"specialist_enemy_tether_offset": 9,
			## === Mutator and Encounter Complexity ===
			"mutator_frequency_mult": 1.0,
			"trial_encounter_frequency_mult": 1.0,
			"mutator_damage_mult": 1.0,
			## === Player Affordances ===
			"player_health_mult": 1.0,
			"player_starting_health_bonus": 0.0,
			"player_damage_taken_mult": 0.92,
			"enemy_contact_damage_mult": 0.94,
			"player_damage_dealt_mult": 1.0,
			"player_heal_mult": 1.0,
			"rest_heal_ratio_mult": 1.0,
			## === Multiplayer Co-op Scaling ===
			"coop_enemy_count_per_extra_player": 0.25,
			"coop_enemy_count_curve_power": 0.85,
			"coop_enemy_count_max_mult": 1.6,
			"coop_enemy_health_per_extra_player": 0.62,
			"coop_enemy_health_curve_power": 0.92,
			"coop_enemy_health_max_mult": 2.7,
			"coop_boss_health_per_extra_player": 1.08,
			"coop_boss_health_curve_power": 0.95,
			"coop_boss_health_max_mult": 3.7
		},
		BEARING_ENUMS.BearingTier.HARBINGER: {
			"name": META_PROGRESS.TIER_NAMES[BEARING_ENUMS.BearingTier.HARBINGER],
			"description": META_PROGRESS.TIER_DESCRIPTIONS[BEARING_ENUMS.BearingTier.HARBINGER],
			"bearing_key": "Harbinger",
			"difficulty_rank": 2,
			## === Encounter Generation (Singleplayer Base) ===
			"encounter_count_before_boss": get_base_encounter_count_before_boss(),
			"base_enemy_pressure_mult": 1.25,
			"wave_interval_seconds": 9.0,
			"depth_pressure_divisor": 0.8,
			"specialist_enemy_depth_offset": -1,
			"specialist_enemy_pressure_mult": 1.05,
			"boss_difficulty_mult": 1.15,
			## === Specialist Enemy Type Offsets (Multiplayer) ===
			"specialist_enemy_lurker_offset": 3,
			"specialist_enemy_ram_offset": 4,
			"specialist_enemy_lancer_offset": 5,
			"specialist_enemy_spectre_offset": 6,
			"specialist_enemy_pyre_offset": 7,
			"specialist_enemy_tether_offset": 8,
			## === Mutator and Encounter Complexity ===
			"mutator_frequency_mult": 1.3,
			"trial_encounter_frequency_mult": 1.2,
			"mutator_damage_mult": 1.1,
			## === Player Affordances ===
			"player_health_mult": 1.0,
			"player_starting_health_bonus": 0.0,
			"player_damage_taken_mult": 1.0,
			"enemy_contact_damage_mult": 0.94,
			"player_damage_dealt_mult": 1.0,
			"player_heal_mult": 1.0,
			"rest_heal_ratio_mult": 1.0,
			## === Multiplayer Co-op Scaling ===
			"coop_enemy_count_per_extra_player": 0.28,
			"coop_enemy_count_curve_power": 0.85,
			"coop_enemy_count_max_mult": 1.65,
			"coop_enemy_health_per_extra_player": 0.68,
			"coop_enemy_health_curve_power": 0.95,
			"coop_enemy_health_max_mult": 2.9,
			"coop_boss_health_per_extra_player": 1.18,
			"coop_boss_health_curve_power": 0.98,
			"coop_boss_health_max_mult": 4.0
		},
		BEARING_ENUMS.BearingTier.FORSWORN: {
			"name": META_PROGRESS.TIER_NAMES[BEARING_ENUMS.BearingTier.FORSWORN],
			"description": META_PROGRESS.TIER_DESCRIPTIONS[BEARING_ENUMS.BearingTier.FORSWORN],
			"bearing_key": "Forsworn",
			"difficulty_rank": 3,
			## === Encounter Generation (Singleplayer Base) ===
			"encounter_count_before_boss": get_base_encounter_count_before_boss(),
			"base_enemy_pressure_mult": 1.5,
			"wave_interval_seconds": 8.0,
			"depth_pressure_divisor": 0.6,
			"specialist_enemy_depth_offset": -2,
			"specialist_enemy_pressure_mult": 1.15,
			"boss_difficulty_mult": 1.3,
			## === Specialist Enemy Type Offsets (Multiplayer) ===
			"specialist_enemy_lurker_offset": 2,
			"specialist_enemy_ram_offset": 3,
			"specialist_enemy_lancer_offset": 4,
			"specialist_enemy_spectre_offset": 5,
			"specialist_enemy_pyre_offset": 6,
			"specialist_enemy_tether_offset": 7,
			## === Mutator and Encounter Complexity ===
			"mutator_frequency_mult": 1.6,
			"trial_encounter_frequency_mult": 1.4,
			"mutator_damage_mult": 1.25,
			## === Player Affordances ===
			"player_health_mult": 1.0,
			"player_starting_health_bonus": 0.0,
			"player_damage_taken_mult": 1.0,
			"enemy_contact_damage_mult": 0.94,
			"player_damage_dealt_mult": 1.0,
			"player_heal_mult": 1.0,
			"rest_heal_ratio_mult": 1.0,
			## === Multiplayer Co-op Scaling ===
			"coop_enemy_count_per_extra_player": 0.30,
			"coop_enemy_count_curve_power": 0.85,
			"coop_enemy_count_max_mult": 1.7,
			"coop_enemy_health_per_extra_player": 0.74,
			"coop_enemy_health_curve_power": 0.98,
			"coop_enemy_health_max_mult": 3.1,
			"coop_boss_health_per_extra_player": 1.28,
			"coop_boss_health_curve_power": 1.0,
			"coop_boss_health_max_mult": 4.3
		}
	}

static var BEARING_DEFINITIONS = _build_bearing_definitions()
static var _bearing_definitions_validated: bool = false

static func _ensure_bearing_definitions_validated() -> void:
	if _bearing_definitions_validated:
		return
	_validate_bearing_definitions()
	_bearing_definitions_validated = true

## Difficulty config per tier: pacing, pressure, and affordances
static func get_tier_config(tier: int) -> Dictionary:
	_ensure_bearing_definitions_validated()
	if BEARING_DEFINITIONS.has(tier):
		return (BEARING_DEFINITIONS[tier] as Dictionary).duplicate(true)
	push_error("Invalid tier %d requested in get_tier_config()" % tier)
	return (BEARING_DEFINITIONS[BEARING_ENUMS.BearingTier.DELVER] as Dictionary).duplicate(true)

## Resolve a tier config with an ascension loadout layered on top.
## Mutates a fresh dict; the base get_tier_config() result is untouched.
## Returns a dict with the standard tier keys plus:
##   "ascension_rank"     int   total heat cost of the loadout
##   "ascension_loadout"  Array sanitized list of modifier ids applied
##   "ascension"          Dict  raw merged modifier payload (for keys not
##                              folded into the base config — e.g. enemy_health_mult,
##                              reward_choice_count_add, rest_disabled_set,
##                              arcana_pool_shrink_mult).
static func get_tier_config_with_ascension(tier: int, ascension_loadout: Array) -> Dictionary:
	var config: Dictionary = get_tier_config(tier).duplicate(true)
	var sanitized: Array = []
	for entry in ascension_loadout:
		var id: String = String(entry)
		if ASCENSION_REGISTRY.has_modifier(id) and not sanitized.has(id):
			sanitized.append(id)
	config["ascension_loadout"] = sanitized
	config["ascension_rank"] = ASCENSION_REGISTRY.compute_loadout_rank(sanitized)
	var merged: Dictionary = ASCENSION_REGISTRY.merge_loadout_payload(sanitized)
	config["ascension"] = merged
	for key in merged.keys():
		var key_str: String = String(key)
		if not _ASCENSION_TO_CONFIG_MAPPING.has(key_str):
			continue
		var mapping: Array = _ASCENSION_TO_CONFIG_MAPPING[key_str] as Array
		var base_key: String = String(mapping[0])
		var op: String = String(mapping[1])
		var ascension_value: float = float(merged[key_str])
		var existing: Variant = config.get(base_key, 0.0 if op == "add" else 1.0)
		match op:
			"mul":
				config[base_key] = float(existing) * ascension_value
			"add":
				config[base_key] = float(existing) + ascension_value
			"set":
				config[base_key] = merged[key_str]
	return config

## Get a specific multiplier for a tier
static func get_tier_multiplier(tier: int, key: String, default: float = 1.0) -> float:
	var config := get_tier_config(tier)
	return float(config.get(key, default))

## Get a specific value for a tier
static func get_tier_value(tier: int, key: String, default: Variant = null) -> Variant:
	var config := get_tier_config(tier)
	return config.get(key, default)

## Check if a specialist enemy type should appear at this depth/tier
static func should_specialist_appear(tier: int, specialist_start_depth: int, current_depth: int) -> bool:
	var config := get_tier_config(tier)
	var offset := int(config.get("specialist_enemy_depth_offset", 0))
	var adjusted_depth := specialist_start_depth + offset
	return current_depth >= adjusted_depth

## Get player starting health bonus for this tier
static func get_player_starting_health_bonus(tier: int) -> float:
	return get_tier_multiplier(tier, "player_starting_health_bonus", 0.0)

## Get player damage reduction for this tier
static func get_player_damage_taken_mult(tier: int) -> float:
	return get_tier_multiplier(tier, "player_damage_taken_mult", 1.0)

## Get Rest Site heal multiplier for this tier
static func get_rest_heal_ratio_mult(tier: int) -> float:
	return get_tier_multiplier(tier, "rest_heal_ratio_mult", 1.0)

## Get normalized difficulty rank for systemic scaling helpers
static func get_difficulty_rank(tier: int) -> int:
	return clampi(int(get_tier_value(tier, "difficulty_rank", BEARING_ENUMS.BearingTier.DELVER)), 0, 3)

## Shared objective pressure curve used by objective encounter runtime logic
static func get_objective_pressure_mult(tier: int) -> float:
	return 0.8 + float(get_difficulty_rank(tier)) * 0.2

## ===== UNIFIED BEARING DEFINITIONS VALIDATION =====
## Verify bearing definitions have all required fields and multiplayer fields are present

static func _validate_bearing_definitions() -> void:
	"""Validate that all bearing definitions have required fields."""
	var required_fields := [
		"name", "description", "bearing_key", "difficulty_rank",
		"encounter_count_before_boss", "base_enemy_pressure_mult", "wave_interval_seconds",
		"depth_pressure_divisor", "specialist_enemy_depth_offset", "specialist_enemy_pressure_mult",
		"boss_difficulty_mult", "mutator_frequency_mult", "trial_encounter_frequency_mult",
		"mutator_damage_mult", "player_starting_health_bonus", "player_damage_taken_mult",
		"enemy_contact_damage_mult", "rest_heal_ratio_mult",
		# Multiplayer-specific fields
		"specialist_enemy_lurker_offset", "specialist_enemy_ram_offset", "specialist_enemy_lancer_offset",
		"specialist_enemy_spectre_offset", "specialist_enemy_pyre_offset", "specialist_enemy_tether_offset",
		"player_health_mult", "player_damage_dealt_mult", "player_heal_mult",
		"coop_enemy_count_per_extra_player", "coop_enemy_count_curve_power", "coop_enemy_count_max_mult",
		"coop_enemy_health_per_extra_player", "coop_enemy_health_curve_power", "coop_enemy_health_max_mult",
		"coop_boss_health_per_extra_player", "coop_boss_health_curve_power", "coop_boss_health_max_mult"
	]
	
	for tier in get_base_progression_ranks().keys():
		assert(BEARING_DEFINITIONS.has(tier), "Bearing tier %d missing from BEARING_DEFINITIONS" % tier)
		var def = BEARING_DEFINITIONS[tier] as Dictionary
		
		for field in required_fields:
			assert(def.has(field), "Bearing tier %d missing required field '%s'" % [tier, field])

## ===== MULTIPLAYER SYNC VALIDATION (LEGACY) =====
## These functions are now simplified since configs are unified.
## Kept for backward compatibility with any external callers.

static func validate_multiplayer_config_sync(multiplayer_config: Node) -> Dictionary:
	"""
	Validate that multiplayer config is in sync with unified bearing definitions.
	Returns { "valid": bool, "errors": [str], "warnings": [str] }
	"""
	var result := {"valid": true, "errors": [], "warnings": []}
	
	if not multiplayer_config:
		result["errors"].append("Multiplayer config is null")
		result["valid"] = false
		return result
	
	# Since configs are now unified, this simply checks that the multiplayer accessor works
	for tier in get_base_progression_ranks().keys():
		var config: Dictionary = multiplayer_config.get_tier_config(tier)
		if config.is_empty():
			result["errors"].append("Tier %d returned empty config from multiplayer accessor" % tier)
			result["valid"] = false
	
	return result
