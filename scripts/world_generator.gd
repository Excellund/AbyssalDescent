extends Node2D

const ENEMY_CHASER_SCRIPT := preload("res://scripts/enemy_chaser.gd")
const ENEMY_CHARGER_SCRIPT := preload("res://scripts/enemy_charger.gd")
const ENEMY_ARCHER_SCRIPT := preload("res://scripts/enemy_archer.gd")
const ENEMY_SHIELDER_SCRIPT := preload("res://scripts/enemy_shielder.gd")
const ENEMY_BOSS_SCRIPT := preload("res://scripts/enemy_boss.gd")
const POWER_REGISTRY := preload("res://scripts/power_registry.gd")
const MUSIC_SYSTEM_SCRIPT := preload("res://scripts/music_system.gd")
const ENEMY_SPAWNER_SCRIPT := preload("res://scripts/enemy_spawner.gd")
const ENCOUNTER_PROFILE_BUILDER_SCRIPT := preload("res://scripts/encounter_profile_builder.gd")
const ENCOUNTER_FLOW_SYSTEM_SCRIPT := preload("res://scripts/encounter_flow_system.gd")
const REWARD_SELECTION_UI_SCRIPT := preload("res://scripts/reward_selection_ui.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const RUN_CONTEXT_PATH := "/root/RunContext"
const MENU_SCENE_PATH := "res://scenes/Menu.tscn"
const WORLD_HUD_SCRIPT := preload("res://scripts/world_hud.gd")
const WORLD_RENDERER_SCRIPT := preload("res://scripts/world_renderer.gd")
const PAUSE_MENU_CONTROLLER_SCRIPT := preload("res://scripts/pause_menu_controller.gd")
const DEBUG_ENCOUNTER_NONE := 0
const DEBUG_ENCOUNTER_SKIRMISH := 1
const DEBUG_ENCOUNTER_CROSSFIRE := 2
const DEBUG_ENCOUNTER_ONSLAUGHT := 3
const DEBUG_ENCOUNTER_FORTRESS := 4
const DEBUG_ENCOUNTER_TRIAL := 5
const DEBUG_ENCOUNTER_OBJECTIVE_LAST_STAND := 6
const DEBUG_ENCOUNTER_OBJECTIVE_PRIORITY_TARGET := 7
const DEBUG_ENCOUNTER_OBJECTIVE_RANDOM := 8
const DEBUG_ENCOUNTER_REST_SITE := 9
const DEBUG_ENCOUNTER_BOSS := 10
const DEBUG_MUTATOR_NONE := 0
const DEBUG_MUTATOR_BLOOD_RUSH := 1
const DEBUG_MUTATOR_FLASHPOINT := 2
const DEBUG_MUTATOR_SIEGEBREAK := 3
const DEBUG_MUTATOR_IRON_VOLLEY := 4
const DEBUG_MUTATOR_KILLBOX := 5
const DEBUG_MUTATOR_RANDOM_HARD := 6

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
@export var music_volume_db: float = -46.0
@export var music_intro_fade_duration: float = 1.6
@export var music_crossfade_duration: float = 0.75
@export var rest_heal_ratio: float = 0.32
@export var hard_room_enemy_bonus: int = 3
@export var debug_apply_test_powers_on_start: bool = false
@export var debug_skip_starting_boon_selection: bool = false
@export var debug_start_power_ids: PackedStringArray = PackedStringArray()
@export_multiline var debug_start_command: String = ""
@export_enum("None", "Skirmish", "Crossfire", "Onslaught", "Fortress", "Trial", "Objective - Last Stand", "Objective - Cut the Signal", "Objective - Random", "Rest Site", "Boss") var debug_start_encounter: int = DEBUG_ENCOUNTER_NONE
@export_enum("None", "Blood Rush", "Flashpoint", "Siegebreak", "Iron Volley", "Killbox", "Random Hard") var debug_mutator_override: int = DEBUG_MUTATOR_NONE

var player: Node2D
var player_camera: Camera2D
var rng := RandomNumberGenerator.new()
var power_registry_instance: Node

var rooms_cleared: int = 0
var room_depth: int = 0
var active_room_enemy_count: int = 0
var boss_unlocked: bool = false
var in_boss_room: bool = false
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
var active_objective_kind: String = ""
var objective_time_left: float = 0.0
var objective_spawn_interval: float = 0.0
var objective_spawn_timer: float = 0.0
var objective_spawn_batch: int = 1
var objective_max_enemies: int = 0
var objective_kill_target: int = 0
var objective_kills: int = 0
var objective_overtime: bool = false
var objective_target_enemy: CharacterBody2D
var objective_target_type: String = ""
var objective_target_name: String = ""
var objective_target_flee_thresholds: Array[float] = [0.75, 0.5, 0.25]
var objective_target_next_flee_index: int = 0
var objective_target_dash_line: Line2D
var objective_target_dash_line_time_left: float = 0.0

var hud: Node
var renderer: Node2D
var music_system: Node
var enemy_spawner: Node
var encounter_profile_builder: Node
var encounter_flow_system: Node
var reward_selection_ui: Node
var pause_menu_controller: Node

func _ready() -> void:
	rng.randomize()
	power_registry_instance = POWER_REGISTRY.new()
	player = get_node_or_null(player_path) as Node2D
	if is_instance_valid(player):
		player_camera = player.get_node_or_null("Camera2D") as Camera2D
	_sync_audio_settings_from_context()
	endless_boss_defeated = false

	current_room_size = room_base_size
	current_room_label = "Starting Chamber"
	_apply_camera_bounds_for_room(current_room_size)
	music_system = MUSIC_SYSTEM_SCRIPT.new()
	add_child(music_system)
	music_system.call("initialize", normal_room_music, boss_room_music, music_volume_db, music_crossfade_duration)
	encounter_flow_system = ENCOUNTER_FLOW_SYSTEM_SCRIPT.new()
	add_child(encounter_flow_system)
	reward_selection_ui = REWARD_SELECTION_UI_SCRIPT.new()
	add_child(reward_selection_ui)
	reward_selection_ui.call("initialize", boon_choice_count, boon_reveal_duration)
	if reward_selection_ui.has_signal("reward_selected"):
		reward_selection_ui.connect("reward_selected", Callable(self, "_on_reward_selected"))
	encounter_profile_builder = ENCOUNTER_PROFILE_BUILDER_SCRIPT.new()
	add_child(encounter_profile_builder)
	encounter_profile_builder.call("initialize", rng)
	encounter_profile_builder.call("configure", {
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
	enemy_spawner.call("initialize", self, player, rng, {
		"chaser": ENEMY_CHASER_SCRIPT,
		"charger": ENEMY_CHARGER_SCRIPT,
		"archer": ENEMY_ARCHER_SCRIPT,
		"shielder": ENEMY_SHIELDER_SCRIPT
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
	pause_menu_controller.call("initialize", RUN_CONTEXT_PATH, Callable(self, "_set_music_volume_runtime"))
	pause_menu_controller.connect("pause_opened", Callable(self, "_on_pause_menu_opened"))
	pause_menu_controller.connect("pause_closed", Callable(self, "_on_pause_menu_closed"))
	pause_menu_controller.connect("back_to_main_menu_requested", Callable(self, "_on_pause_back_to_menu_requested"))
	pause_menu_controller.connect("exit_game_requested", Callable(self, "_on_pause_exit_game_requested"))
	hud.refresh(_get_hud_state(), player)
	_apply_debug_start_powers_if_needed()
	if debug_start_encounter != DEBUG_ENCOUNTER_NONE:
		_start_debug_selected_encounter(debug_start_encounter)
		return
	if debug_skip_starting_boon_selection:
		_begin_room(_build_skirmish_profile(room_depth))
	else:
		_open_boon_selection("Choose Starting Boon", true, ENUMS.RewardMode.BOON)

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
		if player.has_method("apply_power_for_test"):
			if bool(player.call("apply_power_for_test", id)):
				applied.append(id)
			else:
				unknown.append(id)
		else:
			unknown.append(id)

	hud.refresh(_get_hud_state(), player)
	return {
		"applied": applied,
		"unknown": unknown
	}

func start_run_with_command(command: String) -> Dictionary:
	return start_run_with_powers(_parse_power_command(command))

func go_do_that_thing(state: String) -> Dictionary:
	return start_debug_encounter(state)

func start_objective_test(kind: String = "") -> Dictionary:
	return _start_debug_objective_room(kind)

func start_last_stand_test() -> Dictionary:
	return _start_debug_objective_room("last_stand")

func start_endurance_test() -> Dictionary:
	return _start_debug_objective_room("last_stand")

func start_debug_encounter(encounter_key: String) -> Dictionary:
	var key := encounter_key.strip_edges().to_lower()
	match key:
		"skirmish":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_SKIRMISH)
		"crossfire":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_CROSSFIRE)
		"onslaught":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_ONSLAUGHT)
		"fortress":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_FORTRESS)
		"trial":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_TRIAL)
		"objective_last_stand", "last_stand":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_OBJECTIVE_LAST_STAND)
		"objective_priority_target", "priority_target", "cut_the_signal", "cut the signal":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_OBJECTIVE_PRIORITY_TARGET)
		"objective_endurance", "endurance":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_OBJECTIVE_LAST_STAND)
		"objective_random", "objective":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_OBJECTIVE_RANDOM)
		"rest", "rest_site":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_REST_SITE)
		"boss":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_BOSS)
		"objective_test":
			return _start_debug_selected_encounter(DEBUG_ENCOUNTER_OBJECTIVE_RANDOM)
		_:
			return {"ok": false, "note": "Unknown encounter key."}

