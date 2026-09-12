extends "res://scripts/tests/test_relic_recovery.gd"
## Actual Main and Rest reward flow with representative staged builds/health.
var frames: Array[Dictionary] = []

func _run() -> void:
	if not _is_isolated() or DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.content_scale_size = Vector2i(2560, 1440)
	var folder := ProjectSettings.globalize_path("res://rest_site_choice_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720)]:
		root.size = window_size
		await process_frame
		for state in ["recover_only", "tradeoff", "healthy"]:
			_setup_recovery_world()
			if state != "recover_only":
				for choice in world.power_registry_instance.get_upgrade_pool(world.player):
					world.player.apply_upgrade(String(choice.id))
			world.player.health_state.set_health(world.player.get_max_health() if state == "healthy" else 60)
			world._choose_door(CONTRACTS.rest_door_option())
			var ui: Node = world.reward_selection_ui
			check(ui.is_active() and ui.reward_selection_mode == ENUMS.RewardMode.REST, "Actual Rest door opens the local decision")
			if state == "tradeoff":
				await _check_every_upgrade(ui)
			await _settle_rest(ui)
			var picture := root.get_texture().get_image()
			var name_text := "%s_%d" % [state, picture.get_width()]
			var path := folder.path_join(name_text + ".png")
			check(picture.save_png(path) == OK, "Native Rest frame saves: " + name_text)
			check(ui._layout_root.size.is_equal_approx(Vector2(picture.get_size())), "Rest uses the actual production game image size")
			check(not ui.skip_button.visible and not ui.reroll_button.visible, "Native Rest shows only the available actions")
			for i in ui.boon_choices.size():
				_check_card(ui, i, name_text)
			check(Rect2(Vector2.ZERO, ui._layout_root.size).encloses(ui.build_button.get_rect()), "Your Build remains inside the displayed game area")
			frames.append({"name": name_text, "path": path, "size": picture.get_size(), "canvas": root.content_scale_size, "choices": ui.boon_choices.duplicate(true)})
			# Native GUI keyboard input resolves the actual visible offer through World.
			var chosen_index := 0 if state == "recover_only" else 1
			var choice: Dictionary = ui.boon_choices[chosen_index].duplicate(true)
			var old_health: int = world.player.get_current_health()
			var old_stack: int = world.player.get_upgrade_stack_count(String(choice.id))
			ui.boon_card_panels[chosen_index].grab_focus()
			var press := InputEventKey.new()
			press.keycode = KEY_ENTER
			press.physical_keycode = KEY_ENTER
			press.pressed = true
			root.push_input(press, true)
			var release := press.duplicate() as InputEventKey
			release.pressed = false
			root.push_input(release, true)
			await process_frame
			check(not ui.is_active() and world.choosing_next_room, "Native Rest confirmation opens the real next doors")
			if chosen_index == 0:
				check(world.player.get_current_health() > old_health, "Recover grants healing through the real Rest resolver")
			else:
				check(world.player.get_upgrade_stack_count(String(choice.id)) == old_stack + 1, "Upgrade grants the chosen owned Boon's next stack")
			await _cleanup_recovery_world()
			node_added.disconnect(audio_retirement.observe_node)
	FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name(), "scope": "Actual Main Rest doors and native keyboard reward confirmation, with staged health/builds for UI inspection; production 2560x1440 canvas. Not balance evidence."}, "\t"))
	print("[OK] Rest Site GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _settle_rest(ui: Node) -> void:
	ui.process_input(1.0)
	ui.process_input(0.016)
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw

func _check_card(ui: Node, index: int, context: String) -> void:
	check(Rect2(Vector2.ZERO, ui._layout_root.size).encloses(ui.boon_card_rects[index]), "Rest card fits: " + context)
	check(ui.boon_card_labels[index].get_content_height() <= ui.boon_card_labels[index].size.y, "Rest copy fits: %s / %s" % [context, ui.boon_choices[index].name])

func _check_every_upgrade(ui: Node) -> void:
	var saved: Array[Dictionary] = ui.boon_choices.duplicate(true)
	var pool: Array[Dictionary] = world.power_registry_instance.get_upgrade_pool(world.player)
	for start in range(0, pool.size(), 2):
		var offers: Array[Dictionary] = [saved[0].duplicate(true)]
		for i in range(start, mini(start + 2, pool.size())):
			var choice := pool[i].duplicate(true)
			choice["rest_action"] = "upgrade"
			offers.append(choice)
		ui.open_rest_selection(offers, world.player, world.current_character_id)
		await _settle_rest(ui)
		for index in offers.size():
			_check_card(ui, index, "every owned Boon")
	ui.open_rest_selection(saved, world.player, world.current_character_id)
