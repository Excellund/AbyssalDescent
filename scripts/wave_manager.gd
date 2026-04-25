extends Node2D

const ENEMY_CHASER_SCRIPT := preload("res://scripts/enemy_chaser.gd")
const ENEMY_CHARGER_SCRIPT := preload("res://scripts/enemy_charger.gd")

@export var player_path: NodePath = NodePath("Player")
@export var first_wave_count: int = 3
@export var wave_growth: int = 1
@export var max_wave_count: int = 20
@export var max_waves: int = 8
@export var time_between_waves: float = 1.8
@export var spawn_radius_min: float = 180.0
@export var spawn_radius_max: float = 340.0
@export var charger_start_wave: int = 2
@export_range(0.0, 1.0, 0.01) var charger_spawn_ratio: float = 0.25

var player: Node2D
var current_wave: int = 0
var enemies_alive: int = 0
var kills: int = 0
var waiting_for_next_wave: bool = false
var between_wave_timer: float = 0.0
var hud_label: Label
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	player = get_node_or_null(player_path) as Node2D
	_create_hud()
	_start_next_wave()

func _process(delta: float) -> void:
	if waiting_for_next_wave:
		between_wave_timer = maxf(0.0, between_wave_timer - delta)
		if between_wave_timer <= 0.0:
			waiting_for_next_wave = false
			_start_next_wave()
		else:
			_update_hud()
		return

	if current_wave < max_waves and enemies_alive <= 0 and current_wave > 0:
		waiting_for_next_wave = true
		between_wave_timer = time_between_waves
		_update_hud()

func _start_next_wave() -> void:
	if current_wave >= max_waves:
		_update_hud()
		return

	current_wave += 1
	var wave_size := mini(max_wave_count, first_wave_count + (current_wave - 1) * wave_growth)
	for _i in range(wave_size):
		_spawn_enemy()
	_update_hud()

func _spawn_enemy() -> void:
	var is_charger := current_wave >= charger_start_wave and rng.randf() < charger_spawn_ratio
	var enemy_script := ENEMY_CHARGER_SCRIPT if is_charger else ENEMY_CHASER_SCRIPT
	
	var enemy := CharacterBody2D.new()
	enemy.set_script(enemy_script)
	
	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = CircleShape2D.new()
	collision_shape.shape.radius = 13.0
	enemy.add_child(collision_shape)
	
	enemy.global_position = _pick_spawn_position()
	enemy.set("target_path", NodePath("../Player"))
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemies_alive += 1

func _pick_spawn_position() -> Vector2:
	var center := Vector2.ZERO
	if is_instance_valid(player):
		center = player.global_position
	var angle := rng.randf_range(0.0, TAU)
	var radius := rng.randf_range(spawn_radius_min, spawn_radius_max)
	return center + Vector2.RIGHT.rotated(angle) * radius

func _on_enemy_died() -> void:
	enemies_alive = maxi(0, enemies_alive - 1)
	kills += 1
	_update_hud()

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)

	hud_label = Label.new()
	hud_label.position = Vector2(16.0, 12.0)
	hud_label.add_theme_font_size_override("font_size", 20)
	layer.add_child(hud_label)
	_update_hud()

func _update_hud() -> void:
	if hud_label == null:
		return

	if current_wave >= max_waves and enemies_alive <= 0:
		hud_label.text = "Run Clear  Kills: %d" % kills
		return

	if waiting_for_next_wave:
		hud_label.text = "Wave %d cleared  Next: %.1fs  Kills: %d" % [current_wave, between_wave_timer, kills]
		return

	hud_label.text = "Wave %d/%d  Enemies: %d  Kills: %d" % [maxi(1, current_wave), max_waves, enemies_alive, kills]