func _debug_encounter_key(encounter_state: int) -> String:
	match encounter_state:
		DEBUG_ENCOUNTER_SKIRMISH:
			return "skirmish"
		DEBUG_ENCOUNTER_CROSSFIRE:
			return "crossfire"
		DEBUG_ENCOUNTER_ONSLAUGHT:
			return "onslaught"
		DEBUG_ENCOUNTER_FORTRESS:
			return "fortress"
		DEBUG_ENCOUNTER_TRIAL:
			return "trial"
		DEBUG_ENCOUNTER_OBJECTIVE_LAST_STAND:
			return "objective_last_stand"
		DEBUG_ENCOUNTER_OBJECTIVE_PRIORITY_TARGET:
			return "objective_priority_target"
		DEBUG_ENCOUNTER_OBJECTIVE_RANDOM:
			return "objective_random"
		DEBUG_ENCOUNTER_REST_SITE:
			return "rest"
		DEBUG_ENCOUNTER_BOSS:
			return "boss"
		_:
			return ""

func _start_debug_selected_encounter(encounter_state: int) -> Dictionary:
	var encounter_key := _debug_encounter_key(encounter_state)
	if encounter_key.is_empty():
		return {"ok": true, "note": "No debug encounter selected."}
	if encounter_key == "boss":
		return _start_debug_boss_room()

	_reset_for_debug_jump()
	var encounter_depth := 1
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
	_begin_boss_room()
	hud.refresh(_get_hud_state(), player)
	return {"ok": true, "state": "debug_encounter", "encounter": "Boss Chamber"}

func _build_debug_encounter_profile(encounter_key: String, depth: int) -> Dictionary:
	if not is_instance_valid(encounter_profile_builder):
		return {}
	return encounter_profile_builder.call("build_debug_encounter_profile", encounter_key, depth)

