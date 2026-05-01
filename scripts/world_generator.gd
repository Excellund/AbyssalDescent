extends Node2D

const ENEMY_CHASER_SCRIPT := preload("res://scripts/enemy_chaser.gd")
const ENEMY_CHARGER_SCRIPT := preload("res://scripts/enemy_charger.gd")
const ENEMY_ARCHER_SCRIPT := preload("res://scripts/enemy_archer.gd")
const ENEMY_SHIELDER_SCRIPT := preload("res://scripts/enemy_shielder.gd")
const ENEMY_LURKER_SCRIPT := preload("res://scripts/enemy_lurker.gd")
const ENEMY_RAM_SCRIPT := preload("res://scripts/enemy_ram.gd")
const ENEMY_LANCER_SCRIPT := preload("res://scripts/enemy_lancer.gd")
const ENEMY_BOSS_SCRIPT := preload("res://scripts/enemy_boss.gd")
const ENEMY_BOSS_2_SCRIPT := preload("res://scripts/enemy_boss_2.gd")
const POWER_REGISTRY := preload("res://scripts/power_registry.gd")
const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const MUSIC_SYSTEM_SCRIPT := preload("res://scripts/music_system.gd")
const ENEMY_SPAWNER_SCRIPT := preload("res://scripts/enemy_spawner.gd")
const ENCOUNTER_PROFILE_BUILDER_SCRIPT := preload("res://scripts/encounter_profile_builder.gd")
const ENCOUNTER_FLOW_SYSTEM_SCRIPT := preload("res://scripts/encounter_flow_system.gd")
const OBJECTIVE_RUNTIME_SCRIPT := preload("res://scripts/objective_runtime.gd")
const REWARD_SELECTION_UI_SCRIPT := preload("res://scripts/reward_selection_ui.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")
const RUN_TELEMETRY_STORE := preload("res://scripts/run_telemetry_store.gd")
const TELEMETRY_SPIKE_SENDER_SCRIPT := preload("res://scripts/telemetry_spike_sender.gd")
const RUN_SNAPSHOT_SERVICE := preload("res://scripts/run_snapshot_service.gd")
const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")
const DEBUG_ENUMS := preload("res://scripts/shared/debug_enums.gd")
const DEBUG_SETTINGS_SCRIPT := preload("res://scripts/debug_settings.gd")
const RUN_CONTEXT_PATH := "/root/RunContext"
const MENU_SCENE_PATH := "res://scenes/Menu.tscn"
const RUN_SNAPSHOT_VERSION := 1
const BOSS_SPAWN_TRANSPORT_DURATION := 0.40
const INTRO_SURVEY_TRANSPORT_PULSE_DURATION := 0.24
const WORLD_HUD_SCRIPT := preload("res://scripts/world_hud.gd")
const WORLD_RENDERER_SCRIPT := preload("res://scripts/world_renderer.gd")
const PAUSE_MENU_CONTROLLER_SCRIPT := preload("res://scripts/pause_menu_controller.gd")
const VICTORY_SCREEN_SCRIPT := preload("res://scripts/victory_screen.gd")
const DEFEAT_SCREEN_SCRIPT := preload("res://scripts/defeat_screen.gd")

func _find_debug_encounter_entry(key: String) -> Dictionary:
	return ENCOUNTER_CONTRACTS.debug_encounter_entry(key)

func _get_debug_encounter_reward_mode(encounter_key: String) -> int:
	if encounter_key == "trial":
		return ENUMS.RewardMode.ARCANA
	if encounter_key.begins_with("objective_"):
		return ENUMS.RewardMode.MISSION
	return ENUMS.RewardMode.BOON

@export var player_path: NodePath = NodePath("Player")
@export var encounter_count: int = 8
@export var room_base_size: Vector2 = Vector2(940.0, 700.0)
@export var room_size_growth: Vector2 = Vector2(80.0, 45.0)
@export var spawn_padding: float = 90.0
@export var spawn_safe_radius: float = 170.0
@export var static_camera_room_threshold: float = 980.0
@export var base_chaser_count: int = 5
@export var chasers_per_room: int = 2
@export var chargers_start_room: int = 2
@export var chargers_per_room: int = 1
@export var archer_start_room: int = 1
@export var archers_per_room: int = 1
@export var shielder_start_room: int = 2
@export var shielders_per_room: int = 1
@export var boss_chaser_count: int = 10
@export var boss_charger_count: int = 5
@export var door_distance_from_center: float = 290.0
@export var door_use_radius: float = 72.0
@export var camera_room_margin: Vector2 = Vector2(160.0, 120.0)
@export_range(0.85, 2.0, 0.01) var camera_base_zoom_in: float = 0.95
@export var boon_choice_count: int = 3
@export var camera_player_margin: float = 18.0
@export var boon_reveal_duration: float = 0.22
@export var floor_grid_step: float = 70.0
@export var floor_grid_fine_step: float = 35.0
@export var arena_glow_strength: float = 0.22
@export var ambient_backdrop_alpha: float = 0.96
@export var floor_coarse_grid_alpha: float = 0.075
@export var floor_fine_grid_alpha: float = 0.024
@export var floor_border_alpha: float = 0.72
@export var hud_background_alpha: float = 0.7
@export var normal_room_music: AudioStream
@export var boss_room_music: AudioStream
@export var music_volume_db: float = -20.0
@export var sfx_volume_db: float = 0.0
@export var music_intro_fade_duration: float = 1.6
@export var music_crossfade_duration: float = 0.75
@export var rest_heal_ratio: float = 0.32
@export var hard_room_enemy_bonus: int = 3
@export var second_boss_encounter_count: int = 7
var settings_enabled: bool = false
var apply_test_powers_on_start: bool = false
var skip_starting_boon_selection: bool = false
var start_power_preset: int = DEBUG_ENUMS.PowerPreset.NONE
var start_power_ids: PackedStringArray = PackedStringArray()
var start_encounter: int = ENCOUNTER_CONTRACTS.DEBUG_ENCOUNTER_NONE
var start_depth: int = 1
var start_bearing: int = -1
var mutator_override: int = DEBUG_ENUMS.MutatorOverride.NONE
var end_screen_preview: int = DEBUG_ENUMS.EndScreenPreview.NONE
var victory_unlock_tier: int = -1

var player: Node2D
var player_camera: Camera2D
var rng := RandomNumberGenerator.new()
var power_registry_instance: Node
var current_difficulty_tier: int = 0
var current_difficulty_config: Dictionary = {}

var rooms_cleared: int = 0
var room_depth: int = 0
var active_room_enemy_count: int = 0
var boss_unlocked: bool = false
var in_boss_room: bool = false
var in_second_boss_room: bool = false
var first_boss_defeated: bool = false
var phase_two_rooms_cleared: int = 0
var endless_boss_defeated: bool = false
var choosing_next_room: bool = false
var run_cleared: bool = false

var boons_taken: Array[String] = []
var arcana_rewards_taken: Array[String] = []

var current_room_size: Vector2 = Vector2.ZERO
var current_room_static_camera: bool = true
var current_room_label: String = ""
var door_options: Array[Dictionary] = []
var pending_room_reward: int = ENUMS.RewardMode.NONE
var current_room_enemy_mutator: Dictionary = {}
var current_room_player_mutator: Dictionary = {}
var active_objective_kind: String = ""
var objective_time_left: float = 0.0
var objective_spawn_interval: float = 0.0
var objective_spawn_timer: float = 0.0
var objective_spawn_batch: int = 1
var objective_max_enemies: int = 0
var objective_kill_target: int = 0
var objective_kills: int = 0
var objective_overtime: bool = false
var objective_survival_quota_announced: bool = false
var objective_target_enemy: CharacterBody2D
var objective_target_type: String = ""
var objective_target_name: String = ""
var objective_target_flee_thresholds: Array[float] = [0.75, 0.5, 0.25]
var objective_target_next_flee_index: int = 0
var objective_target_dash_line: Line2D
var objective_target_dash_line_time_left: float = 0.0
var objective_escort_dash_lines: Array[Line2D] = []
var objective_escort_dash_line_time_left: float = 0.0
var objective_hunt_kill_progress: int = 0
var objective_hunt_kill_goal: int = 4
var objective_control_anchor: Vector2 = Vector2.ZERO
var objective_control_radius: float = 0.0
var objective_control_progress: float = 0.0
var objective_control_goal: float = 0.0
var objective_control_decay_rate: float = 0.0
var objective_control_contest_threshold: int = 0
var objective_control_enemies_in_zone: int = 0
var objective_control_player_inside: bool = false
var objective_control_contested: bool = false
var objective_exposure_duration: float = 2.0
var objective_exposure_left: float = 0.0
var objective_exposure_push_duration: float = 1.2
var objective_exposure_push_left: float = 0.0
var objective_exposure_push_strength: float = 380.0
var objective_exposure_push_radius: float = 252.0
var objective_exposure_push_accel: float = 940.0
var objective_relocation_escort_radius: float = 236.0
var objective_relocation_escort_cap: int = 3
var objective_last_relocated_escort_count: int = 0
var objective_relocation_hint_left: float = 0.0
var objective_signal_fx_node: Node2D
var objective_signal_fx_left: float = 0.0
var objective_signal_fx_duration: float = 0.0
var objective_signal_fx_strength: float = 1.0
var objective_signal_fx_phase: float = 0.0

var encounter_intro_grace_active: bool = false

var hud: Node
var renderer: Node2D
var music_system: Node
var enemy_spawner: Node
var encounter_profile_builder
var encounter_flow_system
var objective_runtime: Node
var reward_selection_ui
var pause_menu_controller: Node
var victory_screen: Node
var defeat_screen: Node
var telemetry_run_id: String = ""
var telemetry_enabled: bool = false
var telemetry_run_finished: bool = false
var player_defeated: bool = false
var telemetry_spike_enabled: bool = false
var telemetry_spike_endpoint: String = ""
var telemetry_spike_api_key: String = ""
var telemetry_spike_timeout_seconds: float = 8.0
var telemetry_spike_sender: Node
var telemetry_spike_requested: bool = false

func _apply_debug_settings_from_node() -> void:
	var debug_settings := get_node_or_null("DebugSettings")
	if not (is_instance_valid(debug_settings) and debug_settings.get_script() == DEBUG_SETTINGS_SCRIPT):
		return
	settings_enabled = bool(debug_settings.get("enabled"))
	apply_test_powers_on_start = bool(debug_settings.get("apply_test_powers_on_start"))
	skip_starting_boon_selection = bool(debug_settings.get("skip_starting_boon_selection"))
	start_power_preset = int(debug_settings.get("start_power_preset"))
	var start_power_ids_value: Variant = debug_settings.get("start_power_ids")
	if start_power_ids_value is PackedStringArray:
		start_power_ids = start_power_ids_value
	else:
		start_power_ids = PackedStringArray()
	start_encounter = int(debug_settings.get("start_encounter"))
	start_depth = int(debug_settings.get("start_depth"))
	start_bearing = int(debug_settings.get("start_bearing"))
	mutator_override = int(debug_settings.get("mutator_override"))
	end_screen_preview = int(debug_settings.get("end_screen_preview"))
	victory_unlock_tier = int(debug_settings.get("victory_unlock_tier"))
	telemetry_spike_enabled = bool(debug_settings.get("telemetry_spike_enabled"))
	var telemetry_endpoint_value: Variant = debug_settings.get("telemetry_spike_endpoint")
	var telemetry_api_key_value: Variant = debug_settings.get("telemetry_spike_api_key")
	var telemetry_timeout_value: Variant = debug_settings.get("telemetry_spike_timeout_seconds")
	telemetry_spike_endpoint = String(telemetry_endpoint_value) if telemetry_endpoint_value != null else ""
	telemetry_spike_api_key = String(telemetry_api_key_value) if telemetry_api_key_value != null else ""
	telemetry_spike_timeout_seconds = float(telemetry_timeout_value) if telemetry_timeout_value != null else 8.0

