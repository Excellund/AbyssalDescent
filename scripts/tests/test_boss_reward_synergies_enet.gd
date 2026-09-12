extends "res://scripts/tests/test_combat_interactions_enet.gd"
## Accepted reward inputs cross real damage, Mark, state and kill RPCs.

var active_action: Dictionary = {}

func setup_actors(client_id: int) -> void:
	super.setup_actors(client_id)
	for actor in [local_player, remote_player]:
		actor.reward_storm_crown = false
		actor.reward_hunters_snare = false
		actor.apply_trial_power("wraithstep")
		actor.apply_upgrade("pillar_convergence")
		actor.apply_upgrade("sovereign_tempo")
		actor.damage = 100
		actor.shared_build_runtime.set_physics_process(false)
		actor.arcana_motion.set_process(false)
		actor.boss_combinations.set_process(false)
	for id in range(101, 111):
		enemy(id).position = Vector2(float(id - 101) * 1000.0, 0.0)
	# Only this group can be reached by the ancestry scenario's Crown/Lacuna.
	enemy(106).position = enemy(105).position + Vector2(20.0, 0.0)
	enemy(107).position = enemy(105).position + Vector2(40.0, 0.0)

func report(key: String) -> void:
	var zones: Array[Dictionary] = []
	for zone in local_player.void_echo_zones:
		zones.append((zone.get("interaction", {}) as Dictionary).duplicate(true))
	world.fixture_result.rpc_id(1, key, {
		"pillar": local_player.convergence_surge_hit_counter,
		"seal": is_instance_valid(local_player.player_feedback.faultline_seal),
		"seal_position": local_player.player_feedback.faultline_seal.global_position if is_instance_valid(local_player.player_feedback.faultline_seal) else Vector2.INF,
		"host_seal": is_instance_valid(remote_player.player_feedback.faultline_seal),
		"seal_timer": local_player.convergence_window_left,
		"tempo": local_player.apex_momentum_stacks,
		"host_pillar": remote_player.convergence_surge_hit_counter,
		"host_tempo": remote_player.apex_momentum_stacks,
		"damage_events": world.damage_events.size(),
		"kills": (local_player as InteractionPlayer).kill_interactions.duplicate(true),
		"zones": zones,
		"action": next_action.duplicate(true),
		"scope": DAMAGE.current_interaction_context(),
		"epoch": local_player.combat_interactions._epoch})

func deal(id: int, source: String, action: Dictionary, raw: float = 20.0) -> void:
	DAMAGE.apply_damage(enemy(id), int(raw), INTERACTIONS.damage_context(action, source, {"raw_amount": raw, "damage_coefficient": raw / 100.0}), joiner_id)

func inspect_owner(key: String, pillar: int, tempo: int) -> void:
	PlayerReplicationService._flush_pending_cue_events()
	await command(key, {"pillar": pillar, "tempo": tempo})
	check(int(results[key].pillar) == pillar and int(results[key].tempo) == tempo, "Owning joiner mirrors exact accepted reward counters: " + key)
	check(results[key].host_pillar == 0 and results[key].host_tempo == 0, "Other owner's counters remain untouched: " + key)
	check(results[key].damage_events == 0, "Joining replica never simulates authoritative damage: " + key)

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	begin_run()
	await command("begin")
	check(await until(received), "Reward synergies bind the actual common run identity")
	check(remote_player.convergence_surge_damage_ratio > 0.0 and remote_player.apex_momentum_speed_bonus > 0.0, "Actual reward acquisition maps both synergy receivers")
	await test_electric_action_budget()
	await test_marked_damage()
	await test_active_window_budget()
	await test_tempo_ancestry(client_id)
	await test_authority_and_cancellation()
	await command("finish")
	await finish()

func test_electric_action_budget() -> void:
	await command("electric_root")
	check(remote_player.convergence_surge_hit_counter == 1 and remote_player.apex_momentum_stacks == 0, "Wake ticks and an Electric Echo share one Pillar charge without granting unmarked Tempo")
	await command("same_root_attack")
	check(remote_player.convergence_surge_hit_counter == 1 and remote_player.apex_momentum_stacks == 1, "Attack and Electric alternatives share Pillar's action budget while Tempo keeps its own allowance")
	await command("ordinary_echo")
	check(remote_player.convergence_surge_hit_counter == 1 and remote_player.apex_momentum_stacks == 1, "An unmarked non-Electric Echo supplies neither reward input")
	await inspect_owner("inspect_electric", 1, 1)