func _debug_mutator_key(state_value: int) -> String:
	match state_value:
		DEBUG_MUTATOR_BLOOD_RUSH:
			return "blood_rush"
		DEBUG_MUTATOR_FLASHPOINT:
			return "flashpoint"
		DEBUG_MUTATOR_SIEGEBREAK:
			return "siegebreak"
		DEBUG_MUTATOR_IRON_VOLLEY:
			return "iron_volley"
		DEBUG_MUTATOR_KILLBOX:
			return "killbox"
		DEBUG_MUTATOR_RANDOM_HARD:
			return "random_hard"
		_:
			return ""

func _apply_debug_mutator_override(profile: Dictionary) -> Dictionary:
	if profile.is_empty():
		return profile
	var mutator_key := _debug_mutator_key(debug_mutator_override)
	if mutator_key.is_empty():
		return profile
	if not is_instance_valid(encounter_profile_builder):
		return profile
	var mutator: Dictionary = encounter_profile_builder.call("build_debug_mutator", mutator_key)
	if mutator.is_empty():
		return profile
	var modified := profile.duplicate(true)
	ENCOUNTER_CONTRACTS.profile_set_enemy_mutator(modified, mutator)
	return modified

func _reset_for_debug_jump() -> void:
	if is_instance_valid(reward_selection_ui):
		reward_selection_ui.call("close_selection")
	_set_combat_paused(false)
	choosing_next_room = false
	door_options.clear()
	pending_room_reward = ENUMS.RewardMode.NONE
	run_cleared = false
	in_boss_room = false
	endless_boss_defeated = false
	active_room_enemy_count = 0
	_clear_all_enemies()

	if is_instance_valid(player):
		player.global_position = Vector2.ZERO

func _start_debug_objective_room(kind: String = "") -> Dictionary:
	_reset_for_debug_jump()
	var objective_depth := 1
	rooms_cleared = objective_depth - 1
	room_depth = objective_depth
	boss_unlocked = false
	var profile := _build_objective_test_profile(objective_depth, kind)
	profile = _apply_debug_mutator_override(profile)
	if profile.is_empty():
		return {"ok": false, "state": "objective_test", "note": "Could not build objective profile."}
	pending_room_reward = ENUMS.RewardMode.BOON
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
	return encounter_profile_builder.call("build_objective_profile", depth, kind)

func _apply_debug_start_powers_if_needed() -> void:
	if not debug_apply_test_powers_on_start:
		return
	var ids: Array[String] = []
	for id in debug_start_power_ids:
		ids.append(String(id))
	if not debug_start_command.strip_edges().is_empty():
		ids.append_array(_parse_power_command(debug_start_command))
	if ids.is_empty():
		return
	start_run_with_powers(ids)

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
	if not event.is_action_pressed("ui_cancel"):
		return
	if not is_instance_valid(pause_menu_controller):
		return
	if bool(pause_menu_controller.call("is_open")) and bool(pause_menu_controller.call("is_options_open")):
		pause_menu_controller.call("close_options")
		get_viewport().set_input_as_handled()
		return
	if bool(pause_menu_controller.call("is_open")):
		pause_menu_controller.call("close")
		get_viewport().set_input_as_handled()
		return
	pause_menu_controller.call("open")
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if is_instance_valid(pause_menu_controller) and bool(pause_menu_controller.call("is_open")):
		hud.refresh(_get_hud_state(), player)
		_sync_renderer()
		return
	if is_instance_valid(reward_selection_ui) and bool(reward_selection_ui.call("is_active")):
		reward_selection_ui.call("process_input", delta)
		hud.refresh(_get_hud_state(), player)
		_sync_renderer()
		return

	_keep_player_inside_current_room()
	_keep_enemies_inside_current_room()
	_keep_player_inside_camera_view()
	_update_objective_state(delta)
	_update_priority_target_marker(delta)
	_try_use_door()
	_update_encounter_state()
	_update_camera_mode()
	hud.refresh(_get_hud_state(), player)
	_sync_renderer()

func _update_objective_state(delta: float) -> void:
	if active_objective_kind == "survival":
		_update_survival_objective_state(delta)
		return
	if active_objective_kind == "priority_target":
		_update_priority_target_objective_state(delta)
		return

func _update_survival_objective_state(delta: float) -> void:
	if choosing_next_room or run_cleared:
		return
	if objective_kills >= objective_kill_target and objective_kill_target > 0:
		_complete_current_objective("Objective Complete", "Kill quota reached")
		return
	var pressure_floor := mini(18, 6 + int(floor(float(room_depth) * 0.6)) + objective_spawn_batch)
	if objective_max_enemies > 0:
		pressure_floor = mini(pressure_floor, objective_max_enemies)
	if active_room_enemy_count < pressure_floor and (objective_time_left > 0.0 or objective_overtime):
		objective_spawn_timer = minf(objective_spawn_timer, 0.4)
	if objective_time_left > 0.0:
		objective_time_left = maxf(0.0, objective_time_left - delta)
	objective_spawn_timer = maxf(0.0, objective_spawn_timer - delta)
	if objective_spawn_timer <= 0.0 and (objective_time_left > 0.0 or objective_overtime):
		objective_spawn_timer = objective_spawn_interval
		_spawn_survival_wave()
	if objective_time_left <= 0.0 and not objective_overtime:
		objective_overtime = true
		objective_spawn_interval = maxf(0.45, objective_spawn_interval * 0.65)
		objective_spawn_batch = mini(7, objective_spawn_batch + 1)
		objective_spawn_timer = 0.1
		var kills_left := maxi(0, objective_kill_target - objective_kills)
		hud.show_banner("Overtime", "%d kills remaining" % kills_left)

