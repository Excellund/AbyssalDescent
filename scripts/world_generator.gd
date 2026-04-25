extends Node2D

const ENEMY_CHASER_SCRIPT := preload("res://scripts/enemy_chaser.gd")
const ENEMY_CHARGER_SCRIPT := preload("res://scripts/enemy_charger.gd")

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
@export var rest_heal_ratio: float = 0.32
@export var hard_room_enemy_bonus: int = 3
@export var debug_apply_test_powers_on_start: bool = false
@export var debug_skip_starting_boon_selection: bool = false
@export var debug_start_power_ids: PackedStringArray = PackedStringArray()
@export_multiline var debug_start_command: String = ""

var player: Node2D
var player_camera: Camera2D
var hud_label: Label
var rng := RandomNumberGenerator.new()

var rooms_cleared: int = 0
var room_depth: int = 0
var active_room_enemy_count: int = 0
var boss_unlocked: bool = false
var in_boss_room: bool = false
var choosing_next_room: bool = false
var run_cleared: bool = false

var boon_selection_active: bool = false
var boon_title_text: String = ""
var boon_choices: Array[Dictionary] = []
var pending_initial_boon: bool = false
var boons_taken: Array[String] = []
var hard_rewards_taken: Array[String] = []
var boon_confirm_lock_time: float = 0.0
var boon_hovered_index: int = -1
var boon_reveal_time: float = 0.0
var reward_selection_mode: String = "boon"

var current_room_size: Vector2 = Vector2.ZERO
var current_room_static_camera: bool = true
var current_room_label: String = ""
var door_options: Array[Dictionary] = []
var pending_room_reward: String = "none"
var current_room_enemy_mutator: Dictionary = {}

var boon_layer: CanvasLayer
var boon_title_label: Label
var boon_card_panels: Array[Panel] = []
var boon_card_labels: Array[Label] = []
var boon_card_rects: Array[Rect2] = []
var boon_backdrop: ColorRect
var hud_panel: Panel
var art_time: float = 0.0

func _ready() -> void:
	rng.randomize()
	player = get_node_or_null(player_path) as Node2D
	if is_instance_valid(player):
		player_camera = player.get_node_or_null("Camera2D") as Camera2D

	current_room_size = room_base_size
	current_room_label = "Starting Chamber"
	_apply_camera_bounds_for_room(current_room_size)
	_create_hud()
	_create_boon_ui()
	_apply_debug_start_powers_if_needed()
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
	for boon in _get_boon_pool():
		if String(boon["id"]) == power_id:
			return true
	for reward in _get_hard_reward_pool():
		if String(reward["id"]) == power_id:
			return true
	return false

func _process(delta: float) -> void:
	art_time += delta
	if boon_selection_active:
		_update_boon_selection_input(delta)
		_update_hud()
		queue_redraw()
		return

	_keep_player_inside_current_room()
	_keep_player_inside_camera_view()
	_try_use_door()
	_update_encounter_state()
	_update_camera_mode()
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
	if in_boss_room:
		run_cleared = true
		choosing_next_room = false
		return

	_advance_room_progress()

	if pending_room_reward == "boon":
		pending_room_reward = "none"
		_open_boon_selection("Choose Boon Reward", false, "boon")
		return

	if pending_room_reward == "hard_reward":
		pending_room_reward = "none"
		_open_boon_selection("Choose Hard Trial Reward", false, "hard_reward")
		return

	pending_room_reward = "none"
	_spawn_door_options()

func _spawn_door_options() -> void:
	door_options.clear()
	choosing_next_room = true
	if boss_unlocked:
		door_options.append({
			"label": "Boss",
			"position": Vector2(0.0, -40.0),
			"color": Color(0.95, 0.18, 0.22, 0.98),
			"kind": "boss",
			"icon": "boss",
			"profile": {}
		})
		return

	var route_options := _roll_route_options(room_depth)
	var positions := [Vector2(-door_distance_from_center, -40.0), Vector2(door_distance_from_center, -40.0)]
	for i in range(mini(route_options.size(), positions.size())):
		var option := route_options[i]
		option["position"] = positions[i]
		door_options.append(option)

