extends "res://scripts/tests/render_motion_arcana.gd"
## Actual production swing polygons, shade drawing and damage at gameplay scale.

class RemotePlayer extends RenderPlayer:
	func _is_local_control_owner() -> bool:
		return false

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Attack GPU fixture requires an isolated validation project")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Attack GPU fixture requires a real GPU renderer")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2(FRAME_SIZE) * 0.5 + Vector2(0.0, 25.0))
	output_directory = project_path.path_join("attack_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _moving_melee_frame()
	await _wind_pair_frame()
	await _shade_wind_frame()
	await create_timer(0.2).timeout
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures, "size": [FRAME_SIZE.x, FRAME_SIZE.y]}
	var file := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("[OK] Attack GPU fixture: %d frames, %d failures" % [frames.size(), failures.size()])
	print("ATTACK_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)

func _prepare_world() -> void:
	await _make_world()
	for label in world.find_children("*", "Label", true, false):
		if String(label.text).begins_with("MOTION ARCANA"):
			label.text = "ATTACK FEEDBACK  /  Isolated GPU playtest fixture  /  1280 × 720"

func _swings(actor: Node2D) -> Array[Polygon2D]:
	var result: Array[Polygon2D] = []
	for child in actor.player_feedback.get_children():
		if child is Polygon2D:
			result.append(child)
	return result

func _origin_marker(point: Vector2) -> void:
	var line := Line2D.new()
	line.position = point
	line.width = 1.0
	line.default_color = Color(0.74, 0.82, 0.9, 0.75)
	line.z_index = 6
	line.points = PackedVector2Array([Vector2(-5.0, 0.0), Vector2(5.0, 0.0), Vector2.ZERO, Vector2(0.0, -5.0), Vector2(0.0, 5.0)])
	world.add_child(line)

func _moving_melee_frame() -> void:
	await _prepare_world()
	var origin := player.global_position
	var target := _add_enemy(origin + Vector2(50.0, 10.0))
	_add_enemy(origin + Vector2(150.0, -40.0))
	await physics_frame
	player.arcana_motion.motion = MOTION.Motion.RECOIL
	player.arcana_motion.recoil_direction = Vector2.LEFT
	player.arcana_motion.recoil_initial_direction = Vector2.LEFT
	player.arcana_motion.recoil_left = 170.0
	player.arcana_motion.recoil_speed = 700.0
	player._try_execute_attack(Vector2.RIGHT)
	var swing := _swings(player)[0]
	player.arcana_motion.process_movement(0.08, Vector2.ZERO)
	_origin_marker(origin)
	_check(target.get_current_health() < 10000 and player.global_position.distance_to(origin) > 50.0, "Real melee damage occurs while recoil keeps moving the player")
	_check(swing.global_position == origin and swing.scale == Vector2.ONE, "Visible melee remains at true strike position and range")
	await _capture("moving_melee", "MELEE DURING RECOIL / STRIKE STAYS AT THE HIT", "The small cross marks the attack origin. The player has recoiled 56px; the fading swing stays with the struck enemy.")
	await _free_world()

func _wind_pair_frame() -> void:
	await _prepare_world()
	player.global_position = Vector2(-160.0, -110.0)
	for _index in range(3):
		player.apply_trial_power("razor_wind")
	var origin := player.global_position
	player._try_execute_attack(Vector2.RIGHT)
	var swings := _swings(player)
	_check(swings.size() == 2, "Local Razor Wind uses separate melee and outer-band geometry")
	# Isolate the wind layer in this comparison; both layers still render during play.
	swings[0].visible = false
	var wind := swings[1]
	var context := player.upgrade_system.build_melee_attack_context(player.damage, player.attack_range, player.attack_arc_degrees, false, player.execution_damage_mult)
	var wind_context := player.upgrade_system.build_razor_wind_attack_context(context, player.razor_wind_damage_ratio, player.razor_wind_range_scale, player.razor_wind_arc_degrees, player.damage, player.attack_range)
	var remote := RemotePlayer.new()
	_add_shape(remote, 14.0)
	world.add_child(remote)
	remote.apply_character_package(CHARACTER.get_character("bastion"))
	remote.arcana_motion.set_process(false)
	remote.position = Vector2(-240.0, 125.0)
	var remote_origin := Vector2(-160.0, 125.0)
	remote.play_network_attack_indicator(Vector2.RIGHT, float(wind_context["range"]), float(wind_context["arc_degrees"]), wind.color, 0.14, remote_origin, player.attack_range)
	var remote_wind := _swings(remote)[0]
	player.global_position += Vector2(-80.0, 0.0)
	_origin_marker(origin)
	_origin_marker(remote_origin)
	_check(wind.polygon == remote_wind.polygon and remote_wind.global_position == remote_origin, "Local and replica display identical wind bands at transmitted origins")
	await _capture("razor_wind_local_remote", "RAZOR WIND / LOCAL ABOVE, REMOTE BELOW", "Wind layer only: both leave the same hollow inner area. Each player moved 80px away from the marked strike origin.")
	if is_instance_valid(remote.upgrade_system.power_registry):
		remote.upgrade_system.power_registry.free()
	await _free_world()

func _shade_wind_frame() -> void:
	await _prepare_world()
	var origin := Vector2(-80.0, 0.0)
	player.position = Vector2(-260.0, 80.0)
	var inner := _add_enemy(origin + Vector2(35.0, 0.0))
	var outer := _add_enemy(origin + Vector2(130.0, 0.0))
	await physics_frame
	player.sovereigns_double_stacks = 2
	player.boss_combinations.create_shade(origin)
	player.boss_combinations.repeat_strike(Vector2.RIGHT, [{"source": "razor_wind", "damage": 30, "range": 195.0, "arc_degrees": 70.0, "inner_range": 78.0}])
	_check(inner.get_current_health() == 10000 and outer.get_current_health() < 10000, "Shade wind frame has real damage only in the visible outer band")
	_check(float(player.boss_combinations._echo_visuals[0]["inner_range"]) == 78.0, "Shade drawing receives its real inner damage boundary")
	await _capture("shade_wind_boundary", "SOVEREIGN'S DOUBLE / WIND BOUNDARY", "The violet inner arc marks where wind damage begins. The inner enemy stays untouched; the enemy between the arcs is struck.")
	await _free_world()