func _ready() -> void:
	rng.randomize()
	_apply_debug_settings_from_node()
	_maybe_start_telemetry_spike_probe()
	power_registry_instance = POWER_REGISTRY.new()
	player = get_node_or_null(player_path) as Node2D
	if is_instance_valid(player):
		player.set_power_registry(power_registry_instance)
	if is_instance_valid(player):
		player_camera = player.get_node_or_null("Camera2D") as Camera2D
		if is_instance_valid(player_camera) and player_camera.has_method("set_room_fit_zoom_scale"):
			player_camera.call("set_room_fit_zoom_scale", camera_base_zoom_in)
		if player.has_signal("damage_taken"):
			player.connect("damage_taken", Callable(self, "_on_player_damage_taken"))
		if player.has_signal("died"):
			player.connect("died", Callable(self, "_on_player_died_for_telemetry"))
			player.connect("died", Callable(self, "_on_player_died"))
	_sync_audio_settings_from_context()
	endless_boss_defeated = false

	current_room_size = room_base_size
	current_room_label = "Starting Chamber"
	_apply_camera_bounds_for_room(current_room_size)
	music_system = MUSIC_SYSTEM_SCRIPT.new()
	add_child(music_system)
	music_system.initialize(normal_room_music, boss_room_music, music_volume_db, music_crossfade_duration)
	encounter_flow_system = ENCOUNTER_FLOW_SYSTEM_SCRIPT.new()
	add_child(encounter_flow_system)
	reward_selection_ui = REWARD_SELECTION_UI_SCRIPT.new()
	add_child(reward_selection_ui)
	reward_selection_ui.initialize(boon_choice_count, boon_reveal_duration)
	if reward_selection_ui.has_signal("reward_selected"):
		reward_selection_ui.connect("reward_selected", Callable(self, "_on_reward_selected"))
	encounter_profile_builder = ENCOUNTER_PROFILE_BUILDER_SCRIPT.new()
	add_child(encounter_profile_builder)
	encounter_profile_builder.initialize(rng)
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	var should_apply_difficulty := false
	var difficulty_tier := current_difficulty_tier
	if run_context != null:
		difficulty_tier = int(run_context.get_current_difficulty_tier())
		should_apply_difficulty = true
	var debug_bearing_tier := _debug_bearing_override_tier()
	if debug_bearing_tier >= 0:
		difficulty_tier = debug_bearing_tier
		should_apply_difficulty = true
	if should_apply_difficulty:
		encounter_profile_builder.set_difficulty_tier(difficulty_tier)
		_apply_difficulty_tier_bonuses(difficulty_tier)
	encounter_profile_builder.configure({
		"room_base_size": room_base_size,
		"room_size_growth": room_size_growth,
		"static_camera_room_threshold": static_camera_room_threshold,
		"base_chaser_count": base_chaser_count,
		"chasers_per_room": chasers_per_room,
		"chargers_start_room": chargers_start_room,
		"chargers_per_room": chargers_per_room,
		"archer_start_room": archer_start_room,
		"archers_per_room": archers_per_room,
		"shielder_start_room": shielder_start_room,
		"shielders_per_room": shielders_per_room,
		"hard_room_enemy_bonus": hard_room_enemy_bonus
	})
	enemy_spawner = ENEMY_SPAWNER_SCRIPT.new()
	add_child(enemy_spawner)
	enemy_spawner.initialize(self, player, rng, {
		"chaser": ENEMY_CHASER_SCRIPT,
		"charger": ENEMY_CHARGER_SCRIPT,
		"archer": ENEMY_ARCHER_SCRIPT,
		"shielder": ENEMY_SHIELDER_SCRIPT,
		"lurker": ENEMY_LURKER_SCRIPT,
		"ram": ENEMY_RAM_SCRIPT,
		"lancer": ENEMY_LANCER_SCRIPT
	}, Callable(self, "_on_room_enemy_died"))
	_play_room_music(false, false, music_intro_fade_duration)
	hud = WORLD_HUD_SCRIPT.new()
	add_child(hud)
	hud.setup(encounter_count, 18.0)
	renderer = WORLD_RENDERER_SCRIPT.new()
	add_child(renderer)
	renderer.configure({
		"ambient_backdrop_alpha": ambient_backdrop_alpha,
		"arena_glow_strength": arena_glow_strength,
		"floor_coarse_grid_alpha": floor_coarse_grid_alpha,
		"floor_fine_grid_alpha": floor_fine_grid_alpha,
		"floor_border_alpha": floor_border_alpha,
		"floor_grid_step": floor_grid_step,
		"floor_grid_fine_step": floor_grid_fine_step,
		"door_use_radius": door_use_radius,
	})
	pause_menu_controller = PAUSE_MENU_CONTROLLER_SCRIPT.new()
	add_child(pause_menu_controller)
	pause_menu_controller.initialize(RUN_CONTEXT_PATH, Callable(self, "_set_music_volume_runtime"), Callable(self, "_set_sfx_volume_runtime"))
	pause_menu_controller.connect("pause_opened", Callable(self, "_on_pause_menu_opened"))
	pause_menu_controller.connect("pause_closed", Callable(self, "_on_pause_menu_closed"))
	pause_menu_controller.connect("back_to_main_menu_requested", Callable(self, "_on_pause_back_to_menu_requested"))
	pause_menu_controller.connect("abandon_run_requested", Callable(self, "_on_pause_abandon_run_requested"))
	pause_menu_controller.connect("exit_game_requested", Callable(self, "_on_pause_exit_game_requested"))
	victory_screen = VICTORY_SCREEN_SCRIPT.new()
	add_child(victory_screen)
	victory_screen.connect("back_to_main_menu_requested", Callable(self, "_on_victory_back_to_menu"))
	defeat_screen = DEFEAT_SCREEN_SCRIPT.new()
	add_child(defeat_screen)
	defeat_screen.connect("back_to_main_menu_requested", Callable(self, "_on_defeat_back_to_menu"))
	objective_runtime = OBJECTIVE_RUNTIME_SCRIPT.new()
	add_child(objective_runtime)
	objective_runtime.initialize(self, rng)
	var resumed_run := _try_resume_saved_run()
	_initialize_run_telemetry(not _is_debug_boot_session())
	hud.refresh(_get_hud_state(), player)
	if resumed_run:
		return
	_apply_debug_start_powers_if_needed()
	if settings_enabled:
		match end_screen_preview:
			DEBUG_ENUMS.EndScreenPreview.VICTORY:
				victory_screen.show_victory(0, victory_unlock_tier)
				return
			DEBUG_ENUMS.EndScreenPreview.DEFEAT:
				defeat_screen.show_defeat("Debug Arena", max(1, start_depth))
				return
		if start_encounter != ENCOUNTER_CONTRACTS.DEBUG_ENCOUNTER_NONE:
			_start_debug_selected_encounter(start_encounter)
			return
	if settings_enabled and skip_starting_boon_selection:
		pending_room_reward = ENUMS.RewardMode.BOON
		_begin_room(_build_skirmish_profile(room_depth))
	else:
		_open_boon_selection("Choose Starting Arcana", true, ENUMS.RewardMode.ARCANA)

func start_run_with_powers(power_ids: Array[String]) -> Dictionary:
	var applied: Array[String] = []
	var unknown: Array[String] = []
	if not is_instance_valid(player):
		return {
			"applied": applied,
			"unknown": power_ids.duplicate()
		}

	for power_id in power_ids:
		var id := power_id.strip_edges().to_lower()
		if id.is_empty():
			continue
		if not _is_known_power_id(id):
			unknown.append(id)
			continue
		if bool(player.apply_power_for_test(id)):
			applied.append(id)
		else:
			unknown.append(id)

	hud.refresh(_get_hud_state(), player)
	return {
		"applied": applied,
		"unknown": unknown
	}

func start_run_with_command(command: String) -> Dictionary:
	return start_run_with_powers(_parse_power_command(command))

func start_run_with_preset(preset_key: String) -> Dictionary:
	var normalized := preset_key.strip_edges().to_lower()
	var preset := DEBUG_ENUMS.PowerPreset.NONE
	match normalized:
		"dash", "dasher", "dash_specialist", "dash specialist":
			preset = DEBUG_ENUMS.PowerPreset.DASH_SPECIALIST
		"bruiser", "no_dash_bruiser", "no dash bruiser", "iron_vanguard", "iron vanguard", "grounded", "non_dash", "non-dash":
			preset = DEBUG_ENUMS.PowerPreset.NO_DASH_BRUISER
		"marksman", "high_range_dps", "high range dps", "ranged", "range_dps", "range dps":
			preset = DEBUG_ENUMS.PowerPreset.HIGH_RANGE_DPS
		_:
			preset = DEBUG_ENUMS.PowerPreset.NONE
	return start_run_with_powers(_get_debug_power_preset_ids(preset, _debug_depth_for_power_preset()))

func get_balance_telemetry(max_runs: int = 10, max_age_days: int = 21, include_debug: bool = false, game_version: String = "") -> Dictionary:
	return RUN_TELEMETRY_STORE.build_balance_summary(max_runs, max_age_days, include_debug, game_version)

func go_do_that_thing(state: String) -> Dictionary:
	return start_debug_encounter(state)

func start_objective_test(kind: String = "") -> Dictionary:
	return _start_debug_objective_room(kind)

func start_last_stand_test() -> Dictionary:
	return _start_debug_objective_room("last_stand")

func start_endurance_test() -> Dictionary:
	return _start_debug_objective_room("last_stand")

func start_debug_encounter(encounter_key: String) -> Dictionary:
	var entry := _find_debug_encounter_entry(encounter_key)
	if entry.is_empty():
		return {"ok": false, "note": "Unknown encounter key."}
	return _start_debug_selected_encounter(entry["id"])

func _debug_encounter_key(encounter_state: int) -> String:
	return ENCOUNTER_CONTRACTS.debug_encounter_key_from_id(encounter_state)

func _start_debug_selected_encounter(encounter_state: int) -> Dictionary:
	_mark_telemetry_debug_mode()
	var encounter_key := _debug_encounter_key(encounter_state)
	if encounter_key.is_empty():
		return {"ok": true, "note": "No debug encounter selected."}
	if encounter_key == "boss_1":
		return _start_debug_boss_room()
	if encounter_key == "boss_2":
		return _start_debug_second_boss_room()

	_reset_for_debug_jump()
	var encounter_depth := start_depth
	rooms_cleared = encounter_depth - 1
	room_depth = encounter_depth
	boss_unlocked = false

	if encounter_key == "rest":
		_enter_rest_site()
		hud.refresh(_get_hud_state(), player)
		return {"ok": true, "state": "debug_encounter", "encounter": "Rest Site"}

	var profile := _build_debug_encounter_profile(encounter_key, encounter_depth)
	profile = _apply_debug_mutator_override(profile)
	if profile.is_empty():
		return {"ok": false, "state": "debug_encounter", "note": "Could not build encounter profile."}
	pending_room_reward = ENUMS.RewardMode.ARCANA if encounter_key == "trial" else ENUMS.RewardMode.BOON
	if encounter_key.begins_with("objective_"):
		pending_room_reward = ENUMS.RewardMode.MISSION
	_begin_room(profile)
	hud.refresh(_get_hud_state(), player)
	return {
		"ok": true,
		"state": "debug_encounter",
		"encounter": ENCOUNTER_CONTRACTS.profile_label(profile)
	}

