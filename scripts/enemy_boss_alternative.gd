extends "res://scripts/enemy_base.gd"
## Three encounter identities share only the committed-warning lifecycle. Shapes
## are captured in world space once, and used by both damage and presentation.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")
const ATTACK_CALLOUT := preload("res://scripts/shared/enemy_attack_callout.gd")
enum State { IDLE, WARNING, RECOVER }

const PROFILES := {
	"kilnheart": {"health": 1320, "radius": 34.0, "speed": 190.0, "distance": 145.0, "damage": 38, "cooldown": 0.44, "recover": 0.8, "tint": Color(1.0, 0.48, 0.19), "names": ["Crucible Slam", "Furnace Halo", "Cinderfall"]},
	"glassweaver": {"health": 2000, "radius": 38.0, "speed": 158.0, "distance": 290.0, "damage": 40, "cooldown": 0.52, "recover": 0.58, "tint": Color(0.3, 0.88, 0.94), "names": ["Split Loom", "Cross Stitch", "Glass Cage"]},
	"null_archivist": {"health": 2400, "radius": 40.0, "speed": 146.0, "distance": 235.0, "damage": 36, "cooldown": 0.48, "recover": 0.62, "tint": Color(0.79, 0.61, 1.0), "names": ["Record", "Revision", "Final Margin"]},
}

@export var boss_id: String = "kilnheart"
@export var arena_size: Vector2 = Vector2(1260.0, 900.0)
var move_speed: float = 122.0
var action_cooldown: float = 0.68
var recover_time: float = 0.72
var attack_damage: int = 38
var boss_state: int = State.IDLE
var attack_kind: int = 0
var state_time_left: float = 0.0
var warning_duration: float = 1.0
var cooldown_left: float = 0.8
var telegraph_alpha: float = 0.0
var _warning_shapes: Array[Dictionary] = []
var _impact_shapes: Array[Dictionary] = []
var _recorded_positions: Array[Vector2] = []
var _afterglow_left: float = 0.0
var _cycle_step: int = 0
var _attack_bag: Array[int] = []
var _last_root_attack: int = -1
var _attack_serial: int = 0
var _snapshot_serial: int = 0
var _received_serial: int = -1
var _received_phase: int = 0
var _received_snapshot: int = -1
var _sequence_step: int = 0
var _sequence_root: int = 0
var _pending_attack_kind: int = -1
var _sequence_focus: Vector2 = Vector2.ZERO
var _sequence_forward: Vector2 = Vector2.RIGHT
var _move_start: Vector2 = Vector2.ZERO
var _slam_landing: Vector2 = Vector2.ZERO
var _slam_collision_layer: int = -1
var _furnace_sound: AudioStreamPlayer
var _furnace_cue_serial: int = -1
var _furnace_cue_phase: int = 0
var _furnace_cue_count: int = 0
static var _furnace_charge_audio: AudioStreamWAV
static var _furnace_impact_audio: AudioStreamWAV

func _ready() -> void:
	if not PROFILES.has(boss_id):
		boss_id = "kilnheart"
	var profile: Dictionary = PROFILES[boss_id]
	max_health = int(profile["health"])
	move_speed = float(profile["speed"])
	action_cooldown = float(profile["cooldown"])
	recover_time = float(profile["recover"])
	attack_damage = int(profile["damage"])
	super._ready()
	dread_resonance_visual_boss_emphasis = true
	configure_health_bar_visuals(Vector2(-72.0, -86.0), Vector2(144.0, 12.0))
	if boss_id == "kilnheart":
		cooldown_left = 0.35
		if DisplayServer.get_name() != "headless":
			_furnace_sound = AudioStreamPlayer.new()
			if AudioServer.get_bus_index("SFX") >= 0:
				_furnace_sound.bus = &"SFX"
			add_child(_furnace_sound)

