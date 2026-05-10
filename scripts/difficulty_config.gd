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

## Difficulty config per tier: pacing, pressure, and affordances
static func get_tier_config(tier: int) -> Dictionary:
	match tier:
		BEARING_ENUMS.BearingTier.PILGRIM:
			return {
				"name": META_PROGRESS.TIER_NAMES[BEARING_ENUMS.BearingTier.PILGRIM],
				"description": META_PROGRESS.TIER_DESCRIPTIONS[BEARING_ENUMS.BearingTier.PILGRIM],
				## Encounter generation
				"encounter_count_before_boss": get_base_encounter_count_before_boss(),
				"base_enemy_pressure_mult": 0.6,  ## Baseline enemy count multiplier
				"wave_interval_seconds": 12.0,  ## Upper bound between waves; kill-threshold can fire earlier
				"depth_pressure_divisor": 1.5,  ## Higher = slower ramping of difficulty; Apprentice ramps slower
				"specialist_enemy_depth_offset": 3,  ## Lurkers start at depth 5 on apprentice (vs depth 5 on standard)
				"specialist_enemy_pressure_mult": 0.75,  ## Specialist enemies ramp slower to avoid burst spikes
				"boss_difficulty_mult": 0.75,  ## Boss health/damage multiplier
				## Mutator and encounter complexity
				"mutator_frequency_mult": 0.5,  ## Fewer mutators per room on lower tiers
				"trial_encounter_frequency_mult": 0.7,  ## Fewer trial encounters
				"mutator_damage_mult": 0.8,  ## Mutators hurt less
				## Player affordances on easiest tier
				"player_starting_health_bonus": 35.0,  ## Extra starting health
				"player_damage_taken_mult": 0.78,  ## 22% damage reduction — enough to survive two slams where one would have killed
				"rest_heal_ratio_mult": 1.25,  ## Rest Sites always heal more on Pilgrim instead of spending hidden charges
				"difficulty_rank": 0
			}
		
		BEARING_ENUMS.BearingTier.DELVER:
			return {
				"name": META_PROGRESS.TIER_NAMES[BEARING_ENUMS.BearingTier.DELVER],
				"description": META_PROGRESS.TIER_DESCRIPTIONS[BEARING_ENUMS.BearingTier.DELVER],
				## Encounter generation (baseline)
				"encounter_count_before_boss": get_base_encounter_count_before_boss(),
				"base_enemy_pressure_mult": 1.0,
				"wave_interval_seconds": 10.0,
				"depth_pressure_divisor": 1.0,
				"specialist_enemy_depth_offset": 0,
				"specialist_enemy_pressure_mult": 1.0,
				"boss_difficulty_mult": 1.0,
				## Mutator and encounter complexity
				"mutator_frequency_mult": 1.0,
				"trial_encounter_frequency_mult": 1.0,
				"mutator_damage_mult": 1.0,
			## Slight damage buffer — keeps run-ending spikes from gating players before they learn patterns
			"player_starting_health_bonus": 0.0,
			"player_damage_taken_mult": 0.92,
				"enemy_contact_damage_mult": 0.94,
				"rest_heal_ratio_mult": 1.0,
				"difficulty_rank": 1
			}
		
		BEARING_ENUMS.BearingTier.HARBINGER:
			return {
				"name": META_PROGRESS.TIER_NAMES[BEARING_ENUMS.BearingTier.HARBINGER],
				"description": META_PROGRESS.TIER_DESCRIPTIONS[BEARING_ENUMS.BearingTier.HARBINGER],
				## Encounter generation (harder)
				"encounter_count_before_boss": get_base_encounter_count_before_boss(),
				"base_enemy_pressure_mult": 1.25,  ## More enemies per room
				"wave_interval_seconds": 9.0,
				"depth_pressure_divisor": 0.8,  ## Faster ramping
				"specialist_enemy_depth_offset": -1,  ## Specialist enemies appear 1 depth earlier
				"specialist_enemy_pressure_mult": 1.05,
				"boss_difficulty_mult": 1.15,  ## Stronger boss
				## Mutator and encounter complexity
				"mutator_frequency_mult": 1.3,  ## More mutators
				"trial_encounter_frequency_mult": 1.2,  ## More trials
				"mutator_damage_mult": 1.1,  ## Mutators are more dangerous
				## Contact-heavy rooms can spike too hard at this tier; keep identity while trimming touch damage.
				"enemy_contact_damage_mult": 0.94,
				## No player bonuses (veteran players don't need them)
				"player_starting_health_bonus": 0.0,
				"player_damage_taken_mult": 1.0,
				"rest_heal_ratio_mult": 1.0,
				"difficulty_rank": 2
			}
		
		BEARING_ENUMS.BearingTier.FORSWORN:
			return {
				"name": META_PROGRESS.TIER_NAMES[BEARING_ENUMS.BearingTier.FORSWORN],
				"description": META_PROGRESS.TIER_DESCRIPTIONS[BEARING_ENUMS.BearingTier.FORSWORN],
				## Encounter generation (extreme)
				"encounter_count_before_boss": get_base_encounter_count_before_boss(),
				"base_enemy_pressure_mult": 1.5,  ## Significantly more enemies
				"wave_interval_seconds": 8.0,
				"depth_pressure_divisor": 0.6,  ## Very fast ramping
				"specialist_enemy_depth_offset": -2,  ## Specialist enemies much earlier
				"specialist_enemy_pressure_mult": 1.15,
				"boss_difficulty_mult": 1.3,  ## Very strong boss
				## Mutator and encounter complexity
				"mutator_frequency_mult": 1.6,  ## Frequent mutators
				"trial_encounter_frequency_mult": 1.4,  ## More trials
				"mutator_damage_mult": 1.25,  ## Heavily damaging mutators
				## Keep Forsworn lethal but avoid contact stack one-shots.
				"enemy_contact_damage_mult": 0.94,
				## No player bonuses
				"player_starting_health_bonus": 0.0,
				"player_damage_taken_mult": 1.0,
				"rest_heal_ratio_mult": 1.0,
				"difficulty_rank": 3
			}
		
		_:
			return get_tier_config(BEARING_ENUMS.BearingTier.DELVER)

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

