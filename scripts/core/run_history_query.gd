extends RefCounted
## Read-only views of locally recorded runs. Missing old fields stay unknown.

static func filter_records(records: Array, outcome: String = "all", mode: String = "all") -> Array:
	var result: Array = []
	for value in records:
		if not value is Dictionary:
			continue
		var record := value as Dictionary
		var recorded_outcome := String(record.get("outcome", "unknown"))
		if outcome == "other" and recorded_outcome in ["clear", "death"]:
			continue
		if outcome not in ["all", "other"] and recorded_outcome != outcome:
			continue
		var coop := bool(record.get("is_multiplayer", false)) or int(record.get("player_count", 1)) > 1
		if (mode == "solo" and coop) or (mode == "coop" and not coop):
			continue
		result.append(record)
	return result

static func journey(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = record.get("reward_timeline", [])
	if not raw is Array:
		return result
	for value in raw:
		if not value is Dictionary:
			continue
		var entry := value as Dictionary
		var label := String(entry.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		var depth := -1
		var raw_depth: Variant = entry.get("depth")
		if (raw_depth is int or raw_depth is float) and is_finite(float(raw_depth)) and float(raw_depth) >= 0.0 and float(raw_depth) == floor(float(raw_depth)):
			depth = int(raw_depth)
		result.append({"label": label, "depth": depth, "category": String(entry.get("category", ""))})
	return result