func _process_behavior(delta: float) -> void:
	if not network_simulation_enabled:
		return
	if _get_current_health() <= 0 or is_queued_for_deletion():
		_cancel_attack()
		return
	_afterglow_left = maxf(0.0, _afterglow_left - delta)
	if _get_damageable_targets().is_empty():
		if boss_state != State.IDLE:
			_cancel_attack()
		velocity = Vector2.ZERO
		return
	match boss_state:
		State.IDLE:
			_move_between_attacks(delta)
			cooldown_left = maxf(0.0, cooldown_left - delta)
			if cooldown_left <= 0.0:
				begin_attack(_choose_root_attack())
				_cycle_step += 1
		State.WARNING:
			# Neither crowd separation nor player movement may drag the attack.
			velocity = Vector2.ZERO
			state_time_left = maxf(0.0, state_time_left - delta)
			telegraph_alpha = 1.0 - state_time_left / warning_duration
			if boss_id == "kilnheart" and attack_kind == 0 and _sequence_step == 0:
				# The body approaches the already painted landing. Neither this
				# motion nor subsequent target movement changes its damage disk.
				global_position = _move_start.lerp(_slam_landing, _slam_travel_progress(telegraph_alpha))
			if state_time_left <= 0.0:
				_resolve_attack()
		State.RECOVER:
			velocity = Vector2.ZERO
			state_time_left = maxf(0.0, state_time_left - delta)
			if state_time_left <= 0.0:
				if _pending_attack_kind >= 0:
					var followup_kind: int = _pending_attack_kind
					_pending_attack_kind = -1
					begin_attack(followup_kind, 1)
					return
				boss_state = State.IDLE
				# Enrage changes the interval, preserving the full dodge warning.
				cooldown_left = action_cooldown * (0.72 if _get_current_health() < max_health / 2 else 1.0)
	queue_redraw()

func _choose_root_attack() -> int:
	# Host-only weighted bags react to spacing without starving a move or
	# repeating the previous root across bag boundaries. Follow-ups never draw.
	if _attack_bag.is_empty():
		_attack_bag.assign([0, 2] if boss_id == "null_archivist" else [0, 1, 2])
	var distance: float = global_position.distance_to(target.global_position) if is_instance_valid(target) else 300.0
	var choices: Array[int] = []
	var weights: Array[float] = []
	var total: float = 0.0
	for kind in _attack_bag:
		if kind == _last_root_attack and _attack_bag.size() > 1:
			continue
		var weight: float = 1.0
		if boss_id == "kilnheart":
			weight = 4.0 if (kind == 0 and distance > 280.0) or (kind == 1 and distance < 250.0) else 1.5
		elif boss_id == "glassweaver":
			weight = 4.0 if (kind == 0 and distance >= 240.0) or (kind == 2 and distance < 240.0) else 2.0
		choices.append(kind)
		weights.append(weight)
		total += weight
	var roll: float = randf() * total
	var chosen: int = choices.back()
	for index in range(choices.size()):
		roll -= weights[index]
		if roll <= 0.0:
			chosen = choices[index]
			break
	_attack_bag.erase(chosen)
	_last_root_attack = chosen
	return chosen

