extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Separate host/joiner processes exercise the production enemy ability RPC.

const ALTERNATIVE_TEST := preload("res://scripts/tests/test_alternative_bosses.gd")
const RECORDER := preload("res://scripts/core/run_summary_recorder.gd")
const DIFFICULTY_PROVIDER := preload("res://scripts/core/difficulty_scaling_provider.gd")
var bosses: Array = []
var boss: Node2D
var boss_index: int = 0

func _run() -> void:
	await super._run()
	if is_instance_valid(deadline_timer):
		deadline_timer.start(40.0)

class AlternativePlayer extends Player:
	var damage_contexts: Array[Dictionary] = []
	func _ready() -> void:
		super._ready()
		damage_taken.connect(func(_raw: int, _final: int, context: Dictionary): damage_contexts.append(context.duplicate(true)))

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	world.position = Vector2(40.0, -60.0)
	world.current_room_size = Vector2(1800.0, 1100.0)
	world.current_effective_room_size = world.current_room_size
	for id in [1, client_id]:
		var actor := AlternativePlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.set_max_health_and_current(500, 500)
		actor.arcana_motion.set_process(false)
		actor.returning_crescent.set_physics_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	for index in range(ALTERNATIVE_TEST.IDS.size()):
		var enemy := ALTERNATIVE_TEST.Alternative.new()
		enemy.boss_id = ALTERNATIVE_TEST.IDS[index]
		enemy.name = "AlternativeBoss%d" % index
		circle(enemy, 34.0)
		world.add_child(enemy)
		enemy.position = Vector2(-750.0, 350.0)
		enemy.target = local_player
		enemy.target_candidates = [local_player, local_player, remote_player]
		world.enemy_state_sync_broadcaster.register_enemy(enemy, 851 + index)
		enemy.set_physics_process(false)
		bosses.append(enemy)
	# Shared player damage requires the same authenticated run identity as
	# production. Boss-only damage did not previously exercise this boundary.
	RunContext.set_multiplayer_session("alternative-bosses-loopback", role == "host")
	world.difficulty_provider = DIFFICULTY_PROVIDER.new(world)
	GameStateReplicationService.initialize(world)
	world.run_summary_recorder = RECORDER.new(world)
	world.run_summary_recorder.reset_summary_tracker()
	world.run_summary_recorder.initialize(false)
	world.run_summary_recorder.mark_run_start()

func _reset_players() -> void:
	for actor_variant in [local_player, remote_player]:
		var actor := actor_variant as AlternativePlayer
		actor.discard_pending_combat_input()
		actor.set_max_health_and_current(500, 500)
		actor.set_combat_damage_enabled(true)
		actor._dash_damage_immune_left = 0.0
		actor._contact_damage_grace_left = 0.0
		actor.damage_contexts.clear()
	local_player.global_position = boss.global_position + Vector2(170.0, 10.0)
	remote_player.global_position = local_player.global_position

func _send_state(packet: Dictionary = {}, room_id: int = 7) -> Dictionary:
	var actual: Dictionary = boss.get_projectile_network_sync_state() if packet.is_empty() else packet
	world._sync_archer_projectile_states.rpc([{"enemy_id": 851 + boss_index, "payload": actual}], room_id)
	return actual

func _snapshot() -> Dictionary:
	return {
		"geometry": boss.get_attack_warning_geometry(), "id": boss.boss_id,
		"local_health": local_player.get_current_health(), "remote_health": remote_player.get_current_health(),
		"local_calls": (local_player as AlternativePlayer).damage_contexts.size(),
		"remote_calls": (remote_player as AlternativePlayer).damage_contexts.size(),
		"run": GameStateReplicationService.get_current_run_sync_token(),
		"snapshot": boss._received_snapshot, "phase": boss.boss_state,
		"serial": boss._attack_serial, "sequence_step": boss._sequence_step,
		"sequence_root": boss._sequence_root, "callout": boss.get_attack_callout(),
		"attack_kind": boss.attack_kind, "remaining": boss.state_time_left,
		"warning_duration": boss.warning_duration,
		"move_start": boss._move_start, "slam_landing": boss._slam_landing,
		"furnace_cues": boss._furnace_cue_count,
	}

