extends Node
class_name HealthState

signal health_changed(current_health: int, max_health: int)
signal died

@export var max_health: int = 100
var current_health: int = 100

func setup(initial_max_health: int, initial_current_health: int = -1) -> void:
	max_health = maxi(1, initial_max_health)
	if initial_current_health < 0:
		current_health = max_health
	else:
		current_health = clampi(initial_current_health, 0, max_health)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		died.emit()

func take_damage(amount: int) -> bool:
	if amount <= 0:
		return false
	return set_health(current_health - amount)

func heal(amount: int) -> bool:
	if amount <= 0:
		return false
	return set_health(current_health + amount)

func set_health(value: int) -> bool:
	var previous_health := current_health
	current_health = clampi(value, 0, max_health)
	if current_health == previous_health:
		return false
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		died.emit()
	return true

func is_dead() -> bool:
	return current_health <= 0