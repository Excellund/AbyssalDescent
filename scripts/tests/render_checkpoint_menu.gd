extends "res://scripts/tests/test_checkpoint_menu.gd"
## Real menu error controls with a future-format checkpoint in disposable storage.
func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	_prepare_menu()
	_write_primary_record({"version": 999, "snapshot": snapshot})
	menu._refresh_primary_run_button()
	menu.primary_run_button.pressed.emit()
	var folder := project_path.path_join("checkpoint_menu_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	for size in [Vector2i(960, 720), Vector2i(1280, 720)]:
		await _check_error_layout(size)
		await RenderingServer.frame_post_draw
		var filename := "checkpoint_error_%d.png" % size.x
		var picture := root.get_texture().get_image()
		check(not picture.is_empty() and picture.save_png(folder.path_join(filename)) == OK, "Captured " + filename)
		frames.append({"file": filename, "size": [size.x, size.y]})
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	await _release_menu()
	print("[OK] Checkpoint menu frames: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
