extends "res://scripts/enemy_base.gd"
## Alternate the ram's sidestep with a shore-to-shore Harbor Gate: stop in a
## committed opening as the seawall passes. Terrain still breaks Return Tide.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const ARENA_BOUNDARY := preload("res://scripts/shared/arena_boundary.gd")
const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")
const TRACK_TIME := 0.35
const LOCK_TIME := 0.55
const CHARGE_SPEED := 640.0
const CHARGE_DISTANCE := 760.0
const CHARGE_MIN_DISTANCE := 280.0
const CHARGE_OVERRUN := 180.0
const WALL_RECOVERY := 1.8
const MISS_RECOVERY := 0.55
const BODY_RADIUS := 30.0
const PATH_RADIUS := 38.0
const SEEK_SPEED := 106.0
const EDGE_RESET_MARGIN := 115.0
const REMOTE_LEASE := 0.35
const IMPACT_DURATION := 0.22
const BACKWASH_TIME := 1.8
const TIDE_SPEED := 310.0
const TIDE_HALF_DEPTH := 24.0
const TIDE_HALF_WIDTH := 230.0
const TIDE_WAKE_HALF_WIDTH := 32.0
const TIDE_EDGE_INSET := 24.0
const TIDE_RECOVERY := 1.1
const TIDE_CURVE_SEGMENTS := 16
const TIDE_CURVE_DEPTH := 34.0
const GATE_WARNING := 1.2
const GATE_SPEED := 370.0
const GATE_HALF_DEPTH := 24.0
const GATE_HALF_GAP := 56.0
const GATE_RECOVERY := 1.1
const GATE_BRACE_SPEED := 190.0
const GATE_BRACE_CLEARANCE := 96.0
const ATTACK_CALLOUT := preload("res://scripts/shared/enemy_attack_callout.gd")
enum Phase { SEEK, TRACK, LOCK, CHARGE, RECOVER, BACKWASH, TIDE, GATE_BRACE, GATE }

@export var max_health_apex: int = 900
@export var charge_damage: int = 16
@export var attack_cooldown: float = 1.5

var phase: Phase = Phase.SEEK
var phase_left := 0.8
var charge_origin := Vector2.ZERO
var charge_end := Vector2.ZERO
var charge_direction := Vector2.RIGHT
var wall_recovery := false
var _forecast_hits_wall := false
var _charge_bounds := Rect2()
var _hit_players: Dictionary = {}
var _exceptions: Dictionary = {}
var _attack_generation := 0
var _wire_sequence := 0
var _received_sequence := -1
var _remote_lease := 0.0
var _impact_left := 0.0
var _impact_position := Vector2.ZERO
var _reset_inward := false
var _reset_left := 0.0
var _backwash_pending := false
var _backwash_center := Vector2.ZERO
var _tide_origin := Vector2.ZERO
var _tide_direction := Vector2.LEFT
var _tide_bounds := Rect2()
var _tide_distance := 0.0
var _tide_progress := 0.0
var _gate_next := false
var _gate_origin := Vector2.ZERO
var _gate_direction := Vector2.RIGHT
var _gate_bounds := Rect2()
var _gate_distance := 0.0
var _gate_progress := 0.0
var _gate_brace_position := Vector2.ZERO
var _gate_gaps := PackedVector2Array()
var _gate_player_positions: Dictionary = {}
var _gate_player_resets: Dictionary = {}
var _body_shape := CircleShape2D.new()
var _sound: AudioStreamPlayer
var _sound_left := 0.0
static var _surge_sound: AudioStreamWAV
static var _impact_sound: AudioStreamWAV

func _ready() -> void:
	max_health = max_health_apex
	crowd_separation_strength = 0.0
	_body_shape.radius = BODY_RADIUS
	for owner_id in get_shape_owners():
		for index in range(shape_owner_get_shape_count(owner_id)):
			var shape := shape_owner_get_shape(owner_id, index)
			if shape is CircleShape2D:
				(shape as CircleShape2D).radius = BODY_RADIUS
	health_bar_size = Vector2(92.0, 8.0)
	health_bar_offset = Vector2(-46.0, -49.0)
	super._ready()
	if DisplayServer.get_name() != "headless":
		_sound = AudioStreamPlayer.new()
		_sound.stream = _make_sound()
		_sound.volume_db = -19.0
		if AudioServer.get_bus_index("SFX") >= 0:
			_sound.bus = &"SFX"
		add_child(_sound)

func _exit_tree() -> void:
	_clear_exceptions()

func _on_health_state_died() -> void:
	_cancel_attack()
	super._on_health_state_died()

func set_network_simulation_enabled(enabled: bool) -> void:
	if enabled != network_simulation_enabled:
		_cancel_attack()
		_received_sequence = -1
		_remote_lease = 0.0
	super.set_network_simulation_enabled(enabled)

func _is_in_priority_attack_state() -> bool:
	return phase != Phase.SEEK or _impact_left > 0.0

func _process_behavior(delta: float) -> void:
	if not network_simulation_enabled or not is_finite(delta) or delta <= 0.0 or is_dead():
		return
	_impact_left = maxf(0.0, _impact_left - delta)
	_sound_left = maxf(0.0, _sound_left - delta)
	if phase in [Phase.LOCK, Phase.CHARGE, Phase.BACKWASH, Phase.TIDE, Phase.GATE_BRACE, Phase.GATE] and EnemyReplicationService.get_current_room_bounds() != _charge_bounds:
		_cancel_attack() # Forced bounds changes are not traveled attack segments.
		return
	if (phase in [Phase.BACKWASH, Phase.TIDE, Phase.GATE_BRACE, Phase.GATE] or (phase == Phase.RECOVER and _backwash_pending)) and _living_players().is_empty():
		_cancel_attack()
		return
	match phase:
		Phase.SEEK:
			_process_seek(delta)
		Phase.TRACK:
			velocity = Vector2.ZERO
			if _acquisition_target() == null:
				_cancel_attack()
				return
			_aim_forecast()
			phase_left = maxf(0.0, phase_left - delta)
			if phase_left <= 0.0:
				_lock_charge()
		Phase.LOCK:
			velocity = Vector2.ZERO
			phase_left = maxf(0.0, phase_left - delta)
			if phase_left <= 0.0:
				_begin_charge()
		Phase.CHARGE:
			_process_charge(delta)
		Phase.RECOVER:
			velocity = Vector2.ZERO
			phase_left = maxf(0.0, phase_left - delta)
			if phase_left <= 0.0:
				if _backwash_pending:
					_begin_backwash()
					return
				phase = Phase.SEEK
				phase_left = maxf(0.1, attack_cooldown)
				_reset_inward = wall_recovery
				_reset_left = 1.5
		Phase.TIDE:
			_process_tide(delta)
		Phase.GATE_BRACE:
			_step_gate_brace(delta)
			phase_left = maxf(0.0, phase_left - delta)
			if phase_left <= 0.0:
				_release_harbor_gate()
		Phase.GATE:
			_process_harbor_gate(delta)
		Phase.BACKWASH:
			velocity = Vector2.ZERO
			phase_left = maxf(0.0, phase_left - delta)
			if phase_left <= 0.0:
				_resolve_backwash()
	queue_redraw()

