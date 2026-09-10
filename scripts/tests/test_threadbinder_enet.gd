extends "res://scripts/tests/test_combat_interactions_enet.gd"
## Real joiner damage requests, authoritative Cross Stitch and packed state/cues.

const CHARACTERS := preload("res://scripts/character_registry.gd")

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	RunContext.set_multiplayer_session("threadbinder-loopback", role == "host")
	RunContext.meta_progress_profile = {}
	world.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(world)
	GameStateReplicationService.initialize(world)
	for id in [1, client_id]:
		var actor := InteractionPlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		world.add_child(actor)
		actor.apply_character_package(CHARACTERS.get_character("threadbinder"))
		actor.damage = 100
		actor.position = Vector2.ZERO
		actor.shared_build_runtime.set_physics_process(false)
		actor.returning_crescent.set_physics_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	var positions := {101: Vector2(60, 0), 102: Vector2(150, 0), 103: Vector2(82, 0), 104: Vector2(-90, 0), 105: Vector2(-180, 0)}
	for id in positions:
		var target := Enemy.new()
		target.name = "Enemy_%d" % id
		world.add_child(target)
		target.position = positions[id]
		target.health_state.setup(10000, 10000)
		world.enemy_state_sync_broadcaster.register_enemy(target, id)
	world.active_room_enemy_count = positions.size()

func report(key: String) -> void:
	world.fixture_result.rpc_id(1, key, {
		"target": local_player.cross_stitch_target_network_id,
		"window": local_player.cross_stitch_window_left,
		"host_target": remote_player.cross_stitch_target_network_id,
		"host_window": remote_player.cross_stitch_window_left,
		"mark": DAMAGE.status_snapshot(enemy(101), joiner_id),
		"rings": (local_player.player_feedback as Feedback).rings,
		"host_rings": (remote_player.player_feedback as Feedback).rings,
		"damage_events": world.damage_events.size(),
		"scope": DAMAGE.current_interaction_context()
	})

func _sync_observed_state() -> void:
	world.enemy_state_sync_broadcaster.tick(0.25)
	world.enemy_state_sync_broadcaster.tick(0.25)
	PlayerReplicationService._flush_pending_cue_events()

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	begin_run()
	await command("begin")
	check(await until(received), "Threadbinder peers complete the production run-token handshake")
	await command("first_attack")
	check(enemy(101).get_current_health() == 9900 and enemy(103).get_current_health() == 10000, "Joiner first contact deals one base attack without an initial Burst")
	check(is_equal_approx(float(DAMAGE.status_snapshot(enemy(101), client_id).mark_ratio), 0.12), "The host applies the joiner's 12% Cross Stitch Mark after accepted damage")
	check(remote_player.cross_stitch_target_network_id == 101 and remote_player.cross_stitch_window_left > 0.0, "Host stores the joiner's first threaded target")
	check(local_player.cross_stitch_target_network_id == 0, "Joiner attacks do not change the host player's own thread")
	_sync_observed_state()
	await command("inspect_first")
	check(results.inspect_first.target == 101 and results.inspect_first.window > 0.0 and is_equal_approx(float(results.inspect_first.mark.mark_ratio), 0.12), "Native status and packed player state reach the owning joiner")
	check(results.inspect_first.damage_events == 0, "Client requests and state updates do not simulate authoritative damage")
	await command("switch_attack")
	check(enemy(102).get_current_health() == 9900 and enemy(101).get_current_health() == 9833 and enemy(103).get_current_health() == 9940, "A new joiner Attack switches targets and releases one 60% Burst with each victim's own Mark scaling")
	check(remote_player.cross_stitch_target_network_id == 102, "The host advances only the joiner's thread to the new target")
	check(world.damage_events.size() == 4 and world.damage_events.all(func(event: Dictionary) -> bool: return int(event.peer) == client_id), "Host records the attack and both Burst victims under the authenticated joiner")
	_sync_observed_state()
	await command("inspect_switch")
	check(results.inspect_switch.target == 102 and results.inspect_switch.rings == 1 and results.inspect_switch.host_rings == 0, "The reliable host Burst cue reaches its owner exactly once with the new endpoint")
	await command("same_attack")
	check(enemy(103).get_current_health() == 9840 and remote_player.cross_stitch_target_network_id == 102 and (remote_player.player_feedback as Feedback).rings == 1, "A later contact of the same original Attack cannot move the thread or release another Burst")
	await command("automatic_and_forged_mark")
	check(enemy(104).get_current_health() == 9970 and float(DAMAGE.status_snapshot(enemy(103), client_id).mark_ratio) == 0.0, "Automatic damage cannot stitch and a direct client Mark request cannot bypass the accepted-attack boundary")
	check(remote_player.cross_stitch_target_network_id == 102, "Automatic damage preserves the existing joiner endpoint")
	await command("forge_burst")
	check((remote_player.player_feedback as Feedback).rings == 1, "A client cannot broadcast the host-owned Burst cue")
	var host_action := local_player.combat_interactions.begin_action("attack")
	DAMAGE.apply_damage(enemy(104), 100, INTERACTIONS.damage_context(host_action, "melee", {"raw_amount": 100.0, "damage_coefficient": 1.0}), 1)
	host_action = local_player.combat_interactions.begin_action("attack")
	DAMAGE.apply_damage(enemy(105), 100, INTERACTIONS.damage_context(host_action, "melee", {"raw_amount": 100.0, "damage_coefficient": 1.0}), 1)
	check(local_player.cross_stitch_target_network_id == 105 and remote_player.cross_stitch_target_network_id == 102, "Host and joiner retain independent endpoints after both switch targets")
	_sync_observed_state()
	await command("inspect_host")
	check(results.inspect_host.host_target == 105 and results.inspect_host.host_window > 0.0 and results.inspect_host.host_rings == 1, "Observing joiner receives the host player's endpoint and Burst cue")
	check(results.inspect_host.target == 102 and results.inspect_host.rings == 1 and results.inspect_host.damage_events == 0 and results.inspect_host.scope.is_empty(), "Both peer presentations stay separate without duplicate damage or interaction-scope leakage")
	await command("finish")
	await finish()

