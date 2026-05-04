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

	# Exposure
	exposure_duration = 2.0
	exposure_left = 0.0
	exposure_push_duration = 1.2
	exposure_push_left = 0.0
	exposure_push_strength = 380.0
	exposure_push_radius = 252.0
	exposure_push_accel = 940.0

	# Relocation
	relocation_escort_dash_lines.clear()
	relocation_escort_dash_line_time_left = 0.0
	last_relocated_escort_count = 0
	relocation_hint_left = 0.0

	# Signal FX
	signal_fx_node = null
	signal_fx_left = 0.0
	signal_fx_duration = 0.0
	signal_fx_strength = 1.0
	signal_fx_phase = 0.0


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
	return active_objective_kind == "last_stand" or active_objective_kind == "cut_the_signal" or active_objective_kind == "hold_the_line"


## Whether hold-the-line control overlay should currently render
func should_draw_control_overlay() -> bool:
	if control_radius <= 0.0:
		return false
	if active_objective_kind == "hold_the_line":
		return true
	return control_progress > 0.0


## Get objective telemetry fields used by world-level run events
func get_telemetry_state() -> Dictionary:
	return {
		"objective_kind": active_objective_kind,
		"objective_player_inside": control_player_inside,
		"objective_contested": control_contested,
	}


## Get control overlay render state for world drawing
func get_control_overlay_state() -> Dictionary:
	return {
		"should_draw": should_draw_control_overlay(),
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
	}
