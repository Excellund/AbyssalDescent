extends "res://scripts/tests/test_party_provenance_enet.gd"
## Real authenticated damage/status/epoch/cue/kill transports, separate profiles.
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")

class InteractionPlayer extends Player:
	var kill_interactions: Array[Dictionary] = []
	var interaction_cues: Array[Dictionary] = []
	func notify_enemy_killed(position: Vector2 = Vector2.INF) -> void:
		kill_interactions.append(DAMAGE.current_interaction_context())
		super.notify_enemy_killed(position)
	func apply_owner_cue_event(event_name: String, payload: Dictionary) -> void:
		super.apply_owner_cue_event(event_name, payload)
		if event_name == "combat_interaction_state":
			interaction_cues.append(payload.duplicate(true))
	func apply_network_cue_event(event_name: String, payload: Dictionary) -> void:
		super.apply_network_cue_event(event_name, payload)
		if event_name == "combat_interaction_state":
			interaction_cues.append(payload.duplicate(true))

var saved_action: Dictionary = {}
var next_action: Dictionary = {}

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	RunContext.set_multiplayer_session("interactions-loopback", role == "host")
	RunContext.meta_progress_profile = {}
	world.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(world)
	GameStateReplicationService.initialize(world)
	for id in [1, client_id]:
		var actor := InteractionPlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		world.add_child(actor)
		actor.position = Vector2(-500.0, 0.0)
		actor.apply_trial_power("storm_crown")
		actor.apply_trial_power("storm_crown")
		actor.apply_trial_power("hunters_snare")
		actor.apply_trial_power("hunters_snare")
		actor.returning_crescent.set_physics_process(false)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	for id in range(101, 111):
		var target := Enemy.new()
		target.name = "Enemy_%d" % id
		world.add_child(target)
		target.position = Vector2((id - 101) * 100.0, 0.0)
		target.health_state.setup(10000, 10000)
		world.enemy_state_sync_broadcaster.register_enemy(target, id)
	world.active_room_enemy_count = 10

func report(key: String) -> void:
	world.fixture_result.rpc_id(1, key, {
		"counter": local_player.storm_crown_hit_counter,
		"host_counter": remote_player.storm_crown_hit_counter,
		"cues": (local_player as InteractionPlayer).interaction_cues.duplicate(true),
		"kills": (local_player as InteractionPlayer).kill_interactions.duplicate(true),
		"scope": DAMAGE.current_interaction_context(),
		"epoch": local_player.combat_interactions._epoch,
		"slow": enemy(101).is_slowed(),
		"slow_mult": enemy(101).slow_speed_mult,
		"snare_bonus": local_player._hunters_snare_aoe_bonus_against(enemy(101)),
		"damage_events": world.damage_events.size()})