func _update_priority_target_objective_state(delta: float) -> void:
	if choosing_next_room or run_cleared:
		return
	if not is_instance_valid(objective_target_enemy):
		_complete_current_objective("Target Eliminated", "%s down" % objective_target_name)
		return
	_check_priority_target_relocation_threshold()
	var pressure_floor := 5 + objective_spawn_batch
	if objective_overtime:
		pressure_floor += 2
	if objective_max_enemies > 0:
		pressure_floor = mini(pressure_floor, objective_max_enemies)
	if active_room_enemy_count < pressure_floor:
		objective_spawn_timer = minf(objective_spawn_timer, 0.45)
	if objective_time_left > 0.0:
		objective_time_left = maxf(0.0, objective_time_left - delta)
	objective_spawn_timer = maxf(0.0, objective_spawn_timer - delta)
	if objective_spawn_timer <= 0.0:
		objective_spawn_timer = objective_spawn_interval
		_spawn_priority_target_wave()
	if objective_time_left <= 0.0 and not objective_overtime:
		objective_overtime = true
		objective_spawn_interval = maxf(0.55, objective_spawn_interval * 0.7)
		objective_spawn_batch = mini(6, objective_spawn_batch + 1)
		objective_spawn_timer = 0.15
		_enrage_priority_target()
		hud.show_banner("Signal Escalating", "Escorts intensify and the mark speeds up")

func _spawn_survival_wave() -> void:
	if not is_instance_valid(enemy_spawner):
		return
	if objective_max_enemies > 0 and active_room_enemy_count >= objective_max_enemies:
		return
	var roster: Array[String] = ["charger", "archer", "chaser", "charger", "shielder", "archer"]
	if objective_overtime:
		roster = ["charger", "archer", "charger", "archer", "shielder", "chaser", "charger"]
	var spawn_count := objective_spawn_batch
	if active_room_enemy_count <= objective_spawn_batch:
		spawn_count += 1
	if objective_overtime:
		spawn_count += 1
	spawn_count = mini(8, spawn_count)
	if objective_max_enemies > 0:
		spawn_count = mini(spawn_count, maxi(0, objective_max_enemies - active_room_enemy_count))
	if spawn_count <= 0:
		return
	for _i in range(spawn_count):
		var enemy_type := roster[rng.randi_range(0, roster.size() - 1)]
		active_room_enemy_count += int(enemy_spawner.call("spawn_enemy_type", enemy_type, 1))

func _spawn_priority_target_wave() -> void:
	if not is_instance_valid(enemy_spawner):
		return
	if objective_max_enemies > 0 and active_room_enemy_count >= objective_max_enemies:
		return
	var roster: Array[String] = ["chaser", "shielder", "chaser", "charger", "shielder"]
	if objective_overtime:
		roster = ["charger", "shielder", "chaser", "charger", "shielder", "archer"]
	var spawn_count := objective_spawn_batch
	if objective_overtime:
		spawn_count += 1
	if objective_max_enemies > 0:
		spawn_count = mini(spawn_count, maxi(0, objective_max_enemies - active_room_enemy_count))
	if spawn_count <= 0:
		return
	for _i in range(spawn_count):
		var enemy_type := roster[rng.randi_range(0, roster.size() - 1)]
		active_room_enemy_count += int(enemy_spawner.call("spawn_enemy_type", enemy_type, 1))

func _complete_current_objective(title: String, subtitle: String) -> void:
	active_objective_kind = ""
	objective_spawn_timer = 0.0
	objective_time_left = 0.0
	objective_overtime = false
	objective_target_enemy = null
	objective_target_type = ""
	objective_target_name = ""
	objective_target_next_flee_index = 0
	_clear_priority_target_dash_line()
	_clear_all_enemies()
	active_room_enemy_count = 0
	hud.show_banner(title, subtitle)
	_on_room_cleared()

func _spawn_priority_target_enemy() -> void:
	if not is_instance_valid(enemy_spawner):
		return
	var target_type := objective_target_type if not objective_target_type.is_empty() else "archer"
	var target_spawn_distance := maxf(spawn_safe_radius + 180.0, 320.0)
	var spawned_target := enemy_spawner.call("spawn_enemy_node_type", target_type, target_spawn_distance) as CharacterBody2D
	if not is_instance_valid(spawned_target):
		return
	objective_target_enemy = spawned_target
	active_room_enemy_count += 1
	if spawned_target.get("max_health") != null:
		var boosted_max := maxi(40, int(round(float(int(spawned_target.get("max_health"))) * 2.6)))
		spawned_target.set("max_health", boosted_max)
		var health_state: Object = spawned_target.get("health_state") as Object
		if health_state != null and health_state.has_method("setup"):
			health_state.call("setup", boosted_max)
	if spawned_target.get("has_mutator_overlay") != null:
		spawned_target.set("has_mutator_overlay", true)
	if spawned_target.get("mutator_theme_color") != null:
		spawned_target.set("mutator_theme_color", Color(1.0, 0.84, 0.3, 1.0))
	spawned_target.scale *= 1.14
	objective_target_next_flee_index = 0
	if spawned_target.has_method("configure_health_bar_visuals"):
		spawned_target.call("configure_health_bar_visuals", Vector2(-36.0, -48.0), Vector2(72.0, 9.0))
	if spawned_target.has_method("set_health_threshold_markers"):
		spawned_target.call("set_health_threshold_markers", objective_target_flee_thresholds, objective_target_next_flee_index)
	_attach_priority_target_marker(spawned_target)
	_spawn_priority_target_opening_escorts()
	if spawned_target.has_signal("died"):
		spawned_target.died.connect(Callable(self, "_on_priority_target_died"))

