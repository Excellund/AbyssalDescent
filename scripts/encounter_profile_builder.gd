extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")
const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")

var rng: RandomNumberGenerator
var current_difficulty_tier: int = BEARING_ENUMS.BearingTier.DELVER
var current_difficulty_config: Dictionary = DIFFICULTY_CONFIG.get_tier_config(BEARING_ENUMS.BearingTier.DELVER)

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
const BEARING_LABELS: Array[String] = [
	"Crossfire",
	"Onslaught",
	"Fortress",
	"Blitz",
	"Suppression",
	"Vanguard",
	"Ambush",
	"Gauntlet"
]
const MUTATOR_DAMAGE_STAT_KEYS: Array[String] = [
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_DAMAGE_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_PROJECTILE_DAMAGE_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_DAMAGE_MULT
]
const CONTROL_TUNING_BY_RANK := {
	0: {
		"pressure_mult": 0.95,
		"spawn_interval_bias": 0.2,
		"radius_bias": 12.0,
		"goal_bias": 1.05,
		"decay_bias": 0.05
	},
	1: {
		"pressure_mult": 0.84,
		"spawn_interval_bias": 0.18,
		"radius_bias": 12.0,
		"goal_bias": 0.45,
		"decay_bias": -0.005
	},
	2: {
		"pressure_mult": 0.74,
		"spawn_interval_bias": 0.14,
		"radius_bias": 12.0,
		"goal_bias": -0.3,
		"decay_bias": -0.05
	},
	3: {
		"pressure_mult": 0.78,
		"spawn_interval_bias": 0.08,
		"radius_bias": 9.0,
		"goal_bias": 0.05,
		"decay_bias": -0.01
	}
}
const CONTROL_DEPTH_WINDOWS_BY_RANK := {
	2: [
		{
			"start_depth": 1,
			"end_depth": 3,
			"pressure_bias": 0.02,
			"spawn_interval_bias": -0.05,
			"goal_bias": 0.14,
			"decay_bias": 0.015
		},
		{
			"start_depth": 6,
			"end_depth": 8,
			"pressure_bias": -0.04,
			"spawn_interval_bias": 0.08,
			"goal_bias": -0.2,
			"decay_bias": -0.02
		}
	]
}

var _bearing_definitions_cache: Dictionary = {}

func _bearing_definition(room_size: Vector2, base_counts: Dictionary, rank_counts: Array[Dictionary]) -> Dictionary:
	return {
		"room_size": room_size,
		"base_counts": base_counts,
		"rank_counts": rank_counts
	}

