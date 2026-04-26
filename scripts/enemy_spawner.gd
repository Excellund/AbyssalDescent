extends Node

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

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
	var chaser_count := ENCOUNTER_CONTRACTS.profile_chaser_count(profile)
	var charger_count := ENCOUNTER_CONTRACTS.profile_charger_count(profile)
	var archer_count := ENCOUNTER_CONTRACTS.profile_archer_count(profile)
	var shielder_count := ENCOUNTER_CONTRACTS.profile_shielder_count(profile)
	var lurker_count := int(profile.get("lurker_count", 0))
	var ram_count := int(profile.get("ram_count", 0))
	var lancer_count := int(profile.get("lancer_count", 0))
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
	for _i in range(lurker_count):
		_spawn_enemy_in_current_room(scripts.get("lurker"))
		total += 1
	for _i in range(ram_count):
		_spawn_enemy_in_current_room(scripts.get("ram"))
		total += 1
	for _i in range(lancer_count):
		_spawn_enemy_in_current_room(scripts.get("lancer"))
		total += 1
	return total

func clear_all_enemies() -> void:
	if not is_instance_valid(world_root):
		return
	for enemy in world_root.get_tree().get_nodes_in_group("enemies"):
		if enemy is Node:
			(enemy as Node).queue_free()

func spawn_enemy_type(enemy_type: String, count: int = 1) -> int:
	var enemy_script: Script = scripts.get(enemy_type)
	if enemy_script == null:
		return 0
	var spawned := 0
	for _i in range(maxi(0, count)):
		if _spawn_enemy_in_current_room(enemy_script) != null:
			spawned += 1
	return spawned

func spawn_enemy_node_type(enemy_type: String, min_player_distance: float = -1.0) -> CharacterBody2D:
	var enemy_script: Script = scripts.get(enemy_type)
	if enemy_script == null:
		return null
	return _spawn_enemy_in_current_room(enemy_script, min_player_distance)

func pick_room_position(min_player_distance: float = -1.0, min_enemy_spacing: float = 86.0) -> Vector2:
	return _pick_spawn_position_in_current_room(min_player_distance, min_enemy_spacing)

func _spawn_enemy_in_current_room(enemy_script: Script, min_player_distance: float = -1.0) -> CharacterBody2D:
	if enemy_script == null:
		return null
	if not is_instance_valid(world_root):
		return null
	var enemy := CharacterBody2D.new()
	enemy.set_script(enemy_script)
	_apply_enemy_mutator(enemy, enemy_script)

	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = CircleShape2D.new()
	collision_shape.shape.radius = 13.0
	enemy.add_child(collision_shape)

	enemy.global_position = _pick_spawn_position_in_current_room(min_player_distance)
	world_root.add_child(enemy)
	enemy.set("target", player)
	if enemy.get("arena_size") != null:
		enemy.set("arena_size", current_room_size)
	if enemy.has_signal("died") and on_enemy_died.is_valid():
		enemy.died.connect(on_enemy_died)
	return enemy

