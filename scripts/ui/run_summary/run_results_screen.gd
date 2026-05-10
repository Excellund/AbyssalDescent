extends Node
class_name RunResultsScreen

signal return_to_main_menu_requested
signal retry_run_requested

const RUN_STATS_PANEL_SCRIPT := preload("res://scripts/ui/run_summary/run_stats_panel.gd")
const BUILD_SUMMARY_PANEL_SCRIPT := preload("res://scripts/ui/run_summary/build_summary_panel.gd")
const REWARD_SUMMARY_PANEL_SCRIPT := preload("res://scripts/ui/run_summary/reward_summary_panel.gd")
const RUN_ACTION_BUTTONS_SCRIPT := preload("res://scripts/ui/run_summary/run_action_buttons.gd")
const RARITY_COMMON := Color(0.62, 0.7, 0.8, 0.9)
const RARITY_RARE := Color(0.46, 0.78, 1.0, 0.94)
const RARITY_EPIC := Color(0.82, 0.58, 1.0, 0.96)
const RARITY_LEGENDARY := Color(1.0, 0.74, 0.42, 1.0)

var _layer: CanvasLayer
var _root: Control
var _card: Panel
var _title_label: Label
var _subtitle_label: Label
var _meta_label: Label
var _content_scroll: ScrollContainer
var _content_stack: VBoxContainer
var _stats_panel
var _build_panel
var _reward_panel
var _action_buttons
var _timeline_visible: bool = true
var _input_delay_left: float = 0.0

func show_result(result_title: String, subtitle: String, summary: Dictionary, defeat_theme: bool = false, allow_retry_run: bool = true) -> void:
	if _layer == null:
		_build_ui()
	_apply_theme(defeat_theme)
	_fill_summary(result_title, subtitle, summary, allow_retry_run)
	_input_delay_left = 0.2
	_layer.visible = true
	_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_card.scale = Vector2(0.97, 0.97)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_root, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.34).set_ease(Tween.EASE_OUT)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.36).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func is_open() -> bool:
	return _layer != null and _layer.visible

func set_retry_label(text: String) -> void:
	if _action_buttons != null:
		_action_buttons.set_retry_label(text)

func set_retry_disabled(disabled: bool) -> void:
	if _action_buttons != null:
		_action_buttons.set_retry_disabled(disabled)

func _process(delta: float) -> void:
	if _input_delay_left > 0.0:
		_input_delay_left = maxf(0.0, _input_delay_left - delta)

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 212
	add_child(_layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_root)
	if not get_viewport().size_changed.is_connected(_layout_card):
		get_viewport().size_changed.connect(_layout_card)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.9)
	_root.add_child(backdrop)

	_card = Panel.new()
	_card.custom_minimum_size = Vector2(1020.0, 700.0)
	_root.add_child(_card)
	_layout_card()

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.05, 0.08, 0.13, 0.96)
	card_style.border_color = Color(RARITY_COMMON.r, RARITY_COMMON.g, RARITY_COMMON.b, 0.78)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(20)
	card_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	card_style.shadow_size = 12
	card_style.shadow_offset = Vector2(0.0, 4.0)
	_card.add_theme_stylebox_override("panel", card_style)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	_card.add_child(margin)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 56)
	stack.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 20)
	stack.add_child(_subtitle_label)

	_meta_label = Label.new()
	_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta_label.add_theme_font_size_override("font_size", 15)
	stack.add_child(_meta_label)

	var separator := ColorRect.new()
	separator.custom_minimum_size = Vector2(0.0, 2.0)
	separator.color = Color(RARITY_RARE.r, RARITY_RARE.g, RARITY_RARE.b, 0.3)
	stack.add_child(separator)

	_content_scroll = ScrollContainer.new()
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.clip_contents = true
	stack.add_child(_content_scroll)

	_content_stack = VBoxContainer.new()
	_content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_stack.add_theme_constant_override("separation", 12)
	_content_scroll.add_child(_content_stack)

	_stats_panel = RUN_STATS_PANEL_SCRIPT.new()
	_content_stack.add_child(_stats_panel)

	_build_panel = BUILD_SUMMARY_PANEL_SCRIPT.new()
	_content_stack.add_child(_build_panel)

	_reward_panel = REWARD_SUMMARY_PANEL_SCRIPT.new()
	_content_stack.add_child(_reward_panel)

	_action_buttons = RUN_ACTION_BUTTONS_SCRIPT.new()
	_action_buttons.return_to_menu_pressed.connect(func() -> void:
		if _input_delay_left > 0.0:
			return
		return_to_main_menu_requested.emit()
	)
	_action_buttons.retry_run_pressed.connect(func() -> void:
		if _input_delay_left > 0.0:
			return
		retry_run_requested.emit()
	)
	_action_buttons.toggle_timeline_pressed.connect(_toggle_timeline)
	stack.add_child(_action_buttons)

	_layer.visible = false
	set_process(true)

