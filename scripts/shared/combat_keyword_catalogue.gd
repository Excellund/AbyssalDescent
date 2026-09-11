extends RefCounted
## Authored semantic spans only. Ordinary prose and internal HIT IDs are never rewritten.

# A warm neutral and five muted accents separate the combinations players scan.
# Shared colors are presentation groups, never additional trigger eligibility.
const BASE_COLOR := "DFDACE"
const MOTION_COLOR := "AFC8D8"
const MARK_COLOR := "D3B6D1"
const ELECTRIC_COLOR := "E0CB8D"
const FIELD_COLOR := "ACCBB5"
const BURST_COLOR := "DFB6A2"
const KEYWORD_COLORS := {
	"attack": BASE_COLOR, "attack_hit": BASE_COLOR, "kill": BASE_COLOR,
	"projectile": BASE_COLOR, "echo": BASE_COLOR,
	"dash": MOTION_COLOR, "recoil": MOTION_COLOR, "orbit": MOTION_COLOR,
	"slow": MOTION_COLOR, "push": MOTION_COLOR, "pull": MOTION_COLOR,
	"launch": MOTION_COLOR,
	"mark": MARK_COLOR, "electric": ELECTRIC_COLOR, "field": FIELD_COLOR,
	"burst": BURST_COLOR, "impact": BURST_COLOR
}
# Retain metadata IDs for matching, but these are ordinary prose/stat names.
const PLAIN_TERMS := ["damage", "damage_stat"]

const KEYWORDS := {
	"attack": {"label": "Attack", "definition": "A deliberate use of the Attack control; it can miss."},
	"attack_hit": {"label": "attack hit", "definition": "Your deliberate melee, extended arc or charged blast connects with a foe."},
	"damage": {"label": "dealing damage", "definition": "Damage accepted from any eligible source, including automatic effects."},
	"damage_stat": {"label": "Damage", "definition": "The player stat used to scale damage amounts."},
	"dash": {"label": "Dash", "definition": "The normal Dash action; Recoil and Orbit count only when named."},
	"recoil": {"label": "Recoil", "definition": "Movement caused by releasing a charged blast."},
	"orbit": {"label": "Orbit", "definition": "Movement around a hooked anchor."},
	"kill": {"label": "Kill", "definition": "An enemy death credited to you, from any eligible damage source."},
	"slow": {"label": "Slow", "definition": "Reduced movement; already Slowed checks the state before damage."},
	"mark": {"label": "Mark", "definition": "Timed vulnerability shared by players; strongest wins and damage never consumes it."},
	"field": {"label": "Field", "definition": "A persistent area with a defined footprint and lifetime."},
	"burst": {"label": "Burst", "definition": "A brief area effect that may deal damage or apply a condition."},
	"projectile": {"label": "Projectile", "definition": "A traveling effect; its damage does not perform another Attack."},
	"push": {"label": "Push", "definition": "Forced movement away from an origin."},
	"pull": {"label": "Pull", "definition": "Forced movement toward an origin."},
	"launch": {"label": "Launch", "definition": "Forced movement armed for a collision payoff; immovable foes compress in place."},
	"impact": {"label": "Impact", "definition": "A launched foe collides with a foe or geometry; once per Launch."},
	"echo": {"label": "Echo", "definition": "A weaker copied attack shape, without another action or resource cost."},
	"electric": {"label": "Electric", "definition": "A damage property; it does not imply a shared charge resource."}
}

static func keyword_color(id: String) -> String:
	return String(KEYWORD_COLORS.get(id, BASE_COLOR))

static func keyword_bbcode(id: String, label: String = "") -> String:
	if not KEYWORDS.has(id):
		return label if not label.is_empty() else id
	var item: Dictionary = KEYWORDS[id]
	var text: String = item.label if label.is_empty() else label
	if PLAIN_TERMS.has(id):
		return text
	return "[b][color=#%s]%s[/color][/b]" % [keyword_color(id), text]

static func format_text(authored: String) -> String:
	var result := ""
	var cursor := 0
	while cursor < authored.length():
		var start := authored.find("{kw:", cursor)
		if start < 0:
			return result + authored.substr(cursor)
		result += authored.substr(cursor, start - cursor)
		var finish := authored.find("}", start)
		if finish < 0:
			return result + authored.substr(start)
		var parts := authored.substr(start + 4, finish - start - 4).split("|", true, 1)
		result += keyword_bbcode(parts[0], parts[1] if parts.size() > 1 else "")
		cursor = finish + 1
	return result

static func keyword_ids(authored: String) -> Array[String]:
	var found: Array[String] = []
	var cursor := 0
	while true:
		var start := authored.find("{kw:", cursor)
		if start < 0:
			break
		var finish := authored.find("}", start)
		if finish < 0:
			break
		var id := authored.substr(start + 4, finish - start - 4).split("|", true, 1)[0]
		if KEYWORDS.has(id) and not PLAIN_TERMS.has(id) and not found.has(id):
			found.append(id)
		cursor = finish + 1
	return found

static func definitions_bbcode(ids: Array[String]) -> String:
	var lines: Array[String] = []
	for id in ids:
		if KEYWORDS.has(id) and not PLAIN_TERMS.has(id):
			lines.append("%s: %s" % [keyword_bbcode(id), KEYWORDS[id].definition])
	return "\n".join(lines)

static func to_plain(authored: String) -> String:
	return preload("res://scripts/shared/description_cap_guard.gd").strip_bbcode(format_text(authored))
