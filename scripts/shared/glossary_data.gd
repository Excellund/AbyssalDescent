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
			"desc": "Bait a wall charge, leave the marked lane, then punish its recovery.",
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
		rows.append({
			"name": biome.name,
			"act": biome.act,
			"color": biome.color_theme.accent,
			"desc": KEYWORDS.format_text(String(identity.rule) + "\n" + String(identity.tactic))
		})
	return rows

static func _biomes_section_bbcode() -> String:
	var lines: Array[String] = []
	lines.append(_section_title_bbcode("Biomes"))
	lines.append("Each biome favors its own encounter styles and enemy mix. Terrain below shapes ordinary rooms.")
	lines.append("Breach, Undertow, Missions, Trials, Apex rooms and bosses keep their own arenas.")
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

## Use the same definitions and restrained semantic styling as power details.
static func _build_keywords_section_bbcode() -> String:
	var lines: Array[String] = [_section_title_bbcode("Build Keywords"), ""]
	for id: String in KEYWORDS.KEYWORDS:
		if KEYWORDS.PLAIN_TERMS.has(id):
			continue
		lines.append("%s  [color=#BFD2E8]—[/color]  %s" % [KEYWORDS.keyword_bbcode(id), KEYWORDS.KEYWORDS[id].definition])
	return "\n".join(lines)

static func _power_rules_section_bbcode() -> String:
	var rows: Array[Dictionary] = [
		{"name": "Blast Drive", "rule": "Hold Attack, then release a blast that propels you backward.", "detail": "Charge: 0.25–0.65s. Level 2: two charges. Level 3: steer recoil."},
		{"name": "Razor Orbit", "rule": "Aim and hold Dash to circle a foe for up to 1.4s; release to depart.", "detail": "Level 2: hook columns. Level 3: transfer once when the anchor dies (2.4s total)."},
		{"name": "Returning Crescent", "rule": "Attack throws a blade; move to guide its return through foes.", "detail": "Hits once each way. Level 2: two blades. Level 3: one outward bounce."},
		{"name": "Static Wake", "rule": "Dash leaves up to two Electric Fields; overlapping trails share damage.", "detail": "Only Dash draws trails. Damage scales with contact time. Level 3: Slow after damage."},
		{"name": "Hunter's Snare", "rule": "Attack hits Slow foes; bonus damage requires an already Slowed foe.", "detail": "Level 1: Attack damage. Level 2: all damage. Level 3: double your Slow durations."},
		{"name": "Wraithstep", "rule": "Dash Marks foes. At level 2, Attack hits on Marked foes release a Burst.", "detail": "One Burst per Attack. Level 3 continues through up to three more Marked foes."},
		{"name": "Eclipse Mark", "rule": "Kills Mark nearby foes. Damage does not spend a Mark."},
		{"name": "Dread Resonance", "rule": "Attack hits Mark and build damage stacks against that foe.", "detail": "Once per foe per Attack. Stacks clear when you or the foe dies, or the room ends."},
		{"name": "Storm Crown", "rule": "Dealing damage charges chain lightning; each foe counts once per action.", "detail": "One chain per action; never charges itself. Level 2: one extra jump through a Slowed foe."},
		{"name": "Ruinous Impact", "rule": "Attack hits and eligible Pushes or Pulls arm a Launch that bursts on Impact.", "detail": "Bosses and Apex foes compress in place. Impact bursts cannot cause another Launch."},
		{"name": "Sovereign's Double", "rule": "Dash, Recoil or Orbit completion leaves a shade that Echoes your Attack.", "detail": "Echoes deal 55% damage. Level 2: two Echoes. Further movement replaces the shade."},
		{"name": "Warden's Verdict", "rule": "Consecutive attack hits grow stronger; every fourth triggers a Burst.", "detail": "Resets after 2.2s without an attack hit. The same foe can count on later Attacks."},
		{"name": "Sovereign Tempo", "rule": KEYWORDS.format_text("{kw:attack_hit|Attack hits} or your damage against already {kw:mark|Marked} foes build temporary move speed.\nFinishing {kw:dash}, {kw:recoil} or {kw:orbit} spends all stacks in a {kw:burst}."), "detail": KEYWORDS.format_text("One stack per original action across all foes, ticks and descendants.\nUp to six stacks; expire 1.8s after the last accepted stack.\nThe target must be {kw:mark|Marked} before damage.\nAccepted {kw:burst} damage refunds 0.12s of {kw:dash} cooldown per spent stack,\nonce per {kw:burst}; the {kw:burst} and its descendants cannot build Tempo.")},
		{"name": "Pillar Convergence", "rule": KEYWORDS.format_text("{kw:attack_hit|Attack hits} or your {kw:electric} damage charge a pulsing {kw:field} that follows you."), "detail": KEYWORDS.format_text("One charge per original action across all foes, ticks and descendants.\nCharging pauses while the {kw:field} is active.\nAn action that qualifies during this window cannot charge it later,\neven with delayed damage after the {kw:field} ends.\nLevel 1: four charges, 1.60s duration and 0.25s pulses.\nLevel 2: two charges, 1.99s duration and 0.19s pulses.")},
		{"name": "Sigil Chain", "rule": "Four attack hits arm a Field; a later Attack hit places it.", "detail": "Level 2: Slow. Level 3: stronger chains. Hexweaver's passive Burst detonates sigils."},
		{"name": "Farline Volley", "rule": "Outer attack hits add arc and damage per stack; Dash clears the stacks.", "detail": "Level 2: Slow from 2 stacks (4 Prismatic). Level 3: Dash bursts only at full stacks."},
		{"name": "Conditional Boons", "rule": "Bonuses scale with the damage source, Field contact time and Echo strength.", "detail": "Conditions apply once per target; copied damage never doubles the same bonus."},
	]
	var lines: Array[String] = [_section_title_bbcode("Power Rules"), ""]
	for row in rows:
		lines.append("[b]%s[/b]  [color=#BFD2E8]—[/color]  %s" % [row.name, row.rule])
		if row.has("detail"):
			lines.append("[color=#9BAFC4]%s[/color]" % row.detail)
		lines.append("")
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
		{"label": "Power Rules", "bbcode": _power_rules_section_bbcode()},
		{"label": "Character Passives", "bbcode": _character_passives_section_bbcode()},
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
