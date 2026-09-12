extends "res://scripts/tests/render_motion_arcana.gd"
const CALLOUT_TEST := preload("res://scripts/tests/test_boss_callouts.gd")
const CALLOUT := preload("res://scripts/shared/enemy_attack_callout.gd")
const FAMILIES := ["warden", "sovereign", "lacuna", "seamlock", "mirrorline", "toll"]

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2.ONE * 0.78, 0.0, Vector2(FRAME_SIZE) * 0.5)
	output_directory = project_path.path_join("boss_callout_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _make_world()
	player.position = Vector2(220, 70)
	for family in range(FAMILIES.size()):
		for move in range(CALLOUT_TEST.COUNTS[family]):
			var boss: Node2D = CALLOUT_TEST.SCRIPTS[family].new()
			_add_shape(boss, 34.0)
			world.add_child(boss)
			boss.set_physics_process(false)
			boss.set("target", player)
			boss.set("target_candidates", [player])
			CALLOUT_TEST.prepare(boss, family, move)
			var callout: String = boss.call("get_attack_callout")
			_check(not callout.is_empty(), "A native move has its callout")
			await _capture("%s_%d" % [FAMILIES[family], move], FAMILIES[family].to_upper() + " / " + callout.replace("\n", " + "), "The native attack state supplies the readable move name; its danger geometry stays visible.")
			if family == 3 and move == 0:
				boss.call("_enter_illusion_phase", false)
				_check(boss.call("get_attack_callout").is_empty(), "The illusion answer stays hidden")
				await _capture("seamlock_illusions", "SEAMLOCK / FALSE REFLECTIONS APPEAR", "The announcement clears at the split so it does not identify the real body.")
			if family == 5 and move == 2:
				root.canvas_transform = Transform2D(0.0, Vector2.ONE * 0.5, 0.0, Vector2(FRAME_SIZE) * 0.5)
				boss.position = Vector2(-1100, -400)
				boss.queue_redraw()
				_check(root.get_visible_rect().encloses(CALLOUT.layout(boss, callout, -100.0).rect), "Both edge callouts fit")
				await _capture("toll_edge", "TOLL / SMALL ZOOM / TOP LEFT EDGE", "Both simultaneous callouts remain readable and stay inside the viewport.")
				root.canvas_transform = Transform2D(0.0, Vector2.ONE * 0.78, 0.0, Vector2(FRAME_SIZE) * 0.5)
			boss.free()
			await process_frame
	await _capture("owners_removed", "ENCOUNTER CLEARED", "Move names are drawn by their owners; none survive encounter cleanup.")
	await _free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var file := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures}, "\t"))
	file.close()
	print("[OK] Boss callout GPU: %d frames, %d failures" % [frames.size(), failures.size()])
	print("CALLOUT_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)
