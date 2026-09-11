extends "res://scripts/tests/render_biome_identity.gd"
## Eighteen real Main frames: warning/active for eight timed rules, then intact/
## opened Shatterfield cover. Actors remain staged; runtime and ENet prove damage.
## render_gameplay_fixture.ps1 -FixtureScript res://scripts/tests/render_biome_rules.gd
## -FrameFolder biome_rules_frames -ExpectedFrames 18 -MaxFrames 1600

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Biome rules GPU fixture requires an isolated real renderer")
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-biome-rules-gpu")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "veilstrider"
	RunContext.current_difficulty_tier = 1
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	root.size = NORMAL_SIZE
	root.content_scale_size = NORMAL_SIZE
	output_directory = ProjectSettings.globalize_path("res://biome_rules_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.set_physics_process(false)
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	world.run_session.act_biome_ids = ["crumble", "grinding_vault", "void_breach"]
	for biome_id: String in BIOMES.BIOME_DEFINITIONS:
		await _enter_biome(biome_id, NORMAL_SIZE)
		check(is_instance_valid(world._biome_rules), "Main owns the production biome rule controller: " + biome_id)
		if not is_instance_valid(world._biome_rules):
			continue
		world._biome_rules.set_process(false)
		if biome_id == "shatterfield":
			await _capture_rule("shatterfield_intact", biome_id, "intact")
			for cover_id in [2, 3]:
				for _contact in range(3):
					world._arena_cover.apply_contact(cover_id)
			world._refresh_arena_cover_geometry()
			check(world.renderer.obstacle_layout.size() == 2 and world.renderer.cover_rubble_layout.size() == 2, "Shatterfield's opened lane removes inner cover and leaves readable rubble")
			await _capture_rule("shatterfield_opened", biome_id, "opened")
			continue
		var warning := _advance_rule_phase("warning", [world.player])
		var warned_shape: Dictionary = warning.get("shape", {})
		check(String(warning.get("id", "")) == biome_id and not warned_shape.is_empty(), "Actual room setup selects its own visible rule: " + biome_id)
		await _capture_rule(biome_id + "_warning", biome_id, "warning")
		if biome_id == "storm_reach":
			world.player.global_position = Vector2(330.0, 240.0)
		var active := _advance_rule_phase("active", [])
		check(active.get("shape", {}) == warned_shape, "The active area matches the warning the player saw: " + biome_id)
		await _capture_rule(biome_id + "_active", biome_id, "active")
	world.player.discard_pending_combat_input()
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after biome-rule Main is released")
	check(frames.size() == 18, "All nine biomes have both requested visual states")
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures, "scope": "Production Main terrain, rule controller and HUD. Eight warning/active pairs; Shatterfield intact/opened pair. Idle actors make telegraph inspection repeatable; damage and network boundaries are verified separately."}, "\t"))
	print("[OK] Biome rules GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _advance_rule_phase(phase: String, players: Array) -> Dictionary:
	for _step in range(8):
		var state: Dictionary = world._biome_rules.snapshot()
		if String(state.get("phase", "")) == phase:
			return state
		world._biome_rules.tick(100.0, true, players, [], true)
	check(false, "Production rule reaches the requested capture phase: " + phase)
	return world._biome_rules.snapshot()

func _capture_rule(frame_name: String, biome_id: String, phase: String) -> void:
	world._biome_rules.queue_redraw()
	await _capture(frame_name, biome_id, false)
	frames[-1]["phase"] = phase
	frames[-1]["rule_state"] = world._biome_rules.snapshot()
