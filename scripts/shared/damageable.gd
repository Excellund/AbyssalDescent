extends RefCounted

# Shared helper to enforce the take_damage contract consistently.
static func can_take_damage(target: Object) -> bool:
	return is_instance_valid(target)

static func apply_damage(target: Object, amount: int, damage_context: Dictionary = {}) -> bool:
	if amount <= 0:
		return false
	if not can_take_damage(target):
		return false
	if damage_context.is_empty():
		target.take_damage(amount)
	else:
		target.take_damage(amount, damage_context)
	return true
