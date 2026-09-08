extends SceneTree
## GPU fixture: real combat/effect/render scripts, synthetic in-process actions.
## Run only through render_motion_arcana.ps1 in a disposable validation project.

const MOTION := preload("res://scripts/arcana_motion_controller.gd")
const CHARACTER := preload("res://scripts/character_registry.gd")
const RENDERER := preload("res://scripts/world_renderer.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const FRAME_SIZE := Vector2i(1280, 720)
const STEP := 1.0 / 60.0

class RenderPlayer extends "res://scripts/player.gd":
	var aim_point := Vector2(120.0, 0.0)
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _get_mouse_attack_direction() -> Vector2:
		return (aim_point - global_position).normalized()
	func _read_movement_direction() -> Vector2:
		return Vector2.ZERO
	func _notification(_what: int) -> void:
		# The fixture's offscreen window intentionally cannot acquire OS focus.
		pass

class RenderMotion extends "res://scripts/arcana_motion_controller.gd":
	var aimed_anchor: Node2D
	func find_anchor(_cursor: Vector2, _enemies_only: bool = false) -> Node2D:
		# Geometry/LOS selection is exercised separately by test_arcana_motion.gd.
		return aimed_anchor if is_instance_valid(aimed_anchor) else null

class RenderEnemy extends "res://scripts/enemy_chaser.gd":
	func _ready() -> void:
		max_health = 10000
		super._ready()
		set_physics_process(false)

class RenderWorld extends Node2D:
	var current_effective_room_size := Vector2(1180.0, 580.0)
	var damage_recorded := 0
	func record_player_damage_dealt(amount: int, _peer_id: int = 0, _killed: bool = false, _enemy_id: int = 0) -> void:
		damage_recorded += amount

var world: RenderWorld
var player: RenderPlayer
var title_label: Label
var detail_label: Label
var output_directory: String
var failures: Array[String] = []
var frames: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("GPU fixtures require an isolated validation project")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("GPU fixtures require a real renderer, not the headless dummy driver")
		quit(1)
		return
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	root.canvas_transform = Transform2D(0.0, Vector2(FRAME_SIZE) * 0.5 + Vector2(0.0, 25.0))
	output_directory = project_path.path_join("motion_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	await _blast_frames()
	await _orbit_frames(false)
	await _orbit_frames(true)
	await _combined_frames()
	await _boss_frames()
	await _release_actions()
	# Let the audio thread finish releasing stopped WAV playback resources before
	# this short-lived process exits; no production sound behavior is replaced.
	await create_timer(0.2).timeout
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	var manifest := {
		"size": [FRAME_SIZE.x, FRAME_SIZE.y],
		"gpu": RenderingServer.get_video_adapter_name(),
		"frames": frames, "failures": failures,
		"scope": "Isolated real Player, motion controller, Chaser and arena renderer; deterministic local actions; no live co-op.",
	}
	var file := FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("[OK] Motion GPU fixture: %d frames, %d failures" % [frames.size(), failures.size()])
	print("MOTION_FRAMES=" + output_directory)
	quit(0 if failures.is_empty() else 1)

func _make_world() -> void:
	world = RenderWorld.new()
	root.add_child(world)
	current_scene = world
	var renderer := RENDERER.new()
	renderer.room_size = world.current_effective_room_size
	world.add_child(renderer)
	var columns: Array[Dictionary] = [
		{"pos": Vector2(-390.0, -180.0), "radius": 28.0},
		{"pos": Vector2(380.0, -180.0), "radius": 28.0},
		{"pos": Vector2(-390.0, 185.0), "radius": 28.0},
		{"pos": Vector2(380.0, 185.0), "radius": 28.0},
	]
	renderer.set_obstacle_layout(columns)
	for column in columns:
		_add_column(column["pos"], float(column["radius"]))
	player = RenderPlayer.new()
	player.name = "Player"
	player.add_to_group("player")
	_add_shape(player, 14.0)
	player.position = Vector2(-150.0, 0.0)
	world.add_child(player)
	player.apply_character_package(CHARACTER.get_character("bastion"))
	player.arcana_motion.free()
	player.arcana_motion = RenderMotion.new()
	player.add_child(player.arcana_motion)
	player.arcana_motion.initialize(player)
	player.arcana_motion.set_process(false)
	var layer := CanvasLayer.new()
	world.add_child(layer)
	title_label = Label.new()
	title_label.position = Vector2(36.0, 18.0)
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0))
	layer.add_child(title_label)
	detail_label = Label.new()
	detail_label.position = Vector2(36.0, 53.0)
	detail_label.add_theme_font_size_override("font_size", 16)
	detail_label.add_theme_color_override("font_color", Color(0.67, 0.78, 0.87))
	layer.add_child(detail_label)
	var footer := Label.new()
	footer.text = "MOTION ARCANA  /  Isolated GPU playtest fixture  /  1280 × 720"
	footer.position = Vector2(36.0, 688.0)
	footer.add_theme_font_size_override("font_size", 13)
	footer.modulate = Color(0.58, 0.69, 0.79)
	layer.add_child(footer)
	await physics_frame
	await _release_actions()

