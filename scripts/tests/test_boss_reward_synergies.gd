extends "res://scripts/tests/test_connected_build_runtime.gd"
## Exercise learned rewards through native effects and the accepted-damage boundary.

class ObservedEnemy extends "res://scripts/enemy_base.gd":
	var hits: Array[Dictionary] = []
	var blocked := false
	var cancel_after_damage: Node = null
	var mark_after_damage: Node = null

	func _ready() -> void:
		set_physics_process(false)
		max_health = 10000
		_create_health_state()
		add_to_group("enemies")
		crowd_separation_strength = 0.0

	func take_damage(amount: int, context: Dictionary = {}) -> void:
		if blocked:
			return
		var before := get_current_health()
		super.take_damage(amount, context)
		if get_current_health() < before:
			hits.append({"amount": before - get_current_health(), "type": context.get("attack_type", ""), "context": context.duplicate(true)})
			if is_instance_valid(mark_after_damage):
				mark_after_damage._apply_eclipse_mark(global_position)
			if is_instance_valid(cancel_after_damage):
				cancel_after_damage.clear_lingering_combat_effects()

func _observed_enemy(position: Vector2) -> ObservedEnemy:
	var target := ObservedEnemy.new()
	_add_circle(target, 13.0)
	world.add_child(target)
	target.global_position = position
	return target

func _synergy_world() -> void:
	_make_world()
	player.returning_crescent.set_physics_process(false)

func _wake(start: Vector2, finish: Vector2) -> Dictionary:
	var action := player.new_combat_action("dash")
	player.static_wake_controller.begin_dash(action)
	player.static_wake_controller.append_segment(start, finish)
	player.static_wake_controller.end_dash()
	return action

func _run() -> void:
	await _test_shared_reward_allowances()
	await _test_native_electric_engine()
	await _test_convergence_gathering()
	await _test_marked_native_effects()
	await _test_accepted_prestate()
	await _test_tempo_descendants()
	await _test_retirement_and_cancellation()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[BossRewardSynergies] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_shared_reward_allowances() -> void:
	for first_source in ["melee", "static_wake"]:
		_synergy_world()
		_learn("wraithstep", 1)
		var first := _observed_enemy(Vector2(40, 0))
		var second := _observed_enemy(Vector2(60, 0))
		player._apply_wraithstep_marks_during_dash(Vector2.ZERO, Vector2(80, 0))
		_packet(first, "static_wake")
		_check(player.convergence_surge_hit_counter == 0 and player.apex_momentum_stacks == 0, "Electric damage on Mark cannot grant unlearned boss rewards")
		player.apply_upgrade("pillar_convergence")
		player.apply_upgrade("sovereign_tempo")
		var action := player.new_combat_action("attack")
		_packet(first, first_source, 20, 1, action)
		for target in [first, second]:
			for source in ["melee", "razor_wind", "static_wake", "storm_crown", "sigil_chain_zone"]:
				_packet(target, source, 20, 1, action)
		_check(first.hits.size() == 7 and second.hits.size() == 5, "Repeated accepted shapes and ticks still deal their own damage")
		_check(player.convergence_surge_hit_counter == 1, first_source + " shares one Convergence charge with all Electric and Attack descendants")
		_check(player.apex_momentum_stacks == 1, first_source + " shares one Tempo charge with all marked damage and Attack descendants")
		_check(DAMAGEABLE.status_snapshot(first, 1).mark_ratio > 0.0 and DAMAGEABLE.status_snapshot(second, 1).mark_ratio > 0.0, "Tempo inputs preserve both foes' Mark windows")
		await _settle()
		_free_world()
	_synergy_world()
	player.apply_upgrade("pillar_convergence")
	player.apply_upgrade("sovereign_tempo")
	var unmarked := _observed_enemy(Vector2(40, 0))
	for source in ["returning_crescent", "sigil_chain_zone", "sovereigns_double", "rupture_wave", "razor_orbit"]:
		_packet(unmarked, source)
	_check(player.convergence_surge_hit_counter == 0 and player.apex_momentum_stacks == 0, "Unmarked non-Electric generated damage cannot count as an Attack hit")
	await _settle()
	_free_world()

