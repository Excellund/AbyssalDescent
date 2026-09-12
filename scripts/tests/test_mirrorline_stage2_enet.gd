extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Separate peers, real runtime broadcaster budget and native replica receiver.
const FOCUSED := preload("res://scripts/tests/test_mirrorline_stage2.gd")
const MIRROR_ID := 974
var mirror: FOCUSED.Mirrorline

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	for id in [1, client_id]:
		var actor := Player.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.position = Vector2(220, 130) if id == 1 else Vector2(-150, 240)
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
		actor.returning_crescent.set_physics_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	mirror = FOCUSED.Mirrorline.new()
	mirror.name = "Mirrorline"
	circle(mirror, 32.0)
	world.add_child(mirror)
	mirror.position = Vector2(-250, -180)
	mirror.target = PlayerReplicationService.player_nodes[1]
	mirror.target_candidates = [PlayerReplicationService.player_nodes[1], PlayerReplicationService.player_nodes[client_id]]
	mirror.set_physics_process(false)
	mirror._axis_normal = Vector2.RIGHT
	mirror._axis_origin = Vector2.ZERO
	mirror._axis_target_normal = Vector2.RIGHT
	mirror._axis_target_origin = Vector2.ZERO
	world.enemy_state_sync_broadcaster.register_enemy(mirror, MIRROR_ID)
	world.active_room_enemy_count = 1
	check(mirror.network_simulation_enabled == (role == "host"), "Registration preserves host-only simulation")
	_begin_reward_run()

