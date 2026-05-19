extends RefCounted

class_name CharacterPackage

const CharacterDefinition = preload("res://scripts/character_definition.gd")
const DUPLICATE_VARIANT_HUE_SHIFTS_DEG := [0.0, 60.0, -60.0, 120.0, -120.0, 180.0, 90.0]
const DUPLICATE_VARIANT_VALUE_SHIFTS := [0.0, 0.08, -0.08, 0.14, -0.14, 0.18, -0.18]

var definition: CharacterDefinition
var variant_index: int = 0

func _init(definition: CharacterDefinition, variant_index: int = 0):
	self.definition = definition.duplicate()
	self.variant_index = variant_index
	_apply_variant()

func get_id() -> String:
	return definition.id

func get_name() -> String:
	return definition.name

func get_passive_id() -> String:
	return definition.passive_id

func get_stat_modifiers() -> CharacterStatModifiers:
	return definition.stat_modifiers

func get_visual() -> CharacterVisualProfile:
	return definition.visual

func _apply_variant() -> void:
	if variant_index <= 0:
		return
	var slot: int = clampi(variant_index, 0, DUPLICATE_VARIANT_HUE_SHIFTS_DEG.size() - 1)
	var hue_shift: float = float(DUPLICATE_VARIANT_HUE_SHIFTS_DEG[slot]) / 360.0
	var value_shift: float = float(DUPLICATE_VARIANT_VALUE_SHIFTS[slot])
	definition.apply_color_variant(hue_shift, value_shift)
