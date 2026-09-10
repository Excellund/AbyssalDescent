extends SceneTree
const MENU := preload("res://scripts/menu_controller.gd")
const META := preload("res://scripts/meta_progress_store.gd")
const ASCENSION := preload("res://scripts/progression/ascension_modifier_registry.gd")
const CATALYST := preload("res://scripts/progression/catalyst_registry.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")
class FixtureMenu extends "res://scripts/menu_controller.gd":
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_build_ui()
		_apply_menu_layout()
		set_process(false)
var checks := 0
var failures: Array[String] = []
var retirement := AUDIO.new()
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
func _toggle(list: VBoxContainer, id: String) -> Button:
	for card in list.get_children():
		if card.is_queued_for_deletion():
			continue
		var definition: Dictionary = ASCENSION.get_definition(id)
		if definition.is_empty():
			definition = CATALYST.get_definition(id)
		var expected_label := String(definition.get("label", ""))
		var matches := false
		for label in card.find_children("*", "Label", true, false):
			matches = matches or label.text == expected_label
		if matches:
			return card.find_children("*", "Button", true, false).front() as Button
	return null
func _check_passive_labels(menu: MENU, viewport_size: Vector2i) -> void:
	check(menu.character_ids == MENU.CHARACTER_REGISTRY.get_launch_character_ids(), "Every playable character passive is present in roster order")
	for index in range(menu.character_ids.size()):
		var character_id := menu.character_ids[index]
		var passive_id := String(MENU.CHARACTER_REGISTRY.get_character(character_id).get("passive_id", ""))
		var label := menu.character_identity_containers[index].get_node_or_null("PassiveDescription") as RichTextLabel
		check(label != null, "Passive uses rich text: " + character_id)
		if label == null:
			continue
		check(label.text == MENU.CHARACTER_PASSIVES.get_short_description(passive_id), "Selection displays the shared passive rules: " + character_id)
		check(label.text.contains("[b][color=#") and not label.get_parsed_text().contains("{kw:"), "Selection renders authored keyword emphasis: " + character_id)
		check(label.get_theme_font_size("normal_font_size") == 14 and label.get_theme_font_size("bold_font_size") == 14, "Passive keywords retain the body size: " + character_id)
		check(label.fit_content and not label.scroll_active and label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Passive text fits and leaves the character button interactive")
		check(label.get_content_height() <= label.size.y + 1.0 and label.get_content_width() <= label.size.x + 1.0, "Full passive text fits at %s: %s" % [viewport_size, character_id])
		check(menu.character_buttons[index].get_global_rect().grow(1.0).encloses(label.get_global_rect()), "Passive remains inside its selection row at %s: %s" % [viewport_size, character_id])
func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	RunContext.current_difficulty_tier = 3
	RunContext.selected_character_id = "bastion"
	RunContext.meta_progress_profile = META._get_default_profile()
	RunContext.active_ascension_loadout = []
	META.unlock_character_tier(RunContext.meta_progress_profile, "bastion", 3)
	META.record_forsworn_clear(RunContext.meta_progress_profile, "bastion")
	for id in CATALYST.get_catalyst_ids():
		META.unlock_catalyst(RunContext.meta_progress_profile, id)
	var menu := FixtureMenu.new()
	root.add_child(menu)
	menu.root_panel.hide()
	menu.character_selector_panel.show()
	await _settle()
	for size in [Vector2i(1280, 720), Vector2i(960, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.size = size
		root.content_scale_size = size
		await _settle()
		menu._apply_menu_layout()
		await _settle()
		_check_passive_labels(menu, size)
		for panel: Panel in [menu.root_panel, menu.character_selector_panel, menu.difficulty_selector_panel, menu.ascension_panel]:
			check(Rect2(Vector2.ZERO, Vector2(size)).encloses(panel.get_global_rect()), "%s contains actual panel %s" % [size, panel.size])
		check(menu.character_selector_panel.size == menu._character_selector_panel_size(), "Fitting preserves full vessel layout dimensions")
		check(menu.ascension_panel.size == Vector2(1520, 920), "Fitting preserves Ascension internal layout dimensions")
		if size == Vector2i(2560, 1440):
			check(menu.character_selector_panel.scale == Vector2.ONE and menu.ascension_panel.scale == Vector2.ONE, "Large viewport preserves original unscaled panels")
	menu.root_panel.hide()
	menu.character_selector_panel.hide()
	var panel = menu.ascension_panel
	panel.set_setup_bearing(3)
	panel.set_run_setup_mode(true)
	panel.set_oaths_only_mode(false)
	panel.set_character_id("bastion")
	panel.show()
	panel.populate()
	await _settle()
	for id in ["hardened_foes", "thinned_choices"]:
		for _repeat in 3:
			var toggle := _toggle(panel._modifier_list, id)
			check(toggle != null and not toggle.disabled, "Unlocked modifier provides a native toggle")
			if toggle == null:
				continue
			var before := META.get_ascension_loadout(RunContext.meta_progress_profile, "bastion").has(id)
			var old_id := toggle.get_instance_id()
			toggle.grab_focus()
			toggle.pressed.emit()
			await _settle()
			var replacement := _toggle(panel._modifier_list, id)
			check(not is_instance_id_valid(old_id), "Rebuild actually retires the previous modifier button")
			check(replacement != null and replacement.has_focus(), "Modifier keeps focus on its replacement")
			check(META.get_ascension_loadout(RunContext.meta_progress_profile, "bastion").has(id) != before, "Focused native modifier toggle changes saved loadout once")
			check(RunContext.active_ascension_loadout.is_empty(), "Modifier UI edit does not activate runtime modifiers")
	panel._back_button.grab_focus()
	panel._toggle_modifier("hardened_foes")
	await _settle()
	check(panel._back_button.has_focus(), "Programmatic modifier edit does not steal focus from Back")
	var catalyst_id := String(CATALYST.get_catalyst_ids().front())
	for _repeat in 3:
		var toggle := _toggle(panel._catalyst_list, catalyst_id)
		check(toggle != null and not toggle.disabled, "Unlocked catalyst provides a native toggle")
		if toggle == null:
			continue
		var before := META.get_equipped_catalyst_ids(RunContext.meta_progress_profile, "bastion").has(catalyst_id)
		toggle.grab_focus()
		toggle.pressed.emit()
		await _settle()
		var replacement := _toggle(panel._catalyst_list, catalyst_id)
		check(replacement != null and replacement.has_focus(), "Catalyst keeps focus on its replacement")
		check(META.get_equipped_catalyst_ids(RunContext.meta_progress_profile, "bastion").has(catalyst_id) != before, "Focused native catalyst toggle changes equipment once")
	panel._back_button.grab_focus()
	panel._toggle_catalyst(catalyst_id)
	await _settle()
	check(panel._back_button.has_focus(), "Programmatic catalyst edit does not steal focus from Back")
	menu.queue_free()
	await _settle()
	check(await retirement.wait_until_retired(self), "Native fixture audio retires")
	print("[OK] Menu panel fit/focus: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