func _try_use_door() -> void:
	if not choosing_next_room:
		return
	if not is_instance_valid(player):
		return
	if not Input.is_action_just_pressed("interact"):
		return

	for door in door_options:
		var door_pos: Vector2 = door["position"]
		if player.global_position.distance_to(door_pos) > door_use_radius:
			continue
		_choose_door(door)
		return

func _choose_door(door: Dictionary) -> void:
	choosing_next_room = false
	door_options.clear()
	_clear_all_enemies()

	if not is_instance_valid(player):
		return
	player.global_position = Vector2.ZERO

	if String(door["kind"]) == "boss":
		_begin_boss_room()
		return
	if String(door["kind"]) == "rest":
		_enter_rest_site()
		return

	var profile: Dictionary = door["profile"]
	pending_room_reward = String(door.get("reward", "none"))
	current_room_enemy_mutator = profile.get("enemy_mutator", {})
	_begin_room(profile)

func _begin_room(profile: Dictionary) -> void:
	if profile.is_empty():
		return
	in_boss_room = false
	current_room_size = profile["room_size"]
	current_room_static_camera = profile["static_camera"]
	current_room_label = profile["label"]
	current_room_enemy_mutator = profile.get("enemy_mutator", {})
	_apply_camera_bounds_for_room(current_room_size)
	active_room_enemy_count = _spawn_profile_enemies(profile)

func _enter_rest_site() -> void:
	in_boss_room = false
	current_room_label = "Rest Site"
	current_room_static_camera = true
	_advance_room_progress()
	if is_instance_valid(player) and player.has_method("heal"):
		var player_max_health := int(player.get("max_health"))
		var heal_amount := maxi(8, int(round(float(player_max_health) * rest_heal_ratio)))
		player.call("heal", heal_amount)
	_spawn_door_options()

func _advance_room_progress() -> void:
	rooms_cleared += 1
	room_depth += 1
	if rooms_cleared >= encounter_count:
		boss_unlocked = true

func _begin_boss_room() -> void:
	in_boss_room = true
	current_room_size = Vector2(1260.0, 900.0)
	current_room_static_camera = false
	current_room_label = "Boss Chamber"
	_apply_camera_bounds_for_room(current_room_size)
	active_room_enemy_count = 0
	for _i in range(boss_chaser_count):
		_spawn_enemy_in_current_room(ENEMY_CHASER_SCRIPT)
		active_room_enemy_count += 1
	for _i in range(boss_charger_count):
		_spawn_enemy_in_current_room(ENEMY_CHARGER_SCRIPT)
		active_room_enemy_count += 1

func _spawn_profile_enemies(profile: Dictionary) -> int:
	var total := 0
	var chaser_count := int(profile["chaser_count"])
	var charger_count := int(profile["charger_count"])
	for _i in range(chaser_count):
		_spawn_enemy_in_current_room(ENEMY_CHASER_SCRIPT)
		total += 1
	for _i in range(charger_count):
		_spawn_enemy_in_current_room(ENEMY_CHARGER_SCRIPT)
		total += 1
	return total

func _spawn_enemy_in_current_room(enemy_script: Script) -> void:
	var enemy := CharacterBody2D.new()
	enemy.set_script(enemy_script)
	_apply_enemy_mutator(enemy, enemy_script)

	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = CircleShape2D.new()
	collision_shape.shape.radius = 13.0
	enemy.add_child(collision_shape)

	enemy.global_position = _pick_spawn_position_in_current_room()
	add_child(enemy)
	enemy.set("target", player)
	if enemy.has_signal("died"):
		enemy.died.connect(_on_room_enemy_died)

