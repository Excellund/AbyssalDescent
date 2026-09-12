extends CanvasLayer
## Presentation only. Practice owns combat, pausing, attempts and scene changes.

const SCALED_FONT := preload("res://scripts/ui/scaled_ui_font.gd")
const STYLES := preload("res://scripts/core/menu_style_factory.gd")
const CONFIG_EDITOR := preload("res://scripts/ui/practice/practice_config_editor.gd")

signal pause_requested
signal resume_requested
signal retry_requested
signal menu_requested
signal vessel_requested(id: String)
signal config_requested(config: Dictionary)
signal start_requested
signal apply_requested
signal configure_requested
signal gameplay_rect_changed

var canvas: Control
var hud: PanelContainer
var heading: Label
var attempt_label: Label
var context_label: Label
var player_label: Label
var encounter_hint_label: Label
var boss_label: Label
var player_bar: ProgressBar
var boss_bar: ProgressBar
var pause_button: Button
var controls_label: Label
var shade: ColorRect
var modal: PanelContainer
var modal_title: Label
var modal_detail: Label
var modal_notice: Label
var vessel_row: HBoxContainer
var vessel_label: Label
var vessel_selector: OptionButton
var resume_button: Button
var retry_button: Button
var menu_button: Button
var editor: CONFIG_EDITOR
var validation_label: Label
var shown_state: Dictionary = {}
var _mode := ""
var _last_gameplay_rect := Rect2()

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	SCALED_FONT.apply_to(canvas)
	hud = _panel(8.0)
	canvas.add_child(hud)
	var stack := _stack(hud, 10)
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	stack.add_child(header)
	heading = _label("Practice", 22)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	attempt_label = _label("Attempt 1", 18)
	header.add_child(attempt_label)
	pause_button = _button("Pause · Esc", "pause")
	pause_button.custom_minimum_size.y = 36.0
	for style_name in ["normal", "hover", "pressed", "focus"]:
		var compact_style := pause_button.get_theme_stylebox(style_name) as StyleBoxFlat
		compact_style.content_margin_top = 6.0
		compact_style.content_margin_bottom = 6.0
	# Escape is the keyboard pause action. A focused gameplay button would
	# consume Space, which is the player's Dash control.
	pause_button.focus_mode = Control.FOCUS_NONE
	context_label = _label("Choose your encounter", 18)
	context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_label.custom_minimum_size.x = 200.0
	context_label.size.x = 200.0
	context_label.add_theme_color_override("font_color", Color("b6c8da"))
	stack.add_child(context_label)
	var health_row := VBoxContainer.new()
	health_row.add_theme_constant_override("separation", 16)
	stack.add_child(health_row)
	var player_stack := VBoxContainer.new()
	player_stack.add_theme_constant_override("separation", 2)
	player_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_row.add_child(player_stack)
	player_label = _label("Bastion", 18)
	player_stack.add_child(player_label)
	player_bar = _health_bar(Color("70b8cb"))
	player_stack.add_child(player_bar)
	var boss_stack := VBoxContainer.new()
	boss_stack.add_theme_constant_override("separation", 2)
	boss_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_row.add_child(boss_stack)
	boss_label = _label("Enemies remaining", 18)
	boss_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boss_label.custom_minimum_size.x = 200.0
	boss_label.size.x = 200.0
	boss_stack.add_child(boss_label)
	boss_bar = _health_bar(Color("d78c82"))
	boss_stack.add_child(boss_bar)
	encounter_hint_label = _label("", 18)
	encounter_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	encounter_hint_label.custom_minimum_size.x = 200.0
	encounter_hint_label.size.x = 200.0
	encounter_hint_label.add_theme_color_override("font_color", Color("e1c695"))
	boss_stack.add_child(encounter_hint_label)
	var hud_spacer := Control.new()
	hud_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(hud_spacer)
	stack.add_child(pause_button)
	controls_label = _label("Move: WASD   ·   Attack: left click   ·   Dash: Space   ·   Pause: Esc", 18)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	controls_label.add_theme_constant_override("shadow_offset_x", 1)
	controls_label.add_theme_constant_override("shadow_offset_y", 1)
	controls_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(controls_label)
	shade = ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.045, 0.76)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(shade)
	modal = _panel()
	canvas.add_child(modal)
	var modal_stack := _stack(modal, 8)
	modal_title = _label("Set up Practice", 26)
	modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_stack.add_child(modal_title)
	modal_detail = _label("", 18)
	modal_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_stack.add_child(modal_detail)
	modal_notice = _label("All Vessels and powers are available here. Your saved descent and normal setup are kept.", 18)
	modal_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_notice.add_theme_color_override("font_color", Color("b6c8da"))
	modal_stack.add_child(modal_notice)
	editor = CONFIG_EDITOR.new()
	modal_stack.add_child(editor)
	editor.config_changed.connect(func(config: Dictionary) -> void: config_requested.emit(config.duplicate(true)))
	vessel_selector = editor.character_selector
	validation_label = _label("", 18)
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validation_label.add_theme_color_override("font_color", Color("ffc2b3"))
	modal_stack.add_child(validation_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	modal_stack.add_child(actions)
	resume_button = _button("Resume", "resume")
	retry_button = _button("Start", "apply")
	menu_button = _button("Menu", "menu")
	for button in [resume_button, retry_button, menu_button]:
		actions.add_child(button)
	# Wrapped labels initially measure before their container assigns a width.
	# Refit when their real minimum settles, including the first paused frame.
	modal.minimum_size_changed.connect(func() -> void: call_deferred("_layout"))
	hud.minimum_size_changed.connect(func() -> void: call_deferred("_layout"))
	get_viewport().size_changed.connect(_layout)
	_layout()
	present(shown_state)

func _panel(vertical_margin: float = 16.0) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := STYLES.make_panel_style(Color("111b29"), Color("557b9e"), 14, 2)
	for side in ["left", "right"]:
		style.set("content_margin_" + side, 20.0)
	for side in ["top", "bottom"]:
		style.set("content_margin_" + side, vertical_margin)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _stack(parent: Control, separation: int) -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", separation)
	parent.add_child(stack)
	return stack

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("eef5ff"))
	return label

