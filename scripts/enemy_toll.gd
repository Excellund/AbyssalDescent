extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

# No global state machine — pulses and heals run independently on their own clocks.

# --- Scale & Health ---
@export var max_health_apex: int = 1500
@export var body_draw_radius: float = 38.0
@export var collision_shape_radius: float = 34.0

# --- Stationary positioning ---
@export var anchor_world_position: Vector2 = Vector2.ZERO
@export var anchor_pull_strength: float = 220.0
@export var anchor_arrival_speed_cap: float = 220.0

# --- Aura of Tithe (passive slow zone) ---
@export var aura_radius: float = 280.0
@export_range(0.05, 1.0, 0.01) var aura_slow_mult: float = 0.55
@export var aura_slow_refresh_interval: float = 0.25
@export var aura_slow_apply_duration: float = 0.45

# --- Inner Sanctum (heal-interrupt zone) ---
@export var inner_sanctum_radius: float = 120.0

# --- Contact attack ---
@export var contact_damage: int = 22
@export var contact_attack_range: float = 70.0
@export var contact_attack_interval: float = 0.85

# --- Tribute Pulse (telegraphed CC + damage ring) ---
@export var pulse_interval: float = 2.5
@export var pulse_telegraph_duration: float = 0.55
@export var pulse_expand_duration: float = 1.10
@export var pulse_max_radius: float = 380.0
@export var pulse_band_thickness: float = 64.0
@export var pulse_damage: int = 18
@export_range(0.0, 1.5, 0.05) var stun_duration: float = 0.5
@export_range(0.05, 1.0, 0.05) var stun_slow_mult: float = 0.18

# --- Heal Channel (interruptible self-heal) ---
@export var heal_channel_interval: float = 6.0
@export var heal_channel_duration: float = 1.8
@export_range(0.0, 0.5, 0.01) var heal_fraction: float = 0.12

@export var arena_size: Vector2 = Vector2(1160.0, 860.0)
@export var arena_center_world: Vector2 = Vector2.ZERO

@export var health_bar_size_apex: Vector2 = Vector2(110.0, 12.0)
@export var health_bar_offset_apex: Vector2 = Vector2(-55.0, -82.0)

const PULSE_PHASE_NONE := 0
const PULSE_PHASE_TELEGRAPH := 1
const PULSE_PHASE_EXPAND := 2

var _pulse_timer: float = 0.0
var _pulse_count: int = 0
var _pulse_is_directed: bool = false
var _directed_spoke_angle: float = 0.0
var _heal_timer: float = 0.0
var _heal_channel_left: float = 0.0
var _heal_silenced_flash: float = 0.0
var _heal_success_flash: float = 0.0
var _stagger_left: float = 0.0
var _aura_refresh_left: float = 0.0
var _contact_attack_cooldown_left: float = 0.0
var _last_heal_success_flash: float = 0.0

var _pulse_phase: int = PULSE_PHASE_NONE
var _pulse_phase_left: float = 0.0
var _pulse_radius: float = 0.0
var _pulse_prev_radius: float = 0.0
var _pulse_marked_ids: Dictionary = {}

func should_force_network_runtime_state_sampling() -> bool:
	return _pulse_phase != PULSE_PHASE_NONE or _heal_channel_left > 0.0 or _heal_silenced_flash > 0.0 or _heal_success_flash > 0.0 or _stagger_left > 0.0

func get_priority_network_sync_interval_sec() -> float:
	if _pulse_phase == PULSE_PHASE_EXPAND or _heal_channel_left > 0.0:
		return 0.05
	if _pulse_phase == PULSE_PHASE_TELEGRAPH:
		return 0.08
	return 0.0

func _get_custom_network_runtime_state() -> Dictionary:
	# Compact wire payload — see /memories/repo/custom_runtime_state_size_budget.md.
	return {
		"hc": _heal_channel_left,
		"pp": _pulse_phase,
		"pl": _pulse_phase_left,
		"pr": _pulse_radius,
		"hs": _heal_silenced_flash,
		"hk": _heal_success_flash,
		"st": _stagger_left,
		"pd": _pulse_is_directed,
		"da": _directed_spoke_angle
	}

func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	if custom_state.is_empty():
		return
	_heal_channel_left = float(custom_state.get("hc", _heal_channel_left))
	_pulse_phase = int(custom_state.get("pp", _pulse_phase))
	_pulse_phase_left = float(custom_state.get("pl", _pulse_phase_left))
	_pulse_radius = float(custom_state.get("pr", _pulse_radius))
	_heal_silenced_flash = float(custom_state.get("hs", _heal_silenced_flash))
	_stagger_left = float(custom_state.get("st", _stagger_left))
	_pulse_is_directed = bool(custom_state.get("pd", _pulse_is_directed))
	_directed_spoke_angle = float(custom_state.get("da", _directed_spoke_angle))
	var incoming_success_flash := float(custom_state.get("hk", _heal_success_flash))
	# Detect heal-success rising edge on joiner so we can fire the rest-site VFX once per cycle.
	if incoming_success_flash > _last_heal_success_flash + 0.01 and incoming_success_flash > 0.4:
		_emit_heal_success_vfx()
	_heal_success_flash = incoming_success_flash
	_last_heal_success_flash = incoming_success_flash

