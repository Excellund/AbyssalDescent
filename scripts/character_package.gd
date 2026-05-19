extends RefCounted

class_name CharacterPackage

const CharacterDefinition = preload("res://scripts/character_definition.gd")

var definition: CharacterDefinition
var variant_index: int = 0

func _init(definition: CharacterDefinition, variant_index: int = 0):
	self.definition = definition.duplicate()
	self.variant_index = variant_index

func apply_variant():
	if variant_index > 0:
		var slot: int = variant_index
		var hue_shift: float = 0.0
		var value_shift: float = 0.0
		# Variant logic can be expanded here if needed
		# For now, just call the definition's color variant method if needed
		definition.apply_color_variant(hue_shift, value_shift)
