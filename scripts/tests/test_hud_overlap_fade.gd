extends "res://scripts/tests/test_run_scene_ownership.gd"
## Actual Main movement, modal/room transitions, and focused viewport/owner bounds.

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	ProjectSettings.set_setting("application/config/version", "dev-hud-overlap-fixture")
	RunContext.telemetry_upload_enabled = false
	RunContext.telemetry_consent_asked = true
	RunContext.set_profile_name("FixturePilot", false)
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.selected_character_id = "bastion"
	RunContext.current_difficulty_tier = 0
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var profiles := PROFILE.new()
	var profile := profiles.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	profiles.save_profile(profile)
	root.size = Vector2i(960, 720)
	root.content_scale_size = Vector2i(960, 720)
	node_added.connect(_disable_debug_before_ready)
	node_added.connect(audio_retirement.observe_node)
	active_world = MAIN.instantiate() as WORLD
	active_world.get_node("DebugSettings").enabled = false
	root.add_child(active_world)
	current_scene = active_world
	_pick_reward({"rewards": []})
	active_world._refresh_frame_ui()
	check(active_world.encounter_intro_grace_active and not active_world._get_hud_state().combat_hud_overlap_fade_enabled, "Accepted initial reward enters survey with overlap fading disabled")
	check(_both_restored(), "Survey starts with fully readable Stats and build")
	# This fixed screen-space route tests native movement and HUD projection.
	# Biome terrain has independent collision coverage and may block the route;
	# stage a clear arena without changing input, camera or encounter state.
	active_world._clear_room_obstacles()
	await process_frame
	var actor: Node = active_world.player
	var start: Vector2 = actor.global_position
	await _walk_to_screen_axis("move_down", 1, 440.0, true)
	await _walk_to_screen_axis("move_left", 0, 220.0, false)
	await _walk_to_screen_axis("move_up", 1, 350.0, false)
	check(not active_world.encounter_intro_grace_active and actor.global_position.x < start.x - 80.0, "Native Move engages and moves into the left HUD area")
	check(_stats_faded() and is_equal_approx(active_world.hud.build_strip_panel.modulate.a, 1.0), "Ordinary movement fades only the overlapped Stats parent")
	check(active_world.hud.stats_label.modulate.a == 1.0 and active_world.hud.status_panel.modulate.a == 1.0, "Stats text inherits its parent fade; status remains unchanged")
	active_world.set_process(false)
	actor.set_physics_process(false)
	active_world.player_camera.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	await _check_modals()
	await _check_projected_bounds()
	await _check_build_bounds()
	_check_owner_lifetime()
	await _check_room_reset()
	_check_outcomes()
	current_scene = null
	active_world.queue_free()
	active_world = null
	await process_frame
	await process_frame
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Scene audio retires before the isolated fixture exits")
	print("[HUDOverlap] ", checks, " checks, ", failures.size(), " failures")
	call_deferred("quit", 0 if failures.is_empty() else 1)


func _stats_faded() -> bool:
	return is_equal_approx(active_world.hud.stats_panel.modulate.a, active_world.hud.COMBAT_OVERLAP_ALPHA)


func _walk_to_screen_axis(action: String, axis: int, target: float, increasing: bool) -> void:
	Input.action_press(action)
	for frame in 210:
		await physics_frame
		await process_frame
		var coordinate: float = (root.get_canvas_transform() * active_world.player.global_position)[axis]
		if coordinate >= target if increasing else coordinate <= target:
			break
	Input.action_release(action)


func _both_restored() -> bool:
	return is_equal_approx(active_world.hud.stats_panel.modulate.a, 1.0) and is_equal_approx(active_world.hud.build_strip_panel.modulate.a, 1.0)


func _place_at_screen(point: Vector2) -> void:
	active_world.player.global_position = root.get_canvas_transform().affine_inverse() * point
	active_world._refresh_frame_ui()


func _stats_center() -> Vector2:
	return active_world.hud.stats_panel.get_global_rect().get_center()