func _ready() -> void:
	max_health = max_health_apex
	super._ready()
	crowd_separation_radius = 80.0
	crowd_separation_strength = 110.0
	configure_health_bar_visuals(health_bar_offset_apex, health_bar_size_apex)
	_pulse_timer = pulse_interval
	_heal_timer = heal_channel_interval
	for child in get_children():
		if child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if shape_node.shape is CircleShape2D:
				(shape_node.shape as CircleShape2D).radius = collision_shape_radius
			break
	_resolve_anchor()

func _resolve_anchor() -> void:
	# Toll is the centerpiece: it always glides toward the arena center, regardless of where it spawns.
	anchor_world_position = arena_center_world

func _process_behavior(delta: float) -> void:
	# Survey grace: hold pulse/heal timers while encounter intro is running so the bell never rings
	# before players have engaged. Anchor-pull keeps the body planted.
	var in_survey := not is_instance_valid(target) and target_candidates.is_empty()
	if not in_survey:
		# Gameplay is active — tick all systems.
		_decay_flash_timers(delta)
		_tick_aura(delta)
		_tick_pulse(delta)
		_tick_heal_channel(delta)
		_tick_contact(delta)
		if _stagger_left > 0.0:
			_stagger_left = maxf(0.0, _stagger_left - delta)
		_apply_anchor_pull(delta)
	else:
		# Survey phase: hold all timers and pin position exactly — no drift toward anchor.
		velocity = Vector2.ZERO

	move_and_slide()
	queue_redraw()

func should_process_remote_visuals_every_frame() -> bool:
	return not network_simulation_enabled and (
		_heal_channel_left > 0.0
		or _pulse_phase != PULSE_PHASE_NONE
		or _heal_silenced_flash > 0.0
		or _heal_success_flash > 0.0
		or _stagger_left > 0.0
	)

func _process_network_visuals(delta: float) -> void:
	# Joiner-side ticking — host owns gameplay, this drives smooth visuals between syncs.
	_decay_flash_timers(delta)
	if _stagger_left > 0.0:
		_stagger_left = maxf(0.0, _stagger_left - delta)
	if _heal_channel_left > 0.0:
		_heal_channel_left = maxf(0.0, _heal_channel_left - delta)
	if _pulse_phase != PULSE_PHASE_NONE:
		_pulse_phase_left = maxf(0.0, _pulse_phase_left - delta)
		if _pulse_phase == PULSE_PHASE_EXPAND:
			var t := 1.0 - clampf(_pulse_phase_left / maxf(0.001, pulse_expand_duration), 0.0, 1.0)
			_pulse_radius = lerpf(0.0, pulse_max_radius, t)
		elif _pulse_phase == PULSE_PHASE_TELEGRAPH:
			_pulse_radius = 0.0
		if _pulse_phase_left <= 0.0 and _pulse_phase == PULSE_PHASE_EXPAND:
			_pulse_phase = PULSE_PHASE_NONE
			_pulse_radius = 0.0
	queue_redraw()

func _remote_extrapolate(_delta: float) -> void:
	pass

func _decay_flash_timers(delta: float) -> void:
	if _heal_silenced_flash > 0.0:
		_heal_silenced_flash = maxf(0.0, _heal_silenced_flash - delta)
	if _heal_success_flash > 0.0:
		_heal_success_flash = maxf(0.0, _heal_success_flash - delta)

func _apply_anchor_pull(delta: float) -> void:
	# Toll is stationary — apply a stiff pull toward the anchor so any shove/knockback decays away,
	# and the body always glides back toward the arena center.
	var to_anchor := anchor_world_position - global_position
	var dist := to_anchor.length()
	if dist < 1.0:
		velocity = velocity.move_toward(Vector2.ZERO, anchor_pull_strength * delta)
		return
	var desired_speed := minf(anchor_arrival_speed_cap, dist * 4.0)
	var desired := to_anchor.normalized() * desired_speed
	velocity = velocity.move_toward(desired, anchor_pull_strength * delta)

# --- Aura of Tithe -----------------------------------------------------------

func _tick_aura(delta: float) -> void:
	_aura_refresh_left = maxf(0.0, _aura_refresh_left - delta)
	if _aura_refresh_left > 0.0:
		return
	_aura_refresh_left = aura_slow_refresh_interval
	if aura_slow_mult >= 1.0:
		return
	var is_channeling := _heal_channel_left > 0.0
	for player in _get_damageable_targets():
		if not is_instance_valid(player):
			continue
		var dist := player.global_position.distance_to(anchor_world_position)
		if dist > aura_radius:
			continue
		var peer_id := 0
		if "player_id" in player:
			peer_id = int(player.player_id)
		var applied_mult := aura_slow_mult
		# During channel: players outside the sanctum are hit with a stronger slow.
		# Only standing in the sanctum offers relief — makes ignoring channels actively punishing.
		if is_channeling and dist > inner_sanctum_radius:
			applied_mult = minf(applied_mult, 0.28)
		_dispatch_slow(peer_id, player, aura_slow_apply_duration, applied_mult)