func _test_native_electric_engine() -> void:
	for level in [1, 2]:
		_synergy_world()
		_learn("static_wake", 1)
		player.apply_upgrade("first_strike")
		player.apply_upgrade("lacuna_echo")
		for pick in range(level):
			player.apply_upgrade("pillar_convergence")
		var wake_target := _observed_enemy(Vector2(500, 0))
		var bystander := _observed_enemy(Vector2(565, 0))
		var body_target := _observed_enemy(Vector2(40, 0))
		var every := 3 if level == 1 else 2
		var action: Dictionary = {}
		for charge in range(every):
			player.static_wake_controller.cancel()
			action = _wake(Vector2(480, 0), Vector2(520, 0))
			player.static_wake_controller.tick(.25)
			_check((player.convergence_window_left > 0.0) == (charge == every - 1), "Native Wake reaches the learned Faultline threshold on distinct action %d" % [charge + 1])
		var wake_hit: Dictionary = wake_target.hits[0]
		var wake_raw := float(player.static_wake_damage) * 4.5 * .25
		var wake_coefficient := wake_raw / float(player.damage)
		var field_multiplier := 1.14 + float(player.void_echo_damage) * .0015
		var wake_expected := int(floor((wake_raw + wake_coefficient * player.first_strike_bonus_damage) * field_multiplier + .000000001))
		_check(wake_hit.amount == wake_expected, "Native Wake retains its actual-target conditional coefficient and Lacuna bonus")
		_check(player._convergence_interaction.seq == action.seq and player._convergence_origin == wake_target.position, "The seal retains its planting Dash root and anchors at the distant struck foe")
		_check(not player._shared_owned_field_contains(bystander) and not player._shared_owned_field_contains(body_target), "A fuse marker registers no Field at either the seal or player")
		_check(bystander.hits.is_empty(), "The planting Field event cannot immediately detonate the new seal")
		player.static_wake_controller.tick(.25)
		var coefficient := 2.7 if level == 1 else 3.6
		var expected := int(round((float(player.damage) + player.first_strike_bonus_damage) * coefficient))
		_check(bystander.hits.size() == 1 and bystander.hits[0].amount == expected, "A later real Wake tick releases the stronger Burst with the bystander's own conditions and no borrowed Field bonus")
		_check(body_target.hits.is_empty() and bystander.velocity.is_zero_approx(), "Faultline neither reaches the distant player nor displaces nearby foes")
		_check(player.convergence_window_left == 0.0 and player.convergence_surge_hit_counter == 0 and player.convergence_pulse_cooldown > 0.0, "Early detonation closes the seal and enforces its rearm lock")
		var during_lock := player.new_combat_action("dash")
		_packet(wake_target, "static_wake", 20, 1, during_lock)
		player._update_convergence_window(.61)
		_packet(wake_target, "static_wake", 20, 1, during_lock)
		_check(player.convergence_surge_hit_counter == 0, "An action accepted during rearm cannot bank delayed charging")
		_packet(wake_target, "static_wake")
		_check(player.convergence_surge_hit_counter == 1, "A fresh Electric action charges after rearm")
		await _settle()
		_free_world()

func _test_convergence_gathering() -> void:
	# Historical fixture entry retained; assert the replacement's fixed seal.
	for level in [1, 2]:
		_synergy_world()
		for pick in range(level):
			player.apply_upgrade("pillar_convergence")
		player.dash_cooldown_left = 1.0
		var distant := _observed_enemy(Vector2(500, 0))
		var radius := 76.0 if level == 1 else 90.0
		var edge := _observed_enemy(Vector2(500 + radius, 0))
		var outer := _observed_enemy(Vector2(501 + radius, 0))
		for charge in range(3 if level == 1 else 2):
			_packet(distant, "melee")
		_check(player.convergence_window_left > 0.0 and player.dash_cooldown_left == 1.0, "Attack input arms the seal without the retired Dash refund")
		var during := player.new_combat_action("attack")
		_packet(outer, "melee", 20, 1, during)
		player.position = Vector2(-300, 0)
		distant.position = Vector2(900, 0)
		player._update_convergence_window(.79)
		_check(edge.hits.is_empty() and player._convergence_origin == Vector2(500, 0), "Repeated hits, target movement and owner movement cannot refresh or relocate the fuse")
		var before := outer.hits.size()
		player._update_convergence_window(.02)
		_check(edge.hits.size() == 1 and edge.hits[0].amount == int(round(float(player.damage) * (1.8 if level == 1 else 2.4))), "The ordinary fuse delivers its exact level damage at the compact boundary")
		_check(outer.hits.size() == before and edge.velocity.is_zero_approx(), "The Burst excludes the outside edge and never Pulls its victims")
		player._update_convergence_window(1.0)
		_packet(outer, "melee", 20, 1, during)
		_check(player.convergence_surge_hit_counter == 0, "Delayed contacts from a fuse-locked action cannot charge later")
		await _settle()
		_free_world()

