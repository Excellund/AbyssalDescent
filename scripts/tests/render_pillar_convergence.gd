extends "res://scripts/tests/render_motion_arcana.gd"
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")

func _arm(target: Node2D) -> void:
	for index in range(3):
		var action := player.new_combat_action("attack")
		DAMAGEABLE.apply_damage(target, 10, INTERACTIONS.damage_context(action, "melee", {"raw_amount": 10.0, "damage_coefficient": .5}), 1)
	_check(player.convergence_window_left > 0.0, "Native accepted attacks arm the displayed stationary seal")

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2(FRAME_SIZE) * .5 + Vector2(0, 25))
	output_directory = project_path.path_join("pillar_convergence_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _make_world()
	player.player_id = 1
	player.position = Vector2(-140, 0)
	player.apply_upgrade("pillar_convergence")
	var primary := _add_enemy(Vector2(180, 0))
	var near := _add_enemy(Vector2(225, 25))
	for target in [primary, near]:
		target.spawn_transport_time_left = 0.0
	_arm(primary)
	await _capture("armed", "FAULTLINE SEAL / A FIXED TARGET", "Three Attack hits or Electric actions plant a compact seal at the struck foe. The rising shard and fuse show its 0.8-second delay.")
	player.position = Vector2(-225, 65)
	primary.position = Vector2(160, -50)
	await create_timer(.2).timeout
	_check(player.player_feedback.faultline_seal.global_position == Vector2(180, 0), "The visible seal stays fixed while both actor and target move")
	await _capture("fixed", "FAULTLINE SEAL / HOLD THE GROUND", "The seal stays where it was planted. Neither moving the player nor striking another foe relocates it.")
	player._update_convergence_window(.81)
	_check(near.get_current_health() < 10000 and near.velocity.is_zero_approx(), "Ordinary expiry delivers compact damage with no Pull")
	await _capture("burst", "FAULTLINE SEAL / THE FUSE BREAKS", "At the end of its fuse, the seal releases one Burst for 180% of Damage. No moving Field and no enemy displacement.")
	await create_timer(.3).timeout
	player._update_convergence_window(.61)
	primary.position = Vector2(180, 0)
	_arm(primary)
	player.apply_trial_power("static_wake")
	var action := player.new_combat_action("dash")
	player.static_wake_controller.begin_dash(action)
	player.static_wake_controller.append_segment(Vector2(160, 0), Vector2(190, 0))
	player.static_wake_controller.end_dash()
	var before := near.get_current_health()
	player.static_wake_controller.tick(.25)
	_check(player.convergence_window_left == 0.0 and near.get_current_health() < before, "A later native owned Field tick triggers the stronger Burst early")
	await _capture("field_burst", "FAULTLINE SEAL / FIELD DETONATION", "Your Field damage inside the seal detonates it early for 50% more damage. A warm impact distinguishes this stronger payoff.")
	player.static_wake_controller.cancel()
	await create_timer(.4).timeout
	_check(not is_instance_valid(player.player_feedback.faultline_seal), "No expired seal marker remains after either detonation")
	await _free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames": frames, "failures": failures, "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	print("[FaultlineSealGPU] %d frames, %d failures" % [frames.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
