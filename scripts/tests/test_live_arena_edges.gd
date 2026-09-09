extends SceneTree
## Real WorldGenerator bounds and production movement; no perimeter colliders.

const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const MOTION := preload("res://scripts/arcana_motion_controller.gd")
const STEP := 1.0 / 60.0
const SIDES := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]

class Room extends "res://scripts/world_generator.gd":
	var damage_events: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _exit_tree() -> void:
		pass
	func record_player_damage_dealt(amount: int, peer: int = 0, killed: bool = false, enemy_id: int = 0) -> void:
		damage_events.append({"amount": amount, "peer": peer, "killed": killed, "enemy": enemy_id})

class Actor extends "res://scripts/player.gd":
	var aim := Vector2.LEFT
	var completions: Array[Vector2] = []
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _get_mouse_attack_direction() -> Vector2:
		return aim
	func _notification(_what: int) -> void:
		# Isolated GPU fixtures deliberately use a window without OS focus.
		pass
	func on_arcana_motion_completed(origin: Vector2, contact: Vector2 = Vector2.INF) -> void:
		completions.append(global_position)
		super.on_arcana_motion_completed(origin, contact)

class Enemy extends "res://scripts/enemy_base.gd":
	var hits: Array[Dictionary] = []
	func _ready() -> void:
		max_health = 10000
		_create_health_state()
		add_to_group("enemies")
		set_physics_process(false)
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		var before := get_current_health()
		super.take_damage(amount, context)
		if get_current_health() < before:
			hits.append(context.duplicate(true))

var room: Room
var actor: Actor
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures.append(detail)
		push_error(detail)

func _circle(body: CollisionObject2D, radius: float) -> void:
	var collider := CollisionShape2D.new()
	collider.shape = CircleShape2D.new()
	(collider.shape as CircleShape2D).radius = radius
	body.add_child(collider)

func _setup() -> void:
	room = Room.new()
	root.add_child(room)
	current_scene = room
	room.current_room_size = Vector2(1160.0, 860.0)
	room.current_effective_room_size = room.current_room_size
	EnemyReplicationService.bind_world(room)
	actor = Actor.new()
	_circle(actor, 14.0)
	room.add_child(actor)
	room.player = actor
	actor.player_id = 1
	actor.damage = 20
	actor.attack_range = 78.0
	actor.arcana_motion.set_process(false)
	actor.returning_crescent.set_physics_process(false)
	actor.boss_combinations.set_process(false)
	for audio in room.find_children("*", "AudioStreamPlayer", true, false):
		audio.stream = null

func _clear() -> void:
	actor.discard_pending_combat_input()
	if is_instance_valid(actor.upgrade_system.power_registry):
		actor.upgrade_system.power_registry.free()
	EnemyReplicationService.unbind_world(room)
	current_scene = null
	room.free()

func _enemy(position: Vector2) -> Enemy:
	var enemy := Enemy.new()
	_circle(enemy, 13.0)
	room.add_child(enemy)
	enemy.global_position = position
	return enemy

func _edge(direction: Vector2) -> Vector2:
	return direction * room.current_effective_room_size * 0.5

func _inside(position: Vector2) -> bool:
	var half := room.current_effective_room_size * 0.5
	return absf(position.x) <= half.x + 0.01 and absf(position.y) <= half.y + 0.01

