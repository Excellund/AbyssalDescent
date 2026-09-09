extends "res://scripts/tests/test_blast_feedback.gd"

const REWARD_UI := preload("res://scripts/reward_selection_ui.gd")
const BUILD_PANEL := preload("res://scripts/build_detail_panel.gd")
const REGISTRY := preload("res://scripts/power_registry.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")

var ui: REWARD_UI
var build: BUILD_PANEL
var viewport: SubViewport
var registry: REGISTRY
var rng := RandomNumberGenerator.new()
var selected: Array[Dictionary] = []
var skipped := 0
var offered := 0

func _run() -> void:
	var retirement := AUDIO_RETIREMENT.new()
	node_added.connect(retirement.observe_node)
	_setup_ui()
	await _check_inspection()
	await _check_owned_details()
	_check_property_wording()
	await _check_mission_bundle()
	await _check_expanded_scroll()
	await _check_responsive_actions()
	ui.close_selection()
	viewport.free()
	registry.free()
	_free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Native UI audio retires after owner teardown")
	print("[OK] Reward build inspection: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _setup_ui() -> void:
	_make_world(0)
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 720)
	root.add_child(viewport)
	ui = REWARD_UI.new()
	viewport.add_child(ui)
	ui.initialize(4, 0.0)
	ui.configure_catalyst_payload({"reward_rerolls_per_encounter_add": 1.0, "arcana_capacity_add": 1.0})
	build = BUILD_PANEL.new()
	viewport.add_child(build)
	build.setup()
	registry = REGISTRY.new()
	root.add_child(registry)
	rng.seed = 991
	ui.reward_selected.connect(func(choice: Dictionary, _mode: int, _initial: bool): selected.append(choice))
	ui.reward_skipped.connect(func(_mode: int, _initial: bool): skipped += 1)
	ui.reward_offers_presented.connect(func(_choices: Array[Dictionary], _mode: int, _initial: bool, _stage: int): offered += 1)
	ui.build_inspection_requested.connect(func(candidate: Dictionary):
		build.refresh_from_player(player, "bastion", [], candidate)
		build.open(true))
	build.build_detail_closed.connect(ui.resume_after_inspection)

func _open(mode: int = ENUMS.RewardMode.ARCANA, mutator: Dictionary = {}) -> void:
	ui.open_selection("Choose a reward", false, mode, registry, player, rng, mutator, "", "bastion")
	ui.boon_confirm_lock_time = 0.0
	ui.boon_reveal_time = 2.0
	ui.process_input(0.016)

func _action(name: String, pressed: bool = true) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	return event

