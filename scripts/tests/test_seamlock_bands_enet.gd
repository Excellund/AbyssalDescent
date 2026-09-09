extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Separate native ENet processes, production runtime/projectile receivers.

const SEAMLOCK_ID := 601
const STATES := preload("res://scripts/shared/enemy_state_enums.gd")
const BAND_TARGET := preload("res://scripts/tests/test_drifter_replication.gd")

class Seamlock extends "res://scripts/enemy_seamlock.gd":
	var deliveries: Array[Dictionary] = []
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _apply_custom_network_runtime_state(state: Dictionary) -> void:
		deliveries.append({"channel": "custom", "q": state.get("q", -1)})
		super._apply_custom_network_runtime_state(state)
	func apply_projectile_network_sync_state(state: Dictionary) -> void:
		deliveries.append({"channel": "projectile", "q": state.get("q", -1)})
		super.apply_projectile_network_sync_state(state)

var seamlock: Seamlock
var band_target: Node2D

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	for id in [1, client_id]:
		var actor := Player.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		world.add_child(actor)
		actor.position = Vector2(-200.0, 0.0)
		actor.arcana_motion.set_process(false)
		actor.arcana_motion.visible = false
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	band_target = BAND_TARGET.TestTarget.new()
	band_target.name = "BandTarget"
	world.add_child(band_target)
	band_target.position = Vector2(200.0, 0.0)
	seamlock = Seamlock.new()
	seamlock.name = "Seamlock"
	world.add_child(seamlock)
	seamlock.target = band_target
	world.enemy_state_sync_broadcaster.register_enemy(seamlock, SEAMLOCK_ID)
	world.active_room_enemy_count = 1
	check(seamlock.network_simulation_enabled == (role == "host"), "Production registration assigns host and replica authority")

func _send_custom(state: Dictionary) -> void:
	world._sync_enemy_states.rpc([{"enemy_id": SEAMLOCK_ID, "runtime_state_delta": {"custom": state}}], 1)

func _send_projectile(state: Dictionary, room: int = 7) -> void:
	world._sync_archer_projectile_states.rpc([{"enemy_id": SEAMLOCK_ID, "payload": state}], room)

func _inspect(key: String, channel: String, sequence: int, step: float = 0.0, expected_count: int = 1) -> Dictionary:
	world.fixture_command.rpc_id(joiner_id, "inspect", {"key": key, "channel": channel, "q": sequence, "step": step, "count": expected_count})
	check(await until(func(): return results.has(key)), "Joiner reports %s through the fixture acknowledgment" % key)
	return results.get(key, {})

