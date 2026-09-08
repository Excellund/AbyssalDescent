extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
const MOTION := preload("res://scripts/arcana_motion_controller.gd")
const CHARACTER := preload("res://scripts/character_registry.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")

class MotionPlayer extends "res://scripts/player.gd":
	var blast_releases: int = 0
	var pause_during_blast: bool = false
	var local_owner: bool = true
	var aim: Vector2 = Vector2.RIGHT
	var motion_blast_cues: int = 0

	func _ready() -> void:
		super._ready()
		set_physics_process(false)

	func _is_local_control_owner() -> bool:
		return local_owner

	func _get_mouse_attack_direction() -> Vector2:
		return aim

	func perform_motion_blast(direction: Vector2, strength: float) -> void:
		blast_releases += 1
		super.perform_motion_blast(direction, strength)
		if pause_during_blast:
			# Room clears synchronously open a reward modal during damage delivery.
			encounter_input_frozen = true
			discard_pending_combat_input()

	func _broadcast_cue_event(event_name: String, payload: Dictionary, reliable: bool = false) -> void:
		if event_name == "motion_blast":
			motion_blast_cues += 1
		super._broadcast_cue_event(event_name, payload, reliable)

class AimMotion extends "res://scripts/arcana_motion_controller.gd":
	var aimed_anchor: Node2D
	var acquisition_attempts: int = 0

	func find_anchor(_cursor: Vector2, _enemies_only: bool = false) -> Node2D:
		acquisition_attempts += 1
		return aimed_anchor if is_instance_valid(aimed_anchor) else null

class PointerMotion extends "res://scripts/arcana_motion_controller.gd":
	var viewport_pointer: Vector2 = Vector2.ZERO

	func _orbit_aim_world_position() -> Vector2:
		# A headless Window has no OS cursor. Keep the real camera conversion and
		# all production candidate/range/LOS logic, supplying only pointer pixels.
		return player.get_canvas_transform().affine_inverse() * viewport_pointer

class MotionEnemy extends "res://scripts/enemy_base.gd":
	func _ready() -> void:
		set_physics_process(false)
		max_health = 10000
		_create_health_state()
		add_to_group("enemies")

class MotionWorld extends Node2D:
	var recorded_damage: int = 0

	func record_player_damage_dealt(amount: int, _peer_id: int = 0, _killed: bool = false, _enemy_id: int = 0) -> void:
		recorded_damage += amount

var checks: int = 0
var failures: Array[String] = []
var world: MotionWorld
var player: MotionPlayer

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _make_world(character_id: String = "bastion", deterministic_aim: bool = false, live_scene: bool = false) -> void:
	world = MotionWorld.new()
	root.add_child(world)
	current_scene = world
	if live_scene:
		var scene_player := (load("res://scenes/Player.tscn") as PackedScene).instantiate()
		scene_player.set_script(MotionPlayer)
		player = scene_player as MotionPlayer
	else:
		player = MotionPlayer.new()
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		(shape.shape as CircleShape2D).radius = 14.0
		player.add_child(shape)
	world.add_child(player)
	player.apply_character_package(CHARACTER.get_character(character_id))
	if deterministic_aim:
		player.arcana_motion.free()
		player.arcana_motion = AimMotion.new()
		player.add_child(player.arcana_motion)
		player.arcana_motion.initialize(player)
	player.arcana_motion.set_process(false)
	player.arcana_motion.hide()
	for audio_node in world.find_children("*", "AudioStreamPlayer", true, false):
		(audio_node as AudioStreamPlayer).stream = null
	for audio_node in world.find_children("*", "AudioStreamPlayer2D", true, false):
		(audio_node as AudioStreamPlayer2D).stream = null

func _free_world() -> void:
	if player != null and is_instance_valid(player.upgrade_system.power_registry):
		player.upgrade_system.power_registry.free()
	current_scene = null
	world.free()
	world = null
	player = null

func _enemy(position: Vector2) -> MotionEnemy:
	var enemy := MotionEnemy.new()
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	(shape.shape as CircleShape2D).radius = 13.0
	enemy.add_child(shape)
	world.add_child(enemy)
	enemy.global_position = position
	return enemy

func _column(position: Vector2, radius: float = 28.0) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.add_to_group("arena_columns")
	body.set_meta("column_radius", radius)
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	(shape.shape as CircleShape2D).radius = radius
	body.add_child(shape)
	world.add_child(body)
	body.global_position = position
	return body

