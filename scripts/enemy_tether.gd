extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const ENEMY_BASE_SCRIPT := preload("res://scripts/enemy_base.gd")
const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const BEAM_VISUAL_LEASE := 0.35

const STATE_STALK := 0
const STATE_WINDUP := 1
const STATE_BEAM := 2
const STATE_RECOVER := 3

@export var move_speed: float = 96.0
@export var acceleration: float = 820.0
@export var deceleration: float = 1140.0
@export var preferred_range: float = 176.0
@export var range_tolerance: float = 40.0
@export var partner_refresh_interval: float = 0.22
@export var partner_switch_margin: float = 34.0
@export var beam_thickness: float = 24.0
@export var beam_damage: int = 9
@export var beam_tick_interval: float = 0.2
@export var beam_windup_time: float = 0.78
@export var beam_duration: float = 2.1
@export var beam_cooldown: float = 3.0
@export var recover_time: float = 0.38

var tether_state: int = STATE_STALK
var state_time_left: float = 0.0
var beam_cooldown_left: float = 0.0
var beam_tick_left: float = 0.0
var beam_partner: ENEMY_BASE_SCRIPT
var _orbit_sign: float = 1.0
var _partner_refresh_left: float = 0.0
var _beam_player_positions: Dictionary = {}
var _beam_player_reset_generations: Dictionary = {}
var _beam_pending_contacts: Dictionary = {}
var _beam_partner_instance_id := 0
var _beam_generation := 0
var _beam_room_id := -1
var _beam_room_bounds := Rect2()
var _last_beam_sample_a: Vector2 = Vector2.ZERO
var _last_beam_sample_b: Vector2 = Vector2.ZERO
var _has_last_beam_sample_segment: bool = false
var _attack_sync_was_active: bool = false
var _beam_wire_sequence := 0
var _beam_received_sequence := -1
var _beam_visual_lease := 0.0
var _beam_visual_a := Vector2.ZERO
var _beam_visual_b := Vector2.ZERO
var _beam_visual_radius := 0.0

func _physics_process(delta: float) -> void:
	if network_simulation_enabled and tether_state in [STATE_WINDUP, STATE_BEAM] and (_endpoint_is_launched(self) or _endpoint_is_launched(beam_partner)):
		# EnemyBase gives Ruinous exclusive movement ownership. Interrupt the
		# old hazard before that early return can freeze its timer and samples.
		_enter_recover_state()
	super._physics_process(delta)

func _endpoint_is_launched(endpoint: Variant) -> bool:
	return is_instance_valid(endpoint) and endpoint is ENEMY_BASE_SCRIPT and endpoint._launch_state != null and endpoint._launch_state.active and not endpoint._launch_state.compression

func _exit_tree() -> void:
	_clear_beam_history()

func _on_health_state_died() -> void:
	_clear_beam_history()
	_beam_visual_lease = 0.0
	super._on_health_state_died()

func set_network_simulation_enabled(enabled: bool) -> void:
	if not enabled:
		_clear_beam_history()
		_beam_visual_lease = 0.0
	super.set_network_simulation_enabled(enabled)

func _ready() -> void:
	super()
	max_health = 84
	crowd_separation_radius = 62.0
	crowd_separation_strength = 90.0
	_orbit_sign = 1.0 if int(get_instance_id()) % 2 == 0 else -1.0

func is_tether_enemy() -> bool:
	return true

func is_beam_state_active() -> bool:
	return tether_state == STATE_BEAM and state_time_left > 0.0 and (network_simulation_enabled or _beam_visual_lease > 0.0)

func is_on_kill_run() -> bool:
	if tether_state == STATE_BEAM or tether_state == STATE_WINDUP:
		return true
	if _is_valid_tether_partner(beam_partner) and beam_partner.is_beam_state_active():
		return true
	return false

func _process_behavior(delta: float) -> void:
	if beam_cooldown_left > 0.0:
		beam_cooldown_left = maxf(0.0, beam_cooldown_left - delta)
	_update_beam_partner(delta)
	match tether_state:
		STATE_STALK:
			_process_stalk(delta)
		STATE_WINDUP:
			_process_windup(delta)
		STATE_BEAM:
			_process_beam(delta)
		STATE_RECOVER:
			_process_recover(delta)

func _is_in_priority_attack_state() -> bool:
	return tether_state == STATE_WINDUP or tether_state == STATE_BEAM

func get_projectile_network_sync_state() -> Dictionary:
	if not network_simulation_enabled:
		return {}
	var active := tether_state == STATE_WINDUP or tether_state == STATE_BEAM
	if not active and not _attack_sync_was_active:
		return {}
	_attack_sync_was_active = active
	return {"beam": _build_beam_network_state()}

