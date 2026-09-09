extends "res://scripts/tests/test_live_arena_edges.gd"
## Actual beam state, accepted damage and warning geometry share these cases.

const TETHER := preload("res://scripts/enemy_tether.gd")
const DIFFICULTY := preload("res://scripts/difficulty_config.gd")
const PLAYER_FLOW := preload("res://scripts/core/player_flow_coordinator.gd")

class Tether extends "res://scripts/enemy_tether.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)

class Probe extends Node2D:
	var health_state := preload("res://scripts/health_state.gd").new()
	var attempts := 0
	var on_hit: Callable
	func _ready() -> void:
		add_child(health_state)
		health_state.setup(10000)
	func is_dead() -> bool:
		return health_state.is_dead()
	func take_damage(amount: int, _context: Dictionary = {}) -> void:
		attempts += 1
		health_state.take_damage(amount)
		if on_hit.is_valid():
			on_hit.call()

var first: Tether
var partner: Tether

func _probe(position: Vector2) -> Probe:
	var probe := Probe.new()
	room.add_child(probe)
	probe.global_position = position
	return probe

func _tether(position: Vector2, network_id: int) -> Tether:
	var enemy := Tether.new()
	_circle(enemy, 14.0)
	room.add_child(enemy)
	enemy.global_position = position
	enemy.set_meta("network_enemy_id", network_id)
	enemy.move_speed = 0.0
	enemy.crowd_separation_strength = 0.0
	return enemy

func _setup_pair() -> void:
	_setup()
	actor.global_position = Vector2(450.0, 300.0)
	first = _tether(Vector2(-200.0, 0.0), 901)
	partner = _tether(Vector2(200.0, 0.0), 902)
	first.beam_partner = partner
	partner.beam_partner = first

func _begin(players: Array) -> void:
	first.target_candidates = players.duplicate()
	first.target = players[0] if not players.is_empty() else null
	first._enter_windup_state()
	first._enter_beam_state()

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	await _test_area_and_cadence()
	await _test_histories_and_solver()
	await _test_lifetime_and_pair_cleanup()
	await _test_resets_and_membership()
	await _test_ruinous_interruptions()
	await _test_freed_partner_physics()
	await _test_freed_target_physics()
	await _test_geometry_and_wire()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Tether hazard: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_freed_target_physics() -> void:
	for queued in [false,true]:
		_setup_pair()
		var player := _probe(Vector2.ZERO)
		_begin([player])
		await physics_frame
		first.target_candidates.clear()
		if queued:player.queue_free()
		else:player.free()
		_check(first._get_beam_damageable_targets().is_empty(), "A queued or freed current target is rejected by the empty-roster fallback")
		first._physics_process(0.02)
		_check(first._beam_pending_contacts.is_empty() and first._beam_player_positions.is_empty(), "Inherited physics removes the departing target's contact and motion history")
		if queued:
			_check(player.attempts == 0, "A queued current target receives no final beam tick")
			await process_frame
			first._physics_process(0.02)
		_check(first.target == null and first._get_beam_damageable_targets().is_empty(), "Inherited refresh clears the freed current target without a typed-reference error")
		var newcomer := _probe(Vector2(0.0,-100.0))
		first.set_target_candidates([newcomer])
		first._process_beam(first.beam_tick_interval)
		_check(first.target == newcomer and newcomer.attempts == 0, "A replacement target starts with its own position and no phantom crossing")
		newcomer.global_position.y = 100.0
		first._process_beam(first.beam_tick_interval)
		_check(newcomer.attempts == 1, "A replacement target's later deliberate crossing keeps ordinary area-damage eligibility")
		_clear()

func _test_area_and_cadence() -> void:
	for tier in range(4):
		for count in range(1, 5):
			_setup_pair()
			room.current_difficulty_tier = tier
			room.current_difficulty_config = DIFFICULTY.get_tier_config(tier)
			var players: Array = []
			for index in range(count):
				players.append(_probe(Vector2(-80.0 + index * 40.0, 0.0)))
			_begin(players)
			first.target_candidates.append(players[0])
			await physics_frame
			first._process_beam(0.02)
			for player in players:
				_check(player.attempts == 1 and player.health_state.current_health == 9991, "Bearing%d player receives one original9-damage area tick" % tier)
			first._process_beam(0.1)
			_check(players[0].attempts == 1, "The existing0.2-second cadence prevents an early second hit")
			first._process_beam(0.7)
			_check(players[0].attempts == 2, "A hitch delivers at most one due tick, not catch-up bursts")
			partner.target_candidates = players.duplicate()
			partner.target = players[0]
			partner._enter_windup_state()
			partner._enter_beam_state()
			partner._try_apply_beam_damage()
			_check(players[0].attempts == 2 and partner.get_beam_geometry().is_empty(), "The opposite endpoint cannot own a duplicate beam")
			_clear()

