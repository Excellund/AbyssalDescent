extends Node2D
## Owner-simulated blades; remote instances only predict bounded visual state.
## An enemy may be hit once per leg. Neither leg executes another primary attack.

const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const LAUNCH := preload("res://scripts/enemy_launch_state.gd")
const ARENA_BOUNDARY := preload("res://scripts/shared/arena_boundary.gd")
const DAMAGE_RATIO := 0.45
const OUTBOUND_DISTANCE := 220.0
const OUTBOUND_SPEED := 620.0
const RETURN_SPEED := 780.0
const BLADE_RADIUS := 10.0
const CATCH_RADIUS := 24.0
const MAX_LIFETIME := 2.0
const MAX_STEP_DISTANCE := 8.0
const STATE_INTERVAL := 0.08
const REMOTE_LEASE := 0.35
const COLOR_OUT := Color(0.42, 0.84, 1.0, 0.95)
const COLOR_RETURN := Color(0.80, 0.72, 1.0, 0.96)

class Blade extends RefCounted:
	var id: int
	var position: Vector2
	var visual_position: Vector2
	var direction: Vector2
	var returning: bool = false
	var travel_left: float
	var life_left: float = MAX_LIFETIME
	var bounces_left: int = 0
	var damage: int
	var damage_coefficient: float = DAMAGE_RATIO
	var interaction: Dictionary = {}
	var source_peer: int
	var outgoing_hits: Dictionary = {}
	var returning_hits: Dictionary = {}
	var trail: Array[Vector2] = []
	var flash_left: float = 0.0
	var presentation_finished: bool = false

var player: CharacterBody2D
var blades: Array[Blade] = []
var _next_id: int = 1
var _sequence: int = 0
var _received_sequence: int = -1
var _highest_received_id: int = 0
var _discard_through: int = 0
var _cancel_generation: int = 0
var _state_left: float = 0.0
var _remote_lease: float = 0.0
var _shape := CircleShape2D.new()
var _sound: AudioStreamPlayer
var _sound_left: float = 0.0

func initialize(owner_player: CharacterBody2D) -> void:
	player = owner_player
	top_level = true
	global_position = Vector2.ZERO
	z_index = 4
	_shape.radius = BLADE_RADIUS
	if DisplayServer.get_name() != "headless":
		_sound = AudioStreamPlayer.new()
		_sound.volume_db = -21.0
		if AudioServer.get_bus_index("SFX") >= 0:
			_sound.bus = &"SFX"
		_sound.stream = _make_sound()
		add_child(_sound)

func _visible_allowed() -> bool:
	return is_instance_valid(player) and not player.is_queued_for_deletion() and bool(player._is_alive_state) and bool(player.combat_damage_enabled) and not bool(player.encounter_input_frozen)

func _owner_allowed() -> bool:
	return _visible_allowed() and _is_local_owner()

func _is_local_owner() -> bool:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return false
	var api := player.get_multiplayer()
	if api == null or (api.has_multiplayer_peer() and api.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED):
		return false
	return bool(player._is_local_control_owner())

func try_launch(direction: Vector2, attack_origin: Vector2 = Vector2.INF) -> bool:
	if not _owner_allowed() or get_tree().paused or DAMAGEABLE.is_launch_suppressed() or not bool(player.reward_returning_crescent):
		return false
	if not direction.is_finite() or direction.length_squared() < 0.000001 or not player.global_position.is_finite():
		return false
	var stacks := clampi(int(player.returning_crescent_stacks), 0, 3)
	var capacity := 2 if stacks >= 2 else 1
	if stacks <= 0 or blades.size() >= capacity:
		return false
	var damage_scale := float(player.returning_crescent_damage_scale)
	var reach_scale := float(player.returning_crescent_reach_scale)
	if not is_finite(damage_scale) or not is_finite(reach_scale) or damage_scale <= 0.0 or reach_scale <= 0.0:
		return false
	var blade := Blade.new()
	blade.id = _next_id
	_next_id += 1
	# A remote delivery point changes the outbound origin; the return still
	# follows the living owner's body, preserving its repositioning decision.
	blade.position = attack_origin if attack_origin.is_finite() else player.global_position
	blade.visual_position = blade.position
	blade.direction = direction.normalized()
	blade.travel_left = OUTBOUND_DISTANCE * minf(reach_scale, 2.0)
	blade.bounces_left = 1 if stacks >= 3 else 0
	blade.damage_coefficient = DAMAGE_RATIO * damage_scale
	blade.damage = maxi(1, int(round(float(player.damage) * DAMAGE_RATIO * damage_scale)))
	blade.interaction = player._capture_combat_action("returning_crescent")
	blade.source_peer = DAMAGEABLE._resolve_local_peer_id()
	blades.append(blade)
	_play_sound(1.0)
	_publish_state(true)
	queue_redraw()
	return true

