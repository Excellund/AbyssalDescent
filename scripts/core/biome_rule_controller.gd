extends Node2D
## One room-owned, committed environmental event. The world supplies lifecycle,
## authority and actors; this node never starts timers or RPCs on its own.

signal state_changed(state: Dictionary)

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const POLARITY_CONTOUR := preload("res://scripts/shared/biome_polarity_marker.gd")
const SHARD_DAMAGE := 60
const SHARD_RADIUS := 160.0
const SHARD_VISUAL_TIME := 0.48
const IDS := ["crumble", "haunt", "shatterfield", "grinding_vault", "storm_reach", "hollow", "void_breach", "the_maelstrom", "convergence_end"]
const PHASES := ["idle", "recovery", "warning", "active"]
const MODES := ["ordinary", "compact", "assistance"]
const MAX_STATE_TIME := 12.0
const MIN_EFFECTIVE_BOUNDS := Vector2(320.0, 240.0)
const PLAYER_PLANNING_RADIUS := 22.627417
const WALKING_MARGIN := 12.0
const MAX_EXCLUSIONS := 32

var environment_damage_active: bool = false
var shard_bursts: Array[Dictionary] = []
var rule_id: String = ""
var mode: String = "ordinary"
var fragments: bool = false
var phase: String = "idle"
var phase_left: float = 0.0
var phase_duration: float = 0.0
var event_index: int = 0
var revision: int = 0
var shape: Dictionary = {}
var room_size := Vector2.ZERO
var _initial_room_size := Vector2.ZERO
var _entry_mode: String = "ordinary"
var _exclusions: Array[Dictionary] = []
var _exclusions_valid: bool = true
var _world: Node
var _run: String = ""
var _room: int = 0
var _seed: int = 0
var _generation: int = 0
var _last_remote_revision: int = -1
var _obstacles: Array[Dictionary] = []
var _hit_ids: Dictionary = {}
var _warning_time: float = 1.4
var _active_time: float = 0.85
var _recovery_time: float = 2.5
var _player_damage: int = 8
var _enemy_damage: int = 35
var _slow_mult: float = 0.6
var _combat_visible: bool = false
var _contour_cache_key := 0
var _contour_cache: Array[Dictionary] = []

func initialize(world: Node) -> void:
	_world = world
	position = Vector2.ZERO
	z_index = -2
	set_process(false)
	set_physics_process(false)

func configure(rule: Dictionary, bounds_size: Vector2, run_token: String, room_id: int, seed: int = 0) -> void:
	reset()
	var requested_id := String(rule.get("id", ""))
	var requested_mode := String(rule.get("mode", "ordinary"))
	if not IDS.has(requested_id) or not MODES.has(requested_mode) or not bounds_size.is_finite() or bounds_size.x < 300.0 or bounds_size.y < 300.0 or run_token.is_empty() or room_id < 0:
		return
	rule_id = requested_id
	fragments = rule_id == "shatterfield" and rule.get("shatter_fragments", false) == true
	mode = "compact" if fragments and requested_mode == "ordinary" else requested_mode
	_entry_mode = mode
	room_size = bounds_size
	_initial_room_size = bounds_size
	_run = run_token
	_room = room_id
	_seed = seed
	var compact := mode != "ordinary"
	var default_warning := 1.8 if compact else 1.4
	var default_active := (2.0 if compact else 3.0) if rule_id == "haunt" else (0.5 if compact else 0.85)
	var default_recovery := 6.0 if mode == "assistance" else (5.0 if compact else 2.5)
	_warning_time = _bounded_number(rule.get("warning_time", default_warning), default_warning, 1.8 if compact else 0.8, 4.0)
	_active_time = _bounded_number(rule.get("active_time", default_active), default_active, 0.25, 5.0)
	_recovery_time = _bounded_number(rule.get("recovery_time", default_recovery), default_recovery, default_recovery if compact else 1.0, 8.0)
	_player_damage = int(_bounded_number(rule.get("player_damage", 10 if rule_id == "storm_reach" else 8), 8.0, 1.0, 30.0))
	_enemy_damage = int(_bounded_number(rule.get("enemy_damage", 50 if rule_id == "storm_reach" else 35), 35.0, 1.0, 200.0))
	_slow_mult = _bounded_number(rule.get("slow_mult", 0.75 if compact else 0.6), 0.75 if compact else 0.6, 0.45, 0.85)
	var entries: Variant = rule.get("obstacles", [])
	if entries is Array:
		for entry: Variant in entries:
			if entry is Dictionary and entry.get("pos") is Vector2 and (entry.pos as Vector2).is_finite():
				_obstacles.append(entry.duplicate(true))
	if rule_id != "shatterfield" or fragments:
		_set_phase("recovery", _recovery_time)
	_publish()

func reset() -> void:
	_generation += 1
	# A synchronous enemy death may reset the room before its other callbacks
	# run. Preserve the damage-origin guard until take_damage returns.
	rule_id = ""
	mode = "ordinary"
	_entry_mode = "ordinary"
	fragments = false
	phase = "idle"
	phase_left = 0.0
	phase_duration = 0.0
	event_index = 0
	revision = 0
	_last_remote_revision = -1
	_run = ""
	_room = 0
	room_size = Vector2.ZERO
	_initial_room_size = Vector2.ZERO
	_exclusions.clear()
	_exclusions_valid = true
	shape.clear()
	shard_bursts.clear()
	_hit_ids.clear()
	_obstacles.clear()
	_combat_visible = false
	queue_redraw()