func _layout_card() -> void:
	if _card == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var card_size := Vector2(minf(1060.0, viewport_size.x - 40.0), minf(760.0, viewport_size.y - 30.0))
	_card.size = card_size
	_card.position = (viewport_size - card_size) * 0.5
	if _content_stack != null:
		_content_stack.custom_minimum_size = Vector2(maxf(0.0, card_size.x - 86.0), 0.0)

func _apply_theme(defeat_theme: bool) -> void:
	if _card == null:
		return
	var style := _card.get_theme_stylebox("panel")
	if not (style is StyleBoxFlat):
		return
	var flat := style as StyleBoxFlat
	if defeat_theme:
		flat.border_color = Color(0.92, 0.46, 0.44, 0.84)
		flat.bg_color = Color(0.12, 0.06, 0.08, 0.96)
	else:
		flat.border_color = Color(RARITY_COMMON.r, RARITY_COMMON.g, RARITY_COMMON.b, 0.84)
		flat.bg_color = Color(0.05, 0.08, 0.13, 0.96)
	_card.add_theme_stylebox_override("panel", flat)

func _fill_summary(result_title: String, subtitle: String, summary: Dictionary, allow_retry_run: bool) -> void:
	_title_label.text = result_title
	_title_label.add_theme_color_override("font_color", RARITY_LEGENDARY if result_title == "Victory" else Color(1.0, 0.76, 0.72, 1.0))
	_subtitle_label.text = subtitle
	_subtitle_label.add_theme_color_override("font_color", Color(RARITY_RARE.r, RARITY_RARE.g, RARITY_RARE.b, 0.82))

	var character_name := String(summary.get("character_name", "Unknown"))
	var depth := int(summary.get("max_depth", 0))
	var duration := _format_duration(int(summary.get("duration_seconds", 0)))
	var difficulty := String(summary.get("difficulty_label", "Pilgrim"))
	_meta_label.text = "%s  |  Depth %d  |  %s  |  %s" % [character_name, depth, duration, difficulty]
	_meta_label.add_theme_color_override("font_color", Color(RARITY_COMMON.r, RARITY_COMMON.g, RARITY_COMMON.b, 0.94))

	var stats := summary.get("stats", {}) as Dictionary
	_stats_panel.set_stats(stats)
	var build_summary := summary.get("build_summary", {}) as Dictionary
	_build_panel.set_build_summary(build_summary)
	_reward_panel.set_progression(summary.get("unlocks", []) as Array, summary.get("reward_timeline", []) as Array)
	_reward_panel.set_timeline_visible(_timeline_visible)
	_action_buttons.set_timeline_expanded(_timeline_visible)
	_action_buttons.set_retry_visible(allow_retry_run)

func _toggle_timeline() -> void:
	_timeline_visible = not _timeline_visible
	_reward_panel.set_timeline_visible(_timeline_visible)
	_action_buttons.set_timeline_expanded(_timeline_visible)

func _format_duration(total_seconds: int) -> String:
	var safe_total := maxi(0, total_seconds)
	var minutes := int(floor(float(safe_total) / 60.0))
	var seconds := safe_total % 60
	return "%02d:%02d" % [minutes, seconds]
