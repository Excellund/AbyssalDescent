extends "res://scripts/tests/test_descent_presentation.gd"
## Real Main entry, ordinary builder profiles, colliders, camera and HUD.
## Four-player frame stages production characters locally; it is not a network test.

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const CHARACTERS := preload("res://scripts/character_registry.gd")
const NORMAL_SIZE := Vector2i(1280, 720)
const NARROW_SIZE := Vector2i(960, 720)
var frames: Array[Dictionary] = []
var output_directory := ""

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Biome identity GPU fixture requires an isolated real renderer")
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-biome-identity-gpu")
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
	output_directory = ProjectSettings.globalize_path("res://biome_identity_frames")
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
		await _capture("room_" + biome_id, biome_id, false)
		await _resize(NARROW_SIZE)
		world.hud._on_biome_header_entered()
		world.hud._process(world.hud.BIOME_HOVER_DELAY + 0.1)
		await _capture("tooltip_960_" + biome_id, biome_id, true)
		world.hud._on_biome_header_exited()
	await _enter_biome("convergence_end", NORMAL_SIZE)
	_stage_party()
	await _capture("party_convergence_end", "convergence_end", false)
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
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after Main is released")
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures, "scope": "Nine production ordinary-room terrains and entry hints, nine narrow-screen HUD tooltips, one locally staged four-character party. Multiplayer transport is checked separately."}, "\t"))
	print("[OK] Biome identity GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _enter_biome(biome_id: String, frame_size: Vector2i) -> void:
	world._clear_all_enemies()
	var biome := BIOMES.get_biome(biome_id)
	var act := int(biome.act)
	world.first_boss_defeated = act >= 2
	world.second_boss_defeated = act >= 3
	world.run_session.act_biome_ids[act - 1] = biome_id
	world._last_announced_act = 0
	world._apply_active_biome(act)
	world.encounter_profile_builder.rng.seed = 196443
	var encounter: Dictionary = world.encounter_profile_builder.build_debug_encounter_profile("crossfire", 5)
	var expected := CONTRACTS.profile_obstacle_layout(encounter)
	world._begin_room(encounter)
	world._sync_renderer()
	world.player.global_position = Vector2.ZERO
	world.player.set_physics_process(false)
	world.enemy_spawner.set_process(false)
	world.enemy_spawner.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	if is_instance_valid(world.hud.room_banner_tween):
		world.hud.room_banner_tween.pause()
	world.hud.room_banner_title_label.modulate.a = 1.0
	world.hud.room_banner_subtitle_label.modulate.a = 1.0
	check(world.renderer.environment_biome_id == biome_id, "Main renders the requested biome: " + biome_id)
	check(world.renderer.obstacle_layout == expected, "Rendered terrain equals the real builder profile: " + biome_id)
	check(world._active_obstacle_nodes.size() == expected.size(), "Physical cover count equals the builder profile: " + biome_id)
	for index in mini(expected.size(), world._active_obstacle_nodes.size()):
		var body: StaticBody2D = world._active_obstacle_nodes[index]
		check(body.global_position.is_equal_approx(expected[index].pos), "Cover collider position matches visible terrain: %s/%d" % [biome_id, index])
		var owners := body.get_shape_owners()
		check(owners.size() == 1, "Cover has one shape owner")
		if owners.size() == 1:
			var circle := body.shape_owner_get_shape(owners[0], 0) as CircleShape2D
			check(circle != null and is_equal_approx(circle.radius, float(expected[index].radius)), "Cover collision radius matches builder terrain: %s/%d" % [biome_id, index])
	var identity := BIOMES.get_combat_identity(biome_id)
	check(world.hud.room_banner_subtitle_label.text.contains(String(identity.entry_hint)), "Real entry shows the biome's positioning hint: " + biome_id)
	await _resize(frame_size)

func _resize(frame_size: Vector2i) -> void:
	root.size = frame_size
	root.content_scale_size = frame_size
	await process_frame
	world._apply_camera_bounds_for_room(world.current_effective_room_size)
	world._update_camera_mode()
	world.player_camera.set_physics_process(false)
	world.player_camera.global_position = Vector2.ZERO
	world.player_camera.zoom = world.player_camera.target_zoom
	world.player_camera.force_update_scroll()
	world.hud.refresh(world._get_hud_state(), world.player)
	world.renderer.queue_redraw()
	await process_frame

func _capture(frame_name: String, biome_id: String, tooltip: bool) -> void:
	await process_frame
	await process_frame
	world.hud.refresh(world._get_hud_state(), world.player)
	await RenderingServer.frame_post_draw
	var bounds := root.get_visible_rect()
	var title: Label = world.hud.room_banner_title_label
	var subtitle: Label = world.hud.room_banner_subtitle_label
	check(bounds.encloses(title.get_global_rect()), "Entry title stays on screen: " + frame_name)
	check(bounds.encloses(subtitle.get_global_rect()), "Entry hint stays on screen: " + frame_name)
	check(subtitle.get_minimum_size().y <= subtitle.size.y + 0.01, "Complete entry hint fits its label: " + frame_name)
	check(title.get_minimum_size().x <= bounds.size.x, "Entry title does not overflow the viewport: " + frame_name)
	if tooltip:
		var panel: PanelContainer = world.hud._biome_tooltip_panel
		var content: RichTextLabel = world.hud._biome_tooltip_content
		var tooltip_layer := panel.get_canvas_layer_node()
		var banner_layer := title.get_canvas_layer_node()
		check(tooltip_layer.layer > banner_layer.layer, "Biome tooltip draws above the entry banner: " + biome_id)
		check(not tooltip_layer.follow_viewport_enabled, "Biome tooltip retains screen coordinates: " + biome_id)
		check(panel.visible and bounds.encloses(panel.get_global_rect()), "Biome tooltip fits narrow viewport: " + biome_id)
		check(content.get_content_height() <= content.size.y + 0.01, "Complete biome tooltip is readable without clipping: " + biome_id)
		check(content.get_parsed_text().to_lower().contains(String(BIOMES.get_combat_identity(biome_id).terrain).to_lower()), "Tooltip names the live terrain: " + biome_id)
		check(not content.get_parsed_text().contains("{kw:"), "Tooltip resolves combat semantic spans: " + biome_id)
	var frame_path := output_directory.path_join(frame_name + ".png")
	check(root.get_texture().get_image().save_png(frame_path) == OK, "GPU frame saves: " + frame_name)
	frames.append({"name": frame_name, "path": frame_path, "biome": biome_id, "size": root.size, "obstacles": world.renderer.obstacle_layout.size(), "camera_zoom": world.player_camera.zoom})
	print("[FRAME] " + frame_path)

func _stage_party() -> void:
	var ids := ["bastion", "hexweaver", "veilstrider", "riftlancer"]
	var positions := [Vector2(-105.0, -65.0), Vector2(105.0, -65.0), Vector2(-105.0, 65.0), Vector2(105.0, 65.0)]
	for index in ids.size():
		var member = world.player if index == 0 else PLAYER_SCENE.instantiate()
		if index > 0:
			world.add_child(member)
		member.apply_character_package(CHARACTERS.get_character(ids[index]))
		member.global_position = positions[index]
		member.set_physics_process(false)
		member.encounter_input_frozen = true
		var extra_camera := member.get_node_or_null("Camera2D") as Camera2D
		if index > 0 and extra_camera != null:
			extra_camera.enabled = false
	world.player_camera.make_current()
	world.player_camera.force_update_scroll()