func set_room_context(effective_bounds: Vector2, exclusions: Array[Dictionary], authoritative: bool) -> void:
	# Replicas take bounds and allegiance from the ordered host snapshot. A local
	# objective or Seamlock update must not rewrite a committed remote warning.
	if not authoritative or rule_id.is_empty() or not _valid_bounds_size(effective_bounds, _initial_room_size):
		return
	var normalized: Array[Dictionary] = []
	var valid := exclusions.size() <= MAX_EXCLUSIONS
	if valid:
		for exclusion: Dictionary in exclusions:
			if not _valid_exclusion(exclusion):
				valid = false
				break
			normalized.append(exclusion.duplicate(true))
	var bounds_changed := not room_size.is_equal_approx(effective_bounds)
	var required_space_changed := valid != _exclusions_valid or normalized != _exclusions
	if not bounds_changed and not required_space_changed:
		return
	room_size = effective_bounds
	_exclusions = normalized
	_exclusions_valid = valid
	var committed := phase in ["warning", "active"]
	var invalidated := bounds_changed or (mode == "compact" and not _avoids_required_space(shape))
	if committed and invalidated:
		_generation += 1
		shape.clear()
		_hit_ids.clear()
		_set_phase("recovery", _recovery_time)
	# Recovery has no geometry to move. Its next warning uses the current bounds
	# and all reserved objective space, including future route segments.
	_publish()

func tick(delta: float, combat_active: bool, players: Array, enemies: Array, authoritative: bool) -> void:
	if _combat_visible != combat_active:
		_combat_visible = combat_active
		queue_redraw()
	if combat_active and is_finite(delta) and delta > 0.0 and not shard_bursts.is_empty():
		for index in range(shard_bursts.size() - 1, -1, -1):
			shard_bursts[index].left = maxf(0.0, float(shard_bursts[index].left) - delta)
			if float(shard_bursts[index].left) <= 0.0:
				shard_bursts.remove_at(index)
		queue_redraw()
	if not combat_active or rule_id.is_empty() or phase == "idle" or not is_finite(delta) or delta <= 0.0:
		return
	if not authoritative:
		# Replicas cannot invent the next event or keep a slow patch alive while
		# awaiting another authoritative state. Only owned movement needs Slow.
		if phase == "active" and phase_left > 0.0 and rule_id == "haunt" and mode != "assistance":
			_apply_slow(players, [], false)
		phase_left = maxf(0.0, phase_left - delta)
		queue_redraw()
		return
	var generation := _generation
	if phase == "active" and phase_left > 0.0:
		_apply_active_effect(players, enemies, false)
		if generation != _generation:
			return
	phase_left = maxf(0.0, phase_left - delta)
	if phase_left > 0.0:
		queue_redraw()
		return
	# Advance at most one phase per frame. Even a long frame must publish and
	# display the warning before a future tick is allowed to resolve its impact.
	match phase:
		"recovery":
			event_index += 1
			shape = _build_shape(enemies if mode == "assistance" else players)
			if shape.is_empty() and mode == "compact":
				mode = "assistance"
				_recovery_time = maxf(_recovery_time, 6.0)
				shape = _build_shape(enemies)
			_hit_ids.clear()
			_set_phase("warning", _warning_time)
		"warning":
			_set_phase("active", _active_time)
			_apply_active_effect(players, enemies, true)
			if generation != _generation:
				return
		"active":
			shape.clear()
			_hit_ids.clear()
			_set_phase("recovery", _recovery_time)
	_publish()

func snapshot() -> Dictionary:
	return {"run": _run, "room": _room, "revision": revision, "id": rule_id,
		"phase": phase, "left": phase_left, "duration": phase_duration,
		"event": event_index, "shape": shape.duplicate(true), "slow": _slow_mult,
		"mode": mode, "fragments": fragments, "bounds_size": room_size}

func apply_snapshot(state: Dictionary) -> bool:
	if not valid_snapshot_envelope(state):
		return false
	if rule_id.is_empty() or state.get("run") != _run or state.get("room") != _room or state.get("id") != rule_id:
		return false
	if not (state.get("revision") is int) or not (state.get("event") is int):
		return false
	var incoming_revision: int = state.revision
	var incoming_event: int = state.event
	var incoming_phase := String(state.get("phase", ""))
	if incoming_revision <= _last_remote_revision or incoming_revision < 1 or incoming_event < event_index or incoming_event < 0 or not PHASES.has(incoming_phase):
		return false
	var incoming_mode: String = "ordinary"
	var incoming_bounds: Vector2 = _initial_room_size
	var has_context := state.has("mode") or state.has("fragments") or state.has("bounds_size")
	if has_context:
		if not (state.get("mode") is String) or not (state.get("fragments") is bool) or not (state.get("bounds_size") is Vector2):
			return false
		incoming_mode = state.mode
		incoming_bounds = state.bounds_size
		if bool(state.fragments) != fragments or not _valid_bounds_size(incoming_bounds, _initial_room_size):
			return false
	elif fragments or _entry_mode != "ordinary":
		return false
	if not MODES.has(incoming_mode) or (incoming_mode != mode and not (mode == "compact" and incoming_mode == "assistance")):
		return false
	var left: Variant = state.get("left")
	var duration: Variant = state.get("duration")
	var slow: Variant = state.get("slow", 0.6)
	if not _finite_number(left) or not _finite_number(duration) or not _finite_number(slow):
		return false
	if float(left) < 0.0 or float(duration) < 0.0 or float(left) > float(duration) or float(duration) > MAX_STATE_TIME or float(slow) < 0.45 or float(slow) > 0.85:
		return false
	var incoming_shape: Variant = state.get("shape")
	if not (incoming_shape is Dictionary):
		return false
	var has_geometry := incoming_phase in ["warning", "active"]
	if has_geometry and (incoming_event == 0 or not _valid_shape(incoming_shape, incoming_bounds)):
		return false
	if has_geometry and incoming_mode != "ordinary" and not _valid_compact_shape(rule_id, incoming_shape, incoming_bounds):
		return false
	if not has_geometry and not incoming_shape.is_empty():
		return false
	if rule_id == "shatterfield" and not fragments and incoming_phase != "idle":
		return false
	_last_remote_revision = incoming_revision
	revision = incoming_revision
	event_index = incoming_event
	phase = incoming_phase
	phase_left = float(left)
	phase_duration = float(duration)
	mode = incoming_mode
	room_size = incoming_bounds
	_slow_mult = float(slow)
	shape = incoming_shape.duplicate(true)
	queue_redraw()
	return true