# --- Contact strike ----------------------------------------------------------

func _tick_contact(delta: float) -> void:
	if _contact_attack_cooldown_left > 0.0:
		_contact_attack_cooldown_left = maxf(0.0, _contact_attack_cooldown_left - delta)
		return
	for player in _get_damageable_targets():
		if not is_instance_valid(player):
			continue
		if global_position.distance_to(player.global_position) > contact_attack_range:
			continue
		if not DAMAGEABLE.apply_damage(player, contact_damage, {"source": "enemy_contact", "ability": "toll_strike"}):
			continue
		_contact_attack_cooldown_left = contact_attack_interval
		attack_anim_time_left = attack_anim_duration
		return

# --- Tribute Pulse -----------------------------------------------------------

func _tick_pulse(delta: float) -> void:
	if _pulse_phase == PULSE_PHASE_NONE:
		_pulse_timer = maxf(0.0, _pulse_timer - delta)
		if _pulse_timer <= 0.0:
			_begin_pulse_telegraph()
		return
	_pulse_phase_left = maxf(0.0, _pulse_phase_left - delta)
	if _pulse_phase == PULSE_PHASE_TELEGRAPH:
		if _pulse_phase_left <= 0.0:
			_begin_pulse_expand()
	elif _pulse_phase == PULSE_PHASE_EXPAND:
		_pulse_prev_radius = _pulse_radius
		var t := 1.0 - clampf(_pulse_phase_left / maxf(0.001, pulse_expand_duration), 0.0, 1.0)
		_pulse_radius = lerpf(0.0, pulse_max_radius, t)
		_resolve_pulse_band_hits()
		if _pulse_phase_left <= 0.0:
			_end_pulse()

func _begin_pulse_telegraph() -> void:
	_pulse_count += 1
	# Every 3rd pulse is a directed spoke-pulse aimed at the player.
	_pulse_is_directed = (_pulse_count % 3 == 0)
	if _pulse_is_directed:
		var targets := _get_damageable_targets()
		if not targets.is_empty() and is_instance_valid(targets[0]):
			var to_player := targets[0].global_position - anchor_world_position
			_directed_spoke_angle = to_player.angle() if to_player.length() > 0.001 else 0.0
		else:
			_directed_spoke_angle = 0.0
	_pulse_phase = PULSE_PHASE_TELEGRAPH
	_pulse_phase_left = pulse_telegraph_duration
	_pulse_radius = 0.0
	_pulse_prev_radius = 0.0
	_pulse_marked_ids.clear()

func _begin_pulse_expand() -> void:
	_pulse_phase = PULSE_PHASE_EXPAND
	_pulse_phase_left = pulse_expand_duration
	_pulse_radius = 0.0
	_pulse_prev_radius = 0.0

func _end_pulse() -> void:
	_pulse_phase = PULSE_PHASE_NONE
	_pulse_phase_left = 0.0
	_pulse_radius = 0.0
	_pulse_prev_radius = 0.0
	_pulse_marked_ids.clear()
	_pulse_timer = pulse_interval
	# Stagger: guarantee a safe approach window between pulse resolve and the next heal channel.
	# Push the heal timer forward so it won't fire for at least half an interval.
	_heal_timer = maxf(_heal_timer, heal_channel_interval * 0.5)

func _resolve_pulse_band_hits() -> void:
	var leading := _pulse_radius
	var trailing := maxf(0.0, leading - pulse_band_thickness)
	for player in _get_damageable_targets():
		if not is_instance_valid(player):
			continue
		var pid := player.get_instance_id()
		if _pulse_marked_ids.has(pid):
			continue
		var dist := player.global_position.distance_to(anchor_world_position)
		var to_player := player.global_position - anchor_world_position
		if dist < trailing or dist > leading:
			continue
		# Regular ring pulses can be dashed through, but directed spokes are phase-resistant.
		if bool(player.get("dash_phasing_active")) and not _pulse_is_directed:
			continue
		# Directed spoke-pulse: only three 60°-wide arcs hit — the gaps are safe.
		if _pulse_is_directed:
			var player_angle: float = to_player.angle() if dist > 0.001 else 0.0
			var half_arc: float = PI / 6.0
			var in_spoke := false
			for si in range(3):
				var spoke_ang: float = _directed_spoke_angle + float(si) / 3.0 * TAU
				var diff: float = abs(fmod(player_angle - spoke_ang + PI * 3.0, TAU) - PI)
				if diff < half_arc:
					in_spoke = true
					break
			if not in_spoke:
				continue
		# Player is inside the expanding band this frame — register a hit.
		_pulse_marked_ids[pid] = true
		_apply_pulse_hit(player, dist)

