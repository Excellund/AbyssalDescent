extends SceneTree
const MENU := preload("res://scripts/menu_controller.gd")
const DATA := preload("res://scripts/shared/glossary_data.gd")
const KEYWORDS := preload("res://scripts/shared/combat_keyword_catalogue.gd")

class GlossaryMenu extends MENU:
	func _ready() -> void:
		set_process(false)
		set_process_unhandled_input(false)

var viewport: SubViewport
var menu: GlossaryMenu
var body: RichTextLabel
var navigation: VBoxContainer
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _setup() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color(0.015, 0.025, 0.045)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(background)
	menu = GlossaryMenu.new()
	viewport.add_child(menu)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.glossary_panel = menu._build_glossary_panel()
	menu.add_child(menu.glossary_panel)
	body = menu.glossary_panel.find_child("GlossaryBody", true, false) as RichTextLabel
	navigation = menu.glossary_panel.find_child("GlossaryNavigation", true, false) as VBoxContainer

func _select(label: String) -> void:
	for button in navigation.get_children():
		if button is Button and button.text == label:
			button.grab_focus()
			button.button_pressed = true
			button.pressed.emit()
			return

func _settle() -> void:
	await process_frame
	await process_frame

func _check_section(label: String, size: Vector2i) -> void:
	_select(label)
	await _settle()
	var panel := menu.glossary_panel
	var bounds := viewport.get_visible_rect()
	_check(bounds.encloses(panel.get_global_rect()), "Glossary fits viewport: %s/%s" % [label, size])
	_check(panel.get_global_rect().encloses(body.get_global_rect()), "Glossary text remains inside panel: " + label)
	_check(body.autowrap_mode != TextServer.AUTOWRAP_OFF and body.scroll_active, "Glossary preserves full text through wrapping and scrolling: " + label)
	var rendered_font_size := body.get_theme_font_size("normal_font_size") * body.get_global_transform_with_canvas().get_scale().y * viewport.get_stretch_transform().get_scale().y
	_check(rendered_font_size >= 17.99, "Glossary keeps at least 18 screen pixels at " + str(size))
	if label == "Character Passives":
		_check(body.scroll_active, "The character passive list can scroll without clipping at " + str(size))
		for character: Dictionary in DATA.CHARACTERS.get_launch_characters():
			_check(body.text.contains(DATA.PASSIVES.get_build_description(character.passive_id)), "Glossary preserves the exact Build Details paragraph for " + String(character.name))
	_check(not body.text.contains("{kw:"), "Glossary renders authored keyword spans: " + label)
	if label == "Build Keywords":
		_check(body.get_content_height() > 0.0, "Core keyword definitions lay out at " + str(size))
		_check(not body.text.contains("Static Wake"), "Core definitions contain no power paragraphs")

func _run() -> void:
	_setup()
	var labels: Array[String] = []
	for section in DATA.glossary_sections():
		labels.append(section.label)
	for removed in ["Motion Arcana", "Boss Combinations", "Keeper", "Power Rules"]:
		_check(not labels.has(removed), "Requested glossary section is removed: " + removed)
	_check(not DATA.glossary_bbcode().contains("Power Rules"), "Combined glossary contains no removed Power Rules chapter")
	for power in ["Farshot", "Patient Hunter", "Marked Prey", "Static Wake", "Storm Crown", "Blast Drive", "Razor Orbit", "Sovereign's Double", "Sovereign Tempo", "Faultline Seal"]:
		_check(not DATA.glossary_bbcode().contains("[b]" + power + "[/b]"), "Removed individual power entry is absent: " + power)
	for button in navigation.get_children():
		if button is Button:
			_check(button.text != "Power Rules", "Actual glossary navigation contains no Power Rules button")
	var keyword_text := DATA._build_keywords_section_bbcode()
	var keyword_rows := 0
	for id: String in KEYWORDS.KEYWORDS:
		var definition: String = KEYWORDS.KEYWORDS[id].definition
		if KEYWORDS.PLAIN_TERMS.has(id):
			_check(not keyword_text.contains(definition), "Ordinary prose is absent from the keyword list: " + id)
			continue
		keyword_rows += 1
		_check(keyword_text.contains(KEYWORDS.keyword_bbcode(id)), "Glossary uses canonical keyword style: " + id)
		_check(keyword_text.contains(definition), "Glossary uses canonical definition: " + id)
	_check(keyword_rows == 17, "Glossary contains the 17 actual combat keywords")
	for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		menu._apply_menu_layout()
		for label in labels:
			await _check_section(label, size)
	_select("Encounters")
	await _settle()
	body.get_v_scroll_bar().value = body.get_v_scroll_bar().max_value
	_select("Build Keywords")
	await _settle()
	_check(is_zero_approx(body.get_v_scroll_bar().value), "Changing glossary pages resets scrolling")
	viewport.free()
	await process_frame
	print("[GlossaryReadability] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
