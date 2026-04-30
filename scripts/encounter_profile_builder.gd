extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")

var rng: RandomNumberGenerator
var current_difficulty_tier: int = META_PROGRESS.TIER_DELVER
var current_difficulty_config: Dictionary = DIFFICULTY_CONFIG.get_tier_config(META_PROGRESS.TIER_DELVER)

var room_base_size: Vector2 = Vector2(940.0, 700.0)
var room_size_growth: Vector2 = Vector2(80.0, 45.0)
var static_camera_room_threshold: float = 980.0
var base_chaser_count: int = 5
var chasers_per_room: int = 2
var chargers_start_room: int = 2
var chargers_per_room: int = 1
var archer_start_room: int = 1
var archers_per_room: int = 1
var shielder_start_room: int = 2
var shielders_per_room: int = 1
var hard_room_enemy_bonus: int = 4

const INTRO_ROOM_SIZE := Vector2(940.0, 700.0)
const POOL_ROOM_SIZE := Vector2(1040.0, 760.0)
const TRIAL_ROOM_SIZE := Vector2(1160.0, 860.0)
const MUTATOR_DAMAGE_STAT_KEYS: Array[String] = [
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_DAMAGE_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_PROJECTILE_DAMAGE_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_DAMAGE_MULT
]
const BEARING_DEFINITIONS := {
	"Crossfire": {
		"room_size": POOL_ROOM_SIZE,
		"base_counts": {
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 4,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0,
			"lurker_count": 0,
			"ram_count": 0,
			"lancer_count": 0
		},
		"rank_counts": [
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 3, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 4, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 7, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 9, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 0, "ram_count": 0, "lancer_count": 0}
		]
	},
	"Onslaught": {
		"room_size": POOL_ROOM_SIZE,
		"base_counts": {
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 7,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 2,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0,
			"lurker_count": 0,
			"ram_count": 0,
			"lancer_count": 0
		},
		"rank_counts": [
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 4, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 7, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 8, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 10, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 3, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 0, "ram_count": 0, "lancer_count": 0}
		]
	},
	"Fortress": {
		"room_size": POOL_ROOM_SIZE,
		"base_counts": {
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 1,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 4,
			"lurker_count": 0,
			"ram_count": 0,
			"lancer_count": 0
		},
		"rank_counts": [
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 2, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 5, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 7, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 9, "lurker_count": 0, "ram_count": 0, "lancer_count": 0}
		]
	},
	"Blitz": {
		"room_size": POOL_ROOM_SIZE,
		"base_counts": {
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0,
			"lurker_count": 3,
			"ram_count": 1,
			"lancer_count": 0
		},
		"rank_counts": [
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 2, "ram_count": 1, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 3, "ram_count": 1, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 3, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 3, "ram_count": 1, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 4, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 3, "ram_count": 2, "lancer_count": 0}
		]
	},
	"Suppression": {
		"room_size": POOL_ROOM_SIZE,
		"base_counts": {
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 2,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 1,
			"lurker_count": 0,
			"ram_count": 0,
			"lancer_count": 2
		},
		"rank_counts": [
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 1, "lurker_count": 0, "ram_count": 0, "lancer_count": 2},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 1, "lurker_count": 0, "ram_count": 0, "lancer_count": 3},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 3, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 2, "lurker_count": 0, "ram_count": 0, "lancer_count": 3},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 4, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 2, "lurker_count": 0, "ram_count": 0, "lancer_count": 4}
		]
	},
	"Vanguard": {
		"room_size": POOL_ROOM_SIZE,
		"base_counts": {
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 2,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 2,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 3,
			"lurker_count": 0,
			"ram_count": 0,
			"lancer_count": 0
		},
		"rank_counts": [
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 2, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 3, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 3, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 4, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 4, "lurker_count": 0, "ram_count": 0, "lancer_count": 0},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 3, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 5, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 4, "lurker_count": 0, "ram_count": 0, "lancer_count": 0}
		]
	},
	"Ambush": {
		"room_size": POOL_ROOM_SIZE,
		"base_counts": {
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 2,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0,
			"lurker_count": 4,
			"ram_count": 0,
			"lancer_count": 1
		},
		"rank_counts": [
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 3, "ram_count": 0, "lancer_count": 1},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 4, "ram_count": 0, "lancer_count": 1},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 4, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 4, "ram_count": 0, "lancer_count": 2},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 4, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 0, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 0, "lurker_count": 5, "ram_count": 0, "lancer_count": 3}
		]
	},
	"Gauntlet": {
		"room_size": POOL_ROOM_SIZE,
		"base_counts": {
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 1,
			ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 1,
			"lurker_count": 1,
			"ram_count": 0,
			"lancer_count": 1
		},
		"rank_counts": [
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 1, "lurker_count": 1, "ram_count": 0, "lancer_count": 1},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 1, "lurker_count": 1, "ram_count": 0, "lancer_count": 1},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 3, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 1, "lurker_count": 2, "ram_count": 0, "lancer_count": 1},
			{ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT: 4, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT: 2, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT: 1, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT: 1, "lurker_count": 2, "ram_count": 0, "lancer_count": 1}
		]
	}
}

func initialize(rng_instance: RandomNumberGenerator) -> void:
	rng = rng_instance

func set_difficulty_tier(tier: int) -> void:
	current_difficulty_tier = tier
	_refresh_difficulty_config()

func _refresh_difficulty_config() -> void:
	current_difficulty_config = DIFFICULTY_CONFIG.get_tier_config(current_difficulty_tier)

func _difficulty_float(key: String, fallback: float = 1.0) -> float:
	return float(current_difficulty_config.get(key, fallback))

func _difficulty_int(key: String, fallback: int = 0) -> int:
	return int(current_difficulty_config.get(key, fallback))

func _difficulty_rank() -> int:
	return clampi(_difficulty_int("difficulty_rank", 1), 0, 3)

func _effective_depth(depth: int) -> int:
	var divisor := maxf(0.1, _difficulty_float("depth_pressure_divisor", 1.0))
	return int(floor(float(maxi(0, depth)) / divisor))

func _scale_enemy_count(count: int, minimum: int = 0, pressure_mult_override: float = 1.0) -> int:
	var pressure_mult := _difficulty_float("base_enemy_pressure_mult", 1.0) * pressure_mult_override
	var scaled := int(floor(float(maxi(0, count)) * pressure_mult))
	return maxi(minimum, scaled)