## ===== MULTIPLAYER SYNC VALIDATION =====
## Verify that multiplayer config has not drifted from singleplayer base definitions

static func validate_multiplayer_config_sync(multiplayer_config: Node) -> Dictionary:
	"""
	Validate that multiplayer config is in sync with singleplayer base definitions.
	Returns { "valid": bool, "errors": [str], "warnings": [str] }
	"""
	var result := {"valid": true, "errors": [], "warnings": []}
	
	if not multiplayer_config:
		result["errors"].append("Multiplayer config is null")
		result["valid"] = false
		return result
	
	# Check encounter count consistency
	var expected_encounter_count := get_base_encounter_count_before_boss()
	for tier in get_base_progression_ranks().keys():
		var mp_config = multiplayer_config.get_tier_config(tier) if multiplayer_config.has_method("get_tier_config") else {}
		var actual_encounter_count = mp_config.get("encounter_count_before_boss", -1)
		
		if actual_encounter_count != expected_encounter_count:
			result["warnings"].append("Tier %d: encounter_count_before_boss mismatch (expected %d, got %d)" % [tier, expected_encounter_count, actual_encounter_count])
	
	# Check progression ranks
	var expected_ranks := get_base_progression_ranks()
	var actual_ranks := {}
	for tier in expected_ranks.keys():
		var mp_config = multiplayer_config.get_tier_config(tier) if multiplayer_config.has_method("get_tier_config") else {}
		actual_ranks[tier] = mp_config.get("difficulty_rank", -1)
	
	for tier in expected_ranks.keys():
		if actual_ranks[tier] != expected_ranks[tier]:
			result["warnings"].append("Tier %d: difficulty_rank mismatch (expected %d, got %d)" % [tier, expected_ranks[tier], actual_ranks[tier]])
	
	return result

