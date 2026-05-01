extends Node

const ENUMS := preload("res://scripts/shared/enums.gd")
const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")

# Objective roles are stable internal IDs. Encounter kind strings can change in one place below.
const OBJECTIVE_ROLE_LAST_STAND = "last_stand_role"
const OBJECTIVE_ROLE_CUT_THE_SIGNAL = "cut_the_signal_role"
const OBJECTIVE_ROLE_HOLD_THE_LINE = "hold_the_line_role"
const OBJECTIVE_KIND_BY_ROLE := {
	OBJECTIVE_ROLE_LAST_STAND: "last_stand",
	OBJECTIVE_ROLE_CUT_THE_SIGNAL: "cut_the_signal",
	OBJECTIVE_ROLE_HOLD_THE_LINE: "hold_the_line"
}

# === OBJECTIVE CONFIGS ===
class LastStandConfig:
	const SPAWN_INTERVAL_MULT_BASE = 1.15
	const SPAWN_INTERVAL_MULT_PRESSURE = 0.2
	const SPAWN_INTERVAL_CLAMP_MIN = 0.8
	const SPAWN_INTERVAL_CLAMP_MAX = 1.08
	const MAX_ENEMIES_BASE = 12
	const MAX_ENEMIES_HARD_CAP = 24
	const MAX_ENEMIES_DEPTH_MULT = 0.9
	const KILL_TARGET_MIN = 8
	const KILL_TARGET_BASE = 10
	const KILL_TARGET_TIME_MULT = 0.42
	const KILL_TARGET_BASE_BONUS = 2
	const KILL_TARGET_DEPTH_MULT = 0.35
	const KILL_TARGET_ROUND_TO = 5
	const CLEANUP_WINDOW = 8.0
	const QUOTA_MET_DECAY_MULT = 0.85
	const OVERTIME_SPAWN_INTERVAL_MULT = 0.65
	const OVERTIME_SPAWN_BATCH_CAP = 7

class CutTheSignalConfig:
	const SPAWN_TIMER_MIN = 0.35
	const SPAWN_INTERVAL_BASE = 1.2
	const SPAWN_INTERVAL_CLAMP_MIN = 0.5
	const SPAWN_INTERVAL_CLAMP_MAX = 0.95
	const MAX_ENEMIES_BASE = 12
	const MAX_ENEMIES_DEPTH_MULT = 0.6
	const MAX_ENEMIES_MIN = 6
	const HUNT_KILL_GOAL_MIN = 2
	const HUNT_KILL_GOAL_MAX = 6
	const HUNT_KILL_MULT = 4.0
	const SPAWN_TIMER_REFILL = 0.45
	const SPAWN_INTERVAL_OVERTIME_MULT = 0.7
	const SPAWN_BATCH_OVERTIME_CAP = 6
	const SPAWN_TIMER_OVERTIME = 0.15
	const HEALTH_BOOST_MULT = 2.6
	const HEALTH_BOOST_MIN = 40
	const SCALE_MULT = 1.14
	const MARKER_Y_OFFSET = -62.0
	const MARKER_Z_INDEX = 50
	const HEALTH_BAR_SIZE = Vector2(72.0, 9.0)
	const HEALTH_BAR_OFFSET = Vector2(-36.0, -48.0)
	const DEFAULT_TYPE = "archer"
	const SPAWN_DISTANCE_MIN = 320.0
	const SPAWN_DISTANCE_BASE = 180.0
	const OPENING_ESCORT_TYPES = ["shielder", "chaser", "chaser"]
	const OPENING_ESCORT_RADIUS_SHIELDER = 76.0
	const OPENING_ESCORT_RADIUS_OTHER = 92.0
	const RELOCATION_MIN_DISTANCE = 120.0
	const RELOCATION_ATTEMPT_COUNT = 8
	const RELOCATION_CANDIDATE_MIN_DISTANCE = 160.0
	const RELOCATION_SCORE_PLAYER_MULT = 1.2
	const RELOCATION_SCORE_NEIGHBOR_MULT = 0.35
	const RELOCATION_SCORE_NEIGHBOR_CAP = 180.0
	const EXPOSURE_THRESHOLD_PHASE_BASE = 1.9
	const EXPOSURE_THRESHOLD_PHASE_STEP = 0.28
	const EXPOSURE_THRESHOLD_PHASE_MAX = 3.0
	const EXPOSURE_FX_STRENGTH_BASE = 1.0
	const EXPOSURE_FX_STRENGTH_STEP = 0.2
	const EXPOSURE_FX_STRENGTH_MAX = 1.8
	const EXPOSURE_PUSH_STRENGTH_MIN_MULT = 0.62
	const EXPOSURE_PUSH_LERP_A = 0.62
	const EXPOSURE_PUSH_LERP_B = 1.0
	const EXPOSURE_PUSH_AWAY_DIR_BONUS = 0.38
	const EXPOSURE_PUSH_CLOSE_THRESHOLD = 188.0
	const EXPOSURE_PUSH_CLOSE_MULT = 0.72
	const EXPOSURE_PUSH_VERY_CLOSE_THRESHOLD = 96.0
	const EXPOSURE_PUSH_VERY_CLOSE_MULT = 0.82

class HoldTheLineConfig:
	const MAX_ENEMIES_BASE = 5
	const MAX_ENEMIES_DEPTH_MULT = 0.32
	const MAX_ENEMIES_MIN = 5
	const SPAWN_TIMER_MIN = 1.0
	const SPAWN_INTERVAL_BASE = 1.36
	const SPAWN_INTERVAL_CLAMP_MIN = 0.98
	const SPAWN_INTERVAL_CLAMP_MAX = 1.24
	const SPAWN_INTERVAL_OVERTIME_MULT = 0.95
	const SPAWN_INTERVAL_OVERTIME_MIN = 1.2
	const SPAWN_BATCH_OVERTIME_CAP = 4
	const SPAWN_TIMER_OVERTIME = 0.8

# === COLORS ===
const COLOR_SIGNAL_BASE = Color(1.0, 0.84, 0.3, 0.95)
const COLOR_SIGNAL_MUTATOR = Color(1.0, 0.84, 0.3, 1.0)
const COLOR_DASH_LINE = Color(1.0, 0.9, 0.54, 0.96)
const COLOR_ESCORT_CARRY_LINE = Color(0.9, 0.98, 1.0, 0.96)
const COLOR_MARKER_DIAMOND_EXPOSED = Color(1.0, 0.98, 0.7, 1.0)
const COLOR_MARKER_DIAMOND_OVERTIME = Color(1.0, 0.44, 0.32, 0.96)
const COLOR_MARKER_DIAMOND_BASE = Color(1.0, 0.84, 0.3, 0.95)
const COLOR_MARKER_STEM_EXPOSED = Color(1.0, 0.94, 0.62, 0.98)
const COLOR_MARKER_STEM_OVERTIME = Color(1.0, 0.62, 0.36, 0.92)
const COLOR_MARKER_STEM_BASE = Color(1.0, 0.9, 0.46, 0.9)
const COLOR_SIGNAL_FX_CIRCLE = Color(1.0, 0.84, 0.3, 0.0)

