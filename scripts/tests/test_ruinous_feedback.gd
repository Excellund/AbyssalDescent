extends SceneTree

const FIXTURE := preload("res://scripts/tests/test_boss_combinations_enet.gd")
const BOSS_FIXTURE := preload("res://scripts/tests/test_boss_combinations.gd")
const FEEDBACK := preload("res://scripts/ruinous_impact_feedback.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")

var checks: int = 0
var failures: Array[String] = []
var world: FIXTURE.World
var player: FIXTURE.Player

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _circle(body: CollisionObject2D, radius: float = 13.0) -> void:
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	(shape.shape as CircleShape2D).radius = radius
	body.add_child(shape)

func _run() -> void:
	world = FIXTURE.World.new()
	root.add_child(world)
	current_scene = world
	EnemyReplicationService.bind_world(world)
	world._world_multiplayer_sync_state.current_room_sync_id = 12
	player = FIXTURE.Player.new()
	_circle(player)
	world.add_child(player)
	world.player = player
	player.player_id = 1
	player.damage = 20
	player.global_position = Vector2(-200.0, 0.0)
	player.apply_upgrade("ruinous_impact")
	var enemy := FIXTURE.Enemy.new()
	_circle(enemy)
	world.add_child(enemy)
	enemy.global_position = Vector2(100.0, 0.0)
	EnemyReplicationService.enemy_nodes_by_id[101] = enemy
	enemy.set_meta("network_enemy_id", 101)
	player.boss_combinations.launch_enemy(enemy, Vector2(450.0, 100.0), 1)
	var state := enemy.get_launch_state()
	var feedback: FEEDBACK = EnemyReplicationService._ruinous_feedback
	feedback.set_process(false)
	feedback._impact_sound.stream = null
	check(state.active and not state.compression, "An ordinary launch keeps its existing movement state")
	check(feedback.launches.size() == 1 and feedback.bursts.is_empty(), "A launch creates one attached cue without a premature explosion")
	var serial := int(feedback.launches.keys().front())
	var cue: Dictionary = feedback.launches[serial]
	check((cue.target as WeakRef).get_ref() == enemy and Vector2(cue.direction).is_equal_approx(Vector2(450.0, 100.0).normalized()), "The cue tracks the launched actor and actual impulse direction")
	var paused_left := float(cue.left)
	feedback._process(0.20)
	check(is_equal_approx(float(cue.left), paused_left), "Pause does not consume an enemy's launch indicator")
	enemy.set_physics_process(true)
	feedback._process(0.05)
	enemy.set_physics_process(false)
	check(is_equal_approx(float(cue.left), paused_left - 0.05), "The launch indicator advances again with enemy physics")
	state.cancel()
	check(feedback.launches.is_empty() and feedback.bursts.is_empty(), "Cancel removes the cue immediately without inventing a burst")
	check(state.ended.get_connections().is_empty(), "The per-launch visual connection is released after cancel")
	state.cancel()
	check(feedback.launches.is_empty(), "Repeated cancellation is harmless")

	var boss := BOSS_FIXTURE.ComboBoss.new()
	_circle(boss, 36.0)
	world.add_child(boss)
	boss.global_position = Vector2(350.0, 50.0)
	player.boss_combinations.launch_enemy(boss, Vector2.RIGHT * 450.0, 1)
	var boss_state := boss.get_launch_state()
	check(boss_state.active and boss_state.compression, "An immovable boss still compresses rather than moving")
	var compression: Dictionary = feedback.launches.values().front()
	check(compression.compression and is_equal_approx(float(compression.duration), 0.16), "Compression brackets use the real existing delay")
	var boss_origin := boss.global_position
	var boss_health := boss.get_current_health()
	boss_state.step(boss, 0.16)
	check(boss.global_position == boss_origin and boss.get_current_health() == boss_health - 20, "Compression still deals one existing-strength burst without displacing the boss")
	check(feedback.launches.is_empty() and feedback.bursts.size() == 1, "Compression ends before displaying its one explosion")
	var burst: Dictionary = feedback.bursts.front()
	check(burst.position == boss_origin and burst.radius == 70.0, "The stationary burst contour receives the exact damage origin and radius")
	check(not boss_state.active and not state.active, "Visual feedback cannot recursively arm launches")
	feedback._process(FEEDBACK.BURST_LIFETIME + 0.01)
	check(feedback.bursts.is_empty(), "Completed damage feedback expires within its short lifetime")

	state.cooldown_left = 0.0
	player.boss_combinations.launch_enemy(enemy, Vector2.RIGHT * 450.0, 1)
	player.discard_pending_combat_input()
	check(not state.active and feedback.launches.is_empty(), "Input/phase cancellation clears the live launch and its attached cue")
	for index in range(FEEDBACK.MAX_LAUNCHES + 5):
		feedback.show_launch(1000 + index, enemy, Vector2.RIGHT, false, 0.32)
	check(feedback.launches.size() == FEEDBACK.MAX_LAUNCHES, "Crowded launches have a fixed presentation cap")
	for index in range(FEEDBACK.MAX_BURSTS + 5):
		feedback.show_burst(Vector2(index, 0.0), 95.0, Vector2.RIGHT, -80.0)
	check(feedback.bursts.size() == FEEDBACK.MAX_BURSTS, "Crowded impacts have a fixed presentation cap")
	feedback.launches.clear()
	feedback.bursts.clear()
	feedback.show_launch(0, enemy, Vector2.RIGHT, false, 0.32)
	feedback.show_launch(2, enemy, Vector2.INF, false, 0.32)
	feedback.show_burst(Vector2.INF, 70.0, Vector2.RIGHT, 0.0)
	feedback.show_burst(Vector2.ZERO, -1.0, Vector2.RIGHT, 0.0)
	check(feedback.launches.is_empty() and feedback.bursts.is_empty(), "Invalid event geometry does not create a cue")

	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = false
	MultiplayerSessionManager.local_peer_id = 2
	check(EnemyReplicationService.broadcast_ruinous_launch(enemy, Vector2.RIGHT, false, 0.32) == 0, "A joiner cannot originate enemy launch feedback")
	EnemyReplicationService.broadcast_ruinous_burst(Vector2.ZERO, 70.0, Vector2.RIGHT)
	check(feedback.bursts.is_empty(), "A joiner cannot originate an authoritative impact")
	var payload := {"kind": "burst", "position": Vector2(45.5, 80.25), "radius": 95.0, "direction": Vector2.UP}
	EnemyReplicationService._sync_ruinous_feedback(payload, 11)
	check(feedback.bursts.is_empty(), "A stale room cannot display a previous encounter's burst")
	EnemyReplicationService._sync_ruinous_feedback(payload, 12)
	check(feedback.bursts.size() == 1 and feedback.bursts.front().position == payload.position, "The current room receives the host's exact burst geometry")
	EnemyReplicationService._sync_ruinous_feedback({"kind": "launch", "serial": 2000, "enemy": 101, "direction": Vector2.UP, "compression": false, "duration": 0.32}, 12)
	check(feedback.launches.has(2000) and not state.active, "Remote launch presentation never activates enemy simulation")
	EnemyReplicationService._sync_ruinous_feedback({"kind": "finish", "serial": 2000}, 12)
	check(feedback.launches.is_empty(), "The host's finish event clears a remote launch cue")
	MultiplayerSessionManager.session_connected = false
	MultiplayerSessionManager.is_host_peer = true
	EnemyReplicationService.clear_state()
	check(feedback.is_queued_for_deletion() and EnemyReplicationService._ruinous_feedback == null, "Room cleanup releases the entire transient feedback layer")
	EnemyReplicationService.unbind_world(world)
	if is_instance_valid(player.upgrade_system.power_registry):
		player.upgrade_system.power_registry.free()
	world.free()
	current_scene = null
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await create_timer(0.15).timeout
	print("[OK] Ruinous feedback: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