func _count_from_counts(counts: Dictionary, key: String) -> int:
	return int(counts.get(key, 0))

func _build_profile_from_counts(label: String, room_size: Vector2, counts: Dictionary) -> Dictionary:
	return _build_profile(
		label,
		room_size,
		_count_from_counts(counts, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT),
		_count_from_counts(counts, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT),
		_count_from_counts(counts, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT),
		_count_from_counts(counts, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT)
	)

func _set_profile_counts_from_counts_dict(profile: Dictionary, counts: Dictionary) -> void:
	ENCOUNTER_CONTRACTS.profile_set_counts(
		profile,
		_count_from_counts(counts, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT),
		_count_from_counts(counts, ENCOUNTER_CONTRACTS.PROFILE_KEY_CHARGER_COUNT),
		_count_from_counts(counts, ENCOUNTER_CONTRACTS.PROFILE_KEY_ARCHER_COUNT),
		_count_from_counts(counts, ENCOUNTER_CONTRACTS.PROFILE_KEY_SHIELDER_COUNT)
	)
	ENCOUNTER_CONTRACTS.profile_set_specialist_counts(
		profile,
		_count_from_counts(counts, ENCOUNTER_CONTRACTS.PROFILE_KEY_LURKER_COUNT),
		_count_from_counts(counts, ENCOUNTER_CONTRACTS.PROFILE_KEY_RAM_COUNT),
		_count_from_counts(counts, ENCOUNTER_CONTRACTS.PROFILE_KEY_LANCER_COUNT)
	)

func _apply_bearing_count_scaling(profile: Dictionary, pressure_mult_override: float = 1.0, minimum_total: int = 0) -> Dictionary:
	if profile.is_empty():
		return profile
	var modified := profile.duplicate(true)
	var chasers := _scale_enemy_count(ENCOUNTER_CONTRACTS.profile_chaser_count(modified), 0, pressure_mult_override)
	var chargers := _scale_enemy_count(ENCOUNTER_CONTRACTS.profile_charger_count(modified), 0, pressure_mult_override)
	var archers := _scale_enemy_count(ENCOUNTER_CONTRACTS.profile_archer_count(modified), 0, pressure_mult_override)
	var shielders := _scale_enemy_count(ENCOUNTER_CONTRACTS.profile_shielder_count(modified), 0, pressure_mult_override)
	ENCOUNTER_CONTRACTS.profile_set_counts(
		modified,
		chasers,
		chargers,
		archers,
		shielders
	)
	var lurkers := ENCOUNTER_CONTRACTS.profile_lurker_count(modified)
	var rams := ENCOUNTER_CONTRACTS.profile_ram_count(modified)
	var lancers := ENCOUNTER_CONTRACTS.profile_lancer_count(modified)
	ENCOUNTER_CONTRACTS.profile_set_specialist_counts(
		modified,
		_scale_enemy_count(lurkers, 0, pressure_mult_override),
		_scale_enemy_count(rams, 0, pressure_mult_override),
		_scale_enemy_count(lancers, 0, pressure_mult_override)
	)
	if minimum_total > 0:
		var current_total := ENCOUNTER_CONTRACTS.profile_total_enemy_count(modified)
		if current_total < minimum_total:
			var delta := minimum_total - current_total
			modified[ENCOUNTER_CONTRACTS.PROFILE_KEY_CHASER_COUNT] = ENCOUNTER_CONTRACTS.profile_chaser_count(modified) + delta
	return modified

func _skirmish_min_total_enemies() -> int:
	return 3 + _difficulty_rank()

func _apply_profile_counts(profile: Dictionary, counts: Dictionary) -> Dictionary:
	var modified := profile.duplicate(true)
	_set_profile_counts_from_counts_dict(modified, counts)
	return modified

func _build_bearing_profile(label: String) -> Dictionary:
	var definition := BEARING_DEFINITIONS.get(label, {}) as Dictionary
	if definition.is_empty():
		return {}
	var counts := definition.get("base_counts", {}) as Dictionary
	var room_size := definition.get("room_size", POOL_ROOM_SIZE) as Vector2
	var profile := _build_profile_from_counts(label, room_size, counts)
	return _apply_profile_counts(profile, counts)

func _apply_identity_bearing_scaling(profile: Dictionary) -> Dictionary:
	var label := ENCOUNTER_CONTRACTS.profile_label(profile)
	var definition := BEARING_DEFINITIONS.get(label, {}) as Dictionary
	if definition.is_empty():
		return _apply_bearing_count_scaling(profile, 1.0, _skirmish_min_total_enemies())
	var rank_counts := definition.get("rank_counts", []) as Array
	var rank := _difficulty_rank()
	if rank_counts.is_empty() or rank >= rank_counts.size():
		return profile.duplicate(true)
	return _apply_profile_counts(profile, rank_counts[rank] as Dictionary)

func _scale_mutator_damage(mutator: Dictionary) -> Dictionary:
	if mutator.is_empty():
		return {}
	var damage_mult := _difficulty_float("mutator_damage_mult", 1.0)
	if is_equal_approx(damage_mult, 1.0):
		return mutator.duplicate(true)
	var modified := mutator.duplicate(true)
	for stat_key in MUTATOR_DAMAGE_STAT_KEYS:
		if not modified.has(stat_key):
			continue
		var base_value := float(modified.get(stat_key, 1.0))
		modified[stat_key] = 1.0 + (base_value - 1.0) * damage_mult
	return modified

func _trial_option_chance(depth: int) -> float:
	var depth_bonus := float(maxi(0, depth - 3)) * 0.015
	return clampf((0.45 + depth_bonus) * _difficulty_float("trial_encounter_frequency_mult", 1.0), 0.12, 0.95)

func _hard_mutator_chance(depth: int) -> float:
	var depth_bonus := float(maxi(0, depth - 2)) * 0.02
	return clampf((0.18 + depth_bonus) * _difficulty_float("mutator_frequency_mult", 1.0), 0.04, 0.9)