func _apply_pulse_hit(player: Node2D, dist: float) -> void:
	DAMAGEABLE.apply_damage(player, pulse_damage, {"source": "enemy_toll", "ability": "pulse_hit"})
	if not is_instance_valid(player):
		return
	var peer_id := 0
	if "player_id" in player:
		peer_id = int(player.player_id)
	# Stun = heavy slow only. No dash lockout — players must be able to dash into the
	# sanctum after being clipped. The outward impulse already pushes them away.
	if stun_duration > 0.0:
		_dispatch_slow(peer_id, player, stun_duration, stun_slow_mult)
	# Outward nudge along the radial direction so players are visibly displaced by the wave.
	var dir := Vector2.RIGHT
	if dist > 0.001:
		dir = (player.global_position - anchor_world_position) / dist
	_dispatch_polar_shift(peer_id, player, dir, 360.0, 0.0)

# --- Heal Channel ------------------------------------------------------------

func _tick_heal_channel(delta: float) -> void:
	# Heal runs on an independent timer — not tied to any global state.
	if _heal_channel_left > 0.0:
		_heal_channel_left = maxf(0.0, _heal_channel_left - delta)
		if _heal_channel_left <= 0.0:
			_resolve_heal_channel()
		return
	# Not channeling — count down to next heal.
	if health_state == null:
		return
	var current := int(health_state.current_health)
	var max_hp := int(health_state.max_health)
	if current >= max_hp:
		# At full health — keep the timer paused so we don't waste a channel attempt.
		_heal_timer = maxf(_heal_timer, 1.0)
		return
	_heal_timer = maxf(0.0, _heal_timer - delta)
	if _heal_timer <= 0.0:
		_begin_heal_channel()

func _begin_heal_channel() -> void:
	_heal_channel_left = heal_channel_duration

func _resolve_heal_channel() -> void:
	var interrupted := _is_anyone_in_inner_sanctum()
	if interrupted:
		_heal_silenced_flash = 0.65
		# Stagger: bell visibly shakes to confirm the interrupt landed.
		_stagger_left = 0.55
	else:
		var healed := _apply_heal()
		if healed:
			_heal_success_flash = 0.55
			_last_heal_success_flash = _heal_success_flash
			_emit_heal_success_vfx()
	_heal_channel_left = 0.0
	_heal_timer = heal_channel_interval

func _is_anyone_in_inner_sanctum() -> bool:
	for player in _get_damageable_targets():
		if not is_instance_valid(player):
			continue
		var dist := player.global_position.distance_to(anchor_world_position)
		if dist <= inner_sanctum_radius:
			return true
	return false

func _apply_heal() -> bool:
	if health_state == null:
		return false
	var max_hp := int(health_state.max_health)
	if max_hp <= 0:
		return false
	var heal_amount := maxi(1, int(round(float(max_hp) * clampf(heal_fraction, 0.0, 0.5))))
	var before := int(health_state.current_health)
	if before >= max_hp:
		return false
	# Use health_state.heal so the health_changed signal fires and the bar redraws.
	heal(heal_amount)
	return int(health_state.current_health) > before

func _emit_heal_success_vfx() -> void:
	# Reuse the rest-site heal VFX so the heal lands with the same readability cue.
	var feedback_targets: Array[Object] = []
	for candidate in target_candidates:
		if not is_instance_valid(candidate):
			continue
		var feedback_obj: Object = candidate.get("player_feedback") as Object
		if feedback_obj == null:
			continue
		if feedback_targets.has(feedback_obj):
			continue
		feedback_targets.append(feedback_obj)
	for feedback in feedback_targets:
		if feedback.has_method("play_rest_site_heal"):
			feedback.call("play_rest_site_heal", global_position)

# --- Multiplayer dispatch helpers -------------------------------------------

func _dispatch_slow(peer_id: int, player_node: Node2D, duration: float, mult: float) -> void:
	if duration <= 0.0 or mult >= 1.0:
		return
	# Direct call first (most reliable), then fallback to replication service.
	if player_node.has_method("apply_external_slow"):
		player_node.apply_external_slow(duration, mult)
		return
	var replication_service := get_node_or_null("/root/PlayerReplicationService")
	if replication_service != null and replication_service.has_method("send_external_slow"):
		replication_service.send_external_slow(peer_id, duration, mult)

func _dispatch_polar_shift(peer_id: int, player_node: Node2D, dir: Vector2, force: float, dash_lockout: float) -> void:
	var replication_service := get_node_or_null("/root/PlayerReplicationService")
	if peer_id > 0 and replication_service != null and replication_service.has_method("send_polar_shift_effect"):
		replication_service.send_polar_shift_effect(peer_id, dir, force, dash_lockout)
		return
	if player_node.has_method("apply_polar_shift_impulse"):
		player_node.apply_polar_shift_impulse(dir, force)
	if dash_lockout > 0.0 and player_node.has_method("apply_polar_shift_dash_lockout"):
		player_node.apply_polar_shift_dash_lockout(dash_lockout)

# --- Lifecycle ---------------------------------------------------------------

func _on_health_state_died() -> void:
	_pulse_phase = PULSE_PHASE_NONE
	_pulse_phase_left = 0.0
	_pulse_radius = 0.0
	_pulse_marked_ids.clear()
	_heal_channel_left = 0.0
	died.emit()
	queue_free()

