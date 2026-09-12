extends "res://scripts/tests/test_enemy_field_guide.gd"

var frames: Array[Dictionary] = []

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	var folder := project_path.path_join("enemy_guide_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	_check_roster()
	_setup()
	viewport.size_2d_override = Vector2i(2560, 1440)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for size in SCREEN_SIZES:
		viewport.size = size
		menu._apply_menu_layout()
		await _check_section(GUIDE_LABEL, size)
		_check_back_button(menu.glossary_panel)
		await _check_navigation(menu.glossary_panel)
		await _capture_groups(folder, body, "menu", size)
		if size.x == 1280:
			await _capture_keyword_styles(folder, menu.glossary_panel, body, "menu")
	menu.hide()
	_setup_pause()
	for size in SCREEN_SIZES:
		viewport.size = size
		await _settle()
		_check_pause(size)
		_check_back_button(pause_panel)
		await _check_navigation(pause_panel)
		await _capture_groups(folder, pause_body, "pause", size)
		if size.x == 1280:
			await _capture_keyword_styles(folder, pause_panel, pause_body, "pause")
	viewport.free()
	await process_frame
	FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures}, "\t"))
	print("[OK] Enemy guide GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture_groups(folder: String, label: RichTextLabel, context: String, size: Vector2i) -> void:
	var paragraphs := label.get_parsed_text().split("\n")
	var headings: Array[String] = ["Enemy Field Guide", "Charger", "Lurker", "Ranged pressure", "Dangerous ground", "Tether", "Protection"]
	if size.y == 540:
		headings = ["Enemy Field Guide"]
		for row in DATA._enemy_rows():
			headings.append(String(row.name))
	for heading in headings:
		var paragraph := paragraphs.find(heading)
		_check(paragraph >= 0, "Capture finds the actual guide section: " + heading)
		label.scroll_to_paragraph(maxi(0, paragraph))
		await _settle()
		await RenderingServer.frame_post_draw
		var frame_name := "%s_%s_%dx%d" % [context, heading.to_snake_case(), size.x, size.y]
		var path := folder.path_join(frame_name + ".png")
		_check(viewport.get_texture().get_image().save_png(path) == OK, "Native glossary frame saves: " + frame_name)
		frames.append({"name": frame_name, "path": path})

func _capture_keyword_styles(folder: String, panel: Panel, label: RichTextLabel, context: String) -> void:
	var buttons := panel.find_children("*", "Button", true, false)
	for candidate in buttons:
		var button := candidate as Button
		if button.text == "Build Keywords":
			button.grab_focus()
			button.button_pressed = true
			button.pressed.emit()
			break
	await _settle()
	await RenderingServer.frame_post_draw
	_check(label.text.contains(KEYWORDS.keyword_bbcode("attack")), "Canonical keyword styling remains in the production " + context + " glossary")
	var path := folder.path_join(context + "_keyword_styles_1280x720.png")
	_check(viewport.get_texture().get_image().save_png(path) == OK, "Native keyword typography frame saves")
	frames.append({"name": context + "_keyword_styles", "path": path})
	for candidate in buttons:
		var button := candidate as Button
		if button.text == GUIDE_LABEL:
			button.grab_focus()
			button.button_pressed = true
			button.pressed.emit()
			break
	await _settle()