func _profile_has_enemy_archetype(profile: Dictionary, archetype: String) -> bool:
	match archetype:
		"melee":
			return ENCOUNTER_CONTRACTS.profile_chaser_count(profile) > 0 or ENCOUNTER_CONTRACTS.profile_lurker_count(profile) > 0
		"charger":
			return ENCOUNTER_CONTRACTS.profile_charger_count(profile) > 0 or ENCOUNTER_CONTRACTS.profile_ram_count(profile) > 0
		"archer":
			return ENCOUNTER_CONTRACTS.profile_archer_count(profile) > 0 or ENCOUNTER_CONTRACTS.profile_lancer_count(profile) > 0
		"shielder":
			return ENCOUNTER_CONTRACTS.profile_shielder_count(profile) > 0
		_:
			return false

func _mutator_matches_profile(mutator: Dictionary, profile: Dictionary) -> bool:
	var archetypes_variant: Variant = mutator.get("affected_archetypes", [])
	if not (archetypes_variant is Array):
		return true
	var archetypes := archetypes_variant as Array
	if archetypes.is_empty():
		return true
	for archetype_variant in archetypes:
		if _profile_has_enemy_archetype(profile, String(archetype_variant)):
			return true
	return false

func _roll_hard_enemy_mutator_for_profile(profile: Dictionary) -> Dictionary:
	var pool := _hard_mutator_pool()
	var filtered_pool: Array[Dictionary] = []
	for mutator in pool:
		if _mutator_matches_profile(mutator, profile):
			filtered_pool.append(mutator)
	var candidate_pool := filtered_pool if not filtered_pool.is_empty() else pool
	return _scale_mutator_damage(candidate_pool[rng.randi_range(0, candidate_pool.size() - 1)])

func _maybe_apply_hard_mutator(profile: Dictionary, depth: int) -> Dictionary:
	if profile.is_empty():
		return profile
	if rng.randf() > _hard_mutator_chance(depth):
		return profile
	var modified := profile.duplicate(true)
	ENCOUNTER_CONTRACTS.profile_set_enemy_mutator(modified, _roll_hard_enemy_mutator_for_profile(modified))
	return modified

func configure(settings: Dictionary) -> void:
	room_base_size = settings.get("room_base_size", room_base_size)
	room_size_growth = settings.get("room_size_growth", room_size_growth)
	static_camera_room_threshold = float(settings.get("static_camera_room_threshold", static_camera_room_threshold))
	base_chaser_count = int(settings.get("base_chaser_count", base_chaser_count))
	chasers_per_room = int(settings.get("chasers_per_room", chasers_per_room))
	chargers_start_room = int(settings.get("chargers_start_room", chargers_start_room))
	chargers_per_room = int(settings.get("chargers_per_room", chargers_per_room))
	archer_start_room = int(settings.get("archer_start_room", archer_start_room))
	archers_per_room = int(settings.get("archers_per_room", archers_per_room))
	shielder_start_room = int(settings.get("shielder_start_room", shielder_start_room))
	shielders_per_room = int(settings.get("shielders_per_room", shielders_per_room))
	hard_room_enemy_bonus = int(settings.get("hard_room_enemy_bonus", hard_room_enemy_bonus))

func _build_profile(label: String, room_size: Vector2, chasers: int, chargers: int, archers: int, shielders: int, enemy_mutator: Dictionary = {}) -> Dictionary:
	return ENCOUNTER_CONTRACTS.profile(
		label,
		room_size,
		room_size.x <= static_camera_room_threshold,
		chasers,
		chargers,
		archers,
		shielders,
		enemy_mutator
	)

func _build_intro_profile(depth: int) -> Dictionary:
	if depth <= 0:
		return _apply_bearing_count_scaling(_build_profile("Skirmish", INTRO_ROOM_SIZE, 3, 0, 0, 0), 1.0, _skirmish_min_total_enemies())
	var rank := _difficulty_rank()
	var chasers_by_rank := [2, 3, 3, 4]
	return _build_profile("Skirmish", INTRO_ROOM_SIZE, chasers_by_rank[rank], 0, 1, 0)

func _build_intro_variant_profile(depth: int) -> Dictionary:
	var rank := _difficulty_rank()
	if depth <= 0:
		var opening_chasers_by_rank := [2, 2, 3, 3]
		return _build_profile("Pursuit", INTRO_ROOM_SIZE, opening_chasers_by_rank[rank], 1, 0, 0)
	var chasers_by_rank := [1, 2, 2, 2]
	var chargers_by_rank := [1, 1, 1, 1]
	return _build_profile("Pursuit", INTRO_ROOM_SIZE, chasers_by_rank[rank], chargers_by_rank[rank], 0, 0)

func build_skirmish_profile(depth: int) -> Dictionary:
	if depth < 2:
		return _build_intro_profile(depth)
	var hard_pool := _get_hard_pool_for_depth(depth)
	var profile := hard_pool[rng.randi_range(0, hard_pool.size() - 1)]
	profile = _maybe_apply_hard_mutator(profile, depth)
	return _apply_identity_bearing_scaling(profile)

func build_objective_profile(depth: int, preferred: String = "") -> Dictionary:
	var normalized := preferred.strip_edges().to_lower()
	if normalized == "last_stand" or normalized == "last stand" or normalized == "survival":
		return _build_survival_profile(depth)
	if normalized == "priority_target" or normalized == "priority target" or normalized == "cut_the_signal" or normalized == "cut the signal":
		return _build_priority_target_profile(depth)
	if normalized == "hold_the_line" or normalized == "hold the line" or normalized == "control" or normalized == "zone_control":
		return _build_control_profile(depth)
	var objective_profiles: Array[Dictionary] = [_build_survival_profile(depth), _build_priority_target_profile(depth), _build_control_profile(depth)]
	return objective_profiles[rng.randi_range(0, objective_profiles.size() - 1)]

func _canonicalize_debug_encounter_key(encounter_key: String) -> String:
	return ENCOUNTER_CONTRACTS.canonicalize_debug_encounter_key(encounter_key)