func _start_debug_boss_room() -> Dictionary:
	_reset_for_debug_jump()
	rooms_cleared = encounter_count
	room_depth = encounter_count
	boss_unlocked = true
	first_boss_defeated = false
	in_second_boss_room = false
	phase_two_rooms_cleared = 0
	_begin_boss_room()
	hud.refresh(_get_hud_state(), player)
	return {"ok": true, "state": "debug_encounter", "encounter": "Warden"}

func _start_debug_second_boss_room() -> Dictionary:
	_reset_for_debug_jump()
	rooms_cleared = encounter_count + second_boss_encounter_count
	room_depth = rooms_cleared
	boss_unlocked = true
	first_boss_defeated = true
	in_second_boss_room = false
	phase_two_rooms_cleared = second_boss_encounter_count
	_begin_second_boss_room()
	hud.refresh(_get_hud_state(), player)
	return {"ok": true, "state": "debug_encounter", "encounter": "Sovereign"}

func _build_debug_encounter_profile(encounter_key: String, depth: int) -> Dictionary:
	if not is_instance_valid(encounter_profile_builder):
		return {}
	return encounter_profile_builder.build_debug_encounter_profile(encounter_key, depth)

func _debug_mutator_key(state_value: int) -> String:
	match state_value:
		DEBUG_ENUMS.MutatorOverride.BLOOD_RUSH:
			return "blood_rush"
		DEBUG_ENUMS.MutatorOverride.FLASHPOINT:
			return "flashpoint"
		DEBUG_ENUMS.MutatorOverride.SIEGEBREAK:
			return "siegebreak"
		DEBUG_ENUMS.MutatorOverride.IRON_VOLLEY:
			return "iron_volley"
		DEBUG_ENUMS.MutatorOverride.KILLBOX:
			return "killbox"
		DEBUG_ENUMS.MutatorOverride.RANDOM_HARD:
			return "random_hard"
		_:
			return ""

func _debug_bearing_override_tier() -> int:
	if not settings_enabled:
		return -1
	if start_bearing < META_PROGRESS.TIER_PILGRIM:
		return -1
	return clampi(start_bearing, META_PROGRESS.TIER_PILGRIM, META_PROGRESS.TIER_FORSWORN)

func _apply_debug_mutator_override(profile: Dictionary) -> Dictionary:
	if not settings_enabled:
		return profile
	if profile.is_empty():
		return profile
	var mutator_key := _debug_mutator_key(mutator_override)
	if mutator_key.is_empty():
		return profile
	if not is_instance_valid(encounter_profile_builder):
		return profile
	var mutator: Dictionary = encounter_profile_builder.build_debug_mutator(mutator_key)
	if mutator.is_empty():
		return profile
	return encounter_profile_builder.apply_mutator_variant_to_profile(profile, mutator, room_depth)

func _reset_for_debug_jump() -> void:
	if is_instance_valid(reward_selection_ui):
		reward_selection_ui.close_selection()
	_set_combat_paused(false)
	choosing_next_room = false
	door_options.clear()
	pending_room_reward = ENUMS.RewardMode.NONE
	run_cleared = false
	in_boss_room = false
	in_second_boss_room = false
	first_boss_defeated = false
	phase_two_rooms_cleared = 0
	endless_boss_defeated = false
	active_room_enemy_count = 0
	_clear_all_enemies()

	if is_instance_valid(player):
		player.global_position = Vector2.ZERO

func _start_debug_objective_room(kind: String = "") -> Dictionary:
	_mark_telemetry_debug_mode()
	_reset_for_debug_jump()
	var objective_depth := 1
	rooms_cleared = objective_depth - 1
	room_depth = objective_depth
	boss_unlocked = false
	var profile := _build_objective_test_profile(objective_depth, kind)
	profile = _apply_debug_mutator_override(profile)
	if profile.is_empty():
		return {"ok": false, "state": "objective_test", "note": "Could not build objective profile."}
	pending_room_reward = ENUMS.RewardMode.MISSION
	_begin_room(profile)
	hud.refresh(_get_hud_state(), player)
	return {
		"ok": true,
		"state": "objective_test",
		"objective": ENCOUNTER_CONTRACTS.profile_label(profile)
	}

func _build_objective_test_profile(depth: int, kind: String = "") -> Dictionary:
	if not is_instance_valid(encounter_profile_builder):
		return {}
	return encounter_profile_builder.build_objective_profile(depth, kind)

func _apply_debug_start_powers_if_needed() -> void:
	if not settings_enabled:
		return
	if not apply_test_powers_on_start:
		return
	var ids: Array[String] = []
	ids.append_array(_get_debug_power_preset_ids(start_power_preset, start_depth))
	for id in start_power_ids:
		ids.append(String(id))
	if ids.is_empty():
		return
	start_run_with_powers(ids)

func _debug_depth_for_power_preset() -> int:
	if settings_enabled:
		return maxi(1, start_depth)
	if room_depth > 0:
		return room_depth
	return 1

func _debug_preset_power_count_for_depth(depth: int) -> int:
	var clamped_depth := maxi(1, depth)
	return 2 + int(floor(float(clamped_depth - 1) / 2.0))

func _get_debug_power_preset_pool(preset: int) -> Array[String]:
	match preset:
		DEBUG_ENUMS.PowerPreset.DASH_SPECIALIST:
			return [
				"fleet_foot",
				"blink_dash",
				"surge_step",
				"phantom_step",
				"reaper_step",
				"static_wake",
				"wraithstep"
			]
		DEBUG_ENUMS.PowerPreset.NO_DASH_BRUISER:
			return [
				"heavy_blow",
				"wide_arc",
				"long_reach",
				"iron_skin",
				"heartstone",
				"battle_trance",
				"rupture_wave",
				"aegis_field",
				"hunters_snare"
			]
		DEBUG_ENUMS.PowerPreset.HIGH_RANGE_DPS:
			return [
				"first_strike",
				"heavy_blow",
				"long_reach",
				"razor_wind",
				"execution_edge",
				"storm_crown",
				"hunters_snare"
			]
		_:
			return []

func _get_debug_power_preset_ids(preset: int, depth: int = -1) -> Array[String]:
	var pool := _get_debug_power_preset_pool(preset)
	if pool.is_empty():
		return []
	var resolved_depth := depth if depth > 0 else _debug_depth_for_power_preset()
	var target_count := mini(pool.size(), _debug_preset_power_count_for_depth(resolved_depth))
	var selected: Array[String] = []
	for i in range(target_count):
		selected.append(pool[i])
	return selected

func _parse_power_command(command: String) -> Array[String]:
	var normalized := command.to_lower()
	for keyword in ["start", "a", "run", "with", "these", "powers", "power", "and"]:
		normalized = normalized.replace(keyword, " ")
	for sep in [",", ";", "|", "\n", "\t"]:
		normalized = normalized.replace(sep, " ")

	var ids: Array[String] = []
	for token in normalized.split(" ", false):
		var id := token.strip_edges()
		if id.is_empty():
			continue
		ids.append(id)
	return ids

func _is_known_power_id(power_id: String) -> bool:
	return power_registry_instance.is_valid_power_id(power_id)

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(defeat_screen) and bool(defeat_screen.is_open()):
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if not is_instance_valid(pause_menu_controller):
		return
	if bool(pause_menu_controller.is_open()) and bool(pause_menu_controller.is_options_open()):
		pause_menu_controller.close_options()
		get_viewport().set_input_as_handled()
		return
	if bool(pause_menu_controller.is_open()) and bool(pause_menu_controller.is_glossary_open()):
		pause_menu_controller.close_glossary()
		get_viewport().set_input_as_handled()
		return
	if bool(pause_menu_controller.is_open()):
		pause_menu_controller.close()
		get_viewport().set_input_as_handled()
		return
	pause_menu_controller.open()
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if is_instance_valid(defeat_screen) and bool(defeat_screen.is_open()):
		hud.refresh(_get_hud_state(), player)
		_sync_renderer()
		return
	if is_instance_valid(pause_menu_controller) and bool(pause_menu_controller.is_open()):
		hud.refresh(_get_hud_state(), player)
		_sync_renderer()
		return
	if is_instance_valid(reward_selection_ui) and reward_selection_ui.is_active():
		reward_selection_ui.process_input(delta)
		hud.refresh(_get_hud_state(), player)
		_sync_renderer()
		return

	_keep_player_inside_current_room()
	_keep_enemies_inside_current_room()
	_keep_player_inside_camera_view()
	var _grace_active := _update_encounter_intro_grace()
	if not _grace_active:
		_update_objective_state(delta)
	_update_priority_target_marker(delta)
	if active_objective_kind == "control" or objective_control_radius > 0.0:
		queue_redraw()
	_try_use_door()
	_update_encounter_state()
	_update_camera_mode()
	hud.refresh(_get_hud_state(), player)
	_sync_renderer()

func _draw() -> void:
	if objective_control_radius <= 0.0:
		return
	if active_objective_kind != "control" and objective_control_progress <= 0.0:
		return
	var goal := maxf(0.01, objective_control_goal)
	var progress_ratio := clampf(objective_control_progress / goal, 0.0, 1.0)
	var fill_color := Color(0.32, 0.72, 0.96, 0.08)
	var ring_color := Color(0.46, 0.86, 1.0, 0.4)
	var progress_color := Color(0.98, 0.86, 0.42, 0.92)
	if objective_control_player_inside and not objective_control_contested:
		fill_color = Color(0.38, 0.92, 0.62, 0.1)
		ring_color = Color(0.56, 1.0, 0.74, 0.5)
		progress_color = Color(0.92, 1.0, 0.7, 0.98)
	elif objective_control_contested:
		fill_color = Color(0.98, 0.46, 0.34, 0.08)
		ring_color = Color(1.0, 0.64, 0.44, 0.54)
		progress_color = Color(1.0, 0.8, 0.52, 0.94)
	draw_circle(objective_control_anchor, objective_control_radius, fill_color)
	draw_arc(objective_control_anchor, objective_control_radius, 0.0, TAU, 72, ring_color, 3.0)
	draw_arc(objective_control_anchor, objective_control_radius - 8.0, -PI * 0.5, -PI * 0.5 + TAU * progress_ratio, 64, progress_color, 6.0)
	draw_circle(objective_control_anchor, 8.0, Color(1.0, 0.96, 0.72, 0.75))

func _update_objective_state(delta: float) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.update_objective_state(delta)

func _update_survival_objective_state(delta: float) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.update_survival_objective_state(delta)

func _update_priority_target_objective_state(delta: float) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.update_priority_target_objective_state(delta)

func _spawn_survival_wave() -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.spawn_survival_wave()

func _spawn_priority_target_wave() -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.spawn_priority_target_wave()

func _update_priority_target_exposure_state(delta: float) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.update_priority_target_exposure_state(delta)

func _trigger_priority_target_exposure(banner_title: String = "Signal Exposed", banner_subtitle: String = "Take the shot", duration_override: float = -1.0, fx_strength: float = 1.0) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.trigger_priority_target_exposure(banner_title, banner_subtitle, duration_override, fx_strength)

func _apply_priority_target_exposure_push(delta: float) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.apply_priority_target_exposure_push(delta)

func _complete_current_objective(title: String, _subtitle: String) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.complete_current_objective(title, _subtitle)

func _spawn_priority_target_enemy() -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.spawn_priority_target_enemy()

