extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const MUTATOR_ICON_BLOOD_RUSH: Texture2D = preload("res://assets/ui/mutators/blood_rush.svg")
const MUTATOR_ICON_FLASHPOINT: Texture2D = preload("res://assets/ui/mutators/flashpoint.svg")
const MUTATOR_ICON_SIEGEBREAK: Texture2D = preload("res://assets/ui/mutators/siegebreak.svg")
const MUTATOR_ICON_IRON_VOLLEY: Texture2D = preload("res://assets/ui/mutators/iron_volley.svg")
const MUTATOR_ICON_FORTIFIED_PATH := "res://assets/ui/mutators/fortified.svg"
const MUTATOR_ICON_HUNTERS_FOCUS_PATH := "res://assets/ui/mutators/hunters_focus.svg"
const MUTATOR_ICON_KILLBOX_PATH := "res://assets/ui/mutators/killbox.svg"
const MUTATOR_ICON_COMBO_RELAY_PATH := "res://assets/ui/mutators/combo_relay.svg"
const MUTATOR_ICON_CONVERGENCE_PATH := "res://assets/ui/mutators/convergence.svg"
const MUTATOR_ICON_CONFLAGRATION_PATH := "res://assets/ui/mutators/conflagration.svg"
const MUTATOR_ICON_TETHER_WEB_PATH := "res://assets/ui/mutators/tether_web.svg"

signal reward_selected(choice: Dictionary, mode: int, is_initial: bool)
signal reward_offers_presented(offers: Array[Dictionary], mode: int, is_initial: bool, stage: int)

var boon_choice_count: int = 3
var boon_reveal_duration: float = 0.22

var boon_selection_active: bool = false
var boon_title_text: String = ""
var boon_choices: Array[Dictionary] = []
var pending_initial_boon: bool = false
var boon_confirm_lock_time: float = 0.0
var boon_hovered_index: int = -1
var boon_reveal_time: float = 0.0
var reward_selection_mode: int = ENUMS.RewardMode.BOON
var mission_reward_stage: int = 0
var pending_mission_upgrade_choice: Dictionary = {}
var current_player: Node2D
var current_character_id: String = ""

func _is_upgrade_blocked_for_character(upgrade_id: String) -> bool:
	var normalized_character_id := current_character_id.strip_edges().to_lower()
	var normalized_upgrade_id := upgrade_id.strip_edges().to_lower()
	return normalized_character_id == "riftlancer" and normalized_upgrade_id == "wide_arc"

var boon_layer: CanvasLayer
var boon_title_label: Label
var boon_subtitle_label: Label
var epitaph_label: RichTextLabel
var boon_card_panels: Array[Panel] = []
var boon_card_labels: Array[RichTextLabel] = []
var boon_card_stack_labels: Array[Label] = []
var boon_card_icon_nodes: Array[TextureRect] = []
var boon_card_rects: Array[Rect2] = []
var boon_backdrop: ColorRect
var current_player_mutator: Dictionary = {}
var _epitaph_text: String = ""
var _epitaph_pulse_active: bool = false
var _epitaph_pulse_time: float = 0.0
var _mutator_icon_killbox: Texture2D
var _mutator_icon_fortified: Texture2D
var _mutator_icon_hunters_focus: Texture2D
var _mutator_icon_combo_relay: Texture2D
var _mutator_icon_convergence: Texture2D
var _mutator_icon_conflagration: Texture2D
var _mutator_icon_tether_web: Texture2D
const EPITAPH_COLOR_COOL := Color(0.72, 0.86, 1.0, 0.9)
const EPITAPH_COLOR_WARM := Color(1.0, 0.95, 0.84, 1.0)
const EPITAPH_PULSE_SPEED := 2.1
const BOON_CARD_MAX_WIDTH := 1460.0
const BOON_CARD_MIN_WIDTH := 860.0
const BOON_CARD_HEIGHT := 118.0
const BOON_CARD_GAP := 20.0
const BOON_TOP_SAFE_Y := 156.0
const BOON_TOP_MAX_Y := 210.0
const BOON_SIDE_MARGIN_RATIO := 0.08
const BOON_ICON_POS := Vector2(14.0, 14.0)
const BOON_ICON_SIZE := Vector2(24.0, 24.0)
const BOON_LABEL_X := 52.0
const MUTATOR_ICON_POS := Vector2(10.0, 10.0)
const MUTATOR_ICON_SIZE := Vector2(32.0, 32.0)
const MUTATOR_LABEL_X := 52.0

func initialize(choice_count: int, reveal_duration: float) -> void:
	boon_choice_count = choice_count
	boon_reveal_duration = reveal_duration
	_create_ui()

func is_active() -> bool:
	return boon_selection_active

func get_confirm_lock_time() -> float:
	return boon_confirm_lock_time

func get_choice_count() -> int:
	return boon_choice_count