func _add_shape(body: CollisionObject2D, radius: float) -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	body.add_child(shape)

func _add_enemy(position: Vector2) -> RenderEnemy:
	var enemy := RenderEnemy.new()
	_add_shape(enemy, 13.0)
	enemy.position = position
	world.add_child(enemy)
	enemy.target = player
	return enemy

func _add_column(position: Vector2, radius: float) -> StaticBody2D:
	var column := StaticBody2D.new()
	column.add_to_group("arena_columns")
	column.set_meta("column_radius", radius)
	_add_shape(column, radius)
	column.position = position
	world.add_child(column)
	return column

func _release_actions() -> void:
	Input.action_release("attack")
	Input.action_release("dash")
	await process_frame
	await physics_frame
	await process_frame
	if is_instance_valid(player):
		player._refresh_combat_input_release()

func _press_attack() -> void:
	# Input's just-pressed clocks are advanced after the physics_frame signal.
	# Inject in an idle frame, as the ordinary GUI/input path does.
	await process_frame
	player.attack_cooldown_left = 0.0
	player.attack_lock_time_left = 0.0
	Input.action_press("attack")
	player._try_attack_input()

func _press_dash() -> void:
	await process_frame
	player.dash_cooldown_left = 0.0
	player.attack_lock_time_left = 0.0
	Input.action_press("dash")
	player._try_start_dash(Vector2.RIGHT)
	_check(player.arcana_motion.dash_hold >= 0.0, "An accepted dash arms the held-dash gesture")

func _step_frames(count: int) -> void:
	for _index in count:
		await physics_frame
		player._update_dash_cooldown(STEP)
		player._update_dash_phase_state(STEP)
		player._update_contact_damage_grace(STEP)
		player._update_attack_cooldown(STEP)
		player._update_attack_lock(STEP)
		player._update_attack_animation(STEP)
		player.arcana_motion.tick(STEP)
		player.boss_combinations.tick(STEP)
		if not player.arcana_motion.process_movement(STEP, Vector2.ZERO):
			player._process_active_dash(STEP)
		player.arcana_motion._process(STEP)
		player.queue_redraw()

func _capture(name: String, title: String, detail: String) -> void:
	title_label.text = title
	detail_label.text = detail
	player.arcana_motion.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and frame.get_size() == FRAME_SIZE, "Captured frame has the requested GPU resolution")
	var path := output_directory.path_join(name + ".png")
	_check(frame.save_png(path) == OK, "Saved " + name)
	frames.append({"name": name, "path": path, "motion": player.arcana_motion.motion, "charge": player.arcana_motion.charge_hold, "damage_recorded": world.damage_recorded})
	print("[FRAME] " + path)

