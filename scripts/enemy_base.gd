extends CharacterBody2D

const HEALTH_STATE_SCRIPT := preload("res://scripts/health_state.gd")
const COLOR_PALETTE := preload("res://scripts/shared/color_palette.gd")

signal health_changed(current_health: int, max_health: int)
signal died

static var _shared_enemy_nodes_cache: Array[Node2D] = []
static var _shared_enemy_count: int = 0
static var _shared_enemy_cache_physics_frame: int = -1

# === SHARED COLOR PALETTE ===
const COLOR_HEALTH_BAR_BG := COLOR_PALETTE.COLOR_HEALTH_BAR_BG
const COLOR_ENEMY_HEALTH_FILL := COLOR_PALETTE.COLOR_ENEMY_HEALTH_FILL
const COLOR_PLAYER_HEALTH_FILL := COLOR_PALETTE.COLOR_PLAYER_HEALTH_FILL
const COLOR_BODY_OUTER_GLOW := COLOR_PALETTE.COLOR_BODY_OUTER_GLOW
const COLOR_BODY_HORN := COLOR_PALETTE.COLOR_BODY_HORN
const COLOR_BODY_EYE := COLOR_PALETTE.COLOR_BODY_EYE
const COLOR_BODY_SPIKE := COLOR_PALETTE.COLOR_BODY_SPIKE
const COLOR_PLAYER_GLOW := COLOR_PALETTE.COLOR_PLAYER_GLOW
const COLOR_PLAYER_OUTER := COLOR_PALETTE.COLOR_PLAYER_OUTER
const COLOR_PLAYER_BODY := COLOR_PALETTE.COLOR_PLAYER_BODY
const COLOR_PLAYER_CORE := COLOR_PALETTE.COLOR_PLAYER_CORE
const COLOR_PLAYER_LIGHT := COLOR_PALETTE.COLOR_PLAYER_LIGHT
const COLOR_PLAYER_POINTER := COLOR_PALETTE.COLOR_PLAYER_POINTER
const COLOR_PLAYER_EYE := COLOR_PALETTE.COLOR_PLAYER_EYE
const COLOR_PLAYER_WING := COLOR_PALETTE.COLOR_PLAYER_WING
const COLOR_PLAYER_SPEED_ARC := COLOR_PALETTE.COLOR_PLAYER_SPEED_ARC
const COLOR_PLAYER_DASH_PHASE := COLOR_PALETTE.COLOR_PLAYER_DASH_PHASE
const COLOR_PLAYER_DASH_STREAK := COLOR_PALETTE.COLOR_PLAYER_DASH_STREAK
const COLOR_SWING_DEFAULT := COLOR_PALETTE.COLOR_SWING_DEFAULT
const COLOR_SWING_RAZOR_WIND := COLOR_PALETTE.COLOR_SWING_RAZOR_WIND
const COLOR_SWING_RAZOR_WIND_EXTENDED := COLOR_PALETTE.COLOR_SWING_RAZOR_WIND_EXTENDED
const COLOR_EXECUTION_RING := COLOR_PALETTE.COLOR_EXECUTION_RING
const COLOR_EXECUTION_PROC := COLOR_PALETTE.COLOR_EXECUTION_PROC
const COLOR_EXECUTION_PROC_EXTENDED := COLOR_PALETTE.COLOR_EXECUTION_PROC_EXTENDED
const COLOR_EXECUTION_PIP_LIT := COLOR_PALETTE.COLOR_EXECUTION_PIP_LIT
const COLOR_EXECUTION_PIP_DARK := COLOR_PALETTE.COLOR_EXECUTION_PIP_DARK
const COLOR_EXECUTION_WIND_EXTENDED := COLOR_PALETTE.COLOR_EXECUTION_WIND_EXTENDED
const COLOR_RUPTURE_WAVE_RING := COLOR_PALETTE.COLOR_RUPTURE_WAVE_RING
const COLOR_RUPTURE_WAVE_AURA := COLOR_PALETTE.COLOR_RUPTURE_WAVE_AURA
const COLOR_RAZOR_WIND_TRIANGLE := COLOR_PALETTE.COLOR_RAZOR_WIND_TRIANGLE
const COLOR_RAZOR_WIND_LINE := COLOR_PALETTE.COLOR_RAZOR_WIND_LINE
const COLOR_DAMAGE_FLASH := COLOR_PALETTE.COLOR_DAMAGE_FLASH
const COLOR_CHASER_BODY := COLOR_PALETTE.COLOR_CHASER_BODY
const COLOR_CHASER_CORE := COLOR_PALETTE.COLOR_CHASER_CORE
const COLOR_CHARGER_BODY := COLOR_PALETTE.COLOR_CHARGER_BODY
const COLOR_CHARGER_CORE := COLOR_PALETTE.COLOR_CHARGER_CORE
const COLOR_CHARGER_CORE_CHARGED := COLOR_PALETTE.COLOR_CHARGER_CORE_CHARGED
const COLOR_ARCHER_BODY := COLOR_PALETTE.COLOR_ARCHER_BODY
const COLOR_ARCHER_CORE := COLOR_PALETTE.COLOR_ARCHER_CORE
const COLOR_ARCHER_AIM := COLOR_PALETTE.COLOR_ARCHER_AIM
const COLOR_ARCHER_AIM_BRACKET := COLOR_PALETTE.COLOR_ARCHER_AIM_BRACKET
const COLOR_ARCHER_PROJECTILE := COLOR_PALETTE.COLOR_ARCHER_PROJECTILE
const COLOR_SHIELDER_BODY := COLOR_PALETTE.COLOR_SHIELDER_BODY
const COLOR_SHIELDER_CORE := COLOR_PALETTE.COLOR_SHIELDER_CORE
const COLOR_SHIELDER_BODY_WINDUP := COLOR_PALETTE.COLOR_SHIELDER_BODY_WINDUP
const COLOR_SHIELDER_BODY_THUMP := COLOR_PALETTE.COLOR_SHIELDER_BODY_THUMP
const COLOR_SHIELDER_CORE_THUMP := COLOR_PALETTE.COLOR_SHIELDER_CORE_THUMP
const COLOR_SHIELDER_SHIELD := COLOR_PALETTE.COLOR_SHIELDER_SHIELD
const COLOR_SHIELDER_SHIELD_OUTLINE := COLOR_PALETTE.COLOR_SHIELDER_SHIELD_OUTLINE
const COLOR_SHIELDER_SLAM_WARNING_GLOW := COLOR_PALETTE.COLOR_SHIELDER_SLAM_WARNING_GLOW
const COLOR_SHIELDER_SLAM_WARNING_RING := COLOR_PALETTE.COLOR_SHIELDER_SLAM_WARNING_RING
const COLOR_SHIELDER_SLAM_SHOCK_GLOW := COLOR_PALETTE.COLOR_SHIELDER_SLAM_SHOCK_GLOW
const COLOR_SHIELDER_SLAM_SHOCK_RING := COLOR_PALETTE.COLOR_SHIELDER_SLAM_SHOCK_RING
const COLOR_BOSS_BODY := COLOR_PALETTE.COLOR_BOSS_BODY
const COLOR_BOSS_BODY_TELEGRAPH := COLOR_PALETTE.COLOR_BOSS_BODY_TELEGRAPH
const COLOR_BOSS_BODY_ATTACK := COLOR_PALETTE.COLOR_BOSS_BODY_ATTACK
const COLOR_BOSS_CORE := COLOR_PALETTE.COLOR_BOSS_CORE
const COLOR_BOSS_CORE_TELEGRAPH := COLOR_PALETTE.COLOR_BOSS_CORE_TELEGRAPH
const COLOR_BOSS_CORE_ATTACK := COLOR_PALETTE.COLOR_BOSS_CORE_ATTACK
const COLOR_BOSS_GLOW := COLOR_PALETTE.COLOR_BOSS_GLOW
const COLOR_BOSS_CHARGE_LINE := COLOR_PALETTE.COLOR_BOSS_CHARGE_LINE
const COLOR_BOSS_CHARGE_LINE_INNER := COLOR_PALETTE.COLOR_BOSS_CHARGE_LINE_INNER
const COLOR_BOSS_NOVA_GLOW := COLOR_PALETTE.COLOR_BOSS_NOVA_GLOW
const COLOR_BOSS_NOVA_RING := COLOR_PALETTE.COLOR_BOSS_NOVA_RING
const COLOR_BOSS_CLEAVE_FILL := COLOR_PALETTE.COLOR_BOSS_CLEAVE_FILL
const COLOR_BOSS_CLEAVE_OUTLINE := COLOR_PALETTE.COLOR_BOSS_CLEAVE_OUTLINE