func close_selection() -> void:
	boon_selection_active = false
	pending_initial_boon = false
	reward_selection_mode = ENUMS.RewardMode.BOON
	mission_reward_stage = 0
	pending_mission_upgrade_choice = {}
	current_player = null
	current_player_mutator = {}
	current_character_id = ""
	boon_choices.clear()
	_epitaph_text = ""
	_epitaph_pulse_active = false
	if boon_layer != null:
		boon_layer.visible = false


func open_selection(title: String, is_initial: bool, mode: int, power_registry: Node, player: Node2D, rng: RandomNumberGenerator, player_mutator: Dictionary = {}, epitaph: String = "", character_id: String = "") -> void:
	boon_selection_active = true
	pending_initial_boon = is_initial
	boon_title_text = title
	reward_selection_mode = mode
	mission_reward_stage = 0
	pending_mission_upgrade_choice = {}
	current_player = player
	current_player_mutator = player_mutator
	current_character_id = character_id
	_epitaph_text = epitaph
	_apply_mode_theme()
	if reward_selection_mode == ENUMS.RewardMode.ARCANA:
		boon_choices = _roll_arcana_choices(boon_choice_count, power_registry, player, rng)
	elif reward_selection_mode == ENUMS.RewardMode.MISSION:
		boon_choices = _roll_objective_choices(boon_choice_count, power_registry, player, rng)
	elif reward_selection_mode == ENUMS.RewardMode.BOSS:
		boon_choices = _roll_boss_reward_choices(boon_choice_count, power_registry, player, rng)
	else:
		boon_choices = _roll_boon_choices(boon_choice_count, power_registry, player, rng)
	boon_confirm_lock_time = boon_reveal_duration + 0.08
	boon_reveal_time = 0.0
	boon_hovered_index = -1
	_apply_boon_card_styles(-1)
	_refresh_boon_ui(player)
	_refresh_epitaph_display()
	_emit_reward_offers_presented()

func process_input(delta: float) -> void:
	if not boon_selection_active:
		return
	if boon_choices.is_empty():
		return

	if boon_confirm_lock_time > 0.0:
		boon_confirm_lock_time = maxf(0.0, boon_confirm_lock_time - delta)
		boon_reveal_time += delta
		_update_boon_reveal_visuals()
		return

	_update_boon_hover()
	if Input.is_action_just_pressed("attack"):
		if boon_hovered_index >= 0 and boon_hovered_index < boon_choices.size():
			var picked := boon_choices[boon_hovered_index]
			if reward_selection_mode == ENUMS.RewardMode.MISSION and mission_reward_stage == 0 and _has_mission_bonus_mutator():
				pending_mission_upgrade_choice = picked
				mission_reward_stage = 1
				boon_choices = _roll_objective_mutator_choice(current_player_mutator)
				boon_confirm_lock_time = boon_reveal_duration + 0.08
				boon_reveal_time = 0.0
				boon_hovered_index = -1
				_apply_boon_card_styles(-1)
				_refresh_boon_ui(current_player)
				_emit_reward_offers_presented()
				return
			var mode := reward_selection_mode
			var initial := pending_initial_boon
			var emitted_choice := picked
			if mode == ENUMS.RewardMode.MISSION and mission_reward_stage == 1 and not pending_mission_upgrade_choice.is_empty():
				emitted_choice = {
					"mission_upgrade": pending_mission_upgrade_choice,
					"mission_mutator": picked
				}
			boon_selection_active = false
			boon_choices.clear()
			if boon_layer != null:
				boon_layer.visible = false
			reward_selection_mode = ENUMS.RewardMode.BOON
			mission_reward_stage = 0
			pending_mission_upgrade_choice = {}
			current_player = null
			current_player_mutator = {}
			pending_initial_boon = false
			emit_signal("reward_selected", emitted_choice, mode, initial)
			return
	
	_update_epitaph_pulse(delta)


func _update_epitaph_pulse(delta: float) -> void:
	if not _epitaph_pulse_active or epitaph_label == null:
		return
	_epitaph_pulse_time += delta
	var t := (sin(_epitaph_pulse_time * EPITAPH_PULSE_SPEED) + 1.0) * 0.5
	epitaph_label.modulate = EPITAPH_COLOR_COOL.lerp(EPITAPH_COLOR_WARM, t)

func _refresh_epitaph_display() -> void:
	if epitaph_label == null:
		return
	if _epitaph_text.is_empty():
		epitaph_label.visible = false
		_epitaph_pulse_active = false
		return
	epitaph_label.text = "[center][wave amp=14.0 freq=3.0]" + _epitaph_text + "[/wave][/center]"
	epitaph_label.visible = true
	epitaph_label.modulate = EPITAPH_COLOR_COOL
	_epitaph_pulse_time = 0.0
	_epitaph_pulse_active = true