func build_debug_encounter_profile(encounter_key: String, depth: int) -> Dictionary:
	var key := _canonicalize_debug_encounter_key(encounter_key)
	match key:
		"skirmish":
			return _build_intro_profile(0)
		"crossfire":
			return _apply_identity_bearing_scaling(_build_bearing_profile("Crossfire"))
		"onslaught":
			return _apply_identity_bearing_scaling(_build_bearing_profile("Onslaught"))
		"fortress":
			return _apply_identity_bearing_scaling(_build_bearing_profile("Fortress"))
		"blitz":
			return _apply_identity_bearing_scaling(_build_bearing_profile("Blitz"))
		"suppression":
			return _apply_identity_bearing_scaling(_build_bearing_profile("Suppression"))
		"vanguard":
			return _apply_identity_bearing_scaling(_build_bearing_profile("Vanguard"))
		"ambush":
			return _apply_identity_bearing_scaling(_build_bearing_profile("Ambush"))
		"gauntlet":
			return _apply_identity_bearing_scaling(_build_bearing_profile("Gauntlet"))
		"trial":
			return _build_trial_profile(depth)
		"objective_last_stand":
			return _build_survival_profile(depth)
		"objective_priority_target":
			return _build_priority_target_profile(depth)
		"objective_hold_the_line":
			return _build_control_profile(depth)
		"objective_random":
			return build_objective_profile(depth)
		_:
			return {}

func build_debug_mutator(mutator_key: String) -> Dictionary:
	var key := mutator_key.strip_edges().to_lower()
	if key.is_empty() or key == "none":
		return {}
	if key == "killbox":
		return _build_killbox_mutator()
	if key == "random_hard":
		return roll_hard_enemy_mutator()
	var hard_pool := _hard_mutator_pool()
	for mutator in hard_pool:
		var icon_id := String(mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID, "")).to_lower()
		var normalized_name := String(mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME, "")).to_lower().replace(" ", "_")
		if key == icon_id or key == normalized_name:
			return mutator.duplicate(true)
	return {}

func _get_hard_pool() -> Array[Dictionary]:
	# Crossfire: archers pin you, charger punishes standing still.
	# Onslaught: pure melee flood — no respite from ranged.
	# Fortress: true defensive wall — shielders advance with no charger to bypass.
	# Blitz: all fast melee — lurkers ambush, ram charges, no ranged cover.
	# Suppression: lancer hazard zones force constant movement, archers +
	#              shielder deny safe angles.
	# Vanguard: shielded advance with chargers punching through the line.
	# Ambush: lancer cuts escape routes while lurkers converge.
	# Gauntlet: one of everything — a comprehensive skill test.
	var crossfire := _build_bearing_profile("Crossfire")
	var onslaught := _build_bearing_profile("Onslaught")
	var fortress := _build_bearing_profile("Fortress")
	var blitz := _build_bearing_profile("Blitz")
	var suppression := _build_bearing_profile("Suppression")
	var vanguard := _build_bearing_profile("Vanguard")
	var ambush := _build_bearing_profile("Ambush")
	var gauntlet := _build_bearing_profile("Gauntlet")
	return [crossfire, onslaught, fortress, blitz, suppression, vanguard, ambush, gauntlet]

func _get_hard_pool_for_depth(depth: int) -> Array[Dictionary]:
	var pool := _get_hard_pool()
	var filtered: Array[Dictionary] = []
	var effective_depth := _effective_depth(depth)
	var ambush_depth_gate := 4 if _difficulty_rank() == 0 else 3
	for profile in pool:
		var label := ENCOUNTER_CONTRACTS.profile_label(profile)
		if label == "Ambush" and effective_depth < ambush_depth_gate:
			continue
		filtered.append(profile)
	if filtered.is_empty():
		return pool
	return filtered

func _build_trial_profile(depth: int = 0) -> Dictionary:
	var mutator: Dictionary = roll_hard_enemy_mutator()
	var base: Dictionary = _pick_trial_base_profile(mutator)
	var effective_depth := _effective_depth(depth)
	var depth_pressure := maxi(0, effective_depth - 2)
	var base_pressure_mult := _difficulty_float("base_enemy_pressure_mult", 1.0)
	
	var chasers := int(float(ENCOUNTER_CONTRACTS.profile_chaser_count(base) + hard_room_enemy_bonus + int(floor(float(depth_pressure) * 0.75))) * base_pressure_mult)
	var chargers := int(float(ENCOUNTER_CONTRACTS.profile_charger_count(base) + 2 + int(floor(float(depth_pressure) / 4.0))) * base_pressure_mult)
	var archers := int(float(maxi(ENCOUNTER_CONTRACTS.profile_archer_count(base), 1) + int(floor(float(depth_pressure) / 5.0))) * base_pressure_mult)
	var shielders := int(float(ENCOUNTER_CONTRACTS.profile_shielder_count(base) + int(floor(float(depth_pressure) / 4.0))) * base_pressure_mult)
	var specialist_counts := _trial_specialist_counts(mutator, depth, chasers, chargers, archers, shielders)
	chasers = int(specialist_counts.get("chasers", chasers))
	chargers = int(specialist_counts.get("chargers", chargers))
	archers = int(specialist_counts.get("archers", archers))
	shielders = int(specialist_counts.get("shielders", shielders))
	var mutator_name := ENCOUNTER_CONTRACTS.mutator_name(mutator)
	if mutator_name.is_empty():
		mutator_name = "Frenzy"
	var profile := _build_profile("Trial %s" % mutator_name, TRIAL_ROOM_SIZE, chasers, chargers, archers, shielders, mutator)
	var specialist_enemies := _trial_specialist_enemies(mutator, depth, current_difficulty_tier)
	ENCOUNTER_CONTRACTS.profile_set_specialist_counts(
		profile,
		int(specialist_enemies.get(ENCOUNTER_CONTRACTS.PROFILE_KEY_LURKER_COUNT, 0)),
		int(specialist_enemies.get(ENCOUNTER_CONTRACTS.PROFILE_KEY_RAM_COUNT, 0)),
		int(specialist_enemies.get(ENCOUNTER_CONTRACTS.PROFILE_KEY_LANCER_COUNT, 0))
	)
	return profile