func take_damage(amount: int, _damage_context: Dictionary = {}) -> void:
	if amount <= 0:
		return
	if damage_blocked:
		return
	var before_health := int(health_state.current_health)
	health_state.take_damage(amount)
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

# --- Drawing -----------------------------------------------------------------

func _draw() -> void:
	_draw_aura()
	_draw_inner_sanctum()
	_draw_pulse()
	_draw_body()
	_draw_heal_channel_overlay()
	_draw_heal_flash()

func _draw_aura() -> void:
	if aura_slow_mult >= 1.0:
		return
	var local_center := anchor_world_position - global_position
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.0028)
	# Soft tinted ground disc so the slow zone is always readable but never noisy.
	draw_circle(local_center, aura_radius, Color(0.78, 0.46, 0.18, 0.07 + 0.03 * pulse))
	draw_arc(local_center, aura_radius, 0.0, TAU, 64, Color(0.96, 0.66, 0.28, 0.42 + 0.14 * pulse), 2.2)
	draw_arc(local_center, aura_radius - 4.0, 0.0, TAU, 64, Color(1.0, 0.86, 0.50, 0.22 + 0.08 * pulse), 1.2)
	# Inward chevrons emphasize the "pull toward the altar" reading and make the aura feel alive.
	var chevron_color := Color(1.0, 0.84, 0.46, 0.45 + 0.20 * pulse)
	var chevron_count := 16
	for i in range(chevron_count):
		var angle := float(i) / float(chevron_count) * TAU
		var dir := Vector2.RIGHT.rotated(angle)
		var perp := Vector2(-dir.y, dir.x)
		var tip := local_center + dir * (aura_radius - 12.0)
		var back_a := tip + dir * 8.0 + perp * 5.0
		var back_b := tip + dir * 8.0 - perp * 5.0
		draw_line(tip, back_a, chevron_color, 1.4)
		draw_line(tip, back_b, chevron_color, 1.4)

func _draw_inner_sanctum() -> void:
	var local_center := anchor_world_position - global_position
	var channeling := _heal_channel_left > 0.0
	var t_ms := float(Time.get_ticks_msec())
	var idle_pulse := 0.5 + 0.5 * sin(t_ms * 0.006)

	# Always draw the sanctum floor so the mechanic is legible before the first channel fires.
	var idle_fill_alpha := 0.06 + 0.03 * idle_pulse
	var idle_rim_alpha := 0.40 + 0.12 * idle_pulse
	draw_circle(local_center, inner_sanctum_radius, Color(0.50, 1.0, 0.72, idle_fill_alpha))
	draw_arc(local_center, inner_sanctum_radius, 0.0, TAU, 48, Color(0.50, 1.0, 0.72, idle_rim_alpha), 1.6)

	# Always-on inward arrows around the sanctum ring — communicates "stand here to interrupt".
	var arrow_count := 8
	var arrow_alpha := 0.30 + 0.14 * idle_pulse
	if channeling:
		arrow_alpha = 0.75 + 0.20 * (0.5 + 0.5 * sin(t_ms * 0.022))
	var arrow_color := Color(0.84, 1.0, 0.92, arrow_alpha)
	for i in range(arrow_count):
		var angle := float(i) / float(arrow_count) * TAU
		var dir := Vector2.RIGHT.rotated(angle)
		# Arrow tip points inward toward the center.
		var tip := local_center + dir * (inner_sanctum_radius - 10.0)
		var perp := Vector2(-dir.y, dir.x)
		var base_a := tip + dir * 10.0 + perp * 5.0
		var base_b := tip + dir * 10.0 - perp * 5.0
		draw_line(tip, base_a, arrow_color, 1.6)
		draw_line(tip, base_b, arrow_color, 1.6)

	if channeling:
		# Escalated channel state: bright pulsing rim + fill so it clearly reads as "active window".
		var ch_pulse := 0.5 + 0.5 * sin(t_ms * 0.022)
		draw_circle(local_center, inner_sanctum_radius, Color(0.50, 1.0, 0.72, 0.14 + 0.08 * ch_pulse))
		draw_arc(local_center, inner_sanctum_radius, 0.0, TAU, 48, Color(0.50, 1.0, 0.72, 0.85 + 0.15 * ch_pulse), 2.8)