func _create_ui() -> void:
	boon_layer = CanvasLayer.new()
	boon_layer.layer = 130
	add_child(boon_layer)
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)

	boon_backdrop = ColorRect.new()
	boon_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	boon_backdrop.offset_left = 0.0
	boon_backdrop.offset_top = 0.0
	boon_backdrop.offset_right = 0.0
	boon_backdrop.offset_bottom = 0.0
	boon_backdrop.color = Color(0.01, 0.02, 0.05, 0.7)
	boon_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boon_layer.add_child(boon_backdrop)

	boon_title_label = Label.new()
	boon_title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	boon_title_label.offset_top = 44.0
	boon_title_label.offset_bottom = 108.0
	boon_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boon_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boon_title_label.add_theme_font_size_override("font_size", 46)
	boon_title_label.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0, 1.0))
	boon_title_label.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.06, 0.96))
	boon_title_label.add_theme_constant_override("shadow_offset_x", 3)
	boon_title_label.add_theme_constant_override("shadow_offset_y", 3)
	boon_layer.add_child(boon_title_label)

	boon_subtitle_label = Label.new()
	boon_subtitle_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	boon_subtitle_label.offset_top = 108.0
	boon_subtitle_label.offset_bottom = 148.0
	boon_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boon_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boon_subtitle_label.add_theme_font_size_override("font_size", 20)
	boon_subtitle_label.add_theme_color_override("font_color", Color(0.72, 0.82, 1.0, 0.65))
	boon_subtitle_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	boon_subtitle_label.add_theme_constant_override("shadow_offset_x", 2)
	boon_subtitle_label.add_theme_constant_override("shadow_offset_y", 2)
	boon_layer.add_child(boon_subtitle_label)

	boon_card_panels.clear()
	boon_card_labels.clear()
	boon_card_stack_labels.clear()
	boon_card_icon_nodes.clear()
	boon_card_rects.clear()
	for i in range(boon_choice_count):
		var panel := Panel.new()
		panel.position = Vector2.ZERO
		panel.custom_minimum_size = Vector2(BOON_CARD_MAX_WIDTH, BOON_CARD_HEIGHT)
		boon_layer.add_child(panel)

		var icon_node := TextureRect.new()
		icon_node.position = BOON_ICON_POS
		icon_node.size = BOON_ICON_SIZE
		icon_node.custom_minimum_size = BOON_ICON_SIZE
		icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_node.visible = false
		panel.add_child(icon_node)

		var option_label := RichTextLabel.new()
		option_label.position = Vector2(BOON_LABEL_X, 6.0)
		option_label.custom_minimum_size = Vector2(1158.0, 106.0)
		option_label.bbcode_enabled = true
		option_label.scroll_active = false
		option_label.fit_content = false
		option_label.add_theme_font_size_override("normal_font_size", 22)
		option_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
		option_label.add_theme_constant_override("shadow_offset_x", 2)
		option_label.add_theme_constant_override("shadow_offset_y", 2)
		panel.add_child(option_label)

		var stack_label := Label.new()
		stack_label.position = Vector2(1230.0, 10.0)
		stack_label.custom_minimum_size = Vector2(210.0, 28.0)
		stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stack_label.add_theme_font_size_override("font_size", 21)
		stack_label.add_theme_color_override("font_color", Color(0.98, 0.9, 0.68, 0.95))
		stack_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		stack_label.add_theme_constant_override("shadow_offset_x", 2)
		stack_label.add_theme_constant_override("shadow_offset_y", 2)
		stack_label.visible = false
		panel.add_child(stack_label)

		boon_card_panels.append(panel)
		boon_card_labels.append(option_label)
		boon_card_stack_labels.append(stack_label)
		boon_card_icon_nodes.append(icon_node)
		boon_card_rects.append(Rect2(Vector2.ZERO, Vector2.ZERO))

	epitaph_label = RichTextLabel.new()
	epitaph_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	epitaph_label.offset_left = 60.0
	epitaph_label.offset_right = -60.0
	epitaph_label.bbcode_enabled = true
	epitaph_label.scroll_active = false
	epitaph_label.fit_content = true
	epitaph_label.custom_minimum_size = Vector2(0.0, 100.0)
	epitaph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	epitaph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	epitaph_label.add_theme_font_size_override("normal_font_size", 24)
	epitaph_label.add_theme_color_override("font_color", EPITAPH_COLOR_COOL)
	epitaph_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	epitaph_label.add_theme_constant_override("shadow_offset_x", 2)
	epitaph_label.add_theme_constant_override("shadow_offset_y", 2)
	epitaph_label.visible = false
	boon_layer.add_child(epitaph_label)

	_layout_boon_cards()
	_position_epitaph_label()
	boon_layer.visible = false

func _on_viewport_size_changed() -> void:
	_layout_boon_cards()
	_position_epitaph_label()
	if boon_selection_active:
		_update_boon_reveal_visuals()