func apply_mutator_variant_to_profile(profile: Dictionary, mutator: Dictionary, depth: int = 1) -> Dictionary:
	if profile.is_empty() or mutator.is_empty():
		return profile
	var modified := profile.duplicate(true)
	ENCOUNTER_CONTRACTS.profile_set_enemy_mutator(modified, mutator)
	var chasers := ENCOUNTER_CONTRACTS.profile_chaser_count(modified)
	var chargers := ENCOUNTER_CONTRACTS.profile_charger_count(modified)
	var archers := ENCOUNTER_CONTRACTS.profile_archer_count(modified)
	var shielders := ENCOUNTER_CONTRACTS.profile_shielder_count(modified)
	var specialist_counts := _trial_specialist_counts(mutator, depth, chasers, chargers, archers, shielders)
	ENCOUNTER_CONTRACTS.profile_set_counts(
		modified,
		int(specialist_counts.get("chasers", chasers)),
		int(specialist_counts.get("chargers", chargers)),
		int(specialist_counts.get("archers", archers)),
		int(specialist_counts.get("shielders", shielders))
	)
	var specialist_enemies := _trial_specialist_enemies(mutator, depth)
	ENCOUNTER_CONTRACTS.profile_set_specialist_counts(
		modified,
		int(specialist_enemies.get(ENCOUNTER_CONTRACTS.PROFILE_KEY_LURKER_COUNT, 0)),
		int(specialist_enemies.get(ENCOUNTER_CONTRACTS.PROFILE_KEY_RAM_COUNT, 0)),
		int(specialist_enemies.get(ENCOUNTER_CONTRACTS.PROFILE_KEY_LANCER_COUNT, 0))
	)
	var label := ENCOUNTER_CONTRACTS.profile_label(modified)
	var mutator_name := ENCOUNTER_CONTRACTS.mutator_name(mutator)
	if not mutator_name.is_empty() and label.begins_with("Trial"):
		modified[ENCOUNTER_CONTRACTS.PROFILE_KEY_LABEL] = "Trial %s" % mutator_name
	return modified

func _pick_trial_base_profile(mutator: Dictionary) -> Dictionary:
	var hard_pool := _get_hard_pool()
	var icon := ENCOUNTER_CONTRACTS.mutator_icon_shape_id(mutator)
	if icon.is_empty():
		return hard_pool[rng.randi_range(0, hard_pool.size() - 1)]
	match icon:
		"iron_volley":
			return _build_profile("Fortress", POOL_ROOM_SIZE, 2, 0, 3, 3)
		"blood_rush":
			return _build_profile("Onslaught", POOL_ROOM_SIZE, 7, 3, 0, 0)
		"flashpoint":
			return _build_profile("Crossfire", POOL_ROOM_SIZE, 2, 2, 4, 0)
		"siegebreak":
			if current_difficulty_tier == META_PROGRESS.TIER_PILGRIM:
				return _build_profile("Vanguard", POOL_ROOM_SIZE, 3, 2, 0, 2)
			return _build_profile("Vanguard", POOL_ROOM_SIZE, 3, 3, 0, 3)
		_:
			return hard_pool[rng.randi_range(0, hard_pool.size() - 1)]

func _trial_specialist_counts(mutator: Dictionary, depth: int, chasers: int, chargers: int, archers: int, shielders: int) -> Dictionary:
	var icon := ENCOUNTER_CONTRACTS.mutator_icon_shape_id(mutator)
	match icon:
		"iron_volley":
			return {
				"chasers": maxi(3, chasers),
				"chargers": mini(chargers, 1),
				"archers": maxi(6, archers + 2 + int(floor(float(depth) * 0.25))),
				"shielders": maxi(4, shielders + 1 + int(floor(float(depth) * 0.15)))
			}
		"blood_rush":
			return {
				"chasers": maxi(chasers + 2, 7 + int(floor(float(depth) * 0.3))),
				"chargers": maxi(chargers + 2, 4 + int(floor(float(depth) * 0.2))),
				"archers": mini(archers, 1),
				"shielders": mini(shielders, 1)
			}
		"flashpoint":
			return {
				"chasers": maxi(3, chasers - 1),
				"chargers": maxi(chargers + 1, 3 + int(floor(float(depth) * 0.2))),
				"archers": maxi(4, archers + 1 + int(floor(float(depth) * 0.2))),
				"shielders": maxi(1, shielders)
			}
		"siegebreak":
			if current_difficulty_tier == META_PROGRESS.TIER_PILGRIM:
				return {
					"chasers": maxi(3, chasers),
					"chargers": maxi(chargers, 3 + int(floor(float(depth) * 0.15))),
					"archers": mini(archers, 1),
					"shielders": maxi(shielders, 3 + int(floor(float(depth) * 0.1)))
				}
			return {
				"chasers": maxi(3, chasers),
				"chargers": maxi(chargers + 1, 4 + int(floor(float(depth) * 0.2))),
				"archers": mini(archers, 1),
				"shielders": maxi(shielders + 1, 4 + int(floor(float(depth) * 0.15)))
			}
		_:
			return {
				"chasers": chasers,
				"chargers": chargers,
				"archers": archers,
				"shielders": shielders
			}

func _trial_specialist_enemies(mutator: Dictionary, depth: int, tier: int = META_PROGRESS.TIER_DELVER) -> Dictionary:
	var icon := ENCOUNTER_CONTRACTS.mutator_icon_shape_id(mutator)
	var difficulty_config := DIFFICULTY_CONFIG.get_tier_config(tier)
	var specialist_offset := int(difficulty_config.get("specialist_enemy_depth_offset", 0))
	var depth_pressure_divisor := maxf(0.1, float(difficulty_config.get("depth_pressure_divisor", 1.0)))
	var effective_depth := int(floor(float(maxi(0, depth)) / depth_pressure_divisor))
	var specialist_pressure_mult := float(difficulty_config.get("specialist_enemy_pressure_mult", 1.0))
	
	## Adjust depth gates for specialist enemies based on tier
	var lurker_gate := 5 + specialist_offset
	var ram_gate := 6 + specialist_offset
	var lancer_gate := 7 + specialist_offset
	
	var lurker_count := int(floor(float(maxi(0, effective_depth - lurker_gate + 1)) * 0.6)) if effective_depth >= lurker_gate else 0
	var ram_count := int(floor(float(maxi(0, effective_depth - ram_gate + 1)) * 0.4)) if effective_depth >= ram_gate else 0
	var lancer_count := 1 if effective_depth >= lancer_gate else 0
	match icon:
		"iron_volley":
			lurker_count = 0
			ram_count = 0
			lancer_count = 0
		"blood_rush":
			lurker_count += 1 if effective_depth >= lurker_gate + 1 else 0
			ram_count += 1 if depth >= ram_gate else 0
		"flashpoint":
			lancer_count += 1 if depth >= lancer_gate else 0
		"siegebreak":
			if tier != META_PROGRESS.TIER_PILGRIM:
				ram_count += 1 if effective_depth >= ram_gate else 0
	lurker_count = int(floor(float(maxi(0, lurker_count)) * specialist_pressure_mult))
	ram_count = int(floor(float(maxi(0, ram_count)) * specialist_pressure_mult))
	lancer_count = int(floor(float(maxi(0, lancer_count)) * specialist_pressure_mult))
	if icon == "blood_rush":
		var blood_rush_lurker_cap := 3 + int(floor(float(maxi(0, effective_depth - lurker_gate)) / 5.0))
		lurker_count = mini(lurker_count, blood_rush_lurker_cap)
	return {
		ENCOUNTER_CONTRACTS.PROFILE_KEY_LURKER_COUNT: maxi(0, lurker_count),
		ENCOUNTER_CONTRACTS.PROFILE_KEY_RAM_COUNT: maxi(0, ram_count),
		ENCOUNTER_CONTRACTS.PROFILE_KEY_LANCER_COUNT: maxi(0, lancer_count)
	}

