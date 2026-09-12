extends "res://scripts/tests/test_relic_recovery.gd"
## Native Main reward/build flow. Offer order and Rest health are staged for UI QA.
const OFFER_IDS := ["farshot", "heavy_blow", "heartstone", "fleet_foot"]
var frames: Array[Dictionary] = []
var frame_folder := ""

func _run() -> void:
	if not _is_isolated() or DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.content_scale_size = Vector2i(2560, 1440)
	frame_folder = ProjectSettings.globalize_path("res://farshot_frames")
	DirAccess.make_dir_recursive_absolute(frame_folder)
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = window_size
		await process_frame
		_setup_recovery_world()
		if not is_instance_valid(world.reward_selection_ui) or not is_instance_valid(world.build_detail_panel):
			push_error("Native Farshot fixture could not construct the real reward/build controllers")
			quit(1)
			return
		ProjectSettings.set_setting("application/config/version", "dev-farshot-native-ui")
		for owned_level in 3:
			if owned_level > 0:
				await _capture_rest(owned_level)
			for choice_count in [3, 4]:
				await _capture_offer(owned_level, choice_count)
			await _confirm_farshot(owned_level)
			await _capture_build(owned_level + 1)
		var capped_pool: Array[Dictionary] = world.reward_selection_ui._roll_boon_choices(99, world.power_registry_instance, world.player, world.rng)
		check(not capped_pool.any(func(choice: Dictionary) -> bool: return String(choice.id) == "farshot"), "Level three leaves the ordinary eligible pool")
		world._choose_door(CONTRACTS.rest_door_option())
		check(not world.reward_selection_ui.boon_choices.any(func(choice: Dictionary) -> bool: return String(choice.id) == "farshot"), "Level three leaves the real Rest eligible pool")
		if window_size == Vector2i(960, 540):
			await _capture_dense_offers()
		await _cleanup_recovery_world()
		node_added.disconnect(audio_retirement.observe_node)
	var manifest := {"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name(), "scope": "Actual Main; production 2560x1440 canvas at 960/1280/1920 physical widths. Three/four ordinary offers, all Farshot picks, eligible real Rest offers, expanded owned Build rules, keyboard inspection and exactly-one ordinary grants. Two dense existing Arcana/Boss four-card layouts at960x540 verify shared layout. Offer order, dense prerequisite builds and Rest health are staged; combat is idle. UI evidence, not combat or balance acceptance."}
	FileAccess.open(frame_folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[OK] Farshot native UI: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture_dense_offers() -> void:
	var ui: Node = world.reward_selection_ui
	ui.close_selection()
	var arcana_ids := ["aegis_field", "blast_drive", "razor_orbit", "returning_crescent"]
	for id in arcana_ids:
		world.player.apply_trial_power(id)
		if id != "aegis_field":
			world.player.apply_trial_power(id)
	await _capture_dense_page(arcana_ids, ENUMS.RewardMode.ARCANA, "dense_arcana_four_960")
	ui.close_selection()
	var boss_ids := ["wardens_verdict", "lacuna_echo", "pillar_convergence", "shatterwake"]
	for id in boss_ids:
		world.player.apply_upgrade(id)
	await _capture_dense_page(boss_ids, ENUMS.RewardMode.BOSS, "dense_boss_four_960")

func _capture_dense_page(ids: Array, mode: int, context: String) -> void:
	var ui: Node = world.reward_selection_ui
	ui.initialize(4, 0.0)
	var epitaph := String(world.power_registry_instance.get_boss_epitaph("warden", "bastion")) if mode == ENUMS.RewardMode.BOSS else ""
	world._open_networked_reward_selection("Choose Boss Reward" if mode == ENUMS.RewardMode.BOSS else "Choose Arcana", mode, {}, epitaph)
	var pool: Array[Dictionary] = world.power_registry_instance.get_boss_reward_pool(world.player) if mode == ENUMS.RewardMode.BOSS else world.power_registry_instance.get_trial_power_pool(world.player)
	var offers: Array[Dictionary] = []
	for id in ids:
		for choice in pool:
			if String(choice.id) == id:
				offers.append(choice.duplicate(true))
	check(offers.size() == 4, "Dense native regression uses four real catalogue descriptions")
	ui.boon_choices = offers
	ui._refresh_boon_ui(world.player)
	ui._on_viewport_size_changed()
	await _settle_ui(ui)
	var descriptions: Array[String] = []
	for index in 4:
		_check_card(ui, index, context)
		descriptions.append(ui.boon_card_labels[index].get_parsed_text())
		check(String(offers[index].desc) == ui.boon_card_labels[index].text, "Dense native card retains its complete authored explanation and figures")
	if mode == ENUMS.RewardMode.BOSS:
		check(ui.epitaph_label.get_content_height() <= ui.epitaph_label.size.y + 1, "Dense Boss epitaph fits completely")
		check(_physical_rect(ui.epitaph_label).intersection(_physical_rect(ui.build_button)).size.y <= 0.01, "Dense Boss epitaph clears its visible build action within transform precision")
	_capture(context, {"choice_ids": ids, "card_copy": descriptions, "body_pixels": _font_pixels(ui.boon_card_labels[0]), "line_separation": ui.boon_card_labels[0].get_theme_constant("line_separation"), "epitaph_rect": _physical_rect(ui.epitaph_label), "build_button_rect": _physical_rect(ui.build_button), "epitaph_button_intersection_height": _physical_rect(ui.epitaph_label).intersection(_physical_rect(ui.build_button)).size.y})

func _capture_offer(owned_level: int, count: int) -> void:
	var ui: Node = world.reward_selection_ui
	ui.close_selection()
	ui.initialize(count, 0.0)
	world._open_networked_reward_selection("Choose Boon Reward", ENUMS.RewardMode.BOON)
	var pool: Array[Dictionary] = world.power_registry_instance.get_upgrade_pool(world.player)
	var offers: Array[Dictionary] = []
	for id in OFFER_IDS.slice(0, count):
		for choice in pool:
			if String(choice.id) == id:
				offers.append(choice.duplicate(true))
	check(offers.size() == count and String(offers[0].id) == "farshot", "Native layout uses actual eligible catalogue choices")
	ui.boon_choices = offers
	ui._refresh_boon_ui(world.player)
	ui._on_viewport_size_changed()
	await _settle_ui(ui)
	ui.boon_card_panels[0].grab_focus()
	if count == 4:
		await _key(KEY_RIGHT)
		check(ui.boon_hovered_index == 1, "Four-offer Right moves to the adjacent card")
		await _key(KEY_DOWN)
		check(ui.boon_hovered_index == 3, "Four-offer Down moves to the card below")
		await _key(KEY_LEFT)
		await _key(KEY_UP)
		check(ui.boon_hovered_index == 0, "Four-offer spatial navigation returns to Farshot")
	var saved: Array[Dictionary] = ui.boon_choices.duplicate(true)
	var focus_before := _focus_probe(ui)
	await _key(KEY_TAB)
	check(world.build_detail_panel.is_open() and ui._inspection_active, "Native Tab opens inspection from the offered card")
	check(world.player.get_upgrade_stack_count("farshot") == owned_level, "Inspection does not grant an offered Farshot")
	await _key(KEY_ESCAPE)
	var focus_on_return := _focus_probe(ui)
	await _settle_ui(ui)
	check(not world.build_detail_panel.is_open() and ui.is_active() and ui.boon_choices == saved, "Escape returns to the identical unclaimed offer")
	# Hidden Windows surfaces report unstable offscreen OS mouse coordinates.
	# Assert the returned keyboard selection, not a later mouse-hover poll.
	check(int(focus_on_return.hover) == 0, "Inspection returns to the selected Farshot card")
	check(root.gui_get_focus_owner() == ui.boon_card_panels[0], "Inspection restores native keyboard focus to the offered Farshot")
	await _settle_frames()
	var context := "offer_level_%d_%d_choices_%d" % [owned_level + 1, count, root.size.x]
	for index in count:
		_check_card(ui, index, context)
	_check_farshot_copy(ui.boon_card_labels[0], owned_level + 1, context)
	check(ui.boon_card_labels[0].text == String(offers[0].desc), "Native card preserves authored catalogue BBCode")
	check(ui.boon_card_stack_labels[0].visible, "Farshot keeps its separate level diamonds")
	_capture(context, {"owned_level": owned_level, "offered_level": owned_level + 1, "choice_count": count, "body_pixels": _font_pixels(ui.boon_card_labels[0]), "card_copy": ui.boon_card_labels[0].get_parsed_text(), "focus_before": focus_before, "focus_on_return": focus_on_return, "focus_settled": _focus_probe(ui)})

func _capture_rest(owned_level: int) -> void:
	world.player.health_state.set_health(60)
	world._choose_door(CONTRACTS.rest_door_option())
	var ui: Node = world.reward_selection_ui
	check(ui.is_active() and ui.reward_selection_mode == ENUMS.RewardMode.REST, "Actual Rest door opens its owned upgrade decision")
	check(ui.boon_choices.size() == 2 and String(ui.boon_choices[1].id) == "farshot", "Actual Rest offers Recover and the only eligible owned Boon")
	await _settle_ui(ui)
	ui.boon_card_panels[1].grab_focus()
	await _settle_frames()
	var context := "rest_level_%d_%d" % [owned_level + 1, root.size.x]
	for index in ui.boon_choices.size():
		_check_card(ui, index, context)
	_check_farshot_copy(ui.boon_card_labels[1], owned_level + 1, context)
	check(not ui.skip_button.visible and not ui.reroll_button.visible, "Rest retains its one-choice action contract")
	_capture(context, {"owned_level": owned_level, "offered_level": owned_level + 1, "body_pixels": _font_pixels(ui.boon_card_labels[1]), "card_copy": ui.boon_card_labels[1].get_parsed_text(), "title_rect": ui.boon_card_title_labels[1].get_rect(), "body_rect": ui.boon_card_labels[1].get_rect()})
	ui.boon_card_panels[0].grab_focus()
	await _key(KEY_ENTER)
	await _settle_ui(ui)
	check(not ui.is_active() and world.choosing_next_room, "Keyboard Recover closes actual Rest and opens doors")
	check(world.player.get_current_health() > 60 and world.player.get_upgrade_stack_count("farshot") == owned_level, "Recover heals without claiming the alternative Farshot")

func _confirm_farshot(owned_level: int) -> void:
	var ui: Node = world.reward_selection_ui
	ui.boon_card_panels[0].grab_focus()
	await _key(KEY_ENTER)
	await _settle_ui(ui)
	check(not ui.is_active() and world.choosing_next_room, "Native Farshot confirmation reaches the actual next doors")
	check(world.player.get_upgrade_stack_count("farshot") == owned_level + 1, "Native reward flow grants exactly the selected next Farshot level")
	check(world.player.farshot_bonus_damage == 10 * (owned_level + 1), "Native reward grant has the advertised conditional Damage value")
	await _key(KEY_ENTER)
	check(world.player.get_upgrade_stack_count("farshot") == owned_level + 1, "Repeated confirmation does not grant another level")

func _capture_build(level: int) -> void:
	# Finish the real room-entry fade before a static inspection capture.
	if is_instance_valid(world.hud.room_banner_tween):
		world.hud.room_banner_tween.custom_step(10.0)
	await _key(KEY_TAB)
	var build: Node = world.build_detail_panel
	check(build.is_open() and not build.opened_from_reward, "Native Tab opens the owned build from gameplay")
	await _settle_frames()
	var toggle: Button = null
	var current: RichTextLabel = null
	var rules: RichTextLabel = null
	for entry in build.boons_list_container.get_children():
		if not (entry is VBoxContainer) or entry.is_queued_for_deletion():
			continue
		var button := entry.get_child(0) as Button
		if button != null and button.text.contains("Farshot"):
			toggle = button
			current = entry.get_child(1) as RichTextLabel
			rules = (button.get_meta("build_details") as WeakRef).get_ref() as RichTextLabel
	check(toggle != null and current != null and rules != null, "Real owned Build Details includes Farshot and expandable rules")
	if toggle == null or current == null or rules == null:
		return
	toggle.grab_focus()
	await _key(KEY_ENTER)
	await _settle_frames()
	build._scroll.ensure_control_visible(rules)
	await _settle_frames()
	var context := "build_level_%d_%d" % [level, root.size.x]
	check(rules.is_visible_in_tree(), "Keyboard expands the owned Farshot rules")
	_check_farshot_copy(current, level, context)
	var plain := rules.get_parsed_text()
	for fragment in ["Foe center", "160", "current body", "when damage lands", "Fields and Echoes", "contact time", "copied-effect strength", "Effigy and Projectile origins"]:
		check(plain.contains(fragment), "Expanded native rule preserves: " + fragment)
	check(_font_pixels(current) >= 17.99 and _font_pixels(rules) >= 17.99, "Owned current value and full rules stay at least 18 physical pixels")
	check(_physical_rect(build.panel).intersection(Rect2(Vector2.ZERO, Vector2(root.size))).size.is_equal_approx(_physical_rect(build.panel).size), "Build panel fits the actual physical game image")
	check(current.get_content_height() <= current.size.y + 1 and rules.get_content_height() <= rules.size.y + 1, "Owned Farshot descriptions fit their content labels")
	# Scroll offsets are integers; canvas stretch can leave one physical pixel
	# of the label's trailing padding outside its clipping rectangle.
	check(_physical_rect(build._scroll).grow(1.01).encloses(_physical_rect(rules)), "Expanded Farshot rules are visible within one physical scroll-rounding pixel")
	check(_physical_rect(build._scroll).encloses(_physical_rect(current)) and _physical_rect(build._scroll).encloses(_physical_rect(toggle)), "Owned Farshot title and value remain visible alongside its rules")
	_capture(context, {"owned_level": level, "body_pixels": _font_pixels(current), "rules_pixels": _font_pixels(rules), "current_copy": current.get_parsed_text(), "rules_copy": plain, "scroll_rect": _physical_rect(build._scroll), "rules_rect": _physical_rect(rules)})
	await _key(KEY_TAB)
	check(not build.is_open() and world.player.get_upgrade_stack_count("farshot") == level, "Closing the owned build preserves the granted level")

func _check_card(ui: Node, index: int, context: String) -> void:
	var label: RichTextLabel = ui.boon_card_labels[index]
	var panel: Control = ui.boon_card_panels[index]
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(_physical_rect(panel)), "Reward card stays inside physical image: " + context)
	check(label.get_content_height() <= label.size.y + 1, "Reward copy fits completely: " + context)
	check(_font_pixels(label) >= 17.99, "Reward body is at least 18 physical pixels: " + context)
	check(not ui.boon_card_title_labels[index].get_rect().intersects(label.get_rect()), "Reward title and body have separate rows: " + context)
	if ui.boon_card_stack_labels[index].visible:
		check(not ui.boon_card_title_labels[index].get_rect().intersects(ui.boon_card_stack_labels[index].get_rect()), "Reward title and level diamonds stay separate: " + context)
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(_physical_rect(ui.build_button)), "Your Build stays in the physical image: " + context)

