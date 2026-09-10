extends "res://scripts/tests/test_descent_presentation.gd"
## Actual objective/HUD flow, with replica presentation and legacy payloads.

const OBJECTIVE := preload("res://scripts/objective_manager.gd")
const FRAME := preload("res://scripts/core/objective_frame_coordinator.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Pulse HUD tests require disposable user data")
		quit(1)
		return
	_prepare_pulse_world()
	_test_host_presentation()
	_test_replica_presentation()
	await _test_hud_states()
	await _release_pulse_world()
	print("[OK] Pulse HUD: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _prepare_pulse_world() -> void:
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-pulse-hud")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "veilstrider"
	RunContext.current_difficulty_tier = 1
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	world._clear_all_enemies()
	world._set_progression_counters(5, 5, 0, 0)
	world._begin_room(world.encounter_profile_builder.build_objective_profile(5, "pulse_window"))
	world._exit_encounter_intro_grace()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.active_room_enemy_count = 100
	world.objective_manager.spawn_timer = 100.0
	world.objective_manager.kill_target = 999

func _test_host_presentation() -> void:
	var manager := world.objective_manager
	world.objective_runtime._fire_pulse()
	var chosen := manager.pulse_active_mutator.duplicate(true)
	var state := world._get_hud_state()
	check(not chosen.is_empty() and state.current_room_enemy_mutator == chosen, "Actual pulse reaches the intended World modifier display")
	check(state.objective_pulse_active and is_equal_approx(state.objective_pulse_active_timer, 6.0), "World forwards the existing six-second active duration")
	check(state.objective_pulse_rule_text == CONTRACTS.mutator_banner_suffix(chosen), "World forwards the actual selected modifier rule")
	var detached: Dictionary = manager.get_hud_state().pulse_active_mutator
	detached["name"] = "Changed copy"
	check(manager.pulse_active_mutator == chosen, "HUD consumers cannot mutate the authoritative modifier")
	manager.tick_pulse_presentation(2.0)
	check(is_equal_approx(manager.pulse_active_timer, 6.0), "Presentation tick leaves the host's gameplay timer alone")
	manager.pulse_next_timer = 8.0
	world.objective_runtime.update_pulse_window_objective_state(1.0)
	check(is_equal_approx(manager.pulse_active_timer, 5.0), "Existing authoritative runtime remains the only host countdown")
	world.objective_runtime.update_pulse_window_objective_state(5.0)
	state = world._get_hud_state()
	check(not state.objective_pulse_active and state.objective_pulse_rule_text.is_empty() and state.current_room_enemy_mutator.is_empty(), "Expired host pulse clears the HUD rule and modifier")
	check(manager.pulse_active_mutator == chosen, "Host retains the previous profile used by subsequent wave rosters")
	manager.reset()
	state = manager.get_hud_state()
	check(not state.pulse_active and state.pulse_active_mutator.is_empty() and state.pulse_rule_text.is_empty(), "Room reset removes all pulse presentation")

func _test_replica_presentation() -> void:
	var host := OBJECTIVE.new()
	var replica := OBJECTIVE.new()
	var frame := FRAME.new()
	var chosen: Dictionary = world.encounter_profile_builder.get_hard_enemy_mutator_pool()[0]
	host.active_objective_kind = "pulse_window"
	host.pulse_active = true
	host.pulse_active_timer = 5.5
	host.pulse_mode = CONTRACTS.mutator_name(chosen)
	host.pulse_active_mutator = chosen.duplicate(true)
	host.pulse_next_timer = 8.5
	var wire: Dictionary = bytes_to_var(var_to_bytes(host.serialize_sync_state()))
	replica.apply_sync_state(wire)
	check(replica.get_hud_state() == host.get_hud_state(), "A joining replica recovers the same active rule and remaining duration")
	(wire.pulse_active_mutator as Dictionary)["name"] = "Changed wire copy"
	check(replica.pulse_active_mutator == chosen, "Replica owns its copied modifier payload")
	wire = host.serialize_sync_state()
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = false
	world.objective_manager.apply_sync_state(wire)
	world.pause_menu_controller.open()
	world._process(1.0)
	check(is_equal_approx(world.objective_manager.pulse_active_timer, 5.5), "Actual Pause prevents World's replica presentation tick")
	world.build_detail_panel.open()
	world.pause_menu_controller.close()
	world._process(1.0)
	check(is_equal_approx(world.objective_manager.pulse_active_timer, 5.5), "Build Details above Pause retains the replica countdown")
	world.build_detail_panel.close()
	frame.tick(replica, null, 1.0, true)
	check(is_equal_approx(replica.pulse_active_timer, 5.5), "Survey grace freezes replica display time")
	frame.tick(replica, null, 1.0, false)
	check(is_equal_approx(replica.pulse_active_timer, 4.5) and is_equal_approx(replica.pulse_next_timer, 7.5), "Existing objective frame path counts down replica display between packets")
	replica.apply_sync_state(wire)
	check(is_equal_approx(replica.pulse_active_timer, 5.5), "Authoritative snapshot replaces rather than accumulates predicted time")
	replica.apply_sync_state(wire)
	check(replica.get_hud_state() == host.get_hud_state(), "Repeated snapshot is idempotent")
	frame.tick(replica, null, 6.0, false)
	check(not replica.get_hud_state().pulse_active and replica.pulse_active_mutator.is_empty(), "Lost expiry packet cannot leave the old active rule visible")
	frame.tick(replica, null, 5.0, false)
	check(not replica.pulse_active and replica.pulse_next_timer == 0.0, "Replica expiry never generates a new pulse or negative countdown")
	replica.apply_sync_state(wire)
	var legacy := wire.duplicate(true)
	legacy.erase("pulse_active_mutator")
	replica.apply_sync_state(legacy)
	check(replica.get_hud_state().pulse_active and replica.get_hud_state().pulse_mode == host.pulse_mode and replica.get_hud_state().pulse_rule_text.is_empty(), "Legacy state without a rule preserves its known mode without reusing old text")
	legacy.erase("pulse_active_timer")
	replica.apply_sync_state(legacy)
	check(not replica.get_hud_state().pulse_active and replica.pulse_active_timer == 0.0, "Legacy state without a duration cannot retain a stale active countdown")
	wire["pulse_active_mutator"] = "invalid"
	replica.apply_sync_state(wire)
	check(replica.pulse_active_mutator.is_empty(), "Malformed optional rule payload is ignored")
	wire = host.serialize_sync_state()
	wire["pulse_active"] = false
	replica.apply_sync_state(wire)
	check(replica.pulse_mode.is_empty() and replica.pulse_active_mutator.is_empty(), "Authoritative expiry clears replica metadata immediately")
	wire["pulse_active"] = true
	wire["active_objective_kind"] = "hold_the_line"
	replica.apply_sync_state(wire)
	check(not replica.get_hud_state().pulse_active, "Another objective cannot inherit an active Pulse Window card")
	MultiplayerSessionManager.session_connected = false
	MultiplayerSessionManager.is_host_peer = false
	host.free()
	replica.free()

func _show_pulse(mutator: Dictionary, remaining: float = 4.7) -> void:
	var manager := world.objective_manager
	manager.active_objective_kind = "pulse_window"
	manager.time_left = 32.0
	manager.kills = 12
	manager.kill_target = 38
	manager.pulse_active = true
	manager.pulse_active_timer = remaining
	manager.pulse_next_timer = remaining + 3.0
	manager.pulse_mode = CONTRACTS.mutator_name(mutator)
	manager.pulse_active_mutator = mutator.duplicate(true)
	world.hud.refresh(world._get_hud_state(), world.player)

func _test_hud_states() -> void:
	for mutator in world.encounter_profile_builder.get_hard_enemy_mutator_pool():
		_show_pulse(mutator)
		await process_frame
		var mode := CONTRACTS.mutator_name(mutator)
		check(world.hud._status_obj_line2.text.contains(mode) and world.hud._status_obj_line2.text.contains("4.7s"), "Persistent active mode and timer: " + mode)
		check(world.hud._status_obj_line3.text == CONTRACTS.mutator_banner_suffix(mutator) and world.hud._status_obj_line3.visible, "Persistent actual rule: " + mode)
		_check_pulse_layout(mode)
	world.objective_manager.pulse_active = false
	world.objective_manager.pulse_next_timer = 1.7
	var active_height: float = world.hud.status_panel.size.y
	world.hud.refresh(world._get_hud_state(), world.player)
	check(world.hud._status_obj_line2.text == "Next pulse in 1.7s" and not world.hud._status_obj_line3.visible, "Between pulses the countdown replaces the active rule")
	check(world.hud.status_panel.size.y < active_height, "Inactive pulse HUD gives back the explanation's vertical space")
	world.objective_manager.pulse_next_timer = 0.0
	world.hud.refresh(world._get_hud_state(), world.player)
	check(world.hud._status_obj_line2.text == "Next pulse soon", "Awaiting an authoritative pulse never displays negative time")
	world.objective_manager.reset()
	world.hud.refresh(world._get_hud_state(), world.player)
	check(not world.hud._status_obj_line2.visible and not world.hud._status_obj_line3.visible, "Next room cannot retain the pulse labels")

func _check_pulse_layout(label: String) -> void:
	var rule: Label = world.hud._status_obj_line3
	var bounds: Rect2 = world.hud.status_panel.get_global_rect()
	check(bounds.encloses(rule.get_global_rect()), "Complete pulse rule stays inside the HUD card: " + label)
	check(rule.size.y >= rule.get_minimum_size().y, "Wrapped pulse rule has its full required height: " + label)
	check(rule.global_position.y >= world.hud._status_obj_line2.get_global_rect().end.y, "Pulse explanation stays below its active timer: " + label)

func _release_pulse_world() -> void:
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
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after the fixture scene")
