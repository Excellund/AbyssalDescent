extends "res://scripts/tests/test_live_arena_edges.gd"
const ARCHER := preload("res://scripts/enemy_archer.gd")
var shooter: ARCHER

func _spawn_archer() -> void:
	_setup()
	actor.global_position = Vector2.ZERO
	shooter = ARCHER.new()
	_circle(shooter, 12.0)
	room.add_child(shooter)
	shooter.set_physics_process(false)
	shooter.global_position = Vector2(-250.0, 0.0)
	shooter.target = actor
	shooter.target_candidates = [actor]
	shooter.arena_size = room.current_effective_room_size

func _shot(position: Vector2, direction: Vector2 = Vector2.RIGHT) -> Node2D:
	shooter.arrow_direction = direction
	shooter._fire_arrow()
	var bullet: Node2D = shooter.projectiles.back()
	bullet.global_position = position
	return bullet

func _cover(position: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4.0, 80.0)
	collision.shape = shape
	body.add_child(collision)
	room.add_child(body)
	body.global_position = position
	return body

const RENDERER := preload("res://scripts/world_renderer.gd")
const FRAME_SIZE := Vector2i(1280,720)
var frames: Array[Dictionary] = []
var output_directory: String
var title: Label
var detail: Label

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Archer fixture requires an actual GPU")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	var zoom := minf(1280.0/1160.0,720.0/860.0)*0.95
	root.canvas_transform = Transform2D(Vector2(zoom,0.0),Vector2(0.0,zoom),Vector2(FRAME_SIZE)*0.5)
	output_directory = project_path.path_join("archer_projectile_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	_spawn_archer()
	actor.global_position = Vector2(160.0,0.0)
	var renderer := RENDERER.new()
	renderer.room_size = room.current_effective_room_size
	room.add_child(renderer)
	var layer := CanvasLayer.new()
	room.add_child(layer)
	title = Label.new()
	title.position = Vector2(35.0,24.0)
	title.add_theme_font_size_override("font_size",23)
	layer.add_child(title)
	detail = Label.new()
	detail.position = Vector2(35.0,58.0)
	detail.add_theme_font_size_override("font_size",16)
	detail.modulate = Color(0.75,0.85,0.92)
	layer.add_child(detail)
	await physics_frame
	await process_frame
	shooter._enter_windup_state()
	shooter._process_windup_state(0.3)
	await _capture("warning", "ARCHER / COMMITTED AIM", "The existing aimed volley and its timing are unchanged.")
	shooter._enter_fire_state()
	var bullet := _shot(Vector2(-200.0,0.0))
	shooter._process_projectiles(0.3)
	_check(bullet.global_position.is_equal_approx(Vector2(-116.0,0.0)), "Original280px-per-second projectile flight is preserved")
	await _capture("host_flight", "ARCHER / AUTHORITATIVE FLIGHT", "The shot keeps its original size and speed; the host resolves its full traveled segment.")
	var layout: Array[Dictionary] = [{"pos": Vector2.ZERO, "radius":28.0,"type":"column"}]
	room._spawn_room_obstacles(layout)
	renderer.set_obstacle_layout(layout)
	await physics_frame
	await process_frame
	shooter._process_projectiles(0.8)
	_check(shooter.projectiles.is_empty() and actor.get_current_health() == 100, "Real column stops the shot before the protected player during a hitch")
	var marker := Line2D.new()
	marker.position = bullet.global_position
	marker.width = 1.0
	marker.default_color = Color(0.9,0.8,0.5,0.8)
	marker.points = PackedVector2Array([Vector2(-4.0,0.0),Vector2(4.0,0.0),Vector2.ZERO,Vector2(0.0,-4.0),Vector2(0.0,4.0)])
	room.add_child(marker)
	await _capture("cover_stop", "ARCHER / COVER STOPS THE SHOT", "The small cross marks the actual contact. The projectile is gone; the player behind cover is unharmed.")
	marker.hide()
	_shot(Vector2(-120.0,-110.0))
	var packet := shooter.get_projectile_network_sync_state()
	shooter.hide()
	var replica := ARCHER.new()
	room.add_child(replica)
	replica.global_position = shooter.global_position + Vector2(12.0,-8.0)
	replica.set_physics_process(false)
	replica.set_network_simulation_enabled(false)
	# The received-body stand-in is on the other peer in actual play.
	replica.remove_from_group("enemies")
	replica.apply_network_runtime_state(shooter.get_network_runtime_state())
	replica._update_network_facing_lerp(1.0)
	replica.apply_projectile_network_sync_state(packet)
	replica._process_network_visuals(0.1)
	_check(replica.projectiles.size() == 1 and replica.projectiles[0].global_position.is_equal_approx(Vector2(-92.0,-110.0)), "Joiner draws native world-space positions and the host's actual velocity")
	await _capture("joiner_flight", "ARCHER / RECEIVED FLIGHT", "The shot remains in world space while the Archer's body interpolates.")
	actor.ruinous_impact_stacks = 1
	actor.boss_combinations.launch_enemy(shooter,Vector2.UP * 300.0,1)
	shooter._physics_process(0.1)
	replica.global_position = shooter.global_position + Vector2(12.0,-8.0)
	var frozen_packet := shooter.get_projectile_network_sync_state()
	replica.apply_projectile_network_sync_state(frozen_packet)
	replica._process_network_visuals(0.1)
	_check(replica.projectiles[0].global_position == Vector2(-120.0,-110.0), "Joiner extrapolation stops while the host's existing arrows are frozen by Ruinous launch")
	await _capture("frozen", "ARCHER / MATCHING HOST FREEZE", "Ruinous Impact keeps the existing pause in arrow flight; the joiner now shows that same stationary shot.")
	shooter._clear_all_projectiles()
	replica._process_network_visuals(ARCHER.PROJECTILE_VISUAL_LEASE)
	_check(replica.projectiles.is_empty(), "A lost final packet cannot leave a ghost projectile")
	await _capture("expired", "ARCHER / EXPIRED PRESENTATION", "Missing updates expire the projectile; stale packets cannot bring it back.")
	for audio in room.find_children("*","AudioStreamPlayer",true,false):
		audio.stop()
		audio.stream = null
	_clear()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	FileAccess.open(output_directory.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"zoom":zoom,"frames":frames,"failures":failures},"\t"))
	print("[OK] Archer GPU: %d frames, %d failures" % [frames.size(),failures.size()])
	print("ARCHER_PROJECTILE_FRAMES="+output_directory)
	quit(0 if failures.is_empty() else 1)

func _capture(name: String, heading: String, explanation: String) -> void:
	title.text = heading
	detail.text = explanation
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var path := output_directory.path_join(name+".png")
	_check(frame.get_size() == FRAME_SIZE and frame.save_png(path) == OK,"Saved actual GPU frame "+name)
	frames.append({"name":name,"path":path})
	print("[FRAME] "+path)