func _build_survival_profile(depth: int) -> Dictionary:
	var hard_pool := _get_hard_pool()
	var base: Dictionary = hard_pool[rng.randi_range(0, hard_pool.size() - 1)]
	var effective_depth := _effective_depth(depth)
	var survival_room_size := Vector2(980.0, 740.0)
	var chasers := maxi(5, ENCOUNTER_CONTRACTS.profile_chaser_count(base) + 2)
	var chargers := maxi(1, ENCOUNTER_CONTRACTS.profile_charger_count(base) + 1)
	var archers := maxi(1, ENCOUNTER_CONTRACTS.profile_archer_count(base) + 1)
	var shielders: int
	if current_difficulty_tier == META_PROGRESS.TIER_PILGRIM and effective_depth < 4:
		shielders = 0
	else:
		shielders = maxi(1, ENCOUNTER_CONTRACTS.profile_shielder_count(base))
	var pressure_mutator := _build_killbox_mutator()
	var profile := _build_profile("Last Stand", survival_room_size, chasers, chargers, archers, shielders, pressure_mutator)
	var fortified_mutator := _build_fortified_mutator()
	ENCOUNTER_CONTRACTS.profile_set_player_mutator(profile, fortified_mutator)
	var raw_duration := clampf(22.0 + float(effective_depth) * 0.85, 22.0, 34.0)
	var duration := int(ceil(raw_duration / 5.0)) * 5
	var spawn_interval := clampf(1.82 - float(effective_depth) * 0.06, 0.8, 1.82)
	var spawn_batch := mini(5, 2 + int(floor(float(effective_depth) / 3.0)))
	ENCOUNTER_CONTRACTS.profile_set_survival_objective(profile, duration, spawn_interval, spawn_batch)
	return _apply_bearing_count_scaling(profile)

func _build_priority_target_profile(depth: int) -> Dictionary:
	var effective_depth := _effective_depth(depth)
	var room_size := Vector2(1040.0, 760.0)
	var chasers := 4 + int(floor(float(effective_depth) * 0.55))
	var chargers := 1 + int(floor(float(effective_depth) / 5.0)) if effective_depth >= 2 else 0
	var archers := 1
	var shielders := 1 + int(floor(float(effective_depth) / 3.0))
	var profile := _build_profile("Cut the Signal", room_size, chasers, chargers, archers, shielders)
	var hunters_focus_mutator := _build_hunters_focus_mutator()
	ENCOUNTER_CONTRACTS.profile_set_player_mutator(profile, hunters_focus_mutator)
	var raw_duration := clampf(20.0 + float(effective_depth) * 0.8, 20.0, 30.0)
	var duration := int(ceil(raw_duration / 5.0)) * 5
	var spawn_interval := clampf(2.18 - float(effective_depth) * 0.06, 1.05, 2.18)
	var spawn_batch := mini(4, 2 + int(floor(float(effective_depth) / 4.0)))
	ENCOUNTER_CONTRACTS.profile_set_priority_target_objective(profile, "archer", duration, spawn_interval, spawn_batch)
	return _apply_bearing_count_scaling(profile)

func _build_control_profile(depth: int) -> Dictionary:
	var effective_depth := _effective_depth(depth)
	var difficulty_rank := _difficulty_rank()
	var control_pressure_mult := 0.85
	var contest_threshold := 3
	var tier_spawn_interval_bias := 0.0
	var tier_radius_bias := 0.0
	var tier_goal_bias := 0.0
	var tier_decay_bias := 0.0
	match difficulty_rank:
		0:
			control_pressure_mult = 0.98
			contest_threshold = 2
			tier_spawn_interval_bias = -0.2
			tier_radius_bias = -12.0
			tier_goal_bias = 1.1
			tier_decay_bias = 0.08
		1:
			control_pressure_mult = 0.93
			contest_threshold = 2
			tier_spawn_interval_bias = -0.12
			tier_radius_bias = -8.0
			tier_goal_bias = 0.7
			tier_decay_bias = 0.05
		3:
			control_pressure_mult = 0.86
	var room_size := Vector2(1000.0, 760.0)
	var chasers := 2 + int(floor(float(effective_depth) * 0.34))
	var chargers := 1 + int(floor(float(effective_depth) / 6.0)) if effective_depth >= 2 else 0
	var archers := 1 if effective_depth >= 5 else 0
	var shielders := 1 + int(floor(float(effective_depth) / 5.0))
	var profile := _build_profile("Hold the Line", room_size, chasers, chargers, archers, shielders)
	ENCOUNTER_CONTRACTS.profile_set_player_mutator(profile, _build_breach_momentum_mutator())
	var raw_duration := clampf(22.0 + float(effective_depth) * 0.75, 22.0, 30.0)
	var duration := int(ceil(raw_duration / 5.0)) * 5
	var spawn_interval := clampf(2.52 - float(effective_depth) * 0.04 + tier_spawn_interval_bias, 1.5, 2.52)
	var spawn_batch := mini(3, 1 + int(floor(float(effective_depth) / 5.0)))
	var zone_radius := clampf(184.0 + float(effective_depth) * 3.2 + tier_radius_bias, 172.0, 228.0)
	var progress_goal := clampf(8.4 + float(effective_depth) * 0.28 + tier_goal_bias, 8.4, 12.8)
	var progress_decay := clampf(0.24 + float(effective_depth) * 0.014 + tier_decay_bias, 0.24, 0.5)
	ENCOUNTER_CONTRACTS.profile_set_control_objective(profile, duration, spawn_interval, spawn_batch, zone_radius, progress_goal, progress_decay, contest_threshold)
	return _apply_bearing_count_scaling(profile, control_pressure_mult)

