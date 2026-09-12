extends "res://scripts/tests/test_menu_panel_fit.gd"
## Capture the real Oaths menu at production canvas scale. Run only through
## render_gameplay_fixture.ps1 -PreserveProductionCanvas in an isolated copy.
## Eighteen frames: ordinary browsing with every vessel/Bearing/catalyst
## unlocked, saved completion and unlock order, plus explicit setup eligibility.

const OATHS := preload("res://scripts/progression/oaths_registry.gd")
const OATH_PANEL := preload("res://scripts/ui/ascension/ascension_panel.gd")
const CHARACTERS := preload("res://scripts/character_registry.gd")
const CANVAS_SIZE := Vector2i(2560, 1440)
const CAPTURES := {
	0: ["forsworn_warden_no_hit", "unassisted_ascension"],
	1: ["forsworn_sovereign_no_hit"],
	3: ["unassisted_ascension", "vessel_roster", "clear_bastion_forsworn", "clear_threadbinder_forsworn"],
}

var frames: Array[Dictionary] = []

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	check(root.content_scale_size == CANVAS_SIZE, "Fixture starts with the production 2560x1440 canvas")
	check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "Fixture retains production canvas_items stretching")
	if not failures.is_empty():
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	RunContext.telemetry_upload_enabled = false
	RunContext.selected_character_id = "bastion"
	RunContext.meta_progress_profile = META._get_default_profile()
	for character_id: String in CHARACTERS.get_launch_character_ids():
		META.unlock_character(RunContext.meta_progress_profile, character_id)
		META.unlock_character_tier(RunContext.meta_progress_profile, character_id, 3)
		META.record_forsworn_clear(RunContext.meta_progress_profile, character_id)
	for catalyst_id: String in CATALYST.get_catalyst_ids():
		META.unlock_catalyst(RunContext.meta_progress_profile, catalyst_id)
	for legacy_id in ["warden_no_hit", "sovereign_no_hit", "singular_focus", "hundredfold", "pilgrims_road", "clear_bastion_pilgrim"]:
		META.mark_oath_completed(RunContext.meta_progress_profile, legacy_id)
	META.mark_oath_completed(RunContext.meta_progress_profile, "forsworn_grounded")
	META.mark_oath_completed(RunContext.meta_progress_profile, "forsworn_unassisted")
	RunContext.current_difficulty_tier = 0
	var menu := FixtureMenu.new()
	root.add_child(menu)
	menu._on_ascension_pressed()
	# Let the normal menu transition complete before measuring its final layout.
	for _frame in range(45):
		await process_frame
	var panel = menu.ascension_panel
	var scroll := panel._oath_list.get_parent().get_parent() as ScrollContainer
	check(panel._oaths_only_mode_enabled and panel.visible, "Native menu action opens Oaths-only mode")
	check(scroll != null, "Native Oaths list has its scrolling container")
	panel.set_setup_bearing(3)
	panel.set_run_setup_mode(true)
	_assert_oath_state(panel, "unassisted_ascension", false, true, "Forsworn · Bearing matches setup")
	panel.set_run_setup_mode(false)
	_assert_oath_state(panel, "unassisted_ascension", false, true, "Forsworn")
	check(panel._selected_oath_bearing() == -1, "Leaving setup clears presentation eligibility despite its cached Forsworn selection")
	var original_completed := META.get_completed_oath_ids(RunContext.meta_progress_profile).duplicate()
	var folder := project_path.path_join("oaths_feedback_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	for physical_size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = physical_size
		await _settle()
		menu._apply_menu_layout()
		await _settle()
		check(root.content_scale_size == CANVAS_SIZE, "Physical resizing retains production logical canvas: " + str(physical_size))
		check(menu.get_viewport_rect().size.is_equal_approx(Vector2(CANVAS_SIZE)), "Menu is laid out in the production canvas: " + str(physical_size))
		for tier: int in [0, 1, 3]:
			panel._collapsed_clear_groups.clear()
			RunContext.current_difficulty_tier = tier
			panel.populate()
			await _settle()
			_check_roster(panel, tier)
			_check_reclaimed_list_space(panel, scroll)
			panel._back_button.grab_focus()
			check(panel._back_button.has_focus(), "Back remains keyboard-accessible: " + str(physical_size))
			scroll.scroll_vertical = 0
			await _settle()
			for oath_id: String in CAPTURES[tier]:
				if oath_id == "vessel_roster":
					await _capture_vessel_roster(folder, physical_size, panel, scroll)
					continue
				if oath_id.begins_with("clear_"):
					var character_id := String((OATHS.get_definition(oath_id).get("params", {}) as Dictionary).get("character_id", ""))
					panel._collapsed_clear_groups.clear()
					panel.populate()
					await _settle()
					var vessel_button := _vessel_group(panel, character_id)
					check(vessel_button != null and not vessel_button.disabled, "Vessel progression remains browsable at every Bearing")
					if vessel_button == null:
						continue
					vessel_button.pressed.emit()
					await _settle()
					_check_vessel_progression(panel, tier, character_id)
				await _capture_id(folder, oath_id, physical_size, panel, scroll, "_" + OATHS._bearing_label(tier).to_lower())
		# The real setup still explains whether its selected run can earn a goal.
		# Its status must disappear again on returning to ordinary browsing.
		panel.set_oaths_only_mode(false)
		panel.set_run_setup_mode(true)
		for setup_tier: int in [1, 3]:
			panel.set_setup_bearing(setup_tier)
			panel.populate()
			await _settle()
			_assert_oath_state(panel, "unassisted_ascension", false, setup_tier == 3, "Forsworn · " + ("Bearing matches setup" if setup_tier == 3 else "Bearing differs from setup"))
			await _capture_id(folder, "unassisted_ascension", physical_size, panel, scroll, "_setup_" + OATHS._bearing_label(setup_tier).to_lower())
		panel.set_run_setup_mode(false)
		panel.set_oaths_only_mode(true)
		panel.populate()
		await _settle()
		_assert_oath_state(panel, "unassisted_ascension", false, true, "Forsworn")
	RunContext.current_difficulty_tier = 2
	panel.populate()
	_assert_oath_state(panel, "forsworn_sovereign_no_hit", false, true, "Delver+")
	_assert_oath_state(panel, "unassisted_ascension", false, true, "Forsworn")
	check(META.get_completed_oath_ids(RunContext.meta_progress_profile) == original_completed, "Browsing never seeds or migrates saved completions")
	menu.queue_free()
	await _settle()
	check(await retirement.wait_until_retired(self), "Native Oaths fixture audio retires")
	var file := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name(), "logical_canvas": [CANVAS_SIZE.x, CANVAS_SIZE.y]}, "\t"))
	file.close()
	print("[OK] Oaths feedback GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_reclaimed_list_space(panel: OATH_PANEL, scroll: ScrollContainer) -> void:
	var column := panel._oath_column_root as Control
	check(column.get_child_count() == 1 and column.get_child(0) == scroll, "The Oaths column contains only its scrolling list, with no top box")
	check(scroll.get_global_rect().is_equal_approx(column.get_global_rect()), "The scrolling list uses the entire reclaimed column")
	check(scroll.size.y >= 690.0, "Removing the box restores at least 690 logical pixels of scrolling space")
	for label: Label in panel.find_children("*", "Label", true, false):
		if label.is_queued_for_deletion():
			continue
		check(not label.text.contains("Selected Bearing") and not label.text.contains("Oaths for every stage of the descent"), "Removed overview and selected-Bearing text are absent")

func _check_roster(panel: OATH_PANEL, _tier: int) -> void:
	var character_ids := CHARACTERS.get_launch_character_ids()
	check(OATHS.get_oath_ids().size() == 17 + character_ids.size() * 4, "Board lists seventeen challenges and four Bearing goals for every playable vessel")
	check(character_ids.has("threadbinder"), "The playable roster includes Threadbinder")
	var group_titles: Array[String] = []
	var group_counts: Array[int] = []
	for child in panel._oath_list.get_children():
		if child is Label:
			group_titles.append(child.text)
			group_counts.append(0)
		if child is PanelContainer:
			group_counts[-1] += 1
	check(group_titles == ["Journey · Any Bearing", "Challenges · Delver+", "Prestige · Forsworn", "Vessel Progression"], "Progression stages explicitly show their Bearing requirements")
	check(group_counts == [4, 5, 8, 0], "Unassisted moves from Journey to Prestige without changing the total roster")
	_assert_oath_state(panel, "forsworn_warden_no_hit", true, true, "Any Bearing · Completed")
	_assert_oath_state(panel, "forsworn_singular_focus", true, true, "Any Bearing · Completed")
	_assert_oath_state(panel, "unassisted_ascension", false, true, "Forsworn")
	_assert_oath_state(panel, "forsworn_grounded", true, true, "Delver+ · Completed")
	_assert_oath_state(panel, "forsworn_sovereign_no_hit", false, true, "Delver+")
	_assert_oath_state(panel, "forsworn_glass_pilgrimage", false, true, "Forsworn")
	check(panel._selected_oath_bearing() == -1, "Ordinary browsing has no selected-run Bearing")
	var vessel_rows: Array[String] = []
	for child in panel._oath_list.get_children():
		if child is Button:
			vessel_rows.append(child.text)
	check(vessel_rows.size() == character_ids.size(), "Every playable vessel has one progression row")
	var previous_index := -1
	for character_id: String in META.CHARACTER_UNLOCK_CHAIN:
		var button := _vessel_group(panel, character_id)
		check(button != null and button.get_index() > previous_index, "Vessel rows follow actual unlock order: " + character_id)
		if button != null:
			previous_index = button.get_index()
	for character_id: String in character_ids:
		var vessel_button := _vessel_group(panel, character_id)
		var expected_progress := "(1 / 4)" if character_id == "bastion" else "(0 / 4)"
		check(vessel_button != null and vessel_button.text.ends_with(expected_progress), "Each vessel retains four Bearing goals and its saved progress: " + character_id)
	for bearing: String in ["pilgrim", "delver", "harbinger", "forsworn"]:
		var definition := OATHS.get_definition("clear_threadbinder_" + bearing)
		check(not definition.is_empty() and String((definition.get("params", {}) as Dictionary).get("character_id", "")) == "threadbinder", "Threadbinder has its own registered clear goal: " + bearing)

func _vessel_group(panel: OATH_PANEL, character_id: String) -> Button:
	var character_name := String(CHARACTERS.get_character(character_id).get("name", ""))
	for child in panel._oath_list.get_children():
		if child is Button and not child.is_queued_for_deletion() and child.text.contains("  " + character_name + "  ("):
			return child
	return null

func _check_vessel_progression(panel: OATH_PANEL, _selected_tier: int, character_id: String) -> void:
	for tier: int in range(4):
		var bearing := OATHS._bearing_label(tier)
		var completed := character_id == "bastion" and tier == 0
		var requirement := bearing + " Bearing" + (" · Completed" if completed else "")
		_assert_oath_state(panel, "clear_" + character_id + "_" + bearing.to_lower(), completed, true, requirement)

func _capture_vessel_roster(folder: String, physical_size: Vector2i, panel: OATH_PANEL, scroll: ScrollContainer) -> void:
	var character_ids := CHARACTERS.get_launch_character_ids()
	var last_button: Button
	for child in panel._oath_list.get_children():
		if child is Button and not child.is_queued_for_deletion():
			last_button = child
	check(last_button != null, "Vessel roster has a final visible row")
	if last_button == null:
		return
	scroll.ensure_control_visible(last_button)
	await _settle()
	for character_id: String in character_ids:
		var button := _vessel_group(panel, character_id)
		check(button != null, "Roster capture contains: " + character_id)
		if button == null:
			continue
		check(scroll.get_global_rect().grow(1.0).encloses(button.get_global_rect()), "All vessel rows fit together after scrolling: " + character_id)
		check(button.get_combined_minimum_size().x <= button.size.x + 1.0, "Vessel name and four-Bearing progress fit: " + character_id)
	await RenderingServer.frame_post_draw
	var filename := "vessel_roster_%d.png" % physical_size.x
	var picture := root.get_texture().get_image()
	check(picture.get_size() == physical_size, "Vessel roster capture uses physical output dimensions")
	check(not picture.is_empty() and picture.save_png(folder.path_join(filename)) == OK, "Captured " + filename)
	frames.append({"file": filename, "character_ids": character_ids, "physical_size": [physical_size.x, physical_size.y], "scroll_vertical": scroll.scroll_vertical, "selected_bearing": panel._selected_oath_bearing()})

func _assert_oath_state(panel: OATH_PANEL, oath_id: String, completed: bool, available: bool, requirement: String) -> void:
	var card := _find_oath_card(panel._oath_list, OATHS.get_definition(oath_id), completed)
	check(card != null, "Earned marker reflects actual saved progress: " + oath_id)
	if card == null:
		return
	check(card.get_meta(&"oath_bearing_eligible") == available, "Card checks eligibility only for an explicitly selected run: " + oath_id)
	check(card.get_meta(&"oath_setup_bearing") == panel._selected_oath_bearing(), "Card records whether it has a current setup: " + oath_id)
	var labels := card.find_children("*", "Label", true, false)
	check(labels.any(func(label: Label): return label.text == requirement), "Card visibly states its requirement and status: " + oath_id)
	var color := (card.get_theme_stylebox("panel") as StyleBoxFlat).border_color
	check(color.g > color.r if completed else (color.b > color.r if available else color.r > color.b), "Completed and ordinary cards keep their styles; only explicit setup can indicate ineligibility: " + oath_id)
	for label: Label in labels:
		check(not label.text.contains("Requires another Bearing"), "The misleading legacy warning is absent: " + oath_id)
	if not completed and panel._selected_oath_bearing() < 0:
		check(not requirement.contains(" · "), "Ordinary unearned goals state the requirement without a run status")
		for label: Label in labels:
			if label.text == requirement:
				var requirement_color := label.get_theme_color("font_color")
				check(requirement_color.b > requirement_color.r, "Ordinary requirement text uses neutral styling")

func _capture_id(folder: String, oath_id: String, physical_size: Vector2i, panel: OATH_PANEL, scroll: ScrollContainer, variant: String = "") -> void:
	var definition: Dictionary = OATHS.get_definition(oath_id)
	check(not definition.is_empty(), "Requested Oath is registered: " + oath_id)
	check(definition.has("minimum_bearing_tier") and definition.has("progression_stage"), "Rendered Oath declares its progression requirement: " + oath_id)
	var completed := OATHS.is_completed(oath_id, META.get_completed_oath_ids(RunContext.meta_progress_profile))
	var card := _find_oath_card(panel._oath_list, definition, completed)
	check(card != null, "Native Oaths list contains: " + oath_id)
	if card == null or scroll == null:
		return
	scroll.ensure_control_visible(card)
	await _settle()
	await _capture_oath(folder, oath_id, physical_size, panel, scroll, card, definition, variant)

func _find_oath_card(list: VBoxContainer, definition: Dictionary, completed: bool = false) -> PanelContainer:
	if definition.is_empty():
		return null
	var expected_title := ("◆  " if completed else "◇  ") + String(definition.get("label", ""))
	for child in list.get_children():
		if not child is PanelContainer or child.is_queued_for_deletion():
			continue
		for label: Label in child.find_children("*", "Label", true, false):
			if label.text == expected_title:
				return child as PanelContainer
	return null

func _capture_oath(folder: String, oath_id: String, physical_size: Vector2i, panel: OATH_PANEL, scroll: ScrollContainer, card: PanelContainer, definition: Dictionary, variant: String = "") -> void:
	var frame_name := "%s_%d%s" % [oath_id, physical_size.x, variant]
	var canvas_bounds := Rect2(Vector2.ZERO, Vector2(CANVAS_SIZE))
	check(canvas_bounds.encloses(panel.get_global_rect()), "Panel stays in the production canvas: " + frame_name)
	check(panel.get_global_rect().encloses(panel._back_button.get_global_rect()), "Back stays inside the panel: " + frame_name)
	check(scroll.get_global_rect().grow(1.0).encloses(card.get_global_rect()), "Entire requested card is visible after scrolling: " + frame_name)
	var labels := card.find_children("*", "Label", true, false)
	check(labels.size() >= 2, "Oath has title and description: " + frame_name)
	var has_exact_description := false
	var has_exact_reward := false
	var has_exact_requirement := false
	var expected_reward := String(panel._format_oath_reward(definition))
	var expected_requirement := panel._format_oath_requirement(definition, bool(card.get_meta(&"oath_completed")))
	var label_metrics: Array[Dictionary] = []
	for label: Label in labels:
		var is_description := label.text == String(definition.get("description", ""))
		has_exact_description = has_exact_description or is_description
		has_exact_reward = has_exact_reward or label.text == expected_reward
		has_exact_requirement = has_exact_requirement or label.text == expected_requirement
		check(card.get_global_rect().grow(1.0).encloses(label.get_global_rect()), "Label stays inside its card: " + frame_name + ": " + label.text)
		check(label.get_combined_minimum_size().y <= label.size.y + 1.0, "Complete wrapped label height fits: " + frame_name + ": " + label.text)
		check(label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and label.max_lines_visible == -1, "Oath text wraps without a line limit: " + frame_name)
		check(label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING, "Oath text is not abbreviated by clipping: " + frame_name)
		var physical_font_size := float(label.get_theme_font_size("font_size")) * label.get_global_transform().get_scale().abs().y * float(physical_size.y) / float(CANVAS_SIZE.y)
		var required_font_size := 11.5 if is_description else (10.5 if label.text == expected_reward or label.text == expected_requirement else 14.0)
		check(physical_font_size >= required_font_size - 0.01, "Oath text keeps readable physical font size: " + frame_name + ": " + label.text)
		label_metrics.append({"text": label.text, "lines": label.get_line_count(), "logical_width": label.size.x, "logical_height": label.size.y, "font_size": label.get_theme_font_size("font_size"), "physical_font_size": physical_font_size})
	check(has_exact_description, "UI displays the exact source description: " + frame_name)
	check(expected_reward.is_empty() or has_exact_reward, "UI displays the exact source reward: " + frame_name)
	check(has_exact_requirement, "UI displays the selected Bearing requirement and completion state: " + frame_name)
	await RenderingServer.frame_post_draw
	var filename := frame_name + ".png"
	var picture := root.get_texture().get_image()
	check(picture.get_size() == physical_size, "Capture uses physical output dimensions: " + frame_name)
	check(not picture.is_empty() and picture.save_png(folder.path_join(filename)) == OK, "Captured " + filename)
	frames.append({"file": filename, "oath_id": oath_id, "physical_size": [physical_size.x, physical_size.y], "scroll_vertical": scroll.scroll_vertical, "scroll_size": [scroll.size.x, scroll.size.y], "selected_bearing": panel._selected_oath_bearing(), "labels": label_metrics})
