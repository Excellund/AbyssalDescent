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
const DEBUG_RUN_NORMAL := 0
const DEBUG_RUN_FIRST_BOSS := 1

@export var player_path: NodePath = NodePath("Player")
@export var encounter_count: int = 5
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
@export_enum("Normal", "First Boss") var debug_run_state: int = DEBUG_RUN_NORMAL

var player: Node2D
var player_camera: Camera2D
var rng := RandomNumberGenerator.new()
var power_registry_instance: Node

var rooms_cleared: int = 0
var room_depth: int = 0
var active_room_enemy_count: int = 0
var boss_unlocked: bool = false
var in_boss_room: bool = false
var choosing_next_room: bool = false
var run_cleared: bool = false

var boons_taken: Array[String] = []
var trial_rewards_taken: Array[String] = []

var current_room_size: Vector2 = Vector2.ZERO
var current_room_static_camera: bool = true
var current_room_label: String = ""
var door_options: Array[Dictionary] = []
var pending_room_reward: String = "none"
var current_room_enemy_mutator: Dictionary = {}

var hud_panel: Panel
var hud_label: Label
var room_banner_title_label: Label
var room_banner_subtitle_label: Label
var room_banner_tween: Tween
var room_banner_top_margin: float = 18.0
var art_time: float = 0.0
var music_system: Node
var enemy_spawner: Node
var encounter_profile_builder: Node
var encounter_flow_system: Node
var reward_selection_ui: Node

func _ready() -> void:
	rng.randomize()
	power_registry_instance = POWER_REGISTRY.new()
	player = get_node_or_null(player_path) as Node2D
	if is_instance_valid(player):
		player_camera = player.get_node_or_null("Camera2D") as Camera2D

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
	_create_hud()
	_apply_debug_start_powers_if_needed()
	if debug_run_state != DEBUG_RUN_NORMAL:
		_apply_debug_run_state(_debug_run_state_to_key(debug_run_state))
		queue_redraw()
		return
	if debug_skip_starting_boon_selection:
		_begin_room(_build_skirmish_profile(room_depth))
	else:
		_open_boon_selection("Choose Starting Boon", true, "boon")
	queue_redraw()

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

	_update_hud()
	return {
		"applied": applied,
		"unknown": unknown
	}

func start_run_with_command(command: String) -> Dictionary:
	return start_run_with_powers(_parse_power_command(command))

func go_do_that_thing(state: String) -> Dictionary:
	return _apply_debug_run_state(state)

func _debug_run_state_to_key(state_value: int) -> String:
	if state_value == DEBUG_RUN_FIRST_BOSS:
		return "first_boss"
	return "normal"

func _apply_debug_run_state(state: String) -> Dictionary:
	var normalized := state.strip_edges().to_lower()
	for keyword in ["go", "to", "do", "that", "thing", "state", "run", "at", "the"]:
		normalized = normalized.replace(keyword, " ")
	for sep in [",", ";", "|", "\n", "\t", "-"]:
		normalized = normalized.replace(sep, " ")
	normalized = normalized.strip_edges()

	if normalized.is_empty():
		normalized = _debug_run_state_to_key(debug_run_state)

	var aliases := {
		"boss": "first_boss",
		"first boss": "first_boss",
		"boss1": "first_boss",
		"boss 1": "first_boss"
	}
	if aliases.has(normalized):
		normalized = String(aliases[normalized])

	if normalized == "normal":
		return {"ok": true, "state": "normal", "note": "No debug jump applied."}

	if normalized != "first_boss":
		return {"ok": false, "state": normalized, "note": "Unknown state. Use first_boss."}

	# Reset transient UI and encounter state before jumping.
	if is_instance_valid(reward_selection_ui):
		reward_selection_ui.call("close_selection")
	_set_combat_paused(false)
	choosing_next_room = false
	door_options.clear()
	pending_room_reward = "none"
	run_cleared = false
	in_boss_room = false
	active_room_enemy_count = 0
	_clear_all_enemies()

	if is_instance_valid(player):
		player.global_position = Vector2.ZERO

	rooms_cleared = encounter_count
	room_depth = encounter_count
	boss_unlocked = true
	_begin_boss_room()

	_update_hud()
	return {"ok": true, "state": normalized}

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