func _exchange(key: String, expire: bool = false, projectile: bool = false, dense_status: bool = false) -> Dictionary:
	var ids: Array[int] = []
	for echo: Dictionary in mirror._active_echoes:
		ids.append(int(echo.id))
	# Exercise the production size fitter even when all two-player volleys miss
	# and remain in flight. Direct fixture RPCs would hide a dropped custom state.
	world.enemy_state_sync_broadcaster.tick(.25)
	if projectile:
		world._sync_archer_projectile_state_tick(.25)
	world.fixture_command.rpc_id(joiner_id, "inspect", {"key": key, "state": mirror._state, "twin": mirror._twin_active, "pending": mirror._twin_pending, "ids": ids, "warning": mirror._telegraph_total, "expire": expire, "dense_status": dense_status, "left": mirror._state_time_left})
	check(await until(func(): return results.has(key)), "Joiner acknowledges " + key)
	var result: Dictionary = results.get(key, {})
	if not result.is_empty():
		check(bool(result.agrees), "Real broadcaster delivers every axis and echo ID for " + key)
		check(not bool(result.authority) and int(result.created) == 0 and int(result.damage) == 0, "Replica never gains shot or damage authority: " + key)
	return result

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	check(await until(func(): return GameStateReplicationService.get_current_run_sync_token().length() == 32), "Host recorder finishes its deferred run-token startup")
	world.fixture_command.rpc_id(client_id, "run_identity", {"run": GameStateReplicationService.get_current_run_sync_token()})
	check(await until(func(): return results.has("run_identity"), 4.0), "Actual recorder handshake reaches the joiner")
	if results.has("run_identity"):
		check(bool(results.run_identity.common), "Both peers use the real nonempty run identity for statuses")
	mirror._enter_telegraph()
	var initial := await _exchange("stage_one_warning")
	if not initial.is_empty():
		check(is_equal_approx(float(initial.duration), 1.3), "Stage-one joiner warning is unchanged")
	mirror._state_time_left = 0.0
	mirror._advance_axis_rotation()
	mirror._enter_reflect()
	await _exchange("stage_one_reflect")
	FOCUSED.cross_half_health(mirror)
	await _exchange("half_health_pending")
	check(mirror._twin_pending and not mirror._twin_active, "Half HP never adds an unannounced seam during reflect")
	mirror._enter_cooldown()
	await _exchange("transition_recovery")
	mirror._active_echoes.clear()
	mirror._enter_telegraph()
	var twin_warning := await _exchange("first_twin_warning")
	if not twin_warning.is_empty():
		check(is_equal_approx(float(twin_warning.duration), 1.6), "First twin snapshot initializes the full extended local warning")
	mirror._state_time_left = .7
	var late_warning := await _exchange("partial_warning", false, true)
	if not late_warning.is_empty():
		check(is_equal_approx(float(late_warning.duration), .7), "Late projectile snapshot preserves .7 seconds remaining instead of restarting the warning")
	await _check_stream_ordering(client_id)
	mirror._state_time_left = 0.0
	mirror._advance_axis_rotation()
	mirror.volleys.clear()
	mirror._enter_reflect()
	for slot in range(8):
		if slot > 0:
			mirror.elapsed += .2
			mirror._tick_reflect_cadence(.200001)
		check(mirror.volleys.size() == slot + 1 and mirror.volleys[slot].echoes.size() == 2, "Each two-player slot adds one echo per player")
		await _exchange("twin_volley_%d" % slot)
	check(mirror._active_echoes.size() == 16, "All four shots on both axes exist for both players")
	FOCUSED.seed_statuses(mirror, [1, client_id], true)
	mirror._active_echoes.clear()
	mirror._enter_reflect()
	for slot in range(7):
		mirror._tick_reflect_cadence(.200001)
	var status_packet := DAMAGE.get_status_network_packet(mirror)
	check(int(status_packet[18]) == 12 and int(status_packet[19]) == 2 and status_packet.decode_u16(16) == 32, "Dense packet uses actual two-owner Marks/Dread and a real 32-byte run token")
	var full_state := mirror.get_network_runtime_state()
	full_state.shared_status = status_packet
	var dense_envelope := {"enemy_id": MIRROR_ID, "runtime_state_delta": full_state}
	check(not world.enemy_state_sync_broadcaster._fit_state_to_size_limit(dense_envelope, 900).runtime_state_delta.has("custom"), "Real dense status fills the generic budget before dedicated pattern delivery")
	world.enemy_state_sync_broadcaster._previous_runtime_states.erase(MIRROR_ID)
	await _exchange("dense_status_new_volley_ids", false, true, true)
	mirror._enter_cooldown()
	var cooldown := await _exchange("twin_recovery", true, true, true)
	if not cooldown.is_empty():
		check(is_equal_approx(float(cooldown.duration), 1.55) and bool(cooldown.expired), "Native recovery keeps its extension and old echo presentation expires")
	mirror._sundered_reduction_left = 0.0
	mirror.take_damage(10000)
	world.fixture_command.rpc_id(client_id, "death")
	check(await until(func(): return results.has("death")), "Joiner receives real authoritative owner removal")
	if results.has("death"):
		check(bool(results.death.removed), "Death leaves no owner or child echo presentation on the joiner")
	world.fixture_command.rpc_id(client_id, "finish_mirrorline")
	check(await until(func(): return results.has("finished")), "Joiner completes before its transport closes")
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"run_identity":
			var common := await until(func(): return not String(payload.run).is_empty() and GameStateReplicationService.get_current_run_sync_token() == String(payload.run))
			world.fixture_result.rpc_id(1, "run_identity", {"common": common})
		"ordered":
			var arrived := await until(func(): return mirror._mirror_received_sequence >= int(payload.q))
			await create_timer(.08).timeout
			check(arrived and mirror._mirror_received_sequence == int(payload.q) and absf(mirror._state_time_left - float(payload.left)) < .001, "Stale or wrong-room cross-channel snapshots cannot roll back the warning")
			world.fixture_result.rpc_id(1, payload.key, {"q": mirror._mirror_received_sequence, "left": mirror._state_time_left})
		"inspect":
			var agrees := await until(func():
				if not is_instance_valid(mirror) or mirror._state != int(payload.state) or mirror._twin_active != bool(payload.twin) or mirror._twin_pending != bool(payload.pending):
					return false
				var received: Array[int] = []
				for echo: Dictionary in mirror._active_echoes:
					received.append(int(echo.id))
				for id in payload.ids:
					if not received.has(int(id)):
						return false
				if bool(payload.dense_status):
					var status: Node = DAMAGE._target_status(mirror)
					if status == null or status.marks.size() != 12 or status.dread.size() != 2:
						return false
				return is_equal_approx(mirror._telegraph_total, float(payload.warning)) and absf(mirror._state_time_left - float(payload.left)) < .001)
			check(agrees, "Native state contains the expected stage and all volleys: " + String(payload.key))
			var duration := mirror._state_time_left
			var before_id := mirror._next_echo_id
			var before_health := local_player.get_current_health() + remote_player.get_current_health()
			var positions := [local_player.position, remote_player.position]
			local_player.position = mirror._axis_origin + mirror._axis_normal.orthogonal() * 160.0
			remote_player.position = mirror._axis_origin + mirror._axis_normal * 160.0
			mirror._tick_reflect_cadence(.5)
			mirror._spawn_echo_from_player(1)
			mirror._tick_seam_beam_damage(.5)
			local_player.position = positions[0]
			remote_player.position = positions[1]
			var expired := false
			if bool(payload.expire):
				mirror._process_network_visuals(3.0)
				expired = mirror._active_echoes.is_empty() and mirror.get_attack_callout().is_empty()
			check(mirror._next_echo_id == before_id and mirror.volleys.is_empty(), "Replica helper calls cannot spawn an echo")
			world.fixture_result.rpc_id(1, payload.key, {"agrees": agrees, "duration": duration, "authority": mirror.network_simulation_enabled, "created": mirror._next_echo_id - before_id, "damage": before_health - local_player.get_current_health() - remote_player.get_current_health(), "expired": expired})
		"death":
			var removed := await until(func(): return not is_instance_valid(mirror) or mirror.is_queued_for_deletion())
			world.fixture_result.rpc_id(1, "death", {"removed": removed})
		"finish_mirrorline":
			local_player.hide()
			remote_player.hide()
			world.fixture_result.rpc_id(1, "finished", {})
			await create_timer(.05).timeout
			await finish()
		_:
			super.client_command(command, payload)

