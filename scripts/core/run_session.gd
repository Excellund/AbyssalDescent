extends RefCounted
class_name RunSession

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const BIOME_REGISTRY := preload("res://scripts/shared/biome_registry.gd")
const BOSS_CATALOGUE := preload("res://scripts/shared/boss_catalogue.gd")

var boons_taken: Array[String] = []
var arcana_rewards_taken: Array[String] = []
var boss_rewards_taken: Array[String] = []
var rooms_cleared: int = 0
var room_depth: int = 0
var phase_two_rooms_cleared: int = 0
var phase_three_rooms_cleared: int = 0
var act_biome_ids: Array[String] = []
var act_boss_ids: Array[String] = []
var last_standard_encounter_key: String = ""
var last_objective_kind: String = ""

func reset_for_new_run() -> void:
	boons_taken.clear()
	arcana_rewards_taken.clear()
	boss_rewards_taken.clear()
	act_biome_ids.clear()
	act_boss_ids.clear()
	last_standard_encounter_key = ""
	last_objective_kind = ""
	set_progression_counters(0, 0, 0, 0)

## Only room entry advances variety history; generating or declining doors does not.
func record_encounter_entry(profile: Dictionary) -> void:
	var objective_kind := _canonical_objective_kind(ENCOUNTER_CONTRACTS.profile_objective_kind(profile))
	if not objective_kind.is_empty():
		last_objective_kind = objective_kind
		return
	var standard_key := _canonical_standard_key(ENCOUNTER_CONTRACTS.profile_encounter_key(profile))
	if not standard_key.is_empty():
		last_standard_encounter_key = standard_key

## Legacy or invalid biome rosters retain the run's already rolled fallback.
func restore_descent_state(snapshot: Dictionary) -> void:
	act_boss_ids = BOSS_CATALOGUE.normalize_roster(snapshot.get("act_boss_ids", []))
	var saved_biomes: Variant = snapshot.get("act_biome_ids", [])
	if saved_biomes is Array and saved_biomes.size() == 3:
		var restored: Array[String] = []
		for act_index in range(3):
			var biome_id: Variant = saved_biomes[act_index]
			if not (biome_id is String):
				break
			var biome := BIOME_REGISTRY.get_biome(biome_id)
			if biome.is_empty() or int(biome.get("act", 0)) != act_index + 1:
				break
			restored.append(biome_id)
		if restored.size() == 3:
			act_biome_ids = restored
	last_standard_encounter_key = _canonical_standard_key(snapshot.get("last_standard_encounter_key", ""))
	last_objective_kind = _canonical_objective_kind(snapshot.get("last_objective_kind", ""))

static func _canonical_standard_key(value: Variant) -> String:
	if not (value is String):
		return ""
	for label in ENCOUNTER_CONTRACTS.get_bearing_labels_from_registry():
		var key := ENCOUNTER_CONTRACTS.profile_encounter_key({"label": label})
		if value == key:
			return key
	return ""

static func _canonical_objective_kind(value: Variant) -> String:
	if not (value is String) or value == "random_objective":
		return ""
	return value if ENCOUNTER_CONTRACTS.debug_encounter_is_objective(value) and ENCOUNTER_CONTRACTS.canonicalize_debug_encounter_key(value) == value else ""

func record_boon(name: String) -> void:
	boons_taken.append(name)

func record_arcana(name: String) -> void:
	arcana_rewards_taken.append(name)

func record_boss_reward(name: String) -> void:
	boss_rewards_taken.append(name)

func get_boons_taken_snapshot() -> Array[String]:
	return boons_taken.duplicate()

func get_arcana_rewards_taken_snapshot() -> Array[String]:
	return arcana_rewards_taken.duplicate()

func get_boss_rewards_taken_snapshot() -> Array[String]:
	return boss_rewards_taken.duplicate()

func restore_rewards_from_snapshot(boons: Array[String], arcana_rewards: Array[String], boss_rewards: Array[String]) -> void:
	boons_taken = boons.duplicate()
	arcana_rewards_taken = arcana_rewards.duplicate()
	boss_rewards_taken = boss_rewards.duplicate()

func set_progression_counters(next_rooms_cleared: int, next_room_depth: int, next_phase_two_rooms_cleared: int, next_phase_three_rooms_cleared: int) -> void:
	rooms_cleared = next_rooms_cleared
	room_depth = next_room_depth
	phase_two_rooms_cleared = next_phase_two_rooms_cleared
	phase_three_rooms_cleared = next_phase_three_rooms_cleared

func apply_progression_increments(rooms_delta: int, room_depth_delta: int, phase_two_delta: int, phase_three_delta: int) -> void:
	rooms_cleared += rooms_delta
	room_depth += room_depth_delta
	phase_two_rooms_cleared += phase_two_delta
	phase_three_rooms_cleared += phase_three_delta

func get_progression_state() -> Dictionary:
	return {
		"rooms_cleared": rooms_cleared,
		"room_depth": room_depth,
		"phase_two_rooms_cleared": phase_two_rooms_cleared,
		"phase_three_rooms_cleared": phase_three_rooms_cleared,
	}