func _test_marked_native_effects() -> void:
	for generator in ["wraithstep", "eclipse_mark", "dread_resonance"]:
		for effect in ["returning_crescent", "sigil_chain", "sovereigns_double"]:
			_synergy_world()
			_learn(generator, 1)
			player.apply_upgrade("sovereign_tempo")
			player.apply_upgrade("first_strike")
			var target := _observed_enemy(Vector2(160, 0))
			match generator:
				"wraithstep": player._apply_wraithstep_marks_during_dash(Vector2(120, 0), Vector2(180, 0))
				"eclipse_mark": player._apply_eclipse_mark(target.position)
				"dread_resonance":
					_packet(target, "melee")
					player._update_apex_momentum(player.apex_momentum_stack_duration + .01)
			var mark: Dictionary = DAMAGEABLE.status_snapshot(target, 1)
			_check(mark.mark_ratio > 0.0 and player.apex_momentum_stacks == 0, generator + " prepares Mark independently of the next Tempo charge")
			target.hits.clear()
			var expected_raw := 0.0
			var expected_coefficient := 0.0
			match effect:
				"returning_crescent":
					_learn(effect, 1)
					expected_coefficient = .45 * player.returning_crescent_damage_scale
					expected_raw = round(player.damage * expected_coefficient)
					await _settle()
					_check(player.returning_crescent.try_launch(Vector2.RIGHT), "Learned Crescent launches without a connected Attack")
					player.returning_crescent.tick(.30)
				"sigil_chain":
					_learn(effect, 1)
					expected_coefficient = player.sigil_chain_damage_ratio
					expected_raw = round(player.damage * expected_coefficient)
					player._drop_sigil_chain_zone(target.position)
					player._apply_sigil_chain_zone_tick(player._sigil_chain_zones[0])
				"sovereigns_double":
					player.apply_upgrade(effect)
					expected_coefficient = .55
					expected_raw = 11.0
					player.boss_combinations.create_shade(Vector2(120, 0))
					player._perform_melee_attack(Vector2.RIGHT, {"damage": 20})
			var label: String = generator + " -> " + effect
			var multiplier := 1.0 + float(mark.mark_ratio) + float(mark.dread_stacks) * player.dread_resonance_damage_ratio_per_stack
			var expected := int(round((expected_raw + expected_coefficient * player.first_strike_bonus_damage) * multiplier))
			_check(not target.hits.is_empty() and target.hits[0].amount == expected, label + " preserves effect scaling and resolves target Mark and Boon once")
			_check(player.apex_momentum_stacks == 1, label + " charges Tempo through accepted marked damage")
			if effect == "returning_crescent":
				player.returning_crescent.tick(.40)
			elif effect == "sigil_chain":
				player._apply_sigil_chain_zone_tick(player._sigil_chain_zones[0])
			if effect != "sovereigns_double":
				_check(target.hits.size() == 2, label + " actually delivers a second native hit before checking its repeat limit")
			_check(player.apex_momentum_stacks == 1, label + " keeps one Tempo allowance across repeated ticks or the return leg")
			_check(DAMAGEABLE.status_snapshot(target, 1).mark_ratio == mark.mark_ratio, label + " leaves its enabling Mark available")
			await _settle()
			_free_world()

func _test_accepted_prestate() -> void:
	_synergy_world()
	player.apply_upgrade("pillar_convergence")
	player.apply_upgrade("sovereign_tempo")
	_learn("eclipse_mark", 1)
	var target := _observed_enemy(Vector2(40, 0))
	player._apply_eclipse_mark(target.position)
	target.blocked = true
	var action := player.new_combat_action("dash")
	_packet(target, "static_wake", 20, 1, action)
	_packet(target, "melee", 20, 1, action)
	_check(target.hits.is_empty() and player.convergence_surge_hit_counter == 0 and player.apex_momentum_stacks == 0, "Rejected Electric and Attack damage against Mark grants neither reward")
	target.blocked = false
	_packet(target, "static_wake", 0, 0, action)
	_check(player.convergence_surge_hit_counter == 0 and player.apex_momentum_stacks == 0, "A zero-damage contact cannot consume either reward allowance")
	_packet(target, "static_wake", 20, 1, action)
	_check(player.convergence_surge_hit_counter == 1 and player.apex_momentum_stacks == 1, "The first accepted packet can spend allowances preserved by rejection")
	DAMAGEABLE.clear_statuses(target)
	player._update_apex_momentum(player.apex_momentum_stack_duration + .01)
	target.mark_after_damage = player
	action = player.new_combat_action("returning_crescent")
	_packet(target, "returning_crescent", 20, 1, action)
	_check(DAMAGEABLE.status_snapshot(target, 1).mark_ratio > 0.0 and player.apex_momentum_stacks == 0, "Mark applied inside the damage callback cannot retroactively qualify that same hit")
	_packet(target, "returning_crescent", 20, 1, action)
	_check(player.apex_momentum_stacks == 1, "A later accepted hit from the same action can use the now-existing Mark")
	target.mark_after_damage = null
	DAMAGEABLE._target_status(target).advance(player.eclipse_mark_duration + .01)
	player._update_apex_momentum(player.apex_momentum_stack_duration + .01)
	_packet(target, "returning_crescent")
	_check(player.apex_momentum_stacks == 0, "Expired Mark cannot qualify a later non-Attack hit")
	await _settle()
	_free_world()