func _draw_pulse() -> void:
	if _pulse_phase == PULSE_PHASE_NONE:
		return
	var local_center := anchor_world_position - global_position
	if _pulse_phase == PULSE_PHASE_TELEGRAPH:
		# Charge-up: rings collapse inward toward the bell to read as winding tension.
		var t := 1.0 - clampf(_pulse_phase_left / maxf(0.001, pulse_telegraph_duration), 0.0, 1.0)
		var lead := lerpf(pulse_max_radius * 0.55, body_draw_radius + 18.0, t)
		var alpha := 0.35 + 0.45 * t
		if _pulse_is_directed:
			# Show three spoke lines collapsing inward — gives player time to find the safe gap.
			var half_arc := PI / 6.0
			for si in range(3):
				var spoke_ang := _directed_spoke_angle + float(si) / 3.0 * TAU
				draw_arc(local_center, lead, spoke_ang - half_arc, spoke_ang + half_arc, 18, Color(COLOR_PHASE_RESIST_GLOW.r, COLOR_PHASE_RESIST_GLOW.g, COLOR_PHASE_RESIST_GLOW.b, COLOR_PHASE_RESIST_GLOW.a * alpha * 1.6), 3.0)
				draw_arc(local_center, lead - 6.0, spoke_ang - half_arc, spoke_ang + half_arc, 18, Color(COLOR_PHASE_RESIST_RING.r, COLOR_PHASE_RESIST_RING.g, COLOR_PHASE_RESIST_RING.b, alpha), 1.8)
				var spoke_dir := Vector2(cos(spoke_ang), sin(spoke_ang))
				draw_line(local_center, local_center + spoke_dir * lead, Color(COLOR_PHASE_RESIST_RING.r, COLOR_PHASE_RESIST_RING.g, COLOR_PHASE_RESIST_RING.b, alpha * 0.45), 1.4)
				_draw_phase_resistant_notches(local_center, spoke_ang, body_draw_radius + 12.0, lead, alpha, body_draw_radius + 10.0)
		else:
			draw_arc(local_center, lead, 0.0, TAU, 56, Color(1.0, 0.86, 0.42, alpha * 0.7), 2.4)
			draw_arc(local_center, lead - 6.0, 0.0, TAU, 56, Color(1.0, 0.96, 0.78, alpha), 1.4)
	elif _pulse_phase == PULSE_PHASE_EXPAND:
		var leading := _pulse_radius
		var trailing := maxf(0.0, leading - pulse_band_thickness)
		if _pulse_is_directed:
			# Spoke-pulse: draw three 60°-wide arc sectors. Gaps between them are safe.
			var half_arc := PI / 6.0
			for si in range(3):
				var spoke_ang := _directed_spoke_angle + float(si) / 3.0 * TAU
				var arc_s := spoke_ang - half_arc
				var arc_e := spoke_ang + half_arc
				draw_arc(local_center, pulse_max_radius, arc_s, arc_e, 24, Color(COLOR_PHASE_RESIST_GLOW.r, COLOR_PHASE_RESIST_GLOW.g, COLOR_PHASE_RESIST_GLOW.b, 0.46), 1.9)
				draw_arc(local_center, leading, arc_s, arc_e, 32, Color(COLOR_PHASE_RESIST_GLOW.r, COLOR_PHASE_RESIST_GLOW.g, COLOR_PHASE_RESIST_GLOW.b, 0.44), 8.0)
				draw_arc(local_center, leading, arc_s, arc_e, 32, Color(COLOR_PHASE_RESIST_RING.r, COLOR_PHASE_RESIST_RING.g, COLOR_PHASE_RESIST_RING.b, 0.95), 3.1)
				if trailing > 0.5:
					draw_arc(local_center, trailing, arc_s, arc_e, 24, Color(COLOR_PHASE_RESIST_RING.r, COLOR_PHASE_RESIST_RING.g, COLOR_PHASE_RESIST_RING.b, 0.55), 1.8)
				var spoke_dir := Vector2(cos(spoke_ang), sin(spoke_ang))
				draw_line(local_center, local_center + spoke_dir * pulse_max_radius, Color(COLOR_PHASE_RESIST_RING.r, COLOR_PHASE_RESIST_RING.g, COLOR_PHASE_RESIST_RING.b, 0.28), 1.4)
				_draw_phase_resistant_notches(local_center, spoke_ang, trailing + 10.0, leading + 3.0, 1.0, body_draw_radius + 10.0)
		else:
			# Full-ring pulse — ghost ring at max reach then expanding band.
			draw_arc(local_center, pulse_max_radius, 0.0, TAU, 72, Color(1.0, 0.80, 0.36, 0.55), 2.0)
			draw_arc(local_center, leading, 0.0, TAU, 80, Color(1.0, 0.62, 0.24, 0.45), 8.0)
			draw_arc(local_center, leading, 0.0, TAU, 80, Color(1.0, 0.92, 0.58, 0.95), 3.0)
			draw_arc(local_center, leading - pulse_band_thickness * 0.5, 0.0, TAU, 64, Color(1.0, 0.78, 0.36, 0.35), 4.0)
			draw_arc(local_center, trailing, 0.0, TAU, 64, Color(1.0, 0.66, 0.30, 0.55), 1.6)

func _draw_heal_channel_overlay() -> void:
	if _heal_channel_left <= 0.0:
		return
	var t_remaining := clampf(_heal_channel_left / maxf(0.001, heal_channel_duration), 0.0, 1.0)
	var t_progress := 1.0 - t_remaining
	# Arc that fills around the body as the channel completes — clear "is the heal almost done?" read.
	var radius := body_draw_radius + 14.0
	var sweep := t_progress * TAU
	if sweep > 0.01:
		var start_angle := -PI * 0.5
		var end_angle := start_angle + sweep
		draw_arc(Vector2.ZERO, radius, start_angle, end_angle, 64, Color(0.46, 0.98, 0.66, 0.92), 3.4)
	# Faint full ring so players see the channel is in progress even before it fills.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.62, 1.0, 0.78, 0.22), 1.4)

