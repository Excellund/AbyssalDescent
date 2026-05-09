extends Node

var world_generator: Node = null

var enemy_nodes_by_id: Dictionary = {}
var last_damage_peer_by_id: Dictionary = {}
var target_positions_by_id: Dictionary = {}
var target_facing_angles_by_id: Dictionary = {}


func bind_world(world: Node) -> void:
	world_generator = world


func unbind_world(world: Node) -> void:
	if world_generator == world:
		world_generator = null
		clear_state()


func clear_state() -> void:
	enemy_nodes_by_id.clear()
	last_damage_peer_by_id.clear()
	target_positions_by_id.clear()
	target_facing_angles_by_id.clear()


func credit_damage(enemy_id: int, peer_id: int) -> void:
	if enemy_id <= 0 or peer_id <= 0:
		return
	last_damage_peer_by_id[enemy_id] = peer_id


func killer_peer_for(enemy_id: int) -> int:
	return int(last_damage_peer_by_id.get(enemy_id, 0))
