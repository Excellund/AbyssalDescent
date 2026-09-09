extends "res://scripts/tests/test_live_arena_edges.gd"

const TETHER := preload("res://scripts/enemy_tether.gd")
const RENDERER := preload("res://scripts/world_renderer.gd")
const FRAME_SIZE := Vector2i(1280, 720)
var frames: Array[Dictionary] = []
var output_directory: String
var title: Label
var detail: Label
var first: TETHER
var partner: TETHER

func _tether(position: Vector2, network_id: int) -> TETHER:
	var enemy := TETHER.new()
	_circle(enemy, 14.0)
	room.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = position
	enemy.set_meta("network_enemy_id", network_id)
	enemy.move_speed = 0.0
	enemy.crowd_separation_strength = 0.0
	return enemy

func _setup_pair() -> void:
	_setup()
	first = _tether(Vector2(-200.0, 0.0), 901)
	partner = _tether(Vector2(200.0, 0.0), 902)
	first.beam_partner = partner
	partner.beam_partner = first

class Markers extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2(80.0, 23.0), 3.0, Color.ORANGE)
		draw_circle(Vector2(80.0, 33.0), 3.0, Color.SKY_BLUE, false, 1.5)

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Tether GPU fixture requires isolated user data")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Tether GPU fixture requires an actual GPU")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	var zoom := minf(1280.0 / 1160.0, 720.0 / 860.0) * 0.95
	root.canvas_transform = Transform2D(Vector2(zoom, 0.0), Vector2(0.0, zoom), Vector2(FRAME_SIZE) * 0.5)
	output_directory = project_path.path_join("tether_hazard_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	_setup_pair()
	var renderer := RENDERER.new()
	renderer.room_size = room.current_effective_room_size
	room.add_child(renderer)
	var layer := CanvasLayer.new()
	room.add_child(layer)
	title = Label.new()
	title.position = Vector2(35.0, 24.0)
	title.add_theme_font_size_override("font_size", 23)
	layer.add_child(title)
	detail = Label.new()
	detail.position = Vector2(35.0, 58.0)
	detail.add_theme_font_size_override("font_size", 16)
	detail.modulate = Color(0.75, 0.85, 0.92)
	layer.add_child(detail)
	var markers := Markers.new()
	markers.z_index = 200
	room.add_child(markers)
	actor.global_position = Vector2(-50.0, 20.0)
	first.target = actor
	first.target_candidates = [actor]
	first.visual_facing_direction = Vector2.RIGHT
	partner.visual_facing_direction = Vector2.LEFT
	await physics_frame
	first._enter_windup_state()
	first._process_windup(0.45)
	_check(first.get_beam_polygons().size() == 1, "Warning includes the full accepted capsule")
	await _capture("warning", "TETHER / FULL BEAM WARNING", "The bright core sits inside the full 24px danger radius, including rounded endpoints.")
	first._process_windup(first.beam_windup_time)
	var before: int = actor.health_state.current_health
	first._process_beam(0.02)
	_check(actor.health_state.current_health == before - first.beam_damage, "Real player20px from center receives the shown area damage")
	await create_timer(0.7).timeout
	await _capture("active", "TETHER / ACTIVE AREA", "The player and orange marker are inside the damage boundary. The blue marker is outside.")
	var expected := first.get_beam_geometry()
	var packet := first.get_projectile_network_sync_state()
	first.hide()
	var remote := _tether(first.global_position + Vector2(12.0, -8.0), 905)
	remote.set_network_simulation_enabled(false)
	remote.apply_projectile_network_sync_state(packet)
	_check(remote.get_beam_geometry() == expected, "Received capsule stays at the host endpoints while bodies interpolate")
	await _capture("joiner_active", "TETHER / RECEIVED AREA", "One host-owned capsule keeps its world position while the joiner's enemy body interpolates.")
	remote._process_network_visuals(TETHER.BEAM_VISUAL_LEASE + 0.01)
	_check(remote.get_beam_geometry().is_empty(), "Dropped final update cannot leave an active beam")
	markers.hide()
	await _capture("expired", "TETHER / EXPIRED BEAM", "The hazard clears when its update lease expires. The pair's dim idle link is harmless.")
	remote.apply_projectile_network_sync_state(first.get_projectile_network_sync_state())
	partner.health_state.take_damage(partner.health_state.current_health)
	_check(remote.get_beam_geometry().is_empty(), "Partner death immediately removes the received hazard")
	await _capture("partner_removed", "TETHER / PARTNER REMOVED", "Losing an endpoint clears the beam. A replacement pair must complete a new warning.")
	for audio in room.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	_clear()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "zoom": zoom, "frames": frames, "failures": failures}, "\t"))
	print("[OK] Tether GPU: %d frames, %d failures" % [frames.size(), failures.size()])
	print("TETHER_HAZARD_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)

func _capture(name: String, heading: String, explanation: String) -> void:
	title.text = heading
	detail.text = explanation
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var path := output_directory.path_join(name + ".png")
	_check(frame.get_size() == FRAME_SIZE and frame.save_png(path) == OK, "Saved actual GPU frame " + name)
	frames.append({"name": name, "path": path})
	print("[FRAME] " + path)
