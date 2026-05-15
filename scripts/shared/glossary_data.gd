extends RefCounted

const RARITY_COMMON := Color(0.62, 0.7, 0.8, 0.9)
const RARITY_RARE := Color(0.46, 0.78, 1.0, 0.94)
const RARITY_EPIC := Color(0.82, 0.58, 1.0, 0.96)
const RARITY_LEGENDARY := Color(1.0, 0.74, 0.42, 1.0)

static func _encounter_rows() -> Array[Dictionary]:
	return [
		{
			"name": "Tutorial",
			"group": "Special",
			"color": Color(0.56, 0.84, 1.0, 1.0),
			"desc": "One-time first-descent room that teaches movement, dash, attack, and build view.",
		},
		{
			"name": "Skirmish",
			"group": "Core",
			"color": Color(0.66, 0.9, 1.0, 1.0),
			"desc": "Chargers lead the hunt. Stay mobile or get run down.",
		},
		{
			"name": "Crossfire",
			"group": "Core",
			"color": Color(1.0, 0.78, 0.48, 1.0),
			"desc": "Ranged units pin you while flankers close the distance.",
		},
		{
			"name": "Onslaught",
			"group": "Core",
			"color": Color(1.0, 0.5, 0.42, 1.0),
			"desc": "Pure melee flood. Enemies close from all sides.",
		},
		{
			"name": "Fortress",
			"group": "Core",
			"color": Color(0.72, 0.9, 1.0, 1.0),
			"desc": "Shielders block every approach. Find the gap or create one.",
		},
		{
			"name": "Blitz",
			"group": "Advanced",
			"color": Color(1.0, 0.66, 0.4, 1.0),
			"desc": "High-speed assault. Hesitation is punished.",
		},
		{
			"name": "Suppression",
			"group": "Advanced",
			"color": Color(0.96, 0.64, 1.0, 1.0),
			"desc": "Lancers carpet the floor with zones. Archers punish any open ground.",
		},
		{
			"name": "Vanguard",
			"group": "Advanced",
			"color": Color(0.72, 0.88, 1.0, 1.0),
			"desc": "Shielded enemies advance in formation. Break the line to move forward.",
		},
		{
			"name": "Ambush",
			"group": "Advanced",
			"color": Color(1.0, 0.58, 0.52, 1.0),
			"desc": "Enemies cut off exits and converge from multiple angles.",
		},
		{
			"name": "Gauntlet",
			"group": "Advanced",
			"color": Color(1.0, 0.82, 0.54, 1.0),
			"desc": "Every enemy role at once. No single counter works.",
		},
		{
			"name": "Convergence",
			"group": "Advanced",
			"color": Color(0.5, 0.96, 0.86, 1.0),
			"desc": "Spectres target where you're heading. Pressure closes from every direction.",
		},
		{
			"name": "Trial",
			"group": "Trial",
			"color": Color(1.0, 0.66, 0.52, 1.0),
			"desc": "Standard encounter with an added enemy mutator. Harder, with a better reward.",
		},
		{
			"name": "Apex Seamlock",
			"group": "Trial",
			"color": Color(0.96, 0.54, 0.34, 1.0),
			"desc": "Elite Seamlock. Anchors lanes and punishes retreating in straight lines.",
		},
		{
			"name": "Apex Mirrorline",
			"group": "Trial",
			"color": Color(0.78, 0.92, 1.0, 1.0),
			"desc": "Elite Mirrorline. Splits into a second seam at half health and briefly resists damage. Burst it before the split.",
		},
		{
			"name": "Apex Toll",
			"group": "Trial",
			"color": Color(1.0, 0.74, 0.32, 1.0),
			"desc": "Elite altar. Outer aura slows you; periodic pulses deal damage. Interrupt self-heals by entering the inner ring when it channels.",
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
			"name": "Circuit Sweep",
			"group": "Objective",
			"color": Color(0.62, 1.0, 0.62, 1.0),
			"desc": "Three signal nodes appear one at a time. Stand inside each node's zone to capture it before the timer runs out.",
		},
		{
			"name": "Pulse Window",
			"group": "Objective",
			"color": Color(1.0, 0.9, 0.4, 1.0),
			"desc": "Every few seconds a pulse fires and randomly applies a mode to all enemies: SURGE (enemies run faster), EXPOSED (enemies take more damage), or SLOWED (enemies slowed). Adapt to each mode and kill the quota.",
		},
		{
			"name": "Intercept Run",
			"group": "Objective",
			"color": Color(0.62, 0.88, 1.0, 1.0),
			"desc": "A drone travels across the room. Keep its path clear — enemies that reach it stall its progress. Escort it to the far side to win.",
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
			"desc": "Aggressive boss that chains charges, area blasts, and wide cleaves.",
		},
		{
			"name": "Sovereign",
			"group": "Boss",
			"color": Color(1.0, 0.58, 0.48, 1.0),
			"desc": "Control boss with delayed attacks. Move unpredictably.",
		},
		{
			"name": "Lacuna",
			"group": "Boss",
			"color": Color(0.46, 1.0, 0.82, 1.0),
			"desc": "Final boss. Cuts escape routes and suppresses dashes.",
		},
	]