func apply_projectile_network_sync_state(sync_state: Dictionary) -> void:
	if network_simulation_enabled:
		return
	_apply_beam_network_state(sync_state.get("beam"))

func _process_network_visuals(delta: float) -> void:
	state_time_left = maxf(0.0, state_time_left - delta)
	_beam_visual_lease = maxf(0.0, _beam_visual_lease - delta)
	if tether_state in [STATE_WINDUP, STATE_BEAM] and (state_time_left <= 0.0 or _beam_visual_lease <= 0.0 or not _is_valid_tether_partner(beam_partner)):
		tether_state = STATE_RECOVER
		_beam_visual_lease = 0.0
	queue_redraw()

func _update_beam_partner(delta: float) -> void:
	_partner_refresh_left = maxf(0.0, _partner_refresh_left - delta)
	if tether_state == STATE_WINDUP or tether_state == STATE_BEAM:
		if _committed_partner_valid():
			return
		# A replacement partner needs a new warning; never sweep the old link
		# across the arena or silently turn it into an unannounced new beam.
		_enter_recover_state()
		beam_partner = null
		return
	if _partner_refresh_left > 0.0 and _is_valid_tether_partner(beam_partner):
		return
	beam_partner = _find_beam_partner_with_hysteresis(beam_partner as Variant)
	_partner_refresh_left = partner_refresh_interval

func _is_valid_tether_partner(candidate: Variant) -> bool:
	if typeof(candidate) != TYPE_OBJECT:
		return false
	if not is_instance_valid(candidate):
		return false
	var candidate_body := candidate as ENEMY_BASE_SCRIPT
	if candidate_body == null:
		return false
	if candidate_body == self:
		return false
	if candidate_body.is_queued_for_deletion() or (candidate_body.health_state != null and candidate_body.health_state.is_dead()):
		return false
	return candidate_body.is_tether_enemy()

func _find_beam_partner_with_hysteresis(current_partner: Variant) -> ENEMY_BASE_SCRIPT:
	var nearest := _find_beam_partner()
	if not _is_valid_tether_partner(current_partner):
		return nearest
	var current_partner_enemy := current_partner as ENEMY_BASE_SCRIPT
	if current_partner_enemy == null:
		return nearest
	if nearest == null or nearest == current_partner_enemy:
		return current_partner_enemy
	var current_distance := global_position.distance_to(current_partner_enemy.global_position)
	var nearest_distance := global_position.distance_to(nearest.global_position)
	if nearest_distance + partner_switch_margin < current_distance:
		return nearest
	return current_partner_enemy

func _find_beam_partner() -> ENEMY_BASE_SCRIPT:
	var nearest: ENEMY_BASE_SCRIPT = null
	var nearest_distance := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy == self:
			continue
		var enemy_body := enemy as ENEMY_BASE_SCRIPT
		if enemy_body == null:
			continue
		if not _is_valid_tether_partner(enemy_body):
			continue
		var distance := global_position.distance_to(enemy_body.global_position)
		if distance >= nearest_distance:
			continue
		nearest = enemy_body
		nearest_distance = distance
	return nearest

func _is_primary_pair() -> bool:
	return _is_valid_tether_partner(beam_partner) and get_instance_id() < beam_partner.get_instance_id()

func _committed_partner_valid() -> bool:
	return _is_primary_pair() and not _endpoint_is_launched(self) and not _endpoint_is_launched(beam_partner) and beam_partner.get_instance_id() == _beam_partner_instance_id and _beam_room_id == EnemyReplicationService._current_room_sync_id() and _beam_room_bounds == EnemyReplicationService.get_current_room_bounds()

func _process_stalk(delta: float) -> void:
	var desired := _stalk_desired_velocity() * slow_speed_mult
	velocity = velocity.move_toward(desired, (acceleration if desired != Vector2.ZERO else deceleration) * delta)
	move_and_slide()
	if is_instance_valid(beam_partner):
		queue_redraw()
	if beam_cooldown_left <= 0.0 and _is_primary_pair():
		_enter_windup_state()

func _stalk_desired_velocity() -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	if _is_valid_tether_partner(beam_partner) and beam_partner.is_beam_state_active():
		return _beam_crossing_support_velocity()
	return _web_desired_velocity()

func _beam_crossing_support_velocity() -> Vector2:
	var player_pos := target.global_position
	var partner_pos := beam_partner.global_position
	var from_partner := player_pos - partner_pos
	if from_partner.length_squared() <= 0.000001:
		return Vector2.ZERO
	var cross_anchor := player_pos + from_partner.normalized() * (preferred_range * 1.45)
	var to_cross := cross_anchor - global_position
	if to_cross.length_squared() <= 0.000001:
		return Vector2.ZERO
	return to_cross.normalized() * move_speed * slow_speed_mult