func _move_between_attacks(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = Vector2.ZERO
		return
	var offset := target.global_position - global_position
	var forward := offset.normalized()
	var desired_distance := float(PROFILES[boss_id]["distance"])
	var direction := forward * clampf((offset.length() - desired_distance) / 90.0, -0.55, 1.0)
	if boss_id == "glassweaver":
		direction += forward.orthogonal() * (0.7 if _cycle_step % 2 == 0 else -0.7)
	var half := arena_size * 0.5 - Vector2(125.0, 125.0)
	var inward := Vector2.ZERO
	if absf(global_position.x) > half.x:
		inward.x = -signf(global_position.x)
	if absf(global_position.y) > half.y:
		inward.y = -signf(global_position.y)
	direction = (direction + inward * 2.0).limit_length(1.0)
	velocity = velocity.move_toward(direction * move_speed * slow_speed_mult, 920.0 * delta)
	move_and_slide()
	if forward.length_squared() > 0.001:
		visual_facing_direction = forward

func begin_attack(kind: int, sequence_step: int = 0) -> void:
	if not network_simulation_enabled or _get_current_health() <= 0 or is_queued_for_deletion():
		return
	var candidates := _get_damageable_targets()
	if candidates.is_empty():
		return
	_set_slam_nonblocking(false)
	attack_kind = clampi(kind, 0, 2)
	_sequence_step = clampi(sequence_step, 0, 1)
	if _sequence_step == 0:
		_sequence_root = attack_kind
	_pending_attack_kind = -1
	_attack_serial += 1
	boss_state = State.WARNING
	velocity = Vector2.ZERO
	telegraph_alpha = 0.0
	_afterglow_left = 0.0
	_impact_shapes.clear()
	_warning_shapes.clear()
	var aim: Vector2 = candidates[0].global_position
	if is_instance_valid(target) and candidates.has(target):
		aim = target.global_position
	var forward := (aim - global_position).normalized()
	if forward.length_squared() < 0.001:
		forward = Vector2.RIGHT
	visual_facing_direction = forward
	match boss_id:
		"kilnheart":
			warning_duration = [1.25, 1.3, 1.05][attack_kind]
			match attack_kind:
				0:
					if _sequence_step == 0:
						_move_start = global_position
						_slam_landing = global_position.move_toward(_clamp_to_arena(aim, 205.0), 420.0)
						_sequence_forward = forward
						_circle(_slam_landing, 185.0)
						_set_slam_nonblocking(true)
					else:
						# The hammer opens four furnace vents. These are a new
						# committed warning, with a safe hub and wide safe wedges.
						warning_duration = 1.05
						for index in range(4):
							var axis := _sequence_forward.rotated(index * PI * 0.5)
							_lane(_slam_landing + axis * 115.0, _arena_ray_end(_slam_landing, axis, 480.0, 40.0), 36.0)
				1:
					if _sequence_step == 0:
						_sequence_focus = _clamp_to_arena(global_position, 250.0)
						_circle(_sequence_focus, 185.0)
					else:
						warning_duration = 1.25
						_ring(_sequence_focus, 155.0, 300.0)
				2:
					if _sequence_step == 0:
						for candidate in candidates:
							_circle(candidate.global_position, 108.0)
					else:
						# A fresh visible capture leads a moving target, making a
						# continued orbit different from changing direction.
						warning_duration = 1.65
						var selected: Node2D = target if is_instance_valid(target) and candidates.has(target) else candidates[0]
						var lead: Vector2 = (selected as CharacterBody2D).velocity.limit_length(210.0) * 1.2 if selected is CharacterBody2D else Vector2.ZERO
						_circle(_clamp_to_arena(selected.global_position + lead, 70.0), 108.0)
		"glassweaver":
			warning_duration = [1.1, 0.95, 1.15][attack_kind]
			match attack_kind:
				0:
					# Pick available floor beside the aim. The target must move
					# into the corridor instead of receiving a free safe center.
					_sequence_focus = _offset_safe_point(aim, forward.orthogonal(), 135.0)
					var shift: Vector2 = _sequence_focus - aim
					forward = shift.normalized().orthogonal()
					_sequence_forward = forward
					for side in [-1.0, 1.0]:
						var center: Vector2 = _sequence_focus + forward.orthogonal() * side * 150.0
						_lane(center - forward * 470.0, center + forward * 470.0, 55.0)
				1:
					if _sequence_step > 0:
						aim = _sequence_focus
						forward = _sequence_forward
						if _sequence_root == 1:
							forward = forward.rotated(PI * 0.25)
							warning_duration = 1.1
					else:
						_sequence_focus = aim
						_sequence_forward = forward
					for axis in [forward, forward.orthogonal()]:
						_lane(aim - axis * 330.0, aim + axis * 330.0, 38.0)
				2:
					_sequence_focus = aim
					_sequence_forward = forward
					var cage_positions: Array[Vector2] = []
					for candidate in candidates:
						cage_positions.append(candidate.global_position)
					_rings_with_shared_pockets(cage_positions, 100.0, 225.0)
		"null_archivist":
			warning_duration = [1.05, 0.95, 1.25][attack_kind]
			match attack_kind:
				0:
					_recorded_positions.clear()
					for candidate in candidates:
						_recorded_positions.append(candidate.global_position)
						_circle(candidate.global_position, 105.0)
				1:
					if _recorded_positions.is_empty():
						_recorded_positions.append(aim)
					# Return to the previous marks: their centers are now safe.
					_rings_with_shared_pockets(_recorded_positions, 112.0, 480.0)
				2:
					if _sequence_step == 0:
						# A wall can remove the outside escape. Keep the band
						# narrow enough to cross inward without spending a Dash.
						_sequence_focus = global_position
						_sequence_forward = forward
						_ring(_sequence_focus, 280.0, 450.0)
						for axis in [forward, forward.orthogonal()]:
							_lane(_sequence_focus - axis * 450.0, _sequence_focus + axis * 450.0, 32.0)
					else:
						# Close the four earlier inner quadrants; the boss center,
						# former crossing lanes and outer floor become safe.
						warning_duration = 1.65
						for index in range(4):
							var axis: Vector2 = _sequence_forward.rotated(PI * 0.25 + index * PI * 0.5)
							_circle(_sequence_focus + axis * 170.0, 108.0)
	state_time_left = warning_duration
	_observe_furnace_cue(State.WARNING)
	queue_redraw()

func _clamp_to_arena(point: Vector2, margin: float) -> Vector2:
	var arena_center: Vector2 = (get_parent() as Node2D).global_position if get_parent() is Node2D else Vector2.ZERO
	var half: Vector2 = (arena_size * 0.5 - Vector2.ONE * margin).max(Vector2.ZERO)
	return arena_center + (point - arena_center).clamp(-half, half)

func _arena_ray_end(origin: Vector2, direction: Vector2, distance: float, margin: float) -> Vector2:
	# Clip along the ray rather than clamping axes independently, preserving
	# the four committed directions and keeping the capsule caps on the floor.
	var center: Vector2 = (get_parent() as Node2D).global_position if get_parent() is Node2D else Vector2.ZERO
	var half: Vector2 = (arena_size * 0.5 - Vector2.ONE * margin).max(Vector2.ZERO)
	var offset := origin - center
	var length := distance
	for axis in range(2):
		if absf(direction[axis]) > 0.0001:
			var boundary := half[axis] if direction[axis] > 0.0 else -half[axis]
			length = minf(length, maxf(0.0, (boundary - offset[axis]) / direction[axis]))
	return origin + direction * length

func _offset_safe_point(point: Vector2, direction: Vector2, distance: float) -> Vector2:
	var first: Vector2 = _clamp_to_arena(point + direction * distance, 70.0)
	var second: Vector2 = _clamp_to_arena(point - direction * distance, 70.0)
	return first if first.distance_squared_to(point) >= second.distance_squared_to(point) else second

func _set_slam_nonblocking(enabled: bool) -> void:
	# A bystander outside the landing disk must not be carried into it by the
	# approaching body. Preserve the configured layer, including layer zero.
	if enabled and _slam_collision_layer < 0:
		_slam_collision_layer = collision_layer
		collision_layer = 0
	elif not enabled and _slam_collision_layer >= 0:
		collision_layer = _slam_collision_layer
		_slam_collision_layer = -1

func _circle(center: Vector2, radius: float) -> void:
	_warning_shapes.append({"kind": "circle", "center": center, "radius": radius})

func _ring(center: Vector2, inner_radius: float, radius: float) -> void:
	_warning_shapes.append({"kind": "ring", "center": center, "inner_radius": inner_radius, "radius": radius})

## Nearby co-op rings become one enclosing safe pocket. Otherwise one player's
## promised inner pocket could be entirely covered by three teammates' rings.
## Merge transitively until no two danger bands intersect. Each merge encloses
## both original safe disks, so every marked center remains safe.
func _rings_with_shared_pockets(points: Array[Vector2], inner: float, outer: float) -> void:
	var pockets: Array[Dictionary] = []
	var thickness := outer - inner
	for point in points:
		pockets.append({"center": point, "radius": inner})
	var merged := true
	while merged:
		merged = false
		for i in range(pockets.size()):
			if merged:
				break
			for j in range(i + 1, pockets.size()):
				var first: Vector2 = pockets[i]["center"]
				var second: Vector2 = pockets[j]["center"]
				var a := float(pockets[i]["radius"])
				var b := float(pockets[j]["radius"])
				var distance := first.distance_to(second)
				if distance > a + b + 2.0 * thickness:
					continue
				if distance + b <= a:
					pass
				elif distance + a <= b:
					pockets[i] = pockets[j].duplicate()
				else:
					var radius := (distance + a + b) * 0.5
					pockets[i] = {"center": first + (second - first).normalized() * (radius - a), "radius": radius}
				pockets.remove_at(j)
				merged = true
				break
	for pocket in pockets:
		_ring(pocket["center"], float(pocket["radius"]), float(pocket["radius"]) + thickness)

func _lane(start: Vector2, finish: Vector2, width: float) -> void:
	_warning_shapes.append({"kind": "lane", "start": start, "end": finish, "width": width})

func get_attack_warning_geometry() -> Array[Dictionary]:
	return _warning_shapes.duplicate(true)

static func shape_contains_point(shape: Dictionary, point: Vector2) -> bool:
	if String(shape.get("kind", "")) == "lane":
		var start: Vector2 = shape["start"]
		var finish: Vector2 = shape["end"]
		return point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, finish)) <= float(shape["width"])
	var distance := point.distance_to(Vector2(shape["center"]))
	return distance <= float(shape["radius"]) and distance >= float(shape.get("inner_radius", 0.0))

