extends RefCounted

const RARITY_COMMON := Color(0.62, 0.7, 0.8, 0.9)
const RARITY_RARE := Color(0.46, 0.78, 1.0, 0.94)
const RARITY_EPIC := Color(0.82, 0.58, 1.0, 0.96)
const RARITY_LEGENDARY := Color(1.0, 0.74, 0.42, 1.0)

static func _encounter_rows() -> Array[Dictionary]:
	return [
		{
			"name": "Skirmish",
			"group": "Core",
			"color": Color(0.62, 0.86, 1.0, 1.0),
			"desc": "Balanced warm-up fight with mixed pressure.",
		},
		{
			"name": "Pursuit",
			"group": "Core",
			"color": Color(0.66, 0.9, 1.0, 1.0),
			"desc": "Early hunt pattern built around charger-led chase pressure.",
		},
		{
			"name": "Crossfire",
			"group": "Core",
			"color": Color(1.0, 0.78, 0.48, 1.0),
			"desc": "Ranged firing line with flanking disruption.",
		},
		{
			"name": "Onslaught",
			"group": "Core",
			"color": Color(1.0, 0.5, 0.42, 1.0),
			"desc": "Melee flood: relentless close-range pressure.",
		},
		{
			"name": "Fortress",
			"group": "Core",
			"color": Color(0.72, 0.9, 1.0, 1.0),
			"desc": "Defensive wall built around shielders.",
		},
		{
			"name": "Blitz",
			"group": "Advanced",
			"color": Color(1.0, 0.66, 0.4, 1.0),
			"desc": "Fast assault. Hesitation gets punished.",
		},
		{
			"name": "Suppression",
			"group": "Advanced",
			"color": Color(0.96, 0.64, 1.0, 1.0),
			"desc": "Lancer zone saturation. Archers reinforce the denial field.",
		},
		{
			"name": "Vanguard",
			"group": "Advanced",
			"color": Color(0.72, 0.88, 1.0, 1.0),
			"desc": "Shielded advance and structured frontline push.",
		},
		{
			"name": "Ambush",
			"group": "Advanced",
			"color": Color(1.0, 0.58, 0.52, 1.0),
			"desc": "Predator pack that collapses escape routes.",
		},
		{
			"name": "Gauntlet",
			"group": "Advanced",
			"color": Color(1.0, 0.82, 0.54, 1.0),
			"desc": "Mixed-threat test of every enemy role.",
		},
		{
			"name": "Convergence",
			"group": "Advanced",
			"color": Color(0.5, 0.96, 0.86, 1.0),
			"desc": "Spectres predict escape routes while pursuit pressure collapses the seam.",
		},
		{
			"name": "Trial",
			"group": "Trial",
			"color": Color(1.0, 0.66, 0.52, 1.0),
			"desc": "Hard variant with an enemy mutator.",
		},
		{
			"name": "Apex Seamlock",
			"group": "Trial",
			"color": Color(0.96, 0.54, 0.34, 1.0),
			"desc": "Elite anchor lord. Lane-control pressure punishes linear retreat.",
		},
		{
			"name": "Apex Mirrorline",
			"group": "Trial",
			"color": Color(0.78, 0.92, 1.0, 1.0),
			"desc": "Elite seam-walker. Below half health it sunders — a perpendicular twin seam appears and it briefly resists damage while the second seam comes online. Burst it before the split.",
		},
		{
			"name": "Apex Toll",
			"group": "Trial",
			"color": Color(1.0, 0.74, 0.32, 1.0),
			"desc": "Stationary elite. It rings a telegraphed expanding ring that always heals it. Caught inside the ring at trigger? You eat a heavy slow. Step out before it resolves to deny the slow, but it still pays itself. Stay close enough during the brief exposed window to land bonus damage. Pulses a short repulse so you can't stack on top.",
		},
		{
			"name": "Last Stand",
			"group": "Objective",
			"color": Color(1.0, 0.8, 0.5, 1.0),
			"desc": "Survive the timer, then clear the kill quota.",
		},
		{
			"name": "Cut the Signal",
			"group": "Objective",
			"color": Color(1.0, 0.86, 0.58, 1.0),
			"desc": "Hunt the marked target as it relocates.",
		},
		{
			"name": "Hold the Line",
			"group": "Objective",
			"color": Color(1.0, 0.82, 0.52, 1.0),
			"desc": "Control the center zone long enough to secure it under pressure.",
		},
		{
			"name": "Rest Site",
			"group": "Special",
			"color": Color(0.64, 1.0, 0.76, 1.0),
			"desc": "Non-combat room that restores health.",
		},
		{
			"name": "Warden",
			"group": "Boss",
			"color": Color(1.0, 0.68, 0.54, 1.0),
			"desc": "Relentless bruiser that chains charge, nova, and cleave pressure.",
		},
		{
			"name": "Sovereign",
			"group": "Boss",
			"color": Color(1.0, 0.58, 0.48, 1.0),
			"desc": "Cosmic control boss that punishes predictable movement lanes.",
		},
		{
			"name": "Lacuna",
			"group": "Boss",
			"color": Color(0.46, 1.0, 0.82, 1.0),
			"desc": "Final boss that severs tempo and traps escape seams with silence pressure.",
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
			"name": "Phase Collapse",
			"color": Color(0.34, 0.96, 0.82, 1.0),
			"icon": "res://assets/ui/mutators/convergence.svg",
			"desc": "Spectres collapse future positions and punish predictable movement.",
		},
		{
			"name": "Conflagration",
			"color": Color(1.0, 0.48, 0.18, 1.0),
			"icon": "res://assets/ui/mutators/conflagration.svg",
			"desc": "Pyres seed lingering burn zones that turn careless clears into traps.",
		},
		{
			"name": "Tether Web",
			"color": Color(0.34, 0.84, 1.0, 1.0),
			"icon": "res://assets/ui/mutators/tether_web.svg",
			"desc": "Tethers multiply into linked sentries that flood lanes with cross-beam denial.",
		},
		{
			"name": "Killbox",
			"color": Color(0.98, 0.72, 0.2, 1.0),
			"icon": "res://assets/ui/mutators/killbox.svg",
			"desc": "Arena pressure rises over time; kiting space becomes risky.",
		},
		{
			"name": "Fortified",
			"color": Color(0.76, 0.82, 0.98, 1.0),
			"icon": "res://assets/ui/mutators/fortified.svg",
			"desc": "Objective mutator that hardens the player against incoming punishment.",
		},
		{
			"name": "Hunter's Focus",
			"color": Color(0.98, 0.76, 0.34, 1.0),
			"icon": "res://assets/ui/mutators/hunters_focus.svg",
			"desc": "Objective mutator that sharpens the player's offensive pressure.",
		},
		{
			"name": "Combo Relay",
			"color": Color(0.98, 0.72, 0.3, 1.0),
			"icon": "res://assets/ui/mutators/combo_relay.svg",
			"desc": "Objective mutator that builds kill-chain momentum before the relay breaks.",
		},
	]

