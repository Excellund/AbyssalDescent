extends "res://scripts/tests/test_boss_reward_synergies.gd"
## Faultline's standalone fuse and Field conversion use real accepted damage.

func _run() -> void:
	await _test_field_receivers()
	await _test_lethal_and_cancellation()
	await _test_cover_and_conditions()
	await _test_descendant_chain()
	await _test_actual_cancellation_paths()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[FaultlineSeal] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _arm(target: Node2D, source: String = "melee") -> void:
	for index in range(player.CONVERGENCE_RULES.charges(player.convergence_surge_damage_ratio)):
		_packet(target, source, 1, 0.05)
	_check(player.convergence_window_left > 0.0, "Distinct accepted actions arm one seal")

func _test_field_receivers() -> void:
	for source in ["static_wake", "sigil_chain_zone", "void_echo_zone", "null_corridor_deflect"]:
		_synergy_world()
		player.apply_upgrade("pillar_convergence")
		var primary := _observed_enemy(Vector2(300, 0))
		var victim := _observed_enemy(Vector2(350, 0))
		var outside := _observed_enemy(Vector2(390, 0))
		_arm(primary)
		var before := victim.hits.size()
		_packet(outside, source)
		_check(player.convergence_window_left > 0.0 and victim.hits.size() == before, source + " outside the seal cannot detonate it")
		primary.blocked = true
		_packet(primary, source)
		_check(player.convergence_window_left > 0.0, "Rejected Field contact cannot detonate the seal")
		primary.blocked = false
		_packet(primary, "returning_crescent")
		_check(player.convergence_window_left > 0.0, "Ordinary Projectile damage inside does not impersonate Field damage")
		_packet(primary, source)
		_check(player.convergence_window_left == 0.0 and victim.hits.size() == before + 1 and victim.hits.back().amount == 54, source + " accepted damage converts the fuse into a 270%-Damage Burst")
		_check(victim.velocity.is_zero_approx() and not player._shared_owned_field_contains(victim), "The replacement provides neither displacement nor owned Field membership")
		var burst: Dictionary = victim.hits.back().context.interaction
		_check(INTERACTIONS.action_forms(burst) == ["Burst"] and (int(burst.ancestry) & INTERACTIONS.FAULTLINE_ANCESTRY) != 0, "Actual seal damage has Burst form and persistent self-exclusion ancestry")
		await _settle()
		_free_world()

func _test_lethal_and_cancellation() -> void:
	_synergy_world()
	player.apply_upgrade("pillar_convergence")
	var primary := _observed_enemy(Vector2(300, 0))
	var victim := _observed_enemy(Vector2(340, 0))
	_packet(primary, "melee", 1, 0.05)
	_packet(primary, "melee", 1, 0.05)
	primary.health_state.current_health = 1
	_packet(primary, "melee", 1, 0.05)
	_check(player.convergence_window_left > 0.0 and player._convergence_origin == Vector2(300, 0), "An accepted lethal planting hit still creates the seal at the defeated foe")
	player._update_convergence_window(.81)
	_check(victim.hits.size() == 1 and victim.hits[0].amount == 36, "The ordinary Burst survives its original foe's death")
	player._update_convergence_window(.61)
	_arm(victim)
	player.clear_lingering_combat_effects()
	var before := victim.hits.size()
	player._update_convergence_window(2.0)
	_check(victim.hits.size() == before and player.convergence_window_left == 0.0 and player.convergence_pulse_cooldown == 0.0, "Room/snapshot cleanup cancels the fuse, lock and deferred damage")
	_arm(victim)
	player.set_alive(false)
	_check(victim.hits.size() == before + 3 and player.convergence_window_left == 0.0, "Owner death clears its armed seal without posthumous damage")
	player.set_alive(true)
	await _settle()
	_free_world()
	_synergy_world()
	player.apply_upgrade("pillar_convergence")
	primary = _observed_enemy(Vector2(300, 0))
	var cancel_target := _observed_enemy(Vector2(330, 0))
	victim = _observed_enemy(Vector2(350, 0))
	_arm(primary)
	cancel_target.cancel_after_damage = player
	player._update_convergence_window(.81)
	_check(cancel_target.hits.size() == 1 and victim.hits.is_empty(), "Cancellation inside an accepted Burst hit prevents every remaining victim")
	await _settle()
	_free_world()

func _test_cover_and_conditions() -> void:
	_synergy_world()
	player.apply_upgrade("pillar_convergence")
	player.apply_upgrade("first_strike")
	player.apply_upgrade("marked_prey")
	player.apply_upgrade("patient_hunter")
	player.apply_trial_power("wraithstep")
	var primary := _observed_enemy(Vector2(300, 0))
	var prepared := _observed_enemy(Vector2(300, 60))
	var plain := _observed_enemy(Vector2(260, 0))
	var covered := _observed_enemy(Vector2(370, 0))
	_wall(Vector2(337, 0), 10.0)
	DAMAGEABLE.apply_mark(prepared, "wraithstep", .15, 2.0, 1, player.new_combat_action("dash"))
	DAMAGEABLE.apply_slow(prepared, 2.0, .75, 1, player.new_combat_action("dash"))
	await _settle()
	_arm(primary)
	player._update_convergence_window(.81)
	var prepared_ratio := float(DAMAGEABLE.status_snapshot(prepared, 1).mark_ratio)
	var expected := int(round((20.0 + 16.0 + 12.0 + 12.0) * 1.8 * (1.0 + prepared_ratio)))
	_check(prepared.hits.size() == 1 and prepared.hits[0].amount == expected, "Burst resolves First Strike, Patient Hunter, Marked Prey and Mark once against its actual prepared victim")
	_check(plain.hits.size() == 1 and plain.hits[0].amount == 65, "An unprepared victim receives its own conditional Damage basis, not the parent's resolved hit")
	_check(covered.hits.is_empty(), "Solid cover blocks the stationary Burst")
	if not prepared.hits.is_empty():
		_check(is_equal_approx(prepared.hits[0].context.raw_amount, 36.0) and is_equal_approx(prepared.hits[0].context.damage_coefficient, 1.8), "Each Burst context retains the unconditioned raw descriptor and effective coefficient")
	await _settle()
	_free_world()