func _resolve_attack() -> void:
	if not network_simulation_enabled or boss_state != State.WARNING or _get_current_health() <= 0 or is_queued_for_deletion():
		return
	# Change phase before callbacks: intersecting shapes and reentrant damage can
	# never deal a second hit from this cast to the same player.
	boss_state = State.RECOVER
	state_time_left = recover_time
	_pending_attack_kind = -1
	if _sequence_step == 0:
		if boss_id == "kilnheart":
			_pending_attack_kind = attack_kind
		elif boss_id == "glassweaver":
			_pending_attack_kind = 1
		elif boss_id == "null_archivist" and attack_kind == 0:
			_pending_attack_kind = 1
		elif boss_id == "null_archivist" and attack_kind == 2:
			_pending_attack_kind = 2
	if _pending_attack_kind >= 0:
		state_time_left = 0.18 if boss_id == "null_archivist" else 0.22
	if boss_id == "kilnheart" and attack_kind == 0 and _sequence_step == 0:
		global_position = _slam_landing
	_set_slam_nonblocking(false)
	_impact_shapes = _warning_shapes.duplicate(true)
	_warning_shapes.clear()
	_afterglow_left = 0.3
	_observe_furnace_cue(State.RECOVER)
	telegraph_alpha = 0.0
	var generation := _attack_serial
	var amount := maxi(1, int(round(attack_damage * (1.15 if attack_kind == 1 else 1.0))))
	for candidate in _get_damageable_targets():
		for shape in _impact_shapes:
			if not shape_contains_point(shape, candidate.global_position):
				continue
			var accepted := DAMAGEABLE.apply_damage(candidate, amount, {"source": "enemy_ability", "ability": boss_id + "_" + str(attack_kind)})
			if generation != _attack_serial or is_queued_for_deletion() or _get_current_health() <= 0:
				return
			if accepted and is_instance_valid(candidate):
				var feedback: Object = candidate.get("player_feedback") as Object
				if feedback != null:
					feedback.play_impact_heavy(candidate.global_position, 90.0)
			if generation != _attack_serial or is_queued_for_deletion():
				return
			break
	queue_redraw()

