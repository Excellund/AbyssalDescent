extends "res://scripts/tests/render_reward_build_inspection.gd"

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or DisplayServer.get_name() == "headless":
		quit(1)
		return
	var retirement := AUDIO_RETIREMENT.new()
	node_added.connect(retirement.observe_node)
	_setup_ui()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var folder := project_path.path_join("reward_upgrade_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	for mode in [ENUMS.RewardMode.ARCANA, ENUMS.RewardMode.BOSS]:
		_free_world()
		_make_world(0)
		var ids: Array = REGISTRY.TRIAL_POWER_POOL_IDS if mode == ENUMS.RewardMode.ARCANA else REGISTRY.BOSS_REWARD_POOL_IDS
		var owned_levels := 3 if mode == ENUMS.RewardMode.ARCANA else 1
		var category := "arcana" if mode == ENUMS.RewardMode.ARCANA else "boss"
		for level in range(1, owned_levels + 1):
			for id: String in ids:
				if mode == ENUMS.RewardMode.ARCANA:
					player.apply_trial_power(id)
				else:
					player.apply_upgrade(id)
			var longest := _longest_native_cards(ids, mode)
			for size in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
				viewport.size = size
				ui.initialize(3, 0.0)
				for page in range(ceili(float(ids.size()) / 3.0)):
					_show_native_page(ids.slice(page * 3, page * 3 + 3), mode, level)
					await _capture(folder, "%s_owned%d_page%d_%d" % [category, level, page, size.x])
					ui.close_selection()
				ui.initialize(4, 0.0)
				_show_native_page(longest, mode, level)
				await _capture(folder, "%s_owned%d_four_%d" % [category, level, size.x])
				ui.close_selection()
	await _finish_render(retirement, folder)

func _longest_native_cards(ids: Array, mode: int) -> Array:
	var lengths: Array[Dictionary] = []
	for id: String in ids:
		var card: String = player.get_trial_power_card_desc(id) if mode == ENUMS.RewardMode.ARCANA else player.get_upgrade_card_desc(id)
		lengths.append({"id": id, "length": BUILD_PANEL.COMBAT_KEYWORDS.to_plain(card).length()})
	lengths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.length) > int(b.length))
	var result: Array[String] = []
	for entry in lengths.slice(0, 4):
		result.append(String(entry.id))
	return result
