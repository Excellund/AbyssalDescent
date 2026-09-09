extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Actual loopback ownership, live room bounds, and production feedback RPCs.

const MOTION := preload("res://scripts/arcana_motion_controller.gd")

class EdgePlayer extends Player:
	var aim := Vector2.LEFT
	func _get_mouse_attack_direction() -> Vector2:
		return aim

var saved_blade_state: Dictionary = {}

func setup_actors(client_id: int) -> void:
	world.current_room_size = Vector2(1160.0, 860.0)
	world.current_effective_room_size = world.current_room_size
	var feedback := ImpactFeedback.new()
	world.add_child(feedback)
	feedback._impact_sound.stream = null
	EnemyReplicationService._ruinous_feedback = feedback
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	for id in [1, client_id]:
		var actor := EdgePlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor, 14.0)
		world.add_child(actor)
		actor.global_position = Vector2.ZERO if id == 1 else Vector2(450.0, 0.0)
		actor.damage = 40
		actor.apply_upgrade("ruinous_impact")
		actor.apply_trial_power("blast_drive")
		actor.apply_trial_power("razor_orbit")
		for _index in range(3):
			actor.apply_trial_power("returning_crescent")
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
		actor.returning_crescent.set_physics_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	for id in [601, 602, 603, 604]:
		var target := Enemy.new()
		target.name = "Enemy_%d" % id
		circle(target, 13.0)
		world.add_child(target)
		target.health_state.setup(1000, 1000)
		target.global_position = {601: Vector2(550.0, 0.0), 602: Vector2(550.0, 150.0), 603: Vector2(560.0, 0.0), 604: Vector2(550.0, -280.0)}[id]
		world.enemy_state_sync_broadcaster.register_enemy(target, id)
	# Only the tested victim occupies the launch lane in the first phase.
	enemy(603).global_position = Vector2(-400.0, -200.0)

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	world.fixture_command.rpc_id(client_id, "edge_strike")
	check(await until(func(): return enemy(601).get_current_health() == 980), "A real joiner strike reaches the host's edge victim once")
	var launch := enemy(601).get_launch_state()
	check(launch.active and launch.source_peer_id == client_id and launch.owner_id == remote_player.get_instance_id(), "The edge launch retains authenticated joiner ownership")
	launch.step(enemy(601), 0.3)
	check(enemy(601).global_position == Vector2(580.0, 0.0) and not launch.active and enemy(601).get_current_health() == 940, "Host first perimeter contact clips the launch and bursts once")
	launch.step(enemy(601), 1.0)
	check(enemy(601).get_current_health() == 940 and world.damage_events.size() == 2, "Later frames cannot repeat primary or boundary damage")
	world._sync_enemy_states.rpc([{"enemy_id": 601, "health": 940, "position": Vector2(580.0, 0.0)}], 3)
	world.fixture_command.rpc_id(client_id, "inspect_impact")
	check(await until(func(): return results.has("impact")), "Joiner receives boundary damage and feedback")
	if results.has("impact"):
		var receipt: Dictionary = results.impact
		check(receipt.health == 940 and not receipt.launch_active and receipt.local_damage_events == 0, "Replica health changes only through host state; it never owns the launch")
		var events: Array = receipt.events
		check(events.size() == 3 and events[0].kind == "launch" and events[1].kind == "finish" and events[2].kind == "burst", "Boundary launch, finish and burst arrive once in order")
		if events.size() == 3:
			check(events[0].serial == events[1].serial and events[2].position == Vector2(580.0, 0.0) and events[2].radius == 70.0, "Joiner draws the actual host boundary origin and unchanged burst radius")
	world.fixture_command.rpc_id(client_id, "crescent")
	check(await until(func(): return results.has("crescent") and not remote_player.returning_crescent.blades.is_empty()), "Owner ricochet crosses the real player cue channel")
	if results.has("crescent") and not remote_player.returning_crescent.blades.is_empty():
		var owner_state: Dictionary = results.crescent
		var blade := remote_player.returning_crescent.blades[0]
		check(blade.bounces_left == 0 and blade.direction.x < 0.0 and blade.position.distance_to(owner_state.position) < 0.2, "Host presentation matches the joiner's one room-edge ricochet")
		check(blade.position.x <= 580.0 and absf(blade.travel_left - float(owner_state.travel_left)) < 0.2, "Network correction preserves the clipped position and remaining outbound budget")
		check(await until(func(): return enemy(602).get_current_health() == 977), "Owner blade submits one secondary hit to authoritative enemy health")
		var count := world.damage_events.size()
		remote_player.returning_crescent.tick(0.05)
		check(world.damage_events.size() == count and enemy(602).get_current_health() == 977, "Host's replica blade prediction cannot apply a second damage hit")
	world.fixture_command.rpc_id(client_id, "cancel_crescent")
	check(await until(func(): return results.has("cancelled") and remote_player.returning_crescent.blades.is_empty()), "Reliable cancellation removes the remote blade")
	await create_timer(0.12).timeout
	check(remote_player.returning_crescent.blades.is_empty(), "Replayed pre-cancel state cannot resurrect the blade")
	world.fixture_command.rpc_id(client_id, "blast_edge")
	check(await until(func(): return results.has("blast") and remote_player.global_position == Vector2(580.0, -150.0) and not remote_player.received_blasts.is_empty()), "Blast boundary stop reaches the host through normal owner position and cue RPCs")
	if results.has("blast") and not remote_player.received_blasts.is_empty():
		check(results.blast.motion == MOTION.Motion.NONE and is_equal_approx(float(results.blast.immunity), 0.17), "Owner recoil ends at the edge without changing dash immunity")
		check(remote_player.received_blasts.back().position == Vector2(550.0, -150.0), "Remote Blast flash stays at its firing origin after edge clipping")
	enemy(603).global_position = Vector2(560.0, 0.0)
	world.fixture_command.rpc_id(client_id, "orbit_edge")
	check(await until(func(): return results.has("orbit") and remote_player.global_position.x >= 579.99), "Orbit departure at the perimeter is replicated")
	if results.has("orbit"):
		check(results.orbit.motion == MOTION.Motion.NONE and not results.orbit.anchor and not bool(remote_player.arcana_motion._visual.get("orbit", false)), "Owner and receiver clear the tether without a carry through the edge")
	world.fixture_command.rpc_id(client_id, "shrink_strike")
	check(await until(func(): return enemy(604).get_current_health() == 980), "A new real joiner hit arms the room-shrink cancellation case")
	var serial := int(impact_events().back().serial)
	world.fixture_command.rpc_id(client_id, "inspect_shrink", {"key": "shrink_start", "serial": serial, "active": true})
	check(await until(func(): return results.has("shrink_start")), "Joiner receives the launch before room shrink")
	var damage_count := world.damage_events.size()
	world.current_effective_room_size = Vector2(400.0, 860.0)
	world._keep_enemies_inside_current_room(0.3)
	enemy(604).get_launch_state().step(enemy(604), 0.2)
	check(enemy(604).global_position == Vector2(200.0, -280.0) and not enemy(604).get_launch_state().active and world.damage_events.size() == damage_count, "Actual host clamp-before-physics cancels an outside launch without damage")
	world._sync_enemy_states.rpc([{"enemy_id": 604, "health": 980, "position": Vector2(200.0, -280.0)}], 4)
	world.fixture_command.rpc_id(client_id, "inspect_shrink", {"key": "shrink_end", "serial": serial, "active": false})
	check(await until(func(): return results.has("shrink_end")), "Joiner receives room-shrink completion and clipped enemy state")
	if results.has("shrink_start") and results.has("shrink_end"):
		var events: Array = results.shrink_end.events.slice(results.shrink_start.events.size())
		check(not results.shrink_end.active and results.shrink_end.health == 980 and events.size() == 1 and events[0].kind == "finish" and events[0].serial == serial, "Forced shrink removes the matching remote launch once and emits no invented burst")
	world.fixture_command.rpc_id(client_id, "finish")
	await until(func(): return results.has("finished"))
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"edge_strike":
			DAMAGE.apply_damage(enemy(601), 20, {"attack_type": "melee", "attack_origin": Vector2(450.0, 0.0), "source_peer_id": 1})
			check(enemy(601).get_current_health() == 1000 and not enemy(601).get_launch_state().active, "Joiner submits the hit without simulating authoritative launch or health")
		"inspect_impact":
			await until(func(): return enemy(601).get_current_health() == 940 and impact_events().size() >= 3)
			var before := impact_events().size()
			check(EnemyReplicationService.broadcast_ruinous_launch(enemy(601), Vector2.RIGHT * 750.0, false, 0.32) == 0, "Replica cannot originate a boundary launch")
			EnemyReplicationService.broadcast_ruinous_burst(Vector2(580.0, 0.0), 70.0, Vector2.RIGHT)
			enemy(601).get_launch_state().step(enemy(601), 1.0)
			check(impact_events().size() == before and world.damage_events.is_empty(), "Replica stepping and feedback APIs cannot duplicate the boundary impact")
			world.fixture_result.rpc_id(1, "impact", {"health": enemy(601).get_current_health(), "launch_active": enemy(601).get_launch_state().active, "events": impact_events().duplicate(true), "local_damage_events": world.damage_events.size()})
		"crescent":
			local_player.global_position = Vector2(500.0, 150.0)
			PlayerReplicationService._sync_all_player_positions()
			local_player.returning_crescent.try_launch(Vector2.RIGHT)
			local_player.returning_crescent.tick(0.16)
			check(local_player.returning_crescent.blades.size() == 1, "Owner still has one bounded outbound blade after reflection")
			if not local_player.returning_crescent.blades.is_empty():
				var blade := local_player.returning_crescent.blades[0]
				saved_blade_state = local_player.returning_crescent.build_network_state().duplicate(true)
				PlayerReplicationService._flush_pending_cue_events()
				world.fixture_result.rpc_id(1, "crescent", {"position": blade.position, "travel_left": blade.travel_left})
		"cancel_crescent":
			local_player.returning_crescent.cancel()
			PlayerReplicationService._flush_pending_cue_events()
			await create_timer(0.05).timeout
			local_player._broadcast_cue_event("returning_crescent_state", saved_blade_state, true)
			PlayerReplicationService._flush_pending_cue_events()
			local_player.reward_returning_crescent = false
			world.fixture_result.rpc_id(1, "cancelled", {})
		"blast_edge":
			local_player.global_position = Vector2(550.0, -150.0)
			local_player._dash_damage_immune_left = 0.17
			local_player.arcana_motion.tick(0.0)
			local_player.arcana_motion.release_blast(1.0)
			local_player.arcana_motion.process_movement(0.10, Vector2.ZERO)
			PlayerReplicationService._flush_pending_cue_events()
			PlayerReplicationService._sync_all_player_positions()
			world.fixture_result.rpc_id(1, "blast", {"motion": local_player.arcana_motion.motion, "immunity": local_player._dash_damage_immune_left})
		"orbit_edge":
			enemy(603).global_position = Vector2(560.0, 0.0)
			local_player.global_position = Vector2(560.0, -70.2)
			local_player.dash_direction = Vector2.RIGHT
			local_player.arcana_motion.start_orbit(enemy(603))
			PlayerReplicationService._flush_pending_cue_events()
			for _index in range(8):
				if local_player.arcana_motion.motion == MOTION.Motion.NONE:
					break
				local_player.arcana_motion.process_movement(1.0 / 60.0, Vector2.ZERO)
			PlayerReplicationService._flush_pending_cue_events()
			PlayerReplicationService._sync_all_player_positions()
			world.fixture_result.rpc_id(1, "orbit", {"motion": local_player.arcana_motion.motion, "anchor": is_instance_valid(local_player.arcana_motion.anchor)})
		"shrink_strike":
			DAMAGE.apply_damage(enemy(604), 20, {"attack_type": "melee", "attack_origin": Vector2(450.0, -280.0)})
		"inspect_shrink":
			var feedback := EnemyReplicationService._ruinous_feedback as ImpactFeedback
			await until(func(): return feedback.launches.has(int(payload.serial)) == bool(payload.active))
			if not bool(payload.active):
				world.current_effective_room_size = Vector2(400.0, 860.0)
				await until(func(): return enemy(604).get_current_health() == 980)
			world.fixture_result.rpc_id(1, payload.key, {"active": feedback.launches.has(int(payload.serial)), "health": enemy(604).get_current_health(), "events": impact_events().duplicate(true)})
		"finish":
			await super.client_command(command, payload)
