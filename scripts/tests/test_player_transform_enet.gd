extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Actual owner RPCs: delayed/replayed samples, lost stops and registry retirement.
var accepted_sequence := 0

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	for id in [1, client_id]:
		var actor := Player.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.position = Vector2.ZERO
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	PlayerReplicationService.set_process(false)

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	world.fixture_command.rpc_id(client_id, "position", {"position": Vector2(300.0, 0.0), "key": "before"})
	check(await until(func(): return remote_player.position == Vector2(300.0, 0.0)), "Native owner transform reaches host before transition")
	world._world_multiplayer_sync_state.current_room_sync_id = 8
	remote_player.position = Vector2.ZERO
	PlayerReplicationService.reset_remote_player_position(client_id, Vector2.ZERO)
	world.fixture_command.rpc_id(client_id, "position", {"position": Vector2(420.0, 0.0), "key": "late"})
	check(await until(func(): return results.has("late")), "Old-room owner sample is sent after host reset, representing a delayed packet")
	await create_timer(0.15).timeout
	check(remote_player.position == Vector2.ZERO, "A late prior-room owner transform must not undo the new spawn")
	results["late_room_position"] = {"observed": remote_player.position}
	world.fixture_command.rpc_id(client_id, "lost_final")
	check(await until(func(): return results.has("lost_final")), "Owner simulates omission of the final unreliable stop packet and runs sync for 0.6 seconds")
	await create_timer(0.15).timeout
	PlayerReplicationService._interpolate_remote_players(1.0)
	check(remote_player.position.distance_to(Vector2(240.0, 0.0)) < 0.1, "A stationary owner's final position is eventually refreshed after one lost packet")
	results["lost_final_position"] = {"observed": remote_player.position}
	world.fixture_command.rpc_id(client_id, "ordered")
	check(await until(func(): return remote_player.position == Vector2(480.0, 25.0)), "A current-room owner movement sample is accepted")
	var accepted_target: Vector2 = PlayerReplicationService._remote_target_positions[client_id]
	var accepted_facing: float = PlayerReplicationService._remote_target_rotations[client_id]
	world.fixture_command.rpc_id(client_id, "older")
	check(await until(func(): return results.has("older")), "Owner replays an earlier same-room sample through the native RPC")
	await create_timer(0.15).timeout
	check(PlayerReplicationService._remote_target_positions[client_id] == accepted_target and PlayerReplicationService._remote_target_rotations[client_id] == accepted_facing, "Older and duplicate samples cannot replace accepted position or facing")
	world.fixture_command.rpc_id(client_id, "malformed_then_valid")
	check(await until(func(): return PlayerReplicationService._remote_target_positions[client_id] == Vector2(500.0, 35.0)), "Malformed high-sequence/future-room samples do not consume ordering or block a later valid packet")
	var bystander := Player.new()
	bystander.player_id = 777
	bystander.name = "UnrelatedPlayer"
	world.add_child(bystander)
	bystander.position = Vector2(-800.0, -200.0)
	PlayerReplicationService.register_player(777, bystander)
	world.fixture_command.rpc_id(client_id, "spoof")
	check(await until(func(): return results.has("spoof")), "Joiner sends a transform naming another registered actor")
	await create_timer(0.15).timeout
	check(bystander.position == Vector2(-800.0, -200.0), "Native sender identity prevents moving another owner's registered actor")
	PlayerReplicationService._remote_position_samples[777] = {"last_pos": bystander.position}
	bystander.free()
	check(PlayerReplicationService._get_player_node(777) == null and not PlayerReplicationService._remote_position_samples.has(777), "Invalid-player retirement removes extrapolation history along with the registry")
	PlayerReplicationService.unregister_player(client_id)
	check(not PlayerReplicationService._last_received_transform_sequence.has(client_id) and not PlayerReplicationService._last_transform_sent_at.has(client_id) and not PlayerReplicationService._remote_position_samples.has(client_id), "Explicit unregister clears transport state for the departed peer")
	world.fixture_command.rpc_id(client_id, "finish")
	await until(func(): return results.has("finished"))
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"position":
			local_player.position = payload.position
			PlayerReplicationService._sync_all_player_positions()
			world.fixture_result.rpc_id(1, payload.key, {"room": world._world_multiplayer_sync_state.current_room_sync_id})
		"lost_final":
			world._world_multiplayer_sync_state.current_room_sync_id = 8
			local_player.position = Vector2(120.0, 0.0)
			PlayerReplicationService._sync_all_player_positions()
			await create_timer(0.08).timeout
			local_player.position = Vector2(240.0, 0.0)
			# The send-side cache advances on send, even when that unreliable packet is lost.
			PlayerReplicationService._last_sync_positions[local_player.player_id] = local_player.position
			for index in range(12):
				await create_timer(0.05).timeout
				PlayerReplicationService._sync_all_player_positions()
			world.fixture_result.rpc_id(1, "lost_final", {})
		"ordered":
			PlayerReplicationService._outgoing_transform_sequence += 1
			accepted_sequence = PlayerReplicationService._outgoing_transform_sequence
			PlayerReplicationService._sync_player_transform.rpc(local_player.player_id, Vector2(480.0, 25.0), 0.7, accepted_sequence, 8, GameStateReplicationService.get_current_run_sync_token())
		"older":
			PlayerReplicationService._sync_player_transform.rpc(local_player.player_id, Vector2(800.0, 0.0), -1.0, accepted_sequence - 1, 8, GameStateReplicationService.get_current_run_sync_token())
			PlayerReplicationService._sync_player_transform.rpc(local_player.player_id, Vector2(900.0, 0.0), -2.0, accepted_sequence, 8, GameStateReplicationService.get_current_run_sync_token())
			world.fixture_result.rpc_id(1, "older", {})
		"malformed_then_valid":
			PlayerReplicationService._sync_player_transform.rpc(local_player.player_id, Vector2.INF, 0.0, accepted_sequence + 100, 8, GameStateReplicationService.get_current_run_sync_token())
			PlayerReplicationService._sync_player_transform.rpc(local_player.player_id, Vector2(700.0, 0.0), NAN, accepted_sequence + 99, 8, GameStateReplicationService.get_current_run_sync_token())
			PlayerReplicationService._sync_player_transform.rpc(local_player.player_id, Vector2(700.0, 0.0), 0.0, accepted_sequence + 98, 9, GameStateReplicationService.get_current_run_sync_token())
			PlayerReplicationService._outgoing_transform_sequence += 1
			PlayerReplicationService._sync_player_transform.rpc(local_player.player_id, Vector2(500.0, 35.0), 0.8, PlayerReplicationService._outgoing_transform_sequence, 8, GameStateReplicationService.get_current_run_sync_token())
		"spoof":
			PlayerReplicationService._sync_player_transform.rpc(777, Vector2.ZERO, 0.0, 900, 8, GameStateReplicationService.get_current_run_sync_token())
			world.fixture_result.rpc_id(1, "spoof", {})
		"finish":
			world.fixture_result.rpc_id(1, "finished", {})
			await create_timer(0.1).timeout
			await finish()