func _spawn_priority_target_opening_escorts() -> void:
	if not is_instance_valid(objective_target_enemy):
		return
	if not is_instance_valid(enemy_spawner):
		return
	var escort_types: Array[String] = ["shielder", "chaser", "chaser"]
	if room_depth >= 2:
		escort_types.append("shielder")
	if room_depth >= 4:
		escort_types[escort_types.size() - 1] = "charger"
	var anchor := objective_target_enemy.global_position
	var base_angle := rng.randf_range(0.0, TAU)
	for escort_index in range(escort_types.size()):
		var escort := enemy_spawner.call("spawn_enemy_node_type", escort_types[escort_index]) as CharacterBody2D
		if not is_instance_valid(escort):
			continue
		var angle := base_angle + TAU * float(escort_index) / float(maxi(1, escort_types.size()))
		var radius := 76.0 if escort_types[escort_index] == "shielder" else 92.0
		escort.global_position = _clamp_position_to_current_room(anchor + Vector2.RIGHT.rotated(angle) * radius, 44.0)
		active_room_enemy_count += 1
	objective_spawn_timer = maxf(objective_spawn_timer, objective_spawn_interval)
	hud.show_banner("Mark Spotted", "Cut through the escort and drop the signal")

func _check_priority_target_relocation_threshold() -> void:
	if not is_instance_valid(objective_target_enemy):
		return
	if objective_target_next_flee_index >= objective_target_flee_thresholds.size():
		return
	var current_health := _get_priority_target_health()
	var max_health := _get_priority_target_max_health()
	if current_health <= 0 or max_health <= 0:
		return
	var threshold_ratio := objective_target_flee_thresholds[objective_target_next_flee_index]
	var current_ratio := float(current_health) / float(max_health)
	if current_ratio > threshold_ratio:
		return
	objective_target_next_flee_index += 1
	if objective_target_enemy.has_method("set_health_threshold_marker_progress"):
		objective_target_enemy.call("set_health_threshold_marker_progress", objective_target_next_flee_index)
	_relocate_priority_target(threshold_ratio)

func _relocate_priority_target(threshold_ratio: float) -> void:
	if not is_instance_valid(objective_target_enemy):
		return
	var old_position := objective_target_enemy.global_position
	var new_position := _pick_priority_target_relocation_position(old_position)
	if old_position.distance_to(new_position) < 120.0:
		return
	objective_target_enemy.global_position = new_position
	objective_target_enemy.velocity = Vector2.ZERO
	_show_priority_target_dash_line(old_position, new_position)
	_spawn_priority_target_relocation_escorts(new_position)
	var threshold_percent := int(round(threshold_ratio * 100.0))
	hud.show_banner("Signal Breakaway", "%d%% threshold hit. The mark dashes away." % threshold_percent)

func _pick_priority_target_relocation_position(old_position: Vector2) -> Vector2:
	if not is_instance_valid(enemy_spawner):
		return old_position
	var min_player_distance := maxf(spawn_safe_radius + 150.0, 300.0)
	var min_enemy_spacing := 132.0
	var best_position := old_position
	var best_score := -INF
	for _attempt in range(8):
		var candidate := enemy_spawner.call("pick_room_position", min_player_distance, min_enemy_spacing) as Vector2
		if candidate.distance_to(old_position) < 160.0:
			continue
		var score := candidate.distance_to(old_position)
		if is_instance_valid(player):
			score += candidate.distance_to(player.global_position) * 1.2
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy == objective_target_enemy or not (enemy is Node2D):
				continue
			var neighbor := enemy as Node2D
			score += minf(180.0, candidate.distance_to(neighbor.global_position)) * 0.35
		if score > best_score:
			best_score = score
			best_position = candidate
	return _clamp_position_to_current_room(best_position, 44.0)

func _spawn_priority_target_relocation_escorts(anchor: Vector2) -> void:
	if not is_instance_valid(enemy_spawner):
		return
	var escort_types: Array[String] = ["chaser"]
	if objective_target_next_flee_index == 1:
		escort_types = ["shielder", "chaser"]
	elif objective_target_next_flee_index >= 2:
		escort_types = ["shielder", "charger"]
	for escort_type in escort_types:
		if objective_max_enemies > 0 and active_room_enemy_count >= objective_max_enemies:
			return
		var escort := enemy_spawner.call("spawn_enemy_node_type", escort_type) as CharacterBody2D
		if not is_instance_valid(escort):
			continue
		var escort_angle := rng.randf_range(0.0, TAU)
		var escort_radius := 80.0 if escort_type == "shielder" else 96.0
		escort.global_position = _clamp_position_to_current_room(anchor + Vector2.RIGHT.rotated(escort_angle) * escort_radius, 44.0)
		active_room_enemy_count += 1

func _show_priority_target_dash_line(from_position: Vector2, to_position: Vector2) -> void:
	_clear_priority_target_dash_line()
	objective_target_dash_line = Line2D.new()
	objective_target_dash_line.name = "PriorityTargetDashLine"
	objective_target_dash_line.width = 5.0
	objective_target_dash_line.default_color = Color(1.0, 0.86, 0.42, 0.9)
	objective_target_dash_line.points = PackedVector2Array([from_position, to_position])
	objective_target_dash_line.z_as_relative = false
	objective_target_dash_line.z_index = 48
	add_child(objective_target_dash_line)
	objective_target_dash_line_time_left = 0.22

