extends RefCounted

const OBJECTIVE_MANAGER_SCRIPT := preload("res://scripts/objective_manager.gd")
const OBJECTIVE_RUNTIME_SCRIPT := preload("res://scripts/objective_runtime.gd")

func tick(objective_manager: OBJECTIVE_MANAGER_SCRIPT, objective_runtime: OBJECTIVE_RUNTIME_SCRIPT, delta: float, grace_active: bool) -> Dictionary:
	var active_kind := ""
	if is_instance_valid(objective_manager):
		active_kind = String(objective_manager.active_objective_kind)
	var should_tick_objective := not grace_active
	if should_tick_objective and is_instance_valid(objective_runtime):
		objective_runtime.update_objective_state(delta)
	if is_instance_valid(objective_runtime):
		objective_runtime.update_priority_target_marker(delta)

	var should_redraw := false
	if is_instance_valid(objective_manager):
		should_redraw = objective_manager.should_draw_control_overlay()

	return {
		"should_redraw": should_redraw
	}
