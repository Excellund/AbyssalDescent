extends "res://scripts/tests/render_reward_build_inspection.gd"

const MENU := preload("res://scripts/menu_controller.gd")
const META := preload("res://scripts/meta_progress_store.gd")

class FixtureMenu extends "res://scripts/menu_controller.gd":
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_build_ui()
		_apply_menu_layout()
		set_process(false)

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	var retirement := AUDIO_RETIREMENT.new()
	node_added.connect(retirement.observe_node)
	_setup_ui()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var folder := project_path.path_join("passive_ui_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	RunContext.meta_progress_profile = META._get_default_profile()
	RunContext.selected_character_id = "bastion"
	for id: String in BUILD_PANEL.CHARACTER_REGISTRY.get_launch_character_ids():
		META.unlock_character(RunContext.meta_progress_profile, id)
	var menu := FixtureMenu.new()
	viewport.add_child(menu)
	menu._update_character_selector()
	menu.root_panel.hide()
	menu.character_selector_panel.show()
	for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		menu._apply_menu_layout()
		await _capture_passive(folder, "character_selection_" + str(size.x))
		for index in range(menu.character_ids.size()):
			var label := menu.character_identity_containers[index].get_node("PassiveDescription") as RichTextLabel
			_check(not menu.character_name_labels[index].text.is_empty(), "Rendered selection includes the character name")
			_check(label.get_content_height() <= label.size.y + 1.0, "Rendered selection passive fits: " + menu.character_ids[index])
			_check(menu.character_buttons[index].get_global_rect().grow(1.0).encloses(label.get_global_rect()), "Rendered passive stays in its selection row")
		menu.hide()
		for character: Dictionary in BUILD_PANEL.CHARACTER_REGISTRY.get_launch_characters():
			build.refresh(String(character.id), [], [])
			build.open()
			await _capture_passive(folder, "passive_%s_%d" % [character.id, size.x])
			_check(build.passive_desc_label.get_content_height() <= build.passive_desc_label.size.y + 1.0, "Rendered build passive text fits")
			build.close()
		menu.show()
		menu.character_selector_panel.hide()
		menu.glossary_panel.show()
		var navigation := menu.glossary_panel.find_child("GlossaryNavigation", true, false)
		for button in navigation.get_children():
			if button is Button and button.text == "Character Passives":
				button.button_pressed = true
				button.pressed.emit()
		var body := menu.glossary_panel.find_child("GlossaryBody", true, false) as RichTextLabel
		await _capture_passive(folder, "passive_glossary_" + str(size.x))
		_check(body.text.contains(BUILD_PANEL.CHARACTER_PASSIVES.get_description("farline_focus")), "Glossary includes the final character's full rules")
		body.get_v_scroll_bar().value = body.get_v_scroll_bar().max_value
		await _capture_passive(folder, "passive_glossary_lower_" + str(size.x))
		menu.glossary_panel.hide()
		menu.character_selector_panel.show()
	menu.free()
	await _finish_render(retirement, folder)

func _capture_passive(folder: String, frame_name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := folder.path_join(frame_name + ".png")
	_check(viewport.get_texture().get_image().save_png(path) == OK, "Passive UI GPU frame saves: " + frame_name)
	frames.append({"name": frame_name, "path": path})