func client_command(name: String, _payload: Dictionary) -> void:
	match name:
		"begin":
			begin_run()
			check(await until(func(): return not INTERACTIONS.current_run().is_empty()), "Joiner binds the actual host run token")
		"first_attack":
			next_action = local_player.combat_interactions.begin_action("attack")
			DAMAGE.apply_damage(enemy(101), 100, INTERACTIONS.damage_context(next_action, "melee", {"raw_amount": 100.0, "damage_coefficient": 1.0}))
			check(enemy(101).get_current_health() == 10000 and local_player.cross_stitch_target_network_id == 0, "Sending the first attack performs no local damage or predicted stitch")
		"inspect_first":
			check(await until(func(): return local_player.cross_stitch_target_network_id == 101 and float(DAMAGE.status_snapshot(enemy(101), joiner_id).mark_ratio) > 0.0), "Owner receives authoritative endpoint and Mark")
		"switch_attack":
			next_action = local_player.combat_interactions.begin_action("attack")
			DAMAGE.apply_damage(enemy(102), 100, INTERACTIONS.damage_context(next_action, "melee", {"raw_amount": 100.0, "damage_coefficient": 1.0}))
		"inspect_switch":
			check(await until(func(): return local_player.cross_stitch_target_network_id == 102 and (local_player.player_feedback as Feedback).rings == 1), "Owner receives one reliable Burst cue after the switch")
		"same_attack":
			DAMAGE.apply_damage(enemy(103), 100, INTERACTIONS.damage_context(next_action, "razor_wind", {"raw_amount": 100.0, "damage_coefficient": 1.0}))
		"automatic_and_forged_mark":
			DAMAGE.apply_damage(enemy(104), 30, INTERACTIONS.damage_context(next_action, "returning_crescent", {"raw_amount": 30.0, "damage_coefficient": 0.3}))
			DAMAGE.apply_mark(enemy(103), "cross_stitch", 9.0, 99.0, joiner_id, next_action)
		"forge_burst":
			PlayerReplicationService.broadcast_cue_event(joiner_id, "cross_stitch_burst", {"position": Vector2.ZERO, "radius": 999.0, "color": Color.WHITE, "duration": 10.0}, true)
			PlayerReplicationService._flush_pending_cue_events()
			var forged_events: Array[Dictionary] = [{"event": "cross_stitch_burst", "payload": {"position": Vector2.ZERO, "radius": 999.0, "color": Color.WHITE, "duration": 10.0}}]
			PlayerReplicationService._sync_player_cue_events_reliable.rpc_id(1, joiner_id, forged_events)
		"inspect_host":
			check(await until(func(): return remote_player.cross_stitch_target_network_id == 105 and (remote_player.player_feedback as Feedback).rings == 1), "Observer receives host endpoint and one Burst cue")
		"finish":
			report(name)
			await create_timer(0.1).timeout
			await finish()
			return
	report(name)