@export var max_health: int = 40
@export var health_bar_size: Vector2 = Vector2(56.0, 8.0)
@export var health_bar_offset: Vector2 = Vector2(-28.0, -34.0)
@export var health_recent_damage_burst_window: float = 0.28
@export var health_recent_damage_hold_time: float = 0.6
@export var health_recent_damage_catchup_ratio_per_sec: float = 0.9
@export var crowd_separation_radius: float = 42.0
@export var crowd_separation_strength: float = 68.0
@export var crowd_separation_recompute_interval_sec: float = 0.08
@export var edge_escape_phase_duration: float = 0.32
@export var edge_escape_nudge_speed: float = 340.0
@export var network_runtime_direction_blend: float = 0.58
@export var network_remote_direction_lerp_speed: float = 14.0
@export var target_refresh_interval_sec: float = 0.12
@export var attack_visual_redraw_interval_sec: float = 0.033
@export var remote_ui_update_interval_sec: float = 0.08
@export var visual_lod_enemy_threshold: int = 28
@export var visual_lod_refresh_interval_sec: float = 0.2
@export var remote_visual_update_interval_sec: float = 0.033

var target: Node2D
var target_candidates: Array = []
var health_bar: ProgressBar
var health_bar_recent_damage_overlay: Panel
var health_bar_threshold_overlay: Control
var health_bar_threshold_markers: Array[ColorRect] = []
var health_recent_damage_display_health: float = 0.0
var health_recent_damage_hold_left: float = 0.0
var health_recent_damage_time_since_last_hit: float = 999.0
var health_recent_damage_flash_strength: float = 0.0
var health_recent_damage_burst_active: bool = false
var health_state
var attack_anim_time_left: float = 0.0
var attack_anim_duration: float = 0.1
var visual_facing_direction: Vector2 = Vector2.LEFT
var _network_target_facing: Vector2 = Vector2.LEFT
var _network_facing_lerp_speed: float = 12.0
var _network_direction_targets: Dictionary = {}
var slow_time_left: float = 0.0
var slow_speed_mult: float = 1.0
var has_mutator_overlay: bool = false
var mutator_theme_color: Color = Color(1.0, 0.4, 0.4, 1.0)
var mutator_icon_shape_id: String = ""
var damage_blocked: bool = false
var dread_resonance_visual_stacks: int = 0
var dread_resonance_visual_max_stacks: int = 3
var dread_resonance_visual_hold_left: float = 0.0
var dread_resonance_visual_hold_duration: float = 0.22
var dread_resonance_visual_decay_left: float = 0.0
var dread_resonance_visual_decay_duration: float = 0.42
var dread_resonance_visual_peak_left: float = 0.0
var dread_resonance_visual_peak_duration: float = 0.14
var dread_resonance_visual_boss_emphasis: bool = false
var spawn_transport_time_left: float = 0.0
var spawn_transport_duration: float = 0.0
var spawn_transport_seed: float = 0.0
var _edge_escape_phase_left: float = 0.0
var _ignoring_target_collision: bool = false
var _target_refresh_left: float = 0.0
var _attack_visual_redraw_left: float = 0.0
var _remote_ui_update_left: float = 0.0
var _remote_ui_update_accum: float = 0.0
var _crowd_separation_recompute_left: float = 0.0
var _crowd_separation_cached_impulse: Vector2 = Vector2.ZERO
var network_simulation_enabled: bool = true
var _draw_time_sec: float = 0.0
var _visual_lod_enemy_count: int = 0
var _visual_lod_refresh_left: float = 0.0
var _remote_visual_update_left: float = 0.0
var _remote_visual_update_accum: float = 0.0

const NETWORK_ATTACK_STATE_KEYWORDS: PackedStringArray = [
	"state",
	"cooldown",
	"attack",
	"windup",
	"recover",
	"slam",
	"beam",
	"shield",
	"telegraph",
	"charge",
	"time_left",
	"direction",
	"facing"
]
const NETWORK_ATTACK_STATE_EXCLUDED: Dictionary = {
	"target": true,
	"target_candidates": true,
	"health_bar": true,
	"health_bar_recent_damage_overlay": true,
	"health_bar_threshold_overlay": true,
	"health_bar_threshold_markers": true,
	"health_state": true,
	"projectiles": true,
	"projectile_directions": true
}

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	_crowd_separation_recompute_left = fmod(float(get_instance_id()) * 0.0017, maxf(0.001, crowd_separation_recompute_interval_sec))
	_target_refresh_left = fmod(float(get_instance_id()) * 0.0011, maxf(0.02, target_refresh_interval_sec))
	_remote_ui_update_left = fmod(float(get_instance_id()) * 0.0019, maxf(0.02, remote_ui_update_interval_sec))
	_visual_lod_refresh_left = fmod(float(get_instance_id()) * 0.0013, maxf(0.05, visual_lod_refresh_interval_sec))
	_remote_visual_update_left = fmod(float(get_instance_id()) * 0.0015, maxf(0.016, remote_visual_update_interval_sec))
	add_to_group("enemies")
	_visual_lod_enemy_count = _get_shared_enemy_count()
	health_changed.connect(_update_health_bar)
	_create_health_bar()
	_create_health_state()
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.visible = false
	queue_redraw()

func _physics_process(delta: float) -> void:
	_refresh_visual_lod_metrics(delta)
	_update_attack_animation(delta)
	if network_simulation_enabled:
		_update_recent_damage_overlay(delta)
		_update_dread_resonance_visual(delta)
	else:
		var remote_ui_interval := _get_remote_ui_update_interval_for_enemy_load()
		_remote_ui_update_accum += delta
		_remote_ui_update_left -= delta
		if _remote_ui_update_left <= 0.0:
			var ui_delta := _remote_ui_update_accum
			_remote_ui_update_accum = 0.0
			_remote_ui_update_left = remote_ui_interval
			_update_recent_damage_overlay(ui_delta)
			_update_dread_resonance_visual(ui_delta)
	_update_spawn_transport(delta)
	if is_spawn_transporting():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if not network_simulation_enabled:
		velocity = Vector2.ZERO
		_update_network_direction_targets(delta)
		_update_network_facing_lerp(delta)
		if should_process_remote_visuals_every_frame():
			_remote_visual_update_accum = 0.0
			_remote_visual_update_left = _get_remote_visual_update_interval_for_enemy_load()
			_process_network_visuals(delta)
		else:
			var remote_visual_interval := _get_remote_visual_update_interval_for_enemy_load()
			_remote_visual_update_accum += delta
			_remote_visual_update_left -= delta
			if _remote_visual_update_left <= 0.0:
				var visual_delta := _remote_visual_update_accum
				_remote_visual_update_accum = 0.0
				_remote_visual_update_left = remote_visual_interval
				_process_network_visuals(visual_delta)
		return
	_maybe_refresh_target(delta)
	_apply_crowd_separation(delta)
	_process_behavior(delta)
	_update_visual_facing_direction()