func _check_modals() -> void:
	active_world.pause_menu_controller.open()
	active_world._process(0.0)
	check(active_world.player.combat_damage_enabled and not active_world._get_hud_state().combat_hud_overlap_fade_enabled and _both_restored(), "Actual Pause restores panels even though the ordinary damage flag remains enabled")
	active_world.build_detail_panel.open()
	active_world.pause_menu_controller.close()
	active_world._process(0.0)
	check(active_world.build_detail_panel.is_open() and _both_restored(), "Closing Pause beneath open Build Details keeps panels readable")
	active_world.build_detail_panel.close()
	active_world._process(0.0)
	check(_stats_faded(), "Closing the final modal resumes the existing overlap fade")
	await process_frame


func _check_projected_bounds() -> void:
	var actor: Node = active_world.player
	var camera: Camera2D = active_world.player_camera
	var body: CollisionShape2D = actor.get_node("CollisionShape2D")
	camera.limit_left = -100000
	camera.limit_right = 100000
	camera.limit_top = -100000
	camera.limit_bottom = 100000
	camera.zoom = Vector2(0.75, 1.4)
	camera.offset = Vector2(38.0, -17.0)
	camera.force_update_scroll()
	actor.scale = Vector2(1.25, 0.8)
	body.position = Vector2(7.0, -4.0)
	await process_frame
	active_world._refresh_frame_ui()
	_place_at_screen(Vector2(600.0, 350.0))
	check(_both_restored(), "Moving out restores both panels with an offset, nonuniform camera zoom")
	var stats: Rect2 = active_world.hud.stats_panel.get_global_rect()
	# Actual rectangular body half-width is 16 * owner-scale * camera-zoom.
	# Put its center outside Stats, while its near edge and 6px margin overlap.
	var half_width := 16.0 * 1.25 * 0.75
	var projected_body_offset := 7.0 * 1.25 * 0.75
	var owner_x := stats.end.x + half_width + 6.0 - 2.0 - projected_body_offset
	_place_at_screen(Vector2(owner_x, stats.get_center().y))
	check(not stats.has_point(root.get_canvas_transform() * actor.global_position) and _stats_faded(), "Projected body edge triggers fading before its center enters Stats, without double-scaling")
	_place_at_screen(Vector2(owner_x + 3.0, stats.get_center().y))
	check(_stats_faded(), "Small boundary movement keeps the fade stable inside its exit margin")
	_place_at_screen(Vector2(owner_x + 9.0, stats.get_center().y))
	check(_both_restored(), "Leaving the exit margin restores Stats without a pending tween")
	actor.scale = Vector2.ONE
	body.position = Vector2.ZERO
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE
	camera.force_update_scroll()
	await process_frame
	active_world._refresh_frame_ui()


func _check_build_bounds() -> void:
	var actor: Node = active_world.player
	actor.apply_trial_power("blast_drive")
	actor.apply_trial_power("razor_orbit")
	active_world._refresh_frame_ui()
	await process_frame
	await process_frame
	active_world._refresh_frame_ui()
	var hud: Node = active_world.hud
	var last_chip: Control = hud.build_strip_arcana_chips[1]
	check(hud.build_strip_panel.size.y == 0.0 and last_chip.is_visible_in_tree(), "Real populated build uses visible chips outside its zero-height parent")
	_place_at_screen(last_chip.get_global_rect().get_center())
	check(is_equal_approx(hud.build_strip_panel.modulate.a, hud.COMBAT_OVERLAP_ALPHA) and hud.stats_panel.modulate.a == 1.0, "Visible lower Arcana chip fades the whole build parent independently of Stats")
	check(hud.build_strip_passive_chip.modulate.a == 1.0 and hud.build_strip_arcana_labels[1].modulate.a == 1.0, "Passive and power text inherit the one parent fade without individual alpha mutation")
	var state: Dictionary = active_world._get_hud_state()
	state.active_arcana = []
	state.active_boons = []
	state.active_boss_rewards = []
	hud.refresh(state, actor)
	check(not last_chip.visible and hud.build_strip_panel.modulate.a == 1.0, "Hidden old chip bounds do not keep an empty build row faded")
	hud.refresh(active_world._get_hud_state(), actor)
	await process_frame
	_place_at_screen(Vector2(600.0, 600.0))
	check(_both_restored(), "Leaving visible build content restores its parent")


