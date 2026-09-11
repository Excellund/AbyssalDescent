extends "res://scripts/tests/test_pulse_hud.gd"
## Before/current native actor draw comparisons, with the old inheritance tree retained.
const ROLES := ["chaser", "charger", "archer", "shielder", "weaver", "drifter", "sentinel", "pyre", "boss"]
const VISUAL_STATES := preload("res://scripts/shared/enemy_state_enums.gd")
var actors: Array[Node2D] = []
var frames: Array[Dictionary] = []
var draw_profiles: Array[Dictionary] = []
var loaded_scripts: Array[GDScript] = []
var output_directory := ""
var variant := ""

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	output_directory = ProjectSettings.globalize_path("res://enemy_visual_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	_prepare_pulse_world()
	world._clear_all_enemies()
	world.objective_manager.reset()
	world.rng.seed = 88127
	world.encounter_profile_builder.rng.seed = 88127
	world.run_session.act_biome_ids.assign(["crumble", "grinding_vault", "convergence"])
	world._apply_active_biome(1)
	world._begin_room(world.encounter_profile_builder.build_debug_encounter_profile("crossfire", 5))
	world._clear_all_enemies()
	world.enemy_spawner._clear_pending_waves()
	world._clear_room_obstacles()
	world.player.set_max_health_and_current(10000)
	world.player.global_position = Vector2(-330, 240)
	world._exit_encounter_intro_grace()
	world.player.combat_damage_enabled = false
	world.hud.hide_persistent_banner()
	world.hud.room_banner_title_label.modulate.a = 0.0
	world.hud.room_banner_subtitle_label.modulate.a = 0.0
	await process_frame
	for selected: String in ["before", "after"]:
		variant = selected
		await _roster()
		await _capture("roster_960", 960)
		await _capture("roster_1280", 1280)
		_stage_frontline_warnings()
		await _capture("frontline_warnings", 1280)
		await _roster()
		_stage_specialist_warnings()
		await _capture("specialist_warnings", 1280)
		await _roster()
		for index in 7:
			if index == 4:
				actors[index].begin_spawn_transport(.6)
				actors[index]._update_spawn_transport(.25)
			elif index % 2 == 0:
				actors[index].apply_slow(3.0, .6)
			else:
				actors[index].set_dread_resonance_visual(3, 5, false)
		await _capture("status_spawn", 1280)
		await _crowd()
		await _capture("crowd_lod", 960, .58)
		await _measure_crowd()
	await _clear_actors()
	await _release_pulse_world()
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation_fixtures/enemy_visual_baseline.json"))
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures, "draw_profiles": draw_profiles, "baseline": config, "scope": "Nine native bodies (seven revised, unchanged Pyre/Warden), production room-fit cameras at960/1280, warnings, Slow/Mark/spawn and28-actor low-detail crowd at0.58zoom. _draw timings measure CPU command submission for300 redraws after60 warmup frames with frozen simulation; not GPU time or FPS."}
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[EnemyVisualProfiles] %d checks, %d failures; %d frames" % [checks, failures.size(), frames.size()])
	quit(0 if failures.is_empty() else 1)

func _actor(role: String, position: Vector2, caption: bool = true) -> Node2D:
	var path := "res://validation_fixtures/enemy_visual_baseline/enemy_%s.gd" % role if variant == "before" else "res://scripts/enemy_%s.gd" % role
	var script := GDScript.new()
	script.source_code = "extends \"%s\"\nvar draw_measuring := false\nvar draw_samples: Array = []\nfunc _draw() -> void:\n\tvar started := Time.get_ticks_usec()\n\tsuper._draw()\n\tif draw_measuring: draw_samples.append(Time.get_ticks_usec() - started)\n" % path
	check(script.reload() == OK, "Native role measurement wrapper compiles: " + variant + "/" + role)
	loaded_scripts.append(script)
	var actor := CharacterBody2D.new()
	actor.set_script(script)
	# Keep its real physics space available while the enclosing staged world is
	# disabled; native windup pumps call move_and_slide even with zero velocity.
	actor.process_mode = Node.PROCESS_MODE_ALWAYS
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 13.0
	actor.add_child(shape)
	actor.position = position
	world.add_child(actor)
	actor.set_meta("visual_role", role)
	actor.set("target", world.player)
	actor.set("visual_facing_direction", Vector2.RIGHT)
	if role == "sentinel": actor.set("cone_direction_angle", 0.0)
	if role == "weaver":
		actor.set("_burst_angle_offset", 0.0)
		actor.call("_init_feet")
	actor.set("spawn_transport_seed", 13.0)
	actor.set("spawn_transport_time_left", 0.0)
	actor.set_physics_process(false)
	actor.set_process(false)
	if caption:
		var label := Label.new()
		label.text = role.capitalize() if role != "boss" else "Warden (unchanged)"
		label.position = Vector2(-76, 42)
		label.size = Vector2(152, 24)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		actor.add_child(label)
	actors.append(actor)
	return actor

