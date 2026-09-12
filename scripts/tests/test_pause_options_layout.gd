extends "res://scripts/tests/test_run_oath_ui.gd"
## Existing settings controls remain readable within the physical Pause canvas.

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	viewport = SubViewport.new()
	viewport.size_2d_override = Vector2i(2560, 1440)
	viewport.size_2d_override_stretch = true
	root.add_child(viewport)
	controller = PAUSE.new()
	viewport.add_child(controller)
	controller.initialize("/root/RunContext", Callable(), Callable())
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720)]:
		viewport.size = window_size
		await _settle()
		controller.open()
		controller._options_button.pressed.emit()
		await create_timer(0.22).timeout
		_check_native_fit(controller.pause_options_panel, window_size, "Pause Options")
		check(not controller.pause_menu_panel.visible and controller._options_button.disabled, "Options retains its modal boundary")
		check(viewport.gui_get_focus_owner() == controller._pause_options_back, "Options opens with a visible Back action focused")
		var panel: Control = controller.pause_options_panel
		var scroll: ScrollContainer = controller._pause_options_scroll
		for control: Control in [controller._pause_options_title, controller._pause_options_back, scroll]:
			check(Rect2(Vector2.ZERO, panel.size).encloses(control.get_rect()), "Options header, viewport and Back remain inside the panel")
		for control: Control in controller._pause_options_body.get_children():
			check(Rect2(Vector2.ZERO, controller._pause_options_body.size).encloses(control.get_rect()), "Every existing setting fits the scrolling body")
			if control is Label or control is BaseButton:
				check(control.get_theme_font_size("font_size") * control.get_global_transform_with_canvas().get_scale().y * viewport.get_stretch_transform().get_scale().y >= 17.99, "Setting copy is at least 18 physical pixels")
			if control is Label:
				check(control.get_minimum_size().y <= control.size.y + 1, "Setting copy is not clipped")
		var needs_scroll := not _physical_rect(scroll).encloses(_physical_rect(controller.pause_telemetry_upload_checkbox))
		var old_scroll := scroll.scroll_vertical
		controller.pause_telemetry_upload_checkbox.grab_focus()
		await _settle()
		if needs_scroll:
			check(scroll.scroll_vertical > old_scroll, "Keyboard focus scrolls to an offscreen final setting")
		check(_physical_rect(scroll).grow(1).encloses(_physical_rect(controller.pause_telemetry_upload_checkbox)), "Final setting is fully visible after keyboard focus")
		check(controller.pause_telemetry_upload_checkbox.get_theme_icon("checked").get_width() >= 20 and controller.pause_telemetry_upload_checkbox.get_theme_icon("unchecked").get_width() >= 20, "Both telemetry states have legible outlined icons")
		controller._pause_options_back.grab_focus()
		await _settle()
		check(_physical_rect(panel).encloses(_physical_rect(controller._pause_options_back)), "Back remains fixed while the options body is scrolled")
		controller._pause_options_back.pressed.emit()
		check(controller.is_open() and not controller.is_options_open() and viewport.gui_get_focus_owner() == controller._options_button, "Options Back restores its main action and keeps Pause open")
		controller.close()
	# Resize during entrance: the final layout wins over the old animation.
	viewport.size = Vector2i(960, 540)
	await _settle()
	controller.open()
	controller._options_button.pressed.emit()
	viewport.size = Vector2i(1280, 720)
	await create_timer(0.24).timeout
	_check_native_fit(controller.pause_options_panel, viewport.size, "Resized Options")
	controller.close_options()
	controller._options_button.pressed.emit()
	await create_timer(0.22).timeout
	_check_native_fit(controller.pause_options_panel, viewport.size, "Reopened Options after resize")
	controller.close()
	viewport.free()
	await process_frame
	print("[OK] Pause Options layout: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _physical_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	var stretch := viewport.get_stretch_transform().get_scale()
	return Rect2(transform.origin * stretch, control.size * transform.get_scale() * stretch)
