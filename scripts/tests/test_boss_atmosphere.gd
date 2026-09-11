extends "res://scripts/tests/test_descent_presentation.gd"
## Actual Main doors, readiness, native bosses, rewards and result attribution.
const BOSSES := preload("res://scripts/shared/boss_catalogue.gd")
const STAGES := preload("res://scripts/shared/boss_stage_registry.gd")
const VICTORY := preload("res://scripts/victory_screen.gd")
const ALTERNATIVE := preload("res://scripts/enemy_boss_alternative.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-boss-atmosphere")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "veilstrider"
	RunContext.current_difficulty_tier = 1
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	root.size = Vector2i(960, 720)
	root.content_scale_size = root.size
	_test_summary_attribution()
	for id: String in BOSSES.NAMES:
		await _exercise_boss(id)
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after all boss scenes")
	await _finish_capture()
	print("[BossAtmosphere] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _exercise_boss(id: String) -> void:
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.set_physics_process(false)
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	world._clear_all_enemies()
	var stage := BOSSES.stage_for_id(id)
	world.first_boss_defeated = stage >= 2
	world.second_boss_defeated = stage >= 3
	world.run_session.act_boss_ids = BOSSES.normalize_roster(BOSSES.DEFAULT_IDS)
	world.run_session.act_boss_ids[stage - 1] = id
	world._choose_door(CONTRACTS.boss_door_option(BOSSES.DEFAULT_IDS[stage - 1]))
	world.player.set_physics_process(false)
	world.enemy_spawner.set_process(false)
	world.enemy_spawner.set_physics_process(false)
	var boss: Node2D
	for enemy: Node in get_nodes_in_group("enemies"):
		if not enemy.is_queued_for_deletion() and String(enemy.get_meta("boss_id", "")) == id:
			boss = enemy as Node2D
			enemy.set_physics_process(false)
	check(is_instance_valid(boss), id + ": the actual door creates the selected native boss")
	if not is_instance_valid(boss):
		await _dispose_world()
		return
	world._sync_renderer()
	world.hud.refresh(world._get_hud_state(), world.player)
	check(world.encounter_intro_grace_active and boss.target == null and world.player.encounter_input_frozen, id + ": greeting belongs to the existing passive survey phase")
	check(world.hud.boss_intro_visible and world.hud.room_banner_title_label.text == STAGES.get_descriptor(stage, id).banner_title and world.hud.room_banner_subtitle_label.text.contains(BOSSES.get_greeting(id)), id + ": the survey attributes the exact selected boss's greeting")
	check(world.hud._status_hint_label.visible and world.hud._status_hint_label.text.contains("Move or Attack"), id + ": readiness remains separate from the spoken line")
	var greeting: String = world.hud.room_banner_subtitle_label.text
	world.hud.room_banner_tween.custom_step(8.0)
	check(world.hud.boss_intro_visible and world.hud.room_banner_subtitle_label.modulate.a > .99, id + ": taking time to survey does not expire the greeting")
	world.pause_menu_controller.open()
	world.pause_menu_controller.close()
	check(world.encounter_intro_grace_active and world.hud.boss_intro_visible and world.hud.room_banner_subtitle_label.text == greeting, id + ": Pause returns to the same survey without starting combat")
	if id == "warden":
		world.hud.show_persistent_banner("Ready", "Waiting for allies...")
		world.hud.hide_boss_intro()
		check(world.hud.room_banner_title_label.text == "Ready" and world.hud.room_banner_persistent_visible and world.hud.room_banner_subtitle_label.modulate.a == 1.0, "Clearing obsolete dialogue cannot hide higher-priority co-op waiting")
		check(world.hud.room_banner_title_label.autowrap_mode == TextServer.AUTOWRAP_OFF and world.hud.room_banner_subtitle_label.autowrap_mode == TextServer.AUTOWRAP_OFF, "Ready restores the existing ordinary banner layout")
		world.hud.show_boss_intro(String(STAGES.get_descriptor(stage, id).banner_title), BOSSES.get_greeting(id))
		world.hud.room_banner_tween.custom_step(.3)
	await _capture_phase("greeting_" + id, "greeting")
	world._signal_local_player_ready()
	check(not world.encounter_intro_grace_active and not world.player.encounter_input_frozen and boss.target != null, id + ": the existing readiness action starts combat immediately")
	check(not world.hud.boss_intro_visible and world.hud.room_banner_title_label.modulate.a == 0.0 and world.hud.room_banner_subtitle_label.modulate.a == 0.0, id + ": dialogue and Engage are absent before any live attack warning")
	world._broadcast_all_players_ready(world.get_current_room_sync_id())
	check(not world.hud.boss_intro_visible, id + ": duplicate readiness cannot replay an introduction")
	boss.spawn_transport_time_left = 0.0
	boss.global_position = Vector2(90, 0)
	world.player.global_position = Vector2(-160, 0)
	if boss is ALTERNATIVE:
		boss.begin_attack(0)
		boss._process_behavior(float(boss.warning_duration) * .5)
		check(not boss.get_attack_warning_geometry().is_empty(), id + ": real alternative warning is committed after greeting dismissal")
	else:
		boss._start_next_attack(250.0, 0.0)
		boss._process_behavior(float(boss.state_time_left) * .5)
		check(float(boss.telegraph_alpha) > 0.0, id + ": real original boss warning is visible after greeting dismissal")
		if id == "lacuna":
			check(is_instance_valid(boss._attack_overlay) and boss._attack_overlay.telegraph_active, "Lacuna's actual world-space warning overlay is active before capture")
	boss.queue_redraw()
	await _capture_phase("combat_" + id, "combat")
	boss.health_state.set_health(0)
	world._update_encounter_state()
	var caption := String(BOSSES.NAMES[id]) + ": \"" + BOSSES.get_defeat_line(id) + "\""
	check(world.last_defeated_boss_id == id and not world.hud.boss_intro_visible, id + ": native boss death retains the defeated speaker and retires the greeting")
	if stage < 3:
		check(world.reward_selection_ui.is_active() and world.reward_selection_ui._epitaph_text == caption, id + ": the actual reward attributes this boss's final words")
		await _capture_phase("reward_" + id, "reward")
		world.reward_selection_ui.close_selection()
		world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.BOSS, false)
		world._enter_rest_site()
		check(not world.hud.boss_intro_visible and not world.hud.room_banner_subtitle_label.text.contains(BOSSES.get_greeting(id)), id + ": the next room cannot retain the defeated boss's greeting")
	else:
		check(world.victory_screen.is_open() and world.victory_screen._results_screen._subtitle_label.text == caption, id + ": native final victory uses authoritative defeated identity")
		await _capture_phase("victory_" + id, "victory")
	await _dispose_world()

