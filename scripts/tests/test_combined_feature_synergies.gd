extends "res://scripts/tests/test_threadbinder_runtime.gd"
## Combined-branch contracts: native Cross Stitch Marks feed the new Tempo
## receiver, while Attack, Burst and Electric descendants share one allowance.

func _run() -> void:
	for effect in ["sigil_chain", "returning_crescent"]:
		await _test_cross_stitch_mark_receiver(effect)
	await _test_switch_burst_reward_allowances()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[CombinedFeatureSynergies] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_cross_stitch_mark_receiver(effect: String) -> void:
	_character("threadbinder")
	player.returning_crescent.set_physics_process(false)
	var first := _target(Vector2(40.0, 0.0))
	var second := _target(Vector2(-40.0, 0.0))
	await _settle()
	_check(player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "damage_coefficient": 1.0}), effect + " setup: native Attack threads the first foe")
	_check(player._perform_melee_attack(Vector2.LEFT, {"damage": 20, "damage_coefficient": 1.0}), effect + " setup: switching Attack threads the second foe")
	_check(not _thread_mark(first).is_empty() and not _thread_mark(second).is_empty(), effect + " setup: Cross Stitch alone prepares both shared Marks")
	# Learn the receiver after preparing targets, so its first stack must come
	# from the generated effect rather than either setup Attack.
	player.apply_upgrade("sovereign_tempo")
	player.apply_trial_power(effect)
	first.position = Vector2(140.0, 0.0)
	second.position = Vector2(180.0, 0.0)
	await _settle()
	for target in [first, second]:
		target.hits.clear()
		target.contexts.clear()
	_check(player.apex_momentum_stacks == 0 and _thread_target() == second, effect + " starts with no Tempo and preserves the committed thread")
	var source := "sigil_chain_zone" if effect == "sigil_chain" else effect
	if effect == "sigil_chain":
		player._drop_sigil_chain_zone(Vector2(160.0, 0.0))
		player._apply_sigil_chain_zone_tick(player._sigil_chain_zones[0])
	else:
		_check(player.returning_crescent.try_launch(Vector2.RIGHT), "A learned Crescent launches without another Attack contact")
		player.returning_crescent.tick(0.30)
	_check(_source_hits(first, source).size() == 1 and _source_hits(second, source).size() == 1, effect + " delivers native damage to both Cross-Stitched foes")
	_check(player.apex_momentum_stacks == 1, effect + " grants exactly one Tempo stack across both Marked victims")
	if effect == "sigil_chain":
		player._apply_sigil_chain_zone_tick(player._sigil_chain_zones[0])
	else:
		player.returning_crescent.tick(0.40)
	var first_hits := _source_hits(first, source)
	var second_hits := _source_hits(second, source)
	_check(first_hits.size() == 2 and second_hits.size() == 2, effect + " actually delivers a second tick or return-leg hit to each foe")
	_check(player.apex_momentum_stacks == 1, effect + " repeated accepted damage cannot spend its original-action Tempo allowance twice")
	if first_hits.size() == 2 and second_hits.size() == 2:
		var root_id := int(first_hits[0].interaction.seq)
		_check(int(first_hits[1].interaction.seq) == root_id and int(second_hits[0].interaction.seq) == root_id and int(second_hits[1].interaction.seq) == root_id, effect + " preserves one root across both foes and both hits")
	_check(_thread_target() == second and not _thread_mark(first).is_empty() and not _thread_mark(second).is_empty(), effect + " damage preserves Cross Stitch's thread and enabling Marks")
	if effect == "sigil_chain":
		player._drop_sigil_chain_zone(Vector2(160.0, 0.0))
		player._apply_sigil_chain_zone_tick(player._sigil_chain_zones.back())
	else:
		_check(player.returning_crescent.try_launch(Vector2.RIGHT), "A completed Crescent permits a fresh Projectile action")
		player.returning_crescent.tick(0.30)
	_check(_source_hits(first, source).size() == 3 and _source_hits(second, source).size() == 3, effect + " fresh root deals another accepted hit to each foe")
	_check(player.apex_momentum_stacks == 2, effect + " fresh root receives its own single Tempo stack")
	_free_world()

