extends RefCounted

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

const ROOM_SIZE_POOL := Vector2(1040.0, 760.0)
const EXPECTED_BEARING_RANK_COUNT := 4

static func _bearing_definition(room_size: Vector2, base_counts: Dictionary, rank_counts: Array[Dictionary]) -> Dictionary:
	return {
		"room_size": room_size,
		"base_counts": base_counts,
		"rank_counts": rank_counts
	}

static func get_bearing_definitions() -> Dictionary:
	return {
		"Crossfire": _bearing_definition(ROOM_SIZE_POOL, ENCOUNTER_CONTRACTS.profile_counts(1, 1, 4, 0), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 1, 3, 0),
			ENCOUNTER_CONTRACTS.profile_counts(1, 1, 4, 0),
			ENCOUNTER_CONTRACTS.profile_counts(1, 2, 7, 0),
			ENCOUNTER_CONTRACTS.profile_counts(1, 2, 9, 0)
		]),
		"Onslaught": _bearing_definition(ROOM_SIZE_POOL, ENCOUNTER_CONTRACTS.profile_counts(7, 2, 0, 0), [
			ENCOUNTER_CONTRACTS.profile_counts(4, 1, 0, 0, 0, 0, 0, 0, 1, 0),
			ENCOUNTER_CONTRACTS.profile_counts(6, 2, 0, 0, 0, 0, 0, 0, 2, 0),
			ENCOUNTER_CONTRACTS.profile_counts(7, 2, 0, 0, 0, 0, 0, 0, 3, 0),
			ENCOUNTER_CONTRACTS.profile_counts(8, 3, 0, 0, 0, 0, 0, 0, 4, 0)
		]),
		"Fortress": _bearing_definition(ROOM_SIZE_POOL, ENCOUNTER_CONTRACTS.profile_counts(1, 0, 1, 4), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 0, 1, 2),
			ENCOUNTER_CONTRACTS.profile_counts(1, 0, 1, 5),
			ENCOUNTER_CONTRACTS.profile_counts(2, 0, 1, 7),
			ENCOUNTER_CONTRACTS.profile_counts(2, 0, 2, 9)
		]),
		"Blitz": _bearing_definition(ROOM_SIZE_POOL, ENCOUNTER_CONTRACTS.profile_counts(1, 0, 0, 0, 3, 1), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 0, 0, 0, 2, 1),
			ENCOUNTER_CONTRACTS.profile_counts(2, 0, 0, 0, 3, 1),
			ENCOUNTER_CONTRACTS.profile_counts(3, 0, 0, 0, 3, 1),
			ENCOUNTER_CONTRACTS.profile_counts(4, 0, 0, 0, 3, 2)
		]),
		"Suppression": _bearing_definition(ROOM_SIZE_POOL, ENCOUNTER_CONTRACTS.profile_counts(1, 1, 2, 1, 0, 0, 2), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 1, 1, 1, 0, 0, 2),
			ENCOUNTER_CONTRACTS.profile_counts(1, 1, 2, 1, 0, 0, 3),
			ENCOUNTER_CONTRACTS.profile_counts(2, 1, 3, 2, 0, 0, 3),
			ENCOUNTER_CONTRACTS.profile_counts(2, 2, 4, 2, 0, 0, 4)
		]),
		"Vanguard": _bearing_definition(ROOM_SIZE_POOL, ENCOUNTER_CONTRACTS.profile_counts(2, 2, 0, 3), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 2, 0, 2),
			ENCOUNTER_CONTRACTS.profile_counts(2, 3, 0, 3),
			ENCOUNTER_CONTRACTS.profile_counts(2, 4, 0, 4),
			ENCOUNTER_CONTRACTS.profile_counts(3, 5, 0, 4)
		]),
		"Ambush": _bearing_definition(ROOM_SIZE_POOL, ENCOUNTER_CONTRACTS.profile_counts(2, 0, 0, 0, 4, 0, 1, 0, 0, 1), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 0, 0, 0, 3, 0, 1, 0, 0, 1),
			ENCOUNTER_CONTRACTS.profile_counts(2, 0, 0, 0, 4, 0, 1, 0, 0, 1),
			ENCOUNTER_CONTRACTS.profile_counts(3, 0, 0, 0, 4, 0, 2, 0, 0, 2),
			ENCOUNTER_CONTRACTS.profile_counts(4, 0, 0, 0, 5, 0, 3, 0, 0, 2)
		]),
		"Convergence": _bearing_definition(ROOM_SIZE_POOL, ENCOUNTER_CONTRACTS.profile_counts(3, 0, 0, 0, 0, 0, 0, 2, 0, 0), [
			ENCOUNTER_CONTRACTS.profile_counts(2, 0, 0, 0, 0, 0, 0, 1, 0, 0),
			ENCOUNTER_CONTRACTS.profile_counts(3, 0, 0, 0, 0, 0, 0, 2, 0, 0),
			ENCOUNTER_CONTRACTS.profile_counts(4, 0, 0, 0, 0, 0, 0, 3, 0, 0),
			ENCOUNTER_CONTRACTS.profile_counts(5, 0, 0, 0, 0, 0, 0, 4, 0, 0)
		]),
		"Gauntlet": _bearing_definition(ROOM_SIZE_POOL, ENCOUNTER_CONTRACTS.profile_counts(1, 1, 1, 1, 1, 0, 1), [
			ENCOUNTER_CONTRACTS.profile_counts(1, 1, 1, 1, 1, 0, 1),
			ENCOUNTER_CONTRACTS.profile_counts(2, 1, 1, 1, 1, 0, 1),
			ENCOUNTER_CONTRACTS.profile_counts(3, 1, 1, 1, 2, 0, 1),
			ENCOUNTER_CONTRACTS.profile_counts(4, 2, 1, 1, 2, 0, 1)
		])
	}

static func validate_bearing_definitions(valid_labels: Array[String]) -> Array[String]:
	var issues: Array[String] = []
	var definitions := get_bearing_definitions()
	for label_variant in definitions.keys():
		var label := String(label_variant)
		if not valid_labels.has(label):
			issues.append("Canonical definition '%s' is not present in BEARING_LABELS." % label)
		var definition := definitions.get(label, {}) as Dictionary
		if not definition.has("room_size") or not (definition.get("room_size") is Vector2):
			issues.append("Canonical definition '%s' is missing Vector2 room_size." % label)
		if not definition.has("base_counts") or not (definition.get("base_counts") is Dictionary):
			issues.append("Canonical definition '%s' is missing base_counts dictionary." % label)
		var rank_counts_variant: Variant = definition.get("rank_counts", [])
		if not (rank_counts_variant is Array):
			issues.append("Canonical definition '%s' rank_counts is not an array." % label)
			continue
		var rank_counts := rank_counts_variant as Array
		if rank_counts.size() != EXPECTED_BEARING_RANK_COUNT:
			issues.append("Canonical definition '%s' rank_counts expected %d entries, got %d." % [label, EXPECTED_BEARING_RANK_COUNT, rank_counts.size()])
		for rank_index in range(rank_counts.size()):
			if not (rank_counts[rank_index] is Dictionary):
				issues.append("Canonical definition '%s' rank_counts[%d] must be a dictionary." % [label, rank_index])
	for label in valid_labels:
		if not definitions.has(label):
			issues.append("BEARING_LABELS has '%s' but canonical definition is missing." % label)
	return issues
