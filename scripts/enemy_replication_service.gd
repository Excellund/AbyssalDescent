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
		enemy_nodes_by_id.clear()
		last_damage_peer_by_id.clear()
		target_positions_by_id.clear()
		target_facing_angles_by_id.clear()
