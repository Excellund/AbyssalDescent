extends RefCounted

const ENUMS := preload("res://scripts/shared/enums.gd")

class CharacterDefinition:
	var id: String = ""
	var name: String = ""
	var archetype: String = ""
	var boss_opposition: String = ""
	var tagline: String = ""
	var lore: String = ""
	var arcana_pool_key: String = ""
	var passive_id: String = ""
	var stat_modifiers: Dictionary = {}
	var visual: Dictionary = {}
	var design_lanes: Dictionary = {}

	func _init(source: Dictionary = {}) -> void:
		var data := source.duplicate(true)
		id = String(data.get("id", "")).strip_edges().to_lower()
		name = String(data.get("name", "")).strip_edges()
		archetype = String(data.get("archetype", "")).strip_edges()
		boss_opposition = String(data.get("boss_opposition", "")).strip_edges()
		tagline = String(data.get("tagline", "")).strip_edges()
		lore = String(data.get("lore", "")).strip_edges()
		arcana_pool_key = String(data.get("arcana_pool_key", "")).strip_edges().to_lower()
		passive_id = String(data.get("passive_id", "")).strip_edges().to_lower()
		stat_modifiers = (data.get("stat_modifiers", {}) as Dictionary).duplicate(true)
		visual = (data.get("visual", {}) as Dictionary).duplicate(true)
		design_lanes = (data.get("design_lanes", {}) as Dictionary).duplicate(true)

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"archetype": archetype,
			"boss_opposition": boss_opposition,
			"tagline": tagline,
			"lore": lore,
			"arcana_pool_key": arcana_pool_key,
			"passive_id": passive_id,
			"stat_modifiers": stat_modifiers.duplicate(true),
			"visual": visual.duplicate(true),
			"design_lanes": design_lanes.duplicate(true),
		}

