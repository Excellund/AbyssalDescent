extends "res://scripts/tests/render_motion_arcana.gd"
## Real host/joiner warning paths and cleanup at the normal combat scale.

const REGRESSION := preload("res://scripts/tests/test_boss_telegraphs.gd")

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Boss GPU fixture requires an isolated validation project")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Boss GPU fixture requires an actual GPU renderer")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2(FRAME_SIZE) * 0.5 + Vector2(0.0, 25.0))
	output_directory = project_path.path_join("boss_telegraph_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _make_world()
	player.position = Vector2(-280.0, 120.0)
	var host := REGRESSION.Lacuna.new()
	world.add_child(host)
	host.boss_state = host.STATE_WINDUP
	host.active_attack = host.ATTACK_ECHO_CROSS
	host.telegraph_alpha = 1.0
	host._echo_cross_angle = 0.4
	host._sync_attack_overlay()
	await _capture("host_cross", "LACUNA / HOST CROSS WARNING", "Warning follows the complete damage capsule: full side width and rounded ends.")
	var state := host.get_projectile_network_sync_state().duplicate(true)
	host.free()
	await process_frame
	var remote := REGRESSION.Lacuna.new()
	world.add_child(remote)
	remote.set_network_simulation_enabled(false)
	remote.set_physics_process(false)
	remote.global_position = Vector2(10.0, -6.0)
	remote.apply_projectile_network_sync_state(state)
	await _capture("joiner_cross", "LACUNA / JOINER CROSS WARNING", "The received warning keeps the host's world origin while the replica body interpolates.")
	remote.free()
	await process_frame
	host = REGRESSION.Lacuna.new()
	world.add_child(host)
	var center := Vector2(180.0, 70.0)
	host._spawn_seam(center)
	host.seam_zones[0]["time_left"] = 0.24
	host.seam_zones[0]["tick_left"] = 0.01
	host._process_seam_zones(0.02)
	_check(host._seam_overlay.seam_zones.size() == 1, "The active seam has one synchronized warning")
	await _capture("late_active_seam", "LACUNA / FINAL ACTIVE SEAM TICK", "The seam is fading, but its boundary still marks the full damage radius.")
	var seam_overlay := host._seam_overlay
	var attack_overlay := host._attack_overlay
	host.free()
	await process_frame
	_check(not is_instance_valid(seam_overlay) and not is_instance_valid(attack_overlay), "Owner removal frees every boss warning")
	await _capture("owner_removed", "LACUNA REMOVED / WARNINGS CLEARED", "No expired seam or attack warning survives its owner.")
	await _free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures}
	var file := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("[OK] Boss telegraphs GPU: %d frames, %d failures" % [frames.size(), failures.size()])
	print("BOSS_TELEGRAPH_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)
