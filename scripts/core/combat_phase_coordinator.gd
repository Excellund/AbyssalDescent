extends RefCounted

const PLAYER_SCRIPT := preload("res://scripts/player.gd")

# A repeated pause (for example Pause above Build Details) must retain the
# original processing flags, including actors/effects disabled for other reasons.
var _paused_nodes: Dictionary = {} # Instance ID -> weak node and prior flags.

func clear_enemy_lingering_effects(tree: SceneTree) -> void:
	if tree == null:
		return
	for effect in tree.get_nodes_in_group("enemy_lingering_effects"):
		if effect is Node:
			(effect as Node).queue_free()

func clear_player_lingering_effects(player: PLAYER_SCRIPT) -> void:
	if is_instance_valid(player):
		player.clear_lingering_combat_effects()

func set_player_combat_damage_enabled(player: PLAYER_SCRIPT, enabled: bool) -> void:
	if is_instance_valid(player):
		player.set_combat_damage_enabled(enabled)

func begin_combat_phase(player: PLAYER_SCRIPT, tree: SceneTree) -> void:
	set_player_combat_damage_enabled(player, true)
	clear_enemy_lingering_effects(tree)
	clear_player_lingering_effects(player)

func end_combat_phase(player: PLAYER_SCRIPT, tree: SceneTree) -> void:
	set_player_combat_damage_enabled(player, false)
	clear_player_lingering_effects(player)
	clear_enemy_lingering_effects(tree)

func set_combat_paused(player: PLAYER_SCRIPT, tree: SceneTree, paused: bool) -> void:
	if is_instance_valid(player):
		player.velocity = Vector2.ZERO
		player.discard_pending_combat_input()
	if not paused:
		_restore_paused_nodes()
		return
	if is_instance_valid(player):
		_pause_node(player, false)
	if tree == null:
		return
	for group in [&"enemies", &"enemy_lingering_effects"]:
		for node in tree.get_nodes_in_group(group):
			_pause_node(node, true)

func _pause_node(node: Node, pause_idle: bool) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	var id := node.get_instance_id()
	if not _paused_nodes.has(id):
		_paused_nodes[id] = {
			"node": weakref(node),
			"physics": node.is_physics_processing(),
			"idle": node.is_processing(),
			"pause_idle": pause_idle
		}
	node.set_physics_process(false)
	if pause_idle:
		node.set_process(false)

func _restore_paused_nodes() -> void:
	for state: Dictionary in _paused_nodes.values():
		var node := (state["node"] as WeakRef).get_ref() as Node
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		node.set_physics_process(bool(state["physics"]))
		if bool(state["pause_idle"]):
			node.set_process(bool(state["idle"]))
	_paused_nodes.clear()
