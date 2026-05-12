extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

const STATE_STALK := 0
const STATE_TELEGRAPH := 1
const STATE_REFLECT := 2
const STATE_COOLDOWN := 3

# --- Scale & Health ---
@export var max_health_apex: int = 660
@export var body_draw_radius: float = 36.0
@export var collision_shape_radius: float = 32.0

# --- Movement ---
@export var move_speed: float = 88.0
@export var acceleration: float = 720.0
@export var deceleration: float = 940.0
@export var stalk_band_min: float = 170.0
@export var stalk_band_max: float = 260.0

# --- Contact ---
@export var contact_damage: int = 26
@export var contact_attack_range: float = 70.0
@export var contact_attack_interval: float = 0.85

# --- State timings ---
@export var stalk_duration_min: float = 1.4
@export var stalk_duration_max: float = 2.0
@export var telegraph_duration: float = 1.30
@export_range(0.0, 0.85, 0.05) var telegraph_settle_fraction: float = 0.45
@export var reflect_duration: float = 1.7
@export var cooldown_duration: float = 1.3

# --- Echoes ---
@export var echo_speed_cap: float = 880.0
@export var echo_min_speed: float = 680.0
@export var echo_radius: float = 32.0
@export var echo_damage: int = 26
@export var echo_lifetime: float = 2.6
@export var reflect_echo_count: int = 4
@export var reflect_echo_interval: float = 0.4
@export var mirror_line_half_length: float = 3200.0

# --- Seam beam (line itself damages while in REFLECT) ---
@export var seam_beam_half_thickness: float = 22.0
@export var seam_beam_tick_damage: int = 14
@export var seam_beam_tick_interval: float = 0.45

# --- Sundered phase: when health drops to or below half max, gain a flat damage reduction
# (mirroring Sovereign's Orbital Fortress reduction pattern) and split the seam into a
# perpendicular twin so a second mirror exists opposite the first.
@export_range(0.0, 0.95, 0.05) var sundered_damage_reduction: float = 0.70
@export_range(0.0, 1.0, 0.05) var sundered_health_threshold: float = 0.5
@export var sundered_hit_flash_duration: float = 0.16
# Damage reduction is a brief window — about the time it takes for the twin seam to spawn and start firing
# (grace flash + telegraph + a beat into reflect). After it elapses the boss is vulnerable again, but the
# twin axis remains active for the rest of the fight as the lasting Sundered consequence.
@export var sundered_reduction_duration: float = 2.0

@export var arena_size: Vector2 = Vector2(1160.0, 860.0)
@export var arena_center_world: Vector2 = Vector2.ZERO

@export var health_bar_size_apex: Vector2 = Vector2(110.0, 12.0)
@export var health_bar_offset_apex: Vector2 = Vector2(-55.0, -64.0)

var _state: int = STATE_STALK
var _state_time_left: float = 0.0
var _contact_attack_cooldown_left: float = 0.0
var _reflect_echoes_remaining: int = 0
var _reflect_next_echo_time_left: float = 0.0
var _seam_beam_tick_left: float = 0.0

# Telegraph axis: line through arena center with given unit normal vector.
# A point P is reflected as: P - 2 * dot((P - origin), normal) * normal
var _axis_normal: Vector2 = Vector2.ZERO
var _axis_origin: Vector2 = Vector2.ZERO
var _axis_prev_normal: Vector2 = Vector2.ZERO
var _axis_prev_origin: Vector2 = Vector2.ZERO
var _axis_target_normal: Vector2 = Vector2.ZERO
var _axis_target_origin: Vector2 = Vector2.ZERO
var _telegraph_total: float = 0.0

# Active echoes. Each entry: {origin: Vector2, velocity: Vector2, time_left: float, time_total: float, hit: bool}
var _active_echoes: Array = []

# Sundered phase state. _twin_pending flips on at the half-HP threshold and grants damage reduction
# immediately, but the twin seam itself only becomes active (drawn + damaging) when the next telegraph
# starts so it visibly rotates into place instead of popping in mid-reflect on top of the player.
var _twin_pending: bool = false
var _twin_active: bool = false
var _sundered_flash_time_left: float = 0.0
var _sundered_hit_flash_left: float = 0.0
var _sundered_reduction_left: float = 0.0
var _sundered_health_fill_default: Color = Color(0.0, 0.0, 0.0, 0.0)
var _sundered_health_bg_default: Color = Color(0.0, 0.0, 0.0, 0.0)
var _sundered_health_colors_cached: bool = false
var _next_echo_id: int = 0

func should_force_network_runtime_state_sampling() -> bool:
	return _state == STATE_TELEGRAPH or _state == STATE_REFLECT or not _active_echoes.is_empty()

func get_priority_network_sync_interval_sec() -> float:
	# Tighten sync to ~33Hz during the telegraph/reflect attack window so the seam rotation and echo
	# spawns reach joiners with low jitter; idle states fall back to the broadcaster default.
	if _state == STATE_TELEGRAPH or _state == STATE_REFLECT or not _active_echoes.is_empty():
		return 0.03
	return 0.0

