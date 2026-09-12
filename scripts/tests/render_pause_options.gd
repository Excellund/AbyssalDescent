extends "res://scripts/tests/render_run_oath_tracker.gd"
## Actual Main Options with production stretch and native keyboard GUI input.
const OPTIONS_SETTINGS := preload("res://scripts/settings_store.gd")

func _run() -> void:
	if not _is_isolated() or DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.content_scale_size = Vector2i(2560, 1440)
	frame_folder = ProjectSettings.globalize_path("res://pause_options_frames")
	DirAccess.make_dir_recursive_absolute(frame_folder)
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720)]:
		root.size = window_size
		await process_frame
		_setup_recovery_world()
		_enter_recovery()
		world._exit_encounter_intro_grace()
		await _settle_oaths()
		var pause_ui: Node = world.pause_menu_controller
		# The render helper already uses a window; mirror that isolated mode in
		# settings without applying or moving an operating-system window.
		RunContext.display_mode = OPTIONS_SETTINGS.DISPLAY_MODE_WINDOWED
		await _key(KEY_ESCAPE)
		await _settle_oaths(16)
		await _key(KEY_TAB)
		await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == pause_ui._options_button, "Native Pause traversal reaches Options")
		await _key(KEY_ENTER)
		await _settle_oaths(16)
		check(pause_ui.is_options_open() and root.gui_get_focus_owner() == pause_ui._pause_options_back, "Native Options opens with Back focused")
		_check_underlying_pause_hidden(pause_ui, "Options")
		pause_ui._pause_options_scroll.scroll_vertical = 0
		await _settle_oaths()
		await _capture("options_top", "Actual Main Options; production canvas and original settings callbacks")
		await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == pause_ui.pause_master_slider, "Native Tab enters the first setting")
		var old_volume: float = RunContext.master_volume_db
		await _key(KEY_RIGHT)
		check(RunContext.master_volume_db != old_volume, "Native slider change reaches the actual isolated settings callback")
		# Restore the fixture's muted state through the same existing callback.
		await _key(KEY_LEFT)
		check(is_equal_approx(RunContext.master_volume_db, old_volume), "Native slider reversal restores its original volume")
		for _step in 3:
			await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == pause_ui.pause_display_mode_selector, "Native Tab reaches the real display selector")
		await _key(KEY_ENTER)
		await _settle_oaths()
		var popup: PopupMenu = pause_ui.pause_display_mode_selector.get_popup()
		check(popup.visible, "Native Enter opens the actual display choices")
		await _capture("options_selector", "Actual display selector popup, opened then cancelled without changing display settings")
		# Route through the root's embedded-window dispatcher. Calling the
		# popup Viewport directly bypasses Popup::_input_from_window cancellation.
		await _key(KEY_ESCAPE)
		await _settle_oaths()
		check(not popup.visible and pause_ui.is_options_open(), "Cancelling display choices keeps Options open")
		await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == pause_ui.pause_resolution_selector and not pause_ui.pause_resolution_selector.disabled, "Native Tab reaches resolution in the fixture's windowed mode")
		await _key(KEY_ENTER)
		await _settle_oaths()
		var resolution_popup: PopupMenu = pause_ui.pause_resolution_selector.get_popup()
		check(resolution_popup.visible, "Native Enter opens the actual resolution choices")
		await _capture("options_resolution", "Actual resolution choices in the fixture's windowed mode; cancelled without applying a resolution")
		await _key(KEY_ESCAPE)
		await _settle_oaths()
		check(not resolution_popup.visible and pause_ui.is_options_open(), "Cancelling resolution choices keeps Options open")
		var needs_scroll := not _physical_rect(pause_ui._pause_options_scroll).encloses(_physical_rect(pause_ui.pause_telemetry_upload_checkbox))
		var old_scroll: int = pause_ui._pause_options_scroll.scroll_vertical
		for _step in 3:
			if root.gui_get_focus_owner() == pause_ui.pause_telemetry_upload_checkbox:
				break
			await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == pause_ui.pause_telemetry_upload_checkbox, "Native keyboard reaches the last available setting")
		await _settle_oaths()
		if needs_scroll:
			check(pause_ui._pause_options_scroll.scroll_vertical > old_scroll, "Native focus scrolls an offscreen final setting into view")
		check(_physical_rect(pause_ui._pause_options_scroll).grow(1).encloses(_physical_rect(pause_ui.pause_telemetry_upload_checkbox)), "Final setting fits within the visible scroller")
		await _capture("options_bottom", "Actual Options final setting reached through native Tab; telemetry remains disabled")
		await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == pause_ui._pause_options_back, "Native focus wraps to fixed Back")
		await _key(KEY_ENTER)
		check(pause_ui.is_open() and not pause_ui.is_options_open() and root.gui_get_focus_owner() == pause_ui._options_button, "Native Back restores Pause and Options focus")
		await _key(KEY_ESCAPE)
		check(not pause_ui.is_open(), "Escape resumes after closing Options")
		await _cleanup_recovery_world()
		node_added.disconnect(audio_retirement.observe_node)
	FileAccess.open(frame_folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name(), "scope": "Actual Main Options and native GUI input at production stretch. Audio settings changed only in disposable data and restored; display popup cancelled and telemetry disabled."}, "\t"))
	print("[OK] Pause Options GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
