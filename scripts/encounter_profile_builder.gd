extends Node

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
	var profile := {
		"label": label,
		"room_size": room_size,
		"static_camera": room_size.x <= static_camera_room_threshold,
		"chaser_count": chasers,
		"charger_count": chargers,
		"archer_count": archers,
		"shielder_count": shielders
	}
	if not enemy_mutator.is_empty():
		profile["enemy_mutator"] = enemy_mutator
	return profile

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
	var chasers := int(base["chaser_count"]) + hard_room_enemy_bonus
	var chargers := int(base["charger_count"]) + 1
	var archers: int = maxi(int(base["archer_count"]), 1)
	var shielders := int(base["shielder_count"])
	var mutator_name := String(mutator.get("name", "Frenzy"))
	return _build_profile("Trial %s" % mutator_name, TRIAL_ROOM_SIZE, chasers, chargers, archers, shielders, mutator)

func roll_route_options(depth: int) -> Array[Dictionary]:
	if depth < 2:
		var intro_profile: Dictionary = _build_intro_profile(depth)
		var easy_option: Dictionary = {
			"label": "%s + Boon" % String(intro_profile["label"]),
			"color": Color(0.34, 0.8, 1.0, 0.95),
			"kind": "encounter",
			"icon": "easy",
			"reward": "boon",
			"profile": intro_profile
		}
		var intro_rest_option: Dictionary = {
			"label": "Rest Site",
			"color": Color(0.66, 1.0, 0.76, 0.92),
			"kind": "rest",
			"icon": "rest",
			"reward": "none",
			"profile": {}
		}
		var intro_options: Array[Dictionary] = [easy_option, intro_rest_option]
		if rng.randf() < 0.5:
			return intro_options
		var reversed_intro_options: Array[Dictionary] = [intro_options[1], intro_options[0]]
		return reversed_intro_options

	# After room 2: no more easy-pool encounters.
	var hard_pool: Array[Dictionary] = _get_hard_pool()
	var hard_profile: Dictionary = hard_pool[rng.randi_range(0, hard_pool.size() - 1)]
	var hard_option: Dictionary = {
		"label": "%s + Boon" % String(hard_profile["label"]),
		"color": Color(0.93, 0.62, 0.28, 0.95),
		"kind": "encounter",
		"icon": "hard",
		"reward": "boon",
		"profile": hard_profile
	}

	var trial_profile: Dictionary = _build_trial_profile()
	var trial_option: Dictionary = {
		"label": "%s + Trial Reward" % String(trial_profile["label"]),
		"color": Color(1.0, 0.32, 0.22, 0.96),
		"kind": "encounter",
		"icon": "trial",
		"reward": "trial_reward",
		"profile": trial_profile
	}

	var rest_option: Dictionary = {
		"label": "Rest Site",
		"color": Color(0.66, 1.0, 0.76, 0.92),
		"kind": "rest",
		"icon": "rest",
		"reward": "none",
		"profile": {}
	}

	var options: Array[Dictionary] = [hard_option, trial_option, rest_option]
	var first: int = rng.randi_range(0, options.size() - 1)
	var chosen: Array[Dictionary] = [options[first]]

	var remaining_indices: Array[int] = [0, 1, 2]
	remaining_indices.erase(first)
	var second_index: int = remaining_indices[rng.randi_range(0, remaining_indices.size() - 1)]
	chosen.append(options[second_index])
	return chosen

func roll_hard_enemy_mutator() -> Dictionary:
	var pool: Array[Dictionary] = [
		{
			"name": "Blood Rush",
			"chaser_damage_mult": 1.45,
			"chaser_attack_interval_mult": 0.82,
			"chaser_speed_mult": 1.08,
			"charger_damage_mult": 1.35,
			"charger_speed_mult": 1.0,
			"charger_windup_mult": 0.95
		},
		{
			"name": "Lightning Lunge",
			"chaser_damage_mult": 1.12,
			"chaser_attack_interval_mult": 0.95,
			"chaser_speed_mult": 1.25,
			"charger_damage_mult": 1.22,
			"charger_speed_mult": 1.26,
			"charger_windup_mult": 0.7
		},
		{
			"name": "Siegebreak",
			"chaser_damage_mult": 1.22,
			"chaser_attack_interval_mult": 1.0,
			"chaser_speed_mult": 1.02,
			"charger_damage_mult": 1.52,
			"charger_speed_mult": 1.12,
			"charger_windup_mult": 0.82
		}
	]
	return pool[rng.randi_range(0, pool.size() - 1)]