func _get_custom_network_runtime_state() -> Dictionary:
	# Short keys keep the per-tick custom payload under the broadcaster's ~900B size limit. With 4
	# active echoes the long-key version exceeded the cap and `_fit_state_to_size_limit` would erase
	# `custom` wholesale, hiding any echoes that spawned after the first one or two. time_total is
	# elided (joiner uses echo_lifetime) and hit is elided (host removes hit echoes immediately, so
	# this array only ever carries live ones).
	var echoes_payload: Array = []
	for echo_variant in _active_echoes:
		if echo_variant is Dictionary:
			var echo := echo_variant as Dictionary
			echoes_payload.append({
				"i": int(echo.get("id", 0)),
				"o": echo.get("origin", Vector2.ZERO),
				"v": echo.get("velocity", Vector2.ZERO),
				"t": float(echo.get("time_left", 0.0))
			})
	return {
		"s": _state,
		"cc": _contact_attack_cooldown_left,
		"pn": _axis_prev_normal,
		"po": _axis_prev_origin,
		"tn": _axis_target_normal,
		"to": _axis_target_origin,
		"tt": _telegraph_total,
		"tp": _twin_pending,
		"ta": _twin_active,
		"hf": _sundered_hit_flash_left,
		"sr": _sundered_reduction_left,
		"e": echoes_payload
	}

func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	if custom_state.is_empty():
		return
	var prev_state := _state
	_state = int(custom_state.get("s", _state))
	if prev_state != _state:
		# State transitioned this packet — reset the local timer to the canonical duration so the joiner
		# can tick it down locally between syncs without ever needing state_time_left on the wire.
		_state_time_left = _local_duration_for_state(_state)
	_contact_attack_cooldown_left = float(custom_state.get("cc", _contact_attack_cooldown_left))
	_axis_prev_normal = custom_state.get("pn", _axis_prev_normal) as Vector2
	_axis_prev_origin = custom_state.get("po", _axis_prev_origin) as Vector2
	_axis_target_normal = custom_state.get("tn", _axis_target_normal) as Vector2
	_axis_target_origin = custom_state.get("to", _axis_target_origin) as Vector2
	_telegraph_total = float(custom_state.get("tt", _telegraph_total))
	_twin_pending = bool(custom_state.get("tp", _twin_pending))
	_twin_active = bool(custom_state.get("ta", _twin_active))
	_sundered_hit_flash_left = float(custom_state.get("hf", _sundered_hit_flash_left))
	_sundered_reduction_left = float(custom_state.get("sr", _sundered_reduction_left))
	_merge_remote_echoes(custom_state.get("e", []) as Array)
	# Axis is purely derived from prev/target/time. Recompute locally so incoming snapshots never
	# directly overwrite the visible axis position (which would shake against local extrapolation).
	if _state == STATE_TELEGRAPH:
		_advance_axis_rotation()
	else:
		_axis_normal = _axis_target_normal
		_axis_origin = _axis_target_origin

func _local_duration_for_state(state_id: int) -> float:
	match state_id:
		STATE_TELEGRAPH:
			return maxf(0.001, telegraph_duration)
		STATE_REFLECT:
			return maxf(0.001, reflect_duration)
		STATE_COOLDOWN:
			return maxf(0.001, cooldown_duration)
		STATE_STALK:
			return maxf(0.001, (stalk_duration_min + stalk_duration_max) * 0.5)
		_:
			return 0.0

func _merge_remote_echoes(incoming: Array) -> void:
	# Append-only merge: keep our locally-simulated echoes intact (origin/velocity/time_left), only adding
	# new ones the host has spawned. Hit flagging is implicit: host removes hit echoes from its array, so
	# any id missing from incoming is either hit or expired — we let the local sim despawn it on time_left
	# expiry to avoid pop. Wire payload uses short keys (i/o/v/t) for size; we re-expand to long keys here
	# so the rest of the script (drawing, hit checks, etc.) keeps using the readable names.
	var incoming_ids: Dictionary = {}
	var incoming_by_id: Dictionary = {}
	for echo_variant in incoming:
		if not (echo_variant is Dictionary):
			continue
		var incoming_echo := echo_variant as Dictionary
		var id := int(incoming_echo.get("i", 0))
		if id == 0:
			continue
		incoming_ids[id] = true
		incoming_by_id[id] = incoming_echo
	var survivors: Array = []
	var local_ids: Dictionary = {}
	for echo_variant in _active_echoes:
		if not (echo_variant is Dictionary):
			continue
		var local_echo := echo_variant as Dictionary
		var id := int(local_echo.get("id", 0))
		local_ids[id] = true
		if id != 0 and not incoming_ids.has(id):
			# Host says this echo is gone; let local sim despawn it naturally on time_left expiry to avoid pop.
			if float(local_echo.get("time_left", 0.0)) <= 0.0:
				continue
		survivors.append(local_echo)
	for id_variant in incoming_ids.keys():
		var id := int(id_variant)
		if local_ids.has(id):
			continue
		var incoming_echo := incoming_by_id[id] as Dictionary
		survivors.append({
			"id": id,
			"origin": incoming_echo.get("o", Vector2.ZERO),
			"velocity": incoming_echo.get("v", Vector2.ZERO),
			"time_left": float(incoming_echo.get("t", 0.0)),
			"time_total": echo_lifetime,
			"hit": false
		})
	_active_echoes = survivors

