extends "res://scripts/player.gd"
## Training-only immunity leaves all normal combat/action processing enabled.
var practice_invulnerable := false

func take_damage(amount: int, context: Dictionary = {}) -> void:
	if not practice_invulnerable:
		super.take_damage(amount, context)