# === VFX AND TIMING ===
const VFX_DASH_LINE_WIDTH = 6.6
const VFX_ESCORT_LINE_WIDTH = 2.6
const VFX_DASH_LINE_Z_INDEX = 48
const VFX_ESCORT_LINE_Z_INDEX = 49
const VFX_EXPOSURE_Z_INDEX = 32
const VFX_MARKER_Z_INDEX = 50
const VFX_MARKER_SCALE_PULSE_MAGNITUDE = 0.08
const VFX_MARKER_SCALE_PULSE_FREQUENCY = 5.0
const VFX_DASH_LINE_FADE_TIME = 0.34
const VFX_ESCORT_LINE_FADE_TIME = 0.48
const VFX_EXPOSURE_CIRCLE_RADIUS_BASE = 120.0
const VFX_EXPOSURE_CIRCLE_RADIUS_STEP = 40.0
const VFX_EXPOSURE_CIRCLE_COUNT = 3
const VFX_EXPOSURE_CIRCLE_POINT_COUNT = 24
const VFX_EXPOSURE_PULSE_PHASE_MULT = 3.2
const VFX_EXPOSURE_PULSE_PHASE_OFFSET = 0.4
const VFX_EXPOSURE_PULSE_AMPLITUDE = 0.5
const VFX_MARKER_DIAMOND_SIZE = 8.0

var world: Node
var rng: RandomNumberGenerator

func initialize(world_generator: Node, random_number_generator: RandomNumberGenerator) -> void:
	world = world_generator
	rng = random_number_generator

func _objective_kind_for_role(role: String) -> String:
	return String(OBJECTIVE_KIND_BY_ROLE.get(role, ""))

func _is_active_objective_role(role: String) -> bool:
	return world.active_objective_kind == _objective_kind_for_role(role)

func _clear_all_objective_state() -> void:
	world.active_objective_kind = ""
	world.objective_time_left = 0.0
	world.objective_spawn_interval = 0.0
	world.objective_spawn_timer = 0.0
	world.objective_spawn_batch = 1
	world.objective_max_enemies = 0
	world.objective_kill_target = 0
	world.objective_kills = 0
	world.objective_overtime = false
	world.objective_survival_quota_announced = false
	world.objective_target_enemy = null
	world.objective_target_type = ""
	world.objective_target_name = ""
	world.objective_hunt_kill_progress = 0
	world.objective_control_anchor = Vector2.ZERO
	world.objective_control_radius = 0.0
	world.objective_control_progress = 0.0
	world.objective_control_goal = 0.0
	world.objective_control_decay_rate = 0.0
	world.objective_control_contest_threshold = 0
	world.objective_control_enemies_in_zone = 0
	world.objective_control_player_inside = false
	world.objective_control_contested = false
	world.objective_exposure_left = 0.0
	world.objective_exposure_push_left = 0.0
	world.objective_last_relocated_escort_count = 0
	world.objective_relocation_hint_left = 0.0
	clear_priority_target_escort_dash_lines()
	clear_priority_target_exposure_vfx()

func reset_room_objective_state() -> void:
	_clear_all_objective_state()

func begin_room_objective(profile: Dictionary) -> void:
	world.active_objective_kind = ENCOUNTER_CONTRACTS.profile_objective_kind(profile)
	if _is_active_objective_role(OBJECTIVE_ROLE_LAST_STAND):
		_begin_survival_objective(profile)
		return
	if _is_active_objective_role(OBJECTIVE_ROLE_CUT_THE_SIGNAL):
		_begin_priority_target_objective(profile)
		return
	if _is_active_objective_role(OBJECTIVE_ROLE_HOLD_THE_LINE):
		_begin_control_objective(profile)

func _begin_survival_objective(profile: Dictionary) -> void:
	world.objective_time_left = ENCOUNTER_CONTRACTS.profile_objective_duration(profile)
	world.objective_spawn_interval = ENCOUNTER_CONTRACTS.profile_objective_spawn_interval(profile)
	var objective_pressure_mult: float = world._objective_pressure_mult()
	world.objective_spawn_interval *= clampf(LastStandConfig.SPAWN_INTERVAL_MULT_BASE - objective_pressure_mult * LastStandConfig.SPAWN_INTERVAL_MULT_PRESSURE, LastStandConfig.SPAWN_INTERVAL_CLAMP_MIN, LastStandConfig.SPAWN_INTERVAL_CLAMP_MAX)
	world.objective_spawn_timer = world.objective_spawn_interval
	world.objective_spawn_batch = ENCOUNTER_CONTRACTS.profile_objective_spawn_batch(profile)
	world.objective_spawn_batch = maxi(1, int(round(float(world.objective_spawn_batch) * objective_pressure_mult)))
	world.objective_max_enemies = mini(LastStandConfig.MAX_ENEMIES_HARD_CAP, LastStandConfig.MAX_ENEMIES_BASE + int(floor(float(world.room_depth) * LastStandConfig.MAX_ENEMIES_DEPTH_MULT)))
	world.objective_max_enemies = maxi(8, int(round(float(world.objective_max_enemies) * objective_pressure_mult)))
	var raw_kill_target := maxi(LastStandConfig.KILL_TARGET_BASE, int(round(world.objective_time_left * LastStandConfig.KILL_TARGET_TIME_MULT)) + LastStandConfig.KILL_TARGET_BASE_BONUS + int(floor(float(world.room_depth) * LastStandConfig.KILL_TARGET_DEPTH_MULT)))
	raw_kill_target = maxi(LastStandConfig.KILL_TARGET_MIN, int(round(float(raw_kill_target) * objective_pressure_mult)))
	world.objective_kill_target = int(ceil(float(raw_kill_target) / 5.0)) * 5
	world.objective_kills = 0
	world.objective_overtime = false
	world.objective_survival_quota_announced = false

func _begin_priority_target_objective(profile: Dictionary) -> void:
	world.objective_target_type = ENCOUNTER_CONTRACTS.profile_objective_target_type(profile)
	if world.objective_target_type.is_empty():
		world.objective_target_type = CutTheSignalConfig.DEFAULT_TYPE
	world.objective_target_name = "Signal"
	world.objective_time_left = ENCOUNTER_CONTRACTS.profile_objective_duration(profile)
	world.objective_spawn_interval = ENCOUNTER_CONTRACTS.profile_objective_spawn_interval(profile)
	var objective_pressure_mult: float = world._objective_pressure_mult()
	world.objective_spawn_timer = maxf(CutTheSignalConfig.SPAWN_TIMER_MIN, world.objective_spawn_interval * clampf(CutTheSignalConfig.SPAWN_INTERVAL_BASE - objective_pressure_mult * 0.45, CutTheSignalConfig.SPAWN_INTERVAL_CLAMP_MIN, CutTheSignalConfig.SPAWN_INTERVAL_CLAMP_MAX))
	world.objective_spawn_batch = ENCOUNTER_CONTRACTS.profile_objective_spawn_batch(profile)
	world.objective_spawn_batch = maxi(1, int(round(float(world.objective_spawn_batch) * objective_pressure_mult)))
	world.objective_max_enemies = 12 + int(floor(float(world.room_depth) * CutTheSignalConfig.MAX_ENEMIES_DEPTH_MULT))
	world.objective_max_enemies = maxi(CutTheSignalConfig.MAX_ENEMIES_MIN, int(round(float(world.objective_max_enemies) * objective_pressure_mult)))
	world.objective_hunt_kill_goal = clampi(int(round(CutTheSignalConfig.HUNT_KILL_MULT * objective_pressure_mult)), CutTheSignalConfig.HUNT_KILL_GOAL_MIN, CutTheSignalConfig.HUNT_KILL_GOAL_MAX)
	world.objective_overtime = false
	spawn_priority_target_enemy()

