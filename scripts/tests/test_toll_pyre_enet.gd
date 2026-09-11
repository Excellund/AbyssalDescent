extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Actual owner RPC effects, ordered pulse visuals, and existing Pyre death transport.

const TOLL_ID := 701
const PYRE_ID := 702
const PYRE := preload("res://scripts/enemy_pyre.gd")

class Toll extends "res://scripts/enemy_toll.gd":
	var deliveries: Array[int] = []
	var heal_flashes := 0
	func _emit_heal_success_vfx() -> void:
		heal_flashes += 1
		super._emit_heal_success_vfx()
	func _apply_custom_network_runtime_state(state: Dictionary) -> void:
		if state.get("pc") is Array:
			deliveries.append(int(state.pc[0]))
		super._apply_custom_network_runtime_state(state)

var toll: Toll
var pyre: Node2D
var owner_damage: Array[Dictionary] = []
var authoritative_damage: Array[Dictionary] = []

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	world.current_room_size = Vector2(1160, 860)
	world.current_effective_room_size = world.current_room_size
	for id in [1, client_id]:
		var actor := Player.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		actor.is_local_player = id == get_multiplayer().get_unique_id()
		circle(actor, 14.0)
		world.add_child(actor)
		actor.set_max_health_and_current(500, 500)
		actor.position = Vector2(180, 0) if id == 1 else Vector2(-180, 0)
		actor.arcana_motion.set_process(false)
		actor.returning_crescent.set_physics_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id, actor)
		actor.damage_taken.connect(func(raw, final, context): authoritative_damage.append({"peer": actor.player_id, "raw": raw, "final": final, "context": context}))
		if actor.is_local_player:
			local_player = actor
			world.player = actor
			actor.damage_taken.connect(func(raw, final, context): owner_damage.append({"raw": raw, "final": final, "context": context}))
		else:
			remote_player = actor
	toll = Toll.new()
	toll.name = "Toll"
	circle(toll, 34.0)
	world.add_child(toll)
	toll.set_physics_process(false)
	toll.target = local_player
	toll.target_candidates = [local_player, remote_player, remote_player]
	world.enemy_state_sync_broadcaster.register_enemy(toll, TOLL_ID)
	check(toll.network_simulation_enabled == (role == "host"), "Registration assigns real host and replica roles")
	pyre = PYRE.new()
	pyre.name = "Pyre"
	world.add_child(pyre)
	pyre.position = Vector2(180, 0)
	pyre.target = local_player
	pyre.set_physics_process(false)
	world.enemy_state_sync_broadcaster.register_enemy(pyre, PYRE_ID)
	world.active_room_enemy_count = 2

func _inspect(key: String, q: int = -1, step: float = 0.0, copies: int = 1) -> Dictionary:
	world.fixture_command.rpc_id(joiner_id, "inspect", {"key": key, "q": q, "step": step, "copies": copies})
	check(await until(func(): return results.has(key)), "Actual joiner reports " + key)
	return results.get(key, {})