func _apply_enemy_mutator(enemy: CharacterBody2D, enemy_script: Script) -> void:
	if current_room_enemy_mutator.is_empty():
		return

	if enemy_script == ENEMY_CHASER_SCRIPT:
		var base_damage := int(enemy.get("attack_damage"))
		var damage_mult := float(current_room_enemy_mutator.get("chaser_damage_mult", 1.0))
		enemy.set("attack_damage", maxi(1, int(round(float(base_damage) * damage_mult))))

		var base_interval := float(enemy.get("attack_interval"))
		var interval_mult := float(current_room_enemy_mutator.get("chaser_attack_interval_mult", 1.0))
		enemy.set("attack_interval", maxf(0.2, base_interval * interval_mult))

		var base_speed := float(enemy.get("move_speed"))
		var speed_mult := float(current_room_enemy_mutator.get("chaser_speed_mult", 1.0))
		enemy.set("move_speed", maxf(25.0, base_speed * speed_mult))

	if enemy_script == ENEMY_CHARGER_SCRIPT:
		var base_charge_damage := int(enemy.get("charge_damage"))
		var charge_damage_mult := float(current_room_enemy_mutator.get("charger_damage_mult", 1.0))
		enemy.set("charge_damage", maxi(1, int(round(float(base_charge_damage) * charge_damage_mult))))

		var base_charge_speed := float(enemy.get("charge_speed"))
		var charge_speed_mult := float(current_room_enemy_mutator.get("charger_speed_mult", 1.0))
		enemy.set("charge_speed", maxf(60.0, base_charge_speed * charge_speed_mult))

		var base_windup := float(enemy.get("windup_time"))
		var windup_mult := float(current_room_enemy_mutator.get("charger_windup_mult", 1.0))
		enemy.set("windup_time", maxf(0.2, base_windup * windup_mult))

	enemy.modulate = Color(1.0, 0.92, 0.92, 1.0)

func _pick_spawn_position_in_current_room() -> Vector2:
	var half := current_room_size * 0.5 - Vector2.ONE * spawn_padding
	var candidate := Vector2.ZERO
	for _try in range(60):
		candidate = Vector2(
			rng.randf_range(-half.x, half.x),
			rng.randf_range(-half.y, half.y)
		)
		if is_instance_valid(player) and candidate.distance_to(player.global_position) < spawn_safe_radius:
			continue
		return candidate
	return candidate

func _on_room_enemy_died() -> void:
	active_room_enemy_count = maxi(0, active_room_enemy_count - 1)

func _clear_all_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node:
			(enemy as Node).queue_free()

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
	if boon_selection_active or choosing_next_room:
		if player_camera.has_method("set_static_mode"):
			player_camera.call("set_static_mode", Vector2.ZERO)
		return
	if current_room_static_camera and player_camera.has_method("set_static_mode"):
		player_camera.call("set_static_mode", Vector2.ZERO)
		return
	if player_camera.has_method("set_follow_mode"):
		player_camera.call("set_follow_mode")

func _build_skirmish_profile(depth: int) -> Dictionary:
	var size := room_base_size + room_size_growth * float(depth)
	return {
		"label": "Skirmish",
		"room_size": size,
		"static_camera": size.x <= static_camera_room_threshold,
		"chaser_count": base_chaser_count + depth * chasers_per_room,
		"charger_count": maxi(0, depth - chargers_start_room + 1) * chargers_per_room
	}

func _build_onslaught_profile(depth: int) -> Dictionary:
	var size := room_base_size + room_size_growth * float(depth) + Vector2(180.0, 120.0)
	return {
		"label": "Onslaught",
		"room_size": size,
		"static_camera": false,
		"chaser_count": base_chaser_count + depth * chasers_per_room + 3,
		"charger_count": maxi(1, (depth - chargers_start_room + 1) * chargers_per_room + 1)
	}

func _build_easy_boon_profile(depth: int) -> Dictionary:
	var profile := _build_skirmish_profile(depth)
	profile["label"] = "Calm Hunt"
	profile["chaser_count"] = maxi(2, int(profile["chaser_count"]) - 1)
	profile["charger_count"] = maxi(0, int(profile["charger_count"]) - 1)
	profile["enemy_mutator"] = {}
	return profile

