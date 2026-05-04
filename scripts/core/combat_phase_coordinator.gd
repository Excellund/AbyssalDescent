extends RefCounted

func clear_enemy_lingering_effects(tree: SceneTree) -> void:
	if tree == null:
		return
	for effect in tree.get_nodes_in_group("enemy_lingering_effects"):
		if effect is Node:
			(effect as Node).queue_free()

func clear_player_lingering_effects(player: Node) -> void:
	if is_instance_valid(player) and player.has_method("clear_lingering_combat_effects"):
		player.clear_lingering_combat_effects()

func set_player_combat_damage_enabled(player: Node, enabled: bool) -> void:
	if is_instance_valid(player) and player.has_method("set_combat_damage_enabled"):
		player.set_combat_damage_enabled(enabled)

func begin_combat_phase(player: Node, tree: SceneTree) -> void:
	set_player_combat_damage_enabled(player, true)
	clear_enemy_lingering_effects(tree)
	clear_player_lingering_effects(player)

func end_combat_phase(player: Node, tree: SceneTree) -> void:
	set_player_combat_damage_enabled(player, false)
	clear_enemy_lingering_effects(tree)

func set_combat_paused(player: Node, tree: SceneTree, paused: bool) -> void:
	if is_instance_valid(player):
		if player is CharacterBody2D:
			(player as CharacterBody2D).velocity = Vector2.ZERO
		player.set_physics_process(not paused)
	if tree == null:
		return
	for enemy in tree.get_nodes_in_group("enemies"):
		if enemy is Node:
			(enemy as Node).set_physics_process(not paused)
			(enemy as Node).set_process(not paused)
