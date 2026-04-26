extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

var rng: RandomNumberGenerator

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
var hard_room_enemy_bonus: int = 3

const INTRO_ROOM_SIZE := Vector2(940.0, 700.0)
const POOL_ROOM_SIZE := Vector2(1040.0, 760.0)
const TRIAL_ROOM_SIZE := Vector2(1160.0, 860.0)

func initialize(rng_instance: RandomNumberGenerator) -> void:
	rng = rng_instance

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
		return _build_profile("Skirmish", INTRO_ROOM_SIZE, 3, 0, 0, 0)
	return _build_profile("Skirmish", INTRO_ROOM_SIZE, 3, 0, 1, 0)

func build_skirmish_profile(depth: int) -> Dictionary:
	if depth < 2:
		return _build_intro_profile(depth)
	var hard_pool := _get_hard_pool()
	return hard_pool[rng.randi_range(0, hard_pool.size() - 1)]

func _get_hard_pool() -> Array[Dictionary]:
	return [
		_build_profile("Crossfire", POOL_ROOM_SIZE, 4, 1, 2, 0),
		_build_profile("Onslaught", POOL_ROOM_SIZE, 5, 2, 0, 1),
		_build_profile("Fortress", POOL_ROOM_SIZE, 3, 1, 1, 2)
	]

func _build_trial_profile() -> Dictionary:
	var hard_pool := _get_hard_pool()
	var base: Dictionary = hard_pool[rng.randi_range(0, hard_pool.size() - 1)]
	var mutator: Dictionary = roll_hard_enemy_mutator()
	var chasers := ENCOUNTER_CONTRACTS.profile_chaser_count(base) + hard_room_enemy_bonus
	var chargers := ENCOUNTER_CONTRACTS.profile_charger_count(base) + 1
	var archers: int = maxi(ENCOUNTER_CONTRACTS.profile_archer_count(base), 1)
	var shielders := ENCOUNTER_CONTRACTS.profile_shielder_count(base)
	var mutator_name := ENCOUNTER_CONTRACTS.mutator_name(mutator)
	if mutator_name.is_empty():
		mutator_name = "Frenzy"
	return _build_profile("Trial %s" % mutator_name, TRIAL_ROOM_SIZE, chasers, chargers, archers, shielders, mutator)

func _build_survival_profile(depth: int) -> Dictionary:
	var hard_pool := _get_hard_pool()
	var base: Dictionary = hard_pool[rng.randi_range(0, hard_pool.size() - 1)]
	var survival_room_size := Vector2(980.0, 740.0)
	var chasers := maxi(4, ENCOUNTER_CONTRACTS.profile_chaser_count(base) + 1)
	var chargers := maxi(1, ENCOUNTER_CONTRACTS.profile_charger_count(base))
	var archers := maxi(1, ENCOUNTER_CONTRACTS.profile_archer_count(base) + 1)
	var shielders := maxi(1, ENCOUNTER_CONTRACTS.profile_shielder_count(base))
	var pressure_mutator := {
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
	}
	var profile := _build_profile("Last Stand", survival_room_size, chasers, chargers, archers, shielders, pressure_mutator)
	var raw_duration := clampf(22.0 + float(depth) * 0.85, 22.0, 34.0)
	var duration := int(ceil(raw_duration / 5.0)) * 5
	var spawn_interval := clampf(1.95 - float(depth) * 0.06, 0.85, 1.95)
	var spawn_batch := mini(5, 2 + int(floor(float(depth) / 3.0)))
	ENCOUNTER_CONTRACTS.profile_set_survival_objective(profile, duration, spawn_interval, spawn_batch)
	return profile