func _layout_boon_cards() -> void:
	if boon_card_panels.is_empty() or get_viewport() == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var side_margin := maxf(48.0, viewport_size.x * BOON_SIDE_MARGIN_RATIO)
	var card_width := clampf(viewport_size.x - side_margin * 2.0, BOON_CARD_MIN_WIDTH, BOON_CARD_MAX_WIDTH)
	var total_height := float(boon_choice_count) * BOON_CARD_HEIGHT + float(maxi(0, boon_choice_count - 1)) * BOON_CARD_GAP
	var start_x := (viewport_size.x - card_width) * 0.5
	var centered_y := (viewport_size.y - total_height) * 0.5
	var start_y := clampf(centered_y, BOON_TOP_SAFE_Y, BOON_TOP_MAX_Y)
	for i in range(boon_card_panels.size()):
		var panel := boon_card_panels[i]
		var base_pos := Vector2(start_x, start_y + float(i) * (BOON_CARD_HEIGHT + BOON_CARD_GAP))
		panel.position = base_pos
		panel.custom_minimum_size = Vector2(card_width, BOON_CARD_HEIGHT)
		if i < boon_card_rects.size():
			boon_card_rects[i] = Rect2(base_pos, Vector2(card_width, BOON_CARD_HEIGHT))
		if i < boon_card_labels.size():
			var label := boon_card_labels[i]
			var stack_w := 210.0
			var stack_x := card_width - stack_w - 18.0
			var text_x := BOON_LABEL_X
			label.position = Vector2(text_x, 6.0)
			label.custom_minimum_size = Vector2(maxf(320.0, stack_x - text_x - 12.0), 106.0)
		if i < boon_card_stack_labels.size():
			var stack_label := boon_card_stack_labels[i]
			stack_label.position = Vector2(card_width - stack_label.custom_minimum_size.x - 18.0, 10.0)

func _position_epitaph_label() -> void:
	if epitaph_label == null or boon_card_rects.is_empty() or get_viewport() == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	# Find the bottom of the last card
	var last_card_bottom := 0.0
	for rect in boon_card_rects:
		var card_bottom := rect.position.y + rect.size.y
		if card_bottom > last_card_bottom:
			last_card_bottom = card_bottom
	# Calculate halfway point between card bottom and viewport bottom
	var halfway_y := (last_card_bottom + viewport_size.y) * 0.5
	# Position epitaph centered on halfway point
	var epitaph_height := 100.0  # Approximate label height
	epitaph_label.offset_top = halfway_y - epitaph_height * 0.5
	epitaph_label.position = Vector2(epitaph_label.position.x, halfway_y - epitaph_height * 0.5)
	epitaph_label.size = Vector2(viewport_size.x - 120.0, epitaph_height)

func _apply_mode_theme() -> void:
	if boon_backdrop == null or boon_title_label == null:
		return
	if reward_selection_mode == ENUMS.RewardMode.ARCANA:
		boon_backdrop.color = Color(0.05, 0.02, 0.01, 0.72)
		boon_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.76, 1.0))
		boon_title_label.add_theme_color_override("font_shadow_color", Color(0.08, 0.03, 0.01, 0.96))
		if boon_subtitle_label != null:
			boon_subtitle_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.55, 0.65))
	elif reward_selection_mode == ENUMS.RewardMode.MISSION:
		boon_backdrop.color = Color(0.035, 0.03, 0.015, 0.7)
		boon_title_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.76, 1.0))
		boon_title_label.add_theme_color_override("font_shadow_color", Color(0.09, 0.06, 0.02, 0.95))
		if boon_subtitle_label != null:
			boon_subtitle_label.add_theme_color_override("font_color", Color(0.94, 0.82, 0.6, 0.7))
	elif reward_selection_mode == ENUMS.RewardMode.BOSS:
		boon_backdrop.color = Color(0.04, 0.01, 0.06, 0.72)
		boon_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.95, 1.0))
		boon_title_label.add_theme_color_override("font_shadow_color", Color(0.08, 0.01, 0.08, 0.96))
		if boon_subtitle_label != null:
			boon_subtitle_label.add_theme_color_override("font_color", Color(0.92, 0.72, 0.98, 0.7))
	else:
		boon_backdrop.color = Color(0.01, 0.02, 0.05, 0.7)
		boon_title_label.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0, 1.0))
		boon_title_label.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.04, 0.95))
		if boon_subtitle_label != null:
			boon_subtitle_label.add_theme_color_override("font_color", Color(0.72, 0.82, 1.0, 0.65))