static func valid_snapshot_envelope(state: Dictionary) -> bool:
	# Safe before a future room is configured. Configuration-specific bounds,
	# entry mode and revision checks still belong to apply_snapshot.
	if not (state.get("run") is String) or String(state.run).is_empty() or not (state.get("room") is int) or int(state.room) < 0:
		return false
	if not (state.get("id") is String) or not IDS.has(state.id) or not (state.get("revision") is int) or int(state.revision) < 1 or not (state.get("event") is int) or int(state.event) < 0:
		return false
	if not (state.get("phase") is String) or not PHASES.has(state.phase) or not _finite_number(state.get("left")) or not _finite_number(state.get("duration")) or not _finite_number(state.get("slow", 0.6)):
		return false
	var left := float(state.left)
	var duration := float(state.duration)
	var slow := float(state.get("slow", 0.6))
	if left < 0.0 or duration < 0.0 or left > duration or duration > MAX_STATE_TIME or slow < 0.45 or slow > 0.85 or not (state.get("shape") is Dictionary):
		return false
	var incoming_mode: String = "ordinary"
	var incoming_fragments := false
	var incoming_bounds := Vector2.ZERO
	var has_context := state.has("mode") or state.has("fragments") or state.has("bounds_size")
	if has_context:
		if not (state.get("mode") is String) or not MODES.has(state.mode) or not (state.get("fragments") is bool) or not (state.get("bounds_size") is Vector2):
			return false
		incoming_mode = state.mode
		incoming_fragments = state.fragments
		incoming_bounds = state.bounds_size
		if not incoming_bounds.is_finite() or incoming_bounds.x < 300.0 or incoming_bounds.y < 240.0 or incoming_bounds.x > 10000.0 or incoming_bounds.y > 10000.0:
			return false
		if incoming_fragments and (String(state.id) != "shatterfield" or incoming_mode == "ordinary"):
			return false
	var geometry: Dictionary = state.shape
	var has_geometry := String(state.phase) in ["warning", "active"]
	if String(state.id) == "shatterfield" and not incoming_fragments and String(state.phase) != "idle":
		return false
	if not has_geometry:
		return geometry.is_empty() and (String(state.phase) != "idle" or (left == 0.0 and duration == 0.0))
	if int(state.event) <= 0 or duration <= 0.0 or not (geometry.get("bounds") is Rect2):
		return false
	if not has_context:
		incoming_bounds = (geometry.bounds as Rect2).size
		if not incoming_bounds.is_finite() or incoming_bounds.x < 300.0 or incoming_bounds.y < 240.0 or incoming_bounds.x > 10000.0 or incoming_bounds.y > 10000.0:
			return false
	return _valid_shape(geometry, incoming_bounds) and (incoming_mode == "ordinary" or _valid_compact_shape(String(state.id), geometry, incoming_bounds))

func _set_phase(next_phase: String, duration: float) -> void:
	phase = next_phase
	phase_duration = duration
	phase_left = duration
	queue_redraw()

func _publish() -> void:
	revision += 1
	queue_redraw()
	state_changed.emit(snapshot())

