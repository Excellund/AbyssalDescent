extends "res://scripts/tests/test_live_arena_edges.gd"
## Actual controller and camera at normal arena fit; no production input override.

const CAMERA := preload("res://scripts/player_camera.gd")
const RENDERER := preload("res://scripts/world_renderer.gd")
const DEFINITIONS := preload("res://scripts/shared/encounter_definition_data.gd")
const CHARACTER := preload("res://scripts/character_registry.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
const FRAME_SIZE := Vector2i(1280, 720)

class VisibleEnemy extends "res://scripts/enemy_chaser.gd":
	func _ready() -> void:
		max_health = 10000
		super._ready()
		set_physics_process(false)

var output_directory: String
var frames: Array[Dictionary] = []
var title: Label
var detail: Label
var retirement := AUDIO_RETIREMENT.new()
var camera: CAMERA

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Orbit GPU fixture requires an isolated real renderer")
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	output_directory = ProjectSettings.globalize_path("res://orbit_duration_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	_setup()
	room.current_room_size = DEFINITIONS.POOL_ROOM_SIZE
	room.current_effective_room_size = room.current_room_size
	var renderer := RENDERER.new()
	renderer.room_size = room.current_effective_room_size
	room.add_child(renderer)
	actor.apply_character_package(CHARACTER.get_character("bastion"))
	actor.apply_trial_power("razor_orbit")
	actor.apply_trial_power("blast_drive")
	actor.global_position = Vector2(-70.0, 0.0)
	actor.dash_direction = Vector2.RIGHT
	actor.aim = Vector2.RIGHT
	camera = CAMERA.new()
	actor.add_child(camera)
	camera.set_world_bounds(Rect2(-room.current_effective_room_size * 0.5, room.current_effective_room_size))
	camera.set_static_mode(Vector2.ZERO)
	camera.global_position = Vector2.ZERO
	camera.zoom = camera.target_zoom
	camera.set_physics_process(false)
	camera.force_update_scroll()
	var anchor := VisibleEnemy.new()
	_circle(anchor, 13.0)
	room.add_child(anchor)
	anchor.position = Vector2.ZERO
	var charger := preload("res://scripts/enemy_charger.gd").new()
	_circle(charger, 14.0)
	room.add_child(charger)
	charger.set_physics_process(false)
	charger.position = Vector2(-285.0, 115.0)
	charger.target = actor
	charger._enter_windup_state()
	charger.charger_charge_direction = Vector2.RIGHT
	charger.visual_facing_direction = Vector2.RIGHT
	var layer := CanvasLayer.new()
	room.add_child(layer)
	title = Label.new()
	title.position = Vector2(32.0, 20.0)
	title.add_theme_font_size_override("font_size", 23)
	layer.add_child(title)
	detail = Label.new()
	detail.position = Vector2(32.0, 53.0)
	detail.add_theme_font_size_override("font_size", 16)
	layer.add_child(detail)
	await physics_frame
	Input.action_press("dash")
	actor.arcana_motion.start_orbit(anchor)
	_check(actor.arcana_motion.motion == MOTION.Motion.ORBIT, "Real controller owns initial Orbit")
	_check(is_equal_approx(actor.arcana_motion.get_orbit_seconds_left(), actor.arcana_motion.orbit_limit), "Full countdown matches the actual duration")
	await _capture("full", "RAZOR ORBIT / FULL DURATION", "The time cue is read at the normal camera fit with a nearby enemy warning.")
	await _advance(actor.arcana_motion.orbit_limit * 0.5)
	_check(actor.arcana_motion.motion == MOTION.Motion.ORBIT, "Halfway frame retains the real anchor")
	await _capture("middle", "RAZOR ORBIT / HALF REMAINING", "The timer changes while the tether and enemy warning preserve their shapes.")
	await _advance(maxf(0.0, actor.arcana_motion.orbit_limit - actor.arcana_motion.orbit_elapsed - 0.25))
	Input.action_press("attack")
	actor.arcana_motion.charge_hold = MOTION.FULL_CHARGE_TIME
	actor.arcana_motion._publish_state()
	_check(actor.arcana_motion.orbit_limit - actor.arcana_motion.orbit_elapsed <= 0.35, "Expiry frame is within the final 0.35 seconds")
	await _capture("expiring", "RAZOR ORBIT / ABOUT TO RELEASE", "A charged Blast shares the player footprint; the time and tangent cue must remain distinct.")
	# Drop only the fixture's staged charge; automatic Orbit expiry drives release.
	actor.arcana_motion.charge_hold = -1.0
	Input.action_release("attack")
	await _advance(maxf(0.0, actor.arcana_motion.orbit_limit - actor.arcana_motion.orbit_elapsed) + 0.04)
	_check(actor.arcana_motion.motion == MOTION.Motion.CARRY, "The release frame uses actual tangential carry")
	_check(actor.arcana_motion.get_orbit_seconds_left() < 0.0 and actor.arcana_motion._orbit_hint_left > 0.0, "Real release replaces the timer with a short departure cue")
	await _capture("released", "RAZOR ORBIT / TANGENTIAL RELEASE", "The tether has ended and the player travels along the actual departure direction.")
	actor.arcana_motion.cancel()
	Input.action_release("dash")
	await _capture("cleared", "RAZOR ORBIT / ACTION CLEARED", "Cancellation clears the motion presentation without leaving a false timer.")
	_check(actor.arcana_motion.get_orbit_seconds_left() < 0.0 and actor.arcana_motion._orbit_hint_left <= 0.0, "Cancellation clears both the timer and departure cue")
	actor.global_position = Vector2(-70.0, 0.0)
	actor.arcana_motion.start_orbit(anchor)
	room.current_effective_room_size = Vector2(60.0, 60.0)
	room._keep_player_inside_current_room()
	_check(actor.arcana_motion.get_orbit_seconds_left() < 0.0 and actor.arcana_motion._orbit_hint_left <= 0.0, "Actual room clamp cancels without a false departure cue")
	_clear()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Native audio retires before renderer exit")
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures}, "\t"))
	print("[OK] Orbit duration GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _advance(duration: float) -> void:
	var remaining := duration
	while remaining > 0.00001:
		var delta := minf(STEP, remaining)
		actor.arcana_motion.tick(delta)
		actor.arcana_motion.process_movement(delta, Vector2.ZERO)
		actor.arcana_motion._process(delta)
		remaining -= delta
		await physics_frame
	actor.arcana_motion._publish_state()

func _capture(name: String, heading: String, explanation: String) -> void:
	title.text = heading
	detail.text = explanation
	actor.arcana_motion.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := output_directory.path_join(name + ".png")
	_check(picture.save_png(path) == OK, "Saved " + name)
	frames.append({"name": name, "path": path, "zoom": camera.zoom.x, "remaining": maxf(0.0, actor.arcana_motion.orbit_limit - actor.arcana_motion.orbit_elapsed), "motion": actor.arcana_motion.motion, "visual": actor.arcana_motion._visual.duplicate(true)})
	print("[FRAME] " + path)