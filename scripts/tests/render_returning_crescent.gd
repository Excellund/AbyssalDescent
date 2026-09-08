extends "res://scripts/tests/render_motion_arcana.gd"
## Reuses the isolated real arena/player renderer; only the new blade is stepped.

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Crescent GPU fixture requires an isolated project and real renderer")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2(FRAME_SIZE) * 0.5 + Vector2(0.0, 25.0))
	output_directory = project_path.path_join("crescent_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _path_frames()
	await _capacity_frame()
	await _bounce_frame()
	await create_timer(0.2).timeout
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {"size": [FRAME_SIZE.x, FRAME_SIZE.y], "gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures, "scope": "Real local Player, Crescent sweeps, Chasers, columns and arena rendering; multiplayer checked separately over ENet."}
	var file := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("[OK] Crescent GPU fixture: %d frames, %d failures" % [frames.size(), failures.size()])
	print("CRESCENT_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)

func _make_world() -> void:
	await super._make_world()
	player.returning_crescent.set_physics_process(false)
	player.damage = 40
	player.apply_trial_power("returning_crescent")

func _step_frames(count: int) -> void:
	for index in count:
		await super._step_frames(1)
		player.returning_crescent.tick(STEP)

func _path_frames() -> void:
	await _make_world()
	var direct := _add_enemy(Vector2(-35.0, 0.0))
	var returning_target := _add_enemy(Vector2(-40.0, 80.0))
	await physics_frame
	await _press_attack()
	await _step_frames(14)
	_check(direct.get_current_health() < 10000 and returning_target.get_current_health() == 10000, "Outgoing blade follows its own narrow aim and hits beyond melee reach")
	_check(player.returning_crescent.blades.size() == 1 and not player.returning_crescent.blades[0].returning, "First capture shows the outbound leg")
	await _capture("outbound", "RETURNING CRESCENT / FIRST THROW", "An attack throws a narrow blade. The cyan trail shows its outgoing path beyond the melee swing.")
	await _step_frames(8)
	player.global_position = Vector2(-130.0, 140.0)
	await _step_frames(9)
	_check(player.returning_crescent.blades.size() == 1 and player.returning_crescent.blades[0].returning, "Second capture shows the return leg chasing the moved owner")
	_check(returning_target.get_current_health() < 10000, "Repositioning sends the return leg through a different enemy")
	await _capture("steered_return", "RETURNING CRESCENT / CHANGE THE RETURN PATH", "Move before the blade comes home. Its violet return cuts through the second enemy.")
	await _free_world()

func _capacity_frame() -> void:
	await _make_world()
	player.apply_trial_power("returning_crescent")
	_add_enemy(Vector2(10.0, 0.0))
	_add_enemy(Vector2(0.0, -70.0))
	await physics_frame
	await _press_attack()
	await _step_frames(10)
	await _release_actions()
	player.aim_point = Vector2(80.0, -100.0)
	await _press_attack()
	await _step_frames(8)
	_check(player.returning_crescent.blades.size() == 2, "Level 2 supports two differently aimed blades")
	await _capture("two_blades", "RETURNING CRESCENT / LEVEL 2", "Two available blades let consecutive attacks send cuts along different paths.")
	await _free_world()

func _bounce_frame() -> void:
	await _make_world()
	player.apply_trial_power("returning_crescent")
	player.apply_trial_power("returning_crescent")
	var columns: Array[Dictionary] = [{"pos": Vector2(35.0, 15.0), "radius": 28.0}]
	for child in world.get_children():
		if child is RENDERER:
			child.set_obstacle_layout(columns)
	_add_column(Vector2(35.0, 15.0), 28.0)
	_add_enemy(Vector2(-25.0, -70.0))
	await physics_frame
	await _press_attack()
	await _step_frames(17)
	_check(player.returning_crescent.blades.size() == 1 and player.returning_crescent.blades[0].bounces_left == 0 and player.returning_crescent.blades[0].direction.y < -0.4, "Level 3 reflects from the visible column's real collision surface")
	await _capture("column_bounce", "RETURNING CRESCENT / LEVEL 3", "Glancing off a column changes the outgoing path. Each blade has one bounce before returning.")
	await _free_world()