func _check_inspection() -> void:
	_open()
	ui.boon_hovered_index = 2
	ui.boon_card_panels[2].grab_focus()
	var choices := ui.boon_choices.duplicate(true)
	var rng_before := rng.state
	var rerolls_before := ui._reward_rerolls_remaining
	_check(ui.handle_input(_action("reward_inspect")), "Mapped inspection action is handled")
	_check(build.is_open() and build._layer.layer == 140, "Build opens above the reward layer")
	_check(ui.is_active(), "Inspection retains the active paused offer")
	_check(ui.build_button.focus_mode == Control.FOCUS_NONE and ui.boon_card_panels[0].focus_mode == Control.FOCUS_NONE, "Underlying offer controls leave the modal focus cycle")
	_check(build._modal_backdrop.visible and build._modal_backdrop.mouse_filter == Control.MOUSE_FILTER_STOP, "Modal backdrop blocks pointer access to underlying cards")
	_check(build._candidate_details.text.contains(String(choices[2].name)), "Inspection compares the focused offer")
	ui._confirm_choice(2)
	ui._on_skip_button_pressed()
	ui._on_reroll_button_pressed()
	_check(selected.is_empty() and skipped == 0, "Inspection cannot choose or skip an offer")
	_check(ui.boon_choices == choices and rng.state == rng_before and ui._reward_rerolls_remaining == rerolls_before, "Inspection preserves offers, RNG and rerolls")
	Input.action_press("attack")
	_check(build.handle_input(_action("reward_back")), "Back closes the reward build view")
	ui.process_input(0.016)
	_check(not build.is_open() and ui.boon_hovered_index == 2, "Closing restores the selected offer")
	_check(ui.build_button.focus_mode == Control.FOCUS_ALL and ui.boon_card_panels[0].focus_mode == Control.FOCUS_ALL, "Closing restores reward focus navigation")
	_check(selected.is_empty(), "Closing with Attack held cannot select")
	ui._confirm_choice(2)
	_check(selected.is_empty(), "Direct button confirmation also respects release gate")
	Input.action_release("attack")
	await process_frame
	await process_frame
	ui.process_input(0.016)
	_check(not ui._confirm_release_required, "Released controls rearm confirmation")
	ui.handle_input(_action("ui_accept"))
	_check(selected.size() == 1 and not ui.is_active(), "Fresh keyboard confirmation selects the restored card")
	selected.clear()
	_open()
	var y_button := InputEventJoypadButton.new()
	y_button.button_index = JOY_BUTTON_Y
	y_button.pressed = true
	_check(ui.handle_input(y_button) and build.is_open(), "Controller Y opens Your Build")
	var b_button := InputEventJoypadButton.new()
	b_button.button_index = JOY_BUTTON_B
	b_button.pressed = true
	_check(build.handle_input(b_button) and not build.is_open(), "Controller B returns to the unchanged offer")
	await process_frame
	ui.process_input(0.016)
	ui.boon_card_panels[3].grab_focus()
	ui.handle_input(_action("ui_down"))
	_check(viewport.gui_get_focus_owner() == ui.build_button, "D-pad reaches Your Build after the final card")
	ui.handle_input(_action("ui_down"))
	_check(viewport.gui_get_focus_owner() == ui.reroll_button, "D-pad reaches reroll")
	ui.handle_input(_action("ui_down"))
	_check(viewport.gui_get_focus_owner() == ui.skip_button, "D-pad reaches Skip")
	ui.handle_input(_action("ui_down"))
	_check(viewport.gui_get_focus_owner() == ui.boon_card_panels[0], "D-pad wraps to cards without a focus trap")
	# Real viewport dispatch must intercept Tab before ordinary GUI focus travel.
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.keycode = KEY_TAB
	tab.pressed = true
	viewport.push_input(tab, true)
	_check(build.is_open(), "Native Tab dispatch opens inspection before focus navigation")
	tab.pressed = false
	viewport.push_input(tab, true)
	_check(build.is_open(), "Tab release does not close the reward inspection modal")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	viewport.push_input(escape, true)
	_check(not build.is_open() and ui.is_active(), "Native Escape closes only the build modal")
	ui.close_selection()

func _check_owned_details() -> void:
	for _level in range(3):
		player.apply_trial_power("returning_crescent")
	player.apply_trial_power("returning_crescent")
	player.apply_trial_power("razor_orbit")
	player.apply_upgrade("sovereigns_double")
	player.apply_upgrade("sovereigns_double")
	_open(ENUMS.RewardMode.BOSS)
	build.refresh_from_player(player, "bastion")
	_check(build._owned_levels.get("returning_crescent", 0) == 3, "Build reads the actual learned Arcana level")
	_check(build._owned_levels.get("sovereigns_double", 0) == 2, "Build reads actual boss stacks")
	var text := _all_text(build.panel)
	_check(text.contains("Level 3 · Prismatic"), "Owned Arcana explicitly shows one-time Prismatic")
	_check(text.contains("Sovereign's Double  · Level 2"), "Owned boss reward visibly shows Level 2")
	_check(text.contains("Razor Orbit  · Level 1"), "Owned first level is explicit")
	var owned_entry: VBoxContainer = build.arcana_list_container.get_child(build.arcana_list_container.get_child_count() - 1)
	var details: RichTextLabel = owned_entry.get_child(owned_entry.get_child_count() - 1)
	_check(not details.visible, "Keyword details start collapsed for owned powers")
	(owned_entry.get_child(0) as Button).pressed.emit()
	_check(details.visible and not details.text.is_empty(), "Owned power button exposes actionable keyword definitions")
	build.open(true)
	await process_frame
	await process_frame
	viewport.push_input(_action("ui_up"), true)
	await process_frame
	await process_frame
	var focused := viewport.gui_get_focus_owner()
	_check(focused is Button and focused != build._close_button, "Native D-pad reaches an owned power from the Return button")
	_check(build._scroll.scroll_vertical > 0 or focused.get_global_rect().intersects(build._scroll.get_global_rect()), "Controller inspection keeps its selected entry visible")
	build.close()
	ui.close_selection()

