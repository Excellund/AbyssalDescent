## Centralized objective state holder
## Replaces scattered objective_* fields from world_generator
## Objective-runtime reads from this, world_generator syncs for UI
extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

# ============================================================================
# OBJECTIVE KIND & ROLE
# ============================================================================

var active_objective_kind: String = ""  # "last_stand", "cut_the_signal", "hold_the_line", ""

# ============================================================================
# SHARED OBJECTIVE STATE
# ============================================================================

var time_left: float = 0.0
var spawn_interval: float = 0.0
var spawn_timer: float = 0.0
var spawn_batch: int = 1
var max_enemies: int = 0
var overtime: bool = false

# ============================================================================
# HUNT_TARGET OBJECTIVE STATE (cut_the_signal)
# ============================================================================

var hunt_target_enemy: CharacterBody2D = null
var hunt_target_type: String = ""
var hunt_target_name: String = ""
var hunt_target_kill_progress: int = 0
var hunt_target_kill_goal: int = 4
var hunt_target_dash_line: Line2D = null
var hunt_target_dash_line_time_left: float = 0.0
var hunt_target_flee_thresholds: Array[float] = [0.75, 0.5, 0.25]
var hunt_target_next_flee_index: int = 0

# ============================================================================
# SURVIVAL OBJECTIVE STATE (last_stand)
# ============================================================================

var survival_quota_announced: bool = false
var kill_target: int = 0
var kills: int = 0

# ============================================================================
# CONTROL OBJECTIVE STATE (hold_the_line)
# ============================================================================

var control_anchor: Vector2 = Vector2.ZERO
var control_radius: float = 0.0
var control_progress: float = 0.0
var control_goal: float = 0.0
var control_decay_rate: float = 0.0
var control_contest_threshold: int = 0
var control_enemies_in_zone: int = 0
var control_player_inside: bool = false
var control_contested: bool = false
var control_kill_baseline: int = 0
var control_unbroken: bool = false
var engagement_kill_progress_bonus: float = 0.4
var engagement_bonus_radius_scale: float = 1.18

# ============================================================================
# EXPOSURE STATE (cut_the_signal specific)
# ============================================================================

var exposure_duration: float = 2.0
var exposure_left: float = 0.0
var exposure_push_duration: float = 1.2
var exposure_push_left: float = 0.0
var exposure_push_strength: float = 380.0
var exposure_push_radius: float = 252.0
var exposure_push_accel: float = 940.0

# ============================================================================
# RELOCATION STATE (cut_the_signal specific)
# ============================================================================

var relocation_escort_radius: float = 236.0
var relocation_escort_cap: int = 3
var relocation_escort_dash_lines: Array[Line2D] = []
var relocation_escort_dash_line_time_left: float = 0.0
var last_relocated_escort_count: int = 0
var relocation_hint_left: float = 0.0

# ============================================================================
# SIGNAL FX STATE (cut_the_signal specific)
# ============================================================================

var signal_fx_node: Node2D = null
var signal_fx_left: float = 0.0
var signal_fx_duration: float = 0.0
var signal_fx_strength: float = 1.0
var signal_fx_phase: float = 0.0

# ============================================================================
# CIRCUIT SWEEP STATE
# ============================================================================

var sweep_node_count: int = 3
var sweep_nodes_completed: int = 0
var sweep_capture_progress: float = 0.0
var sweep_capture_goal: float = 2.0
var sweep_node_position: Vector2 = Vector2.ZERO
var sweep_node_radius: float = 88.0

# ============================================================================
# PULSE WINDOW STATE
# ============================================================================

var pulse_next_timer: float = 9.0
var pulse_interval: float = 9.0
var pulse_active: bool = false
var pulse_active_timer: float = 0.0
var pulse_mode: String = ""
var pulse_active_mutator: Dictionary = {}
var pulse_ring_time_left: float = 0.0
var pulse_ring_duration: float = 0.65
var pulse_ring_color: Color = Color.WHITE
var pulse_count: int = 0

# ============================================================================
# INTERCEPT RUN STATE
# ============================================================================

var intercept_drone_progress: float = 0.0
var intercept_drone_position: Vector2 = Vector2.ZERO
var intercept_start: Vector2 = Vector2.ZERO
var intercept_end: Vector2 = Vector2.ZERO
var intercept_drone_speed: float = 0.025
var intercept_enemies_near_drone: int = 0
var intercept_drone_stalled: bool = false
var intercept_drone_radius: float = 80.0
var intercept_escort_radius: float = 240.0
var intercept_player_in_escort_zone: bool = true