func _build_hard_trial_profile(depth: int) -> Dictionary:
	var profile := _build_onslaught_profile(depth)
	profile["label"] = "Savage Trial"
	profile["chaser_count"] = int(profile["chaser_count"]) + hard_room_enemy_bonus
	profile["charger_count"] = int(profile["charger_count"]) + 1
	profile["enemy_mutator"] = _roll_hard_enemy_mutator()
	return profile

func _roll_route_options(depth: int) -> Array[Dictionary]:
	var easy_option := {
		"label": "Calm Hunt + Boon",
		"color": Color(0.28, 0.83, 1.0, 0.95),
		"kind": "encounter",
		"icon": "easy",
		"reward": "boon",
		"profile": _build_easy_boon_profile(depth)
	}
	var hard_profile := _build_hard_trial_profile(depth)
	var mutator_name := String(hard_profile["enemy_mutator"].get("name", "Frenzy"))
	var hard_option := {
		"label": "Savage Trial: %s" % mutator_name,
		"color": Color(1.0, 0.46, 0.2, 0.95),
		"kind": "encounter",
		"icon": "hard",
		"reward": "hard_reward",
		"profile": hard_profile
	}
	var rest_option := {
		"label": "Rest Site",
		"color": Color(0.55, 1.0, 0.65, 0.92),
		"kind": "rest",
		"icon": "rest",
		"reward": "none",
		"profile": {}
	}

	var options := [easy_option, hard_option, rest_option]
	var first: int = 0 if rng.randf() < 0.5 else 1
	var chosen: Array[Dictionary] = [options[first]]

	var remaining_indices: Array[int] = [0, 1, 2]
	remaining_indices.erase(first)
	var second_index: int = remaining_indices[rng.randi_range(0, remaining_indices.size() - 1)]
	chosen.append(options[second_index])
	return chosen

func _roll_hard_enemy_mutator() -> Dictionary:
	var pool: Array[Dictionary] = [
		{
			"name": "Blood Rush",
			"chaser_damage_mult": 1.45,
			"chaser_attack_interval_mult": 0.82,
			"chaser_speed_mult": 1.08,
			"charger_damage_mult": 1.35,
			"charger_speed_mult": 1.0,
			"charger_windup_mult": 0.95
		},
		{
			"name": "Lightning Lunge",
			"chaser_damage_mult": 1.12,
			"chaser_attack_interval_mult": 0.95,
			"chaser_speed_mult": 1.25,
			"charger_damage_mult": 1.22,
			"charger_speed_mult": 1.26,
			"charger_windup_mult": 0.7
		},
		{
			"name": "Siegebreak",
			"chaser_damage_mult": 1.22,
			"chaser_attack_interval_mult": 1.0,
			"chaser_speed_mult": 1.02,
			"charger_damage_mult": 1.52,
			"charger_speed_mult": 1.12,
			"charger_windup_mult": 0.82
		}
	]
	return pool[rng.randi_range(0, pool.size() - 1)]

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)

	hud_panel = Panel.new()
	hud_panel.position = Vector2(12.0, 10.0)
	hud_panel.custom_minimum_size = Vector2(980.0, 74.0)
	var hud_style := StyleBoxFlat.new()
	hud_style.bg_color = Color(0.03, 0.05, 0.08, 0.78)
	hud_style.border_color = Color(0.45, 0.65, 0.88, 0.82)
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
	hud_label.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0, 0.98))
	hud_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.06, 0.95))
	hud_label.add_theme_constant_override("shadow_offset_x", 2)
	hud_label.add_theme_constant_override("shadow_offset_y", 2)
	hud_panel.add_child(hud_label)
	_update_hud()

