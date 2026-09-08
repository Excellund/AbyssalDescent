extends SceneTree
## Two separate processes; production RPCs run only on a loopback ENet transport.
const DAMAGE := preload("res://scripts/shared/damageable.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const SENDER := preload("res://scripts/core/enemy_state_sync_broadcaster.gd")
const RECEIVER := preload("res://scripts/core/enemy_state_sync_receiver.gd")
const DIFFICULTY := preload("res://scripts/difficulty_config.gd")
const BLAST_EFFECT := preload("res://scripts/blast_impact_effect.gd")

class Feedback extends "res://scripts/player_feedback.gd":
	var rings: int = 0
	func play_world_ring(position: Vector2, radius: float, color: Color, lifetime: float = 0.2) -> void:
		rings += 1
		super.play_world_ring(position, radius, color, lifetime)

class Player extends "res://scripts/player.gd":
	var kill_scopes: Array[bool] = []
	var received_blasts: Array[Dictionary] = []
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _create_player_feedback() -> void:
		player_feedback = Feedback.new()
		add_child(player_feedback)
		player_feedback.setup(max_health, get_current_health())
	func notify_enemy_killed(position: Vector2 = Vector2.INF) -> void:
		kill_scopes.append(DAMAGE.is_launch_suppressed())
		super.notify_enemy_killed(position)
	func apply_network_cue_event(event_name: String, payload: Dictionary) -> void:
		super.apply_network_cue_event(event_name, payload)
		if event_name == "motion_blast" and not arcana_motion._blast_effects.is_empty():
			var effect := arcana_motion._blast_effects.back() as BLAST_EFFECT
			received_blasts.append({"position": effect.global_position, "range": effect.reach, "arc": effect.arc_degrees, "serial": effect.serial})

class Enemy extends "res://scripts/enemy_base.gd":
	func _ready() -> void:
		max_health = 100
		_create_health_state()
		add_to_group("enemies")
		set_physics_process(false)

class World extends "res://scripts/world_generator.gd":
	var harness: SceneTree
	var damage_events: Array[Dictionary] = []
	var kill_peers: Array[int] = []
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _exit_tree() -> void:
		pass
	func record_player_damage_dealt(amount: int, peer: int = 0, killed: bool = false, enemy_id: int = 0) -> void:
		damage_events.append({"amount": amount, "peer": peer, "killed": killed, "enemy": enemy_id})
	func _record_peer_enemy_kill(peer: int) -> void:
		kill_peers.append(peer)
	@rpc("any_peer", "call_remote", "reliable")
	func fixture_ready() -> void:
		harness.host_scenarios(multiplayer.get_remote_sender_id())
	@rpc("authority", "call_remote", "reliable")
	func fixture_command(command: String, payload: Dictionary = {}) -> void:
		harness.client_command(command, payload)
	@rpc("any_peer", "call_remote", "reliable")
	func fixture_result(key: String, value: Dictionary) -> void:
		harness.results[key] = value

var world: World
var peer: ENetMultiplayerPeer
var role: String
var prefix: String
var local_player: Player
var remote_player: Player
var joiner_id: int = 0
var failures: Array[String] = []
var checks: int = 0
var results: Dictionary = {}
var finished: bool = false
var deadline_timer: Timer

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or args.size() != 4:
		push_error("ENet fixture requires isolated project, role, port, and report prefix")
		quit(1)
		return
	role = args[1]
	prefix = args[3]
	world = World.new()
	world.name = "World"
	world.harness = self
	root.add_child(world)
	current_scene = world
	world.is_multiplayer = true
	world.enemy_state_sync_broadcaster = SENDER.new(world)
	world.enemy_state_sync_receiver = RECEIVER.new(world)
	world._world_multiplayer_sync_state.current_room_sync_id = 7
	EnemyReplicationService.bind_world(world)
	PlayerReplicationService.multiplayer_session_manager = MultiplayerSessionManager
	peer = ENetMultiplayerPeer.new()
	if role == "host":
		peer.set_bind_ip("127.0.0.1")
		check(peer.create_server(int(args[2]), 1) == OK, "Loopback host binds its ephemeral UDP port")
	else:
		check(peer.create_client("127.0.0.1", int(args[2])) == OK, "Joiner creates loopback ENet connection")
	get_multiplayer().multiplayer_peer = peer
	MultiplayerSessionManager._multiplayer = get_multiplayer()
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = role == "host"
	MultiplayerSessionManager.local_peer_id = get_multiplayer().get_unique_id()
	PlayerReplicationService.local_peer_id = MultiplayerSessionManager.local_peer_id
	if role == "host":
		FileAccess.open(prefix + "-ready", FileAccess.WRITE).store_string("ready")
	else:
		var connected := await until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
		check(connected, "Joiner connects to the separate host process")
		if connected:
			joiner_id = get_multiplayer().get_unique_id()
			setup_actors(joiner_id)
			world.fixture_ready.rpc_id(1)
	deadline_timer = Timer.new()
	deadline_timer.one_shot = true
	deadline_timer.wait_time = 15.0
	root.add_child(deadline_timer)
	deadline_timer.timeout.connect(_timed_out)
	deadline_timer.start()

func _timed_out() -> void:
	check(false, "Fixture completed before its 15-second deadline")
	await finish()

func until(predicate: Callable, duration: float = 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(duration * 1000.0)
	while Time.get_ticks_msec() < deadline and not finished:
		if predicate.call():
			return true
		await create_timer(0.02).timeout
	return false

func circle(body: CollisionObject2D, radius: float) -> void:
	var collision := CollisionShape2D.new()
	collision.shape = CircleShape2D.new()
	(collision.shape as CircleShape2D).radius = radius
	body.add_child(collision)

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	for id in [1, client_id]:
		var actor := Player.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.position = Vector2(-500.0, 0.0) if id == 1 else Vector2.ZERO
		actor.damage = 40
		actor.apply_upgrade("ruinous_impact")
		actor.apply_upgrade("edict_of_the_court")
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	for id in [101, 102, 103, 104]:
		var enemy := Enemy.new()
		enemy.name = "Enemy_%d" % id
		circle(enemy, 13.0)
		world.add_child(enemy)
		enemy.position = {101: Vector2(100.0, 0.0), 102: Vector2(520.0, 0.0), 103: Vector2(560.0, 0.0), 104: Vector2(110.0, -180.0)}[id]
		world.enemy_state_sync_broadcaster.register_enemy(enemy, id)
		if id == 102:
			enemy.health_state.current_health = 10
		if id == 104:
			enemy.health_state.setup(1000, 1000)
	var wall := StaticBody2D.new()
	circle(wall, 20.0)
	wall.position = Vector2(165.0, 0.0)
	world.add_child(wall)

func enemy(id: int) -> Enemy:
	return EnemyReplicationService.enemy_nodes_by_id.get(id) as Enemy

func ring_count() -> int:
	return (local_player.player_feedback as Feedback).rings + (remote_player.player_feedback as Feedback).rings

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	world.fixture_command.rpc_id(client_id, "primary")
	check(await until(func(): return enemy(101).get_current_health() == 80), "Real joiner damage RPC lowers host health once")
	var launched := enemy(101).get_launch_state()
	check(launched.active and launched.source_peer_id == client_id and launched.owner_id == remote_player.get_instance_id(), "Host launch belongs to the authenticated joiner, despite spoofed source context")
	check(world.damage_events.size() == 1 and world.damage_events[0].amount == 20, "Host accounts the primary exactly once")
	launched.step(enemy(101), 0.2)
	check(not launched.active and enemy(101).get_current_health() == 40, "Host collision produces one real Ruinous Impact burst")
	world._sync_enemy_states.rpc([{"enemy_id": 101, "health": 40, "position": enemy(101).position}], 3)
	world.fixture_command.rpc_id(client_id, "inspect_primary")
	check(await until(func(): return results.has("primary")), "Joiner confirms authoritative state and effect receipt")
	if results.has("primary"):
		var received: Dictionary = results.primary
		check(received.health == 40 and not received.launch_active and received.local_damage_events == 0, "Joiner applies synced health without locally duplicating damage or launch")
		check(received.rings >= 2, "Production enemy ring RPC reaches the joiner")
	world.fixture_command.rpc_id(client_id, "secondary_kill")
	check(await until(func(): return world.kill_peers.size() == 1 and enemy(103).velocity.x > 0.0), "Secondary kill crosses the kill-notification RPC and returns an Edict impulse")
	check(not enemy(103).get_launch_state().active, "Returned secondary-kill impulse does not arm another launch")
	check(world.kill_peers == [client_id], "Secondary kill retains the joiner's kill credit")
	world.fixture_command.rpc_id(client_id, "inspect_secondary")
	check(await until(func(): return results.has("secondary")), "Joiner reports the kill-notification scope")
	if results.has("secondary"):
		check(results.secondary.scopes == [true], "Suppression survives the actual kill RPC boundary")
	world.fixture_command.rpc_id(client_id, "blast_feedback")
	check(await until(func(): return results.has("blast_owner") and not remote_player.received_blasts.is_empty() and remote_player.global_position == Vector2(-200.0, -180.0)), "Real Blast cue and owner movement RPCs reach the other process")
	if results.has("blast_owner") and not remote_player.received_blasts.is_empty():
		var received: Dictionary = remote_player.received_blasts.back()
		check(received.position == Vector2(-20.0, -180.0) and received.range == 160.0 and received.arc == 70.0, "Remote Blast effect receives the short cone and exact firing origin")
		check(results.blast_owner.position == received.position and results.blast_owner.range == received.range and results.blast_owner.arc == received.arc and results.blast_owner.serial == received.serial, "Owner and receiver agree on shot geometry and serial over the production cue channel")
		var effect := remote_player.arcana_motion._blast_effects.back() as BLAST_EFFECT
		check(is_instance_valid(effect) and effect.global_position == Vector2(-20.0, -180.0) and effect.hits == [Vector2(110.0, -180.0)], "Remote movement leaves the live blast anchored, with the accepted-hit glint delivered by RPC")
	check(await until(func(): return enemy(104).get_current_health() == 900), "The same short-range shot applies host-owned Blast damage exactly once")
	for tier in [3, 1]:
		var configuration := resolve_configuration(tier, ["hardened_foes"])
		var result_key := "configuration_%d" % tier
		world.fixture_command.rpc_id(client_id, "configuration", {"tier": tier, "loadout": configuration.ascension_loadout, "result_key": result_key})
		check(await until(func(): return results.has(result_key)), "Joiner receives the explicit host bearing/loadout")
		if results.has(result_key):
			check(results[result_key] == configuration, "Host and joiner resolve identical tier %d settings independently of menu preference" % tier)
		check(int(configuration.ascension_rank) == (2 if tier == 3 else 0), "Ascension modifiers apply only on Forsworn")
	world.fixture_command.rpc_id(client_id, "finish")
	await until(func(): return results.has("finished"))
	await finish()

func resolve_configuration(tier: int, loadout: Array) -> Dictionary:
	# Use production frozen-loadout and tier resolution, with a conflicting menu
	# preference. Fixture RPC carries this payload; lobby startup stays suppressed.
	RunContext.current_difficulty_tier = 1 if tier == 3 else 3
	RunContext.set_multiplayer_session("loopback-fixture", role == "host")
	RunContext.set_multiplayer_difficulty_tier(tier)
	RunContext.set_active_ascension_loadout(loadout, tier)
	return DIFFICULTY.get_tier_config_with_ascension(tier, RunContext.get_active_ascension_loadout(tier))

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"primary":
			DAMAGE.apply_damage(enemy(101), 20, {"attack_type": "melee", "source_peer_id": 1})
			check(enemy(101).get_current_health() == 100 and not enemy(101).get_launch_state().active, "Joiner routes primary damage without applying it locally")
		"inspect_primary":
			await until(func(): return enemy(101).get_current_health() == 40 and ring_count() >= 2, 2.0)
			world.fixture_result.rpc_id(1, "primary", {"health": enemy(101).get_current_health(), "launch_active": enemy(101).get_launch_state().active, "rings": ring_count(), "local_damage_events": world.damage_events.size()})
		"secondary_kill":
			DAMAGE.apply_damage(enemy(102), 20, {"attack_type": "sovereigns_double", "secondary": true})
		"inspect_secondary":
			world.fixture_result.rpc_id(1, "secondary", {"scopes": local_player.kill_scopes})
		"blast_feedback":
			local_player.apply_trial_power("blast_drive")
			local_player.global_position = Vector2(-20.0, -180.0)
			local_player.perform_motion_blast(Vector2.RIGHT, 1.0)
			var effect := local_player.arcana_motion._blast_effects.back() as BLAST_EFFECT
			var owner_state := {"position": effect.global_position, "range": effect.reach, "arc": effect.arc_degrees, "serial": effect.serial}
			local_player.global_position = Vector2(-200.0, -180.0)
			PlayerReplicationService._flush_pending_cue_events()
			PlayerReplicationService._sync_all_player_positions()
			check(effect.global_position == Vector2(-20.0, -180.0) and enemy(104).get_current_health() == 1000, "Owner recoil leaves the shot fixed while enemy damage remains host-owned")
			world.fixture_result.rpc_id(1, "blast_owner", owner_state)
		"configuration":
			world.fixture_result.rpc_id(1, payload.result_key, resolve_configuration(int(payload.tier), payload.loadout))
		"finish":
			world.fixture_result.rpc_id(1, "finished", {})
			await create_timer(0.1).timeout
			await finish()

func finish() -> void:
	if finished:
		return
	finished = true
	if is_instance_valid(deadline_timer):
		deadline_timer.stop()
		deadline_timer.queue_free()
	var file := FileAccess.open(prefix + "-" + role + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"role": role, "checks": checks, "failures": failures, "results": results}, "\t"))
	file.close()
	MultiplayerSessionManager.session_connected = false
	PlayerReplicationService.player_nodes.clear()
	EnemyReplicationService.unbind_world(world)
	for actor in [local_player, remote_player]:
		if is_instance_valid(actor) and is_instance_valid(actor.upgrade_system.power_registry):
			actor.upgrade_system.power_registry.free()
	current_scene = null
	world.free()
	peer.close()
	get_multiplayer().multiplayer_peer = null
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await create_timer(0.1).timeout
	print("[ENet] %s: %d checks, %d failures" % [role, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