func _web_desired_velocity() -> Vector2:
	var player_pos := target.global_position
	var to_player := player_pos - global_position
	if to_player.length_squared() <= 0.000001:
		return Vector2.ZERO
	var player_dist := to_player.length()
	var to_player_dir := to_player / player_dist

	# Slots are anchored far out to fill the arena — not a ring around the player
	var ring_radius := preferred_range * 3.6
	var slot_target := _hivemind_slot_position(player_pos, ring_radius)
	var to_slot := slot_target - global_position
	var desired_vec := Vector2.ZERO
	if to_slot.length_squared() > 0.000001:
		desired_vec += to_slot.normalized() * 1.1

	# Repulsion from peers is the dominant spreading force
	desired_vec += _tether_group_repulsion()

	# Only hard-push if the player walks directly underneath
	if player_dist < preferred_range * 0.7:
		desired_vec += (-to_player_dir) * 2.2

	# Partner spacing — keep beam pairs linkable but not fused
	if _is_valid_tether_partner(beam_partner):
		var partner_dist := global_position.distance_to(beam_partner.global_position)
		var min_partner_dist := preferred_range * 1.2
		var max_partner_dist := preferred_range * 3.2
		if partner_dist < min_partner_dist:
			var away := global_position - beam_partner.global_position
			if away.length_squared() > 0.000001:
				desired_vec += (away / partner_dist) * 1.8
		elif partner_dist > max_partner_dist:
			var toward_partner := beam_partner.global_position - global_position
			if toward_partner.length_squared() > 0.000001:
				desired_vec += toward_partner.normalized() * 0.6

	if desired_vec.length_squared() <= 0.000001:
		return Vector2.ZERO
	return desired_vec.normalized() * move_speed

func _hivemind_slot_position(player_pos: Vector2, ring_radius: float) -> Vector2:
	var tether_total: int = _count_tether_enemies()
	var slot_count: int = clampi(tether_total, 4, 12)
	var slot_index: int = absi(int(get_instance_id())) % slot_count
	var time_s := float(Time.get_ticks_msec()) * 0.001
	# Each slot drifts on its own slow sine so slots don't all pulse in/out together
	var drift := 0.5 + 0.5 * sin(time_s * 0.55 + float(slot_index) * 1.1)
	var spread_mult := lerpf(0.7, 1.0, drift)
	var angle := (TAU * float(slot_index) / float(slot_count)) + sin(time_s * 0.3 + float(slot_index) * 0.9) * 0.22
	return player_pos + Vector2(cos(angle), sin(angle)) * ring_radius * spread_mult

func _count_tether_enemies() -> int:
	var total := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var enemy_body := enemy as CharacterBody2D
		if enemy_body == null:
			continue
		if enemy_body == self:
			total += 1
			continue
		if not _is_valid_tether_partner(enemy_body):
			continue
		total += 1
	return maxi(1, total)

func _tether_group_repulsion() -> Vector2:
	# Kill-committed tethers (beaming or crossing support) don't get pushed off their aim.
	if is_on_kill_run():
		return Vector2.ZERO
	var repel_sum := Vector2.ZERO
	var contributors := 0
	var spacing_radius := preferred_range * 3.2
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy == self:
			continue
		var enemy_body := enemy as ENEMY_BASE_SCRIPT
		if enemy_body == null:
			continue
		if not _is_valid_tether_partner(enemy_body):
			continue
		var offset := global_position - enemy_body.global_position
		var distance := offset.length()
		if distance < 0.000001 or distance >= spacing_radius:
			continue
		var push_scale := clampf((spacing_radius - distance) / maxf(1.0, spacing_radius), 0.0, 1.0)
		var enemy_on_kill_run := enemy_body.is_on_kill_run()
		var push_strength := 3.2 if enemy_on_kill_run else 2.4
		repel_sum += (offset / distance) * (push_strength * push_scale)
		contributors += 1
	if contributors <= 0:
		return Vector2.ZERO
	return repel_sum / float(contributors)

func _beam_aim_velocity() -> Vector2:
	if not is_instance_valid(target) or not _is_valid_tether_partner(beam_partner):
		return _orbit_desired_velocity()
	var player_pos := target.global_position
	var partner_pos := beam_partner.global_position
	var from_partner := player_pos - partner_pos
	if from_partner.length_squared() <= 0.000001:
		return _orbit_desired_velocity()
	# Move to the opposite side of the player from our partner so the beam segment crosses through them
	var aim_pos := player_pos + from_partner.normalized() * (preferred_range * 1.45)
	var to_aim := aim_pos - global_position
	if to_aim.length_squared() <= 0.000001:
		return Vector2.ZERO
	return to_aim.normalized() * move_speed * 1.1 * slow_speed_mult