## Reset all state to defaults (call when entering a room without objectives)
func reset() -> void:
	active_objective_kind = ""
	time_left = 0.0
	spawn_interval = 0.0
	spawn_timer = 0.0
	spawn_batch = 1
	max_enemies = 0
	overtime = false

	# Hunt target
	hunt_target_enemy = null
	hunt_target_type = ""
	hunt_target_name = ""
	hunt_target_kill_progress = 0
	hunt_target_kill_goal = 4
	if is_instance_valid(hunt_target_dash_line):
		hunt_target_dash_line.queue_free()
	hunt_target_dash_line = null
	hunt_target_dash_line_time_left = 0.0
	hunt_target_flee_thresholds = [0.75, 0.5, 0.25]
	hunt_target_next_flee_index = 0

	# Survival
	survival_quota_announced = false
	kill_target = 0
	kills = 0

	# Control
	control_anchor = Vector2.ZERO
	control_radius = 0.0
	control_progress = 0.0
	control_goal = 0.0
	control_decay_rate = 0.0
	control_contest_threshold = 0
	control_enemies_in_zone = 0
	control_player_inside = false
	control_contested = false
	control_kill_baseline = 0
	control_unbroken = false

	# Exposure
	exposure_duration = 2.0
	exposure_left = 0.0
	exposure_push_duration = 1.2
	exposure_push_left = 0.0
	exposure_push_strength = 380.0
	exposure_push_radius = 252.0
	exposure_push_accel = 940.0

	# Relocation
	for escort_line in relocation_escort_dash_lines:
		if is_instance_valid(escort_line):
			escort_line.queue_free()
	relocation_escort_dash_lines.clear()
	relocation_escort_dash_line_time_left = 0.0
	last_relocated_escort_count = 0
	relocation_hint_left = 0.0

	# Signal FX
	if is_instance_valid(signal_fx_node):
		signal_fx_node.queue_free()
	signal_fx_node = null
	signal_fx_left = 0.0
	signal_fx_duration = 0.0
	signal_fx_strength = 1.0
	signal_fx_phase = 0.0

	# Circuit Sweep
	sweep_node_count = 3
	sweep_nodes_completed = 0
	sweep_capture_progress = 0.0
	sweep_capture_goal = 2.0
	sweep_node_position = Vector2.ZERO
	sweep_node_radius = 88.0

	# Pulse Window
	pulse_next_timer = 9.0
	pulse_interval = 9.0
	pulse_active = false
	pulse_active_timer = 0.0
	pulse_mode = ""
	pulse_active_mutator = {}
	pulse_ring_time_left = 0.0
	pulse_ring_color = Color.WHITE
	pulse_count = 0

	# Intercept Run
	intercept_drone_progress = 0.0
	intercept_drone_position = Vector2.ZERO
	intercept_start = Vector2.ZERO
	intercept_end = Vector2.ZERO
	intercept_drone_speed = 0.025
	intercept_enemies_near_drone = 0
	intercept_drone_stalled = false
	intercept_drone_radius = 80.0
	intercept_escort_radius = 240.0
	intercept_player_in_escort_zone = true


## Get hunt target's health for HUD display
func get_hunt_target_health() -> int:
	if not is_instance_valid(hunt_target_enemy):
		return 0
	return hunt_target_enemy.get_current_health()


## Get hunt target's max health for HUD display
func get_hunt_target_max_health() -> int:
	if not is_instance_valid(hunt_target_enemy):
		return 0
	return hunt_target_enemy.get_max_health()


## Whether any room objective is currently active
func has_active_objective() -> bool:
	return active_objective_kind == "last_stand" or active_objective_kind == "cut_the_signal" or active_objective_kind == "hold_the_line" or active_objective_kind == "circuit_sweep" or active_objective_kind == "pulse_window" or active_objective_kind == "intercept_run"


## Whether hold-the-line control overlay should currently render
func should_draw_control_overlay() -> bool:
	if active_objective_kind == "pulse_window":
		return pulse_ring_time_left > 0.0
	if control_radius <= 0.0 and intercept_drone_radius <= 0.0 and sweep_node_radius <= 0.0:
		return false
	if active_objective_kind == "hold_the_line":
		return true
	if active_objective_kind == "circuit_sweep":
		return sweep_node_radius > 0.0 and sweep_nodes_completed < sweep_node_count
	if active_objective_kind == "intercept_run":
		return intercept_drone_progress < 1.0 and intercept_drone_speed > 0.0
	return control_progress > 0.0


## Get objective telemetry fields used by world-level run events
func get_telemetry_state() -> Dictionary:
	return {
		"objective_kind": active_objective_kind,
		"objective_player_inside": control_player_inside,
		"objective_contested": control_contested,
	}