func _create_boon_ui() -> void:
	boon_layer = CanvasLayer.new()
	boon_layer.layer = 130
	add_child(boon_layer)

	boon_backdrop = ColorRect.new()
	boon_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	boon_backdrop.offset_left = 0.0
	boon_backdrop.offset_top = 0.0
	boon_backdrop.offset_right = 0.0
	boon_backdrop.offset_bottom = 0.0
	boon_backdrop.color = Color(0.01, 0.02, 0.05, 0.8)
	boon_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boon_layer.add_child(boon_backdrop)

	boon_title_label = Label.new()
	boon_title_label.position = Vector2(350.0, 76.0)
	boon_title_label.add_theme_font_size_override("font_size", 32)
	boon_title_label.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0, 1.0))
	boon_title_label.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.04, 0.95))
	boon_title_label.add_theme_constant_override("shadow_offset_x", 2)
	boon_title_label.add_theme_constant_override("shadow_offset_y", 2)
	boon_layer.add_child(boon_title_label)

	boon_card_panels.clear()
	boon_card_labels.clear()
	boon_card_rects.clear()
	for i in range(boon_choice_count):
		var panel := Panel.new()
		panel.position = Vector2(220.0, 164.0 + i * 138.0)
		panel.custom_minimum_size = Vector2(1460.0, 118.0)
		boon_layer.add_child(panel)

		var option_label := Label.new()
		option_label.position = Vector2(18.0, 14.0)
		option_label.add_theme_font_size_override("font_size", 22)
		option_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
		option_label.add_theme_constant_override("shadow_offset_x", 2)
		option_label.add_theme_constant_override("shadow_offset_y", 2)
		panel.add_child(option_label)

		boon_card_panels.append(panel)
		boon_card_labels.append(option_label)
		boon_card_rects.append(Rect2(panel.position, panel.custom_minimum_size))

	boon_layer.visible = false

func _open_boon_selection(title: String, is_initial: bool, mode: String = "boon") -> void:
	boon_selection_active = true
	pending_initial_boon = is_initial
	boon_title_text = title
	reward_selection_mode = mode
	if reward_selection_mode == "hard_reward":
		boon_choices = _roll_hard_reward_choices(boon_choice_count)
	else:
		boon_choices = _roll_boon_choices(boon_choice_count)
	boon_confirm_lock_time = boon_reveal_duration + 0.08
	boon_reveal_time = 0.0
	boon_hovered_index = -1
	_apply_boon_card_styles(-1)
	_set_combat_paused(true)
	_refresh_boon_ui()

func _update_boon_selection_input(delta: float) -> void:
	if boon_choices.is_empty():
		return

	if boon_confirm_lock_time > 0.0:
		boon_confirm_lock_time = maxf(0.0, boon_confirm_lock_time - delta)
		boon_reveal_time += delta
		_update_boon_reveal_visuals()
		return

	_update_boon_hover()
	if Input.is_action_just_pressed("attack"):
		if boon_hovered_index >= 0 and boon_hovered_index < boon_choices.size():
			_confirm_selected_boon(boon_hovered_index)

func _confirm_selected_boon(choice_index: int) -> void:
	if boon_choices.is_empty():
		return
	if choice_index < 0 or choice_index >= boon_choices.size():
		return
	var picked := boon_choices[choice_index]
	if reward_selection_mode == "hard_reward":
		_apply_hard_reward_to_player(String(picked["id"]))
		hard_rewards_taken.append(String(picked["name"]))
	else:
		_apply_boon_to_player(String(picked["id"]))
		boons_taken.append(String(picked["name"]))

	boon_selection_active = false
	boon_choices.clear()
	boon_layer.visible = false
	reward_selection_mode = "boon"
	_set_combat_paused(false)

	if pending_initial_boon:
		pending_initial_boon = false
		_begin_room(_build_skirmish_profile(room_depth))
		return

	_spawn_door_options()

func _apply_boon_to_player(boon_id: String) -> void:
	if not is_instance_valid(player):
		return
	if player.has_method("apply_boon"):
		player.call("apply_boon", boon_id)

func _apply_hard_reward_to_player(reward_id: String) -> void:
	if not is_instance_valid(player):
		return
	if player.has_method("apply_hard_reward"):
		player.call("apply_hard_reward", reward_id)

