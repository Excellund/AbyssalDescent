extends RefCounted
## Authored semantic spans only. Ordinary prose and internal HIT IDs are never rewritten.

const KEYWORDS := {
	"attack": {"label": "Attack", "color": "F1D38A", "definition": "The deliberate Attack-control action. Using Attack and connecting an attack are different triggers."},
	"attack_hit": {"label": "attack hit", "color": "F1D38A", "definition": "An Attack connects with an enemy. Automatic damage does not perform another Attack."},
	"damage": {"label": "dealing damage", "color": "F0B5A0", "definition": "Accepted damage from any qualifying source. Each receiving power keeps its own counting and repeat limits."},
	"damage_stat": {"label": "Damage", "color": "F0B5A0", "definition": "Your base Damage stat. A percentage of Damage scales the whole eligible damage coefficient, including time spent in a Field."},
	"dash": {"label": "Dash", "color": "8FCEF2", "definition": "Your normal Dash action. Powers state whether they react to starting, contact or completion."},
	"recoil": {"label": "Recoil", "color": "8FCEF2", "definition": "Movement caused by releasing a charged blast. It does not count as a normal Dash."},
	"orbit": {"label": "Orbit", "color": "8FCEF2", "definition": "Movement around a hooked anchor. It does not count as a normal Dash."},
	"kill": {"label": "Kill", "color": "F2AB94", "definition": "An enemy dies from damage credited to you. The receiving power defines any further restrictions."},
	"slow": {"label": "Slow", "color": "8DDDBE", "definition": "Reduced enemy movement for a limited time. Slowed means the effect is already active; another player's Slow can prepare a target."},
	"mark": {"label": "Mark", "color": "DEADEE", "definition": "A timed vulnerability. The strongest active Mark increases all player damage to that enemy; Marks do not add together or disappear when damaged."},
	"field": {"label": "Field", "color": "ABAEEF", "definition": "A persistent area. Each Field defines its shape, duration, damage cadence and overlap rules."},
	"burst": {"label": "Burst", "color": "EFB38A", "definition": "An instant area effect. A Burst does not persist as a Field."},
	"projectile": {"label": "Projectile", "color": "B9D7F3", "definition": "An effect that travels through the arena. Its power defines collision and repeat-hit limits."},
	"push": {"label": "Push", "color": "E5C597", "definition": "Displacement away from a source. It becomes a Launch only when a power explicitly enables that interaction."},
	"pull": {"label": "Pull", "color": "E5C597", "definition": "Displacement toward a source. It becomes a Launch only when a power explicitly enables that interaction."},
	"launch": {"label": "Launch", "color": "E9AC83", "definition": "Displacement armed to cause an Impact. Immovable enemies compress in place instead."},
	"impact": {"label": "Impact", "color": "E9AC83", "definition": "A launched enemy meets another enemy or arena geometry. One Launch can cause one impact Burst."},
	"echo": {"label": "Echo", "color": "B8ACED", "definition": "A copied attack shape and scaled damage. It deals damage without performing another Attack, repeating movement or creating another Echo."},
	"electric": {"label": "Electric", "color": "91DFF2", "definition": "A damage property. It identifies matching damage without implying a shared charge mechanic."}
}

static func keyword_bbcode(id: String, label: String = "") -> String:
	if not KEYWORDS.has(id):
		return label if not label.is_empty() else id
	var item: Dictionary = KEYWORDS[id]
	return "[b][color=#%s]%s[/color][/b]" % [item.color, item.label if label.is_empty() else label]

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
		if KEYWORDS.has(id) and not found.has(id):
			found.append(id)
		cursor = finish + 1
	return found

static func definitions_bbcode(ids: Array[String]) -> String:
	var lines: Array[String] = []
	for id in ids:
		if KEYWORDS.has(id):
			lines.append("%s: %s" % [keyword_bbcode(id), KEYWORDS[id].definition])
	return "\n\n".join(lines)

static func to_plain(authored: String) -> String:
	return preload("res://scripts/shared/description_cap_guard.gd").strip_bbcode(format_text(authored))
