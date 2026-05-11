extends RefCounted

const STAT_ATTRIBUTION_TRACE := false

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
	var killed_enemy := health_before > 0 and health_after <= 0
	var source_peer_id := _resolve_local_peer_id()
	var enemy_id := 0
	if target_node.has_meta("network_enemy_id"):
		enemy_id = int(target_node.get_meta("network_enemy_id"))
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		return
	var world := scene_tree.current_scene
	if world == null:
		return
	if STAT_ATTRIBUTION_TRACE:
		print_debug("[StatAttribution][LocalApply] peer=%d enemy_id=%d applied=%d killed=%s" % [source_peer_id, enemy_id, applied_amount, str(killed_enemy)])
	world.record_player_damage_dealt(applied_amount, source_peer_id, killed_enemy, enemy_id)


static func _resolve_local_peer_id() -> int:
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree != null and scene_tree.get_multiplayer() != null:
		var active_peer_id := int(scene_tree.get_multiplayer().get_unique_id())
		if active_peer_id > 0:
			return active_peer_id
	if MultiplayerSessionManager != null and MultiplayerSessionManager.is_session_connected():
		return int(MultiplayerSessionManager.local_peer_id)
	return 0


static func _should_route_enemy_damage_to_host(target: Object) -> bool:
	if not MultiplayerSessionManager.is_remote_replica():
		return false
	if not (target is Node):
		return false
	var target_node := target as Node
	if target_node == null:
		return false
	if not target_node.has_meta("network_enemy_id"):
		return false
	return true


static func _route_enemy_damage_to_host(target: Object, amount: int, damage_context: Dictionary) -> void:
	if not (target is Node):
		return
	var target_node := target as Node
	if target_node == null:
		return
	if not target_node.has_meta("network_enemy_id"):
		return
	var routed_context := damage_context.duplicate(true)
	var local_peer_id := _resolve_local_peer_id()
	if local_peer_id > 0:
		routed_context["source_peer_id"] = local_peer_id
	var enemy_id := int(target_node.get_meta("network_enemy_id"))
	if enemy_id <= 0:
		return
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		return
	var world := scene_tree.current_scene
	if world == null:
		return
	if STAT_ATTRIBUTION_TRACE:
		print_debug("[StatAttribution][RouteToHost] peer=%d enemy_id=%d amount=%d attack=%s" % [local_peer_id, enemy_id, amount, String(routed_context.get("attack_type", "unknown"))])
	world.request_enemy_damage_from_client(enemy_id, amount, routed_context)
