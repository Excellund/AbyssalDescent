extends "res://scripts/tests/test_room_layout_entry.gd"
## Actual offered cards, World acceptance, exhausted pools and disk resume.
const CHARACTERS := preload("res://scripts/character_registry.gd")
const DAMAGE := preload("res://scripts/shared/damageable.gd")
var primary_attacks := 0

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-reward-availability")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	for character_id in CHARACTERS.get_launch_character_ids():
		for tier in range(4):
			await _check_build(character_id, tier)
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after actual Main teardown")
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[RewardAvailability] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _new_main() -> void:
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.player.primary_attack_fired.connect(func(): primary_attacks += 1)

func _free_main() -> void:
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame

func _check_build(character_id: String, tier: int) -> void:
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	RunContext.selected_character_id = character_id
	RunContext.current_difficulty_tier = tier
	RunContext.restore_active_catalysts(character_id, [])
	_new_main()
	var label := "%s Bearing%d: " % [character_id, tier]
	var ui: Node = world.reward_selection_ui
	ui.close_selection()
	for entry in world.power_registry_instance.get_trial_power_pool(world.player):
		if String(entry.id) == "returning_crescent":
			continue
		for _level in int(entry.stack_limit):
			world.player.apply_trial_power(String(entry.id))
	for level in range(1, 4):
		Input.action_release("attack")
		await process_frame
		await physics_frame
		await process_frame
		world._open_boon_selection("Arcana", level == 1, ENUMS.RewardMode.ARCANA, {}, "", character_id)
		check(ui.boon_choices.size() == 1 and String(ui.boon_choices[0].id) == "returning_crescent", label + "real available pool offers only the remaining Crescent level%d" % level)
		ui.process_input(ui.boon_confirm_lock_time + 0.01)
		ui.process_input(0.01)
		# Headless display has no movable mouse. Map only the offered card's hit rect
		# to its fixed pointer in the physical reward layout's coordinates;
		# production hover, input, signal and World apply stay real.
		var reward_pointer: Vector2 = ui._layout_root.get_global_transform_with_canvas().affine_inverse() * root.get_mouse_position()
		ui.boon_card_rects[0] = Rect2(reward_pointer - Vector2(10, 10), Vector2(20, 20))
		ui._update_boon_hover()
		check(ui.boon_hovered_index == 0, label + "offered card enters production hover selection")
		var attacks_before := primary_attacks
		Input.action_press("attack")
		ui.process_input(0.016)
		check(not ui.is_active() and world.player.get_trial_power_stack_count("returning_crescent") == level and world.player.returning_crescent_stacks == level, label + "actual attack confirmation applies Crescent level%d through World" % level)
		world.player._try_attack_input()
		check(primary_attacks == attacks_before, label + "accepted card cannot leak a primary attack")
		Input.action_release("attack")
		await process_frame
		await physics_frame
		world.player._refresh_combat_input_release()
	var timeline: Array = world.run_summary_recorder.run_summary_tracker.reward_timeline.duplicate(true)
	check(timeline.size() == 3, label + "all three accepted cards enter Oath/build accounting")
	_check_empty_offer(ENUMS.RewardMode.ARCANA, false, label)
	for entry in world.power_registry_instance.get_boss_reward_pool(world.player):
		for _level in int(entry.stack_limit):
			world.player.apply_upgrade(String(entry.id))
	world.boss_reward_pending = true
	_check_empty_offer(ENUMS.RewardMode.BOSS, false, label)
	check(not world.boss_reward_pending, label + "empty boss reward clears pending progression")
	check(world.run_summary_recorder.run_summary_tracker.reward_timeline == timeline, label + "empty continuations grant no picks or Oath items")
	world._save_active_run_checkpoint()
	var expected := world.player.build_run_snapshot()
	check(not RunContext.load_active_run().is_empty(), label + "accepted World build is written by actual checkpoint service")
	await _free_main()
	RunContext.request_resume_saved_run()
	_new_main()
	ui = world.reward_selection_ui
	check(world.current_character_id == character_id and world.current_difficulty_tier == tier, label + "fresh Main restores character and Bearing")
	check(world.player.build_run_snapshot() == expected, label + "fresh Main restores the complete accepted build and structural levels")
	check(world.run_summary_recorder.run_summary_tracker.reward_timeline == timeline, label + "fresh Main restores actual accepted card evidence")
	_check_empty_offer(ENUMS.RewardMode.ARCANA, false, label + "resumed ")
	# The existing initial-skip branch must also start its pending first encounter.
	world.pending_initial_room_profile = world.encounter_profile_builder.build_debug_encounter_profile("apex_breakwater", 8)
	_check_empty_offer(ENUMS.RewardMode.ARCANA, true, label)
	check(_only_breakwater_alive() and not world.choosing_next_room, label + "empty initial continuation starts the actual pending Breakwater once")
	if character_id == "veilstrider" and tier == 1:
		await _check_native_apex_reward()
	await _free_main()

