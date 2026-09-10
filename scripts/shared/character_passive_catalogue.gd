extends RefCounted
## Shared character rules and explicit combat properties for selection, builds and the glossary.

const KEYWORDS := preload("res://scripts/shared/combat_keyword_catalogue.gd")

const PASSIVES := {
	"iron_retort": {
		"name": "Iron Retort",
		"build": "Hold your ground briefly between {kw:attack|Attacks} to Brace, boosting melee and charged {kw:attack} damage by 80%. Your first {kw:attack_hit} spends Brace, releases a {kw:burst} and grants 25% resistance for 1.5s. {kw:dash}, {kw:recoil} and {kw:orbit} break Brace.",
		"short": "Brace boosts melee and charged {kw:attack|Attacks}. The first {kw:attack_hit} grants Guard and a {kw:burst}. {kw:dash}, {kw:recoil} and {kw:orbit} break Brace.",
		"rules": [
			"Between {kw:attack|Attacks}, hold your ground for 0.42s to Brace for 2.4s; moving slowly also qualifies.",
			"Braced melee and charged {kw:attack|Attacks} deal +80% damage and have a 24° wider arc.",
			"The first accepted {kw:attack_hit} spends Brace, releases a {kw:burst} and grants 25% resistance for 1.5s.",
			"The {kw:burst} deals 55% of the empowered strike's damage basis; each foe's conditions apply separately.",
			"Missed or rejected contacts grant no {kw:burst} or Guard. {kw:dash}, {kw:recoil} and {kw:orbit} break Brace.",
			"{kw:dash|Dashing} also prevents rebuilding Brace for 0.8s."
		],
		"produces": ["damage", "burst"],
		"accepts": ["attack_hit"],
		"condition_text": "Brace empowers melee and charged Attacks. The first accepted melee, extended arc or charged blast contact spends Brace. Its Burst deals damage without another attack hit."
	},
	"sigil_burst": {
		"name": "Sigil Burst",
		"build": "{kw:dash} to arm one {kw:burst}. Your next {kw:attack_hit} releases it at the foe for 70% of that attack's damage basis. Repeated {kw:dash|Dashes} do not store extra Bursts.",
		"short": "{kw:dash|Dashing} arms a {kw:burst}. Your next {kw:attack_hit} releases it at the foe for 70% of that attack's damage basis.",
		"rules": [
			"A normal {kw:dash} arms one {kw:burst}; your next accepted {kw:attack_hit} releases it at that foe.",
			"Melee, extended arcs and charged blasts qualify. Misses and automatic damage leave it armed.",
			"The {kw:burst} deals 70% of that attack's damage basis; each foe's conditions apply separately.",
			"One {kw:burst} per {kw:dash}, at most once per original {kw:attack}. Repeated {kw:dash|Dashes} do not store extra Bursts.",
			"It also detonates nearby owned Sigil Chain sigils for three times their tick damage.",
			"Active {kw:field|Fields} are consumed; dormant sigils can detonate again until the chain resets."
		],
		"produces": ["damage", "burst"],
		"accepts": ["dash", "attack_hit"],
		"condition_text": "A normal Dash arms one Burst for the next accepted melee, extended arc or charged blast contact. Automatic damage cannot spend it. It detonates nearby owned Sigil Chain sigils, including dormant ones; other Fields do not detonate."
	},
	"veilstep_rhythm": {
		"name": "Veilstep Rhythm",
		"short": "{kw:dash} through foes to gain a shard, once per {kw:dash}. Two shards refresh {kw:dash}; use it within 4s to end in a 160% Damage {kw:burst}.",
		"rules": [
			"A normal {kw:dash} through foes grants one shard, at most once per {kw:dash} regardless of foes touched.",
			"Two shards refresh {kw:dash} and open a 4s Surge window. {kw:recoil} and {kw:orbit} do not grant shards.",
			"Your next {kw:dash} in that window has no cooldown and ends in a {kw:burst} dealing 160% Damage.",
			"The {kw:burst} spends all shards. If the window expires before you {kw:dash}, the shards are lost.",
			"No {kw:attack} is needed. The {kw:burst} deals damage without producing another {kw:attack_hit}."
		],
		"produces": ["damage", "burst", "dash"],
		"accepts": ["dash"],
		"condition_text": "Normal Dash contact grants one shard per Dash. Two shards refresh Dash; a Dash within 4s ends in one Burst. The refresh does not perform a Dash automatically; Recoil and Orbit do not grant shards."
	},
	"farline_focus": {
		"name": "Farline Focus",
		"short": "Melee and charged {kw:attack|Attacks} deal +70% damage inside your farline band and aim lane, or 30% less outside them.",
		"rules": [
			"Melee and charged {kw:attack|Attacks} deal +70% damage to foes inside both your farline band and aim lane.",
			"Those {kw:attack|Attacks} deal 30% less damage outside either boundary; each foe is checked separately.",
			"The band covers the outer 26% of {kw:attack} range and grows with range. Your {kw:attack} arc sets the aim lane.",
			"A foe's body must overlap the band and its center must lie in the aim lane.",
			"Razor Wind and automatic damage do not make a new Farline check; copied damage retains its source scaling."
		],
		"produces": [],
		"accepts": ["attack_hit"],
		"attack_hit_sources": ["melee", "blast_drive"],
		"condition_text": "Only melee and charged blast contacts check Farline. Each foe must overlap the outer range band and lie within the aim lane. Razor Wind and automatic damage do not make a new Farline check."
	}
}

static func get_display_name(passive_id: String) -> String:
	var id := passive_id.strip_edges().to_lower()
	if PASSIVES.has(id):
		return String(PASSIVES[id].name)
	return "Passive" if id.is_empty() else id.capitalize()

static func get_short_description(passive_id: String) -> String:
	return KEYWORDS.format_text(String(PASSIVES.get(passive_id.strip_edges().to_lower(), {}).get("short", "")))

static func get_build_description(passive_id: String) -> String:
	var data: Dictionary = PASSIVES.get(passive_id.strip_edges().to_lower(), {})
	return KEYWORDS.format_text(String(data.get("build", data.get("short", "Passive ability"))))

static func get_description(passive_id: String) -> String:
	var lines: Array[String] = []
	for rule: String in PASSIVES.get(passive_id.strip_edges().to_lower(), {}).get("rules", []):
		lines.append("• " + KEYWORDS.format_text(rule))
	return "\n".join(lines) if not lines.is_empty() else "Passive ability"

static func get_keyword_metadata(passive_id: String) -> Dictionary:
	var data: Dictionary = PASSIVES.get(passive_id.strip_edges().to_lower(), {})
	var authored := String(data.get("short", "")) + " " + String(data.get("build", "")) + " " + " ".join(data.get("rules", []))
	var metadata := {
		"produces": data.get("produces", []).duplicate(),
		"accepts": data.get("accepts", []).duplicate(),
		"conditions": [],
		"condition_text": String(data.get("condition_text", "")),
		"description_keywords": KEYWORDS.keyword_ids(authored)
	}
	if data.has("attack_hit_sources"):
		metadata["attack_hit_sources"] = data.attack_hit_sources.duplicate()
	return metadata

static func get_keyword_details(passive_id: String) -> String:
	return KEYWORDS.definitions_bbcode(get_keyword_metadata(passive_id).description_keywords)