func _measure_payloads() -> void:
	var measurements: Array[Dictionary] = []
	for phase in ["band", "spiral", "illusions", "illusions_and_spiral"]:
		seamlock._illusion_positions.clear()
		seamlock._illusion_shatter_times.clear()
		seamlock._spiral_arms.clear()
		seamlock._spiral_hit_cooldowns.clear()
		seamlock._spiral_active = false
		seamlock._enter_band_attack()
		if phase in ["spiral", "illusions_and_spiral"]:
			seamlock._enter_spiral()
			seamlock._launch_spiral_arms()
		if phase in ["illusions", "illusions_and_spiral"]:
			seamlock.seamlock_state = STATES.SeamlockState.ILLUSION_PHASE
			seamlock._illusion_positions = [Vector2(100, 100), Vector2(-100, 100), Vector2(0, -100)]
			seamlock._illusion_shatter_times = [0.0, 0.0, 0.0]
		for channel in ["custom", "projectile"]:
			var payload := seamlock._get_custom_network_runtime_state() if channel == "custom" else seamlock.get_projectile_network_sync_state()
			var legacy := payload.duplicate(true)
			legacy.erase("q")
			legacy.erase("r")
			var entry := {"enemy_id": SEAMLOCK_ID, "runtime_state_delta": {"custom": payload}} if channel == "custom" else {"enemy_id": SEAMLOCK_ID, "payload": payload}
			var envelope_budget := 220 if channel == "custom" else 160
			var encoded_with_budget := var_to_bytes(entry).size() + envelope_budget
			measurements.append({"phase": phase, "channel": channel, "encoded_payload": var_to_bytes(payload).size(), "legacy_encoded_payload": var_to_bytes(legacy).size(), "encoded_entry": var_to_bytes(entry).size(), "estimated_entry": world.enemy_state_sync_broadcaster.estimate_variant_size_bytes(entry), "encoded_entry_plus_reserved_overhead": encoded_with_budget})
			check(encoded_with_budget < world.enemy_state_sync_broadcaster.transport_mtu_bytes, "%s %s remains within configured MTU including reserved overhead" % [phase, channel])
	results["payload_measurements"] = measurements
	seamlock._illusion_positions.clear()
	seamlock._illusion_shatter_times.clear()
	seamlock._spiral_arms.clear()
	seamlock._spiral_hit_cooldowns.clear()
	seamlock._spiral_active = false

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	_measure_payloads()
	seamlock._enter_band_attack()
	seamlock._band_windup_left = 0.2
	world.enemy_state_sync_broadcaster.tick(0.25)
	var warning_q := seamlock._attack_state_sequence
	var warning := await _inspect("custom_warning", "custom", warning_q, 0.3)
	if not warning.is_empty():
		check(warning.warning == 0.0 and not warning.active and warning.arms.is_empty(), "Custom warning expiry cannot invent a band or spiral")
		check(warning.hits == 0, "Warning expiry causes no replica damage")
	seamlock._band_windup_left = 0.0
	seamlock._band_is_active = true
	seamlock._band_duration_left = 0.2
	seamlock._band_tick_left = 0.1
	var older_custom := seamlock._get_custom_network_runtime_state()
	world._sync_archer_projectile_state_tick(0.1)
	var active_q := seamlock._attack_state_sequence
	var active := await _inspect("projectile_active", "projectile", active_q)
	if not active.is_empty():
		check(active.active and is_equal_approx(active.life, 0.2), "Production projectile tick activates the host band on the joiner")
		check(active.hits == 0, "Calling a replica's band damage hook cannot damage its target")
	seamlock._process_band_attack(0.4)
	check(band_target.hits == 1 and seamlock.seamlock_state == STATES.SeamlockState.SPIRAL, "Host hitch clips damaging time and transitions once to spiral windup")
	# Deliberately omit the host's final packet; use actual EnemyBase replica physics.
	var expired := await _inspect("lost_final", "projectile", active_q, 0.4)
	if not expired.is_empty():
		check(not expired.active and expired.life == 0.0 and expired.arms.is_empty(), "Replica expires an active band without receiving its final packet")
		check(expired.hits == 0 and expired.state == STATES.SeamlockState.BAND_ATTACK, "Replica expiry does not simulate damage or infer the next attack")
	_send_custom(older_custom)
	var old := await _inspect("old_custom", "custom", older_custom.q)
	if not old.is_empty():
		check(not old.active and old.q == active_q, "Late custom state cannot revive an expired newer projectile band")
	seamlock._process_spiral(seamlock.spiral_windup)
	world.enemy_state_sync_broadcaster.tick(0.25)
	var spiral_q := seamlock._attack_state_sequence
	var spiral := await _inspect("custom_spiral", "custom", spiral_q)
	if not spiral.is_empty():
		check(spiral.state == STATES.SeamlockState.SPIRAL and spiral.arms.size() == 4 and not spiral.active, "Actual custom broadcaster delivers the next four-arm spiral")
		check(spiral.hits == 0, "Receiving the spiral does not invoke host damage")
	var old_projectile := seamlock.get_projectile_network_sync_state()
	seamlock.seamlock_state = STATES.SeamlockState.ILLUSION_PHASE
	seamlock._illusion_phase_left = 1.2
	seamlock._illusion_positions = [Vector2(90, 70), Vector2(-90, 70)]
	seamlock._illusion_shatter_times = [0.1, 0.2]
	var illusion_custom := seamlock._get_custom_network_runtime_state()
	_send_custom(illusion_custom)
	var illusion := await _inspect("new_custom", "custom", illusion_custom.q)
	if not illusion.is_empty():
		check(illusion.illusions == seamlock._illusion_positions and illusion.shatters == seamlock._illusion_shatter_times and illusion.arms.size() == 4, "Custom ordering preserves existing illusion and independent spiral state")
	_send_projectile(old_projectile)
	var late := await _inspect("old_projectile", "projectile", old_projectile.q)
	if not late.is_empty():
		check(late.q == illusion_custom.q and late.state == STATES.SeamlockState.ILLUSION_PHASE and late.illusions == seamlock._illusion_positions, "Late projectile cannot roll back newer custom attack state")
	var wrong_room := old_projectile.duplicate(true)
	wrong_room.q = illusion_custom.q + 1000
	wrong_room.r = 6
	_send_projectile(wrong_room)
	var rejected := await _inspect("payload_room", "projectile", wrong_room.q)
	if not rejected.is_empty():
		check(rejected.q == illusion_custom.q and rejected.illusions == seamlock._illusion_positions, "Inner room identifier rejects stale projectile state without poisoning sequence")
	var custom_room := illusion_custom.duplicate(true)
	custom_room.q = wrong_room.q + 1
	custom_room.r = 6
	_send_custom(custom_room)
	rejected = await _inspect("custom_room", "custom", custom_room.q)
	if not rejected.is_empty():
		check(rejected.q == illusion_custom.q, "Custom channel independently rejects a prior room")
	var next_state := seamlock.get_projectile_network_sync_state()
	_send_projectile(next_state, 6)
	world.fixture_command.rpc_id(client_id, "outer_room", {"q": next_state.q})
	check(await until(func(): return results.has("outer_room")), "Joiner checks the outer projectile room filter")
	if results.has("outer_room"):
		check(results.outer_room.filtered, "Stale outer room never reaches the enemy's projectile receiver")
	_send_projectile(next_state)
	var resumed := await _inspect("current_room", "projectile", next_state.q)
	if not resumed.is_empty():
		check(resumed.q == next_state.q and resumed.illusions == seamlock._illusion_positions and resumed.arms.size() == 4, "Current room heartbeat recovers both existing attack components")
	world.fixture_command.rpc_id(client_id, "finish")
	check(await until(func(): return results.has("finished")), "Joiner acknowledges completion before closing its transport")
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"inspect":
			var arrived := await until(func(): return seamlock.deliveries.filter(func(entry): return entry.channel == payload.channel and entry.q == payload.q).size() >= int(payload.count))
			check(arrived, "Real %s packet reached joiner for %s" % [payload.channel, payload.key])
			if float(payload.step) > 0.0:
				seamlock._physics_process(float(payload.step))
			seamlock._try_band_damage()
			world.fixture_result.rpc_id(1, payload.key, {"q": seamlock._received_attack_state_sequence, "active": seamlock._band_is_active, "warning": seamlock._band_windup_left, "life": seamlock._band_duration_left, "state": seamlock.seamlock_state, "arms": seamlock._spiral_arms.duplicate(true), "illusions": seamlock._illusion_positions.duplicate(), "shatters": seamlock._illusion_shatter_times.duplicate(), "hits": band_target.hits})
		"outer_room":
			await create_timer(0.08).timeout
			world.fixture_result.rpc_id(1, "outer_room", {"filtered": seamlock.deliveries.filter(func(entry): return entry.channel == "projectile" and entry.q == payload.q).is_empty()})
		"finish":
			# Stop fixture observers before the host closes ENet; no world scene
			# transition callback is installed by this isolated World._ready seam.
			local_player.visible = false
			remote_player.visible = false
			world.fixture_result.rpc_id(1, "finished", {})
			await create_timer(0.05).timeout
			await finish()
		_:
			super.client_command(command, payload)