func _get_bearing_definitions() -> Dictionary:
	if not _bearing_definitions_cache.is_empty():
		return _bearing_definitions_cache
	_bearing_definitions_cache = {
		"Crossfire": _bearing_definition(POOL_ROOM_SIZE, ENCOUNTER_CONTRACTS.profile_counts(1, 1, 4, 0), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 1, 3, 0),
			ENCOUNTER_CONTRACTS.profile_counts(1, 1, 4, 0),
			ENCOUNTER_CONTRACTS.profile_counts(1, 2, 7, 0),
			ENCOUNTER_CONTRACTS.profile_counts(1, 2, 9, 0)
		]),
		"Onslaught": _bearing_definition(POOL_ROOM_SIZE, ENCOUNTER_CONTRACTS.profile_counts(7, 2, 0, 0), [
			ENCOUNTER_CONTRACTS.profile_counts(4, 1, 0, 0),
			ENCOUNTER_CONTRACTS.profile_counts(7, 2, 0, 0),
			ENCOUNTER_CONTRACTS.profile_counts(8, 2, 0, 0),
			ENCOUNTER_CONTRACTS.profile_counts(10, 3, 0, 0)
		]),
		"Fortress": _bearing_definition(POOL_ROOM_SIZE, ENCOUNTER_CONTRACTS.profile_counts(1, 0, 1, 4), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 0, 1, 2),
			ENCOUNTER_CONTRACTS.profile_counts(1, 0, 1, 5),
			ENCOUNTER_CONTRACTS.profile_counts(2, 0, 1, 7),
			ENCOUNTER_CONTRACTS.profile_counts(2, 0, 2, 9)
		]),
		"Blitz": _bearing_definition(POOL_ROOM_SIZE, ENCOUNTER_CONTRACTS.profile_counts(1, 0, 0, 0, 3, 1), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 0, 0, 0, 2, 1),
			ENCOUNTER_CONTRACTS.profile_counts(2, 0, 0, 0, 3, 1),
			ENCOUNTER_CONTRACTS.profile_counts(3, 0, 0, 0, 3, 1),
			ENCOUNTER_CONTRACTS.profile_counts(4, 0, 0, 0, 3, 2)
		]),
		"Suppression": _bearing_definition(POOL_ROOM_SIZE, ENCOUNTER_CONTRACTS.profile_counts(1, 1, 2, 1, 0, 0, 2), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 1, 1, 1, 0, 0, 2),
			ENCOUNTER_CONTRACTS.profile_counts(1, 1, 2, 1, 0, 0, 3),
			ENCOUNTER_CONTRACTS.profile_counts(2, 1, 3, 2, 0, 0, 3),
			ENCOUNTER_CONTRACTS.profile_counts(2, 2, 4, 2, 0, 0, 4)
		]),
		"Vanguard": _bearing_definition(POOL_ROOM_SIZE, ENCOUNTER_CONTRACTS.profile_counts(2, 2, 0, 3), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 2, 0, 2),
			ENCOUNTER_CONTRACTS.profile_counts(2, 3, 0, 3),
			ENCOUNTER_CONTRACTS.profile_counts(2, 4, 0, 4),
			ENCOUNTER_CONTRACTS.profile_counts(3, 5, 0, 4)
		]),
		"Ambush": _bearing_definition(POOL_ROOM_SIZE, ENCOUNTER_CONTRACTS.profile_counts(2, 0, 0, 0, 4, 0, 1), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 0, 0, 0, 3, 0, 1),
			ENCOUNTER_CONTRACTS.profile_counts(2, 0, 0, 0, 4, 0, 1),
			ENCOUNTER_CONTRACTS.profile_counts(4, 0, 0, 0, 4, 0, 2),
			ENCOUNTER_CONTRACTS.profile_counts(4, 0, 0, 0, 5, 0, 3)
		]),
		"Gauntlet": _bearing_definition(POOL_ROOM_SIZE, ENCOUNTER_CONTRACTS.profile_counts(1, 1, 1, 1, 1, 0, 1), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 1, 1, 1, 1, 0, 1),
			ENCOUNTER_CONTRACTS.profile_counts(2, 1, 1, 1, 1, 0, 1),
			ENCOUNTER_CONTRACTS.profile_counts(3, 1, 1, 1, 2, 0, 1),
			ENCOUNTER_CONTRACTS.profile_counts(4, 2, 1, 1, 2, 0, 1)
		])
	}
	return _bearing_definitions_cache

func _get_bearing_definition(label: String) -> Dictionary:
	return _get_bearing_definitions().get(label, {}) as Dictionary

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

func _apply_bearing_count_scaling(profile: Dictionary, pressure_mult_override: float = 1.0, minimum_total: int = 0) -> Dictionary:
	var pressure_mult := _difficulty_float("base_enemy_pressure_mult", 1.0) * pressure_mult_override
	return ENCOUNTER_CONTRACTS.profile_scaled_counts(profile, pressure_mult, minimum_total)

func _skirmish_min_total_enemies() -> int:
	return 3 + _difficulty_rank()

func _apply_profile_counts(profile: Dictionary, counts: Dictionary) -> Dictionary:
	return ENCOUNTER_CONTRACTS.profile_with_counts(profile, counts)

func _build_bearing_profile(label: String) -> Dictionary:
	var definition := _get_bearing_definition(label)
	if definition.is_empty():
		return {}
	var counts := definition.get("base_counts", {}) as Dictionary
	var room_size := definition.get("room_size", POOL_ROOM_SIZE) as Vector2
	var profile := _build_profile(label, room_size)
	return _apply_profile_counts(profile, counts)

func _build_scaled_bearing_profile(label: String) -> Dictionary:
	return _apply_identity_bearing_scaling(_build_bearing_profile(label))

func _bearing_label_from_debug_key(key: String) -> String:
	for label in BEARING_LABELS:
		if label.to_lower() == key:
			return label
	return ""

func _apply_identity_bearing_scaling(profile: Dictionary) -> Dictionary:
	var label := ENCOUNTER_CONTRACTS.profile_label(profile)
	var definition := _get_bearing_definition(label)
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