func _test_descendant_chain() -> void:
	_synergy_world()
	player.apply_upgrade("pillar_convergence")
	player.apply_trial_power("spark_relay")
	player.apply_upgrade("shatterwake")
	var primary := _observed_enemy(Vector2(180, 0))
	var receiver := _observed_enemy(Vector2(220, 0))
	_arm(primary, "storm_crown")
	var root_action: Dictionary = player._convergence_interaction.duplicate(true)
	player._update_convergence_window(.81)
	_check(is_instance_valid(player.spark_relay_controller), "The real Faultline Burst activates the learned Burst-to-Electric-Projectile receiver")
	if is_instance_valid(player.spark_relay_controller):
		player.spark_relay_controller.set_physics_process(false)
		player.spark_relay_controller.tick(.5)
	var relay_hits: Array = primary.hits.filter(func(hit: Dictionary) -> bool: return hit.type == "spark_relay_projectile")
	relay_hits.append_array(receiver.hits.filter(func(hit: Dictionary) -> bool: return hit.type == "spark_relay_projectile"))
	_check(not relay_hits.is_empty(), "Faultline's native seeking Relay reaches a real enemy")
	player._update_convergence_window(.61)
	if not relay_hits.is_empty():
		var relay: Dictionary = relay_hits[0].context.interaction
		_check((int(relay.ancestry) & INTERACTIONS.FAULTLINE_ANCESTRY) != 0 and int(relay.seq) == int(root_action.seq), "The actual Electric descendant retains Faultline ancestry and the original action")
		_packet(primary, "static_wake", 1, .05, relay)
		_packet(receiver, "melee", 1, .05, relay)
	_check(player.convergence_window_left == 0.0 and player.convergence_surge_hit_counter == 0, "Electric, Field and Attack-shaped descendants cannot replant after the rearm lock")
	# A delayed kill-created Field may outlive the original effect; ancestry must
	# still exclude it even if the controller receives a distinct child root.
	var delayed := player.new_combat_action("field")
	delayed.ancestry = INTERACTIONS.FAULTLINE_ANCESTRY
	_packet(primary, "static_wake", 1, .05, delayed)
	_check(player.convergence_surge_hit_counter == 0, "Persistent ancestry prevents a later child Field from banking fresh charges")
	_packet(primary, "storm_crown", 1, .05)
	_check(player.convergence_surge_hit_counter == 1, "Independent Electric damage remains a valid input after the finite chain")
	await _settle()
	_free_world()

func _test_actual_cancellation_paths() -> void:
	for route in ["death", "discard", "remove", "room", "snapshot", "new_owner_epoch"]:
		for armed in [false, true]:
			_synergy_world()
			player.apply_upgrade("pillar_convergence")
			player.apply_upgrade("unbroken_oath")
			var target := _observed_enemy(Vector2(300, 0))
			if armed:
				_arm(target)
			else:
				_packet(target, "melee", 1, .05)
				_check(player.convergence_surge_hit_counter == 1, "A real accepted action creates partial charge before cancellation")
			player.indomitable_damage_bank = 10.0
			var snapshot: Dictionary = player.build_run_snapshot()
			var delayed := player._faultline_cue({"position": Vector2(300, 0), "power_ratio": .22})
			match route:
				"death": player.set_alive(false)
				"discard": player.discard_pending_combat_input()
				"remove": player.set_combat_removed(true)
				"room": player.clear_lingering_combat_effects()
				"snapshot": player.apply_run_snapshot(snapshot)
				"new_owner_epoch": player.combat_interactions.accept_epoch(player.combat_interactions._accepted_epoch + 1, INTERACTIONS.current_run(), INTERACTIONS.current_room())
			_check(player.convergence_window_left == 0.0 and player.convergence_surge_hit_counter == 0 and player.convergence_pulse_cooldown == 0.0 and not is_instance_valid(player.player_feedback.faultline_seal), route + " synchronously clears active and partial Faultline state through the real lifecycle")
			if armed:
				_check(player.cues.has("boss_convergence_clear"), route + " emits an authoritative clear for an armed marker")
			var hits := target.hits.size()
			player._on_cue_boss_convergence_start(delayed)
			_check(not is_instance_valid(player.player_feedback.faultline_seal), route + " rejects a previously unseen start cue from before cancellation")
			player._update_convergence_window(1.5)
			_check(target.hits.size() == hits, route + " leaves no deferred Burst after cancellation")
			_check(is_equal_approx(player.indomitable_damage_bank, 10.0), "Faultline cancellation preserves the unrelated learned Oath bank")
			await _settle()
			_free_world()