func _refresh_visual_lod_metrics(delta: float) -> void:
	_visual_lod_refresh_left -= delta
	if _visual_lod_refresh_left > 0.0:
		return
	_visual_lod_refresh_left = maxf(0.05, visual_lod_refresh_interval_sec)
	_visual_lod_enemy_count = _get_shared_enemy_count()

func _refresh_shared_enemy_cache() -> void:
	var tree := get_tree()
	if tree == null:
		_shared_enemy_nodes_cache.clear()
		_shared_enemy_count = 0
		_shared_enemy_cache_physics_frame = -1
		return
	var physics_frame := Engine.get_physics_frames()
	if _shared_enemy_cache_physics_frame == physics_frame:
		return
	var raw_nodes := tree.get_nodes_in_group("enemies")
	var cached_nodes: Array[Node2D] = []
	for node_variant in raw_nodes:
		if node_variant is Node2D:
			cached_nodes.append(node_variant as Node2D)
	_shared_enemy_nodes_cache = cached_nodes
	_shared_enemy_count = cached_nodes.size()
	_shared_enemy_cache_physics_frame = physics_frame

func _get_shared_enemy_nodes_cache() -> Array[Node2D]:
	_refresh_shared_enemy_cache()
	return _shared_enemy_nodes_cache

func _get_shared_enemy_count() -> int:
	_refresh_shared_enemy_cache()
	return _shared_enemy_count

func _is_high_load_visual_lod_active() -> bool:
	return _visual_lod_enemy_count >= maxi(1, visual_lod_enemy_threshold)

func _get_facing_redraw_threshold_sq() -> float:
	if _is_high_load_visual_lod_active():
		return 0.0012
	return 0.0001

func _get_remote_ui_update_interval_for_enemy_load() -> float:
	var interval := maxf(0.02, remote_ui_update_interval_sec)
	var enemy_count := _visual_lod_enemy_count
	if enemy_count >= 40:
		return maxf(interval, 0.13)
	if enemy_count >= 30:
		return maxf(interval, 0.11)
	if enemy_count >= 20:
		return maxf(interval, 0.095)
	return interval

func _get_remote_visual_update_interval_for_enemy_load() -> float:
	var interval := maxf(0.016, remote_visual_update_interval_sec)
	var enemy_count := _visual_lod_enemy_count
	if enemy_count >= 40:
		return maxf(interval, 0.066)
	if enemy_count >= 30:
		return maxf(interval, 0.05)
	if enemy_count >= 20:
		return maxf(interval, 0.04)
	return interval


func set_target_candidates(candidates: Array) -> void:
	target_candidates.clear()
	for candidate in candidates:
		if candidate is Node2D:
			target_candidates.append(candidate)
	_refresh_target()