func _process(delta: float) -> void:
	art_time += delta
	if is_instance_valid(reward_selection_ui) and bool(reward_selection_ui.call("is_active")):
		_update_boon_selection_input(delta)
		_update_hud()
		queue_redraw()
		return

	_keep_player_inside_current_room()
	_keep_enemies_inside_current_room()
	_keep_player_inside_camera_view()
	_try_use_door()
	_update_encounter_state()
	_update_camera_mode()
	_update_room_banner_layout()
	_update_hud()
	queue_redraw()

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
	if active_room_enemy_count > 0:
		return
	_on_room_cleared()

func _on_room_cleared() -> void:
	if not is_instance_valid(encounter_flow_system):
		return
	var outcome: Dictionary = encounter_flow_system.call("resolve_room_cleared", in_boss_room, pending_room_reward, rooms_cleared, room_depth, encounter_count)
	run_cleared = bool(outcome.get("run_cleared", false))
	if run_cleared:
		choosing_next_room = false
		return
	rooms_cleared = int(outcome.get("rooms_cleared", rooms_cleared))
	room_depth = int(outcome.get("room_depth", room_depth))
	boss_unlocked = bool(outcome.get("boss_unlocked", boss_unlocked))
	pending_room_reward = String(outcome.get("pending_room_reward", "none"))
	var reward_mode := String(outcome.get("open_reward_mode", ""))
	if reward_mode == "boon":
		_open_boon_selection("Choose Boon Reward", false, "boon")
		return
	if reward_mode == "trial_reward":
		_open_boon_selection("Choose Trial Reward", false, "trial_reward")
		return
	if bool(outcome.get("spawn_doors", false)):
		_spawn_door_options()

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
	var result: Dictionary = encounter_flow_system.call("find_used_door", player.global_position, door_options, door_use_radius)
	if not bool(result.get("used", false)):
		return
	var used_door := result.get("door", {}) as Dictionary
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
	var choice: Dictionary = encounter_flow_system.call("resolve_chosen_door", door)
	var action := String(choice.get("action", "encounter"))
	if action == "boss":
		_begin_boss_room()
		return
	if action == "rest":
		_enter_rest_site()
		return
	var profile: Dictionary = choice.get("profile", {})
	pending_room_reward = String(choice.get("reward", "none"))
	current_room_enemy_mutator = profile.get("enemy_mutator", {})
	_begin_room(profile)

func _begin_room(profile: Dictionary) -> void:
	if profile.is_empty():
		return
	in_boss_room = false
	_play_room_music(false)
	current_room_size = profile["room_size"]
	current_room_static_camera = profile["static_camera"]
	current_room_label = profile["label"]
	current_room_enemy_mutator = profile.get("enemy_mutator", {})
	var mutator_name := String(current_room_enemy_mutator.get("name", ""))
	var room_subtitle := ""
	if not mutator_name.is_empty():
		var banner_suffix := String(current_room_enemy_mutator.get("banner_suffix", ""))
		room_subtitle = mutator_name
		if not banner_suffix.is_empty():
			room_subtitle += "  —  " + banner_suffix
		var sub_color: Color = current_room_enemy_mutator.get("theme_color", Color(0.78, 0.9, 1.0, 0.92))
		sub_color.a = 0.92
		if room_banner_subtitle_label != null:
			room_banner_subtitle_label.add_theme_color_override("font_color", sub_color)
	else:
		if room_banner_subtitle_label != null:
			room_banner_subtitle_label.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0, 0.92))
	_show_room_banner(current_room_label, room_subtitle)
	if is_instance_valid(enemy_spawner):
		enemy_spawner.call("configure_room", current_room_size, spawn_padding, spawn_safe_radius, current_room_enemy_mutator)
	_apply_camera_bounds_for_room(current_room_size)
	active_room_enemy_count = _spawn_profile_enemies(profile)