func _inspect(client_id: int, key: String, options: Dictionary = {}) -> Dictionary:
	var payload := options.duplicate(true)
	payload["index"] = boss_index
	payload["key"] = key
	world.fixture_command.rpc_id(client_id, "inspect", payload)
	check(await until(func(): return results.has(key), 4.0), key + ": joiner replies")
	return results.get(key, {})

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	await physics_frame
	check(await until(func(): return world.run_summary_recorder.run_summary_tracker._received_provenance_peers.has(client_id), 6.0), "The real party handshake establishes the shared-damage run identity on both peers")
	for index in range(bosses.size()):
		boss_index = index
		boss = bosses[index]
		boss.position = Vector2(-120.0, 0.0)
		for kind in range(3):
			boss.position = Vector2(-120.0, 0.0)
			_reset_players()
			boss._cancel_attack()
			if boss.boss_id == "kilnheart" and kind == 0:
				local_player.global_position = boss.global_position + Vector2(600.0, 0.0)
				remote_player.global_position = local_player.global_position
			boss.begin_attack(kind)
			var geometry: Array = boss.get_attack_warning_geometry()
			var label := "%s_%d" % [boss.boss_id, kind]
			var hit_position: Vector2 = Vector2.ZERO
			var safe_position: Vector2 = Vector2.ZERO
			for point in ALTERNATIVE_TEST.sample_points(geometry, boss.global_position):
				if ALTERNATIVE_TEST.warning_contains(geometry, point):
					hit_position = point
				else:
					safe_position = point
			var packet := _send_state()
			var packet_bytes := var_to_bytes([{"enemy_id": 851 + index, "payload": packet}]).size() + 15
			check(packet_bytes <= 1392, label + ": warning fits an uncached ENet packet")
			print("[ENet] ", label, " warning bytes=", packet_bytes)
			var received := await _inspect(client_id, label + "_warning", {"expected_geometry": geometry, "try_damage": hit_position})
			check(received.get("geometry", []) == geometry and received.get("id", "") == boss.boss_id, label + ": host identity and committed geometry arrive exactly")
			check(not String(received.get("run", "")).is_empty() and received.get("run") == GameStateReplicationService.get_current_run_sync_token(), label + ": native host and joiner share the authenticated combat run")
			check(received.get("local_calls", -1) == 0 and received.get("remote_calls", -1) == 0, label + ": joiner cannot resolve boss damage")
			if boss.boss_id == "kilnheart" and kind == 0:
				var move_start: Vector2 = boss.global_position
				var landing_shape: Dictionary = geometry[0]
				var landing: Vector2 = landing_shape.center
				check(is_equal_approx(move_start.distance_to(landing), 420.0), label + ": distant target commits a capped forward landing")
				check(received.get("move_start", Vector2.INF) == move_start and received.get("slam_landing", Vector2.INF) == landing, label + ": exact approach and landing arrive with the warning")
				local_player.global_position = move_start + Vector2(-300.0, 200.0)
				remote_player.global_position = local_player.global_position
				boss._process_behavior(boss.warning_duration * 0.5)
				check(boss.global_position.is_equal_approx(move_start.lerp(landing, pow((0.5 - 0.38) / 0.62, 2.0))) and boss.get_attack_warning_geometry() == geometry, label + ": body approaches the committed landing after the target changes direction")
				check(local_player.get_current_health() == 500 and remote_player.get_current_health() == 500, label + ": approach movement cannot resolve damage before the warning finishes")
				var approach_packet: Dictionary = _send_state()
				received = await _inspect(client_id, label + "_approach", {"expected_geometry": geometry, "expected_snapshot": int(approach_packet.snapshot_serial)})
				check(received.get("slam_landing", Vector2.INF) == landing and is_equal_approx(float(received.get("remaining", -1.0)), boss.warning_duration * 0.5), label + ": moving Slam retains its exact landing and remaining warning on the joiner")
				_test_slam_remains_damageable()
			var quantized: Dictionary = world.enemy_state_sync_broadcaster._quantize_runtime_state_for_network(boss.get_network_runtime_state())
			world._sync_enemy_states.rpc([{"enemy_id": 851 + index, "runtime_state_delta": quantized}], 3)
			received = await _inspect(client_id, label + "_quantized_runtime")
			check(received.get("geometry", []) == geometry, label + ": quantized body state cannot move the exact committed warning")
			# Interpolation and later target movement cannot drag a committed warning.
			local_player.global_position = hit_position
			remote_player.global_position = safe_position
			boss._resolve_attack()
			if boss.boss_id == "kilnheart" and kind == 0:
				check(boss.global_position == boss._slam_landing, label + ": authoritative impact places the body at its warned landing")
			check(local_player.get_current_health() < 500 and remote_player.get_current_health() == 500, label + ": host damages the marked region and preserves its safe zone")
			check((local_player as AlternativePlayer).damage_contexts.size() == 1, label + ": duplicated candidates produce one host hit")
			_send_state()
			received = await _inspect(client_id, label + "_resolved", {"expected_geometry": [], "health": {"host": local_player.get_current_health(), "joiner": 500}})
			check(received.get("local_calls", -1) == 0 and received.get("remote_calls", -1) == 0, label + ": health synchronization does not replay damage")
			var resolved_cues := int(received.get("furnace_cues", 0))
			_send_state(packet)
			received = await _inspect(client_id, label + "_stale")
			check(int(received.get("furnace_cues", 0)) == resolved_cues, label + ": reordered warning cannot replay furnace audio")
			check(received.get("geometry", []).is_empty(), label + ": old warning cannot return after authoritative resolution")
			boss.begin_attack(kind)
			_send_state({}, 6)
			received = await _inspect(client_id, label + "_wrong_room")
			check(received.get("geometry", []).is_empty(), label + ": prior-room packets cannot create a warning")
			_send_state()
			received = await _inspect(client_id, label + "_expire", {"expected_geometry": boss.get_attack_warning_geometry(), "expire": true})
			check(received.get("geometry", []).is_empty(), label + ": lost final packet still expires the joiner warning")
			boss._cancel_attack()
		match String(boss.boss_id):
			"kilnheart":
				await _test_pressure_sequence(client_id, 0)
				await _test_pressure_sequence(client_id, 1)
				await _test_pressure_sequence(client_id, 2)
			"glassweaver":
				await _test_pressure_sequence(client_id, 0)
				await _test_pressure_sequence(client_id, 1)
				await _test_pressure_sequence(client_id, 2)
			"null_archivist":
				await _test_pressure_sequence(client_id, 0)
				await _test_pressure_sequence(client_id, 2)
		boss.position = Vector2(-750.0, 350.0)
	world.fixture_command.rpc_id(client_id, "finish")
	await until(func(): return results.has("finished"))
	await finish()