func command(name: String, payload: Dictionary = {}) -> bool:
	results.erase(name)
	world.fixture_command.rpc_id(joiner_id, name, payload)
	var done := await until(func(): return results.has(name))
	check(done, "Real joiner completes " + name)
	return done

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	begin_run()
	await command("begin")
	check(await until(received), "Actual recorder handshake establishes a nonempty common run identity")
	check(not INTERACTIONS.current_run().is_empty(), "Host interaction identity is the actual run token")
	await command("wake_prepare")
	check(remote_player.combat_interactions._accepted_epoch > 0, "Synchronous reliable epoch arrives before the first damage request")
	check(enemy(101).is_slowed(), "Client Slow request mutates the host enemy")
	var bonus := remote_player.hunters_snare_bonus_damage
	check(enemy(101).get_current_health() == 10000 - 20 - bonus, "Same-packet Slow then Wake resolves Snare bonus on the authoritative target")
	check(remote_player.storm_crown_hit_counter == 1, "One accepted client Wake tick counts once on host")
	check(world.damage_events.size() == 1 and world.damage_events[0].peer == client_id, "Only host records the authenticated owner's accepted damage")
	# Exercise the production delta generator + existing native World RPC.
	var snapshot: Dictionary = world.enemy_state_sync_broadcaster._quantize_runtime_state_for_network(enemy(101).get_network_runtime_state())
	var delta: Dictionary = world.enemy_state_sync_broadcaster._compute_runtime_state_delta(snapshot, {})
	world._sync_enemy_states.rpc([{"enemy_id": 101, "health": enemy(101).get_current_health(), "runtime_state_delta": delta}], 10)
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_slow")
	check(results.inspect_slow.slow and is_equal_approx(float(results.inspect_slow.slow_mult), 0.5), "Existing runtime RPC mirrors authoritative Slow for the joiner")
	check(results.inspect_slow.snare_bonus == bonus and results.inspect_slow.damage_events == 0, "Joiner preparation bonus reads mirrored status without local damage simulation")
	check(results.inspect_slow.counter == 1, "Host's accepted counter reaches the owning joiner")
	await command("echo_same")
	check(remote_player.storm_crown_hit_counter == 1, "Echo and Wake on the same root/target share one Hit allowance")
	await command("echo_other")
	check(remote_player.storm_crown_hit_counter == 2, "Echo on a new target can complete its original root's one discharge")
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_discharge")
	var cues: Array = results.inspect_discharge.cues
	var discharges := cues.filter(func(cue: Dictionary) -> bool: return cue.links.size() > 1)
	check(discharges.size() == 1 and discharges[0].links.size() == 5, "One original-root discharge uses pre-slowed downstream enemy for the one extra hop")
	if discharges.size() == 1:
		check(discharges[0].conduction_index == 4, "Owner receives the exact Slow-assisted hop index")
	await command("spent_root")
	check(remote_player.storm_crown_hit_counter == 2, "Later primary/secondary native Hits cannot recharge an already discharged root")
	await command("zero_bonus")
	check(world.damage_events.back().amount == bonus, "Zero-base scheduled Wake contact may still deal one positive authoritative Snare bonus")
	check(remote_player.storm_crown_hit_counter == 3, "Positive host-resolved zero-base damage produces one accepted Hit")
	await command("forge_state")
	check(remote_player.storm_crown_hit_counter == 3, "A joiner-owned cue cannot forge host-accepted reaction state")
	var before_cancel := remote_player.storm_crown_hit_counter
	await command("cancel_stale")
	check(remote_player.combat_interactions._accepted_epoch == results.cancel_stale.epoch, "Owner cancellation advances the host's authenticated epoch synchronously")
	check(remote_player.storm_crown_hit_counter == before_cancel and not enemy(109).is_slowed(), "Old epoch cannot create a Hit or attach/refresh Slow")
	check(enemy(109).get_current_health() == 9980, "Rejecting stale interaction metadata preserves legacy base damage")
	await command("forged_owner")
	check(remote_player.storm_crown_hit_counter == before_cancel and local_player.storm_crown_hit_counter == 0, "Payload owner identity cannot spend either player's reaction budget")
	check(not enemy(110).is_slowed(), "Forged owner cannot apply declared hit Slow")
	await command("new_root")
	check(remote_player.storm_crown_hit_counter == before_cancel + 1, "New valid post-cancel root remains playable")
	await command("old_room_run")
	check(remote_player.storm_crown_hit_counter == before_cancel + 1 and not enemy(110).is_slowed(), "Wrong room or run metadata cannot react or apply status")
	# A host-origin root's counter must reach observers as well as local owner.
	var host_action := local_player.combat_interactions.begin_action("attack")
	DAMAGE.apply_damage(enemy(108), 10, INTERACTIONS.damage_context(host_action, "melee"), 1)
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_observer")
	check(results.inspect_observer.host_counter == 1, "Observer mirrors the host-owned accepted Hit counter")
	local_player.combat_interactions.cancel()
	PlayerReplicationService.broadcast_cue_event(1, "combat_interaction_state", {"run": host_action.run, "room": host_action.room, "epoch": host_action.epoch, "serial": 999999, "counter": 99999, "links": PackedVector2Array([Vector2.ZERO, Vector2(20.0, 0.0)]), "conduction_index": -1}, true)
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_observer_cancel", {"epoch": local_player.combat_interactions._epoch})
	check(results.inspect_observer_cancel.host_counter == 1, "An observer rejects a delayed old-epoch host cue even with a greater visual serial")
	# Production kill RPC carries ancestry independently of existing two-bit scopes.
	var killed_action: Dictionary = results.new_root.action.duplicate(true)
	var killed_id := enemy(110).get_instance_id()
	DAMAGE.apply_damage(enemy(110), enemy(110).get_current_health(), INTERACTIONS.damage_context(killed_action, "storm_crown", {"secondary": true, "kill_proc_suppression": DAMAGE.KILL_PROC_SUPPRESS_FRACTURE}), client_id)
	await command("inspect_kill")
	var kills: Array = results.inspect_kill.kills
	check(kills.size() == 1 and int(kills[0].ancestry) == INTERACTIONS.CROWN_ANCESTRY and kills[0].seq == killed_action.seq, "Real kill callback RPC retains exact root and Crown ancestry")
	check(world.kill_peers == [client_id] and not is_instance_id_valid(killed_id), "Actual enemy death retires the body and preserves the authenticated joiner's kill credit")
	check(results.inspect_kill.scope.is_empty(), "Remote kill callback releases interaction scope without leakage")
	await command("finish")
	await finish()