func _check_empty_offer(mode: int, initial: bool, label: String) -> void:
	var ui: Node = world.reward_selection_ui
	world._open_boon_selection("Reward", initial, mode, {}, "", world.current_character_id)
	check(ui.boon_choices.is_empty() and ui.is_active() and not world.player.is_physics_processing(), label + "exhausted offer remains paused until deliberate continuation")
	check(not ui.skip_button.visible and not ui._can_skip_current_offer(), label + "empty offer retains original reveal/confirmation guard")
	ui.skip_button.pressed.emit()
	check(ui.is_active(), label + "early Continue cannot skip confirmation guard")
	ui.process_input(ui.boon_confirm_lock_time + 0.01)
	ui.process_input(0.01)
	check(ui.skip_button.visible and ui.skip_button.text.begins_with("Continue") and ui._can_skip_current_offer(), label + "empty offer reveals real Continue after guard")
	check(ui.boon_subtitle_label.text.contains("No rewards remain") and not ui.reroll_button.visible, label + "empty state explains availability and offers no invalid reroll")
	var attacks_before := primary_attacks
	Input.action_press("attack")
	Input.action_press("dash")
	ui.skip_button.pressed.emit()
	world.player._try_attack_input()
	world.player._try_start_dash(Vector2.RIGHT)
	check(not ui.is_active() and primary_attacks == attacks_before and world.player.dash_remaining_distance == 0.0, label + "actual Continue closes without leaking attack or dash")
	Input.action_release("attack")
	Input.action_release("dash")
	if not initial:
		check(world.choosing_next_room and not world.door_options.is_empty(), label + "actual continuation offers next rooms")

func _until(predicate: Callable, seconds: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func _check_native_apex_reward() -> void:
	var ui: Node = world.reward_selection_ui
	var apex := world.encounter_profile_builder.build_debug_encounter_profile("apex_breakwater", 8)
	world._choose_door(CONTRACTS.apex_trial_door_option(apex, "Apex Breakwater", Color.ORANGE))
	check(_only_breakwater_alive(), "Actual chosen Apex route spawns one Breakwater")
	Input.action_press("move_right")
	check(await _until(func(): return not world.encounter_intro_grace_active), "Actual movement leaves the Apex survey")
	Input.action_release("move_right")
	var enemy: Node
	for candidate in get_nodes_in_group("enemies"):
		if not candidate.is_queued_for_deletion() and candidate.get_script() == BREAKWATER:
			enemy = candidate
	check(await _until(func(): return not enemy.is_spawn_transporting()), "Actual Apex spawn transport completes")
	check(DAMAGE.apply_damage(enemy, 1000000, {"source":"fixture","attack_type":"ground"}), "Actual Apex death completes the room")
	check(await _until(func(): return ui.is_active()), "Native World room-clear reward opens")
	check(ui.reward_selection_mode == ENUMS.RewardMode.ARCANA and ui.boon_choices.is_empty(), "Native Apex reward resolves the genuinely exhausted Arcana pool")
	check(await _until(func(): return ui.skip_button.visible and ui._can_skip_current_offer()), "Natural World frame ticks unlock exhausted reward Continue")
	ui.skip_button.pressed.emit()
	check(not ui.is_active() and world.choosing_next_room and not world.door_options.is_empty(), "Actual exhausted Apex reward continues through its real route options")
