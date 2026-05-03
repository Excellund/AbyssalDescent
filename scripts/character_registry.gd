extends RefCounted

const ENUMS := preload("res://scripts/shared/enums.gd")

const CHARACTER_DEFINITIONS := {
	ENUMS.CHARACTER_ID_BASTION: {
		"id": ENUMS.CHARACTER_ID_BASTION,
		"name": "Bastion",
		"archetype": "Iron Rampart",
		"boss_opposition": "Warden",
		"tagline": "Break brute force with iron poise and punish windows.",
		"lore": "The Bastion was forged from crushed vows at the pit rim. Every charge that would shatter lesser steel only sharpens their resolve. Where the Warden advances, the Bastion plants ground and breaks momentum.",
		"arcana_pool_key": "bastion",
		"passive_id": "iron_retort",
		"stat_modifiers": {
			"max_health": 130,
			"max_speed": 180.0,
			"damage": 24,
			"attack_arc_degrees": 150.0,
			"dash_cooldown": 0.52,
			"iron_skin_armor": 1
		},
		"visual": {
			"body_color": Color(0.46, 0.62, 0.82, 1.0),
			"core_color": Color(0.22, 0.38, 0.62, 1.0),
			"glow_color": Color(0.10, 0.18, 0.42, 0.16),
			"speed_arc_color": Color(0.42, 0.62, 0.88, 0.26),
			"dash_phase_color": Color(0.40, 0.60, 1.00, 0.24),
			"dash_streak_color": Color(0.40, 0.62, 0.95, 0.20)
		}
	},
	ENUMS.CHARACTER_ID_HEXWEAVER: {
		"id": ENUMS.CHARACTER_ID_HEXWEAVER,
		"name": "Hexweaver",
		"archetype": "Fracture Mage",
		"boss_opposition": "Sovereign",
		"tagline": "Unmake control fields with volatile sigils and burst timing.",
		"lore": "Hexweavers read the abyss as grammar, then overwrite its rules. They fracture gravitational prisons and turn rigid patterns into openings. The Sovereign commands order; the Hexweaver answers with collapse.",
		"arcana_pool_key": "hexweaver",
		"passive_id": "sigil_burst",
		"stat_modifiers": {
			"max_health": 75,
			"max_speed": 210.0,
			"damage": 28,
			"attack_range": 90.0,
			"attack_cooldown": 0.22,
			"dash_cooldown": 0.54
		},
		"visual": {
			"body_color": Color(0.72, 0.26, 0.96, 1.0),
			"core_color": Color(0.46, 0.08, 0.72, 1.0),
			"glow_color": Color(0.28, 0.06, 0.42, 0.16),
			"speed_arc_color": Color(0.72, 0.42, 1.00, 0.26),
			"dash_phase_color": Color(0.80, 0.50, 1.00, 0.24),
			"dash_streak_color": Color(0.78, 0.50, 1.00, 0.20)
		}
	},
	ENUMS.CHARACTER_ID_VEILSTRIDER: {
		"id": ENUMS.CHARACTER_ID_VEILSTRIDER,
		"name": "Veilstrider",
		"archetype": "Riftbound Blade",
		"boss_opposition": "Lacuna",
		"tagline": "Dictate tempo through execution pressure and precise disengage.",
		"lore": "Veilstriders walk the seam between heartbeat and silence. They do not win by force but by ending turns before they begin. Where Lacuna claims the missing beat between breaths, the Veilstrider exists to sever that silence and reclaim tempo.",
		"arcana_pool_key": "veilstrider",
		"passive_id": "death_tempo",
		"stat_modifiers": {
			"max_health": 70,
			"max_speed": 260.0,
			"damage": 18,
			"dash_cooldown": 0.30,
			"attack_cooldown": 0.24
		},
		"visual": {
			"body_color": Color(0.14, 0.94, 0.62, 1.0),
			"core_color": Color(0.06, 0.56, 0.38, 1.0),
			"glow_color": Color(0.04, 0.32, 0.22, 0.16),
			"speed_arc_color": Color(0.26, 0.96, 0.66, 0.26),
			"dash_phase_color": Color(0.24, 1.00, 0.72, 0.24),
			"dash_streak_color": Color(0.24, 0.96, 0.66, 0.20)
		}
	},
	ENUMS.CHARACTER_ID_RIFTLANCER: {
		"id": ENUMS.CHARACTER_ID_RIFTLANCER,
		"name": "Riftlancer",
		"archetype": "Farline Harpoon",
		"boss_opposition": "Mirror Hunt",
		"tagline": "Skewer from the seam where distance becomes certainty.",
		"lore": "Riftlancers bind abyssal anchors to a single line, then force the world to answer through that seam. They do not brawl for ground; they draft kill corridors and punish any step into them. Where Mirror Hunt multiplies false targets and punishes linear commitment, the Riftlancer survives by mastering one true lane and breaking the reflection before it closes.",
		"design_lanes": {
			"survivability": "Stabilize by maintaining farline spacing and denying contact collapse.",
			"expression": "Pre-aim lane control and strike only when enemies enter the precision band.",
			"mastery": "Route fights so chained farline punctures keep pressure without losing distance discipline."
		},
		"arcana_pool_key": "riftlancer",
		"passive_id": "farline_focus",
		"stat_modifiers": {
			"max_health": 64,
			"max_speed": 228.0,
			"damage": 20,
			"attack_range": 190.0,
			"attack_arc_degrees": 16.0,
			"attack_cooldown": 0.26,
			"dash_cooldown": 0.44
		},
		"visual": {
			"body_color": Color(0.90, 0.78, 0.28, 1.0),
			"core_color": Color(0.52, 0.40, 0.08, 1.0),
			"glow_color": Color(0.38, 0.26, 0.08, 0.16),
			"speed_arc_color": Color(1.00, 0.84, 0.34, 0.26),
			"dash_phase_color": Color(1.00, 0.90, 0.56, 0.24),
			"dash_streak_color": Color(1.00, 0.78, 0.30, 0.20)
		}
	}
}

const DEFAULT_CHARACTER_ID := ENUMS.CHARACTER_ID_BASTION
const LAUNCH_CHARACTER_IDS := [
	ENUMS.CHARACTER_ID_BASTION,
	ENUMS.CHARACTER_ID_HEXWEAVER,
	ENUMS.CHARACTER_ID_VEILSTRIDER,
	ENUMS.CHARACTER_ID_RIFTLANCER
]

static func get_launch_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in LAUNCH_CHARACTER_IDS:
		ids.append(String(id))
	return ids

static func get_default_character_id() -> String:
	return DEFAULT_CHARACTER_ID

static func is_known_character_id(character_id: String) -> bool:
	return CHARACTER_DEFINITIONS.has(character_id.strip_edges().to_lower())

static func get_character(character_id: String) -> Dictionary:
	var key: String = character_id.strip_edges().to_lower()
	if not CHARACTER_DEFINITIONS.has(key):
		key = DEFAULT_CHARACTER_ID
	return (CHARACTER_DEFINITIONS.get(key, {}) as Dictionary).duplicate(true)

static func get_launch_characters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for character_id in LAUNCH_CHARACTER_IDS:
		result.append(get_character(String(character_id)))
	return result
