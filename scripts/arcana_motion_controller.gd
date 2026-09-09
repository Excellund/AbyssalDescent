extends Node2D
const ARENA_BOUNDARY := preload("res://scripts/shared/arena_boundary.gd")
## Owns special movement, never dash immunity. The player supplies accepted input
## edges; held buttons cannot arm abilities after a modal or a failed action.

const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const BLAST_EFFECT := preload("res://scripts/blast_impact_effect.gd")
const BLAST_RANGE_MIN := 100.0
const BLAST_RANGE_MAX := 160.0
const BLAST_DAMAGE_MULT_MIN := 1.5
const BLAST_DAMAGE_MULT_MAX := 2.5
const BLAST_ARC_DEGREES := 70.0
const HOLD_TIME := 0.25
const FULL_CHARGE_TIME := 0.65
const BLAST_RECHARGE := 1.8
const ORBIT_SPEED := 540.0
const ORBIT_ACQUIRE_RANGE := 260.0
const ORBIT_CUT_DAMAGE_RATIO := 0.35
const ORBIT_DURATION := 1.4
const ORBIT_ACQUIRE_WINDOW := 0.70
const TRANSFER_DURATION_CAP := 2.4
const ORBIT_RELEASE_WARNING := 0.35
const ORBIT_RELEASE_HINT := 0.15
const ORBIT_DIAL_RADIUS := 34.0
enum Motion { NONE, RECOIL, ORBIT, CARRY }

var player: CharacterBody2D
var motion: Motion = Motion.NONE
var blast_charges: int = 0
var recharge_left: float = 0.0
var charge_hold: float = -1.0
var dash_hold: float = -1.0
var _pending_orbit_anchor: Node2D
var anchor: Node2D
var orbit_elapsed: float = 0.0
var orbit_limit: float = ORBIT_DURATION
var orbit_transferred: bool = false
var orbit_sign: float = 1.0
var tangent: Vector2 = Vector2.RIGHT
var motion_origin: Vector2
var last_contact_position: Vector2 = Vector2.INF
var recoil_direction: Vector2
var recoil_initial_direction: Vector2
var recoil_left: float = 0.0
var recoil_speed: float = 0.0
var carry_left: float = 0.0
var contact_cooldowns: Dictionary = {}
var _known_charge_cap: int = 0
var _cancel_generation: int = 0
var _cue_left: float = 0.0
var _visual: Dictionary = {}
var _visual_life: float = 0.0
var _preview_anchor: Node2D
var _trail: Array[Vector2] = []
var _blast_effects: Array[Node2D] = []
var _blast_serial: int = 0
var _active_blast_effect: BLAST_EFFECT
var _sound: AudioStreamPlayer
var _blast_sound: AudioStreamWAV
var _hook_sound: AudioStreamWAV
var _orbit_end_sound: AudioStreamWAV
var _orbit_warning_played := false
var _orbit_hint_left := 0.0
var _orbit_hint_origin := Vector2.ZERO
var _orbit_hint_direction := Vector2.RIGHT

var _orbit_interaction: Dictionary = {}
var _recoil_interaction: Dictionary = {}

func initialize(owner_player: CharacterBody2D) -> void:
	player = owner_player
	z_index = 3
	if DisplayServer.get_name() != "headless":
		_sound = AudioStreamPlayer.new()
		_sound.volume_db = -15.0
		if AudioServer.get_bus_index("SFX") >= 0:
			_sound.bus = &"SFX"
		add_child(_sound)
		_blast_sound = _make_sound(false)
		_hook_sound = _make_sound(true)
		_orbit_end_sound = _make_sound(true, true)

func owns_movement() -> bool:
	return motion != Motion.NONE

## Personal control feedback reads the movement owner's real clock. Remote
## tethers retain their existing presentation without another player's timer.
func get_orbit_seconds_left() -> float:
	if not _allowed() or motion != Motion.ORBIT or not _anchor_alive():
		return -1.0
	return maxf(0.0, orbit_limit - orbit_elapsed)

