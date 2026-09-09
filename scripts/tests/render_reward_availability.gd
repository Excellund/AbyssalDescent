extends "res://scripts/tests/test_reward_availability.gd"
var frames: Array[Dictionary] = []

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-reward-availability-render")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "veilstrider"
	RunContext.current_difficulty_tier = 1
	RunContext.restore_active_catalysts("veilstrider", [])
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	_new_main()
	var ui: Node = world.reward_selection_ui
	ui.close_selection()
	for entry in world.power_registry_instance.get_trial_power_pool(world.player):
		for _level in int(entry.stack_limit):
			world.player.apply_trial_power(String(entry.id))
	for entry in world.power_registry_instance.get_boss_reward_pool(world.player):
		for _level in int(entry.stack_limit):
			world.player.apply_upgrade(String(entry.id))
	var folder := project_path.path_join("reward_availability_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	for spec in [{"size":Vector2i(1280,720),"mode":ENUMS.RewardMode.ARCANA,"title":"Choose Arcana","name":"arcana_empty_1280"}, {"size":Vector2i(960,720),"mode":ENUMS.RewardMode.BOSS,"title":"Claim Boss Reward","name":"boss_empty_960"}]:
		root.size = spec.size
		root.content_scale_size = spec.size
		world._open_boon_selection(spec.title, false, spec.mode, {}, "", world.current_character_id)
		var deadline := Time.get_ticks_msec() + 3000
		while not ui.skip_button.visible and Time.get_ticks_msec() < deadline:
			await process_frame
		check(ui.skip_button.visible and ui.boon_choices.is_empty(), "Actual empty reward reaches its rendered Continue state")
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := folder.path_join(spec.name + ".png")
		check(image.save_png(path) == OK, "Actual Main empty-state frame saves")
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(spec.size))
		check(viewport_rect.encloses(ui.skip_button.get_global_rect()) and viewport_rect.encloses(ui.boon_subtitle_label.get_global_rect()), "Empty text and Continue remain in viewport")
		frames.append({"name":spec.name,"path":path})
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = ui.skip_button.get_global_rect().get_center()
		click.pressed = true
		root.push_input(click, true)
		var release := click.duplicate() as InputEventMouseButton
		release.pressed = false
		root.push_input(release, true)
		await process_frame
		check(not ui.is_active() and world.choosing_next_room and not world.door_options.is_empty(), "Native GUI click on rendered empty Continue advances real World")
	await _free_main()
	check(await audio_retirement.wait_until_retired(self), "Native render audio retires")
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	FileAccess.open(folder.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"frames":frames,"failures":failures},"\t"))
	print("[RewardAvailabilityGPU] %d frames, %d checks, %d failures" % [frames.size(),checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