func cancel() -> void:
	_cancel_generation += 1
	var had_blades := not blades.is_empty()
	blades.clear()
	_remote_lease = 0.0
	_discard_through = maxi(_discard_through, _highest_received_id)
	if had_blades and _is_local_owner():
		_publish_state(true)
	queue_redraw()

func _physics_process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if not _visible_allowed():
		if not blades.is_empty():
			cancel()
		return
	if get_tree().paused:
		return
	_sound_left = maxf(0.0, _sound_left - delta)
	if blades.is_empty():
		return
	var owner := _is_local_owner()
	if not owner:
		_remote_lease = maxf(0.0, _remote_lease - delta)
		if _remote_lease <= 0.0:
			cancel()
			return
	var exclusions := _geometry_exclusions()
	var generation := _cancel_generation
	var changed := false
	for blade: Blade in blades.duplicate():
		if blade.presentation_finished:
			continue
		var was_returning := blade.returning
		var prior_bounces := blade.bounces_left
		var survives := _advance(blade, delta, owner, exclusions)
		if generation != _cancel_generation:
			return
		if not survives:
			if owner:
				blades.erase(blade)
			else:
				# Keep this bounded tombstone until the owner omits the ID. A late
				# correction must not make an already-caught blade appear again.
				blade.presentation_finished = true
			changed = true
			continue
		changed = changed or was_returning != blade.returning or prior_bounces != blade.bounces_left
		blade.visual_position = blade.position if owner else blade.visual_position.lerp(blade.position, minf(1.0, delta * 24.0))
		blade.flash_left = maxf(0.0, blade.flash_left - delta)
		blade.trail.append(blade.visual_position)
		if blade.trail.size() > 8:
			blade.trail.pop_front()
	if owner:
		_state_left -= delta
		if changed or _state_left <= 0.0:
			_publish_state(changed)
	queue_redraw()

func _advance(blade: Blade, delta: float, deal_damage: bool, exclusions: Array[RID]) -> bool:
	var available := minf(delta, blade.life_left)
	blade.life_left = maxf(0.0, blade.life_left - available)
	var generation := _cancel_generation
	var iterations := 0
	while available > 0.000001 and iterations < 512:
		iterations += 1
		var speed := RETURN_SPEED if blade.returning else OUTBOUND_SPEED
		var distance := minf(MAX_STEP_DISTANCE, speed * available)
		if blade.returning:
			var to_owner := player.global_position - blade.position
			if not to_owner.is_finite() or to_owner.length() <= CATCH_RADIUS:
				return false
			blade.direction = to_owner.normalized()
			distance = minf(distance, to_owner.length() - CATCH_RADIUS)
		else:
			distance = minf(distance, blade.travel_left)
			if distance <= 0.000001:
				blade.returning = true
				continue
		var start := blade.position
		var motion := blade.direction * distance
		var wall := _wall_sweep(start, motion, exclusions)
		if bool(wall.get("outside", false)):
			return false # A shrinking arena cannot teleport a blade into a new hit.
		var fraction := float(wall.get("fraction", 1.0))
		blade.position += motion * fraction
		if deal_damage:
			_apply_segment_hits(blade, start, blade.position, exclusions)
			if generation != _cancel_generation:
				return false
		var travelled := distance * fraction
		if not blade.returning:
			blade.travel_left = maxf(0.0, blade.travel_left - travelled)
		available = maxf(0.0, available - maxf(travelled / speed, 0.0001))
		if not wall.is_empty():
			if blade.returning:
				return false
			var normal: Vector2 = wall.get("normal", -blade.direction)
			blade.position += normal * 0.2
			if blade.bounces_left > 0:
				blade.bounces_left -= 1
				blade.direction = blade.direction.bounce(normal).normalized()
				blade.flash_left = 0.10
				if deal_damage:
					_play_sound(1.45)
			else:
				blade.returning = true
		elif not blade.returning and blade.travel_left <= 0.000001:
			blade.returning = true
	return blade.life_left > 0.0

