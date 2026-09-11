extends SceneTree
## Exercise actual Main transitions, saved identity and canonical route payoffs.
const MAIN := preload("res://scenes/Main.tscn")
const WORLD := preload("res://scripts/world_generator.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
var audio_retirement := AUDIO_RETIREMENT.new()
var checks := 0
var failures: Array[String] = []
var world: WORLD
var score_playback_id := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _music_playback_id() -> int:
	var music: Node = world.music_system
	if music.active_music_player_index < 0:
		return 0
	var active: AudioStreamPlayer = music.music_players[music.active_music_player_index]
	var playback: AudioStreamPlayback = active.get_stream_playback()
	return playback.get_instance_id() if active.playing and playback != null else 0

func _check_score_continuity(label: String) -> void:
	check(score_playback_id != 0 and _music_playback_id() == score_playback_id, label)

func _check_score_location(act: int, depth: int, boss_chamber: bool, label: String) -> void:
	var expected_normal := posmod(depth + act - 1, 3)
	check(world.music_system.get_normal_score_variant() == expected_normal, label + ": normal variation follows the presented act and depth")
	check(world.music_system.get_selected_score_variant() == (3 if boss_chamber else expected_normal), label + ": selected variation matches the chamber")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Descent presentation requires disposable user data")
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-descent-presentation")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "veilstrider"
	RunContext.current_difficulty_tier = 1
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.set_physics_process(false)
	var ui: Node = world.reward_selection_ui
	check(ui.is_active() and world.music_system.music_context == &"reward", "Starting selection records the reward context without changing the music")
	check(world.music_system.is_adaptive_score(), "Main replaces the run music with the adaptive Riot Depth score")
	score_playback_id = _music_playback_id()
	check(score_playback_id != 0, "Starting selection already owns one live synchronized score playback")
	_check_score_location(1, world.room_depth, false, "Starting chamber")
	ui.close_selection()
	ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	world.run_session.act_biome_ids = ["shatterfield", "grinding_vault", "void_breach"]
	world.run_session.act_boss_ids = ["warden", "sovereign", "lacuna"]
	_test_route_previews()
	_test_room_history_and_identity()
	_test_boss_transition(1, "warden", "shatterfield", "grinding_vault")
	_test_boss_transition(2, "sovereign", "grinding_vault", "void_breach")
	_test_final_boss()
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after the scene is released")
	print("[OK] Descent presentation: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_route_previews() -> void:
	var builder: Node = world.encounter_profile_builder
	for tier in range(4):
		builder.set_difficulty_tier(tier)
		for entry in CONTRACTS.debug_encounter_entries():
			var key := String(entry.get("key", ""))
			if not CONTRACTS.debug_encounter_is_objective(key) or key == "random_objective":
				continue
			var room: Dictionary = builder.build_debug_encounter_profile(key, 8)
			var door := CONTRACTS.objective_door_option(room)
			var before := door.duplicate(true)
			var bonus := CONTRACTS.profile_player_mutator(room)
			var preview := CONTRACTS.door_reward_preview_text(door)
			check(preview.begins_with("Boon + ") and preview.contains(CONTRACTS.mutator_name(bonus)), "Mission door names its actual fixed bonus on Bearing%d/%s" % [tier, key])
			check(preview.contains("(%d rooms)" % int(bonus.get("duration_encounters", 0))), "Mission door retains its real duration on Bearing%d/%s" % [tier, key])
			check(door == before, "Inspecting a payoff never mutates an offer")
	builder.set_difficulty_tier(1)
	var standard: Dictionary = builder.build_debug_encounter_profile("crossfire", 5)
	check(CONTRACTS.door_reward_preview_text(CONTRACTS.standard_encounter_door_option(standard)) == "Boon", "Ordinary route shows its permanent Boon")
	check(CONTRACTS.door_reward_preview_text(CONTRACTS.trial_door_option(standard, "Blood Rush", Color.WHITE)) == "Arcana", "Trial payoff remains Arcana regardless of encounter label")
	check(CONTRACTS.door_reward_preview_text(CONTRACTS.apex_trial_door_option(standard, "Apex Breakwater", Color.WHITE)) == "Arcana", "Apex uses its actual Arcana reward")
	check(CONTRACTS.door_reward_preview_text(CONTRACTS.rest_door_option()) == "Restore health", "Rest promises healing without claiming a full heal")
	for boss_key in ["warden", "sovereign"]:
		check(CONTRACTS.door_reward_preview_text(CONTRACTS.boss_door_option(boss_key)) == "Boss power", "Early boss names its power reward")
	check(CONTRACTS.door_reward_preview_text(CONTRACTS.boss_door_option("lacuna")) == "Complete the descent", "Final boss promises victory rather than another power")
	check(CONTRACTS.door_reward_preview_text({}).is_empty(), "Missing payoff metadata does not fabricate a reward")

func _test_room_history_and_identity() -> void:
	world._clear_all_enemies()
	world._apply_active_biome(1)
	var room: Dictionary = world.encounter_profile_builder.build_debug_encounter_profile("crossfire", 5)
	world._begin_room(room)
	world._sync_renderer()
	check(world.run_session.last_standard_encounter_key == "crossfire", "Real room entry records the chosen standard identity")
	check(world.renderer.environment_act == 1 and world.renderer.environment_biome_id == "shatterfield", "Actual room applies the selected Act I environment")
	check(world.renderer.obstacle_layout.size() == 4 and world._active_obstacle_nodes.size() == 4, "Shatterfield pilot reaches both visible and physical cover")
	check(world.music_system.music_context == &"combat", "Encounter entry restores combat music context")
	var entered_depth := world.room_depth
	var entered_variant: int = world.music_system.get_selected_score_variant()
	_check_score_location(1, entered_depth, false, "Ordinary room entry")
	_check_score_continuity("Starting selection and standard encounter share the same native score playback")
	var before: String = world.run_session.last_standard_encounter_key
	var offered: Array[Dictionary] = world._roll_route_options(world._build_route_context(5))
	check(world.run_session.last_standard_encounter_key == before, "Generating live route alternatives leaves entered-room history intact")
	for door in offered:
		if CONTRACTS.door_option_reward_mode(door) == ENUMS.RewardMode.BOON:
			check(CONTRACTS.profile_encounter_key(CONTRACTS.door_option_profile(door)) != "crossfire", "Live standard offer avoids the previous entered room")
	world._exit_encounter_intro_grace()
	var rule_hint := String(BIOMES.get_combat_identity("shatterfield").entry_hint)
	check(world.hud.room_banner_subtitle_label.text == rule_hint, "Starting combat retains the actionable biome cue instead of replacing it with Engage")
	world.hud.refresh(world._get_hud_state(), world.player)
	check(world.hud._status_biome_rule_label.visible and world.hud._status_biome_rule_label.text == rule_hint, "The ordinary-room biome rule remains readable in the HUD after survey ends")
	world._clear_all_enemies()
	world.active_room_enemy_count = 0
	world.pending_room_reward = ENUMS.RewardMode.BOON
	world._update_encounter_state()
	check(world.reward_selection_ui.is_active() and world.music_system.music_context == &"reward", "Clearing an ordinary encounter records reward selection")
	check(world.music_system.get_selected_score_variant() == entered_variant, "Clearing an ordinary room preserves its variation despite advancing progression")
	_check_score_continuity("Ordinary combat clear preserves the music while rewards open")
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.BOON, false)
	check(world.choosing_next_room and not world.door_options.is_empty() and world.music_system.music_context == &"doors", "Completing an ordinary reward records door selection")
	_check_score_location(1, entered_depth, false, "Ordinary doorway")
	_check_score_continuity("Ordinary reward completion keeps the same music through door selection")
	var snapshot: Dictionary = world._build_active_run_snapshot()
	world.music_system.set_run_location(3, entered_depth + 1, true)
	world.music_system.set_context(&"boss", true)
	check(world._apply_active_run_snapshot(snapshot), "Ordinary Continue path accepts the saved doorway")
	check(world.music_system.get_selected_score_variant() == entered_variant, "Continue restores the cleared room's variation rather than the next depth's variation")
	_check_score_location(1, entered_depth, false, "Continued ordinary doorway")
	_check_score_continuity("Ordinary Continue preserves the native score playback")

func _test_boss_transition(stage: int, boss_key: String, old_biome: String, next_biome: String) -> void:
	world._clear_all_enemies()
	# Follow the real door entry so the previous room's routes are consumed.
	# Calling the inner boss builder directly would leave stale visible doors.
	world._choose_door(CONTRACTS.boss_door_option(boss_key))
	world._sync_renderer()
	check(not world.choosing_next_room and world.door_options.is_empty(), "Choosing the boss consumes the preceding room's offered doors")
	check(world.renderer.environment_act == stage and world.renderer.environment_biome_id == old_biome, "Boss enters its own act environment")
	check(world.renderer.boss_entrance_active and world.renderer.boss_entrance_key == boss_key, "Boss motif appears during the real survey phase")
	check(world.music_system.music_context == &"boss", "Boss entry selects boss music")
	var entered_depth := world.room_depth
	_check_score_location(stage, entered_depth, true, "Boss entry")
	_check_score_continuity("Boss entry retains Riot Depth's running synchronized score")
	world._exit_encounter_intro_grace()
	world._sync_renderer()
	check(not world.renderer.boss_entrance_active, "Decorative boss entrance stops when combat begins")
	world._clear_all_enemies()
	if stage == 1:
		world._finish_first_boss_clear()
	else:
		world._finish_second_boss_clear()
	world._sync_renderer()
	check(world._get_current_act() == stage + 1 and world._get_room_presentation_act() == stage, "Progress advances without changing the defeated chamber")
	check(world.renderer.environment_biome_id == old_biome and world._get_active_biome_name() == String(BIOMES.get_biome(old_biome).name), "Boss rewards retain the old environment and HUD biome")
	check(world._get_hud_state().display_act == stage, "HUD act stays with the visible chamber")
	check(world.music_system.music_context == &"reward" and world.reward_selection_ui.is_active(), "Boss reward records its selection context")
	_check_score_location(stage, entered_depth, true, "Boss reward")
	_check_score_continuity("Boss reward selection preserves the native score playback")
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.BOSS, false)
	check(world.choosing_next_room and not world.door_options.is_empty() and world.music_system.music_context == &"doors", "Boss reward completion records the offered door choices")
	_check_score_location(stage, entered_depth, true, "Boss doorway after act progress advances")
	_check_score_continuity("Boss rewards flow into doors without restarting the score")
	var saved_doors: Array[Dictionary] = world.door_options.duplicate(true)
	var snapshot: Dictionary = world._build_active_run_snapshot()
	check(snapshot.get("act_biome_ids") == ["shatterfield", "grinding_vault", "void_breach"], "Real snapshot contains the original biome roster")
	world.run_session.act_biome_ids = ["haunt", "hollow", "convergence_end"]
	world.music_system.set_run_location(stage + 1, world.room_depth, false)
	world.music_system.set_context(&"combat", true)
	check(world._apply_active_run_snapshot(snapshot), "Real Continue path accepts the checkpoint")
	check(world.renderer.environment_biome_id == old_biome and world.door_options == saved_doors, "Continue keeps the defeated place and exact offered doors")
	check(world.music_system.music_context == &"doors", "Continue restores the saved door-selection context")
	_check_score_location(stage, entered_depth, true, "Continue restores the defeated boss chamber from its saved label")
	_check_score_continuity("Applying a doorway checkpoint preserves the existing score playback")
	world._enter_rest_site()
	check(world.renderer.environment_act == stage + 1 and world.renderer.environment_biome_id == next_biome, "Taking the next room reveals its new act")
	check(world.music_system.music_context == &"rest", "Rest records its entered-room context")
	_check_score_location(stage + 1, world.room_depth, false, "Next-act rest after its depth increment")
	_check_score_continuity("Rest entry and its offered doors preserve the same native playback")
	check(world.hud.room_banner_title_label.text.contains(String(BIOMES.get_biome(next_biome).name)), "First next-act room announces its biome in the existing banner")
	check(world.run_summary_recorder.run_summary_tracker.reached_act == stage + 1, "Only actual next-act entry advances the recorded reached act")

func _test_final_boss() -> void:
	world._choose_door(CONTRACTS.boss_door_option("lacuna"))
	_check_score_location(3, world.room_depth, true, "Final boss entry")
	world._sync_renderer()
	check(world.renderer.environment_act == 3 and world.renderer.boss_entrance_key == "lacuna", "Lacuna receives the Act III threshold presentation")
	world._exit_encounter_intro_grace()
	world._sync_renderer()
	check(not world.renderer.boss_entrance_active, "Lacuna's decorative motif cannot survive into attack warnings")
