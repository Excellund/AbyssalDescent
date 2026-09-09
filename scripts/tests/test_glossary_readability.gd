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
	var bounds := Rect2(Vector2.ZERO, Vector2(size))
	_check(bounds.encloses(panel.get_global_rect()), "Glossary fits viewport: %s/%s" % [label, size])
	_check(panel.get_global_rect().encloses(body.get_global_rect()), "Glossary text remains inside panel: " + label)
	if label != "Character Passives":
		_check(body.get_line_count() == body.get_paragraph_count(), "%s entries fit authored lines: %d lines/%d paragraphs at %s" % [label, body.get_line_count(), body.get_paragraph_count(), size])
	else:
		_check(body.scroll_active, "Full passive rules can scroll without clipping at " + str(size))
		for character: Dictionary in DATA.CHARACTERS.get_launch_characters():
			_check(body.text.contains(DATA.PASSIVES.get_description(character.passive_id)), "Glossary preserves the complete build rules for " + String(character.name))
	_check(not body.text.contains("{kw:"), "Glossary renders authored keyword spans: " + label)
	if label == "Build Keywords":
		_check(body.get_content_height() <= body.size.y, "Core keyword definitions fit without scrolling at " + str(size))
		_check(not body.text.contains("Static Wake"), "Core definitions contain no power paragraphs")
	if label == "Power Rules":
		for power in ["Blast Drive", "Razor Orbit", "Returning Crescent", "Static Wake", "Storm Crown", "Sovereign's Double", "Warden's Verdict", "Sovereign Tempo", "Sigil Chain", "Farline Volley"]:
			_check(body.text.contains(power), "Removed chapter powers retain individual rules: " + power)

func _run() -> void:
	_setup()
	var labels: Array[String] = []
	for section in DATA.glossary_sections():
		labels.append(section.label)
	for removed in ["Motion Arcana", "Boss Combinations", "Keeper"]:
		_check(not labels.has(removed), "Requested glossary section is removed: " + removed)
	_check(labels.has("Power Rules"), "Individual power rules remain available outside the core definitions")
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