func _orbit_desired_velocity() -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	if to_target.length_squared() <= 0.000001:
		return Vector2.ZERO
	var dir := to_target.normalized()
	var tangent := Vector2(-dir.y, dir.x) * _orbit_sign
	var dist := to_target.length()
	if dist < preferred_range - range_tolerance:
		return (-dir + tangent * 0.48).normalized() * move_speed * 0.72
	if dist > preferred_range + range_tolerance:
		return (dir + tangent * 0.34).normalized() * move_speed
	return tangent * move_speed * 0.9

func _enter_windup_state() -> void:
	_clear_beam_history()
	if not _is_primary_pair():
		return
	_beam_partner_instance_id = beam_partner.get_instance_id()
	_beam_room_id = EnemyReplicationService._current_room_sync_id()
	_beam_room_bounds = EnemyReplicationService.get_current_room_bounds()
	tether_state = STATE_WINDUP
	state_time_left = beam_windup_time
	velocity = Vector2.ZERO
	queue_redraw()

func _process_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
	if not _committed_partner_valid():
		_enter_recover_state()
		return
	state_time_left = maxf(0.0, state_time_left - delta)
	queue_redraw()
	if state_time_left <= 0.0:
		_enter_beam_state()

func _enter_beam_state() -> void:
	if not _committed_partner_valid():
		_enter_recover_state()
		return
	tether_state = STATE_BEAM
	state_time_left = beam_duration
	beam_tick_left = 0.0
	_beam_player_positions.clear()
	_beam_pending_contacts.clear()
	for player in _get_beam_damageable_targets():
		_beam_player_positions[player.get_instance_id()] = player.global_position
		_beam_player_reset_generations[player.get_instance_id()] = int(player.get_meta("combat_position_reset_generation", 0))
	_last_beam_sample_a = global_position
	_last_beam_sample_b = beam_partner.global_position
	_has_last_beam_sample_segment = true
	queue_redraw()

func _process_beam(delta: float) -> void:
	if not network_simulation_enabled or not is_finite(delta) or delta <= 0.0:
		return
	if not _committed_partner_valid() or state_time_left <= 0.0:
		_enter_recover_state()
		return
	var previous_life := state_time_left
	var previous_tick := beam_tick_left
	var active_delta := minf(delta, previous_life)
	var active_fraction := active_delta / delta
	velocity = velocity.move_toward(_beam_aim_velocity(), acceleration * active_delta)
	# move_and_slide uses the full physics step. Scale only its last movement
	# so the segment stops when this beam's actual lifetime ends.
	velocity *= active_fraction
	move_and_slide()
	velocity /= active_fraction
	_sample_beam_contacts(active_fraction)
	state_time_left = maxf(0.0, previous_life - delta)
	beam_tick_left = maxf(0.0, previous_tick - active_delta)
	if beam_tick_left <= 0.0 and previous_life > maxf(0.0, previous_tick):
		beam_tick_left = beam_tick_interval
		_try_apply_beam_damage()
		if is_queued_for_deletion() or not _committed_partner_valid():
			return
	queue_redraw()
	if state_time_left <= 0.0:
		_enter_recover_state()

func _try_apply_beam_damage() -> void:
	if not network_simulation_enabled or tether_state != STATE_BEAM or not _committed_partner_valid():
		return
	var generation := _beam_generation
	var contacts := _beam_pending_contacts.duplicate()
	_beam_pending_contacts.clear()
	for player in _get_beam_damageable_targets():
		if not contacts.has(player.get_instance_id()):
			continue
		if not _committed_partner_valid() or is_queued_for_deletion() or _beam_generation != generation:
			return
		if DAMAGEABLE.apply_damage(player, beam_damage, {"source": "enemy_ability", "ability": "tether_beam_tick"}):
			attack_anim_time_left = attack_anim_duration