func _get_boon_pool() -> Array[Dictionary]:
	return [
		{"id": "swift_strike", "name": "Swift Strike", "desc": "Attack cooldown reduced by 14%."},
		{"id": "heavy_blow", "name": "Heavy Blow", "desc": "Attack damage +8."},
		{"id": "wide_arc", "name": "Wide Arc", "desc": "Attack arc +18 degrees."},
		{"id": "long_reach", "name": "Long Reach", "desc": "Attack range +14."},
		{"id": "fleet_foot", "name": "Fleet Foot", "desc": "Move speed +18."},
		{"id": "blink_dash", "name": "Blink Dash", "desc": "Dash cooldown reduced by 15%."},
		{"id": "iron_skin", "name": "Iron Skin", "desc": "Max health +20 and heal +20."}
	]

func _roll_boon_choices(choice_count: int) -> Array[Dictionary]:
	var pool := _get_boon_pool()
	var available := pool.duplicate(true)
	var picks: Array[Dictionary] = []
	for _i in range(mini(choice_count, available.size())):
		var index := rng.randi_range(0, available.size() - 1)
		picks.append(available[index])
		available.remove_at(index)
	return picks

func _get_hard_reward_pool() -> Array[Dictionary]:
	var razor_desc := "Attacks launch a long-range piercing wind slash."
	var execution_desc := "Every 3rd swing is a huge execution strike."
	var rupture_desc := "Hits detonate a damaging shockwave."
	if is_instance_valid(player) and player.has_method("get_hard_reward_card_desc"):
		razor_desc = String(player.call("get_hard_reward_card_desc", "razor_wind"))
		execution_desc = String(player.call("get_hard_reward_card_desc", "execution_edge"))
		rupture_desc = String(player.call("get_hard_reward_card_desc", "rupture_wave"))
	return [
		{"id": "razor_wind", "name": "Razor Wind", "desc": razor_desc},
		{"id": "execution_edge", "name": "Execution Edge", "desc": execution_desc},
		{"id": "rupture_wave", "name": "Rupture Wave", "desc": rupture_desc}
	]

func _roll_hard_reward_choices(choice_count: int) -> Array[Dictionary]:
	var pool := _get_hard_reward_pool()
	var available := pool.duplicate(true)
	var picks: Array[Dictionary] = []
	for _i in range(mini(choice_count, available.size())):
		var index := rng.randi_range(0, available.size() - 1)
		picks.append(available[index])
		available.remove_at(index)
	return picks

func _refresh_boon_ui() -> void:
	if boon_layer == null:
		return
	boon_layer.visible = true
	boon_title_label.text = "%s  (Cards reveal in...)" % boon_title_text

	for i in range(boon_card_labels.size()):
		var panel := boon_card_panels[i]
		var label := boon_card_labels[i]
		if i >= boon_choices.size():
			label.text = ""
			panel.visible = false
			continue
		panel.visible = true
		var boon := boon_choices[i]
		if reward_selection_mode == "hard_reward":
			var reward_id := String(boon.get("id", ""))
			var stack_count := 0
			if is_instance_valid(player) and player.has_method("get_hard_reward_stack_count"):
				stack_count = int(player.call("get_hard_reward_stack_count", reward_id))
			var stack_icons := _format_stack_icons(stack_count)
			label.text = "%d. %s\nStacks: %s\n%s" % [i + 1, boon["name"], stack_icons, boon["desc"]]
		else:
			label.text = "%d. %s\n%s" % [i + 1, boon["name"], boon["desc"]]
		label.modulate = Color(0.82, 0.86, 0.94, 0.95)

	_update_boon_reveal_visuals()

func _format_stack_icons(stack_count: int) -> String:
	var visible_slots := 5
	var filled := mini(stack_count, visible_slots)
	var icons := ""
	for _i in range(filled):
		icons += "◆"
	for _i in range(visible_slots - filled):
		icons += "◇"
	if stack_count > visible_slots:
		icons += "+%d" % (stack_count - visible_slots)
	return icons