func _release_actions() -> void:
	Input.action_release("attack")
	Input.action_release("dash")
	await process_frame
	await physics_frame
	await process_frame
	if is_instance_valid(player):
		player._refresh_combat_input_release()

func _ready_attack() -> void:
	player.attack_lock_time_left = 0.0
	player.attack_cooldown_left = 0.0
	Input.action_press("attack")
	player._try_attack_input()

func _tick_hold(duration: float) -> void:
	var remaining := duration
	while remaining > 0.00001:
		var delta := minf(0.025, remaining)
		player.arcana_motion.tick(delta)
		remaining -= delta

func _finish_dash_for_input_test() -> void:
	player.dash_remaining_distance = 0.0
	player.dash_time_left = 0.0
	player.dash_phase_release_left = 0.0
	player._dash_damage_immune_left = 0.0
	player._set_dash_phasing(false)

func _start_dash() -> void:
	player.attack_lock_time_left = 0.0
	player.dash_cooldown_left = 0.0
	Input.action_press("dash")
	player._try_start_dash(Vector2.RIGHT)

func _run() -> void:
	await _test_attack_gestures()
	await _test_cancellation()
	await _test_dash_gestures()
	await _test_real_anchor_geometry()
	await _test_live_camera_aim_capture()
	await _test_captured_anchor_gates()
	await _test_collision_and_immunity()
	await _test_carry_hitch_bound()
	await _test_orbit_attack_and_blast_detach()
	await _test_upgrade_and_snapshot_parity()
	await _test_contact_cadence_and_transfer()
	await _test_fixed_orbit_direction()
	await _test_transfer_direction()
	await _release_actions()
	for audio_node in root.find_children("*", "AudioStreamPlayer", true, false):
		(audio_node as AudioStreamPlayer).stop()
	for audio_node in root.find_children("*", "AudioStreamPlayer2D", true, false):
		(audio_node as AudioStreamPlayer2D).stop()
	await create_timer(0.05).timeout
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("Arcana motion regressions: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_attack_gestures() -> void:
	_make_world()
	player.apply_trial_power("blast_drive")
	await _release_actions()
	var before := player.attack_combo_counter
	_ready_attack()
	_check(player.attack_combo_counter == before + 1, "Attack tap strikes immediately, without waiting for a hold decision")
	_check(player.arcana_motion.charge_hold == 0.0, "Accepted primary press arms the optional charge")
	Input.action_release("attack")
	player.arcana_motion.tick(0.30)
	_check(player.blast_releases == 0 and player.arcana_motion.blast_charges == 1, "Quick attack tap does not fire or spend a blast")
	await _release_actions()
	_ready_attack()
	_tick_hold(0.24)
	Input.action_release("attack")
	player.arcana_motion.tick(0.01)
	_check(player.blast_releases == 0, "Releasing below the deliberate-hold threshold remains an ordinary attack")
	await _release_actions()
	_ready_attack()
	_tick_hold(0.66)
	_check(player.blast_releases == 0, "A full charge waits for release")
	Input.action_release("attack")
	player.arcana_motion.tick(0.01)
	_check(player.blast_releases == 1 and player.arcana_motion.blast_charges == 0, "Release fires exactly one charged blast")
	_check(player.arcana_motion.motion == MOTION.Motion.RECOIL and player.arcana_motion.recoil_direction.x < -0.99, "A forward blast propels the player backward")
	player.arcana_motion.tick(0.01)
	_check(player.blast_releases == 1, "A released button cannot repeatedly fire")
	player.arcana_motion.cancel()
	await _release_actions()
	_ready_attack()
	_check(player.arcana_motion.charge_hold < 0.0, "A press while out of blast charges cannot arm a delayed blast")
	_tick_hold(2.0)
	Input.action_release("attack")
	player.arcana_motion.tick(0.01)
	_check(player.blast_releases == 1 and player.arcana_motion.blast_charges == 1, "Recharging while Attack remains held does not retroactively fire")
	await _release_actions()
	player.attack_cooldown_left = 10.0
	player.attack_lock_time_left = 0.0
	Input.action_press("attack")
	player._try_attack_input()
	_tick_hold(0.70)
	Input.action_release("attack")
	player.arcana_motion.tick(0.01)
	_check(player.blast_releases == 1, "A rejected primary press cannot charge a blast")
	await _release_actions()
	_free_world()

func _test_cancellation() -> void:
	_make_world()
	player.apply_trial_power("blast_drive")
	for reason in ["modal", "focus", "death", "remote"]:
		await _release_actions()
		_ready_attack()
		_tick_hold(0.40)
		match reason:
			"modal":
				player.encounter_input_frozen = true
				player.discard_pending_combat_input()
			"focus":
				player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"death":
				player._is_alive_state = false
				player.arcana_motion.tick(0.01)
			"remote":
				player.local_owner = false
				player.arcana_motion.tick(0.01)
		if reason in ["modal", "focus"]:
			player.encounter_input_frozen = false
			var attacks_before := player.attack_combo_counter
			player.attack_lock_time_left = 0.0
			player.attack_cooldown_left = 0.0
			player._try_attack_input()
			_tick_hold(0.70)
			_check(player.attack_combo_counter == attacks_before and player.arcana_motion.charge_hold < 0.0, "%s resume still requires release before a fresh primary or charge" % reason)
		Input.action_release("attack")
		player.arcana_motion.tick(0.01)
		_check(player.blast_releases == 0 and not player.arcana_motion.owns_movement(), "%s cancellation drops held input without firing" % reason)
		player.encounter_input_frozen = false
		player._is_alive_state = true
		player.local_owner = true
	await _release_actions()
	_ready_attack()
	_tick_hold(0.30)
	_start_dash()
	_check(player._is_dash_active() and player.arcana_motion.charge_hold < 0.0, "A fresh accepted dash cancels Blast charge")
	Input.action_release("attack")
	player.arcana_motion.tick(0.01)
	_check(player.blast_releases == 0, "Dash cancellation does not fire on later Attack release")
	_finish_dash_for_input_test()
	await _release_actions()
	player.pause_during_blast = true
	_ready_attack()
	_tick_hold(0.66)
	Input.action_release("attack")
	player.arcana_motion.tick(0.01)
	_check(player.encounter_input_frozen and not player.arcana_motion.owns_movement(), "Synchronous reward pause during blast damage cannot restart recoil afterward")
	_check(player.motion_blast_cues == 1, "An already discharged Blast publishes its cue before a killing hit opens rewards")
	await _release_actions()
	_free_world()

func _test_dash_gestures() -> void:
	_make_world("bastion", true)
	player.apply_trial_power("razor_orbit")
	player.apply_trial_power("blast_drive")
	var target := _enemy(Vector2(85.0, 0.0))
	var motion := player.arcana_motion as AimMotion
	motion.aimed_anchor = target
	await _release_actions()
	_start_dash()
	_check(player._is_dash_active(), "Dash starts immediately on press")
	_finish_dash_for_input_test()
	motion.tick(0.08)
	_check(motion.motion == MOTION.Motion.NONE and motion.dash_hold < MOTION.HOLD_TIME, "An early wall-stopped dash cannot immediately acquire an orbit")
	Input.action_release("dash")
	motion.tick(0.01)
	_check(motion.motion == MOTION.Motion.NONE, "A quick Dash tap remains a normal dash")
	await _release_actions()
	_start_dash()
	_finish_dash_for_input_test()
	_tick_hold(0.26)
	_check(motion.motion == MOTION.Motion.ORBIT and motion.anchor == target, "Holding through an accepted dash acquires the deliberately aimed foe")
	_check(motion.dash_hold < 0.0, "Successful Orbit entry consumes the held-dash acquisition request")
	Input.action_release("dash")
	motion.tick(0.01)
	_check(motion.motion == MOTION.Motion.CARRY and motion.anchor == null, "Releasing Dash detaches with tangent carry")
	motion.cancel()
	await _release_actions()
	motion.aimed_anchor = null
	_start_dash()
	_finish_dash_for_input_test()
	_tick_hold(0.26)
	_check(motion.dash_hold >= 0.0, "Empty initial aim leaves a bounded window for deliberate correction")
	_tick_hold(0.45)
	_check(motion.dash_hold < 0.0, "A failed Orbit acquisition expires after the bounded aim window")
	motion.aimed_anchor = target
	_tick_hold(0.70)
	_check(motion.motion == MOTION.Motion.NONE, "Failed acquisition does not unexpectedly latch a later target while Dash stays held")
	await _release_actions()
	motion.aimed_anchor = null
	_start_dash()
	_finish_dash_for_input_test()
	_tick_hold(0.30)
	motion.aimed_anchor = target
	motion.tick(0.10)
	_check(motion.motion == MOTION.Motion.ORBIT and motion.anchor == target, "Deliberate cursor correction can acquire a target within the short hold window")
	motion.cancel()
	await _release_actions()
	_start_dash()
	Input.action_press("attack")
	player._try_attack_input()
	_check(player.queued_attack_after_dash and motion.charge_hold < 0.0, "Attack during a dash queues its ordinary strike without charging")
	_finish_dash_for_input_test()
	player._try_consume_queued_attack()
	_check(not player.queued_attack_after_dash and is_zero_approx(motion.charge_hold), "A still-held queued strike starts Blast charge at the actual attack, with no earlier hold time")
	await _release_actions()
	_free_world()

func _test_real_anchor_geometry() -> void:
	_make_world()
	player.apply_trial_power("razor_orbit")
	var target := _enemy(Vector2(160.0, 0.0))
	await physics_frame
	_check(player.arcana_motion.find_anchor(target.global_position) == target, "Actual geometry selects the cursor-indicated living foe")
	_check(player.arcana_motion.find_anchor(Vector2(-130.0, 100.0)) == null, "Empty cursor aim does not fall back to a nearby foe")
	var front_enemy := _enemy(Vector2(65.0, 0.0))
	await _release_actions()
	_check(player.arcana_motion.find_anchor(target.global_position) == target, "An intentionally aimed foe can be grappled through another combat enemy")
	front_enemy.remove_from_group("enemies")
	front_enemy.add_to_group("combat_players")
	_check(player.arcana_motion.find_anchor(target.global_position) == target, "A teammate on the aim line cannot block grapple targeting")
	front_enemy.free()
	target.global_position = Vector2(275.0, 0.0)
	await physics_frame
	_check(player.arcana_motion.find_anchor(target.global_position) == null, "L1 rejects an anchor beyond 260px")
	player.apply_trial_power("razor_orbit")
	_check(player.arcana_motion.find_anchor(target.global_position) == target, "L2 reach growth changes actual anchor acquisition")
	target.global_position = Vector2(160.0, 0.0)
	var occluder := _column(Vector2(80.0, 0.0))
	await physics_frame
	_check(player.arcana_motion.find_anchor(target.global_position) == null, "Solid cover blocks a grapple to an enemy behind it")
	_check(player.arcana_motion.find_anchor(occluder.global_position) == occluder, "L2 can deliberately anchor the visible column")
	player.razor_orbit_stacks = 1
	_check(player.arcana_motion.find_anchor(occluder.global_position) == null, "L1 cannot anchor a column")
	player.razor_orbit_stacks = 2
	_check(player.arcana_motion.find_anchor(occluder.global_position, true) == null, "Kill-transfer acquisition excludes environmental anchors")
	occluder.free()
	target.health_state.current_health = 0
	await physics_frame
	_check(player.arcana_motion.find_anchor(target.global_position) == null, "A dead foe cannot be acquired")
	await _release_actions()
	_free_world()

func _test_live_camera_aim_capture() -> void:
	_make_world("bastion", false, true)
	player.apply_trial_power("razor_orbit")
	var live_enemy := (load("res://scenes/Enemy.tscn") as PackedScene).instantiate() as CharacterBody2D
	live_enemy.set_script(load("res://scripts/enemy_chaser.gd"))
	world.add_child(live_enemy)
	live_enemy.global_position = Vector2(150.0, 0.0)
	live_enemy.set_physics_process(false)
	var camera := player.get_node("Camera2D") as Camera2D
	camera.set_physics_process(false)
	camera.zoom = Vector2(1.35, 1.35)
	camera.force_update_scroll()
	await _release_actions()
	var motion := _use_pointer_motion()
	motion.viewport_pointer = world.get_global_transform_with_canvas() * live_enemy.global_position
	_check(motion._orbit_aim_world_position().distance_to(live_enemy.global_position) < 1.0, "Live Player scene converts the aimed viewport pointer into the enemy's world position")
	_check(motion.find_anchor(motion._orbit_aim_world_position()) == live_enemy, "Real Enemy scene collision layers allow a deliberate aim before dashing")
	_start_dash()
	for _frame in range(40):
		await physics_frame
		player._update_dash_phase_state(1.0 / 60.0)
		player.arcana_motion.tick(1.0 / 60.0)
		if player.arcana_motion.motion == MOTION.Motion.ORBIT:
			break
		player._process_active_dash(1.0 / 60.0)
		camera.call("_physics_process", 1.0 / 60.0)
		camera.force_update_scroll()
	_check(motion._orbit_aim_world_position().distance_to(live_enemy.global_position) > 49.0, "The real follow camera moves the world beneath a stationary aimed pointer during a dash")
	_check(player.arcana_motion.motion == MOTION.Motion.ORBIT and player.arcana_motion.anchor == live_enemy, "A deliberate pre-dash aim survives camera motion until the held dash can enter Orbit")
	var orbit_position := player.global_position
	var health_before := int(live_enemy.get_current_health())
	for _frame in range(16):
		await physics_frame
		player._update_dash_phase_state(1.0 / 60.0)
		motion.tick(1.0 / 60.0)
		motion.process_movement(1.0 / 60.0, Vector2.UP)
	_check(motion.motion == MOTION.Motion.ORBIT and player.global_position.distance_to(orbit_position) > 30.0, "Captured live-scene target produces sustained Orbit movement after the dash")
	_check(int(live_enemy.get_current_health()) < health_before, "Actual-scene Orbit movement cuts its live target")
	_check(not player.dash_phasing_active and player._dash_damage_immune_left <= 0.0, "Sustained Orbit does not prolong ordinary dash immunity")
	await _release_actions()
	_free_world()

func _use_pointer_motion() -> PointerMotion:
	player.arcana_motion.free()
	var motion := PointerMotion.new()
	player.add_child(motion)
	motion.initialize(player)
	motion.set_process(false)
	player.arcana_motion = motion
	return motion

func _test_captured_anchor_gates() -> void:
	for invalidation in ["range", "wall", "death", "freed", "cancel", "empty"]:
		_make_world()
		player.apply_trial_power("razor_orbit")
		var target := _enemy(Vector2(140.0, 0.0))
		var motion := _use_pointer_motion()
		motion.viewport_pointer = target.global_position if invalidation != "empty" else Vector2(-500.0, 200.0)
		await _release_actions()
		_start_dash()
		if invalidation != "empty":
			_check(motion._pending_orbit_anchor == target, "%s fixture captures only the explicitly aimed target on accepted press" % invalidation)
		motion.viewport_pointer = Vector2(-500.0, 200.0)
		match invalidation:
			"range": target.global_position = Vector2(400.0, 0.0)
			"wall": _column(Vector2(70.0, 0.0), 22.0)
			"death": target.health_state.current_health = 0
			"freed": target.free()
			"cancel": player.discard_pending_combat_input()
		await physics_frame
		_finish_dash_for_input_test()
		_tick_hold(0.40)
		_check(motion.motion == MOTION.Motion.NONE, "%s cannot bypass live range, cover, life or input validity through a captured target" % invalidation)
		if invalidation == "cancel":
			_check(motion._pending_orbit_anchor == null and motion.dash_hold < 0.0, "Modal cancellation discards the captured grapple target and request")
		_tick_hold(0.40)
		motion.viewport_pointer = Vector2(140.0, 0.0)
		motion.tick(0.1)
		_check(motion.motion == MOTION.Motion.NONE and motion.dash_hold < 0.0, "%s cannot acquire a late target after the hold window expires" % invalidation)
		await _release_actions()
		_free_world()

func _test_collision_and_immunity() -> void:
	_make_world()
	player.apply_trial_power("blast_drive")
	player.apply_trial_power("razor_orbit")
	player.arcana_motion._refresh_capacity()
	_column(Vector2(-70.0, 0.0), 20.0)
	await physics_frame
	player.arcana_motion.release_blast(1.0)
	for step in range(20):
		player.arcana_motion.process_movement(0.025, Vector2.ZERO)
		if not player.arcana_motion.owns_movement():
			break
	_check(player.global_position.x > -40.0 and player.global_position.x < -5.0, "Blast recoil stops at real solid geometry without tunnelling")
	_check(not player.arcana_motion.owns_movement(), "Blocked recoil relinquishes movement")
	var target := _enemy(Vector2(65.0, 0.0))
	player.global_position = Vector2.ZERO
	await physics_frame
	Input.action_press("dash")
	player.arcana_motion.start_orbit(target)
	player.dash_remaining_distance = 0.0
	player.dash_phase_release_left = 0.10
	player._dash_damage_immune_left = 0.10
	for step in range(12):
		player._update_dash_phase_state(0.025)
		player.arcana_motion.tick(0.025)
		player.arcana_motion.process_movement(0.025, Vector2.UP)
	_check(player._dash_damage_immune_left == 0.0, "Orbit cannot extend the preceding dash's damage immunity")
	_check(not player._is_dash_active(), "Orbit movement never masquerades as another normal dash")
	var health_before := player.get_current_health()
	player.take_damage(12, {"source": "enemy_ability", "ability": "test_hazard"})
	_check(player.get_current_health() < health_before, "Ordinary hazards still damage the orbiting player")
	player.arcana_motion.cancel()
	player.global_position = Vector2.ZERO
	target.global_position = Vector2(80.0, 0.0)
	_column(Vector2(15.0, -48.0), 10.0)
	await physics_frame
	player.arcana_motion.start_orbit(target)
	for step in range(10):
		player.arcana_motion.process_movement(0.025, Vector2.UP)
		if not player.arcana_motion.owns_movement():
			break
	_check(not player.arcana_motion.owns_movement(), "An obstructed orbit stops safely instead of clipping through solid cover")
	_check(player.global_position.y > -40.0, "Orbit remains on the near side of the blocking column")
	await _release_actions()
	_free_world()

func _test_carry_hitch_bound() -> void:
	_make_world()
	await physics_frame
	var motion := player.arcana_motion
	motion.tangent = Vector2.RIGHT
	motion.detach(true)
	var carry_speed := minf(MOTION.ORBIT_SPEED, player.max_speed * 1.5)
	motion.process_movement(0.05, Vector2.ZERO)
	_check(is_equal_approx(player.global_position.x, carry_speed * 0.05), "Carry advances normally before a hitch")
	motion.process_movement(0.75, Vector2.ZERO)
	_check(absf(player.global_position.x - carry_speed * 0.15) < 0.01 and motion.carry_left == 0.0, "A long frame moves only the remaining carry duration")
	var end_position := player.global_position
	_check(not motion.process_movement(0.05, Vector2.ZERO) and player.global_position == end_position, "Expired carry cannot move the player again")
	await _release_actions()
	_free_world()

func _test_orbit_attack_and_blast_detach() -> void:
	_make_world()
	player.apply_trial_power("blast_drive")
	player.apply_trial_power("razor_orbit")
	var target := _enemy(Vector2(80.0, 0.0))
	await _release_actions()
	Input.action_press("dash")
	player.arcana_motion.start_orbit(target)
	var origin := player.global_position
	player.arcana_motion.process_movement(0.025, Vector2.UP)
	_check(player.global_position.distance_to(origin) > 1.0, "Orbit owns real player movement")
	var health_before := target.get_current_health()
	_ready_attack()
	_check(target.get_current_health() < health_before, "A manual primary strike still hits while orbiting")
	_check(player.arcana_motion.motion == MOTION.Motion.ORBIT and player.attack_lock_time_left == 0.0, "Manual attacks do not stall or cancel orbit movement")
	_tick_hold(0.66)
	Input.action_release("attack")
	player.arcana_motion.tick(0.01)
	_check(player.blast_releases == 1 and player.arcana_motion.motion == MOTION.Motion.RECOIL and player.arcana_motion.anchor == null, "Charged Blast release explicitly detaches Orbit before recoil")
	_check(player.arcana_motion.dash_hold < 0.0, "Still-held Dash cannot immediately reacquire after Blast detach")
	player.arcana_motion.cancel()
	await _release_actions()
	_free_world()

func _test_upgrade_and_snapshot_parity() -> void:
	for character_id in CHARACTER.get_launch_character_ids():
		_make_world(character_id)
		for power_id in ["blast_drive", "razor_orbit"]:
			for level in range(3):
				player.apply_trial_power(power_id)
			player.apply_trial_power(power_id)
		player.arcana_motion._refresh_capacity()
		_check(player.arcana_motion.blast_charges == 2, "%s receives L2's two-charge capacity" % character_id)
		_check(is_equal_approx(player.blast_drive_damage_scale, 1.56) and is_equal_approx(player.razor_orbit_reach_scale, 1.56), "%s receives actual Prismatic runtime scales" % character_id)
		var before_snapshot := player.build_run_snapshot()
		_ready_attack()
		_tick_hold(0.66)
		Input.action_release("attack")
		player.arcana_motion.tick(0.01)
		_check(player.blast_releases == 1, "%s can activate Blast through its real primary hold/release input" % character_id)
		var recoil_origin := player.global_position
		player.arcana_motion.process_movement(0.025, Vector2.UP)
		_check(player.global_position.distance_to(recoil_origin) > 0.0, "%s can use real Blast propulsion" % character_id)
		_check(absf(player.arcana_motion.recoil_initial_direction.angle_to(player.arcana_motion.recoil_direction)) <= PI / 4.0 + 0.001, "%s L3 recoil steering stays bounded" % character_id)
		_check(absf(player.arcana_motion.recoil_initial_direction.angle_to(player.arcana_motion.recoil_direction)) > 0.10, "%s L3 unlock actually enables steering" % character_id)
		player.apply_run_snapshot(before_snapshot)
		_check(player.blast_drive_stacks == 3 and player.razor_orbit_stacks == 3, "%s snapshot restores both Arcana levels" % character_id)
		_check(player.has_trial_power_prismatic("blast_drive") and player.has_trial_power_prismatic("razor_orbit"), "%s snapshot restores both Prismatic states" % character_id)
		_check(player.arcana_motion.charge_hold < 0.0 and not player.arcana_motion.owns_movement(), "%s snapshot discards transient holds and motion" % character_id)
		_check(is_equal_approx(player.blast_drive_reach_scale, 1.56) and is_equal_approx(player.razor_orbit_damage_scale, 1.56), "%s snapshot preserves both applied scales" % character_id)
		await _release_actions()
		_free_world()

func _trace_orbit(motion: MOTION, target: Node2D, move_inputs: Array[Vector2], sample_count: int = 60) -> Dictionary:
	var initial_sign := motion.orbit_sign
	var previous_radial := player.global_position - target.global_position
	var winding := 0.0
	var reversed := false
	var sign_changed := false
	var last_displacement := Vector2.ZERO
	for index in range(sample_count):
		var start := player.global_position
		motion.tick(0.02)
		motion.process_movement(0.02, move_inputs[int(index / 12) % move_inputs.size()])
		var radial := player.global_position - target.global_position
		var angle := previous_radial.angle_to(radial)
		reversed = reversed or angle * initial_sign < -0.001
		sign_changed = sign_changed or motion.orbit_sign != initial_sign
		winding += angle * initial_sign
		last_displacement = player.global_position - start
		previous_radial = radial
		if motion.motion != MOTION.Motion.ORBIT:
			break
	return {"winding": winding, "reversed": reversed, "sign_changed": sign_changed, "last_displacement": last_displacement}

func _test_fixed_orbit_direction() -> void:
	var input_cases: Array[Array] = [[Vector2.UP], [Vector2.LEFT], [Vector2.DOWN], [Vector2.RIGHT], [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.ZERO]]
	for sense in [-1.0, 1.0]:
		for input_index in range(input_cases.size()):
			_make_world("bastion", true)
			player.apply_trial_power("razor_orbit")
			# This fixture begins on the intended 90 px orbit, so the first movement
			# can be compared directly to its accepted tangential entry dash.
			player.attack_range = 100.0
			player.global_position = Vector2(90.0, 0.0)
			var target := _enemy(Vector2.ZERO)
			var motion := player.arcana_motion as AimMotion
			motion.aimed_anchor = target
			await _release_actions()
			var entry_dash := Vector2(0.0, sense)
			Input.action_press("dash")
			player._try_start_dash(entry_dash)
			_check(player._is_dash_active(), "Direction fixture uses an accepted entry dash")
			_finish_dash_for_input_test()
			motion.start_orbit(target)
			var start := player.global_position
			motion.process_movement(0.01, Vector2.ZERO)
			_check((player.global_position - start).normalized().dot(entry_dash) > 0.95, "First circular displacement follows entry dash sense %s" % sense)
			var move_inputs: Array[Vector2] = []
			move_inputs.assign(input_cases[input_index])
			var trace := _trace_orbit(motion, target, move_inputs)
			_check(not trace["reversed"] and not trace["sign_changed"] and trace["winding"] > TAU and motion.motion == MOTION.Motion.ORBIT, "Orbit completes a continuous full circle for sense %s input case %d without input-driven reversal" % [sense, input_index])
			var last_displacement: Vector2 = trace["last_displacement"]
			Input.action_release("dash")
			motion.tick(0.001)
			_check(motion.motion == MOTION.Motion.CARRY and motion.anchor == null, "Releasing Dash still detaches the fixed-direction orbit")
			start = player.global_position
			motion.process_movement(0.02, Vector2.ZERO)
			_check((player.global_position - start).normalized().dot(last_displacement.normalized()) > 0.95, "Release carry continues the last circular displacement instead of reversing")
			motion.process_movement(0.20, Vector2.ZERO)
			_check(not motion.owns_movement(), "Fixed-direction detach still ends after bounded carry")
			await _release_actions()
			_free_world()

func _test_transfer_direction() -> void:
	for sense in [-1.0, 1.0]:
		_make_world("bastion", true)
		for _level in range(3):
			player.apply_trial_power("razor_orbit")
		player.attack_range = 100.0
		player.global_position = Vector2(90.0, 0.0)
		var first := _enemy(Vector2.ZERO)
		var second := _enemy(Vector2(0.0, 260.0))
		var motion := player.arcana_motion as AimMotion
		motion.aimed_anchor = first
		await _release_actions()
		Input.action_press("dash")
		player._try_start_dash(Vector2(0.0, sense))
		_finish_dash_for_input_test()
		motion.start_orbit(first)
		var original_sign := motion.orbit_sign
		_trace_orbit(motion, first, [Vector2.LEFT], 12)
		first.health_state.set_health(0)
		second.global_position = player.global_position - Vector2(90.0, 0.0)
		motion.aimed_anchor = second
		await physics_frame
		await process_frame
		motion.process_movement(0.02, Vector2.UP)
		_check(motion.anchor == second and motion.orbit_transferred and motion.orbit_sign == original_sign, "L3 transfer retains its original angular sense %s" % sense)
		var trace := _trace_orbit(motion, second, [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT], 40)
		_check(not trace["reversed"] and not trace["sign_changed"] and trace["winding"] > PI and motion.motion == MOTION.Motion.ORBIT, "Changing movement input after L3 transfer cannot reverse the new circle")
		Input.action_release("dash")
		motion.tick(0.001)
		_check(motion.anchor == null and motion.motion == MOTION.Motion.CARRY, "Release also detaches a transferred fixed-direction orbit")
		await _release_actions()
		_free_world()

func _test_contact_cadence_and_transfer() -> void:
	_make_world("bastion", true)
	for level in range(3):
		player.apply_trial_power("razor_orbit")
	var first := _enemy(Vector2(50.0, 0.0))
	var second := _enemy(Vector2(60.0, 20.0))
	var motion := player.arcana_motion as AimMotion
	await _release_actions() # Flush initial collider transforms before swept movement.
	Input.action_press("dash")
	motion.start_orbit(first)
	var first_before := first.get_current_health()
	var second_before := second.get_current_health()
	motion._apply_cut_contacts(Vector2.ZERO, Vector2(5.0, 0.0))
	var first_damage := first_before - first.get_current_health()
	_check(first_damage > 0 and second.get_current_health() < second_before, "Orbit cuts apply independently to each contacted enemy")
	motion._apply_cut_contacts(Vector2.ZERO, Vector2(5.0, 0.0))
	_check(first_before - first.get_current_health() == first_damage, "Repeated contacts in one window cannot multiply damage")
	motion.tick(0.29)
	motion._apply_cut_contacts(Vector2.ZERO, Vector2(5.0, 0.0))
	_check(first_before - first.get_current_health() == first_damage, "Contact cooldown lasts the full 0.30 seconds")
	motion.tick(0.02)
	motion._apply_cut_contacts(Vector2.ZERO, Vector2(5.0, 0.0))
	_check(first_before - first.get_current_health() == first_damage * 2, "A new contact window permits one new cut")
	motion.aimed_anchor = second
	first.health_state.current_health = 0
	motion.process_movement(0.025, Vector2.ZERO)
	_check(motion.anchor == second and motion.orbit_transferred, "L3 transfers once to the explicitly aimed foe when its anchor dies (motion=%d, transferred=%s, attempts=%d)" % [motion.motion, motion.orbit_transferred, motion.acquisition_attempts])
	_check(motion.orbit_limit <= 2.4, "Transfer cannot make the total orbit unbounded")
	second.health_state.current_health = 0
	motion.aimed_anchor = _enemy(Vector2(65.0, -20.0))
	motion.process_movement(0.025, Vector2.ZERO)
	_check(motion.motion != MOTION.Motion.ORBIT, "A second anchor death detaches instead of chaining forever")
	await _release_actions()
	_free_world()