func _living_players() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var candidates: Array = get_tree().get_nodes_in_group("combat_players")
	if candidates.is_empty():
		candidates.append_array(target_candidates)
		if is_instance_valid(target):
			candidates.append(target)
	for value in candidates:
		if not is_instance_valid(value) or not (value is Node2D):
			continue
		var candidate := value as Node2D
		if not candidate.is_inside_tree() or candidate.is_queued_for_deletion() or DAMAGEABLE._read_target_health(candidate) <= 0:
			continue
		if candidate is PLAYER_SCRIPT and (candidate as PLAYER_SCRIPT)._combat_removed:
			continue
		if not result.has(candidate):
			result.append(candidate)
	return result

func _process_seek(delta: float) -> void:
	var selected := _acquisition_target()
	if selected == null:
		velocity = Vector2.ZERO
		return # Encounter survey intentionally clears the assigned targets.
	phase_left = maxf(0.0, phase_left - delta)
	_reset_left = maxf(0.0, _reset_left - delta)
	if _reset_left <= 0.0:
		_reset_inward = false # Co-op body blocking cannot stall a fight forever.
	var destination := global_position
	var bounds := EnemyReplicationService.get_current_room_bounds()
	if _reset_inward and bounds.has_area():
		var inner := bounds.grow(-EDGE_RESET_MARGIN)
		destination = Vector2(clampf(global_position.x, inner.position.x, inner.end.x), clampf(global_position.y, inner.position.y, inner.end.y))
		if destination.distance_to(global_position) <= 5.0:
			_reset_inward = false
	else:
		var offset := selected.global_position - global_position
		if offset.length() > 260.0:
			destination = selected.global_position - offset.normalized() * 240.0
		elif offset.length() < 150.0:
			destination = global_position - offset.normalized() * 70.0
		if bounds.has_area():
			var inner := bounds.grow(-BODY_RADIUS)
			destination = Vector2(clampf(destination.x, inner.position.x, inner.end.x), clampf(destination.y, inner.position.y, inner.end.y))
	var displacement := (destination - global_position).limit_length(SEEK_SPEED * delta)
	velocity = displacement / maxf(delta, 0.0001)
	move_and_collide(displacement)
	if not _reset_inward and phase_left <= 0.0:
		if _gate_next:
			_begin_harbor_gate()
		else:
			_begin_tracking()

func _begin_tracking() -> void:
	if _acquisition_target() == null:
		return
	_clear_exceptions()
	_attack_generation += 1
	phase = Phase.TRACK
	_gate_next = true
	phase_left = TRACK_TIME
	velocity = Vector2.ZERO
	wall_recovery = false
	_backwash_pending = false
	charge_origin = global_position
	_hit_players.clear()
	_aim_forecast()
	queue_redraw()

func _aim_forecast() -> void:
	var selected := _acquisition_target()
	var planned_distance := CHARGE_MIN_DISTANCE
	if selected != null:
		var offset := selected.global_position - charge_origin
		planned_distance = clampf(offset.length() + CHARGE_OVERRUN, CHARGE_MIN_DISTANCE, CHARGE_DISTANCE)
		if offset.length_squared() > 0.001:
			charge_direction = offset.normalized()
	visual_facing_direction = charge_direction
	var contact := _terrain_sweep(charge_origin, charge_direction * planned_distance)
	charge_end = contact.get("position", charge_origin + charge_direction * planned_distance)
	_forecast_hits_wall = not contact.is_empty()

func _acquisition_target() -> Node2D:
	var living := _living_players()
	if living.has(target):
		return target
	for candidate in target_candidates:
		if living.has(candidate):
			return candidate
	return null

func _endpoint_still_blocked() -> bool:
	# A destructible blocker can vanish after commitment. Keep the locked endpoint,
	# but award terrain recovery only if terrain still exists at that endpoint.
	if not _forecast_hits_wall:
		return false
	var contact := _terrain_sweep(global_position, charge_direction * 2.0)
	return not contact.is_empty() and global_position.distance_to(contact["position"]) <= 0.05

func _lock_charge() -> void:
	phase = Phase.LOCK
	phase_left = LOCK_TIME
	_charge_bounds = EnemyReplicationService.get_current_room_bounds()
	_play_sound(1.55)
	queue_redraw()

func _begin_charge() -> void:
	phase = Phase.CHARGE
	phase_left = charge_origin.distance_to(charge_end) / CHARGE_SPEED
	_sync_exceptions()
	_play_sound(0.95)
	queue_redraw()

func _process_charge(delta: float) -> void:
	_sync_exceptions()
	var distance_left := maxf(0.0, (charge_end - global_position).dot(charge_direction))
	if distance_left <= 0.01:
		_apply_charge_hits(global_position, global_position)
		if phase != Phase.CHARGE or is_queued_for_deletion():
			return
		_enter_recovery(_endpoint_still_blocked())
		return
	var start := global_position
	var travel := charge_direction * minf(distance_left, CHARGE_SPEED * delta)
	var boundary := ARENA_BOUNDARY.sweep(start, travel, EnemyReplicationService.get_current_room_bounds())
	if bool(boundary.get("outside", false)):
		global_position = boundary["position"]
		_cancel_attack()
		return
	var collision := move_and_collide(travel * float(boundary.get("fraction", 1.0)))
	velocity = charge_direction * CHARGE_SPEED
	_apply_charge_hits(start, global_position)
	if phase != Phase.CHARGE or is_queued_for_deletion():
		return
	phase_left = maxf(0.0, (charge_end - global_position).dot(charge_direction)) / CHARGE_SPEED
	if collision != null or not boundary.is_empty():
		_enter_recovery(true)
	elif phase_left <= 0.0001:
		_enter_recovery(_endpoint_still_blocked())

func _apply_charge_hits(start: Vector2, finish: Vector2) -> void:
	if not network_simulation_enabled or phase != Phase.CHARGE:
		return
	var generation := _attack_generation
	for candidate in _living_players():
		var peer_value: Variant = candidate.get("player_id")
		var key: int = int(peer_value) if peer_value is int and int(peer_value) > 0 else candidate.get_instance_id()
		if _hit_players.has(key):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(candidate.global_position, start, finish)
		if closest.distance_squared_to(candidate.global_position) > PATH_RADIUS * PATH_RADIUS:
			continue
		_hit_players[key] = true
		DAMAGEABLE.apply_damage(candidate, charge_damage, {"source": "enemy_contact", "ability": "breakwater_charge", "attack_origin": start})
		if generation != _attack_generation or is_queued_for_deletion():
			return

