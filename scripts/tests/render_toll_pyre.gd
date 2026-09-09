extends "res://scripts/tests/test_toll_pyre.gd"
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
		push_error("Toll/Pyre fixture requires an actual GPU")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	var zoom := minf(1280.0/1160.0,720.0/860.0)*0.95
	root.canvas_transform = Transform2D(Vector2(zoom,0),Vector2(0,zoom),Vector2(FRAME_SIZE)*0.5)
	output_directory = project_path.path_join("toll_pyre_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	_setup_toll()
	actor.global_position = Vector2(200,170)
	var renderer := RENDERER.new()
	renderer.room_size = room.current_effective_room_size
	room.add_child(renderer)
	var layer := CanvasLayer.new()
	room.add_child(layer)
	title = Label.new()
	title.position = Vector2(35,24)
	title.add_theme_font_size_override("font_size",23)
	layer.add_child(title)
	detail = Label.new()
	detail.position = Vector2(35,58)
	detail.add_theme_font_size_override("font_size",16)
	layer.add_child(detail)
	_begin(180)
	await _capture("full_ring","TOLL / ORIGINAL PULSE BAND","The outer and inner boundaries keep their original reach and thickness.")
	toll._end_pulse()
	toll._pulse_count = 2
	actor.global_position = Vector2(260,0)
	_begin(260)
	actor.global_position = Vector2.RIGHT.rotated(PI/3)*280
	_check(toll._pulse_is_directed and is_inf(TOLL._first_pulse_contact_fraction(actor.global_position,Vector2.ZERO,260,280,64,true,0)),"The visible60-degree gap remains safe")
	await _capture("directed_spokes","TOLL / FIXED DIRECTED SPOKES","The third pulse preserves its three sectors and safe angular gaps.")
	var packet := toll._get_custom_network_runtime_state()
	toll.hide()
	var replica := TOLL.new()
	room.add_child(replica)
	replica.set_physics_process(false)
	replica.set_network_simulation_enabled(false)
	replica.remove_from_group("enemies")
	replica.global_position = Vector2(80,-50)
	replica._apply_custom_network_runtime_state(packet)
	replica._process_network_visuals(0.05)
	_check(replica.get_pulse_geometry().origin == Vector2.ZERO and replica.global_position != Vector2.ZERO,"Received pulse stays at its host anchor while the body interpolates")
	await _capture("received_spokes","TOLL / RECEIVED ANCHOR","The body can move while the pulse remains fixed at the host's arena anchor.")
	replica._process_network_visuals(TOLL.PULSE_VISUAL_LEASE)
	_check(replica.get_pulse_geometry().is_empty(),"Lost final updates expire the pulse")
	await _capture("expired_pulse","TOLL / EXPIRED PULSE","The active pulse is gone. The existing aura and inner sanctum remain visible.")
	replica.hide()
	var field := FIELD.new()
	room.add_child(field)
	field.set_process(false)
	field.initialize(actor,94.0,6.5,0.42,7)
	field._process(0.4)
	await _capture("pyre_active","PYRE / LINGERING FIELD","The field keeps its original expanding footprint and survives its owner's death.")
	field.time_left = 0.01
	field.tick_left = 0.1
	field._process(0.2)
	_check(field.is_queued_for_deletion() and actor.get_current_health() == 100,"Expired field is removed without a late damage tick")
	await _capture("pyre_expired","PYRE / EXPIRED FIELD","The expired field has disappeared and cannot deliver another tick.")
	_clear()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	FileAccess.open(output_directory.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"zoom":zoom,"frames":frames,"failures":failures},"\t"))
	print("[OK] Toll/Pyre GPU: %d frames, %d failures" % [frames.size(),failures.size()])
	print("TOLL_PYRE_FRAMES="+output_directory)
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