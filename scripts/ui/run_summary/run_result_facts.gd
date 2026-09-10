extends RefCounted

const BOSS_NAMES := preload("res://scripts/shared/boss_catalogue.gd").NAMES
const ACT_NAMES := {1: "I", 2: "II", 3: "III"}

static func is_recorded_count(value: Variant) -> bool:
	return (value is int and value >= 0) or (value is float and is_finite(value) and value >= 0.0 and value == floor(value))

static func has_partial_history(summary: Dictionary) -> bool:
	var complete: Variant = summary.get("full_run_tracking_complete")
	return complete is bool and not complete

static func headline(summary: Dictionary, fallback: String) -> String:
	var parts: Array[String] = []
	var act: Variant = summary.get("reached_act")
	if is_recorded_count(act) and ACT_NAMES.has(int(act)):
		parts.append("Act " + String(ACT_NAMES[int(act)]))
	var depth: Variant = summary.get("max_depth")
	if is_recorded_count(depth):
		parts.append("Depth %d" % depth)
	return " · ".join(parts) if not parts.is_empty() else fallback

static func boss_line(summary: Dictionary) -> String:
	var lines: Array[String] = []
	var stats: Variant = summary.get("stats", {})
	if stats is Dictionary and not has_partial_history(summary):
		var count: Variant = stats.get("bosses_defeated")
		if is_recorded_count(count):
			lines.append("Bosses defeated · %d" % count)
	var names: Array[String] = []
	var ids: Variant = summary.get("defeated_boss_ids", [])
	if ids is Array:
		for id in ids:
			if id is String and BOSS_NAMES.has(id) and not names.has(BOSS_NAMES[id]):
				names.append(BOSS_NAMES[id])
	if not names.is_empty():
		lines.append("Defeated: " + " · ".join(names))
	return "\n".join(lines)

static func metadata(summary: Dictionary) -> String:
	var parts: Array[String] = []
	for key in ["character_name", "difficulty_label"]:
		var value: Variant = summary.get(key)
		if value is String and not value.strip_edges().is_empty() and value.to_lower() != "unknown":
			parts.append(value)
	var duration: Variant = summary.get("duration_seconds")
	if is_recorded_count(duration):
		parts.append("%02d:%02d" % [int(duration) / 60, int(duration) % 60])
	var rank: Variant = summary.get("ascension_rank")
	if is_recorded_count(rank) and rank > 0:
		parts.append("Ascension %d" % rank)
	return "  |  ".join(parts)