func _ready() -> void:
	max_health = max_health_apex
	super._ready()
	crowd_separation_radius = 80.0
	crowd_separation_strength = 110.0
	configure_health_bar_visuals(health_bar_offset_apex, health_bar_size_apex)
	_state_time_left = randf_range(stalk_duration_min, stalk_duration_max)
	for child in get_children():
		if child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if shape_node.shape is CircleShape2D:
				(shape_node.shape as CircleShape2D).radius = collision_shape_radius
			break
	_resolve_arena_center()
	_initialize_default_axis()

func _initialize_default_axis() -> void:
	_axis_normal = Vector2.RIGHT.rotated(randf() * TAU)
	_axis_origin = arena_center_world
	_axis_prev_normal = _axis_normal
	_axis_prev_origin = _axis_origin
	_axis_target_normal = _axis_normal
	_axis_target_origin = _axis_origin

func _resolve_arena_center() -> void:
	if arena_center_world == Vector2.ZERO:
		arena_center_world = global_position

func _process_behavior(delta: float) -> void:
	if _contact_attack_cooldown_left > 0.0:
		_contact_attack_cooldown_left = maxf(0.0, _contact_attack_cooldown_left - delta)
	_state_time_left = maxf(0.0, _state_time_left - delta)
	if _sundered_flash_time_left > 0.0:
		_sundered_flash_time_left = maxf(0.0, _sundered_flash_time_left - delta)
		queue_redraw()
	if _sundered_hit_flash_left > 0.0:
		_sundered_hit_flash_left = maxf(0.0, _sundered_hit_flash_left - delta)
	if _sundered_reduction_left > 0.0:
		_sundered_reduction_left = maxf(0.0, _sundered_reduction_left - delta)
	_update_sundered_health_bar_visuals()
	match _state:
		STATE_STALK:
			_process_stalk(delta)
			if _state_time_left <= 0.0:
				_enter_telegraph()
		STATE_TELEGRAPH:
			_anchor_in_place(delta)
			_advance_axis_rotation()
			queue_redraw()
			if _state_time_left <= 0.0:
				_enter_reflect()
		STATE_REFLECT:
			_anchor_in_place(delta)
			_tick_reflect_cadence(delta)
			_tick_seam_beam_damage(delta)
			if _state_time_left <= 0.0:
				_enter_cooldown()
		STATE_COOLDOWN:
			_anchor_in_place(delta)
			if _state_time_left <= 0.0:
				_enter_stalk()
	_advance_echoes(delta)
	move_and_slide()
	_try_contact_strike()
	queue_redraw()

func should_process_remote_visuals_every_frame() -> bool:
	# During telegraph/reflect (and while echoes are alive), the joiner needs every-frame ticking so the
	# axis rotates smoothly and projectiles fly between snapshots instead of stepping at the throttled
	# remote-visual interval.
	return not network_simulation_enabled and (
		_state == STATE_TELEGRAPH
		or _state == STATE_REFLECT
		or not _active_echoes.is_empty()
		or _sundered_hit_flash_left > 0.0
		or _sundered_flash_time_left > 0.0
	)

func _process_network_visuals(delta: float) -> void:
	# Joiner-side ticking. Runs in place of _process_behavior on remote clients (network_simulation_enabled=false)
	# at either every frame or the throttled remote-visual interval depending on should_process_remote_visuals_every_frame().
	if _sundered_flash_time_left > 0.0:
		_sundered_flash_time_left = maxf(0.0, _sundered_flash_time_left - delta)
	if _sundered_hit_flash_left > 0.0:
		_sundered_hit_flash_left = maxf(0.0, _sundered_hit_flash_left - delta)
	if _sundered_reduction_left > 0.0:
		_sundered_reduction_left = maxf(0.0, _sundered_reduction_left - delta)
	_update_sundered_health_bar_visuals()
	_state_time_left = maxf(0.0, _state_time_left - delta)
	if _state == STATE_TELEGRAPH and _telegraph_total > 0.0:
		_advance_axis_rotation()
	elif _state != STATE_TELEGRAPH:
		_axis_normal = _axis_target_normal
		_axis_origin = _axis_target_origin
	_update_echoes_visual_only(delta)
	queue_redraw()

func _remote_extrapolate(_delta: float) -> void:
	pass

func _process_stalk(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		return
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	var desired := Vector2.ZERO
	if dist > stalk_band_max:
		desired = to_target.normalized() * move_speed * slow_speed_mult
	elif dist < stalk_band_min:
		desired = -to_target.normalized() * move_speed * slow_speed_mult
	else:
		var tangent := Vector2(-to_target.y, to_target.x).normalized()
		desired = tangent * move_speed * 0.7 * slow_speed_mult
	velocity = velocity.move_toward(desired, (acceleration if desired != Vector2.ZERO else deceleration) * delta)

func _anchor_in_place(delta: float) -> void:
	# Anchor the body during attack windows so joiners (who lerp toward sampled host positions) aren't
	# perpetually chasing motion that isn't gameplay-relevant. The seam itself is the threat; the body
	# only needs to move during STALK to stay engaged with the player.
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)

