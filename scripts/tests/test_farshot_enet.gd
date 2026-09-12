extends "res://scripts/tests/test_combat_interactions_enet.gd"
## Two actual ENet peers, native Player/build/movement/accepted-damage transports.
## Combat time and positions are staged; this is authority proof, not balance.

class FarshotPlayer extends InteractionPlayer:
	func _notification(_what: int) -> void:
		pass # Headless peers have no focused OS game window.

var transport_tick_usec: int = 0

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	RunContext.set_multiplayer_session("farshot-loopback", role == "host")
	RunContext.meta_progress_profile = {}
	world.current_room_size = Vector2(2000, 1500)
	world.current_effective_room_size = world.current_room_size
	world.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(world)
	GameStateReplicationService.initialize(world)
	process_frame.connect(_pump_transport)
	for id in [1, client_id]:
		var actor := FarshotPlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		actor.is_local_player = id == get_multiplayer().get_unique_id()
		circle(actor, 14)
		world.add_child(actor)
		actor.position = Vector2(200, 0) if id == 1 else Vector2.ZERO
		actor.damage = 100
		actor.arcana_motion.set_process(false)
		actor.returning_crescent.set_physics_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		if actor.is_local_player:
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	for id in range(101, 111):
		var target := Enemy.new()
		target.name = "Enemy_%d" % id
		circle(target, 13)
		world.add_child(target)
		target.position = Vector2(159 if id == 101 else (160 if id == 102 else (100 if id == 107 else 200)), 0)
		target.health_state.setup(10000, 10000)
		world.enemy_state_sync_broadcaster.register_enemy(target, id)
	world.active_room_enemy_count = 10

func _pump_transport() -> void:
	if finished or not MultiplayerSessionManager.is_session_connected() or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var now := Time.get_ticks_usec()
	var delta := 1.0 / 60.0 if transport_tick_usec == 0 else float(now - transport_tick_usec) / 1000000.0
	transport_tick_usec = now
	PlayerReplicationService._sync_all_player_positions()
	PlayerReplicationService._interpolate_remote_players(delta)
	PlayerReplicationService._flush_pending_cue_events()
	if role == "host":
		world.enemy_state_sync_broadcaster.tick(delta)

func report(key: String) -> void:
	world.fixture_result.rpc_id(1, key, {"body": local_player.global_position, "farshot": local_player.farshot_bonus_damage, "damage_events": world.damage_events.size(), "health": enemy(101).get_current_health()})

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	begin_run()
	await command("begin")
	check(await until(received), "Native recorder handshake binds both Farshot peers to the same run")
	await command("build")
	check(await until(func(): return remote_player.farshot_bonus_damage == 20 and remote_player.get_upgrade_stack_count("farshot") == 2), "Joining owner's ordinary two picks arrive through existing build snapshot RPC")
	check(local_player.farshot_bonus_damage == 0, "Remote acquisition cannot grant Farshot to the host")
	await command("thresholds")
	check(enemy(101).get_current_health() == 9900 and enemy(102).get_current_health() == 9880, "Host evaluates the remote body at below160 and inclusive160, despite its own nearby body")
	await command("launch")
	await _move_joiner(Vector2(100, 0))
	await command("impact", {"id": 103})
	check(enemy(103).get_current_health() == 9900, "Remote movement toward the target after launch removes the impact bonus")
	await _move_joiner(Vector2(-100, 0))
	await command("impact", {"id": 104})
	check(enemy(104).get_current_health() == 9880, "Remote movement away after launch enables the same saved descriptor")
	await command("fractions")
	check(enemy(105).get_current_health() == 9988 and enemy(106).get_current_health() == 9934, "Real remote Field fractions total12 and55percent Echo deals66 at level2")
	await _move_joiner(Vector2.ZERO)
	await command("collateral")
	check(enemy(107).get_current_health() == 9940 and enemy(108).get_current_health() == 9928, "Remote collateral resolves its actual near/far targets with0.6 source coefficient")
	await command("forge")
	check(enemy(109).get_current_health() == 10000, "Forged owner cannot borrow the host body or claim Farshot damage")
	check(world.damage_events.all(func(event: Dictionary): return event.peer == client_id), "Every accepted remote result remains attributed to the authenticated owner")
	check(results.collateral.damage_events == 0, "Joining replica never performs local authoritative damage")
	for level in 3:
		local_player.apply_upgrade("farshot")
	local_player.broadcast_network_build_snapshot()
	var action := local_player.combat_interactions.begin_action("dash")
	DAMAGE.apply_damage(enemy(110), 100, INTERACTIONS.damage_context(action, "static_wake", {"raw_amount": 100.0, "damage_coefficient": 1.0}), 1)
	check(enemy(110).get_current_health() == 9900, "Host's own nearby body does not borrow the distant joining body, even at level3")
	await command("observe")
	check(results.observe.farshot == 20, "Host broadcast cannot replace the joining owner's Farshot level")
	check(DAMAGE.current_interaction_context().is_empty(), "Farshot leaves no interaction scope behind")
	await command("finish")
	await finish()

func _move_joiner(position: Vector2) -> void:
	await command("move", {"position": position})
	check(await until(func(): return remote_player.global_position.distance_to(position) < 0.001), "Existing movement transport delivers current remote body%s before impact" % position)

func _deal(id: int, source: String, raw: float, coefficient: float, action: Dictionary = {}) -> void:
	if action.is_empty():
		action = local_player.combat_interactions.begin_action("attack")
	if source == "sovereigns_double":
		action = INTERACTIONS.damage_context(action, "melee").interaction
	DAMAGE.apply_damage(enemy(id), int(raw), INTERACTIONS.damage_context(action, source, {"raw_amount": raw, "damage_coefficient": coefficient, "attack_origin": Vector2(195, 0)}), local_player.player_id)

func client_command(name: String, payload: Dictionary) -> void:
	match name:
		"begin":
			begin_run()
			check(await until(func(): return not INTERACTIONS.current_run().is_empty()), "Joiner receives the native host run token")
		"build":
			local_player.apply_upgrade("farshot")
			local_player.apply_upgrade("farshot")
			local_player.broadcast_network_build_snapshot()
		"thresholds":
			_deal(101, "returning_crescent", 100, 1)
			_deal(102, "returning_crescent", 100, 1)
		"launch":
			saved_action = local_player.combat_interactions.begin_action("attack")
		"move":
			local_player.position = payload.position
			PlayerReplicationService._sync_all_player_positions()
		"impact":
			_deal(int(payload.id), "returning_crescent", 100, 1, saved_action)
		"fractions":
			for index in 10:
				_deal(105, "static_wake", 1, 0.01)
			_deal(106, "sovereigns_double", 55, 0.55)
		"collateral":
			var action := local_player.combat_interactions.begin_action("attack")
			_deal(107, "rupture_wave", 60, 0.6, action)
			_deal(108, "rupture_wave", 60, 0.6, action)
		"forge":
			var forged := local_player.combat_interactions.begin_action("attack")
			forged.owner = 1
			DAMAGE.apply_damage(enemy(109), 100, INTERACTIONS.damage_context(forged, "returning_crescent", {"raw_amount": 100.0, "damage_coefficient": 1.0}), joiner_id)
		"observe":
			check(await until(func(): return remote_player.farshot_bonus_damage == 30 and enemy(101).get_current_health() == 9900), "Observer receives host level3 and authoritative enemy health through native transports")
		"finish":
			report(name)
			await create_timer(0.1).timeout
			await finish()
			return
	report(name)