func _terrain_sweep(start: Vector2, motion: Vector2) -> Dictionary:
	var bounds_hit := ARENA_BOUNDARY.sweep(start, motion, EnemyReplicationService.get_current_room_bounds())
	var fraction := float(bounds_hit.get("fraction", 1.0))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _body_shape
	query.transform = Transform2D(0.0, start)
	query.motion = motion * fraction
	query.margin = safe_margin
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	var exclusions: Array[RID] = [get_rid()]
	for group in ["combat_players", "enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is CollisionObject2D:
				exclusions.append((node as CollisionObject2D).get_rid())
	query.exclude = exclusions
	var fractions := get_world_2d().direct_space_state.cast_motion(query)
	if fractions.size() >= 2 and fractions[0] < 1.0:
		# Godot's long shape cast brackets contact coarsely. Refine that bracket
		# so a thin blocker's warning endpoint also reaches its actual impact.
		var full_motion := query.motion
		var safe_fraction := fractions[0]
		var unsafe_fraction := fractions[1]
		for _index in range(3):
			var interval := unsafe_fraction - safe_fraction
			if interval * full_motion.length() <= 0.005:
				break
			query.transform.origin = start + full_motion * safe_fraction
			query.motion = full_motion * interval
			var refined := get_world_2d().direct_space_state.cast_motion(query)
			if refined.size() < 2 or refined[0] >= 1.0:
				break
			unsafe_fraction = safe_fraction + interval * refined[1]
			safe_fraction += interval * refined[0]
		return {"position": start + full_motion * safe_fraction, "fraction": fraction * safe_fraction}
	return bounds_hit

func _sync_exceptions() -> void:
	for group in ["combat_players", "enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			if node == self or not (node is PhysicsBody2D):
				continue
			var id: int = node.get_instance_id()
			if not _exceptions.has(id):
				add_collision_exception_with(node)
				_exceptions[id] = (node as PhysicsBody2D).get_rid()

func _clear_exceptions() -> void:
	for target_rid: RID in _exceptions.values():
		PhysicsServer2D.body_remove_collision_exception(get_rid(), target_rid)
	_exceptions.clear()

func _enter_recovery(hit_wall: bool, queue_backwash: bool = true) -> void:
	_clear_exceptions()
	phase = Phase.RECOVER
	wall_recovery = hit_wall
	_backwash_pending = not hit_wall and queue_backwash
	phase_left = WALL_RECOVERY if hit_wall else MISS_RECOVERY
	velocity = Vector2.ZERO
	if hit_wall:
		_impact_left = IMPACT_DURATION
		_impact_position = global_position
		_play_sound(0.60)
	queue_redraw()

func _begin_backwash() -> void:
	_backwash_pending = false
	if not network_simulation_enabled or _living_players().is_empty() or is_dead():
		_cancel_attack()
		return
	_attack_generation += 1
	_hit_players.clear()
	_backwash_center = global_position
	_charge_bounds = EnemyReplicationService.get_current_room_bounds()
	_tide_direction = -charge_direction.normalized()
	_tide_origin = global_position + _tide_direction * (BODY_RADIUS + TIDE_HALF_DEPTH + 12.0)
	_tide_bounds = _charge_bounds.grow(-TIDE_EDGE_INSET)
	_tide_distance = 0.0
	for corner in [_charge_bounds.position, Vector2(_charge_bounds.end.x, _charge_bounds.position.y), _charge_bounds.end, Vector2(_charge_bounds.position.x, _charge_bounds.end.y)]:
		_tide_distance = maxf(_tide_distance, (corner - _tide_origin).dot(_tide_direction) + TIDE_HALF_DEPTH)
	_tide_progress = 0.0
	phase = Phase.BACKWASH
	phase_left = BACKWASH_TIME
	velocity = Vector2.ZERO
	_play_sound(1.25)
	queue_redraw()

func _resolve_backwash() -> void:
	# The legacy enum/method name now denotes the brace warning. Its expiry
	# releases a moving crest; it never applies an instantaneous area hit.
	if not network_simulation_enabled or phase != Phase.BACKWASH or is_dead():
		return
	phase = Phase.TIDE
	phase_left = _tide_distance / TIDE_SPEED
	_tide_progress = 0.0
	velocity = Vector2.ZERO
	_play_sound(0.72)
	queue_redraw()

func _process_tide(delta: float) -> void:
	if not network_simulation_enabled or phase != Phase.TIDE or is_dead():
		return
	var previous := _tide_progress
	_tide_progress = minf(_tide_distance, _tide_progress + TIDE_SPEED * delta)
	var generation := _attack_generation
	_apply_tide_hits(previous, _tide_progress)
	if generation != _attack_generation or is_queued_for_deletion() or is_dead():
		return
	phase_left = maxf(0.0, _tide_distance - _tide_progress) / TIDE_SPEED
	if _tide_progress >= _tide_distance:
		_enter_recovery(false, false)
		phase_left = TIDE_RECOVERY
	queue_redraw()

func _apply_tide_hits(from_distance: float, to_distance: float) -> void:
	if not network_simulation_enabled or phase != Phase.TIDE:
		return
	var generation := _attack_generation
	for candidate in _living_players():
		if not tide_contains_point(candidate.global_position, from_distance, to_distance):
			continue
		var peer_value: Variant = candidate.get("player_id")
		var key: int = int(peer_value) if peer_value is int and int(peer_value) > 0 else candidate.get_instance_id()
		if _hit_players.has(key):
			continue
		# Contact classification preserves the normal Dash crossing answer.
		# One attempted crossing owns this wave's allowance even if Dash avoids it.
		_hit_players[key] = true
		DAMAGEABLE.apply_damage(candidate, charge_damage, {"source": "enemy_contact", "ability": "breakwater_tide", "attack_origin": _tide_origin})
		if generation != _attack_generation or is_queued_for_deletion() or is_dead():
			return

func tide_contains_point(point: Vector2, from_distance: float, to_distance: float) -> bool:
	if not _tide_bounds.has_point(point):
		return false
	var offset := point - _tide_origin
	var across := absf(offset.dot(_tide_direction.orthogonal()))
	var along := offset.dot(_tide_direction) - _tide_curve_offset(across)
	return across >= TIDE_WAKE_HALF_WIDTH and across <= TIDE_HALF_WIDTH and along >= from_distance - TIDE_HALF_DEPTH and along <= to_distance + TIDE_HALF_DEPTH

func _tide_polygons(from_distance: float, to_distance: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not _tide_bounds.has_area():
		return result
	var side := _tide_direction.orthogonal()
	var floor := PackedVector2Array([_tide_bounds.position, Vector2(_tide_bounds.end.x, _tide_bounds.position.y), _tide_bounds.end, Vector2(_tide_bounds.position.x, _tide_bounds.end.y)])
	for sign_value: float in [-1.0, 1.0]:
		var lobe := PackedVector2Array()
		for index in range(TIDE_CURVE_SEGMENTS + 1):
			var across := lerpf(TIDE_WAKE_HALF_WIDTH, TIDE_HALF_WIDTH, float(index) / TIDE_CURVE_SEGMENTS)
			lobe.append(_tide_origin + _tide_direction * (from_distance - TIDE_HALF_DEPTH + _tide_curve_offset(across)) + side * sign_value * across)
		for index in range(TIDE_CURVE_SEGMENTS, -1, -1):
			var across := lerpf(TIDE_WAKE_HALF_WIDTH, TIDE_HALF_WIDTH, float(index) / TIDE_CURVE_SEGMENTS)
			lobe.append(_tide_origin + _tide_direction * (to_distance + TIDE_HALF_DEPTH + _tide_curve_offset(across)) + side * sign_value * across)
		result.append_array(Geometry2D.intersect_polygons(lobe, floor))
	return result

func _tide_curve_offset(across: float) -> float:
	# Piecewise-linear curvature is shared with the published polygons, so
	# the curved front and the swept contact boundary agree exactly.
	var at := clampf((across - TIDE_WAKE_HALF_WIDTH) / (TIDE_HALF_WIDTH - TIDE_WAKE_HALF_WIDTH), 0.0, 1.0) * TIDE_CURVE_SEGMENTS
	var segment := mini(int(floor(at)), TIDE_CURVE_SEGMENTS - 1)
	var first := sin(PI * float(segment) / TIDE_CURVE_SEGMENTS)
	var second := sin(PI * float(segment + 1) / TIDE_CURVE_SEGMENTS)
	return lerpf(first, second, at - segment) * TIDE_CURVE_DEPTH

func _begin_harbor_gate() -> void:
	var selected := _acquisition_target()
	var bounds := EnemyReplicationService.get_current_room_bounds()
	if not network_simulation_enabled or selected == null or not bounds.has_area() or is_dead():
		_cancel_attack()
		return
	_clear_exceptions()
	_attack_generation += 1
	_gate_next = false
	_backwash_pending = false
	wall_recovery = false
	_reset_inward = false
	velocity = Vector2.ZERO
	_hit_players.clear()
	_charge_bounds = bounds
	_gate_bounds = bounds
	# The nearest shore arrives soon enough to challenge continuous circling.
	# All geometry, including each player's opening, commits before the warning.
	var focus := selected.global_position.clamp(bounds.position, bounds.end)
	var distances := [focus.x - bounds.position.x, bounds.end.x - focus.x, focus.y - bounds.position.y, bounds.end.y - focus.y]
	var directions := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
	var nearest := 0
	for index in range(1, 4):
		if distances[index] < distances[nearest]:
			nearest = index
	_gate_direction = directions[nearest]
	var along_extent := absf(_gate_direction.x) * bounds.size.x + absf(_gate_direction.y) * bounds.size.y
	_gate_origin = bounds.get_center() - _gate_direction * (along_extent * 0.5 + GATE_HALF_DEPTH)
	_gate_distance = along_extent + GATE_HALF_DEPTH * 2.0
	_gate_progress = 0.0
	var side := _gate_direction.orthogonal()
	var cross_extent := _gate_cross_extent()
	var openings: Array[float] = []
	for player in _living_players():
		openings.append(clampf((player.global_position - _gate_origin).dot(side), -cross_extent, cross_extent))
	openings.sort()
	_gate_gaps.clear()
	for center in openings:
		var gap := Vector2(maxf(-cross_extent, center - GATE_HALF_GAP), minf(cross_extent, center + GATE_HALF_GAP))
		if not _gate_gaps.is_empty() and gap.x <= _gate_gaps[-1].y:
			_gate_gaps[-1] = Vector2(_gate_gaps[-1].x, maxf(gap.y, _gate_gaps[-1].y))
		else:
			_gate_gaps.append(gap)
	phase = Phase.GATE_BRACE
	phase_left = GATE_WARNING
	_gate_brace_position = _choose_gate_brace_position()
	_play_sound(1.25)
	queue_redraw()

func _choose_gate_brace_position() -> Vector2:
	# Leave the calm opening's melee pocket during the tell. Chasing this
	# lateral, harmless brace step means leaving shelter before the crest passes.
	var side := _gate_direction.orthogonal()
	var cross := (global_position - _gate_origin).dot(side)
	var inner := _gate_bounds.grow(-BODY_RADIUS)
	var selected := global_position
	var best_score := INF
	for span in _gate_damage_spans():
		var pad := minf(GATE_BRACE_CLEARANCE, (span.y - span.x) * 0.5)
		var destination_cross := clampf(cross, span.x + pad, span.y - pad)
		var destination := (global_position + side * (destination_cross - cross)).clamp(inner.position, inner.end)
		var nearest_player := INF
		for player in _living_players():
			nearest_player = minf(nearest_player, destination.distance_to(player.global_position))
		var score := global_position.distance_to(destination) + maxf(0.0, 150.0 - nearest_player) * 4.0
		if score < best_score:
			best_score = score
			selected = destination
	return selected

func _step_gate_brace(delta: float) -> void:
	var motion := (_gate_brace_position - global_position).limit_length(GATE_BRACE_SPEED * minf(delta, phase_left))
	velocity = motion / maxf(delta, 0.0001)
	if move_and_collide(motion) != null:
		_gate_brace_position = global_position # A wall or player can pin the brace.
	velocity = Vector2.ZERO

func _release_harbor_gate() -> void:
	if not network_simulation_enabled or phase != Phase.GATE_BRACE or is_dead():
		return
	phase = Phase.GATE
	phase_left = _gate_distance / GATE_SPEED
	_gate_player_positions.clear()
	_gate_player_resets.clear()
	for player in _living_players():
		_gate_player_positions[player.get_instance_id()] = player.global_position
		_gate_player_resets[player.get_instance_id()] = int(player.get_meta("combat_position_reset_generation", 0))
	_play_sound(0.72)

func _process_harbor_gate(delta: float) -> void:
	var previous := _gate_progress
	_gate_progress = minf(_gate_distance, _gate_progress + GATE_SPEED * delta)
	var generation := _attack_generation
	var active_fraction := clampf((_gate_progress - previous) / maxf(0.0001, GATE_SPEED * delta), 0.0, 1.0)
	_apply_gate_hits(previous, _gate_progress, active_fraction)
	if generation != _attack_generation or is_dead():
		return
	phase_left = maxf(0.0, (_gate_distance - _gate_progress) / GATE_SPEED)
	if _gate_progress >= _gate_distance:
		_enter_recovery(false, false)
		phase_left = GATE_RECOVERY

func _apply_gate_hits(from_distance: float, to_distance: float, active_fraction: float = 1.0) -> void:
	if not network_simulation_enabled or phase != Phase.GATE or is_dead():
		return
	var generation := _attack_generation
	var positions := {}
	var resets := {}
	for player in _living_players():
		var id := player.get_instance_id()
		var reset := int(player.get_meta("combat_position_reset_generation", 0))
		var current := player.global_position
		var previous: Vector2 = _gate_player_positions.get(id, current) if _gate_player_resets.get(id, -1) == reset else current
		positions[id] = current
		resets[id] = reset
		var peer_value: Variant = player.get("player_id")
		var key: int = int(peer_value) if peer_value is int and int(peer_value) > 0 else player.get_instance_id()
		if _hit_players.has(key) or not _gate_crosses_path(previous, previous.lerp(current, active_fraction), from_distance, to_distance):
			continue
		_hit_players[key] = true
		DAMAGEABLE.apply_damage(player, charge_damage, {"source": "enemy_contact", "ability": "breakwater_gate", "attack_origin": _gate_origin})
		if generation != _attack_generation or is_dead():
			return
	_gate_player_positions = positions
	_gate_player_resets = resets

func _gate_crosses_path(start: Vector2, end: Vector2, from_distance: float, to_distance: float) -> bool:
	if not start.is_finite() or not end.is_finite():
		return false
	var time := Vector2(0.0, 1.0)
	time = _gate_clip_time(time, start.x, end.x, _gate_bounds.position.x, _gate_bounds.end.x)
	time = _gate_clip_time(time, start.y, end.y, _gate_bounds.position.y, _gate_bounds.end.y)
	var first := start - _gate_origin
	var last := end - _gate_origin
	time = _gate_clip_time(time, first.dot(_gate_direction) - from_distance, last.dot(_gate_direction) - to_distance, -GATE_HALF_DEPTH, GATE_HALF_DEPTH)
	if time.x > time.y:
		return false
	var side := _gate_direction.orthogonal()
	for span in _gate_damage_spans():
		var contact := _gate_clip_time(time, first.dot(side), last.dot(side), span.x, span.y)
		if contact.x <= contact.y:
			return true
	return false

func _gate_clip_time(time: Vector2, start: float, end: float, low: float, high: float) -> Vector2:
	if time.x > time.y:
		return time
	var delta := end - start
	if is_zero_approx(delta):
		return time if start >= low and start <= high else Vector2(1.0, 0.0)
	var a := (low - start) / delta
	var b := (high - start) / delta
	return Vector2(maxf(time.x, minf(a, b)), minf(time.y, maxf(a, b)))

func _gate_cross_extent() -> float:
	var side := _gate_direction.orthogonal()
	return (absf(side.x) * _gate_bounds.size.x + absf(side.y) * _gate_bounds.size.y) * 0.5

func gate_contains_point(point: Vector2, from_distance: float, to_distance: float) -> bool:
	if point.x < _gate_bounds.position.x or point.x > _gate_bounds.end.x or point.y < _gate_bounds.position.y or point.y > _gate_bounds.end.y:
		return false
	var offset := point - _gate_origin
	var along := offset.dot(_gate_direction)
	if along < from_distance - GATE_HALF_DEPTH or along > to_distance + GATE_HALF_DEPTH:
		return false
	var cross := offset.dot(_gate_direction.orthogonal())
	for gap in _gate_gaps:
		if cross > gap.x and cross < gap.y:
			return false
	return true

func _gate_polygons(from_distance: float, to_distance: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var first := maxf(GATE_HALF_DEPTH, from_distance - GATE_HALF_DEPTH)
	var last := minf(_gate_distance - GATE_HALF_DEPTH, to_distance + GATE_HALF_DEPTH)
	if last <= first:
		return result
	var side := _gate_direction.orthogonal()
	for span in _gate_damage_spans():
		result.append(PackedVector2Array([
			_gate_origin + _gate_direction * first + side * span.x,
			_gate_origin + _gate_direction * last + side * span.x,
			_gate_origin + _gate_direction * last + side * span.y,
			_gate_origin + _gate_direction * first + side * span.y,
		]))
	return result

func _gate_damage_spans() -> PackedVector2Array:
	var cross_extent := _gate_cross_extent()
	var result := PackedVector2Array()
	var edge := -cross_extent
	for gap in _gate_gaps:
		if gap.x > edge:
			result.append(Vector2(edge, gap.x))
		edge = gap.y
	if edge < cross_extent:
		result.append(Vector2(edge, cross_extent))
	return result

func _cancel_attack() -> void:
	_attack_generation += 1
	_clear_exceptions()
	phase = Phase.SEEK
	phase_left = maxf(0.1, attack_cooldown)
	velocity = Vector2.ZERO
	_hit_players.clear()
	_impact_left = 0.0
	_reset_inward = false
	_reset_left = 0.0
	_backwash_pending = false
	_tide_distance = 0.0
	_tide_progress = 0.0
	_gate_next = false
	_gate_distance = 0.0
	_gate_progress = 0.0
	_gate_gaps.clear()
	_gate_player_positions.clear()
	_gate_player_resets.clear()
	if is_instance_valid(_sound):
		_sound.stop()
	queue_redraw()

func get_network_runtime_state() -> Dictionary:
	var result := super.get_network_runtime_state()
	if phase in [Phase.GATE_BRACE, Phase.GATE]:
		# This Apex draws its own phase animation. The gate never uses the base
		# attack animation or spawn-transport tuning; keep the active Slow and
		# blocked state plus an explicit zero transport clock in the full packet.
		for key in ["attack_anim_time_left", "attack_anim_duration", "visual_facing_direction", "spawn_transport_duration", "spawn_transport_seed"]:
			result.erase(key)
	return result

func _get_custom_network_runtime_state() -> Dictionary:
	_wire_sequence += 1
	var result := {"q": _wire_sequence, "r": EnemyReplicationService._current_room_sync_id(), "s": phase, "t": int(round(phase_left * 1000.0)), "o": charge_origin, "e": charge_end, "a": int(round(charge_direction.angle() * 10000.0)), "w": wall_recovery, "i": int(round(_impact_left * 1000.0)), "p": _impact_position, "b": PackedVector2Array([_backwash_center]), "v": PackedVector2Array([_tide_origin, _tide_direction, _tide_bounds.position, _tide_bounds.size, Vector2(_tide_progress, _tide_distance)])}
	if phase in [Phase.GATE_BRACE, Phase.GATE]:
		var gate := PackedVector2Array([_gate_origin, _gate_direction, _gate_bounds.position, _gate_bounds.size, Vector2(_gate_progress, _gate_distance), _gate_brace_position])
		gate.append_array(_gate_gaps)
		result["g"] = gate
		for key in ["o", "e", "a", "w", "i", "p", "v", "b"]:
			result.erase(key) # Inactive ram/tide geometry must not consume the full-status packet budget.
	return result

func _apply_custom_network_runtime_state(state: Dictionary) -> void:
	if network_simulation_enabled or state.is_empty() or int(state.get("r", -1)) != EnemyReplicationService._current_room_sync_id():
		return
	var sequence := int(state.get("q", -1))
	if sequence <= _received_sequence:
		return
	var incoming_phase := int(state.get("s", -1))
	var is_gate := incoming_phase in [Phase.GATE_BRACE, Phase.GATE]
	var incoming_origin: Variant = state.get("o", charge_origin if is_gate else null)
	var incoming_end: Variant = state.get("e", charge_end if is_gate else null)
	var incoming_impact: Variant = state.get("p", Vector2.ZERO if is_gate else null)
	var incoming_backwash: Variant = state.get("b", incoming_end)
	# Packed geometry bypasses the generic runtime's coarse Vector2 rounding.
	if incoming_backwash is PackedVector2Array and incoming_backwash.size() == 1:
		incoming_backwash = incoming_backwash[0]
	if incoming_phase < Phase.SEEK or incoming_phase > Phase.GATE or not (incoming_origin is Vector2) or not (incoming_end is Vector2) or not (incoming_impact is Vector2) or not (incoming_backwash is Vector2):
		return
	if not incoming_origin.is_finite() or not incoming_end.is_finite() or not incoming_impact.is_finite() or not incoming_backwash.is_finite():
		return
	var tide: Variant = state.get("v", PackedVector2Array())
	if incoming_phase in [Phase.BACKWASH, Phase.TIDE]:
		if not (tide is PackedVector2Array) or tide.size() != 5:
			return
		for point in tide:
			if not point.is_finite():
				return
		if tide[1].length_squared() < 0.9 or tide[1].length_squared() > 1.1 or tide[3].x <= 0.0 or tide[3].y <= 0.0 or tide[4].x < 0.0 or tide[4].y < tide[4].x:
			return
	var gate: Variant = state.get("g", PackedVector2Array())
	if incoming_phase in [Phase.GATE_BRACE, Phase.GATE]:
		if not _valid_gate_packet(gate):
			return
	var previous := phase
	_received_sequence = sequence
	_remote_lease = REMOTE_LEASE
	phase = incoming_phase as Phase
	phase_left = clampf(float(state.get("t", 0)) * 0.001, 0.0, 10.0)
	charge_origin = incoming_origin
	charge_end = incoming_end
	charge_direction = Vector2.from_angle(float(state.get("a", 0)) * 0.0001)
	wall_recovery = bool(state.get("w", false))
	_impact_left = clampf(float(state.get("i", 0)) * 0.001, 0.0, IMPACT_DURATION)
	_impact_position = incoming_impact
	_backwash_center = incoming_backwash
	if tide is PackedVector2Array and tide.size() == 5:
		_tide_origin = tide[0]
		_tide_direction = tide[1]
		_tide_bounds = Rect2(tide[2], tide[3])
		_tide_progress = tide[4].x
		_tide_distance = tide[4].y
	_gate_gaps.clear()
	if incoming_phase in [Phase.GATE_BRACE, Phase.GATE]:
		_gate_origin = gate[0]
		_gate_direction = gate[1]
		_gate_bounds = Rect2(gate[2], gate[3])
		_gate_progress = gate[4].x
		_gate_distance = gate[4].y
		_gate_brace_position = gate[5]
		_gate_gaps = gate.slice(6)
	if previous != phase:
		if phase == Phase.LOCK:
			_play_sound(1.55)
		elif phase == Phase.CHARGE:
			_play_sound(0.95)
		elif phase == Phase.RECOVER and wall_recovery:
			_play_sound(0.60)
		elif phase in [Phase.BACKWASH, Phase.GATE_BRACE]:
			_play_sound(1.25)
		elif phase in [Phase.TIDE, Phase.GATE]:
			_play_sound(0.72)
	queue_redraw()

func _valid_gate_packet(gate: Variant) -> bool:
	if not (gate is PackedVector2Array) or gate.size() < 7 or gate.size() > 10:
		return false
	for point in gate:
		if not point.is_finite():
			return false
	var direction: Vector2 = gate[1]
	if not is_equal_approx(direction.length_squared(), 1.0) or not is_zero_approx(direction.x * direction.y) or gate[3].x <= 0.0 or gate[3].y <= 0.0 or gate[4].x < 0.0 or gate[4].y < gate[4].x:
		return false
	var cross_extent: float = (absf(direction.y) * gate[3].x + absf(direction.x) * gate[3].y) * 0.5
	var previous := -INF
	for index in range(6, gate.size()):
		var gap: Vector2 = gate[index]
		if gap.x < -cross_extent or gap.y > cross_extent or gap.x >= gap.y or gap.x <= previous:
			return false
		previous = gap.y
	return true

func _process_network_visuals(delta: float) -> void:
	_remote_lease = maxf(0.0, _remote_lease - delta)
	_sound_left = maxf(0.0, _sound_left - delta)
	_impact_left = maxf(0.0, _impact_left - delta)
	phase_left = maxf(0.0, phase_left - delta)
	if _remote_lease <= 0.0:
		phase = Phase.SEEK
		_impact_left = 0.0
		_gate_gaps.clear()
		if is_instance_valid(_sound):
			_sound.stop()
	elif phase in [Phase.BACKWASH, Phase.TIDE, Phase.GATE_BRACE, Phase.GATE] and phase_left <= 0.0:
		phase = Phase.RECOVER
	elif phase == Phase.TIDE:
		_tide_progress = minf(_tide_distance, _tide_progress + TIDE_SPEED * delta)
	elif phase == Phase.GATE:
		_gate_progress = minf(_gate_distance, _gate_progress + GATE_SPEED * delta)
	queue_redraw()

func get_warning_polygons() -> Array[PackedVector2Array]:
	if phase == Phase.GATE_BRACE:
		return _gate_polygons(0.0, _gate_distance)
	if phase == Phase.GATE:
		return _gate_polygons(_gate_progress, _gate_progress)
	if phase == Phase.BACKWASH:
		return _tide_polygons(0.0, _tide_distance)
	if phase == Phase.TIDE:
		return _tide_polygons(_tide_progress, _tide_progress)
	if phase not in [Phase.TRACK, Phase.LOCK]:
		return []
	if charge_origin.distance_squared_to(charge_end) < 0.0001:
		var circle := PackedVector2Array()
		for index in range(48):
			circle.append(charge_origin + Vector2.from_angle(TAU * float(index) / 48.0) * PATH_RADIUS)
		return [circle]
	return Geometry2D.offset_polyline(PackedVector2Array([charge_origin, charge_end]), PATH_RADIUS, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)

func get_attack_callout() -> String:
	if phase == Phase.GATE_BRACE:
		return "Harbor Gate / HOLD THE OPENING"
	if phase == Phase.GATE:
		return "Harbor Gate"
	match phase:
		Phase.TRACK:
			return "Breakwater / RAM"
		Phase.LOCK, Phase.CHARGE:
			return "Breakwater / RAM"
		Phase.BACKWASH:
			return "Return Tide / FIND THE WAKE"
		Phase.TIDE:
			return "Return Tide"
	return ""

func _draw() -> void:
	var locked := phase in [Phase.LOCK, Phase.BACKWASH, Phase.GATE_BRACE]
	for polygon in get_warning_polygons():
		var points := PackedVector2Array()
		for point in polygon:
			points.append(to_local(point))
		draw_colored_polygon(points, Color(0.25, 0.64, 0.72, 0.38) if phase in [Phase.TIDE, Phase.GATE] else Color(1.0, 0.48, 0.18, 0.06 if phase in [Phase.BACKWASH, Phase.GATE_BRACE] else 0.17 if locked else 0.07))
		if phase not in [Phase.BACKWASH, Phase.GATE_BRACE, Phase.GATE]:
			points.append(points[0])
			draw_polyline(points, Color(1.0, 0.67, 0.33, 0.96 if phase == Phase.TIDE else 0.86 if locked else 0.38), 2.5 if phase == Phase.TIDE else 2.0, true)
	if phase in [Phase.BACKWASH, Phase.TIDE]:
		_draw_tide()
	if phase in [Phase.GATE_BRACE, Phase.GATE]:
		_draw_gate()
	if phase == Phase.BACKWASH:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 14.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - phase_left / BACKWASH_TIME), 48, Color(1.0, 0.88, 0.62), 3.0, true)
	elif phase == Phase.GATE_BRACE:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 14.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - phase_left / GATE_WARNING), 48, Color(1.0, 0.88, 0.62), 3.0, true)
	if phase in [Phase.TRACK, Phase.LOCK]:
		var from := to_local(charge_origin)
		var to := to_local(charge_end)
		draw_line(from, to, Color(1.0, 0.84, 0.57, 0.75 if locked else 0.28), 1.6, true)
		var side := charge_direction.rotated(PI * 0.5)
		draw_line(to - side * 16.0, to + side * 16.0, Color(1.0, 0.84, 0.57, 0.80), 3.0, true)
	var facing := _gate_direction if phase in [Phase.GATE_BRACE, Phase.GATE] else _tide_direction if phase in [Phase.BACKWASH, Phase.TIDE] else charge_direction if phase != Phase.SEEK else visual_facing_direction
	var exhausted := phase == Phase.RECOVER and not _backwash_pending
	var body_color := Color(0.36, 0.24, 0.17) if not exhausted else Color(0.20, 0.32, 0.34)
	var core_color := Color(0.98, 0.54, 0.23) if not exhausted else Color(0.62, 0.91, 0.93)
	_draw_common_body(BODY_RADIUS, body_color, core_color, facing)
	if is_spawn_transporting():
		return
	var side := facing.rotated(PI * 0.5)
	var spread := 11.0 if exhausted else (8.0 if phase in [Phase.BACKWASH, Phase.TIDE, Phase.GATE_BRACE, Phase.GATE] else 0.0)
	for sign_value: float in [-1.0, 1.0]:
		var shoulder := side * sign_value * (19.0 + spread)
		var plate := PackedVector2Array([shoulder + facing * 34.0 - side * sign_value * 5.0, shoulder + facing * 34.0 + side * sign_value * 5.0, shoulder - facing * 19.0 + side * sign_value * 8.0, shoulder - facing * 13.0 - side * sign_value * 5.0])
		draw_colored_polygon(plate, Color(0.76, 0.51, 0.29, 0.95))
		plate.append(plate[0])
		draw_polyline(plate, Color(1.0, 0.81, 0.50, 0.9), 1.7, true)
	if phase in [Phase.BACKWASH, Phase.TIDE, Phase.GATE_BRACE, Phase.GATE]:
		# A broad seawall silhouette visibly holds back the water at its front.
		var hull := PackedVector2Array([facing * 18.0 - side * 39.0, facing * 34.0 - side * 23.0, facing * 41.0, facing * 34.0 + side * 23.0, facing * 18.0 + side * 39.0, facing * 23.0 + side * 20.0, facing * 30.0, facing * 23.0 - side * 20.0])
		draw_colored_polygon(hull, Color(0.22, 0.38, 0.41))
		draw_polyline(PackedVector2Array([facing * 18.0 - side * 39.0, facing * 34.0 - side * 23.0, facing * 41.0, facing * 34.0 + side * 23.0, facing * 18.0 + side * 39.0]), Color(0.68, 0.88, 0.86), 4.0, true)
	elif locked:
		draw_line(facing * 34.0 - side * 11.0, facing * 34.0 + side * 11.0, Color(1.0, 0.95, 0.75), 3.0, true)
	elif phase == Phase.CHARGE:
		for offset: float in [-12.0, 0.0, 12.0]:
			draw_line(-facing * 22.0 + side * offset, -facing * 66.0 + side * offset, Color(1.0, 0.73, 0.34, 0.55), 2.5, true)
	elif exhausted:
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, Color(0.75, 0.98, 1.0, 0.85), 2.0, true)
	if _impact_left > 0.0:
		var progress := 1.0 - _impact_left / IMPACT_DURATION
		var center := to_local(_impact_position)
		for index in range(8):
			var direction := Vector2.from_angle(float(index) * TAU / 8.0)
			draw_line(center + direction * (32.0 + progress * 18.0), center + direction * (39.0 + progress * 28.0), Color(1.0, 0.81, 0.51, (1.0 - progress) * 0.75), 2.0, true)
	ATTACK_CALLOUT.draw_callout(self, get_attack_callout(), -76.0)