func _sample_beam_contacts(active_fraction: float = 1.0) -> void:
	if not network_simulation_enabled or not _committed_partner_valid():
		return
	var current_a := global_position
	var current_b := beam_partner.global_position
	# Our endpoint has already been clipped by movement above. The partner and
	# players may have advanced the full frame, so clip their final samples too.
	var sampled_b := _last_beam_sample_b.lerp(current_b, active_fraction) if _has_last_beam_sample_segment else current_b
	var sweep_bounds := Rect2(current_a, Vector2.ZERO).expand(sampled_b).expand(_last_beam_sample_a).expand(_last_beam_sample_b).grow(beam_thickness)
	var current_ids: Dictionary = {}
	for player in _get_beam_damageable_targets():
		var id := player.get_instance_id()
		current_ids[id] = true
		var current_position := player.global_position
		var previous_position: Vector2 = _beam_player_positions.get(id, current_position)
		var reset_generation := int(player.get_meta("combat_position_reset_generation", 0))
		var has_history := _beam_player_positions.has(id) and reset_generation == int(_beam_player_reset_generations.get(id, reset_generation))
		if not has_history:
			previous_position = current_position
			_beam_pending_contacts.erase(id)
		var sampled_position := previous_position.lerp(current_position, active_fraction)
		var distance := _distance_to_segment(sampled_position, current_a, sampled_b)
		var player_bounds := Rect2(previous_position, Vector2.ZERO).expand(sampled_position)
		var possible_crossing := player_bounds.position.x <= sweep_bounds.end.x and player_bounds.end.x >= sweep_bounds.position.x and player_bounds.position.y <= sweep_bounds.end.y and player_bounds.end.y >= sweep_bounds.position.y
		if possible_crossing and _has_last_beam_sample_segment and has_history:
			distance = minf(distance, _moving_beam_sweep_nearest_distance(previous_position, sampled_position, _last_beam_sample_a, _last_beam_sample_b, current_a, sampled_b))
		if distance <= beam_thickness:
			_beam_pending_contacts[id] = true
		_beam_player_positions[id] = current_position
		_beam_player_reset_generations[id] = reset_generation
	for id in _beam_player_positions.keys():
		if not current_ids.has(id):
			_beam_player_positions.erase(id)
			_beam_player_reset_generations.erase(id)
			_beam_pending_contacts.erase(id)
	_last_beam_sample_a = current_a
	_last_beam_sample_b = sampled_b
	_has_last_beam_sample_segment = true

func _get_beam_damageable_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for candidate in target_candidates:
		if candidate is Node2D and _is_beam_target_valid(candidate) and not result.has(candidate):
			result.append(candidate)
	if result.is_empty() and _is_beam_target_valid(target):
		result.append(target)
	return result

func _is_beam_target_valid(candidate: Variant) -> bool:
	if not _is_target_valid(candidate):
		return false
	var candidate_node := candidate as Node2D
	if candidate_node.is_queued_for_deletion():
		return false
	var player := candidate_node as PLAYER_SCRIPT
	return player == null or not player._combat_removed

func _clear_beam_history() -> void:
	_beam_generation += 1
	_beam_player_positions.clear()
	_beam_player_reset_generations.clear()
	_beam_pending_contacts.clear()
	_beam_partner_instance_id = 0
	_has_last_beam_sample_segment = false