func _test_slam_remains_damageable() -> void:
	var saved_position: Vector2 = local_player.global_position
	var saved_properties: Dictionary = {}
	for property in ["damage", "reward_returning_crescent", "returning_crescent_stacks", "returning_crescent_damage_scale", "returning_crescent_reach_scale"]:
		saved_properties[property] = local_player.get(property)
	var health_before: int = boss.get_current_health()
	local_player.global_position = boss.global_position + Vector2(-70.0, 0.0)
	local_player.damage = 12
	local_player.attack_cooldown_left = 0.0
	local_player.attack_lock_time_left = 0.0
	check(boss.collision_layer == 0 and boss.boss_state == boss.State.WARNING, "Slam approach temporarily removes body collision without ending its warning")
	local_player._try_execute_attack(Vector2.RIGHT)
	var after_attack: int = boss.get_current_health()
	check(after_attack < health_before and after_attack > 0, "A deliberate Attack still damages the approaching Slam boss through enemy-group targeting")
	local_player.reward_returning_crescent = true
	local_player.returning_crescent_stacks = 1
	local_player.returning_crescent_damage_scale = 1.0
	local_player.returning_crescent_reach_scale = 1.0
	local_player.returning_crescent.cancel()
	check(local_player.returning_crescent.try_launch(Vector2.RIGHT), "The local owner can launch Returning Crescent during the Slam approach")
	local_player.returning_crescent.tick(0.16)
	check(boss.get_current_health() < after_attack and boss.get_current_health() > 0 and boss.boss_state == boss.State.WARNING and boss.collision_layer == 0, "Returning Crescent still damages the approaching boss while its physical collision is disabled")
	local_player.returning_crescent.cancel()
	for property in saved_properties:
		local_player.set(property, saved_properties[property])
	local_player.global_position = saved_position
	local_player.discard_pending_combat_input()
	boss.health_state.current_health = health_before

