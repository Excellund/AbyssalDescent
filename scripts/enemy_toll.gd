extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

const STATE_COOLDOWN := 0
const STATE_RING_EXPAND := 1
const STATE_BONUS_WINDOW := 2

# --- Scale & Health ---
@export var max_health_apex: int = 540
@export var body_draw_radius: float = 38.0
@export var collision_shape_radius: float = 34.0

# --- Stationary positioning ---
@export var anchor_world_position: Vector2 = Vector2.ZERO
@export var anchor_pull_strength: float = 320.0

# --- Ring cadence ---
# Per-bearing pressure lever: cooldown_duration shortens at higher tiers so the cycle gets tighter.
# ring_expand_duration and bonus_window_duration stay constant so telegraph readability is preserved.
@export var ring_expand_duration: float = 2.5
@export var bonus_window_duration: float = 2.0
@export var cooldown_duration: float = 1.0
@export var ring_max_radius: float = 280.0
@export var ring_inner_safe_radius: float = 0.0

# --- Exposed (bonus window) damage amplification ---
@export var exposed_damage_mult: float = 1.75

# --- Heal on miss (no players inside at trigger) ---
@export_range(0.0, 0.5, 0.01) var heal_fraction_on_miss: float = 0.06

# --- Slow on late-exit (still inside ring footprint when bonus window ends) ---
@export_range(0.05, 1.0, 0.05) var slow_mult: float = 0.50
@export var slow_duration: float = 2.2

# --- Repulse (short-range anti-stack) ---
@export var repulse_radius: float = 90.0
@export var repulse_interval: float = 0.65
@export var repulse_force: float = 540.0

# --- Contact ---
@export var contact_damage: int = 22
@export var contact_attack_range: float = 70.0
@export var contact_attack_interval: float = 0.85

@export var arena_size: Vector2 = Vector2(1160.0, 860.0)
@export var arena_center_world: Vector2 = Vector2.ZERO

@export var health_bar_size_apex: Vector2 = Vector2(110.0, 12.0)
@export var health_bar_offset_apex: Vector2 = Vector2(-55.0, -64.0)

var _state: int = STATE_COOLDOWN
var _state_time_left: float = 0.0
var _ring_radius: float = 0.0
var _bonus_window_left: float = 0.0
var _heal_flash_left: float = 0.0
var _repulse_cooldown_left: float = 0.0
var _repulse_flash_left: float = 0.0
var _contact_attack_cooldown_left: float = 0.0

# Host-only: instance ids of player nodes that were inside the ring at trigger. Using instance ids
# instead of peer ids so singleplayer (player_id == 0) is handled identically to multiplayer.
var _marked_players: Dictionary = {}

func should_force_network_runtime_state_sampling() -> bool:
	return _state == STATE_RING_EXPAND or _state == STATE_BONUS_WINDOW or _repulse_flash_left > 0.0 or _heal_flash_left > 0.0

func get_priority_network_sync_interval_sec() -> float:
	if _state == STATE_RING_EXPAND or _state == STATE_BONUS_WINDOW:
		return 0.05
	return 0.0

func _get_custom_network_runtime_state() -> Dictionary:
	# Short wire keys keep this small. Per /memories/repo/custom_runtime_state_size_budget.md.
	# We DO NOT ship _state_time_left — joiner derives via _local_duration_for_state on transition.
	return {
		"s": _state,
		"rr": _ring_radius,
		"bw": _bonus_window_left,
		"hf": _heal_flash_left,
		"rf": _repulse_flash_left,
		"cc": _contact_attack_cooldown_left
	}

func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	if custom_state.is_empty():
		return
	var prev_state := _state
	_state = int(custom_state.get("s", _state))
	if prev_state != _state:
		_state_time_left = _local_duration_for_state(_state)
	_ring_radius = float(custom_state.get("rr", _ring_radius))
	_bonus_window_left = float(custom_state.get("bw", _bonus_window_left))
	_heal_flash_left = float(custom_state.get("hf", _heal_flash_left))
	_repulse_flash_left = float(custom_state.get("rf", _repulse_flash_left))
	_contact_attack_cooldown_left = float(custom_state.get("cc", _contact_attack_cooldown_left))

