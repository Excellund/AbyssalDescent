extends "res://scripts/tests/test_boss_charge.gd"
## Real host and replica warnings at normal boss-room combat zoom.

const RENDERER := preload("res://scripts/world_renderer.gd")
const FRAME_SIZE := Vector2i(1280, 720)
var output_directory: String
var frames: Array[Dictionary] = []
var title: Label
var detail: Label

class BoundaryMarkers extends Node2D:
	var inside: Vector2
	var outside: Vector2
	func _draw() -> void:
		draw_circle(inside, 5.0, Color(1.0, 0.6, 0.3))
		draw_circle(outside, 5.0, Color(0.4, 0.85, 1.0), false, 2.0)

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Boss charge GPU fixture requires isolated user data")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Boss charge GPU fixture requires an actual GPU")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	var zoom := minf(1280.0 / 1160.0, 720.0 / 860.0) * 0.95
	root.canvas_transform = Transform2D(Vector2(zoom, 0.0), Vector2(0.0, zoom), Vector2(FRAME_SIZE) * 0.5)
	output_directory = project_path.path_join("boss_charge_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	for kind in ["warden", "lacuna"]:
		await _combat_frames(kind)
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "zoom": zoom, "frames": frames, "failures": failures}
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[OK] Boss charge GPU: %d frames, %d failures" % [frames.size(), failures.size()])
	print("BOSS_CHARGE_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)

func _prepare() -> void:
	_setup()
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
	await physics_frame

func _capture(name: String, heading: String, explanation: String, boss: Variant) -> void:
	title.text = heading
	detail.text = explanation
	boss.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and frame.get_size() == FRAME_SIZE, "GPU frame uses the requested resolution")
	var path := output_directory.path_join(name + ".png")
	_check(frame.save_png(path) == OK, "Saved boss charge frame " + name)
	frames.append({"name": name, "path": path, "warning": str(boss.get_charge_warning_geometry())})
	print("[FRAME] " + path)

func _combat_frames(kind: String) -> void:
	await _prepare()
	actor.global_position = Vector2(290.0, 0.0)
	var boss: Variant = _boss(kind, Vector2(-230.0 if kind == "warden" else -100.0, 0.0))
	await physics_frame
	_start_warning(boss, kind)
	var original: Dictionary = boss.get_charge_warning_geometry()
	actor.global_position = Vector2(290.0, 150.0)
	if kind == "warden":
		boss._process_telegraph_state(0.15)
		_check(boss.get_charge_warning_geometry() == original, "Warden keeps its existing early direction commitment")
	else:
		boss._process_windup_state(0.15)
		_check((boss.get_charge_warning_geometry()["direction"] as Vector2).distance_to(original["direction"]) > 0.1, "Lacuna retains its tracking windup")
		boss._sync_attack_overlay()
	var geometry: Dictionary = boss.get_charge_warning_geometry()
	var direction: Vector2 = geometry["direction"]
	var tip: Vector2 = geometry["end"] + direction * (float(geometry["front"]) + float(geometry["radius"]))
	var markers := BoundaryMarkers.new()
	markers.inside = tip - direction * 3.0
	markers.outside = tip + direction * 15.0
	markers.z_index = 220
	room.add_child(markers)
	_check(boss._charge_motion.contains_contact(markers.inside, geometry["origin"], geometry["end"]), "Orange marker is inside the accepted swept capsule")
	_check(not boss._charge_motion.contains_contact(markers.outside, geometry["origin"], geometry["end"]), "Blue marker is outside the accepted swept capsule")
	await _capture(kind + "_host", kind.to_upper() + " / FULL CHARGE WARNING", "The rounded warning includes the real front and rear contact reach. Orange is inside; blue is outside.", boss)
	var packet: Dictionary = boss.get_projectile_network_sync_state().duplicate(true)
	var runtime: Dictionary = boss._get_custom_network_runtime_state().duplicate(true)
	var polygons: Array[PackedVector2Array] = boss.get_charge_warning_polygons()
	boss.hide()
	if kind == "lacuna":
		boss._attack_overlay.hide()
	var remote: Variant = _boss(kind, Vector2(40.0, -80.0))
	remote.set_network_simulation_enabled(false)
	remote.set_physics_process(false)
	remote._apply_custom_network_runtime_state(runtime)
	remote.apply_projectile_network_sync_state(packet)
	remote.global_position = boss.global_position + Vector2(16.0, -9.0)
	if kind == "lacuna":
		remote._sync_attack_overlay()
	_check(remote.get_charge_warning_geometry() == geometry and remote.get_charge_warning_polygons() == polygons, "Replica warning is identical to the host despite body interpolation")
	await _capture(kind + "_joiner", kind.to_upper() + " / RECEIVED WARNING", "The joiner uses the host's world capsule, even while its enemy body is offset by interpolation.", remote)
	remote._process_network_visuals(CHARGE.LEASE_SECONDS + 0.02)
	_check(remote.get_charge_warning_polygons().is_empty(), "Lost final state cannot leave a permanent charge warning")
	if kind == "lacuna":
		remote._sync_attack_overlay()
		_check(not remote._attack_overlay.telegraph_active and remote._attack_overlay.get_sever_polygons().is_empty(), "Expired Lacuna warning clears its independent overlay")
	markers.hide()
	await _capture(kind + "_expired", kind.to_upper() + " / WARNING LEASE EXPIRED", "A missing final packet clears the warning; a stale body phase cannot draw it again.", remote)
	for audio in room.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	_clear()
	await process_frame