func _clear_priority_target_dash_line() -> void:
	if is_instance_valid(objective_target_dash_line):
		objective_target_dash_line.queue_free()
	objective_target_dash_line = null
	objective_target_dash_line_time_left = 0.0

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
	if objective_target_dash_line_time_left > 0.0:
		objective_target_dash_line_time_left = maxf(0.0, objective_target_dash_line_time_left - delta)
		if is_instance_valid(objective_target_dash_line):
			var alpha := clampf(objective_target_dash_line_time_left / 0.22, 0.0, 1.0)
			objective_target_dash_line.default_color = Color(1.0, 0.86, 0.42, 0.9 * alpha)
			objective_target_dash_line.width = 3.0 + 3.0 * alpha
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
		if objective_overtime:
			diamond.color = Color(1.0, 0.44, 0.32, 0.96)
		else:
			diamond.color = Color(1.0, 0.84, 0.3, 0.95)
	if stem != null:
		if objective_overtime:
			stem.default_color = Color(1.0, 0.62, 0.36, 0.92)
		else:
			stem.default_color = Color(1.0, 0.9, 0.46, 0.9)

func _enrage_priority_target() -> void:
	if not is_instance_valid(objective_target_enemy):
		return
	if objective_target_enemy.get("seek_speed") != null:
		objective_target_enemy.set("seek_speed", float(objective_target_enemy.get("seek_speed")) * 1.2)
	if objective_target_enemy.get("move_speed") != null:
		objective_target_enemy.set("move_speed", float(objective_target_enemy.get("move_speed")) * 1.18)
	if objective_target_enemy.get("windup_time") != null:
		objective_target_enemy.set("windup_time", maxf(0.18, float(objective_target_enemy.get("windup_time")) * 0.8))
	if objective_target_enemy.get("attack_cooldown") != null:
		objective_target_enemy.set("attack_cooldown", maxf(0.45, float(objective_target_enemy.get("attack_cooldown")) * 0.8))

func _on_priority_target_died() -> void:
	if active_objective_kind != "priority_target":
		return
	objective_target_enemy = null
	_complete_current_objective("Target Eliminated", "%s down" % objective_target_name)

func _get_hud_state() -> Dictionary:
	return {
		"room_size": current_room_size,
		"rooms_cleared": rooms_cleared,
		"room_depth": room_depth,
		"run_cleared": run_cleared,
		"current_room_enemy_mutator": current_room_enemy_mutator,
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
		"objective_target_flee_thresholds": objective_target_flee_thresholds,
		"objective_target_next_flee_index": objective_target_next_flee_index,
	}

func _get_priority_target_health() -> int:
	if not is_instance_valid(objective_target_enemy):
		return 0
	if objective_target_enemy.has_method("_get_current_health"):
		return int(objective_target_enemy.call("_get_current_health"))
	return 0

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

	var half_view := viewport_size * 0.5 * player_camera.zoom
	var min_visible := player_camera.global_position - half_view + Vector2.ONE * camera_player_margin
	var max_visible := player_camera.global_position + half_view - Vector2.ONE * camera_player_margin

	player.global_position.x = clampf(player.global_position.x, min_visible.x, max_visible.x)
	player.global_position.y = clampf(player.global_position.y, min_visible.y, max_visible.y)

func _update_encounter_state() -> void:
	if choosing_next_room or run_cleared:
		return
	if active_objective_kind == "survival" or active_objective_kind == "priority_target":
		return
	if active_room_enemy_count > 0:
		return
	_on_room_cleared()

func _on_room_cleared() -> void:
	if not is_instance_valid(encounter_flow_system):
		return
	var raw_outcome: Variant = encounter_flow_system.call("resolve_room_cleared", in_boss_room, pending_room_reward, rooms_cleared, room_depth, encounter_count)
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
		hud.show_banner("Boss Defeated", "Endless continues")
		_spawn_door_options()
		return
	if run_cleared:
		choosing_next_room = false
		return
	rooms_cleared = ENCOUNTER_CONTRACTS.outcome_rooms_cleared(outcome)
	room_depth = ENCOUNTER_CONTRACTS.outcome_room_depth(outcome)
	boss_unlocked = ENCOUNTER_CONTRACTS.outcome_boss_unlocked(outcome)
	if _is_endless_mode() and endless_boss_defeated:
		boss_unlocked = false
	pending_room_reward = ENCOUNTER_CONTRACTS.outcome_pending_room_reward(outcome)
	var reward_mode: int = ENCOUNTER_CONTRACTS.outcome_open_reward_mode(outcome)
	if reward_mode == ENUMS.RewardMode.BOON:
		_open_boon_selection("Choose Boon Reward", false, ENUMS.RewardMode.BOON)
		return
	if reward_mode == ENUMS.RewardMode.ARCANA:
		var is_first_arcana := arcana_rewards_taken.is_empty()
		_open_boon_selection("Choose Arcana", is_first_arcana, ENUMS.RewardMode.ARCANA)
		return
	if ENCOUNTER_CONTRACTS.outcome_spawn_doors(outcome):
		_spawn_door_options()

func _get_run_context() -> Node:
	return get_node_or_null(RUN_CONTEXT_PATH)

func _is_endless_mode() -> bool:
	var run_context := _get_run_context()
	if run_context == null:
		return false
	if run_context.has_method("is_endless_mode"):
		return bool(run_context.call("is_endless_mode"))
	var mode_value: Variant = run_context.get("run_mode")
	if mode_value == null:
		return false
	if mode_value is int:
		return int(mode_value) == ENUMS.RunMode.ENDLESS
	return String(mode_value).to_lower() == "endless"

func _sync_audio_settings_from_context() -> void:
	var run_context := _get_run_context()
	if run_context == null:
		return
	var music_volume_value: Variant = run_context.get("music_volume_db")
	if music_volume_value != null:
		music_volume_db = float(music_volume_value)

func _is_reward_selection_active() -> bool:
	return is_instance_valid(reward_selection_ui) and bool(reward_selection_ui.call("is_active"))