func _local_duration_for_state(state_id: int) -> float:
	match state_id:
		STATE_RING_EXPAND:
			return maxf(0.001, ring_expand_duration)
		STATE_BONUS_WINDOW:
			return maxf(0.001, bonus_window_duration)
		STATE_COOLDOWN:
			return maxf(0.001, cooldown_duration)
		_:
			return 0.0

func _ready() -> void:
	max_health = max_health_apex
	super._ready()
	crowd_separation_radius = 80.0
	crowd_separation_strength = 110.0
	configure_health_bar_visuals(health_bar_offset_apex, health_bar_size_apex)
	_state = STATE_COOLDOWN
	_state_time_left = cooldown_duration
	for child in get_children():
		if child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if shape_node.shape is CircleShape2D:
				(shape_node.shape as CircleShape2D).radius = collision_shape_radius
			break
	_resolve_anchor()

func _resolve_anchor() -> void:
	if anchor_world_position == Vector2.ZERO:
		anchor_world_position = global_position
	if arena_center_world == Vector2.ZERO:
		arena_center_world = anchor_world_position

func _process_behavior(delta: float) -> void:
	# Survey phase guard: when targets are passive (target == null and no candidates) the encounter
	# intro grace is active. Hold in cooldown so the ring never starts ticking before players engage.
	if not is_instance_valid(target) and target_candidates.is_empty():
		_state = STATE_COOLDOWN
		_state_time_left = cooldown_duration
		_ring_radius = 0.0
		_bonus_window_left = 0.0
		_marked_players.clear()
		_apply_anchor_pull(delta)
		move_and_slide()
		queue_redraw()
		return
	if _contact_attack_cooldown_left > 0.0:
		_contact_attack_cooldown_left = maxf(0.0, _contact_attack_cooldown_left - delta)
	_state_time_left = maxf(0.0, _state_time_left - delta)
	if _bonus_window_left > 0.0:
		_bonus_window_left = maxf(0.0, _bonus_window_left - delta)
	if _heal_flash_left > 0.0:
		_heal_flash_left = maxf(0.0, _heal_flash_left - delta)
	if _repulse_flash_left > 0.0:
		_repulse_flash_left = maxf(0.0, _repulse_flash_left - delta)
	if _repulse_cooldown_left > 0.0:
		_repulse_cooldown_left = maxf(0.0, _repulse_cooldown_left - delta)
	match _state:
		STATE_COOLDOWN:
			_ring_radius = 0.0
			if _state_time_left <= 0.0:
				_enter_ring_expand()
		STATE_RING_EXPAND:
			var t := 1.0 - clampf(_state_time_left / maxf(0.001, ring_expand_duration), 0.0, 1.0)
			_ring_radius = lerpf(0.0, ring_max_radius, smoothstep(0.0, 1.0, t))
			if _state_time_left <= 0.0:
				_trigger_ring()
		STATE_BONUS_WINDOW:
			_ring_radius = ring_max_radius
			if _state_time_left <= 0.0:
				_resolve_bonus_window_end()
	_tick_repulse(delta)
	_apply_anchor_pull(delta)
	move_and_slide()
	_try_contact_strike()
	queue_redraw()

func should_process_remote_visuals_every_frame() -> bool:
	return not network_simulation_enabled and (
		_state == STATE_RING_EXPAND
		or _state == STATE_BONUS_WINDOW
		or _repulse_flash_left > 0.0
		or _heal_flash_left > 0.0
	)

func _process_network_visuals(delta: float) -> void:
	# Joiner-side ticking — host owns gameplay, this drives smooth visuals between syncs.
	_state_time_left = maxf(0.0, _state_time_left - delta)
	if _bonus_window_left > 0.0:
		_bonus_window_left = maxf(0.0, _bonus_window_left - delta)
	if _heal_flash_left > 0.0:
		_heal_flash_left = maxf(0.0, _heal_flash_left - delta)
	if _repulse_flash_left > 0.0:
		_repulse_flash_left = maxf(0.0, _repulse_flash_left - delta)
	if _state == STATE_RING_EXPAND:
		var t := 1.0 - clampf(_state_time_left / maxf(0.001, ring_expand_duration), 0.0, 1.0)
		_ring_radius = lerpf(0.0, ring_max_radius, smoothstep(0.0, 1.0, t))
	elif _state == STATE_BONUS_WINDOW:
		_ring_radius = ring_max_radius
	else:
		_ring_radius = 0.0
	queue_redraw()