func _enter_rest_site() -> void:
	in_boss_room = false
	_play_room_music(false)
	current_room_label = "Rest Site"
	_show_room_banner("Rest Site", "Recovering...")
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
	_show_room_banner("Boss Chamber", "The Warden")
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

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)

	hud_panel = Panel.new()
	hud_panel.position = Vector2(12.0, 10.0)
	hud_panel.custom_minimum_size = Vector2(980.0, 74.0)
	var hud_style := StyleBoxFlat.new()
	hud_style.bg_color = Color(0.03, 0.05, 0.08, clampf(hud_background_alpha, 0.45, 0.9))
	hud_style.border_color = Color(0.83, 0.9, 1.0, 0.76)
	hud_style.border_width_left = 2
	hud_style.border_width_top = 2
	hud_style.border_width_right = 2
	hud_style.border_width_bottom = 2
	hud_style.corner_radius_top_left = 8
	hud_style.corner_radius_top_right = 8
	hud_style.corner_radius_bottom_left = 8
	hud_style.corner_radius_bottom_right = 8
	hud_panel.add_theme_stylebox_override("panel", hud_style)
	layer.add_child(hud_panel)

	hud_label = Label.new()
	hud_label.position = Vector2(16.0, 10.0)
	hud_label.add_theme_font_size_override("font_size", 20)
	hud_label.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0, 0.98))
	hud_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.06, 0.95))
	hud_label.add_theme_constant_override("shadow_offset_x", 2)
	hud_label.add_theme_constant_override("shadow_offset_y", 2)
	hud_panel.add_child(hud_label)
	_update_hud()

	# Room entry banner — centered, fades in then out on room entry.
	var banner_layer := CanvasLayer.new()
	banner_layer.layer = 110
	banner_layer.follow_viewport_enabled = false
	banner_layer.follow_viewport_scale = 1.0
	add_child(banner_layer)

	var banner_container := Control.new()
	banner_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_layer.add_child(banner_container)

	room_banner_title_label = Label.new()
	room_banner_title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	room_banner_title_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	room_banner_title_label.grow_vertical = Control.GROW_DIRECTION_END
	room_banner_title_label.offset_left = 0.0
	room_banner_title_label.offset_right = 0.0
	room_banner_title_label.offset_top = 92.0
	room_banner_title_label.offset_bottom = 126.0
	room_banner_title_label.add_theme_font_size_override("font_size", 30)
	room_banner_title_label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.84, 0.96))
	room_banner_title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	room_banner_title_label.add_theme_constant_override("shadow_offset_x", 2)
	room_banner_title_label.add_theme_constant_override("shadow_offset_y", 2)
	room_banner_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_banner_title_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	room_banner_title_label.modulate.a = 0.0
	banner_container.add_child(room_banner_title_label)

	room_banner_subtitle_label = Label.new()
	room_banner_subtitle_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	room_banner_subtitle_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	room_banner_subtitle_label.grow_vertical = Control.GROW_DIRECTION_END
	room_banner_subtitle_label.offset_left = 0.0
	room_banner_subtitle_label.offset_right = 0.0
	room_banner_subtitle_label.offset_top = 124.0
	room_banner_subtitle_label.offset_bottom = 152.0
	room_banner_subtitle_label.add_theme_font_size_override("font_size", 18)
	room_banner_subtitle_label.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0, 0.92))
	room_banner_subtitle_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	room_banner_subtitle_label.add_theme_constant_override("shadow_offset_x", 2)
	room_banner_subtitle_label.add_theme_constant_override("shadow_offset_y", 2)
	room_banner_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_banner_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	room_banner_subtitle_label.modulate.a = 0.0
	banner_container.add_child(room_banner_subtitle_label)
	_update_room_banner_layout()

func _update_room_banner_layout() -> void:
	if room_banner_title_label == null or room_banner_subtitle_label == null:
		return

	var top_y := 92.0
	if current_room_size != Vector2.ZERO:
		var room_top_world := Vector2(0.0, -current_room_size.y * 0.5)
		var canvas_xform := get_viewport().get_canvas_transform()
		var room_top_screen := canvas_xform * room_top_world
		var viewport_height := get_viewport().get_visible_rect().size.y
		top_y = clampf(room_top_screen.y + room_banner_top_margin, 16.0, viewport_height * 0.45)

	room_banner_title_label.offset_top = top_y
	room_banner_title_label.offset_bottom = top_y + 34.0
	room_banner_subtitle_label.offset_top = top_y + 32.0
	room_banner_subtitle_label.offset_bottom = top_y + 60.0

