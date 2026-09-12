extends "res://scripts/tests/test_build_keyword_overview.gd"

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
	var folder := project_path.path_join("keyword_overview_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	_seed_overview()
	for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		build.refresh_from_player(player, "bastion")
		build.open(true)
		await _capture(folder, "hybrid_" + str(size.x))
		build.keyword_overview_toggle.button_pressed = true
		_keyword_button("electric").pressed.emit()
		await _capture(folder, "electric_sources_" + str(size.x))
		build.close()
	for id: String in REGISTRY.TRIAL_POWER_POOL_IDS:
		for _level in range(3):
			player.apply_trial_power(id)
	for id: String in REGISTRY.BOSS_REWARD_BALANCE:
		player.apply_upgrade(id)
	for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		build.refresh_from_player(player, "bastion")
		build.open(true)
		await _capture(folder, "full_roster_" + str(size.x))
		build.keyword_overview_toggle.button_pressed = true
		await _capture(folder, "full_breakdown_" + str(size.x))
		build.close()
	var hud := HUD.new()
	viewport.add_child(hud)
	hud.setup(5)
	var empty_mutators: Array[Dictionary] = []
	hud.refresh({"current_character_passive_name": "iron_retort", "active_player_mutators": empty_mutators}, player)
	for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		hud._layout_hud_panels(Vector2(size), Vector2.ZERO, Transform2D.IDENTITY)
		await _capture(folder, "hud_" + str(size.x))
		_check(hud.build_keyword_label.get_content_height() <= hud.build_keyword_label.size.y and hud.build_keyword_label.get_content_height() <= 23.0, "HUD summary fits one line")
	hud.free()
	ui.close_selection()
	viewport.free()
	registry.free()
	_free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Overview GPU audio retires")
	FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures}, "\t"))
	print("[OK] Build keywords GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture(folder: String, label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := folder.path_join(label + ".png")
	_check(viewport.get_texture().get_image().save_png(path) == OK, "Saved " + label)
	if build.is_open():
		_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(build.panel.get_global_rect()), "Build panel fits " + label)
		for flow: HFlowContainer in [build.keyword_effect_flow, build.keyword_action_flow]:
			if not flow.is_visible_in_tree():
				continue
			for button in flow.get_children():
				_check(flow.get_global_rect().encloses(button.get_global_rect()), "Keyword chip fits " + label)
		_check(build.keyword_source_details.get_content_height() <= build.keyword_source_details.size.y or not build.keyword_source_details.visible, "Source list fully laid out " + label)
	frames.append({"name": label, "path": path})
