extends RefCounted
## Identity only: usable by saves, summaries and menus without loading enemies.

const DEFAULT_IDS := ["warden", "sovereign", "lacuna"]
const ALTERNATIVE_IDS := ["kilnheart", "glassweaver", "null_archivist"]
const NAMES := {
	"warden": "Warden", "sovereign": "Sovereign", "lacuna": "Lacuna",
	"kilnheart": "Kilnheart", "glassweaver": "Glassweaver", "null_archivist": "The Null Archivist",
}

## Spoken during the existing survey pause, then replaced by combat warnings.
## Plain text keeps this identity catalogue usable by every presentation surface.
const GREETINGS := {
	"warden": "Your descent ends at my feet.",
	"sovereign": "You may kneel now. The room will teach you how.",
	"lacuna": "I heard you before you had a name.",
	"kilnheart": "Come closer. Let me see what survives the heat.",
	"glassweaver": "Keep moving. You make the pattern for me.",
	"null_archivist": "Hold still. I have almost finished erasing you.",
}
const DEFEAT_LINES := {
	"warden": "Then carry what I could no longer hold.",
	"sovereign": "Take the crown. It has never spared its bearer.",
	"lacuna": "Go, then. Take the silence with you.",
	"kilnheart": "Keep it burning. It is all I have left.",
	"glassweaver": "One loose thread. That was enough.",
	"null_archivist": "An error, then. I will leave your name.",
}

static func get_greeting(boss_id: String) -> String:
	return String(GREETINGS.get(boss_id, ""))

static func get_defeat_line(boss_id: String) -> String:
	return String(DEFEAT_LINES.get(boss_id, ""))

static func stage_for_id(boss_id: String) -> int:
	for index in range(3):
		if boss_id == DEFAULT_IDS[index] or boss_id == ALTERNATIVE_IDS[index]:
			return index + 1
	return 0

static func resolve_id(stage: int, value: Variant = "") -> String:
	if stage < 1 or stage > 3:
		return ""
	return value if value is String and stage_for_id(value) == stage else DEFAULT_IDS[stage - 1]

## Missing or malformed entries retain the pre-alternatives encounter for that act.
static func normalize_roster(value: Variant) -> Array[String]:
	var ids: Array[String] = []
	for index in range(3):
		ids.append(resolve_id(index + 1, value[index] if value is Array and value.size() > index else ""))
	return ids

static func roll_roster(rng: RandomNumberGenerator) -> Array[String]:
	var ids: Array[String] = []
	for index in range(3):
		ids.append(DEFAULT_IDS[index] if rng.randi_range(0, 1) == 0 else ALTERNATIVE_IDS[index])
	return ids