func _process_drift(delta: float, speed_factor: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		return
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	var desired := Vector2.ZERO
	if dist > stalk_band_max + 30.0:
		desired = to_target.normalized() * move_speed * speed_factor * slow_speed_mult
	elif dist < stalk_band_min - 30.0:
		desired = -to_target.normalized() * move_speed * speed_factor * slow_speed_mult
	velocity = velocity.move_toward(desired, (acceleration if desired != Vector2.ZERO else deceleration) * delta)

func _enter_telegraph() -> void:
	_state = STATE_TELEGRAPH
	_state_time_left = telegraph_duration
	_telegraph_total = telegraph_duration
	if _twin_pending and not _twin_active:
		# Promote at telegraph entry so the twin rotates into place during the windup instead of popping in mid-reflect.
		_twin_active = true
		_twin_pending = false
	_axis_prev_normal = _axis_normal if _axis_normal.length_squared() > 0.0001 else Vector2.RIGHT
	_axis_prev_origin = _axis_origin
	var midpoint := arena_center_world
	var target_normal := _axis_prev_normal
	if is_instance_valid(target):
		midpoint = (target.global_position + global_position) * 0.5
		var to_mid := midpoint - arena_center_world
		if to_mid.length_squared() < 1.0:
			target_normal = Vector2.RIGHT.rotated(randf() * TAU)
		else:
			target_normal = to_mid.normalized()
	else:
		target_normal = Vector2.RIGHT.rotated(randf() * TAU)
	_axis_target_normal = target_normal
	# Pull the seam 10% off the spawn-anchored arena center toward the live action midpoint so the mirror reads as being between player and enemy.
	_axis_target_origin = arena_center_world.lerp(midpoint, 0.10)
	queue_redraw()

func _advance_axis_rotation() -> void:
	var raw_t := 1.0 - clampf(_state_time_left / maxf(0.001, _telegraph_total), 0.0, 1.0)
	var settle := clampf(telegraph_settle_fraction, 0.0, 0.85)
	var rotation_window := maxf(0.001, 1.0 - settle)
	var t := clampf(raw_t / rotation_window, 0.0, 1.0)
	var smoothed := smoothstep(0.0, 1.0, t)
	var prev_angle := _axis_prev_normal.angle()
	var target_angle := _axis_target_normal.angle()
	var interpolated_angle := lerp_angle(prev_angle, target_angle, smoothed)
	_axis_normal = Vector2.RIGHT.rotated(interpolated_angle)
	_axis_origin = _axis_prev_origin.lerp(_axis_target_origin, smoothed)

func _enter_reflect() -> void:
	_state = STATE_REFLECT
	_state_time_left = reflect_duration
	_reflect_echoes_remaining = maxi(1, reflect_echo_count)
	_spawn_echo_from_player()
	_reflect_echoes_remaining -= 1
	_reflect_next_echo_time_left = reflect_echo_interval
	_seam_beam_tick_left = 0.15
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _tick_seam_beam_damage(delta: float) -> void:
	_seam_beam_tick_left = maxf(0.0, _seam_beam_tick_left - delta)
	if _seam_beam_tick_left > 0.0:
		return
	_seam_beam_tick_left = seam_beam_tick_interval
	var players := _get_damageable_targets()
	if players.is_empty():
		return
	for axis in _active_axes():
		var axis_normal := axis["normal"] as Vector2
		if axis_normal.length_squared() < 0.0001:
			continue
		var axis_origin := axis["origin"] as Vector2
		for player in players:
			if not is_instance_valid(player):
				continue
			var player_offset := player.global_position - axis_origin
			var perpendicular_distance := absf(player_offset.dot(axis_normal))
			if perpendicular_distance > seam_beam_half_thickness:
				continue
			DAMAGEABLE.apply_damage(player, seam_beam_tick_damage, {"source": "enemy_contact", "ability": "mirrorline_seam"})

func _tick_reflect_cadence(delta: float) -> void:
	if _reflect_echoes_remaining <= 0:
		return
	_reflect_next_echo_time_left = maxf(0.0, _reflect_next_echo_time_left - delta)
	if _reflect_next_echo_time_left > 0.0:
		return
	_spawn_echo_from_player()
	_reflect_echoes_remaining -= 1
	_reflect_next_echo_time_left = reflect_echo_interval

func _enter_cooldown() -> void:
	_state = STATE_COOLDOWN
	_state_time_left = cooldown_duration
	queue_redraw()

func _enter_stalk() -> void:
	_state = STATE_STALK
	_state_time_left = randf_range(stalk_duration_min, stalk_duration_max)
	_telegraph_total = 0.0
	queue_redraw()

func _spawn_echo_from_player() -> void:
	var players := _get_damageable_targets()
	if players.is_empty():
		return
	for axis in _active_axes():
		var axis_normal := axis["normal"] as Vector2
		if axis_normal.length_squared() < 0.0001:
			continue
		var axis_origin := axis["origin"] as Vector2
		# One echo per player per axis: each player must dodge their own mirrored shot.
		for player in players:
			if not is_instance_valid(player):
				continue
			var echo_origin := _reflect_point_about(player.global_position, axis_normal, axis_origin)
			var to_player := player.global_position - echo_origin
			var direction := axis_normal
			if to_player.length_squared() > 0.0001:
				direction = to_player.normalized()
			var echo_velocity := direction * echo_speed_cap
			_active_echoes.append({
				"id": _allocate_echo_id(),
				"origin": echo_origin,
				"velocity": echo_velocity,
				"time_left": echo_lifetime,
				"time_total": echo_lifetime,
				"hit": false
			})

func _allocate_echo_id() -> int:
	_next_echo_id += 1
	if _next_echo_id <= 0:
		_next_echo_id = 1
	return _next_echo_id

func _advance_echoes(delta: float) -> void:
	if _active_echoes.is_empty():
		return
	var survivors: Array = []
	for echo_variant in _active_echoes:
		if not (echo_variant is Dictionary):
			continue
		var echo := echo_variant as Dictionary
		var time_left := float(echo.get("time_left", 0.0)) - delta
		echo["time_left"] = time_left
		if time_left <= 0.0:
			continue
		if not bool(echo.get("hit", false)):
			var elapsed := float(echo.get("time_total", echo_lifetime)) - time_left
			# Grace window: don't allow hits in the first 0.12s. This guarantees the spawn is sampled by
			# the network broadcaster at least once (so joiners always see the projectile) and prevents
			# zero-range shots when the player is sitting on the seam (mirrored origin coincides with player).
			if elapsed < 0.12:
				survivors.append(echo)
				continue
			var current_pos := _echo_current_position(echo)
			var hit_player: Node2D = null
			for player in _get_damageable_targets():
				if not is_instance_valid(player):
					continue
				if current_pos.distance_to(player.global_position) <= echo_radius + 14.0:
					hit_player = player
					break
			if hit_player != null:
				if DAMAGEABLE.apply_damage(hit_player, echo_damage, {"source": "enemy_ability", "ability": "mirrorline_echo"}):
					echo["hit"] = true
					echo["time_left"] = 0.0
					continue
		survivors.append(echo)
	_active_echoes = survivors
	queue_redraw()

func _update_echoes_visual_only(delta: float) -> void:
	if _active_echoes.is_empty():
		return
	var survivors: Array = []
	for echo_variant in _active_echoes:
		if not (echo_variant is Dictionary):
			continue
		var echo := echo_variant as Dictionary
		var time_left := float(echo.get("time_left", 0.0)) - delta
		echo["time_left"] = time_left
		if time_left <= 0.0:
			continue
		survivors.append(echo)
	_active_echoes = survivors
	queue_redraw()

func _echo_current_position(echo: Dictionary) -> Vector2:
	var origin := echo.get("origin", Vector2.ZERO) as Vector2
	var vel := echo.get("velocity", Vector2.ZERO) as Vector2
	var elapsed := float(echo.get("time_total", echo_lifetime)) - float(echo.get("time_left", 0.0))
	return origin + vel * maxf(0.0, elapsed)

func _reflect_point(point: Vector2) -> Vector2:
	return _reflect_point_about(point, _axis_normal, _axis_origin)

func _reflect_point_about(point: Vector2, axis_normal: Vector2, axis_origin: Vector2) -> Vector2:
	if axis_normal.length_squared() < 0.0001:
		return point
	var rel := point - axis_origin
	return axis_origin + rel - 2.0 * rel.dot(axis_normal) * axis_normal

func _twin_axis_normal() -> Vector2:
	if _axis_normal.length_squared() < 0.0001:
		return Vector2.ZERO
	return Vector2(-_axis_normal.y, _axis_normal.x)

func _active_axes() -> Array:
	var axes: Array = [{"normal": _axis_normal, "origin": _axis_origin}]
	if _twin_active:
		axes.append({"normal": _twin_axis_normal(), "origin": _axis_origin})
	return axes

func _try_contact_strike() -> void:
	if not is_instance_valid(target):
		return
	if _contact_attack_cooldown_left > 0.0:
		return
	if global_position.distance_to(target.global_position) > contact_attack_range:
		return
	if not DAMAGEABLE.apply_damage(target, contact_damage, {"source": "enemy_contact", "ability": "mirrorline_strike"}):
		return
	_contact_attack_cooldown_left = contact_attack_interval
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _on_health_state_died() -> void:
	_active_echoes.clear()
	_telegraph_total = 0.0
	died.emit()
	queue_free()

func take_damage(amount: int, _damage_context: Dictionary = {}) -> void:
	if amount <= 0:
		return
	if damage_blocked:
		return
	var before_health := int(health_state.current_health)
	var final_damage := amount
	if _is_damage_reduction_active():
		var reduction := clampf(sundered_damage_reduction, 0.0, 0.95)
		final_damage = maxi(1, int(round(float(amount) * (1.0 - reduction))))
		if final_damage < amount:
			_sundered_hit_flash_left = sundered_hit_flash_duration
	health_state.take_damage(final_damage)
	var after_health := int(health_state.current_health)
	var applied_amount := maxi(0, before_health - after_health)
	if applied_amount > 0:
		damage_received.emit(applied_amount, after_health)
	_check_sundered_threshold()

func _is_sundered_active() -> bool:
	return _twin_pending or _twin_active

func _is_damage_reduction_active() -> bool:
	return _sundered_reduction_left > 0.0

func _get_damageable_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for candidate_variant in target_candidates:
		if not (candidate_variant is Node2D):
			continue
		var candidate := candidate_variant as Node2D
		if not is_instance_valid(candidate):
			continue
		if not DAMAGEABLE.can_take_damage(candidate):
			continue
		result.append(candidate)
	if result.is_empty() and is_instance_valid(target) and DAMAGEABLE.can_take_damage(target):
		result.append(target)
	return result

func _cache_sundered_health_bar_defaults() -> void:
	if health_bar == null:
		return
	var fill_style := health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style != null:
		_sundered_health_fill_default = fill_style.bg_color
	var bg_style := health_bar.get_theme_stylebox("background") as StyleBoxFlat
	if bg_style != null:
		_sundered_health_bg_default = bg_style.bg_color
	_sundered_health_colors_cached = true

func _update_sundered_health_bar_visuals() -> void:
	if health_bar == null:
		return
	if not _sundered_health_colors_cached:
		_cache_sundered_health_bar_defaults()
	var fill_style := health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	var bg_style := health_bar.get_theme_stylebox("background") as StyleBoxFlat
	if fill_style == null or bg_style == null:
		return
	if _is_damage_reduction_active():
		var hit_t := clampf(_sundered_hit_flash_left / maxf(0.001, sundered_hit_flash_duration), 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.016)
		var shield_fill := Color(0.62, 0.86, 1.0, 1.0)
		var hot_fill := Color(0.96, 1.0, 1.0, 1.0)
		fill_style.bg_color = shield_fill.lerp(hot_fill, hit_t * (0.72 + pulse * 0.28))
		bg_style.bg_color = Color(0.08, 0.18, 0.32, 0.95)
		return
	fill_style.bg_color = _sundered_health_fill_default
	bg_style.bg_color = _sundered_health_bg_default

func _check_sundered_threshold() -> void:
	if _twin_pending or _twin_active:
		return
	if health_state == null or health_state.max_health <= 0:
		return
	var ratio := float(health_state.current_health) / float(health_state.max_health)
	if ratio > clampf(sundered_health_threshold, 0.05, 0.95):
		return
	_twin_pending = true
	_sundered_flash_time_left = 0.45
	_sundered_reduction_left = maxf(0.05, sundered_reduction_duration)
	queue_redraw()

func _draw() -> void:
	_draw_axis()
	_draw_mirror_preview()
	_draw_echoes()
	_draw_body()
	_draw_sundered_flash()

func _draw_sundered_flash() -> void:
	if _sundered_flash_time_left <= 0.0:
		return
	var t := clampf(_sundered_flash_time_left / 0.45, 0.0, 1.0)
	var ring_alpha := 0.55 * t
	var ring_radius := body_draw_radius + 12.0 + (1.0 - t) * 28.0
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 36, Color(0.78, 0.92, 1.0, ring_alpha), 3.0)
	draw_arc(Vector2.ZERO, ring_radius - 6.0, 0.0, TAU, 36, Color(0.96, 0.99, 1.0, ring_alpha * 0.7), 1.6)

