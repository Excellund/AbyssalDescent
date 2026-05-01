extends RefCounted

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

static func from_label(label: String, fallback: String = "unknown") -> String:
	var key := label.strip_edges().to_lower()
	if key.is_empty():
		return fallback
	for sep in [":", "-", "/", "."]:
		key = key.replace(sep, " ")
	for punct in ["'", "\""]:
		key = key.replace(punct, "")
	while key.find("  ") != -1:
		key = key.replace("  ", " ")
	key = key.strip_edges().replace(" ", "_")
	return key if not key.is_empty() else fallback

static func from_profile(profile: Dictionary, fallback: String = "unknown") -> String:
	if profile.is_empty():
		return fallback
	return from_label(ENCOUNTER_CONTRACTS.profile_label(profile), fallback)