func _set_music_volume_runtime(music_db: float) -> void:
	music_volume_db = clampf(music_db, -60.0, -6.0)
	if is_instance_valid(music_system):
		music_system.set("music_volume_db", music_volume_db)

func _on_pause_menu_opened() -> void:
	_set_combat_paused(true)

func _on_pause_menu_closed() -> void:
	_set_combat_paused(_is_reward_selection_active())

func _on_pause_back_to_menu_requested() -> void:
	_set_combat_paused(false)
	if is_instance_valid(pause_menu_controller):
		pause_menu_controller.call("close")
	get_tree().change_scene_to_file(MENU_SCENE_PATH)

func _on_pause_exit_game_requested() -> void:
	get_tree().quit()

func _spawn_door_options() -> void:
	if not is_instance_valid(encounter_flow_system):
		return
	door_options.clear()
	choosing_next_room = true
	var route_options := _roll_route_options(room_depth)
	door_options = encounter_flow_system.call("build_door_options", boss_unlocked, room_depth, door_distance_from_center, route_options)

func _try_use_door() -> void:
	if not choosing_next_room:
		return
	if not is_instance_valid(player):
		return
	if not Input.is_action_just_pressed("interact"):
		return
	if not is_instance_valid(encounter_flow_system):
		return
	var raw_result: Variant = encounter_flow_system.call("find_used_door", player.global_position, door_options, door_use_radius)
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
	var raw_choice: Variant = encounter_flow_system.call("resolve_chosen_door", door)
	var choice: Dictionary = ENCOUNTER_CONTRACTS.normalize_door_choice(raw_choice)
	var action_id: int = ENCOUNTER_CONTRACTS.door_choice_action_id(choice)
	if action_id == ENUMS.EncounterAction.BOSS:
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
	in_boss_room = false
	active_objective_kind = ""
	objective_time_left = 0.0
	objective_spawn_interval = 0.0
	objective_spawn_timer = 0.0
	objective_spawn_batch = 1
	objective_max_enemies = 0
	objective_kill_target = 0
	objective_kills = 0
	objective_overtime = false
	objective_target_enemy = null
	objective_target_type = ""
	objective_target_name = ""
	_play_room_music(false)
	current_room_size = ENCOUNTER_CONTRACTS.profile_room_size(profile)
	current_room_static_camera = ENCOUNTER_CONTRACTS.profile_static_camera(profile)
	current_room_label = ENCOUNTER_CONTRACTS.profile_label(profile)
	current_room_enemy_mutator = ENCOUNTER_CONTRACTS.profile_enemy_mutator(profile)
	var mutator_name := ENCOUNTER_CONTRACTS.mutator_name(current_room_enemy_mutator)
	var room_subtitle := ""
	var sub_color := Color(0.78, 0.9, 1.0, 0.92)
	if not mutator_name.is_empty():
		var banner_suffix := ENCOUNTER_CONTRACTS.mutator_banner_suffix(current_room_enemy_mutator)
		room_subtitle = mutator_name
		if not banner_suffix.is_empty():
			room_subtitle += "  -  " + banner_suffix
		sub_color = ENCOUNTER_CONTRACTS.mutator_theme_color(current_room_enemy_mutator, sub_color)
		sub_color.a = 0.92
	hud.show_banner(current_room_label, room_subtitle, sub_color)
	if is_instance_valid(enemy_spawner):
		enemy_spawner.call("configure_room", current_room_size, spawn_padding, spawn_safe_radius, current_room_enemy_mutator)
	_apply_camera_bounds_for_room(current_room_size)
	active_room_enemy_count = _spawn_profile_enemies(profile)
	active_objective_kind = ENCOUNTER_CONTRACTS.profile_objective_kind(profile)
	if active_objective_kind == "survival":
		objective_time_left = ENCOUNTER_CONTRACTS.profile_objective_duration(profile)
		objective_spawn_interval = ENCOUNTER_CONTRACTS.profile_objective_spawn_interval(profile)
		objective_spawn_timer = objective_spawn_interval
		objective_spawn_batch = ENCOUNTER_CONTRACTS.profile_objective_spawn_batch(profile)
		objective_max_enemies = mini(24, 12 + int(floor(float(room_depth) * 0.9)))
		var raw_kill_target := maxi(10, int(round(objective_time_left * 0.42)) + 2 + int(floor(float(room_depth) * 0.35)))
		objective_kill_target = int(ceil(float(raw_kill_target) / 5.0)) * 5
		objective_kills = 0
		objective_overtime = false
		hud.show_banner(current_room_label, "Survive %.0fs and kill %d" % [objective_time_left, objective_kill_target], sub_color)
	elif active_objective_kind == "priority_target":
		objective_target_type = ENCOUNTER_CONTRACTS.profile_objective_target_type(profile)
		if objective_target_type.is_empty():
			objective_target_type = "archer"
		objective_target_name = "Signal"
		objective_time_left = ENCOUNTER_CONTRACTS.profile_objective_duration(profile)
		objective_spawn_interval = ENCOUNTER_CONTRACTS.profile_objective_spawn_interval(profile)
		objective_spawn_timer = maxf(0.4, objective_spawn_interval * 0.7)
		objective_spawn_batch = ENCOUNTER_CONTRACTS.profile_objective_spawn_batch(profile)
		objective_max_enemies = 12 + int(floor(float(room_depth) * 0.6))
		objective_overtime = false
		_spawn_priority_target_enemy()
		hud.show_banner(current_room_label, "The mark starts guarded. Timer expiry escalates escorts.", Color(1.0, 0.84, 0.3, 0.95))

