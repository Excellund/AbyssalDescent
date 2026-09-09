extends "res://scripts/tests/render_motion_arcana.gd"
## Real reward and build panels, using actual next/current descriptions.

const REWARDS := preload("res://scripts/reward_selection_ui.gd")
const BUILD := preload("res://scripts/build_detail_panel.gd")
const REGISTRY := preload("res://scripts/power_registry.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const DESCRIPTION_GUARD := preload("res://scripts/shared/description_cap_guard.gd")

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Description GPU fixture requires an isolated validation project")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Description GPU fixture requires a real GPU renderer")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2(FRAME_SIZE) * 0.5 + Vector2(0.0, 25.0))
	output_directory = project_path.path_join("description_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _make_world()
	for id in ["blast_drive", "razor_orbit", "returning_crescent"]:
		player.apply_trial_power(id)
		player.apply_trial_power(id)
	var registry := REGISTRY.new()
	world.add_child(registry)
	var rewards := REWARDS.new()
	world.add_child(rewards)
	rewards._create_ui()
	await _cards(rewards, registry, ["blast_drive", "razor_orbit", "returning_crescent"], "arcana_level_three", "Level 3 Arcana")
	for id in ["blast_drive", "razor_orbit", "returning_crescent", "eclipse_mark"]:
		while player.get_trial_power_stack_count(id) < 3:
			player.apply_trial_power(id)
	rewards.configure_catalyst_payload({"arcana_capacity_add": 1.0})
	await _cards(rewards, registry, ["blast_drive", "razor_orbit", "returning_crescent"], "arcana_prismatic", "Prismatic Arcana")
	player.apply_upgrade("null_corridor")
	player.apply_upgrade("bloodpact")
	await _cards(rewards, registry, ["eclipse_mark", "null_corridor", "bloodpact"], "mark_corridor_bloodpact", "Power Descriptions")
	rewards.close_selection()
	var build := BUILD.new()
	world.add_child(build)
	build.setup()
	build.refresh("bastion", [], ["blast_drive", "razor_orbit", "returning_crescent"], ["null_corridor"], player)
	build.open()
	await _capture("current_build", "", "")
	for description in build.arcana_list_container.find_children("*", "RichTextLabel", true, false):
		var label := description as RichTextLabel
		_check(label.get_content_height() <= label.size.y + 1.0, "Current Arcana description fits its real build entry")
	build.power_registry_instance.free()
	await _free_world()
	await create_timer(0.2).timeout
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures, "size": [FRAME_SIZE.x, FRAME_SIZE.y]}
	var file := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("[OK] Description GPU fixture: %d frames, %d failures" % [frames.size(), failures.size()])
	print("DESCRIPTION_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)

func _cards(rewards: REWARDS, registry: REGISTRY, ids: Array, name: String, heading: String) -> void:
	rewards.boon_choices.clear()
	for id in ids:
		var trial := REGISTRY.TRIAL_POWER_POOL_IDS.has(id)
		var description := player.get_trial_power_card_desc(id) if trial else player.get_upgrade_card_desc(id)
		rewards.boon_choices.append({"id": id, "name": registry.get_power_display_name(id), "desc": description, "stack_limit": registry.get_power_stack_limit(id), "type": REGISTRY.POWER_TYPE_TRIAL if trial else REGISTRY.POWER_TYPE_UPGRADE})
		var lines := DESCRIPTION_GUARD.strip_bbcode(description).split("\n", false)
		_check(DESCRIPTION_GUARD.visible_length(description) <= DESCRIPTION_GUARD.MAX_VISIBLE_CARD_CHARS, id + " full reward explanation fits the visible cap")
		_check(not lines.is_empty() and String(lines[-1]).length() <= DESCRIPTION_GUARD.MAX_VISIBLE_DESC_CHARS, id + " numeric line retains the compact visible cap")
	rewards.boon_title_text = heading
	rewards.reward_selection_mode = ENUMS.RewardMode.ARCANA
	rewards.current_player = player
	rewards.current_character_id = "bastion"
	rewards.boon_selection_active = true
	rewards.boon_confirm_lock_time = 0.0
	rewards.boon_reveal_time = 1.0
	rewards._open_fade_time = 1.0
	rewards._apply_mode_theme()
	rewards._refresh_boon_ui(player)
	rewards._apply_global_ui_alpha(1.0)
	rewards.boon_layer.show()
	await process_frame
	await _capture(name, "", "")
	for label in rewards.boon_card_labels:
		_check(label.get_content_height() <= label.size.y + 1.0, "Reward text fits its production card height: " + label.get_parsed_text().get_slice("\n", 0))
		_check(label.get_global_rect().end.x <= FRAME_SIZE.x, "Reward text stays inside the viewport: " + label.get_parsed_text().get_slice("\n", 0))
		_check(label.size.x <= label.custom_minimum_size.x + 1.0, "Reward text shrinks to its computed card width")
	for panel in rewards.boon_card_panels:
		_check(panel.get_global_rect().end.x <= FRAME_SIZE.x, "Reward panel stays inside the viewport")
