extends RefCounted

func reset_for_new_room(objective_manager: Node, objective_runtime: Node) -> void:
	if is_instance_valid(objective_manager):
		objective_manager.reset()
	if is_instance_valid(objective_runtime):
		objective_runtime.reset_room_objective_state()

func clear_on_player_defeat(objective_manager: Node) -> void:
	if is_instance_valid(objective_manager):
		objective_manager.active_objective_kind = ""