func _enter_rest_site() -> void:
	in_boss_room = false
	_play_room_music(false)
	current_room_label = "Rest Site"
	hud.show_banner("Rest Site", "Recovering...")
	current_room_static_camera = true
	_advance_room_progress()
	if is_instance_valid(player) and player.has_method("heal"):
		var player_max_health := int(player.get("max_health"))
		var heal_amount := maxi(8, int(round(float(player_max_health) * rest_heal_ratio)))
		player.call("heal", heal_amount)
	_spawn_door_options()

func _advance_room_progress() -> void:
	if not is_instance_valid(encounter_flow_system):
		return
	var progress: Dictionary = encounter_flow_system.call("advance_room_progress", rooms_cleared, room_depth, encounter_count)
	rooms_cleared = int(progress.get("rooms_cleared", rooms_cleared))
	room_depth = int(progress.get("room_depth", room_depth))
	boss_unlocked = bool(progress.get("boss_unlocked", boss_unlocked))

func _begin_boss_room() -> void:
	in_boss_room = true
	_play_room_music(true)
	current_room_size = Vector2(1260.0, 900.0)
	current_room_static_camera = false
	current_room_label = "Boss Chamber: The Warden"
	hud.show_banner("Boss Chamber", "The Warden")
	_apply_camera_bounds_for_room(current_room_size)
	active_room_enemy_count = 1
	var boss := CharacterBody2D.new()
	boss.set_script(ENEMY_BOSS_SCRIPT)

	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = CircleShape2D.new()
	collision_shape.shape.radius = 34.0
	boss.add_child(collision_shape)

	boss.global_position = Vector2(0.0, -30.0)
	add_child(boss)
	boss.set("target", player)
	boss.set("arena_size", current_room_size)
	if boss.has_signal("died"):
		boss.died.connect(_on_room_enemy_died)

func _spawn_profile_enemies(profile: Dictionary) -> int:
	if not is_instance_valid(enemy_spawner):
		return 0
	return int(enemy_spawner.call("spawn_profile_enemies", profile))

func _play_room_music(is_boss_room: bool, instant: bool = false, fade_duration: float = -1.0) -> void:
	if not is_instance_valid(music_system):
		return
	music_system.call("play_room_music", is_boss_room, instant, fade_duration)

func _on_room_enemy_died() -> void:
	active_room_enemy_count = maxi(0, active_room_enemy_count - 1)
	if active_objective_kind == "survival":
		objective_kills += 1
	if active_objective_kind == "priority_target" and objective_overtime and objective_spawn_timer > 0.2:
		objective_spawn_timer = maxf(0.2, objective_spawn_timer - 0.08)
	if is_instance_valid(player) and player.has_method("notify_enemy_killed"):
		player.call("notify_enemy_killed")

func _clear_all_enemies() -> void:
	if is_instance_valid(enemy_spawner):
		enemy_spawner.call("clear_all_enemies")

func _apply_camera_bounds_for_room(room_size: Vector2) -> void:
	if not is_instance_valid(player_camera):
		return
	if not player_camera.has_method("set_world_bounds"):
		return
	var rect := Rect2(-room_size * 0.5, room_size)
	player_camera.call("set_world_bounds", rect)

func _update_camera_mode() -> void:
	if not is_instance_valid(player_camera):
		return
	if (is_instance_valid(reward_selection_ui) and bool(reward_selection_ui.call("is_active"))) or choosing_next_room:
		if player_camera.has_method("set_static_mode"):
			player_camera.call("set_static_mode", Vector2.ZERO)
		return
	if current_room_static_camera and player_camera.has_method("set_static_mode"):
		player_camera.call("set_static_mode", Vector2.ZERO)
		return
	if player_camera.has_method("set_follow_mode"):
		player_camera.call("set_follow_mode")

func _build_skirmish_profile(depth: int) -> Dictionary:
	if not is_instance_valid(encounter_profile_builder):
		return {}
	return encounter_profile_builder.call("build_skirmish_profile", depth)

func _roll_route_options(depth: int) -> Array[Dictionary]:
	if not is_instance_valid(encounter_profile_builder):
		return []
	return encounter_profile_builder.call("roll_route_options", depth)

func _open_boon_selection(title: String, is_initial: bool, mode: int = ENUMS.RewardMode.BOON) -> void:
	if is_instance_valid(reward_selection_ui):
		reward_selection_ui.call("open_selection", title, is_initial, mode, power_registry_instance, player, rng)
		_set_combat_paused(true)

func _on_reward_selected(choice: Dictionary, mode: int, is_initial: bool) -> void:
	if mode == ENUMS.RewardMode.ARCANA:
		_apply_arcana_to_player(String(choice["id"]))
		arcana_rewards_taken.append(String(choice["name"]))
	else:
		_apply_boon_to_player(String(choice["id"]))
		boons_taken.append(String(choice["name"]))
	_set_combat_paused(false)
	if is_initial:
		_begin_room(_build_skirmish_profile(room_depth))
	else:
		_spawn_door_options()
	hud.refresh(_get_hud_state(), player)

func _apply_boon_to_player(boon_id: String) -> void:
	if not is_instance_valid(player):
		return
	if player.has_method("apply_upgrade"):
		player.call("apply_upgrade", boon_id)

func _apply_arcana_to_player(reward_id: String) -> void:
	if not is_instance_valid(player):
		return
	if player.has_method("apply_trial_power"):
		player.call("apply_trial_power", reward_id)

func _set_combat_paused(paused: bool) -> void:
	if is_instance_valid(player):
		if player is CharacterBody2D:
			(player as CharacterBody2D).velocity = Vector2.ZERO
		player.set_physics_process(not paused)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node:
			(enemy as Node).set_physics_process(not paused)
			(enemy as Node).set_process(not paused)
