extends "res://scripts/tests/test_relic_recovery.gd"
## Native Main, production 2560x1440 canvas, actual window sizes. Cargo is
## acquired through ordinary walking/collision; secondary party views are
## explicitly staged, while actual authority transport is checked by ENet.
var frames: Array[Dictionary] = []
var folder := ""

func _run() -> void:
	if not _is_isolated() or DisplayServer.get_name() == "headless":
		quit(1)
		return
	_setup_recovery_world()
	folder = ProjectSettings.globalize_path("res://relic_recovery_frames")
	DirAccess.make_dir_recursive_absolute(folder)
	for width in [960, 1280]:
		root.size = Vector2i(width, 720)
		# Keep the actual production canvas. Do not make UI fit by shrinking it
		# to the screenshot's dimensions, which hides native scaling defects.
		root.content_scale_size = Vector2i(2560, 1440)
		await process_frame
		var profile := _enter_recovery()
		for enemy in get_nodes_in_group("enemies"):
			enemy._update_spawn_transport(2.0)
		var sites := CONTRACTS.profile_relic_positions(profile)
		world._apply_camera_bounds_for_room(world.current_effective_room_size)
		world._update_camera_mode()
		world.player_camera.set_physics_process(false)
		world.player_camera.zoom = world.player_camera.target_zoom
		world.player_camera.global_position = Vector2.ZERO
		world.player_camera.force_update_scroll()
		await _capture("survey_" + str(width), "survey")
		world._exit_encounter_intro_grace()
		world.player.global_position = Vector2.ZERO
		await _walk_to(sites[0], 3.0)
		check(world.objective_manager.relic_recovery.carrier_has_relic(maxi(1, world.player.player_id)), "Native collision-based walking acquires the relic at " + str(width))
		await _capture("carrying_" + str(width), "carrying")
		await _walk_to(Vector2.ZERO, 3.0)
		check(world.objective_manager.relic_recovery.delivered_count() == 1, "Native walking returns cargo to the receiver at " + str(width))
		await _capture("delivered_" + str(width), "delivered")
		# Render the remaining two states on the real actor after natural pickup.
		await _walk_to(sites[1], 3.0)
		world.player.global_position = Vector2(130, 90)
		_tick_recovery()
		var snapshot: Dictionary = world.objective_manager.relic_recovery.snapshot()
		var local_id := maxi(1, world.player.player_id)
		world.objective_manager.relic_recovery.advance([_roster(local_id, world.player.global_position, false)])
		check(world.objective_manager.relic_recovery.delivered_count() == 1 and not world.objective_manager.relic_recovery.carrier_has_relic(local_id), "Staged fallen carrier leaves one delivered and one dropped relic")
		world.player.hide()
		await _capture("dropped_" + str(width), "staged death drop")
		world.player.show()
		world.objective_manager.relic_recovery.apply_snapshot(snapshot)
		for index in [1, 2]:
			world.player.global_position = sites[index]
			_tick_recovery()
			world.player.global_position = Vector2.ZERO
			_tick_recovery()
		await _capture("reward_" + str(width), "Mission reward")
	await _cleanup_recovery_world()
	var manifest := {"frames": frames, "checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name(), "scope": "Production canvas and real Main survey, normal walking pickup/deposit, staged drop and actual Mission reward. Enemies are held idle for consistent visual review; this is not balance acceptance."}
	FileAccess.open(folder.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[OK] Relic Recovery GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _walk_to(destination: Vector2, seconds: float) -> void:
	for _frame in ceili(seconds * 60.0):
		var offset: Vector2 = destination - world.player.global_position
		if offset.length() <= 20.0:
			break
		for action in ["move_left", "move_right", "move_up", "move_down"]:
			Input.action_release(action)
		if absf(offset.x) > 8.0:
			Input.action_press("move_right" if offset.x > 0 else "move_left")
		if absf(offset.y) > 8.0:
			Input.action_press("move_down" if offset.y > 0 else "move_up")
		world.player._physics_process(1.0 / 60.0)
		_tick_recovery(1.0 / 60.0)
		for enemy in get_nodes_in_group("enemies"):
			enemy.set_physics_process(false)
			enemy._update_spawn_transport(2.0)
		await physics_frame
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
	world.player.velocity = Vector2.ZERO
	_tick_recovery()
	check(world.player.global_position.distance_to(destination) <= 45.0, "Ordinary player collision reaches requested recovery location")

func _capture(label: String, stage: String) -> void:
	if world.reward_selection_ui.is_active():
		world.reward_selection_ui.process_input(1.0)
	world.hud.refresh(world._get_hud_state(), world.player)
	world._sync_renderer()
	await process_frame
	await process_frame
	# Main normally refreshes every frame. Give changed objective text its
	# next normal layout pass after containers have resolved their height.
	world.hud.refresh(world._get_hud_state(), world.player)
	await process_frame
	await RenderingServer.frame_post_draw
	if stage != "Mission reward":
		for line: Label in [world.hud._status_obj_line1, world.hud._status_obj_line2, world.hud._status_obj_line3]:
			check(line.visible and line.get_minimum_size().x <= line.size.x + 1.0, "Objective line fits its actual native layout: " + label)
	var path := folder.path_join(label + ".png")
	var picture := root.get_texture().get_image()
	check(picture.save_png(path) == OK, "Native frame saves: " + label)
	frames.append({"name": label, "path": path, "stage": stage, "size": picture.get_size(), "canvas": root.content_scale_size, "zoom": world.player_camera.zoom})
	print("[FRAME] " + path)