static func blast_range(strength: float, reach_scale: float) -> float:
	return lerpf(BLAST_RANGE_MIN, BLAST_RANGE_MAX, clampf(strength, 0.0, 1.0)) * reach_scale

func _allowed() -> bool:
	return is_instance_valid(player) and bool(player._is_local_control_owner()) and not bool(player.encounter_input_frozen) and bool(player._is_alive_state) and bool(player.combat_damage_enabled)

func _held(action: StringName) -> bool:
	return not player._combat_actions_awaiting_release.has(action) and Input.is_action_pressed(action)

func on_primary_pressed(accepted: bool) -> void:
	_refresh_capacity()
	if accepted and _allowed() and bool(player.reward_blast_drive) and blast_charges > 0 and not player._is_dash_active():
		charge_hold = 0.0

func on_dash_started() -> void:
	charge_hold = -1.0
	_finish_motion(false)
	_clear_orbit_request()
	dash_hold = 0.0 if bool(player.reward_razor_orbit) else -1.0
	if dash_hold >= 0.0 and _allowed():
		# Camera follow and enemy movement must not erase an intentional press aim.
		_pending_orbit_anchor = find_anchor(_orbit_aim_world_position())
		_preview_anchor = _pending_orbit_anchor

func _orbit_aim_world_position() -> Vector2:
	return player.get_global_mouse_position()

func _clear_orbit_request() -> void:
	dash_hold = -1.0
	_pending_orbit_anchor = null

func _refresh_capacity() -> void:
	var cap := 0 if not bool(player.reward_blast_drive) else (2 if int(player.blast_drive_stacks) >= 2 else 1)
	if cap > _known_charge_cap:
		blast_charges += cap - _known_charge_cap
	_known_charge_cap = cap
	blast_charges = mini(blast_charges, cap)

func tick(delta: float) -> void:
	if not _allowed():
		cancel()
		return
	_refresh_capacity()
	if blast_charges < _known_charge_cap:
		recharge_left -= delta
		if recharge_left <= 0.0:
			blast_charges += 1
			recharge_left = BLAST_RECHARGE if blast_charges < _known_charge_cap else 0.0
	for id in contact_cooldowns.keys():
		contact_cooldowns[id] = float(contact_cooldowns[id]) - delta
		if float(contact_cooldowns[id]) <= 0.0:
			contact_cooldowns.erase(id)
	if charge_hold >= 0.0:
		if _held(&"attack"):
			charge_hold = minf(FULL_CHARGE_TIME, charge_hold + delta)
			_visual["charge"] = charge_hold / FULL_CHARGE_TIME
			_visual_life = 0.3
		else:
			var released_hold := charge_hold
			charge_hold = -1.0
			if released_hold >= HOLD_TIME and not player._combat_actions_awaiting_release.has(&"attack"):
				release_blast(inverse_lerp(HOLD_TIME, FULL_CHARGE_TIME, released_hold))
	if dash_hold >= 0.0:
		if not _held(&"dash"):
			_clear_orbit_request()
		else:
			dash_hold += delta
			if dash_hold >= ORBIT_ACQUIRE_WINDOW:
				_clear_orbit_request()
			elif dash_hold >= HOLD_TIME and not player._is_dash_active():
				var candidate := _pending_orbit_anchor if _valid_orbit_anchor(_pending_orbit_anchor) else find_anchor(_orbit_aim_world_position())
				if candidate != null:
					start_orbit(candidate)
	if motion == Motion.ORBIT and not _held(&"dash"):
		detach(true)
	_cue_left -= delta
	if _cue_left <= 0.0:
		_cue_left = 0.10
		_preview_anchor = _pending_orbit_anchor if dash_hold >= 0.0 and _valid_orbit_anchor(_pending_orbit_anchor) else (find_anchor(_orbit_aim_world_position()) if bool(player.reward_razor_orbit) else null)
		_publish_state()

