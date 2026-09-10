extends "res://scripts/tests/test_reward_build_inspection.gd"

var frames: Array[Dictionary] = []

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	var retirement := AUDIO_RETIREMENT.new()
	node_added.connect(retirement.observe_node)
	_setup_ui()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var folder := project_path.path_join("reward_build_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	for id in ["blast_drive", "razor_orbit", "returning_crescent", "static_wake", "storm_crown"]:
		player.apply_trial_power(id)
		player.apply_trial_power(id)
	player.apply_upgrade("sovereigns_double")
	player.apply_upgrade("sovereigns_double")
	player.apply_trial_power("aegis_field")
	player.apply_trial_power("hunters_snare")
	for _pick in range(4):
		player.apply_trial_power("phantom_step")
	for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		ui.initialize(3, 0.0)
		_show_arcana()
		await _capture(folder, "arcana_three_" + str(size.x))
		ui.close_selection()
		ui.initialize(4, 0.0)
		_show_arcana()
		await _capture(folder, "arcana_" + str(size.x))
		ui.boon_hovered_index = 3
		ui._request_build_inspection()
		await _capture(folder, "build_top_" + str(size.x))
		_owned_toggle("Blast Drive").grab_focus()
		await _press_pad(JOY_BUTTON_A)
		await _capture(folder, "build_keywords_" + str(size.x))
		await _press_pad(JOY_BUTTON_DPAD_DOWN)
		await _press_pad(JOY_BUTTON_DPAD_DOWN)
		await _capture(folder, "build_keywords_middle_" + str(size.x))
		for entry in build.arcana_list_container.get_children():
			if entry.get_child_count() > 0 and entry.get_child(0) is Button and String(entry.get_child(0).text).contains("Phantom Step"):
				build._scroll.ensure_control_visible(entry)
				break
		await _capture(folder, "build_prismatic_" + str(size.x))
		build._scroll.scroll_vertical = 100000
		await _capture(folder, "build_owned_" + str(size.x))
		build.close()
		ui.close_selection()
		_open(ENUMS.RewardMode.MISSION, {"name": "Combo Relay", "icon_shape_id": "combo_relay"})
		ui._on_viewport_size_changed()
		ui._apply_global_ui_alpha(1.0)
		await _capture(folder, "mission_" + str(size.x))
		ui.close_selection()
	_free_world()
	_make_world(0)
	for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		ui.initialize(3, 0.0)
		_show_native_page(["static_wake", "wraithstep", "dread_resonance"], ENUMS.RewardMode.ARCANA)
		await _capture(folder, "unowned_engines_" + str(size.x))
		ui.close_selection()
		for mode in [ENUMS.RewardMode.ARCANA, ENUMS.RewardMode.BOSS]:
			var ids: Array = REGISTRY.TRIAL_POWER_POOL_IDS if mode == ENUMS.RewardMode.ARCANA else REGISTRY.BOSS_REWARD_POOL_IDS
			var category := "arcana" if mode == ENUMS.RewardMode.ARCANA else "boss"
			for page in range(ceili(float(ids.size()) / 3.0)):
				_show_native_page(ids.slice(page * 3, page * 3 + 3), mode)
				await _capture(folder, "unowned_%s_%d_%d" % [category, page, size.x])
				ui.close_selection()
		ui.initialize(4, 0.0)
		_show_native_page(["static_wake", "wraithstep", "dread_resonance", "storm_crown"], ENUMS.RewardMode.ARCANA)
		await _capture(folder, "unowned_four_" + str(size.x))
		ui.close_selection()
	await _finish_render(retirement, folder)

func _finish_render(retirement: AUDIO_RETIREMENT, folder: String) -> void:
	ui.close_selection()
	viewport.free()
	registry.free()
	_free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Native render audio retires")
	FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures}, "\t"))
	print("[RewardBuildGPU] %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _show_arcana() -> void:
	_open()
	ui.boon_choices.clear()
	for id in ["blast_drive", "razor_orbit", "returning_crescent", "storm_crown"].slice(0, ui.boon_choice_count):
		ui.boon_choices.append({"id": id, "name": registry.get_power_display_name(id), "desc": player.get_trial_power_card_desc(id), "stack_limit": registry.get_power_stack_limit(id)})
	ui._refresh_boon_ui(player)
	ui._on_viewport_size_changed()
	ui._apply_global_ui_alpha(1.0)

func _show_native_page(ids: Array, mode: int, expected_level: int = 0) -> void:
	_open(mode)
	ui.boon_choices.clear()
	for id: String in ids:
		var arcana := mode == ENUMS.RewardMode.ARCANA
		var actual_level: int = player.get_trial_power_stack_count(id) if arcana else player.get_upgrade_stack_count(id)
		_check(actual_level == expected_level, "Native comparison starts at owned level %d: %s" % [expected_level, id])
		ui.boon_choices.append({"id": id, "name": registry.get_power_display_name(id), "desc": player.get_trial_power_card_desc(id) if arcana else player.get_upgrade_card_desc(id), "stack_limit": registry.get_power_stack_limit(id)})
	ui._refresh_boon_ui(player)
	ui._on_viewport_size_changed()
	ui._apply_global_ui_alpha(1.0)

func _capture(folder: String, name_text: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := folder.path_join(name_text + ".png")
	_check(viewport.get_texture().get_image().save_png(path) == OK, "GPU frame saves: " + name_text)
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport.size))
	if build.is_open():
		_check(bounds.encloses(build.panel.get_global_rect()), "Build fits: " + name_text)
		_check(build.panel.get_global_rect().encloses(build._close_button.get_global_rect()), "Build close remains in panel: " + name_text)
	else:
		for index in range(ui.boon_card_labels.size()):
			var label: RichTextLabel = ui.boon_card_labels[index]
			if label.get_parent().visible:
				_check(label.get_content_height() <= label.size.y, "Highlighted card text fits: " + name_text)
				var title: Label = ui.boon_card_title_labels[index]
				_check(title.get_minimum_size().y <= title.size.y, "Complete card title fits: " + name_text)
				_check(float(label.get_theme_font_size("normal_font_size")) * label.get_global_transform().get_scale().abs().y >= 18.0 - 0.01, "Card body keeps readable effective font size: " + name_text)
		for button: Button in [ui.build_button, ui.reroll_button, ui.skip_button]:
			_check(bounds.encloses(button.get_global_rect()), "Reward action fits: " + name_text)
		if ui.mission_bonus_label.visible:
			_check(ui.mission_bonus_label.get_content_height() <= ui.mission_bonus_label.size.y, "Mission bonus fits: " + name_text)
	frames.append({"name": name_text, "path": path})
