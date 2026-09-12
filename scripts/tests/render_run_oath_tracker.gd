extends "res://scripts/tests/test_relic_recovery.gd"
## Actual Main provider and native GUI input; staged states are explicitly labelled.
const OATH_PRESENTATION := preload("res://scripts/progression/run_oath_presentation.gd")
const OATH_TRACKER := preload("res://scripts/core/run_summary_tracker.gd")
const OATH_META := preload("res://scripts/meta_progress_store.gd")

var frames: Array[Dictionary] = []
var frame_folder := ""

func _run() -> void:
	if not _is_isolated() or DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.content_scale_size = Vector2i(2560, 1440)
	frame_folder = ProjectSettings.globalize_path("res://run_oath_tracker_frames")
	DirAccess.make_dir_recursive_absolute(frame_folder)
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720)]:
		root.size = window_size
		await process_frame
		_setup_recovery_world()
		_enter_recovery()
		world._exit_encounter_intro_grace()
		await _settle_oaths()
		var pause_ui: Node = world.pause_menu_controller
		var panel: Panel = pause_ui.pause_oaths_panel
		await _key(KEY_ESCAPE)
		await _settle_oaths(16)
		check(pause_ui.is_open() and root.gui_get_focus_owner() == pause_ui._pause_buttons[0], "Actual Escape opens Pause with Resume focused")
		_check_pause(pause_ui)
		await _capture("pause_main", "Actual Main Pause; no staged Oath evidence")
		pause_ui.set_checkpoint_notice("Could not save this descent. Your previous checkpoint is still available.")
		await _settle_oaths()
		_check_pause(pause_ui)
		check(pause_ui.checkpoint_notice_label.get_minimum_size().y <= pause_ui.checkpoint_notice_label.size.y, "Checkpoint warning wraps without clipping")
		await _capture("pause_notice", "Actual Pause layout; staged checkpoint failure notice")
		pause_ui.set_checkpoint_notice("")
		# Reach the new action using GUI focus traversal rather than an OS cursor.
		for _step in 4:
			await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == pause_ui._oaths_button, "Four native Tab steps reach Oaths from Resume")
		await _key(KEY_ENTER)
		await _settle_oaths()
		check(pause_ui.is_oaths_open() and root.gui_get_focus_owner() == panel.back_button, "Native Enter opens the real recorder provider and focuses Back")
		check(panel.provider == Callable(world.run_summary_recorder, "get_live_oath_presentation"), "Live frames retain World's actual recorder provider")
		check(not panel.shown_rows.is_empty(), "Actual ongoing run provides relevant Oaths")
		_check_oath_panel(panel, "live top")
		await _capture("live_provider_top", "Actual Main recorder provider; no staged summary or profile")
		await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == panel.include_completed, "Tab reaches the earned filter inside the modal")
		for _step in panel.shown_rows.size():
			await _key(KEY_TAB)
			var focus := root.gui_get_focus_owner()
			check(focus != null and panel.is_ancestor_of(focus), "Native row traversal stays inside the Oath modal")
		await _settle_oaths()
		var last: Control = panel.rows_container.get_child(panel.rows_container.get_child_count() - 1)
		check(root.gui_get_focus_owner() == last, "Native Tab traversal reaches the final Oath")
		_check_visible_row_focus(last)
		check(panel.scroll.scroll_vertical > 0, "Native row focus scrolls the current run list")
		check(_physical_rect(panel.scroll).grow(1).encloses(_physical_rect(last)), "Final focused goal is fully visible in the scroll viewport")
		await _capture("live_provider_bottom", "Actual Main recorder provider; final goal reached by native Tab navigation")
		await _key(KEY_TAB)
		check(root.gui_get_focus_owner() == panel.back_button, "Tab wraps to Back without enabling underlying Pause actions")
		await _key(KEY_ENTER)
		check(pause_ui.is_open() and not pause_ui.is_oaths_open() and root.gui_get_focus_owner() == pause_ui._oaths_button, "Native Back returns to Pause and restores Oaths focus")
		await _key(KEY_ENTER)
		await _key(KEY_ESCAPE)
		check(pause_ui.is_open() and not pause_ui.is_oaths_open(), "Escape closes only the Oath overlay")
		await _key(KEY_ESCAPE)
		check(not pause_ui.is_open(), "A second Escape resumes the real run")
		await _key(KEY_ESCAPE)
		await _settle_oaths(16)
		var actual_provider: Callable = panel.provider
		for state in ["broken", "earned", "legacy", "joiner"]:
			var staged := _staged_snapshot(state)
			panel.provider = func() -> Dictionary: return staged
			pause_ui.open_oaths()
			await _settle_oaths()
			panel.scroll.scroll_vertical = 0
			if state == "earned":
				await _key(KEY_TAB)
				await _key(KEY_SPACE)
				check(panel.include_completed.button_pressed, "Native Space reveals already earned Oaths")
				await _settle_oaths()
				panel.scroll.scroll_vertical = 0
			if state in ["broken", "legacy"]:
				await _key(KEY_TAB)
				var expected_state := "broken" if state == "broken" else "unverified"
				for row: Dictionary in panel.shown_rows:
					await _key(KEY_TAB)
					if row.state == expected_state:
						break
				var focused := root.gui_get_focus_owner()
				check(focused != null and focused.has_meta("oath_id"), "Staged evidence is shown on a native keyboard-focused row")
				if focused != null and focused.has_meta("oath_id"):
					_check_visible_row_focus(focused)
			await _settle_oaths()
			if state == "earned":
				check(panel.shown_rows[0].state == "earned" and panel.scroll.scroll_vertical == 0, "Saved Oath is visible at the top of the staged earned capture")
			if state == "joiner":
				check(panel.shown_rows[0].state == "unverified" and panel.scroll.scroll_vertical == 0, "Host-unverified boss goal is visible in the staged joiner capture")
			_check_oath_panel(panel, "staged " + state)
			await _capture("staged_" + state, "Staged " + state + " summary/profile through real Oath projection; never saved")
			await _key(KEY_ESCAPE)
			panel.include_completed.button_pressed = false
		panel.provider = actual_provider
		if window_size.x == 960:
			await _check_existing_options(pause_ui)
		pause_ui.close()
		await _cleanup_recovery_world()
		node_added.disconnect(audio_retirement.observe_node)
	FileAccess.open(frame_folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name(), "scope": "Actual Main live recorder and native keyboard Pause/Oaths navigation. Staged broken, earned, legacy, joiner and save-notice presentations are explicitly labelled. Production 2560x1440 stretch. No balance or live co-op claim."}, "\t"))
	print("[OK] Run Oath GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _staged_snapshot(state: String) -> Dictionary:
	var tracker := OATH_TRACKER.new()
	tracker.reset_for_run({"difficulty_tier": 3, "character_id": "bastion", "character_name": "Bastion", "difficulty_label": "Forsworn", "equipped_catalyst_ids": [], "ascension_tracking_complete": true, "ascension_rank": 10, "ascension_loadout": ["glass_descent", "pilgrims_burden"]})
	var summary := tracker.build_summary({"outcome": "in_progress", "duration_seconds": 120})
	summary.build_summary.arcana = [{"id": "static_wake", "stacks": 2}]
	var profile := OATH_META._get_default_profile()
	match state:
		"broken":
			summary.primary_attacks_fired = 3
			summary.dashes_performed = 4
			summary.rest_count = 1
			summary.stats.damage_taken_total = 27
			summary.duration_seconds = 490
			summary.build_summary.arcana.append({"id": "ember_ring", "stacks": 1})
		"earned":
			OATH_META.mark_oath_completed(profile, "warden_no_hit")
			summary.boss_no_hit_ids = ["warden", "sovereign"]
		"legacy":
			summary.full_run_tracking_complete = false
			summary.dash_tracking_complete = false
	return {"character_name": "Bastion [staged %s]" % state, "difficulty_label": "Forsworn", "elapsed_seconds": summary.duration_seconds, "is_joiner": state == "joiner", "rows": OATH_PRESENTATION.presentation(summary, profile, {"is_joiner": state == "joiner"})}

func _check_existing_options(pause_ui: Node) -> void:
	pause_ui._pause_buttons[2].grab_focus()
	await _key(KEY_ENTER)
	await _settle_oaths(16)
	check(pause_ui.is_options_open(), "Existing Options still opens by keyboard")
	_check_underlying_pause_hidden(pause_ui, "Options")
	await _capture("pause_options", "Actual Main Options overlay after new Pause layout")
	await _key(KEY_TAB)
	for _step in 16:
		var focus := root.gui_get_focus_owner()
		if focus is Button and focus.text == "Back":
			break
		await _key(KEY_TAB)
		var next_focus := root.gui_get_focus_owner()
		check(next_focus != null and pause_ui.pause_options_panel.is_ancestor_of(next_focus), "Native Options focus remains inside its overlay")
	var back := root.gui_get_focus_owner()
	check(back is Button and back.text == "Back", "Native Tab reaches existing Options Back")
	if back is Button and back.text == "Back":
		await _key(KEY_ENTER)
		await _settle_oaths(16)
		check(pause_ui.is_open() and not pause_ui.is_options_open(), "Existing Options Back returns to Pause")
		check(pause_ui.pause_menu_panel.visible and root.gui_get_focus_owner() == pause_ui._pause_buttons[2], "Options Back restores the main panel and its opener focus")
	pause_ui._pause_buttons[2].grab_focus()
	await _key(KEY_ENTER)
	await _settle_oaths(16)
	await _key(KEY_ESCAPE)
	await _settle_oaths(16)
	check(pause_ui.is_open() and not pause_ui.is_options_open(), "Existing Options Escape returns to Pause")
	check(pause_ui.pause_menu_panel.visible and root.gui_get_focus_owner() == pause_ui._pause_buttons[2], "Options Escape restores the main panel and its opener focus")
	pause_ui._pause_buttons[3].grab_focus()
	await _key(KEY_ENTER)
	await _settle_oaths(16)
	check(pause_ui.is_glossary_open(), "Existing Glossary still opens by keyboard")
	_check_underlying_pause_hidden(pause_ui, "Glossary")
	await _capture("pause_glossary", "Actual Main Glossary overlay after new Pause layout")
	await _key(KEY_ESCAPE)
	await _settle_oaths(16)
	check(pause_ui.is_open() and not pause_ui.is_glossary_open(), "Existing Glossary Escape returns to Pause")
	check(pause_ui.pause_menu_panel.visible and root.gui_get_focus_owner() == pause_ui._pause_buttons[3], "Glossary Escape restores the main panel and its opener focus")

func _check_underlying_pause_hidden(pause_ui: Node, context: String) -> void:
	check(not pause_ui.pause_menu_panel.visible, context + " hides the underlying main actions")
	for button: Button in pause_ui._pause_buttons:
		check(button.disabled, context + " disables the underlying main action: " + button.text)

func _check_visible_row_focus(card: Control) -> void:
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	check(style != null and style.border_width_left >= 2 and style.border_width_right >= 2 and style.border_width_top >= 2 and style.border_width_bottom >= 2, "Focused Oath row uses a visible border on its actually drawn panel style")

func _check_pause(pause_ui: Node) -> void:
	var panel: Control = pause_ui.pause_menu_panel
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(_physical_rect(panel)), "Pause panel fits the physical game image")
	for button: Button in pause_ui._pause_buttons:
		check(Rect2(Vector2.ZERO, panel.size).encloses(button.get_rect()), "Pause action fits: " + button.text)
		check(button.get_theme_font_size("font_size") * button.get_global_transform_with_canvas().get_scale().y * root.get_stretch_transform().get_scale().y >= 17.99, "Pause action is at least 18 physical pixels: " + button.text)