func _draw_axis() -> void:
	if _axis_normal.length_squared() < 0.0001:
		return
	for axis in _active_axes():
		_draw_axis_one(axis["normal"] as Vector2, axis["origin"] as Vector2)

func _draw_axis_one(axis_normal: Vector2, axis_origin: Vector2) -> void:
	if axis_normal.length_squared() < 0.0001:
		return
	var local_origin := axis_origin - global_position
	var tangent := Vector2(-axis_normal.y, axis_normal.x)
	var half_extent := mirror_line_half_length
	var start := local_origin - tangent * half_extent
	var end := local_origin + tangent * half_extent
	match _state:
		STATE_TELEGRAPH:
			var t_norm := 1.0 - clampf(_state_time_left / maxf(0.001, _telegraph_total), 0.0, 1.0)
			var fade := 0.45 + 0.55 * t_norm
			draw_line(start, end, Color(0.78, 0.92, 1.0, 0.22 + 0.22 * t_norm), 22.0)
			draw_line(start, end, Color(0.96, 0.98, 1.0, fade), 6.5)
			draw_line(start, end, Color(1.0, 1.0, 1.0, fade * 0.9), 2.0)
			_draw_mirror_chevrons(local_origin, tangent, axis_normal, fade)
		STATE_REFLECT:
			var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.020)
			var normal_offset := axis_normal * seam_beam_half_thickness
			var quad := PackedVector2Array([start + normal_offset, end + normal_offset, end - normal_offset, start - normal_offset])
			draw_colored_polygon(quad, Color(0.62, 0.82, 1.0, 0.22 + 0.10 * pulse))
			draw_line(start, end, Color(0.78, 0.92, 1.0, 0.45 + 0.18 * pulse), seam_beam_half_thickness * 1.8)
			draw_line(start, end, Color(0.96, 0.99, 1.0, 0.92), 7.5)
			draw_line(start, end, Color(1.0, 1.0, 1.0, 0.95), 2.4)
			_draw_mirror_chevrons(local_origin, tangent, axis_normal, 0.95)
		_:
			_draw_dormant_axis(local_origin, tangent, axis_normal, start, end)