func _roster() -> void:
	await _clear_actors()
	seed(88127)
	for index in ROLES.size():
		_actor(ROLES[index], Vector2(-160 + (index % 3) * 250, -215 + int(index / 3) * 205))
	await process_frame
	for actor in actors:
		actor.set("_visual_lod_refresh_left", 0.0)
		actor.call("_refresh_visual_lod_metrics", .5)
		check(not actor.call("_is_high_load_visual_lod_active"), "Normal roster retains full-detail role presentation")

func _stage_frontline_warnings() -> void:
	actors[0].set("attack_anim_time_left", .09)
	world.player.global_position = actors[1].global_position + Vector2(125, 0)
	actors[1]._enter_windup_state()
	actors[1]._process_windup_state(.35)
	world.player.global_position = actors[2].global_position + Vector2(-100, 40)
	actors[2]._enter_windup_state()
	actors[2]._process_windup_state(.25)
	world.player.global_position = actors[3].global_position + Vector2(90, 0)
	actors[3].set("slam_cooldown_left", 0.0)
	actors[3]._try_start_slam()
	actors[3]._process_slam_windup(.3)
	check(actors[1].charger_state == VISUAL_STATES.ChargerState.WINDUP and actors[2].archer_state == VISUAL_STATES.ArcherState.WINDUP and actors[3].slam_state == VISUAL_STATES.ShielderSlamState.WINDUP, "Actual frontline windup states remain active under revised bodies")

func _stage_specialist_warnings() -> void:
	world.player.global_position = actors[4].global_position + Vector2(150, 0)
	actors[4]._enter_windup()
	actors[4]._process_windup(.3)
	actors[5]._emit_ring()
	actors[5]._process_rings(.7)
	actors[5].set("wave_timer", .3)
	actors[6].set("cone_direction_angle", -.3)
	check(not actors[5].rings.is_empty() and actors[4]._is_in_priority_attack_state(), "Native Weaver windup and Drifter safe-gap ring remain present")

func _crowd() -> void:
	await _clear_actors()
	for index in 28:
		_actor(ROLES[index % 7], Vector2(-250 + (index % 7) * 85, -170 + int(index / 7) * 112), false)
	await process_frame
	for actor in actors:
		actor.set("_visual_lod_refresh_left", 0.0)
		actor.call("_refresh_visual_lod_metrics", .5)
		check(actor.call("_is_high_load_visual_lod_active"), "Real28-actor count activates native reduced detail")

func _capture(name: String, width: int, forced_zoom: float = 0.0) -> void:
	root.size = Vector2i(width, 720)
	root.content_scale_size = root.size
	await process_frame
	world._apply_camera_bounds_for_room(world.current_effective_room_size)
	world._update_camera_mode()
	world.player_camera.set_physics_process(false)
	world.player_camera.global_position = Vector2.ZERO
	world.player_camera.zoom = Vector2.ONE * forced_zoom if forced_zoom > 0.0 else world.player_camera.target_zoom
	world.player_camera.force_update_scroll()
	world.player.global_position = Vector2(-330, 240)
	world.hud.refresh(world._get_hud_state(), world.player)
	world._sync_renderer()
	for actor in actors: actor.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(variant + "_" + name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Captured native enemy view: " + variant + "/" + name)
	frames.append({"name": variant + "_" + name, "path": path, "viewport": root.size, "zoom": world.player_camera.zoom})

func _measure_crowd() -> void:
	for frame_index in 360:
		for actor in actors:
			actor.set("draw_measuring", frame_index >= 60)
			actor.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
	var samples: Array = []
	for actor in actors:
		actor.set("draw_measuring", false)
		samples.append_array(actor.get("draw_samples"))
	check(samples.size() == 28 * 300, "Every crowded native actor rendered all300 measured frames")
	samples.sort()
	var total := 0.0
	for sample: float in samples: total += sample
	draw_profiles.append({"variant": variant, "count": samples.size(), "mean_actor_draw_usec": total / maxi(1, samples.size()), "mean_crowd_draw_usec": total / 300.0, "p50_actor_usec": samples[int(samples.size() * .5)], "p95_actor_usec": samples[int(samples.size() * .95)]})
	print("[EnemyDrawProfile] " + JSON.stringify(draw_profiles.back()))

func _clear_actors() -> void:
	for actor in actors:
		if is_instance_valid(actor): actor.queue_free()
	actors.clear()
	await process_frame
