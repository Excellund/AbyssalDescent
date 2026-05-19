extends RefCounted

class_name CharacterDefinition

const CharacterStatModifiers = preload("res://scripts/character_stat_modifiers.gd")
const CharacterVisualProfile = preload("res://scripts/character_visual_profile.gd")

var id: String = ""
var name: String = ""
var archetype: String = ""
var boss_opposition: String = ""
var tagline: String = ""
var lore: String = ""
var arcana_pool_key: String = ""
var passive_id: String = ""
var stat_modifiers: CharacterStatModifiers = CharacterStatModifiers.new()
var visual: CharacterVisualProfile = CharacterVisualProfile.new()
var design_lanes: Dictionary = {}

func _init(source: Dictionary = {}):
	var data := source.duplicate(true)
	id = String(data.get("id", "")).strip_edges().to_lower()
	name = String(data.get("name", "")).strip_edges()
	archetype = String(data.get("archetype", "")).strip_edges()
	boss_opposition = String(data.get("boss_opposition", "")).strip_edges()
	tagline = String(data.get("tagline", "")).strip_edges()
	lore = String(data.get("lore", "")).strip_edges()
	arcana_pool_key = String(data.get("arcana_pool_key", "")).strip_edges().to_lower()
	passive_id = String(data.get("passive_id", "")).strip_edges().to_lower()
	stat_modifiers = CharacterStatModifiers.new(data.get("stat_modifiers", {}))
	visual = CharacterVisualProfile.new(data.get("visual", {}))
	design_lanes = (data.get("design_lanes", {}) as Dictionary).duplicate(true)

func duplicate() -> CharacterDefinition:
	var copy = CharacterDefinition.new()
	copy.id = id
	copy.name = name
	copy.archetype = archetype
	copy.boss_opposition = boss_opposition
	copy.tagline = tagline
	copy.lore = lore
	copy.arcana_pool_key = arcana_pool_key
	copy.passive_id = passive_id
	copy.stat_modifiers = stat_modifiers.duplicate()
	copy.visual = visual.duplicate()
	copy.design_lanes = design_lanes.duplicate(true)
	return copy

func apply_color_variant(hue_shift: float, value_shift: float) -> void:
	visual.apply_color_variant(hue_shift, value_shift)
