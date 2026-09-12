extends RefCounted

const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const KEYWORDS := preload("res://scripts/shared/combat_keyword_catalogue.gd")
const PASSIVES := preload("res://scripts/shared/character_passive_catalogue.gd")
const CHARACTERS := preload("res://scripts/character_registry.gd")

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
			"desc": "Learn movement, dash, attack and build view on your first descent.",
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
			"desc": "Ranged pressure and flankers. Use offset cover to break firing lanes.",
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
			"desc": "Shielders defend a broken ring of cover. Move through its gaps.",
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
			"desc": "A shielded formation advances. Take a forked route around it.",
		},
		{
			"name": "Ambush",
			"group": "Advanced",
			"color": Color(1.0, 0.58, 0.52, 1.0),
			"desc": "Enemies surround you. Use side cover to escape through the open center.",
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
			"desc": "Acts 2–3: escape Drifter ring gaps while melee enemies pursue you.",
		},
		{
			"name": "Breach",
			"group": "Advanced",
			"color": Color(0.56, 0.9, 0.76, 1.0),
			"desc": "Acts 2–3: warded foes survive at 1 HP. Kill/push the Keeper or break links with cover.",
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
			"name": "Apex Breakwater",
			"group": "Trial",
			"color": Color(1.0, 0.66, 0.38, 1.0),
			"desc": "Bait the ram into terrain to break Return Tide; otherwise enter its calm wake.\nHarbor Gate commits an opening where each player stands, then crosses the arena.\nHold the opening and pursue Breakwater after the crest passes.",
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
			"desc": "Clear the kill quota as pulses change enemy status.",
		},
		{
			"name": "Intercept Run",
			"group": "Objective",
			"color": Color(0.62, 0.88, 1.0, 1.0),
			"desc": "Escort a drone across the room; enemies near it slow its progress.",
		},
		{
			"name": "Relic Recovery",
			"group": "Objective",
			"color": Color(0.62, 0.88, 1.0, 1.0),
			"desc": "Walk over three relics and carry them to the central receiver.\nEach living player carries one; entering the receiver delivers it.\nFirst pickups summon reinforcements. A fallen carrier drops their relic.",
		},
		{
			"name": "Rest Site",
			"group": "Special",
			"color": Color(0.64, 1.0, 0.76, 1.0),
			"desc": "Choose healing or an upgrade to a Boon you already own.\nUp to two eligible Boons are offered, keeping their normal limits.\nChoosing an upgrade replaces this visit's healing.",
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
		{
			"name": "Kilnheart", "group": "Boss", "color": Color(1.0, 0.55, 0.22, 1.0),
			"desc": "First boss alternative. Dodge furnace blasts and marked ground.",
		},
		{
			"name": "Glassweaver", "group": "Boss", "color": Color(0.4, 0.87, 1.0, 1.0),
			"desc": "Second boss alternative. Find safe spaces between crossing lanes.",
		},
		{
			"name": "The Null Archivist", "group": "Boss", "color": Color(0.79, 0.59, 1.0, 1.0),
			"desc": "Final boss alternative. Leave disks, then return to their safe centers.",
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
			"desc": "Nearby enemies grant damage resistance, up to 30%.",
		},
		{
			"name": "Overcharge",
			"color": Color(1.0, 0.9, 0.4, 1.0),
			"icon": "res://assets/ui/mutators/overcharge.svg",
			"desc": KEYWORDS.format_text("Temporary boost: {kw:attack} and {kw:dash} cooldowns x0.80 for 3 room clears."),
		},
	]