func _test_pressure_sequence(client_id: int, root_kind: int) -> void:
	var label: String = "%s_%d_sequence" % [boss.boss_id, root_kind]
	boss.position = Vector2(-120.0, 0.0)
	_reset_players()
	boss._cancel_attack()
	var origin: Vector2 = boss.global_position
	var aim: Vector2 = local_player.global_position
	var forward: Vector2 = (aim - origin).normalized()
	boss.begin_attack(root_kind)
	var root_geometry: Array = boss.get_attack_warning_geometry()
	var root_serial: int = boss._attack_serial
	var escape_position: Vector2 = aim
	var followup_safe: Vector2 = aim
	match String(boss.boss_id):
		"kilnheart":
			escape_position = origin + Vector2(300.0, 0.0)
			followup_safe = origin
			if root_kind == 0:
				escape_position = boss._slam_landing + forward * 220.0
				followup_safe = boss._slam_landing + forward.rotated(PI * 0.25) * 220.0
			if root_kind == 2:
				escape_position = aim + Vector2(0.0, -140.0)
				followup_safe = escape_position + Vector2(0.0, -140.0)
		"glassweaver":
			if root_kind == 0 and root_geometry.size() == 2:
				var first_lane: Dictionary = root_geometry[0]
				var second_lane: Dictionary = root_geometry[1]
				escape_position = (Vector2(first_lane.start) + Vector2(first_lane.end) + Vector2(second_lane.start) + Vector2(second_lane.end)) * 0.25
				check(is_equal_approx(escape_position.distance_to(aim), 135.0), label + ": first warning moves its safe corridor away from the initial target")
			followup_safe = escape_position + forward * 200.0 + forward.orthogonal() * 200.0
			if root_kind == 1:
				escape_position = aim + forward.rotated(PI * 0.25) * 120.0
				followup_safe = aim + forward * 150.0
		"null_archivist":
			escape_position = aim + Vector2(300.0, 0.0)
			if root_kind == 2:
				escape_position = origin + forward.rotated(PI * 0.25) * 170.0
				followup_safe = origin
	check(not ALTERNATIVE_TEST.warning_contains(root_geometry, escape_position), label + ": first step has the promised escape or safe pocket")
	local_player.global_position = escape_position
	remote_player.global_position = escape_position
	_send_state()
	var received: Dictionary = await _inspect(client_id, label + "_root", {"expected_geometry": root_geometry})
	check(int(received.get("sequence_step", -1)) == 0 and int(received.get("serial", -1)) == root_serial, label + ": root cast identity arrives over the native RPC")
	boss._resolve_attack()
	check(local_player.get_current_health() == 500 and remote_player.get_current_health() == 500, label + ": both players can evade the first impact")
	var root_resolved: Dictionary = _send_state()
	received = await _inspect(client_id, label + "_gap", {"expected_geometry": [], "try_advance": true})
	check(received.get("geometry", []).is_empty() and int(received.get("sequence_step", -1)) == 0, label + ": joiner cannot start a queued follow-up itself")
	boss._process_behavior(0.1)
	check(boss.boss_state == boss.State.RECOVER and boss.get_attack_warning_geometry().is_empty(), label + ": the two impacts have a distinct empty gap")
	boss._process_behavior(0.2)
	var followup_geometry: Array = boss.get_attack_warning_geometry()
	var followup_serial: int = boss._attack_serial
	check(boss.boss_state == boss.State.WARNING and boss._sequence_step == 1 and followup_serial > root_serial, label + ": queued follow-up begins a fresh warning serial")
	check(is_equal_approx(boss.state_time_left, boss.warning_duration), label + ": crossing the gap preserves the complete follow-up warning")
	check(ALTERNATIVE_TEST.warning_contains(followup_geometry, escape_position) and not ALTERNATIVE_TEST.warning_contains(followup_geometry, followup_safe), label + ": follow-up pressures the previous escape while keeping a new safe region")
	local_player.global_position = escape_position
	remote_player.global_position = followup_safe
	var followup_packet: Dictionary = _send_state()
	var packet_bytes: int = var_to_bytes([{"enemy_id": 851 + boss_index, "payload": followup_packet}]).size() + 15
	check(packet_bytes <= 1392, label + ": follow-up fits an uncached ENet packet")
	received = await _inspect(client_id, label + "_warning", {"expected_geometry": followup_geometry, "try_damage": escape_position, "try_advance": true})
	check(int(received.get("serial", -1)) == followup_serial and int(received.get("sequence_step", -1)) == 1 and int(received.get("attack_kind", -1)) == boss.attack_kind and int(received.get("sequence_root", -1)) == root_kind and String(received.get("callout", "")) == boss.get_attack_callout(), label + ": joiner receives the exact follow-up cast identity and move name")
	check(received.get("geometry", []) == followup_geometry and received.get("local_calls", -1) == 0 and received.get("remote_calls", -1) == 0, label + ": replica cannot resolve or advance follow-up damage")
	_send_state(root_resolved)
	received = await _inspect(client_id, label + "_old_root_resolution")
	check(received.get("geometry", []) == followup_geometry and int(received.get("serial", -1)) == followup_serial, label + ": old root resolution cannot erase the newer warning")
	check(boss.get_attack_warning_geometry() == followup_geometry, label + ": player movement cannot retarget the committed follow-up")
	boss._resolve_attack()
	var health_after: int = local_player.get_current_health()
	boss._resolve_attack()
	check(health_after < 500 and local_player.get_current_health() == health_after and remote_player.get_current_health() == 500, label + ": host resolves the follow-up once and preserves its safe region")
	check((local_player as AlternativePlayer).damage_contexts.size() == 1 and (remote_player as AlternativePlayer).damage_contexts.is_empty(), label + ": overlapping tells and duplicate candidates produce one follow-up hit per victim")
	_send_state()
	received = await _inspect(client_id, label + "_resolved", {"expected_geometry": [], "health": {"host": health_after, "joiner": 500}})
	check(received.get("local_calls", -1) == 0 and received.get("remote_calls", -1) == 0, label + ": synchronized follow-up health never replays damage on the joiner")
	boss._process_behavior(boss.recover_time + 0.01)
	check(boss.boss_state == boss.State.IDLE and boss.get_attack_warning_geometry().is_empty(), label + ": final impact completes the sequence after normal recovery")
	await _test_queued_sequence_cancellation(client_id, root_kind, label)