func _test_histories_and_solver() -> void:
	_setup_pair()
	var above := _probe(Vector2(0.0, -100.0))
	var below := _probe(Vector2(0.0, 100.0))
	_begin([above, below])
	await physics_frame
	first._process_beam(0.02)
	first._set_target_node(below)
	first._process_beam(0.21)
	_check(above.attempts == 0 and below.attempts == 0, "AI target handoff does not draw a movement path between different players")
	above.global_position.y = 100.0
	first._process_beam(0.21)
	_check(above.attempts == 1 and below.attempts == 0, "Only the player whose own movement crosses the beam is hit")
	var newcomer := _probe(Vector2(0.0, -100.0))
	first.target_candidates.append(newcomer)
	first._process_beam(0.21)
	_check(newcomer.attempts == 0, "A newly eligible player has no invented historical segment")
	var thin := first._moving_beam_sweep_nearest_distance(Vector2(0.0, -70.0), Vector2(0.0, 74.0), Vector2(-200.0, 0.0), Vector2(200.0, 0.0), Vector2(-200.0, 0.0), Vector2(200.0, 0.0))
	_check(thin < 0.001, "Fast crossing of a1px beam cannot fall between samples")
	var parallel := first._moving_beam_sweep_nearest_distance(Vector2(-100.0, 0.0), Vector2(100.0, 0.0), Vector2(-50.0, -100.0), Vector2(-50.0, 100.0), Vector2(150.0, -100.0), Vector2(150.0, 100.0))
	_check(absf(parallel - 50.0) < 0.001, "Parallel player and beam movement at50px separation stays safe")
	var swapped := first._moving_beam_sweep_nearest_distance(Vector2(0.0, 10.0), Vector2(0.0, 10.0), Vector2(-100.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 0.0), Vector2(-100.0, 0.0))
	_check(absf(swapped - 10.0) < 0.001, "Swapping endpoints stays finite when the segment collapses")
	var started := Time.get_ticks_usec()
	for index in range(1000):
		var offset := float(index % 41)
		first._moving_beam_sweep_nearest_distance(Vector2(-200.0, offset), Vector2(180.0, 35.0), Vector2(-100.0, -90.0), Vector2(170.0, 70.0), Vector2(90.0, 170.0), Vector2(-80.0, -100.0))
	print("[MEASURE] Tether1000 rotating sweeps microseconds=", Time.get_ticks_usec() - started)
	_clear()

func _test_lifetime_and_pair_cleanup() -> void:
	for tick in [0.1, 0.005]:
		_setup_pair()
		var player := _probe(Vector2.ZERO)
		_begin([player])
		first.state_time_left = 0.01
		first.beam_tick_left = tick
		await physics_frame
		first._process_beam(0.2)
		_check(player.attempts == (1 if tick < 0.01 else 0), "Only a tick scheduled before expiry survives a hitch")
		_check(first.tether_state == first.STATE_RECOVER and first._beam_player_positions.is_empty() and first._beam_pending_contacts.is_empty(), "Expiry clears history and enters the unchanged recovery")
		_clear()
	_setup_pair()
	var player := _probe(Vector2.ZERO)
	_begin([player])
	var replacement := _tether(Vector2(0.0, 260.0), 903)
	first.beam_partner = replacement
	first._process_beam(0.02)
	_check(player.attempts == 0 and first.tether_state == first.STATE_RECOVER, "Replacing the partner requires a fresh warning instead of sweeping the old link")
	first.beam_partner = partner
	_begin([player])
	partner.health_state.take_damage(partner.health_state.current_health)
	first._process_beam(0.02)
	_check(player.attempts == 0 and first.get_beam_geometry().is_empty(), "A dead partner cancels damage and geometry immediately")
	_clear()
	_setup_pair()
	var first_player := _probe(Vector2.ZERO)
	var second_player := _probe(Vector2.ZERO)
	first_player.on_hit = func(): first.health_state.take_damage(first.health_state.current_health)
	_begin([first_player, second_player])
	await physics_frame
	first._process_beam(0.02)
	_check(first_player.attempts == 1 and second_player.attempts == 0, "Synchronous owner death stops the remaining damage loop")
	_clear()