static func _reward_rows() -> Array[Dictionary]:
	return [
		{
			"tier": "BOON",
			"color": RARITY_COMMON,
			"desc": "Standard room reward. Choose one core power upgrade.",
		},
		{
			"tier": "MISSION",
			"color": RARITY_RARE,
			"desc": "Objective reward tier. Higher-impact upgrade path for run momentum.",
		},
		{
			"tier": "ARCANA",
			"color": RARITY_EPIC,
			"desc": "Trial reward tier. Rare arcana powers that stack through the run.",
		},
		{
			"tier": "BOSS",
			"color": RARITY_LEGENDARY,
			"desc": "Boss reward tier. Unique major powers earned from boss clears.",
		},
		{
			"tier": "NONE",
			"color": RARITY_COMMON,
			"desc": "No immediate reward card.",
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

static func _encounter_title_bbcode(row: Dictionary) -> String:
	var name := String(row.get("name", ""))
	var color := row.get("color", Color(0.9, 0.96, 1.0, 1.0)) as Color
	return "[color=%s][b]%s[/b][/color]" % [_color_hex(color), name]

static func _reward_tier_title_bbcode(row: Dictionary) -> String:
	var tier := String(row.get("tier", ""))
	var color := row.get("color", Color(0.9, 0.96, 1.0, 1.0)) as Color
	return "[color=%s][b]%s[/b][/color]" % [_color_hex(color), tier]

static func _section_title_bbcode(title: String) -> String:
	return "[center][b]%s[/b][/center]" % title

static func _subsection_title_bbcode(title: String) -> String:
	return "[color=#8EA8C0][b]%s[/b][/color]" % title

static func _encounter_group_header_bbcode(group_name: String) -> String:
	var reward_tier := "BOON"
	var tier_color := RARITY_COMMON
	match group_name:
		"Objective":
			reward_tier = "MISSION"
			tier_color = RARITY_RARE
		"Trial":
			reward_tier = "ARCANA"
			tier_color = RARITY_EPIC
		"Boss":
			reward_tier = "BOSS"
			tier_color = RARITY_LEGENDARY
		"Special":
			reward_tier = "NONE"
			tier_color = RARITY_COMMON
		_:
			reward_tier = "BOON"
			tier_color = RARITY_COMMON
	var title := "%s Encounter" % group_name
	return "[color=#9EC9E8][b]%s[/b][/color] [color=#7F96AE]-[/color] [color=%s][b][%s][/b][/color]" % [title, _color_hex(tier_color), reward_tier]

static func glossary_bbcode() -> String:
	var lines: Array[String] = []
	lines.append(_section_title_bbcode("Reward Tiers"))
	for row in _reward_rows():
		lines.append("%s  [color=#BFD2E8]-[/color]  %s" % [_reward_tier_title_bbcode(row), row.get("desc", "")])
	lines.append("")
	lines.append(_section_title_bbcode("Encounters"))
	var encounter_groups: Array[String] = ["Core", "Advanced", "Objective", "Trial", "Special", "Boss"]
	for group_name in encounter_groups:
		lines.append(_encounter_group_header_bbcode(group_name))
		for row in _encounter_rows():
			if String(row.get("group", "")) != group_name:
				continue
			lines.append("%s  [color=#BFD2E8]-[/color]  %s" % [_encounter_title_bbcode(row), row.get("desc", "")])
		lines.append("")
	lines.append(_section_title_bbcode("Mutators"))
	for row in _mutator_rows():
		lines.append("%s: %s" % [_mutator_title_bbcode(row), row.get("desc", "")])
	lines.append("")
	lines.append(_section_title_bbcode("Endgame Chase"))
	lines.append(_subsection_title_bbcode("Ascension"))
	lines.append("[color=#BFD2E8]Stack difficulty modifiers above Forsworn for higher leaderboard standing. Each modifier adds heat (rank); your highest cleared rank is recorded per character. Some modifiers are gated behind Oaths.[/color]")
	lines.append(_subsection_title_bbcode("Oaths"))
	lines.append("[color=#BFD2E8]Specific run goals: per-character bearing clears, no-hit boss kills, no-boon and no-arcana clears, and reaching higher Ascension ranks. Completing an Oath unlocks a Catalyst, an Ascension modifier, or both.[/color]")
	lines.append(_subsection_title_bbcode("Catalysts"))
	lines.append("[color=#BFD2E8]Pre-run augments equipped per-character. Free to equip but disclosed on the leaderboard alongside your Ascension rank. Examples: extra arcana slot, shop reroll, +20 max HP, door reveal.[/color]")
	return "\n".join(lines)