func _test_queued_sequence_cancellation(client_id: int, root_kind: int, label: String) -> void:
	for mode in range(2):
		var dies: bool = mode == 1
		_reset_players()
		boss._cancel_attack()
		boss.begin_attack(root_kind)
		var warning: Array = boss.get_attack_warning_geometry()
		_send_state()
		var suffix: String = "_death" if dies else "_cancel"
		await _inspect(client_id, label + suffix + "_pending", {"expected_geometry": warning})
		local_player.global_position = Vector2(4000.0, 4000.0)
		remote_player.global_position = local_player.global_position
		boss._resolve_attack()
		if dies:
			boss.health_state.current_health = 0
		else:
			boss._cancel_attack()
		boss._process_behavior(0.3)
		check(boss.boss_state == boss.State.IDLE and boss.get_attack_warning_geometry().is_empty(), label + suffix + ": cancelled queued sequence cannot start its follow-up")
		check(local_player.get_current_health() == 500 and remote_player.get_current_health() == 500, label + suffix + ": cancellation cannot deal a late sequence hit")
		_send_state()
		var received: Dictionary = await _inspect(client_id, label + suffix + "_cleared", {"expected_geometry": [], "try_advance": true})
		check(received.get("geometry", []).is_empty() and int(received.get("phase", -1)) == boss.State.IDLE, label + suffix + ": native cancellation removes the joiner's pending warning")
		if dies:
			boss.health_state.current_health = boss.max_health

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"inspect":
			boss_index = int(payload.index)
			boss = bosses[boss_index]
			if payload.has("expected_snapshot"):
				check(await until(func(): return boss._received_snapshot >= int(payload.expected_snapshot)), "Joiner receives the expected ability snapshot: " + String(payload.key))
			if payload.has("expected_geometry"):
				var matched := await until(func(): return boss.get_attack_warning_geometry() == payload.expected_geometry)
				check(matched, "Joiner receives the expected live warning state: " + String(payload.key))
				if not matched:
					print("[ENet] warning mismatch ", payload.key, " actual=", _snapshot(), " expected=", payload.expected_geometry)
			if payload.has("try_damage"):
				_reset_players()
				local_player.global_position = payload.try_damage
				remote_player.global_position = payload.try_damage
				boss._resolve_attack()
			if bool(payload.get("try_advance", false)):
				boss._process_behavior(20.0)
			if payload.has("health"):
				check(await until(func(): return local_player.get_current_health() == int(payload.health.joiner) and remote_player.get_current_health() == int(payload.health.host)), "Joiner receives authoritative player health")
			if bool(payload.get("expire", false)):
				boss._process_network_visuals(5.0)
			world.fixture_result.rpc_id(1, payload.key, _snapshot())
		"finish":
			world.fixture_result.rpc_id(1, "finished", {})
			await create_timer(0.1).timeout
			await finish()