## Serialize all network-synced fields into a payload for transmission.
func serialize_sync_state() -> Dictionary:
	return {
		"active_objective_kind": String(active_objective_kind),
		"time_left": float(time_left),
		"spawn_interval": float(spawn_interval),
		"spawn_timer": float(spawn_timer),
		"spawn_batch": int(spawn_batch),
		"max_enemies": int(max_enemies),
		"overtime": bool(overtime),
		"survival_quota_announced": bool(survival_quota_announced),
		"kill_target": int(kill_target),
		"kills": int(kills),
		"hunt_target_type": String(hunt_target_type),
		"hunt_target_name": String(hunt_target_name),
		"hunt_target_kill_progress": int(hunt_target_kill_progress),
		"hunt_target_kill_goal": int(hunt_target_kill_goal),
		"hunt_target_flee_thresholds": hunt_target_flee_thresholds.duplicate(),
		"hunt_target_next_flee_index": int(hunt_target_next_flee_index),
		"control_progress": float(control_progress),
		"control_goal": float(control_goal),
		"control_enemies_in_zone": int(control_enemies_in_zone),
		"control_contested": bool(control_contested),
		"control_player_inside": bool(control_player_inside),
		"exposure_left": float(exposure_left),
		"last_relocated_escort_count": int(last_relocated_escort_count),
		"relocation_hint_left": float(relocation_hint_left),
		"purge_kill_target": 0,  # removed — kept as 0 for legacy save compat
		"sweep_nodes_completed": int(sweep_nodes_completed),
		"sweep_capture_progress": float(sweep_capture_progress),
		"sweep_node_position": sweep_node_position,
		"pulse_next_timer": float(pulse_next_timer),
		"pulse_active": bool(pulse_active),
		"pulse_active_timer": float(pulse_active_timer),
		"pulse_mode": String(pulse_mode),
		"pulse_active_mutator": pulse_active_mutator.duplicate(true),
		"pulse_ring_time_left": float(pulse_ring_time_left),
		"pulse_ring_color": pulse_ring_color,
		"pulse_count": int(pulse_count),
		"intercept_drone_progress": float(intercept_drone_progress),
		"intercept_drone_position": intercept_drone_position,
		"intercept_enemies_near_drone": int(intercept_enemies_near_drone),
		"intercept_drone_stalled": bool(intercept_drone_stalled),
		"intercept_player_in_escort_zone": bool(intercept_player_in_escort_zone),
	}

## Apply a received network sync payload, clamping all values to safe ranges.
func apply_sync_state(state: Dictionary) -> void:
	active_objective_kind = String(state.get("active_objective_kind", active_objective_kind))
	time_left = maxf(0.0, float(state.get("time_left", time_left)))
	spawn_interval = maxf(0.0, float(state.get("spawn_interval", spawn_interval)))
	spawn_timer = maxf(0.0, float(state.get("spawn_timer", spawn_timer)))
	spawn_batch = maxi(1, int(state.get("spawn_batch", spawn_batch)))
	max_enemies = maxi(0, int(state.get("max_enemies", max_enemies)))
	overtime = bool(state.get("overtime", overtime))
	survival_quota_announced = bool(state.get("survival_quota_announced", survival_quota_announced))
	kill_target = maxi(0, int(state.get("kill_target", kill_target)))
	kills = maxi(0, int(state.get("kills", kills)))
	hunt_target_type = String(state.get("hunt_target_type", hunt_target_type))
	hunt_target_name = String(state.get("hunt_target_name", hunt_target_name))
	hunt_target_kill_progress = maxi(0, int(state.get("hunt_target_kill_progress", hunt_target_kill_progress)))
	hunt_target_kill_goal = maxi(0, int(state.get("hunt_target_kill_goal", hunt_target_kill_goal)))
	hunt_target_flee_thresholds = (state.get("hunt_target_flee_thresholds", hunt_target_flee_thresholds) as Array).duplicate()
	hunt_target_next_flee_index = maxi(0, int(state.get("hunt_target_next_flee_index", hunt_target_next_flee_index)))
	control_progress = maxf(0.0, float(state.get("control_progress", control_progress)))
	control_goal = maxf(0.0, float(state.get("control_goal", control_goal)))
	control_enemies_in_zone = maxi(0, int(state.get("control_enemies_in_zone", control_enemies_in_zone)))
	control_contested = bool(state.get("control_contested", control_contested))
	control_player_inside = bool(state.get("control_player_inside", control_player_inside))
	exposure_left = maxf(0.0, float(state.get("exposure_left", exposure_left)))
	last_relocated_escort_count = maxi(0, int(state.get("last_relocated_escort_count", last_relocated_escort_count)))
	relocation_hint_left = maxf(0.0, float(state.get("relocation_hint_left", relocation_hint_left)))
	sweep_nodes_completed = maxi(0, int(state.get("sweep_nodes_completed", sweep_nodes_completed)))
	sweep_capture_progress = maxf(0.0, float(state.get("sweep_capture_progress", sweep_capture_progress)))
	var raw_sweep_pos: Variant = state.get("sweep_node_position", sweep_node_position)
	if raw_sweep_pos is Vector2:
		sweep_node_position = raw_sweep_pos
	pulse_next_timer = maxf(0.0, float(state.get("pulse_next_timer", pulse_next_timer)))
	pulse_active = bool(state.get("pulse_active", pulse_active))
	pulse_active_timer = maxf(0.0, float(state.get("pulse_active_timer", pulse_active_timer)))
	pulse_mode = String(state.get("pulse_mode", pulse_mode))
	pulse_ring_time_left = maxf(0.0, float(state.get("pulse_ring_time_left", pulse_ring_time_left)))
	var raw_ring_color: Variant = state.get("pulse_ring_color", pulse_ring_color)
	if raw_ring_color is Color:
		pulse_ring_color = raw_ring_color
	pulse_count = maxi(0, int(state.get("pulse_count", pulse_count)))
	intercept_drone_progress = clampf(float(state.get("intercept_drone_progress", intercept_drone_progress)), 0.0, 1.0)
	var raw_intercept_pos: Variant = state.get("intercept_drone_position", intercept_drone_position)
	if raw_intercept_pos is Vector2:
		intercept_drone_position = raw_intercept_pos
	intercept_enemies_near_drone = maxi(0, int(state.get("intercept_enemies_near_drone", intercept_enemies_near_drone)))
	intercept_drone_stalled = bool(state.get("intercept_drone_stalled", intercept_drone_stalled))
	intercept_player_in_escort_zone = bool(state.get("intercept_player_in_escort_zone", intercept_player_in_escort_zone))