func release_blast(strength: float) -> void:
	if not _allowed() or blast_charges <= 0 or not bool(player.reward_blast_drive) or float(player._voidfire_lockout_left) > 0.0:
		return
	strength = clampf(strength, 0.0, 1.0)
	var direction: Vector2 = player._get_mouse_attack_direction()
	_finish_motion(true)
	_clear_orbit_request()
	blast_charges -= 1
	if recharge_left <= 0.0:
		recharge_left = BLAST_RECHARGE
	motion_origin = player.global_position
	last_contact_position = Vector2.INF
	var generation := _cancel_generation
	_recoil_interaction = player._capture_combat_action("blast_drive")
	var previous := DAMAGEABLE.begin_interaction_scope(_recoil_interaction)
	player.perform_motion_blast(direction, strength)
	DAMAGEABLE.end_interaction_scope(previous)
	# A killing hit may synchronously open rewards or end the run.
	if generation != _cancel_generation or not _allowed():
		return
	recoil_direction = -direction
	recoil_initial_direction = recoil_direction
	recoil_left = lerpf(90.0, 170.0, strength)
	recoil_speed = recoil_left / 0.20
	motion = Motion.RECOIL
	player.attack_lock_time_left = 0.0
	player._clear_iron_retort_brace(false)
	_publish_state() # Clear the tether and charge ring in the release frame.

func find_anchor(cursor: Vector2, enemies_only: bool = false) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	var candidates: Array[Node] = get_tree().get_nodes_in_group("enemies")
	if not enemies_only and int(player.razor_orbit_stacks) >= 2:
		candidates.append_array(get_tree().get_nodes_in_group("arena_columns"))
	for node in candidates:
		if not (node is Node2D) or node.is_queued_for_deletion():
			continue
		var candidate := node as Node2D
		var radius := _anchor_radius(candidate)
		var cursor_distance := cursor.distance_to(candidate.global_position)
		if cursor_distance > radius + 36.0:
			continue
		if not _valid_orbit_anchor(candidate):
			continue
		if cursor_distance < best_distance:
			best = candidate
			best_distance = cursor_distance
	return best

func _valid_orbit_anchor(candidate_ref: Variant) -> bool:
	# Freed objects must be checked before a typed argument/cast: Godot rejects
	# a stale Node2D reference before a typed validator can inspect it.
	if not is_instance_valid(candidate_ref) or not (candidate_ref is Node2D):
		return false
	var candidate := candidate_ref as Node2D
	if candidate.is_queued_for_deletion():
		return false
	if candidate.is_in_group("enemies"):
		if DAMAGEABLE._read_target_health(candidate) <= 0:
			return false
	elif not candidate.is_in_group("arena_columns") or int(player.razor_orbit_stacks) < 2:
		return false
	return player.global_position.distance_to(candidate.global_position) <= ORBIT_ACQUIRE_RANGE * float(player.razor_orbit_reach_scale) and _anchor_visible(candidate)

func _anchor_visible(candidate: Node2D) -> bool:
	if player.get_world_2d() == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(player.global_position, candidate.global_position, 1)
	var excluded: Array[RID] = [player.get_rid()]
	# Grapple sight is blocked by arena cover, not a foreground enemy or ally.
	# Combat bodies remain solid for the subsequent physical Orbit movement.
	for group in [&"enemies", &"combat_players"]:
		for body in get_tree().get_nodes_in_group(group):
			if is_instance_valid(body) and body is CollisionObject2D:
				var body_rid := (body as CollisionObject2D).get_rid()
				if not excluded.has(body_rid):
					excluded.append(body_rid)
	query.exclude = excluded
	var result := player.get_world_2d().direct_space_state.intersect_ray(query)
	return result.is_empty() or result.get("collider") == candidate

func _anchor_radius(candidate: Node2D) -> float:
	if candidate.is_in_group("arena_columns"):
		return float(candidate.get_meta("column_radius", 28.0))
	return float(player._get_body_radius_for(candidate, 13.0))