func _refresh_boon_ui(player: Node2D) -> void:
	if boon_layer == null:
		return
	boon_layer.visible = true
	boon_title_label.text = _get_boon_title_text()
	if boon_subtitle_label != null:
		boon_subtitle_label.text = _get_boon_subtitle_text()

	for i in range(boon_card_labels.size()):
		var panel := boon_card_panels[i]
		var label := boon_card_labels[i]
		var stack_label := boon_card_stack_labels[i]
		var icon_node := boon_card_icon_nodes[i]
		if i >= boon_choices.size():
			label.text = ""
			stack_label.text = ""
			stack_label.visible = false
			icon_node.texture = null
			icon_node.visible = false
			panel.visible = false
			continue
		panel.visible = true
		var boon := boon_choices[i]
		var is_mutator_choice := bool(boon.get("is_mutator", false))
		var stack_limit := int(boon.get("stack_limit", 0))
		var stack_count := _get_stack_count_for_choice(boon, player)
		var icon_line := _format_stack_progress_icons(stack_count, stack_limit)
		if is_mutator_choice or icon_line.is_empty():
			stack_label.text = ""
			stack_label.visible = false
		else:
			stack_label.text = icon_line
			stack_label.visible = true
		if is_mutator_choice:
			var mutator_data := boon.get("full_data", {}) as Dictionary
			var icon_shape := String(mutator_data.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID, ""))
			var icon_texture := _get_mutator_icon_texture(icon_shape)
			var icon_color: Color = mutator_data.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_THEME_COLOR, Color(0.95, 0.95, 0.95, 1.0)) as Color
			icon_node.position = MUTATOR_ICON_POS
			icon_node.size = MUTATOR_ICON_SIZE
			icon_node.custom_minimum_size = MUTATOR_ICON_SIZE
			label.position = Vector2(MUTATOR_LABEL_X, 6.0)
			icon_node.texture = icon_texture
			icon_node.modulate = Color(icon_color.r, icon_color.g, icon_color.b, 1.0)
			icon_node.visible = icon_texture != null
			var boon_desc := String(boon.get("desc", boon.get("description", "")))
			var mutator_name := _choice_display_name(boon)
			label.text = "[b][color=#fffef0]%s[/color][/b]\n%s" % [mutator_name, boon_desc]
		else:
			icon_node.position = BOON_ICON_POS
			icon_node.size = BOON_ICON_SIZE
			icon_node.custom_minimum_size = BOON_ICON_SIZE
			label.position = Vector2(BOON_LABEL_X, 6.0)
			icon_node.texture = null
			icon_node.visible = false
			var boon_desc := String(boon.get("desc", boon.get("description", "")))
			var choice_name := _choice_display_name(boon)
			label.text = "[b][color=#ddeeff]%d. %s[/color][/b]\n%s" % [i + 1, choice_name, boon_desc]
		label.modulate = Color(1.0, 1.0, 1.0, 0.95)

	_update_boon_reveal_visuals()

func _has_mission_bonus_mutator() -> bool:
	return reward_selection_mode == ENUMS.RewardMode.MISSION and not current_player_mutator.is_empty()

func _get_boon_title_text() -> String:
	if _has_mission_bonus_mutator():
		if mission_reward_stage == 0:
			return "%s (1/2)" % boon_title_text
		return "Claim Mission Mutator (2/2)"
	return boon_title_text

func _get_boon_subtitle_text() -> String:
	var is_arcana := reward_selection_mode == ENUMS.RewardMode.ARCANA
	var is_boss := reward_selection_mode == ENUMS.RewardMode.BOSS
	var reveal_complete := boon_confirm_lock_time <= 0.0
	if is_arcana and pending_initial_boon:
		if reveal_complete:
			return "Choose one - it will grow stronger every time you claim it"
		return "Arcana are rare powers that permanently shape your run"
	if is_boss:
		if reveal_complete:
			return "Claim your victory reward - choose one ascended power"
		return "Preparing your boss reward..."
	if reward_selection_mode == ENUMS.RewardMode.MISSION:
		if mission_reward_stage == 0:
			if reveal_complete:
				return "Step 1 of 2: Select a card to claim your reward"
			return "Step 1 of 2: Preparing your choices..."
		if reveal_complete:
			return "Step 2 of 2: claim your bonus mission mutator"
		return "Permanent upgrade locked in. Bonus mutator ready to claim"
	if reveal_complete:
		if is_arcana:
			return "Add another stack and push your stats further"
		return "Select a card to claim your reward"
	return "Preparing your choices..."