func _all_text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button or node is RichTextLabel:
		result = String(node.get("text"))
	for child in node.get_children():
		result += "\n" + _all_text(child)
	return result

func _check_property_wording() -> void:
	var saved_levels := build._owned_levels.duplicate(true)
	build._owned_levels = {"static_wake": 2, "phantom_step": 1, "aegis_field": 1, "hunters_snare": 2}
	var formatted := build._compatibility_text("storm_crown", 2)
	var plain := BUILD_PANEL.COMBAT_KEYWORDS.to_plain(formatted)
	_check(plain.contains("Static Wake deals damage."), "Damage-producing connections use a natural verb")
	_check(plain.contains("Aegis Pulse applies Slow."), "Status-producing connections use a natural verb")
	_check(plain.contains("Phantom Step deals damage and applies Slow."), "Mixed properties retain both highlighted actions in one grammatical line")
	_check(plain.contains("Hunter's Snare responds to damage."), "Receiver wording uses the damage noun without changing its conditions")
	_check(formatted.contains(BUILD_PANEL.COMBAT_KEYWORDS.keyword_bbcode("damage", "damage")) and formatted.contains(BUILD_PANEL.COMBAT_KEYWORDS.keyword_bbcode("slow")), "Natural verbs preserve explicit keyword color and bold spans")
	_check(not plain.contains("supplies dealing damage"), "Property wording contains no awkward supplied gerund")
	build._owned_levels = {"sigil_chain": 1, "razor_wind": 1, "reaper_step": 1}
	plain = BUILD_PANEL.COMBAT_KEYWORDS.to_plain(build._compatibility_text("lacuna_echo", 1))
	_check(plain.contains("Sigil Chain creates a Field."), "Persistent area connections identify a created Field")
	plain = BUILD_PANEL.COMBAT_KEYWORDS.to_plain(build._compatibility_text("wraithstep", 2))
	_check(plain.contains("Razor Wind lands attack hits."), "Direct-hit connections retain the distinct attack-hit keyword")
	_check(plain.contains("Reaper Step supports Dash."), "Dash refresh support never claims an automatic Dash occurs")
	build._owned_levels = saved_levels

func _check_mission_bundle() -> void:
	var mutator := {"name": "Combo Relay", "banner_suffix": "Kill chain: +5% damage and movement speed per kill, up to 4; resets after 2.8s.", "icon_shape_id": "combo_relay"}
	_open(ENUMS.RewardMode.MISSION, mutator)
	var offer_count := offered
	var boon: Dictionary = ui.boon_choices[0].duplicate(true)
	_check(ui.mission_bonus_label.visible and ui.mission_bonus_label.text.contains("next 3 encounters"), "Mission shows its fixed bonus duration on the Boon screen")
	_check(not ui.boon_title_label.text.contains("1/2"), "Mission has no second-screen progress promise")
	ui._confirm_choice(0)
	_check(selected.size() == 1 and selected[0].get("mission_upgrade", {}) == boon, "First selection includes the selected Boon")
	_check(selected[0].get("mission_mutator", {}).get("full_data", {}) == mutator, "Same selection atomically includes the fixed temporary bonus")
	_check(not ui.is_active() and ui.mission_reward_stage == 0 and offered == offer_count, "Mission completes without a second offer or intermediate claim")
	selected.clear()
	_open(ENUMS.RewardMode.MISSION, mutator)
	ui._on_reroll_button_pressed()
	_check(ui.current_player_mutator == mutator, "Reroll changes only Boon choices, retaining the fixed Mission bonus")
	ui.boon_confirm_lock_time = 0.0
	ui._on_skip_button_pressed()
	_check(skipped == 1 and selected.is_empty(), "Skipping declines both parts of the Mission bundle")

