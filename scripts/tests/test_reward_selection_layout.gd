extends "res://scripts/tests/test_blast_feedback.gd"

const REWARD_UI := preload("res://scripts/reward_selection_ui.gd")
const REGISTRY := preload("res://scripts/power_registry.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")

func _run() -> void:
	var retirement := AUDIO_RETIREMENT.new()
	node_added.connect(retirement.observe_node)
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var ui := REWARD_UI.new()
	viewport.add_child(ui)
	ui._create_ui()
	var registry := REGISTRY.new()
	root.add_child(registry)
	for character_id in CHARACTER.CHARACTER_DEFINITIONS:
		_make_world(0)
		player.apply_character_package(CHARACTER.get_character(character_id))
		for id in ["blast_drive", "razor_orbit", "returning_crescent"]:
			player.apply_trial_power(id)
			player.apply_trial_power(id)
		await _check_offers(viewport, ui, registry, ["blast_drive", "razor_orbit", "returning_crescent"], ENUMS.RewardMode.ARCANA, character_id)
		for id in ["blast_drive", "razor_orbit", "returning_crescent"]:
			player.apply_trial_power(id)
		ui.configure_catalyst_payload({"arcana_capacity_add": 1.0})
		await _check_offers(viewport, ui, registry, ["blast_drive", "razor_orbit", "returning_crescent"], ENUMS.RewardMode.ARCANA, character_id)
		player.apply_upgrade("sovereigns_double")
		player.apply_upgrade("ruinous_impact")
		await _check_offers(viewport, ui, registry, ["sovereigns_double", "ruinous_impact", "execution_edge"], ENUMS.RewardMode.BOSS, character_id)
		_free_world()
	await _check_native_clicks(viewport, ui, registry)
	ui.close_selection()
	viewport.free()
	registry.free()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Native reward click playback retires before fixture exit")
	print("[OK] Reward selection layout: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_offers(viewport: SubViewport, ui: Node, registry: Node, ids: Array, mode: int, character_id: String) -> void:
	for count in [2, 3, 4, 3]:
		ui.initialize(count, 0.0)
		var choices := ids.slice(0, count)
		if count == 4:
			choices.append("razor_wind" if mode == ENUMS.RewardMode.ARCANA else "null_corridor")
		await _check_layout(viewport, ui, registry, choices, mode, character_id)

func _check_layout(viewport: SubViewport, ui: Node, registry: Node, ids: Array, mode: int, character_id: String) -> void:
	ui.open_selection("Reward", false, mode, registry, player, RandomNumberGenerator.new(), {}, registry.get_boss_epitaph("warden", character_id) if mode == ENUMS.RewardMode.BOSS else "", character_id)
	ui.boon_choices.clear()
	for id in ids:
		var trial: bool = REGISTRY.TRIAL_POWER_POOL_IDS.has(id)
		ui.boon_choices.append({"id": id, "name": registry.get_power_display_name(id), "desc": player.get_trial_power_card_desc(id) if trial else player.get_upgrade_card_desc(id), "stack_limit": registry.get_power_stack_limit(id), "type": REGISTRY.POWER_TYPE_TRIAL if trial else REGISTRY.POWER_TYPE_UPGRADE})
	ui._refresh_boon_ui(player)
	ui.boon_confirm_lock_time = 0.0
	ui.boon_reveal_time = 2.0
	ui._set_skip_button_visible(true)
	for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(960, 720)]:
		viewport.size = size
		ui._on_viewport_size_changed()
		await process_frame
		await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(size))
		for i in range(ids.size()):
			var card: Control = ui.boon_card_panels[i]
			var label: RichTextLabel = ui.boon_card_labels[i]
			var context := "%s %s %s" % [character_id, ids[i], size]
			_check(label.get_content_height() <= label.size.y, "Complete description at " + context)
			_check(bounds.encloses(card.get_global_rect()), "Visible card fits at " + context)
			_check(card.get_global_rect().is_equal_approx(ui.boon_card_rects[i]), "Settled visual and clickable rectangle agree at " + context)
			_check(not card.get_global_rect().intersects(ui.skip_button.get_global_rect()), "Action clears card at " + context)
		_check(bounds.encloses(ui.skip_button.get_global_rect()), "Action remains inside viewport")
		if ui.epitaph_label.visible:
			_check(not ui.epitaph_label.get_global_rect().intersects(ui.skip_button.get_global_rect()), "Boss epitaph clears action")
			_check(ui.epitaph_label.get_content_height() <= ui.epitaph_label.size.y, "Complete boss epitaph remains readable")
func _native_button(viewport: SubViewport, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	viewport.push_input(event, true)

func _native_motion(viewport: SubViewport, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)

func _check_native_clicks(viewport: SubViewport, ui: Node, registry: Node) -> void:
	_make_world(0)
	for count in [2, 3, 4]:
		ui.initialize(count, 0.0)
		for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			viewport.size = size
			ui._on_viewport_size_changed()
			ui.configure_catalyst_payload({"reward_rerolls_per_encounter_add": 1.0})
			ui.open_selection("Boon", false, ENUMS.RewardMode.BOON, registry, player, RandomNumberGenerator.new())
			ui.boon_confirm_lock_time = 0.0
			ui.boon_reveal_time = 2.0
			ui.process_input(0.016)
			await process_frame
			var point: Vector2 = ui.boon_card_rects[count - 1].get_center()
			_native_motion(viewport, point)
			_native_button(viewport, point, true)
			ui.process_input(0.016)
			_check(ui.boon_hovered_index == count - 1 and not ui.is_active(), "Native click selects last visible card: %d at %s" % [count, size])
			_native_button(viewport, point, false)
			await process_frame
			ui.open_selection("Boon", false, ENUMS.RewardMode.BOON, registry, player, RandomNumberGenerator.new())
			ui.boon_confirm_lock_time = 0.0
			ui.process_input(0.016)
			await process_frame
			_check(ui.reroll_button.visible, "Existing reroll is available")
			point = ui.reroll_button.get_global_rect().get_center()
			_native_motion(viewport, point)
			_native_button(viewport, point, true)
			_native_button(viewport, point, false)
			_check(ui._reward_rerolls_remaining == 0 and ui.is_active(), "Native reroll button remains usable")
			await process_frame
			ui.boon_confirm_lock_time = 0.0
			ui.process_input(0.016)
			point = ui.skip_button.get_global_rect().get_center()
			_native_motion(viewport, point)
			_native_button(viewport, point, true)
			_native_button(viewport, point, false)
			_check(not ui.is_active(), "Native Skip button remains usable")
			await process_frame
	_free_world()