func _build_shape(players: Array) -> Dictionary:
	if mode != "ordinary":
		return _build_compact_shape(players)
	var half := room_size * 0.5
	var bounds := Rect2(-half, room_size)
	var step := event_index - 1 + posmod(_seed, 8)
	var result: Dictionary
	match rule_id:
		"crumble":
			var centers: Array[Vector2] = [Vector2(-220, -57), Vector2(220, 57)]
			if _obstacles.size() >= 4:
				centers = [(_obstacles[0].pos + _obstacles[1].pos) * 0.5, (_obstacles[2].pos + _obstacles[3].pos) * 0.5]
			result = {"kind": "circle", "center": _clamp_center(centers[step % 2], 76.0), "radius": 76.0}
		"haunt":
			var center := Vector2(-half.x * 0.5 if step % 2 == 0 else half.x * 0.5, 0.0)
			if not _obstacles.is_empty():
				center = _obstacles[step % _obstacles.size()].pos
				center += center.direction_to(Vector2.ZERO) * 70.0
			result = {"kind": "circle", "center": _clamp_center(center, 100.0), "radius": 100.0}
		"grinding_vault":
			var inner_radius := minf(165.0, minf(half.x, half.y) * 0.42)
			result = {"kind": "circle", "center": Vector2.ZERO, "radius": inner_radius} if step % 2 == 0 else {"kind": "annulus", "center": Vector2.ZERO, "inner": inner_radius + 100.0, "outer": inner_radius + 250.0}
		"storm_reach":
			var candidates: Array[Node2D] = []
			for actor: Variant in players:
				if _actor_alive(actor) and not candidates.has(actor):
					candidates.append(actor)
			candidates.sort_custom(func(a: Node2D, b: Node2D): return _actor_order(a) < _actor_order(b))
			var center := Vector2.ZERO if candidates.is_empty() else to_local(candidates[(event_index - 1) % candidates.size()].global_position)
			result = {"kind": "circle", "center": _clamp_center(center, 82.0), "radius": 82.0}
		"hollow":
			# Each fighting lane has a narrow danger strip, with safe space on
			# both sides. A warning never demands a half-room crossing.
			var width := minf(160.0, half.x * 0.38)
			var center_x := (-0.5 if step % 2 == 0 else 0.5) * half.x
			var rect := Rect2(Vector2(center_x - width * 0.5, -half.y), Vector2(width, room_size.y))
			result = {"kind": "rects", "rects": [rect]}
		"void_breach":
			var lane_y: float = float([-0.45, 0.0, 0.45][step % 3]) * half.y
			var gap_x := (-0.35 if step % 2 == 0 else 0.35) * half.x
			var gap_half := minf(105.0, half.x * 0.30)
			var thickness := minf(90.0, half.y * 0.28)
			result = {"kind": "rects", "rects": [Rect2(Vector2(-half.x, lane_y - thickness * 0.5), Vector2(gap_x - gap_half + half.x, thickness)), Rect2(Vector2(gap_x + gap_half, lane_y - thickness * 0.5), Vector2(half.x - gap_x - gap_half, thickness))]}
		"the_maelstrom":
			result = {"kind": "sector", "center": Vector2.ZERO, "inner": 55.0, "outer": minf(340.0, minf(half.x, half.y) - 25.0), "angle": float(step % 8) * PI * 0.25, "half_angle": PI * 0.25}
		"convergence_end":
			# Pair averages follow the exact serialized post layout, including
			# the diagonal variant. Pulse openings rather than unrelated axes.
			var gates: Array[Vector2] = [Vector2(-245, 0), Vector2(245, 0), Vector2(0, -240), Vector2(0, 240)]
			if _obstacles.size() >= 8:
				for index in 4:
					gates[index] = (_obstacles[index * 2].pos + _obstacles[index * 2 + 1].pos) * 0.5
			var width := minf(140.0, minf(half.x, half.y) * 0.38)
			var patches: Array[Rect2] = []
			for index in 2:
				var center := _clamp_center(gates[(step % 2) * 2 + index], width * 0.5)
				patches.append(Rect2(center - Vector2.ONE * width * 0.5, Vector2.ONE * width))
			result = {"kind": "rects", "rects": patches}
	result["bounds"] = bounds
	return result

func _build_compact_shape(actors: Array) -> Dictionary:
	var step := event_index - 1 + posmod(_seed, 8)
	var half := room_size * 0.5
	var anchors: Array[Vector2] = [Vector2(-0.55, -0.55), Vector2(0.55, 0.55), Vector2(0.55, -0.55), Vector2(-0.55, 0.55), Vector2(-0.65, 0), Vector2(0.65, 0), Vector2(0, -0.65), Vector2(0, 0.65), Vector2.ZERO]
	var candidates: Array[Vector2] = []
	if mode == "assistance" or rule_id == "storm_reach":
		var living: Array[Node2D] = []
		for actor: Variant in actors:
			if _actor_alive(actor) and not living.has(actor):
				living.append(actor)
		living.sort_custom(func(a: Node2D, b: Node2D): return _actor_order(a) < _actor_order(b))
		if not living.is_empty():
			var target := to_local(living[posmod(event_index - 1, living.size())].global_position)
			if mode == "assistance":
				for orientation in 8:
					var directed_step := step + orientation
					var aimed_shape := _compact_shape_at(_assistance_anchor(target, directed_step), directed_step)
					if geometry_contains(aimed_shape, target):
						return aimed_shape
			candidates.append(target)
	for index in anchors.size():
		candidates.append(anchors[posmod(step + index, anchors.size())] * half)
	for center: Vector2 in candidates:
		var candidate := _compact_shape_at(center, step)
		if mode == "assistance" or (_avoids_required_space(candidate) and _avoids_solid_cover(candidate)):
			return candidate
	# A crowded objective never removes the biome from the room. The caller
	# commits a friendly warning instead, and keeps that allegiance thereafter.
	return {}

func _assistance_anchor(target: Vector2, step: int) -> Vector2:
	# Put a damage-bearing part of the pattern at the committed foe position.
	# The centre of a ring, paired patches or a split lane is deliberately safe.
	var half := room_size * 0.5
	match rule_id:
		"grinding_vault":
			if step % 2 != 0:
				var outer := minf(120.0, minf(half.x, half.y) - 18.0)
				return target - Vector2.from_angle(float(step % 8) * PI * 0.25) * (outer - 25.0)
		"void_breach":
			var length := minf(400.0, room_size.x - 36.0)
			var gap := minf(150.0, length * 0.45)
			return target + Vector2((length + gap) * (0.25 if step % 2 == 0 else -0.25), 0)
		"the_maelstrom":
			var outer := minf(180.0, minf(half.x, half.y) - 18.0)
			return target - Vector2.from_angle(float(step % 8) * PI * 0.25) * ((40.0 + outer) * 0.5)
		"convergence_end":
			var vertical := step % 2 != 0
			var separation := minf(110.0, (half.y if vertical else half.x) - 58.0)
			var offset := Vector2(0, separation) if vertical else Vector2(separation, 0)
			return target - offset * (1.0 if step % 4 < 2 else -1.0)
	return target

