extends CharacterBody2D

@export var speed: float = 200.0

func _physics_process(_delta: float) -> void:
	# Uses Input Map actions so controls can be remapped in Project Settings.
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
