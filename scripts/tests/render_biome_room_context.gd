extends "res://scripts/tests/test_biome_room_context.gd"
## Native Main presentation for compact rules, assistance and actual objective
## geometry, with full contextual tooltips at the narrow supported viewport.

const ALTERNATIVE := preload("res://scripts/enemy_boss_alternative.gd")
var frames: Array[Dictionary] = []
var output_directory := ""

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not DirAccess.dir_exists_absolute("res://validation_fixtures") or not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	output_directory = ProjectSettings.globalize_path("res://biome_room_context_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _setup_context_world()
	var ids: Array = BIOMES.BIOME_DEFINITIONS.keys()
	var boss_ids: Array = BOSSES.NAMES.keys()
	for index in ids.size():
		var id := String(ids[index])
		await _enter_context(id, COMPACT_KEYS[index])
		_start_context_combat()
		_context_phase("warning")
		await _capture_context(id + "_compact_warning_1280", Vector2i(1280, 720), false)
		_context_phase("active")
		await _capture_context(id + "_compact_active_960", Vector2i(960, 720), true)
		var boss: Node2D
		if index < boss_ids.size():
			boss = await _enter_context_boss(id, String(boss_ids[index]))
		else:
			await _enter_context(id, APEX_KEYS[index - boss_ids.size()])
			for enemy in _context_enemies():
				if enemy.has_method("_enter_band_attack") or enemy.has_method("_enter_telegraph") or enemy.has_method("_begin_pulse_telegraph"):
					boss = enemy
					break
		_start_context_combat()
		_stage_native_warning(boss)
		_context_phase("warning")
		await _capture_context(id + "_assistance_warning_1280", Vector2i(1280, 720), false)
		_context_phase("active")
		await _capture_context(id + "_assistance_active_960", Vector2i(960, 720), true)
	await _enter_context("storm_reach", "apex_breakwater")
	_start_context_combat()
	for enemy in _context_enemies():
		if enemy.has_method("_begin_tracking"):
			_stage_native_warning(enemy)
	_context_phase("warning")
	await _capture_context("breakwater_assistance_warning_1280", Vector2i(1280, 720), false)
	_context_phase("active")
	await _capture_context("breakwater_assistance_active_960", Vector2i(960, 720), true)
	await _dispose_context_world()
	check(frames.size() == 38, "Nine compact/assistance pairs plus the fourth Apex have both native viewport states")
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name(), "scope": "Native Main doors, all nine compact and assistance rules, six real boss warnings and four Apex warnings;1280 warning and960 active/contextual tooltip. Timers held after commitment for visual review."}, "\t"))
	print("[BiomeRoomContextGPU] %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _stage_native_warning(enemy: Node2D) -> void:
	check(is_instance_valid(enemy), "Native assistance context has its actual boss or Apex opponent")
	if not is_instance_valid(enemy):
		return
	enemy.global_position = Vector2(100, 0)
	world.player.global_position = Vector2(-160, 0)
	enemy.set("target", world.player)
	enemy.set("spawn_transport_time_left", 0.0)
	if enemy is ALTERNATIVE:
		enemy.begin_attack(0)
		enemy._process_behavior(float(enemy.warning_duration) * .5)
		check(not enemy.get_attack_warning_geometry().is_empty(), "Alternative boss retains its real committed warning beside friendly biome geometry")
	elif enemy.has_method("_start_next_attack"):
		enemy.call("_start_next_attack", 260.0, 0.0)
		enemy.call("_process_behavior", float(enemy.get("state_time_left")) * .5)
		check(float(enemy.get("telegraph_alpha")) > 0.0, "Original boss retains its real visible warning beside friendly biome geometry")
	elif enemy.has_method("_enter_band_attack"):
		enemy.call("_enter_band_attack")
		enemy.call("_process_behavior", .2)
	elif enemy.has_method("_enter_telegraph"):
		enemy.call("_enter_telegraph")
		enemy.call("_process_behavior", .2)
	elif enemy.has_method("_begin_pulse_telegraph"):
		enemy.call("_begin_pulse_telegraph")
		enemy.call("_process_behavior", .2)
	elif enemy.has_method("_begin_tracking"):
		enemy.call("_begin_tracking")
		enemy.call("_process_behavior", .2)
	enemy.queue_redraw()

func _capture_context(frame_name: String, size: Vector2i, tooltip: bool) -> void:
	world.hud._on_biome_header_exited()
	# A previous compact impact can precede the next staged room by only a
	# couple of real frames. Settle its existing cosmetic fade before review.
	var feedback: Node = world.player.player_feedback
	if is_instance_valid(feedback.damage_flash_tween):
		feedback.damage_flash_tween.custom_step(1.0)
	check(not is_instance_valid(feedback.damage_flash_rect) or feedback.damage_flash_rect.modulate.a <= .01, "Prior impact flash has completed before native presentation review")
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
	var state: Dictionary = world._biome_rules.snapshot()
	var identity := BIOMES.get_room_combat_identity(String(state.id), String(state.mode), bool(state.fragments))
	var hint: Label = world.hud._status_biome_rule_label
	check(hint.visible and hint.text == identity.entry_hint, "Actual HUD displays the current compact/assistance rule: " + frame_name)
	check(hint.get_minimum_size().y <= hint.size.y + .01 and root.get_visible_rect().encloses(hint.get_global_rect()), "Complete contextual rule fits the native HUD: " + frame_name)
	if world.hud.room_banner_title_label.text == world._get_active_biome_name() and world.hud.room_banner_subtitle_label.modulate.a > .01:
		check(world.hud.room_banner_subtitle_label.text == identity.entry_hint, "Visible biome banner agrees with the current safe or hostile instruction: " + frame_name)
	if tooltip:
		world.hud._on_biome_header_entered()
		world.hud._process(world.hud.BIOME_HOVER_DELAY + .1)
		await process_frame
		var panel: PanelContainer = world.hud._biome_tooltip_panel
		var content: RichTextLabel = world.hud._biome_tooltip_content
		check(panel.visible and root.get_visible_rect().encloses(panel.get_global_rect()) and content.get_content_height() <= content.size.y + .01, "Complete contextual tooltip fits960 without clipping: " + frame_name)
		check(content.get_parsed_text().to_lower().contains(String(identity.terrain).to_lower()), "Tooltip describes the live room pattern instead of an absent terrain layout: " + frame_name)
		check(content.get_parsed_text().contains("foes only") if state.mode == "assistance" else content.get_parsed_text().contains("objective space"), "Tooltip states who is affected and the room-specific protection: " + frame_name)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(frame_name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Saved native biome context: " + frame_name)
	frames.append({"name": frame_name, "path": path, "state": state, "room": world.current_room_label, "size": size, "camera_zoom": world.player_camera.zoom})
	print("[FRAME] " + path)