func roll_route_options(depth: int) -> Array[Dictionary]:
	if depth < 2:
		var intro_profile: Dictionary = _build_intro_profile(depth)
		var easy_option := ENCOUNTER_CONTRACTS.door_option(
			ENCOUNTER_CONTRACTS.profile_label(intro_profile),
			Color(0.34, 0.8, 1.0, 0.95),
			ENUMS.DoorKind.ENCOUNTER,
			"easy",
			ENUMS.RewardMode.BOON,
			intro_profile
		)
		var intro_rest_option := ENCOUNTER_CONTRACTS.door_option(
			"Rest Site",
			Color(0.66, 1.0, 0.76, 0.92),
			ENUMS.DoorKind.REST,
			"rest",
			ENUMS.RewardMode.NONE,
			{}
		)
		var intro_options: Array[Dictionary] = [easy_option, intro_rest_option]
		if rng.randf() < 0.5:
			return intro_options
		var reversed_intro_options: Array[Dictionary] = [intro_options[1], intro_options[0]]
		return reversed_intro_options

	# After room 2: no more easy-pool encounters.
	var hard_pool: Array[Dictionary] = _get_hard_pool()
	var hard_profile: Dictionary = hard_pool[rng.randi_range(0, hard_pool.size() - 1)]
	var hard_option := ENCOUNTER_CONTRACTS.door_option(
		ENCOUNTER_CONTRACTS.profile_label(hard_profile),
		Color(0.93, 0.62, 0.28, 0.95),
		ENUMS.DoorKind.ENCOUNTER,
		"hard",
		ENUMS.RewardMode.BOON,
		hard_profile
	)

	var trial_profile: Dictionary = _build_trial_profile()
	var trial_mutator: Dictionary = ENCOUNTER_CONTRACTS.profile_enemy_mutator(trial_profile)
	var trial_mutator_name := ENCOUNTER_CONTRACTS.mutator_name(trial_mutator)
	if trial_mutator_name.is_empty():
		trial_mutator_name = "Trial"
	var trial_color: Color = ENCOUNTER_CONTRACTS.mutator_theme_color(trial_mutator, Color(1.0, 0.32, 0.22, 0.96))
	trial_color.a = 0.96
	var trial_option := ENCOUNTER_CONTRACTS.door_option(
		"Trial - %s" % trial_mutator_name,
		trial_color,
		ENUMS.DoorKind.ENCOUNTER,
		"trial",
		ENUMS.RewardMode.ARCANA,
		trial_profile
	)

	var survival_profile := _build_survival_profile(depth)
	var survival_option := ENCOUNTER_CONTRACTS.door_option(
		"Objective - Last Stand",
		Color(0.98, 0.78, 0.34, 0.96),
		ENUMS.DoorKind.ENCOUNTER,
		"trial",
		ENUMS.RewardMode.BOON,
		survival_profile
	)

	var rest_option := ENCOUNTER_CONTRACTS.door_option(
		"Rest Site",
		Color(0.66, 1.0, 0.76, 0.92),
		ENUMS.DoorKind.REST,
		"rest",
		ENUMS.RewardMode.NONE,
		{}
	)

	var options: Array[Dictionary] = [hard_option, trial_option, survival_option, rest_option]
	var first: int = rng.randi_range(0, options.size() - 1)
	var chosen: Array[Dictionary] = [options[first]]

	var remaining_indices: Array[int] = [0, 1, 2]
	remaining_indices.erase(first)
	var second_index: int = remaining_indices[rng.randi_range(0, remaining_indices.size() - 1)]
	chosen.append(options[second_index])
	return chosen

func roll_hard_enemy_mutator() -> Dictionary:
	var C := ENCOUNTER_CONTRACTS
	var pool: Array[Dictionary] = [
		{
			C.MUTATOR_KEY_NAME: "Blood Rush",
			# Melee attackers hit harder and faster — chasers + chargers
			C.MUTATOR_KEY_THEME_COLOR: Color(0.95, 0.22, 0.28, 1.0),
			C.MUTATOR_KEY_ICON_SHAPE_ID: "blood_rush",
			C.MUTATOR_KEY_BANNER_SUFFIX: "Melee enemies strike harder and faster",
			C.MUTATOR_KEY_ENEMY_TINT: Color(1.0, 0.80, 0.80, 1.0),
			C.MUTATOR_STAT_CHASER_DAMAGE_MULT: 1.5,
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
			C.MUTATOR_KEY_BANNER_SUFFIX: "Charges and volleys strike with almost no warning",
			C.MUTATOR_KEY_ENEMY_TINT: Color(0.88, 0.82, 1.0, 1.0),
			C.MUTATOR_STAT_CHARGER_DAMAGE_MULT: 1.2,
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
			C.MUTATOR_KEY_BANNER_SUFFIX: "Chargers and shielders hit with overwhelming force",
			C.MUTATOR_KEY_ENEMY_TINT: Color(1.0, 0.88, 0.72, 1.0),
			C.MUTATOR_STAT_CHARGER_DAMAGE_MULT: 1.62,
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
	return pool[rng.randi_range(0, pool.size() - 1)]