func _check_farshot_copy(label: RichTextLabel, level: int, context: String) -> void:
	var plain := label.get_parsed_text()
	check(plain.contains("+%d" % (level * 10)) and plain.contains("160") and plain.contains("from your body when damage lands."), "Farshot value, threshold, body and impact timing agree: " + context)
	check(not plain.contains("\n"), "Farshot keeps the ordinary single-stat sentence: " + context)

func _font_pixels(label: RichTextLabel) -> float:
	var transform: Transform2D = root.get_stretch_transform() * label.get_global_transform_with_canvas()
	return label.get_theme_font_size("normal_font_size") * transform.get_scale().abs().y

func _focus_probe(ui: Node) -> Dictionary:
	return {"card": ui.boon_card_panels.find(root.gui_get_focus_owner()), "hover": ui.boon_hovered_index, "keyboard": ui._keyboard_selection, "mouse": ui._layout_root.get_local_mouse_position(), "saved_mouse": ui._last_mouse_position}

func _physical_rect(control: Control) -> Rect2:
	return (root.get_stretch_transform() * control.get_global_transform_with_canvas()) * Rect2(Vector2.ZERO, control.size)

func _capture(context: String, detail: Dictionary) -> void:
	var picture := root.get_texture().get_image()
	var path := frame_folder.path_join(context + ".png")
	check(picture.get_size() == root.size, "Capture matches the physical window: " + context)
	check(picture.save_png(path) == OK, "Native Farshot frame saves: " + context)
	var frame := {"name": context, "path": path, "size": picture.get_size(), "canvas": root.content_scale_size}
	frame.merge(detail)
	frames.append(frame)

func _key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	root.push_input(press, true)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release, true)
	await process_frame

func _settle_ui(ui: Node) -> void:
	if is_instance_valid(world.hud.room_banner_tween):
		world.hud.room_banner_tween.custom_step(10.0)
	ui.process_input(1.0)
	ui.process_input(0.016)
	await _settle_frames()

func _settle_frames() -> void:
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
