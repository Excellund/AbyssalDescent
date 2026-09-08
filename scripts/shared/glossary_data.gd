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
			"desc": "Ranged units pin you while flankers close the distance. Offset cover can break firing lanes without sealing the center.",
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
			"desc": "Shielders block every approach. A broken ring of cover offers gaps to cross or grapple through.",
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
			"desc": "Shielded enemies advance in formation. Forked cover can split your approach around the line.",
		},
		{
			"name": "Ambush",
			"group": "Advanced",
			"color": Color(1.0, 0.58, 0.52, 1.0),
			"desc": "Enemies cut off exits and converge from multiple angles. Side cover gives escape routes around an open center.",
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
			"name": "Undertow",
			"group": "Advanced",
			"color": Color(0.42, 0.88, 0.92, 1.0),
			"desc": "Appears in Acts 2 and 3. Drifters release staggered rings; find each gap while chasers keep you moving. At most two Drifters are active.",
		},
		{
			"name": "Breach",
			"group": "Advanced",
			"color": Color(0.56, 0.9, 0.76, 1.0),
			"desc": "Acts 2 and 3: one vulnerable Keeper partially protects a small firing line. Cross the open center, use cover to break ward links, or launch the Keeper. Clear the room for a normal reward.",
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
			"desc": "Splits at half health and briefly resists damage. Burst it before the split.",
		},
		{
			"name": "Apex Toll",
			"group": "Trial",
			"color": Color(1.0, 0.74, 0.32, 1.0),
			"desc": "Outer aura slows you; pulses deal damage. Enter the inner ring to interrupt its self-heal.",
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
			"desc": "Capture three nodes in sequence. Stand in each zone before time runs out.",
		},
		{
			"name": "Pulse Window",
			"group": "Objective",
			"color": Color(1.0, 0.9, 0.4, 1.0),
			"desc": "Periodic pulses apply SURGE, EXPOSED, or SLOWED to all enemies. Kill the quota through each shift.",
		},
		{
			"name": "Intercept Run",
			"group": "Objective",
			"color": Color(0.62, 0.88, 1.0, 1.0),
			"desc": "Escort a drone to the far side. Kill enemies before they reach it and stall its progress.",
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
			"desc": "Kills trigger a brief speed surge. Reposition or close on a node quickly.",
		},
		{
			"name": "Node Shield",
			"color": Color(0.46, 0.86, 1.0, 1.0),
			"icon": "res://assets/ui/mutators/node_shield.svg",
			"desc": "Nearby enemies grant stacking damage resistance, up to 30%. Stay close to clusters to earn more.",
		},
		{
			"name": "Overcharge",
			"color": Color(1.0, 0.9, 0.4, 1.0),
			"icon": "res://assets/ui/mutators/overcharge.svg",
			"desc": "Kill chains build weapon charge (5 stacks). At max, your next kill fires a nova burst and resets to 2 stacks.",
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

static func _biome_title_bbcode(row: Dictionary) -> String:
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

static func _reward_tiers_section_bbcode() -> String:
	var lines: Array[String] = []
	lines.append(_section_title_bbcode("Reward Tiers"))
	for row in _reward_rows():
		lines.append("%s  [color=#BFD2E8]-[/color]  %s" % [_reward_tier_title_bbcode(row), row.get("desc", "")])
	return "\n".join(lines)

static func _encounters_section_bbcode() -> String:
	var lines: Array[String] = []
	lines.append(_section_title_bbcode("Encounters"))
	var encounter_groups: Array[String] = ["Core", "Advanced", "Objective", "Trial", "Special", "Boss"]
	for group_name in encounter_groups:
		lines.append(_encounter_group_header_bbcode(group_name))
		for row in _encounter_rows():
			if String(row.get("group", "")) != group_name:
				continue
			lines.append("%s  [color=#BFD2E8]-[/color]  %s" % [_encounter_title_bbcode(row), row.get("desc", "")])
		lines.append("")
	return "\n".join(lines)

static func _biome_rows() -> Array[Dictionary]:
	return [
		{
			"name": "The Crumble",
			"act": 1,
			"color": Color(1.0, 0.68, 0.22, 1.0),
			"desc": "Chargers and Shielders dominate. Expect melee-forward pressure with strong frontline formations.",
		},
		{
			"name": "The Haunt",
			"act": 1,
			"color": Color(0.78, 0.44, 1.0, 1.0),
			"desc": "Lurkers, Spectres, and Seamlocks cut off retreats. Ambush and disorientation define the threat.",
		},
		{
			"name": "The Shatterfield",
			"act": 1,
			"color": Color(0.44, 0.92, 1.0, 1.0),
			"desc": "Ranged harassment and zone hazards. Archers and Lancers punish any open ground.",
		},
		{
			"name": "The Grinding Vault",
			"act": 2,
			"color": Color(0.96, 0.88, 0.42, 1.0),
			"desc": "Mirrorlines and Sentinels hold every lane. Suppression and control define each room.",
		},
		{
			"name": "The Storm Reach",
			"act": 2,
			"color": Color(1.0, 0.66, 0.24, 1.0),
			"desc": "Fire zones and suppression fill the field. Pyres and Tethers deny any safe position.",
		},
		{
			"name": "The Hollow",
			"act": 2,
			"color": Color(0.32, 0.86, 0.82, 1.0),
			"desc": "Seamlocks, Lurkers, and Weavers converge. Nothing moves in a straight line.",
		},
		{
			"name": "The Void Breach",
			"act": 3,
			"color": Color(0.96, 0.24, 0.32, 1.0),
			"desc": "Spectres and Pyres at overwhelming density. No angle stays safe.",
		},
		{
			"name": "The Maelstrom",
			"act": 3,
			"color": Color(1.0, 0.92, 0.38, 1.0),
			"desc": "Every enemy type at full strength. The full arsenal, unrestricted.",
		},
		{
			"name": "The Convergence",
			"act": 3,
			"color": Color(0.88, 0.96, 1.0, 1.0),
			"desc": "Tethers, Lancers, and Sentinels lock down all movement. Area denial closes every gap.",
		},
	]

static func _biomes_section_bbcode() -> String:
	var lines: Array[String] = []
	lines.append(_section_title_bbcode("Biomes"))
	for act in [1, 2, 3]:
		lines.append(_subsection_title_bbcode("Act %d" % act))
		for row in _biome_rows():
			if int(row.get("act", 0)) != act:
				continue
			lines.append("%s  [color=#BFD2E8]-[/color]  %s" % [_biome_title_bbcode(row), row.get("desc", "")])
		lines.append("")
	return "\n".join(lines)

static func _mutators_section_bbcode() -> String:
	var lines: Array[String] = []
	lines.append(_section_title_bbcode("Mutators"))
	for row in _mutator_rows():
		lines.append("%s: %s" % [_mutator_title_bbcode(row), row.get("desc", "")])
	return "\n".join(lines)

static func _motion_arcana_section_bbcode() -> String:
	var lines: Array[String] = [_section_title_bbcode("Motion Arcana")]
	lines.append("[b]Blast Drive[/b]")
	lines.append("Tap Attack to strike immediately. Hold Attack for at least 0.25 seconds, then release a short, narrow cone forward and launch backward. Charge for 0.65 seconds for full power.")
	lines.append("The blast covers a 70-degree cone. At level 1, charging increases reach from 100 to 160 and damage from 150% to 250% of Damage. Level 2 multiplies damage and reach by 1.15; level 3 by 1.30; Prismatic by 1.56.")
	lines.append("Level 2 stores two blasts; each charge returns after 1.8 seconds. Level 3 lets movement keys steer the recoil.")
	lines.append("")
	lines.append("[b]Razor Orbit[/b]")
	lines.append("Tap Dash for your normal dash. To orbit, aim at a nearby foe first, then hold Dash through the normal dash. The highlighted target is remembered while you move. If no target is highlighted, aim at a foe during the dash.")
	lines.append("Keep holding Dash to orbit and cut. Your entry dash chooses the circling direction, which stays fixed until you detach. Attack still works. Release Dash to launch along your orbit.")
	lines.append("At level 1, hook foes within 260. Each cut deals 35% of Damage, at most once per enemy every 0.3 seconds. An orbit lasts up to 1.4 seconds; a level 3 transfer can extend the whole sequence to 2.4 seconds. Cards show cut damage and hook reach; Blast cards show full-charge damage and reach.")
	lines.append("Level 2 can also anchor to columns. At level 3, keep holding and aim at another foe when your anchor dies to transfer once.")
	lines.append("")
	lines.append("Release a charged Blast Drive while orbiting to detach with explosive recoil. Starting a new dash cancels a held blast charge. Each Arcana level increases its damage and reach; Prismatic strengthens both again.")
	lines.append("")
	lines.append("[b]Returning Crescent[/b]")
	lines.append("Attack throws a blade alongside your strike. It flies outward, then returns toward your current position. Move or dash to pull the return path across another part of the room.")
	lines.append("At level 1, the blade travels up to 220 and deals 45% of Damage each way. An enemy can be struck once on the outward flight and once on return. One blade can be active; level 2 allows two.")
	lines.append("Level 3 lets each blade bounce once off a wall or column on its outward flight. A blocked return dissolves. Each level adds 15% of base damage and reach; Prismatic strengthens both by another 20%.")
	return "\n".join(lines)


static func _endgame_chase_section_bbcode() -> String:
	var lines: Array[String] = []
	lines.append(_section_title_bbcode("Endgame Chase"))
	lines.append("[font_size=18][color=#F0C060][b]Ascension[/b][/color][/font_size]")
	lines.append("[color=#BFD2E8][indent]Stack modifiers above Forsworn to raise your rank. Each modifier adds heat; your highest cleared rank is tracked per character. Some require Oaths to unlock.[/indent][/color]")
	lines.append("")
	lines.append("[font_size=18][color=#60D0A0][b]Oaths[/b][/color][/font_size]")
	lines.append("[color=#BFD2E8][indent]Run goals that unlock rewards. Types: bearing clears, no-hit boss kills, no-boon/no-arcana runs, and Ascension rank targets. Completing one grants a Catalyst, a modifier, or both.[/indent][/color]")
	lines.append("")
	lines.append("[font_size=18][color=#80C0F0][b]Catalysts[/b][/color][/font_size]")
	lines.append("[color=#BFD2E8][indent]Per-character bonuses equipped before a run, such as Prismatic Arcana, Reward Reroll, and Iron Vigil's +20 max HP. Free to use; shown on the leaderboard with your rank.[/indent][/color]")
	return "\n".join(lines)

static func _boss_combinations_section_bbcode() -> String:
	var lines: Array[String] = [_section_title_bbcode("Boss Combinations")]
	lines.append("[b]Ruinous Impact[/b]")
	lines.append("Direct strikes launch enemies. A launched foe bursts when it hits another enemy, a wall or a column. Existing pushes and pulls can also start a launch, including Blast Drive, Lacuna Echo, Edict of the Court and Null Corridor.")
	lines.append("Bosses and Apex enemies instead compress and burst in place, preserving their attacks. Each enemy can launch once every 1.1 seconds. Level 1 bursts deal 100% of Damage in a radius of 70; level 2 raises these to 140% and 95.")
	lines.append("")
	lines.append("[b]Sovereign's Double[/b]")
	lines.append("Completing a dash, Blast Drive recoil or Razor Orbit leaves one shade for 4 seconds. It appears where you last made contact during that movement, or where you started if there was no contact.")
	lines.append("Your next deliberate melee attack or charged blast repeats from the shade at 55% damage. Attack reach and strike bonuses carry through, including Razor Wind, Execution Edge and Blood Vow. Level 2 allows two echoes. Further movement replaces the shade; automatic orbit cuts leave its echoes ready.")
	lines.append("Phantom Step helps place the shade among enemies. Reaper Step refreshes your dash on kills, giving you another chance to place it.")
	return "\n".join(lines)

static func _keeper_section_bbcode() -> String:
	var lines: Array[String] = [_section_title_bbcode("Keeper")]
	lines.append("A Keeper links to at most two nearby ordinary allies, reducing their damage taken by 30%. The links and marked allies show who is protected. Wards never heal or grant immunity, and the Keeper itself remains vulnerable.")
	lines.append("Kill or launch the Keeper to interrupt its links. Cover or distance also breaks a link and creates a brief opening before it can return. Bosses, Apex enemies and other Keepers cannot be warded; multiple wards never stack.")
	return "\n".join(lines)

static func glossary_sections() -> Array[Dictionary]:
	return [
		{"label": "Reward Tiers", "bbcode": _reward_tiers_section_bbcode()},
		{"label": "Motion Arcana", "bbcode": _motion_arcana_section_bbcode()},
		{"label": "Boss Combinations", "bbcode": _boss_combinations_section_bbcode()},
		{"label": "Encounters", "bbcode": _encounters_section_bbcode()},
		{"label": "Keeper", "bbcode": _keeper_section_bbcode()},
		{"label": "Biomes", "bbcode": _biomes_section_bbcode()},
		{"label": "Mutators", "bbcode": _mutators_section_bbcode()},
		{"label": "Endgame Chase", "bbcode": _endgame_chase_section_bbcode()},
	]

static func glossary_bbcode() -> String:
	var parts: Array[String] = []
	for s in glossary_sections():
		parts.append(s["bbcode"])
	return "\n\n".join(parts)