func _remote_extrapolate(_delta: float) -> void:
	pass

func _apply_anchor_pull(delta: float) -> void:
	# Toll is stationary — apply a stiff pull toward the anchor so any shove/knockback decays away.
	var to_anchor := anchor_world_position - global_position
	var dist := to_anchor.length()
	if dist < 1.0:
		velocity = velocity.move_toward(Vector2.ZERO, anchor_pull_strength * delta)
		return
	var desired := to_anchor.normalized() * minf(anchor_pull_strength, dist * 6.0)
	velocity = velocity.move_toward(desired, anchor_pull_strength * delta)

func _enter_ring_expand() -> void:
	_state = STATE_RING_EXPAND
	_state_time_left = ring_expand_duration
	_ring_radius = 0.0
	queue_redraw()

func _trigger_ring() -> void:
	# Ring resolution: the Toll always heals (the toll is paid no matter what), and any player still
	# caught inside the ring footprint at trigger eats a heavy slow as their tribute. The bonus damage
	# window remains as a brief vulnerability that rewards players who chose to step in to fight.
	var players := _get_damageable_targets()
	var any_inside := false
	for player in players:
		if not is_instance_valid(player):
			continue
		var dist := player.global_position.distance_to(anchor_world_position)
		if dist > ring_max_radius:
			continue
		any_inside = true
		var pid := 0
		if "player_id" in player:
			pid = int(player.player_id)
		_dispatch_slow(pid, player)
	_heal_on_trigger()
	if any_inside:
		_state = STATE_BONUS_WINDOW
		_state_time_left = bonus_window_duration
		_bonus_window_left = bonus_window_duration
	else:
		_state = STATE_COOLDOWN
		_state_time_left = cooldown_duration
	_marked_players.clear()
	queue_redraw()

func _heal_on_trigger() -> void:
	if health_state == null:
		return
	var max_hp := int(health_state.max_health)
	if max_hp <= 0:
		return
	var heal_amount := maxi(1, int(round(float(max_hp) * clampf(heal_fraction_on_miss, 0.0, 0.5))))
	var current := int(health_state.current_health)
	var new_health := mini(max_hp, current + heal_amount)
	if new_health <= current:
		return
	health_state.current_health = new_health
	_heal_flash_left = 0.55
	queue_redraw()

func _resolve_bonus_window_end() -> void:
	# Bonus window ends quietly — the slow and heal were already paid at ring trigger.
	_bonus_window_left = 0.0
	_state = STATE_COOLDOWN
	_state_time_left = cooldown_duration
	queue_redraw()

func _dispatch_slow(peer_id: int, player_node: Node2D) -> void:
	var replication_service := get_node_or_null("/root/PlayerReplicationService")
	if replication_service != null and replication_service.has_method("send_external_slow"):
		replication_service.send_external_slow(peer_id, slow_duration, slow_mult)
		return
	if player_node.has_method("apply_external_slow"):
		player_node.apply_external_slow(slow_duration, slow_mult)

func _tick_repulse(delta: float) -> void:
	if _repulse_cooldown_left > 0.0:
		return
	var players := _get_damageable_targets()
	if players.is_empty():
		_repulse_cooldown_left = repulse_interval * 0.5
		return
	var pulsed_any := false
	for player in players:
		if not is_instance_valid(player):
			continue
		var to_player := player.global_position - global_position
		var dist := to_player.length()
		if dist > repulse_radius or dist < 0.001:
			continue
		var dir := to_player / dist
		var peer_id := 0
		if "player_id" in player:
			peer_id = int(player.player_id)
		_dispatch_repulse(peer_id, player, dir)
		pulsed_any = true
	if pulsed_any:
		_repulse_flash_left = 0.32
	_repulse_cooldown_left = repulse_interval
	# Suppress unused-delta warning.
	var _unused := delta