func _dispose_world() -> void:
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()

func _test_summary_attribution() -> void:
	for final_id: String in ["lacuna", "null_archivist"]:
		var summary := {"defeated_boss_ids": ["warden", final_id, final_id, "unknown"], "max_depth": 22}
		var before := summary.duplicate(true)
		var caption := VICTORY.get_victory_subtitle(summary)
		check(caption.contains(String(BOSSES.NAMES[final_id])) and caption.contains(BOSSES.get_defeat_line(final_id)), "Final attribution accepts duplicate records of the same known final boss")
		check(summary == before, "Reading victory dialogue never mutates the authoritative run summary")
	for summary: Dictionary in [{}, {"stats": {"bosses_defeated": 3}}, {"defeated_boss_ids": ["warden", "sovereign"]}, {"defeated_boss_ids": ["lacuna", "null_archivist"]}, {"defeated_boss_ids": "lacuna"}, {"defeated_boss_ids": [false, 3, "unknown"]}]:
		check(VICTORY.get_victory_subtitle(summary) == "The descent is complete.", "Legacy, malformed, absent and ambiguous final identities retain the neutral result subtitle")
	check(BOSSES.get_greeting("unknown").is_empty() and BOSSES.get_defeat_line("unknown").is_empty(), "Unknown identity never borrows another boss's voice")

func _capture_phase(_name: String, phase: String) -> void:
	await process_frame
	world.hud.refresh(world._get_hud_state(), world.player)
	var bounds := root.get_visible_rect()
	if phase == "greeting":
		for width in [1280, 960]:
			root.size = Vector2i(width, 720)
			root.content_scale_size = root.size
			await process_frame
			world.hud.refresh(world._get_hud_state(), world.player)
			await process_frame
			for label: Label in [world.hud.room_banner_title_label, world.hud.room_banner_subtitle_label]:
				check(not label.get_global_rect().intersects(world.hud.status_panel.get_global_rect()), "Live boss greeting resize clears the actual status panel at%d" % width)
		bounds = root.get_visible_rect()
		for label: Label in [world.hud.room_banner_title_label, world.hud.room_banner_subtitle_label, world.hud._status_hint_label]:
			check(bounds.encloses(label.get_global_rect()) and label.get_minimum_size().x <= label.size.x + 1.0 and label.get_minimum_size().y <= label.size.y + 1.0, "Entire boss greeting/readiness label fits at960: " + label.text)
	elif phase == "reward":
		var label: RichTextLabel = world.reward_selection_ui.epitaph_label
		check(label.visible and bounds.encloses(label.get_global_rect()) and label.get_content_height() <= label.size.y + 1.0, "Attributed reward epitaph fits its native960 surface")
	elif phase == "victory":
		var screen: Node = world.victory_screen._results_screen
		screen._appearance_tween.custom_step(1.0)
		await process_frame
		check(bounds.encloses(screen._card.get_global_rect()) and screen._subtitle_label.get_minimum_size().y <= screen._subtitle_label.size.y + 1.0, "Attributed victory subtitle and result card fit960")

func _finish_capture() -> void:
	pass
