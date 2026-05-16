extends RefCounted

const PLAYER_SCRIPT := preload("res://scripts/player.gd")

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
		player.set_physics_process(not paused)
	if tree == null:
		return
	for enemy in tree.get_nodes_in_group("enemies"):
		if enemy is Node:
			(enemy as Node).set_physics_process(not paused)
			(enemy as Node).set_process(not paused)