func start_orbit(candidate: Node2D) -> void:
	if not is_instance_valid(candidate):
		return
	_clear_orbit_request()
	_finish_motion(true)
	anchor = candidate
	_orbit_interaction = player._dash_interaction.duplicate(true) if not player._dash_interaction.is_empty() else player._capture_combat_action("razor_orbit")
	motion = Motion.ORBIT
	motion_origin = player.global_position
	last_contact_position = Vector2.INF
	orbit_elapsed = 0.0
	orbit_limit = ORBIT_DURATION
	orbit_transferred = false
	contact_cooldowns.clear()
	var radial := (player.global_position - anchor.global_position).normalized()
	if radial.is_zero_approx():
		radial = -Vector2(player.dash_direction)
	# Choose the travel direction once. Re-evaluating a held world-space input
	# against the rotating tangent would make the orbit reverse mid-circle.
	var positive_tangent := radial.rotated(PI * 0.5)
	orbit_sign = -1.0 if Vector2(player.dash_direction).dot(positive_tangent) < 0.0 else 1.0
	tangent = positive_tangent * orbit_sign
	player.attack_lock_time_left = 0.0
	player._clear_iron_retort_brace(false)
	_play_sound(true)
	_publish_state()

func process_movement(delta: float, move_input: Vector2) -> bool:
	if not owns_movement():
		return false
	var start := player.global_position
	var correction := ARENA_BOUNDARY.sweep(start, Vector2.ZERO, EnemyReplicationService.get_current_room_bounds())
	if bool(correction.get("outside", false)):
		player.global_position = correction["position"]
		player.velocity = Vector2.ZERO
		cancel()
		return true # Arena shrink is a clamp, not a traveled cutting segment.
	match motion:
		Motion.RECOIL:
			if int(player.blast_drive_stacks) >= 3 and not move_input.is_zero_approx():
				var angle := clampf(recoil_initial_direction.angle_to(move_input), -PI / 4.0, PI / 4.0)
				recoil_direction = recoil_initial_direction.rotated(angle)
			var step := recoil_direction * minf(recoil_left, recoil_speed * delta)
			var collided := _move_within_arena(step)
			player.velocity = (player.global_position - start) / maxf(delta, 0.0001)
			recoil_left -= player.global_position.distance_to(start)
			if collided or recoil_left < 0.1:
				_finish_motion(true)
		Motion.CARRY:
			var movement_delta := minf(maxf(delta, 0.0), maxf(carry_left, 0.0))
			carry_left = maxf(0.0, carry_left - movement_delta)
			var collided := _move_within_arena(tangent * minf(ORBIT_SPEED, float(player.max_speed) * 1.5) * movement_delta)
			player.velocity = (player.global_position - start) / maxf(delta, 0.0001)
			if collided or carry_left <= 0.0:
				motion = Motion.NONE
		Motion.ORBIT:
			orbit_elapsed += delta
			if not _anchor_alive():
				var next_anchor := find_anchor(_orbit_aim_world_position(), true) if int(player.razor_orbit_stacks) >= 3 and not orbit_transferred else null
				if next_anchor == null or next_anchor == anchor:
					detach(true)
					return true
				anchor = next_anchor
				orbit_transferred = true
				orbit_limit = minf(TRANSFER_DURATION_CAP, orbit_elapsed + ORBIT_DURATION)
				_orbit_warning_played = false
				_play_sound(true)
			if orbit_elapsed >= orbit_limit:
				detach(true)
				return true
			var center := anchor.global_position
			var offset := start - center
			var radius := maxf(float(player.body_radius_cache) + _anchor_radius(anchor) + 14.0, 0.9 * float(player.attack_range))
			radius = minf(170.0, radius)
			var radial := offset.normalized() if offset.length() > 0.1 else Vector2.RIGHT
			var next_radius := move_toward(offset.length(), radius, ORBIT_SPEED * delta)
			var angle_step := ORBIT_SPEED * delta / maxf(radius, 1.0) if absf(offset.length() - radius) < 12.0 else 0.0
			var next_radial := radial.rotated(angle_step * orbit_sign)
			tangent = next_radial.rotated(PI * 0.5) * orbit_sign
			var step := (center + next_radial * next_radius - start).limit_length(ORBIT_SPEED * delta)
			var collided := _move_within_arena(step)
			player.velocity = (player.global_position - start) / maxf(delta, 0.0001)
			_apply_cut_contacts(start, player.global_position)
			if motion != Motion.ORBIT:
				return true
			if collided:
				detach(false)
	_trail.append(start)
	if _trail.size() > 12:
		_trail.pop_front()
	return true