func _send(state: Dictionary) -> void:
	world._sync_enemy_states.rpc([{"enemy_id": TOLL_ID, "runtime_state_delta": {"custom": state}}], 2)

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	toll._tick_aura(0.0)
	var report := await _inspect("aura")
	check(is_equal_approx(local_player.external_slow_mult, 0.55), "Aura reaches the host owner")
	check(is_equal_approx(float(report.get("slow_mult", 0)), 0.55) and float(report.get("slow_left", 0)) > 0.0, "Aura reaches the actual joiner through production slow RPC")
	toll._begin_pulse_telegraph()
	toll._tick_pulse(toll.pulse_telegraph_duration)
	toll._tick_pulse(0.6)
	toll._resolve_pulse_band_hits()
	toll._tick_pulse(0.02)
	report = await _inspect("pulse")
	var joiner_events := authoritative_damage.filter(func(event): return event.peer == client_id)
	check(report.get("health") == 482 and joiner_events.size() == 1, "Actual sweep damages joiner once despite repeated ticks and duplicate target entries")
	check(is_equal_approx(float(report.get("slow_mult", 0)), 0.18) and is_equal_approx(float(report.get("slow_left", 0)), 0.5), "Pulse routes its original heavy slow to joiner owner")
	if joiner_events.size() == 1:
		check(joiner_events[0].context.get("source") == "enemy_toll" and joiner_events[0].context.get("ability") == "pulse_hit" and joiner_events[0].raw == 18, "Pulse preserves damage amount and host-owned enemy/Oath accounting category")
	check(report.get("velocity", Vector2.ZERO).x < 0.0, "Existing outward impulse still reaches actual joiner")
	toll._end_pulse()
	toll._pulse_count = 2
	local_player.position = Vector2(180, 77)
	toll._begin_pulse_telegraph()
	world.enemy_state_sync_broadcaster.tick(0.25)
	var warning := toll._get_custom_network_runtime_state()
	# The broadcaster sampled q before this manual read advances an active heartbeat.
	var warning_q := int(warning.pc[0]) - 1
	report = await _inspect("warning_lost", warning_q, 0.7)
	check(report.get("geometry", {}).is_empty() and report.get("phase") == Toll.PULSE_PHASE_NONE, "Lost warning expires through real replica physics without inferred activation")
	_send(warning)
	report = await _inspect("warning_recovery", int(warning.pc[0]))
	check(report.get("phase") == Toll.PULSE_PHASE_TELEGRAPH, "A newer host warning heartbeat recovers a leased visual")
	toll._tick_pulse(toll.pulse_telegraph_duration)
	toll._tick_pulse(0.25)
	var active := toll._get_custom_network_runtime_state()
	_send(active)
	report = await _inspect("active", int(active.pc[0]))
	check(report.get("phase") == Toll.PULSE_PHASE_EXPAND and not report.get("geometry", {}).is_empty(), "Actual custom receiver accepts expanding pulse geometry")
	check(absf(float(report.get("angle", 99)) - float(active.pc[5]) / 10000.0) < 0.00001, "Integer spoke angle preserves sub-quantum aim precision")
	report = await _inspect("active_lost_final", int(active.pc[0]), 0.4)
	check(report.get("geometry", {}).is_empty() and report.get("health") == 482, "Lost final packet expires lease without replica damage")
	_send(active)
	report = await _inspect("duplicate", int(active.pc[0]), 0.0, 2)
	check(report.get("geometry", {}).is_empty(), "Duplicate old active packet cannot revive expired visual")
	var wrong_room := active.duplicate(true)
	wrong_room.pc[0] += 1000
	wrong_room.pc[1] = 6
	_send(wrong_room)
	report = await _inspect("wrong_room", int(wrong_room.pc[0]))
	check(report.get("q") == active.pc[0] and report.get("geometry", {}).is_empty(), "Stale room cannot revive or poison accepted sequence")
	toll._heal_channel_left = 0.73
	toll._heal_silenced_flash = 0.23
	toll._stagger_left = 0.17
	var recovery := toll._get_custom_network_runtime_state()
	_send(recovery)
	report = await _inspect("active_recovery", int(recovery.pc[0]))
	check(report.get("phase") == Toll.PULSE_PHASE_EXPAND and is_equal_approx(float(report.get("heal", 0)), 0.73), "New heartbeat recovers active phase and preserves heal companion state")
	toll._end_pulse()
	var ended := toll._get_custom_network_runtime_state()
	_send(ended)
	report = await _inspect("ended", int(ended.pc[0]))
	check(report.get("phase") == Toll.PULSE_PHASE_NONE, "Authoritative end clears pulse")
	_send(recovery)
	report = await _inspect("old_after_end", int(recovery.pc[0]), 0.0, 2)
	check(report.get("phase") == Toll.PULSE_PHASE_NONE and report.get("q") == ended.pc[0], "Delayed active packet cannot revive after host end")
	toll._heal_success_flash = 0.55
	var heal_high := toll._get_custom_network_runtime_state()
	_send(heal_high)
	report = await _inspect("heal_success", int(heal_high.pc[0]))
	check(report.get("flashes") == 1, "New authoritative heal-success rising edge displays exactly one effect")
	_send(ended)
	await _inspect("stale_heal_low", int(ended.pc[0]), 0.0, 2)
	_send(heal_high)
	report = await _inspect("duplicate_heal_high", int(heal_high.pc[0]), 0.0, 2)
	check(report.get("flashes") == 1, "Stale low then duplicate high cannot retrigger heal-success presentation")
	toll._heal_success_flash = 0.0
	var heal_low := toll._get_custom_network_runtime_state()
	_send(heal_low)
	await _inspect("next_heal_low", int(heal_low.pc[0]))
	toll._heal_success_flash = 0.55
	var next_heal := toll._get_custom_network_runtime_state()
	_send(next_heal)
	report = await _inspect("next_heal_high", int(next_heal.pc[0]))
	check(report.get("flashes") == 2, "A real new low-to-high heal cycle can display its next effect")
	DAMAGE.apply_damage(pyre, 10000, {"source_peer_id": 1, "source": "melee"})
	check(pyre.is_queued_for_deletion() and get_nodes_in_group("enemy_lingering_effects").size() == 1, "Actual Pyre death retains host field after its owner dies")
	world.fixture_command.rpc_id(client_id, "pyre_lifetime")
	check(await until(func(): return results.has("pyre_lifetime")), "Joiner reports actual replicated Pyre death field")
	var field_report: Dictionary = results.get("pyre_lifetime", {})
	check(field_report.get("visual_only", false) and field_report.get("survives_before", false), "Actual death RPC creates targetless zero-damage replica with its original lifetime")
	check(field_report.get("readable_before", false), "Actual Pyre replica keeps readable danger through its final active interval")
	check(field_report.get("expired", false) and field_report.get("health") == 482, "Replica field expires and cannot damage the joining player")
	check(field_report.get("hidden_at_expiry", false), "Actual Pyre replica hides at lifetime expiry before deferred deletion")
	for field in get_nodes_in_group("enemy_lingering_effects"):
		field.queue_free()
	world.fixture_command.rpc_id(client_id, "finish")
	check(await until(func(): return results.has("finished")), "Joiner acknowledges before transport teardown")
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"inspect":
			if int(payload.q) >= 0:
				check(await until(func(): return toll.deliveries.count(int(payload.q)) >= int(payload.copies)), "Real custom packet reaches joiner for " + payload.key)
			if float(payload.step) > 0.0:
				toll._physics_process(float(payload.step))
			var before := local_player.get_current_health()
			toll._tick_pulse(1.0)
			toll._resolve_pulse_band_hits()
			toll._apply_pulse_hit(local_player, 180.0)
			check(local_player.get_current_health() == before, "Replica pulse methods cannot apply local damage")
			world.fixture_result.rpc_id(1, payload.key, {"slow_mult": local_player.external_slow_mult, "slow_left": local_player.external_slow_left, "health": local_player.get_current_health(), "velocity": local_player.velocity, "damage": owner_damage, "geometry": toll.get_pulse_geometry(), "phase": toll._pulse_phase, "q": toll._pulse_received_sequence, "angle": toll._directed_spoke_angle, "heal": toll._heal_channel_left, "flashes": toll.heal_flashes})
		"pyre_lifetime":
			check(await until(func(): return not get_nodes_in_group("enemy_lingering_effects").is_empty()), "Real enemy-death RPC creates Pyre replica field")
			var fields := get_nodes_in_group("enemy_lingering_effects")
			var report := {"visual_only": false, "survives_before": false, "readable_before": false, "expired": false, "hidden_at_expiry": false, "health": local_player.get_current_health()}
			if fields.size() == 1:
				var field: Node2D = fields[0]
				field.set_process(false)
				report.visual_only = field.target == null and field.tick_damage == 0 and is_equal_approx(field.duration, 6.5)
				field._process(maxf(0.0, field.time_left - 0.01))
				report.survives_before = not field.is_queued_for_deletion() and field.time_left > 0.0
				var late_visual: Dictionary = field.get_visual_state()
				report.readable_before = field.visible and late_visual.active and float(late_visual.fill_alpha) >= 0.14 and float(late_visual.boundary_alpha) >= 0.7
				field._process(0.02)
				report.expired = field.is_queued_for_deletion() and field.time_left == 0.0
				var expired_visual: Dictionary = field.get_visual_state()
				report.hidden_at_expiry = not field.visible and not expired_visual.active and float(expired_visual.fill_alpha) == 0.0 and float(expired_visual.boundary_alpha) == 0.0
				await process_frame
				report.health = local_player.get_current_health()
			world.fixture_result.rpc_id(1, "pyre_lifetime", report)
		"finish":
			world.fixture_result.rpc_id(1, "finished", {})
			await create_timer(0.05).timeout
			await finish()