func _compact_shape_at(center: Vector2, step: int) -> Dictionary:
	var half := room_size * 0.5
	var result: Dictionary = {}
	match rule_id:
		"crumble", "storm_reach", "shatterfield", "haunt":
			var radius := 80.0 if rule_id == "haunt" else 60.0
			result = {"kind": "circle", "center": _clamp_center(center, radius), "radius": radius}
		"grinding_vault":
			if step % 2 == 0:
				result = {"kind": "circle", "center": _clamp_center(center, 65.0), "radius": 65.0}
			else:
				var outer := minf(120.0, minf(half.x, half.y) - 18.0)
				result = {"kind": "annulus", "center": _clamp_center(center, outer), "inner": outer - 50.0, "outer": outer}
		"hollow":
			var size := Vector2(70.0, minf(240.0, room_size.y - 36.0))
			var focus := _clamp_center_extents(center, size * 0.5)
			result = {"kind": "rects", "rects": [Rect2(focus - size * 0.5, size)]}
		"void_breach":
			var length := minf(400.0, room_size.x - 36.0)
			var gap := minf(150.0, length * 0.45)
			var focus := _clamp_center_extents(center, Vector2(length * 0.5, 30.0))
			var width := (length - gap) * 0.5
			result = {"kind": "rects", "rects": [Rect2(focus + Vector2(-length * 0.5, -30.0), Vector2(width, 60.0)), Rect2(focus + Vector2(gap * 0.5, -30.0), Vector2(width, 60.0))]}
		"the_maelstrom":
			var outer := minf(180.0, minf(half.x, half.y) - 18.0)
			result = {"kind": "sector", "center": _clamp_center(center, outer), "inner": 40.0, "outer": outer, "angle": float(step % 8) * PI * 0.25, "half_angle": PI / 6.0}
		"convergence_end":
			var vertical := step % 2 != 0
			var separation := minf(110.0, (half.y if vertical else half.x) - 58.0)
			var offset := Vector2(0, separation) if vertical else Vector2(separation, 0)
			var focus := _clamp_center_extents(center, offset.abs() + Vector2(40, 40))
			result = {"kind": "rects", "rects": [Rect2(focus - offset - Vector2(40, 40), Vector2(80, 80)), Rect2(focus + offset - Vector2(40, 40), Vector2(80, 80))]}
	result["bounds"] = Rect2(-half, room_size)
	return result

func _clamp_center_extents(center: Vector2, extents: Vector2) -> Vector2:
	var limit := (room_size * 0.5 - extents - Vector2(18, 18)).max(Vector2.ZERO)
	return center.clamp(-limit, limit).snapped(Vector2(0.5, 0.5))

func _avoids_required_space(geometry: Dictionary) -> bool:
	if not _exclusions_valid:
		return false
	for exclusion: Dictionary in _exclusions:
		if _overlaps_exclusion(geometry, exclusion, PLAYER_PLANNING_RADIUS + WALKING_MARGIN):
			return false
	return true

func _avoids_solid_cover(geometry: Dictionary) -> bool:
	for obstacle: Dictionary in _obstacles:
		var radius := _bounded_number(obstacle.get("radius", 30.0), 30.0, 0.0, room_size.length())
		if _overlaps_exclusion(geometry, {"kind": "circle", "center": obstacle.pos, "radius": radius}, PLAYER_PLANNING_RADIUS + WALKING_MARGIN):
			return false
	return true

static func _valid_exclusion(exclusion: Dictionary) -> bool:
	if not _finite_number(exclusion.get("radius")) or float(exclusion.radius) < 0.0:
		return false
	match String(exclusion.get("kind", "")):
		"circle":
			return exclusion.get("center") is Vector2 and (exclusion.center as Vector2).is_finite()
		"capsule":
			return exclusion.get("start") is Vector2 and exclusion.get("end") is Vector2 and (exclusion.start as Vector2).is_finite() and (exclusion.end as Vector2).is_finite()
	return false

static func _overlaps_exclusion(geometry: Dictionary, exclusion: Dictionary, margin: float) -> bool:
	var radius := float(exclusion.radius) + margin
	# Conservative envelopes preserve the entire objective footprint and its
	# walking clearance. Over-rejection promotes to assistance, never a tighter
	# hazard around the mandatory route.
	for envelope: Rect2 in _shape_envelopes(geometry):
		if String(exclusion.kind) == "circle":
			var center: Vector2 = exclusion.center
			if center.distance_to(center.clamp(envelope.position, envelope.end)) <= radius:
				return true
		else:
			var start: Vector2 = exclusion.start
			var end: Vector2 = exclusion.end
			var expanded := envelope.grow(radius)
			if expanded.has_point(start) or expanded.has_point(end):
				return true
			var corners := _rect_polygon(expanded)
			for index in 4:
				if Geometry2D.segment_intersects_segment(start, end, corners[index], corners[(index + 1) % 4]) != null:
					return true
	return false