func _spawn_priority_target_opening_escorts() -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.spawn_priority_target_opening_escorts()

func _check_priority_target_relocation_threshold() -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.check_priority_target_relocation_threshold()

func _trigger_priority_target_threshold_phase(_threshold_ratio: float) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.trigger_priority_target_threshold_phase(_threshold_ratio)

func _relocate_priority_target(_threshold_ratio: float) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.relocate_priority_target(_threshold_ratio)

func _relocate_priority_target_nearby_escorts(old_position: Vector2, new_position: Vector2) -> int:
	if is_instance_valid(objective_runtime):
		return objective_runtime.relocate_priority_target_nearby_escorts(old_position, new_position)
	return 0

func _pick_priority_target_relocation_position(old_position: Vector2) -> Vector2:
	if is_instance_valid(objective_runtime):
		return objective_runtime.pick_priority_target_relocation_position(old_position)
	return old_position

func _spawn_priority_target_relocation_escorts(anchor: Vector2) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.spawn_priority_target_relocation_escorts(anchor)

func _show_priority_target_dash_line(from_position: Vector2, to_position: Vector2) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.show_priority_target_dash_line(from_position, to_position)

func _clear_priority_target_dash_line() -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.clear_priority_target_dash_line()

func _show_priority_target_escort_carry_lines(paths: Array[Dictionary]) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.show_priority_target_escort_carry_lines(paths)

func _clear_priority_target_escort_dash_lines() -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.clear_priority_target_escort_dash_lines()
	objective_escort_dash_line_time_left = 0.0

func _show_priority_target_exposure_vfx(strength: float, duration: float) -> void:
	if not is_instance_valid(objective_target_enemy):
		return
	_clear_priority_target_exposure_vfx()
	objective_signal_fx_node = Node2D.new()
	objective_signal_fx_node.name = "PriorityTargetExposureFX"
	objective_signal_fx_node.z_as_relative = false
	objective_signal_fx_node.z_index = 49
	add_child(objective_signal_fx_node)
	var fill := Polygon2D.new()
	fill.color = Color(1.0, 0.9, 0.46, 0.22)
	fill.z_as_relative = false
	fill.z_index = 49
	objective_signal_fx_node.add_child(fill)
	for _i in range(2):
		var ring := Line2D.new()
		ring.width = 3.8
		ring.default_color = Color(1.0, 0.95, 0.68, 0.92)
		ring.z_as_relative = false
		ring.z_index = 50
		objective_signal_fx_node.add_child(ring)
	for _i in range(6):
		var spoke := Line2D.new()
		spoke.width = 2.4
		spoke.default_color = Color(1.0, 0.9, 0.58, 0.86)
		spoke.z_as_relative = false
		spoke.z_index = 50
		objective_signal_fx_node.add_child(spoke)
	objective_signal_fx_left = duration
	objective_signal_fx_duration = duration
	objective_signal_fx_strength = strength
	objective_signal_fx_phase = 0.0
	_refresh_priority_target_exposure_vfx()

