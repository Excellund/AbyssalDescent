extends "res://scripts/tests/test_run_result_identity.gd"

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	_prepare_screen()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var folder := project_path.path_join("run_result_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	# Focused review of an actual incomplete-history result without repeating
	# the nine unchanged complete/legacy layouts: -- --partial-only.
	var partial_only := OS.get_cmdline_user_args().has("--partial-only")
	var sizes: Array[Vector2i] = [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]
	if partial_only:
		sizes = [Vector2i(960, 720)]
	for size in sizes:
		viewport.size = size
		var outcomes: Array[String] = ["Defeat", "Victory", "Legacy"]
		if partial_only:
			outcomes = ["Partial"]
		for outcome in outcomes:
			var summary := fixture_summary()
			var subtitle := "Run ended in Apex Breakwater."
			if outcome == "Victory":
				summary["defeated_boss_ids"] = ["warden", "sovereign", "lacuna"]
				summary["stats"]["bosses_defeated"] = 3
				summary["max_depth"] = 22
				subtitle = "The descent is complete."
			elif outcome == "Legacy":
				summary = {"max_depth": 12, "stats": {"bosses_defeated": 1}}
				subtitle = "Run ended in Crossfire."
			elif outcome == "Partial":
				summary = {"reached_act": 3, "max_depth": 22, "full_run_tracking_complete": false, "defeated_boss_ids": ["lacuna"], "stats": {"bosses_defeated": 1, "damage_dealt_total": 1460, "damage_taken_total": 36, "enemies_killed": 17}}
				subtitle = "The descent is complete."
			screen.show_result("Defeat" if outcome == "Legacy" else ("Victory" if outcome == "Partial" else outcome), subtitle, summary, outcome not in ["Victory", "Partial"])
			await _settle()
			screen._appearance_tween.custom_step(1.0)
			await _settle()
			_check_layout(size)
			if outcome == "Partial":
				check(screen._boss_label.text == "Defeated: Lacuna" and screen._stats_panel._title.text == "Stats since resuming", "Partial GPU result states only observed boss identity and qualifies the counters")
			await RenderingServer.frame_post_draw
			var filename := "%s_%d.png" % [outcome.to_lower(), size.x]
			var picture := viewport.get_texture().get_image()
			check(not picture.is_empty() and picture.save_png(folder.path_join(filename)) == OK, "Captured " + filename)
			frames.append({"file": filename, "size": [size.x, size.y], "outcome": outcome})
	var manifest := {"frames": frames, "failures": failures, "checks": checks, "gpu": RenderingServer.get_video_adapter_name()}
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	viewport.queue_free()
	await _settle()
	print("[OK] Result identity frames: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