func _draw_heal_flash() -> void:
	if _heal_success_flash > 0.0:
		var t := clampf(_heal_success_flash / 0.55, 0.0, 1.0)
		var ring_radius := body_draw_radius + 8.0 + (1.0 - t) * 26.0
		var alpha := 0.6 * t
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 36, Color(0.46, 0.96, 0.62, alpha), 3.0)
		draw_arc(Vector2.ZERO, ring_radius - 5.0, 0.0, TAU, 36, Color(0.84, 1.0, 0.92, alpha * 0.7), 1.6)
	if _heal_silenced_flash > 0.0:
		var t2 := clampf(_heal_silenced_flash / 0.65, 0.0, 1.0)
		var ring_radius2 := body_draw_radius + 6.0 + (1.0 - t2) * 30.0
		var alpha2 := 0.7 * t2
		# Cross-out ring + spokes to read clearly as a SILENCE / interrupt.
		draw_arc(Vector2.ZERO, ring_radius2, 0.0, TAU, 36, Color(0.96, 0.36, 0.30, alpha2), 3.4)
		var spoke_color := Color(1.0, 0.84, 0.62, alpha2 * 0.95)
		for i in range(4):
			var ang := float(i) / 4.0 * TAU + PI * 0.25
			var dir := Vector2.RIGHT.rotated(ang)
			draw_line(dir * (ring_radius2 - 8.0), dir * (ring_radius2 + 8.0), spoke_color, 2.2)

func _draw_body() -> void:
	var time := float(Time.get_ticks_msec())
	var breathe := 0.5 + 0.5 * sin(time * 0.0026)
	var channeling := _heal_channel_left > 0.0
	var crack_glow := 0.70 + 0.30 * breathe if channeling else 0.40 + 0.22 * breathe
	var r := body_draw_radius

	# === Outer shadow halo — grounds the altar ===
	draw_circle(Vector2.ZERO, r + 16.0, Color(0.06, 0.03, 0.01, 0.35))

	# === Trapezoid monolith body ===
	# Wide base, narrower top — reads as heavy stone altar.
	var w_bot := r * 1.30
	var w_top := r * 0.82
	var h_top := -r * 0.88
	var h_bot := r * 0.72
	var stone_color := Color(0.18, 0.12, 0.09, 0.96)
	var stone_pts := PackedVector2Array([
		Vector2(-w_top, h_top),
		Vector2(w_top, h_top),
		Vector2(w_bot, h_bot),
		Vector2(-w_bot, h_bot)
	])
	draw_colored_polygon(stone_pts, stone_color)

	# Stone edge highlights — left and right flanks
	var edge_col := Color(0.52, 0.36, 0.22, 0.55)
	draw_line(Vector2(-w_top, h_top), Vector2(-w_bot, h_bot), edge_col, 2.0)
	draw_line(Vector2(w_top, h_top), Vector2(w_bot, h_bot), edge_col, 2.0)
	# Top ledge — slightly lighter to read as a flat surface
	var ledge_col := Color(0.62, 0.44, 0.28, 0.70)
	draw_line(Vector2(-w_top, h_top), Vector2(w_top, h_top), ledge_col, 2.6)

	# === Four angular flanges at cardinal directions ===
	# Thin blade-like protrusions that reinforce the "altar ward" silhouette.
	var flange_color := Color(0.28, 0.18, 0.10, 0.90)
	var flange_bright := Color(0.72, 0.52, 0.28, 0.65)
	for fi in range(4):
		var ang := float(fi) / 4.0 * TAU + PI * 0.25
		var fd := Vector2(cos(ang), sin(ang))
		var fp := Vector2(-fd.y, fd.x)
		var f_tip := fd * (r * 1.55)
		var f_base_a := fd * (r * 0.72) + fp * (r * 0.16)
		var f_base_b := fd * (r * 0.72) - fp * (r * 0.16)
		draw_colored_polygon(PackedVector2Array([f_tip, f_base_a, f_base_b]), flange_color)
		draw_line(f_base_a, f_tip, flange_bright, 1.4)
		draw_line(f_base_b, f_tip, Color(flange_bright.r, flange_bright.g, flange_bright.b, 0.35), 1.0)

	# === Crack network on the stone face ===
	# Three cracks radiating from the center, filled with amber glow.
	var crack_col := Color(1.0, 0.72, 0.22, crack_glow)
	var crack_glow_col := Color(1.0, 0.58, 0.14, crack_glow * 0.45)
	var crack_angles: Array[float] = [PI * 0.15, PI * 0.88, PI * 1.52]
	for ci in range(3):
		var ca: float = crack_angles[ci]
		var cd := Vector2(cos(ca), sin(ca))
		var c_end := cd * (r * 0.72)
		var c_mid := cd * (r * 0.36) + Vector2(-cd.y, cd.x) * (r * 0.10)
		# Glow beneath
		draw_line(Vector2.ZERO, c_end, crack_glow_col, 5.0)
		# Bright crack line
		draw_line(Vector2.ZERO, c_mid, crack_col, 2.2)
		draw_line(c_mid, c_end, crack_col, 1.6)

	# === Glowing core (altar heart) ===
	var core_r := r * 0.28 + breathe * 2.2
	var core_col := Color(1.0, 0.68, 0.18, 0.85 + 0.15 * breathe)
	if channeling:
		core_col = Color(0.52, 1.0, 0.72, 0.90 + 0.10 * breathe)
	draw_circle(Vector2.ZERO, core_r + 5.0, Color(core_col.r, core_col.g, core_col.b, 0.22))
	draw_circle(Vector2.ZERO, core_r, core_col)
	draw_circle(Vector2.ZERO, core_r * 0.45, Color(1.0, 1.0, 0.92, 0.95))

	# === Floating bell crown — rotates slowly, unique silhouette identifier ===
	var bell_y := h_top - r * 0.28 - breathe * 1.6
	var bell_center := Vector2(0.0, bell_y)
	var bell_spin := time * 0.00042
	_draw_bell_crown(bell_center, r * 0.54, bell_spin, channeling, breathe)

	# === Gaze indicator toward target ===
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		if to_target.length() > 0.001:
			var look := to_target.normalized()
			var eye_pos := look * (r * 0.52)
			draw_circle(eye_pos, 3.2 + breathe * 0.6, Color(0.08, 0.04, 0.02, 0.95))
			draw_circle(eye_pos, 1.4, Color(1.0, 0.72, 0.20, 0.95))