func _free_world() -> void:
	await _release_actions()
	for audio_node in world.find_children("*", "AudioStreamPlayer", true, false):
		(audio_node as AudioStreamPlayer).stop()
		(audio_node as AudioStreamPlayer).stream = null
	for audio_node in world.find_children("*", "AudioStreamPlayer2D", true, false):
		(audio_node as AudioStreamPlayer2D).stop()
		(audio_node as AudioStreamPlayer2D).stream = null
	await create_timer(0.1).timeout
	if is_instance_valid(player.upgrade_system.power_registry):
		player.upgrade_system.power_registry.free()
	current_scene = null
	world.free()
	world = null
	player = null
	await process_frame

func _blast_frames() -> void:
	await _make_world()
	player.apply_trial_power("blast_drive")
	var close_first := _add_enemy(Vector2(-20.0, -28.0))
	var close_second := _add_enemy(Vector2(-10.0, 24.0))
	var distant := _add_enemy(Vector2(135.0, -15.0))
	await physics_frame
	await _press_attack()
	await _step_frames(40)
	_check(is_equal_approx(player.arcana_motion.charge_hold, MOTION.FULL_CHARGE_TIME), "Accepted Attack hold reaches full charge")
	await _capture("blast_charge", "BLAST DRIVE  /  CHARGE", "Hold Attack after the opening strike. The ring fills while the blast is ready to release.")
	var fire_origin := player.global_position
	Input.action_release("attack")
	await _step_frames(1)
	_check(player.arcana_motion.motion == MOTION.Motion.RECOIL and close_first.get_current_health() < 10000 and close_second.get_current_health() < 10000, "Release damages the nearby pack and begins real recoil")
	_check(distant.get_current_health() == 10000, "The narrower short-range blast leaves the distant enemy unharmed")
	await _capture("blast_fire", "BLAST DRIVE  /  CLOSE IMPACT", "A focused 70-degree blast hits the two nearby foes. The distant enemy stays outside its 160px reach.")
	await _step_frames(7)
	_check(player.global_position.distance_to(fire_origin) > 80.0, "The follow-up frame shows substantial real recoil")
	_check(not player.arcana_motion._blast_effects.is_empty() and (player.arcana_motion._blast_effects.back() as Node2D).global_position.is_equal_approx(fire_origin), "The visible blast remains at its world-space firing origin while the player recoils")
	await _capture("blast_recoil", "BLAST DRIVE  /  RECOIL AND HIT FEEDBACK", "The impact stays where the shot fired; recoil moves the player away from the struck enemies.")
	await _free_world()

func _orbit_frames(column_anchor: bool) -> void:
	await _make_world()
	player.apply_trial_power("razor_orbit")
	var target: Node2D
	if column_anchor:
		player.apply_trial_power("razor_orbit")
		target = _add_column(Vector2(120.0, 0.0), 28.0)
		var renderer := world.get_child(0) as RENDERER
		renderer.obstacle_layout.append({"pos": target.position, "radius": 28.0})
	else:
		target = _add_enemy(Vector2(120.0, 0.0))
	(player.arcana_motion as RenderMotion).aimed_anchor = target
	_add_enemy(Vector2(140.0, -145.0))
	_add_enemy(Vector2(185.0, 155.0))
	await physics_frame
	await _press_dash()
	await _step_frames(37)
	_check(player.arcana_motion.motion == MOTION.Motion.ORBIT, "Held dash enters the real orbit movement state")
	if column_anchor:
		await _capture("orbit_column", "RAZOR ORBIT II  /  COLUMN ANCHOR", "A column becomes an anchor. Steering and collision still use the real player body.")
	else:
		player.aim_point = target.global_position
		await _press_attack()
		await _step_frames(1)
		_check(world.damage_recorded > 0, "Orbit cuts and a manual strike deal real damage")
		await _capture("orbit_cut", "RAZOR ORBIT  /  CUTTING PASS", "Hold Dash to swing around the target. A manual strike remains available during the orbit.")
	await _free_world()