func _dispatch_repulse(peer_id: int, player_node: Node2D, dir: Vector2) -> void:
	var replication_service := get_node_or_null("/root/PlayerReplicationService")
	if peer_id > 0 and replication_service != null and replication_service.has_method("send_polar_shift_effect"):
		replication_service.send_polar_shift_effect(peer_id, dir, repulse_force, 0.0)
		return
	if player_node.has_method("apply_polar_shift_impulse"):
		player_node.apply_polar_shift_impulse(dir, repulse_force)
	else:
		player_node.velocity = Vector2.ZERO
		player_node.velocity = dir * repulse_force

func _try_contact_strike() -> void:
	if not is_instance_valid(target):
		return
	if _contact_attack_cooldown_left > 0.0:
		return
	if global_position.distance_to(target.global_position) > contact_attack_range:
		return
	if not DAMAGEABLE.apply_damage(target, contact_damage, {"source": "enemy_contact", "ability": "toll_strike"}):
		return
	_contact_attack_cooldown_left = contact_attack_interval
	attack_anim_time_left = attack_anim_duration
	queue_redraw()

func _on_health_state_died() -> void:
	# Clean stop: cancel any in-flight ring + marks so no slow lands after death.
	_state = STATE_COOLDOWN
	_state_time_left = 0.0
	_ring_radius = 0.0
	_bonus_window_left = 0.0
	_marked_players.clear()
	died.emit()
	queue_free()

func take_damage(amount: int, _damage_context: Dictionary = {}) -> void:
	if amount <= 0:
		return
	if damage_blocked:
		return
	var before_health := int(health_state.current_health)
	var final_damage := amount
	if _bonus_window_left > 0.0:
		final_damage = maxi(1, int(round(float(amount) * maxf(1.0, exposed_damage_mult))))
	health_state.take_damage(final_damage)
	var after_health := int(health_state.current_health)
	var applied_amount := maxi(0, before_health - after_health)
	if applied_amount > 0:
		damage_received.emit(applied_amount, after_health)

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

func _draw() -> void:
	_draw_ring()
	_draw_body()
	_draw_repulse_flash()
	_draw_heal_flash()

func _draw_ring() -> void:
	if _ring_radius <= 0.5 and _bonus_window_left <= 0.0:
		return
	var local_center := anchor_world_position - global_position
	if _state == STATE_RING_EXPAND:
		var t_norm := clampf(_ring_radius / maxf(1.0, ring_max_radius), 0.0, 1.0)
		var fade := 0.35 + 0.55 * t_norm
		draw_arc(local_center, _ring_radius, 0.0, TAU, 64, Color(0.96, 0.62, 0.30, fade * 0.55), 10.0)
		draw_arc(local_center, _ring_radius, 0.0, TAU, 64, Color(1.0, 0.86, 0.42, fade), 3.6)
		draw_arc(local_center, _ring_radius - 4.0, 0.0, TAU, 64, Color(1.0, 1.0, 0.86, fade * 0.85), 1.4)
		_draw_tribute_chevrons(local_center, _ring_radius, fade)
	elif _state == STATE_BONUS_WINDOW:
		var bw_t := clampf(_bonus_window_left / maxf(0.001, bonus_window_duration), 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		var fill_alpha := 0.10 + 0.06 * pulse
		draw_circle(local_center, ring_max_radius, Color(1.0, 0.74, 0.32, fill_alpha))
		draw_arc(local_center, ring_max_radius, 0.0, TAU, 64, Color(1.0, 0.86, 0.42, 0.85), 4.4)
		draw_arc(local_center, ring_max_radius, 0.0, TAU, 64, Color(1.0, 1.0, 0.92, 0.95), 1.8)
		_draw_window_progress_arc(local_center, ring_max_radius - 14.0, bw_t)

func _draw_tribute_chevrons(local_center: Vector2, radius: float, alpha: float) -> void:
	if radius <= 6.0:
		return
	var chevron_color := Color(1.0, 0.94, 0.78, clampf(alpha * 0.85, 0.0, 1.0))
	var count := 12
	for i in range(count):
		var angle := float(i) / float(count) * TAU
		var dir := Vector2.RIGHT.rotated(angle)
		var perp := Vector2(-dir.y, dir.x)
		var outer := local_center + dir * radius
		var back_a := outer - dir * 10.0 + perp * 6.0
		var back_b := outer - dir * 10.0 - perp * 6.0
		draw_line(outer, back_a, chevron_color, 1.8)
		draw_line(outer, back_b, chevron_color, 1.8)

func _draw_window_progress_arc(local_center: Vector2, radius: float, remaining_t: float) -> void:
	# Inner arc shrinks counter-clockwise as the bonus window expires — players can read time remaining at a glance.
	var sweep := maxf(0.0, remaining_t) * TAU
	if sweep <= 0.01:
		return
	var start_angle := -PI * 0.5
	var end_angle := start_angle + sweep
	draw_arc(local_center, radius, start_angle, end_angle, 48, Color(1.0, 0.98, 0.86, 0.85), 2.6)

func _draw_repulse_flash() -> void:
	if _repulse_flash_left <= 0.0:
		return
	var t := clampf(_repulse_flash_left / 0.32, 0.0, 1.0)
	var ring_radius := repulse_radius * (0.6 + 0.4 * (1.0 - t))
	var alpha := 0.6 * t
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 32, Color(1.0, 0.84, 0.50, alpha), 3.2)
	draw_arc(Vector2.ZERO, ring_radius * 0.7, 0.0, TAU, 28, Color(1.0, 0.96, 0.78, alpha * 0.85), 1.6)