func _test_tempo_descendants() -> void:
	_synergy_world()
	player.apply_upgrade("sovereign_tempo")
	player.apply_upgrade("sovereign_tempo")
	_learn("wraithstep", 1)
	var primary := _observed_enemy(Vector2(40, 0))
	var chained := _observed_enemy(Vector2(140, 0))
	player._apply_wraithstep_marks_during_dash(Vector2.ZERO, Vector2(160, 0))
	_packet(primary, "melee")
	_learn("storm_crown", 3)
	player.storm_crown_hit_counter = player.storm_crown_proc_every - 1
	player.dash_cooldown_left = 1.0
	var movement := player.new_combat_action("dash")
	player._accept_shared_movement("dash", Vector2.ZERO, movement)
	_check(primary.hits.back().type == "apex_momentum_wave" and chained.hits.size() == 1 and chained.hits[0].type == "storm_crown", "Native Tempo Burst can produce Crown Electric damage on another Marked foe")
	_check(player.apex_momentum_stacks == 0 and player.dash_cooldown_left < 1.0, "Accepted Tempo damage refunds Dash without its Burst or Crown refilling Tempo")
	var wave_action: Dictionary = primary.hits.back().context.interaction
	var crown_action: Dictionary = chained.hits[0].context.interaction if not chained.hits.is_empty() else {}
	_check((int(wave_action.ancestry) & INTERACTIONS.TEMPO_ANCESTRY) != 0 and (int(crown_action.get("ancestry", 0)) & INTERACTIONS.TEMPO_ANCESTRY) != 0, "Tempo ancestry survives its native Crown descendant")
	_packet(primary, "melee", 20, 1, wave_action)
	_packet(primary, "sovereigns_double", 20, 1, crown_action)
	_check(player.apex_momentum_stacks == 0, "Even Attack-shaped and Echo descendants cannot shed Tempo's self-refill restriction")
	var canonical := player.new_combat_action("dash")
	canonical["source"] = "apex_momentum_wave"
	canonical["ancestry"] = 0
	var validated := INTERACTIONS.validate_action(canonical, 1)
	_check((int(validated.get("ancestry", 0)) & INTERACTIONS.TEMPO_ANCESTRY) != 0, "Authoritative validation restores Tempo ancestry from its canonical source")
	_packet(primary, "apex_momentum_wave", 20, 1, canonical)
	_check(player.apex_momentum_stacks == 0, "A canonical Tempo packet cannot remove its restriction with zero ancestry metadata")
	await _settle()
	_free_world()

func _test_retirement_and_cancellation() -> void:
	_synergy_world()
	player.apply_upgrade("pillar_convergence")
	player.apply_upgrade("sovereign_tempo")
	_learn("wraithstep", 1)
	var target := _observed_enemy(Vector2(40, 0))
	player._apply_wraithstep_marks_during_dash(Vector2.ZERO, Vector2(60, 0))
	var oldest := player.new_combat_action("dash")
	_packet(target, "static_wake", 1, 0, oldest)
	player.convergence_window_left = 100.0
	for index in range(INTERACTIONS.MAX_ROOTS):
		_packet(target, "static_wake", 1, 0)
	_check(player.combat_interactions._roots.size() <= INTERACTIONS.MAX_ROOTS, "Mixed boss-reward reactions retain the bounded root ledger")
	player.convergence_window_left = 0.0
	player.convergence_surge_hit_counter = 0
	player.apex_momentum_stacks = 0
	_packet(target, "static_wake", 1, 0, oldest)
	_check(player.convergence_surge_hit_counter == 0 and player.apex_momentum_stacks == 0, "Retired roots cannot reopen either boss-reward allowance")
	var cancelled := player.new_combat_action("dash")
	player.clear_lingering_combat_effects()
	_packet(target, "static_wake", 1, 0, cancelled)
	_packet(target, "melee", 1, 0, cancelled)
	_check(player.convergence_surge_hit_counter == 0 and player.apex_momentum_stacks == 0, "Cancelled Electric and Attack packets cannot rebuild either reward")
	target.cancel_after_damage = player
	_packet(target, "melee")
	_check(player.convergence_surge_hit_counter == 0 and player.apex_momentum_stacks == 0, "Cancellation inside accepted damage prevents queued reward reactions")
	target.cancel_after_damage = null
	_packet(target, "melee")
	_check(player.convergence_surge_hit_counter == 1 and player.apex_momentum_stacks == 1, "A new action after cancellation can charge both learned rewards normally")
	await _settle()
	_free_world()
