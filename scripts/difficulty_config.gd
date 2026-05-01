## Centralized difficulty configuration
## Maps tier to scaling multipliers, pacing rules, and encounter generation parameters

extends RefCounted

const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")
const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")

## Difficulty config per tier: pacing, pressure, and affordances
static func get_tier_config(tier: int) -> Dictionary:
	match tier:
		BEARING_ENUMS.BearingTier.PILGRIM:
			return {
				"name": META_PROGRESS.TIER_NAMES[BEARING_ENUMS.BearingTier.PILGRIM],
				"description": META_PROGRESS.TIER_DESCRIPTIONS[BEARING_ENUMS.BearingTier.PILGRIM],
				## Encounter generation
				"encounter_count_before_boss": 8,  ## Rooms to clear before boss
				"base_enemy_pressure_mult": 0.6,  ## Baseline enemy count multiplier
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
				"encounter_count_before_boss": 8,
				"base_enemy_pressure_mult": 1.0,
				"depth_pressure_divisor": 1.0,
				"specialist_enemy_depth_offset": 0,
				"specialist_enemy_pressure_mult": 1.0,
				"boss_difficulty_mult": 1.0,
				## Mutator and encounter complexity
				"mutator_frequency_mult": 1.0,
				"trial_encounter_frequency_mult": 1.0,
				"mutator_damage_mult": 1.0,
				## No player bonuses
				"player_starting_health_bonus": 0.0,
				"player_damage_taken_mult": 1.0,
				"enemy_contact_damage_mult": 0.94,
				"rest_heal_ratio_mult": 1.0,
				"difficulty_rank": 1
			}
		
		BEARING_ENUMS.BearingTier.HARBINGER:
			return {
				"name": META_PROGRESS.TIER_NAMES[BEARING_ENUMS.BearingTier.HARBINGER],
				"description": META_PROGRESS.TIER_DESCRIPTIONS[BEARING_ENUMS.BearingTier.HARBINGER],
				## Encounter generation (harder)
				"encounter_count_before_boss": 8,
				"base_enemy_pressure_mult": 1.25,  ## More enemies per room
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
				"encounter_count_before_boss": 8,
				"base_enemy_pressure_mult": 1.5,  ## Significantly more enemies
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
