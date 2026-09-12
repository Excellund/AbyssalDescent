extends "res://scripts/tests/render_farshot.gd"
## Actual Main reward presentation for all six Mission bonuses under production stretch.
## The offer order and already-cleared Mission are staged; combat/balance is not tested.

func _run() -> void:
	if not _is_isolated() or DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.content_scale_size = Vector2i(2560, 1440)
	frame_folder = ProjectSettings.globalize_path("res://mission_reward_frames")
	DirAccess.make_dir_recursive_absolute(frame_folder)
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = window_size
		await process_frame
		_setup_recovery_world()
		var builder: Node = world.encounter_profile_builder
		var bonuses: Array[Dictionary] = [builder._build_fortified_mutator(), builder._build_overcharge_mutator(), builder._build_hunters_focus_mutator(), builder._build_relay_boost_mutator(), builder._build_node_shield_mutator(), builder._build_combo_relay_mutator()]
		for bonus in bonuses:
			for count in [3, 4]:
				await _capture_mission(bonus, count)
		await _cleanup_recovery_world()
		node_added.disconnect(audio_retirement.observe_node)
	FileAccess.open(frame_folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name(), "scope": "Actual Main reward UI; six real Mission definitions, three/four real Boon offers, production canvas at960/1280/1920. Staged clear/offer order, normal keyboard confirmation and World grant. UI evidence, not combat or balance."}, "\t"))
	print("[OK] Mission reward native UI: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture_mission(bonus: Dictionary, count: int) -> void:
	var ui: Node = world.reward_selection_ui
	ui.close_selection()
	ui.initialize(count, 0.0)
	world._open_networked_reward_selection("Choose Mission Reward", ENUMS.RewardMode.MISSION, bonus)
	var pool: Array[Dictionary] = world.power_registry_instance.get_upgrade_pool(world.player)
	var offers: Array[Dictionary] = []
	for id in ["farshot", "patient_hunter", "marked_prey", "battle_trance"].slice(0, count):
		for choice in pool:
			if String(choice.id) == id:
				offers.append(choice.duplicate(true))
	check(offers.size() == count, "Mission UI uses complete real Boon descriptions")
	ui.boon_choices = offers
	ui._refresh_boon_ui(world.player)
	ui._on_viewport_size_changed()
	await _settle_ui(ui)
	var context := "%s_%d_choices_%d" % [CONTRACTS.mutator_id(bonus), count, root.size.x]
	var banner: RichTextLabel = ui.mission_bonus_label
	var banner_rect := _physical_rect(banner)
	check(banner.visible and not ui.boon_subtitle_label.visible, "Mission displays its supplied bonus: " + context)
	check(banner.get_content_height() <= banner.size.y + 1, "Complete Mission benefit and duration fit: " + context)
	check(_font_pixels(banner) >= 17.99, "Mission explanation stays at least 18 physical pixels: " + context)
	check(banner.get_parsed_text().contains(CONTRACTS.mutator_name(bonus)) and banner.get_parsed_text().contains("next 3 encounters"), "Mission reward states the exact bonus and duration: " + context)
	for index in count:
		_check_card(ui, index, context)
		check(banner_rect.intersection(_physical_rect(ui.boon_card_panels[index])).get_area() <= 0.01, "Mission benefit clears the Boon cards: " + context)
	check(banner_rect.intersection(_physical_rect(ui.boon_title_label)).get_area() <= 0.01, "Mission benefit clears the title: " + context)
	_capture(context, {"bonus": CONTRACTS.mutator_id(bonus), "bonus_copy": banner.get_parsed_text(), "bonus_pixels": _font_pixels(banner), "bonus_rect": banner_rect, "choice_count": count})
	# Exercise one real grant per window; other captures keep the comparison build unchanged.
	if CONTRACTS.mutator_id(bonus) == "combo_relay" and count == 4:
		var before: int = world.player.get_upgrade_stack_count("farshot")
		ui.boon_card_panels[0].grab_focus()
		await _key(KEY_ENTER)
		await _settle_frames()
		check(not ui.is_active() and world.player.get_upgrade_stack_count("farshot") == before + 1, "Keyboard confirms exactly one ordinary Mission Boon")
		var active: Array[Dictionary] = world.player.get_active_objective_mutators()
		check(active.any(func(entry: Dictionary) -> bool: return CONTRACTS.mutator_id(entry) == "combo_relay" and int(entry.get("remaining_encounters", 0)) == 3), "Actual World claim grants the displayed three-encounter Mission bonus")