func _draw_dormant_axis(local_origin: Vector2, tangent: Vector2, axis_normal: Vector2, start: Vector2, end: Vector2) -> void:
	# Powered-down look: thin dim dashed line, no chevrons, no fill bar. Reads as 'safe to cross'.
	var dim_color := Color(0.62, 0.78, 0.96, 0.28)
	var dim_core := Color(0.86, 0.94, 1.0, 0.38)
	var tick_color := Color(0.7, 0.86, 1.0, 0.32)
	var dash_len := 22.0
	var gap_len := 18.0
	var total := (end - start).length()
	if total < 0.001:
		return
	var dir := (end - start) / total
	var traveled := 0.0
	while traveled < total:
		var segment := minf(dash_len, total - traveled)
		var a := start + dir * traveled
		var b := start + dir * (traveled + segment)
		draw_line(a, b, dim_color, 3.2)
		draw_line(a, b, dim_core, 1.2)
		traveled += dash_len + gap_len
	var tick := tangent * 6.0
	var normal_tick := axis_normal * 14.0
	draw_line(local_origin - normal_tick, local_origin + normal_tick, tick_color, 1.6)
	draw_line(local_origin - tick, local_origin + tick, tick_color, 1.6)

func _draw_mirror_chevrons(local_origin: Vector2, tangent: Vector2, axis_normal: Vector2, alpha: float) -> void:
	# Paired arrows on either side of the seam pointing inward, reading as a mirror plane.
	var spacings: Array[float] = [-220.0, -110.0, 0.0, 110.0, 220.0]
	var chevron_size := 16.0
	var chevron_color := Color(0.86, 0.96, 1.0, clampf(alpha * 0.85, 0.0, 1.0))
	for offset in spacings:
		var center := local_origin + tangent * offset
		var tip_a := center + axis_normal * (seam_beam_half_thickness + 4.0)
		var back_a1 := tip_a + axis_normal * chevron_size + tangent * chevron_size * 0.7
		var back_a2 := tip_a + axis_normal * chevron_size - tangent * chevron_size * 0.7
		draw_line(tip_a, back_a1, chevron_color, 2.0)
		draw_line(tip_a, back_a2, chevron_color, 2.0)
		var tip_b := center - axis_normal * (seam_beam_half_thickness + 4.0)
		var back_b1 := tip_b - axis_normal * chevron_size + tangent * chevron_size * 0.7
		var back_b2 := tip_b - axis_normal * chevron_size - tangent * chevron_size * 0.7
		draw_line(tip_b, back_b1, chevron_color, 2.0)
		draw_line(tip_b, back_b2, chevron_color, 2.0)