func _apply_enemy_mutator(enemy: CharacterBody2D, enemy_script: Script) -> void:
	if current_room_enemy_mutator.is_empty():
		return
	var is_affected: bool = false
	var enemy_health_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ENEMY_HEALTH_MULT, 1.0)
	if not is_equal_approx(enemy_health_mult, 1.0):
		if enemy.get("max_health") != null:
			var base_max_health := int(enemy.get("max_health"))
			enemy.set("max_health", maxi(1, int(round(float(base_max_health) * enemy_health_mult))))
		is_affected = true

	if enemy_script == scripts.get("chaser"):
		var chaser_damage_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT, 1.0)
		var chaser_interval_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_ATTACK_INTERVAL_MULT, 1.0)
		var chaser_speed_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_SPEED_MULT, 1.0)
		is_affected = not is_equal_approx(chaser_damage_mult, 1.0) \
			or not is_equal_approx(chaser_interval_mult, 1.0) \
			or not is_equal_approx(chaser_speed_mult, 1.0)
		var base_damage := int(enemy.get("attack_damage"))
		enemy.set("attack_damage", maxi(1, int(round(float(base_damage) * chaser_damage_mult))))
		var base_interval := float(enemy.get("attack_interval"))
		enemy.set("attack_interval", maxf(0.2, base_interval * chaser_interval_mult))
		var base_speed := float(enemy.get("move_speed"))
		enemy.set("move_speed", maxf(25.0, base_speed * chaser_speed_mult))

	if enemy_script == scripts.get("charger"):
		var charger_damage_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_DAMAGE_MULT, 1.0)
		var charger_speed_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_SPEED_MULT, 1.0)
		var charger_windup_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_WINDUP_MULT, 1.0)
		is_affected = not is_equal_approx(charger_damage_mult, 1.0) \
			or not is_equal_approx(charger_speed_mult, 1.0) \
			or not is_equal_approx(charger_windup_mult, 1.0)
		var base_charge_damage := int(enemy.get("charge_damage"))
		enemy.set("charge_damage", maxi(1, int(round(float(base_charge_damage) * charger_damage_mult))))
		var base_charge_speed := float(enemy.get("charge_speed"))
		enemy.set("charge_speed", maxf(60.0, base_charge_speed * charger_speed_mult))
		var base_windup := float(enemy.get("windup_time"))
		enemy.set("windup_time", maxf(0.18, base_windup * charger_windup_mult))

	if enemy_script == scripts.get("archer"):
		var archer_windup_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_WINDUP_MULT, 1.0)
		var archer_cooldown_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_COOLDOWN_MULT, 1.0)
		var archer_projectile_damage_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_PROJECTILE_DAMAGE_MULT, 1.0)
		is_affected = not is_equal_approx(archer_windup_mult, 1.0) \
			or not is_equal_approx(archer_cooldown_mult, 1.0) \
			or not is_equal_approx(archer_projectile_damage_mult, 1.0)
		var base_windup := float(enemy.get("windup_time"))
		enemy.set("windup_time", maxf(0.18, base_windup * archer_windup_mult))
		var base_cooldown := float(enemy.get("attack_cooldown"))
		enemy.set("attack_cooldown", maxf(0.6, base_cooldown * archer_cooldown_mult))
		var base_proj_damage := int(enemy.get("projectile_damage"))
		enemy.set("projectile_damage", maxi(1, int(round(float(base_proj_damage) * archer_projectile_damage_mult))))

	if enemy_script == scripts.get("shielder"):
		var shielder_slam_damage_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_DAMAGE_MULT, 1.0)
		var shielder_slam_windup_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_WINDUP_MULT, 1.0)
		var shielder_speed_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SPEED_MULT, 1.0)
		is_affected = not is_equal_approx(shielder_slam_damage_mult, 1.0) \
			or not is_equal_approx(shielder_slam_windup_mult, 1.0) \
			or not is_equal_approx(shielder_speed_mult, 1.0)
		var base_slam_damage := int(enemy.get("slam_damage"))
		enemy.set("slam_damage", maxi(1, int(round(float(base_slam_damage) * shielder_slam_damage_mult))))
		var base_slam_windup := float(enemy.get("slam_windup_time"))
		enemy.set("slam_windup_time", maxf(0.32, base_slam_windup * shielder_slam_windup_mult))
		var base_speed := float(enemy.get("move_speed"))
		enemy.set("move_speed", maxf(20.0, base_speed * shielder_speed_mult))

	if enemy_script == scripts.get("lurker"):
		# Lurker is a melee striker — reads chaser mutator stats so Blood Rush buffs it alongside Chasers.
		var chaser_damage_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT, 1.0)
		var chaser_speed_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_SPEED_MULT, 1.0)
		is_affected = not is_equal_approx(chaser_damage_mult, 1.0) or not is_equal_approx(chaser_speed_mult, 1.0)
		var base_strike := int(enemy.get("strike_damage"))
		enemy.set("strike_damage", maxi(1, int(round(float(base_strike) * chaser_damage_mult))))
		var base_lurker_speed := float(enemy.get("move_speed"))
		enemy.set("move_speed", maxf(25.0, base_lurker_speed * chaser_speed_mult))

	if enemy_script == scripts.get("ram"):
		# Ram is a charge attacker — reads charger mutator stats so Flashpoint/Siegebreak buff it alongside Chargers.
		var charger_damage_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_DAMAGE_MULT, 1.0)
		var charger_speed_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_SPEED_MULT, 1.0)
		var charger_windup_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_WINDUP_MULT, 1.0)
		is_affected = not is_equal_approx(charger_damage_mult, 1.0) \
			or not is_equal_approx(charger_speed_mult, 1.0) \
			or not is_equal_approx(charger_windup_mult, 1.0)
		var base_ram_charge_damage := int(enemy.get("charge_damage"))
		enemy.set("charge_damage", maxi(1, int(round(float(base_ram_charge_damage) * charger_damage_mult))))
		var base_ram_charge_speed := float(enemy.get("charge_speed"))
		enemy.set("charge_speed", maxf(60.0, base_ram_charge_speed * charger_speed_mult))
		var base_ram_windup := float(enemy.get("windup_time"))
		enemy.set("windup_time", maxf(0.18, base_ram_windup * charger_windup_mult))

	if enemy_script == scripts.get("lancer"):
		# Lancer is a ranged area-denial enemy — reads archer windup/cooldown so
		# Flashpoint and Iron Volley both affect it alongside archers.
		var archer_windup_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_WINDUP_MULT, 1.0)
		var archer_cooldown_mult := ENCOUNTER_CONTRACTS.mutator_stat(current_room_enemy_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_COOLDOWN_MULT, 1.0)
		is_affected = not is_equal_approx(archer_windup_mult, 1.0) or not is_equal_approx(archer_cooldown_mult, 1.0)
		var base_lancer_windup := float(enemy.get("windup_time"))
		enemy.set("windup_time", maxf(0.22, base_lancer_windup * archer_windup_mult))
		var base_lancer_cooldown := float(enemy.get("attack_cooldown"))
		enemy.set("attack_cooldown", maxf(0.8, base_lancer_cooldown * archer_cooldown_mult))

	enemy.modulate = ENCOUNTER_CONTRACTS.mutator_enemy_tint(current_room_enemy_mutator, Color(1.0, 0.92, 0.92, 1.0))
	if enemy.get("has_mutator_overlay") != null:
		enemy.set("has_mutator_overlay", is_affected)
	if enemy.get("mutator_theme_color") != null:
		enemy.set("mutator_theme_color", ENCOUNTER_CONTRACTS.mutator_theme_color(current_room_enemy_mutator, Color(1.0, 0.4, 0.4, 1.0)))

func _pick_spawn_position_in_current_room(min_player_distance: float = -1.0, min_enemy_spacing: float = 86.0) -> Vector2:
	if rng == null:
		return Vector2.ZERO
	var half := current_room_size * 0.5 - Vector2.ONE * spawn_padding
	var required_player_distance := spawn_safe_radius if min_player_distance < 0.0 else maxf(spawn_safe_radius, min_player_distance)
	var candidate := Vector2.ZERO
	for _try in range(60):
		candidate = Vector2(
			rng.randf_range(-half.x, half.x),
			rng.randf_range(-half.y, half.y)
		)
		if is_instance_valid(player) and candidate.distance_to(player.global_position) < required_player_distance:
			continue
		var too_close_to_enemy := false
		if is_instance_valid(world_root):
			for enemy in world_root.get_tree().get_nodes_in_group("enemies"):
				if not (enemy is Node2D):
					continue
				if candidate.distance_to((enemy as Node2D).global_position) < min_enemy_spacing:
					too_close_to_enemy = true
					break
		if too_close_to_enemy:
			continue
		return candidate
	return candidate