func test_marked_damage() -> void:
	await command("unmarked_field")
	check(remote_player.apex_momentum_stacks == 1, "Unmarked Field damage does not consume Tempo's qualifying opportunity")
	await command("mark_then_field")
	check(DAMAGE.status_snapshot(enemy(103), joiner_id).mark_ratio > 0.0, "Real joiner Mark request reaches the authoritative target before its damage")
	check(remote_player.apex_momentum_stacks == 2 and remote_player.convergence_surge_hit_counter == 1, "Already-Marked Field and Echo damage grant one Tempo stack per original action")
	await inspect_owner("inspect_marked", 1, 2)

func test_active_window_budget() -> void:
	await command("fill_pillar", {"count": 3 - remote_player.convergence_surge_hit_counter})
	check(remote_player.convergence_window_left > 0.0 and remote_player.convergence_surge_hit_counter == 0, "Independent Electric actions plant a real stationary seal on the host")
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_seal", {"armed": true})
	check(results.inspect_seal.seal and results.inspect_seal.seal_position == remote_player._convergence_origin and results.inspect_seal.seal_timer == 0.0, "Owning joiner receives the stationary start cue without simulating a gameplay fuse")
	var victim := enemy(109)
	victim.position = remote_player._convergence_origin + Vector2(65, 0)
	var before: int = victim.get_current_health()
	remote_player.position += Vector2(400, 200)
	remote_player._update_convergence_window(.79)
	check(victim.get_current_health() == before and remote_player.convergence_window_left > 0.0, "The joining owner's seal waits for its full fuse and does not follow the body")
	# A different-location Field action is accepted during the fuse but cannot
	# detonate this seal or bank a later charge.
	await command("active_root")
	remote_player._update_convergence_window(.02)
	check(victim.get_current_health() == before - 180 and victim.velocity.is_zero_approx(), "The host delivers the joiner-owned normal Burst without Pull")
	check(world.damage_events.back().peer == joiner_id, "Stationary Burst keeps authenticated joining-owner damage credit")
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_seal", {"armed": false})
	check(not results.inspect_seal.seal, "Normal Burst cue removes the joining owner’s armed visual")
	remote_player._update_convergence_window(.61)
	await command("repeat_active_root")
	check(remote_player.convergence_window_left == 0.0 and remote_player.convergence_surge_hit_counter == 0, "A fuse-locked action cannot bank delayed charges after expiry")
	victim.position = Vector2(8000, 0)
	await command("fresh_electric")
	check(remote_player.convergence_surge_hit_counter == 1, "A fresh Electric action charges after rearm")
	await command("fill_pillar", {"count": 2})
	victim.position = remote_player._convergence_origin + Vector2(65, 0)
	before = victim.get_current_health()
	await command("field_detonate")
	check(victim.get_current_health() == before - 270 and remote_player.convergence_window_left == 0.0, "Later real joining Field damage converts the seal into a stronger host Burst")
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_seal", {"armed": false})
	check(not results.inspect_seal.seal, "Early Field detonation clears the joining owner’s seal immediately")
	check(world.damage_events.back().peer == joiner_id, "The Field-triggered Burst also retains joining-owner credit")
	remote_player._update_convergence_window(.61)
	await command("fresh_electric")
	await command("fill_pillar", {"count": 2})
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_seal", {"armed": true})
	remote_player.set_alive(false)
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_seal", {"armed": false})
	check(not results.inspect_seal.seal, "Authoritative death clears the joining owner's visual through the real reliable cue")
	remote_player.set_alive(true)
	await command("fresh_electric")
	await inspect_owner("inspect_window", 1, 2)