func _button(text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(132, 46)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("eef5ff"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var border := Color("badfff") if state == "focus" else Color("557b9e")
		var fill := Color("253d56") if state == "hover" else Color("192b3e")
		button.add_theme_stylebox_override(state, STYLES.make_button_style(fill, border, 10, 2))
	button.pressed.connect(_request.bind(action))
	return button

func _health_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 4
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", STYLES.make_panel_style(Color("26384b"), Color.TRANSPARENT, 4, 0))
	bar.add_theme_stylebox_override("fill", STYLES.make_panel_style(color, Color.TRANSPARENT, 4, 0))
	return bar

func present(state: Dictionary) -> void:
	shown_state = state.duplicate(true)
	if canvas == null:
		return
	var next_mode := String(state.get("mode", "setup"))
	var changed := next_mode != _mode
	_mode = next_mode
	var attempt := maxi(0, int(state.get("attempt", 0)))
	var elapsed := maxi(0, int(state.get("elapsed_seconds", 0.0)))
	var character_name := String(state.get("character_name", "Bastion"))
	heading.text = "Practice"
	attempt_label.text = "Attempt %d · %d:%02d" % [attempt, elapsed / 60, elapsed % 60]
	var current: Dictionary = state.get("current_config", {})
	context_label.text = "Floor %d\n%s" % [int(current.get("floor", 1)), String(state.get("encounter_name", "Practice"))]
	_update_health(player_label, player_bar, character_name, float(state.get("health", 130.0)), float(state.get("max_health", 130.0)))
	var health_width := player_label.get_theme_font("font").get_string_size(player_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, player_label.get_theme_font_size("font_size")).x
	if health_width > 200.0:
		player_label.text = player_label.text.replace(character_name + "  ", character_name + "\n")
	var enemy_count := maxi(0, int(state.get("enemy_count", 0)))
	var alive_count := maxi(0, int(state.get("alive_count", 0)))
	boss_label.text = "Empty arena\n0 enemies" if enemy_count == 0 else "Enemies remaining\n%d / %d" % [alive_count, enemy_count]
	boss_bar.max_value = maxi(1, enemy_count)
	boss_bar.value = alive_count
	var encounter_status := String(state.get("encounter_status", ""))
	if not encounter_status.is_empty():
		boss_label.text = encounter_status
	boss_bar.visible = not bool((state.get("objective_state", {}) as Dictionary).get("active", false))
	var active := _mode == "active"
	encounter_hint_label.text = String(state.get("encounter_hint", ""))
	encounter_hint_label.visible = active and not encounter_hint_label.text.is_empty()
	shade.visible = not active
	modal.visible = not active
	pause_button.visible = active
	hud.visible = active
	controls_label.visible = active
	resume_button.visible = _mode == "paused" or (_mode == "setup" and bool(state.get("can_resume", false)))
	retry_button.visible = _mode in ["setup", "paused", "victory", "defeat"]
	retry_button.text = "Start" if attempt == 0 else "Apply & restart"
	retry_button.tooltip_text = "Start a fresh attempt with this setup."
	menu_button.visible = not active
	modal_title.text = {"setup": "Set up Practice", "paused": "Practice paused", "victory": "Encounter cleared", "defeat": "Attempt ended", "error": "Practice unavailable"}.get(_mode, "Practice")
	var detail := String(state.get("detail", ""))
	if detail.is_empty():
		detail = "Choose a Vessel, build and encounter, then Start." if attempt == 0 else "%s · Attempt %d · %d:%02d · Changes apply to a fresh attempt." % [character_name, attempt, elapsed / 60, elapsed % 60]
	modal_detail.text = detail
	editor.visible = _mode != "error"
	editor.present(state.get("draft_config", {}), state.get("catalogue", {}), _mode in ["setup", "paused", "victory", "defeat"])
	var validation: Dictionary = state.get("validation", {"valid": true})
	var errors: Array = validation.get("errors", [])
	var warnings: Array = validation.get("warnings", [])
	validation_label.text = String(errors[0]) if not errors.is_empty() else String(warnings[0]) if not warnings.is_empty() else ""
	validation_label.tooltip_text = "\n".join(errors + warnings)
	validation_label.visible = not validation_label.text.is_empty() and not active
	retry_button.disabled = not bool(validation.get("valid", true))
	if changed:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and canvas.is_ancestor_of(focused):
			focused.release_focus()
		if _mode == "paused":
			resume_button.grab_focus()
		elif _mode in ["setup", "victory", "defeat"]:
			retry_button.grab_focus()
		elif _mode == "error":
			menu_button.grab_focus()
	_layout()

func _request_vessel(index: int) -> void:
	if not (_mode in ["setup", "paused", "victory", "defeat"]) or vessel_selector.disabled or index < 0 or index >= vessel_selector.item_count:
		return
	get_viewport().set_input_as_handled()
	editor._set_scalar("character_id", vessel_selector.get_item_metadata(index))

func _update_health(label: Label, bar: ProgressBar, name_text: String, health: float, maximum: float) -> void:
	var safe_max := maxf(1.0, maximum)
	var safe_health := clampf(health, 0.0, safe_max)
	label.text = "%s  %d / %d" % [name_text, ceili(safe_health), ceili(safe_max)]
	bar.max_value = safe_max
	bar.value = safe_health

func _request(action: String) -> void:
	var allowed := (action == "pause" and _mode == "active") or (action == "resume" and resume_button.visible) or (action == "apply" and _mode in ["setup", "paused", "victory", "defeat"] and not retry_button.disabled) or (action == "menu" and _mode in ["setup", "paused", "victory", "defeat", "error"])
	if not allowed:
		return
	get_viewport().set_input_as_handled()
	match action:
		"pause": pause_requested.emit()
		"resume": resume_requested.emit()
		"apply":
			if int(shown_state.get("attempt", 0)) == 0:
				start_requested.emit()
			else:
				apply_requested.emit()
		"menu": menu_requested.emit()

func _layout() -> void:
	if canvas == null or not is_inside_tree() or get_viewport() == null:
		return
	var stretch := get_viewport().get_stretch_transform().get_scale().abs()
	if stretch.x <= 0.0 or stretch.y <= 0.0:
		return
	canvas.scale = Vector2.ONE / stretch
	canvas.size = get_viewport().get_visible_rect().size * stretch
	controls_label.position = Vector2(24, canvas.size.y - 38)
	controls_label.size = Vector2(canvas.size.x - 48, 26)
	hud.position = Vector2(canvas.size.x - 264.0, 24.0)
	hud.size = Vector2(240.0, controls_label.position.y - 12.0 - hud.position.y)
	# The button row changes minimum size when modes switch. A stable frame
	# avoids centering against the previous mode before containers sort.
	var modal_height := minf(900.0, canvas.size.y - 32.0) if _mode != "error" else 260.0
	modal.size = Vector2(minf(1080.0, canvas.size.x - 32.0), modal_height)
	modal.position = (canvas.size - modal.size) * 0.5
	var clear_rect := get_gameplay_rect()
	if clear_rect != _last_gameplay_rect:
		_last_gameplay_rect = clear_rect
		gameplay_rect_changed.emit()

func get_gameplay_rect() -> Rect2:
	if not is_inside_tree() or canvas == null or hud == null or controls_label == null or canvas.size.x <= 0.0:
		return Rect2()
	var stretch := get_viewport().get_stretch_transform().get_scale().abs()
	if stretch.x <= 0.0 or stretch.y <= 0.0:
		return Rect2()
	var top := 24.0
	var bottom := controls_label.position.y - 12.0
	var right := hud.position.x - 12.0
	if bottom <= top or right <= 24.0:
		return Rect2()
	return Rect2(Vector2(24.0, top) / stretch, Vector2(right - 24.0, bottom - top) / stretch)