func _begin_control_objective(profile: Dictionary) -> void:
	world.objective_time_left = ENCOUNTER_CONTRACTS.profile_objective_duration(profile)
	world.objective_spawn_interval = ENCOUNTER_CONTRACTS.profile_objective_spawn_interval(profile)
	var objective_pressure_mult: float = world._objective_pressure_mult()
	world.objective_spawn_timer = maxf(HoldTheLineConfig.SPAWN_TIMER_MIN, world.objective_spawn_interval * clampf(HoldTheLineConfig.SPAWN_INTERVAL_BASE - objective_pressure_mult * 0.16, HoldTheLineConfig.SPAWN_INTERVAL_CLAMP_MIN, HoldTheLineConfig.SPAWN_INTERVAL_CLAMP_MAX))
	world.objective_spawn_batch = ENCOUNTER_CONTRACTS.profile_objective_spawn_batch(profile)
	world.objective_spawn_batch = maxi(1, int(round(float(world.objective_spawn_batch) * objective_pressure_mult)))
	world.objective_max_enemies = HoldTheLineConfig.MAX_ENEMIES_BASE + int(floor(float(world.room_depth) * HoldTheLineConfig.MAX_ENEMIES_DEPTH_MULT))
	world.objective_max_enemies = maxi(HoldTheLineConfig.MAX_ENEMIES_MIN, int(round(float(world.objective_max_enemies) * objective_pressure_mult)))
	world.objective_control_anchor = Vector2.ZERO
	world.objective_control_radius = ENCOUNTER_CONTRACTS.profile_objective_zone_radius(profile)
	world.objective_control_progress = 0.0
	world.objective_control_goal = ENCOUNTER_CONTRACTS.profile_objective_progress_goal(profile)
	world.objective_control_decay_rate = ENCOUNTER_CONTRACTS.profile_objective_progress_decay(profile)
	world.objective_control_contest_threshold = ENCOUNTER_CONTRACTS.profile_objective_contest_threshold(profile)
	world.objective_control_enemies_in_zone = 0
	world.objective_control_player_inside = false
	world.objective_control_contested = false
	world.objective_overtime = false
	world.hud.show_banner("Hold the Line", "Secure the control zone")
	world.queue_redraw()

func update_objective_state(delta: float) -> void:
	if _is_active_objective_role(OBJECTIVE_ROLE_LAST_STAND):
		update_survival_objective_state(delta)
		return
	if _is_active_objective_role(OBJECTIVE_ROLE_CUT_THE_SIGNAL):
		update_priority_target_objective_state(delta)
		return
	if _is_active_objective_role(OBJECTIVE_ROLE_HOLD_THE_LINE):
		update_control_objective_state(delta)
		return

func update_survival_objective_state(delta: float) -> void:
	var quota_met: bool = world.objective_kill_target > 0 and world.objective_kills >= world.objective_kill_target
	if world.choosing_next_room or world.run_cleared:
		return
	if quota_met and not world.objective_survival_quota_announced and world.objective_time_left > 0.0 and not world.objective_overtime:
		world.objective_survival_quota_announced = true
		# Shift into a short cleanup window once quota is met so the player is rewarded for engaging.
		world.objective_time_left = minf(world.objective_time_left, 8.0)
		world.hud.show_banner("Kill Quota Fulfilled", "Cleanup phase: hold briefly")
	if world.objective_time_left > 0.0:
		world.objective_time_left = maxf(0.0, world.objective_time_left - delta)
	if quota_met and world.objective_time_left > 0.0 and not world.objective_overtime:
		world.objective_time_left = maxf(0.0, world.objective_time_left - delta * LastStandConfig.QUOTA_MET_DECAY_MULT)
	if world.objective_time_left <= 0.0 and not world.objective_overtime:
		if quota_met:
			complete_current_objective("Objective Complete", "Survived the timer")
			return
		world.objective_overtime = true
		world.objective_spawn_interval = maxf(0.45, world.objective_spawn_interval * LastStandConfig.OVERTIME_SPAWN_INTERVAL_MULT)
		world.objective_spawn_batch = mini(LastStandConfig.OVERTIME_SPAWN_BATCH_CAP, world.objective_spawn_batch + 1)
		world.objective_spawn_timer = 0.1
		world.hud.show_banner("Overtime", "")
	if world.objective_overtime and quota_met:
		complete_current_objective("Objective Complete", "Kill quota reached")
		return

	if quota_met:
		if world.active_room_enemy_count <= 0:
			complete_current_objective("Objective Complete", "Kill quota reached")
			return
		return

	var pressure_floor: int = mini(18, 5 + int(floor(float(world.room_depth) * 0.45)) + world.objective_spawn_batch)
	if world.objective_max_enemies > 0:
		pressure_floor = mini(pressure_floor, world.objective_max_enemies)
	if world.active_room_enemy_count < pressure_floor and (world.objective_time_left > 0.0 or world.objective_overtime):
		world.objective_spawn_timer = minf(world.objective_spawn_timer, 0.4)
	world.objective_spawn_timer = maxf(0.0, world.objective_spawn_timer - delta)
	if world.objective_spawn_timer <= 0.0 and (world.objective_time_left > 0.0 or world.objective_overtime):
		world.objective_spawn_timer = world.objective_spawn_interval
		spawn_survival_wave()

func update_priority_target_objective_state(delta: float) -> void:
	if world.choosing_next_room or world.run_cleared:
		return
	if not is_instance_valid(world.objective_target_enemy):
		complete_current_objective("Target Eliminated", "%s down" % world.objective_target_name)
		return
	update_priority_target_exposure_state(delta)
	check_priority_target_relocation_threshold()
	var pressure_floor: int = 5 + world.objective_spawn_batch
	if world.objective_overtime:
		pressure_floor += 2
	if world.objective_max_enemies > 0:
		pressure_floor = mini(pressure_floor, world.objective_max_enemies)
	if world.active_room_enemy_count < pressure_floor:
		world.objective_spawn_timer = minf(world.objective_spawn_timer, 0.45)
	if world.objective_time_left > 0.0:
		world.objective_time_left = maxf(0.0, world.objective_time_left - delta)
	if world.objective_relocation_hint_left > 0.0:
		world.objective_relocation_hint_left = maxf(0.0, world.objective_relocation_hint_left - delta)
	if world.objective_exposure_left > 0.0:
		return
	world.objective_spawn_timer = maxf(0.0, world.objective_spawn_timer - delta)
	if world.objective_spawn_timer <= 0.0:
		world.objective_spawn_timer = world.objective_spawn_interval
		spawn_priority_target_wave()
	if world.objective_time_left <= 0.0 and not world.objective_overtime:
		world.objective_overtime = true
		world.objective_spawn_interval = maxf(0.55, world.objective_spawn_interval * 0.7)
		world.objective_spawn_batch = mini(CutTheSignalConfig.SPAWN_BATCH_OVERTIME_CAP, world.objective_spawn_batch + 1)
		world.objective_spawn_timer = CutTheSignalConfig.SPAWN_TIMER_OVERTIME
		enrage_priority_target()
		world.hud.show_banner("Signal Escalating", "")

