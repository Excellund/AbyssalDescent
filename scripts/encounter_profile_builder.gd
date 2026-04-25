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

func build_skirmish_profile(depth: int) -> Dictionary:
	var size := room_base_size + room_size_growth * float(depth)
	return {
		"label": "Skirmish",
		"room_size": size,
		"static_camera": size.x <= static_camera_room_threshold,
		"chaser_count": maxi(2, base_chaser_count + depth * chasers_per_room - 2),
		"charger_count": maxi(0, depth - chargers_start_room + 1) * chargers_per_room,
		"archer_count": maxi(0, depth - archer_start_room + 1) * archers_per_room,
		"shielder_count": maxi(0, depth - shielder_start_room + 1) * shielders_per_room
	}

func build_onslaught_profile(depth: int) -> Dictionary:
	var size := room_base_size + room_size_growth * float(depth) + Vector2(180.0, 120.0)
	return {
		"label": "Onslaught",
		"room_size": size,
		"static_camera": false,
		"chaser_count": maxi(1, base_chaser_count + depth * chasers_per_room),
		"charger_count": maxi(1, (depth - chargers_start_room + 1) * chargers_per_room + 1),
		"archer_count": maxi(0, (depth - archer_start_room + 1) * archers_per_room + 1),
		"shielder_count": maxi(0, (depth - shielder_start_room + 1) * shielders_per_room + 1)
	}

func build_easy_boon_profile(depth: int) -> Dictionary:
	var profile := build_skirmish_profile(depth)
	profile["label"] = "Calm Hunt"
	profile["chaser_count"] = maxi(2, int(profile["chaser_count"]) - 1)
	profile["charger_count"] = maxi(0, int(profile["charger_count"]) - 1)
	profile["enemy_mutator"] = {}
	return profile

func build_hard_trial_profile(depth: int) -> Dictionary:
	var profile := build_onslaught_profile(depth)
	profile["label"] = "Savage Trial"
	profile["chaser_count"] = int(profile["chaser_count"]) + hard_room_enemy_bonus
	profile["charger_count"] = int(profile["charger_count"]) + 1
	profile["enemy_mutator"] = roll_hard_enemy_mutator()
	return profile

func roll_route_options(depth: int) -> Array[Dictionary]:
	var easy_option := {
		"label": "Calm Hunt + Boon",
		"color": Color(0.34, 0.8, 1.0, 0.95),
		"kind": "encounter",
		"icon": "easy",
		"reward": "boon",
		"profile": build_easy_boon_profile(depth)
	}
	var hard_profile := build_hard_trial_profile(depth)
	var mutator_name := String(hard_profile["enemy_mutator"].get("name", "Frenzy"))
	var hard_option := {
		"label": "Savage Trial: %s" % mutator_name,
		"color": Color(1.0, 0.56, 0.26, 0.95),
		"kind": "encounter",
		"icon": "hard",
		"reward": "hard_reward",
		"profile": hard_profile
	}
	var rest_option := {
		"label": "Rest Site",
		"color": Color(0.66, 1.0, 0.76, 0.92),
		"kind": "rest",
		"icon": "rest",
		"reward": "none",
		"profile": {}
	}

	var options := [easy_option, hard_option, rest_option]
	var first: int = 0 if rng.randf() < 0.5 else 1
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
