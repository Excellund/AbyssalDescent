extends "res://scripts/tests/test_reward_build_inspection.gd"
## Actual reward controls with a Rest offer: optional Catalysts, inspection,
## deliberate confirmation, native canvas coordinates and return to rewards.
var rest_modes: Array[int] = []

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	var retirement := AUDIO_RETIREMENT.new()
	node_added.connect(retirement.observe_node)
	_setup_ui()
	ui.reward_selected.connect(func(_choice: Dictionary, mode: int, initial: bool):
		rest_modes.append(mode)
		_check(not initial, "Rest never uses the initial Arcana path"))
	var choices := _rest_offer()
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720)]:
		viewport.size = window_size
		viewport.size_2d_override = Vector2i(2560, 1440)
		viewport.size_2d_override_stretch = true
		await process_frame
		ui.open_rest_selection(choices, player, "bastion")
		await process_frame
		_check(ui.is_active() and ui.reward_selection_mode == ENUMS.RewardMode.REST and ui.boon_choices.size() == 3, "Rest shows Recover and two supplied owned upgrades")
		_check(ui.get_choice_count() == 4 and ui.boon_card_panels.size() == 4 and not ui.boon_card_panels[3].visible, "Rest retains the normal four-choice setup while showing three Rest cards")
		_check(not ui._can_reroll_current_offer() and ui._reward_rerolls_remaining == 0, "Rest cannot spend or gain Catalyst rerolls")
		ui._confirm_choice(1)
		_check(ui.is_active() and selected.is_empty(), "Rest retains the ordinary reveal confirmation guard")
		ui.process_input(1.0)
		ui.process_input(0.016)
		_check(not ui.skip_button.visible and not ui.reroll_button.visible and ui.build_button.visible, "Rest exposes build inspection and no skip/reroll action")
		ui._on_skip_button_pressed()
		_check(ui.is_active() and skipped == 0, "A stale Skip activation cannot bypass a Rest decision")
		_check(ui._layout_root.size.is_equal_approx(Vector2(window_size)), "Rest layout uses physical viewport size under production stretch")
		_check((ui._layout_root.scale * viewport.get_stretch_transform().get_scale()).is_equal_approx(Vector2.ONE), "Rest copy retains one display pixel per layout pixel")
		for i in choices.size():
			_check(Rect2(Vector2.ZERO, Vector2(window_size)).encloses(ui.boon_card_rects[i]), "Rest card stays within the displayed game area")
			_check(ui.boon_card_labels[i].get_content_height() <= ui.boon_card_labels[i].size.y, "Rest explanation fits its actual label")
		var motion := InputEventMouseMotion.new()
		motion.position = ui._layout_root.get_global_transform_with_canvas() * ui.boon_card_rects[1].get_center()
		viewport.push_input(motion, true)
		ui._update_boon_hover()
		_check(ui.boon_hovered_index == 1, "Ordinary pointer hit testing matches scaled Rest card geometry")
		ui.boon_card_panels[1].grab_focus()
		ui._request_build_inspection()
		_check(build.is_open() and ui.is_active(), "Your Build preserves the pending Rest offer")
		var before := ui.boon_choices.duplicate(true)
		build.close()
		await process_frame
		ui.process_input(0.016)
		_check(not ui._inspection_active and ui.boon_choices == before, "Closing build inspection restores the same Rest offer")
		ui.close_selection()
	# Deliberate keyboard confirmation emits exactly once, with the Rest mode.
	ui.open_rest_selection(choices, player, "bastion")
	ui.process_input(1.0)
	ui.process_input(0.016)
	ui.boon_card_panels[1].grab_focus()
	ui.handle_input(_action("ui_accept"))
	ui.handle_input(_action("ui_accept"))
	_check(selected.size() == 1 and selected[0].get("rest_action") == "upgrade" and rest_modes == [ENUMS.RewardMode.REST], "One keyboard decision emits one tagged Rest upgrade")
	ui.close_selection()
	_open(ENUMS.RewardMode.BOON)
	_check(ui.get_choice_count() == 4 and (ui._layout_root.scale * viewport.get_stretch_transform().get_scale()).is_equal_approx(Vector2.ONE) and ui._reward_rerolls_remaining == 1, "Subsequent ordinary rewards retain readable physical geometry, four choices and Catalyst rerolls")
	_check(ui.build_button.get_theme_font_size("font_size") == 18 and ui.skip_button.get_theme_font_size("font_size") == 22, "Leaving Rest preserves the separately authored normal action text sizes")
	ui.close_selection()
	viewport.free()
	registry.free()
	_free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Rest UI fixture releases its native audio")
	print("[OK] Rest Site UI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _rest_offer() -> Array[Dictionary]:
	var first := registry.get_upgrade_pool(player).slice(0, 2)
	for choice in first:
		if player.get_upgrade_stack_count(String(choice.id)) == 0:
			player.apply_upgrade(String(choice.id))
	var result: Array[Dictionary] = [{"id": "rest_recover", "name": "Recover", "desc": "Restore 42 health.\nHealth: 60 → 102 / 130", "rest_action": "recover", "stack_limit": 0}]
	for candidate in registry.get_upgrade_pool(player):
		if player.get_upgrade_stack_count(String(candidate.id)) > 0:
			var choice: Dictionary = candidate.duplicate(true)
			choice["rest_action"] = "upgrade"
			result.append(choice)
			if result.size() == 3:
				break
	return result