static func _shape_envelopes(geometry: Dictionary) -> Array[Rect2]:
	var envelopes: Array[Rect2] = []
	if geometry.is_empty():
		return envelopes
	if String(geometry.get("kind", "")) == "rects":
		for rect: Rect2 in geometry.get("rects", []):
			envelopes.append(rect)
	elif String(geometry.get("kind", "")) == "sector":
		var center: Vector2 = geometry.center
		var angle := float(geometry.angle)
		var half_angle := float(geometry.half_angle)
		var inner := float(geometry.inner)
		var outer := float(geometry.outer)
		var first := center + Vector2.from_angle(angle - half_angle) * inner
		var envelope := Rect2(first, Vector2.ZERO)
		for boundary_angle: float in [angle - half_angle, angle + half_angle]:
			envelope = envelope.expand(center + Vector2.from_angle(boundary_angle) * inner)
			envelope = envelope.expand(center + Vector2.from_angle(boundary_angle) * outer)
		for index in 4:
			var axis_angle := float(index) * PI * 0.5
			if absf(wrapf(axis_angle - angle, -PI, PI)) <= half_angle:
				envelope = envelope.expand(center + Vector2.from_angle(axis_angle) * outer)
		envelopes.append(envelope)
	else:
		var center: Vector2 = geometry.get("center", Vector2.ZERO)
		var extent := float(geometry.get("radius", geometry.get("outer", 0.0)))
		envelopes.append(Rect2(center - Vector2.ONE * extent, Vector2.ONE * extent * 2.0))
	return envelopes

static func _valid_bounds_size(size: Vector2, ceiling: Vector2) -> bool:
	var minimum := MIN_EFFECTIVE_BOUNDS.min(ceiling)
	return size.is_finite() and size.x >= minimum.x and size.y >= minimum.y and size.x <= ceiling.x and size.y <= ceiling.y

static func _valid_compact_shape(id: String, geometry: Dictionary, size: Vector2) -> bool:
	var bounds := Rect2(-size * 0.5, size)
	for envelope: Rect2 in _shape_envelopes(geometry):
		if not bounds.grow(0.1).encloses(envelope):
			return false
	var kind := String(geometry.get("kind", ""))
	match id:
		"crumble", "storm_reach", "shatterfield", "haunt":
			return kind == "circle" and float(geometry.radius) <= (80.0 if id == "haunt" else 60.0)
		"grinding_vault":
			return (kind == "circle" and float(geometry.radius) <= 65.0) or (kind == "annulus" and float(geometry.outer) <= 120.0 and float(geometry.outer) - float(geometry.inner) <= 50.0)
		"hollow":
			return kind == "rects" and geometry.rects.size() == 1 and geometry.rects[0].size.x <= 70.0 and geometry.rects[0].size.y <= 240.0
		"void_breach":
			return kind == "rects" and geometry.rects.size() == 2 and geometry.rects[0].size.y <= 60.0 and geometry.rects[1].size.y <= 60.0
		"the_maelstrom":
			return kind == "sector" and float(geometry.outer) <= 180.0 and float(geometry.half_angle) <= PI / 6.0
		"convergence_end":
			return kind == "rects" and geometry.rects.size() == 2 and geometry.rects[0].size.x <= 80.0 and geometry.rects[0].size.y <= 80.0 and geometry.rects[1].size.x <= 80.0 and geometry.rects[1].size.y <= 80.0
	return false

func _clamp_center(center: Vector2, radius: float) -> Vector2:
	var limit := (room_size * 0.5 - Vector2.ONE * (radius + 18.0)).max(Vector2.ZERO)
	return center.clamp(-limit, limit).snapped(Vector2(0.5, 0.5))

func _apply_active_effect(players: Array, enemies: Array, entering: bool) -> void:
	if rule_id == "haunt":
		_apply_slow(players, enemies, true)
		return
	if rule_id in ["crumble", "storm_reach", "shatterfield"] and not entering:
		return
	var generation := _generation
	for actor: Variant in players:
		if mode != "assistance" and _eligible_for_impact(actor):
			_hit_ids[actor.get_instance_id()] = true
			# Authority alone changes health. Use the ordinary player damage
			# boundary so armor, resistance, attribution and owner feedback stay live.
			actor.take_damage(_player_damage, {"source": "enemy_ability", "ability": "biome_" + rule_id, "environment": true})
			if generation != _generation:
				return
	for actor: Variant in enemies:
		if not _eligible_for_impact(actor):
			continue
		_hit_ids[actor.get_instance_id()] = true
		# Never resolve source_peer_id=0 through shared player damage. Clear a
		# surrounding action scope, preserve native enemy protection, and let
		# world death callbacks recognize that no player earned this kill.
		var old_scope := DAMAGEABLE.begin_interaction_scope({})
		DAMAGEABLE.begin_secondary_scope()
		environment_damage_active = true
		actor.take_damage(_enemy_damage, {"source": "environment", "ability": "biome_" + rule_id, "interaction": {}, "secondary": true, "is_ground_attack": true})
		environment_damage_active = false
		DAMAGEABLE.end_secondary_scope()
		DAMAGEABLE.end_interaction_scope(old_scope)
		if generation != _generation:
			return

