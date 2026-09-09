extends SceneTree

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const PLAYER_REPLICATION := preload("res://scripts/player_replication_service.gd")

class LaunchRecorder extends Node:
	var launches: Array[Dictionary] = []
	func launch_enemy(enemy: CharacterBody2D, impulse: Vector2, source_peer: int) -> void:
		launches.append({"enemy": enemy, "impulse": impulse, "peer": source_peer})

class FeedbackOptions extends Node:
	var sfx_volume_db: float = -80.0

class CombatOwner extends CharacterBody2D:
	var player_id: int = 0
	var visual_facing_direction := Vector2.RIGHT
	var boss_combinations := LaunchRecorder.new()
	var player_feedback := FeedbackOptions.new()
	var push_target: CharacterBody2D
	var kill_count := 0
	var observed_suppression := false
	func _ready() -> void:
		add_to_group("combat_players")
		add_child(boss_combinations)
		add_child(player_feedback)
	func notify_enemy_killed(_position: Vector2) -> void:
		kill_count += 1
		observed_suppression = DAMAGEABLE.is_launch_suppressed()
		if push_target != null:
			DAMAGEABLE.apply_impulse(push_target, Vector2(200.0, 0.0))

class TestEnemy extends "res://scripts/enemy_base.gd":
	func _ready() -> void:
		set_physics_process(false)
		max_health = 100
		_create_health_state()
		add_to_group("enemies")
	func _on_health_state_died() -> void:
		died.emit() # Keep the fixture available for health/accounting assertions.

class TestWorld extends Node2D:
	var damage_events: Array[Dictionary] = []
	var damage_requests: Array[Dictionary] = []
	var impulse_requests: Array[Dictionary] = []
	var _world_multiplayer_sync_state := {"current_room_sync_id": 7}
	var player: Node
	func record_player_damage_dealt(amount: int, peer: int = 0, killed: bool = false, enemy: int = 0) -> void:
		damage_events.append({"amount": amount, "peer": peer, "killed": killed, "enemy": enemy})
	func request_enemy_damage_from_client(enemy_id: int, amount: int, context: Dictionary = {}) -> void:
		damage_requests.append({"enemy": enemy_id, "amount": amount, "context": context})
	func request_enemy_impulse_from_client(enemy_id: int, impulse: Vector2, suppress_launch: bool = false, _interaction: Dictionary = {}) -> void:
		impulse_requests.append({"enemy": enemy_id, "impulse": impulse, "suppressed": suppress_launch})

var checks := 0
var failures: Array[String] = []
var world: TestWorld
var host: CombatOwner
var joiner: CombatOwner

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _enemy(id: int = 0) -> TestEnemy:
	var enemy := TestEnemy.new()
	world.add_child(enemy)
	if id > 0:
		enemy.set_meta("network_enemy_id", id)
	return enemy