func _check_stream_ordering(client_id: int) -> void:
	var old_custom := mirror._get_custom_network_runtime_state()
	mirror._state_time_left = .6
	var current_projectile := mirror.get_projectile_network_sync_state()
	world._sync_archer_projectile_states.rpc([{"enemy_id": MIRROR_ID, "payload": current_projectile}], 7)
	world._sync_enemy_states.rpc([{"enemy_id": MIRROR_ID, "runtime_state_delta": {"custom": old_custom}}], 1)
	var wrong_room := current_projectile.duplicate(true)
	wrong_room.r = 6
	wrong_room.q += 1000
	world._sync_archer_projectile_states.rpc([{"enemy_id": MIRROR_ID, "payload": wrong_room}], 7)
	world.fixture_command.rpc_id(client_id, "ordered", {"key": "projectile_over_custom", "q": current_projectile.q, "left": .6})
	check(await until(func(): return results.has("projectile_over_custom")), "Joiner checks newer projectile versus stale custom and wrong inner room")
	mirror._state_time_left = .5
	var current_custom := mirror._get_custom_network_runtime_state()
	world._sync_enemy_states.rpc([{"enemy_id": MIRROR_ID, "runtime_state_delta": {"custom": current_custom}}], 1)
	world._sync_archer_projectile_states.rpc([{"enemy_id": MIRROR_ID, "payload": current_projectile}], 7)
	var wrong_outer := current_custom.duplicate(true)
	wrong_outer.q += 1000
	world._sync_archer_projectile_states.rpc([{"enemy_id": MIRROR_ID, "payload": wrong_outer}], 6)
	world.fixture_command.rpc_id(client_id, "ordered", {"key": "custom_over_projectile", "q": current_custom.q, "left": .5})
	check(await until(func(): return results.has("custom_over_projectile")), "Joiner checks newer custom versus stale projectile and wrong outer room")