func _draw_bell_crown(center: Vector2, r: float, spin: float, channeling: bool, breathe: float) -> void:
	# Stagger shake: displace the crown horizontally after an interrupt to visually confirm it landed.
	if _stagger_left > 0.0:
		var st := _stagger_left / 0.55
		center = center + Vector2(sin(_stagger_left * 42.0) * r * 0.28 * st, 0.0)
	# Outer glow halo
	var bell_base_col := Color(0.96, 0.74, 0.28, 0.30 + 0.14 * breathe)
	if channeling:
		bell_base_col = Color(0.52, 1.0, 0.72, 0.40 + 0.20 * breathe)
	draw_circle(center, r + 7.0, Color(bell_base_col.r, bell_base_col.g, bell_base_col.b, 0.18))

	# Bell dome — flat-bottomed arc (half-circle wider at base).
	var dome_pts: PackedVector2Array = PackedVector2Array()
	var dome_segs := 20
	for i in range(dome_segs + 1):
		var t := float(i) / float(dome_segs)
		var ang := PI + t * PI  # bottom-left → top → bottom-right
		dome_pts.append(center + Vector2(cos(ang) * r, sin(ang) * r * 0.76))
	# Close flat bottom
	dome_pts.append(center + Vector2(r, 0.0))
	dome_pts.append(center + Vector2(-r, 0.0))
	var dome_col := Color(0.22, 0.14, 0.08, 0.92)
	draw_colored_polygon(dome_pts, dome_col)

	# Bell rim band
	var rim_col := Color(0.82, 0.56, 0.24, 0.90)
	if channeling:
		rim_col = Color(0.52, 1.0, 0.72, 0.92)
	draw_line(center + Vector2(-r, 0.0), center + Vector2(r, 0.0), rim_col, 3.2)
	# Rim left/right flare
	draw_line(center + Vector2(-r, 0.0), center + Vector2(-r - r * 0.18, r * 0.14), rim_col, 2.4)
	draw_line(center + Vector2(r, 0.0), center + Vector2(r + r * 0.18, r * 0.14), rim_col, 2.4)

	# Three vertical ridges on the dome face for visual texture
	var ridge_col := Color(0.62, 0.44, 0.22, 0.45)
	for ri in range(3):
		var rx := lerpf(-r * 0.55, r * 0.55, float(ri) / 2.0)
		# Find dome y at this x
		var dome_y := center.y - r * 0.76 * sqrt(maxf(0.0, 1.0 - (rx / r) * (rx / r)))
		draw_line(center + Vector2(rx, 0.0), Vector2(center.x + rx, dome_y), ridge_col, 1.4)

	# Clapper — hangs from center, swings based on spin offset
	var clapper_swing := sin(spin * 4.2) * r * 0.32
	var clapper_top := center + Vector2(0.0, -r * 0.24)
	var clapper_bot := center + Vector2(clapper_swing, r * 0.14)
	var clapper_col := Color(1.0, 0.88, 0.46, 0.95)
	draw_line(clapper_top, clapper_bot, clapper_col, 2.4)
	draw_circle(clapper_bot, r * 0.14 + breathe * 1.0, clapper_col)
	draw_circle(clapper_bot, r * 0.06, Color(1.0, 1.0, 0.88, 1.0))

	# Four spinning accent marks orbiting the crown — read as "ringing"
	var accent_count := 4
	for ai in range(accent_count):
		var ang := spin * 1.8 + float(ai) / float(accent_count) * TAU
		var accent_pos := center + Vector2(cos(ang), sin(ang)) * (r + 5.0)
		var accent_alpha := 0.35 + 0.22 * breathe
		draw_circle(accent_pos, 1.8, Color(1.0, 0.82, 0.36, accent_alpha))
