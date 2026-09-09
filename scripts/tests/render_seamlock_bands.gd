extends "res://scripts/tests/test_seamlock_bands.gd"
## Production Seamlock draw and replica countdown at the actual room-fit zoom.

const RENDERER := preload("res://scripts/world_renderer.gd")
const BUILDER := preload("res://scripts/encounter_profile_builder.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const CAMERA := preload("res://scripts/player_camera.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const FRAME_SIZE := Vector2i(1280, 720)

class RenderPlayer extends "res://scripts/player.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
		arcana_motion.set_process(false)
		boss_combinations.set_process(false)

var frames: Array[Dictionary] = []
var output_directory: String
var camera: CAMERA
var rendered_enemy: Seamlock
var title: Label
var detail: Label

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Seamlock GPU fixture requires isolated user data and an actual GPU")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	output_directory = project_path.path_join("seamlock_band_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	var builder := BUILDER.new()
	var profile := builder._build_apex_seamlock_profile(5)
	var renderer := RENDERER.new()
	renderer.room_size = CONTRACTS.profile_room_size(profile)
	world.add_child(renderer)
	var actor := RenderPlayer.new()
	world.add_child(actor)
	actor.position = Vector2(20.0, -25.0)
	camera = CAMERA.new()
	actor.add_child(camera)
	camera.set_static_mode(Vector2.ZERO)
	camera.set_room_fit_zoom_scale(0.95)
	camera.set_world_bounds(Rect2(-renderer.room_size * 0.5, renderer.room_size))
	camera.global_position = Vector2.ZERO
	camera.zoom = camera.target_zoom
	camera.set_physics_process(false)
	camera.force_update_scroll()
	var layer := CanvasLayer.new()
	world.add_child(layer)
	title = Label.new()
	title.position = Vector2(35.0, 22.0)
	title.add_theme_font_size_override("font_size", 23)
	layer.add_child(title)
	detail = Label.new()
	detail.position = Vector2(35.0, 56.0)
	detail.add_theme_font_size_override("font_size", 16)
	detail.modulate = Color(0.78, 0.86, 0.93)
	layer.add_child(detail)
	var host := _enemy()
	host.position = Vector2(-100.0, 0.0)
	host.hide()
	rendered_enemy = _enemy(true)
	rendered_enemy.position = host.position
	rendered_enemy.target = actor
	await physics_frame
	host._enter_band_attack()
	host._band_windup_left = 0.6
	rendered_enemy._apply_custom_network_runtime_state(host._get_custom_network_runtime_state())
	_check(rendered_enemy._band_windup_left == 0.6 and not rendered_enemy._band_is_active, "Warning frame receives the host's unmodified annuli")
	await _capture("warning", "SEAMLOCK / RECEIVED WARNING", "Yellow marks the coming danger. The player stands in the first safe annulus.")
	_active_band(host, 0.8, 0.4)
	rendered_enemy.apply_projectile_network_sync_state(host.get_projectile_network_sync_state())
	_check(rendered_enemy._band_is_active and is_equal_approx(rendered_enemy._band_duration_left, 0.8), "Active frame receives the exact host lifetime")
	await _capture("active", "SEAMLOCK / RECEIVED ACTIVE BAND", "The same danger annuli turn orange; safe paths and the enemy silhouette remain visible.")
	var before_health := actor.get_current_health()
	rendered_enemy._physics_process(0.9)
	_check(not rendered_enemy._band_is_active and rendered_enemy._band_duration_left == 0.0, "Actual EnemyBase replica physics expires the last received band without a final packet")
	_check(rendered_enemy._spiral_arms.is_empty() and actor.get_current_health() == before_health, "Visual expiry starts no local spiral and deals no local damage")
	await _capture("expired", "SEAMLOCK / FINAL PACKET OMITTED", "After the received lifetime ends, the old bands disappear. No next attack is invented locally.")
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures, "room_size": str(renderer.room_size), "camera_zoom": camera.zoom.x, "scope": "Production draw, real profile room size and PlayerCamera fit; host dictionaries applied through replica APIs. Separate real ENet fixture proves transport; this fixture inspects visual lifetime."}
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	actor.upgrade_system.power_registry.free()
	current_scene = null
	world.free()
	builder.multiplayer_difficulty_config.free()
	builder.free()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Seamlock bands GPU: %d frames, %d failures" % [frames.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture(name: String, heading: String, explanation: String) -> void:
	title.text = heading
	detail.text = explanation
	rendered_enemy.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(name + ".png")
	var frame := root.get_texture().get_image()
	_check(frame.get_size() == FRAME_SIZE and frame.save_png(path) == OK, "Saved actual GPU frame " + name)
	frames.append({"name": name, "path": path, "active": rendered_enemy._band_is_active, "windup": rendered_enemy._band_windup_left, "life": rendered_enemy._band_duration_left, "state": rendered_enemy.seamlock_state, "camera_zoom": camera.zoom.x})
	print("[FRAME] " + path)