func _roll_boon_choices(choice_count: int, power_registry: Node, player: Node2D, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var pool: Array[Dictionary] = power_registry.get_upgrade_pool(player)
	var available: Array[Dictionary] = []
	for entry in pool:
		if _is_upgrade_blocked_for_character(String(entry.get("id", ""))):
			continue
		var limit := int(entry.get("stack_limit", 0))
		if limit > 0 and is_instance_valid(player):
			var current := int(player.get_upgrade_stack_count(String(entry["id"])))
			if current >= limit:
				continue
		available.append(entry)
	var picks: Array[Dictionary] = []
	for _i in range(mini(choice_count, available.size())):
		var index := rng.randi_range(0, available.size() - 1)
		picks.append(available[index])
		available.remove_at(index)
	return picks

func _roll_arcana_choices(choice_count: int, power_registry: Node, player: Node2D, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var pool: Array[Dictionary] = power_registry.get_trial_power_pool(player)
	var available: Array[Dictionary] = []
	for entry in pool:
		var limit := int(entry.get("stack_limit", 0))
		if limit > 0 and is_instance_valid(player):
			var current := int(player.get_trial_power_stack_count(String(entry["id"])))
			if current >= limit:
				continue
		available.append(entry)
	var picks: Array[Dictionary] = []
	for _i in range(mini(choice_count, available.size())):
		var index := rng.randi_range(0, available.size() - 1)
		picks.append(available[index])
		available.remove_at(index)
	return picks

func _roll_objective_mutator_choice(player_mutator: Dictionary) -> Array[Dictionary]:
	if player_mutator.is_empty():
		return []
	var mutator_name := String(player_mutator.get("name", "Unknown Mutator"))
	var mutator_color: Color = player_mutator.get("theme_color", Color(0.76, 0.76, 0.76, 1.0)) as Color
	var mutator_desc := _build_objective_mutator_desc(player_mutator)
	var mutator_choice: Dictionary = {
		"id": mutator_name.to_lower().replace(" ", "_"),
		"name": mutator_name,
		"desc": mutator_desc,
		"is_mutator": true,
		"color": mutator_color,
		"full_data": player_mutator
	}
	return [mutator_choice]

func _build_objective_mutator_desc(mutator_data: Dictionary) -> String:
	var mutator_id := ENCOUNTER_CONTRACTS.mutator_id(mutator_data)
	if mutator_id == "combo_relay":
		return "Kill chain: [color=#FFE4A6]+5% damage[/color] [color=#FFE4A6]+5% movement speed[/color] per kill (max 4). Reset after [color=#FFE4A6]2.8s[/color]."
	var flavor := String(mutator_data.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_BANNER_SUFFIX, ""))
	if not flavor.is_empty():
		return flavor
	return ""

func _roll_objective_choices(choice_count: int, power_registry: Node, player: Node2D, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var prioritized_pool: Array[Dictionary] = power_registry.get_objective_upgrade_pool(player)
	var regular_pool: Array[Dictionary] = power_registry.get_upgrade_pool(player)
	var available_priority: Array[Dictionary] = []
	var available_regular: Array[Dictionary] = []
	for entry in prioritized_pool:
		if _is_upgrade_blocked_for_character(String(entry.get("id", ""))):
			continue
		var limit := int(entry.get("stack_limit", 0))
		if limit > 0 and is_instance_valid(player):
			var current := int(player.get_upgrade_stack_count(String(entry["id"])))
			if current >= limit:
				continue
		available_priority.append(entry)
	for entry in regular_pool:
		if _is_upgrade_blocked_for_character(String(entry.get("id", ""))):
			continue
		var limit := int(entry.get("stack_limit", 0))
		if limit > 0 and is_instance_valid(player):
			var current := int(player.get_upgrade_stack_count(String(entry["id"])))
			if current >= limit:
				continue
		available_regular.append(entry)
	var picks: Array[Dictionary] = []
	if not available_priority.is_empty():
		var featured_index := rng.randi_range(0, available_priority.size() - 1)
		var featured := available_priority[featured_index]
		picks.append(featured)
		for i in range(available_regular.size() - 1, -1, -1):
			if String(available_regular[i].get("id", "")) == String(featured.get("id", "")):
				available_regular.remove_at(i)
	for _i in range(mini(choice_count - picks.size(), available_regular.size())):
		var index := rng.randi_range(0, available_regular.size() - 1)
		picks.append(available_regular[index])
		available_regular.remove_at(index)
	return picks

func _roll_boss_reward_choices(choice_count: int, power_registry: Node, player: Node2D, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var pool: Array[Dictionary] = power_registry.get_boss_reward_pool(player)
	var available: Array[Dictionary] = []
	for entry in pool:
		if _is_upgrade_blocked_for_character(String(entry.get("id", ""))):
			continue
		var limit := int(entry.get("stack_limit", 0))
		if limit > 0 and is_instance_valid(player):
			var current := int(player.get_upgrade_stack_count(String(entry["id"])))
			if current >= limit:
				continue
		available.append(entry)
	var picks: Array[Dictionary] = []
	for _i in range(mini(choice_count, available.size())):
		var index := rng.randi_range(0, available.size() - 1)
		picks.append(available[index])
		available.remove_at(index)
	return picks

func _get_stack_count_for_choice(choice: Dictionary, player: Node2D) -> int:
	if not is_instance_valid(player):
		return 0
	var id := String(choice.get("id", ""))
	if reward_selection_mode == ENUMS.RewardMode.ARCANA:
		return int(player.get_trial_power_stack_count(id))
	return int(player.get_upgrade_stack_count(id))

func _choice_display_name(choice: Dictionary) -> String:
	var raw_name := String(choice.get("name", "")).strip_edges()
	if not raw_name.is_empty() and raw_name.to_lower() != "unknown":
		return raw_name
	var id := String(choice.get("id", "")).strip_edges().to_lower()
	if id.is_empty():
		return "Power"
	match id:
		"hunters_snare":
			return "Hunter's Snare"
		"wraithstep":
			return "Wraithstep"
		_:
			var words := id.split("_", false)
			var result := ""
			for i in range(words.size()):
				if i > 0:
					result += " "
				result += String(words[i]).capitalize()
			return result.strip_edges()

func _build_offer_payload(choice: Dictionary) -> Dictionary:
	var id := String(choice.get("id", "")).strip_edges()
	var choice_name := _choice_display_name(choice)
	var payload := {
		"choice_id": id,
		"choice_name": choice_name,
	}
	if bool(choice.get("is_mutator", false)):
		payload["is_mutator"] = true
		var mutator_data := choice.get("full_data", {}) as Dictionary
		payload["mutator_name"] = String(mutator_data.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME, choice_name))
	return payload

func _emit_reward_offers_presented() -> void:
	if boon_choices.is_empty():
		return
	var offers: Array[Dictionary] = []
	for choice_variant in boon_choices:
		var choice := choice_variant as Dictionary
		offers.append(_build_offer_payload(choice))
	emit_signal("reward_offers_presented", offers, reward_selection_mode, pending_initial_boon, mission_reward_stage)

func _format_stack_progress_icons(stack_count: int, stack_limit: int) -> String:
	if stack_limit <= 0:
		return ""
	var clamped := clampi(stack_count, 0, stack_limit)
	var icons := ""
	for _i in range(clamped):
		icons += "◆"
	for _i in range(stack_limit - clamped):
		icons += "◇"
	return icons

func _update_boon_hover() -> void:
	if boon_layer == null:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var hovered := -1
	for i in range(boon_choices.size()):
		if i >= boon_card_rects.size():
			continue
		if boon_card_rects[i].has_point(mouse_pos):
			hovered = i
			break

	if hovered == boon_hovered_index:
		return
	boon_hovered_index = hovered
	_apply_boon_card_styles(boon_hovered_index)

func _apply_boon_card_styles(hovered_index: int) -> void:
	for i in range(boon_card_panels.size()):
		var panel := boon_card_panels[i]
		var style := StyleBoxFlat.new()
		var t := float(i) / maxf(1.0, float(maxi(1, boon_choice_count - 1)))
		var base_color := Color(0.08, 0.17, 0.28, 0.96).lerp(Color(0.12, 0.2, 0.34, 0.96), t)
		var border_color := Color(0.57, 0.71, 0.88, 0.86)
		if reward_selection_mode == ENUMS.RewardMode.ARCANA:
			base_color = Color(0.16, 0.11, 0.08, 0.96).lerp(Color(0.22, 0.14, 0.09, 0.96), t)
			border_color = Color(1.0, 0.72, 0.4, 0.84)
		elif reward_selection_mode == ENUMS.RewardMode.MISSION:
			var mission_tint := Color(0.98, 0.78, 0.34, 1.0)
			if i < boon_choices.size():
				mission_tint = boon_choices[i].get("color", mission_tint) as Color
			base_color = Color(0.12, 0.09, 0.06, 0.96).lerp(Color(mission_tint.r * 0.26, mission_tint.g * 0.24, mission_tint.b * 0.2, 0.97), 0.5 + t * 0.2)
			border_color = Color(mission_tint.r, mission_tint.g, mission_tint.b, 0.9)
		elif reward_selection_mode == ENUMS.RewardMode.BOSS:
			base_color = Color(0.12, 0.06, 0.16, 0.96).lerp(Color(0.16, 0.08, 0.22, 0.96), t)
			border_color = Color(0.95, 0.65, 1.0, 0.88)
		if i == hovered_index and boon_confirm_lock_time <= 0.0:
			if reward_selection_mode == ENUMS.RewardMode.ARCANA:
				style.bg_color = Color(0.33, 0.2, 0.12, 0.97)
				style.border_color = Color(1.0, 0.9, 0.72, 1.0)
			elif reward_selection_mode == ENUMS.RewardMode.MISSION:
				var hover_tint := Color(1.0, 0.9, 0.72, 1.0)
				if i < boon_choices.size():
					hover_tint = boon_choices[i].get("color", hover_tint) as Color
				style.bg_color = Color(hover_tint.r * 0.42, hover_tint.g * 0.34, hover_tint.b * 0.22, 0.98)
				style.border_color = Color(hover_tint.r, hover_tint.g, hover_tint.b, 1.0)
			elif reward_selection_mode == ENUMS.RewardMode.BOSS:
				style.bg_color = Color(0.3, 0.14, 0.38, 0.97)
				style.border_color = Color(1.0, 0.9, 1.0, 1.0)
			else:
				style.bg_color = Color(0.22, 0.32, 0.46, 0.96)
				style.border_color = Color(0.98, 0.99, 1.0, 1.0)
			style.border_width_left = 4
			style.border_width_top = 4
			style.border_width_right = 4
			style.border_width_bottom = 4
		else:
			style.bg_color = base_color
			style.border_color = border_color
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0.0, 4.0)
		panel.add_theme_stylebox_override("panel", style)

func _update_boon_reveal_visuals() -> void:
	var reveal_t := clampf(boon_reveal_time / maxf(0.001, boon_reveal_duration), 0.0, 1.0)
	for i in range(boon_card_panels.size()):
		if i >= boon_choices.size():
			continue
		var panel := boon_card_panels[i]
		var label := boon_card_labels[i]
		var stack_label := boon_card_stack_labels[i]
		var delay := float(i) * 0.06
		var local_t := clampf((reveal_t - delay) / 0.6, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - local_t, 3.0)
		var base_pos := panel.position
		if i < boon_card_rects.size():
			base_pos = boon_card_rects[i].position
		panel.position = base_pos + Vector2(0.0, (1.0 - eased) * 18.0)
		panel.modulate = Color(1.0, 1.0, 1.0, eased)
		panel.scale = Vector2(0.94 + 0.06 * eased, 0.94 + 0.06 * eased)
		label.modulate.a = eased
		stack_label.modulate.a = eased

	if boon_subtitle_label != null:
		boon_subtitle_label.text = _get_boon_subtitle_text()

func _get_mutator_icon_texture(icon_shape_id: String) -> Texture2D:
	match icon_shape_id:
		"blood_rush":
			return MUTATOR_ICON_BLOOD_RUSH
		"flashpoint":
			return MUTATOR_ICON_FLASHPOINT
		"siegebreak":
			return MUTATOR_ICON_SIEGEBREAK
		"iron_volley":
			return MUTATOR_ICON_IRON_VOLLEY
		"killbox":
			return _get_killbox_icon_texture()
		"fortified":
			return _get_fortified_icon_texture()
		"hunters_focus":
			return _get_hunters_focus_icon_texture()
		"combo_relay":
			return _get_combo_relay_icon_texture()
		"breach_momentum":
			return _get_combo_relay_icon_texture()
		"convergence":
			return _get_convergence_icon_texture()
		"conflagration":
			return _get_conflagration_icon_texture()
		"tether_web":
			return _get_tether_web_icon_texture()
		_:
			return null

func _get_killbox_icon_texture() -> Texture2D:
	if _mutator_icon_killbox != null:
		return _mutator_icon_killbox
	var icon_resource := load(MUTATOR_ICON_KILLBOX_PATH)
	if icon_resource is Texture2D:
		_mutator_icon_killbox = icon_resource as Texture2D
		return _mutator_icon_killbox
	return MUTATOR_ICON_SIEGEBREAK

func _get_fortified_icon_texture() -> Texture2D:
	if _mutator_icon_fortified != null:
		return _mutator_icon_fortified
	var icon_resource := load(MUTATOR_ICON_FORTIFIED_PATH)
	if icon_resource is Texture2D:
		_mutator_icon_fortified = icon_resource as Texture2D
		return _mutator_icon_fortified
	return MUTATOR_ICON_SIEGEBREAK

func _get_hunters_focus_icon_texture() -> Texture2D:
	if _mutator_icon_hunters_focus != null:
		return _mutator_icon_hunters_focus
	var icon_resource := load(MUTATOR_ICON_HUNTERS_FOCUS_PATH)
	if icon_resource is Texture2D:
		_mutator_icon_hunters_focus = icon_resource as Texture2D
		return _mutator_icon_hunters_focus
	return MUTATOR_ICON_IRON_VOLLEY

func _get_combo_relay_icon_texture() -> Texture2D:
	if _mutator_icon_combo_relay != null:
		return _mutator_icon_combo_relay
	var icon_resource := load(MUTATOR_ICON_COMBO_RELAY_PATH)
	if icon_resource is Texture2D:
		_mutator_icon_combo_relay = icon_resource as Texture2D
		return _mutator_icon_combo_relay
	return _get_hunters_focus_icon_texture()

func _get_convergence_icon_texture() -> Texture2D:
	if _mutator_icon_convergence != null:
		return _mutator_icon_convergence
	var icon_resource := load(MUTATOR_ICON_CONVERGENCE_PATH)
	if icon_resource is Texture2D:
		_mutator_icon_convergence = icon_resource as Texture2D
		return _mutator_icon_convergence
	return MUTATOR_ICON_FLASHPOINT

func _get_conflagration_icon_texture() -> Texture2D:
	if _mutator_icon_conflagration != null:
		return _mutator_icon_conflagration
	var icon_resource := load(MUTATOR_ICON_CONFLAGRATION_PATH)
	if icon_resource is Texture2D:
		_mutator_icon_conflagration = icon_resource as Texture2D
		return _mutator_icon_conflagration
	return MUTATOR_ICON_SIEGEBREAK

func _get_tether_web_icon_texture() -> Texture2D:
	if _mutator_icon_tether_web != null:
		return _mutator_icon_tether_web
	var icon_resource := load(MUTATOR_ICON_TETHER_WEB_PATH)
	if icon_resource is Texture2D:
		_mutator_icon_tether_web = icon_resource as Texture2D
		return _mutator_icon_tether_web
	return _get_convergence_icon_texture()
