extends "res://scripts/tests/test_breakwater_runtime.gd"
## Actual room, route door and enemy at normal room-fit combat zoom.

const RENDERER := preload("res://scripts/world_renderer.gd")
const BUILDER := preload("res://scripts/encounter_profile_builder.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const FRAME_SIZE := Vector2i(1280, 720)

var output_directory: String
var frames: Array[Dictionary] = []
var title: Label
var detail: Label
var renderer: RENDERER

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Breakwater GPU fixture requires isolated user data")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Breakwater GPU fixture requires an actual GPU")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	var zoom := minf(1280.0 / 1160.0, 720.0 / 860.0) * 0.95
	root.canvas_transform = Transform2D(Vector2(zoom, 0.0), Vector2(0.0, zoom), Vector2(FRAME_SIZE) * 0.5)
	output_directory = project_path.path_join("breakwater_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _route_frame()
	await _combat_frames()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "zoom": zoom, "frames": frames, "failures": failures}
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[OK] Breakwater GPU: %d frames, %d failures" % [frames.size(), failures.size()])
	print("BREAKWATER_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)

func _prepare() -> void:
	_setup()
	renderer = RENDERER.new()
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

func _capture(name: String, heading: String, explanation: String, boss: Apex = null) -> void:
	title.text = heading
	detail.text = explanation
	if boss != null:
		boss.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and frame.get_size() == FRAME_SIZE, "GPU frame uses the requested resolution")
	var path := output_directory.path_join(name + ".png")
	_check(frame.save_png(path) == OK, "Saved Breakwater frame " + name)
	frames.append({"name": name, "path": path, "phase": boss.phase if boss != null else -1, "origin": str(boss.charge_origin) if boss != null else "", "endpoint": str(boss.charge_end) if boss != null else ""})
	print("[FRAME] " + path)

func _release_room() -> void:
	for audio in room.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
		audio.stream = null
	_clear()
	await process_frame

func _route_frame() -> void:
	await _prepare()
	var builder := BUILDER.new()
	var profile := builder._build_apex_breakwater_profile(5)
	var mutator := CONTRACTS.profile_enemy_mutator(profile)
	var door := CONTRACTS.apex_trial_door_option(profile, "Apex Breakwater", CONTRACTS.mutator_theme_color(mutator, Color.ORANGE))
	CONTRACTS.door_option_set_position(door, Vector2(170.0, -80.0))
	var alternative := CONTRACTS.rest_door_option()
	CONTRACTS.door_option_set_position(alternative, Vector2(-230.0, -80.0))
	renderer.choosing_next_room = true
	renderer.door_options = [alternative, door]
	actor.global_position = Vector2(170.0, 10.0)
	renderer.player_global_position = actor.global_position
	_check(CONTRACTS.mutator_icon_shape_id(mutator) == "breakwater", "The actual Apex profile selects its arrow-meets-wall route glyph")
	_check(CONTRACTS.door_identity_label(door).contains("Breakwater"), "The actual route label preserves the new Apex identity")
	await create_timer(0.65).timeout
	await _capture("route_door", "APEX BREAKWATER / OPTIONAL ROUTE", "The existing route presents its own wall-impact glyph, Apex label and Arcana reward.")
	builder.multiplayer_difficulty_config.free()
	builder.free()
	await _release_room()

