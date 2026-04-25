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
var boon_confirm_lock_time: float = 0.0
var boon_hovered_index: int = -1
var boon_reveal_time: float = 0.0

var current_room_size: Vector2 = Vector2.ZERO
var current_room_static_camera: bool = true
var current_room_label: String = ""
var door_options: Array[Dictionary] = []

var boon_layer: CanvasLayer
var boon_title_label: Label
var boon_card_panels: Array[Panel] = []
var boon_card_labels: Array[Label] = []
var boon_card_rects: Array[Rect2] = []

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
	_open_boon_selection("Choose Starting Boon", true)
	queue_redraw()

func _process(delta: float) -> void:
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

	rooms_cleared += 1
	room_depth += 1
	if rooms_cleared >= encounter_count:
		boss_unlocked = true
	_open_boon_selection("Choose Boon Reward", false)

func _spawn_door_options() -> void:
	door_options.clear()
	choosing_next_room = true

	var left_pos := Vector2(-door_distance_from_center, -40.0)
	var right_pos := Vector2(door_distance_from_center, -40.0)

	var skirmish := {
		"label": "Skirmish",
		"position": left_pos,
		"color": Color(0.34, 0.78, 1.0, 0.95),
		"kind": "encounter",
		"profile": _build_skirmish_profile(room_depth)
	}
	var onslaught := {
		"label": "Onslaught",
		"position": right_pos,
		"color": Color(1.0, 0.5, 0.26, 0.95),
		"kind": "encounter",
		"profile": _build_onslaught_profile(room_depth)
	}
	door_options.append(skirmish)

	if boss_unlocked:
		var boss_door := {
			"label": "Boss",
			"position": right_pos,
			"color": Color(0.95, 0.18, 0.22, 0.98),
			"kind": "boss",
			"profile": {}
		}
		door_options.append(boss_door)
	else:
		door_options.append(onslaught)

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

	var profile: Dictionary = door["profile"]
	_begin_room(profile)

func _begin_room(profile: Dictionary) -> void:
	if profile.is_empty():
		return
	in_boss_room = false
	current_room_size = profile["room_size"]
	current_room_static_camera = profile["static_camera"]
	current_room_label = profile["label"]
	_apply_camera_bounds_for_room(current_room_size)
	active_room_enemy_count = _spawn_profile_enemies(profile)

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

	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = CircleShape2D.new()
	collision_shape.shape.radius = 13.0
	enemy.add_child(collision_shape)

	enemy.global_position = _pick_spawn_position_in_current_room()
	add_child(enemy)
	enemy.set("target", player)
	if enemy.has_signal("died"):
		enemy.died.connect(_on_room_enemy_died)

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

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)

	hud_label = Label.new()
	hud_label.position = Vector2(16.0, 12.0)
	hud_label.add_theme_font_size_override("font_size", 20)
	layer.add_child(hud_label)
	_update_hud()

func _create_boon_ui() -> void:
	boon_layer = CanvasLayer.new()
	boon_layer.layer = 130
	add_child(boon_layer)

	boon_title_label = Label.new()
	boon_title_label.position = Vector2(430.0, 80.0)
	boon_title_label.add_theme_font_size_override("font_size", 32)
	boon_layer.add_child(boon_title_label)

	boon_card_panels.clear()
	boon_card_labels.clear()
	boon_card_rects.clear()
	for i in range(boon_choice_count):
		var panel := Panel.new()
		panel.position = Vector2(140.0, 160.0 + i * 130.0)
		panel.custom_minimum_size = Vector2(980.0, 112.0)
		boon_layer.add_child(panel)

		var option_label := Label.new()
		option_label.position = Vector2(18.0, 14.0)
		option_label.add_theme_font_size_override("font_size", 22)
		panel.add_child(option_label)

		boon_card_panels.append(panel)
		boon_card_labels.append(option_label)
		boon_card_rects.append(Rect2(panel.position, panel.custom_minimum_size))

	boon_layer.visible = false

func _open_boon_selection(title: String, is_initial: bool) -> void:
	boon_selection_active = true
	pending_initial_boon = is_initial
	boon_title_text = title
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
	_apply_boon_to_player(String(picked["id"]))
	boons_taken.append(String(picked["name"]))

	boon_selection_active = false
	boon_choices.clear()
	boon_layer.visible = false
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
		label.text = "%d. %s\n%s" % [i + 1, boon["name"], boon["desc"]]
		label.modulate = Color(0.82, 0.86, 0.94, 0.95)

	_update_boon_reveal_visuals()

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
		if i == hovered_index and boon_confirm_lock_time <= 0.0:
			style.bg_color = Color(0.18, 0.24, 0.34, 0.95)
			style.border_color = Color(0.92, 0.97, 1.0, 0.95)
			style.border_width_left = 4
			style.border_width_top = 4
			style.border_width_right = 4
			style.border_width_bottom = 4
		else:
			style.bg_color = Color(0.09, 0.12, 0.17, 0.92)
			style.border_color = Color(0.45, 0.55, 0.68, 0.88)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
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
		hud_label.text = "Run Clear  Boons: %d" % boons_taken.size()
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
			prompt = "Choose Door [E]  (Boss Available)"
		hud_label.text = "%s  Rooms Cleared: %d/%d\nIcon Key: + = Skirmish   >< = Onslaught   Crown = Boss   Boons: %d" % [prompt, rooms_cleared, encounter_count, boons_taken.size()]
		return

	var boss_text := "Unlocked" if boss_unlocked else "Locked"
	hud_label.text = "%s  Enemies Left: %d  Boss: %s  Boons: %d" % [current_room_label, active_room_enemy_count, boss_text, boons_taken.size()]

func _draw() -> void:
	if current_room_size == Vector2.ZERO:
		return
	var room_rect := Rect2(-current_room_size * 0.5, current_room_size)
	draw_rect(room_rect, Color(0.03, 0.05, 0.07, 0.16), true)
	draw_rect(room_rect, Color(0.34, 0.47, 0.58, 0.85), false, 4.0)

	if choosing_next_room:
		for door in door_options:
			var door_pos: Vector2 = door["position"]
			var color: Color = door["color"]
			draw_circle(door_pos, 26.0, Color(color.r, color.g, color.b, 0.22))
			draw_circle(door_pos, 14.0, color)
			_draw_door_icon(door)

func _draw_door_icon(door: Dictionary) -> void:
	var door_pos: Vector2 = door["position"]
	var icon_color := Color(0.97, 0.98, 1.0, 0.96)
	var outline_color := Color(0.08, 0.1, 0.14, 0.88)
	var kind := String(door["kind"])
	var label := String(door["label"])

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

	if label == "Onslaught":
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

	var h_l := door_pos + Vector2(-8.0, 0.0)
	var h_r := door_pos + Vector2(8.0, 0.0)
	var v_t := door_pos + Vector2(0.0, -8.0)
	var v_b := door_pos + Vector2(0.0, 8.0)
	draw_line(h_l, h_r, outline_color, 4.0)
	draw_line(v_t, v_b, outline_color, 4.0)
	draw_line(h_l, h_r, icon_color, 2.0)
	draw_line(v_t, v_b, icon_color, 2.0)
