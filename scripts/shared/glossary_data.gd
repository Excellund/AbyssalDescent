extends RefCounted

static func _encounter_rows() -> Array[Dictionary]:
	return [
		{
			"name": "Skirmish",
			"desc": "Standard combat room with mixed enemies.",
		},
		{
			"name": "Crossfire",
			"desc": "Hard combat layout with ranged pressure and flanking lanes.",
		},
		{
			"name": "Onslaught",
			"desc": "Aggressive melee-heavy wave mix that keeps close pressure.",
		},
		{
			"name": "Fortress",
			"desc": "Defensive enemy formation with shielders anchoring the fight.",
		},
		{
			"name": "Trial",
			"desc": "Hard encounter variant with an additional enemy mutator modifier.",
		},
		{
			"name": "Last Stand",
			"desc": "Survive the timer, then finish the kill quota to clear.",
		},
		{
			"name": "Cut the Signal",
			"desc": "Hunt the marked target. It retreats at health thresholds.",
		},
		{
			"name": "Rest Site",
			"desc": "Non-combat room that restores health before the next fight.",
		},
		{
			"name": "Boss",
			"desc": "Defeat the Warden to finish the run or enter endless scaling.",
		},
	]

static func _mutator_rows() -> Array[Dictionary]:
	return [
		{
			"name": "Blood Rush",
			"color": Color(0.95, 0.22, 0.28, 1.0),
			"icon": "res://assets/ui/mutators/blood_rush.svg",
			"desc": "Aggressive melee pace. Enemies hit harder and pressure up close.",
		},
		{
			"name": "Flashpoint",
			"color": Color(0.68, 0.40, 1.0, 1.0),
			"icon": "res://assets/ui/mutators/flashpoint.svg",
			"desc": "Faster enemy windups and tighter attack windows.",
		},
		{
			"name": "Siegebreak",
			"color": Color(0.96, 0.58, 0.18, 1.0),
			"icon": "res://assets/ui/mutators/siegebreak.svg",
			"desc": "Higher durability and frontline pressure from heavy units.",
		},
		{
			"name": "Iron Volley",
			"color": Color(0.32, 0.82, 0.56, 1.0),
			"icon": "res://assets/ui/mutators/iron_volley.svg",
			"desc": "Ranged enemies attack more often and punish open movement.",
		},
		{
			"name": "Killbox",
			"color": Color(0.98, 0.72, 0.2, 1.0),
			"icon": "res://assets/ui/mutators/killbox.svg",
			"desc": "Arena pressure rises over time; kiting space becomes risky.",
		},
	]

static func _color_hex(color: Color) -> String:
	return "#" + color.to_html(false)

static func _mutator_title_bbcode(row: Dictionary) -> String:
	var name := String(row.get("name", ""))
	var icon_path := String(row.get("icon", ""))
	var title := "[b]%s[/b]" % name
	if not icon_path.is_empty():
		title = "[img=16x16]%s[/img]  %s" % [icon_path, title]
	var color := row.get("color", Color(0.86, 0.94, 1.0, 1.0)) as Color
	return "[color=%s]%s[/color]" % [_color_hex(color), title]

static func glossary_bbcode() -> String:
	var lines: Array[String] = []
	lines.append("[center][b]Encounters[/b][/center]")
	for row in _encounter_rows():
		lines.append("[b]%s[/b]: %s" % [row.get("name", ""), row.get("desc", "")])
	lines.append("")
	lines.append("[center][b]Mutators[/b][/center]")
	for row in _mutator_rows():
		lines.append("%s: %s" % [_mutator_title_bbcode(row), row.get("desc", "")])
	return "\n".join(lines)