func _build_profile(label: String, room_size: Vector2, chasers: int = 0, chargers: int = 0, archers: int = 0, shielders: int = 0, enemy_mutator: Dictionary = {}) -> Dictionary:
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

func _build_objective_profile_for_kind(kind: String, depth: int) -> Dictionary:
	match kind:
		"last_stand":
			return _build_survival_profile(depth)
		"cut_the_signal":
			return _build_priority_target_profile(depth)
		"hold_the_line":
			return _build_control_profile(depth)
		_:
			return {}

func build_objective_profile(depth: int, preferred: String = "") -> Dictionary:
	var canonical_kind := preferred.strip_edges().to_lower()
	var explicit_profile := _build_objective_profile_for_kind(canonical_kind, depth)
	if not explicit_profile.is_empty():
		return explicit_profile
	var objective_profiles: Array[Dictionary] = [_build_survival_profile(depth), _build_priority_target_profile(depth), _build_control_profile(depth)]
	return objective_profiles[rng.randi_range(0, objective_profiles.size() - 1)]

func _canonicalize_debug_encounter_key(encounter_key: String) -> String:
	return ENCOUNTER_CONTRACTS.canonicalize_debug_encounter_key(encounter_key)

func build_debug_encounter_profile(encounter_key: String, depth: int) -> Dictionary:
	var key := _canonicalize_debug_encounter_key(encounter_key)
	var bearing_label := _bearing_label_from_debug_key(key)
	if not bearing_label.is_empty():
		return _build_scaled_bearing_profile(bearing_label)
	match key:
		"skirmish":
			return _build_intro_profile(0)
		"trial":
			return _build_trial_profile(depth)
		"last_stand":
			return _build_survival_profile(depth)
		"cut_the_signal":
			return _build_priority_target_profile(depth)
		"hold_the_line":
			return _build_control_profile(depth)
		"random_objective":
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
	var pool: Array[Dictionary] = []
	for label in BEARING_LABELS:
		pool.append(_build_bearing_profile(label))
	return pool

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
			if current_difficulty_tier == BEARING_ENUMS.BearingTier.PILGRIM:
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
			if current_difficulty_tier == BEARING_ENUMS.BearingTier.PILGRIM:
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

func _trial_specialist_enemies(mutator: Dictionary, depth: int, tier: int = BEARING_ENUMS.BearingTier.DELVER) -> Dictionary:
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
			if tier != BEARING_ENUMS.BearingTier.PILGRIM:
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
	if current_difficulty_tier == BEARING_ENUMS.BearingTier.PILGRIM and effective_depth < 4:
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
	var rank_tuning := _control_rank_tuning(difficulty_rank)
	var depth_tuning := _control_depth_tuning(difficulty_rank, depth)
	var control_pressure_mult := float(rank_tuning.get("pressure_mult", 0.8)) + float(depth_tuning.get("pressure_bias", 0.0))
	var contest_threshold := 0
	var tier_spawn_interval_bias := float(rank_tuning.get("spawn_interval_bias", 0.0)) + float(depth_tuning.get("spawn_interval_bias", 0.0))
	var tier_radius_bias := float(rank_tuning.get("radius_bias", 0.0))
	var tier_goal_bias := float(rank_tuning.get("goal_bias", 0.0)) + float(depth_tuning.get("goal_bias", 0.0))
	var tier_decay_bias := float(rank_tuning.get("decay_bias", 0.0)) + float(depth_tuning.get("decay_bias", 0.0))
	var room_size := Vector2(1000.0, 760.0)
	var chasers := 2 + int(floor(float(effective_depth) * 0.32))
	var chargers := 1 + int(floor(float(effective_depth) / 6.0)) if effective_depth >= 2 else 0
	var archers := 1 if effective_depth >= 5 else 0
	var shielders := 1 + int(floor(float(effective_depth) / 5.0))
	var profile := _build_profile("Hold the Line", room_size, chasers, chargers, archers, shielders)
	ENCOUNTER_CONTRACTS.profile_set_player_mutator(profile, _build_combo_relay_mutator())
	var raw_duration := clampf(22.0 + float(effective_depth) * 0.75, 22.0, 30.0)
	var duration := int(ceil(raw_duration / 5.0)) * 5
	var spawn_interval := clampf(2.74 - float(effective_depth) * 0.03 + tier_spawn_interval_bias, 1.75, 2.95)
	var spawn_batch := mini(3, 1 + int(floor(float(effective_depth) / 5.0)))
	var zone_radius := clampf(194.0 + float(effective_depth) * 3.6 + tier_radius_bias, 184.0, 248.0)
	var progress_goal := clampf(7.95 + float(effective_depth) * 0.23 + tier_goal_bias, 7.8, 12.2)
	var progress_decay := clampf(0.2 + float(effective_depth) * 0.01 + tier_decay_bias, 0.16, 0.4)
	ENCOUNTER_CONTRACTS.profile_set_control_objective(profile, duration, spawn_interval, spawn_batch, zone_radius, progress_goal, progress_decay, contest_threshold)
	return _apply_bearing_count_scaling(profile, control_pressure_mult)