## Returns a fresh exclusion array; combat bodies are hit by the swept blade,
## while physics queries reserve their blocking role for arena geometry.
func _geometry_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = []
	for group in ["combat_players", "enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is CollisionObject2D:
				exclusions.append((node as CollisionObject2D).get_rid())
	return exclusions

## Returns a new dictionary with the first safe travel fraction and wall normal.
func _wall_sweep(start: Vector2, motion: Vector2, exclusions: Array[RID]) -> Dictionary:
	var boundary := ARENA_BOUNDARY.sweep(start, motion, EnemyReplicationService.get_current_room_bounds())
	if bool(boundary.get("outside", false)):
		return boundary
	var boundary_fraction := float(boundary.get("fraction", 1.0))
	var clipped_motion := motion * boundary_fraction
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0.0, start)
	query.exclude = exclusions
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = false
	if not space.intersect_shape(query, 1).is_empty():
		return {"fraction": 0.0, "normal": -motion.normalized()}
	query.motion = clipped_motion
	var fractions := space.cast_motion(query)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return boundary
	query.transform.origin = start + clipped_motion * minf(1.0, fractions[1] + 0.005)
	query.motion = Vector2.ZERO
	var contact := space.get_rest_info(query)
	var normal: Vector2 = contact.get("normal", -motion.normalized())
	if not normal.is_finite() or normal.length_squared() < 0.0001:
		normal = -motion.normalized()
	return {"fraction": clampf(fractions[0], 0.0, 1.0) * boundary_fraction, "normal": normal.normalized()}

func _apply_segment_hits(blade: Blade, start: Vector2, finish: Vector2, exclusions: Array[RID]) -> void:
	var hit_ids := blade.returning_hits if blade.returning else blade.outgoing_hits
	var generation := _cancel_generation
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is CharacterBody2D) or node.is_queued_for_deletion() or DAMAGEABLE._read_target_health(node) <= 0:
			continue
		var enemy := node as CharacterBody2D
		var id := enemy.get_instance_id()
		if hit_ids.has(id):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(enemy.global_position, start, finish)
		if closest.distance_to(enemy.global_position) > BLADE_RADIUS + LAUNCH.body_radius(enemy):
			continue
		if closest.distance_squared_to(enemy.global_position) > 0.000001:
			var sight := PhysicsRayQueryParameters2D.create(closest, enemy.global_position, 0xFFFFFFFF, exclusions)
			if not get_world_2d().direct_space_state.intersect_ray(sight).is_empty():
				continue
		hit_ids[id] = true
		DAMAGEABLE.apply_damage(enemy, blade.damage, INTERACTIONS.damage_context(blade.interaction, "returning_crescent", {"secondary": true, "attack_origin": start, "damage_coefficient": blade.damage_coefficient}), blade.source_peer)
		if generation != _cancel_generation:
			return
		if not _owner_allowed():
			cancel()
			return

func _room_id() -> int:
	return EnemyReplicationService._current_room_sync_id()

## Returns a new compact presentation snapshot; no damage or hit sets are sent.
func build_network_state() -> Dictionary:
	var states: Array = []
	for blade in blades:
		states.append([blade.id, blade.position.snapped(Vector2.ONE * 0.1), blade.direction.snapped(Vector2.ONE * 0.001), blade.returning, snappedf(blade.travel_left, 0.1), snappedf(blade.life_left, 0.01), blade.bounces_left])
	return {"s": _sequence, "r": _room_id(), "n": _next_id - 1, "b": states}

func _publish_state(reliable: bool = false) -> void:
	_sequence += 1
	_state_left = STATE_INTERVAL
	if is_instance_valid(player):
		player._broadcast_cue_event("returning_crescent_state", build_network_state(), reliable)

