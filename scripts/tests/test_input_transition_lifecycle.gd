extends "res://scripts/tests/test_run_scene_ownership.gd"
## Real door, nested overlays, focus notification, death and retry input boundaries.

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	ProjectSettings.set_setting("application/config/version", "dev-input-boundary-audit")
	ProjectSettings.set_setting("application/config/update_feed_url", "")
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
	node_added.connect(_disable_debug_before_ready)
	node_added.connect(audio_retirement.observe_node)
	active_world = MAIN.instantiate() as WORLD
	active_world.get_node("DebugSettings").enabled = false
	root.add_child(active_world)
	current_scene = active_world
	_pick_reward({"rewards": []})
	await _clear_first_room_to_checkpoint()
	check(active_world.choosing_next_room and not active_world.door_options.is_empty(), "Real first-room clear offers generated doors")
	active_world.player.set_physics_process(false)
	var actor: Node = active_world.player
	actor.apply_trial_power("blast_drive")
	actor.apply_trial_power("razor_orbit")
	Input.action_release("attack")
	Input.action_release("dash")
	await physics_frame
	await process_frame
	actor._refresh_combat_input_release()
	actor.attack_cooldown_left = 0.0
	actor.attack_lock_time_left = 0.0
	actor.dash_cooldown_left = 0.0
	Input.action_press("dash")
	actor._try_start_dash(Vector2.RIGHT)
	check(actor._is_dash_active(), "Real accepted dash begins before door entry")
	var normal_dash_left: float = actor.dash_remaining_distance
	actor._physics_process(1.0/60.0)
	check(actor.dash_remaining_distance > 0.0 and actor.dash_remaining_distance < normal_dash_left and actor._dash_damage_immune_left > 0.0, "Ordinary dash still advances with its existing immunity before a room reset")
	await physics_frame
	await process_frame
	Input.action_press("attack")
	actor._try_attack_input()
	check(actor.queued_attack_after_dash, "Real Attack edge during dash creates accepted queued request")
	Input.action_release("attack")
	Input.action_release("dash")
	await physics_frame
	await process_frame
	var old_attacks: int = actor.attack_combo_counter
	var door: Dictionary = active_world.door_options[0]
	for offered: Dictionary in active_world.door_options:
		if not CONTRACTS.door_choice_profile(offered).is_empty():
			door = offered
			break
	actor.global_position = CONTRACTS.door_option_get_position(door)
	Input.action_press("interact")
	active_world._try_use_door()
	Input.action_release("interact")
	check(active_world.encounter_intro_grace_active, "Actual generated door enters next arena survey")
	check(not actor.queued_attack_after_dash, "Room entry clears an old queued Attack")
	var survey_start: Vector2 = actor.global_position
	for frame in range(20):
		actor._physics_process(1.0/60.0)
	check(actor.global_position.distance_to(survey_start) < 0.1, "Arena survey cannot replay the previous room's dash")
	# Readiness is a new movement gesture, not a fresh Attack.
	Input.action_press("move_right")
	active_world._update_encounter_intro_grace()
	Input.action_release("move_right")
	check(not active_world.encounter_intro_grace_active, "A deliberate movement gesture readies the new arena")
	for frame in range(45):
		actor._physics_process(1.0/60.0)
	check(actor.attack_combo_counter == old_attacks, "No fresh Attack means no old buffered strike after new-room readiness")
	await _check_actual_modal_handoffs()
	await _check_actual_death_retry()
	current_scene = null
	active_world.queue_free()
	active_world = null
	await process_frame
	await process_frame
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Deleted scene audio releases its native playback before fixture shutdown")
	print("[InputBoundary] ",checks," checks, ",failures.size()," failures")
	call_deferred("quit", 0 if failures.is_empty() else 1)