func _refresh_priority_target_exposure_vfx() -> void:
	if not is_instance_valid(objective_signal_fx_node):
		return
	if not is_instance_valid(objective_target_enemy):
		return
	if objective_signal_fx_node.get_child_count() < 9:
		return
	var origin := objective_target_enemy.global_position
	var life_t := clampf(objective_signal_fx_left / maxf(0.01, objective_signal_fx_duration), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(objective_signal_fx_phase * 11.0)
	var outer_radius := 126.0 + objective_signal_fx_strength * 30.0 + pulse * 12.0
	var inner_radius := outer_radius * 0.58
	var fill := objective_signal_fx_node.get_child(0) as Polygon2D
	if fill != null:
		var cone := PackedVector2Array()
		var segments := 24
		for i in range(segments):
			var angle := TAU * (float(i) / float(segments))
			cone.append(origin + Vector2.RIGHT.rotated(angle) * inner_radius)
		fill.polygon = cone
		fill.color = Color(1.0, 0.9, 0.46, (0.08 + pulse * 0.08) * life_t)
	for i in range(2):
		var ring := objective_signal_fx_node.get_child(1 + i) as Line2D
		if ring == null:
			continue
		var radius := outer_radius - float(i) * 22.0
		var points := PackedVector2Array()
		var segments := 40
		for p in range(segments + 1):
			var angle := TAU * (float(p) / float(segments))
			points.append(origin + Vector2.RIGHT.rotated(angle) * radius)
		ring.points = points
		ring.width = 2.2 + life_t * 2.4
		ring.default_color = Color(1.0, 0.95, 0.68, (0.2 + pulse * 0.6) * life_t)
	for i in range(6):
		var spoke := objective_signal_fx_node.get_child(3 + i) as Line2D
		if spoke == null:
			continue
		var angle := objective_signal_fx_phase * 0.9 + TAU * (float(i) / 6.0)
		var from_p := origin + Vector2.RIGHT.rotated(angle) * (inner_radius * 0.64)
		var to_p := origin + Vector2.RIGHT.rotated(angle) * (outer_radius + pulse * 8.0)
		spoke.points = PackedVector2Array([from_p, to_p])
		spoke.default_color = Color(1.0, 0.9, 0.58, (0.12 + pulse * 0.36) * life_t)
		spoke.width = 1.4 + life_t * 1.8

func _clear_priority_target_exposure_vfx() -> void:
	if is_instance_valid(objective_signal_fx_node):
		objective_signal_fx_node.queue_free()
	objective_signal_fx_node = null
	objective_signal_fx_left = 0.0

func _clamp_position_to_current_room(target_position: Vector2, margin: float = 28.0) -> Vector2:
	if current_room_size == Vector2.ZERO:
		return target_position
	var half := current_room_size * 0.5 - Vector2.ONE * margin
	return Vector2(
		clampf(target_position.x, -half.x, half.x),
		clampf(target_position.y, -half.y, half.y)
	)

func _attach_priority_target_marker(enemy: CharacterBody2D) -> void:
	var existing := enemy.get_node_or_null("PriorityTargetMarker")
	if existing != null:
		existing.queue_free()
	var marker := Node2D.new()
	marker.name = "PriorityTargetMarker"
	marker.position = Vector2(0.0, -62.0)
	marker.z_as_relative = false
	marker.z_index = 50
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([
		Vector2(0.0, -8.0),
		Vector2(8.0, 0.0),
		Vector2(0.0, 8.0),
		Vector2(-8.0, 0.0)
	])
	diamond.color = Color(1.0, 0.84, 0.3, 0.95)
	marker.add_child(diamond)
	var stem := Line2D.new()
	stem.width = 2.0
	stem.default_color = Color(1.0, 0.9, 0.46, 0.9)
	stem.points = PackedVector2Array([Vector2(0.0, 8.0), Vector2(0.0, 16.0)])
	marker.add_child(stem)
	enemy.add_child(marker)

func _update_priority_target_marker(delta: float) -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.update_priority_target_marker(delta)
		var escort_alpha := clampf(objective_escort_dash_line_time_left / 0.48, 0.0, 1.0)
		for line in objective_escort_dash_lines:
			if not is_instance_valid(line):
				continue
			line.default_color = Color(0.9, 0.98, 1.0, 0.96 * escort_alpha)
			line.width = 2.6 + 2.8 * escort_alpha
		if objective_escort_dash_line_time_left <= 0.0:
			_clear_priority_target_escort_dash_lines()
	if objective_target_dash_line_time_left > 0.0:
		objective_target_dash_line_time_left = maxf(0.0, objective_target_dash_line_time_left - delta)
		if is_instance_valid(objective_target_dash_line):
			var alpha := clampf(objective_target_dash_line_time_left / 0.34, 0.0, 1.0)
			objective_target_dash_line.default_color = Color(1.0, 0.9, 0.54, 0.96 * alpha)
			objective_target_dash_line.width = 3.6 + 3.0 * alpha
		if objective_target_dash_line_time_left <= 0.0:
			_clear_priority_target_dash_line()
	if not is_instance_valid(objective_target_enemy):
		return
	var marker := objective_target_enemy.get_node_or_null("PriorityTargetMarker") as Node2D
	if marker == null:
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	marker.scale = Vector2.ONE * (1.0 + 0.08 * sin(t * 5.0))
	var diamond := marker.get_child(0) as Polygon2D
	var stem := marker.get_child(1) as Line2D
	if diamond != null:
		if objective_exposure_left > 0.0:
			diamond.color = Color(1.0, 0.98, 0.7, 1.0)
		elif objective_overtime:
			diamond.color = Color(1.0, 0.44, 0.32, 0.96)
		else:
			diamond.color = Color(1.0, 0.84, 0.3, 0.95)
	if stem != null:
		if objective_exposure_left > 0.0:
			stem.default_color = Color(1.0, 0.94, 0.62, 0.98)
		elif objective_overtime:
			stem.default_color = Color(1.0, 0.62, 0.36, 0.92)
		else:
			stem.default_color = Color(1.0, 0.9, 0.46, 0.9)

func _enrage_priority_target() -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime.enrage_priority_target()

func _on_priority_target_died() -> void:
	if is_instance_valid(objective_runtime):
		objective_runtime._on_priority_target_died()

func _get_hud_state() -> Dictionary:
	var display_room_depth := room_depth
	var between_rooms := choosing_next_room or _is_reward_selection_active()
	var display_enemy_mutator := current_room_enemy_mutator
	if between_rooms:
		display_enemy_mutator = {}
	# Keep the visible depth anchored to the cleared room until the next room is entered.
	if between_rooms and not run_cleared and current_room_label != "Rest Site":
		display_room_depth = maxi(0, room_depth - 1)
	var hud_state := {
		"room_size": current_room_size,
		"current_room_label": current_room_label,
		"current_difficulty_tier": current_difficulty_tier,
		"rooms_cleared": rooms_cleared,
		"room_depth": display_room_depth,
		"run_cleared": run_cleared,
		"current_room_enemy_mutator": display_enemy_mutator,
		"in_boss_room": in_boss_room,
		"active_room_enemy_count": active_room_enemy_count,
		"active_objective_kind": active_objective_kind,
		"objective_time_left": objective_time_left,
		"objective_kills": objective_kills,
		"objective_kill_target": objective_kill_target,
		"objective_overtime": objective_overtime,
		"objective_target_name": objective_target_name,
		"objective_target_health": _get_priority_target_health(),
		"objective_target_max_health": _get_priority_target_max_health(),
		"objective_hunt_kill_progress": objective_hunt_kill_progress,
		"objective_hunt_kill_goal": objective_hunt_kill_goal,
		"objective_control_progress": objective_control_progress,
		"objective_control_goal": objective_control_goal,
		"objective_control_enemies_in_zone": objective_control_enemies_in_zone,
		"objective_control_contested": objective_control_contested,
		"objective_control_player_inside": objective_control_player_inside,
		"objective_exposure_left": objective_exposure_left,
		"objective_last_relocated_escort_count": objective_last_relocated_escort_count,
		"objective_relocation_hint_left": objective_relocation_hint_left,
		"active_player_mutators": _get_active_player_mutators_for_hud(),
		"objective_target_flee_thresholds": objective_target_flee_thresholds,
		"objective_target_next_flee_index": objective_target_next_flee_index,
		"encounter_intro_grace_active": encounter_intro_grace_active,
		"boss_unlocked": boss_unlocked,
		"first_boss_defeated": first_boss_defeated,
		"second_boss_unlocked": _is_second_boss_unlocked(),
	}
	return hud_state

func _get_priority_target_health() -> int:
	if not is_instance_valid(objective_target_enemy):
		return 0
	return int(objective_target_enemy._get_current_health())

func _get_priority_target_max_health() -> int:
	if not is_instance_valid(objective_target_enemy):
		return 0
	if objective_target_enemy.get("max_health") != null:
		return int(objective_target_enemy.get("max_health"))
	return 0

func _sync_renderer() -> void:
	if not is_instance_valid(renderer):
		return
	renderer.room_size = current_room_size
	renderer.choosing_next_room = choosing_next_room
	renderer.door_options = door_options
	renderer.player_global_position = player.global_position if is_instance_valid(player) else Vector2.ZERO

func _keep_player_inside_current_room() -> void:
	if not is_instance_valid(player):
		return
	if current_room_size == Vector2.ZERO:
		return
	var half := current_room_size * 0.5
	player.global_position.x = clampf(player.global_position.x, -half.x, half.x)
	player.global_position.y = clampf(player.global_position.y, -half.y, half.y)

func _keep_enemies_inside_current_room() -> void:
	if current_room_size == Vector2.ZERO:
		return
	var half := current_room_size * 0.5
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not (enemy is Node2D):
			continue
		var enemy_body := enemy as Node2D
		enemy_body.global_position.x = clampf(enemy_body.global_position.x, -half.x, half.x)
		enemy_body.global_position.y = clampf(enemy_body.global_position.y, -half.y, half.y)

func _keep_player_inside_camera_view() -> void:
	if not is_instance_valid(player):
		return
	if not is_instance_valid(player_camera):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var half_view := Vector2(
		viewport_size.x * 0.5 / maxf(0.001, player_camera.zoom.x),
		viewport_size.y * 0.5 / maxf(0.001, player_camera.zoom.y)
	)
	var min_visible := player_camera.global_position - half_view + Vector2.ONE * camera_player_margin
	var max_visible := player_camera.global_position + half_view - Vector2.ONE * camera_player_margin

	player.global_position.x = clampf(player.global_position.x, min_visible.x, max_visible.x)
	player.global_position.y = clampf(player.global_position.y, min_visible.y, max_visible.y)

func _update_encounter_state() -> void:
	if choosing_next_room or run_cleared:
		return
	if active_objective_kind == "survival" or active_objective_kind == "priority_target" or active_objective_kind == "control":
		return
	if active_room_enemy_count > 0:
		return
	_on_room_cleared()

func _on_room_cleared() -> void:
	if not is_instance_valid(encounter_flow_system):
		return
	if in_second_boss_room:
		_finish_second_boss_clear()
		return
	if in_boss_room and not first_boss_defeated:
		_finish_first_boss_clear()
		return
	var raw_outcome: Variant = encounter_flow_system.resolve_room_cleared(in_boss_room, pending_room_reward, rooms_cleared, room_depth, encounter_count)
	var outcome: Dictionary = ENCOUNTER_CONTRACTS.normalize_room_cleared_outcome(raw_outcome)
	run_cleared = ENCOUNTER_CONTRACTS.outcome_run_cleared(outcome)
	if run_cleared and _is_endless_mode() and in_boss_room:
		run_cleared = false
		in_boss_room = false
		endless_boss_defeated = true
		rooms_cleared += 1
		room_depth += 1
		boss_unlocked = false
		pending_room_reward = ENUMS.RewardMode.NONE
		hud.show_banner("Boss Defeated", "")
		_spawn_door_options()
		return
	if run_cleared:
		choosing_next_room = false
		return
	rooms_cleared = ENCOUNTER_CONTRACTS.outcome_rooms_cleared(outcome)
	room_depth = ENCOUNTER_CONTRACTS.outcome_room_depth(outcome)
	if first_boss_defeated:
		phase_two_rooms_cleared += 1
		boss_unlocked = _is_second_boss_unlocked()
	else:
		boss_unlocked = ENCOUNTER_CONTRACTS.outcome_boss_unlocked(outcome)
	if _is_endless_mode() and endless_boss_defeated:
		boss_unlocked = false
	pending_room_reward = ENCOUNTER_CONTRACTS.outcome_pending_room_reward(outcome)
	var reward_mode: int = ENCOUNTER_CONTRACTS.outcome_open_reward_mode(outcome)
	if reward_mode == ENUMS.RewardMode.BOON:
		_open_boon_selection("Choose Boon Reward", false, ENUMS.RewardMode.BOON)
		return
	if reward_mode == ENUMS.RewardMode.MISSION:
		_open_boon_selection("Choose Mission Reward", false, ENUMS.RewardMode.MISSION, current_room_player_mutator)
		return
	if reward_mode == ENUMS.RewardMode.ARCANA:
		_open_boon_selection("Choose Arcana", false, ENUMS.RewardMode.ARCANA)
		return
	if ENCOUNTER_CONTRACTS.outcome_spawn_doors(outcome):
		_spawn_door_options()

func _finish_first_boss_clear() -> void:
	in_boss_room = false
	first_boss_defeated = true
	in_second_boss_room = false
	phase_two_rooms_cleared = 0
	rooms_cleared += 1
	room_depth += 1
	boss_unlocked = false
	pending_room_reward = ENUMS.RewardMode.NONE
	hud.show_banner("Warden Defeated", "")
	_spawn_door_options()

func _finish_second_boss_clear() -> void:
	in_second_boss_room = false
	active_room_enemy_count = 0
	run_cleared = true
	_finish_active_run_telemetry("clear")
	choosing_next_room = false
	boss_unlocked = false
	pending_room_reward = ENUMS.RewardMode.NONE
	_clear_active_run_checkpoint()
	hud.show_banner("Run Complete", "")
	if is_instance_valid(victory_screen):
		var run_context := _get_run_context()
		var unlocked_tier := -1
		if run_context != null:
			run_context.set_last_run_outcome("clear")
			run_context.award_run_clear_unlocks()
			unlocked_tier = int(run_context.consume_just_unlocked_tier())
		victory_screen.show_victory(rooms_cleared, unlocked_tier)

func _get_run_context() -> Node:
	return get_node_or_null(RUN_CONTEXT_PATH)

func _apply_difficulty_tier_bonuses(difficulty_tier: int) -> void:
	if not is_instance_valid(player):
		return
	
	current_difficulty_tier = difficulty_tier
	current_difficulty_config = DIFFICULTY_CONFIG.get_tier_config(difficulty_tier)
	var difficulty_config := current_difficulty_config
	var encounter_target := int(difficulty_config.get("encounter_count_before_boss", encounter_count))
	if encounter_target > 0:
		encounter_count = encounter_target
		second_boss_encounter_count = maxi(1, encounter_target - 1)

	player.set_incoming_damage_taken_mult(float(difficulty_config.get("player_damage_taken_mult", 1.0)))
	player.set_incoming_contact_damage_mult(float(difficulty_config.get("enemy_contact_damage_mult", 1.0)))
	var health_bonus := float(difficulty_config.get("player_starting_health_bonus", 0.0))
	if health_bonus > 0.0 and player.get("max_health") != null:
		var current_max := int(player.get("max_health"))
		var new_max := current_max + int(health_bonus)
		player.set("max_health", new_max)
		if player.get("health_state") != null:
			var health_state: Object = player.get("health_state")
			health_state.setup(new_max)

func _get_second_boss_target_depth() -> int:
	return maxi(encounter_count + 1, encounter_count * 2)

func _build_route_context(depth: int) -> Dictionary:
	var target_depth := encounter_count
	if first_boss_defeated:
		target_depth = _get_second_boss_target_depth()
	return {
		"depth": depth,
		"rooms_until_boss": maxi(0, target_depth - depth)
	}

func _is_second_boss_unlocked() -> bool:
	return first_boss_defeated and room_depth >= _get_second_boss_target_depth()

func _get_boss_difficulty_mult() -> float:
	if current_difficulty_config.is_empty():
		return 1.0
	return float(current_difficulty_config.get("boss_difficulty_mult", 1.0))

func _objective_pressure_mult() -> float:
	return DIFFICULTY_CONFIG.get_objective_pressure_mult(current_difficulty_tier)

func _apply_boss_difficulty_scaling(boss: CharacterBody2D) -> void:
	if not is_instance_valid(boss):
		return
	var boss_mult := _get_boss_difficulty_mult()
	if is_equal_approx(boss_mult, 1.0):
		return
	if boss.get("max_health") != null:
		var base_max_health := int(boss.get("max_health"))
		var scaled_max_health := maxi(1, int(round(float(base_max_health) * boss_mult)))
		boss.set("max_health", scaled_max_health)
		if boss.get("health_state") != null:
			var health_state: Object = boss.get("health_state") as Object
			if health_state != null:
				health_state.setup(scaled_max_health)
	for damage_property in ["charge_damage", "nova_damage", "cleave_damage", "prism_damage", "gravity_damage", "echo_dash_damage", "orbital_lance_damage", "polar_shift_pull_inner_damage"]:
		if boss.get(damage_property) == null:
			continue
		var base_damage := int(boss.get(damage_property))
		boss.set(damage_property, maxi(1, int(round(float(base_damage) * boss_mult))))

func _try_resume_saved_run() -> bool:
	var run_context := _get_run_context()
	if run_context == null:
		return false
	if not bool(run_context.consume_resume_saved_run_request()):
		return false
	var snapshot := run_context.load_active_run() as Dictionary
	if snapshot.is_empty():
		return false
	if int(snapshot.get("version", -1)) != RUN_SNAPSHOT_VERSION:
		run_context.clear_active_run()
		return false
	if not _apply_active_run_snapshot(snapshot):
		run_context.clear_active_run()
		return false
	return true

func _save_active_run_checkpoint() -> void:
	var run_context := _get_run_context()
	if run_context == null:
		return
	var snapshot := _build_active_run_snapshot()
	if snapshot.is_empty():
		return
	run_context.save_active_run(snapshot)

func _clear_active_run_checkpoint() -> void:
	var run_context := _get_run_context()
	if run_context == null:
		return
	run_context.clear_active_run()
	run_context.clear_resume_saved_run_request()

func _build_active_run_snapshot() -> Dictionary:
	var run_context := _get_run_context()
	var fallback_run_mode: Variant = ENUMS.RunMode.ENDLESS if _is_endless_mode() else ENUMS.RunMode.STANDARD
	return RUN_SNAPSHOT_SERVICE.build_snapshot(self, player, run_context, RUN_SNAPSHOT_VERSION, fallback_run_mode)

func _apply_active_run_snapshot(snapshot: Dictionary) -> bool:
	var run_context := _get_run_context()
	if not RUN_SNAPSHOT_SERVICE.apply_snapshot(
		self,
		player,
		run_context,
		snapshot,
		room_base_size,
		ENUMS.RunMode.STANDARD,
		ENUMS.RewardMode.NONE
	):
		return false

	_clear_all_enemies()
	player.global_position = Vector2.ZERO
	_apply_camera_bounds_for_room(current_room_size)
	_play_room_music(false, false)
	hud.refresh(_get_hud_state(), player)
	_set_combat_paused(false)
	return true

func _is_endless_mode() -> bool:
	var run_context := _get_run_context()
	if run_context == null:
		return false
	return bool(run_context.is_endless_mode())

func _sync_audio_settings_from_context() -> void:
	var run_context := _get_run_context()
	if run_context == null:
		return
	var music_volume_value: Variant = run_context.get("music_volume_db")
	if music_volume_value != null:
		music_volume_db = AUDIO_LEVELS.clamp_db(float(music_volume_value))
	var sfx_volume_value: Variant = run_context.get("sfx_volume_db")
	if sfx_volume_value != null:
		sfx_volume_db = AUDIO_LEVELS.clamp_db(float(sfx_volume_value))
	_set_sfx_volume_runtime(sfx_volume_db)

func _is_reward_selection_active() -> bool:
	return is_instance_valid(reward_selection_ui) and reward_selection_ui.is_active()

func _set_music_volume_runtime(music_db: float) -> void:
	music_volume_db = AUDIO_LEVELS.clamp_db(music_db)
	if is_instance_valid(music_system):
		music_system.set_music_volume_db(music_volume_db)

func _set_sfx_volume_runtime(volume_db: float) -> void:
	sfx_volume_db = AUDIO_LEVELS.clamp_db(volume_db)
	if is_instance_valid(player) and player.has_method("set_sfx_volume_db"):
		player.call("set_sfx_volume_db", sfx_volume_db)

func _on_pause_menu_opened() -> void:
	_set_combat_paused(true)

func _on_pause_menu_closed() -> void:
	_set_combat_paused(_is_reward_selection_active())

func _on_victory_back_to_menu() -> void:
	_finish_active_run_telemetry("clear")
	_clear_active_run_checkpoint()
	get_tree().change_scene_to_file(MENU_SCENE_PATH)

func _on_defeat_back_to_menu() -> void:
	_set_combat_paused(false)
	_finish_active_run_telemetry("death")
	_clear_active_run_checkpoint()
	get_tree().change_scene_to_file(MENU_SCENE_PATH)

func _on_pause_back_to_menu_requested() -> void:
	_finish_active_run_telemetry("menu_exit")
	_set_combat_paused(false)
	if is_instance_valid(pause_menu_controller):
		pause_menu_controller.close()
	get_tree().change_scene_to_file(MENU_SCENE_PATH)

func _on_pause_abandon_run_requested() -> void:
	_set_combat_paused(false)
	if is_instance_valid(pause_menu_controller):
		pause_menu_controller.close()
	var run_context := get_node_or_null(RUN_CONTEXT_PATH)
	if run_context != null:
		run_context.set_last_run_outcome("death")
	_finish_active_run_telemetry("abandon")
	_clear_active_run_checkpoint()
	get_tree().change_scene_to_file(MENU_SCENE_PATH)

func _on_pause_exit_game_requested() -> void:
	_finish_active_run_telemetry("quit")
	get_tree().quit()

func _spawn_door_options() -> void:
	if not is_instance_valid(encounter_flow_system):
		return
	door_options.clear()
	choosing_next_room = true
	var route_options := _roll_route_options(_build_route_context(room_depth))
	var show_boss_door := boss_unlocked
	if first_boss_defeated:
		show_boss_door = _is_second_boss_unlocked()
		boss_unlocked = show_boss_door
	door_options = encounter_flow_system.build_door_options(show_boss_door, room_depth, door_distance_from_center, route_options)
	if show_boss_door and not door_options.is_empty():
		if first_boss_defeated:
			door_options[0]["label"] = "Sovereign"
			door_options[0]["color"] = Color(0.92, 0.28, 0.1, 0.98)
		else:
			door_options[0]["label"] = "Warden"
			door_options[0]["color"] = Color(0.96, 0.46, 0.18, 0.98)
	_save_active_run_checkpoint()

func _try_use_door() -> void:
	if not choosing_next_room:
		return
	if not is_instance_valid(player):
		return
	if not Input.is_action_just_pressed("interact"):
		return
	if not is_instance_valid(encounter_flow_system):
		return
	var raw_result: Variant = encounter_flow_system.find_used_door(player.global_position, door_options, door_use_radius)
	var result: Dictionary = ENCOUNTER_CONTRACTS.normalize_door_use_result(raw_result)
	if not ENCOUNTER_CONTRACTS.door_use_is_used(result):
		return
	var used_door := ENCOUNTER_CONTRACTS.door_use_get_door(result)
	_choose_door(used_door)

func _choose_door(door: Dictionary) -> void:
	choosing_next_room = false
	door_options.clear()
	_clear_all_enemies()

	if not is_instance_valid(player):
		return
	player.global_position = Vector2.ZERO
	if not is_instance_valid(encounter_flow_system):
		return
	var raw_choice: Variant = encounter_flow_system.resolve_chosen_door(door)
	var choice: Dictionary = ENCOUNTER_CONTRACTS.normalize_door_choice(raw_choice)
	_record_door_choice(choice)
	var action_id: int = ENCOUNTER_CONTRACTS.door_choice_action_id(choice)
	if action_id == ENUMS.EncounterAction.BOSS:
		if first_boss_defeated:
			_begin_second_boss_room()
		else:
			_begin_boss_room()
		return
	if action_id == ENUMS.EncounterAction.REST:
		_enter_rest_site()
		return
	var profile: Dictionary = ENCOUNTER_CONTRACTS.door_choice_profile(choice)
	profile = _apply_endless_scaling_to_profile(profile)
	pending_room_reward = ENCOUNTER_CONTRACTS.door_choice_reward_mode(choice)
	current_room_enemy_mutator = profile.get("enemy_mutator", {})
	_begin_room(profile)

func _apply_endless_scaling_to_profile(profile: Dictionary) -> Dictionary:
	if profile.is_empty():
		return profile
	if not _is_endless_mode() or not endless_boss_defeated:
		return profile

	var endless_depth := maxi(0, room_depth - encounter_count)
	if endless_depth <= 0:
		return profile

	# Aggressive endless scaling: tier rises every depth after first boss clear.
	var tier := endless_depth
	var scaled := ENCOUNTER_CONTRACTS.normalize_profile(profile.duplicate(true))
	var scaled_chasers := ENCOUNTER_CONTRACTS.profile_chaser_count(scaled) + tier
	var scaled_chargers := ENCOUNTER_CONTRACTS.profile_charger_count(scaled) + int(floor(float(tier) * 0.75))
	var scaled_archers := ENCOUNTER_CONTRACTS.profile_archer_count(scaled) + int(floor(float(tier) * 0.65))
	var scaled_shielders := ENCOUNTER_CONTRACTS.profile_shielder_count(scaled) + int(floor(float(tier) * 0.5))
	ENCOUNTER_CONTRACTS.profile_set_counts(scaled, scaled_chasers, scaled_chargers, scaled_archers, scaled_shielders)

	var base_room_size := ENCOUNTER_CONTRACTS.profile_room_size(scaled)
	if base_room_size == Vector2.ZERO:
		base_room_size = room_base_size
	var room_growth := Vector2(34.0, 22.0) * float(mini(tier, 12))
	var scaled_room_size := Vector2(
		clampf(base_room_size.x + room_growth.x, room_base_size.x, 1800.0),
		clampf(base_room_size.y + room_growth.y, room_base_size.y, 1300.0)
	)
	ENCOUNTER_CONTRACTS.profile_set_room_size(scaled, scaled_room_size)
	ENCOUNTER_CONTRACTS.profile_set_static_camera(scaled, scaled_room_size.x <= static_camera_room_threshold)

	# Merge endless stat pressure into the existing mutator channel.
	var endless_health_mult := clampf(1.0 + float(tier) * 0.28, 1.0, 4.2)
	var endless_damage_mult := clampf(1.0 + float(tier) * 0.14, 1.0, 2.8)
	var endless_speed_mult := clampf(1.0 + float(tier) * 0.07, 1.0, 2.0)
	var endless_windup_mult := clampf(1.0 - float(tier) * 0.03, 0.55, 1.0)
	var merged_mutator := ENCOUNTER_CONTRACTS.profile_enemy_mutator(scaled).duplicate(true)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ENEMY_HEALTH_MULT, endless_health_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT, endless_damage_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_DAMAGE_MULT, endless_damage_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_PROJECTILE_DAMAGE_MULT, endless_damage_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_DAMAGE_MULT, endless_damage_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_SPEED_MULT, endless_speed_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_SPEED_MULT, endless_speed_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SPEED_MULT, endless_speed_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_WINDUP_MULT, endless_windup_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_WINDUP_MULT, endless_windup_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_WINDUP_MULT, endless_windup_mult, 1.0)
	ENCOUNTER_CONTRACTS.profile_set_enemy_mutator(scaled, merged_mutator)

	var base_label := ENCOUNTER_CONTRACTS.profile_label(scaled)
	if base_label.find("Tier ") == -1:
		scaled[ENCOUNTER_CONTRACTS.PROFILE_KEY_LABEL] = "%s  Tier %d" % [base_label, tier]

	return scaled