func _get_control_objective_difficulty_params(difficulty_rank: int) -> Dictionary:
	var params := {
		"progress_gain_mult": 1.36,
		"contested_decay_mult": 0.08,
		"out_of_zone_decay_mult": 0.72,
		"refill_spawn_cap": 1.0,
		"pressure_floor_bonus": 0
	}
	if difficulty_rank == 0:
		params["progress_gain_mult"] = 1.5
		params["contested_decay_mult"] = 0.05
		params["out_of_zone_decay_mult"] = 0.6
		params["refill_spawn_cap"] = 1.08
	elif difficulty_rank == 1:
		params["progress_gain_mult"] = 1.46
		params["contested_decay_mult"] = 0.06
		params["out_of_zone_decay_mult"] = 0.64
		params["refill_spawn_cap"] = 1.2
	elif difficulty_rank == 2:
		params["progress_gain_mult"] = 1.4
		params["contested_decay_mult"] = 0.07
		params["out_of_zone_decay_mult"] = 0.68
		params["refill_spawn_cap"] = 1.1
	elif difficulty_rank == 3:
		params["progress_gain_mult"] = 1.3
		params["contested_decay_mult"] = 0.09
		params["out_of_zone_decay_mult"] = 0.76
		params["refill_spawn_cap"] = 0.92
		params["pressure_floor_bonus"] = 1
	return params

func update_control_objective_state(delta: float) -> void:
	if world.choosing_next_room or world.run_cleared:
		return
	var difficulty_rank := DIFFICULTY_CONFIG.get_difficulty_rank(int(world.current_difficulty_tier))
	var params := _get_control_objective_difficulty_params(difficulty_rank)
	var progress_gain_mult: float = params["progress_gain_mult"]
	var contested_decay_mult: float = params["contested_decay_mult"]
	var out_of_zone_decay_mult: float = params["out_of_zone_decay_mult"]
	var refill_spawn_cap: float = params["refill_spawn_cap"]
	if world.objective_time_left > 0.0:
		world.objective_time_left = maxf(0.0, world.objective_time_left - delta)
	if world.objective_time_left <= 0.0 and not world.objective_overtime:
		world.objective_overtime = true
		world.objective_spawn_interval = maxf(HoldTheLineConfig.SPAWN_INTERVAL_OVERTIME_MIN, world.objective_spawn_interval * HoldTheLineConfig.SPAWN_INTERVAL_OVERTIME_MULT)
		world.objective_spawn_batch = mini(HoldTheLineConfig.SPAWN_BATCH_OVERTIME_CAP, world.objective_spawn_batch + 1)
		world.objective_spawn_timer = HoldTheLineConfig.SPAWN_TIMER_OVERTIME
		world.hud.show_banner("Line Breaking", "Zone pressure escalating")
	var has_player := is_instance_valid(world.player)
	var anchor: Vector2 = world.objective_control_anchor
	var radius := maxf(1.0, world.objective_control_radius)
	world.objective_control_player_inside = has_player and world.player.global_position.distance_to(anchor) <= radius
	world.objective_control_enemies_in_zone = _count_control_zone_enemies(anchor, radius)
	world.objective_control_contested = world.objective_control_enemies_in_zone > world.objective_control_contest_threshold
	if world.objective_control_player_inside and not world.objective_control_contested:
		world.objective_control_progress = minf(world.objective_control_goal, world.objective_control_progress + delta * progress_gain_mult)
	elif world.objective_control_player_inside:
		world.objective_control_progress = maxf(0.0, world.objective_control_progress - world.objective_control_decay_rate * delta * contested_decay_mult)
	else:
		world.objective_control_progress = maxf(0.0, world.objective_control_progress - world.objective_control_decay_rate * delta * out_of_zone_decay_mult)
	if world.objective_control_progress >= world.objective_control_goal:
		complete_current_objective("Objective Complete", "Control secured")
		return
	var pressure_floor: int = world.objective_spawn_batch + params["pressure_floor_bonus"]
	if world.objective_max_enemies > 0:
		pressure_floor = mini(pressure_floor, world.objective_max_enemies)
	if world.active_room_enemy_count < pressure_floor:
		world.objective_spawn_timer = minf(world.objective_spawn_timer, refill_spawn_cap)
	world.objective_spawn_timer = maxf(0.0, world.objective_spawn_timer - delta)
	if world.objective_spawn_timer <= 0.0:
		world.objective_spawn_timer = world.objective_spawn_interval
		spawn_control_wave()
	world.queue_redraw()

func spawn_survival_wave() -> void:
	if not is_instance_valid(world.enemy_spawner):
		return
	if world.objective_max_enemies > 0 and world.active_room_enemy_count >= world.objective_max_enemies:
		return
	var roster: Array[String] = ["charger", "archer", "chaser", "charger", "shielder", "archer"]
	if world.objective_overtime:
		roster = ["charger", "archer", "charger", "archer", "shielder", "chaser", "charger"]
	var spawn_count: int = world.objective_spawn_batch
	if world.active_room_enemy_count <= world.objective_spawn_batch:
		spawn_count += 1
	if world.objective_overtime:
		spawn_count += 1
	spawn_count = mini(8, spawn_count)
	if world.objective_max_enemies > 0:
		spawn_count = mini(spawn_count, maxi(0, world.objective_max_enemies - world.active_room_enemy_count))
	if spawn_count <= 0:
		return
	for _i in range(spawn_count):
		var enemy_type := roster[rng.randi_range(0, roster.size() - 1)]
		world.active_room_enemy_count += int(world.enemy_spawner.spawn_enemy_type(enemy_type, 1))

func spawn_priority_target_wave() -> void:
	if not is_instance_valid(world.enemy_spawner):
		return
	if world.objective_max_enemies > 0 and world.active_room_enemy_count >= world.objective_max_enemies:
		return
	var roster: Array[String] = ["chaser", "shielder", "chaser", "charger", "shielder"]
	if world.objective_overtime:
		roster = ["charger", "shielder", "chaser", "charger", "shielder", "archer"]
	var spawn_count: int = world.objective_spawn_batch
	if world.objective_overtime:
		spawn_count += 1
	if world.objective_max_enemies > 0:
		spawn_count = mini(spawn_count, maxi(0, world.objective_max_enemies - world.active_room_enemy_count))
	if spawn_count <= 0:
		return
	for _i in range(spawn_count):
		var enemy_type := roster[rng.randi_range(0, roster.size() - 1)]
		world.active_room_enemy_count += int(world.enemy_spawner.spawn_enemy_type(enemy_type, 1))