func _advance_crescent(duration: float) -> void:
	var remaining := duration
	while remaining > 0.00001:
		var delta := minf(STEP, remaining)
		actor.returning_crescent.tick(delta)
		remaining -= delta

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Live arena edges require isolated user data")
		quit(1)
		return
	await _test_crescent_sides()
	await _test_crescent_corners_and_hitches()
	await _test_crescent_boundary_and_shrink()
	await _test_ruinous_sides()
	await _test_nearer_cover_and_player()
	await _test_motion_sides()
	await _test_shrinking_room()
	await _test_world_clamp_before_movement()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Live arena edges: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_crescent_sides() -> void:
	for direction: Vector2 in SIDES:
		for level in [1, 2, 3]:
			_setup()
			actor.global_position = _edge(direction) - direction * 50.0
			for _index in range(level):
				actor.apply_trial_power("returning_crescent")
			await physics_frame
			_check(actor.returning_crescent.try_launch(direction), "L%d starts toward %s room edge" % [level, direction])
			var initial_budget: float = actor.returning_crescent.blades[0].travel_left
			actor.returning_crescent.tick(0.10)
			_check(actor.returning_crescent.blades.size() == 1, "Edge turn remains visible before the blade reaches its owner")
			if not actor.returning_crescent.blades.is_empty():
				var blade := actor.returning_crescent.blades[0]
				_check(_inside(blade.position), "Crescent stays inside the actual %s room edge" % direction)
				_check(blade.returning == (level < 3) and blade.bounces_left == 0, "Only L3 reflects outbound; lower levels turn home")
				_check(blade.direction.dot(direction) < -0.99, "Edge contact reverses the blade away from the perimeter")
				if level == 3:
					_check(absf(initial_budget - blade.travel_left - 62.0) < 0.5, "Ricochet consumes the existing outbound budget")
			_advance_crescent(1.0)
			_check(actor.returning_crescent.blades.is_empty(), "A bounded edge sequence returns its blade slot")
			_clear()

func _test_crescent_corners_and_hitches() -> void:
	for signs: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_setup()
		var direction := signs.normalized()
		actor.global_position = signs * room.current_room_size * 0.5 - direction * 50.0
		for _index in range(3):
			actor.apply_trial_power("returning_crescent")
		await physics_frame
		actor.returning_crescent.try_launch(direction)
		actor.returning_crescent.tick(0.10)
		_check(actor.returning_crescent.blades.size() == 1, "Corner reflection keeps one blade")
		if not actor.returning_crescent.blades.is_empty():
			var blade := actor.returning_crescent.blades[0]
			_check(_inside(blade.position) and blade.direction.dot(direction) < -0.99 and blade.bounces_left == 0, "Simultaneous corner contact consumes one bounce and reflects both axes")
		actor.returning_crescent.tick(1.7)
		_check(actor.returning_crescent.blades.is_empty(), "A long frame after a corner cannot strand a blade")
		_clear()

func _test_crescent_boundary_and_shrink() -> void:
	_setup()
	for _index in range(3):
		actor.apply_trial_power("returning_crescent")
	actor.global_position = Vector2(580.0, 0.0)
	await physics_frame
	actor.returning_crescent.try_launch(Vector2.LEFT)
	actor.returning_crescent.tick(0.05)
	var blade := actor.returning_crescent.blades[0]
	_check(blade.bounces_left == 1 and not blade.returning and blade.position.x < 580.0, "Starting exactly at the edge while moving inward does not bounce")
	actor.returning_crescent.cancel()
	actor.returning_crescent.try_launch(Vector2.RIGHT)
	actor.returning_crescent.tick(0.02)
	blade = actor.returning_crescent.blades[0]
	_check(blade.bounces_left == 0 and blade.direction.x < 0.0 and _inside(blade.position), "Starting at the edge outward reflects immediately once")
	actor.returning_crescent.cancel()
	actor.global_position = Vector2.ZERO
	actor.returning_crescent.try_launch(Vector2.RIGHT)
	actor.returning_crescent.tick(0.24)
	var untouched := _enemy(Vector2(120.0, 0.0))
	room.current_effective_room_size = Vector2(200.0, 300.0)
	actor.returning_crescent.tick(0.10)
	_check(actor.returning_crescent.blades.is_empty() and untouched.hits.is_empty(), "An outside blade after arena shrink cancels without teleporting or inventing a hit segment")
	_clear()
	_setup()
	actor.apply_trial_power("returning_crescent")
	actor.global_position = Vector2(550.0, 0.0)
	await physics_frame
	actor.returning_crescent.try_launch(Vector2.LEFT)
	blade = actor.returning_crescent.blades[0]
	blade.position = Vector2(560.0, 0.0)
	blade.returning = true
	actor.global_position = Vector2(640.0, 0.0)
	actor.returning_crescent.tick(0.10)
	_check(actor.returning_crescent.blades.is_empty(), "A returning blade reaching the edge dissolves instead of crossing to an outside owner")
	_clear()