func _refresh_target() -> void:
	var best_target: Node2D = null
	var best_dist_sq := INF
	if target_candidates.is_empty():
		if _is_target_valid(target):
			return
		_set_target_node(null)
		return
	for candidate_variant in target_candidates:
		if not (candidate_variant is Node2D):
			continue
		var candidate := candidate_variant as Node2D
		if not _is_target_valid(candidate):
			continue
		var dist_sq := global_position.distance_squared_to(candidate.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_target = candidate
	if best_target == null and _is_target_valid(target):
		best_target = target
	_set_target_node(best_target)

func _maybe_refresh_target(delta: float) -> void:
	if target_candidates.is_empty():
		if _is_target_valid(target):
			return
		_set_target_node(null)
		return
	_target_refresh_left -= delta
	if _target_refresh_left > 0.0 and _is_target_valid(target):
		return
	_target_refresh_left = maxf(0.02, target_refresh_interval_sec)
	_refresh_target()


func _is_target_valid(candidate: Node2D) -> bool:
	if not is_instance_valid(candidate):
		return false
	if candidate.has_method("is_dead") and bool(candidate.call("is_dead")):
		return false
	return true


func _set_target_node(next_target: Node2D) -> void:
	if target == next_target:
		return
	if _ignoring_target_collision:
		_set_target_collision_ignored(false)
	target = next_target


func set_network_simulation_enabled(enabled: bool) -> void:
	network_simulation_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
		_network_target_facing = visual_facing_direction.normalized() if visual_facing_direction.length_squared() > 0.000001 else Vector2.LEFT
		_network_direction_targets.clear()
	else:
		_network_direction_targets.clear()


func get_network_runtime_state() -> Dictionary:
	var runtime_state := {
		"attack_anim_time_left": attack_anim_time_left,
		"attack_anim_duration": attack_anim_duration,
		"visual_facing_direction": visual_facing_direction,
		"slow_time_left": slow_time_left,
		"slow_speed_mult": slow_speed_mult,
		"spawn_transport_time_left": spawn_transport_time_left,
		"spawn_transport_duration": spawn_transport_duration,
		"spawn_transport_seed": spawn_transport_seed,
		"damage_blocked": damage_blocked,
		"custom": _get_custom_network_runtime_state()
	}
	return runtime_state


func apply_network_runtime_state(runtime_state: Dictionary) -> void:
	if runtime_state.is_empty():
		return
	if runtime_state.has("attack_anim_time_left"):
		attack_anim_time_left = float(runtime_state.get("attack_anim_time_left", attack_anim_time_left))
	if runtime_state.has("attack_anim_duration"):
		attack_anim_duration = float(runtime_state.get("attack_anim_duration", attack_anim_duration))
	if runtime_state.has("visual_facing_direction"):
		var incoming_facing := runtime_state.get("visual_facing_direction", visual_facing_direction) as Vector2
		if network_simulation_enabled:
			visual_facing_direction = incoming_facing
		else:
			_set_remote_direction_target("visual_facing_direction", incoming_facing)
	if runtime_state.has("slow_time_left"):
		slow_time_left = float(runtime_state.get("slow_time_left", slow_time_left))
	if runtime_state.has("slow_speed_mult"):
		slow_speed_mult = float(runtime_state.get("slow_speed_mult", slow_speed_mult))
	if runtime_state.has("spawn_transport_time_left"):
		spawn_transport_time_left = float(runtime_state.get("spawn_transport_time_left", spawn_transport_time_left))
	if runtime_state.has("spawn_transport_duration"):
		spawn_transport_duration = float(runtime_state.get("spawn_transport_duration", spawn_transport_duration))
	if runtime_state.has("spawn_transport_seed"):
		spawn_transport_seed = float(runtime_state.get("spawn_transport_seed", spawn_transport_seed))
	if runtime_state.has("damage_blocked"):
		damage_blocked = bool(runtime_state.get("damage_blocked", damage_blocked))
	var custom_state := runtime_state.get("custom", {}) as Dictionary
	_apply_custom_network_runtime_state(custom_state)
	queue_redraw()


func _get_custom_network_runtime_state() -> Dictionary:
	return _collect_attack_network_state()


func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	if custom_state.is_empty():
		return
	for key_variant in custom_state.keys():
		var property_name := String(key_variant)
		if NETWORK_ATTACK_STATE_EXCLUDED.has(property_name):
			continue
		if not _has_script_property(property_name):
			continue
		var value: Variant = custom_state.get(property_name)
		if _is_serializable_network_value(value):
			if typeof(value) == TYPE_VECTOR2 and _is_directional_property_name(property_name):
				if not network_simulation_enabled:
					_set_remote_direction_target(property_name, value as Vector2)
					continue
				var current_value: Variant = get(property_name)
				if typeof(current_value) == TYPE_VECTOR2:
					var current_direction := current_value as Vector2
					var target_direction := value as Vector2
					if current_direction.length_squared() > 0.000001 and target_direction.length_squared() > 0.000001:
						var blend_weight := clampf(network_runtime_direction_blend, 0.0, 1.0)
						var blended_direction := current_direction.slerp(target_direction.normalized() * target_direction.length(), blend_weight)
						set(property_name, blended_direction)
						continue
			set(property_name, value)


func _collect_attack_network_state() -> Dictionary:
	var state: Dictionary = {}
	for property_variant in get_property_list():
		if not (property_variant is Dictionary):
			continue
		var property := property_variant as Dictionary
		var usage := int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var property_name := String(property.get("name", ""))
		if property_name.is_empty():
			continue
		if NETWORK_ATTACK_STATE_EXCLUDED.has(property_name):
			continue
		if not _is_attack_state_property_name(property_name):
			continue
		var value: Variant = get(property_name)
		if _is_serializable_network_value(value):
			state[property_name] = value
	return state


func _has_script_property(property_name: String) -> bool:
	for property_variant in get_property_list():
		if not (property_variant is Dictionary):
			continue
		var property := property_variant as Dictionary
		if String(property.get("name", "")) != property_name:
			continue
		var usage := int(property.get("usage", 0))
		return (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
	return false


func _is_attack_state_property_name(property_name: String) -> bool:
	var lowered := property_name.to_lower()
	for keyword in NETWORK_ATTACK_STATE_KEYWORDS:
		if lowered.findn(String(keyword)) >= 0:
			return true
	return false


func _is_directional_property_name(property_name: String) -> bool:
	var lowered := property_name.to_lower()
	return lowered.findn("facing") >= 0 or lowered.findn("direction") >= 0


func _is_serializable_network_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_COLOR:
			return true
		TYPE_ARRAY:
			for item in value:
				if not _is_serializable_network_value(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key_variant in value.keys():
				if not _is_serializable_network_value(value.get(key_variant)):
					return false
			return true
		_:
			return false


func get_network_facing_angle() -> float:
	var facing := visual_facing_direction
	if facing.length_squared() <= 0.000001:
		facing = Vector2.LEFT
	return facing.angle()


func _set_remote_direction_target(property_name: String, target_direction: Vector2) -> void:
	if target_direction.length_squared() <= 0.000001:
		return
	var normalized_target := target_direction.normalized() * target_direction.length()
	if property_name == "visual_facing_direction":
		_network_target_facing = normalized_target.normalized()
		if visual_facing_direction.length_squared() <= 0.000001:
			visual_facing_direction = _network_target_facing
		return
	_network_direction_targets[property_name] = normalized_target
	var current_value: Variant = get(property_name)
	if typeof(current_value) == TYPE_VECTOR2:
		var current_direction := current_value as Vector2
		if current_direction.length_squared() <= 0.000001:
			set(property_name, normalized_target)
			queue_redraw()


func _update_network_direction_targets(delta: float) -> void:
	if _network_direction_targets.is_empty():
		return
	var redraw_threshold_sq := _get_facing_redraw_threshold_sq()
	var blend_weight := clampf(delta * maxf(0.001, network_remote_direction_lerp_speed), 0.0, 1.0)
	for property_variant in _network_direction_targets.keys():
		var property_name := String(property_variant)
		if not _has_script_property(property_name):
			continue
		var target_direction := _network_direction_targets.get(property_name, Vector2.ZERO) as Vector2
		if target_direction.length_squared() <= 0.000001:
			continue
		var current_value: Variant = get(property_name)
		if typeof(current_value) != TYPE_VECTOR2:
			continue
		var current_direction := current_value as Vector2
		var next_direction := target_direction
		if current_direction.length_squared() > 0.000001:
			var blended_direction := current_direction.slerp(target_direction, blend_weight)
			if blended_direction.length_squared() > 0.000001:
				next_direction = blended_direction.normalized() * target_direction.length()
		if next_direction.distance_squared_to(current_direction) > redraw_threshold_sq:
			set(property_name, next_direction)
			queue_redraw()


func _update_network_facing_lerp(delta: float) -> void:
	if _network_target_facing.length_squared() <= 0.000001:
		return
	var previous_facing := visual_facing_direction
	var distance_to_target_sq := visual_facing_direction.distance_squared_to(_network_target_facing)
	if distance_to_target_sq <= 0.000001:
		return
	var lerp_amount := minf(1.0, _network_facing_lerp_speed * delta)
	visual_facing_direction = visual_facing_direction.slerp(_network_target_facing, lerp_amount).normalized()
	var redraw_threshold_sq := _get_facing_redraw_threshold_sq()
	if visual_facing_direction.distance_squared_to(previous_facing) > redraw_threshold_sq:
		queue_redraw()


func set_network_facing_angle(facing_radians: float) -> void:
	var target_facing := Vector2.RIGHT.rotated(facing_radians)
	if target_facing.length_squared() <= 0.000001:
		return
	# Store target; joiner will lerp toward it smoothly using _update_network_facing_lerp
	_network_target_facing = target_facing.normalized()
	# Initialize current facing if unset
	if visual_facing_direction.length_squared() <= 0.000001:
		visual_facing_direction = _network_target_facing

func _update_spawn_transport(delta: float) -> void:
	if spawn_transport_time_left <= 0.0:
		return
	spawn_transport_time_left = maxf(0.0, spawn_transport_time_left - delta)
	queue_redraw()

func begin_spawn_transport(duration: float = 0.3) -> void:
	spawn_transport_duration = clampf(duration, 0.16, 1.4)
	spawn_transport_time_left = spawn_transport_duration
	spawn_transport_seed = rng_seed_from_instance()
	velocity = Vector2.ZERO
	queue_redraw()

func is_spawn_transporting() -> bool:
	return spawn_transport_time_left > 0.0

func rng_seed_from_instance() -> float:
	return float(int(get_instance_id()) % 10000) * 0.0137

func _process_behavior(_delta: float) -> void:
	pass

func _process_network_visuals(_delta: float) -> void:
	pass

func should_process_remote_visuals_every_frame() -> bool:
	return false

func get_priority_network_sync_interval_sec() -> float:
	return 0.0

func _get_inward_edge_bias() -> Vector2:
	return Vector2.ZERO

func _update_attack_animation(delta: float) -> void:
	var attack_visual_active := false
	if attack_anim_time_left > 0.0:
		attack_anim_time_left = maxf(0.0, attack_anim_time_left - delta)
		attack_visual_active = true
	if slow_time_left > 0.0:
		slow_time_left -= delta
		if slow_time_left <= 0.0:
			slow_time_left = 0.0
			slow_speed_mult = 1.0
	if attack_visual_active:
		_attack_visual_redraw_left -= delta
		if _attack_visual_redraw_left <= 0.0:
			_attack_visual_redraw_left = maxf(0.01, attack_visual_redraw_interval_sec)
			queue_redraw()
	else:
		_attack_visual_redraw_left = 0.0

func _update_visual_facing_direction() -> void:
	var previous_facing := visual_facing_direction
	if velocity.length_squared() > 1.0:
		var move_facing := velocity.normalized()
		var blended_facing := visual_facing_direction.slerp(move_facing, 0.28)
		if blended_facing.length_squared() > 0.000001:
			visual_facing_direction = blended_facing.normalized()
		else:
			visual_facing_direction = move_facing
	var redraw_threshold_sq := _get_facing_redraw_threshold_sq()
	if previous_facing.length_squared() <= 0.000001 or visual_facing_direction.distance_squared_to(previous_facing) > redraw_threshold_sq:
		queue_redraw()

func take_damage(amount: int, _damage_context: Dictionary = {}) -> void:
	if amount <= 0:
		return
	if damage_blocked:
		return
	health_state.take_damage(amount)

func _apply_crowd_separation(delta: float) -> void:
	if crowd_separation_radius <= 0.0 or crowd_separation_strength <= 0.0:
		_crowd_separation_cached_impulse = Vector2.ZERO
		_crowd_separation_recompute_left = 0.0
		return
	var recompute_interval := maxf(0.0, crowd_separation_recompute_interval_sec)
	if recompute_interval <= 0.0:
		_crowd_separation_cached_impulse = _compute_crowd_separation_impulse()
	else:
		_crowd_separation_recompute_left -= delta
		if _crowd_separation_recompute_left <= 0.0:
			var neighbors := _get_shared_enemy_nodes_cache()
			var neighbor_count := neighbors.size()
			var effective_recompute_interval := recompute_interval
			if neighbor_count >= 36:
				effective_recompute_interval *= 2.0
			elif neighbor_count >= 24:
				effective_recompute_interval *= 1.5
			_crowd_separation_recompute_left = effective_recompute_interval
			_crowd_separation_cached_impulse = _compute_crowd_separation_impulse(neighbors)
	if _crowd_separation_cached_impulse.length_squared() <= 0.000001:
		return
	velocity = velocity.move_toward(velocity + _crowd_separation_cached_impulse, crowd_separation_strength * delta)

func _compute_crowd_separation_impulse(neighbors: Array = []) -> Vector2:
	var total_push := Vector2.ZERO
	if neighbors.is_empty():
		neighbors = _get_shared_enemy_nodes_cache()
	var radius_sq := crowd_separation_radius * crowd_separation_radius
	var max_neighbors := 14
	if neighbors.size() >= 36:
		max_neighbors = 8
	elif neighbors.size() >= 24:
		max_neighbors = 10
	var sampled_neighbors := 0
	for enemy in neighbors:
		if enemy == self or not (enemy is Node2D):
			continue
		var neighbor := enemy as Node2D
		var offset := global_position - neighbor.global_position
		# Fast AABB reject before sqrt.
		if absf(offset.x) >= crowd_separation_radius or absf(offset.y) >= crowd_separation_radius:
			continue
		var dist_sq := offset.length_squared()
		if dist_sq <= 0.0001:
			offset = Vector2.RIGHT.rotated(float(get_instance_id() % 360) * 0.0174533)
			dist_sq = 1.0
		if dist_sq >= radius_sq:
			continue
		var distance := sqrt(dist_sq)
		var weight := 1.0 - (distance / crowd_separation_radius)
		total_push += (offset / distance) * weight
		sampled_neighbors += 1
		if sampled_neighbors >= max_neighbors:
			break
	if total_push.length_squared() <= 0.000001:
		return Vector2.ZERO
	return total_push.normalized() * crowd_separation_strength

func _maybe_trigger_edge_escape(wall_pressure: float, inward_bias: Vector2, to_target: Vector2, edge_stall_time: float) -> void:
	if edge_escape_phase_duration <= 0.0 or edge_escape_nudge_speed <= 0.0:
		return
	if wall_pressure <= 0.42:
		return
	var target_blocks_inward := false
	if to_target.length_squared() > 0.000001 and inward_bias.length_squared() > 0.000001:
		target_blocks_inward = inward_bias.dot(to_target.normalized()) > 0.18
	if edge_stall_time >= 0.1 or (target_blocks_inward and wall_pressure >= 0.48):
		_edge_escape_phase_left = maxf(_edge_escape_phase_left, edge_escape_phase_duration)

func _update_edge_escape_state(delta: float) -> void:
	if edge_escape_phase_duration <= 0.0 or edge_escape_nudge_speed <= 0.0:
		_set_target_collision_ignored(false)
		_edge_escape_phase_left = 0.0
		return
	if _edge_escape_phase_left > 0.0:
		_edge_escape_phase_left = maxf(0.0, _edge_escape_phase_left - delta)
	if _edge_escape_phase_left <= 0.0:
		_set_target_collision_ignored(false)
		return
	_set_target_collision_ignored(true)
	var inward := _get_inward_edge_bias()
	if inward.length_squared() <= 0.000001:
		return
	global_position += inward * edge_escape_nudge_speed * delta

func _clear_edge_escape_state() -> void:
	_edge_escape_phase_left = 0.0
	_set_target_collision_ignored(false)

func _set_target_collision_ignored(should_ignore: bool) -> void:
	if should_ignore == _ignoring_target_collision:
		return
	if not is_instance_valid(target) or not (target is PhysicsBody2D):
		_ignoring_target_collision = false
		return
	var target_body := target as PhysicsBody2D
	if should_ignore:
		add_collision_exception_with(target_body)
	else:
		remove_collision_exception_with(target_body)
	_ignoring_target_collision = should_ignore

func apply_slow(duration: float, mult: float) -> void:
	if duration > slow_time_left:
		slow_time_left = duration
	if mult < slow_speed_mult:
		slow_speed_mult = mult

func is_slowed() -> bool:
	return slow_time_left > 0.0

func _draw_slow_indicator(body_radius: float) -> void:
	if slow_time_left <= 0.0:
		return
	var t := _draw_time_sec if _draw_time_sec > 0.0 else float(Time.get_ticks_msec()) * 0.001
	var pulse := 0.5 + 0.5 * sin(t * 11.0)
	var fade := clampf(slow_time_left * 4.0, 0.0, 1.0)
	draw_circle(Vector2.ZERO, body_radius + 8.0, Color(0.46, 1.0, 0.92, 0.07 * fade))
	var slow_segments := 32 if network_simulation_enabled else 24
	draw_arc(Vector2.ZERO, body_radius + 7.0, 0.0, TAU, slow_segments,
		Color(0.46, 1.0, 0.92, (0.52 + pulse * 0.28) * fade), 2.6)

func heal(amount: int) -> void:
	if amount <= 0:
		return
	health_state.heal(amount)

func set_health(value: float) -> void:
	if not is_instance_valid(health_state):
		return
	health_state.set_health(int(round(value)))

func get_current_health() -> int:
	return _get_current_health()

func get_max_health() -> int:
	return max_health

func set_max_health_and_current(new_max_health: int, new_current_health: int = -1) -> void:
	max_health = maxi(1, new_max_health)
	if not is_instance_valid(health_state):
		return
	if new_current_health < 0:
		health_state.setup(max_health)
		return
	health_state.setup(max_health, new_current_health)

func is_dead() -> bool:
	return health_state.is_dead()

func _create_health_bar() -> void:
	health_bar = ProgressBar.new()
	health_bar.min_value = 0.0
	health_bar.max_value = float(max_health)
	health_bar.value = float(_get_current_health())
	health_bar.show_percentage = false
	health_bar.position = health_bar_offset
	health_bar.custom_minimum_size = health_bar_size
	health_bar.size = health_bar_size
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.clip_contents = true

	var background_style := StyleBoxFlat.new()
	background_style.bg_color = COLOR_HEALTH_BAR_BG
	background_style.corner_radius_top_left = 3
	background_style.corner_radius_top_right = 3
	background_style.corner_radius_bottom_left = 3
	background_style.corner_radius_bottom_right = 3
	background_style.border_width_left = 1
	background_style.border_width_top = 1
	background_style.border_width_right = 1
	background_style.border_width_bottom = 1
	background_style.border_color = Color(0.88, 0.92, 1.0, 0.78)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = COLOR_ENEMY_HEALTH_FILL
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3

	health_bar.add_theme_stylebox_override("background", background_style)
	health_bar.add_theme_stylebox_override("fill", fill_style)
	health_bar_recent_damage_overlay = Panel.new()
	health_bar_recent_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var recent_damage_style := StyleBoxFlat.new()
	recent_damage_style.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	recent_damage_style.corner_radius_top_left = 0
	recent_damage_style.corner_radius_top_right = 3
	recent_damage_style.corner_radius_bottom_left = 0
	recent_damage_style.corner_radius_bottom_right = 3
	health_bar_recent_damage_overlay.add_theme_stylebox_override("panel", recent_damage_style)
	health_bar_recent_damage_overlay.visible = false
	health_bar.add_child(health_bar_recent_damage_overlay)
	health_bar_threshold_overlay = Control.new()
	health_bar_threshold_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	health_bar_threshold_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.add_child(health_bar_threshold_overlay)
	add_child(health_bar)
	health_recent_damage_display_health = float(_get_current_health())
	health_recent_damage_hold_left = 0.0
	health_recent_damage_time_since_last_hit = health_recent_damage_hold_time + 1.0
	health_recent_damage_flash_strength = 0.0
	health_recent_damage_burst_active = false
	_update_recent_damage_overlay_layout()
	_update_health_bar_threshold_layout()

func _update_health_bar(new_health: int, new_max_health: int) -> void:
	if health_bar == null:
		return
	var previous_health := float(health_bar.value)
	health_bar.max_value = float(new_max_health)
	health_bar.value = float(new_health)

	if float(new_health) < previous_health:
		var lost_ratio := (previous_health - float(new_health)) / maxf(1.0, float(new_max_health))
		var continuing_stack := health_recent_damage_burst_active

		if not continuing_stack:
			health_recent_damage_display_health = previous_health
		else:
			health_recent_damage_display_health = maxf(health_recent_damage_display_health, previous_health)
		health_recent_damage_burst_active = true

		health_recent_damage_time_since_last_hit = 0.0
		health_recent_damage_hold_left = health_recent_damage_hold_time
		health_recent_damage_flash_strength = clampf(health_recent_damage_flash_strength + 0.34 + lost_ratio * 2.1, 0.0, 1.0)
	else:
		health_recent_damage_display_health = float(new_health)
		health_recent_damage_hold_left = 0.0
		health_recent_damage_time_since_last_hit = health_recent_damage_hold_time + 1.0
		health_recent_damage_flash_strength = 0.0
		health_recent_damage_burst_active = false

	_update_recent_damage_overlay_layout()
	_update_health_bar_threshold_layout()

func configure_health_bar_visuals(offset: Vector2, size: Vector2 = Vector2.ZERO) -> void:
	health_bar_offset = offset
	if size != Vector2.ZERO:
		health_bar_size = size
	if health_bar == null:
		return
	health_bar.position = health_bar_offset
	health_bar.custom_minimum_size = health_bar_size
	health_bar.size = health_bar_size
	_update_recent_damage_overlay_layout()
	_update_health_bar_threshold_layout()

func _update_recent_damage_overlay(delta: float) -> void:
	if health_bar == null:
		return
	if health_bar_recent_damage_overlay == null:
		return
	var current_health := float(health_bar.value)
	if health_recent_damage_time_since_last_hit > health_recent_damage_hold_time \
		and not health_recent_damage_burst_active \
		and health_recent_damage_flash_strength <= 0.0001 \
		and absf(health_recent_damage_display_health - current_health) <= 0.001:
		if health_bar_recent_damage_overlay.visible:
			health_bar_recent_damage_overlay.visible = false
		return
	var max_health_value := maxf(1.0, float(health_bar.max_value))
	health_recent_damage_time_since_last_hit += delta

	if health_recent_damage_time_since_last_hit <= health_recent_damage_hold_time:
		health_recent_damage_hold_left = health_recent_damage_hold_time - health_recent_damage_time_since_last_hit
	else:
		health_recent_damage_hold_left = 0.0
		var old_display := health_recent_damage_display_health
		var catchup := max_health_value * maxf(0.1, health_recent_damage_catchup_ratio_per_sec) * delta
		health_recent_damage_display_health = maxf(current_health, health_recent_damage_display_health - catchup)
		if health_recent_damage_burst_active and old_display > current_health and health_recent_damage_display_health <= current_health + 0.001:
			health_recent_damage_display_health = current_health
			health_recent_damage_burst_active = false

	health_recent_damage_flash_strength = maxf(0.0, health_recent_damage_flash_strength - delta * 1.9)
	_update_recent_damage_overlay_layout()

func _update_recent_damage_overlay_layout() -> void:
	if health_bar == null:
		return
	if health_bar_recent_damage_overlay == null:
		return
	var max_health_value := maxf(1.0, float(health_bar.max_value))
	var current_ratio := clampf(float(health_bar.value) / max_health_value, 0.0, 1.0)
	var recent_ratio := clampf(health_recent_damage_display_health / max_health_value, 0.0, 1.0)
	var recent_width_ratio := maxf(0.0, recent_ratio - current_ratio)

	if recent_width_ratio <= 0.001:
		health_bar_recent_damage_overlay.visible = false
		return

	var bar_w := maxf(1.0, health_bar_size.x)
	var bar_h := maxf(1.0, health_bar_size.y)
	health_bar_recent_damage_overlay.visible = true
	health_bar_recent_damage_overlay.position = Vector2(bar_w * current_ratio, 0.0)
	var overlay_size := Vector2(maxf(1.0, bar_w * recent_width_ratio), bar_h)
	health_bar_recent_damage_overlay.custom_minimum_size = overlay_size
	health_bar_recent_damage_overlay.size = overlay_size

	var pulse := 1.0
	if health_recent_damage_hold_left > 0.0:
		pulse = 0.78 + 0.22 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.028))
	var alpha := clampf((0.18 + health_recent_damage_flash_strength * 0.56) * pulse, 0.08, 0.92)
	var panel_style := health_bar_recent_damage_overlay.get_theme_stylebox("panel") as StyleBoxFlat
	if panel_style != null:
		panel_style.bg_color = Color(1.0, 1.0, 1.0, alpha)

func set_health_threshold_markers(thresholds: Array, used_count: int = 0) -> void:
	if health_bar_threshold_overlay == null:
		return
	for marker in health_bar_threshold_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	health_bar_threshold_markers.clear()
	for index in range(thresholds.size()):
		var marker := ColorRect.new()
		marker.custom_minimum_size = Vector2(2.0, maxf(health_bar_size.y + 2.0, 10.0))
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		health_bar_threshold_overlay.add_child(marker)
		health_bar_threshold_markers.append(marker)
	set_health_threshold_marker_progress(used_count)
	_update_health_bar_threshold_layout()

func set_health_threshold_marker_progress(used_count: int) -> void:
	for index in range(health_bar_threshold_markers.size()):
		var marker := health_bar_threshold_markers[index]
		if not is_instance_valid(marker):
			continue
		if index < used_count:
			marker.color = Color(0.42, 0.48, 0.56, 0.95)
		else:
			marker.color = Color(1.0, 0.84, 0.3, 0.98)

func _update_health_bar_threshold_layout() -> void:
	if health_bar == null or health_bar_threshold_overlay == null:
		return
	if health_bar_threshold_markers.is_empty():
		return
	var marker_count := health_bar_threshold_markers.size()
	for index in range(marker_count):
		var marker := health_bar_threshold_markers[index]
		if not is_instance_valid(marker):
			continue
		var threshold_ratio := 1.0 - (float(index + 1) / float(marker_count + 1))
		var x := health_bar_size.x * threshold_ratio - 1.0
		marker.position = Vector2(x, -1.0)

func _create_health_state() -> void:
	health_state = HEALTH_STATE_SCRIPT.new()
	health_state.health_changed.connect(_on_health_state_changed)
	health_state.died.connect(_on_health_state_died)
	add_child(health_state)
	health_state.setup(max_health)

func _on_health_state_changed(new_health: int, new_max_health: int) -> void:
	health_changed.emit(new_health, new_max_health)

func _on_health_state_died() -> void:
	died.emit()
	queue_free()

func _get_current_health() -> int:
	if health_state == null:
		return max_health
	return health_state.current_health

func _draw_common_body(body_radius: float, body_color: Color, core_color: Color, facing: Vector2) -> void:
	_draw_time_sec = float(Time.get_ticks_msec()) * 0.001
	if is_spawn_transporting():
		_draw_spawn_transport_fx(body_radius, facing)
		return
	var side := Vector2(-facing.y, facing.x)
	var outer_color := COLOR_BODY_OUTER_GLOW
	if _is_high_load_visual_lod_active():
		draw_circle(Vector2.ZERO, body_radius + 3.6, outer_color)
		draw_circle(Vector2.ZERO, body_radius, body_color)
		draw_circle(Vector2.ZERO, body_radius * 0.68, core_color)
		var lod_horn_tip := facing * (body_radius + 6.6)
		var lod_horn_base := facing * (body_radius - 1.2)
		var lod_horn_w := 3.8
		var lod_horn := PackedVector2Array([lod_horn_tip, lod_horn_base + side * lod_horn_w, lod_horn_base - side * lod_horn_w])
		draw_colored_polygon(lod_horn, COLOR_BODY_HORN)
		var lod_eye := facing * (body_radius * 0.32) + side * 1.6
		draw_circle(lod_eye, 1.5, COLOR_BODY_EYE)
		_draw_mutator_overlay(body_radius)
		_draw_dread_resonance_overlay(body_radius)
		_draw_damage_blocked_indicator(body_radius)
		return
	
	draw_circle(Vector2.ZERO, body_radius + 6.2, Color(body_color.r * 0.6, body_color.g * 0.3, body_color.b * 0.3, 0.14))
	draw_circle(Vector2.ZERO, body_radius + 3.0, outer_color)
	draw_circle(Vector2.ZERO, body_radius, body_color)
	draw_circle(Vector2.ZERO, body_radius * 0.72, core_color)
	draw_circle(Vector2.ZERO, body_radius * 0.38, Color(1.0, 0.9, 0.88, 0.2))

	var horn_tip := facing * (body_radius + 8.0)
	var horn_base := facing * (body_radius - 2.0)
	var horn_w := 4.6
	var horn := PackedVector2Array([horn_tip, horn_base + side * horn_w, horn_base - side * horn_w])
	draw_colored_polygon(horn, COLOR_BODY_HORN)

	var eye := facing * (body_radius * 0.34) + side * 2.0
	draw_circle(eye, 1.8, COLOR_BODY_EYE)

	var spike_l := side * (body_radius - 1.0)
	var spike_r := -side * (body_radius - 1.0)
	draw_line(spike_l, spike_l + side * 6.0, COLOR_BODY_SPIKE, 1.8)
	draw_line(spike_r, spike_r - side * 6.0, COLOR_BODY_SPIKE, 1.8)
	_draw_mutator_overlay(body_radius)
	_draw_dread_resonance_overlay(body_radius)
	_draw_damage_blocked_indicator(body_radius)

func _get_transport_color() -> Color:
	return Color(0.56, 0.94, 1.0, 1.0)

func _draw_spawn_transport_fx(body_radius: float, _facing: Vector2) -> void:
	var duration := maxf(0.001, spawn_transport_duration)
	var t := 1.0 - clampf(spawn_transport_time_left / duration, 0.0, 1.0)
	var transport_seed := spawn_transport_seed
	var tint := _get_transport_color()
	var ring_segments := 48 if network_simulation_enabled else 32

	# Soft outer glow — tinted, atmospheric, bell-curves through the full animation
	var glow_a := sin(clampf(t / 0.88, 0.0, 1.0) * PI) * 0.32
	if glow_a > 0.01:
		draw_circle(Vector2.ZERO, body_radius + 26.0,
				Color(tint.r * 0.52, tint.g * 0.68, tint.b, glow_a))

	# Pillar (t 0→0.50) — drops from above; wide tinted glow + sharp white spine
	var pillar_t := clampf(t / 0.50, 0.0, 1.0)
	var pillar_a := sin(pillar_t * PI)
	if pillar_a > 0.02:
		var ph := 200.0 - pillar_t * 130.0
		draw_line(Vector2(0.0, -ph), Vector2(0.0, body_radius),
				Color(tint.r * 0.62, tint.g * 0.80, tint.b, pillar_a * 0.18), 52.0)
		draw_line(Vector2(0.0, -ph), Vector2(0.0, body_radius),
				Color(1.0, 1.0, 1.0, pillar_a * 0.94), 4.0)

	# Body ring (t 0.26→0.88) — one ring, glow halo + sharp white core
	var ring_t := clampf((t - 0.26) / 0.62, 0.0, 1.0)
	if ring_t > 0.0:
		var ring_a := sin(ring_t * PI)
		draw_arc(Vector2.ZERO, body_radius + 3.0, 0.0, TAU, ring_segments,
				Color(tint.r * 0.68, tint.g * 0.84, tint.b, ring_a * 0.38), 11.0)
		draw_arc(Vector2.ZERO, body_radius + 3.0, 0.0, TAU, ring_segments,
				Color(1.0, 1.0, 1.0, ring_a * 0.86), 2.0)

	# 4 radial streaks (t 0.30→0.80) — directed outward, not orbiting
	var streak_t := clampf((t - 0.30) / 0.50, 0.0, 1.0)
	if streak_t > 0.0 and streak_t < 1.0:
		var streak_a := sin(streak_t * PI)
		for i in range(4):
			var ang := transport_seed + TAU * float(i) / 4.0
			var dir := Vector2.RIGHT.rotated(ang)
			var inner := dir * body_radius * 0.85
			var outer := dir * (body_radius + 5.0 + streak_t * body_radius * 2.4)
			draw_line(inner, outer,
					Color(tint.r * 0.78, tint.g * 0.88, tint.b, streak_a * 0.26), 8.0)
			draw_line(inner, outer,
					Color(1.0, 0.96, 0.90, streak_a * 0.88), 2.0)
			draw_circle(outer, 3.2, Color(1.0, 0.98, 0.92, streak_a * 0.80))

	# Materialize bridge (t 0.72→1.0) — smooth handoff into normal body draw
	var reveal_t := clampf((t - 0.72) / 0.28, 0.0, 1.0)
	if reveal_t > 0.0:
		var reveal_a := reveal_t * reveal_t
		draw_circle(Vector2.ZERO, body_radius + 5.0,
				Color(tint.r * 0.42, tint.g * 0.56, tint.b * 0.98, reveal_a * 0.18))
		draw_circle(Vector2.ZERO, body_radius,
				Color(tint.r * 0.78, tint.g * 0.90, tint.b, reveal_a * 0.52))
		draw_circle(Vector2.ZERO, body_radius * 0.66,
				Color(1.0, 1.0, 1.0, reveal_a * 0.16))

	# Arrival flash (t 0.86→1.0) — fast pop, linear decay, gets out of the way
	var flash_t := clampf((t - 0.86) / 0.14, 0.0, 1.0)
	if flash_t > 0.0:
		var flash_a := 1.0 - flash_t
		draw_circle(Vector2.ZERO, body_radius * (1.0 + flash_t * 0.65),
				Color(lerpf(1.0, tint.r, 0.28), lerpf(0.94, tint.g, 0.20), lerpf(0.88, tint.b, 0.16),
				flash_a * 0.70))
		draw_circle(Vector2.ZERO, body_radius * 0.62,
				Color(1.0, 1.0, 1.0, flash_a * 0.94))

func _draw_mutator_overlay(body_radius: float) -> void:
	if not has_mutator_overlay:
		return
	var t := _draw_time_sec if _draw_time_sec > 0.0 else float(Time.get_ticks_msec()) * 0.001
	var pulse := 0.5 + 0.5 * sin(t * 3.4)
	var ring_segments := 48 if network_simulation_enabled else 32
	var default_segments := 32 if network_simulation_enabled else 24
	var ring_color := mutator_theme_color
	var fill_color := mutator_theme_color
	if mutator_icon_shape_id == "tether_web":
		var web_fill := fill_color
		web_fill.a = 0.10 + pulse * 0.07
		draw_circle(Vector2.ZERO, body_radius + 13.0, web_fill)
		var web_ring := ring_color
		web_ring.a = 0.62 + pulse * 0.28
		draw_arc(Vector2.ZERO, body_radius + 11.0, 0.0, TAU, ring_segments, web_ring, 2.8)
		for i in range(4):
			var angle := t * 0.85 + float(i) * TAU / 4.0
			var dir := Vector2(cos(angle), sin(angle))
			var spoke_color := mutator_theme_color
			spoke_color.a = 0.55 + pulse * 0.3
			draw_line(Vector2.ZERO, dir * (body_radius + 14.0), spoke_color, 1.8)
		return
	ring_color.a = 0.44 + pulse * 0.22
	draw_arc(Vector2.ZERO, body_radius + 9.0, 0.0, TAU, default_segments, ring_color, 2.2)
	fill_color.a = 0.06 + pulse * 0.04
	draw_circle(Vector2.ZERO, body_radius + 8.0, fill_color)

func _draw_damage_blocked_indicator(body_radius: float) -> void:
	if not damage_blocked:
		return
	var t := _draw_time_sec if _draw_time_sec > 0.0 else float(Time.get_ticks_msec()) * 0.001
	var pulse := 0.5 + 0.5 * sin(t * 9.0)
	var ring_segments := 40 if network_simulation_enabled else 28
	var ring_color := Color(0.7, 0.94, 1.0, 0.56 + pulse * 0.2)
	draw_arc(Vector2.ZERO, body_radius + 13.0, 0.0, TAU, ring_segments, ring_color, 2.6)
	draw_circle(Vector2.ZERO, body_radius + 11.2, Color(0.64, 0.9, 1.0, 0.05 + pulse * 0.03))

func set_dread_resonance_visual(stack_count: int, max_stacks: int = 3, peak_flash: bool = false) -> void:
	var clamped_max := maxi(1, max_stacks)
	var clamped_stack := clampi(stack_count, 1, clamped_max)
	dread_resonance_visual_max_stacks = clamped_max
	dread_resonance_visual_stacks = clamped_stack
	dread_resonance_visual_hold_left = dread_resonance_visual_hold_duration
	dread_resonance_visual_decay_left = dread_resonance_visual_decay_duration
	if peak_flash:
		dread_resonance_visual_peak_left = dread_resonance_visual_peak_duration
	queue_redraw()

func clear_dread_resonance_visual() -> void:
	if dread_resonance_visual_stacks <= 0 and dread_resonance_visual_peak_left <= 0.0:
		return
	dread_resonance_visual_stacks = 0
	dread_resonance_visual_hold_left = 0.0
	dread_resonance_visual_decay_left = 0.0
	dread_resonance_visual_peak_left = 0.0
	queue_redraw()

func _update_dread_resonance_visual(delta: float) -> void:
	if dread_resonance_visual_stacks <= 0 and dread_resonance_visual_peak_left <= 0.0:
		return
	var had_visual := dread_resonance_visual_stacks > 0 or dread_resonance_visual_peak_left > 0.0
	if dread_resonance_visual_hold_left > 0.0:
		dread_resonance_visual_hold_left = maxf(0.0, dread_resonance_visual_hold_left - delta)
	else:
		dread_resonance_visual_decay_left = maxf(0.0, dread_resonance_visual_decay_left - delta)
	if dread_resonance_visual_peak_left > 0.0:
		dread_resonance_visual_peak_left = maxf(0.0, dread_resonance_visual_peak_left - delta)
	if dread_resonance_visual_decay_left <= 0.0 and dread_resonance_visual_peak_left <= 0.0:
		dread_resonance_visual_stacks = 0
		dread_resonance_visual_hold_left = 0.0
	var has_visual := dread_resonance_visual_stacks > 0 or dread_resonance_visual_peak_left > 0.0
	if had_visual or has_visual:
		queue_redraw()

func _draw_dread_resonance_overlay(body_radius: float) -> void:
	if dread_resonance_visual_stacks <= 0:
		return
	var max_stacks := maxi(1, dread_resonance_visual_max_stacks)
	var stack_ratio := clampf(float(dread_resonance_visual_stacks) / float(max_stacks), 0.0, 1.0)
	var fade := 1.0
	if dread_resonance_visual_hold_left <= 0.0:
		fade = clampf(dread_resonance_visual_decay_left / maxf(0.001, dread_resonance_visual_decay_duration), 0.0, 1.0)
	if fade <= 0.0:
		return
	var t := _draw_time_sec if _draw_time_sec > 0.0 else float(Time.get_ticks_msec()) * 0.001
	var pulse := 0.5 + 0.5 * sin(t * 6.2)
	var main_arc_segments := 24 if network_simulation_enabled else 18
	var emphasis_arc_segments := 36 if network_simulation_enabled else 26
	var emphasis := 1.4 if dread_resonance_visual_boss_emphasis else 1.0
	var ring_color := Color(0.92, 0.76, 1.0, (0.24 + pulse * 0.06) * fade * emphasis)
	var aura_color := Color(0.6, 0.36, 0.94, (0.04 + pulse * 0.03) * fade * emphasis)
	var arc_radius := body_radius + 10.0
	var arc_width := (1.6 + stack_ratio * 0.9) * emphasis
	draw_circle(Vector2.ZERO, body_radius + 8.0, aura_color)
	var arc_start := -PI * 0.5
	var arc_end := arc_start + TAU * stack_ratio
	draw_arc(Vector2.ZERO, arc_radius, arc_start, arc_end, main_arc_segments, ring_color, arc_width)
	if dread_resonance_visual_boss_emphasis:
		draw_arc(Vector2.ZERO, arc_radius + 3.0, 0.0, TAU, emphasis_arc_segments, Color(0.76, 0.48, 0.98, (0.12 + pulse * 0.05) * fade), 1.2)
	if dread_resonance_visual_peak_left > 0.0:
		var peak_t := clampf(dread_resonance_visual_peak_left / maxf(0.001, dread_resonance_visual_peak_duration), 0.0, 1.0)
		var burst_radius := arc_radius + (1.0 - peak_t) * 10.0
		draw_arc(Vector2.ZERO, burst_radius, 0.0, TAU, emphasis_arc_segments, Color(1.0, 0.92, 1.0, 0.5 * peak_t * fade), 2.0)

func _get_attack_pulse() -> float:
	var attack_t := 1.0 - (attack_anim_time_left / attack_anim_duration) if attack_anim_duration > 0.0 else 1.0
	return sin(attack_t * PI) * 1.8 if attack_anim_time_left > 0.0 else 0.0