func _begin_room(profile: Dictionary) -> void:
	if profile.is_empty():
		return
	encounter_intro_grace_active = false
	if is_instance_valid(player):
		player.clear_lingering_combat_effects()
		player.tick_objective_mutators_for_encounter()
	in_boss_room = false
	in_second_boss_room = false
	if is_instance_valid(objective_runtime):
		objective_runtime.reset_room_objective_state()
	_play_room_music(false)
	current_room_size = ENCOUNTER_CONTRACTS.profile_room_size(profile)
	current_room_static_camera = ENCOUNTER_CONTRACTS.profile_static_camera(profile)
	current_room_label = ENCOUNTER_CONTRACTS.profile_label(profile)
	current_room_enemy_mutator = ENCOUNTER_CONTRACTS.profile_enemy_mutator(profile)
	current_room_player_mutator = ENCOUNTER_CONTRACTS.profile_player_mutator(profile)
	_record_room_entry("encounter", profile)
	var mutator_name := ENCOUNTER_CONTRACTS.mutator_name(current_room_enemy_mutator)
	var _room_subtitle := ""
	var sub_color := Color(0.78, 0.9, 1.0, 0.92)
	if not mutator_name.is_empty():
		var banner_suffix := ENCOUNTER_CONTRACTS.mutator_banner_suffix(current_room_enemy_mutator)
		_room_subtitle = mutator_name
		if not banner_suffix.is_empty():
			_room_subtitle += "  -  " + banner_suffix
		sub_color = ENCOUNTER_CONTRACTS.mutator_theme_color(current_room_enemy_mutator, sub_color)
		sub_color.a = 0.92
	hud.show_banner(current_room_label, "", sub_color)
	if is_instance_valid(enemy_spawner):
		enemy_spawner.configure_room(current_room_size, spawn_padding, spawn_safe_radius, current_room_enemy_mutator, _get_active_enemy_mutators_for_room())
	_apply_camera_bounds_for_room(current_room_size)
	active_room_enemy_count = _spawn_profile_enemies(profile)
	if is_instance_valid(objective_runtime):
		objective_runtime.begin_room_objective(profile)
	_start_encounter_intro_grace()

func _enter_rest_site() -> void:
	in_boss_room = false
	_play_room_music(false)
	current_room_label = "Rest Site"
	_record_room_entry("rest", {})
	hud.show_banner("Rest Site", "")
	current_room_static_camera = true
	if first_boss_defeated:
		rooms_cleared += 1
		room_depth += 1
		phase_two_rooms_cleared += 1
		boss_unlocked = _is_second_boss_unlocked()
	else:
		_advance_room_progress()
	if is_instance_valid(player):
		var player_max_health := int(player.get("max_health"))
		var heal_ratio_mult := float(current_difficulty_config.get("rest_heal_ratio_mult", 1.0))
		var heal_amount := maxi(8, int(round(float(player_max_health) * rest_heal_ratio * heal_ratio_mult)))
		player.heal(heal_amount)
		player.play_rest_site_heal_feedback()
	_spawn_door_options()