func _show_room_banner(title: String, subtitle: String) -> void:
	if room_banner_title_label == null or room_banner_subtitle_label == null:
		return
	if is_instance_valid(room_banner_tween):
		room_banner_tween.kill()

	room_banner_title_label.text = title
	room_banner_subtitle_label.text = subtitle
	_update_room_banner_layout()
	room_banner_title_label.modulate.a = 0.0
	room_banner_subtitle_label.modulate.a = 0.0

	room_banner_tween = create_tween()
	room_banner_tween.tween_property(room_banner_title_label, "modulate:a", 1.0, 0.2)
	if subtitle.is_empty():
		room_banner_subtitle_label.visible = false
	else:
		room_banner_subtitle_label.visible = true
		room_banner_tween.parallel().tween_property(room_banner_subtitle_label, "modulate:a", 1.0, 0.2)
	room_banner_tween.tween_interval(0.95)
	room_banner_tween.tween_property(room_banner_title_label, "modulate:a", 0.0, 0.24)
	room_banner_tween.parallel().tween_property(room_banner_subtitle_label, "modulate:a", 0.0, 0.24)

func _open_boon_selection(title: String, is_initial: bool, mode: String = "boon") -> void:
	if is_instance_valid(reward_selection_ui):
		reward_selection_ui.call("open_selection", title, is_initial, mode, power_registry_instance, player, rng)
		_set_combat_paused(true)
		return

func _update_boon_selection_input(delta: float) -> void:
	if is_instance_valid(reward_selection_ui):
		var result: Dictionary = reward_selection_ui.call("process_input", delta, player)
		if bool(result.get("picked", false)):
			var picked: Dictionary = result.get("choice", {})
			var mode := String(result.get("mode", "boon"))
			if mode == "trial_reward":
				_apply_trial_reward_to_player(String(picked["id"]))
				trial_rewards_taken.append(String(picked["name"]))
			else:
				_apply_boon_to_player(String(picked["id"]))
				boons_taken.append(String(picked["name"]))
			_set_combat_paused(false)
			if bool(result.get("is_initial", false)):
				_begin_room(_build_skirmish_profile(room_depth))
			else:
				_spawn_door_options()
		return

func _apply_boon_to_player(boon_id: String) -> void:
	if not is_instance_valid(player):
		return
	if player.has_method("apply_upgrade"):
		player.call("apply_upgrade", boon_id)

func _apply_trial_reward_to_player(reward_id: String) -> void:
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

func _update_hud() -> void:
	if hud_label == null:
		return
	if run_cleared:
		hud_label.text = "Run Clear  Boons: %d  Trial Rewards: %d" % [boons_taken.size(), trial_rewards_taken.size()]
		return

	if is_instance_valid(reward_selection_ui) and bool(reward_selection_ui.call("is_active")):
		var confirm_lock := float(reward_selection_ui.call("get_confirm_lock_time"))
		if confirm_lock > 0.0:
			hud_label.text = "Boon Reward  Revealing cards..."
		else:
			hud_label.text = "Boon Choice  Click a card to pick 1 of %d" % int(reward_selection_ui.call("get_choice_count"))
		return

	if choosing_next_room:
		var prompt := "Choose Door [E]"
		if boss_unlocked:
			prompt = "Boss Gate Open [E]"
		var option_a := ""
		var option_b := ""
		if door_options.size() > 0:
			option_a = String(door_options[0].get("label", ""))
		if door_options.size() > 1:
			option_b = String(door_options[1].get("label", ""))
		var options_line := option_a
		if not option_b.is_empty():
			options_line += "  |  " + option_b
		hud_label.text = "%s  Rooms Cleared: %d/%d\n%s\nIcon Key: + = Skirmish  >< = Encounter  ◆ = Trial  Cross = Rest  Crown = Boss  Boons: %d  Trials: %d" % [prompt, rooms_cleared, encounter_count, options_line, boons_taken.size(), trial_rewards_taken.size()]
		return

	if in_boss_room and active_room_enemy_count > 0:
		hud_label.text = "%s  Enemies Left: %d\nBoss Telegraphs: Line Charge, Ring Nova, Cone Cleave" % [current_room_label, active_room_enemy_count]
		return

	var boss_text := "Unlocked" if boss_unlocked else "Locked"
	hud_label.text = "%s  Enemies Left: %d  Boss: %s  Boons: %d  Trials: %d" % [current_room_label, active_room_enemy_count, boss_text, boons_taken.size(), trial_rewards_taken.size()]

