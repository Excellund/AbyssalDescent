extends RefCounted

func tick(objective_manager: Node, objective_runtime: Node, delta: float, grace_active: bool) -> Dictionary:
	if not grace_active and is_instance_valid(objective_runtime):
		objective_runtime.update_objective_state(delta)
	if is_instance_valid(objective_runtime):
		objective_runtime.update_priority_target_marker(delta)

	var should_redraw := false
	if is_instance_valid(objective_manager):
		if objective_manager.has_method("should_draw_control_overlay"):
			should_redraw = bool(objective_manager.should_draw_control_overlay())
		else:
			var active_kind := String(objective_manager.active_objective_kind)
			should_redraw = active_kind == "hold_the_line" or float(objective_manager.control_radius) > 0.0

	return {
		"should_redraw": should_redraw
	}