func _play_sound(pitch: float) -> void:
	if _sound == null or _sound_left > 0.0:
		return
	if _impact_sound == null:
		_impact_sound = _make_sound()
		_surge_sound = _make_surge_sound()
	_sound.stream = _surge_sound if is_equal_approx(pitch, 0.72) else _impact_sound
	_sound.volume_db = AUDIO_LEVELS.clamp_db(RunContext.sfx_volume_db - 19.0)
	_sound.pitch_scale = 1.0 if is_equal_approx(pitch, 0.72) else pitch
	_sound.play()
	_sound_left = 0.08

static func _make_sound() -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var samples := 2205
	var data := PackedByteArray()
	data.resize(samples * 2)
	var angle := 0.0
	for index in range(samples):
		var time := float(index) / float(samples)
		angle += TAU * lerpf(410.0, 95.0, time) / 22050.0
		var value := (sin(angle) + 0.3 * sin(angle * 2.7)) * sin(time * PI) * (1.0 - time) * 0.22
		data.encode_s16(index * 2, int(value * 32767.0))
	sound.data = data
	return sound

func _draw_gate() -> void:
	var side := _gate_direction.orthogonal()
	var first := _gate_origin + _gate_direction * GATE_HALF_DEPTH
	var last := _gate_origin + _gate_direction * (_gate_distance - GATE_HALF_DEPTH)
	if phase == Phase.GATE_BRACE and global_position.distance_to(_gate_brace_position) > 8.0:
		var post := to_local(_gate_brace_position)
		for sign_value: float in [-1.0, 1.0]:
			var corner := post + side * 30.0 * sign_value
			draw_line(corner, corner - _gate_direction * 15.0, Color(0.70, 0.89, 0.87, 0.44), 2.0, true)
	# Long calm rails mark the committed openings; they never track a player.
	for gap in _gate_gaps:
		for edge: float in [gap.x, gap.y]:
			draw_line(to_local(first + side * edge), to_local(last + side * edge), Color(0.60, 0.87, 0.78, 0.40), 1.7, true)
		var middle := (gap.x + gap.y) * 0.5
		var marker := first + side * middle + _gate_direction * 24.0
		var half_span := minf(18.0, (gap.y - gap.x) * 0.25)
		draw_polyline(PackedVector2Array([to_local(marker + side * half_span), to_local(marker + _gate_direction * 11.0), to_local(marker - side * half_span)]), Color(0.72, 0.97, 0.87, 0.9), 3.0, true)
	var crest := _gate_progress if phase == Phase.GATE else GATE_HALF_DEPTH + 8.0
	for polygon in _gate_polygons(crest, crest):
		var points := PackedVector2Array()
		for point in polygon:
			points.append(to_local(point))
		if phase == Phase.GATE_BRACE:
			draw_colored_polygon(points, Color(0.32, 0.60, 0.64, 0.32))
		points.append(points[0])
		if phase == Phase.GATE_BRACE:
			draw_polyline(points, Color(0.72, 0.93, 0.95, 0.65), 2.8, true)
		else:
			draw_line(points[0], points[3], Color(0.53, 0.83, 0.89, 0.30), 1.0, true)
			draw_line(points[0], points[1], Color(0.78, 0.96, 0.94, 0.8), 2.4, true)
			draw_line(points[2], points[3], Color(0.78, 0.96, 0.94, 0.8), 2.4, true)
		# The exact leading edge stays readable; uneven foam rolls just behind
		# it, entirely within the real damage band, with two softer trailing wakes.
		draw_line(points[1], points[2], Color(0.84, 0.98, 1.0, 0.85), 1.5, true)
		var segments := maxi(2, int(ceil(points[1].distance_to(points[2]) / 12.0)))
		for lag: float in [5.0, 16.0, 29.0]:
			var foam := PackedVector2Array()
			for index in range(segments + 1):
				var ratio := float(index) / segments
				var ripple := sin(index * 1.73 + _gate_progress * 0.018 + lag) * 2.6 + sin(index * 0.71) * 1.4
				foam.append(points[1].lerp(points[2], ratio) - _gate_direction * (lag + ripple))
			draw_polyline(foam, Color(0.83, 0.97, 1.0, 0.82 if lag == 5.0 else 0.28), 2.5 if lag == 5.0 else 1.2, true)
	if phase == Phase.GATE_BRACE:
		for polygon in _gate_polygons(0.0, _gate_distance):
			var across := ((polygon[0] + polygon[3]) * 0.5 - _gate_origin).dot(side)
			for distance: float in [100.0, 280.0, 460.0, 640.0, 820.0, 1000.0, 1180.0]:
				if distance >= _gate_distance - GATE_HALF_DEPTH:
					continue
				var point := _gate_origin + _gate_direction * distance + side * across
				draw_polyline(PackedVector2Array([to_local(point + side * 8.0), to_local(point + _gate_direction * 12.0), to_local(point - side * 8.0)]), Color(0.95, 0.71, 0.40, 0.60), 1.8, true)