func _combined_frames() -> void:
	await _make_world()
	player.apply_trial_power("blast_drive")
	player.apply_trial_power("razor_orbit")
	var target := _add_enemy(Vector2(120.0, 0.0))
	_add_enemy(Vector2(155.0, -100.0))
	_add_enemy(Vector2(220.0, 65.0))
	(player.arcana_motion as RenderMotion).aimed_anchor = target
	await physics_frame
	await _press_dash()
	await _step_frames(24)
	await _press_attack()
	await _step_frames(40)
	_check(player.arcana_motion.motion == MOTION.Motion.ORBIT and player.arcana_motion.charge_hold >= 0.64, "A blast charges while orbit movement continues")
	await _capture("combined_charge", "BLAST DRIVE + RAZOR ORBIT  /  CHARGE ON THE MOVE", "Hold Attack during the orbit: the blast charges while the tether keeps the player moving.")
	Input.action_release("attack")
	await _step_frames(1)
	_check(player.arcana_motion.motion == MOTION.Motion.RECOIL and player.arcana_motion.anchor == null, "Blast release detaches the tether before recoil")
	_check(Input.is_action_pressed("dash") and player.arcana_motion.dash_hold < 0.0, "The still-held Dash does not immediately reattach")
	await _capture("combined_detach", "BLAST DRIVE + RAZOR ORBIT  /  BLAST TO DETACH", "Release Attack to break the tether and blast away. A still-held Dash does not pull the player back.")
	await _free_world()

func _boss_frames() -> void:
	await _make_world()
	player.apply_upgrade("ruinous_impact")
	player.apply_upgrade("ruinous_impact")
	var launched := _add_enemy(Vector2(-70.0, 0.0))
	var victim := _add_enemy(Vector2(25.0, 0.0))
	await physics_frame
	await _press_attack()
	_check(launched.get_launch_state().active, "A direct strike arms Ruinous without motion Arcana")
	await _capture("ruinous_launch", "RUINOUS IMPACT II  /  LAUNCH", "The direct strike launches its target toward another enemy.")
	var victim_health := victim.get_current_health()
	for _index in range(15):
		await physics_frame
		if launched.get_launch_state().active:
			launched.get_launch_state().step(launched, STEP)
			if not launched.get_launch_state().active:
				break
	_check(victim.get_current_health() < victim_health, "The first enemy contact causes a real compression burst")
	await _capture("ruinous_impact", "RUINOUS IMPACT II  /  COLLISION", "One orange burst marks the impact. Its secondary damage cannot arm another launch.")
	await _free_world()

	await _make_world()
	player.apply_upgrade("sovereigns_double")
	player.apply_upgrade("sovereigns_double")
	player.apply_trial_power("blast_drive")
	player.position = Vector2(-150.0, -85.0)
	player.aim_point = Vector2(200.0, -85.0)
	_add_enemy(Vector2(0.0, -85.0))
	_add_enemy(Vector2(-5.0, 110.0))
	player.boss_combinations.create_shade(Vector2(-150.0, 110.0))
	await _capture("sovereign_shade", "SOVEREIGN'S DOUBLE II  /  SHADE", "The last movement leaves one shade, with two pips showing its remaining deliberate strikes.")
	await _press_attack()
	await _step_frames(40)
	_check(player.boss_combinations.shade_hits == 1, "The opening deliberate tap uses the first shade strike")
	Input.action_release("attack")
	await _step_frames(1)
	_check(player.boss_combinations.shade_hits == 0 and world.damage_recorded > 0, "The charged blast repeats from the shade without extra motion or resources")
	await _capture("sovereign_blast", "SOVEREIGN'S DOUBLE + BLAST DRIVE  /  REPEATED BLAST", "The violet arc repeats the charged blast from the shade; only the player recoils.")
	await _free_world()
