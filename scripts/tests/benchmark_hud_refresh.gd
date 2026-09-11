extends "res://scripts/tests/test_descent_presentation.gd"
## Native live-simulation benchmark; only measurement wrappers differ from production.
const WARMUP_FRAMES := 90
const SAMPLE_FRAMES := 360
const SEED := 731942
const BUILD := ["heartstone", "heavy_blow", "long_reach", "fleet_foot", "static_wake", "stormbrand", "hunters_snare", "spark_relay", "unbroken_oath", "shatterwake"]
var frames: Array[Dictionary] = []
var trials: Array[Dictionary] = []
var output_directory := ""
var measured_scripts: Array[GDScript] = []

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation_fixtures/hud_benchmark.json"))
	output_directory = ProjectSettings.globalize_path("res://hud_benchmark_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-hud-benchmark")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "veilstrider"
	RunContext.current_difficulty_tier = 1
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	for variant: String in config.order:
		await _trial(variant, trials.size())
	for trial: Dictionary in trials:
		check(trial.visual_hud == trials[0].visual_hud, "Same frozen state produces identical HUD text, stack labels and control bounds: " + String(trial.variant))
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after benchmark worlds")
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures, "trials": trials, "config": config, "warmup_frames": WARMUP_FRAMES, "sample_frames": SAMPLE_FRAMES, "seed": SEED, "scope": "Fresh seeded Main per trial; 12 live enemies, ordinary acquired build, deliberate periodic Attacks. Actors have 10000 HP to retain the population. Fixed 60 Hz is pacing, not a measured FPS result. World-script CPU excludes renderer/GPU and other node callbacks; engine process monitor is descriptive."}
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[HudBenchmark] %d checks, %d failures; %d trials" % [checks, failures.size(), trials.size()])
	quit(0 if failures.is_empty() else 1)

func _instrumented_script(base_path: String, methods: Array[Dictionary]) -> GDScript:
	var source := "extends \"%s\"\nvar measuring := false\nvar samples: Dictionary = {}\nfunc _record_sample(key: String, started: int) -> void:\n\tif measuring:\n\t\tif not samples.has(key): samples[key] = []\n\t\tsamples[key].append(Time.get_ticks_usec() - started)\n" % base_path
	for method in methods:
		source += "func %s(%s) -> void:\n\tvar started := Time.get_ticks_usec()\n\tsuper.%s(%s)\n\t_record_sample(\"%s\", started)\n" % [method.name, method.params, method.name, method.args, method.name]
	var script := GDScript.new()
	script.source_code = source
	check(script.reload() == OK, "Identical measurement subclass compiles: " + base_path)
	measured_scripts.append(script)
	return script