func _advance_room_progress() -> void:
	if not is_instance_valid(encounter_flow_system):
		return
	var progress: Dictionary = encounter_flow_system.advance_room_progress(rooms_cleared, room_depth, encounter_count)
	rooms_cleared = int(progress.get("rooms_cleared", rooms_cleared))
	room_depth = int(progress.get("room_depth", room_depth))
	boss_unlocked = bool(progress.get("boss_unlocked", boss_unlocked))

func _pick_boss_spawn_position(min_player_distance: float = 260.0, wall_margin: float = 210.0) -> Vector2:
	if rng == null:
		return Vector2.ZERO
	var half := current_room_size * 0.5
	var usable_half := Vector2(
		maxf(80.0, half.x - wall_margin),
		maxf(80.0, half.y - wall_margin)
	)
	var fallback := Vector2.ZERO
	for _try in range(80):
		var candidate := Vector2(
			rng.randf_range(-usable_half.x, usable_half.x),
			rng.randf_range(-usable_half.y, usable_half.y)
		)
		fallback = candidate
		if is_instance_valid(player) and candidate.distance_to(player.global_position) < min_player_distance:
			continue
		return candidate
	return fallback

func _begin_configured_boss_room(is_first_boss: bool, room_size: Vector2, room_label: String, room_entry_key: String, banner_title: String, boss_script, collision_radius: float, min_player_distance: float, wall_margin: float) -> void:
	in_boss_room = is_first_boss
	in_second_boss_room = not is_first_boss
	_play_room_music(true)
	current_room_size = room_size
	current_room_static_camera = false
	current_room_label = room_label
	_record_room_entry(room_entry_key, {})
	hud.show_banner(banner_title, "")
	_apply_camera_bounds_for_room(current_room_size)
	active_room_enemy_count = 1
	var boss := CharacterBody2D.new()
	boss.set_script(boss_script)

	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = CircleShape2D.new()
	collision_shape.shape.radius = collision_radius
	boss.add_child(collision_shape)

	boss.global_position = _pick_boss_spawn_position(min_player_distance, wall_margin)
	add_child(boss)
	boss.begin_spawn_transport(BOSS_SPAWN_TRANSPORT_DURATION)
	boss.set("target", player)
	boss.set("arena_size", current_room_size)
	_apply_boss_difficulty_scaling(boss)
	if boss.has_signal("died"):
		boss.died.connect(_on_room_enemy_died)
	_start_encounter_intro_grace()

func _begin_boss_room() -> void:
	_begin_configured_boss_room(
		true,
		Vector2(1260.0, 900.0),
		"Boss Chamber: The Warden",
		"boss_1",
		"The Warden",
		ENEMY_BOSS_SCRIPT,
		34.0,
		maxf(260.0, spawn_safe_radius + 90.0),
		maxf(210.0, spawn_padding + 110.0)
	)

func _begin_second_boss_room() -> void:
	_begin_configured_boss_room(
		false,
		Vector2(1360.0, 960.0),
		"Abyss Core: Sovereign",
		"boss_2",
		"Sovereign",
		ENEMY_BOSS_2_SCRIPT,
		38.0,
		maxf(280.0, spawn_safe_radius + 110.0),
		maxf(230.0, spawn_padding + 130.0)
	)

func _spawn_profile_enemies(profile: Dictionary) -> int:
	if not is_instance_valid(enemy_spawner):
		return 0
	return int(enemy_spawner.spawn_profile_enemies(profile))

func _play_room_music(is_boss_room: bool, instant: bool = false, fade_duration: float = -1.0) -> void:
	if not is_instance_valid(music_system):
		return
	music_system.play_room_music(is_boss_room, instant, fade_duration)

func _on_room_enemy_died() -> void:
	active_room_enemy_count = maxi(0, active_room_enemy_count - 1)
	if active_objective_kind == "survival":
		objective_kills += 1
	if active_objective_kind == "priority_target" and is_instance_valid(objective_target_enemy):
		if objective_exposure_left <= 0.0:
			objective_hunt_kill_progress += 1
			if objective_hunt_kill_progress >= objective_hunt_kill_goal:
				_trigger_priority_target_exposure()
	if active_objective_kind == "priority_target" and objective_overtime and objective_spawn_timer > 0.2:
		objective_spawn_timer = maxf(0.2, objective_spawn_timer - 0.08)
	if is_instance_valid(player):
		player.notify_enemy_killed()

func _clear_all_enemies() -> void:
	if is_instance_valid(enemy_spawner):
		enemy_spawner.clear_all_enemies()

func _apply_camera_bounds_for_room(room_size: Vector2) -> void:
	if not is_instance_valid(player_camera):
		return
	var rect := Rect2(-room_size * 0.5, room_size)
	player_camera.set_world_bounds(rect)

func _update_camera_mode() -> void:
	if not is_instance_valid(player_camera):
		return
	if (is_instance_valid(reward_selection_ui) and reward_selection_ui.is_active()) or choosing_next_room:
		player_camera.set_static_mode(Vector2.ZERO)
		return
	if current_room_static_camera:
		player_camera.set_static_mode(Vector2.ZERO)
		return
	player_camera.set_follow_mode()

func _build_skirmish_profile(depth: int) -> Dictionary:
	if not is_instance_valid(encounter_profile_builder):
		return {}
	return encounter_profile_builder.build_skirmish_profile(depth)

func _get_active_player_mutators_for_hud() -> Array[Dictionary]:
	if not is_instance_valid(player):
		return []
	return player.get_active_objective_mutators() as Array[Dictionary]

func _get_active_enemy_mutators_for_room() -> Array[Dictionary]:
	if not is_instance_valid(player):
		return []
	if player.has_method("get_active_enemy_objective_mutators"):
		return player.get_active_enemy_objective_mutators() as Array[Dictionary]
	return []

func _roll_route_options(route_context: Variant) -> Array[Dictionary]:
	if not is_instance_valid(encounter_profile_builder):
		return []
	return encounter_profile_builder.roll_route_options(route_context)

func _open_boon_selection(title: String, is_initial: bool, mode: int = ENUMS.RewardMode.BOON, player_mutator: Dictionary = {}) -> void:
	if is_instance_valid(reward_selection_ui):
		reward_selection_ui.open_selection(title, is_initial, mode, power_registry_instance, player, rng, player_mutator)
		_set_combat_paused(true)

func _on_reward_selected(choice: Dictionary, mode: int, is_initial: bool) -> void:
	_record_reward_choice(choice, mode, is_initial)
	if mode == ENUMS.RewardMode.ARCANA:
		_apply_arcana_to_player(String(choice["id"]))
		arcana_rewards_taken.append(String(choice["name"]))
	elif mode == ENUMS.RewardMode.MISSION:
		_apply_mission_reward(choice)
	else:
		_apply_boon_to_player(String(choice["id"]))
		boons_taken.append(String(choice["name"]))
	_set_combat_paused(false)
	if is_initial:
		pending_room_reward = ENUMS.RewardMode.BOON
		_begin_room(_build_skirmish_profile(room_depth))
	else:
		_spawn_door_options()
	hud.refresh(_get_hud_state(), player)

func _is_debug_boot_session() -> bool:
	if not settings_enabled:
		return false
	if end_screen_preview != DEBUG_ENUMS.EndScreenPreview.NONE:
		return true
	if start_encounter != ENCOUNTER_CONTRACTS.DEBUG_ENCOUNTER_NONE:
		return true
	if _debug_bearing_override_tier() >= 0:
		return true
	if apply_test_powers_on_start:
		return true
	if start_power_preset != DEBUG_ENUMS.PowerPreset.NONE:
		return true
	if skip_starting_boon_selection:
		return true
	return false

func _maybe_start_telemetry_spike_probe() -> void:
	if telemetry_spike_requested:
		return
	if not settings_enabled or not telemetry_spike_enabled:
		return
	telemetry_spike_requested = true
	var endpoint := telemetry_spike_endpoint.strip_edges()
	if endpoint.is_empty():
		push_warning("Telemetry spike probe skipped: endpoint is empty.")
		return
	telemetry_spike_sender = TELEMETRY_SPIKE_SENDER_SCRIPT.new()
	add_child(telemetry_spike_sender)
	telemetry_spike_sender.connect("probe_completed", Callable(self, "_on_telemetry_spike_probe_completed"), CONNECT_ONE_SHOT)
	telemetry_spike_sender.call("begin_probe", {
		"endpoint": endpoint,
		"api_key": telemetry_spike_api_key,
		"timeout_seconds": clampf(telemetry_spike_timeout_seconds, 3.0, 20.0),
		"game_version": String(ProjectSettings.get_setting("application/config/version", "dev")),
	})
	print("Telemetry spike probe started: %s" % endpoint)

func _on_telemetry_spike_probe_completed(success: bool, http_code: int, error_message: String, response_preview: String) -> void:
	if success:
		print("Telemetry spike probe succeeded (HTTP %d)." % http_code)
	else:
		push_warning("Telemetry spike probe failed (%s, HTTP %d)." % [error_message, http_code])
	if not response_preview.is_empty():
		print("Telemetry spike response preview: %s" % response_preview)
	if is_instance_valid(telemetry_spike_sender):
		telemetry_spike_sender.queue_free()
	telemetry_spike_sender = null

func _initialize_run_telemetry(allow_collection: bool) -> void:
	telemetry_run_id = ""
	telemetry_enabled = allow_collection
	telemetry_run_finished = false
	if not telemetry_enabled:
		return
	var run_context := _get_run_context()
	var run_mode := int(ENUMS.RunMode.STANDARD)
	if run_context != null:
		var run_mode_value: Variant = run_context.get("run_mode")
		if run_mode_value != null:
			run_mode = int(run_mode_value)
	var run_seed := {
		"difficulty_tier": current_difficulty_tier,
		"run_mode": run_mode,
		"start_depth": room_depth,
		"rooms_cleared": rooms_cleared,
		"is_debug": false
	}
	telemetry_run_id = RUN_TELEMETRY_STORE.start_run(run_seed)

func _mark_telemetry_debug_mode() -> void:
	if telemetry_run_id.is_empty():
		telemetry_enabled = false
		return
	if telemetry_run_finished:
		telemetry_enabled = false
		return
	RUN_TELEMETRY_STORE.mark_run_debug(telemetry_run_id)
	RUN_TELEMETRY_STORE.finish_run(telemetry_run_id, "debug", {
		"max_depth": room_depth,
		"rooms_cleared": rooms_cleared
	})
	telemetry_enabled = false
	telemetry_run_finished = true

func _finish_active_run_telemetry(outcome: String, death_event: Dictionary = {}) -> void:
	if not telemetry_enabled:
		return
	if telemetry_run_id.is_empty() or telemetry_run_finished:
		return
	var summary := {
		"max_depth": room_depth,
		"rooms_cleared": rooms_cleared
	}
	if not death_event.is_empty():
		summary["death_event"] = death_event.duplicate(true)
	RUN_TELEMETRY_STORE.finish_run(telemetry_run_id, outcome, summary)
	var run_context := _get_run_context()
	if run_context != null and run_context.has_method("enqueue_telemetry_payload"):
		var upload_payload := RUN_TELEMETRY_STORE.build_upload_payload(telemetry_run_id)
		if not upload_payload.is_empty():
			run_context.call("enqueue_telemetry_payload", upload_payload)
	telemetry_run_finished = true