func _move_within_arena(step: Vector2) -> bool:
	var boundary := ARENA_BOUNDARY.sweep(player.global_position, step, EnemyReplicationService.get_current_room_bounds())
	if bool(boundary.get("outside", false)):
		player.global_position = boundary["position"]
		return true
	var collision := player.move_and_collide(step * float(boundary.get("fraction", 1.0)))
	return collision != null or not boundary.is_empty()

func _anchor_alive() -> bool:
	return is_instance_valid(anchor) and not anchor.is_queued_for_deletion() and (not anchor.is_in_group("enemies") or DAMAGEABLE._read_target_health(anchor) > 0)

func _apply_cut_contacts(start: Vector2, finish: Vector2) -> void:
	var generation := _cancel_generation
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node2D) or DAMAGEABLE._read_target_health(node) <= 0:
			continue
		var enemy := node as Node2D
		var id := enemy.get_instance_id()
		if contact_cooldowns.has(id):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(enemy.global_position, start, finish)
		# The cutting ribbon reaches inward from the orbit, while contact damage
		# and boss attacks still threaten the player normally.
		var reach := maxf(28.0, float(player.attack_range) * 0.9)
		if enemy.global_position.distance_to(closest) > reach + _anchor_radius(enemy):
			continue
		contact_cooldowns[id] = 0.30
		var amount := maxi(1, int(round(float(player.damage) * ORBIT_CUT_DAMAGE_RATIO * float(player.razor_orbit_damage_scale))))
		DAMAGEABLE.apply_damage(enemy, amount, INTERACTIONS.damage_context(_orbit_interaction, "razor_orbit", {"is_ground_attack": true, "secondary": true, "damage_coefficient": ORBIT_CUT_DAMAGE_RATIO * float(player.razor_orbit_damage_scale)}))
		if generation != _cancel_generation:
			return
		last_contact_position = finish

func record_contact() -> void:
	if owns_movement():
		last_contact_position = player.global_position

func detach(carry: bool) -> void:
	var show_departure := carry and motion == Motion.ORBIT and _allowed()
	var departure := player.global_position
	var direction := tangent.normalized()
	_finish_motion(true)
	dash_hold = -1.0
	if carry:
		motion = Motion.CARRY
		carry_left = 0.15
	if show_departure:
		_orbit_hint_origin = departure
		_orbit_hint_direction = direction
		_orbit_hint_left = ORBIT_RELEASE_HINT
	_publish_state()

func _finish_motion(completed: bool) -> void:
	if completed and (motion == Motion.ORBIT or motion == Motion.RECOIL):
		# Completion belongs to the same movement that produced its damage.
		# It cannot create fresh Crown allowances for a deferred Tempo Burst.
		var action := _orbit_interaction if motion == Motion.ORBIT else _recoil_interaction
		var previous := DAMAGEABLE.begin_interaction_scope(action)
		player.on_arcana_motion_completed(motion_origin, last_contact_position)
		player._complete_shared_movement("orbit" if motion == Motion.ORBIT else "recoil", player.global_position)
		DAMAGEABLE.end_interaction_scope(previous)
	motion = Motion.NONE
	_orbit_interaction.clear()
	_recoil_interaction.clear()
	anchor = null
	recoil_left = 0.0
	contact_cooldowns.clear()
	_orbit_hint_left = 0.0
	_orbit_warning_played = false