const CHARACTER_DEFINITIONS := {
	ENUMS.CHARACTER_ID_BASTION: {
		"id": ENUMS.CHARACTER_ID_BASTION,
		"name": "Bastion",
		"archetype": "Iron Rampart",
		"boss_opposition": "Warden",
		"tagline": "Hold your ground, absorb pressure, and answer with decisive counters.",
		"lore": "Bastion is the teammate who stabilizes the fight when things get messy. They thrive in close pressure, absorb heavy pushes, and create safe windows for the squad to reset. Against the Warden, Bastion's job is simple: stop momentum and make every overcommit costly.",
		"arcana_pool_key": "bastion",
		"passive_id": ENUMS.PASSIVE_ID_IRON_RETORT,
		"stat_modifiers": {
			"max_health": 130,
			"max_speed": 188.0,
			"damage": 25,
			"attack_arc_degrees": 150.0,
			"dash_cooldown": 0.48,
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
		"tagline": "Break enemy setups with burst windows and smart area control.",
		"lore": "Hexweaver is all about control and timing. They reshape crowded fights, crack open defensive formations, and punish enemies that rely on fixed patterns. When the Sovereign tries to lock down space, Hexweaver turns that control back into opportunity.",
		"arcana_pool_key": "hexweaver",
		"passive_id": ENUMS.PASSIVE_ID_SIGIL_BURST,
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
		"tagline": "Set the pace with clean engages, fast exits, and precise finishers.",
		"lore": "Veilstrider rewards sharp decision-making. They dart in for high-value hits, disengage before retaliation, and keep encounters moving on their terms. Lacuna challenges that rhythm by denying clean timing, so mastering Veilstrider means staying composed under disrupted tempo.",
		"arcana_pool_key": "veilstrider",
		"passive_id": ENUMS.PASSIVE_ID_VEILSTEP_RHYTHM,
		"stat_modifiers": {
			"max_health": 70,
			"max_speed": 260.0,
			"damage": 22,
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
		"tagline": "Control distance, hold your angle, and punish anyone crossing your lane.",
		"lore": "Riftlancer shines when positioning is deliberate. They create strong firing lanes, pressure from range, and force enemies to take bad paths. Mirror Hunt tries to overwhelm that focus with decoys and cross pressure, so Riftlancer play is about discipline: hold the true line and commit at the right moment.",
		"design_lanes": {
			"survivability": "Stabilize by maintaining farline spacing and denying contact collapse.",
			"expression": "Pre-aim lane control and strike only when enemies enter the precision band.",
			"mastery": "Route fights so chained farline punctures keep pressure without losing distance discipline."
		},
		"arcana_pool_key": "riftlancer",
		"passive_id": ENUMS.PASSIVE_ID_FARLINE_FOCUS,
		"stat_modifiers": {
			"max_health": 64,
			"max_speed": 228.0,
			"damage": 20,
			"attack_range": 132.0,
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

static func _normalize_character_id(character_id: String) -> String:
	return character_id.strip_edges().to_lower()

static func _fallback_passive_id_for_character(character_id: String) -> String:
	match _normalize_character_id(character_id):
		ENUMS.CHARACTER_ID_BASTION:
			return ENUMS.PASSIVE_ID_IRON_RETORT
		ENUMS.CHARACTER_ID_HEXWEAVER:
			return ENUMS.PASSIVE_ID_SIGIL_BURST
		ENUMS.CHARACTER_ID_VEILSTRIDER:
			return ENUMS.PASSIVE_ID_VEILSTEP_RHYTHM
		ENUMS.CHARACTER_ID_RIFTLANCER:
			return ENUMS.PASSIVE_ID_FARLINE_FOCUS
		_:
			return ""

static func is_known_character_id(character_id: String) -> bool:
	return CHARACTER_DEFINITIONS.has(_normalize_character_id(character_id))

##
# Returns a deep copy of the character data for the given character_id.
# The returned Dictionary is always safe to mutate.
static func get_character(character_id: String) -> Dictionary:
	var key: String = _normalize_character_id(character_id)
	if not CHARACTER_DEFINITIONS.has(key):
		key = DEFAULT_CHARACTER_ID
	return (CHARACTER_DEFINITIONS.get(key, {}) as Dictionary).duplicate(true)

static func get_character_definition(character_id: String) -> CharacterDefinition:
	return CharacterDefinition.new(get_character(character_id))

static func get_launch_characters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for character_id in LAUNCH_CHARACTER_IDS:
		result.append(get_character(String(character_id)))
	return result

static func get_launch_character_definitions() -> Array[CharacterDefinition]:
	var result: Array[CharacterDefinition] = []
	for character_id in LAUNCH_CHARACTER_IDS:
		result.append(get_character_definition(String(character_id)))
	return result

static func get_character_name(character_id: String) -> String:
	var definition := get_character_definition(character_id)
	if not definition.name.is_empty():
		return definition.name
	return _normalize_character_id(character_id).capitalize()

static func get_character_passive_id(character_id: String) -> String:
	var definition := get_character_definition(character_id)
	if not definition.passive_id.is_empty() and definition.passive_id != "passive":
		return definition.passive_id
	return _fallback_passive_id_for_character(character_id)

static func get_character_stat_modifiers(character_id: String) -> Dictionary:
	return get_character_definition(character_id).stat_modifiers.duplicate(true)

static func get_character_visual(character_id: String) -> Dictionary:
	return get_character_definition(character_id).visual.duplicate(true)

const DUPLICATE_VARIANT_HUE_SHIFTS_DEG := [0.0, 60.0, -60.0, 120.0, -120.0, 180.0, 90.0]
const DUPLICATE_VARIANT_VALUE_SHIFTS := [0.0, 0.08, -0.08, 0.14, -0.14, 0.18, -0.18]

##
# Returns a deep copy of `character_data` with its visual color fields shifted in HSV.
# The returned Dictionary is always safe to mutate. Variant 0 returns a copy with no color shift.
static func apply_duplicate_color_variant(character_data: Dictionary, variant_index: int) -> Dictionary:
	var shifted_data: Dictionary = character_data.duplicate(true)
	if not character_data.has("visual"):
		return shifted_data
	if variant_index <= 0:
		return shifted_data
	var slot: int = clampi(variant_index, 0, DUPLICATE_VARIANT_HUE_SHIFTS_DEG.size() - 1)
	var hue_shift: float = float(DUPLICATE_VARIANT_HUE_SHIFTS_DEG[slot]) / 360.0
	var value_shift: float = float(DUPLICATE_VARIANT_VALUE_SHIFTS[slot])
	var visual: Dictionary = (shifted_data.get("visual", {}) as Dictionary).duplicate(true)
	for key in visual.keys():
		var color_value = visual[key]
		if color_value is Color:
			visual[key] = _shift_color_hsv(color_value, hue_shift, value_shift)
	shifted_data["visual"] = visual
	return shifted_data

static func _shift_color_hsv(source_color: Color, hue_shift: float, value_shift: float) -> Color:
	var hue: float = fposmod(source_color.h + hue_shift, 1.0)
	var saturation: float = source_color.s
	var value: float = clampf(source_color.v + value_shift, 0.0, 1.0)
	var shifted := Color.from_hsv(hue, saturation, value, source_color.a)
	return shifted