func client_command(name: String, payload: Dictionary) -> void:
	match name:
		"begin":
			begin_run()
			check(await until(func(): return not INTERACTIONS.current_run().is_empty()), "Joiner binds the actual host run token")
		"wake_prepare":
			saved_action = local_player.combat_interactions.begin_action("dash")
			check(DAMAGE.apply_slow(enemy(101), 4.0, 0.5, joiner_id, saved_action), "Client uses reliable Slow request boundary")
			check(not enemy(101).is_slowed(), "Sending status does not mutate the client replica")
			DAMAGE.apply_damage(enemy(101), 20, INTERACTIONS.damage_context(saved_action, "static_wake", {"secondary": true, "is_ground_attack": true, "hunters_snare_aoe_bonus": true}))
		"inspect_slow":
			check(await until(func(): return enemy(101).is_slowed() and local_player.storm_crown_hit_counter == 1), "Authoritative status and counter arrive through existing transports")
		"echo_same":
			var copied := INTERACTIONS.damage_context(saved_action, "static_wake").interaction as Dictionary
			DAMAGE.apply_damage(enemy(101), 20, INTERACTIONS.damage_context(copied, "sovereigns_double", {"secondary": true, "is_ground_attack": true}))
		"echo_other":
			var copied := INTERACTIONS.damage_context(saved_action, "static_wake").interaction as Dictionary
			DAMAGE.apply_damage(enemy(102), 20, INTERACTIONS.damage_context(copied, "sovereigns_double", {"secondary": true, "is_ground_attack": true}))
		"inspect_discharge":
			check(await until(func(): return local_player.storm_crown_hit_counter == 2), "Owner receives one authoritative discharge result")
		"spent_root":
			for id in [103, 104, 105]:
				DAMAGE.apply_damage(enemy(id), 20, INTERACTIONS.damage_context(saved_action, "returning_crescent", {"secondary": true}))
		"zero_bonus":
			next_action = local_player.combat_interactions.begin_action("dash")
			DAMAGE.apply_damage(enemy(101), 0, INTERACTIONS.damage_context(next_action, "static_wake", {"secondary": true, "hunters_snare_aoe_bonus": true}))
		"forge_state":
			PlayerReplicationService.broadcast_cue_event(joiner_id, "combat_interaction_state", {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "epoch": local_player.combat_interactions._epoch, "serial": 999999, "counter": 99999, "links": PackedVector2Array(), "conduction_index": -1}, true)
			PlayerReplicationService._flush_pending_cue_events()
		"cancel_stale":
			local_player.combat_interactions.cancel()
			DAMAGE.apply_slow(enemy(109), 3.0, 0.4, joiner_id, saved_action)
			DAMAGE.apply_damage(enemy(109), 20, INTERACTIONS.damage_context(saved_action, "static_wake", {"secondary": true, "slow_on_hit": {"duration": 3.0, "mult": 0.4}}))
		"forged_owner":
			var forged := local_player.combat_interactions.begin_action("attack")
			forged.owner = 1
			PlayerReplicationService._sync_interaction_epoch.rpc_id(1, 1, 999, INTERACTIONS.current_run(), INTERACTIONS.current_room())
			DAMAGE.apply_damage(enemy(110), 20, INTERACTIONS.damage_context(forged, "melee", {"slow_on_hit": {"duration": 3.0, "mult": 0.4}}))
		"new_root":
			next_action = local_player.combat_interactions.begin_action("attack")
			DAMAGE.apply_damage(enemy(109), 20, INTERACTIONS.damage_context(next_action, "melee"))
			world.fixture_result.rpc_id(1, name, {"action": next_action})
			return
		"old_room_run":
			for field in ["room", "run"]:
				var stale := next_action.duplicate()
				stale[field] = 999 if field == "room" else "retired-run"
				DAMAGE.apply_slow(enemy(110), 3.0, 0.4, joiner_id, stale)
				DAMAGE.apply_damage(enemy(110), 20, INTERACTIONS.damage_context(stale, "melee", {"slow_on_hit": {"duration": 3.0, "mult": 0.4}}))
		"inspect_observer":
			check(await until(func(): return remote_player.storm_crown_hit_counter == 1), "Host-owned state arrives at observing joiner")
		"inspect_observer_cancel":
			check(await until(func(): return remote_player.combat_interactions._accepted_epoch == int(payload.epoch)), "Observer receives authenticated host cancellation before inspecting delayed feedback")
		"inspect_kill":
			check(await until(func(): return not (local_player as InteractionPlayer).kill_interactions.is_empty()), "Host kill reaches actual owner callback")
		"finish":
			report(name)
			await create_timer(0.1).timeout
			await finish()
			return
	report(name)