func spawn_control_wave() -> void:
	if not is_instance_valid(world.enemy_spawner):
		return
	if world.objective_max_enemies > 0 and world.active_room_enemy_count >= world.objective_max_enemies:
		return
	var roster: Array[String] = ["shielder", "charger", "archer", "chaser", "archer"]
	if world.objective_overtime:
		roster = ["charger", "shielder", "archer", "chaser", "archer", "shielder"]
	var spawn_count: int = world.objective_spawn_batch
	if world.objective_overtime and world.active_room_enemy_count <= 1:
		spawn_count += 1
	if world.objective_max_enemies > 0:
		spawn_count = mini(spawn_count, maxi(0, world.objective_max_enemies - world.active_room_enemy_count))
	if spawn_count <= 0:
		return
	for _i in range(spawn_count):
		var enemy_type := roster[rng.randi_range(0, roster.size() - 1)]
		world.active_room_enemy_count += int(world.enemy_spawner.spawn_enemy_type(enemy_type, 1))

func _count_control_zone_enemies(anchor: Vector2, radius: float) -> int:
	var count := 0
	for enemy_node in world.get_tree().get_nodes_in_group("enemies"):
		if not (enemy_node is Node2D):
			continue
		var enemy_body := enemy_node as Node2D
		if enemy_body.global_position.distance_to(anchor) <= radius:
			count += 1
	return count

func update_priority_target_exposure_state(delta: float) -> void:
	if world.objective_signal_fx_left > 0.0:
		world.objective_signal_fx_left = maxf(0.0, world.objective_signal_fx_left - delta)
		world.objective_signal_fx_phase += delta
		refresh_priority_target_exposure_vfx()
		if world.objective_signal_fx_left <= 0.0:
			clear_priority_target_exposure_vfx()
	if world.objective_exposure_left <= 0.0:
		return
	world.objective_exposure_left = maxf(0.0, world.objective_exposure_left - delta)
	if world.objective_exposure_push_left > 0.0:
		world.objective_exposure_push_left = maxf(0.0, world.objective_exposure_push_left - delta)
		apply_priority_target_exposure_push(delta)
	if world.objective_exposure_left <= 0.0:
		world.hud.show_banner("Signal Recovered", "")

func trigger_priority_target_exposure(banner_title: String = "Signal Exposed", banner_subtitle: String = "Take the shot", duration_override: float = -1.0, fx_strength: float = 1.0) -> void:
	if not is_instance_valid(world.objective_target_enemy):
		return
	var duration: float = world.objective_exposure_duration if duration_override <= 0.0 else duration_override
	world.objective_exposure_left = maxf(world.objective_exposure_left, duration)
	world.objective_exposure_push_left = maxf(world.objective_exposure_push_left, world.objective_exposure_push_duration)
	world.objective_hunt_kill_progress = 0
	world.objective_spawn_timer = maxf(world.objective_spawn_timer, 1.2)
	show_priority_target_exposure_vfx(fx_strength, duration)
	world.hud.show_banner(banner_title, banner_subtitle)

func apply_priority_target_exposure_push(delta: float) -> void:
	if not is_instance_valid(world.objective_target_enemy):
		return
	var origin: Vector2 = world.objective_target_enemy.global_position
	var player_position: Vector2 = world.player.global_position if is_instance_valid(world.player) else Vector2.ZERO
	var has_player := is_instance_valid(world.player)
	var push_t := clampf(world.objective_exposure_push_left / maxf(0.01, world.objective_exposure_push_duration), 0.0, 1.0)
	var push_strength := lerpf(world.objective_exposure_push_strength * CutTheSignalConfig.EXPOSURE_PUSH_LERP_A, world.objective_exposure_push_strength * CutTheSignalConfig.EXPOSURE_PUSH_LERP_B, push_t)
	for enemy_node in world.get_tree().get_nodes_in_group("enemies"):
		if enemy_node == world.objective_target_enemy or not (enemy_node is CharacterBody2D):
			continue
		var enemy := enemy_node as CharacterBody2D
		var to_enemy: Vector2 = enemy.global_position - origin
		var dist := maxf(0.001, to_enemy.length())
		if dist > world.objective_exposure_push_radius:
			continue
		var dir: Vector2 = to_enemy / dist
		var tuned_strength := push_strength
		if has_player:
			var enemy_to_player: Vector2 = player_position - enemy.global_position
			var player_dist: float = enemy_to_player.length()
			if player_dist < CutTheSignalConfig.EXPOSURE_PUSH_CLOSE_THRESHOLD:
				var to_player_dir: Vector2 = enemy_to_player / maxf(0.001, player_dist)
				var toward_player: float = dir.dot(to_player_dir)
				if toward_player > 0.0:
					var safe_dir: Vector2 = (dir - to_player_dir * (toward_player + CutTheSignalConfig.EXPOSURE_PUSH_AWAY_DIR_BONUS)).normalized()
					if safe_dir.length() > 0.01:
						dir = safe_dir
					else:
						dir = -to_player_dir
					tuned_strength *= CutTheSignalConfig.EXPOSURE_PUSH_CLOSE_MULT
			if player_dist < CutTheSignalConfig.EXPOSURE_PUSH_VERY_CLOSE_THRESHOLD:
				dir = (enemy.global_position - player_position).normalized()
				tuned_strength = maxf(tuned_strength, world.objective_exposure_push_strength * CutTheSignalConfig.EXPOSURE_PUSH_VERY_CLOSE_MULT)
		var target_velocity: Vector2 = dir * tuned_strength
		enemy.velocity = enemy.velocity.move_toward(target_velocity, delta * world.objective_exposure_push_accel)
		enemy.apply_slow(0.2, 0.74)

func complete_current_objective(title: String, _subtitle: String) -> void:
	_clear_all_objective_state()
	clear_priority_target_dash_line()
	world._clear_all_enemies()
	world.active_room_enemy_count = 0
	world.objective_target_next_flee_index = 0
	world.hud.show_banner(title, "")
	world.queue_redraw()
	world._on_room_cleared()