func _check_oath_panel(panel: Panel, context: String) -> void:
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(_physical_rect(panel)), "Oath panel fits: " + context)
	for control: Control in [panel.heading, panel.context_label, panel.explanation, panel.include_completed, panel.back_button, panel.scroll]:
		check(_physical_rect(panel).grow(1).encloses(_physical_rect(control)), "Oath header and navigation fit: " + context)
		if control is Label:
			check(control.get_minimum_size().y <= control.size.y + 1, "Oath header text wraps: " + context)
	for card: Control in panel.rows_container.get_children():
		if card is PanelContainer:
			for label: Label in card.get_child(0).get_children():
				check(label.get_minimum_size().y <= label.size.y + 1, "Oath row copy fits: %s / %s" % [context, card.get_meta("oath_id")])
				check(_physical_rect(card).grow(1).encloses(_physical_rect(label)), "Oath row contains its copy: " + context)

func _physical_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	var stretch := root.get_stretch_transform().get_scale()
	return Rect2(transform.origin * stretch, control.size * transform.get_scale() * stretch)

func _capture(label: String, source: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var name_text := "%s_%d" % [label, picture.get_width()]
	var path := frame_folder.path_join(name_text + ".png")
	check(picture.save_png(path) == OK, "Native Oath frame saves: " + name_text)
	frames.append({"name": name_text, "path": path, "size": picture.get_size(), "canvas": root.content_scale_size, "source": source})

func _key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	root.push_input(press, true)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release, true)
	await process_frame

func _settle_oaths(count: int = 6) -> void:
	for _frame in count:
		await process_frame
	await RenderingServer.frame_post_draw
