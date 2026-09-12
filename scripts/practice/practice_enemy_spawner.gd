extends "res://scripts/enemy_spawner.gd"
## Track native initial, staggered and Mission spawns at the same factory edge.

func _spawn_enemy_in_current_room(enemy_script: Script, min_player_distance: float = -1.0) -> ENEMY_BASE_SCRIPT:
	var actor := super._spawn_enemy_in_current_room(enemy_script, min_player_distance)
	if is_instance_valid(actor):
		world_root._register_enemy(actor, _enemy_script_key(enemy_script))
	return actor