func spawn_priority_target_enemy() -> void:
	var target_type: String = world.objective_target_type if not world.objective_target_type.is_empty() else "archer"
	if not is_instance_valid(world.enemy_spawner):
		return
	var target_spawn_distance := maxf(world.spawn_safe_radius + CutTheSignalConfig.SPAWN_DISTANCE_BASE, CutTheSignalConfig.SPAWN_DISTANCE_MIN)
	var spawned_target := world.enemy_spawner.spawn_enemy_node_type(target_type, target_spawn_distance) as CharacterBody2D
	if not is_instance_valid(spawned_target):
		return
	world.objective_target_enemy = spawned_target
	world.active_room_enemy_count += 1
	var boosted_max := maxi(CutTheSignalConfig.HEALTH_BOOST_MIN, int(round(float(spawned_target.get_max_health()) * CutTheSignalConfig.HEALTH_BOOST_MULT)))
	spawned_target.set_max_health_and_current(boosted_max, boosted_max)
	if spawned_target.get("has_mutator_overlay") != null:
		spawned_target.set("has_mutator_overlay", true)
	if spawned_target.get("mutator_theme_color") != null:
		spawned_target.set("mutator_theme_color", COLOR_SIGNAL_MUTATOR)
	spawned_target.scale *= CutTheSignalConfig.SCALE_MULT
	world.objective_target_next_flee_index = 0
	spawned_target.configure_health_bar_visuals(CutTheSignalConfig.HEALTH_BAR_OFFSET, CutTheSignalConfig.HEALTH_BAR_SIZE)
	spawned_target.set_health_threshold_markers(world.objective_target_flee_thresholds, world.objective_target_next_flee_index)
	world.objective_hunt_kill_progress = 0
	world.objective_hunt_kill_goal = maxi(2, world.objective_hunt_kill_goal)
	world.objective_exposure_left = 0.0
	world.objective_exposure_push_left = 0.0
	world.objective_last_relocated_escort_count = 0
	world.objective_relocation_hint_left = 0.0
	clear_priority_target_exposure_vfx()
	attach_priority_target_marker(spawned_target)
	spawn_priority_target_opening_escorts()
	if spawned_target.has_signal("died"):
		spawned_target.died.connect(Callable(self, "_on_priority_target_died"))

func spawn_priority_target_opening_escorts() -> void:
	if not is_instance_valid(world.objective_target_enemy):
		return
	if not is_instance_valid(world.enemy_spawner):
		return
	var escort_types: Array[String] = ["shielder", "chaser", "chaser"]
	if world.room_depth >= 2:
		escort_types.append("shielder")
	if world.room_depth >= 4:
		escort_types[escort_types.size() - 1] = "charger"
	while escort_types.size() < world.objective_hunt_kill_goal:
		escort_types.append("charger" if world.room_depth >= 4 else "chaser")
	var anchor: Vector2 = world.objective_target_enemy.global_position
	var base_angle := rng.randf_range(0.0, TAU)
	for escort_index in range(escort_types.size()):
		if world.objective_max_enemies > 0 and world.active_room_enemy_count >= world.objective_max_enemies:
			break
		var escort := world.enemy_spawner.spawn_enemy_node_type(escort_types[escort_index]) as CharacterBody2D
		if not is_instance_valid(escort):
			continue
		var angle := base_angle + TAU * float(escort_index) / float(maxi(1, escort_types.size()))
		var radius := CutTheSignalConfig.OPENING_ESCORT_RADIUS_SHIELDER if escort_types[escort_index] == "shielder" else CutTheSignalConfig.OPENING_ESCORT_RADIUS_OTHER
		escort.global_position = world._clamp_position_to_current_room(anchor + Vector2.RIGHT.rotated(angle) * radius, 44.0)
		world.active_room_enemy_count += 1
	world.objective_spawn_timer = maxf(world.objective_spawn_timer, world.objective_spawn_interval)
	world.hud.show_banner("Mark Spotted  Kill %d escorts to expose" % world.objective_hunt_kill_goal, "")

func check_priority_target_relocation_threshold() -> void:
	if not is_instance_valid(world.objective_target_enemy):
		return
	if world.objective_target_next_flee_index >= world.objective_target_flee_thresholds.size():
		return
	var current_health := get_priority_target_health()
	var max_health := get_priority_target_max_health()
	if current_health <= 0 or max_health <= 0:
		return
	var threshold_ratio: float = world.objective_target_flee_thresholds[world.objective_target_next_flee_index]
	var current_ratio := float(current_health) / float(max_health)
	if current_ratio > threshold_ratio:
		return
	world.objective_target_next_flee_index += 1
	world.objective_target_enemy.set_health_threshold_marker_progress(world.objective_target_next_flee_index)
	trigger_priority_target_threshold_phase(threshold_ratio)

func trigger_priority_target_threshold_phase(_threshold_ratio: float) -> void:
	var phase_index: int = world.objective_target_next_flee_index
	if not is_instance_valid(world.objective_target_enemy):
		return
	relocate_priority_target(_threshold_ratio)
	var goal_drop := maxi(1, int(round(world._objective_pressure_mult() - 0.4)))
	world.objective_hunt_kill_goal = maxi(2, world.objective_hunt_kill_goal - goal_drop)
	var duration := clampf(CutTheSignalConfig.EXPOSURE_THRESHOLD_PHASE_BASE + float(phase_index) * CutTheSignalConfig.EXPOSURE_THRESHOLD_PHASE_STEP, CutTheSignalConfig.EXPOSURE_THRESHOLD_PHASE_BASE, CutTheSignalConfig.EXPOSURE_THRESHOLD_PHASE_MAX)
	var fx_strength := clampf(CutTheSignalConfig.EXPOSURE_FX_STRENGTH_BASE + float(phase_index) * CutTheSignalConfig.EXPOSURE_FX_STRENGTH_STEP, CutTheSignalConfig.EXPOSURE_FX_STRENGTH_BASE, CutTheSignalConfig.EXPOSURE_FX_STRENGTH_MAX)
	trigger_priority_target_exposure("Signal Cracked", "Push through", duration, fx_strength)
	if is_instance_valid(world.objective_target_enemy):
		world.objective_target_enemy.velocity = Vector2.ZERO

func relocate_priority_target(_threshold_ratio: float) -> void:
	if not is_instance_valid(world.objective_target_enemy):
		return
	var old_position: Vector2 = world.objective_target_enemy.global_position
	var new_position := pick_priority_target_relocation_position(old_position)
	if old_position.distance_to(new_position) < CutTheSignalConfig.RELOCATION_MIN_DISTANCE:
		return
	world.objective_target_enemy.global_position = new_position
	world.objective_target_enemy.velocity = Vector2.ZERO
	var relocated_count := relocate_priority_target_nearby_escorts(old_position, new_position)
	show_priority_target_dash_line(old_position, new_position)
	world.objective_last_relocated_escort_count = relocated_count
	world.objective_relocation_hint_left = 3.2 if relocated_count > 0 else 0.0
	if relocated_count > 0:
		world.hud.show_banner("Signal Breakaway +%d Escorts" % relocated_count, "")
	else:
		world.hud.show_banner("Signal Breakaway", "")

