extends "res://scripts/tests/test_run_result_identity.gd"
## Staged production Pause/results surfaces; lifecycle fault tests drive callers.

const PAUSE := preload("res://scripts/pause_menu_controller.gd")
const CLEAR_NOTICE := "Could not clear the saved descent. Try the action again."
const SAVE_NOTICE := "Progress could not be saved. Returning later may lose progress."

var frames: Array[Dictionary] = []
var folder: String

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	_prepare_screen()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	folder = project_path.path_join("checkpoint_notice_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	var pause_menu := PAUSE.new()
	viewport.add_child(pause_menu)
	pause_menu.initialize("/root/RunContext", Callable(), Callable())
	for size in [Vector2i(960, 720), Vector2i(1280, 720)]:
		viewport.size = size
		for notice in [SAVE_NOTICE, CLEAR_NOTICE]:
			pause_menu.set_checkpoint_notice(notice)
			pause_menu.open()
			await create_timer(0.25).timeout
			await _settle()
			var panel: Rect2 = pause_menu.pause_menu_panel.get_global_rect()
			var label: Label = pause_menu.checkpoint_notice_label
			check(Rect2(Vector2.ZERO, Vector2(size)).encloses(panel), "Pause error panel fits %s" % size)
			check(panel.encloses(label.get_global_rect()), "Pause notice fits panel")
			check(label.get_line_count() <= 3 and label.visible, "Pause notice wraps into visible lines")
			for child in pause_menu.pause_menu_panel.get_children():
				if child is Button:
					check(child.get_global_rect().end.y < label.get_global_rect().position.y, "Pause action remains above notice: " + child.text)
			await _capture(("save" if notice == SAVE_NOTICE else "clear") + "_pause", size)
			pause_menu.close()
		pause_menu.set_checkpoint_notice("")
		check(not pause_menu.checkpoint_notice_label.visible and pause_menu.pause_menu_panel.size.y == 480.0, "Clearing error restores ordinary Pause height")
		for outcome in ["Victory", "Defeat"]:
			screen.show_result(outcome, "The descent is complete." if outcome == "Victory" else "Run ended in Apex Breakwater.", fixture_summary(), outcome == "Defeat")
			screen.set_checkpoint_notice(CLEAR_NOTICE)
			await _settle()
			screen._appearance_tween.custom_step(1.0)
			await _settle()
			_check_layout(size)
			var notice_rect: Rect2 = screen._checkpoint_notice_label.get_global_rect()
			check(screen._card.get_global_rect().encloses(notice_rect), "Result notice fits card")
			check(notice_rect.end.y <= screen._action_buttons.get_global_rect().position.y, "Result notice stays above actions")
			check(screen._content_scroll.get_global_rect().end.y <= notice_rect.position.y, "Result notice remains outside scrolling build content")
			await _capture(outcome.to_lower(), size)
			screen.show_result(outcome, "", fixture_summary())
			check(not screen._checkpoint_notice_label.visible, "New result clears previous storage notice")
			screen._layer.visible = false
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	viewport.queue_free()
	await _settle()
	print("[OK] Checkpoint notices: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture(mode: String, size: Vector2i) -> void:
	await RenderingServer.frame_post_draw
	var filename := "%s_%d.png" % [mode, size.x]
	var picture := viewport.get_texture().get_image()
	check(not picture.is_empty() and picture.save_png(folder.path_join(filename)) == OK, "Captured " + filename)
	frames.append({"file": filename, "size": [size.x, size.y], "mode": mode})