func _draw_mirror_preview() -> void:
	# During TELEGRAPH, show every player's mirrored position(s) so each spawn point is legible.
	if _state != STATE_TELEGRAPH:
		return
	var players := _get_damageable_targets()
	if players.is_empty():
		return
	if _axis_normal.length_squared() < 0.0001:
		return
	for axis in _active_axes():
		var axis_normal := axis["normal"] as Vector2
		var axis_origin := axis["origin"] as Vector2
		for player in players:
			if not is_instance_valid(player):
				continue
			_draw_mirror_preview_one(axis_normal, axis_origin, player)

func _draw_mirror_preview_one(axis_normal: Vector2, axis_origin: Vector2, player: Node2D) -> void:
	if axis_normal.length_squared() < 0.0001:
		return
	var t_norm := 1.0 - clampf(_state_time_left / maxf(0.001, _telegraph_total), 0.0, 1.0)
	var alpha := 0.45 + 0.5 * t_norm
	var player_world := player.global_position
	var reflected_world := _reflect_point_about(player_world, axis_normal, axis_origin)
	var player_local := player_world - global_position
	var reflected_local := reflected_world - global_position
	var ghost_color := Color(0.86, 0.96, 1.0, alpha)
	draw_circle(reflected_local, 18.0, Color(0.62, 0.82, 1.0, 0.22 * alpha))
	draw_circle(reflected_local, 11.0, Color(0.96, 0.99, 1.0, 0.65 * alpha))
	draw_arc(reflected_local, 16.0, 0.0, TAU, 28, ghost_color, 1.8)
	_draw_dashed_line(reflected_local, player_local, Color(0.78, 0.92, 1.0, alpha * 0.55), 1.4, 10.0, 8.0)

func _draw_dashed_line(from_local: Vector2, to_local: Vector2, color: Color, width: float, dash_len: float, gap_len: float) -> void:
	var delta := to_local - from_local
	var total := delta.length()
	if total < 0.001:
		return
	var dir := delta / total
	var traveled := 0.0
	while traveled < total:
		var segment := minf(dash_len, total - traveled)
		var a := from_local + dir * traveled
		var b := from_local + dir * (traveled + segment)
		draw_line(a, b, color, width)
		traveled += dash_len + gap_len

