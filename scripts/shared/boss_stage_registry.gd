class_name BossStageRegistry
extends RefCounted

## Single source of truth for boss stage metadata and boss node construction.
##
## Used by:
##   - scripts/world_generator.gd (host-side room setup and joiner spawn replication)
##
## To add a new boss stage:
##   1. Preload the boss script below.
##   2. Add an entry to STAGES keyed by stage number with the required fields.
##   3. Wire dispatch in scripts/world_generator.gd `_choose_door` (and any
##      debug entry points) so the new stage gets reached.
## The two boss spawn paths (host setup / joiner replication) automatically
## pick up the new entry through `get_descriptor()` and `create_boss_node()`.

const ENEMY_BOSS_SCRIPT := preload("res://scripts/enemy_boss.gd")
const ENEMY_BOSS_2_SCRIPT := preload("res://scripts/enemy_boss_2.gd")
const ENEMY_BOSS_3_SCRIPT := preload("res://scripts/enemy_boss_3.gd")

const STAGES := {
	1: {
		"script": ENEMY_BOSS_SCRIPT,
		"collision_radius": 34.0,
		"room_size": Vector2(1260.0, 900.0),
		"room_label": "Boss Chamber: The Warden",
		"room_entry_key": "warden",
		"banner_title": "The Warden",
		"min_player_distance_floor": 260.0,
		"min_player_distance_pad": 90.0,
		"wall_margin_floor": 210.0,
		"wall_margin_pad": 110.0,
	},
	2: {
		"script": ENEMY_BOSS_2_SCRIPT,
		"collision_radius": 38.0,
		"room_size": Vector2(1360.0, 960.0),
		"room_label": "Abyss Core: Sovereign",
		"room_entry_key": "sovereign",
		"banner_title": "Sovereign",
		"min_player_distance_floor": 280.0,
		"min_player_distance_pad": 110.0,
		"wall_margin_floor": 230.0,
		"wall_margin_pad": 130.0,
	},
	3: {
		"script": ENEMY_BOSS_3_SCRIPT,
		"collision_radius": 40.0,
		"room_size": Vector2(1460.0, 1040.0),
		"room_label": "Silent Threshold: Lacuna",
		"room_entry_key": "lacuna",
		"banner_title": "Lacuna",
		"min_player_distance_floor": 300.0,
		"min_player_distance_pad": 130.0,
		"wall_margin_floor": 250.0,
		"wall_margin_pad": 150.0,
	},
}

static func has_stage(stage: int) -> bool:
	return STAGES.has(stage)

static func get_descriptor(stage: int) -> Dictionary:
	return STAGES.get(stage, {})

## Constructs a fully-formed boss CharacterBody2D for the given stage with its
## script and circular collision shape attached, positioned at `spawn_position`.
## The caller is responsible for adding it to the scene tree and wiring signals.
## Returns null if `stage` is unknown.
static func create_boss_node(stage: int, spawn_position: Vector2) -> CharacterBody2D:
	var descriptor: Dictionary = STAGES.get(stage, {})
	if descriptor.is_empty():
		return null
	var boss := CharacterBody2D.new()
	boss.set_script(descriptor["script"])
	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = CircleShape2D.new()
	collision_shape.shape.radius = float(descriptor["collision_radius"])
	boss.add_child(collision_shape)
	boss.global_position = spawn_position
	return boss
