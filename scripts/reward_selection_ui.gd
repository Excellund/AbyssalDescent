extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")

signal reward_selected(choice: Dictionary, mode: int, is_initial: bool)

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

var boon_layer: CanvasLayer
var boon_title_label: Label
var boon_subtitle_label: Label
var boon_card_panels: Array[Panel] = []
var boon_card_labels: Array[RichTextLabel] = []
var boon_card_stack_labels: Array[Label] = []
var boon_card_rects: Array[Rect2] = []
var boon_backdrop: ColorRect

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
	boon_choices.clear()
	if boon_layer != null:
		boon_layer.visible = false

func open_selection(title: String, is_initial: bool, mode: int, power_registry: Node, player: Node2D, rng: RandomNumberGenerator) -> void:
	boon_selection_active = true
	pending_initial_boon = is_initial
	boon_title_text = title
	reward_selection_mode = mode
	_apply_mode_theme()
	if reward_selection_mode == ENUMS.RewardMode.ARCANA:
		boon_choices = _roll_arcana_choices(boon_choice_count, power_registry, player, rng)
	else:
		boon_choices = _roll_boon_choices(boon_choice_count, power_registry, player, rng)
	boon_confirm_lock_time = boon_reveal_duration + 0.08
	boon_reveal_time = 0.0
	boon_hovered_index = -1
	_apply_boon_card_styles(-1)
	_refresh_boon_ui(player)

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
			var mode := reward_selection_mode
			var initial := pending_initial_boon
			boon_selection_active = false
			boon_choices.clear()
			if boon_layer != null:
				boon_layer.visible = false
			reward_selection_mode = ENUMS.RewardMode.BOON
			pending_initial_boon = false
			emit_signal("reward_selected", picked, mode, initial)
			return

func _create_ui() -> void:
	boon_layer = CanvasLayer.new()
	boon_layer.layer = 130
	add_child(boon_layer)

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
	boon_card_rects.clear()
	for i in range(boon_choice_count):
		var panel := Panel.new()
		panel.position = Vector2(220.0, 164.0 + i * 138.0)
		panel.custom_minimum_size = Vector2(1460.0, 118.0)
		boon_layer.add_child(panel)

		var option_label := RichTextLabel.new()
		option_label.position = Vector2(14.0, 6.0)
		option_label.custom_minimum_size = Vector2(1200.0, 106.0)
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
		boon_card_rects.append(Rect2(panel.position, panel.custom_minimum_size))

	boon_layer.visible = false

func _apply_mode_theme() -> void:
	if boon_backdrop == null or boon_title_label == null:
		return
	if reward_selection_mode == ENUMS.RewardMode.ARCANA:
		boon_backdrop.color = Color(0.05, 0.02, 0.01, 0.72)
		boon_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.76, 1.0))
		boon_title_label.add_theme_color_override("font_shadow_color", Color(0.08, 0.03, 0.01, 0.96))
		if boon_subtitle_label != null:
			boon_subtitle_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.55, 0.65))
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
	boon_title_label.text = boon_title_text
	if boon_subtitle_label != null:
		var is_arcana := reward_selection_mode == ENUMS.RewardMode.ARCANA
		if is_arcana and pending_initial_boon:
			boon_subtitle_label.text = "Arcana are rare powers that permanently shape your run"
		else:
			boon_subtitle_label.text = "Revealing your options\u2026"

	for i in range(boon_card_labels.size()):
		var panel := boon_card_panels[i]
		var label := boon_card_labels[i]
		var stack_label := boon_card_stack_labels[i]
		if i >= boon_choices.size():
			label.text = ""
			stack_label.text = ""
			stack_label.visible = false
			panel.visible = false
			continue
		panel.visible = true
		var boon := boon_choices[i]
		var stack_limit := int(boon.get("stack_limit", 0))
		var stack_count := _get_stack_count_for_choice(boon, player)
		var icon_line := _format_stack_progress_icons(stack_count, stack_limit)
		if icon_line.is_empty():
			stack_label.text = ""
			stack_label.visible = false
		else:
			stack_label.text = icon_line
			stack_label.visible = true
		label.text = "[b][color=#ddeeff]%d. %s[/color][/b]\n%s" % [i + 1, boon["name"], boon["desc"]]
		label.modulate = Color(1.0, 1.0, 1.0, 0.95)

	_update_boon_reveal_visuals()

func _roll_boon_choices(choice_count: int, power_registry: Node, player: Node2D, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var pool: Array[Dictionary] = power_registry.call("get_upgrade_pool", player)
	var available: Array[Dictionary] = []
	for entry in pool:
		var limit := int(entry.get("stack_limit", 0))
		if limit > 0 and is_instance_valid(player) and player.has_method("get_upgrade_stack_count"):
			var current := int(player.call("get_upgrade_stack_count", String(entry["id"])))
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
	var pool: Array[Dictionary] = power_registry.call("get_trial_power_pool", player)
	var available: Array[Dictionary] = []
	for entry in pool:
		var limit := int(entry.get("stack_limit", 0))
		if limit > 0 and is_instance_valid(player) and player.has_method("get_trial_power_stack_count"):
			var current := int(player.call("get_trial_power_stack_count", String(entry["id"])))
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
		if player.has_method("get_trial_power_stack_count"):
			return int(player.call("get_trial_power_stack_count", id))
		return 0
	if player.has_method("get_upgrade_stack_count"):
		return int(player.call("get_upgrade_stack_count", id))
	return 0

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
		if i == hovered_index and boon_confirm_lock_time <= 0.0:
			if reward_selection_mode == ENUMS.RewardMode.ARCANA:
				style.bg_color = Color(0.33, 0.2, 0.12, 0.97)
				style.border_color = Color(1.0, 0.9, 0.72, 1.0)
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
		var base_pos := Vector2(220.0, 164.0 + i * 138.0)
		panel.position = base_pos + Vector2(0.0, (1.0 - eased) * 18.0)
		panel.modulate = Color(1.0, 1.0, 1.0, eased)
		panel.scale = Vector2(0.94 + 0.06 * eased, 0.94 + 0.06 * eased)
		label.modulate.a = eased
		stack_label.modulate.a = eased

	if boon_subtitle_label != null:
		var is_arcana := reward_selection_mode == ENUMS.RewardMode.ARCANA
		if boon_confirm_lock_time <= 0.0:
			if is_arcana and pending_initial_boon:
				boon_subtitle_label.text = "Choose one — it will grow stronger every time you claim it"
			elif is_arcana:
				boon_subtitle_label.text = "Add another stack and push your stats further"
			else:
				boon_subtitle_label.text = "Select a card to claim your reward"
		else:
			if is_arcana and pending_initial_boon:
				boon_subtitle_label.text = "Arcana are rare powers that permanently shape your run"
			else:
				boon_subtitle_label.text = "Preparing your choices\u2026"