func _get_damageable_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for candidate in target_candidates:
		if _is_living_target(candidate) and not result.has(candidate):
			result.append(candidate)
	if result.is_empty() and _is_living_target(target):
		result.append(target)
	return result

func _is_living_target(candidate: Variant) -> bool:
	if not is_instance_valid(candidate) or not (candidate is Node2D) or candidate.is_queued_for_deletion():
		return false
	if candidate.has_method("is_dead"):
		return not bool(candidate.is_dead())
	return candidate.has_method("get_current_health") and int(candidate.get_current_health()) > 0

func _cancel_attack() -> void:
	_set_slam_nonblocking(false)
	_attack_serial += 1
	boss_state = State.IDLE
	state_time_left = 0.0
	cooldown_left = action_cooldown
	telegraph_alpha = 0.0
	_warning_shapes.clear()
	_impact_shapes.clear()
	_recorded_positions.clear()
	_pending_attack_kind = -1
	_sequence_step = 0
	_afterglow_left = 0.0
	velocity = Vector2.ZERO
	if is_instance_valid(_furnace_sound):
		_furnace_sound.stop()
	queue_redraw()

func _on_health_state_died() -> void:
	_cancel_attack()
	super._on_health_state_died()

func set_network_simulation_enabled(enabled: bool) -> void:
	if enabled != network_simulation_enabled:
		_cancel_attack()
		_received_serial = -1
		_received_phase = 0
		_received_snapshot = -1
		_furnace_cue_serial = -1
		_furnace_cue_phase = 0
	super.set_network_simulation_enabled(enabled)

func _is_in_priority_attack_state() -> bool:
	return boss_state == State.WARNING

func get_projectile_network_sync_state() -> Dictionary:
	if not network_simulation_enabled:
		return {}
	_snapshot_serial += 1
	return {
		"boss_id": boss_id, "attack_serial": _attack_serial, "snapshot_serial": _snapshot_serial,
		"boss_state": boss_state, "attack_kind": attack_kind,
		"sequence_step": _sequence_step, "sequence_root": _sequence_root, "move_start": _move_start, "slam_landing": _slam_landing,
		"state_time_left": state_time_left, "warning_duration": warning_duration,
		"warning_shapes": _warning_shapes.duplicate(true), "impact_shapes": _impact_shapes.duplicate(true),
		"afterglow_left": _afterglow_left, "recorded_positions": _recorded_positions.duplicate(),
		"visual_facing_direction": visual_facing_direction,
	}

