extends Node

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const ENEMY_MUTATOR_STACK_STAT_KEYS := [
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_ENEMY_HEALTH_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_ATTACK_INTERVAL_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_SPEED_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_DAMAGE_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_SPEED_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_WINDUP_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_WINDUP_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_COOLDOWN_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_PROJECTILE_DAMAGE_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_DAMAGE_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_WINDUP_MULT,
	ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SPEED_MULT
]
const ENEMY_MUTATOR_STAT_MAP := {
	"chaser": [
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT, "prop": "damage", "min": 1.0, "is_int": true},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_ATTACK_INTERVAL_MULT, "prop": "attack_interval", "min": 0.2},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_SPEED_MULT, "prop": "move_speed", "min": 25.0}
	],
	"charger": [
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_DAMAGE_MULT, "prop": "charge_damage", "min": 1.0, "is_int": true},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_SPEED_MULT, "prop": "charge_speed", "min": 60.0},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_WINDUP_MULT, "prop": "windup_time", "min": 0.18}
	],
	"archer": [
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_WINDUP_MULT, "prop": "windup_time", "min": 0.18},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_COOLDOWN_MULT, "prop": "attack_cooldown", "min": 0.6},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_PROJECTILE_DAMAGE_MULT, "prop": "projectile_damage", "min": 1.0, "is_int": true}
	],
	"shielder": [
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_DAMAGE_MULT, "prop": "slam_damage", "min": 1.0, "is_int": true},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_WINDUP_MULT, "prop": "slam_windup_time", "min": 0.32},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SPEED_MULT, "prop": "move_speed", "min": 20.0}
	],
	"lurker": [
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT, "prop": "strike_damage", "min": 1.0, "is_int": true},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_SPEED_MULT, "prop": "move_speed", "min": 25.0}
	],
	"ram": [
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_DAMAGE_MULT, "prop": "charge_damage", "min": 1.0, "is_int": true},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_SPEED_MULT, "prop": "charge_speed", "min": 60.0},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_WINDUP_MULT, "prop": "windup_time", "min": 0.18}
	],
	"lancer": [
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_WINDUP_MULT, "prop": "windup_time", "min": 0.22},
		{"stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_COOLDOWN_MULT, "prop": "attack_cooldown", "min": 0.8}
	]
}

