extends "res://scripts/tests/test_boss_atmosphere.gd"
var frames: Array[Dictionary] = []
var output_directory := ""

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		quit(1)
		return
	output_directory = ProjectSettings.globalize_path("res://boss_atmosphere_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await super._run()

func _capture_phase(frame_name: String, phase: String) -> void:
	if phase == "greeting":
		for enemy: Node in get_nodes_in_group("enemies"):
			if enemy.is_queued_for_deletion():
				continue
			enemy._update_spawn_transport(float(enemy.spawn_transport_time_left) + .01)
			check(not enemy.is_spawn_transporting(), "Survey capture settles the native boss's entrance transport")
	elif phase == "reward":
		var ui: Node = world.reward_selection_ui
		for _frame in 40:
			ui.process_input(.05)
		check(ui.boon_title_label.is_visible_in_tree() and ui.boon_title_label.modulate.a > .9, "Native reward title is fully revealed before capture")
		check(ui.epitaph_label.is_visible_in_tree() and ui.epitaph_label.modulate.a > .9, "Native attributed epitaph has visible alpha before capture")
		for index in ui.boon_choices.size():
			check(ui.boon_card_panels[index].is_visible_in_tree() and ui.boon_card_panels[index].modulate.a > .9, "Native reward card is fully revealed before capture")
	world._apply_camera_bounds_for_room(world.current_effective_room_size)
	world._update_camera_mode()
	world.player_camera.set_physics_process(false)
	world.player_camera.global_position = Vector2.ZERO
	world.player_camera.zoom = world.player_camera.target_zoom
	world.player_camera.force_update_scroll()
	world._sync_renderer()
	await super._capture_phase(frame_name, phase)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(frame_name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Captured actual boss surface: " + frame_name)
	frames.append({"name": frame_name, "path": path, "phase": phase, "size": root.size})
	print("[FRAME] " + path)

func _finish_capture() -> void:
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures, "scope": "All six native boss door greetings and first warnings, four attributed reward epitaphs and two authoritative final victory subtitles at960."}, "\t"))