func _run() -> void:
	world = TestWorld.new()
	root.add_child(world)
	current_scene = world
	host = CombatOwner.new()
	host.player_id = 1
	world.add_child(host)
	world.player = host
	joiner = CombatOwner.new()
	joiner.player_id = 2
	world.add_child(joiner)
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = true
	_test_accepted_primary_ownership()
	_test_secondary_kill_and_push()
	_test_remote_routing()
	_test_authority_feedback()
	MultiplayerSessionManager.session_connected = false
	MultiplayerSessionManager.is_host_peer = false
	EnemyReplicationService.unbind_world(world)
	EnemyReplicationService.clear_state()
	current_scene = null
	world.free()
	await process_frame
	print("[LaunchAuthority] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_accepted_primary_ownership() -> void:
	var enemy := _enemy(21)
	enemy.position = Vector2(100.0, 0.0)
	for source in ["melee", "razor_wind", "blast_drive"]:
		var before := joiner.boss_combinations.launches.size()
		DAMAGEABLE.apply_damage(enemy, 5, {"attack_type": source}, 2)
		_check(joiner.boss_combinations.launches.size() == before + 1, "Accepted %s arms the actual joiner owner's launch on the host" % source)
		_check(joiner.boss_combinations.launches.back()["peer"] == 2 and host.boss_combinations.launches.is_empty(), "Launch ownership never falls back to host player")
	_check(EnemyReplicationService.killer_peer_for(21) == 2 and world.damage_events.back()["peer"] == 2, "Accepted damage and launch use the same peer attribution")
	var accepted := joiner.boss_combinations.launches.size()
	enemy.damage_blocked = true
	DAMAGEABLE.apply_damage(enemy, 10, {"attack_type": "melee"}, 2)
	_check(joiner.boss_combinations.launches.size() == accepted, "Rejected primary damage cannot arm a launch")
	enemy.damage_blocked = false
	for context in [{"attack_type": "sovereigns_double", "secondary": true}, {"attack_type": "ruinous_impact", "secondary": true}, {"attack_type": "melee", "secondary": true}, {"attack_type": "dash"}]:
		DAMAGEABLE.apply_damage(enemy, 1, context, 2)
	_check(joiner.boss_combinations.launches.size() == accepted and not DAMAGEABLE.is_launch_suppressed(), "Secondary/dash damage cannot arm launches or leave suppression active")
	DAMAGEABLE.apply_damage(enemy, 1, {"attack_type": "melee"}, 99)
	_check(joiner.boss_combinations.launches.size() == accepted, "Unknown peer cannot borrow another player's launch reward")
	DAMAGEABLE.apply_impulse(enemy, Vector2(300.0, 0.0), 2)
	_check(joiner.boss_combinations.launches.size() == accepted + 1 and enemy.velocity.x == 300.0, "Authenticated joiner push applies host movement and owned launch")
	DAMAGEABLE.apply_impulse(enemy, Vector2(100.0, 0.0), 2, true)
	_check(joiner.boss_combinations.launches.size() == accepted + 1 and enemy.velocity.x == 400.0, "Suppressed push retains physical displacement without rearming")
	DAMAGEABLE.apply_damage(enemy, 1000, {"attack_type": "melee"}, 2)
	_check(joiner.boss_combinations.launches.size() == accepted + 1 and world.damage_events.back()["killed"], "Lethal primary still records a kill without launching the corpse")

func _test_secondary_kill_and_push() -> void:
	var service := PLAYER_REPLICATION.new()
	service.player_nodes = {1: host, 2: joiner}
	var victim := _enemy(22)
	var pushed := _enemy(23)
	host.push_target = pushed
	var before := host.boss_combinations.launches.size()
	victim.died.connect(func(): service._apply_enemy_killed_local(1, victim.global_position, DAMAGEABLE.is_launch_suppressed()))
	DAMAGEABLE.apply_damage(victim, 1000, {"attack_type": "ruinous_impact", "secondary": true}, 1)
	_check(host.kill_count == 1 and host.observed_suppression, "Secondary kill notifies the credited player inside a suppression scope")
	_check(pushed.velocity.x == 200.0 and host.boss_combinations.launches.size() == before, "An Edict-style synchronous kill push cannot recursively arm another impact")
	_check(not DAMAGEABLE.is_launch_suppressed() and world.damage_events.back()["killed"], "Kill/stat accounting survives scope unwind")
	service._apply_enemy_killed_local(1, Vector2.ZERO, true)
	_check(host.kill_count == 2 and host.observed_suppression and host.boss_combinations.launches.size() == before, "A received remote kill flag preserves suppression through local procs")
	service._apply_enemy_killed_local(1, Vector2.ZERO, false)
	_check(host.kill_count == 3 and not host.observed_suppression and host.boss_combinations.launches.size() == before + 1, "A later ordinary kill regains normal launch behavior")
	DAMAGEABLE.begin_secondary_scope()
	DAMAGEABLE.begin_secondary_scope()
	DAMAGEABLE.end_secondary_scope()
	_check(DAMAGEABLE.is_launch_suppressed(), "Nested secondary scope cannot clear its parent's suppression")
	DAMAGEABLE.end_secondary_scope()
	_check(not DAMAGEABLE.is_launch_suppressed(), "Nested suppression returns to zero after complete unwind")
	host.push_target = null
	service.free()

func _test_remote_routing() -> void:
	MultiplayerSessionManager.is_host_peer = false
	var enemy := _enemy(24)
	var before := host.boss_combinations.launches.size() + joiner.boss_combinations.launches.size()
	DAMAGEABLE.begin_secondary_scope()
	DAMAGEABLE.apply_damage(enemy, 10, {"attack_type": "melee"})
	DAMAGEABLE.apply_impulse(enemy, Vector2(100.0, 0.0))
	DAMAGEABLE.end_secondary_scope()
	_check(enemy.get_current_health() == 100 and enemy.velocity == Vector2.ZERO, "Joiner never applies enemy health or displacement locally")
	_check(world.damage_requests.back()["context"].get("secondary", false) and world.impulse_requests.back()["suppressed"], "Nested secondary suppression crosses both client request boundaries")
	DAMAGEABLE.apply_impulse(enemy, Vector2(100.0, 0.0))
	_check(not world.impulse_requests.back()["suppressed"], "Later ordinary push request has no stale suppression")
	_check(host.boss_combinations.launches.size() + joiner.boss_combinations.launches.size() == before, "Client routing never arms local enemy launches")
	MultiplayerSessionManager.is_host_peer = true

func _test_authority_feedback() -> void:
	EnemyReplicationService.bind_world(world)
	# Offline exercises host rendering without sending packets through a real peer.
	MultiplayerSessionManager.session_connected = false
	EnemyReplicationService.broadcast_ruinous_burst(Vector2(40.0, 80.0), 90.0, Vector2.RIGHT)
	var feedback := EnemyReplicationService._ruinous_feedback
	_check(feedback.bursts.size() == 1, "Host-owned impact renders exactly once despite multiple player nodes")
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = false
	EnemyReplicationService.broadcast_ruinous_burst(Vector2.ZERO, 80.0, Vector2.RIGHT)
	_check(feedback.bursts.size() == 1, "A remote replica cannot originate host-owned impact feedback")
	var payload := {"kind": "burst", "position": Vector2(40.0, 80.0), "radius": 90.0, "direction": Vector2.RIGHT}
	EnemyReplicationService._sync_ruinous_feedback(payload, 6)
	_check(feedback.bursts.size() == 1, "Late impact feedback from another room is ignored")
	EnemyReplicationService._sync_ruinous_feedback(payload, 7)
	_check(feedback.bursts.size() == 2 and feedback.bursts.back()["position"] == Vector2(40.0, 80.0), "Host effect reaches joiner feedback with its authoritative position")
	EnemyReplicationService._sync_ruinous_feedback({"kind": "burst", "position": Vector2.INF, "radius": 90.0}, 7)
	_check(feedback.bursts.size() == 2, "Invalid visual payload cannot create an unbounded ring")
