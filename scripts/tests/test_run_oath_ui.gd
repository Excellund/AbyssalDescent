extends SceneTree
const PAUSE := preload("res://scripts/pause_menu_controller.gd")

var checks := 0
var failures: Array[String] = []
var viewport: SubViewport
var controller: Node
var snapshot: Dictionary
var provider_calls := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _provide() -> Dictionary:
	provider_calls += 1
	return snapshot

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.size_2d_override = Vector2i(2560, 1440)
	viewport.size_2d_override_stretch = true
	root.add_child(viewport)
	controller = PAUSE.new()
	viewport.add_child(controller)
	controller.initialize("/root/RunContext", Callable(), Callable())
	controller.set_oath_provider(_provide)
	snapshot = {"character_name": "Bastion", "difficulty_label": "Delver", "elapsed_seconds": 73, "rows": []}
	for i in 20:
		snapshot.rows.append({"id": "oath_%d" % i, "label": "Oath %d" % i, "description": "Clear a descent with this vessel while keeping the recorded requirement intact.", "state": "on_track", "detail": "Requirement intact; clear this run to complete it.", "relevant": true})
	snapshot.rows.append({"id": "earned", "label": "Saved Oath", "state": "earned", "relevant": true})
	snapshot.rows.append({"id": "other_vessel", "label": "Other vessel", "state": "unavailable", "relevant": false})
	var original := snapshot.duplicate(true)
	var panel: Panel = controller.pause_oaths_panel
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720)]:
		viewport.size = window_size
		await process_frame
		controller.open()
		await create_timer(0.22).timeout
		check(controller.is_open() and not controller.is_oaths_open(), "Opening Pause starts on its main actions")
		check(viewport.gui_get_focus_owner() == controller._pause_buttons[0], "Pause keyboard focus begins at Resume")
		_check_native_fit(controller.pause_menu_panel, window_size, "Pause")
		for button: Button in controller._pause_buttons:
			check(controller.pause_menu_panel.get_rect().size.y >= button.get_rect().end.y, "Pause actions fit vertically: " + button.text)
			check(button.get_theme_font_size("font_size") * button.get_global_transform_with_canvas().get_scale().y * viewport.get_stretch_transform().get_scale().y >= 17.99, "Pause action remains readable: " + button.text)
		controller._oaths_button.pressed.emit()
		await _settle()
		check(controller.is_open() and controller.is_oaths_open(), "Oath inspection preserves the existing Pause state")
		check(provider_calls > 0 and panel.shown_rows.size() == 20, "Current goals come from the provider and exclude already earned/other setups")
		check(viewport.gui_get_focus_owner() == panel.back_button, "Oath keyboard focus starts on Back")
		for button: Button in controller._pause_buttons:
			check(button.disabled, "Oaths prevents keyboard activation of underlying action: " + button.text)
		_check_native_fit(panel, window_size, "Oaths")
		check(panel.context_label.text.contains("1:13") and panel.context_label.text.contains("Run time"), "Run context reports formatted elapsed time")
		check(panel.scroll.get_v_scroll_bar().max_value > panel.scroll.size.y, "Long goal list remains available by scrolling")
		var last: Control = panel.rows_container.get_child(panel.rows_container.get_child_count() - 1)
		var normal_card_style: StyleBoxFlat = last.get_theme_stylebox("panel")
		last.grab_focus()
		await _settle()
		check(panel.scroll.scroll_vertical > 0, "Keyboard focus scrolls to the final goal")
		var focused_card_style: StyleBoxFlat = last.get_theme_stylebox("panel")
		check(focused_card_style != normal_card_style and focused_card_style.border_width_left == 2 and focused_card_style.border_color == Color("badfff"), "Focused Oath uses a visible border in the actual drawn panel StyleBox")
		check(focused_card_style.bg_color == normal_card_style.bg_color and focused_card_style.get_minimum_size() == normal_card_style.get_minimum_size(), "Oath focus preserves the card fill and layout")
		panel.back_button.grab_focus()
		check(last.get_theme_stylebox("panel") == normal_card_style, "Leaving a card restores its normal drawn panel style")
		last.grab_focus()
		var old_scroll: int = panel.scroll.scroll_vertical
		var first_card: Node = panel.rows_container.get_child(0)
		panel.refresh()
		await _settle()
		check(panel.rows_container.get_child(0) == first_card and panel.scroll.scroll_vertical == old_scroll, "Unchanged live refresh preserves cards, focus and reading position")
		snapshot.rows[0]["progress_text"] = "Attack actions: 3"
		panel.refresh()
		await _settle()
		var refreshed_focus: Control = viewport.gui_get_focus_owner()
		check(refreshed_focus != null and String(refreshed_focus.get_meta("oath_id", "")) == "oath_19", "Changed live evidence preserves keyboard focus by Oath identity")
		check(refreshed_focus != null and (refreshed_focus.get_theme_stylebox("panel") as StyleBoxFlat).border_width_left == 2, "Changed live evidence retains the visible focus border")
		check(panel.scroll.scroll_vertical == old_scroll, "Changed live evidence preserves the reading position")
		snapshot.rows[0].erase("progress_text")
		panel.refresh()
		await _settle()
		panel.include_completed.button_pressed = true
		await _settle()
		check(panel.shown_rows.size() == 21 and panel.shown_rows[-1].id == "earned", "Completed toggle includes saved achievements only for this setup")
		panel.include_completed.button_pressed = false
		panel.back_button.pressed.emit()
		check(controller.is_open() and not controller.is_oaths_open() and viewport.gui_get_focus_owner() == controller._oaths_button, "Back restores Pause and the Oaths button focus")
		for button: Button in controller._pause_buttons:
			check(not button.disabled, "Back restores the main action: " + button.text)
		controller.set_checkpoint_notice("Could not save this descent. Your previous checkpoint is still available.")
		await _settle()
		_check_native_fit(controller.pause_menu_panel, window_size, "Pause with save notice")
		check(controller.checkpoint_notice_label.get_line_count() <= 3 and controller.pause_menu_panel.size.y >= controller.checkpoint_notice_label.get_rect().end.y, "Save failure stays fully inside the readable Pause panel")
		controller.set_checkpoint_notice("")
		# Existing overlays share the same modal boundary after the menu grows.
		for opener: Button in [controller._options_button, controller._glossary_button]:
			opener.grab_focus()
			opener.pressed.emit()
			var overlay: Panel = controller.pause_options_panel if opener == controller._options_button else controller.pause_glossary_panel
			check(overlay.visible and not controller.pause_menu_panel.visible, "Only the chosen overlay is displayed: " + opener.text)
			check(overlay.is_ancestor_of(viewport.gui_get_focus_owner()), "Existing overlay receives keyboard focus: " + opener.text)
			for button: Button in controller._pause_buttons:
				check(button.disabled, "Overlay prevents background action: " + button.text)
			# Close during its entrance animation, then reopen before an old
			# tween could hide it or overwrite the newly centered position.
			controller.close_options()
			check(not overlay.visible and controller.pause_menu_panel.visible and viewport.gui_get_focus_owner() == opener, "Closing an overlay restores its opener: " + opener.text)
			opener.pressed.emit()
			await create_timer(0.22).timeout
			check(overlay.visible and not controller.pause_menu_panel.visible, "Rapid reopen has no stale closing callback: " + opener.text)
			controller.close_options()
		controller.close()
	check(snapshot == original, "Viewing, refreshing and filtering never changes source evidence")
	snapshot["is_joiner"] = true
	controller.open()
	controller.open_oaths()
	check(panel.context_label.text.contains("Local elapsed") and panel.explanation.text.contains("host confirms"), "Joining player sees local timer and host-verification caveat")
	controller.close()
	var calls_before := provider_calls
	await create_timer(0.6).timeout
	check(provider_calls == calls_before, "Closed Pause never polls live Oath data")
	panel.populate({})
	check(panel.shown_rows.is_empty() and panel.rows_container.get_child(0).text.contains("No current-run evidence"), "Missing recorder evidence uses an honest empty state")
	panel.populate({"rows": [{"id": "earned", "state": "earned", "relevant": true}]})
	check(panel.shown_rows.is_empty() and panel.rows_container.get_child(0).text.contains("already earned"), "An empty missing-evidence view can change to all goals earned")
	panel.populate({"rows": [{"id": "another_vessel", "state": "unavailable", "relevant": false}]})
	check(panel.shown_rows.is_empty() and panel.rows_container.get_child(0).text.contains("No Oaths are available"), "An empty earned view can change to another setup")
	panel.populate({})
	check(panel.rows_container.get_child(0).text.contains("No current-run evidence"), "A later missing provider cannot retain an all-earned or setup claim")
	viewport.free()
	await process_frame
	print("[OK] Run Oath UI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_native_fit(panel: Control, window_size: Vector2i, label: String) -> void:
	var stretch := viewport.get_stretch_transform().get_scale()
	check((panel.scale * stretch).is_equal_approx(Vector2.ONE), label + " cancels only the production canvas stretch")
	var physical := Rect2(panel.position * stretch, panel.size)
	check(Rect2(Vector2.ZERO, Vector2(window_size)).encloses(physical), label + " fits the physical game window")
	check(physical.get_center().distance_to(Vector2(window_size) * 0.5) < 2.0, label + " is centered")

func _settle() -> void:
	for _frame in 4:
		await process_frame
