extends "res://scripts/tests/test_shared_build_producers.gd"
## Character passives retain their own triggers while sharing accepted damage,
## conditional Damage coefficients and original-action reaction allowances.

class BlockedPassiveEnemy extends HitEnemy:
	var blocked: bool = true
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		if not blocked:
			super.take_damage(amount, context)

func _character(id: String) -> void:
	_make_world()
	player.apply_character_package(player.CHARACTER_REGISTRY.get_character(id))
	player.damage = 20

func _packet(target: Node2D, source: String, action: Dictionary = {}) -> void:
	var root_action := action if not action.is_empty() else player.new_combat_action(source)
	DAMAGEABLE.apply_damage(target, 20, INTERACTIONS.damage_context(root_action, source, {"raw_amount": 20.0, "damage_coefficient": 1.0}), 1)

func _source_hits(target: HitEnemy, source: String) -> Array[Dictionary]:
	return target.contexts.filter(func(context: Dictionary) -> bool: return context.get("attack_type") == source)

func _run() -> void:
	for source in ["iron_retort_shockwave", "sigil_burst", "veilstep_rhythm_wave"]:
		_check(INTERACTIONS.effect_forms(source) == ["Burst"], source + " exposes its existing Burst form")
		_check(not INTERACTIONS.is_attack_hit(source), source + " deals damage without another Attack hit")
	await _test_retort_acceptance()
	await _test_retort_scaling()
	await _test_sigil_triggers()
	await _test_sigil_target_conditions()
	await _test_veilstep_limits()
	await _test_farline_scope()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[CharacterPassiveRuntime] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_retort_acceptance() -> void:
	for source in ["melee", "razor_wind", "blast_drive"]:
		_character("bastion")
		var target := BlockedPassiveEnemy.new()
		_add_circle(target, 13.0)
		world.add_child(target)
		target.position = Vector2(100.0 if source == "razor_wind" else 40.0, 0.0)
		if source == "razor_wind":
			player.apply_trial_power("razor_wind")
		await _settle()
		player._activate_iron_retort_brace(Vector2.ZERO)
		var context := {"damage": 20, "damage_coefficient": 1.0, "source": "blast_drive" if source == "blast_drive" else "melee"}
		_check(not player._perform_melee_attack(Vector2.RIGHT, context), source + " rejected damage is not a connected Attack")
		_check(player.iron_retort_brace_ready and is_zero_approx(player.iron_retort_guard_left), source + " rejection preserves brace without granting guard")
		target.blocked = false
		_check(player._perform_melee_attack(Vector2.RIGHT, context), source + " accepted damage connects")
		_check(not player.iron_retort_brace_ready and is_equal_approx(player.iron_retort_guard_left, 1.5), source + " connection spends one brace and grants existing guard")
		_free_world()

func _test_retort_scaling() -> void:
	_character("bastion")
	player.first_strike_bonus_damage = 16
	player.severing_edge_bonus_damage = 14
	player.reward_storm_crown = true
	player.storm_crown_proc_every = 999
	var direct := _target(Vector2(40.0, 0.0))
	var collateral := _target(Vector2(40.0, 40.0))
	direct.health_state.current_health = 4500
	await _settle()
	player._activate_iron_retort_brace(Vector2.ZERO)
	player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "damage_coefficient": 1.0})
	var bursts := _source_hits(collateral, "iron_retort_shockwave")
	_check(not bursts.is_empty() and is_equal_approx(float(bursts[0].damage_coefficient), 0.99), "Retort Burst keeps 55% of the empowered 180% Damage coefficient")
	_check(collateral.hits.any(func(hit: Dictionary) -> bool: return hit.type == "iron_retort_shockwave" and hit.amount == 36), "Retort collateral resolves its own First Strike condition once")
	_check(player.storm_crown_hit_counter == 2, "Retort Burst shares its Attack's Crown allowance per foe")
	_free_world()

	_character("bastion")
	player.apply_trial_power("razor_wind")
	var wind_target := _target(Vector2(100.0, 0.0))
	await _settle()
	player._activate_iron_retort_brace(Vector2.ZERO)
	player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "damage_coefficient": 1.0})
	var wind_hits := _source_hits(wind_target, "razor_wind")
	_check(wind_hits.size() == 1 and is_equal_approx(float(wind_hits[0].damage_coefficient), player.razor_wind_damage_ratio), "Wind-only connection spends Retort without multiplying Razor Wind damage")
	_check(not player.iron_retort_brace_ready, "Wind-only connection consumes the prepared brace")
	_free_world()

	_character("bastion")
	var blast_target := _target(Vector2(40.0, 0.0))
	await _settle()
	player._activate_iron_retort_brace(Vector2.ZERO)
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	var blast_hits := _source_hits(blast_target, "blast_drive")
	var blast_bursts := _source_hits(blast_target, "iron_retort_shockwave")
	var blast_coefficient: float = player.ARCANA_MOTION_SCRIPT.BLAST_DAMAGE_MULT_MAX * player.blast_drive_damage_scale * 1.8
	_check(blast_hits.size() == 1 and is_equal_approx(float(blast_hits[0].damage_coefficient), blast_coefficient), "Charged Blast retains Retort's 80% empowerment")
	_check(blast_bursts.size() == 1 and is_equal_approx(float(blast_bursts[0].damage_coefficient), blast_coefficient * 0.55), "Charged Blast Retort Burst carries the same scaled basis")
	_free_world()