func _normalize_route_context(route_context: Variant) -> Dictionary:
	if route_context is Dictionary:
		var context_dict := route_context as Dictionary
		return {
			"depth": maxi(0, int(context_dict.get("depth", 0))),
			"rooms_until_boss": maxi(-1, int(context_dict.get("rooms_until_boss", -1)))
		}
	return {
		"depth": maxi(0, int(route_context)),
		"rooms_until_boss": -1
	}

func _build_intro_route_option(profile: Dictionary) -> Dictionary:
	return ENCOUNTER_CONTRACTS.door_option(
		ENCOUNTER_CONTRACTS.profile_label(profile),
		Color(0.34, 0.8, 1.0, 0.95),
		ENUMS.DoorKind.ENCOUNTER,
		"easy",
		ENUMS.RewardMode.BOON,
		profile
	)

func _build_hard_route_option(depth: int) -> Dictionary:
	var hard_pool: Array[Dictionary] = _get_hard_pool_for_depth(depth)
	var hard_profile: Dictionary = hard_pool[rng.randi_range(0, hard_pool.size() - 1)]
	hard_profile = _maybe_apply_hard_mutator(hard_profile, depth)
	hard_profile = _apply_identity_bearing_scaling(hard_profile)
	return ENCOUNTER_CONTRACTS.door_option(
		ENCOUNTER_CONTRACTS.profile_label(hard_profile),
		Color(0.93, 0.62, 0.28, 0.95),
		ENUMS.DoorKind.ENCOUNTER,
		"hard",
		ENUMS.RewardMode.BOON,
		hard_profile
	)

func _build_trial_route_option(depth: int) -> Dictionary:
	if depth < 3 or rng.randf() > _trial_option_chance(depth):
		return {}
	var trial_profile: Dictionary = _build_trial_profile(depth)
	var trial_mutator: Dictionary = ENCOUNTER_CONTRACTS.profile_enemy_mutator(trial_profile)
	var trial_mutator_name := ENCOUNTER_CONTRACTS.mutator_name(trial_mutator)
	if trial_mutator_name.is_empty():
		trial_mutator_name = "Trial"
	var trial_color: Color = ENCOUNTER_CONTRACTS.mutator_theme_color(trial_mutator, Color(1.0, 0.32, 0.22, 0.96))
	trial_color.a = 0.96
	return ENCOUNTER_CONTRACTS.door_option(
		"Trial - %s" % trial_mutator_name,
		trial_color,
		ENUMS.DoorKind.ENCOUNTER,
		"trial",
		ENUMS.RewardMode.ARCANA,
		trial_profile
	)

func _build_objective_route_option(depth: int) -> Dictionary:
	var objective_profile := build_objective_profile(depth)
	return ENCOUNTER_CONTRACTS.door_option(
		"Objective - %s" % ENCOUNTER_CONTRACTS.profile_label(objective_profile),
		Color(0.98, 0.78, 0.34, 0.96),
		ENUMS.DoorKind.ENCOUNTER,
		"objective",
		ENUMS.RewardMode.MISSION,
		objective_profile
	)

func _build_rest_route_option() -> Dictionary:
	return ENCOUNTER_CONTRACTS.door_option(
		"Rest Site",
		Color(0.66, 1.0, 0.76, 0.92),
		ENUMS.DoorKind.REST,
		"rest",
		ENUMS.RewardMode.NONE,
		{}
	)

func _shuffle_route_options(options: Array[Dictionary]) -> Array[Dictionary]:
	if options.size() < 2 or rng.randf() < 0.5:
		return options
	return [options[1], options[0]]

func _pick_two_route_options(options: Array[Dictionary]) -> Array[Dictionary]:
	if options.size() <= 2:
		return _shuffle_route_options(options)
	var first: int = rng.randi_range(0, options.size() - 1)
	var chosen: Array[Dictionary] = [options[first]]
	var remaining_indices: Array[int] = []
	for index in range(options.size()):
		if index == first:
			continue
		remaining_indices.append(index)
	var second_index: int = remaining_indices[rng.randi_range(0, remaining_indices.size() - 1)]
	chosen.append(options[second_index])
	return _shuffle_route_options(chosen)

func _build_intro_route_options(depth: int) -> Array[Dictionary]:
	return _shuffle_route_options([
		_build_intro_route_option(_build_intro_profile(depth)),
		_build_intro_route_option(_build_intro_variant_profile(depth))
	])

func _build_non_rest_route_options(depth: int) -> Array[Dictionary]:
	var options: Array[Dictionary] = [_build_hard_route_option(depth), _build_objective_route_option(depth)]
	var trial_option := _build_trial_route_option(depth)
	if not trial_option.is_empty():
		options.append(trial_option)
	return options

func roll_route_options(route_context: Variant) -> Array[Dictionary]:
	var context := _normalize_route_context(route_context)
	var depth := int(context.get("depth", 0))
	var rooms_until_boss := int(context.get("rooms_until_boss", -1))
	if depth < 2:
		return _build_intro_route_options(depth)
	if rooms_until_boss == 1:
		var pre_boss_options := _build_non_rest_route_options(depth)
		var alternate := pre_boss_options[rng.randi_range(0, pre_boss_options.size() - 1)]
		return _shuffle_route_options([alternate, _build_rest_route_option()])
	var options := _build_non_rest_route_options(depth)
	options.append(_build_rest_route_option())
	return _pick_two_route_options(options)

func roll_hard_enemy_mutator() -> Dictionary:
	var pool := _hard_mutator_pool()
	return _scale_mutator_damage(pool[rng.randi_range(0, pool.size() - 1)])

func _build_killbox_mutator() -> Dictionary:
	return _scale_mutator_damage({
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME: "Killbox",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_THEME_COLOR: Color(0.98, 0.72, 0.2, 1.0),
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID: "killbox",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_BANNER_SUFFIX: "The arena closes in and pressure rises",
		ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_SPEED_MULT: 1.18,
		ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_SPEED_MULT: 1.22,
		ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_WINDUP_MULT: 0.85,
		ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_WINDUP_MULT: 0.8,
		ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_COOLDOWN_MULT: 0.78,
		ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SPEED_MULT: 1.16,
		ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_WINDUP_MULT: 0.88
	})