func _draw_tide() -> void:
	var side := _tide_direction.orthogonal()
	var front := _tide_progress if phase == Phase.TIDE else 0.0
	# Arrows explain the returning direction, while the vacated ram lane stays
	# unpainted. Only the moving crest deals damage once the brace releases.
	if phase == Phase.BACKWASH:
		for distance: float in [55.0, 175.0, 295.0, 415.0, 535.0, 655.0, 775.0, 895.0]:
			if distance > _tide_distance:
				continue
			for across: float in [-130.0, 130.0]:
				var point := _tide_origin + _tide_direction * distance + side * across
				if not _tide_bounds.grow(-16.0).has_point(point):
					continue
				var tip := to_local(point + _tide_direction * 10.0)
				draw_polyline(PackedVector2Array([to_local(point + side * 8.0), tip, to_local(point - side * 8.0)]), Color(0.92, 0.73, 0.46, 0.55), 1.5, true)
	for sign_value: float in [-1.0, 1.0]:
		for lag: float in [0.0, 12.0, 25.0]:
			if phase != Phase.TIDE and lag > 0.0:
				continue
			var points := PackedVector2Array()
			for index in range(TIDE_CURVE_SEGMENTS + 1):
				var across := lerpf(TIDE_WAKE_HALF_WIDTH + 2.0, TIDE_HALF_WIDTH - 2.0, float(index) / TIDE_CURVE_SEGMENTS)
				var point := _tide_origin + _tide_direction * (front + TIDE_HALF_DEPTH - 4.0 - lag + _tide_curve_offset(across)) + side * sign_value * across
				if _tide_bounds.has_point(point):
					points.append(to_local(point))
				elif points.size() >= 2:
					draw_polyline(points, Color(0.76, 0.94, 0.96, 0.85 if lag == 0.0 else 0.26), 2.8 if lag == 0.0 else 1.4, true)
					points.clear()
				else:
					points.clear()
			if points.size() >= 2:
				draw_polyline(points, Color(0.76, 0.94, 0.96, 0.85 if phase == Phase.TIDE and lag == 0.0 else 0.32), 2.8 if lag == 0.0 else 1.4, true)
		if phase == Phase.TIDE:
			for index in range(1, 8):
				var across := lerpf(TIDE_WAKE_HALF_WIDTH, TIDE_HALF_WIDTH, float(index) / 8.0)
				var point := _tide_origin + _tide_direction * (front + 12.0 + _tide_curve_offset(across)) + side * sign_value * across
				if _tide_bounds.grow(-5.0).has_point(point):
					draw_arc(to_local(point), 3.5, _tide_direction.angle() - 1.7, _tide_direction.angle() + 1.7, 8, Color(0.85, 0.98, 0.98, 0.58), 1.0, true)

static func _make_surge_sound() -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var samples := 12127
	var data := PackedByteArray()
	data.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 81723
	var water := 0.0
	var phase_angle := 0.0
	for index in range(samples):
		var progress := float(index) / float(samples - 1)
		water = lerpf(water, rng.randf_range(-1.0, 1.0), 0.18)
		phase_angle += TAU * lerpf(88.0, 41.0, progress) / 22050.0
		var envelope := minf(progress * 16.0, 1.0) * pow(1.0 - progress, 1.6)
		var value := (water * 0.8 + sin(phase_angle) * 0.28) * envelope
		data.encode_s16(index * 2, int(value * 32767.0))
	sound.data = data
	return sound