func _trial(variant: String, index: int) -> void:
	seed(SEED)
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	var world_script := _instrumented_script("res://scripts/world_generator.gd", [{"name": "_process", "params": "delta: float", "args": "delta"}])
	world = MAIN.instantiate() as WORLD
	world.set_script(world_script)
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	# Main deliberately randomizes its private run RNG; establish all room inputs
	# after ready so each trial starts with the same biome, terrain and actors.
	seed(SEED)
	world.rng.seed = SEED
	world.room_depth = 5
	world.rooms_cleared = 4
	world.run_session.act_biome_ids.assign(["crumble", "grinding_vault", "convergence"])
	world._apply_active_biome(1)
	world.encounter_profile_builder.rng.seed = SEED
	world._begin_room(world.encounter_profile_builder.build_debug_encounter_profile("crossfire", 5))
	world._clear_all_enemies()
	world.enemy_spawner._clear_pending_waves()
	await process_frame
	var roster := ["chaser", "chaser", "chaser", "chaser", "chaser", "chaser", "archer", "archer", "archer", "archer", "shielder", "shielder"]
	var spawned: Array[Dictionary] = world.enemy_spawner._spawn_types_immediate(roster, true)
	var actor_index := 0
	for entry in spawned:
		var enemy: Node2D = entry.enemy
		enemy.global_position = Vector2(-420 + (actor_index % 6) * 168, -200 if actor_index < 6 else 200)
		enemy.health_state.setup(10000)
		enemy._update_spawn_transport(float(enemy.spawn_transport_time_left) + .01)
		actor_index += 1
	check(spawned.size() == 12, "Each trial creates the same 12 native enemies")
	world.player.global_position = Vector2.ZERO
	world.player.set_max_health_and_current(10000)
	for id: String in BUILD:
		check(world.player.upgrade_system.apply_power(id), "Normal acquisition succeeds for " + id)
	var active_powers: Dictionary = world._get_active_player_powers()
	check(active_powers.boons.size() == 4 and active_powers.arcana.size() == 4 and active_powers.boss_rewards.size() == 2, "Representative build contains four Boons, four Arcana and two boss rewards")
	world._signal_local_player_ready()
	world.hud.free()
	var base := "res://validation_fixtures/hud_refresh_baseline.gd" if variant == "baseline" else "res://scripts/world_hud.gd"
	var methods: Array[Dictionary] = [
		{"name":"refresh", "params":"state: Dictionary, player: Node", "args":"state, player"},
		{"name":"_update_header_bar", "params":"state: Dictionary", "args":"state"},
		{"name":"_update_status_panel_text", "params":"state: Dictionary", "args":"state"},
		{"name":"_update_player_mutator_panel", "params":"state: Dictionary", "args":"state"},
		{"name":"_update_stats_panel_text", "params":"player: Node, state: Dictionary", "args":"player, state"},
		{"name":"_update_build_strip", "params":"state: Dictionary, player: Node", "args":"state, player"},
		{"name":"_layout_hud_panels", "params":"viewport_size: Vector2, room_size: Vector2, canvas_xform: Transform2D", "args":"viewport_size, room_size, canvas_xform"},
		{"name":"_update_banner_layout", "params":"room_size: Vector2, canvas_xform: Transform2D, viewport_size: Vector2", "args":"room_size, canvas_xform, viewport_size"},
		{"name":"_update_combat_overlap_fade", "params":"state: Dictionary, player: Node", "args":"state, player"}]
	var hud_script := _instrumented_script(base, methods)
	world.hud = hud_script.new()
	world.add_child(world.hud)
	world.hud.setup(world.encounter_count, 18.0)
	world._apply_camera_bounds_for_room(world.current_effective_room_size)
	world._update_camera_mode()
	world.player_camera.set_physics_process(false)
	world.player_camera.global_position = Vector2.ZERO
	world.player_camera.zoom = world.player_camera.target_zoom
	world.player_camera.force_update_scroll()
	world.set_process(true)
	var process_ms: Array = []
	var physics_ms: Array = []
	var frame_delta_ms: Array = []
	for frame_index in WARMUP_FRAMES + SAMPLE_FRAMES:
		if frame_index == WARMUP_FRAMES:
			world.set("measuring", true)
			world.hud.set("measuring", true)
		if frame_index % 45 == 0:
			world.player._try_execute_attack(Vector2.from_angle(float(frame_index) * .03))
		await process_frame
		if frame_index >= WARMUP_FRAMES:
			process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			frame_delta_ms.append(world.get_process_delta_time() * 1000.0)
	world.set("measuring", false)
	world.hud.set("measuring", false)
	world.set_process(false)
	var summaries := {}
	for key: String in world.hud.get("samples"):
		summaries[key] = _summary(world.hud.get("samples")[key])
	check(int(summaries.get("refresh", {}).get("count", 0)) >= SAMPLE_FRAMES, "Native HUD refreshes every measured frame and on real health changes")
	check(world.player.get_current_health() > 0 and not world.choosing_next_room, "Live combat persists through the measurement")
	trials.append({"variant": variant, "index": index, "hud_usec": summaries, "world_script_usec": _summary(world.get("samples").get("_process", [])), "engine_process_ms": _summary(process_ms), "engine_physics_ms": _summary(physics_ms), "frame_delta_ms": _summary(frame_delta_ms), "hud_sha256": FileAccess.get_sha256(base), "build": world._get_active_player_powers()})
	print("[HudBenchmarkTrial] " + JSON.stringify(trials.back()))
	# Separate deterministic visual check: no live timers, particles, or AI are benchmarked here.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	root.size = Vector2i(1280, 1080)
	root.content_scale_size = root.size
	await process_frame
	world.player.global_position = Vector2.ZERO
	world.player.set_max_health_and_current(140, 112)
	world.player.external_slow_left = 0.0
	world.player.external_slow_mult = 1.0
	var state: Dictionary = world._get_hud_state()
	state.run_elapsed_seconds = 125
	state.active_room_enemy_count = 12
	state.combat_hud_overlap_fade_enabled = false
	world.hud.refresh(state, world.player)
	world._sync_renderer()
	await process_frame
	world.hud.refresh(state, world.player)
	trials.back()["visual_hud"] = _hud_visual_signature()
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join("%02d_%s.png" % [index, variant])
	check(root.get_texture().get_image().save_png(path) == OK, "Captured native populated HUD")
	frames.append({"name": "%02d_%s" % [index, variant], "path": path})
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()

func _hud_visual_signature() -> Dictionary:
	var result := {"stats": world.hud.stats_label.get_parsed_text(), "stats_rect": var_to_str(world.hud.stats_panel.get_global_rect()), "status": {}, "passive": world.hud.build_strip_passive_label.get_parsed_text(), "chips": []}
	for property: String in ["_status_header_bear_name", "_status_header_biome_name", "_status_header_bear_micro", "_status_header_biome_micro", "_status_act_label", "_status_depth_label", "_status_biome_rule_label", "_status_hint_label", "_status_obj_line1", "_status_obj_line2", "_status_obj_line3"]:
		var label: Label = world.hud.get(property)
		result.status[property] = {"text": label.text, "visible": label.is_visible_in_tree(), "rect": var_to_str(label.get_global_rect()), "font_color": label.get_theme_color("font_color").to_html()}
	for category: String in ["boon", "arcana", "boss"]:
		var chips: Array = world.hud.get("build_strip_" + category + "_chips")
		var labels: Array = world.hud.get("build_strip_" + category + "_labels")
		var stacks: Array = world.hud.get("build_strip_" + category + "_stack_labels")
		for index in chips.size():
			if chips[index].visible:
				result.chips.append({"category": category, "text": labels[index].text, "stack": stacks[index].text, "rect": var_to_str(chips[index].get_global_rect())})
	return result

func _summary(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value: float in ordered:
		total += value
	return {"count": ordered.size(), "mean": total / ordered.size(), "p50": ordered[int(floor((ordered.size() - 1) * .5))], "p95": ordered[int(floor((ordered.size() - 1) * .95))]}