func _test_ruinous_sides() -> void:
	for direction: Vector2 in SIDES:
		_setup()
		actor.ruinous_impact_stacks = 1
		var enemy := _enemy(_edge(direction) - direction * 30.0)
		await physics_frame
		actor.boss_combinations.launch_enemy(enemy, direction * 750.0, 1)
		var state := enemy.get_launch_state()
		state.step(enemy, 0.20)
		_check(enemy.global_position.is_equal_approx(_edge(direction)), "Ruinous resolves at the exact %s allowed-center edge" % direction)
		_check(not state.active and enemy.hits.size() == 1 and enemy.hits[0].get("attack_type") == "ruinous_impact", "Perimeter launch produces one real secondary burst")
		_check(enemy.get_current_health() == 9980 and state.ended.get_connections().is_empty(), "Existing burst strength and one-shot cleanup are preserved")
		state.step(enemy, 1.0)
		room._keep_enemies_inside_current_room(1.0)
		_check(enemy.hits.size() == 1 and _inside(enemy.global_position), "A hitch and subsequent room clamp cannot burst again")
		_clear()

func _thin_cover(position: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	collider.shape = RectangleShape2D.new()
	(collider.shape as RectangleShape2D).size = Vector2(1.0, 180.0)
	body.add_child(collider)
	body.global_position = position
	room.add_child(body)
	return body

func _test_nearer_cover_and_player() -> void:
	_setup()
	actor.global_position = Vector2(450.0, 0.0)
	for _index in range(3):
		actor.apply_trial_power("returning_crescent")
	_thin_cover(Vector2(520.0, 0.0))
	await physics_frame
	actor.returning_crescent.try_launch(Vector2.RIGHT)
	actor.returning_crescent.tick(0.15)
	var blade := actor.returning_crescent.blades[0]
	_check(blade.bounces_left == 0 and blade.position.x < 520.0 and blade.direction.x < 0.0, "Thin physical cover reflects before the farther room edge during a hitch")
	actor.returning_crescent.cancel()
	actor.ruinous_impact_stacks = 1
	actor.global_position = Vector2.ZERO
	var enemy := _enemy(Vector2(470.0, 0.0))
	await physics_frame
	actor.boss_combinations.launch_enemy(enemy, Vector2.RIGHT * 750.0, 1)
	enemy.get_launch_state().step(enemy, 0.5)
	_check(enemy.global_position.x > 490.0 and enemy.global_position.x < 520.0 and enemy.hits.size() == 1, "Nearer cover wins the launch collision and its one burst origin")
	_clear()
	_setup()
	actor.ruinous_impact_stacks = 1
	actor.global_position = Vector2(550.0, 0.0)
	enemy = _enemy(Vector2(490.0, 0.0))
	await physics_frame
	actor.boss_combinations.launch_enemy(enemy, Vector2.RIGHT * 750.0, 1)
	enemy.get_launch_state().step(enemy, 0.5)
	_check(not enemy.get_launch_state().active and enemy.global_position.x < 550.0 and enemy.hits.is_empty(), "A nearer player body cancels the launch without a perimeter burst")
	_clear()

func _test_motion_sides() -> void:
	for direction: Vector2 in SIDES:
		for mode in [MOTION.Motion.RECOIL, MOTION.Motion.CARRY]:
			_setup()
			actor.global_position = _edge(direction) - direction * 30.0
			actor.sovereigns_double_stacks = 1
			actor._dash_damage_immune_left = 0.17
			var motion := actor.arcana_motion
			motion.motion = mode
			motion.motion_origin = actor.global_position
			motion.recoil_direction = direction
			motion.recoil_initial_direction = direction
			motion.recoil_left = 170.0
			motion.recoil_speed = 850.0
			motion.tangent = direction
			motion.carry_left = 0.15
			await physics_frame
			motion.process_movement(0.5, Vector2.ZERO)
			_check(actor.global_position.is_equal_approx(_edge(direction)) and motion.motion == MOTION.Motion.NONE, "%s stops on its first %s edge contact through a hitch" % [mode, direction])
			_check(is_equal_approx(actor._dash_damage_immune_left, 0.17), "Room contact does not alter the independent dash immunity clock")
			if mode == MOTION.Motion.RECOIL:
				_check(actor.completions.size() == 1 and actor.boss_combinations.shade_hits == 1, "Ordinary swept recoil contact completes once and leaves its existing shade")
			var completed_count := actor.completions.size()
			motion.process_movement(0.5, Vector2.ZERO)
			room._keep_player_inside_current_room()
			_check(actor.completions.size() == completed_count and actor.global_position.is_equal_approx(_edge(direction)), "Repeated movement/clamp cannot emit another completion")
			_clear()
		_setup()
		var anchor := _enemy(_edge(direction) - direction * 20.0)
		actor.global_position = anchor.global_position + direction.rotated(-PI * 0.5) * 70.2
		actor.dash_direction = direction
		actor._dash_damage_immune_left = 0.17
		actor.sovereigns_double_stacks = 1
		actor.apply_trial_power("razor_orbit")
		await physics_frame
		actor.arcana_motion.start_orbit(anchor)
		for _index in range(8):
			if actor.arcana_motion.motion == MOTION.Motion.NONE:
				break
			actor.arcana_motion.process_movement(STEP, Vector2.ZERO)
		_check(actor.arcana_motion.motion == MOTION.Motion.NONE and actor.arcana_motion.anchor == null and _inside(actor.global_position), "Orbit detaches at %s perimeter without entering carry" % direction)
		_check(is_equal_approx(actor._dash_damage_immune_left, 0.17), "Orbit edge detachment preserves dash immunity duration")
		_check(actor.completions.size() == 1 and actor.boss_combinations.shade_hits == 1, "Ordinary swept Orbit contact completes once and leaves its existing shade")
		_clear()

func _test_shrinking_room() -> void:
	for mode in [MOTION.Motion.RECOIL, MOTION.Motion.ORBIT, MOTION.Motion.CARRY]:
		_setup()
		actor.global_position = Vector2(550.0, 0.0)
		actor.sovereigns_double_stacks = 1
		var anchor := _enemy(Vector2(450.0, 100.0))
		var untouched := _enemy(Vector2(300.0, 0.0))
		var motion := actor.arcana_motion
		motion.motion = mode
		motion.anchor = anchor
		motion.recoil_direction = Vector2.LEFT
		motion.recoil_left = 170.0
		motion.recoil_speed = 850.0
		motion.tangent = Vector2.LEFT
		motion.carry_left = 0.15
		room.current_effective_room_size = Vector2(400.0, 300.0)
		await physics_frame
		motion.process_movement(0.2, Vector2.ZERO)
		_check(actor.global_position == Vector2(200.0, 0.0) and motion.motion == MOTION.Motion.NONE and motion.anchor == null, "Shrinking arena clamps and ends mode %s immediately" % mode)
		_check(untouched.hits.is_empty(), "Shrink correction never invents an Orbit cutting segment")
		_check(actor.completions.is_empty() and actor.boss_combinations.shade_hits == 0, "Direct shrink correction cancels without a false completion or shade")
		_clear()
	_setup()
	actor.ruinous_impact_stacks = 1
	var launched := _enemy(Vector2(550.0, 0.0))
	await physics_frame
	actor.boss_combinations.launch_enemy(launched, Vector2.LEFT * 750.0, 1)
	room.current_effective_room_size = Vector2(400.0, 300.0)
	launched.get_launch_state().step(launched, 0.2)
	_check(launched.global_position == Vector2(200.0, 0.0) and not launched.get_launch_state().active and launched.hits.is_empty(), "Shrink clamps a launched enemy and cancels without an invented impact burst")
	_clear()

func _test_world_clamp_before_movement() -> void:
	# WorldGenerator's render-frame clamp can run before the next physics step.
	# That order must not erase the outside-start evidence and leave motion live.
	for mode in [MOTION.Motion.RECOIL, MOTION.Motion.ORBIT, MOTION.Motion.CARRY]:
		_setup()
		actor.global_position = Vector2(550.0, 0.0)
		actor.sovereigns_double_stacks = 1
		var anchor := _enemy(Vector2(450.0, 100.0))
		var untouched := _enemy(Vector2(300.0, 0.0))
		var motion := actor.arcana_motion
		motion.motion = mode
		motion.anchor = anchor
		motion.recoil_direction = Vector2.LEFT
		motion.recoil_left = 170.0
		motion.recoil_speed = 850.0
		motion.tangent = Vector2.LEFT
		motion.carry_left = 0.15
		room.current_effective_room_size = Vector2(400.0, 300.0)
		await physics_frame
		room._keep_player_inside_current_room()
		_check(actor.global_position == Vector2(200.0, 0.0) and motion.motion == MOTION.Motion.NONE and motion.anchor == null, "World clamp ends mode %s before physics can resume it" % mode)
		motion.process_movement(0.2, Vector2.ZERO)
		_check(actor.global_position == Vector2(200.0, 0.0) and untouched.hits.is_empty(), "Post-clamp physics cannot continue movement or invent a cutting segment")
		_check(actor.completions.is_empty() and actor.boss_combinations.shade_hits == 0, "World-first shrink correction cancels without a false completion or shade")
		_clear()
	_setup()
	actor.ruinous_impact_stacks = 1
	var launched := _enemy(Vector2(550.0, 0.0))
	await physics_frame
	actor.boss_combinations.launch_enemy(launched, Vector2.LEFT * 750.0, 1)
	room.current_effective_room_size = Vector2(400.0, 300.0)
	room._keep_enemies_inside_current_room(0.02)
	_check(launched.global_position == Vector2(200.0, 0.0) and not launched.get_launch_state().active, "World clamp cancels an outside launch before its physics step")
	launched.get_launch_state().step(launched, 0.2)
	room._keep_enemies_inside_current_room(0.02)
	_check(launched.global_position == Vector2(200.0, 0.0) and launched.hits.is_empty() and launched.get_launch_state().ended.get_connections().is_empty(), "World-clamped launch stays cancelled without an impact or retained completion listener")
	_clear()
	_setup()
	actor.global_position = Vector2(550.0, 0.0)
	actor.velocity = Vector2(80.0, 0.0)
	actor.dash_time_left = 0.12
	actor.dash_remaining_distance = 80.0
	actor._dash_damage_immune_left = 0.17
	room.current_effective_room_size = Vector2(400.0, 300.0)
	room._keep_player_inside_current_room()
	_check(actor.global_position == Vector2(200.0, 0.0) and actor.velocity == Vector2(80.0, 0.0), "Ordinary room clamping retains existing movement velocity")
	_check(is_equal_approx(actor.dash_time_left, 0.12) and is_equal_approx(actor.dash_remaining_distance, 80.0) and is_equal_approx(actor._dash_damage_immune_left, 0.17), "Ordinary dash distance, time and immunity are not changed by the Arcana edge fix")
	_clear()