static func _mutator_rows() -> Array[Dictionary]:
	return [
		{
			"name": "Blood Rush",
			"color": Color(0.95, 0.22, 0.28, 1.0),
			"icon": "res://assets/ui/mutators/blood_rush.svg",
			"desc": "Enemies hit harder at close range. Melee exchanges are more dangerous.",
		},
		{
			"name": "Flashpoint",
			"color": Color(0.68, 0.40, 1.0, 1.0),
			"icon": "res://assets/ui/mutators/flashpoint.svg",
			"desc": "Enemies attack faster with tighter windows to dodge.",
		},
		{
			"name": "Siegebreak",
			"color": Color(0.96, 0.58, 0.18, 1.0),
			"icon": "res://assets/ui/mutators/siegebreak.svg",
			"desc": "Heavy enemies are tougher and push harder at the front.",
		},
		{
			"name": "Iron Volley",
			"color": Color(0.32, 0.82, 0.56, 1.0),
			"icon": "res://assets/ui/mutators/iron_volley.svg",
			"desc": "Ranged enemies fire more often. Open space is risky.",
		},
		{
			"name": "Phase Collapse",
			"color": Color(0.34, 0.96, 0.82, 1.0),
			"icon": "res://assets/ui/mutators/convergence.svg",
			"desc": "Spectres target where you're heading. Move unpredictably to avoid them.",
		},
		{
			"name": "Conflagration",
			"color": Color(1.0, 0.48, 0.18, 1.0),
			"icon": "res://assets/ui/mutators/conflagration.svg",
			"desc": "Pyres leave fire zones when killed. Clearing fast creates hazards.",
		},
		{
			"name": "Tether Web",
			"color": Color(0.34, 0.84, 1.0, 1.0),
			"icon": "res://assets/ui/mutators/tether_web.svg",
			"desc": "Tethers spawn sentries that block lanes with crossing beams.",
		},
		{
			"name": "Killbox",
			"color": Color(0.98, 0.72, 0.2, 1.0),
			"icon": "res://assets/ui/mutators/killbox.svg",
			"desc": "Arena pressure grows over time. Stalling shrinks your safe space.",
		},
		{
			"name": "Surge",
			"color": Color(0.54, 0.92, 0.72, 1.0),
			"icon": "res://assets/ui/mutators/surge.svg",
			"desc": "Enemies move faster and converge on active capture points.",
		},
		{
			"name": "Fortified",
			"color": Color(0.76, 0.82, 0.98, 1.0),
			"icon": "res://assets/ui/mutators/fortified.svg",
			"desc": "Player buff for objective rooms. Reduces incoming damage.",
		},
		{
			"name": "Hunter's Focus",
			"color": Color(0.98, 0.76, 0.34, 1.0),
			"icon": "res://assets/ui/mutators/hunters_focus.svg",
			"desc": "Player buff for objective rooms. Increases damage output.",
		},
		{
			"name": "Combo Relay",
			"color": Color(0.98, 0.72, 0.3, 1.0),
			"icon": "res://assets/ui/mutators/combo_relay.svg",
			"desc": "Player buff for objective rooms. Consecutive kills build damage momentum.",
		},
		{
			"name": "Relay Boost",
			"color": Color(0.62, 1.0, 0.62, 1.0),
			"icon": "res://assets/ui/mutators/relay_boost.svg",
			"desc": "Killing an enemy triggers a brief speed surge, letting you chase down the next target or dash to a node.",
		},
		{
			"name": "Node Shield",
			"color": Color(0.46, 0.86, 1.0, 1.0),
			"icon": "res://assets/ui/mutators/node_shield.svg",
			"desc": "Each nearby enemy (within 180px) grants +6% damage resistance, up to a maximum of 30%. Standing your ground while intercepting clusters earns more protection.",
		},
		{
			"name": "Overcharge",
			"color": Color(1.0, 0.9, 0.4, 1.0),
			"icon": "",
			"desc": "Kill chains charge your weapon (up to 5 stacks, +10% damage each). Reach max charge to enter CHARGED state. Your next kill discharges a nova burst that damages nearby enemies and resets to 2 stacks. Stacks decay by 2 if the chain breaks.",
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
			"desc": "Earned from objective rooms. Stronger upgrades than standard boons.",
		},
		{
			"tier": "ARCANA",
			"color": RARITY_EPIC,
			"desc": "Earned from trial rooms. Rare powers that grow stronger each time you pick them.",
		},
		{
			"tier": "BOSS",
			"color": RARITY_LEGENDARY,
			"desc": "Earned from boss clears. Unique, high-impact powers.",
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
	return "[font_size=20][center][b]%s[/b][/center][/font_size]" % title

static func _subsection_title_bbcode(title: String) -> String:
	return "[font_size=18][color=#8EA8C0][b]%s[/b][/color][/font_size]" % title

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
	return "[font_size=18][color=#9EC9E8][b]%s[/b][/color] [color=#7F96AE]-[/color] [color=%s][b][%s][/b][/color][/font_size]" % [title, _color_hex(tier_color), reward_tier]

static func glossary_bbcode() -> String:
	var lines: Array[String] = []
	lines.append(_section_title_bbcode("Reward Tiers"))
	for row in _reward_rows():
		lines.append("%s  [color=#BFD2E8]-[/color]  %s" % [_reward_tier_title_bbcode(row), row.get("desc", "")])
	lines.append("")
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
	lines.append("")
	lines.append(_section_title_bbcode("Mutators"))
	for row in _mutator_rows():
		lines.append("%s: %s" % [_mutator_title_bbcode(row), row.get("desc", "")])
	lines.append("")
	lines.append("")
	lines.append(_section_title_bbcode("New Enemies"))
	lines.append("[color=#86C8E0][b]Drifter[/b][/color]  [color=#BFD2E8]-[/color]  Slow pursuer that periodically emits expanding rings of projectile nodes. Each ring has one gap — find it or take the hit.")
	lines.append("[color=#B08AE8][b]Weaver[/b][/color]  [color=#BFD2E8]-[/color]  Aggressive rusher that closes in, stops, then fires a radial burst outward from its own feet. Escape past the ring radius before the windup completes.")
	lines.append("[color=#A4C85A][b]Sentinel[/b][/color]  [color=#BFD2E8]-[/color]  Near-stationary enemy that sweeps a rotating cone of danger. Staying inside the arc takes repeated tick damage.")
	lines.append("")
	lines.append("")
	lines.append(_section_title_bbcode("Endgame Chase"))
	lines.append("[font_size=18][color=#F0C060][b]Ascension[/b][/color][/font_size]")
	lines.append("[color=#BFD2E8][indent]Stack modifiers above Forsworn to raise your rank. Each modifier adds heat; your highest cleared rank is tracked per character. Some require Oaths to unlock.[/indent][/color]")
	lines.append("")
	lines.append("[font_size=18][color=#60D0A0][b]Oaths[/b][/color][/font_size]")
	lines.append("[color=#BFD2E8][indent]Run goals that unlock rewards. Types: bearing clears, no-hit boss kills, no-boon/no-arcana runs, and Ascension rank targets. Completing one grants a Catalyst, a modifier, or both.[/indent][/color]")
	lines.append("")
	lines.append("[font_size=18][color=#80C0F0][b]Catalysts[/b][/color][/font_size]")
	lines.append("[color=#BFD2E8][indent]Per-character bonuses equipped before a run. Examples: extra arcana slot, reroll, +20 max HP, door reveal. Free to use; shown on the leaderboard with your rank.[/indent][/color]")
	return "\n".join(lines)
