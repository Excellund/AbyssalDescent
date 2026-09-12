extends "res://scripts/tests/test_glossary_readability.gd"

const SPAWNER := preload("res://scripts/enemy_spawner.gd")
const PAUSE := preload("res://scripts/pause_menu_controller.gd")
const GUIDE_LABEL := "Enemy Field Guide"
const APEX_IDS := ["seamlock", "mirrorline", "toll", "breakwater"]
const SCREEN_SIZES := [Vector2i(960, 540), Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]
var pause_controller: PAUSE
var pause_panel: Panel
var pause_body: RichTextLabel

func _run() -> void:
	_check_roster()
	_setup()
	viewport.size_2d_override = Vector2i(2560, 1440)
	viewport.size_2d_override_stretch = true
	for size in SCREEN_SIZES:
		viewport.size = size
		menu._apply_menu_layout()
		await _check_section(GUIDE_LABEL, size)
		_check_entries(body, "Menu")
		_check_back_button(menu.glossary_panel)
		await _check_navigation(menu.glossary_panel)
	menu.hide()
	_setup_pause()
	for size in SCREEN_SIZES:
		viewport.size = size
		await _settle()
		_check_pause(size)
		_check_back_button(pause_panel)
		await _check_navigation(pause_panel)
	viewport.free()
	await process_frame
	print("[OK] Enemy field guide: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_back_button(panel: Panel) -> void:
	for candidate in panel.find_children("*", "Button", true, false):
		var button := candidate as Button
		if button.text == "Back":
			_check(panel.get_global_rect().grow(1.0).encloses(button.get_global_rect()), "The glossary Back button stays accessible on a small screen")

func _check_navigation(panel: Panel) -> void:
	var scroll := panel.find_child("GlossaryNavigationScroll", true, false) as ScrollContainer
	_check(scroll != null and scroll.follow_focus, "Glossary navigation can scroll with keyboard focus")
	if scroll == null:
		return
	var buttons := scroll.find_children("*", "Button", true, false)
	if buttons.is_empty():
		_check(false, "The glossary keeps its navigation buttons")
		return
	var last_button := buttons.back() as Button
	last_button.grab_focus()
	await _settle()
	# Scroll positions are integer pixels. Allow one physical pixel at the rim,
	# rather than one canvas unit (less than half a pixel on smaller windows).
	var rim_tolerance := 1.01 / viewport.get_stretch_transform().get_scale().y
	_check(scroll.get_global_rect().grow(rim_tolerance).encloses(last_button.get_global_rect()), "Keyboard focus reveals the last glossary section: panel=%s, viewport=%s" % [panel.name, viewport.size])
	for candidate in buttons:
		var button := candidate as Button
		if button.text == GUIDE_LABEL:
			button.grab_focus()
			await _settle()
			return

func _check_roster() -> void:
	var seen: Array[String] = []
	for row in DATA._enemy_rows():
		var id := String(row.id)
		_check(not seen.has(id), "Field guide does not repeat an enemy: " + id)
		seen.append(id)
		_check(SPAWNER.ENEMY_SPAWN_ORDER.has(id), "Field guide enemy is a live spawn type: " + id)
		_check(not String(row.read).is_empty() and not String(row.response).is_empty(), "Enemy has both a behavior and a response: " + id)
	for id in SPAWNER.ENEMY_SPAWN_ORDER:
		_check(seen.has(id) != APEX_IDS.has(id), "Every ordinary spawn type is covered; Apex stays in Encounters: " + id)
	for id in APEX_IDS:
		_check(DATA._encounters_section_bbcode().contains("Apex " + String(id).capitalize()), "The existing Apex entry remains reachable: " + id)

func _check_entries(label: RichTextLabel, context: String) -> void:
	for row in DATA._enemy_rows():
		_check(label.get_parsed_text().contains(String(row.name) + "\n"), context + " exposes the enemy entry: " + String(row.name))
	_check(not label.text.contains("{kw:"), context + " has no unrendered semantic markup")
	_check(label.scroll_active, context + " can reach the complete field guide")

func _setup_pause() -> void:
	# Match production's 2560x1440 canvas stretch while preserving native pixels.
	viewport.size_2d_override = Vector2i(2560, 1440)
	viewport.size_2d_override_stretch = true
	pause_controller = PAUSE.new()
	viewport.add_child(pause_controller)
	pause_controller.initialize("/root/RunContext", Callable(), Callable())
	pause_panel = pause_controller.pause_glossary_panel
	pause_controller.pause_menu_layer.show()
	pause_controller.pause_menu_panel.hide()
	pause_panel.show()
	for candidate in pause_panel.find_children("*", "RichTextLabel", true, false):
		pause_body = candidate as RichTextLabel
	for candidate in pause_panel.find_children("*", "Button", true, false):
		var button := candidate as Button
		if button.text == GUIDE_LABEL:
			button.grab_focus()
			button.button_pressed = true
			button.pressed.emit()
			break

func _check_pause(size: Vector2i) -> void:
	_check(pause_body != null, "Pause glossary builds a real text body")
	if pause_body == null:
		return
	_check(pause_body.text == DATA._enemies_section_bbcode(), "Pause selects the same complete field guide at " + str(size))
	_check(Rect2(Vector2.ZERO, Vector2(2560, 1440)).encloses(pause_panel.get_global_rect()), "Pause field guide fits the production canvas at " + str(size))
	_check(pause_panel.get_global_rect().encloses(pause_body.get_global_rect()), "Pause text stays inside the glossary")
	_check(pause_body.autowrap_mode != TextServer.AUTOWRAP_OFF, "Pause entries wrap within narrow screens")
	var rendered_font_size := pause_body.get_theme_font_size("normal_font_size") * pause_body.get_global_transform_with_canvas().get_scale().y * viewport.get_stretch_transform().get_scale().y
	_check(rendered_font_size >= 17.99, "Pause glossary keeps at least 18 screen pixels at " + str(size))
	_check_entries(pause_body, "Pause")