func cancel(reset_charges: bool = false) -> void:
	_orbit_interaction.clear()
	_cancel_generation += 1
	charge_hold = -1.0
	_clear_orbit_request()
	_finish_motion(false)
	_trail.clear()
	_visual.clear()
	_preview_anchor = null
	# Already discharged blasts finish their brief animation; pending gestures
	# never create one. Effects are freed with the player across scene changes.
	if reset_charges:
		_known_charge_cap = 0
		blast_charges = 0
		recharge_left = 0.0
	queue_redraw()

func _publish_state() -> void:
	var charging := charge_hold >= 0.0
	var orbiting := motion == Motion.ORBIT and is_instance_valid(anchor)
	var state := {"charge": clampf(charge_hold / FULL_CHARGE_TIME, 0.0, 1.0) if charging else -1.0, "orbit": orbiting}
	if orbiting:
		state["anchor"] = anchor.global_position
	if charging or orbiting or not _visual.is_empty():
		player._broadcast_cue_event("motion_arcana", state)
	_visual = state if charging or orbiting else {}
	_visual_life = 0.3

func apply_visual_state(state: Dictionary) -> void:
	_visual = state.duplicate()
	_visual_life = 0.3
	queue_redraw()

func show_blast(direction: Vector2, range_value: float, origin: Vector2 = Vector2.INF, arc_degrees: float = BLAST_ARC_DEGREES, serial: int = 0) -> Node2D:
	for i in range(_blast_effects.size() - 1, -1, -1):
		if not is_instance_valid(_blast_effects[i]):
			_blast_effects.remove_at(i)
	while _blast_effects.size() >= 4:
		var oldest := _blast_effects.pop_front() as Node2D
		if is_instance_valid(oldest):
			oldest.queue_free()
	var effect := BLAST_EFFECT.new()
	add_child(effect)
	effect.initialize(origin if origin.is_finite() else player.global_position, direction, range_value, arc_degrees, serial)
	_blast_effects.append(effect)
	_active_blast_effect = effect
	_play_sound(false)
	return effect

func publish_blast(origin: Vector2, direction: Vector2, range_value: float, arc_degrees: float) -> void:
	_blast_serial += 1
	show_blast(direction, range_value, origin, arc_degrees, _blast_serial)
	player._broadcast_cue_event("motion_blast", {"position": origin, "direction": direction, "range": range_value, "arc": arc_degrees, "serial": _blast_serial}, true)

func record_blast_hit(position: Vector2) -> void:
	if not is_instance_valid(_active_blast_effect) or _active_blast_effect.hits.size() >= BLAST_EFFECT.MAX_HITS:
		return
	_active_blast_effect.add_hit(position)
	player._broadcast_cue_event("motion_blast_hit", {"position": position, "serial": _active_blast_effect.serial}, true)

func show_blast_hit(position: Vector2, serial: int) -> void:
	for node in _blast_effects:
		if not is_instance_valid(node):
			continue
		var effect := node as BLAST_EFFECT
		if is_instance_valid(effect) and effect.serial == serial:
			effect.add_hit(position)
			return