func _test_switch_burst_reward_allowances() -> void:
	_character("threadbinder")
	var previous := _target(Vector2(40.0, 0.0))
	var next := _target(Vector2(-40.0, 0.0))
	await _settle()
	_check(player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "damage_coefficient": 1.0}), "Switch setup creates the previous endpoint through a native Attack")
	player.apply_upgrade("sovereign_tempo")
	player.apply_upgrade("pillar_convergence")
	player.apply_trial_power("storm_crown")
	# Stage the existing Crown counter so the switching Attack contributes
	# once, then its Burst against the old endpoint produces the Electric chain.
	_check(player.storm_crown_proc_every >= 2, "Learned Crown allows staging the next discharge on the Burst's contribution")
	player.storm_crown_hit_counter = player.storm_crown_proc_every - 2
	var collateral := _target(Vector2(65.0, 35.0))
	await _settle()
	_check(not _thread_mark(previous).is_empty() and _thread_mark(next).is_empty() and _thread_mark(collateral).is_empty(), "Only the prior endpoint is Marked before the switching Attack")
	_check(player._perform_melee_attack(Vector2.LEFT, {"damage": 20, "damage_coefficient": 1.0}), "Native switching Attack connects to the new foe")
	var old_bursts := _source_hits(previous, "cross_stitch_burst")
	var collateral_bursts := _source_hits(collateral, "cross_stitch_burst")
	var crown_hits := _source_hits(collateral, "storm_crown")
	var next_attacks := _source_hits(next, "melee")
	_check(old_bursts.size() == 1 and collateral_bursts.size() == 1, "Switching releases one native Burst against the old endpoint and nearby collateral")
	_check(crown_hits.size() == 1, "The native Cross Stitch Burst produces accepted Crown Electric damage")
	_check(player.apex_momentum_stacks == 1, "Switching Attack, damage against its old Mark and Crown descendants grant one Tempo stack together")
	_check(player.convergence_surge_hit_counter == 1, "Switching Attack and its Electric descendants grant one Convergence charge together")
	_check(_thread_target() == next and not _thread_mark(next).is_empty() and _thread_mark(collateral).is_empty(), "Burst and Crown preserve the first new thread without marking collateral")
	if old_bursts.size() == 1 and crown_hits.size() == 1 and next_attacks.size() == 1:
		var action: Dictionary = next_attacks[0].interaction
		_check(int(old_bursts[0].interaction.seq) == int(action.seq) and int(crown_hits[0].interaction.seq) == int(action.seq), "Native Attack, Cross Stitch Burst and Crown retain the same original-action identity")
		_check(is_equal_approx(float(crown_hits[0].damage_coefficient), 0.6 * player.storm_crown_damage_ratio), "Crown damage carries Cross Stitch's 60% coefficient, proving the Burst produced this descendant")
		# Exercise delayed accepted contacts on the same root after native
		# reactions have drained, then verify a genuinely new Attack can count.
		_packet(previous, "razor_wind", action)
		_packet(previous, "storm_crown", action)
		_check(player.apex_momentum_stacks == 1 and player.convergence_surge_hit_counter == 1, "Later Attack and Electric contacts cannot reopen either reward allowance")
		_check(_thread_target() == next and _source_hits(previous, "cross_stitch_burst").size() == 1, "Delayed contacts cannot spend Cross Stitch again or change its committed endpoint")
	_check(player._perform_melee_attack(Vector2.LEFT, {"damage": 20, "damage_coefficient": 1.0}), "A fresh native Attack connects to the current endpoint")
	_check(player.apex_momentum_stacks == 2 and player.convergence_surge_hit_counter == 2, "A fresh Attack receives one new allowance from each boss reward")
	_check(_source_hits(previous, "cross_stitch_burst").size() == 1, "Repeating the current target still does not release another Cross Stitch Burst")
	_free_world()