func apply_projectile_network_sync_state(payload: Dictionary) -> void:
	if network_simulation_enabled or payload.is_empty() or String(payload.get("boss_id", boss_id)) != boss_id:
		return
	var serial := int(payload.get("attack_serial", -1))
	var snapshot := int(payload.get("snapshot_serial", -1))
	var next_state := clampi(int(payload.get("boss_state", State.IDLE)), State.IDLE, State.RECOVER)
	var phase := 3 if next_state == State.IDLE else next_state
	if snapshot <= _received_snapshot or serial < _received_serial or (serial == _received_serial and phase < _received_phase):
		return
	_received_snapshot = snapshot
	_received_serial = serial
	_received_phase = phase
	_attack_serial = serial
	boss_state = next_state
	attack_kind = clampi(int(payload.get("attack_kind", 0)), 0, 2)
	_sequence_step = clampi(int(payload.get("sequence_step", 0)), 0, 1)
	_sequence_root = clampi(int(payload.get("sequence_root", attack_kind)), 0, 2)
	_move_start = payload.get("move_start", global_position) as Vector2
	_slam_landing = payload.get("slam_landing", global_position) as Vector2
	_set_slam_nonblocking(boss_id == "kilnheart" and attack_kind == 0 and _sequence_step == 0 and boss_state == State.WARNING)
	state_time_left = clampf(float(payload.get("state_time_left", 0.0)), 0.0, 3.0)
	warning_duration = clampf(float(payload.get("warning_duration", 1.0)), 0.1, 3.0)
	_warning_shapes.clear()
	_impact_shapes.clear()
	for shape in payload.get("warning_shapes", []):
		if shape is Dictionary and boss_state == State.WARNING:
			_warning_shapes.append(shape.duplicate(true))
	for shape in payload.get("impact_shapes", []):
		if shape is Dictionary:
			_impact_shapes.append(shape.duplicate(true))
	_afterglow_left = clampf(float(payload.get("afterglow_left", 0.0)), 0.0, 0.3)
	_recorded_positions.clear()
	for point in payload.get("recorded_positions", []):
		if point is Vector2:
			_recorded_positions.append(point)
	visual_facing_direction = payload.get("visual_facing_direction", visual_facing_direction)
	telegraph_alpha = 1.0 - state_time_left / warning_duration if boss_state == State.WARNING else 0.0
	if boss_state == State.WARNING or (boss_state == State.RECOVER and _afterglow_left > 0.0):
		_observe_furnace_cue(boss_state)
	elif boss_state == State.IDLE and is_instance_valid(_furnace_sound):
		_furnace_sound.stop()
	queue_redraw()

func _get_custom_network_runtime_state() -> Dictionary:
	# Generic runtime snapshots quantize vectors and floats, and may omit custom
	# data under load. Never let that stream overwrite precise committed geometry.
	return {"attack_active": boss_state != State.IDLE}

func _apply_custom_network_runtime_state(_custom_state: Dictionary) -> void:
	pass

func _process_network_visuals(delta: float) -> void:
	_afterglow_left = maxf(0.0, _afterglow_left - delta)
	state_time_left = maxf(0.0, state_time_left - delta)
	if boss_state == State.WARNING:
		telegraph_alpha = 1.0 - state_time_left / warning_duration
		if state_time_left <= 0.0:
			# A missing resolution packet cannot leave an eternal warning. Only
			# the host's resolution packet may create an impact presentation.
			_warning_shapes.clear()
			boss_state = State.RECOVER
			_set_slam_nonblocking(false)
			_received_phase = 2
	queue_redraw()

func _get_transport_color() -> Color:
	return PROFILES.get(boss_id, PROFILES["kilnheart"])["tint"]

func get_attack_callout() -> String:
	if boss_state != State.WARNING or _warning_shapes.is_empty():
		return ""
	if boss_id == "kilnheart":
		if attack_kind == 0 and _sequence_step > 0:
			return "Crucible Vents"
		if attack_kind == 1:
			return "Furnace Halo / IN" if _sequence_step > 0 else "Furnace Halo / OUT"
		if attack_kind == 2 and _sequence_step > 0:
			return "Cinder Pursuit"
	elif boss_id == "glassweaver" and attack_kind == 1 and _sequence_step > 0 and _sequence_root == 1:
		return "Turning Stitch"
	elif boss_id == "null_archivist" and attack_kind == 2 and _sequence_step > 0:
		return "Closing Margin"
	return String(PROFILES.get(boss_id, PROFILES["kilnheart"])["names"][attack_kind])

