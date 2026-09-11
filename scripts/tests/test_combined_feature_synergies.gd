extends "res://scripts/tests/test_threadbinder_runtime.gd"
## Shared Mark producers still feed Field/Projectile Tempo, while Effigy Keeper
## delivers one original Attack across melee, Electric and extended descendants.

func _run() -> void:
	for effect in ["sigil_chain", "returning_crescent"]:
		await _test_marked_effect_receiver(effect)
	await _test_effigy_reward_allowances()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[CombinedFeatureSynergies] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_marked_effect_receiver(effect: String) -> void:
	_character("threadbinder")
	player.returning_crescent.set_physics_process(false)
	_effigy_attack()
	player.apply_trial_power("dread_resonance")
	var first := _target(player.effigy_position + Vector2(35.0, 0.0))
	var second := _target(player.effigy_position + Vector2(55.0, 0.0))
	await _settle()
	_effigy_attack()
	_check(DAMAGEABLE.status_snapshot(first, 1).mark_ratio > 0.0 and DAMAGEABLE.status_snapshot(second, 1).mark_ratio > 0.0, effect + " setup: a learned native Dread Attack Marks both effigy targets")
	# Learn the receiver afterward so setup contacts cannot supply its stacks.
	player.apply_upgrade("sovereign_tempo")
	player.apply_trial_power(effect)
	first.position = Vector2(140.0, 0.0)
	second.position = Vector2(180.0, 0.0)
	await _settle()
	for target in [first, second]:
		target.hits.clear()
		target.contexts.clear()
	var anchor := player.effigy_position
	var attack_count := player.attack_combo_counter
	_check(player.apex_momentum_stacks == 0, effect + " starts with no Tempo stacks")
	var source := "sigil_chain_zone" if effect == "sigil_chain" else effect
	if effect == "sigil_chain":
		player._drop_sigil_chain_zone(Vector2(160.0, 0.0))
		player._apply_sigil_chain_zone_tick(player._sigil_chain_zones[0])
	else:
		_check(player.returning_crescent.try_launch(Vector2.RIGHT), "A learned Crescent launches as its native Projectile action")
		player.returning_crescent.tick(0.30)
	_check(_source_hits(first, source).size() == 1 and _source_hits(second, source).size() == 1, effect + " delivers native accepted damage to both Marked foes")
	_check(player.apex_momentum_stacks == 1, effect + " grants one Tempo stack across both Marked victims")
	if effect == "sigil_chain":
		player._apply_sigil_chain_zone_tick(player._sigil_chain_zones[0])
	else:
		player.returning_crescent.tick(0.40)
	var first_hits := _source_hits(first, source)
	var second_hits := _source_hits(second, source)
	_check(first_hits.size() == 2 and second_hits.size() == 2, effect + " actually delivers a second tick or return-leg hit to both foes")
	_check(player.apex_momentum_stacks == 1, effect + " repeated damage cannot spend its original-action Tempo allowance twice")
	if first_hits.size() == 2 and second_hits.size() == 2:
		var root_id := int(first_hits[0].interaction.seq)
		_check(int(first_hits[1].interaction.seq) == root_id and int(second_hits[0].interaction.seq) == root_id and int(second_hits[1].interaction.seq) == root_id, effect + " preserves one root across both foes and both hits")
	_check(player.effigy_deployed and player.effigy_position == anchor and player.attack_combo_counter == attack_count, effect + " damage neither moves the effigy nor invents an Attack input")
	if effect == "sigil_chain":
		player._drop_sigil_chain_zone(Vector2(160.0, 0.0))
		player._apply_sigil_chain_zone_tick(player._sigil_chain_zones.back())
	else:
		_check(player.returning_crescent.try_launch(Vector2.RIGHT), "A completed Crescent permits a fresh Projectile action")
		player.returning_crescent.tick(0.30)
	_check(_source_hits(first, source).size() == 3 and _source_hits(second, source).size() == 3, effect + " fresh root deals another accepted hit to each foe")
	_check(player.apex_momentum_stacks == 2, effect + " fresh root receives its own Tempo allowance")
	_free_world()

func _test_effigy_reward_allowances() -> void:
	_character("threadbinder")
	_effigy_attack()
	var anchor := player.effigy_position
	var first := _target(anchor + Vector2(35.0, 0.0))
	var second := _target(anchor + Vector2(55.0, 0.0))
	player.apply_trial_power("dread_resonance")
	await _settle()
	_effigy_attack()
	_check(DAMAGEABLE.status_snapshot(first, 1).mark_ratio > 0.0 and DAMAGEABLE.status_snapshot(second, 1).mark_ratio > 0.0, "The learned Dread producer prepares both shared Marks through the effigy's real Attack")
	for target in [first, second]:
		target.hits.clear()
		target.contexts.clear()
	player.apply_upgrade("sovereign_tempo")
	player.apply_upgrade("pillar_convergence")
	player.apply_trial_power("storm_crown")
	player.storm_crown_hit_counter = player.storm_crown_proc_every - 1
	var attack_count := player.attack_combo_counter
	_effigy_attack()
	var first_attacks := _source_hits(first, "melee")
	var second_attacks := _source_hits(second, "melee")
	var crown_hits: Array[Dictionary] = _source_hits(first, "storm_crown")
	crown_hits.append_array(_source_hits(second, "storm_crown"))
	_check(first_attacks.size() == 1 and second_attacks.size() == 1 and not crown_hits.is_empty(), "A native effigy cleave produces its actual Crown Electric descendant")
	_check(player.attack_combo_counter == attack_count + 1, "Effigy delivery and Electric descendants create one deliberate Attack count")
	_check(player.apex_momentum_stacks == 1 and player.convergence_surge_hit_counter == 1, "Effigy Attack, Marked contacts and Electric descendants share one Tempo and Convergence allowance")
	_check(player.effigy_position == anchor and player.effigy_deployed, "Shared reward reactions leave the fixed effigy intact")
	if first_attacks.size() == 1 and not crown_hits.is_empty():
		var action: Dictionary = first_attacks[0].interaction
		_check(int(crown_hits[0].interaction.seq) == int(action.seq), "The native Attack and Crown descendant retain one original-action identity")
		_check(is_equal_approx(float(crown_hits[0].damage_coefficient), player.storm_crown_damage_ratio), "Crown preserves the original Attack coefficient without a retired Cross Stitch multiplier")
		_packet(first, "razor_wind", action)
		_packet(first, "storm_crown", action)
		_check(player.apex_momentum_stacks == 1 and player.convergence_surge_hit_counter == 1, "Delayed attack-hit and Electric contacts cannot reopen either reward allowance")
	_effigy_attack()
	_check(player.apex_momentum_stacks == 2 and player.convergence_surge_hit_counter == 2, "A fresh real Attack receives one new allowance from both boss rewards")
	_check(_source_hits(first, "cross_stitch_burst").is_empty() and _source_hits(second, "cross_stitch_burst").is_empty(), "Effigy synergy cannot revive the retired alternating-target Burst")
	_free_world()