func relocate_priority_target_nearby_escorts(old_position: Vector2, new_position: Vector2) -> int:
	var candidates: Array[Dictionary] = []
	for enemy_node in world.get_tree().get_nodes_in_group("enemies"):
		if enemy_node == world.objective_target_enemy or not (enemy_node is CharacterBody2D):
			continue
		var escort := enemy_node as CharacterBody2D
		var dist := escort.global_position.distance_to(old_position)
		if dist > world.objective_relocation_escort_radius:
			continue
		candidates.append({"enemy": escort, "distance": dist})
	if candidates.is_empty():
		spawn_priority_target_relocation_escorts(new_position)
		return 0
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance", INF)) < float(b.get("distance", INF))
	)
	var moved := 0
	var carry_paths: Array[Dictionary] = []
	var base_angle := rng.randf_range(0.0, TAU)
	for entry in candidates:
		if moved >= world.objective_relocation_escort_cap:
			break
		var escort := entry.get("enemy") as CharacterBody2D
		if not is_instance_valid(escort):
			continue
		var from_position := escort.global_position
		var slot_t := float(moved) / float(maxi(1, world.objective_relocation_escort_cap))
		var angle := base_angle + TAU * slot_t
		var radius := CutTheSignalConfig.OPENING_ESCORT_RADIUS_OTHER + 14.0 * float(moved)
		escort.global_position = world._clamp_position_to_current_room(new_position + Vector2.RIGHT.rotated(angle) * radius, 44.0)
		escort.velocity = Vector2.ZERO
		carry_paths.append({"from": from_position, "to": escort.global_position})
		moved += 1
	if moved < 1:
		spawn_priority_target_relocation_escorts(new_position)
		return 0
	show_priority_target_escort_carry_lines(carry_paths)
	return moved

func pick_priority_target_relocation_position(old_position: Vector2) -> Vector2:
	if not is_instance_valid(world.enemy_spawner):
		return old_position
	var min_player_distance := maxf(world.spawn_safe_radius + CutTheSignalConfig.SPAWN_DISTANCE_BASE, CutTheSignalConfig.SPAWN_DISTANCE_MIN)
	var min_enemy_spacing := 132.0
	var best_position := old_position
	var best_score := -INF
	for _attempt in range(CutTheSignalConfig.RELOCATION_ATTEMPT_COUNT):
		var candidate := world.enemy_spawner.pick_room_position(min_player_distance, min_enemy_spacing) as Vector2
		if candidate.distance_to(old_position) < CutTheSignalConfig.RELOCATION_CANDIDATE_MIN_DISTANCE:
			continue
		var score := candidate.distance_to(old_position)
		if is_instance_valid(world.player):
			score += candidate.distance_to(world.player.global_position) * CutTheSignalConfig.RELOCATION_SCORE_PLAYER_MULT
		for enemy in world.get_tree().get_nodes_in_group("enemies"):
			if enemy == world.objective_target_enemy or not (enemy is Node2D):
				continue
			var neighbor := enemy as Node2D
			score += minf(CutTheSignalConfig.RELOCATION_SCORE_NEIGHBOR_CAP, candidate.distance_to(neighbor.global_position)) * CutTheSignalConfig.RELOCATION_SCORE_NEIGHBOR_MULT
		if score > best_score:
			best_score = score
			best_position = candidate
	return world._clamp_position_to_current_room(best_position, 44.0)

func spawn_priority_target_relocation_escorts(anchor: Vector2) -> void:
	if not is_instance_valid(world.enemy_spawner):
		return
	var escort_types: Array[String] = ["chaser"]
	if world.objective_target_next_flee_index == 1:
		escort_types = ["shielder", "chaser"]
	elif world.objective_target_next_flee_index >= 2:
		escort_types = ["shielder", "charger"]
	for escort_type in escort_types:
		if world.objective_max_enemies > 0 and world.active_room_enemy_count >= world.objective_max_enemies:
			return
		var escort := world.enemy_spawner.spawn_enemy_node_type(escort_type) as CharacterBody2D
		if not is_instance_valid(escort):
			continue
		var escort_angle := rng.randf_range(0.0, TAU)
		var escort_radius := 80.0 if escort_type == "shielder" else 96.0
		escort.global_position = world._clamp_position_to_current_room(anchor + Vector2.RIGHT.rotated(escort_angle) * escort_radius, 44.0)
		world.active_room_enemy_count += 1

func _create_line_2d(width: float, color: Color, z_index: int, points: PackedVector2Array) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.points = points
	line.z_as_relative = false
	line.z_index = z_index
	return line

func show_priority_target_dash_line(from_position: Vector2, to_position: Vector2) -> void:
	clear_priority_target_dash_line()
	world.objective_target_dash_line = _create_line_2d(VFX_DASH_LINE_WIDTH, COLOR_DASH_LINE, VFX_DASH_LINE_Z_INDEX, PackedVector2Array([from_position, to_position]))
	world.objective_target_dash_line.name = "PriorityTargetDashLine"
	world.add_child(world.objective_target_dash_line)
	world.objective_target_dash_line_time_left = VFX_DASH_LINE_FADE_TIME

func clear_priority_target_dash_line() -> void:
	if is_instance_valid(world.objective_target_dash_line):
		world.objective_target_dash_line.queue_free()
		world.objective_target_dash_line = null

func show_priority_target_escort_carry_lines(paths: Array[Dictionary]) -> void:
	clear_priority_target_escort_dash_lines()
	for path_info in paths:
		var from_pos := path_info.get("from", Vector2.ZERO) as Vector2
		var to_pos := path_info.get("to", Vector2.ZERO) as Vector2
		var line := _create_line_2d(VFX_ESCORT_LINE_WIDTH, COLOR_ESCORT_CARRY_LINE, VFX_ESCORT_LINE_Z_INDEX, PackedVector2Array([from_pos, to_pos]))
		world.add_child(line)
		world.objective_escort_dash_lines.append(line)
	world.objective_escort_dash_line_time_left = VFX_ESCORT_LINE_FADE_TIME

func clear_priority_target_escort_dash_lines() -> void:
	for line in world.objective_escort_dash_lines:
		if is_instance_valid(line):
			line.queue_free()
	world.objective_escort_dash_lines.clear()
	world.objective_escort_dash_line_time_left = 0.0