func _draw() -> void:
	if current_room_size == Vector2.ZERO:
		return
	var t := art_time
	var room_rect := Rect2(-current_room_size * 0.5, current_room_size)
	var pulse := 0.5 + 0.5 * sin(t * 0.9)
	draw_rect(room_rect.grow(240.0), Color(0.01, 0.02, 0.04, clampf(ambient_backdrop_alpha, 0.7, 1.0)), true)

	# Layered floor wash to create depth without textures.
	for i in range(10):
		var ratio := float(i) / 9.0
		var inset := lerpf(0.0, minf(room_rect.size.x, room_rect.size.y) * 0.22, ratio)
		var layer_rect := room_rect.grow(-inset)
		var layer_color := Color(0.03, 0.08, 0.12, 0.17).lerp(Color(0.09, 0.16, 0.23, 0.09 + arena_glow_strength * pulse * 0.32), 1.0 - ratio)
		draw_rect(layer_rect, layer_color, true)

	var coarse_step := maxf(28.0, floor_grid_step)
	var fine_step := maxf(16.0, floor_grid_fine_step)
	for x in range(int(room_rect.position.x), int(room_rect.position.x + room_rect.size.x + coarse_step), int(coarse_step)):
		draw_line(Vector2(float(x), room_rect.position.y), Vector2(float(x), room_rect.position.y + room_rect.size.y), Color(0.36, 0.56, 0.78, clampf(floor_coarse_grid_alpha, 0.01, 0.2)), 2.0)
	for y in range(int(room_rect.position.y), int(room_rect.position.y + room_rect.size.y + coarse_step), int(coarse_step)):
		draw_line(Vector2(room_rect.position.x, float(y)), Vector2(room_rect.position.x + room_rect.size.x, float(y)), Color(0.36, 0.56, 0.78, clampf(floor_coarse_grid_alpha, 0.01, 0.2)), 2.0)

	for x in range(int(room_rect.position.x), int(room_rect.position.x + room_rect.size.x + fine_step), int(fine_step)):
		draw_line(Vector2(float(x), room_rect.position.y), Vector2(float(x), room_rect.position.y + room_rect.size.y), Color(0.55, 0.74, 0.92, clampf(floor_fine_grid_alpha, 0.0, 0.08)), 1.0)
	for y in range(int(room_rect.position.y), int(room_rect.position.y + room_rect.size.y + fine_step), int(fine_step)):
		draw_line(Vector2(room_rect.position.x, float(y)), Vector2(room_rect.position.x + room_rect.size.x, float(y)), Color(0.55, 0.74, 0.92, clampf(floor_fine_grid_alpha, 0.0, 0.08)), 1.0)

	var corners := [
		room_rect.position,
		room_rect.position + Vector2(room_rect.size.x, 0.0),
		room_rect.position + Vector2(0.0, room_rect.size.y),
		room_rect.position + room_rect.size
	]
	for corner in corners:
		draw_circle(corner, 32.0, Color(0.42, 0.74, 1.0, 0.03 + pulse * 0.012))

	draw_rect(room_rect, Color(0.56, 0.78, 0.95, clampf(floor_border_alpha, 0.2, 0.95)), false, 4.0)
	draw_rect(room_rect.grow(-16.0), Color(0.22, 0.42, 0.62, 0.28), false, 2.0)

	if choosing_next_room:
		for door in door_options:
			var door_pos: Vector2 = door["position"]
			var color: Color = door["color"]
			var door_pulse := 0.75 + 0.25 * sin(t * 4.2 + door_pos.x * 0.01)
			draw_circle(door_pos, 34.0 + 4.0 * door_pulse, Color(color.r, color.g, color.b, 0.12))
			draw_circle(door_pos, 22.0 + 2.0 * door_pulse, Color(color.r, color.g, color.b, 0.24))
			draw_circle(door_pos, 14.0, color)
			draw_arc(door_pos, 30.0, -PI * 0.35, PI * 1.35, 36, Color(color.r, color.g, color.b, 0.7), 2.0)
			_draw_door_icon(door)