func _check_responsive_actions() -> void:
	for count in [2, 3, 4]:
		ui.initialize(count, 0.0)
		for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			viewport.size = size
			_open(ENUMS.RewardMode.MISSION, {"name": "Combo Relay", "icon_shape_id": "combo_relay"})
			ui._on_viewport_size_changed()
			await process_frame
			await process_frame
			var bounds := Rect2(Vector2.ZERO, Vector2(size))
			var actions: Array[Button] = [ui.build_button, ui.reroll_button, ui.skip_button]
			for action in actions:
				_check(bounds.encloses(action.get_global_rect()), "Reward action fits %s, %d choices" % [size, count])
				for card: Rect2 in ui.boon_card_rects:
					_check(not card.intersects(action.get_global_rect()), "Action does not cover a selectable card")
			_check(not actions[0].get_global_rect().intersects(actions[1].get_global_rect()) and not actions[1].get_global_rect().intersects(actions[2].get_global_rect()), "Three reward actions remain separate")
			_check(ui.mission_bonus_label.get_content_height() <= ui.mission_bonus_label.size.y, "Full fixed Mission bonus fits its readable header")
			ui._request_build_inspection()
			await process_frame
			await process_frame
			_check(bounds.encloses(build.panel.get_global_rect()), "Build modal fits viewport")
			_check(build.panel.get_global_rect().encloses(build._close_button.get_global_rect()), "Build close button remains visible")
			_check(build._candidate_details.get_content_width() <= build._candidate_details.size.x + 1.0, "Candidate comparison wraps inside the build panel")
			_check(not build._candidate_more.visible, "Offer definitions start collapsed so the owned build remains in view")
			if build._candidate_toggle.visible:
				build._candidate_toggle.pressed.emit()
				_check(build._candidate_more.visible, "Offer conditions and keyword meanings are inspectable")
			build.close()
			ui.close_selection()

func _press_pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	viewport.push_input(event, true)
	event.pressed = false
	viewport.push_input(event, true)
	await process_frame
	await process_frame