func _combat_frames() -> void:
	await _prepare()
	actor.global_position = Vector2(515.0, -90.0)
	var boss := _apex(Vector2(-90.0, -90.0))
	await physics_frame
	boss._begin_tracking()
	_check(boss.charge_end == Vector2(580.0, -90.0), "Tracking marks the actual room-center edge")
	await _capture("tracking", "BREAKWATER / AIM TRACKING", "The first 0.35 seconds track the player. The capsule includes the full danger width and rounded ends.", boss)
	boss._process_behavior(BREAKWATER.TRACK_TIME)
	actor.global_position = Vector2(450.0, 90.0)
	await _capture("locked", "BREAKWATER / DIRECTION LOCKED", "The final 0.55 seconds hold the same endpoint and direction while the player leaves the lane.", boss)
	var packet := boss._get_custom_network_runtime_state().duplicate(true)
	var origin := boss.charge_origin
	var endpoint := boss.charge_end
	boss.hide()
	var remote := _apex(Vector2(-72.0, -81.0))
	remote.set_network_simulation_enabled(false)
	remote.set_physics_process(false)
	remote._apply_custom_network_runtime_state(packet)
	_check(remote.charge_origin == origin and remote.charge_end == endpoint and remote.get_warning_polygons() == boss.get_warning_polygons(), "Received warning keeps the exact host capsule despite interpolated body position")
	await _capture("joiner_locked", "BREAKWATER / RECEIVED LOCKED WARNING", "The joiner's warning stays at the host's accepted world positions while the enemy body interpolates.", remote)
	remote.free()
	boss.show()
	boss._process_behavior(BREAKWATER.LOCK_TIME)
	boss._process_behavior(0.60)
	_check(boss.phase == BREAKWATER.Phase.CHARGE and boss.global_position.x > origin.x, "The actual charge advances along its finite locked path")
	await _capture("charge", "BREAKWATER / COMMITTED CHARGE", "The Apex travels straight through the vacated lane. Baiting a wall prevents the returning tide.", boss)
	boss._process_behavior(1.0)
	_check(boss.wall_recovery and boss.global_position == endpoint and boss.phase_left == BREAKWATER.WALL_RECOVERY, "Real room contact begins the full harmless punish window")
	boss._impact_left = BREAKWATER.IMPACT_DURATION - 0.055
	actor.global_position = endpoint + Vector2(-65.0, 60.0)
	await _capture("wall_impact", "BREAKWATER / WALL IMPACT", "The shoulder plates open and the core changes color. Short fragments mark contact without suggesting an explosion.", boss)
	boss._process_behavior(0.4)
	_check(boss._impact_left == 0.0 and boss.wall_recovery and boss.get_warning_polygons().is_empty(), "The harmless open posture remains after contact fragments end")
	await _capture("punish_window", "BREAKWATER / OPEN PUNISH WINDOW", "The stationary open posture lasts through the remaining recovery; ordinary attacks remain effective throughout.", boss)
	boss._cancel_attack()
	boss.global_position = Vector2(-220.0, 0.0)
	actor.global_position = Vector2(-20.0, 0.0)
	boss._begin_tracking()
	boss._process_behavior(BREAKWATER.TRACK_TIME)
	actor.global_position = Vector2(-20.0, 90.0)
	boss._process_behavior(BREAKWATER.LOCK_TIME)
	boss._process_behavior(1.0)
	_check(not boss.wall_recovery, "The center bait finishes without a wall impact")
	boss._process_behavior(BREAKWATER.MISS_RECOVERY)
	_check(boss.phase == BREAKWATER.Phase.BACKWASH, "The real missed charge creates its returning tide")
	boss._process_behavior(BREAKWATER.BACKWASH_TIME * 0.45)
	await _capture("backwash", "BREAKWATER / BRACING THE TIDE", "The ram lane becomes a calm wake. Step into it or outside the broad returning wave before the brace releases.", boss)
	var backwash_packet := boss._get_custom_network_runtime_state()
	boss.hide()
	var backwash_replica := _apex(boss.global_position + Vector2(28.0, 14.0))
	backwash_replica.set_network_simulation_enabled(false)
	backwash_replica._apply_custom_network_runtime_state(backwash_packet)
	_check(backwash_replica.get_warning_polygons() == boss.get_warning_polygons(), "Backwash replica preserves the exact host wave while its body interpolates")
	await _capture("joiner_backwash", "BREAKWATER / RECEIVED TIDE WARNING", "The same committed wave lobes and calm wake reach the joiner, independently of body interpolation.", backwash_replica)
	backwash_replica.free()
	boss.show()
	actor.global_position = boss.global_position + Vector2(-95.0, 0.0)
	var health_before := actor.get_current_health()
	boss._process_behavior(BREAKWATER.BACKWASH_TIME)
	boss._process_behavior(0.4)
	_check(actor.get_current_health() == health_before and boss.phase == BREAKWATER.Phase.TIDE, "The real moving wave preserves the calm wake")
	await _capture("return_tide", "BREAKWATER / RETURN TIDE", "The crest travels back along both sides of the vacated ram lane. The clear wake remains safe.", boss)
	boss._process_behavior(0.65)
	await _capture("return_tide_late", "BREAKWATER / CREST PASSES", "The wave passes instead of exploding. Crossing into the vacated lane gives time to approach the braced foe.", boss)
	boss._process_behavior(10.0)
	_check(actor.get_current_health() == health_before and boss.get_warning_polygons().is_empty(), "The calm wake survives the full tide and its danger clears")
	await _capture("backwash_recovery", "BREAKWATER / SPENT TIDE", "The sea wall opens into a full 1.1-second stationary punish window. A terrain bait still breaks the tide entirely.", boss)
	await _release_room()
