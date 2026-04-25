extends Node

var world_root: Node2D
var player: Node2D
var rng: RandomNumberGenerator
var on_enemy_died: Callable

var scripts: Dictionary = {}
var current_room_size: Vector2 = Vector2.ZERO
var spawn_padding: float = 90.0
var spawn_safe_radius: float = 170.0
var current_room_enemy_mutator: Dictionary = {}

func initialize(world_root_node: Node2D, player_node: Node2D, rng_instance: RandomNumberGenerator, script_map: Dictionary, enemy_died_callback: Callable) -> void:
	world_root = world_root_node
	player = player_node
	rng = rng_instance
	scripts = script_map
	on_enemy_died = enemy_died_callback

func configure_room(room_size: Vector2, padding: float, safe_radius: float, enemy_mutator: Dictionary) -> void:
	current_room_size = room_size
	spawn_padding = padding
	spawn_safe_radius = safe_radius
	current_room_enemy_mutator = enemy_mutator

func spawn_profile_enemies(profile: Dictionary) -> int:
	var total := 0
	var chaser_count := int(profile.get("chaser_count", 0))
	var charger_count := int(profile.get("charger_count", 0))
	var archer_count := int(profile.get("archer_count", 0))
	var shielder_count := int(profile.get("shielder_count", 0))
	for _i in range(chaser_count):
		_spawn_enemy_in_current_room(scripts.get("chaser"))
		total += 1
	for _i in range(charger_count):
		_spawn_enemy_in_current_room(scripts.get("charger"))
		total += 1
	for _i in range(archer_count):
		_spawn_enemy_in_current_room(scripts.get("archer"))
		total += 1
	for _i in range(shielder_count):
		_spawn_enemy_in_current_room(scripts.get("shielder"))
		total += 1
	return total

func clear_all_enemies() -> void:
	if not is_instance_valid(world_root):
		return
	for enemy in world_root.get_tree().get_nodes_in_group("enemies"):
		if enemy is Node:
			(enemy as Node).queue_free()

func _spawn_enemy_in_current_room(enemy_script: Script) -> void:
	if enemy_script == null:
		return
	if not is_instance_valid(world_root):
		return
	var enemy := CharacterBody2D.new()
	enemy.set_script(enemy_script)
	_apply_enemy_mutator(enemy, enemy_script)

	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = CircleShape2D.new()
	collision_shape.shape.radius = 13.0
	enemy.add_child(collision_shape)

	enemy.global_position = _pick_spawn_position_in_current_room()
	world_root.add_child(enemy)
	enemy.set("target", player)
	if enemy.has_signal("died") and on_enemy_died.is_valid():
		enemy.died.connect(on_enemy_died)

func _apply_enemy_mutator(enemy: CharacterBody2D, enemy_script: Script) -> void:
	if current_room_enemy_mutator.is_empty():
		return

	if enemy_script == scripts.get("chaser"):
		var base_damage := int(enemy.get("attack_damage"))
		var damage_mult := float(current_room_enemy_mutator.get("chaser_damage_mult", 1.0))
		enemy.set("attack_damage", maxi(1, int(round(float(base_damage) * damage_mult))))

		var base_interval := float(enemy.get("attack_interval"))
		var interval_mult := float(current_room_enemy_mutator.get("chaser_attack_interval_mult", 1.0))
		enemy.set("attack_interval", maxf(0.2, base_interval * interval_mult))

		var base_speed := float(enemy.get("move_speed"))
		var speed_mult := float(current_room_enemy_mutator.get("chaser_speed_mult", 1.0))
		enemy.set("move_speed", maxf(25.0, base_speed * speed_mult))

	if enemy_script == scripts.get("charger"):
		var base_charge_damage := int(enemy.get("charge_damage"))
		var charge_damage_mult := float(current_room_enemy_mutator.get("charger_damage_mult", 1.0))
		enemy.set("charge_damage", maxi(1, int(round(float(base_charge_damage) * charge_damage_mult))))

		var base_charge_speed := float(enemy.get("charge_speed"))
		var charge_speed_mult := float(current_room_enemy_mutator.get("charger_speed_mult", 1.0))
		enemy.set("charge_speed", maxf(60.0, base_charge_speed * charge_speed_mult))

		var base_windup := float(enemy.get("windup_time"))
		var windup_mult := float(current_room_enemy_mutator.get("charger_windup_mult", 1.0))
		enemy.set("windup_time", maxf(0.2, base_windup * windup_mult))

	enemy.modulate = Color(1.0, 0.92, 0.92, 1.0)

func _pick_spawn_position_in_current_room() -> Vector2:
	if rng == null:
		return Vector2.ZERO
	var half := current_room_size * 0.5 - Vector2.ONE * spawn_padding
	var candidate := Vector2.ZERO
	for _try in range(60):
		candidate = Vector2(
			rng.randf_range(-half.x, half.x),
			rng.randf_range(-half.y, half.y)
		)
		if is_instance_valid(player) and candidate.distance_to(player.global_position) < spawn_safe_radius:
			continue
		return candidate
	return candidate
