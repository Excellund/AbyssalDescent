extends "res://scripts/tests/test_threadbinder_enet.gd"
## Real ENet owner inputs, host bank reconciliation and observer sword geometry.
var interleave_roots: Array[Dictionary] = []

class OathFeedback extends EffigyFeedback:
	var swords: Array[Dictionary] = []
	func play_boss_unbroken_retaliation(origin: Vector2, impact: Vector2, ratio: float) -> void:
		swords.append({"origin": origin, "impact": impact, "ratio": ratio})
		super.play_boss_unbroken_retaliation(origin, impact, ratio)

class OathKeeper extends EffigyPlayer:
	func _create_player_feedback() -> void:
		player_feedback = OathFeedback.new()
		add_child(player_feedback)
		player_feedback.setup(max_health, get_current_health())

func setup_actors(client_id: int) -> void:
	super.setup_actors(client_id)
	enemy(107).position = Vector2(245, 10)

func _pump_player_transport() -> void:
	# The host may finish during the joiner's final audio-retirement frame.
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	super._pump_player_transport()

func _create_actor(id: int) -> EffigyPlayer:
	var actor := OathKeeper.new()
	actor.name = "Player_%d" % id
	actor.player_id = id
	actor.is_local_player = id == get_multiplayer().get_unique_id()
	circle(actor, 14.0)
	world.add_child(actor)
	actor.apply_character_package(CHARACTERS.get_character("threadbinder"))
	actor.apply_upgrade("unbroken_oath")
	actor.damage = 20
	actor.position = Vector2(-300, -160) if id == 1 else Vector2.ZERO
	actor.arcana_motion.set_process(false)
	actor.returning_crescent.set_physics_process(false)
	actor.boss_combinations.set_process(false)
	PlayerReplicationService.register_player(id, actor)
	return actor

func report(key: String) -> void:
	world.fixture_result.rpc_id(1, key, {"bank": local_player.indomitable_damage_bank, "primed": local_player._indomitable_spirit_primed,
		"origin": local_player.get_attack_origin(), "body": local_player.global_position,
		"swords": (local_player.player_feedback as OathFeedback).swords.duplicate(true),
		"observer_swords": (remote_player.player_feedback as OathFeedback).swords.duplicate(true),
		"damage_events": world.damage_events.size(), "scope": DAMAGE.current_interaction_context(), "interleave_roots": interleave_roots.duplicate(true)})

func _prime_actor(actor: Player) -> void:
	actor.indomitable_damage_bank = actor._get_indomitable_fill_requirement()
	actor._indomitable_spirit_primed = true
	actor._indomitable_primed_this_attack = false