static func _reward_rows() -> Array[Dictionary]:
	return [
		{
			"tier": "BOON",
			"color": RARITY_COMMON,
			"desc": "Generic permanent increases to damage, movement or survival.",
		},
		{
			"tier": "MISSION",
			"color": RARITY_RARE,
			"desc": "A permanent Boon plus a temporary boost lasting 3 room clears.",
		},
		{
			"tier": "ARCANA",
			"color": RARITY_EPIC,
			"desc": "Build-defining powers. Repeat picks level them up; mastery unlocks one Prismatic pick.",
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
	var rows: Array[Dictionary] = []
	for biome_id: String in BIOMES.BIOME_DEFINITIONS:
		var biome := BIOMES.get_biome(biome_id)
		var identity := BIOMES.get_combat_identity(biome_id)
		var rule := String(identity.rule)
		if biome_id == "shatterfield":
			rule = rule.replace(". ", ".\n")
		rows.append({
			"name": biome.name,
			"act": biome.act,
			"color": biome.color_theme.accent,
			"desc": KEYWORDS.format_text(rule + "\n" + BIOMES.get_effect_text(biome_id).replace(". ", ".\n") + "\n" + String(identity.tactic) + ("\nWithout cracked cover, warned fragment falls hurt you and foes.\nChecked-shield HELP fragment falls affect foes only." if biome_id == "shatterfield" else ""))
		})
	return rows

static func _biomes_section_bbcode() -> String:
	var lines: Array[String] = []
	lines.append(_section_title_bbcode("Biomes"))
	lines.append("Each biome changes every combat route with terrain or an effect you can use against foes.\nThe rules below describe ordinary rooms.")
	lines.append("Hover the biome name in the HUD for its current rule. Checked shields mean HELP;\ntriangles with ! mean DANGER. The HUD names targets, the active effect and its phase.\nA warning is preparation time: the effect starts when it ends.")
	lines.append("Breach, Undertow, Missions and Trials keep their arenas and add smaller, slower patterns\naround required objectives. If space is too tight, checked-shield HELP affects foes only.")
	lines.append("Boss and Apex arenas use checked-shield HELP that affects foes only.\nEnemy ability warnings remain dangerous. Biome effects pause during rewards and introductions;\nRest Sites and the tutorial are calm.")
	lines.append("")
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

## Ordinary foes and support specialists. Apex encounters keep their own rules
## in Encounters; these entries describe the normal, unmodified enemy behavior.
static func _enemy_rows() -> Array[Dictionary]:
	return [
		{
			"id": "chaser", "name": "Chaser", "group": "Close pressure",
			"read": "Closes directly and strikes repeatedly at close range.",
			"response": "Keep an exit open; step out of reach before a pack surrounds you.",
		},
		{
			"id": "charger", "name": "Charger", "group": "Close pressure",
			"read": "Shows a straight lane, then rushes along that fixed direction.",
			"response": "Step sideways out of the lane, then use its recovery to deal damage.",
		},
		{
			"id": "lurker", "name": "Lurker", "group": "Close pressure",
			"read": "Pauses near you, keeps aiming, then commits to a quick pounce.",
			"response": "Move across its path as it lunges; the pause still tracks you.",
		},
		{
			"id": "ram", "name": "Ram", "group": "Close pressure",
			"read": "Chains three short charges, aiming again between each rush.",
			"response": "Keep moving through the whole sequence. Strike after the last rush.",
		},
		{
			"id": "spectre", "name": "Spectre", "group": "Close pressure",
			"read": "Predicts your movement, commits its blink, then warns a forward strike.",
			"response": "Change course after the blink target settles; leave the strike lane.",
		},
		{
			"id": "archer", "name": "Archer", "group": "Ranged pressure",
			"read": "Keeps its distance and fires three arrows along one locked aim.",
			"response": "Move across the aim line or use solid cover to stop the arrows.",
		},
		{
			"id": "lancer", "name": "Lancer", "group": "Ranged pressure",
			"read": "Aims ahead of your facing; its bolt leaves a damaging floor zone.",
			"response": "Leave the marked landing point and avoid the zone until it expires.",
		},
		{
			"id": "drifter", "name": "Drifter", "group": "Ranged pressure",
			"read": "Sends expanding rings of pellets, each with one broad gap.",
			"response": "Find the gap in each new wave; the next ring can open elsewhere.",
		},
		{
			"id": "pyre", "name": "Pyre", "group": "Dangerous ground",
			"read": "Pursues you in melee and leaves an expanding fire zone when killed.",
			"response": "Leave room to retreat from the corpse; its fire keeps dealing damage.",
		},
		{
			"id": "weaver", "name": "Weaver", "group": "Dangerous ground",
			"read": "Stops and fires webs outward, leaving damaging zones where they land.",
			"response": "Move away during its windup, then steer around the scattered web zones.",
		},
		{
			"id": "tether", "name": "Tether", "group": "Dangerous ground",
			"read": "Pairs with another Tether, then warns and sweeps a damaging beam.",
			"response": "Leave the space between the pair. Defeating either end breaks the beam.",
		},
		{
			"id": "sentinel", "name": "Sentinel", "group": "Dangerous ground",
			"read": "Slowly advances while a damaging cone rotates around its body.",
			"response": "Follow behind the sweep or move beyond its reach; the cone is active.",
		},
		{
			"id": "shielder", "name": "Shielder", "group": "Protection",
			"read": "Its turning shield reduces damage from the front. It warns a nearby slam.",
			"response": "Circle to an exposed side and leave the slam ring before it strikes.",
		},
		{
			"id": "keeper", "name": "Keeper", "group": "Protection",
			"read": "Wards up to two nearby allies. They resist damage and survive at 1 HP.",
			"response": "Defeat the Keeper or break its links with solid cover.\nThen finish the exposed allies before it can ward them again.",
		},
	]

static func _enemies_section_bbcode() -> String:
	var lines: Array[String] = [
		_section_title_bbcode("Enemy Field Guide"),
		"Read the threat, then choose your opening. These are ordinary enemy patterns;",
		"Mutators can change their pressure. Find Apex rules under Encounters.",
		"",
	]
	var rows := _enemy_rows()
	for group_name in ["Close pressure", "Ranged pressure", "Dangerous ground", "Protection"]:
		lines.append(_subsection_title_bbcode(group_name))
		for row in rows:
			if row.group != group_name:
				continue
			lines.append("[b]%s[/b]" % row.name)
			lines.append(KEYWORDS.format_text(row.read))
			lines.append("[color=#BFD2E8]%s[/color]" % KEYWORDS.format_text(row.response))
			lines.append("")
	return "\n".join(lines)

## Use the same definitions and restrained semantic styling as power details.
static func _build_keywords_section_bbcode() -> String:
	var lines: Array[String] = [_section_title_bbcode("Build Keywords"), ""]
	for id: String in KEYWORDS.KEYWORDS:
		if KEYWORDS.PLAIN_TERMS.has(id):
			continue
		lines.append("%s  [color=#BFD2E8]—[/color]  %s" % [KEYWORDS.keyword_bbcode(id), KEYWORDS.KEYWORDS[id].definition])
	return "\n".join(lines)

static func _character_passives_section_bbcode() -> String:
	var lines: Array[String] = [_section_title_bbcode("Character Passives"), ""]
	for character: Dictionary in CHARACTERS.get_launch_characters():
		var id := String(character.passive_id)
		lines.append("[b]%s — %s[/b]" % [character.name, PASSIVES.get_display_name(id)])
		lines.append(PASSIVES.get_description(id))
		lines.append("")
	return "\n".join(lines)

static func _endgame_chase_section_bbcode() -> String:
	return "\n".join([
		_section_title_bbcode("Endgame Chase"), "",
		"[b]Ascension[/b] — Forsworn-only modifiers that raise your run's rank.",
		"[b]Oaths[/b] — Run goals that unlock Catalysts or Ascension modifiers.",
		"[b]Catalysts[/b] — Character bonuses equipped before starting a run.",
	])

static func glossary_sections() -> Array[Dictionary]:
	return [
		{"label": "Reward Tiers", "bbcode": _reward_tiers_section_bbcode()},
		{"label": "Build Keywords", "bbcode": _build_keywords_section_bbcode()},
		{"label": "Character Passives", "bbcode": _character_passives_section_bbcode()},
		{"label": "Enemy Field Guide", "bbcode": _enemies_section_bbcode()},
		{"label": "Encounters", "bbcode": _encounters_section_bbcode()},
		{"label": "Biomes", "bbcode": _biomes_section_bbcode()},
		{"label": "Mutators", "bbcode": _mutators_section_bbcode()},
		{"label": "Endgame Chase", "bbcode": _endgame_chase_section_bbcode()},
	]

static func glossary_bbcode() -> String:
	var parts: Array[String] = []
	for s in glossary_sections():
		parts.append(s["bbcode"])
	return "\n\n".join(parts)