func _check_owner_lifetime() -> void:
	var actor: Node = active_world.player
	_place_at_screen(_stats_center())
	check(_stats_faded(), "Valid local owner beneath Stats fades it")
	actor.is_local_player = false
	active_world._refresh_frame_ui()
	check(_both_restored(), "A supplied nonowner cannot fade panels even while the camera still follows that actor")
	actor.is_local_player = true
	active_world._refresh_frame_ui()
	actor.hide()
	active_world._refresh_frame_ui()
	check(_both_restored(), "Hidden local owner restores panel readability")
	actor.show()
	actor.set_alive(false)
	active_world._refresh_frame_ui()
	check(_both_restored(), "Downed local owner restores panels without borrowing an ally or camera target")
	actor.set_alive(true)
	active_world._refresh_frame_ui()
	actor.set_combat_removed(true)
	active_world._refresh_frame_ui()
	check(_both_restored(), "Combat removal restores panels immediately")
	actor.set_combat_removed(false)
	actor.set_physics_process(false)
	active_world._refresh_frame_ui()
	active_world.player = null
	active_world._refresh_frame_ui()
	check(_both_restored(), "Missing local owner restores a previously faded panel")
	active_world.player = actor
	active_world._refresh_frame_ui()
	check(_stats_faded(), "Returning valid owner recomputes overlap rather than retaining the old reset")
	var legacy_state: Dictionary = active_world._get_hud_state()
	legacy_state.erase("combat_hud_overlap_fade_enabled")
	active_world.hud.refresh(legacy_state, actor)
	check(_both_restored(), "Older presentation callers without the additive flag remain fully readable")


func _check_room_reset() -> void:
	# Use the existing actual enemy clear/reward helper, then a generated door.
	active_world.player.scale = Vector2.ONE
	active_world.player.global_position = Vector2.ZERO
	active_world.set_process(true)
	await _clear_first_room_to_checkpoint()
	active_world.set_process(false)
	check(active_world.choosing_next_room and not active_world.door_options.is_empty(), "Native room clear and accepted reward reach generated doors")
	_place_at_screen(_stats_center())
	check(not active_world._get_hud_state().combat_hud_overlap_fade_enabled and _both_restored(), "Door selection keeps panels readable even beneath the local player")
	var door: Dictionary = active_world.door_options[0]
	active_world.player.global_position = CONTRACTS.door_option_get_position(door)
	Input.action_press("interact")
	active_world._try_use_door()
	Input.action_release("interact")
	_place_at_screen(_stats_center())
	check(active_world.encounter_intro_grace_active and _both_restored(), "Actual next-door survey resets the previous room's overlap fade")
	Input.action_press("move_right")
	active_world._update_encounter_intro_grace()
	Input.action_release("move_right")
	active_world._refresh_frame_ui()
	check(not active_world.encounter_intro_grace_active and _stats_faded(), "Engage in the new room recomputes overlap for the current local owner")


func _check_outcomes() -> void:
	active_world._run_outcome_coordinator.register_victory(false, 0)
	active_world._refresh_frame_ui()
	check(not active_world._get_hud_state().combat_hud_overlap_fade_enabled and _both_restored(), "Terminal victory state restores panels independently of the player's damage flag")
	active_world._run_outcome_coordinator.reset_for_new_run()
	active_world._refresh_frame_ui()
	active_world.player.take_damage(1000000, {"source": "fixture_hud_death"})
	active_world._refresh_frame_ui()
	check(active_world.defeat_screen.is_open() and _both_restored(), "Actual lethal damage and defeat callbacks restore panels")
