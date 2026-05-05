extends RefCounted

# Shared helper to enforce the take_damage contract consistently.
static func can_take_damage(target: Object) -> bool:
	return is_instance_valid(target)

static func apply_damage(target: Object, amount: int, damage_context: Dictionary = {}) -> bool:
	if amount <= 0:
		return false
	if not can_take_damage(target):
		return false
	if _should_route_enemy_damage_to_host(target):
		_route_enemy_damage_to_host(target, amount, damage_context)
		return true
	if damage_context.is_empty():
		target.take_damage(amount)
	else:
		target.take_damage(amount, damage_context)
	return true


static func _should_route_enemy_damage_to_host(target: Object) -> bool:
	if not MultiplayerSessionManager.is_session_connected():
		return false
	if MultiplayerSessionManager.is_host():
		return false
	if not (target is Node):
		return false
	var target_node := target as Node
	if target_node == null:
		return false
	return target_node.is_in_group("enemies")


static func _route_enemy_damage_to_host(target: Object, amount: int, damage_context: Dictionary) -> void:
	if not (target is Node):
		return
	var target_node := target as Node
	if target_node == null:
		return
	if not target_node.has_meta("network_enemy_id"):
		return
	var enemy_id := int(target_node.get_meta("network_enemy_id"))
	if enemy_id <= 0:
		return
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		return
	var world := scene_tree.current_scene
	if world == null:
		return
	if world.has_method("request_enemy_damage_from_client"):
		world.call("request_enemy_damage_from_client", enemy_id, amount, damage_context)