# Enemy damage intent map for flat-vs-scaling clarity.
# Enemy attacks are flat by default and scale through encounter mutator multipliers.
const ENEMY_DAMAGE_CLASSIFICATION := {
	"chaser": {
		"contact_strike": {"kind": "flat", "scales_via_mutator": true, "mutator_stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT}
	},
	"charger": {
		"charge_hit": {"kind": "flat", "scales_via_mutator": true, "mutator_stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_DAMAGE_MULT}
	},
	"archer": {
		"projectile_hit": {"kind": "flat", "scales_via_mutator": true, "mutator_stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_PROJECTILE_DAMAGE_MULT}
	},
	"shielder": {
		"contact_strike": {"kind": "flat", "scales_via_mutator": true, "mutator_stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT},
		"slam_hit": {"kind": "flat", "scales_via_mutator": true, "mutator_stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_DAMAGE_MULT},
		"body_check": {"kind": "flat", "scales_via_mutator": false, "mutator_stat": "none"}
	},
	"lurker": {
		"strike": {"kind": "flat", "scales_via_mutator": true, "mutator_stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT}
	},
	"ram": {
		"charge_hit": {"kind": "flat", "scales_via_mutator": true, "mutator_stat": ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_DAMAGE_MULT}
	},
	"lancer": {
		"zone_tick": {"kind": "flat", "scales_via_mutator": false, "mutator_stat": "none"}
	},
	"boss_warden": {
		"all_attacks": {"kind": "flat", "scales_via_mutator": false, "mutator_stat": "none"}
	},
	"boss_sovereign": {
		"all_attacks": {"kind": "flat", "scales_via_mutator": false, "mutator_stat": "none"}
	}
}
const ENEMY_SPAWN_ORDER: Array[String] = ["chaser", "charger", "archer", "shielder", "lurker", "ram", "lancer"]

var world_root: Node2D
var player: Node2D
var rng: RandomNumberGenerator
var on_enemy_died: Callable

var scripts: Dictionary = {}
var current_room_size: Vector2 = Vector2.ZERO
var spawn_padding: float = 90.0
var spawn_safe_radius: float = 170.0
var spawn_transport_duration: float = 0.36
var current_room_enemy_mutator: Dictionary = {}
var active_temporary_enemy_mutators: Array[Dictionary] = []

func initialize(world_root_node: Node2D, player_node: Node2D, rng_instance: RandomNumberGenerator, script_map: Dictionary, enemy_died_callback: Callable) -> void:
	world_root = world_root_node
	player = player_node
	rng = rng_instance
	scripts = script_map
	on_enemy_died = enemy_died_callback

func configure_room(room_size: Vector2, padding: float, safe_radius: float, enemy_mutator: Dictionary, temporary_enemy_mutators: Array[Dictionary] = []) -> void:
	current_room_size = room_size
	spawn_padding = padding
	spawn_safe_radius = safe_radius
	current_room_enemy_mutator = enemy_mutator
	active_temporary_enemy_mutators = []
	for entry in temporary_enemy_mutators:
		if not (entry is Dictionary):
			continue
		active_temporary_enemy_mutators.append((entry as Dictionary).duplicate(true))

func _compose_active_enemy_mutator() -> Dictionary:
	var composed := current_room_enemy_mutator.duplicate(true)
	for mutator in active_temporary_enemy_mutators:
		if not ENCOUNTER_CONTRACTS.mutator_affects_scope(mutator, "enemy"):
			continue
		for stat_key in ENEMY_MUTATOR_STACK_STAT_KEYS:
			var current_value := ENCOUNTER_CONTRACTS.mutator_stat(composed, stat_key, 1.0)
			var mutator_value := ENCOUNTER_CONTRACTS.mutator_stat(mutator, stat_key, 1.0)
			ENCOUNTER_CONTRACTS.mutator_set_stat(composed, stat_key, current_value * mutator_value)
		if String(composed.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME, "")).is_empty():
			composed[ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME] = ENCOUNTER_CONTRACTS.mutator_name(mutator)
		if String(composed.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID, "")).is_empty():
			composed[ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID] = ENCOUNTER_CONTRACTS.mutator_icon_shape_id(mutator)
		if composed.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_THEME_COLOR) == null:
			composed[ENCOUNTER_CONTRACTS.MUTATOR_KEY_THEME_COLOR] = ENCOUNTER_CONTRACTS.mutator_theme_color(mutator)
	return composed

func spawn_profile_enemies(profile: Dictionary) -> int:
	var total := 0
	for enemy_type in ENEMY_SPAWN_ORDER:
		var count := _profile_count_for_enemy_type(profile, enemy_type)
		for _i in range(maxi(0, count)):
			_spawn_enemy_in_current_room(scripts.get(enemy_type))
			total += 1
	return total

func _profile_count_for_enemy_type(profile: Dictionary, enemy_type: String) -> int:
	match enemy_type:
		"chaser":
			return ENCOUNTER_CONTRACTS.profile_chaser_count(profile)
		"charger":
			return ENCOUNTER_CONTRACTS.profile_charger_count(profile)
		"archer":
			return ENCOUNTER_CONTRACTS.profile_archer_count(profile)
		"shielder":
			return ENCOUNTER_CONTRACTS.profile_shielder_count(profile)
		"lurker":
			return ENCOUNTER_CONTRACTS.profile_lurker_count(profile)
		"ram":
			return ENCOUNTER_CONTRACTS.profile_ram_count(profile)
		"lancer":
			return ENCOUNTER_CONTRACTS.profile_lancer_count(profile)
		_:
			return 0

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
	enemy.begin_spawn_transport(spawn_transport_duration)
	enemy.set("target", player)
	if enemy.get("arena_size") != null:
		enemy.set("arena_size", current_room_size)
	if enemy.has_signal("died") and on_enemy_died.is_valid():
		enemy.died.connect(on_enemy_died)
	return enemy

func _enemy_script_key(enemy_script: Script) -> String:
	for enemy_key in scripts.keys():
		if scripts.get(enemy_key) == enemy_script:
			return String(enemy_key)
	return ""

func _apply_mutator_specs(enemy: CharacterBody2D, mutator: Dictionary, specs: Array) -> bool:
	var is_affected := false
	for spec_variant in specs:
		var spec := spec_variant as Dictionary
		var stat_key := String(spec.get("stat", ""))
		if stat_key.is_empty():
			continue
		var multiplier := ENCOUNTER_CONTRACTS.mutator_stat(mutator, stat_key, 1.0)
		if not is_equal_approx(multiplier, 1.0):
			is_affected = true
		var property_name := String(spec.get("prop", ""))
		if property_name.is_empty() or enemy.get(property_name) == null:
			continue
		var min_value := float(spec.get("min", 0.0))
		var base_value := float(enemy.get(property_name))
		var scaled_value := maxf(min_value, base_value * multiplier)
		if bool(spec.get("is_int", false)):
			enemy.set(property_name, maxi(int(round(min_value)), int(round(scaled_value))))
		else:
			enemy.set(property_name, scaled_value)
	return is_affected

func _apply_enemy_mutator(enemy: CharacterBody2D, enemy_script: Script) -> void:
	var applied_mutator := _compose_active_enemy_mutator()
	if applied_mutator.is_empty():
		return
	var is_affected: bool = false
	var enemy_health_mult := ENCOUNTER_CONTRACTS.mutator_stat(applied_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ENEMY_HEALTH_MULT, 1.0)
	if not is_equal_approx(enemy_health_mult, 1.0):
		var base_max_health: int = int(enemy.get_max_health())
		var scaled_max_health := maxi(1, int(round(float(base_max_health) * enemy_health_mult)))
		enemy.set_max_health_and_current(scaled_max_health, scaled_max_health)
		is_affected = true
	var enemy_key := _enemy_script_key(enemy_script)
	var specs := ENEMY_MUTATOR_STAT_MAP.get(enemy_key, []) as Array
	is_affected = _apply_mutator_specs(enemy, applied_mutator, specs) or is_affected

	enemy.modulate = ENCOUNTER_CONTRACTS.mutator_enemy_tint(applied_mutator, Color(1.0, 0.92, 0.92, 1.0))
	if enemy.get("has_mutator_overlay") != null:
		enemy.set("has_mutator_overlay", is_affected)
	if enemy.get("mutator_theme_color") != null:
		enemy.set("mutator_theme_color", ENCOUNTER_CONTRACTS.mutator_theme_color(applied_mutator, Color(1.0, 0.4, 0.4, 1.0)))

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