func release_shards(global_center: Vector2, enemies: Array, authoritative: bool) -> void:
	# Called only after an authenticated cover transition, never from effect
	# packets. The existing cover state supplies replica visuals without damage.
	if rule_id != "shatterfield" or fragments or not global_center.is_finite():
		return
	var center := to_local(global_center)
	shard_bursts.append({"center": center, "left": SHARD_VISUAL_TIME})
	queue_redraw()
	if not authoritative:
		return
	var generation := _generation
	var seen := {}
	for actor: Variant in enemies:
		if not _actor_alive(actor) or not actor.has_method("take_damage") or seen.has(actor.get_instance_id()):
			continue
		seen[actor.get_instance_id()] = true
		if global_center.distance_to(actor.global_position) > SHARD_RADIUS + _actor_radius(actor):
			continue
		var old_scope := DAMAGEABLE.begin_interaction_scope({})
		DAMAGEABLE.begin_secondary_scope()
		environment_damage_active = true
		actor.take_damage(SHARD_DAMAGE, {"source": "environment", "ability": "biome_shatter_pillar", "interaction": {}, "secondary": true, "is_ground_attack": true})
		environment_damage_active = false
		DAMAGEABLE.end_secondary_scope()
		DAMAGEABLE.end_interaction_scope(old_scope)
		if generation != _generation:
			return

func _eligible_for_impact(actor: Variant) -> bool:
	return _actor_alive(actor) and actor.has_method("take_damage") and not _hit_ids.has(actor.get_instance_id()) and geometry_contains(shape, to_local(actor.global_position), _actor_radius(actor))

func _apply_slow(players: Array, enemies: Array, authoritative: bool) -> void:
	var duration := minf(0.22, phase_left)
	if duration <= 0.0:
		return
	for actor: Variant in players:
		if mode == "assistance" or not _actor_alive(actor) or not actor.has_method("apply_external_slow") or not geometry_contains(shape, to_local(actor.global_position), _actor_radius(actor)):
			continue
		if actor.has_method("_is_local_control_owner") and not actor._is_local_control_owner():
			continue
		actor.apply_external_slow(duration, _slow_mult)
	if not authoritative:
		return
	for actor: Variant in enemies:
		if _actor_alive(actor) and actor.has_method("apply_slow") and geometry_contains(shape, to_local(actor.global_position), _actor_radius(actor)):
			actor.apply_slow(duration, _slow_mult)

static func _actor_alive(actor: Variant) -> bool:
	return is_instance_valid(actor) and actor is Node2D and not actor.is_queued_for_deletion() and (not actor.has_method("is_dead") or not actor.is_dead())

static func _actor_order(actor: Node2D) -> int:
	# Player nodes expose a stable peer id; lightweight fixtures may not.
	if actor.has_method("_is_local_control_owner"):
		var peer: Variant = actor.get("player_id")
		if peer is int:
			return peer
	return actor.get_instance_id()

static func _actor_radius(actor: Node2D) -> float:
	var collider := actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collider != null and collider.shape is CircleShape2D:
		return (collider.shape as CircleShape2D).radius * actor.global_scale.abs().x
	return 13.0

static func geometry_contains(geometry: Dictionary, point: Vector2, radius: float = 0.0) -> bool:
	if geometry.is_empty() or not point.is_finite() or not is_finite(radius):
		return false
	var body := maxf(0.0, radius)
	var bounds: Variant = geometry.get("bounds")
	if bounds is Rect2 and not bounds.grow(body).has_point(point):
		return false
	var center: Vector2 = geometry.get("center", Vector2.ZERO)
	var offset := point - center
	var distance := offset.length()
	match String(geometry.get("kind", "")):
		"circle":
			return distance <= float(geometry.get("radius", 0.0)) + body
		"annulus":
			return distance + body >= float(geometry.get("inner", 0.0)) and distance - body <= float(geometry.get("outer", 0.0))
		"rects":
			for rect: Rect2 in geometry.get("rects", []):
				if rect.grow(body).has_point(point):
					return true
		"sector":
			if distance + body < float(geometry.get("inner", 0.0)) or distance - body > float(geometry.get("outer", 0.0)):
				return false
			var grace := asin(clampf(body / maxf(0.001, distance), 0.0, 1.0))
			return absf(wrapf(offset.angle() - float(geometry.get("angle", 0.0)), -PI, PI)) <= float(geometry.get("half_angle", 0.0)) + grace
	return false

static func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _bounded_number(value: Variant, fallback: float, lower: float, upper: float) -> float:
	return clampf(float(value), lower, upper) if _finite_number(value) else fallback

static func _valid_shape(geometry: Dictionary, size: Vector2) -> bool:
	var bounds := Rect2(-size * 0.5, size)
	if not (geometry.get("bounds") is Rect2) or not (geometry.bounds as Rect2).is_equal_approx(bounds):
		return false
	var kind := String(geometry.get("kind", ""))
	if kind == "rects":
		var rects: Variant = geometry.get("rects")
		if not (rects is Array) or rects.is_empty() or rects.size() > 2:
			return false
		for rect: Variant in rects:
			if not (rect is Rect2) or not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x <= 0.0 or rect.size.y <= 0.0 or not bounds.grow(0.1).encloses(rect):
				return false
		return true
	if kind not in ["circle", "annulus", "sector"] or not (geometry.get("center") is Vector2) or not (geometry.center as Vector2).is_finite() or not bounds.has_point(geometry.center):
		return false
	if kind == "circle":
		return _finite_number(geometry.get("radius")) and float(geometry.radius) > 0.0 and float(geometry.radius) <= size.length()
	if not _finite_number(geometry.get("inner")) or not _finite_number(geometry.get("outer")) or float(geometry.inner) < 0.0 or float(geometry.outer) <= float(geometry.inner) or float(geometry.outer) > size.length():
		return false
	return kind == "annulus" or (_finite_number(geometry.get("angle")) and _finite_number(geometry.get("half_angle")) and float(geometry.half_angle) > 0.0 and float(geometry.half_angle) <= PI)