func _draw_door_icon(door: Dictionary) -> void:
	var door_pos: Vector2 = door["position"]
	var icon_color := Color(0.97, 0.98, 1.0, 0.96)
	var outline_color := Color(0.08, 0.1, 0.14, 0.88)
	var kind := String(door["kind"])
	var icon := String(door.get("icon", "easy"))

	if kind == "boss":
		var left_tip := door_pos + Vector2(-8.0, -5.0)
		var peak := door_pos + Vector2(0.0, -12.0)
		var right_tip := door_pos + Vector2(8.0, -5.0)
		var crown_base_l := door_pos + Vector2(-9.0, 2.0)
		var crown_base_r := door_pos + Vector2(9.0, 2.0)
		var crown := PackedVector2Array([crown_base_l, left_tip, door_pos + Vector2(-3.0, -2.0), peak, door_pos + Vector2(3.0, -2.0), right_tip, crown_base_r])
		draw_polyline(crown, outline_color, 4.8)
		draw_polyline(crown, icon_color, 3.0)
		draw_circle(door_pos + Vector2(0.0, 0.8), 2.4, outline_color)
		draw_circle(door_pos + Vector2(0.0, 0.8), 1.5, Color(1.0, 0.86, 0.42, 0.96))
		return

	if icon == "hard" or icon == "easy":
		# Crossed blades, reduced to a clear two-stroke silhouette.
		var blade_a_l := door_pos + Vector2(-9.5, -7.0)
		var blade_a_r := door_pos + Vector2(9.5, 7.0)
		var blade_b_l := door_pos + Vector2(-9.5, 7.0)
		var blade_b_r := door_pos + Vector2(9.5, -7.0)
		draw_line(blade_a_l, blade_a_r, outline_color, 5.6)
		draw_line(blade_b_l, blade_b_r, outline_color, 5.6)
		draw_line(blade_a_l, blade_a_r, icon_color, 2.9)
		draw_line(blade_b_l, blade_b_r, icon_color, 2.9)
		draw_circle(door_pos, 3.4, outline_color)
		draw_circle(door_pos, 2.0, Color(1.0, 0.92, 0.74, 0.95))
		return

	if icon == "trial":
		# Read mutator shape identity from embedded profile — fallback to diamond if absent
		var trial_mutator: Dictionary = door.get("profile", {}).get("enemy_mutator", {})
		var shape_id := String(trial_mutator.get("icon_shape_id", ""))
		var theme: Color = trial_mutator.get("theme_color", icon_color)
		theme.a = 1.0
		_draw_trial_mutator_icon(door_pos, shape_id, theme, icon_color, outline_color)
		return

	if icon == "rest":
		draw_circle(door_pos, 10.0, outline_color)
		draw_circle(door_pos, 8.0, Color(0.24, 0.56, 0.34, 0.75))
		var rest_h_l := door_pos + Vector2(-8.0, 0.0)
		var rest_h_r := door_pos + Vector2(8.0, 0.0)
		var rest_v_t := door_pos + Vector2(0.0, -8.0)
		var rest_v_b := door_pos + Vector2(0.0, 8.0)
		draw_line(rest_h_l, rest_h_r, outline_color, 5.0)
		draw_line(rest_v_t, rest_v_b, outline_color, 5.0)
		draw_line(rest_h_l, rest_h_r, Color(0.84, 1.0, 0.86, 0.96), 3.0)
		draw_line(rest_v_t, rest_v_b, Color(0.84, 1.0, 0.86, 0.96), 3.0)
		return

	var h_l := door_pos + Vector2(-8.0, 0.0)
	var h_r := door_pos + Vector2(8.0, 0.0)
	var v_t := door_pos + Vector2(0.0, -8.0)
	var v_b := door_pos + Vector2(0.0, 8.0)
	draw_line(h_l, h_r, outline_color, 4.7)
	draw_line(v_t, v_b, outline_color, 4.7)
	draw_line(h_l, h_r, icon_color, 2.5)
	draw_line(v_t, v_b, icon_color, 2.5)
	draw_circle(door_pos, 1.7, Color(0.92, 0.98, 1.0, 0.92))