## Get control overlay render state for world drawing
func get_control_overlay_state() -> Dictionary:
	if active_objective_kind == "circuit_sweep":
		return {
			"should_draw": should_draw_control_overlay(),
			"overlay_mode": "sweep",
			"anchor": sweep_node_position,
			"radius": sweep_node_radius,
			"capture_progress": sweep_capture_progress,
			"capture_goal": sweep_capture_goal,
		}
	if active_objective_kind == "intercept_run":
		return {
			"should_draw": should_draw_control_overlay(),
			"overlay_mode": "intercept",
			"drone_progress": intercept_drone_progress,
			"drone_position": intercept_drone_position,
			"drone_start": intercept_start,
			"drone_end": intercept_end,
			"drone_radius": intercept_drone_radius,
			"stalled": intercept_drone_stalled,
			"enemies_near": intercept_enemies_near_drone,
			"escort_radius": intercept_escort_radius,
			"player_in_escort_zone": intercept_player_in_escort_zone,
		}
	return {
		"should_draw": should_draw_control_overlay(),
		"overlay_mode": "control",
		"anchor": control_anchor,
		"radius": control_radius,
		"progress": control_progress,
		"goal": control_goal,
		"player_inside": control_player_inside,
		"contested": control_contested,
	}


## Get as HUD-compatible dictionary
func get_hud_state() -> Dictionary:
	return {
		"active_objective_kind": active_objective_kind,
		"time_left": time_left,
		"kills": kills,
		"kill_target": kill_target,
		"overtime": overtime,
		"hunt_target_name": hunt_target_name,
		"hunt_target_health": get_hunt_target_health(),
		"hunt_target_max_health": get_hunt_target_max_health(),
		"hunt_target_kill_progress": hunt_target_kill_progress,
		"hunt_target_kill_goal": hunt_target_kill_goal,
		"hunt_target_flee_thresholds": hunt_target_flee_thresholds,
		"hunt_target_next_flee_index": hunt_target_next_flee_index,
		"control_progress": control_progress,
		"control_goal": control_goal,
		"control_enemies_in_zone": control_enemies_in_zone,
		"control_contested": control_contested,
		"control_player_inside": control_player_inside,
		"exposure_left": exposure_left,
		"last_relocated_escort_count": last_relocated_escort_count,
		"relocation_hint_left": relocation_hint_left,
		"sweep_nodes_completed": sweep_nodes_completed,
		"sweep_node_count": sweep_node_count,
		"sweep_capture_progress": sweep_capture_progress,
		"sweep_capture_goal": sweep_capture_goal,
		"pulse_next_timer": pulse_next_timer,
		"pulse_active": pulse_active,
		"pulse_active_timer": pulse_active_timer,
		"pulse_mode": pulse_mode,
		"pulse_ring_time_left": pulse_ring_time_left,
		"pulse_count": pulse_count,
		"intercept_drone_progress": intercept_drone_progress,
		"intercept_drone_position": intercept_drone_position,
		"intercept_enemies_near_drone": intercept_enemies_near_drone,
		"intercept_drone_stalled": intercept_drone_stalled,
		"intercept_player_in_escort_zone": intercept_player_in_escort_zone,
	}
