extends "res://scripts/tests/test_shatter_pillar_burst.gd"
## Real pillar break and its positive payoff at normal and narrow viewports.

var frames: Array[Dictionary] = []
var output_directory := ""

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	output_directory = ProjectSettings.globalize_path("res://shatter_pillar_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _setup_context_world()
	var center := await _enter_shatter()
	_enemy(center + Vector2(0, -120))
	_enemy(center + Vector2(0, 120))
	_swing()
	_swing()
	await _capture_shards("last_crack_1280", Vector2i(1280, 720), false, false)
	_swing()
	await _capture_shards("shards_impact_1280", Vector2i(1280, 720), false, true)
	world._tick_biome_rules(.16)
	await _capture_shards("shards_spread_1280", Vector2i(1280, 720), false, true)
	await _capture_shards("shards_spread_960", Vector2i(960, 720), false, true)
	world._tick_biome_rules(.20)
	await _capture_shards("shards_fade_tooltip_960", Vector2i(960, 720), true, true)
	world._tick_biome_rules(.2)
	await _capture_shards("shards_expired_960", Vector2i(960, 720), false, false)
	await _dispose_context_world()
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name()}, "\t"))
	print("[ShatterPillarGPU] %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture_shards(frame_name: String, size: Vector2i, tooltip: bool, active: bool) -> void:
	world.hud._on_biome_header_exited()
	root.size = size
	root.content_scale_size = size
	await process_frame
	world._apply_camera_bounds_for_room(world.current_effective_room_size)
	world._update_camera_mode()
	world.player_camera.set_physics_process(false)
	world.player_camera.global_position = Vector2.ZERO
	world.player_camera.zoom = world.player_camera.target_zoom
	world.player_camera.force_update_scroll()
	world._sync_renderer()
	world.hud.refresh(world._get_hud_state(), world.player)
	world._biome_rules.queue_redraw()
	check(not world._biome_rules.shard_bursts.is_empty() if active else world._biome_rules.shard_bursts.is_empty(), "Actual break effect matches its staged lifetime: " + frame_name)
	var hint: Label = world.hud._status_biome_rule_label
	check(hint.text.begins_with("HELP:") and hint.get_minimum_size().y <= hint.size.y + .01, "Complete helpful-pillar advice fits the HUD: " + frame_name)
	if tooltip:
		world.hud._on_biome_header_entered()
		world.hud._process(world.hud.BIOME_HOVER_DELAY + .1)
		await process_frame
		var panel: PanelContainer = world.hud._biome_tooltip_panel
		var content: RichTextLabel = world.hud._biome_tooltip_content
		check(panel.visible and root.get_visible_rect().encloses(panel.get_global_rect()) and content.get_content_height() <= content.size.y + .01, "Full pillar payoff inspection fits the narrow viewport")
		check(content.get_parsed_text().contains("60 base damage") and content.get_parsed_text().contains("You are safe"), "Inspection explains actual payoff and safe target mask")
	await process_frame
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(frame_name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Saved native shard state: " + frame_name)
	frames.append({"name": frame_name, "path": path, "bursts": world._biome_rules.shard_bursts.duplicate(true)})
	print("[FRAME] " + path)