func apply_network_state(payload: Dictionary) -> void:
	if not is_instance_valid(player) or _is_local_owner() or int(payload.get("r", -1)) != _room_id():
		return
	var sequence := int(payload.get("s", -1))
	if sequence <= _received_sequence:
		return
	_received_sequence = sequence
	_highest_received_id = maxi(_highest_received_id, int(payload.get("n", 0)))
	if not _visible_allowed() or get_tree().paused:
		cancel()
		return
	var states: Variant = payload.get("b", [])
	if not (states is Array) or states.size() > 2:
		return
	if states.is_empty():
		cancel()
		return
	var previous: Dictionary = {}
	for blade in blades:
		previous[blade.id] = blade
	var incoming: Array[Blade] = []
	for entry in states:
		if not (entry is Array) or entry.size() != 7 or not (entry[1] is Vector2) or not (entry[2] is Vector2):
			continue
		var id := int(entry[0])
		var position_value: Vector2 = entry[1]
		var direction_value: Vector2 = entry[2]
		var travel := float(entry[4])
		var life := float(entry[5])
		if id <= _discard_through or id > _highest_received_id or not position_value.is_finite() or not direction_value.is_finite() or direction_value.length_squared() < 0.0001 or not is_finite(travel) or not is_finite(life):
			continue
		if incoming.any(func(candidate: Blade) -> bool: return candidate.id == id):
			continue
		var blade: Blade = previous.get(id, Blade.new())
		if not previous.has(id):
			blade.visual_position = position_value
			_play_sound(1.0)
		blade.id = id
		blade.position = position_value
		blade.direction = direction_value.normalized()
		blade.returning = bool(entry[3])
		blade.travel_left = clampf(travel, 0.0, OUTBOUND_DISTANCE * 2.0)
		blade.life_left = clampf(life, 0.0, MAX_LIFETIME)
		blade.bounces_left = clampi(int(entry[6]), 0, 1)
		incoming.append(blade)
	blades = incoming
	_remote_lease = REMOTE_LEASE
	queue_redraw()

func _draw() -> void:
	for blade in blades:
		if blade.presentation_finished:
			continue
		var color := COLOR_RETURN if blade.returning else COLOR_OUT
		for index in range(1, blade.trail.size()):
			var alpha := float(index) / float(blade.trail.size()) * 0.32
			draw_line(blade.trail[index - 1], blade.trail[index], Color(color, alpha), 1.0 + alpha * 5.0, true)
		var center := blade.visual_position
		var rotation_angle := blade.direction.angle() + (MAX_LIFETIME - blade.life_left) * 15.0
		draw_circle(center, BLADE_RADIUS + 4.0, Color(color, 0.08))
		draw_arc(center, BLADE_RADIUS, rotation_angle - 1.8, rotation_angle + 1.8, 16, color, 3.0, true)
		draw_arc(center + blade.direction * 2.0, BLADE_RADIUS * 0.7, rotation_angle - 1.6, rotation_angle + 1.6, 12, Color(0.95, 0.98, 1.0, 0.95), 1.4, true)
		if blade.flash_left > 0.0:
			draw_arc(center, BLADE_RADIUS + 5.0, 0.0, TAU, 16, Color(0.96, 0.97, 1.0, blade.flash_left * 7.0), 1.3, true)

func _play_sound(pitch: float) -> void:
	if _sound == null or _sound_left > 0.0:
		return
	if is_instance_valid(player) and player.player_feedback != null:
		set_sfx_volume_db(float(player.player_feedback.sfx_volume_db))
	_sound_left = 0.05
	_sound.pitch_scale = pitch
	_sound.play()

func set_sfx_volume_db(value: float) -> void:
	if _sound != null:
		_sound.volume_db = clampf(-21.0 + value, -80.0, 6.0)

static func _make_sound() -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var samples := 1764
	var data := PackedByteArray()
	data.resize(samples * 2)
	var phase := 0.0
	for index in range(samples):
		var t := float(index) / float(samples)
		phase += TAU * lerpf(1450.0, 540.0, t) / 22050.0
		var amplitude := sin(t * PI) * (1.0 - t) * 0.18
		data.encode_s16(index * 2, int(sin(phase) * amplitude * 32767.0))
	sound.data = data
	return sound
