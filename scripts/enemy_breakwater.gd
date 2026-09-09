extends "res://scripts/enemy_base.gd"
## One committed charge. Terrain creates a longer harmless punish window.

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
enum Phase { SEEK, TRACK, LOCK, CHARGE, RECOVER }

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
var _body_shape := CircleShape2D.new()
var _sound: AudioStreamPlayer
var _sound_left := 0.0

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

func _is_in_priority_attack_state() -> bool:
	return phase != Phase.SEEK or _impact_left > 0.0

func _process_behavior(delta: float) -> void:
	if not network_simulation_enabled or not is_finite(delta) or delta <= 0.0 or is_dead():
		return
	_impact_left = maxf(0.0, _impact_left - delta)
	_sound_left = maxf(0.0, _sound_left - delta)
	if phase in [Phase.LOCK, Phase.CHARGE] and EnemyReplicationService.get_current_room_bounds() != _charge_bounds:
		_cancel_attack() # Forced bounds changes are not traveled attack segments.
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
				phase = Phase.SEEK
				phase_left = maxf(0.1, attack_cooldown)
				_reset_inward = wall_recovery
				_reset_left = 1.5
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
		_begin_tracking()

func _begin_tracking() -> void:
	if _acquisition_target() == null:
		return
	_clear_exceptions()
	_attack_generation += 1
	phase = Phase.TRACK
	phase_left = TRACK_TIME
	velocity = Vector2.ZERO
	wall_recovery = false
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

func _enter_recovery(hit_wall: bool) -> void:
	_clear_exceptions()
	phase = Phase.RECOVER
	wall_recovery = hit_wall
	phase_left = WALL_RECOVERY if hit_wall else MISS_RECOVERY
	velocity = Vector2.ZERO
	if hit_wall:
		_impact_left = IMPACT_DURATION
		_impact_position = global_position
		_play_sound(0.60)
	queue_redraw()

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
	queue_redraw()

func _get_custom_network_runtime_state() -> Dictionary:
	_wire_sequence += 1
	return {"q": _wire_sequence, "r": EnemyReplicationService._current_room_sync_id(), "s": phase, "t": int(round(phase_left * 1000.0)), "o": charge_origin, "e": charge_end, "a": int(round(charge_direction.angle() * 10000.0)), "w": wall_recovery, "i": int(round(_impact_left * 1000.0)), "p": _impact_position}

func _apply_custom_network_runtime_state(state: Dictionary) -> void:
	if network_simulation_enabled or state.is_empty() or int(state.get("r", -1)) != EnemyReplicationService._current_room_sync_id():
		return
	var sequence := int(state.get("q", -1))
	if sequence <= _received_sequence:
		return
	var incoming_phase := int(state.get("s", -1))
	var incoming_origin: Variant = state.get("o")
	var incoming_end: Variant = state.get("e")
	var incoming_impact: Variant = state.get("p")
	if incoming_phase < Phase.SEEK or incoming_phase > Phase.RECOVER or not (incoming_origin is Vector2) or not (incoming_end is Vector2) or not (incoming_impact is Vector2):
		return
	if not incoming_origin.is_finite() or not incoming_end.is_finite() or not incoming_impact.is_finite():
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
	if previous != phase:
		if phase == Phase.LOCK:
			_play_sound(1.55)
		elif phase == Phase.CHARGE:
			_play_sound(0.95)
		elif phase == Phase.RECOVER and wall_recovery:
			_play_sound(0.60)
	queue_redraw()

func _process_network_visuals(delta: float) -> void:
	_remote_lease = maxf(0.0, _remote_lease - delta)
	_sound_left = maxf(0.0, _sound_left - delta)
	_impact_left = maxf(0.0, _impact_left - delta)
	phase_left = maxf(0.0, phase_left - delta)
	if _remote_lease <= 0.0:
		phase = Phase.SEEK
		_impact_left = 0.0
	queue_redraw()

func get_warning_polygons() -> Array[PackedVector2Array]:
	if phase not in [Phase.TRACK, Phase.LOCK]:
		return []
	if charge_origin.distance_squared_to(charge_end) < 0.0001:
		var circle := PackedVector2Array()
		for index in range(48):
			circle.append(charge_origin + Vector2.from_angle(TAU * float(index) / 48.0) * PATH_RADIUS)
		return [circle]
	return Geometry2D.offset_polyline(PackedVector2Array([charge_origin, charge_end]), PATH_RADIUS, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)

func _draw() -> void:
	var locked := phase == Phase.LOCK
	for polygon in get_warning_polygons():
		var points := PackedVector2Array()
		for point in polygon:
			points.append(to_local(point))
		draw_colored_polygon(points, Color(1.0, 0.48, 0.18, 0.17 if locked else 0.07))
		points.append(points[0])
		draw_polyline(points, Color(1.0, 0.67, 0.33, 0.86 if locked else 0.38), 2.0, true)
	if phase in [Phase.TRACK, Phase.LOCK]:
		var from := to_local(charge_origin)
		var to := to_local(charge_end)
		draw_line(from, to, Color(1.0, 0.84, 0.57, 0.75 if locked else 0.28), 1.6, true)
		var side := charge_direction.rotated(PI * 0.5)
		draw_line(to - side * 16.0, to + side * 16.0, Color(1.0, 0.84, 0.57, 0.80), 3.0, true)
	var facing := charge_direction if phase != Phase.SEEK else visual_facing_direction
	var exhausted := phase == Phase.RECOVER and wall_recovery
	var body_color := Color(0.36, 0.24, 0.17) if not exhausted else Color(0.20, 0.32, 0.34)
	var core_color := Color(0.98, 0.54, 0.23) if not exhausted else Color(0.62, 0.91, 0.93)
	_draw_common_body(BODY_RADIUS, body_color, core_color, facing)
	if is_spawn_transporting():
		return
	var side := facing.rotated(PI * 0.5)
	var spread := 9.0 if exhausted else 0.0
	for sign_value: float in [-1.0, 1.0]:
		var shoulder := side * sign_value * (19.0 + spread)
		var plate := PackedVector2Array([shoulder + facing * 34.0 - side * sign_value * 5.0, shoulder + facing * 34.0 + side * sign_value * 5.0, shoulder - facing * 19.0 + side * sign_value * 8.0, shoulder - facing * 13.0 - side * sign_value * 5.0])
		draw_colored_polygon(plate, Color(0.76, 0.51, 0.29, 0.95))
		plate.append(plate[0])
		draw_polyline(plate, Color(1.0, 0.81, 0.50, 0.9), 1.7, true)
	if locked:
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

func _play_sound(pitch: float) -> void:
	if _sound == null or _sound_left > 0.0:
		return
	_sound.volume_db = AUDIO_LEVELS.clamp_db(RunContext.sfx_volume_db - 19.0)
	_sound.pitch_scale = pitch
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