func update_priority_target_marker(delta: float) -> void:
	if world.objective_escort_dash_line_time_left > 0.0:
		world.objective_escort_dash_line_time_left = maxf(0.0, world.objective_escort_dash_line_time_left - delta)
		var escort_alpha := clampf(world.objective_escort_dash_line_time_left / VFX_ESCORT_LINE_FADE_TIME, 0.0, 1.0)
		for line in world.objective_escort_dash_lines:
			if not is_instance_valid(line):
				continue
			line.default_color = COLOR_ESCORT_CARRY_LINE * Color(1.0, 1.0, 1.0, escort_alpha)
			line.width = VFX_ESCORT_LINE_WIDTH + 2.8 * escort_alpha
		if world.objective_escort_dash_line_time_left <= 0.0:
			clear_priority_target_escort_dash_lines()
	if world.objective_target_dash_line_time_left > 0.0:
		world.objective_target_dash_line_time_left = maxf(0.0, world.objective_target_dash_line_time_left - delta)
		if is_instance_valid(world.objective_target_dash_line):
			var alpha := clampf(world.objective_target_dash_line_time_left / VFX_DASH_LINE_FADE_TIME, 0.0, 1.0)
			world.objective_target_dash_line.default_color = COLOR_DASH_LINE * Color(1.0, 1.0, 1.0, alpha)
			world.objective_target_dash_line.width = 3.6 + 3.0 * alpha
		if world.objective_target_dash_line_time_left <= 0.0:
			clear_priority_target_dash_line()
	if not is_instance_valid(world.objective_target_enemy):
		return
	var marker := world.objective_target_enemy.get_node_or_null("PriorityTargetMarker") as Node2D
	if marker == null:
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	marker.scale = Vector2.ONE * (1.0 + VFX_MARKER_SCALE_PULSE_MAGNITUDE * sin(t * VFX_MARKER_SCALE_PULSE_FREQUENCY))
	var diamond := marker.get_child(0) as Polygon2D
	var stem := marker.get_child(1) as Line2D
	if diamond != null:
		if world.objective_exposure_left > 0.0:
			diamond.color = COLOR_MARKER_DIAMOND_EXPOSED
		elif world.objective_overtime:
			diamond.color = COLOR_MARKER_DIAMOND_OVERTIME
		else:
			diamond.color = COLOR_MARKER_DIAMOND_BASE
	if stem != null:
		if world.objective_exposure_left > 0.0:
			stem.default_color = COLOR_MARKER_STEM_EXPOSED
		elif world.objective_overtime:
			stem.default_color = COLOR_MARKER_STEM_OVERTIME
		else:
			stem.default_color = COLOR_MARKER_STEM_BASE

func attach_priority_target_marker(enemy: CharacterBody2D) -> void:
	var existing := enemy.get_node_or_null("PriorityTargetMarker")
	if existing != null:
		existing.queue_free()
	var marker := Node2D.new()
	marker.name = "PriorityTargetMarker"
	marker.position = Vector2(0.0, CutTheSignalConfig.MARKER_Y_OFFSET)
	marker.z_as_relative = false
	marker.z_index = CutTheSignalConfig.MARKER_Z_INDEX
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([
		Vector2(0.0, -VFX_MARKER_DIAMOND_SIZE),
		Vector2(VFX_MARKER_DIAMOND_SIZE, 0.0),
		Vector2(0.0, VFX_MARKER_DIAMOND_SIZE),
		Vector2(-VFX_MARKER_DIAMOND_SIZE, 0.0)
	])
	diamond.color = COLOR_MARKER_DIAMOND_BASE
	marker.add_child(diamond)
	var stem := Line2D.new()
	stem.width = 2.0
	stem.default_color = COLOR_MARKER_STEM_BASE
	stem.points = PackedVector2Array([Vector2(0.0, VFX_MARKER_DIAMOND_SIZE), Vector2(0.0, VFX_MARKER_DIAMOND_SIZE * 2.0)])
	marker.add_child(stem)
	enemy.add_child(marker)

func enrage_priority_target() -> void:
	if not is_instance_valid(world.objective_target_enemy):
		return
	if world.objective_target_enemy.get("seek_speed") != null:
		world.objective_target_enemy.set("seek_speed", float(world.objective_target_enemy.get("seek_speed")) * 1.2)
	if world.objective_target_enemy.get("move_speed") != null:
		world.objective_target_enemy.set("move_speed", float(world.objective_target_enemy.get("move_speed")) * 1.18)
	if world.objective_target_enemy.get("windup_time") != null:
		world.objective_target_enemy.set("windup_time", maxf(0.18, float(world.objective_target_enemy.get("windup_time")) * 0.8))
	if world.objective_target_enemy.get("attack_cooldown") != null:
		world.objective_target_enemy.set("attack_cooldown", maxf(0.45, float(world.objective_target_enemy.get("attack_cooldown")) * 0.8))

func _on_priority_target_died() -> void:
	if not _is_active_objective_role(OBJECTIVE_ROLE_CUT_THE_SIGNAL):
		return
	world.objective_target_enemy = null
	complete_current_objective("Target Eliminated", "%s down" % world.objective_target_name)

func show_priority_target_exposure_vfx(strength: float, duration: float) -> void:
	clear_priority_target_exposure_vfx()
	world.objective_signal_fx_left = duration
	world.objective_signal_fx_duration = duration
	world.objective_signal_fx_strength = strength
	world.objective_signal_fx_phase = 0.0
	world.objective_signal_fx_node = Node2D.new()
	world.objective_signal_fx_node.name = "SignalExposureFX"
	for _circle_index in range(VFX_EXPOSURE_CIRCLE_COUNT):
		var circle := Line2D.new()
		circle.width = 1.0
		circle.default_color = COLOR_SIGNAL_FX_CIRCLE
		var radius := VFX_EXPOSURE_CIRCLE_RADIUS_BASE + float(_circle_index) * VFX_EXPOSURE_CIRCLE_RADIUS_STEP
		var point_count := VFX_EXPOSURE_CIRCLE_POINT_COUNT
		var points: PackedVector2Array = []
		for point_index in range(point_count + 1):
			var angle := TAU * float(point_index) / float(point_count)
			points.append(Vector2.RIGHT.rotated(angle) * radius)
		circle.points = points
		circle.z_as_relative = false
		circle.z_index = VFX_EXPOSURE_Z_INDEX
		world.objective_signal_fx_node.add_child(circle)
	if is_instance_valid(world.objective_target_enemy):
		world.objective_signal_fx_node.global_position = world.objective_target_enemy.global_position
	world.add_child(world.objective_signal_fx_node)

func refresh_priority_target_exposure_vfx() -> void:
	if not is_instance_valid(world.objective_signal_fx_node):
		return
	var progress := clampf(1.0 - world.objective_signal_fx_left / maxf(0.01, world.objective_signal_fx_duration), 0.0, 1.0)
	var phase_offset: float = world.objective_signal_fx_phase
	for circle_index in range(world.objective_signal_fx_node.get_child_count()):
		var circle := world.objective_signal_fx_node.get_child(circle_index) as Line2D
		if circle == null:
			continue
		var pulse_phase := fmod(phase_offset * VFX_EXPOSURE_PULSE_PHASE_MULT - float(circle_index) * VFX_EXPOSURE_PULSE_PHASE_OFFSET, TAU)
		var pulse_strength := VFX_EXPOSURE_PULSE_AMPLITUDE + VFX_EXPOSURE_PULSE_AMPLITUDE * sin(pulse_phase)
		var alpha_base := 1.0 - progress
		var alpha_pulse: float = alpha_base * pulse_strength * world.objective_signal_fx_strength
		circle.default_color = COLOR_SIGNAL_FX_CIRCLE * Color(1.0, 1.0, 1.0, alpha_pulse)

func clear_priority_target_exposure_vfx() -> void:
	if is_instance_valid(world.objective_signal_fx_node):
		world.objective_signal_fx_node.queue_free()
		world.objective_signal_fx_node = null
	world.objective_signal_fx_left = 0.0

func get_priority_target_health() -> int:
	if not is_instance_valid(world.objective_target_enemy):
		return 0
	return world.objective_target_enemy.get_current_health()

func get_priority_target_max_health() -> int:
	if not is_instance_valid(world.objective_target_enemy):
		return 0
	return world.objective_target_enemy.get_max_health()