func _bearing_key_from_label(label: String, fallback: String = "unknown") -> String:
	var normalized := label.strip_edges().to_lower()
	if normalized.is_empty():
		return fallback
	normalized = normalized.replace(":", " ")
	normalized = normalized.replace("-", " ")
	normalized = normalized.replace("/", " ")
	normalized = normalized.replace(".", " ")
	normalized = normalized.replace("'", "")
	normalized = normalized.replace("\"", "")
	while normalized.find("  ") != -1:
		normalized = normalized.replace("  ", " ")
	normalized = normalized.strip_edges().replace(" ", "_")
	if normalized.is_empty():
		return fallback
	return normalized

func _bearing_key_from_profile(profile: Dictionary, fallback: String = "unknown") -> String:
	if profile.is_empty():
		return fallback
	var profile_label := ENCOUNTER_CONTRACTS.profile_label(profile)
	return _bearing_key_from_label(profile_label, fallback)

func _record_room_entry(room_kind: String, profile: Dictionary) -> void:
	if not telemetry_enabled or telemetry_run_id.is_empty() or telemetry_run_finished:
		return
	var mutator_name := "none"
	var objective_kind := ""
	var bearing_label := current_room_label
	var bearing_key := _bearing_key_from_label(bearing_label, room_kind)
	if not profile.is_empty():
		var mutator := ENCOUNTER_CONTRACTS.profile_enemy_mutator(profile)
		mutator_name = ENCOUNTER_CONTRACTS.mutator_name(mutator)
		if mutator_name.is_empty():
			mutator_name = "none"
		objective_kind = ENCOUNTER_CONTRACTS.profile_objective_kind(profile)
		bearing_label = ENCOUNTER_CONTRACTS.profile_label(profile)
		bearing_key = _bearing_key_from_profile(profile, room_kind)
	RUN_TELEMETRY_STORE.append_room_entry(telemetry_run_id, {
		"unix_time": int(Time.get_unix_time_from_system()),
		"room_kind": room_kind,
		"room_label": current_room_label,
		"bearing_key": bearing_key,
		"bearing_label": bearing_label,
		"enemy_mutator": mutator_name,
		"objective_kind": objective_kind,
		"room_depth": room_depth,
		"rooms_cleared": rooms_cleared
	})

func _record_reward_choice(choice: Dictionary, mode: int, is_initial: bool) -> void:
	if not telemetry_enabled or telemetry_run_id.is_empty() or telemetry_run_finished:
		return
	var choice_id := String(choice.get("id", ""))
	var choice_name := String(choice.get("name", choice_id))
	if mode == ENUMS.RewardMode.MISSION:
		var mission_upgrade := choice.get("mission_upgrade", {}) as Dictionary
		if not mission_upgrade.is_empty():
			choice_id = String(mission_upgrade.get("id", choice_id))
			choice_name = String(mission_upgrade.get("name", choice_name))
	RUN_TELEMETRY_STORE.append_reward_choice(telemetry_run_id, {
		"unix_time": int(Time.get_unix_time_from_system()),
		"mode": mode,
		"choice_id": choice_id,
		"choice_name": choice_name,
		"is_initial": is_initial,
		"room_depth": room_depth
	})

func _record_door_choice(choice: Dictionary) -> void:
	if not telemetry_enabled or telemetry_run_id.is_empty() or telemetry_run_finished:
		return
	var profile := ENCOUNTER_CONTRACTS.door_choice_profile(choice)
	var action_id := ENCOUNTER_CONTRACTS.door_choice_action_id(choice)
	var door_mutator := "none"
	var bearing_label := ENCOUNTER_CONTRACTS.profile_label(profile)
	var bearing_key := _bearing_key_from_profile(profile, "encounter")
	if action_id == ENUMS.EncounterAction.BOSS:
		bearing_key = "boss_2" if first_boss_defeated else "boss_1"
		bearing_label = "Sovereign" if first_boss_defeated else "Warden"
	elif action_id == ENUMS.EncounterAction.REST:
		bearing_key = "rest"
		bearing_label = "Rest Site"
	if not profile.is_empty():
		var mutator := ENCOUNTER_CONTRACTS.profile_enemy_mutator(profile)
		door_mutator = ENCOUNTER_CONTRACTS.mutator_name(mutator)
		if door_mutator.is_empty():
			door_mutator = "none"
	RUN_TELEMETRY_STORE.append_door_choice(telemetry_run_id, {
		"unix_time": int(Time.get_unix_time_from_system()),
		"action_id": action_id,
		"door_label": String(choice.get("label", "")),
		"reward_mode": ENCOUNTER_CONTRACTS.door_choice_reward_mode(choice),
		"encounter_label": ENCOUNTER_CONTRACTS.profile_label(profile),
		"bearing_key": bearing_key,
		"bearing_label": bearing_label,
		"enemy_mutator": door_mutator,
		"room_depth": room_depth
	})

func _on_player_damage_taken(raw_amount: int, final_amount: int, damage_context: Dictionary) -> void:
	if not telemetry_enabled or telemetry_run_id.is_empty() or telemetry_run_finished:
		return
	var context_copy := damage_context.duplicate(true)
	var current_bearing_key := _bearing_key_from_label(current_room_label, "unknown")
	RUN_TELEMETRY_STORE.append_damage_event(telemetry_run_id, {
		"unix_time": int(context_copy.get("unix_time", Time.get_unix_time_from_system())),
		"source": String(context_copy.get("source", "unknown")),
		"ability": String(context_copy.get("ability", "unknown")),
		"raw_amount": raw_amount,
		"final_amount": final_amount,
		"health_before": int(context_copy.get("health_before", 0)),
		"health_after": int(context_copy.get("health_after", 0)),
		"room_label": current_room_label,
		"bearing_key": current_bearing_key,
		"room_depth": room_depth
	})

func _on_player_died_for_telemetry() -> void:
	if not telemetry_enabled or telemetry_run_id.is_empty() or telemetry_run_finished:
		return
	var death_event: Dictionary = {}
	if is_instance_valid(player):
		death_event = player.get_last_damage_event() as Dictionary
	death_event["room_label"] = current_room_label
	death_event["bearing_key"] = _bearing_key_from_label(current_room_label, "unknown")
	death_event["room_depth"] = room_depth
	_finish_active_run_telemetry("death", death_event)

func _on_player_died() -> void:
	if player_defeated:
		return
	player_defeated = true
	_set_combat_paused(true)
	if is_instance_valid(reward_selection_ui):
		reward_selection_ui.close_selection()
	if is_instance_valid(pause_menu_controller) and bool(pause_menu_controller.is_open()):
		pause_menu_controller.close()
	run_cleared = true
	choosing_next_room = false
	active_objective_kind = ""
	active_room_enemy_count = 0
	var run_context := _get_run_context()
	if run_context != null:
		run_context.set_last_run_outcome("death")
		run_context.clear_active_run()
		run_context.clear_resume_saved_run_request()
	hud.show_banner("Defeat", "")
	if is_instance_valid(defeat_screen):
		defeat_screen.show_defeat(current_room_label, room_depth)

func _apply_boon_to_player(boon_id: String) -> void:
	if not is_instance_valid(player):
		return
	player.apply_upgrade(boon_id)

func _apply_mission_reward(choice: Dictionary) -> void:
	var chosen_upgrade := choice.get("mission_upgrade", choice) as Dictionary
	var chosen_mutator := choice.get("mission_mutator", {}) as Dictionary
	var chosen_id := String(chosen_upgrade.get("id", ""))
	if chosen_id.is_empty():
		return
	_apply_boon_to_player(chosen_id)
	boons_taken.append(String(chosen_upgrade.get("name", chosen_id)))
	if is_instance_valid(hud):
		hud.show_banner("Mission Reward", String(chosen_upgrade.get("name", chosen_id)))
	if not chosen_mutator.is_empty():
		_apply_objective_mutator(chosen_mutator)
		return
	if current_room_player_mutator.is_empty():
		return
	_apply_objective_mutator({
		"name": String(current_room_player_mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME, "Objective Mutator")),
		"full_data": current_room_player_mutator
	})

func _roll_bonus_mission_boon(excluded_id: String) -> Dictionary:
	if not is_instance_valid(power_registry_instance):
		return {}
	var pool: Array[Dictionary] = power_registry_instance.get_objective_upgrade_pool(player)
	var available: Array[Dictionary] = []
	for entry in pool:
		var entry_id := String(entry.get("id", ""))
		if entry_id == excluded_id:
			continue
		var limit := int(entry.get("stack_limit", 0))
		if limit > 0 and is_instance_valid(player):
			var current := int(player.get_upgrade_stack_count(entry_id))
			if current >= limit:
				continue
		available.append(entry)
	if available.is_empty():
		return {}
	return available[rng.randi_range(0, available.size() - 1)]

func _apply_arcana_to_player(reward_id: String) -> void:
	if not is_instance_valid(player):
		return
	player.apply_trial_power(reward_id)

func _apply_objective_mutator(choice: Dictionary) -> void:
	if not is_instance_valid(player):
		return
	var mutator_data := choice.get("full_data", {}) as Dictionary
	if mutator_data.is_empty():
		return
	var applied_mutator := mutator_data.duplicate(true)
	var duration := maxi(1, int(applied_mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_DURATION_ENCOUNTERS, 3)))
	applied_mutator[ENCOUNTER_CONTRACTS.MUTATOR_KEY_DURATION_ENCOUNTERS] = duration
	player.apply_objective_mutator(applied_mutator)
	var mutator_name := String(choice.get("name", "Objective Mutator"))
	if is_instance_valid(hud):
		hud.show_banner("Objective Reward", mutator_name)

func _set_combat_paused(paused: bool) -> void:
	if is_instance_valid(player):
		if player is CharacterBody2D:
			(player as CharacterBody2D).velocity = Vector2.ZERO
		player.set_physics_process(not paused)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node:
			(enemy as Node).set_physics_process(not paused)
			(enemy as Node).set_process(not paused)

func _is_spawn_transport_active(enemy: Node) -> bool:
	return bool(enemy.is_spawn_transporting())

func _begin_spawn_transport_if_idle(enemy: Node, duration: float) -> void:
	if _is_spawn_transport_active(enemy):
		return
	enemy.begin_spawn_transport(duration)

func _start_encounter_intro_grace() -> void:
	encounter_intro_grace_active = true
	if is_instance_valid(player) and player is CharacterBody2D:
		(player as CharacterBody2D).velocity = Vector2.ZERO
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node):
			continue
		var enemy := enemy_node as Node
		_begin_spawn_transport_if_idle(enemy, INTRO_SURVEY_TRANSPORT_PULSE_DURATION)
	_set_enemy_targets_passive(true)
	hud.show_banner("Survey the arena", "")

func _update_encounter_intro_grace() -> bool:
	if not encounter_intro_grace_active:
		return false
	if not is_instance_valid(player):
		return false
	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var player_moving := move_input.length_squared() > 0.04 or (player as CharacterBody2D).velocity.length_squared() > 64.0
	var player_attacking := Input.is_action_just_pressed("attack")
	if player_moving or player_attacking:
		encounter_intro_grace_active = false
		_set_enemy_targets_passive(false)
		hud.show_banner("Engage", "")
		return false
	return true

func _set_enemy_targets_passive(passive: bool) -> void:
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is CharacterBody2D):
			continue
		var enemy := enemy_node as CharacterBody2D
		if passive:
			enemy.set("target", null)
			if enemy is CharacterBody2D:
				enemy.velocity = Vector2.ZERO
		else:
			enemy.set("target", player)
			var cooldown_key := ""
			if enemy.get("attack_cooldown_left") != null:
				cooldown_key = "attack_cooldown_left"
			if not cooldown_key.is_empty():
				var current_cd := float(enemy.get(cooldown_key))
				if current_cd < 0.32:
					enemy.set(cooldown_key, 0.32)