func _draw() -> void:
	var profile: Dictionary = PROFILES.get(boss_id, PROFILES["kilnheart"])
	var radius := float(profile["radius"])
	var tint: Color = profile["tint"]
	if is_spawn_transporting():
		_draw_spawn_transport_fx(radius, visual_facing_direction)
		return
	if boss_state == State.WARNING:
		var warning := Color(1.0, 0.47, 0.29)
		for shape in _warning_shapes:
			_draw_warning_shape(shape, warning, 0.12 + telegraph_alpha * 0.12, 2.5)
		if boss_id == "kilnheart" and attack_kind == 0 and _sequence_step == 0:
			draw_dashed_line(to_local(_move_start), to_local(_slam_landing), Color(warning, 0.6), 2.5, 12.0, true)
	if _afterglow_left > 0.0:
		for shape in _impact_shapes:
			_draw_warning_shape(shape, Color(1.0, 0.86, 0.61), _afterglow_left * 0.85, 4.0)
			if boss_id == "kilnheart" and String(shape.kind) == "lane":
				draw_line(to_local(shape.start), to_local(shape.end), Color(1.0, 0.95, 0.8, _afterglow_left / 0.3), 8.0 * _afterglow_left / 0.3, true)
	# Small neutral marks preserve the Archivist's recorded locations between
	# Record and Revision without painting an inactive area as dangerous.
	if boss_id == "null_archivist" and attack_kind == 0 and boss_state != State.WARNING:
		for point in _recorded_positions:
			draw_arc(to_local(point), 15.0, 0.0, TAU, 24, Color(tint, 0.5), 1.5, true)
	var body_color := tint.darkened(0.64)
	if boss_state == State.WARNING:
		body_color = body_color.lerp(tint, telegraph_alpha * 0.4)
	if boss_id == "kilnheart":
		var pose := get_furnace_pose()
		draw_circle(Vector2.ZERO, radius + 8.0, Color(0.02, 0.01, 0.01, 0.42))
		draw_set_transform(Vector2(0.0, -float(pose.lift)), 0.0, pose.scale)
	_draw_common_body(radius, body_color, tint, visual_facing_direction)
	match boss_id:
		"kilnheart":
			# Plates open as pressure builds, then recoil around a white-hot core.
			var heat := telegraph_alpha if boss_state == State.WARNING else _afterglow_left / 0.3
			draw_circle(Vector2.ZERO, 12.0 + heat * 6.0, tint.lerp(Color(1.0, 0.96, 0.74), heat))
			for i in range(6):
				var angle := TAU * i / 6.0
				var plate_offset := Vector2.RIGHT.rotated(angle + 0.45) * heat * 8.0
				draw_arc(plate_offset, radius + 7.0, angle + 0.1, angle + 0.8, 8, tint, 7.0, true)
				if heat > 0.0:
					var axis := Vector2.RIGHT.rotated(angle + 0.95)
					draw_line(axis * (radius + 3.0), axis * (radius + 10.0 + heat * 19.0), Color(1.0, 0.8, 0.46, heat), 3.0, true)
			draw_rect(Rect2(-15.0, -9.0, 30.0, 18.0), tint.darkened(0.3), false, 3.0)
			for x in [-8.0, 0.0, 8.0]:
				draw_line(Vector2(x, -7.0), Vector2(x, 7.0), tint, 2.0, true)
		"glassweaver":
			# Four glass needles, visibly different from Sovereign's orbitals.
			for i in range(4):
				var axis := Vector2.RIGHT.rotated(PI * 0.25 + TAU * i / 4.0)
				var side := axis.orthogonal()
				var points := PackedVector2Array([axis * 29.0, axis * 51.0 + side * 7.0, axis * 67.0, axis * 51.0 - side * 7.0, axis * 29.0])
				draw_colored_polygon(points, Color(tint, 0.22))
				draw_polyline(points, tint, 2.0, true)
		"null_archivist":
			# An open, angular book silhouette and three floating page marks.
			for side in [-1.0, 1.0]:
				var points := PackedVector2Array([Vector2(0, -28), Vector2(side * 45, -40), Vector2(side * 49, 28), Vector2(0, 38)])
				draw_colored_polygon(points, tint.darkened(0.6))
				draw_polyline(points, tint, 2.5, true)
				draw_line(Vector2(side * 14, -16), Vector2(side * 34, -21), tint, 2.0, true)
				draw_line(Vector2(side * 14, -3), Vector2(side * 35, -8), tint, 2.0, true)
			draw_line(Vector2(0, -28), Vector2(0, 38), tint, 3.0, true)
	if boss_state == State.WARNING:
		draw_arc(Vector2.ZERO, radius + 15.0, -PI * 0.5, -PI * 0.5 + TAU * telegraph_alpha, 48, Color(1.0, 0.88, 0.62), 3.0, true)
	draw_set_transform(Vector2.ZERO)
	ATTACK_CALLOUT.draw_callout(self, get_attack_callout(), -100.0)