func _arm_combo() -> void:
	var actor: Node = active_world.player
	Input.action_release("attack")
	Input.action_release("dash")
	await physics_frame
	await process_frame
	actor._refresh_combat_input_release()
	actor.attack_cooldown_left = 0.0
	actor.attack_lock_time_left = 0.0
	actor.apply_trial_power("blast_drive")
	actor.apply_trial_power("razor_orbit")
	Input.action_press("dash")
	var anchor := Node2D.new()
	active_world.add_child(anchor)
	anchor.add_to_group("arena_columns")
	anchor.position = actor.position + Vector2(0,100)
	actor.arcana_motion.start_orbit(anchor)
	Input.action_press("attack")
	actor._try_attack_input()
	actor.arcana_motion.tick(0.65)
	check(actor.arcana_motion.owns_movement() and actor.arcana_motion.charge_hold >= 0.65, "Real deliberate attack is fully charged while Orbit owns movement")

func _check_actual_modal_handoffs() -> void:
	active_world.set_process(false)
	for reason in ["pause_build", "build_pause", "focus"]:
		await _arm_combo()
		var actor: Node = active_world.player
		var attacks: int = actor.attack_combo_counter
		var charges: int = actor.arcana_motion.blast_charges
		if reason == "pause_build":
			active_world.pause_menu_controller.open()
			active_world.build_detail_panel.open()
			active_world.pause_menu_controller.close()
			check(active_world._modal_requires_combat_pause(), "Closing Pause preserves actual open Build Details pause")
			active_world.build_detail_panel.close()
		elif reason == "build_pause":
			active_world.build_detail_panel.open()
			active_world.pause_menu_controller.open()
			active_world.build_detail_panel.close()
			check(active_world._modal_requires_combat_pause(), "Closing Build Details preserves actual open Pause")
			active_world.pause_menu_controller.close()
		else:
			root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
		check(not actor.arcana_motion.owns_movement() and actor.arcana_motion.charge_hold < 0.0 and actor.arcana_motion.dash_hold < 0.0, reason + " clears both held powers through actual callbacks")
		for frame in 45:
			actor._physics_process(1.0/60.0)
		check(actor.attack_combo_counter == attacks and actor.arcana_motion.blast_charges == charges, reason + " cannot rearm from still-held buttons")
		Input.action_release("attack")
		Input.action_release("dash")
		actor.arcana_motion.tick(0.01)
		check(actor.attack_combo_counter == attacks and actor.arcana_motion.blast_charges == charges, reason + " eventual release cannot launch")

func _check_actual_death_retry() -> void:
	await _arm_combo()
	var old_actor: Node = active_world.player
	old_actor.take_damage(1000000, {"source": "fixture_death"})
	check(active_world.defeat_screen.is_open() and not old_actor.arcana_motion.owns_movement() and old_actor.arcana_motion.charge_hold < 0.0, "Actual lethal health callback clears armed powers before defeat UI")
	var old_world_id := active_world.get_instance_id()
	active_world.defeat_screen.retry_run_requested.emit()
	check(await _wait(func(): return current_scene is WORLD and current_scene.get_instance_id() != old_world_id), "Actual defeat retry replaces Main while actions remain held")
	active_world = current_scene as WORLD
	active_world.set_process(false)
	active_world.player.set_physics_process(false)
	_pick_reward({"rewards": []})
	var actor: Node = active_world.player
	actor.apply_trial_power("blast_drive")
	actor.apply_trial_power("razor_orbit")
	Input.action_press("move_right")
	active_world._update_encounter_intro_grace()
	Input.action_release("move_right")
	for frame in 45:
		actor._physics_process(1.0/60.0)
	check(actor.attack_combo_counter == 0 and actor.arcana_motion.charge_hold < 0.0 and not actor.arcana_motion.owns_movement(), "Retry and actual initial-reward handoff require release before any new attack or hook")
	Input.action_release("attack")
	Input.action_release("dash")
	await physics_frame
	await process_frame
	actor._refresh_combat_input_release()
	actor.attack_cooldown_left = 0.0
	actor.attack_lock_time_left = 0.0
	Input.action_press("attack")
	actor._try_attack_input()
	check(actor.attack_combo_counter == 1 and actor.arcana_motion.charge_hold >= 0.0, "A fresh deliberate post-retry Attack rearms normally")
	Input.action_release("attack")