func test_tempo_ancestry(client_id: int) -> void:
	remote_player.reward_storm_crown = true
	remote_player.storm_crown_proc_every = 1
	remote_player.apply_upgrade("lacuna_echo")
	enemy(107).health_state.current_health = 1
	await command("tempo_crown")
	check(await until(func(): return world.kill_peers.size() == 1), "Tempo's native Crown discharge kills through the authoritative enemy boundary")
	check(remote_player.apex_momentum_stacks == 2, "Marked Tempo damage and its Electric Crown descendants cannot recharge Tempo")
	await command("inspect_tempo_kill")
	var kills: Array = results.inspect_tempo_kill.kills
	var expected := INTERACTIONS.TEMPO_ANCESTRY | INTERACTIONS.CROWN_ANCESTRY
	check(kills.size() == 1 and int(kills[0].ancestry) == expected and kills[0].seq == results.tempo_crown.action.seq, "Actual kill RPC preserves the original root and both reaction ancestry bits")
	var zones: Array = results.inspect_tempo_kill.zones
	check(zones.size() == 1 and int(zones[0].ancestry) == expected, "Owner kill callback captures both ancestry bits in its delayed Lacuna Field")
	var health_before: int = enemy(106).get_current_health()
	await command("lacuna_pulse")
	check(enemy(106).get_current_health() < health_before and remote_player.apex_momentum_stacks == 2, "Native delayed Lacuna damage crosses back to host without recharging Tempo")
	check(world.kill_peers == [client_id] and world.damage_events.back().peer == client_id, "Descendant damage and kill credit retain the authenticated joining owner")
	check(results.lacuna_pulse.scope.is_empty() and DAMAGE.current_interaction_context().is_empty(), "Both processes release interaction scope after the descendant round trip")
	remote_player.reward_storm_crown = false
	await inspect_owner("inspect_ancestry", remote_player.convergence_surge_hit_counter, 2)

func test_authority_and_cancellation() -> void:
	var pillar := 0 # Authenticated cancellation retires partial Faultline charge.
	var tempo := remote_player.apex_momentum_stacks
	var health_before: int = enemy(110).get_current_health()
	await command("cancel_stale")
	await command("forged_owner")
	await command("forge_state")
	check(remote_player.convergence_surge_hit_counter == pillar and remote_player.apex_momentum_stacks == tempo, "Authenticated cancellation clears partial Faultline charge; stale damage and forged state cannot restore it")
	check(enemy(110).get_current_health() == health_before and DAMAGE.status_snapshot(enemy(110), joiner_id).mark_ratio == 0.0, "Rejected shared requests cannot damage or Mark the actual target")
	check(local_player.convergence_surge_hit_counter == 0 and local_player.apex_momentum_stacks == 0, "Wrong-owner requests cannot spend the host player's independent reward budget")
	PlayerReplicationService.broadcast_cue_event(joiner_id, "shared_build_state", {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "serial": 999999, "epoch": int(results.cancel_stale.epoch) - 1, "state": {"convergence_surge_hit_counter": 9999, "apex_momentum_stacks": 9999}}, true)
	await inspect_owner("inspect_stale", pillar, tempo)
	var host_action := local_player.combat_interactions.begin_action("attack")
	DAMAGE.apply_damage(enemy(108), 10, INTERACTIONS.damage_context(host_action, "melee", {"raw_amount": 10.0, "damage_coefficient": 0.1}), 1)
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_observer")
	check(results.inspect_observer.host_pillar == 1 and results.inspect_observer.host_tempo == 1, "Host-owned reward counters reach the observing joiner through native state RPCs")
	for index in range(2):
		var action := local_player.combat_interactions.begin_action("attack")
		DAMAGE.apply_damage(enemy(108), 10, INTERACTIONS.damage_context(action, "melee", {"raw_amount": 10.0, "damage_coefficient": .1}), 1)
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_host_seal", {"armed": true})
	check(results.inspect_host_seal.host_seal, "Observing joiner renders the host owner's stationary seal")
	local_player.clear_lingering_combat_effects()
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_host_seal", {"armed": false})
	check(not results.inspect_host_seal.host_seal, "Room/death cleanup also clears the observer’s host-owned seal")