func _process(delta: float) -> void:
	_orbit_hint_left = maxf(0.0, _orbit_hint_left - delta)
	var orbit_left := get_orbit_seconds_left()
	if orbit_left > 0.0 and orbit_left <= ORBIT_RELEASE_WARNING and not _orbit_warning_played:
		_orbit_warning_played = true
		_play_sound(true, true)
	_visual_life = maxf(0.0, _visual_life - delta)
	if _visual_life <= 0.0:
		_visual.clear()
	if not owns_movement() and not _trail.is_empty():
		_trail.pop_front()
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(player) or not player.visible:
		return
	var orange := Color(1.0, 0.47, 0.16, 0.9)
	var blue := Color(0.5, 0.91, 1.0, 0.85)
	var charge := float(_visual.get("charge", -1.0))
	if charge >= 0.0:
		draw_arc(Vector2.ZERO, 21.0 + charge * 8.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 32, orange, 2.5, true)
		for i in range(blast_charges):
			draw_circle(Vector2(-5.0 + i * 10.0, -34.0), 2.5, orange)
	if bool(_visual.get("orbit", false)):
		var local_anchor := to_local(Vector2(_visual.get("anchor", global_position)))
		draw_line(Vector2.ZERO, local_anchor, Color(0.3, 0.7, 1.0, 0.24), 6.0, true)
		draw_line(Vector2.ZERO, local_anchor, blue, 1.5, true)
		draw_arc(local_anchor, 12.0, 0.0, TAU, 20, blue, 1.5, true)
	var orbit_left := get_orbit_seconds_left()
	if orbit_left >= 0.0:
		var remaining := clampf(orbit_left / ORBIT_DURATION, 0.0, 1.0)
		var ending := orbit_left <= ORBIT_RELEASE_WARNING
		var cue_color := Color(0.83, 0.97, 1.0, 0.95) if ending else blue
		draw_arc(Vector2.ZERO, ORBIT_DIAL_RADIUS, 0.0, TAU, 48, Color(blue, 0.14), 1.5, true)
		if remaining > 0.0:
			draw_arc(Vector2.ZERO, ORBIT_DIAL_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * remaining, 48, cue_color, 2.0, true)
		if ending:
			_draw_orbit_departure_hint(Vector2.ZERO, tangent, cue_color)
	elif _orbit_hint_left > 0.0 and _allowed():
		_draw_orbit_departure_hint(to_local(_orbit_hint_origin), _orbit_hint_direction, Color(blue, 0.9 * _orbit_hint_left / ORBIT_RELEASE_HINT))
	if _allowed() and bool(player.reward_razor_orbit) and not bool(player.encounter_input_frozen):
		var preview := _preview_anchor
		if is_instance_valid(preview):
			var target := to_local(preview.global_position)
			draw_arc(target, _anchor_radius(preview) + 7.0, 0.0, TAU, 24, Color(blue, 0.5), 1.5, true)
	for i in range(1, _trail.size()):
		draw_line(to_local(_trail[i - 1]), to_local(_trail[i]), Color(blue, float(i) / _trail.size() * 0.30), 3.0, true)

func _draw_orbit_departure_hint(origin: Vector2, direction: Vector2, color: Color) -> void:
	var forward := direction.normalized()
	var tip := origin + forward * (ORBIT_DIAL_RADIUS + 12.0)
	var back := tip - forward * 7.0
	var side := forward.orthogonal() * 4.0
	draw_line(back + side, tip, color, 2.0, true)
	draw_line(back - side, tip, color, 2.0, true)

func _play_sound(hook: bool, orbit_ending: bool = false) -> void:
	if _sound != null:
		if player.player_feedback != null:
			set_sfx_volume_db(float(player.player_feedback.sfx_volume_db))
		_sound.stream = _orbit_end_sound if orbit_ending else (_hook_sound if hook else _blast_sound)
		_sound.play()

func set_sfx_volume_db(value: float) -> void:
	if _sound != null:
		_sound.volume_db = clampf(-15.0 + value, -80.0, 6.0)

func _make_sound(hook: bool, orbit_ending: bool = false) -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var duration := 0.09 if orbit_ending else (0.14 if hook else 0.24)
	var samples := int(22050 * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 913
	var phase := 0.0
	for i in range(samples):
		var t := float(i) / samples
		var frequency := lerpf(1100.0, 300.0, t) if hook else lerpf(140.0, 45.0, t)
		if orbit_ending:
			frequency = lerpf(620.0, 240.0, t)
		phase += TAU * frequency / 22050.0
		var value := (sin(phase) * 0.65 + rng.randf_range(-1.0, 1.0) * (0.12 if hook else 0.35)) * pow(1.0 - t, 2.0)
		if orbit_ending:
			value *= 0.45
		data.encode_s16(i * 2, int(value * 24000.0))
	sound.data = data
	return sound