func _test_geometry_and_wire() -> void:
	_setup_pair()
	var inside := _probe(Vector2(0.0, 23.0))
	var outside := _probe(Vector2(0.0, 25.0))
	var cap_inside := _probe(Vector2(223.0, 0.0))
	var cap_outside := _probe(Vector2(225.0, 0.0))
	_begin([inside, outside, cap_inside, cap_outside])
	await physics_frame
	var polygons := first.get_beam_polygons()
	for player in [inside, cap_inside]:
		_check(Geometry2D.is_point_in_polygon(player.global_position, polygons[0]), "The full active capsule shows accepted side and cap contacts")
	for player in [outside, cap_outside]:
		_check(not Geometry2D.is_point_in_polygon(player.global_position, polygons[0]), "Outside side and cap points stay outside the warning")
	first._process_beam(0.02)
	_check(inside.attempts == 1 and cap_inside.attempts == 1 and outside.attempts == 0 and cap_outside.attempts == 0, "Actual area damage agrees with both drawn rounded boundaries")
	var remote := _tether(Vector2(80.0, 140.0), 904)
	remote.set_network_simulation_enabled(false)
	var warning := first.get_projectile_network_sync_state()
	remote.apply_projectile_network_sync_state(warning)
	_check(remote.get_beam_geometry() == first.get_beam_geometry(), "Replica uses exact host endpoints despite a displaced enemy body")
	var newer := first._get_custom_network_runtime_state()
	remote._apply_custom_network_runtime_state(newer)
	remote.apply_projectile_network_sync_state(warning)
	_check(remote._beam_received_sequence == newer["beam"][0], "Both channels share one monotonic state order")
	remote._process_network_visuals(TETHER.BEAM_VISUAL_LEASE + 0.01)
	_check(remote.get_beam_geometry().is_empty() and not remote.is_beam_state_active(), "Lost final state expires both geometry and active-body presentation")
	remote._apply_custom_network_runtime_state(newer)
	_check(remote.get_beam_geometry().is_empty(), "Equal stale runtime cannot revive an expired beam")
	first._enter_recover_state()
	var cancelled := first._get_custom_network_runtime_state()
	remote._apply_custom_network_runtime_state(cancelled)
	remote.apply_projectile_network_sync_state(warning)
	_check(remote.get_beam_geometry().is_empty(), "Old projectile state cannot overwrite a newer cancellation")
	_clear()

func _test_resets_and_membership() -> void:
	_setup_pair()
	var player := _probe(Vector2(0.0, -100.0))
	_begin([player])
	await physics_frame
	var flow := PLAYER_FLOW.new()
	flow.reset_player_position(player, Vector2(0.0, 100.0))
	first._process_beam(0.02)
	_check(player.attempts == 0 and int(player.get_meta("combat_position_reset_generation", 0)) == 1, "Explicit position reset seeds a new history without an invented beam crossing")
	player.global_position.y = -100.0
	first._process_beam(0.21)
	_check(player.attempts == 1, "Ordinary subsequent movement still crosses after explicit reset")
	var saved_bounds := room.current_effective_room_size
	room.current_effective_room_size = Vector2(600.0, 600.0)
	first._process_beam(0.21)
	_check(player.attempts == 1 and first._beam_player_positions.is_empty(), "Changed room bounds cancel a prior geometry sweep before world clamps can invent contact")
	room.current_effective_room_size = saved_bounds
	actor.global_position = Vector2.ZERO
	actor.set_combat_removed(true)
	_begin([actor])
	first._process_beam(0.02)
	_check(first._beam_player_positions.is_empty() and first._beam_pending_contacts.is_empty(), "Removed avatars are not eligible area contacts")
	actor.set_combat_removed(false)
	_begin([player])
	first._beam_pending_contacts[player.get_instance_id()] = true
	first.target = null
	first.target_candidates.clear()
	first._process_beam(0.21)
	_check(first._beam_player_positions.is_empty() and player.attempts == 1, "Departed candidates discard pending crossings without damaging a stale target")
	first.set_network_simulation_enabled(false)
	first._try_apply_beam_damage()
	_check(first._beam_player_positions.is_empty() and player.attempts == 1, "Losing authority cancels host contact history")
	_clear()

func _test_ruinous_interruptions() -> void:
	for launch_partner in [false, true]:
		for warning in [false, true]:
			_setup_pair()
			var player := _probe(Vector2.ZERO)
			_begin([player])
			if warning:
				first._enter_windup_state()
			var launched: Tether = partner if launch_partner else first
			actor.apply_upgrade("ruinous_impact")
			actor.apply_trial_power("blast_drive")
			actor.global_position = launched.global_position + Vector2(-90.0, 0.0)
			actor.damage = 5
			await physics_frame
			actor.perform_motion_blast(Vector2.RIGHT, 1.0)
			_check(launched.get_launch_state().active, "Real Blast plus Ruinous launches either Tether endpoint")
			_check(first.get_beam_geometry().is_empty(), "Forced endpoint movement immediately suppresses obsolete hazard geometry")
			first._physics_process(0.02)
			_check(first.tether_state == first.STATE_RECOVER and first._beam_player_positions.is_empty() and player.attempts == 0, "Ruinous interrupts before EnemyBase launch ownership can freeze or replay the beam")
			_clear()

func _test_freed_partner_physics() -> void:
	for freed_immediately in [false, true]:
		_setup_pair()
		var player := _probe(Vector2.ZERO)
		_begin([player])
		await physics_frame
		if freed_immediately:
			partner.free()
		else:
			partner.queue_free()
		first._physics_process(0.02)
		_check(first.tether_state == first.STATE_RECOVER and first.get_beam_geometry().is_empty() and player.attempts == 0, "Queued or freed endpoint cancels safely through inherited physics before contact")
		_clear()
