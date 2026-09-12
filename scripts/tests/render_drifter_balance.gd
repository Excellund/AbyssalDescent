extends "res://scripts/tests/render_motion_arcana.gd"
const DRIFTER := preload("res://scripts/enemy_drifter.gd")

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2.ONE * 0.85, 0.0, Vector2(FRAME_SIZE) * 0.5)
	output_directory = project_path.path_join("drifter_balance_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _make_world()
	player.position = Vector2(0, 190)
	var first := DRIFTER.new()
	_add_shape(first, 13.0)
	world.add_child(first)
	first.set_physics_process(false)
	first._emit_ring()
	first.rings[0]["radius"] = 120.0
	first.rings[0]["gap_index"] = 3
	first.wave_timer = 1.6
	await _capture("first_wave", "DRIFTER / FIRST WAVE", "Eleven visible pellets leave one explicit opening; the outlines match the damage radius.")
	first.rings.clear()
	first._emit_ring()
	first.rings[0]["radius"] = 240.0
	first.rings[0]["gap_index"] = 3
	first.queue_redraw()
	await _capture("second_wave", "DRIFTER / SHIFTED SECOND WAVE", "The next wave shifts by half a spoke, keeping its missing-spoke opening.")
	var second := DRIFTER.new()
	_add_shape(second, 13.0)
	world.add_child(second)
	second.set_physics_process(false)
	second.position = Vector2(180, -70)
	second._emit_ring()
	second.rings[0]["radius"] = 100.0
	second.rings[0]["gap_index"] = 4
	second.wave_timer = 2.1
	await _capture("two_drifters", "UNDERTOW / TWO STAGGERED DRIFTERS", "Each wave retains a visible opening and can deal one hit to each player.")
	await _free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var file := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures}, "\t"))
	file.close()
	print("[OK] Drifter GPU: %d frames, %d failures" % [frames.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