func _clear_bank(actor: Player) -> void:
	actor.indomitable_damage_bank = 0.0
	actor._indomitable_spirit_primed = false
	actor._indomitable_primed_this_attack = false

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	begin_run()
	await command("begin")
	check(await until(received), "Real run handshake binds both Oath owners")
	await command("deploy")
	check(remote_player.effigy_deployed and is_equal_approx(remote_player.indomitable_damage_bank, 2.6 + remote_player.indomitable_spirit_damage_reduction * 8.0), "Joiner's real body deployment earns one accepted Oath contact")
	remote_player.shared_build_runtime.publish_state()
	await command("inspect")
	check(is_equal_approx(float(results.inspect.bank), remote_player.indomitable_damage_bank), "Owner sees the host's accepted bank through production shared-state transport")
	await command("move")
	check(await until(func(): return remote_player.global_position.distance_to(Vector2(-130, 160)) < 2.0), "Production movement transport separates body and fixed effigy")
	_prime_actor(remote_player)
	remote_player.shared_build_runtime.publish_state()
	await command("prime_ready")
	await command("spend")
	check(await until(func(): return (remote_player.player_feedback as OathFeedback).swords.size() == 1), "Host observer receives the actual owner retaliation cue")
	var sword: Dictionary = (remote_player.player_feedback as OathFeedback).swords.back()
	check(sword.origin.is_equal_approx(Vector2(180, 0)) and sword.impact.y == 0.0, "Observed joiner sword launches along the accepted effigy attack ray")
	check(remote_player.indomitable_damage_bank == 0.0 and not remote_player._indomitable_spirit_primed, "Host consumes the primed bank once without refilling on the spending hit")
	remote_player.shared_build_runtime.publish_state()
	await command("inspect")
	check(results.inspect.bank == 0.0 and not results.inspect.primed and results.inspect.swords.size() == 1, "Owner converges on the same spent bank without a duplicated sword")
	_clear_bank(remote_player)
	var first_before := (enemy(102) as EffigyEnemy).received_hits.size()
	var second_before := (enemy(107) as EffigyEnemy).received_hits.size()
	await command("clear_and_interleave")
	# The command acknowledgement is not the accepted-contact observation.
	# Wait for the four actual hits, then assert bank arithmetic independently.
	var contacts_complete := await until(func(): return (enemy(102) as EffigyEnemy).received_hits.size() == first_before + 2 and (enemy(107) as EffigyEnemy).received_hits.size() == second_before + 2)
	check(contacts_complete, "Both original Attack roots deliver exactly two accepted contacts before the stacking assertion")
	results["interleave_transport"] = {"issued_roots": results.clear_and_interleave.interleave_roots, "first_before": first_before, "second_before": second_before, "first_after": (enemy(102) as EffigyEnemy).received_hits.size(), "second_after": (enemy(107) as EffigyEnemy).received_hits.size(), "contacts_complete": contacts_complete, "bank": remote_player.indomitable_damage_bank}
	var gain: float = 2.6 + remote_player.indomitable_spirit_damage_reduction * 8.0
	check(is_equal_approx(remote_player.indomitable_damage_bank, 2.0 * gain * 3.1), "Real reliable RPCs preserve each accepted root's two-contact multiplier when contacts interleave")
	remote_player.shared_build_runtime.publish_state()
	await command("inspect")
	check(is_equal_approx(float(results.inspect.bank), remote_player.indomitable_damage_bank), "Owner receives the independently counted interleaved bank")
	_prime_actor(local_player)
	_attack(local_player, Vector2.RIGHT)
	await command("inspect_host")
	check(results.inspect_host.observer_swords.size() == 1 and results.inspect_host.observer_swords[0].origin.is_equal_approx(Vector2(-300, -160)), "Joiner observer sees a host deployment sword at the committed body origin")
	local_player.global_position = Vector2(-430, 100)
	_prime_actor(local_player)
	local_player.perform_motion_blast(Vector2.RIGHT, 1.0)
	await command("inspect_host")
	check(results.inspect_host.observer_swords.size() == 2 and results.inspect_host.observer_swords[1].origin.is_equal_approx(Vector2(-120, -160)), "Joiner observer sees the host's charged retaliation from its independent effigy")
	check(results.inspect_host.damage_events == 0 and results.inspect_host.scope.is_empty(), "Replica visuals create no damage accounting or leaked action scope")
	await command("finish")
	await finish()

func client_command(name: String, payload: Dictionary) -> void:
	match name:
		"begin":
			begin_run()
			check(await until(func(): return not INTERACTIONS.current_run().is_empty()), "Joiner receives the native run token")
		"deploy":
			_attack(local_player, Vector2.RIGHT)
		"move":
			local_player.global_position = Vector2(-130, 160)
			PlayerReplicationService._sync_all_player_positions()
		"prime_ready":
			check(await until(func(): return local_player._indomitable_spirit_primed), "Host bank primes the actual owner before Attack")
		"spend":
			_attack(local_player, Vector2.RIGHT)
			check((local_player.player_feedback as OathFeedback).swords.back().origin == Vector2(180, 0), "Owner predicts one sword at its committed effigy")
		"clear_and_interleave":
			_clear_bank(local_player)
			var origin := local_player.get_attack_origin()
			var roots: Array[Dictionary] = []
			for index in 2:
				var action: Dictionary = INTERACTIONS.damage_context(local_player.new_combat_action("melee"), "melee").interaction
				roots.append(action)
				world.request_shared_attack_start_from_client(action, {"body_origin": local_player.global_position, "direction": Vector2.RIGHT})
			interleave_roots = roots.duplicate(true)
			# Intentionally submit accepted roots' contacts in alternating order.
			# This is a transport ordering probe, not a claim about ordinary input cadence.
			for index in 4:
				var victim := 102 if index < 2 else 107
				world.request_enemy_damage_from_client(victim, 20, INTERACTIONS.damage_context(roots[index % 2], "melee", {"raw_amount": 20.0, "damage_coefficient": 1.0, "attack_origin": origin}))
		"finish":
			report(name)
			await create_timer(0.1).timeout
			await finish()
			return
		"inspect", "inspect_host":
			await create_timer(0.15).timeout
	report(name)
