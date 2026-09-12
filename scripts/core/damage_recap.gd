extends RefCounted
## Bounded local evidence. Never reconstruct missing damage from aggregate stats.

const SOURCES := preload("res://scripts/shared/damage_source_catalogue.gd")
const MAX_ENTRIES := 6
const VERSION := 1

static func _integer(value: Variant, fallback: int = -1) -> int:
	if (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 2147483647.0 and float(value) == floor(float(value)):
		return int(value)
	return fallback

static func _id(value: Variant) -> String:
	if not value is String or value.length() > 80:
		return "unknown"
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return "unknown"
	return value if not value.is_empty() else "unknown"

static func entry(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var before := _integer(value.get("health_before"))
	var after := _integer(value.get("health_after"))
	if before <= 0 or after < 0 or after >= before:
		return {}
	return {
		"source": _id(value.get("source")), "ability": _id(value.get("ability")),
		"health_before": before, "health_after": after, "health_lost": before - after,
		"raw_amount": _integer(value.get("raw_amount"), before - after),
		"final_amount": _integer(value.get("final_amount"), before - after),
		"elapsed_seconds": _integer(value.get("elapsed_seconds")),
		"room_depth": _integer(value.get("room_depth")),
	}

static func normalize(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("version") != VERSION or not value.get("entries") is Array:
		return {}
	var entries: Array[Dictionary] = []
	var raw_entries: Array = value.entries
	for index in range(maxi(0, raw_entries.size() - MAX_ENTRIES), raw_entries.size()):
		var normalized := entry(raw_entries[index])
		if not normalized.is_empty():
			entries.append(normalized)
	var valid_last_entry: bool = not raw_entries.is_empty() and not entry(raw_entries.back()).is_empty()
	return {"version": VERSION, "entries": entries, "ending_health": _integer(value.get("ending_health")), "peer_id": _integer(value.get("peer_id")),
		"ending_on_damage": valid_last_entry and value.get("ending_on_damage") is bool and value.ending_on_damage}

static func record_health(value: Dictionary, health: int, accepted_damage: Dictionary = {}) -> Dictionary:
	var recap := normalize(value)
	if recap.is_empty():
		recap = {"version": VERSION, "entries": [], "ending_health": -1, "ending_on_damage": false}
	var normalized := entry(accepted_damage)
	var accepted: bool = not normalized.is_empty() and normalized.health_after == health
	if accepted:
		recap.entries.append(normalized)
		while recap.entries.size() > MAX_ENTRIES:
			recap.entries.pop_front()
	if health != recap.ending_health or accepted:
		recap.ending_on_damage = accepted
		recap.ending_health = health
	return recap

static func presentation(summary: Dictionary) -> Dictionary:
	var recap := normalize(summary.get("damage_recap"))
	if recap.is_empty() or recap.entries.is_empty():
		return {"visible": false, "title": "Recent damage", "detail": "", "entries": []}
	var final_damage: bool = summary.get("outcome") == "death" and recap.ending_health == 0 and recap.ending_on_damage and recap.entries.back().health_after == 0
	var rows: Array[Dictionary] = []
	for index in range(recap.entries.size() - 1, -1, -1):
		var damage: Dictionary = recap.entries[index]
		var details: Array[String] = []
		if damage.elapsed_seconds >= 0:
			details.append("%02d:%02d" % [int(damage.elapsed_seconds) / 60, int(damage.elapsed_seconds) % 60])
		if damage.room_depth >= 0:
			details.append("Depth %d" % damage.room_depth)
		details.append("%d → %d HP" % [damage.health_before, damage.health_after])
		rows.append({"label": SOURCES.label(damage.source, damage.ability), "detail": " · ".join(details),
			"health_lost": damage.health_lost, "is_final": final_damage and index == recap.entries.size() - 1})
	return {"visible": true, "title": "Final damage" if final_damage else "Recent damage",
		"detail": "Most recent first. Healing and revivals may occur between entries.", "entries": rows}
