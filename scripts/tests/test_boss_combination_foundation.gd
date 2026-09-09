extends SceneTree
## Small lifecycle checks independent of the player integration suites.

const LAUNCH := preload("res://scripts/enemy_launch_state.gd")
const COMBINATIONS := preload("res://scripts/boss_combination_controller.gd")

class TestEnemy extends "res://scripts/enemy_base.gd":
	var launch := LAUNCH.new()
	func _ready() -> void:
		max_health = 1000
		_create_health_state()
		set_physics_process(false)
		add_to_group("enemies")
	func get_launch_state() -> LAUNCH:
		return launch

class TestOwner extends CharacterBody2D:
	var ruinous_impact_stacks: int = 1
	var sovereigns_double_stacks: int = 2
	var combat_damage_enabled: bool = true
	var encounter_input_frozen: bool = false
	var _is_alive_state: bool = true
	var player_feedback: Node = null
	var damage: int = 40
	var cues: Array[Dictionary] = []
	func _apply_objective_mutator_damage_mult(amount: int) -> int:
		return amount
	func _broadcast_cue_event(event_name: String, payload: Dictionary, _reliable: bool = false) -> void:
		cues.append({"name": event_name, "payload": payload.duplicate(true)})
	func _is_local_control_owner() -> bool:
		return true
	func _capture_combat_action(_kind: String) -> Dictionary:
		# This fixture isolates launch ownership; interaction roots are exercised
		# by the production Player and shared-engine integration suites.
		return {}

var checks: int = 0
var failures: Array[String] = []
var bursts: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _burst(_position: Vector2) -> void:
	bursts += 1

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Run foundation checks only in an isolated validation project")
		quit(1)
		return
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var enemy := TestEnemy.new()
	enemy.collision_layer = 0
	enemy.collision_mask = 0
	var collision := CollisionShape2D.new()
	collision.shape = CircleShape2D.new()
	enemy.add_child(collision)
	world.add_child(enemy)
	await physics_frame
	var state: LAUNCH = enemy.launch
	_check(not state.arm(Vector2.INF, false, 1, 1, _burst), "Nonfinite launches are rejected")
	_check(state.arm(Vector2(1000.0, 0.0), false, 1, 1, _burst), "A finite launch arms")
	_check(state.step(enemy, 0.20), "Active launch replaces ordinary enemy movement")
	_check(state.step(enemy, 0.80), "The final movement step remains authoritative during a hitch")
	_check(is_equal_approx(enemy.position.x, 240.0), "A one-second hitch cannot exceed 750 speed times 0.32-second lifetime")
	_check(not state.active and enemy.velocity == Vector2.ZERO, "Expiry clears launch and velocity")
	_check(not state.arm(Vector2.RIGHT, false, 1, 1, _burst), "Launch cooldown survives movement expiry")
	state.step(enemy, 0.11)
	_check(state.arm(Vector2.RIGHT * 600.0, true, 1, 1, _burst), "Compression can arm after cooldown")
	var before := enemy.position
	_check(not state.step(enemy, 0.30), "Compression never replaces boss AI movement")
	_check(enemy.position == before and bursts == 1, "Compression bursts once without displacement")
	state.step(enemy, 0.30)
	_check(bursts == 1, "A completed compression cannot burst again")
	state.cooldown_left = 0.0
	state.arm(Vector2.RIGHT * 600.0, true, 1, 1, _burst)
	enemy.health_state.current_health = 0
	state.step(enemy, 0.30)
	_check(not state.active and bursts == 1, "Enemy death cancels a pending burst")
	enemy.health_state.current_health = 1000
	var owner := TestOwner.new()
	world.add_child(owner)
	var controller := COMBINATIONS.new()
	owner.add_child(controller)
	controller.initialize(owner)
	controller.set_process(false)
	controller.hide()
	for index in range(100):
		state.cancel()
		state.cooldown_left = 0.0
		controller.launch_enemy(enemy, Vector2.RIGHT * 400.0, 1)
	_check(controller._launch_targets.size() == 1, "Repeated launches retain one weak reference per living enemy")
	state.cancel()
	controller.tick(0.0)
	_check(controller._launch_targets.is_empty(), "Inactive launch references are pruned")
	state.cooldown_left = 0.0
	controller.launch_enemy(enemy, Vector2.RIGHT * 400.0, 1)
	state.owner_id = owner.get_instance_id() + 1
	controller.tick(0.0)
	_check(controller._launch_targets.is_empty() and state.active, "Ownership changes drop stale tracking without canceling another player's launch")
	state.cancel()
	controller.create_shade(Vector2(100.0, 20.0))
	_check(controller.shade_hits == 2, "Level two shade begins with two echoes")
	controller.cancel()
	var last_cue: Dictionary = owner.cues.back()
	_check(last_cue.name == "sovereign_double_shade" and last_cue.payload.hits == 0 and last_cue.payload.life == 0.0, "Cancellation broadcasts the cleared shade immediately")
	current_scene = null
	world.free()
	await process_frame
	print("[OK] Boss combination foundation: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