func _control_rank_tuning(difficulty_rank: int) -> Dictionary:
	if CONTROL_TUNING_BY_RANK.has(difficulty_rank):
		return (CONTROL_TUNING_BY_RANK[difficulty_rank] as Dictionary).duplicate(true)
	return (CONTROL_TUNING_BY_RANK[1] as Dictionary).duplicate(true)

func _control_depth_tuning(difficulty_rank: int, depth: int) -> Dictionary:
	var result := {
		"pressure_bias": 0.0,
		"spawn_interval_bias": 0.0,
		"goal_bias": 0.0,
		"decay_bias": 0.0
	}
	if not CONTROL_DEPTH_WINDOWS_BY_RANK.has(difficulty_rank):
		return result
	var windows := CONTROL_DEPTH_WINDOWS_BY_RANK[difficulty_rank] as Array
	for window_variant in windows:
		var window := window_variant as Dictionary
		var start_depth := int(window.get("start_depth", 1))
		var end_depth := int(window.get("end_depth", start_depth))
		if depth < start_depth or depth > end_depth:
			continue
		result["pressure_bias"] = float(result.get("pressure_bias", 0.0)) + float(window.get("pressure_bias", 0.0))
		result["spawn_interval_bias"] = float(result.get("spawn_interval_bias", 0.0)) + float(window.get("spawn_interval_bias", 0.0))
		result["goal_bias"] = float(result.get("goal_bias", 0.0)) + float(window.get("goal_bias", 0.0))
		result["decay_bias"] = float(result.get("decay_bias", 0.0)) + float(window.get("decay_bias", 0.0))
	return result

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
	return ENCOUNTER_CONTRACTS.intro_encounter_door_option(profile)

func _build_hard_route_option(depth: int) -> Dictionary:
	var hard_pool: Array[Dictionary] = _get_hard_pool_for_depth(depth)
	var hard_profile: Dictionary = hard_pool[rng.randi_range(0, hard_pool.size() - 1)]
	hard_profile = _maybe_apply_hard_mutator(hard_profile, depth)
	hard_profile = _apply_identity_bearing_scaling(hard_profile)
	return ENCOUNTER_CONTRACTS.standard_encounter_door_option(hard_profile)

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
	return ENCOUNTER_CONTRACTS.trial_door_option(trial_profile, trial_mutator_name, trial_color)

func _build_objective_route_option(depth: int) -> Dictionary:
	var objective_profile := build_objective_profile(depth)
	return ENCOUNTER_CONTRACTS.objective_door_option(objective_profile)

func _build_rest_route_option() -> Dictionary:
	return ENCOUNTER_CONTRACTS.rest_door_option()

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

func _build_combo_relay_mutator() -> Dictionary:
	return {
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_ID: "combo_relay",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME: "Combo Relay",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_SOURCE_ENCOUNTER: "Hold the Line",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_SOURCE_OBJECTIVE_KIND: "hold_the_line",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_THEME_COLOR: Color(0.98, 0.72, 0.3, 1.0),
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID: "combo_relay",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_TARGET_SCOPE: "player",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_STACK_POLICY: "refresh",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_STACK_LIMIT: 1,
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_STACK_FALLOFF: 1.0,
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_BANNER_SUFFIX: "Kill chain stacks grant damage and speed",
		ENCOUNTER_CONTRACTS.MUTATOR_KEY_EFFECTS: [],
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