func _update_boon_hover() -> void:
	if boon_layer == null:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var hovered := -1
	for i in range(boon_choices.size()):
		if i >= boon_card_rects.size():
			continue
		if boon_card_rects[i].has_point(mouse_pos):
			hovered = i
			break

	if hovered == boon_hovered_index:
		return
	boon_hovered_index = hovered
	_apply_boon_card_styles(boon_hovered_index)

func _apply_boon_card_styles(hovered_index: int) -> void:
	for i in range(boon_card_panels.size()):
		var panel := boon_card_panels[i]
		var style := StyleBoxFlat.new()
		var t := float(i) / maxf(1.0, float(maxi(1, boon_choice_count - 1)))
		var cool := Color(0.08, 0.17, 0.28, 0.96).lerp(Color(0.12, 0.2, 0.34, 0.96), t)
		if i == hovered_index and boon_confirm_lock_time <= 0.0:
			style.bg_color = Color(0.22, 0.32, 0.46, 0.96)
			style.border_color = Color(0.98, 0.99, 1.0, 1.0)
			style.border_width_left = 4
			style.border_width_top = 4
			style.border_width_right = 4
			style.border_width_bottom = 4
		else:
			style.bg_color = cool
			style.border_color = Color(0.57, 0.71, 0.88, 0.86)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0.0, 4.0)
		panel.add_theme_stylebox_override("panel", style)

func _update_boon_reveal_visuals() -> void:
	var reveal_t := clampf(boon_reveal_time / maxf(0.001, boon_reveal_duration), 0.0, 1.0)
	for i in range(boon_card_panels.size()):
		if i >= boon_choices.size():
			continue
		var panel := boon_card_panels[i]
		var label := boon_card_labels[i]
		var delay := float(i) * 0.06
		var local_t := clampf((reveal_t - delay) / 0.6, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - local_t, 3.0)
		var base_pos := Vector2(220.0, 164.0 + i * 138.0)
		panel.position = base_pos + Vector2(0.0, (1.0 - eased) * 18.0)
		panel.modulate = Color(1.0, 1.0, 1.0, eased)
		panel.scale = Vector2(0.94 + 0.06 * eased, 0.94 + 0.06 * eased)
		label.modulate.a = eased

	if boon_confirm_lock_time <= 0.0:
		boon_title_label.text = "%s  (Click a card to choose)" % boon_title_text
	else:
		boon_title_label.text = "%s  (Get ready...)" % boon_title_text

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
		hud_label.text = "Run Clear  Boons: %d  Hard Rewards: %d" % [boons_taken.size(), hard_rewards_taken.size()]
		return

	if boon_selection_active:
		if boon_confirm_lock_time > 0.0:
			hud_label.text = "Boon Reward  Revealing cards..."
		else:
			hud_label.text = "Boon Choice  Click a card to pick 1 of %d" % boon_choice_count
		return

	if choosing_next_room:
		var prompt := "Choose Door [E]"
		if boss_unlocked:
			prompt = "Boss Gate Open [E]"
		hud_label.text = "%s  Rooms Cleared: %d/%d\nIcon Key: + = Easy Boon   >< = Hard Trial Reward   Cross = Rest   Crown = Boss   Boons: %d  Hard: %d" % [prompt, rooms_cleared, encounter_count, boons_taken.size(), hard_rewards_taken.size()]
		return

	var boss_text := "Unlocked" if boss_unlocked else "Locked"
	hud_label.text = "%s  Enemies Left: %d  Boss: %s  Boons: %d  Hard: %d" % [current_room_label, active_room_enemy_count, boss_text, boons_taken.size(), hard_rewards_taken.size()]