func _check_expanded_scroll() -> void:
	var accept_events := InputMap.action_get_events("ui_accept")
	_check(accept_events.filter(func(event: InputEvent): return event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A).size() == 1, "Repeated UI initialization installs only one default controller accept binding")
	_check(accept_events.any(func(event: InputEvent): return event is InputEventKey and event.keycode == KEY_ENTER), "Controller accept preserves the existing keyboard binding")
	for id in ["blast_drive", "static_wake", "sigil_chain", "hunters_snare", "dread_resonance"]:
		player.apply_trial_power(id)
		player.apply_trial_power(id)
	player.apply_trial_power("storm_crown")
	for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		_open()
		ui.boon_choices[0] = {"id": "storm_crown", "name": "Storm Crown", "desc": player.get_trial_power_card_desc("storm_crown"), "stack_limit": 3}
		ui.boon_hovered_index = 0
		var choices := ui.boon_choices.duplicate(true)
		var rng_before := rng.state
		ui._request_build_inspection()
		await process_frame
		await process_frame
		build._candidate_toggle.grab_focus()
		await _press_pad(JOY_BUTTON_A)
		_check(build._candidate_more.visible, "Native controller accept expands selected keyword details at %s" % size)
		if not build._candidate_more.visible:
			build.close()
			ui.close_selection()
			continue
		_check(build._candidate_more.size.y > build._scroll.size.y, "Regression uses keyword content taller than the viewport")
		_check(build._candidate_details.get_parsed_text().contains("Current — Level 1:") and build._candidate_details.get_parsed_text().contains("Offered — Level 2:"), "Inspection compares actual current and offered levels")
		var candidate_condition := String(REGISTRY.get_power_keyword_metadata("storm_crown", 2).condition_text)
		var receiver_condition := String(REGISTRY.get_power_keyword_metadata("hunters_snare", 2).condition_text)
		_check(build._candidate_more.text.count(candidate_condition) == 1, "Candidate restrictions appear once rather than repeating for every matching source")
		_check(build._candidate_more.text.contains(receiver_condition), "A distinct owned receiver retains its qualifying conditions")
		var steps := 0
		while build._candidate_more.get_global_rect().end.y > build._scroll.get_global_rect().end.y + 1.0 and steps < 40:
			var before := build._scroll.scroll_vertical
			await _press_pad(JOY_BUTTON_DPAD_DOWN)
			_check(viewport.gui_get_focus_owner() == build._candidate_toggle, "D-pad reads the expanded section before leaving its toggle")
			_check(build._scroll.scroll_vertical > before and build._scroll.scroll_vertical - before < build._scroll.size.y, "Successive controller viewports overlap so no keyword lines are skipped")
			steps += 1
		_check(steps > 0 and steps < 40, "The final keyword line is reachable without a controller focus trap")
		steps = 0
		while build._candidate_toggle.get_global_rect().position.y < build._scroll.get_global_rect().position.y - 1.0 and steps < 40:
			var before := build._scroll.scroll_vertical
			await _press_pad(JOY_BUTTON_DPAD_UP)
			_check(build._scroll.scroll_vertical < before and before - build._scroll.scroll_vertical < build._scroll.size.y, "D-pad can read backward without skipping content")
			steps += 1
		_check(steps > 0 and steps < 40, "Controller can return to the expanded section header")
		await _press_pad(JOY_BUTTON_A)
		_check(not build._candidate_more.visible and build.is_open(), "Controller collapses only the keyword section")
		await _press_pad(JOY_BUTTON_DPAD_DOWN)
		_check(viewport.gui_get_focus_owner() != build._candidate_toggle, "Collapsed section resumes ordinary focus navigation")
		# Owned detail toggles use the same navigation, including while scrolled.
		var owned_toggle := viewport.gui_get_focus_owner() as Button
		_check(owned_toggle != null and owned_toggle.has_meta("build_details"), "D-pad reaches an inspectable owned power")
		if owned_toggle != null and owned_toggle.has_meta("build_details"):
			var reference: WeakRef = owned_toggle.get_meta("build_details")
			var details := reference.get_ref() as RichTextLabel
			await _press_pad(JOY_BUTTON_A)
			_check(details.visible, "Controller expands an owned power's conditions")
			steps = 0
			while details.get_global_rect().end.y > build._scroll.get_global_rect().end.y + 1.0 and steps < 40:
				var before := build._scroll.scroll_vertical
				await _press_pad(JOY_BUTTON_DPAD_DOWN)
				_check(build._scroll.scroll_vertical > before and viewport.gui_get_focus_owner() == owned_toggle, "Owned conditions remain readable before focus moves onward")
				steps += 1
			_check(steps < 40, "Owned conditions finish scrolling")
			await _press_pad(JOY_BUTTON_DPAD_DOWN)
			_check(viewport.gui_get_focus_owner() != owned_toggle, "Completed owned section yields focus normally")
		await _press_pad(JOY_BUTTON_B)
		_check(not build.is_open() and ui.is_active() and ui.boon_choices == choices and rng.state == rng_before, "Back from nested details preserves the exact reward offer and RNG")
		_check(selected.is_empty(), "Nested controller inspection never selects a reward")
		ui.close_selection()
	_open()
	ui.boon_card_panels[0].grab_focus()
	await _press_pad(JOY_BUTTON_A)
	_check(selected.size() == 1 and not ui.is_active(), "Native controller A confirms one deliberately selected reward")
	selected.clear()
