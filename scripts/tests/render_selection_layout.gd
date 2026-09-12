extends SceneTree
const MENU := preload("res://scripts/menu_controller.gd")
const WORLD := preload("res://scripts/world_generator.gd")
const META := preload("res://scripts/meta_progress_store.gd")
const CHARACTER := preload("res://scripts/character_registry.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const REGISTRY := preload("res://scripts/power_registry.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")
var audio_retirement := AUDIO.new()
var frames: Array[Dictionary] = []
var observations: Array[Dictionary] = []
var failures: Array[String] = []
var menu: MENU
var world: WORLD
var output_directory: String
var width := 1280
func _initialize() -> void:
	call_deferred("_run")
func _observe(ok: bool, text: String, data: Dictionary = {}) -> void:
	observations.append({"width": width, "ok": ok, "label": text, "data": data})
	if not ok:
		_guard(false, text + ": " + JSON.stringify(data))
func _guard(ok: bool, text: String) -> void:
	if not ok:
		failures.append(text)
		push_error(text)
func _settle(seconds: float = 0.3) -> void:
	await create_timer(seconds).timeout
func _wait(predicate: Callable, limit: float = 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while Time.get_ticks_msec() < end:
		if predicate.call():
			return true
		await process_frame
	return false
func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame
func _tap(code: Key) -> void:
	await _key(code, true)
	await _key(code, false)
func _joy(code: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
func _mouse_position(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	await process_frame
func _click_point(point: Vector2) -> void:
	await _mouse_position(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
func _click(control: Control) -> void:
	await _click_point(control.get_global_rect().get_center())
func _click_reward(ui: Node) -> void:
	# Bespoke card hover reads the OS cursor; use the real GUI Skip button in
	# this offscreen layout audit. Confirmation is separately regression-tested.
	await _click(ui.skip_button)

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := output_directory.path_join(str(width) + "_" + name + ".png")
	_guard(picture.save_png(path) == OK, "Save frame " + name)
	frames.append({"name": name, "width": width, "path": path})
	print("[FRAME] " + path)
func _focus_in(panel: Control) -> bool:
	var owner := root.gui_get_focus_owner()
	return is_instance_valid(owner) and (panel == owner or panel.is_ancestor_of(owner)) and owner.is_visible_in_tree()
func _focus_data() -> Dictionary:
	var owner := root.gui_get_focus_owner()
	return {"owner": str(owner.get_path()) if is_instance_valid(owner) else "none", "visible": owner.is_visible_in_tree() if is_instance_valid(owner) else false}
func _bound(control: Control, label: String) -> void:
	var rect := control.get_global_rect()
	_observe(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(rect), label, {"rect": str(rect)})
func _node_added(node: Node) -> void:
	audio_retirement.observe_node(node)
	if node is WORLD:
		var debug := node.get_node_or_null("DebugSettings")
		if debug != null:
			debug.enabled = false
func _seed_profile() -> void:
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
	RunContext.meta_progress_profile = META._get_default_profile()
	for character in CHARACTER.get_launch_characters():
		META.unlock_character(RunContext.meta_progress_profile, character.id)
		META.unlock_character_tier(RunContext.meta_progress_profile, character.id, 3)
		META.record_forsworn_clear(RunContext.meta_progress_profile, character.id)
	META.set_ascension_loadout(RunContext.meta_progress_profile, "bastion", ["hardened_foes", "thinned_choices"])
	RunContext.save_meta_progress()
	var profiles := PROFILE.new()
	var profile := profiles.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	profiles.save_profile(profile)
func _menu_path() -> void:
	_seed_profile()
	menu = MENU.new()
	root.add_child(menu)
	current_scene = menu
	_guard(await _wait(func(): return menu.root_panel.modulate.a >= 0.99 and menu.primary_run_button.is_visible_in_tree() and not menu._is_profile_prompt_blocked()), "Menu becomes interactive")
	await _settle()
	_bound(menu.root_panel, "Normal menu fits viewport")
	await _capture("menu")
	await _tap(KEY_ENTER)
	_guard(await _wait(func(): return menu.character_selector_panel.visible), "Native Enter opens character selection")
	await _settle()
	await _joy(JOY_BUTTON_DPAD_DOWN)
	_observe(_focus_in(menu.character_selector_panel), "D-pad can navigate character selection without a mouse", _focus_data())
	_bound(menu.character_selector_panel, "Character selection fits viewport")
	await _capture("characters")
	await _click(menu.character_buttons[0])
	_guard(await _wait(func(): return menu.difficulty_selector_panel.visible), "Actual character button opens Bearing")
	await _settle()
	await _tap(KEY_DOWN)
	_observe(_focus_in(menu.difficulty_selector_panel), "Arrow key navigates Bearing without a mouse", _focus_data())
	_bound(menu.difficulty_selector_panel, "Bearing selection fits viewport")
	await _capture("bearings")
	await _click(menu.difficulty_tier_buttons[3])
	_guard(await _wait(func(): return menu.ascension_panel.visible), "Actual Forsworn selection opens Ascension")
	await _settle()
	_observe(RunContext.active_ascension_loadout.is_empty(), "Opening Ascension does not activate saved modifiers", {"active": RunContext.active_ascension_loadout, "rank_label": menu.ascension_panel._rank_label.text})
	_bound(menu.ascension_panel, "Ascension panel fits viewport")
	await _capture("ascension")
	var toggles: Array[Node] = menu.ascension_panel._modifier_list.find_children("*", "CheckButton", true, false)
	if toggles.is_empty():
		toggles = menu.ascension_panel._modifier_list.find_children("*", "Button", true, false)
	if not toggles.is_empty():
		var toggle := toggles.front() as Button
		toggle.grab_focus()
		await _tap(KEY_SPACE)
		await _settle()
		_observe(_focus_in(menu.ascension_panel), "Modifier toggle retains keyboard focus after rebuilding cards", _focus_data())
	await _tap(KEY_ESCAPE)
	await _settle()
	_guard(menu.root_panel.visible, "Escape returns from Ascension")
	await _tap(KEY_ENTER)
	await _settle()
	await _click(menu.character_buttons[0])
	await _settle()
	await _click(menu.difficulty_tier_buttons[0])
	_guard(await _wait(func(): return current_scene is WORLD), "Actual Pilgrim selection launches normal Main")
	world = current_scene as WORLD
	menu = null
	_guard(await _wait(func(): return world.reward_selection_ui.is_active()), "Normal initial reward opens")
	await _settle(1.5)
	_observe(RunContext.active_ascension_loadout.is_empty() and RunContext.get_current_difficulty_tier() == 0, "Pilgrim run has no effective Ascension", {"saved": META.get_ascension_loadout(RunContext.meta_progress_profile, "bastion")})
	await _click_reward(world.reward_selection_ui)
	_guard(await _wait(func(): return not world.reward_selection_ui.is_active()), "Actual Skip button exits initial reward")
func _offers(ids: Array, mode: int, name: String) -> void:
	var ui = world.reward_selection_ui
	world._open_boon_selection("Arcana" if mode == ENUMS.RewardMode.ARCANA else "Boss Reward", false, mode, {}, world.power_registry_instance.get_boss_epitaph("warden", "riftlancer") if mode == ENUMS.RewardMode.BOSS else "", "bastion")
	ui.boon_choices.clear()
	for id in ids:
		var trial: bool = REGISTRY.TRIAL_POWER_POOL_IDS.has(id)
		ui.boon_choices.append({"id": id, "name": world.power_registry_instance.get_power_display_name(id), "desc": world.player.get_trial_power_card_desc(id) if trial else world.player.get_upgrade_card_desc(id), "stack_limit": world.power_registry_instance.get_power_stack_limit(id), "type": REGISTRY.POWER_TYPE_TRIAL if trial else REGISTRY.POWER_TYPE_UPGRADE})
	ui._refresh_boon_ui(world.player)
	await _settle(1.4)
	for i in range(ui.boon_choices.size()):
		_observe(not ui.skip_button.get_global_rect().intersects(ui.boon_card_panels[i].get_global_rect()), "Reward action does not overlap choice " + str(i))
	_bound(ui.skip_button, "Reward action fits viewport")
	await _capture(name)
	for label in ui.boon_card_labels:
		_observe(label.get_content_height() <= label.size.y + 1.0, "Complete reward description visible: " + label.get_parsed_text().get_slice("\n", 0))
	await _click_reward(ui)
	_guard(await _wait(func(): return not ui.is_active()), "Native Skip button closes " + name)
func _build_path() -> void:
	var actor = world.player
	for id in ["blast_drive", "razor_orbit", "returning_crescent"]:
		while actor.get_trial_power_stack_count(id) < 2:
			actor.apply_trial_power(id)
	await _offers(["blast_drive", "razor_orbit", "returning_crescent"], ENUMS.RewardMode.ARCANA, "level_three")
	for id in ["blast_drive", "razor_orbit", "returning_crescent"]:
		while actor.get_trial_power_stack_count(id) < 3:
			actor.apply_trial_power(id)
	world.reward_selection_ui.configure_catalyst_payload({"arcana_capacity_add": 1.0})
	await _offers(["blast_drive", "razor_orbit", "returning_crescent"], ENUMS.RewardMode.ARCANA, "prismatic")
	RunContext.restore_active_catalysts("bastion", ["reward_choice_bonus", "shop_reroll"])
	world._configure_reward_selection_loadout()
	_guard(world.reward_selection_ui.get_choice_count() == 4, "Actual Draft Compass configuration adds fourth choice")
	world.reward_selection_ui.configure_catalyst_payload({"arcana_capacity_add": 1.0, "reward_rerolls_per_encounter_add": 1.0})
	await _offers(["blast_drive", "razor_orbit", "returning_crescent", "razor_wind"], ENUMS.RewardMode.ARCANA, "draft_compass")
	world.current_difficulty_tier = 3
	RunContext.active_ascension_loadout = ["thinned_choices"]
	world._configure_reward_selection_loadout()
	_guard(world.reward_selection_ui.get_choice_count() == 3, "Actual Thinned Choices plus Draft Compass returns three choices")
	RunContext.restore_active_catalysts("bastion", [])
	world._configure_reward_selection_loadout()
	_guard(world.reward_selection_ui.get_choice_count() == 2, "Actual Thinned Choices offers two choices")
	world.reward_selection_ui.configure_catalyst_payload({"arcana_capacity_add": 1.0})
	await _offers(["blast_drive", "razor_orbit"], ENUMS.RewardMode.ARCANA, "thinned_choices")
	world.current_difficulty_tier = 0
	RunContext.active_ascension_loadout = []
	world._configure_reward_selection_loadout()
	for id in ["blast_drive", "razor_orbit", "returning_crescent"]:
		if not actor.has_trial_power_prismatic(id):
			actor.apply_trial_power(id)
	actor.apply_upgrade("sovereigns_double")
	actor.apply_upgrade("ruinous_impact")
	await _offers(["sovereigns_double", "ruinous_impact", "execution_edge"], ENUMS.RewardMode.BOSS, "boss_rewards")
	actor.apply_upgrade("sovereigns_double")
	actor.apply_upgrade("ruinous_impact")
	await _key(KEY_TAB, true)
	await _settle()
	_guard(world.build_detail_panel.is_open(), "Actual Tab press opens Build Details")
	_bound(world.build_detail_panel.panel, "Build Details fits viewport")
	await _capture("build_top")
	var scroll := world.build_detail_panel.panel.find_children("*", "ScrollContainer", true, false).front() as ScrollContainer
	await _mouse_position(scroll.get_global_rect().get_center())
	for _tick in 20:
		var wheel := InputEventMouseButton.new()
		wheel.position = scroll.get_global_rect().get_center()
		wheel.global_position = wheel.position
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		Input.parse_input_event(wheel)
		await process_frame
	await _settle()
	_observe(scroll.scroll_vertical > 0, "Mouse wheel reaches lower current Arcana descriptions", {"scroll": scroll.scroll_vertical})
	await _capture("build_bottom")
	await _key(KEY_TAB, false)
	_guard(world.build_detail_panel.is_open(), "Tab release keeps Build Details open")
	await _key(KEY_TAB, true)
	await _key(KEY_TAB, false)
	await _settle()
	_observe(not world.build_detail_panel.is_open(), "A second Tab press closes Build Details after scrolling")
	current_scene = null
	world.queue_free()
	world = null
	await _settle()
func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	node_added.connect(_node_added)
	ProjectSettings.set_setting("application/config/version", "dev-ui-layout-audit")
	ProjectSettings.set_setting("application/config/update_feed_url", "")
	output_directory = ProjectSettings.globalize_path("res://selection_layout_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	for test_width in [1280, 960, 1920]:
		width = test_width
		root.size = Vector2i(width, 1080 if width == 1920 else 720)
		root.content_scale_size = root.size
		root.canvas_transform = Transform2D.IDENTITY
		await _menu_path()
		await _build_path()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	_guard(await audio_retirement.wait_until_retired(self), "Native audio playback retires before fixture exit")
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "observations": observations, "failures": failures}, "\t"))
	print("[OK] UI visual audit: %d frames, %d causal observations, %d failures" % [frames.size(), observations.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)