extends "res://scripts/tests/render_boss_callout_parity.gd"
## Captures the production presentation in Main. For a historical comparison,
## the disposable validation copy may supply the complete, unedited alternative
## boss script extracted from d3a82a2 at the path below. No production toggle.

const HISTORICAL_PATH := "res://validation_fixtures/callout_historical_alternative.gd"
const PAIR_MOVES := [2, 4, 1]
var historical_script: Script

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Callout reference capture requires a native disposable project")
		quit(1)
		return
	if FileAccess.file_exists(HISTORICAL_PATH):
		historical_script = load(HISTORICAL_PATH) as Script
		check(historical_script != null, "Complete historical source loads in the disposable project")
	output_directory = ProjectSettings.globalize_path("res://callout_reference_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	await _setup_context_world()
	for power_id: String in OWNED_POWERS:
		check(world.player.upgrade_system.apply_power(power_id), "Actual build HUD has " + power_id)
	for family in range(3):
		await _open_pair(family)
		if historical_script != null:
			alternative.free()
			alternative = historical_script.new()
			alternative.boss_id = ALT_IDS[family]
			alternative.set_meta("boss_id", ALT_IDS[family])
			world.add_child(alternative)
			alternative.arena_size = world.current_effective_room_size
			alternative.target = world.player
			alternative.target_candidates = [world.player]
			alternative.set_physics_process(false)
			alternative.set_process(false)
			alternative._update_spawn_transport(float(alternative.spawn_transport_time_left) + .01)
		for capture_size: Vector2i in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			await _fit_native_camera(capture_size)
			_prepare_pair(family, PAIR_MOVES[family])
			# Use Glass Cage at the largest arena scale, alongside the original
			# family's longest root name. All geometry is actual actor drawing.
			if family in [0, 1]:
				alternative._cancel_attack()
				alternative.begin_attack(1 if family == 0 else 2)
				alternative._process_behavior(float(alternative.warning_duration) * .45)
			if family == 2:
				original._enter_attack_state()
				original._process_attack_state(.1)
				original.queue_redraw()
			await _capture_reference("%s_%d_pair" % [BOSSES.DEFAULT_IDS[family], capture_size.x], [original, alternative])
	for apex_index in range(APEX_KEYS.size()):
		await _enter_context("crumble", APEX_KEYS[apex_index])
		_start_context_combat()
		await _fit_native_camera(Vector2i(1280, 720))
		var apex: Node2D
		for candidate in _context_enemies():
			if candidate.has_method("get_attack_callout"):
				apex = candidate
				break
		check(is_instance_valid(apex), "Real Apex door spawns its callout owner")
		if not is_instance_valid(apex):
			continue
		apex.global_position = apex.get_canvas_transform().affine_inverse() * (Vector2(root.size) * Vector2(.65, .5))
		if apex_index == 2:
			apex.global_position = apex.anchor_world_position
		world.player.global_position = apex.global_position + Vector2(190.0, 130.0)
		apex.target = world.player
		apex.target_candidates = [world.player]
		if apex_index < 3:
			CALLOUT_TEST.prepare(apex, apex_index + 3, [0, 1, 2][apex_index])
		else:
			apex._begin_tracking()
		apex.queue_redraw()
		await _capture_reference(APEX_KEYS[apex_index] + "_1280", [apex])
	await _dispose_context_world()
	check(frames.size() == 13, "Three paired boss families at three zooms and all four Apex trials are captured")
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures, "historical_source": "d3a82a2:scripts/enemy_boss_alternative.gd" if historical_script != null else "", "scope": "Actual Main, real boss and Apex doors, paired original/alternative owners, 960/1280/1920 sizes, concurrent Toll callouts, current timing and HUD unchanged."}
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[OK] Callout reference GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture_reference(frame_name: String, actors: Array) -> void:
	await process_frame
	await process_frame
	check(world.hud.is_in_group("attack_callout_hud") and world.hud.status_panel.is_visible_in_tree(), "Production HUD remains present: " + frame_name)
	var records: Array[Dictionary] = []
	for actor: Node2D in actors:
		var historical: bool = historical_script != null and actor.get_script() == historical_script
		var text := ""
		var info := {}
		if historical:
			text = String(actor.PROFILES[actor.boss_id].names[actor.attack_kind])
			if actor.boss_id == "kilnheart" and actor.attack_kind == 1:
				text += " / IN" if actor._sequence_step > 0 else " / OUT"
			var font := ThemeDB.fallback_font
			var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
			var baseline := Vector2(-size.x * .5, -100.0)
			info = {"rect": actor.get_global_transform_with_canvas() * Rect2(baseline - Vector2(0.0, font.get_ascent(18)), size), "font_size": 18, "world_scaled": true}
		else:
			text = actor.get_attack_callout()
			info = CALLOUT.layout(actor, text, -100.0)
			check(float(info.font_size) * root.get_stretch_transform().get_scale().x >= 18.0 - .01, "Current type keeps 18 physical pixels: " + text)
			for exclusion: Rect2 in world.hud.get_attack_callout_exclusion_rects():
				check(not (info.rect as Rect2).intersects(exclusion), "Current callout clears HUD: " + text)
		check(not text.is_empty(), "Actual staged warning is named: " + frame_name)
		check(root.get_visible_rect().encloses(info.rect), "Native view contains name: " + text)
		records.append({"historical": historical, "text": text, "layout": info, "script": actor.get_script().resource_path, "screen_position": actor.get_global_transform_with_canvas().origin})
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(frame_name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Saved native reference comparison: " + frame_name)
	frames.append({"name": frame_name, "path": path, "size": root.size, "camera_zoom": world.player_camera.zoom, "actors": records})
	print("[FRAME] " + path)
