extends "res://scripts/enemy_base.gd"
## Three encounter identities share only the committed-warning lifecycle. Shapes
## are captured in world space once, and used by both damage and presentation.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
enum State { IDLE, WARNING, RECOVER }

const PROFILES := {
	"kilnheart": {"health": 1100, "radius": 34.0, "speed": 122.0, "distance": 175.0, "damage": 38, "cooldown": 0.68, "recover": 0.72, "tint": Color(1.0, 0.48, 0.19), "names": ["Crucible Slam", "Furnace Halo", "Cinderfall"]},
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
var _attack_serial: int = 0
var _snapshot_serial: int = 0
var _received_serial: int = -1
var _received_phase: int = 0
var _received_snapshot: int = -1

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
				begin_attack(_cycle_step % 3)
				_cycle_step += 1
		State.WARNING:
			# Neither crowd separation nor player movement may drag the attack.
			velocity = Vector2.ZERO
			state_time_left = maxf(0.0, state_time_left - delta)
			telegraph_alpha = 1.0 - state_time_left / warning_duration
			if state_time_left <= 0.0:
				_resolve_attack()
		State.RECOVER:
			velocity = Vector2.ZERO
			state_time_left = maxf(0.0, state_time_left - delta)
			if state_time_left <= 0.0:
				boss_state = State.IDLE
				# Enrage changes the interval, preserving the full dodge warning.
				cooldown_left = action_cooldown * (0.72 if _get_current_health() < max_health / 2 else 1.0)
	queue_redraw()

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

func begin_attack(kind: int) -> void:
	if not network_simulation_enabled or _get_current_health() <= 0 or is_queued_for_deletion():
		return
	var candidates := _get_damageable_targets()
	if candidates.is_empty():
		return
	attack_kind = clampi(kind, 0, 2)
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
			warning_duration = [0.95, 1.1, 1.05][attack_kind]
			match attack_kind:
				0: _circle(global_position, 185.0)
				1: _ring(global_position, 135.0, 365.0)
				2:
					for candidate in candidates:
						_circle(candidate.global_position, 108.0)
		"glassweaver":
			warning_duration = [1.1, 0.95, 1.15][attack_kind]
			match attack_kind:
				0:
					# The unpainted corridor between the threads stays safe.
					for side in [-1.0, 1.0]:
						var center: Vector2 = aim + forward.orthogonal() * side * 150.0
						_lane(center - forward * 470.0, center + forward * 470.0, 55.0)
				1:
					for axis in [forward, forward.orthogonal()]:
						_lane(aim - axis * 330.0, aim + axis * 330.0, 38.0)
				2:
					var cage_positions: Array[Vector2] = []
					for candidate in candidates:
						cage_positions.append(candidate.global_position)
					_rings_with_shared_pockets(cage_positions, 100.0, 225.0)
		"null_archivist":
			warning_duration = [1.05, 1.25, 1.1][attack_kind]
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
					_rings_with_shared_pockets(_recorded_positions, 112.0, 260.0)
				2:
					_ring(global_position, 235.0, 450.0)
					for axis in [forward, forward.orthogonal()]:
						_lane(global_position - axis * 450.0, global_position + axis * 450.0, 32.0)
	state_time_left = warning_duration
	queue_redraw()

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
	_impact_shapes = _warning_shapes.duplicate(true)
	_warning_shapes.clear()
	_afterglow_left = 0.3
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
	_attack_serial += 1
	boss_state = State.IDLE
	state_time_left = 0.0
	cooldown_left = action_cooldown
	telegraph_alpha = 0.0
	_warning_shapes.clear()
	_impact_shapes.clear()
	_recorded_positions.clear()
	_afterglow_left = 0.0
	velocity = Vector2.ZERO
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
			_received_phase = 2
	queue_redraw()

func _get_transport_color() -> Color:
	return PROFILES.get(boss_id, PROFILES["kilnheart"])["tint"]

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
	if _afterglow_left > 0.0:
		for shape in _impact_shapes:
			_draw_warning_shape(shape, Color(1.0, 0.86, 0.61), _afterglow_left * 0.85, 4.0)
	# Small neutral marks preserve the Archivist's recorded locations between
	# Record and Revision without painting an inactive area as dangerous.
	if boss_id == "null_archivist" and attack_kind == 0 and boss_state != State.WARNING:
		for point in _recorded_positions:
			draw_arc(to_local(point), 15.0, 0.0, TAU, 24, Color(tint, 0.5), 1.5, true)
	var body_color := tint.darkened(0.64)
	if boss_state == State.WARNING:
		body_color = body_color.lerp(tint, telegraph_alpha * 0.4)
	_draw_common_body(radius, body_color, tint, visual_facing_direction)
	match boss_id:
		"kilnheart":
			# Heavy segmented furnace shell.
			for i in range(6):
				var angle := TAU * i / 6.0
				draw_arc(Vector2.ZERO, radius + 7.0, angle + 0.1, angle + 0.8, 8, tint, 6.0, true)
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
		var attack_name: String = profile["names"][attack_kind]
		var font := ThemeDB.fallback_font
		var label_size := font.get_string_size(attack_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		draw_string(font, Vector2(-label_size.x * 0.5, -100.0), attack_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.89, 0.74))

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
