extends RefCounted

func close_reward_selection_if_active(reward_selection_ui: Node) -> void:
	if is_instance_valid(reward_selection_ui) and reward_selection_ui.has_method("close_selection"):
		reward_selection_ui.close_selection()

func close_pause_menu_if_open(pause_menu_controller: Node) -> void:
	if is_instance_valid(pause_menu_controller) and bool(pause_menu_controller.is_open()):
		pause_menu_controller.close()

func prepare_for_menu_transition(combat_phase_coordinator: RefCounted, player: Node, tree: SceneTree, pause_menu_controller: Node) -> void:
	if combat_phase_coordinator != null:
		combat_phase_coordinator.set_combat_paused(player, tree, false)
	close_pause_menu_if_open(pause_menu_controller)

func reset_player_position(player: Node, position: Vector2 = Vector2.ZERO) -> void:
	if is_instance_valid(player) and player is Node2D:
		(player as Node2D).global_position = position

func show_defeat_feedback(hud: Node, defeat_screen: Node, room_label: String, room_depth: int) -> void:
	if is_instance_valid(hud):
		hud.show_banner("Defeat", "")
	if is_instance_valid(defeat_screen):
		defeat_screen.show_defeat(room_label, room_depth)
