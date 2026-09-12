extends "res://scripts/tests/test_enemy_field_guide.gd"
var frames: Array[Dictionary] = []

func _run() -> void:
	var folder := ProjectSettings.globalize_path("res://glossary_frames")
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(folder)
	_setup()
	viewport.size_2d_override = Vector2i(2560, 1440)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		menu._apply_menu_layout()
		for label in ["Build Keywords", "Character Passives", "Mutators"]:
			await _check_section(label, size)
			await RenderingServer.frame_post_draw
			var path := folder.path_join(label.to_snake_case() + "_" + str(size.x) + ".png")
			_check(viewport.get_texture().get_image().save_png(path) == OK, "Actual glossary GPU frame saves")
			frames.append({"name": label + str(size.x), "path": path})
			if label == "Character Passives":
				body.get_v_scroll_bar().value = body.get_v_scroll_bar().max_value
				await _settle()
				await RenderingServer.frame_post_draw
				path = folder.path_join("character_passives_lower_" + str(size.x) + ".png")
				_check(body.get_v_scroll_bar().value > 0.0 or body.get_content_height() <= body.size.y + 1.0, "Every concise passive is reachable or already fits")
				_check(viewport.get_texture().get_image().save_png(path) == OK, "Actual lower passive list GPU frame saves")
				frames.append({"name": "Character Passives lower" + str(size.x), "path": path})
		await _check_section("Encounters", size)
		await _capture_entry(folder, "Apex Breakwater", size)
	menu.hide()
	_setup_pause()
	for candidate in pause_panel.find_children("*", "Button", true, false):
		var button := candidate as Button
		_check(button.text != "Power Rules", "Pause glossary has no Power Rules navigation")
		if button.text == "Character Passives":
			button.grab_focus()
			button.button_pressed = true
			button.pressed.emit()
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		await _settle()
		_check(pause_body.text == DATA._character_passives_section_bbcode(), "Pause renders the same concise passive paragraphs at " + str(size))
		_check(Rect2(Vector2.ZERO, Vector2(2560, 1440)).encloses(pause_panel.get_global_rect()), "Pause passive glossary fits the production canvas")
		var rendered_size := pause_body.get_theme_font_size("normal_font_size") * pause_body.get_global_transform_with_canvas().get_scale().y * viewport.get_stretch_transform().get_scale().y
		_check(rendered_size >= 17.99, "Pause passive glossary retains 18 physical pixel type")
		_check_back_button(pause_panel)
		for at_bottom in [false, true]:
			pause_body.get_v_scroll_bar().value = pause_body.get_v_scroll_bar().max_value if at_bottom else 0.0
			await _settle()
			await RenderingServer.frame_post_draw
			var name := "pause_character_passives_%s_%d" % ["lower" if at_bottom else "top", size.x]
			var path := folder.path_join(name + ".png")
			_check(viewport.get_texture().get_image().save_png(path) == OK, "Native Pause passive frame saves")
			frames.append({"name": name, "path": path})
	viewport.free()
	await process_frame
	FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures}, "\t"))
	print("[OK] Glossary GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture_entry(folder: String, entry_name: String, size: Vector2i) -> void:
	var paragraphs := body.get_parsed_text().split("\n")
	var paragraph := -1
	for index in range(paragraphs.size()):
		if String(paragraphs[index]).begins_with(entry_name):
			paragraph = index
			break
	_check(paragraph >= 0, "The production glossary contains the requested entry: " + entry_name)
	if paragraph < 0:
		return
	body.scroll_to_paragraph(paragraph)
	await _settle()
	await RenderingServer.frame_post_draw
	var path := folder.path_join(entry_name.to_snake_case() + "_" + str(size.x) + ".png")
	_check(body.get_v_scroll_bar().value > 0.0, "The requested entry is scrolled into view: " + entry_name)
	_check(viewport.get_texture().get_image().save_png(path) == OK, "Actual entry GPU frame saves: " + entry_name)
	frames.append({"name": entry_name + str(size.x), "path": path})
