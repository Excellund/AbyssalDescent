extends "res://scripts/tests/test_glossary_readability.gd"
var frames: Array[Dictionary] = []

func _run() -> void:
	var folder := ProjectSettings.globalize_path("res://glossary_frames")
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(folder)
	_setup()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		menu._apply_menu_layout()
		for label in ["Build Keywords", "Power Rules", "Mutators"]:
			await _check_section(label, size)
			await RenderingServer.frame_post_draw
			var path := folder.path_join(label.to_snake_case() + "_" + str(size.x) + ".png")
			_check(viewport.get_texture().get_image().save_png(path) == OK, "Actual glossary GPU frame saves")
			frames.append({"name": label + str(size.x), "path": path})
			if label == "Power Rules":
				body.get_v_scroll_bar().value = body.get_v_scroll_bar().max_value
				await _settle()
				await RenderingServer.frame_post_draw
				path = folder.path_join("power_rules_lower_" + str(size.x) + ".png")
				_check(body.get_v_scroll_bar().value > 0.0, "The lower power rules are visibly scrolled into view")
				_check(viewport.get_texture().get_image().save_png(path) == OK, "Actual lower power rules GPU frame saves")
				frames.append({"name": "Power Rules lower" + str(size.x), "path": path})
	viewport.free()
	await process_frame
	FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures}, "\t"))
	print("[OK] Glossary GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