func _draw_warning_shape(shape: Dictionary, tint: Color, fill_alpha: float, line_width: float) -> void:
	var fill := Color(tint, fill_alpha)
	var edge := Color(tint, minf(1.0, 0.65 + fill_alpha))
	if String(shape["kind"]) == "lane":
		var start := to_local(Vector2(shape["start"]))
		var finish := to_local(Vector2(shape["end"]))
		var width := float(shape["width"])
		var direction := (finish - start).normalized()
		var angle := direction.angle()
		var polygon := PackedVector2Array()
		for i in range(25):
			polygon.append(finish + Vector2.RIGHT.rotated(angle - PI * 0.5 + PI * i / 24.0) * width)
		for i in range(25):
			polygon.append(start + Vector2.RIGHT.rotated(angle + PI * 0.5 + PI * i / 24.0) * width)
		draw_colored_polygon(polygon, fill)
		polygon.append(polygon[0])
		draw_polyline(polygon, edge, line_width, true)
		return
	var center := to_local(Vector2(shape["center"]))
	var radius := float(shape["radius"])
	var inner := float(shape.get("inner_radius", 0.0))
	if inner > 0.0:
		# Tessellated annulus leaves the safe pocket genuinely unpainted.
		for i in range(80):
			var a := Vector2.RIGHT.rotated(TAU * i / 80.0)
			var b := Vector2.RIGHT.rotated(TAU * (i + 1) / 80.0)
			draw_colored_polygon(PackedVector2Array([center + a * inner, center + a * radius, center + b * radius, center + b * inner]), fill)
		draw_arc(center, inner, 0.0, TAU, 96, edge, line_width, true)
	else:
		draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 96, edge, line_width, true)

## Pressure first, then a fast committed plunge. Collision remains nonblocking
## throughout; this animation never changes the painted landing or damage time.
static func _slam_travel_progress(progress: float) -> float:
	var travel := clampf((progress - 0.38) / 0.62, 0.0, 1.0)
	return travel * travel

func get_furnace_pose() -> Dictionary:
	var lift := 0.0
	var scale := Vector2.ONE
	if boss_state == State.WARNING and attack_kind == 0 and _sequence_step == 0:
		var travel := clampf((telegraph_alpha - 0.38) / 0.62, 0.0, 1.0)
		lift = sin(travel * PI) * 54.0
		var wind := sin(minf(telegraph_alpha / 0.38, 1.0) * PI)
		scale = Vector2(1.0 + wind * 0.14, 1.0 - wind * 0.18)
	elif _afterglow_left > 0.0:
		var recoil := _afterglow_left / 0.3
		scale = Vector2(1.0 + recoil * 0.22, 1.0 - recoil * 0.18)
	return {"lift": lift, "scale": scale}

func _observe_furnace_cue(phase: int) -> void:
	if boss_id != "kilnheart" or _attack_serial < _furnace_cue_serial:
		return
	if _attack_serial == _furnace_cue_serial and phase <= _furnace_cue_phase:
		return
	_furnace_cue_serial = _attack_serial
	_furnace_cue_phase = phase
	_furnace_cue_count += 1
	if not is_instance_valid(_furnace_sound):
		return
	if _furnace_charge_audio == null:
		_furnace_charge_audio = _make_furnace_audio(false)
		_furnace_impact_audio = _make_furnace_audio(true)
	_furnace_sound.stream = _furnace_impact_audio if phase == State.RECOVER else _furnace_charge_audio
	_furnace_sound.volume_db = AUDIO_LEVELS.clamp_db(RunContext.sfx_volume_db - (12.0 if phase == State.RECOVER else 19.0))
	_furnace_sound.pitch_scale = 0.86 if attack_kind == 0 and _sequence_step == 0 else (1.08 if attack_kind == 2 else 1.0)
	_furnace_sound.play()

static func _make_furnace_audio(impact: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var duration := 0.42 if impact else 0.65
	var samples := int(duration * stream.mix_rate)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var phase := 0.0
	var noise := RandomNumberGenerator.new()
	noise.seed = 73921
	var air := 0.0
	for index in range(samples):
		var seconds := float(index) / stream.mix_rate
		var progress := seconds / duration
		var frequency := lerpf(138.0, 43.0, minf(progress * 3.0, 1.0)) if impact else lerpf(62.0, 184.0, progress)
		phase += TAU * frequency / stream.mix_rate
		air = lerpf(air, noise.randf_range(-1.0, 1.0), 0.35)
		var envelope := minf(seconds / 0.006, 1.0) * pow(1.0 - progress, 2.5 if impact else 0.6)
		var metal := sin(phase * 2.73) * (exp(-seconds * 30.0) if impact else 0.12)
		var value := (sin(phase) * 0.44 + metal * 0.28 + air * (0.38 if impact else 0.22)) * envelope
		data.encode_s16(index * 2, int(clampf(value, -0.95, 0.95) * 32767.0))
	stream.data = data
	return stream