func _draw_trial_mutator_icon(door_pos: Vector2, shape_id: String, theme: Color, icon_color: Color, outline_color: Color) -> void:
	# Keep one clean ring and one bold symbol for at-speed readability.
	draw_arc(door_pos, 11.4, 0.0, TAU, 28, outline_color, 3.6)
	draw_arc(door_pos, 11.4, 0.0, TAU, 28, Color(theme.r, theme.g, theme.b, 0.86), 2.2)

	match shape_id:
		"blood_rush":
			# Three simple outward spikes.
			for a in [0.0, PI * 0.667, PI * 1.333]:
				var dir := Vector2.RIGHT.rotated(a)
				var tip := door_pos + dir * 10.5
				var base := door_pos + dir * 3.6
				var side := Vector2(-dir.y, dir.x)
				var left_wing := base + side * 2.9
				var right_wing := base - side * 2.9
				var arrow := PackedVector2Array([left_wing, tip, right_wing])
				draw_colored_polygon(arrow, theme)
			draw_circle(door_pos, 2.9, outline_color)
			draw_circle(door_pos, 1.8, theme)

		"flashpoint":
			# Single bolt shape.
			var top_pt := door_pos + Vector2(-1.0, -11.0)
			var mid_r  := door_pos + Vector2(5.0, -1.0)
			var mid_l  := door_pos + Vector2(-4.5, 1.0)
			var bot_pt := door_pos + Vector2(1.0, 11.0)
			draw_line(top_pt, mid_r, outline_color, 5.6)
			draw_line(mid_r,  bot_pt, outline_color, 5.6)
			draw_line(top_pt, mid_r, theme, 3.4)
			draw_line(mid_r,  bot_pt, theme, 3.4)
			draw_line(mid_l, mid_r, outline_color, 3.4)
			draw_line(mid_l, mid_r, theme, 2.1)

		"siegebreak":
			# Ram head silhouette only.
			var tip_r := door_pos + Vector2(12.0, 0.0)
			var body_tr := door_pos + Vector2(6.0, -6.0)
			var body_tl := door_pos + Vector2(-8.0, -6.0)
			var body_bl := door_pos + Vector2(-8.0, 6.0)
			var body_br := door_pos + Vector2(6.0, 6.0)
			var ram := PackedVector2Array([tip_r, body_tr, body_tl, body_bl, body_br])
			draw_colored_polygon(ram, Color(outline_color.r, outline_color.g, outline_color.b, 0.9))
			var ram_inner := PackedVector2Array([
				door_pos + Vector2(10.0, 0.0),
				door_pos + Vector2(5.0, -4.5),
				door_pos + Vector2(-6.5, -4.5),
				door_pos + Vector2(-6.5, 4.5),
				door_pos + Vector2(5.0, 4.5)
			])
			draw_colored_polygon(ram_inner, theme)
			draw_line(door_pos + Vector2(-4.5, -4.0), door_pos + Vector2(-4.5, 4.0), outline_color, 1.7)

		"iron_volley":
			# Shield with two simple side arrows.
			var shield := PackedVector2Array([
				door_pos + Vector2(0.0, -10.0),
				door_pos + Vector2(8.0, -3.0),
				door_pos + Vector2(6.0, 7.0),
				door_pos + Vector2(0.0, 10.0),
				door_pos + Vector2(-6.0, 7.0),
				door_pos + Vector2(-8.0, -3.0)
			])
			draw_colored_polygon(shield, Color(outline_color.r, outline_color.g, outline_color.b, 0.86))
			var shield_inner := PackedVector2Array([
				door_pos + Vector2(0.0, -8.0),
				door_pos + Vector2(6.0, -2.2),
				door_pos + Vector2(4.6, 5.5),
				door_pos + Vector2(0.0, 8.0),
				door_pos + Vector2(-4.6, 5.5),
				door_pos + Vector2(-6.0, -2.2)
			])
			draw_colored_polygon(shield_inner, theme)
			for sx: float in [-1.0, 1.0]:
				var tip := door_pos + Vector2(sx * 10.0, -4.0)
				var base_l := tip + Vector2(-sx * 2.8, 3.8)
				var base_r := tip + Vector2(sx * 2.8, 3.8)
				var arrow := PackedVector2Array([base_l, tip, base_r])
				draw_colored_polygon(arrow, theme)

		_:
			# Fallback: clean diamond sigil.
			var top := door_pos + Vector2(0.0, -10.0)
			var right := door_pos + Vector2(10.0, 0.0)
			var bottom := door_pos + Vector2(0.0, 10.0)
			var left := door_pos + Vector2(-10.0, 0.0)
			var diamond := PackedVector2Array([top, right, bottom, left, top])
			draw_polyline(diamond, outline_color, 4.4)
			draw_polyline(diamond, icon_color, 2.6)
			draw_line(top, bottom, outline_color, 3.4)
			draw_line(top, bottom, icon_color, 1.9)