func _draw_echoes() -> void:
	for echo_variant in _active_echoes:
		if not (echo_variant is Dictionary):
			continue
		var echo := echo_variant as Dictionary
		var world_pos := _echo_current_position(echo)
		var local_pos := world_pos - global_position
		var time_total := float(echo.get("time_total", echo_lifetime))
		var time_left := float(echo.get("time_left", 0.0))
		var t := clampf(time_left / maxf(0.001, time_total), 0.0, 1.0)
		var elapsed := time_total - time_left
		var was_hit := bool(echo.get("hit", false))
		var alpha_mult := 0.45 if was_hit else 1.0
		var origin_world := echo.get("origin", Vector2.ZERO) as Vector2
		var origin_local := origin_world - global_position
		var velocity := echo.get("velocity", Vector2.ZERO) as Vector2
		if not was_hit and elapsed >= 0.0 and elapsed < 0.22:
			var burst_t := clampf(elapsed / 0.22, 0.0, 1.0)
			var burst_radius := echo_radius * (1.0 + 1.4 * burst_t)
			var burst_alpha := (1.0 - burst_t) * 0.85
			draw_arc(origin_local, burst_radius, 0.0, TAU, 28, Color(0.86, 0.96, 1.0, burst_alpha), 3.0)
			draw_arc(origin_local, burst_radius * 0.6, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, burst_alpha * 0.8), 1.6)
		if not was_hit and velocity.length_squared() > 1.0:
			var speed := velocity.length()
			var dir := velocity / speed
			var trail_segments := 8
			var segment_spacing := echo_radius * 0.55
			for i in range(1, trail_segments + 1):
				var segment_t := float(i) / float(trail_segments)
				var segment_pos := local_pos - dir * (segment_spacing * float(i))
				var segment_alpha := (1.0 - segment_t) * 0.55 * alpha_mult
				var segment_radius := echo_radius * (0.95 - 0.65 * segment_t)
				draw_circle(segment_pos, segment_radius + 4.0, Color(0.6, 0.84, 1.0, segment_alpha * 0.35))
				draw_circle(segment_pos, segment_radius, Color(0.92, 0.97, 1.0, segment_alpha))
		draw_circle(local_pos, echo_radius + 8.0, Color(0.6, 0.84, 1.0, 0.18 * alpha_mult))
		draw_circle(local_pos, echo_radius + 3.0, Color(0.86, 0.94, 1.0, 0.36 * alpha_mult))
		draw_circle(local_pos, echo_radius, Color(0.96, 0.98, 1.0, 0.78 * alpha_mult))
		var inner_radius := echo_radius * (0.45 + 0.35 * t)
		draw_circle(local_pos, inner_radius, Color(1.0, 1.0, 1.0, 0.85 * alpha_mult))

func _draw_body() -> void:
	var time := float(Time.get_ticks_msec())
	var shimmer := 0.5 + 0.5 * sin(time * 0.0062)
	var attack_pulse := _get_attack_pulse()
	var radius := body_draw_radius + attack_pulse * 0.6
	var transparency_mod := 0.55 if _state == STATE_TELEGRAPH else 1.0
	draw_circle(Vector2.ZERO, radius + 10.0, Color(0.62, 0.84, 1.0, 0.14 * transparency_mod))
	draw_circle(Vector2.ZERO, radius + 5.5, Color(0.78, 0.92, 1.0, 0.22 * transparency_mod))
	draw_circle(Vector2.ZERO, radius, Color(0.16, 0.24, 0.36, 0.92 * transparency_mod))
	draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 36, Color(0.86, 0.94, 1.0, 0.86 * transparency_mod), 2.4)
	# Inner reflective core: a tilted bar that rotates with shimmer to sell "mirror".
	var bar_angle := time * 0.0011
	var bar_dir := Vector2(cos(bar_angle), sin(bar_angle))
	var bar_perp := Vector2(-bar_dir.y, bar_dir.x)
	var bar_half := radius * 0.78
	var bar_thickness := radius * 0.22 + shimmer * 1.4
	var p0 := bar_dir * bar_half + bar_perp * bar_thickness
	var p1 := bar_dir * bar_half - bar_perp * bar_thickness
	var p2 := -bar_dir * bar_half - bar_perp * bar_thickness
	var p3 := -bar_dir * bar_half + bar_perp * bar_thickness
	draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]), Color(0.94, 0.98, 1.0, 0.78 * transparency_mod))
	draw_circle(Vector2.ZERO, radius * 0.32 + shimmer * 1.2, Color(1.0, 1.0, 1.0, 0.92 * transparency_mod))
	# Eye line indicates bearing toward target.
	if is_instance_valid(target):
		var to_target := (target.global_position - global_position)
		if to_target.length() > 0.001:
			var look_dir := to_target.normalized()
			var eye_pos := look_dir * (radius * 0.55)
			draw_circle(eye_pos, 2.4 + shimmer * 0.4, Color(0.10, 0.14, 0.20, 0.95 * transparency_mod))