func _test_sigil_triggers() -> void:
	for source in ["melee", "razor_wind", "blast_drive"]:
		_character("hexweaver")
		var target := _target(Vector2(40.0, 0.0))
		var collateral := _target(Vector2(60.0, 0.0))
		player.reward_storm_crown = true
		player.storm_crown_proc_every = 999
		await _settle()
		Input.action_press("dash")
		player._try_start_dash(Vector2.RIGHT)
		Input.action_release("dash")
		_check(player.sigil_burst_ready, "Normal Dash primes Sigil Burst")
		_packet(target, "returning_crescent")
		_check(player.sigil_burst_ready and _source_hits(collateral, "sigil_burst").is_empty(), "Projectile damage cannot spend Sigil Burst")
		var action := player.new_combat_action("melee")
		_packet(target, source, action)
		_packet(collateral, source, action)
		_check(not player.sigil_burst_ready and _source_hits(collateral, "sigil_burst").size() == 1, source + " accepted attack hit releases one Sigil Burst per Attack")
		_check(player.storm_crown_hit_counter == 3, "Sigil Burst and deliberate contacts share original-action Crown limits")
		_free_world()

func _test_sigil_target_conditions() -> void:
	_character("hexweaver")
	player.first_strike_bonus_damage = 16
	player.severing_edge_bonus_damage = 14
	player.sigil_burst_ready = true
	var primary := _target(Vector2(40.0, 0.0))
	var collateral := _target(Vector2(80.0, 0.0))
	primary.health_state.current_health = 4500
	await _settle()
	_packet(primary, "melee")
	_check(primary.hits[0].amount == 34, "Sigil's triggering Attack resolves Severing Edge against its low-health victim")
	_check(collateral.hits.size() == 1 and collateral.hits[0].amount == 25, "Sigil Burst uses 70% unconditioned basis and collateral's own First Strike")
	_check(is_equal_approx(float(collateral.contexts[0].damage_coefficient), 0.7), "Sigil Burst scales conditional Damage by its own coefficient")
	_free_world()

func _test_veilstep_limits() -> void:
	_character("veilstrider")
	var target := _target(Vector2(20.0, 0.0))
	_target(Vector2(30.0, 0.0))
	await _settle()
	player._apply_veilstep_rhythm_during_dash(Vector2.ZERO, Vector2(40.0, 0.0))
	player._apply_veilstep_rhythm_during_dash(Vector2.ZERO, Vector2(40.0, 0.0))
	_check(player.veilstep_rhythm_shards == 1, "Touching multiple foes and multiple frames earns one shard per Dash")
	player.veilstep_rhythm_shard_awarded_this_dash = false
	player.veilstep_rhythm_touched_enemy_ids.clear()
	player.dash_cooldown_left = 1.0
	player._apply_veilstep_rhythm_during_dash(Vector2.ZERO, Vector2(40.0, 0.0))
	_check(player.veilstep_rhythm_surge_ready and is_zero_approx(player.dash_cooldown_left), "Second touching Dash readies Surge and resets Dash cooldown")
	_check(is_equal_approx(player.veilstep_rhythm_surge_window_left, 4.0), "Surge retains its four-second use window")
	player.first_strike_bonus_damage = 16
	player.reward_storm_crown = true
	player.storm_crown_proc_every = 999
	player._dash_interaction = player.new_combat_action("dash")
	var previous := DAMAGEABLE.begin_interaction_scope(player._dash_interaction)
	player._release_veilstep_rhythm_wave(Vector2.ZERO)
	DAMAGEABLE.end_interaction_scope(previous)
	_check(target.hits.size() == 1 and target.hits[0].amount == 58, "Veilstep's 160% Damage Burst scales First Strike without an Attack")
	_check(player.attack_combo_counter == 0 and player.storm_crown_hit_counter == 2, "Veilstep deals damage and feeds Crown without Attack counting")
	_check(player.veilstep_rhythm_shards == 0 and not player.veilstep_rhythm_surge_ready, "Surge Burst spends the two shards and readiness")
	_check(target.contexts[0].interaction.seq == player._dash_interaction.seq, "Veilstep Burst retains its originating Dash identity")
	player.veilstep_rhythm_shards = 2
	player.veilstep_rhythm_surge_ready = true
	player.veilstep_rhythm_surge_window_left = 0.1
	player._update_veilstep_rhythm(0.2)
	_check(player.veilstep_rhythm_shards == 0 and not player.veilstep_rhythm_surge_ready, "Unused Surge expires with its shards")
	_free_world()

func _test_farline_scope() -> void:
	_character("riftlancer")
	player.first_strike_bonus_damage = 16
	var near_target := _target(Vector2(40.0, 0.0))
	var far_target := _target(Vector2(115.0, 0.0))
	await _settle()
	player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "damage_coefficient": 1.0})
	_check(near_target.hits[0].amount == 25 and far_target.hits[0].amount == 61, "Farline applies 70%/170% to melee damage and its conditional Damage basis")
	_packet(near_target, "returning_crescent")
	_check(near_target.hits.back().amount == 36, "Farline does not weaken generated Projectile damage outside its precision band")
	player.apply_trial_power("razor_wind")
	var wind_target := _target(Vector2(170.0, 0.0))
	player._apply_razor_wind(Vector2.RIGHT, {"damage": 20, "damage_coefficient": 1.0, "range": 200.0, "arc_degrees": 130.0})
	_check(wind_target.hits.size() == 1 and wind_target.hits[0].amount == 36, "Farline does not alter Razor Wind outside the main Attack")
	player.attack_range = 264.0
	_check(player._get_farline_focus_range_band().is_equal_approx(Vector2(196.0, 264.0)), "Long Reach keeps Farline's precision band proportional to Attack range")
	_free_world()
