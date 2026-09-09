extends "res://scripts/tests/test_live_arena_edges.gd"
## Production room renderer and power effects at the room's actual fit zoom.

const RENDERER := preload("res://scripts/world_renderer.gd")
const FEEDBACK := preload("res://scripts/ruinous_impact_feedback.gd")
const FRAME_SIZE := Vector2i(1280, 720)

class VisibleEnemy extends "res://scripts/enemy_chaser.gd":
	func _ready() -> void:
		max_health = 10000
		super._ready()
		set_physics_process(false)

class RemoteActor extends Actor:
	func _is_local_control_owner() -> bool:
		return false

var output_directory: String
var frames: Array[Dictionary] = []
var title: Label
var detail: Label

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Live edge GPU fixture requires isolated user data")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Live edge GPU fixture requires an actual GPU")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	var zoom := minf(1280.0 / 1160.0, 720.0 / 860.0) * 0.95
	root.canvas_transform = Transform2D(Vector2(zoom, 0.0), Vector2(0.0, zoom), Vector2(FRAME_SIZE) * 0.5)
	output_directory = project_path.path_join("live_arena_edge_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _crescent_frames()
	await _ruinous_frame()
	await _blast_frame()
	await _orbit_frame()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await create_timer(0.1).timeout
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "zoom": zoom, "frames": frames, "failures": failures}
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[OK] Live arena edge GPU: %d frames, %d failures" % [frames.size(), failures.size()])
	print("LIVE_ARENA_EDGE_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)

func _prepare() -> void:
	_setup()
	var renderer := RENDERER.new()
	renderer.room_size = room.current_effective_room_size
	room.add_child(renderer)
	renderer.z_index = -5
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

func _capture(name: String, heading: String, explanation: String) -> void:
	title.text = heading
	detail.text = explanation
	actor.arcana_motion.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and frame.get_size() == FRAME_SIZE, "GPU frame uses the requested resolution")
	var path := output_directory.path_join(name + ".png")
	_check(frame.save_png(path) == OK, "Saved live edge frame " + name)
	frames.append({"name": name, "path": path, "position": str(actor.global_position), "motion": actor.arcana_motion.motion})
	print("[FRAME] " + path)

func _visible_enemy(position: Vector2) -> VisibleEnemy:
	var target := VisibleEnemy.new()
	_circle(target, 13.0)
	room.add_child(target)
	target.global_position = position
	target.target = actor
	return target

func _release_room() -> void:
	for audio in room.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	_clear()
	await process_frame

func _crescent_frames() -> void:
	await _prepare()
	actor.global_position = Vector2(500.0, 0.0)
	for _index in range(3):
		actor.apply_trial_power("returning_crescent")
	actor.returning_crescent.try_launch(Vector2.RIGHT)
	for _index in range(10):
		actor.returning_crescent.tick(0.015)
	var blade := actor.returning_crescent.blades[0]
	_check(blade.position.x < 580.0 and blade.bounces_left == 0 and blade.direction.x < 0.0, "Visible owner blade reflects at the live room edge")
	await _capture("crescent_owner_edge", "RETURNING CRESCENT / OWNER ROOM-EDGE RICOCHET", "The blade turns at the arena border and spends its existing outbound travel. No physical wall was added.")
	var payload := actor.returning_crescent.build_network_state().duplicate(true)
	actor.hide()
	actor.returning_crescent.cancel()
	var remote := RemoteActor.new()
	_circle(remote, 14.0)
	room.add_child(remote)
	remote.global_position = actor.global_position
	remote.arcana_motion.set_process(false)
	remote.boss_combinations.set_process(false)
	remote.returning_crescent.set_physics_process(false)
	remote.returning_crescent.apply_network_state(payload)
	remote.returning_crescent.tick(0.015)
	_check(remote.returning_crescent.blades.size() == 1 and remote.returning_crescent.blades[0].bounces_left == 0 and remote.returning_crescent.blades[0].position.x <= 580.0, "Remote visual prediction honors the same clipped ricochet")
	await _capture("crescent_remote_edge", "RETURNING CRESCENT / RECEIVED ROOM-EDGE RICOCHET", "The received blade continues inward with its bounce consumed. Replica presentation applies no damage.")
	if is_instance_valid(remote.upgrade_system.power_registry):
		remote.upgrade_system.power_registry.free()
	remote.free()
	await _release_room()

func _ruinous_frame() -> void:
	await _prepare()
	actor.global_position = Vector2(400.0, 0.0)
	actor.ruinous_impact_stacks = 1
	var target := _visible_enemy(Vector2(550.0, 0.0))
	await physics_frame
	actor.boss_combinations.launch_enemy(target, Vector2.RIGHT * 750.0, 1)
	var feedback: FEEDBACK = EnemyReplicationService._ruinous_feedback
	feedback.set_process(false)
	feedback._impact_sound.stream = null
	target.get_launch_state().step(target, 0.20)
	_check(target.global_position == Vector2(580.0, 0.0) and feedback.bursts.size() == 1 and feedback.launches.is_empty(), "Real Ruinous launch ends at the visible edge with one burst")
	feedback.bursts[0]["left"] = FEEDBACK.BURST_LIFETIME - 0.055
	feedback.queue_redraw()
	await _capture("ruinous_room_edge", "RUINOUS IMPACT / ARENA BORDER", "The launch ends exactly at the border. One burst replaces its launch cue at that same position.")
	await _release_room()

func _blast_frame() -> void:
	await _prepare()
	actor.global_position = Vector2(550.0, 0.0)
	actor.apply_trial_power("blast_drive")
	actor.arcana_motion.tick(0.0)
	actor.arcana_motion.release_blast(1.0)
	actor.arcana_motion.process_movement(0.10, Vector2.ZERO)
	_check(actor.global_position == Vector2(580.0, 0.0) and actor.arcana_motion.motion == MOTION.Motion.NONE, "Real Blast recoil stops at first perimeter contact")
	_check(actor.arcana_motion._blast_effects.back().global_position == Vector2(550.0, 0.0), "The blast remains at its accepted firing origin")
	await _capture("blast_room_edge", "BLAST DRIVE / RECOIL STOPS AT THE BORDER", "The player stops on contact; the forward blast stays at the firing position. Dash immunity is unchanged.")
	await _release_room()

func _orbit_frame() -> void:
	await _prepare()
	var anchor := _visible_enemy(Vector2(560.0, 0.0))
	actor.global_position = Vector2(560.0, -70.2)
	actor.apply_trial_power("razor_orbit")
	actor.dash_direction = Vector2.RIGHT
	await physics_frame
	actor.arcana_motion.start_orbit(anchor)
	for _index in range(8):
		if actor.arcana_motion.motion == MOTION.Motion.NONE:
			break
		actor.arcana_motion.process_movement(STEP, Vector2.ZERO)
	_check(actor.arcana_motion.motion == MOTION.Motion.NONE and actor.arcana_motion.anchor == null and actor.global_position.x <= 580.0, "The live perimeter detaches Orbit without residual carry")
	_check(not bool(actor.arcana_motion._visual.get("orbit", false)), "Boundary detachment clears the drawn tether immediately")
	await _capture("orbit_room_edge", "RAZOR ORBIT / BORDER DETACHMENT", "The player reaches the border and releases the anchor. No tether or carry remains past the collision.")
	await _release_room()
