extends RefCounted

func on_enemy_killed(objective_manager: Node, objective_runtime: Node, kill_pos: Vector2) -> Dictionary:
	if not is_instance_valid(objective_manager):
		return {
			"should_redraw": false
		}

	var should_redraw := false
	var active_kind := String(objective_manager.active_objective_kind)

	if active_kind == "last_stand" or active_kind == "hold_the_line":
		objective_manager.kills += 1

	if active_kind == "cut_the_signal" and is_instance_valid(objective_manager.hunt_target_enemy):
		if objective_manager.exposure_left <= 0.0:
			objective_manager.hunt_target_kill_progress += 1
			if objective_manager.hunt_target_kill_progress >= objective_manager.hunt_target_kill_goal:
				if is_instance_valid(objective_runtime):
					objective_runtime.trigger_priority_target_exposure()

	if active_kind == "cut_the_signal" and objective_manager.overtime and objective_manager.spawn_timer > 0.2:
		objective_manager.spawn_timer = maxf(0.2, objective_manager.spawn_timer - 0.08)

	if active_kind == "hold_the_line":
		if objective_manager.control_goal > 0.0 and objective_manager.control_player_inside and not objective_manager.control_contested and kill_pos != Vector2.ZERO:
			var anchor: Vector2 = objective_manager.control_anchor
			var bonus_radius := maxf(1.0, objective_manager.control_radius * objective_manager.engagement_bonus_radius_scale)
			if kill_pos.distance_to(anchor) <= bonus_radius:
				objective_manager.control_progress = minf(objective_manager.control_goal, objective_manager.control_progress + objective_manager.engagement_kill_progress_bonus)
				should_redraw = true

	return {
		"should_redraw": should_redraw
	}