func client_command(name: String, payload: Dictionary) -> void:
	match name:
		"begin":
			begin_run()
			check(await until(func(): return not INTERACTIONS.current_run().is_empty()), "Joining reward owner receives the host's current run token")
		"electric_root":
			saved_action = local_player.combat_interactions.begin_action("dash")
			deal(101, "static_wake", saved_action)
			deal(101, "static_wake", saved_action)
			var wake: Dictionary = INTERACTIONS.damage_context(saved_action, "static_wake").interaction
			deal(102, "sovereigns_double", wake)
			check(local_player.convergence_surge_hit_counter == 0 and enemy(101).get_current_health() == 10000, "Sending Electric damage changes neither local reward state nor replica health")
		"same_root_attack":
			deal(102, "melee", saved_action)
		"ordinary_echo":
			var action := local_player.combat_interactions.begin_action("attack")
			var attack: Dictionary = INTERACTIONS.damage_context(action, "melee").interaction
			deal(102, "sovereigns_double", attack)
		"unmarked_field":
			next_action = local_player.combat_interactions.begin_action("field")
			deal(103, "void_echo_zone", next_action)
		"mark_then_field":
			DAMAGE.apply_mark(enemy(103), "wraithstep", 0.15, 2.5, joiner_id, next_action)
			DAMAGE.apply_mark(enemy(104), "wraithstep", 0.15, 2.5, joiner_id, next_action)
			deal(103, "void_echo_zone", next_action)
			var field: Dictionary = INTERACTIONS.damage_context(next_action, "void_echo_zone").interaction
			deal(104, "sovereigns_double", field)
			deal(103, "void_echo_zone", next_action)
		"fill_pillar":
			for _i in range(int(payload.count)):
				deal(101, "static_wake", local_player.combat_interactions.begin_action("dash"))
		"active_root":
			active_action = local_player.combat_interactions.begin_action("dash")
			deal(102, "static_wake", active_action)
		"repeat_active_root":
			deal(102, "static_wake", active_action)
		"inspect_seal":
			check(await until(func(): return is_instance_valid(local_player.player_feedback.faultline_seal) == bool(payload.armed)), "Joining owner receives the expected Faultline visual state")
		"inspect_host_seal":
			check(await until(func(): return is_instance_valid(remote_player.player_feedback.faultline_seal) == bool(payload.armed)), "Observer receives the host owner's expected Faultline visual state")
		"field_detonate":
			deal(101, "static_wake", local_player.combat_interactions.begin_action("dash"))
		"fresh_electric":
			deal(101, "static_wake", local_player.combat_interactions.begin_action("dash"))
		"tempo_crown":
			local_player.reward_storm_crown = true
			local_player.storm_crown_proc_every = 1
			local_player.apply_upgrade("lacuna_echo")
			next_action = local_player.combat_interactions.begin_action("dash")
			for id in [105, 106, 107]:
				DAMAGE.apply_mark(enemy(id), "wraithstep", 0.15, 2.5, joiner_id, next_action)
			deal(105, "apex_momentum_wave", next_action)
		"inspect_tempo_kill":
			check(await until(func(): return not local_player.void_echo_zones.is_empty()), "Native remote kill notification creates the owner's delayed Lacuna zone")
		"lacuna_pulse":
			local_player._update_void_echo_zones(0.33)
		"cancel_stale":
			local_player.reward_storm_crown = false
			local_player.combat_interactions.cancel()
			DAMAGE.apply_mark(enemy(110), "wraithstep", 0.15, 2.5, joiner_id, saved_action)
			deal(110, "static_wake", saved_action)
		"forged_owner":
			var forged := local_player.combat_interactions.begin_action("dash")
			forged.owner = 1
			DAMAGE.apply_mark(enemy(110), "wraithstep", 0.15, 2.5, joiner_id, forged)
			deal(110, "static_wake", forged)
		"forge_state":
			var fake := {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "serial": 99999, "epoch": local_player.combat_interactions._epoch, "state": {"convergence_surge_hit_counter": 9999, "apex_momentum_stacks": 9999}}
			var entries: Array[Dictionary] = [{"event": "shared_build_state", "payload": PlayerReplicationService._pack_shared_build_state(fake)}]
			PlayerReplicationService._sync_player_cue_events_reliable.rpc_id(1, joiner_id, entries)
		"inspect_electric", "inspect_marked", "inspect_window", "inspect_ancestry", "inspect_stale":
			check(await until(func(): return local_player.convergence_surge_hit_counter == int(payload.pillar) and local_player.apex_momentum_stacks == int(payload.tempo)), "Host accepted reward state reaches the owner")
		"inspect_observer":
			check(await until(func(): return remote_player.convergence_surge_hit_counter == 1 and remote_player.apex_momentum_stacks == 1), "Host-owned reward state reaches its observer")
		"finish":
			report(name)
			await create_timer(0.1).timeout
			await finish()
			return
	report(name)
