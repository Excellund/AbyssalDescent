extends "res://scripts/tests/test_combat_interactions_enet.gd"
## Native accepted damage/cue RPCs on two processes, with presentation-only replay.

func setup_actors(client_id: int) -> void:
	super.setup_actors(client_id)
	for actor in [local_player, remote_player]:
		actor.reward_storm_crown = false
		actor.reward_hunters_snare = false
		actor.apply_upgrade("wardens_verdict")
		actor.position = Vector2(-40, 0)
		actor.attack_range = 78.0

func visual_state(actor: Player) -> Dictionary:
	var visual: Node = actor.player_feedback.warden_verdict
	return {"step": visual.step, "contacts": visual.contacts.size(), "bursts": visual.bursts.duplicate(true), "serial": visual._serial, "remaining": visual.remaining} if visual != null else {"step": 0, "contacts": 0, "bursts": [], "serial": 0, "remaining": 0.0}

func report(key: String) -> void:
	world.fixture_result.rpc_id(1, key, {"own": visual_state(local_player), "observer": visual_state(remote_player), "counter": local_player.apex_predator_combo_hits, "damage": world.damage_events.size()})

func _contact(actor: Player) -> void:
	actor._perform_melee_attack(Vector2.RIGHT, {"damage": actor.damage, "range": 78.0, "arc_degrees": 130.0})

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	begin_run()
	await command("begin")
	check(await until(received), "Warden uses the actual common run-token handshake")
	for step in range(1, 5):
		await command("strike")
		check(await until(func(): return remote_player.apex_predator_combo_hits == step), "Host accepts native joiner contact %d" % step)
		PlayerReplicationService._flush_pending_cue_events()
		await command("inspect", {"step": step})
		check(results.inspect.own.step == step and visual_state(remote_player).step == step, "Owner and host observer display the same accepted contact %d" % step)
		check(results.inspect.damage == 0, "Replica presentation never runs authoritative damage")
	check(results.inspect.own.bursts.size() == 1 and visual_state(remote_player).bursts.size() == 1, "One fourth-contact Burst appears on owner and observer")
	check(results.inspect.own.bursts[0].position == enemy(101).position and results.inspect.own.bursts[0].radius == remote_player._get_apex_predator_burst_radius(), "Real native cue preserves actual impact position and exact radius")
	check(results.inspect.counter == 4, "Visual transport leaves the ordinary accepted counter intact")
	var host_visual: Node = remote_player.player_feedback.warden_verdict
	var saved := {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "epoch": remote_player.combat_interactions._accepted_epoch, "serial": host_visual._serial, "step": 4, "position": enemy(101).position, "radius": remote_player._get_apex_predator_burst_radius(), "duration": 2.2}
	var damage_before := world.damage_events.size()
	PlayerReplicationService.broadcast_cue_event(client_id, "warden_verdict", saved, true)
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect", {"step": 4})
	check(results.inspect.own.bursts.size() == 1 and world.damage_events.size() == damage_before, "Duplicate authoritative cue cannot replay Burst or damage")
	await command("forge", {"cue": saved})
	check(host_visual._serial == saved.serial and world.damage_events.size() == damage_before, "Actual client cue RPC cannot forge an accepted Warden contact")
	for key in ["run", "room"]:
		var invalid := saved.duplicate(true)
		invalid.serial = 900
		invalid[key] = "old-run" if key == "run" else int(saved.room) - 1
		PlayerReplicationService.broadcast_cue_event(client_id, "warden_verdict", invalid, true)
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect", {"step": 4})
	check(results.inspect.own.serial == saved.serial, "Wrong run/room packets cannot create stale combat feedback")
	await command("cancel")
	saved.serial = 901
	PlayerReplicationService.broadcast_cue_event(client_id, "warden_verdict", saved, true)
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_clear")
	check(results.inspect_clear.own.step == 0 and results.inspect_clear.own.bursts.is_empty(), "Room cleanup plus newer owner epoch rejects a delayed previous Burst")
	# Host-controlled fourth contact reaches the other peer's observer as well.
	for step in range(4):
		_contact(local_player)
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_host")
	check(results.inspect_host.observer.step == 4 and results.inspect_host.observer.bursts.size() == 1, "Host's fourth accepted contact reaches the joiner's observer")
	check(results.inspect_host.observer.bursts[0].radius == local_player._get_apex_predator_burst_radius(), "Observer boundary uses the same native radius")
	await command("expire")
	check(results.expire.own.contacts == 0 and results.expire.observer.bursts.is_empty(), "Owner/observer transient shapes expire without a final packet")
	await command("finish")
	await finish()

func client_command(name: String, payload: Dictionary) -> void:
	match name:
		"begin":
			begin_run()
			check(await until(func(): return not INTERACTIONS.current_run().is_empty()), "Joiner binds the actual host run token")
		"strike": _contact(local_player)
		"inspect":
			check(await until(func(): return visual_state(local_player).step == payload.step), "Accepted cue reaches real owner handler")
		"forge":
			var forged: Dictionary = payload.cue.duplicate(true)
			forged.serial = 99999
			var forged_events: Array[Dictionary] = [{"event": "warden_verdict", "payload": forged}]
			PlayerReplicationService._sync_player_cue_events_reliable.rpc_id(1, joiner_id, forged_events)
		"cancel": local_player.clear_lingering_combat_effects()
		"inspect_clear": pass
		"inspect_host":
			check(await until(func(): return visual_state(remote_player).step == 4), "Host cue reaches native observer handler")
		"expire":
			for actor in [local_player, remote_player]:
				if actor.player_feedback.warden_verdict != null:
					actor.player_feedback.warden_verdict.advance(3.0)
		"finish":
			world.fixture_result.rpc_id(1, name, {})
			# The host closes only after receiving our result. Observe that reply
			# before closing the client, and leave the locked World RPC callback.
			check(await until(func(): return peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED), "Host receives final result before client teardown")
			await finish()
			return
	report(name)