func _distance_to_segment(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var closest := Geometry2D.get_closest_point_to_segment(point, seg_a, seg_b)
	return closest.distance_to(point)

func _segment_to_segment_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	var nearest := _distance_to_segment(a0, b0, b1)
	nearest = minf(nearest, _distance_to_segment(a1, b0, b1))
	nearest = minf(nearest, _distance_to_segment(b0, a0, a1))
	nearest = minf(nearest, _distance_to_segment(b1, a0, a1))
	return nearest

func _moving_beam_sweep_nearest_distance(player_from: Vector2, player_to: Vector2, beam_prev_a: Vector2, beam_prev_b: Vector2, beam_current_a: Vector2, beam_current_b: Vector2) -> float:
	# In endpoint A's moving frame the player q(t) and beam c(t) are linear.
	# Endpoint-distance extrema are linear roots. Interior distance squared is
	# cross(q,c)^2 / dot(c,c); its remaining extrema are quadratic/cubic roots.
	# This compares simultaneous positions and has no sampling cap that can
	# miss a thin beam during a fast dash or a long frame.
	var q := player_from - beam_prev_a
	var dq := (player_to - beam_current_a) - q
	var c := beam_prev_b - beam_prev_a
	var dc := (beam_current_b - beam_current_a) - c
	if dc.length_squared() <= 0.00000001:
		return _segment_to_segment_distance(q, q + dq, Vector2.ZERO, c)
	var candidates: Array[float] = [0.0, 1.0]
	if dq.length_squared() > 0.00000001:
		candidates.append(clampf(-q.dot(dq) / dq.length_squared(), 0.0, 1.0))
	var qb := q - c
	var dqb := dq - dc
	if dqb.length_squared() > 0.00000001:
		candidates.append(clampf(-qb.dot(dqb) / dqb.length_squared(), 0.0, 1.0))
	var cross_0 := q.cross(c)
	var cross_1 := q.cross(dc) + dq.cross(c)
	var cross_2 := dq.cross(dc)
	var length_0 := c.length_squared()
	var length_1 := 2.0 * c.dot(dc)
	var length_2 := dc.length_squared()
	candidates.append_array(_unit_polynomial_roots([cross_0, cross_1, cross_2]))
	candidates.append_array(_unit_polynomial_roots([
		2.0 * cross_1 * length_0 - cross_0 * length_1,
		cross_1 * length_1 + 4.0 * cross_2 * length_0 - 2.0 * cross_0 * length_2,
		3.0 * cross_2 * length_1,
		2.0 * cross_2 * length_2,
	]))
	if length_2 > 0.00000001:
		candidates.append(clampf(-c.dot(dc) / length_2, 0.0, 1.0))
	var nearest := INF
	for t in candidates:
		nearest = minf(nearest, _distance_to_segment(q + dq * t, Vector2.ZERO, c + dc * t))
	return nearest

func _unit_polynomial_roots(coefficients: Array[float]) -> Array[float]:
	var scale := 0.0
	for coefficient in coefficients:
		scale = maxf(scale, absf(coefficient))
	if scale <= 0.000000000001:
		return []
	var values: Array[float] = coefficients.duplicate()
	for index in range(values.size()):
		values[index] /= scale
	while values.size() > 1 and absf(values[-1]) < 0.000000000001:
		values.pop_back()
	if values.size() <= 1:
		return []
	if values.size() == 2:
		var linear_root := -values[0] / values[1]
		var roots: Array[float] = []
		if linear_root >= 0.0 and linear_root <= 1.0:
			roots.append(linear_root)
		return roots
	var derivative: Array[float] = []
	for index in range(1, values.size()):
		derivative.append(float(index) * values[index])
	var boundaries: Array[float] = [0.0]
	boundaries.append_array(_unit_polynomial_roots(derivative))
	boundaries.append(1.0)
	boundaries.sort()
	var roots: Array[float] = []
	for point in boundaries:
		if absf(_polynomial_value(values, point)) < 0.000000001:
			roots.append(point)
	for index in range(boundaries.size() - 1):
		var left := boundaries[index]
		var right := boundaries[index + 1]
		var left_value := _polynomial_value(values, left)
		if left_value * _polynomial_value(values, right) >= 0.0:
			continue
		for _iteration in range(36):
			var midpoint := (left + right) * 0.5
			if left_value * _polynomial_value(values, midpoint) <= 0.0:
				right = midpoint
			else:
				left = midpoint
		roots.append((left + right) * 0.5)
	return roots

func _polynomial_value(coefficients: Array[float], point: float) -> float:
	var result := 0.0
	for index in range(coefficients.size() - 1, -1, -1):
		result = result * point + coefficients[index]
	return result

func _enter_recover_state() -> void:
	tether_state = STATE_RECOVER
	state_time_left = recover_time
	beam_cooldown_left = beam_cooldown
	_clear_beam_history()

func _process_recover(delta: float) -> void:
	velocity = velocity.move_toward(_orbit_desired_velocity() * 0.4 * slow_speed_mult, deceleration * delta)
	move_and_slide()
	queue_redraw()
	state_time_left = maxf(0.0, state_time_left - delta)
	if state_time_left <= 0.0:
		tether_state = STATE_STALK

func get_beam_geometry() -> Dictionary:
	if tether_state not in [STATE_WINDUP, STATE_BEAM] or state_time_left <= 0.0:
		return {}
	if network_simulation_enabled:
		if not _committed_partner_valid():
			return {}
		return {"a": global_position, "b": beam_partner.global_position, "radius": beam_thickness, "phase": tether_state}
	if _beam_visual_lease <= 0.0 or not _is_valid_tether_partner(beam_partner):
		return {}
	return {"a": _beam_visual_a, "b": _beam_visual_b, "radius": _beam_visual_radius, "phase": tether_state}

func get_beam_polygons() -> Array[PackedVector2Array]:
	var geometry := get_beam_geometry()
	if geometry.is_empty():
		return []
	return Geometry2D.offset_polyline(PackedVector2Array([geometry["a"], geometry["b"]]), float(geometry["radius"]), Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)

func _build_beam_network_state() -> Array:
	_beam_wire_sequence += 1
	var partner_id := int(beam_partner.get_meta("network_enemy_id", -1)) if _is_valid_tether_partner(beam_partner) else -1
	var geometry := get_beam_geometry()
	var phase := tether_state
	if phase in [STATE_WINDUP, STATE_BEAM] and geometry.is_empty():
		phase = STATE_RECOVER
	var state: Array = [_beam_wire_sequence, EnemyReplicationService._current_room_sync_id(), phase, int(round(state_time_left * 1000.0)), int(round(beam_cooldown_left * 1000.0)), partner_id]
	if not geometry.is_empty():
		# Packed vectors bypass the generic runtime snapshot's 0.5px rounding.
		state.append(PackedVector2Array([geometry["a"], geometry["b"]]))
		state.append(int(round(float(geometry["radius"]) * 1000.0)))
	return state

func _apply_beam_network_state(value: Variant) -> bool:
	if network_simulation_enabled or not (value is Array):
		return false
	var state: Array = value
	if state.size() not in [6, 8]:
		return false
	for index in range(6):
		if not (state[index] is int):
			return false
	var incoming_phase: int = state[2]
	if state[0] <= _beam_received_sequence or state[1] != EnemyReplicationService._current_room_sync_id() or incoming_phase < STATE_STALK or incoming_phase > STATE_RECOVER or state[3] < 0 or state[4] < 0:
		return false
	var active := incoming_phase in [STATE_WINDUP, STATE_BEAM]
	if active:
		if state.size() != 8 or not (state[6] is PackedVector2Array) or not (state[7] is int) or state[7] <= 0:
			return false
		var endpoints: PackedVector2Array = state[6]
		if endpoints.size() != 2 or not endpoints[0].is_finite() or not endpoints[1].is_finite():
			return false
		_beam_visual_a = endpoints[0]
		_beam_visual_b = endpoints[1]
		_beam_visual_radius = float(state[7]) * 0.001
	elif state.size() != 6:
		return false
	# Both channels use this one sequence gate. Neither can resurrect a newer
	# cancellation or an expired warning with an old runtime snapshot.
	_beam_received_sequence = state[0]
	tether_state = incoming_phase
	state_time_left = float(state[3]) * 0.001
	beam_cooldown_left = float(state[4]) * 0.001
	beam_partner = _resolve_partner_by_network_enemy_id(state[5])
	_beam_visual_lease = BEAM_VISUAL_LEASE if active else 0.0
	queue_redraw()
	return true

func _draw() -> void:
	var attack_pulse := _get_attack_pulse()
	var speed_t := clampf(velocity.length() / maxf(1.0, move_speed), 0.0, 1.0)
	var body_radius := 14.0 + attack_pulse + speed_t * 0.7
	var facing := visual_facing_direction if visual_facing_direction.length_squared() > 0.000001 else Vector2.LEFT
	var side := Vector2(-facing.y, facing.x)
	var body_color := Color(0.3, 0.42, 0.92, 0.94)
	var core_color := Color(0.86, 0.92, 1.0, 0.94)
	var state_charge := 0.0
	var beam_geometry := get_beam_geometry()
	var beam_link_active := not beam_geometry.is_empty() and tether_state == STATE_BEAM
	if tether_state == STATE_WINDUP:
		body_color = Color(0.4, 0.58, 1.0, 0.96)
		core_color = Color(1.0, 1.0, 1.0, 0.96)
		state_charge = 1.0 - clampf(state_time_left / maxf(0.001, beam_windup_time), 0.0, 1.0)
	elif beam_link_active:
		body_color = Color(0.22, 0.9, 0.96, 0.96)
		core_color = Color(0.94, 1.0, 1.0, 0.98)
		state_charge = 1.0
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
	var spin := float(Time.get_ticks_msec()) * 0.0011
	var has_partner := is_instance_valid(beam_partner)
	var link_factor := 0.0
	if has_partner:
		link_factor = 0.4
	if beam_link_active:
		link_factor = 1.0

	draw_circle(Vector2.ZERO, body_radius + 10.0, Color(body_color.r, body_color.g + 0.08, 1.0, 0.08 + pulse * 0.06 + link_factor * 0.1))
	draw_circle(Vector2.ZERO, body_radius + 6.2, Color(body_color.r, body_color.g, body_color.b, 0.11 + link_factor * 0.12))

	var shell := PackedVector2Array()
	var shell_points := 12
	for i in range(shell_points):
		var angle := float(i) / float(shell_points) * TAU
		var modulation := 1.2 if (i % 2) == 0 else -1.5
		var ripple := sin(angle * 3.0 + spin * 1.7) * 0.6
		var radius := body_radius + modulation + ripple
		shell.append(Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(shell, Color(body_color.r * 0.86, body_color.g * 0.9, body_color.b, 0.88))
	var closed_shell := shell.duplicate()
	closed_shell.append(shell[0])
	draw_polyline(closed_shell, Color(core_color.r, core_color.g, core_color.b, 0.84), 2.0, false)

	var core_pos := facing * 1.4
	draw_circle(core_pos, body_radius * 0.58, Color(core_color.r, core_color.g, core_color.b, 0.62 + state_charge * 0.2))
	draw_circle(core_pos, body_radius * 0.32 + pulse * 0.8, Color(1.0, 1.0, 1.0, 0.34 + link_factor * 0.22))

	for rune_i in range(3):
		var rune_angle := spin + float(rune_i) * TAU / 3.0
		var rune_dir := Vector2(cos(rune_angle), sin(rune_angle))
		var rune_a := rune_dir * (body_radius * 0.36)
		var rune_b := rune_dir * (body_radius + 3.0 + state_charge * 2.0)
		draw_line(rune_a, rune_b, Color(0.62, 0.94, 1.0, 0.64 + link_factor * 0.2), 1.9)

	var anchor_offset := 6.4 + state_charge * 1.2
	var anchor_alpha := 0.76 + link_factor * 0.2
	draw_circle(side * anchor_offset, 3.1, Color(0.68, 0.94, 1.0, anchor_alpha))
	draw_circle(-side * anchor_offset, 3.1, Color(0.68, 0.94, 1.0, anchor_alpha))
	draw_circle(side * anchor_offset, 1.5, Color(1.0, 1.0, 1.0, 0.72))
	draw_circle(-side * anchor_offset, 1.5, Color(1.0, 1.0, 1.0, 0.72))
	draw_line(side * (anchor_offset - 1.8), facing * 3.6, Color(0.62, 0.9, 1.0, 0.6), 1.4)
	draw_line(-side * (anchor_offset - 1.8), facing * 3.6, Color(0.62, 0.9, 1.0, 0.6), 1.4)

	draw_line(facing * (body_radius + 1.0), facing * (body_radius + 8.8), Color(0.86, 0.98, 1.0, 0.84), 1.9)
	draw_line(side * 4.7, side * 8.2 + facing * 3.9, Color(0.58, 0.9, 1.0, 0.74), 1.6)
	draw_line(-side * 4.7, -side * 8.2 + facing * 3.9, Color(0.58, 0.9, 1.0, 0.74), 1.6)

	if not beam_geometry.is_empty():
		var beam_start := to_local(beam_geometry["a"])
		var beam_end := to_local(beam_geometry["b"])
		var warning := tether_state == STATE_WINDUP
		for polygon in get_beam_polygons():
			var local_polygon := PackedVector2Array()
			for point in polygon:
				local_polygon.append(to_local(point))
			draw_colored_polygon(local_polygon, Color(0.46, 0.94, 1.0, 0.10 if warning else 0.18))
			local_polygon.append(local_polygon[0])
			draw_polyline(local_polygon, Color(0.66, 0.96, 1.0, 0.48 if warning else 0.72), 1.2, true)
		var width := 2.2 if warning else clampf(beam_thickness * 0.48, 3.6, 14.0)
		draw_line(beam_start, beam_end, Color(0.46, 0.94, 1.0, 0.46 if warning else 0.9), width, true)
		if not warning:
			draw_line(beam_start, beam_end, Color(0.92, 1.0, 1.0, 0.52), maxf(1.8, width * 0.34), true)
	elif _is_valid_tether_partner(beam_partner):
		var partner_local := to_local(beam_partner.global_position)
		var alpha := 0.22
		var width := 1.6
		var partner_facing_dir := beam_partner.get("visual_facing_direction") as Vector2
		if partner_facing_dir == null or partner_facing_dir.length_squared() <= 0.000001:
			partner_facing_dir = Vector2.LEFT
		var partner_side := Vector2(-partner_facing_dir.y, partner_facing_dir.x)
		var partner_anchor_plus := partner_local + partner_side * anchor_offset
		var partner_anchor_minus := partner_local - partner_side * anchor_offset
		draw_line(Vector2.ZERO, partner_local, Color(0.46, 0.94, 1.0, alpha), width)
		draw_line(side * anchor_offset, partner_anchor_plus, Color(0.66, 0.96, 1.0, alpha * 0.35), 1.2)
		draw_line(-side * anchor_offset, partner_anchor_minus, Color(0.66, 0.96, 1.0, alpha * 0.35), 1.2)
	_draw_slow_indicator(body_radius)

func _get_custom_network_runtime_state() -> Dictionary:
	return {"beam": _build_beam_network_state()} if network_simulation_enabled else {}

func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	_apply_beam_network_state(custom_state.get("beam"))

func _resolve_partner_by_network_enemy_id(partner_enemy_id: int) -> ENEMY_BASE_SCRIPT:
	if partner_enemy_id <= 0:
		return null
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var enemy_body := enemy as ENEMY_BASE_SCRIPT
		if enemy_body == null:
			continue
		if enemy_body == self:
			continue
		if int(enemy_body.get_meta("network_enemy_id", -1)) != partner_enemy_id:
			continue
		return enemy_body
	return null
