extends "res://scripts/tests/test_blast_feedback.gd"
## Real Build Details controls on the shipped 2560x1440 logical canvas.
## Run in an isolated copy through render_gameplay_fixture.ps1 with
## -PreserveProductionCanvas. The two physical window sizes yield ten frames.

const BUILD_PANEL := preload("res://scripts/build_detail_panel.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
const CANVAS_SIZE := Vector2i(2560, 1440)

var frames: Array[Dictionary] = []
var build: BUILD_PANEL

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	_check(root.content_scale_size == CANVAS_SIZE, "Fixture starts with the production 2560x1440 canvas")
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "Fixture retains production canvas_items stretching")
	if not failures.is_empty():
		quit(1)
		return
	var retirement := AUDIO_RETIREMENT.new()
	node_added.connect(retirement.observe_node)
	var reward_input_owner := preload("res://scripts/reward_selection_ui.gd").new()
	reward_input_owner._ensure_inspection_actions()
	reward_input_owner.free()
	_make_world(0)
	player.hide()
	player.apply_upgrade("heavy_blow")
	player.apply_upgrade("sovereigns_double")
	for power_id in ["blast_drive", "static_wake", "storm_crown"]:
		player.apply_trial_power(power_id)
		player.apply_trial_power(power_id)
	build = BUILD_PANEL.new()
	root.add_child(build)
	build.setup()
	var folder := project_path.path_join("build_details_cleanup_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	for physical_size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = physical_size
		await _settle_build()
		_check(root.content_scale_size == CANVAS_SIZE, "Physical resizing preserves the production logical canvas")
		for character: Dictionary in CHARACTER.get_launch_characters():
			build.refresh_from_player(player, String(character.id), [], {"id": "storm_crown", "desc": "Unused selected offer"})
			build.open(true)
			await _settle_build()
			_check(build._content_vbox.get_child(0) == build.passive_section.get_parent(), "Passive is the first section with no selected-offer box")
			var label := build.passive_desc_label
			_check(label.text == BUILD_PANEL.CHARACTER_PASSIVES.get_build_description(String(character.passive_id)), "Build uses the concise shared character summary")
			_check(not label.get_parsed_text().contains("\n"), "Passive is one paragraph")
			_check(label.get_content_height() <= label.size.y + 1.0 and label.get_content_width() <= label.size.x + 1.0, "Full passive paragraph fits")
			var physical_font_size := float(label.get_theme_font_size("normal_font_size")) * label.get_global_transform().get_scale().abs().y * float(physical_size.y) / float(CANVAS_SIZE.y)
			_check(physical_font_size >= 17.0 - 0.01, "Passive text retains at least 17 physical pixels at the production canvas scale")
			_check(build._scroll.get_global_rect().encloses(build.passive_section.get_global_rect()), "Entire passive section is visible immediately")
			_check(build._close_button.has_focus(), "Return button owns keyboard focus on open")
			await _capture_build(folder, "passive_" + String(character.id), physical_size)
			build.close()
		build.refresh_from_player(player, "bastion")
		build.open(true)
		await _settle_build()
		var toggle := _find_owned_toggle("Blast Drive")
		_check(toggle != null, "Owned Blast Drive retains its rules toggle")
		if toggle != null:
			toggle.grab_focus()
			build._scroll.ensure_control_visible(toggle)
			await _settle_build()
			await _press_build_action("ui_accept")
			var reference: WeakRef = toggle.get_meta("build_details")
			var details := reference.get_ref() as RichTextLabel
			_check(details.visible and details.text.contains("Each blast spends one charge."), "Owned rules remain available with their real limits")
			var steps := 0
			while details.get_global_rect().end.y > build._scroll.get_global_rect().end.y + 1.0 and steps < 40:
				var before := build._scroll.scroll_vertical
				await _press_build_action("ui_down")
				_check(build._scroll.scroll_vertical > before and toggle.has_focus(), "Scaled native input scrolls owned rules before changing focus")
				steps += 1
			_check(steps > 0 and steps < 40, "Native input reaches the final owned keyword line at production scale")
			await _capture_build(folder, "owned_rules", physical_size)
		await _press_build_action("reward_back")
		_check(not build.is_open(), "Native Back closes the scaled build modal")
	build.open(true)
	for physical_size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = physical_size
		await _settle_build()
		var label := build.passive_desc_label
		var physical_font_size := float(label.get_theme_font_size("normal_font_size")) * label.get_global_transform().get_scale().abs().y * float(physical_size.y) / float(CANVAS_SIZE.y)
		_check(physical_font_size >= 17.0 - 0.01, "Live window resize keeps the already-open build readable")
		_check(Rect2(Vector2.ZERO, Vector2(CANVAS_SIZE)).encloses(build.panel.get_global_rect()), "Live window resize keeps the already-open panel inside the canvas")
		_check(build.panel.get_global_rect().encloses(build._close_button.get_global_rect()), "Live window resize keeps Return inside the panel")
	build.free()
	_free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Build fixture audio retires after teardown")
	var manifest := FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name(), "logical_canvas": [CANVAS_SIZE.x, CANVAS_SIZE.y]}, "\t"))
	manifest.close()
	print("[OK] Build Details cleanup GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _find_owned_toggle(power_name: String) -> Button:
	for entry in build.arcana_list_container.get_children():
		if entry.is_queued_for_deletion() or entry.get_child_count() == 0:
			continue
		var first := entry.get_child(0)
		if first is Button and first.text.contains(power_name):
			return first
	return null

func _settle_build() -> void:
	for _frame in range(4):
		await process_frame

func _press_build_action(action_name: String) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await _settle_build()

func _capture_build(folder: String, prefix: String, physical_size: Vector2i) -> void:
	await RenderingServer.frame_post_draw
	var name_text := "%s_%d" % [prefix, physical_size.x]
	var bounds := Rect2(Vector2.ZERO, Vector2(CANVAS_SIZE))
	_check(build.get_viewport().get_visible_rect().size.is_equal_approx(Vector2(CANVAS_SIZE)), "Build lays out in the production canvas: " + name_text)
	_check(bounds.encloses(build.panel.get_global_rect()), "Build panel stays in the canvas: " + name_text)
	_check(build.panel.get_global_rect().encloses(build._close_button.get_global_rect()), "Return remains inside the panel: " + name_text)
	var screenshot := root.get_texture().get_image()
	_check(screenshot.get_size() == physical_size, "Capture uses the actual physical window dimensions: " + name_text)
	var path := folder.path_join(name_text + ".png")
	_check(screenshot.save_png(path) == OK, "GPU frame saves: " + name_text)
	frames.append({"name": name_text, "path": path, "physical_size": [physical_size.x, physical_size.y], "passive_text": build.passive_desc_label.get_parsed_text()})