func _draw_heal_flash() -> void:
	if _heal_flash_left <= 0.0:
		return
	var t := clampf(_heal_flash_left / 0.55, 0.0, 1.0)
	var ring_radius := body_draw_radius + 8.0 + (1.0 - t) * 22.0
	var alpha := 0.55 * t
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 36, Color(0.46, 0.96, 0.62, alpha), 3.0)
	draw_arc(Vector2.ZERO, ring_radius - 5.0, 0.0, TAU, 36, Color(0.84, 1.0, 0.92, alpha * 0.7), 1.6)

func _draw_body() -> void:
	var time := float(Time.get_ticks_msec())
	var pulse := 0.5 + 0.5 * sin(time * 0.0036)
	var attack_pulse := _get_attack_pulse()
	var radius := body_draw_radius + attack_pulse * 0.6
	var exposed_glow := 1.0 if _bonus_window_left > 0.0 else 0.0
	var rim_color := Color(0.96, 0.66, 0.32, 0.32 + 0.30 * exposed_glow + 0.10 * pulse)
	draw_circle(Vector2.ZERO, radius + 10.0, Color(0.86, 0.52, 0.24, 0.14 + 0.16 * exposed_glow))
	draw_circle(Vector2.ZERO, radius + 5.0, rim_color)
	draw_circle(Vector2.ZERO, radius, Color(0.30, 0.20, 0.12, 0.94))
	draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 36, Color(0.96, 0.82, 0.48, 0.82 + 0.18 * exposed_glow), 2.4)
	# Bell-shaped inner mark: stacked diamonds reading as a bell tongue, evoking the "toll".
	var inner_color := Color(1.0, 0.92, 0.68, 0.90 + 0.10 * exposed_glow)
	draw_circle(Vector2.ZERO, radius * 0.42, Color(0.18, 0.12, 0.08, 0.92))
	draw_arc(Vector2.ZERO, radius * 0.42, 0.0, TAU, 28, inner_color, 1.6)
	var tongue_top := Vector2(0.0, -radius * 0.28)
	var tongue_bottom := Vector2(0.0, radius * 0.34)
	draw_line(tongue_top, tongue_bottom, Color(1.0, 0.86, 0.46, 0.95), 3.6)
	draw_circle(tongue_bottom, radius * 0.12 + pulse * 1.4, Color(1.0, 0.96, 0.84, 0.95))
	# Eye line indicates bearing toward target.
	if is_instance_valid(target):
		var to_target := (target.global_position - global_position)
		if to_target.length() > 0.001:
			var look_dir := to_target.normalized()
			var eye_pos := look_dir * (radius * 0.55)
			draw_circle(eye_pos, 2.4 + pulse * 0.4, Color(0.12, 0.08, 0.04, 0.95))