func _build_fortified_mutator() -> Dictionary:
	return {
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME: "Fortified",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_THEME_COLOR: Color(0.76, 0.82, 0.98, 1.0),
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID: "fortified",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_BANNER_SUFFIX: "Incoming damage reduced by 15%",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_PLAYER_DAMAGE_RESIST: 0.15,
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_DURATION_ENCOUNTERS: 3
	}

func _build_hunters_focus_mutator() -> Dictionary:
	return {
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME: "Hunter's Focus",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_THEME_COLOR: Color(0.98, 0.76, 0.34, 1.0),
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID: "hunters_focus",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_BANNER_SUFFIX: "Deal 25% bonus damage",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_PLAYER_DAMAGE_MULT: 0.25,
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_DURATION_ENCOUNTERS: 3
	}

func _build_breach_momentum_mutator() -> Dictionary:
	return {
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME: "Breach Momentum",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_THEME_COLOR: Color(0.94, 0.68, 0.28, 1.0),
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID: "breach_momentum",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_BANNER_SUFFIX: "Deal 18% bonus damage and take 8% less damage",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_PLAYER_DAMAGE_MULT: 0.18,
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_PLAYER_DAMAGE_RESIST: 0.08,
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_DURATION_ENCOUNTERS: 3
	}

func _hard_mutator_pool() -> Array[Dictionary]:
	var C := ENCOUNTER_CONTRACTS
	return [
		{
			C.MUTATOR_KEY_NAME: "Blood Rush",
			# Melee attackers hit harder and faster — chasers + chargers
			C.MUTATOR_KEY_THEME_COLOR: Color(0.95, 0.22, 0.28, 1.0),
			C.MUTATOR_KEY_ICON_SHAPE_ID: "blood_rush",
			"affected_archetypes": ["melee", "charger"],
			C.MUTATOR_KEY_BANNER_SUFFIX: "Melee enemies strike harder and faster",
			C.MUTATOR_KEY_ENEMY_TINT: Color(1.0, 0.80, 0.80, 1.0),
			C.MUTATOR_STAT_CHASER_DAMAGE_MULT: 1.35,
			C.MUTATOR_STAT_CHASER_ATTACK_INTERVAL_MULT: 0.75,
			C.MUTATOR_STAT_CHASER_SPEED_MULT: 1.1,
			C.MUTATOR_STAT_CHARGER_DAMAGE_MULT: 1.45,
			C.MUTATOR_STAT_CHARGER_SPEED_MULT: 1.0,
			C.MUTATOR_STAT_CHARGER_WINDUP_MULT: 1.0
		},
		{
			C.MUTATOR_KEY_NAME: "Flashpoint",
			# Ranged and charging attacks arrive with almost no warning — chargers + archers
			C.MUTATOR_KEY_THEME_COLOR: Color(0.68, 0.40, 1.0, 1.0),
			C.MUTATOR_KEY_ICON_SHAPE_ID: "flashpoint",
			"affected_archetypes": ["charger", "archer"],
			C.MUTATOR_KEY_BANNER_SUFFIX: "Charges and volleys strike with almost no warning",
			C.MUTATOR_KEY_ENEMY_TINT: Color(0.88, 0.82, 1.0, 1.0),
			C.MUTATOR_STAT_CHARGER_DAMAGE_MULT: 1.12,
			C.MUTATOR_STAT_CHARGER_SPEED_MULT: 1.32,
			C.MUTATOR_STAT_CHARGER_WINDUP_MULT: 0.55,
			C.MUTATOR_STAT_ARCHER_WINDUP_MULT: 0.55,
			C.MUTATOR_STAT_ARCHER_COOLDOWN_MULT: 0.72,
			C.MUTATOR_STAT_ARCHER_PROJECTILE_DAMAGE_MULT: 1.25
		},
		{
			C.MUTATOR_KEY_NAME: "Siegebreak",
			# Heavy-impact enemies deal devastating force — chargers + shielders
			C.MUTATOR_KEY_THEME_COLOR: Color(0.96, 0.58, 0.18, 1.0),
			C.MUTATOR_KEY_ICON_SHAPE_ID: "siegebreak",
			"affected_archetypes": ["charger", "shielder"],
			C.MUTATOR_KEY_BANNER_SUFFIX: "Chargers and shielders hit with overwhelming force",
			C.MUTATOR_KEY_ENEMY_TINT: Color(1.0, 0.88, 0.72, 1.0),
			C.MUTATOR_STAT_CHARGER_DAMAGE_MULT: 1.5,
			C.MUTATOR_STAT_CHARGER_SPEED_MULT: 1.15,
			C.MUTATOR_STAT_CHARGER_WINDUP_MULT: 0.82,
			C.MUTATOR_STAT_SHIELDER_SLAM_DAMAGE_MULT: 1.55,
			C.MUTATOR_STAT_SHIELDER_SLAM_WINDUP_MULT: 0.78,
			C.MUTATOR_STAT_SHIELDER_SPEED_MULT: 1.18
		},
		{
			C.MUTATOR_KEY_NAME: "Iron Volley",
			# No chargers — archers pin you while shielders advance
			C.MUTATOR_KEY_THEME_COLOR: Color(0.32, 0.82, 0.56, 1.0),
			C.MUTATOR_KEY_ICON_SHAPE_ID: "iron_volley",
			"affected_archetypes": ["archer", "shielder"],
			C.MUTATOR_KEY_BANNER_SUFFIX: "Archers and shielders hold the line",
			C.MUTATOR_KEY_ENEMY_TINT: Color(0.80, 1.0, 0.86, 1.0),
			C.MUTATOR_STAT_ARCHER_WINDUP_MULT: 0.68,
			C.MUTATOR_STAT_ARCHER_COOLDOWN_MULT: 0.62,
			C.MUTATOR_STAT_ARCHER_PROJECTILE_DAMAGE_MULT: 1.35,
			C.MUTATOR_STAT_SHIELDER_SLAM_DAMAGE_MULT: 1.3,
			C.MUTATOR_STAT_SHIELDER_SLAM_WINDUP_MULT: 0.85,
			C.MUTATOR_STAT_SHIELDER_SPEED_MULT: 1.28
		}
	]