func _draw() -> void:
	if current_room_size == Vector2.ZERO:
		return
	var t := art_time
	var room_rect := Rect2(-current_room_size * 0.5, current_room_size)
	var pulse := 0.5 + 0.5 * sin(t * 0.9)
	draw_rect(room_rect.grow(240.0), Color(0.01, 0.02, 0.04, 0.98), true)

	# Layered floor wash to create depth without textures.
	for i in range(10):
		var ratio := float(i) / 9.0
		var inset := lerpf(0.0, minf(room_rect.size.x, room_rect.size.y) * 0.22, ratio)
		var layer_rect := room_rect.grow(-inset)
		var layer_color := Color(0.03, 0.08, 0.12, 0.22).lerp(Color(0.09, 0.16, 0.23, 0.12 + arena_glow_strength * pulse * 0.45), 1.0 - ratio)
		draw_rect(layer_rect, layer_color, true)

	var coarse_step := maxf(28.0, floor_grid_step)
	var fine_step := maxf(16.0, floor_grid_fine_step)
	for x in range(int(room_rect.position.x), int(room_rect.position.x + room_rect.size.x + coarse_step), int(coarse_step)):
		draw_line(Vector2(float(x), room_rect.position.y), Vector2(float(x), room_rect.position.y + room_rect.size.y), Color(0.36, 0.56, 0.78, 0.11), 2.0)
	for y in range(int(room_rect.position.y), int(room_rect.position.y + room_rect.size.y + coarse_step), int(coarse_step)):
		draw_line(Vector2(room_rect.position.x, float(y)), Vector2(room_rect.position.x + room_rect.size.x, float(y)), Color(0.36, 0.56, 0.78, 0.11), 2.0)

	for x in range(int(room_rect.position.x), int(room_rect.position.x + room_rect.size.x + fine_step), int(fine_step)):
		draw_line(Vector2(float(x), room_rect.position.y), Vector2(float(x), room_rect.position.y + room_rect.size.y), Color(0.55, 0.74, 0.92, 0.035), 1.0)
	for y in range(int(room_rect.position.y), int(room_rect.position.y + room_rect.size.y + fine_step), int(fine_step)):
		draw_line(Vector2(room_rect.position.x, float(y)), Vector2(room_rect.position.x + room_rect.size.x, float(y)), Color(0.55, 0.74, 0.92, 0.035), 1.0)

	var corners := [
		room_rect.position,
		room_rect.position + Vector2(room_rect.size.x, 0.0),
		room_rect.position + Vector2(0.0, room_rect.size.y),
		room_rect.position + room_rect.size
	]
	for corner in corners:
		draw_circle(corner, 32.0, Color(0.42, 0.74, 1.0, 0.05 + pulse * 0.02))

	draw_rect(room_rect, Color(0.56, 0.78, 0.95, 0.88), false, 4.0)
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
		draw_polyline(crown, outline_color, 4.0)
		draw_polyline(crown, icon_color, 2.0)
		return

	if icon == "hard":
		var left_a := door_pos + Vector2(-10.0, -8.0)
		var left_b := door_pos + Vector2(-3.0, 0.0)
		var left_c := door_pos + Vector2(-10.0, 8.0)
		var right_a := door_pos + Vector2(10.0, -8.0)
		var right_b := door_pos + Vector2(3.0, 0.0)
		var right_c := door_pos + Vector2(10.0, 8.0)
		draw_line(left_a, left_b, outline_color, 4.0)
		draw_line(left_b, left_c, outline_color, 4.0)
		draw_line(right_a, right_b, outline_color, 4.0)
		draw_line(right_b, right_c, outline_color, 4.0)
		draw_line(left_a, left_b, icon_color, 2.0)
		draw_line(left_b, left_c, icon_color, 2.0)
		draw_line(right_a, right_b, icon_color, 2.0)
		draw_line(right_b, right_c, icon_color, 2.0)
		return

	if icon == "rest":
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
	draw_line(h_l, h_r, outline_color, 4.0)
	draw_line(v_t, v_b, outline_color, 4.0)
	draw_line(h_l, h_r, icon_color, 2.0)
	draw_line(v_t, v_b, icon_color, 2.0)