func _draw() -> void:
	if _combat_visible:
		_draw_shard_bursts()
	if not _combat_visible or shape.is_empty() or phase not in ["warning", "active"] or phase_left <= 0.0:
		return
	var warning := phase == "warning"
	var tint := POLARITY_CONTOUR.tint(mode == "assistance", warning)
	var fill := Color(tint, 0.10 if warning else 0.23)
	var line := Color(tint, 0.84 if warning else 0.96)
	if mode == "assistance":
		fill.a = 0.07 if warning else 0.16
	var remaining := clampf(phase_left / maxf(0.001, phase_duration), 0.0, 1.0)
	if not warning:
		fill.a *= 0.45 + remaining * 0.55
	var geometry_bounds: Rect2 = shape.get("bounds", Rect2())
	var kind := String(shape.get("kind", ""))
	var center: Vector2 = shape.get("center", Vector2.ZERO)
	match kind:
		"circle":
			var radius := float(shape.radius)
			draw_circle(center, radius, fill)
			if rule_id == "storm_reach":
				var bolt := PackedVector2Array([center + Vector2(8, -21), center + Vector2(-7, 1), center + Vector2(7, 1), center + Vector2(-8, 21)])
				draw_polyline(bolt, line, 3.0, true)
			elif rule_id == "haunt":
				for index in 3:
					draw_arc(center + Vector2((index - 1) * 19, 0), 12.0, PI * 0.2, PI * 1.6, 20, line, 2.0, true)
			elif rule_id == "shatterfield":
				for index in 3:
					var shard_center := center + Vector2.from_angle(float(index) * TAU / 3.0) * 12.0
					var shard := PackedVector2Array([shard_center + Vector2(-5, 3), shard_center + Vector2(1, -9), shard_center + Vector2(6, 5), shard_center + Vector2(-5, 3)])
					draw_polyline(shard, line, 2.0, true)
			else:
				var rock := PackedVector2Array([center + Vector2(-14, -8), center + Vector2(3, -18), center + Vector2(16, 0), center + Vector2(7, 13), center + Vector2(-14, -8)])
				draw_polyline(rock, line, 2.5, true)
		"rects":
			for rect: Rect2 in shape.rects:
				draw_rect(rect, fill)

		"annulus", "sector":
			var inner := float(shape.inner)
			var outer := float(shape.outer)
			var angle := float(shape.get("angle", 0.0))
			var half_angle := float(shape.get("half_angle", PI))
			var segments := 64 if kind == "annulus" else 24
			for index in segments:
				var a := angle - half_angle + 2.0 * half_angle * float(index) / float(segments)
				var b := angle - half_angle + 2.0 * half_angle * float(index + 1) / float(segments)
				var points := PackedVector2Array([center + Vector2.from_angle(a) * inner, center + Vector2.from_angle(a) * outer, center + Vector2.from_angle(b) * outer, center + Vector2.from_angle(b) * inner])
				# Intersect with the arena so diagonal sectors never draw damage
				# outside the same bounds used by collision tests.
				var clipped := Geometry2D.intersect_polygons(points, _rect_polygon(geometry_bounds))
				for polygon: PackedVector2Array in clipped:
					if polygon.size() >= 3:
						draw_colored_polygon(polygon, fill)
	POLARITY_CONTOUR.draw_contours(self, get_polarity_contours(), line, remaining if warning else -1.0)

func get_polarity_contours() -> Array[Dictionary]:
	if not _combat_visible or phase not in ["warning", "active"] or phase_left <= 0.0 or shape.is_empty():
		return []
	var unit := snappedf(POLARITY_CONTOUR.screen_unit(self), .01)
	var cache_key := hash([shape, mode == "assistance", unit])
	if cache_key != _contour_cache_key or _contour_cache.is_empty():
		_contour_cache_key = cache_key
		_contour_cache = POLARITY_CONTOUR.build_contours(shape, mode == "assistance", unit)
	return _contour_cache

func _draw_shard_bursts() -> void:
	for burst: Dictionary in shard_bursts:
		var center: Vector2 = burst.center
		var remaining := clampf(float(burst.left) / SHARD_VISUAL_TIME, 0.0, 1.0)
		var progress := 1.0 - remaining
		var tint := Color(.56, .96, .74, remaining)
		draw_circle(center, SHARD_RADIUS, Color(tint, .15 * remaining))
		var geometry := {"kind": "circle", "center": center, "radius": SHARD_RADIUS, "bounds": Rect2(-room_size * .5, room_size)}
		POLARITY_CONTOUR.draw_contours(self, POLARITY_CONTOUR.build_contours(geometry, true, POLARITY_CONTOUR.screen_unit(self)), tint)
		for index in 12:
			var direction := Vector2.from_angle(float(index) * TAU / 12.0)
			var tip := center + direction * lerpf(28.0, SHARD_RADIUS - 4.0, minf(1.0, progress * 2.5))
			var tail := tip - direction * (13.0 + 11.0 * remaining)
			draw_line(tail, tip, tint, 3.0, true)

static func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
