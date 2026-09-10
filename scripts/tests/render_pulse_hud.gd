extends "res://scripts/tests/test_pulse_hud.gd"
## Full production HUD and arena at native playtest window sizes.

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		push_error("Pulse HUD captures require an isolated GPU renderer")
		quit(1)
		return
	root.size = Vector2i(960, 720)
	root.content_scale_size = root.size
	_prepare_pulse_world()
	for enemy in get_nodes_in_group("enemies"):
		if enemy.has_method("_update_spawn_transport"):
			enemy._update_spawn_transport(1.0)
			enemy.queue_redraw()
	var folder := project_path.path_join("pulse_hud_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	var pool := world.encounter_profile_builder.get_hard_enemy_mutator_pool()
	for size in [Vector2i(960, 720), Vector2i(1280, 720)]:
		root.size = size
		root.content_scale_size = size
		await process_frame
		world._apply_camera_bounds_for_room(world.current_effective_room_size)
		world.player_camera.force_update_scroll()
		world._sync_renderer()
		for mode in ["Flashpoint", "Tether Web", "Waiting"]:
			for mutator in pool:
				if CONTRACTS.mutator_name(mutator) == mode:
					_show_pulse(mutator)
			if mode == "Waiting":
				world.objective_manager.pulse_active = false
				world.objective_manager.pulse_next_timer = 2.2
				world.hud.refresh(world._get_hud_state(), world.player)
				check(not world.hud._status_obj_line3.visible, "Expired pulse rule is absent: %d" % size.x)
			await process_frame
			await process_frame
			world.hud.refresh(world._get_hud_state(), world.player)
			if mode != "Waiting":
				_check_pulse_layout("%s/%d" % [mode, size.x])
			await RenderingServer.frame_post_draw
			var filename := "%s_%d.png" % [mode.to_snake_case(), size.x]
			var picture := root.get_texture().get_image()
			check(not picture.is_empty() and picture.save_png(folder.path_join(filename)) == OK, "Captured " + filename)
			frames.append({"file": filename, "size": [size.x, size.y], "mode": mode})
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	await _release_pulse_world()
	print("[OK] Pulse HUD frames: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
