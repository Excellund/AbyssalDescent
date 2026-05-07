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
	var health_before := _read_target_health(target)
	if damage_context.is_empty():
		target.take_damage(amount)
	else:
		target.take_damage(amount, damage_context)
	_report_enemy_damage_applied(target, health_before)
	return true


static func _read_target_health(target: Object) -> int:
	if target == null:
		return -1
	if target.has_method("get_current_health"):
		return int(target.call("get_current_health"))
	var health_state_node := target.get("health_state") as Object
	if health_state_node != null:
		return int(health_state_node.get("current_health"))
	return -1


static func _report_enemy_damage_applied(target: Object, health_before: int) -> void:
	if health_before < 0:
		return
	if not (target is Node):
		return
	var target_node := target as Node
	if target_node == null or not target_node.is_in_group("enemies"):
		return
	var health_after := _read_target_health(target)
	if health_after < 0:
		return
	var applied_amount := maxi(0, health_before - health_after)
	if applied_amount <= 0:
		return
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		return
	var world := scene_tree.current_scene
	if world == null:
		return
	if world.has_method("record_player_damage_dealt"):
		world.call("record_player_damage_dealt", applied_amount)


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
