extends "res://scripts/tests/test_boss_combinations.gd"
## Native combat contracts: these use real learned powers and accepted damage,
## rather than calling the reaction handlers directly.
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")

func _learn(id: String, level: int) -> void:
	for pick in range(level):
		player.apply_trial_power(id)

func _packet(target: Node2D, source: String, raw: float = 20.0, coefficient: float = 1.0, action: Dictionary = {}) -> void:
	var root := action if not action.is_empty() else player.new_combat_action(source)
	DAMAGEABLE.apply_damage(target, int(raw), INTERACTIONS.damage_context(root, source, {"raw_amount": raw, "damage_coefficient": coefficient, "attack_origin": player.global_position}), 1)

func _run() -> void:
	await _test_prepared_targets()
	await _test_attack_contacts()
	await _test_contact_geometry()
	await _test_movement_payoffs()
	await _test_movement_origin()
	await _test_owned_field_bonus()
	await _test_echo_conditions()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[ConnectedBuildRuntime] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_prepared_targets() -> void:
	for level in [1, 2, 3, 4]:
		_make_world()
		_learn("wraithstep", level)
		_learn("dread_resonance", level)
		var primary := _enemy(Vector2(40, 0))
		var nearby := _enemy(Vector2(75, 0))
		player._apply_wraithstep_marks_during_dash(Vector2.ZERO, primary.position)
		var mark: float = 0.30 if level == 4 else 0.10 + 0.05 * level
		_check(is_equal_approx(DAMAGEABLE.status_snapshot(primary, 1).mark_ratio, mark), "Wraith L%d supplies its mapped shared Mark" % level)
		var action := player.new_combat_action("melee")
		_packet(primary, "melee", 100, 5, action)
		_check(primary.hits[0].amount == int(round(100 * (1 + mark))), "New Dread stacks cannot amplify their own applying hit")
		_check(DAMAGEABLE.status_snapshot(primary, 1).dread_stacks == 1, "Attack adds one Dread stack at L%d" % level)
		var reaction_hits := nearby.hits.size()
		_packet(primary, "razor_wind", 20, 1, action)
		_check(DAMAGEABLE.status_snapshot(primary, 1).dread_stacks == 1 and nearby.hits.size() == reaction_hits, "Overlapping deliberate shapes share Dread and Wraith allowances")
		_check((reaction_hits > 0) == (level >= 2), "Wraith Burst begins at L2 and never consumes Mark")
		var before := primary.get_current_health()
		_packet(primary, "returning_crescent", 100, 5)
		_check(before - primary.get_current_health() == int(round(100 * (1 + mark + (.024 if level == 4 else .02)))), "Projectile benefits from prepared Mark plus owner Dread")
		var other := _enemy(Vector2(500, 0))
		_packet(other, "melee")
		player.notify_enemy_killed(Vector2(900, 0))
		_check(DAMAGEABLE.status_snapshot(primary, 1).dread_stacks == 1, "Switching targets and collateral kills preserve Dread")
		await _settle()
		_free_world()
	for level in [1, 2, 3, 4]:
		_make_world()
		_learn("hunters_snare", level)
		var target := _enemy(Vector2(40, 0))
		_packet(target, "melee", 100, 5)
		_check(target.hits[0].amount == 100 and target.is_slowed(), "Snare first connection applies Slow after damage")
		var before := target.get_current_health()
		_packet(target, "returning_crescent", 100, 5)
		var expected: int = [100, 125, 130, 145][level - 1]
		_check(before - target.get_current_health() == expected, "Snare L%d admits the intended attack/all-damage scope" % level)
		await _settle()
		_free_world()

func _test_attack_contacts() -> void:
	_make_world()
	_learn("sigil_chain", 1)
	_learn("riftpunch", 1)
	player.apply_upgrade("wardens_verdict")
	var targets: Array[ComboEnemy] = []
	for index in range(5):
		targets.append(_enemy(Vector2(180 + index * 20, 0)))
	player._riftpunch_window_left = player.riftpunch_window_duration
	var action := player.new_combat_action("melee")
	for index in range(4):
		_packet(targets[index], "razor_wind", 20, 1, action)
	_check(is_zero_approx(player._riftpunch_window_left), "Wind-only contact spends the Dash-prepared Riftpunch")
	_check(player.apex_predator_combo_hits == 4, "Warden counts separate foes in one Attack")
	_check(player._sigil_chain_drop_armed and player._sigil_chain_zones.is_empty(), "Four contacts arm Sigil for a later Attack")
	_packet(targets[4], "razor_wind", 20, 1, action)
	_check(player._sigil_chain_zones.is_empty(), "Extra geometry in the arming Attack cannot place the next Sigil")
	_packet(targets[4], "razor_wind")
	_check(player._sigil_chain_zones.size() == 1, "A new Wind-only Attack places the prepared Sigil")
	var count := player.apex_predator_combo_hits
	player._apply_farline_volley_dash_burst(20)
	_check(player.apex_predator_combo_hits == count, "Farline Burst cannot replay attack-hit counting")
	await _settle()
	_free_world()

func _test_movement_payoffs() -> void:
	for kind in ["dash", "recoil", "orbit"]:
		_make_world()
		player.apply_upgrade("sovereign_tempo")
		var target := _enemy(Vector2(40, 0))
		_packet(target, "melee")
		_check(player.apex_momentum_stacks == 1, "Connected Attack prepares Tempo")
		player.dash_cooldown_left = 1.0
		var action := player.new_combat_action(kind)
		player._accept_shared_movement(kind, Vector2.ZERO, action)
		_check(player.apex_momentum_stacks == 0 and player.dash_cooldown_left < 1.0, "%s completion spends Tempo and refunds after accepted Burst damage" % kind)
		var after := target.get_current_health()
		var cooldown := player.dash_cooldown_left
		player._accept_shared_movement(kind, Vector2.ZERO, action)
		_check(target.get_current_health() == after and is_equal_approx(cooldown, player.dash_cooldown_left), "Duplicate movement completion cannot repeat Burst/refund")
		await _settle()
		_free_world()

func _test_contact_geometry() -> void:
	_make_world()
	_learn("farline_volley", 1)
	_learn("blast_drive", 1)
	var target := _enemy(Vector2(70, 0))
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	_check(player._farline_volley_current_stacks == 0, "A close Blast contact cannot use the shorter melee reach to charge Farline")
	target.position = Vector2(150, 0)
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	_check(player._farline_volley_current_stacks == 1, "A contact near the actual Blast reach charges Farline")
	await _settle()
	_free_world()
	_make_world()
	_learn("sigil_chain", 1)
	var large_target := _enemy(Vector2(110, 0))
	var shape := large_target.get_child(0) as CollisionShape2D
	(shape.shape as CircleShape2D).radius = 45.0
	player._sigil_chain_drop_armed = true
	await _settle()
	var contacts := player._get_damageable_enemies_in_cone(Vector2.ZERO, Vector2.RIGHT, player.attack_range, deg_to_rad(player.attack_arc_degrees * .5))
	_check(not contacts.is_empty() and large_target.position.length() > player.attack_range, "Large target fixture connects at its edge beyond center-based reach")
	player._perform_melee_attack(Vector2.RIGHT, {"damage": 20})
	_check(player._sigil_chain_zones.size() == 1, "An edge contact places the prepared Sigil")
	if player._sigil_chain_zones.size() == 1 and not contacts.is_empty():
		_check((player._sigil_chain_zones[0].pos as Vector2).is_equal_approx(contacts[0].hit_position), "Host reaction uses the accepted contact point instead of the foe's distant center")
	await _settle()
	_free_world()

func _test_owned_field_bonus() -> void:
	for source in ["static_wake", "sigil_chain", "lacuna_echo", "null_corridor", "pillar_convergence"]:
		_make_world()
		player.apply_upgrade("lacuna_echo")
		var target := _enemy(Vector2(20, 0))
		match source:
			"static_wake":
				_learn(source, 1)
				player.static_wake_controller.begin_dash(player.new_combat_action("dash"))
				player.static_wake_controller.append_segment(Vector2.ZERO, Vector2(40, 0))
				player.static_wake_controller.end_dash()
			"sigil_chain":
				_learn(source, 1)
				player._drop_sigil_chain_zone(Vector2.ZERO)
			"lacuna_echo": player._apply_void_echo(Vector2.ZERO)
			"null_corridor":
				player.apply_upgrade(source)
				player._apply_null_corridor_segment(Vector2.ZERO, Vector2(50, 0))
			"pillar_convergence":
				player.apply_upgrade(source)
				player.convergence_surge_hit_counter = 99
				player._try_apply_convergence_surge(Vector2.ZERO, 20, target.get_instance_id())
		_check(player._shared_owned_field_contains(target), source + " registers actual native gameplay footprint")
		var before := target.get_current_health()
		_packet(target, "returning_crescent", 100, 5)
		var expected := int(round(100 * (1.14 + player.void_echo_damage * .0015)))
		_check(before - target.get_current_health() == expected, source + " enables Lacuna on another damage source")
		target.position = Vector2(900, 900)
		before = target.get_current_health()
		_packet(target, "returning_crescent", 100, 5)
		_check(before - target.get_current_health() == 100, "Outside actual Field geometry grants no Lacuna bonus")
		await _settle()
		_free_world()

func _test_movement_origin() -> void:
	for kind in ["recoil", "orbit"]:
		_make_world()
		player.apply_upgrade("sovereign_tempo")
		var anchor := _enemy(Vector2(45, 0))
		if kind == "recoil":
			_learn("blast_drive", 1)
			_learn("storm_crown", 3)
			player.arcana_motion._refresh_capacity()
			player.arcana_motion.release_blast(1.0)
		else:
			_learn("razor_orbit", 1)
			_packet(anchor, "melee")
			_learn("storm_crown", 3)
			player._dash_interaction = player.new_combat_action("dash")
			player.arcana_motion.start_orbit(anchor)
			player.arcana_motion._apply_cut_contacts(player.position, anchor.position)
		var counter := player.storm_crown_hit_counter
		var sequence := player.combat_interactions._next_sequence
		_check(counter == 1, "Native %s damage uses its initial Crown allowance" % kind)
		var completion_target := _enemy(Vector2(-160, 0) if kind == "recoil" else Vector2(20, 0))
		await _settle()
		if kind == "recoil":
			player.arcana_motion.process_movement(.21, Vector2.ZERO)
		else:
			player.arcana_motion.detach(false)
		_check(completion_target.hits.any(func(hit: Dictionary) -> bool: return hit.type == "apex_momentum_wave"), "Native %s completion releases the banked Tempo Burst" % kind)
		_check(player.combat_interactions._next_sequence == sequence, "Completion cannot invent a new originating action")
		_check(player.storm_crown_hit_counter == counter, "The completion Burst cannot reopen a spent Crown allowance")
		await _settle()
		_free_world()

func _test_echo_conditions() -> void:
	_make_world()
	player.apply_upgrade("sovereigns_double")
	player.apply_upgrade("first_strike")
	_learn("eclipse_mark", 3)
	var direct := _enemy(Vector2(40, 0))
	var copied := _enemy(Vector2(540, 0))
	player._apply_eclipse_mark(direct.position)
	player.boss_combinations.create_shade(Vector2(500, 0))
	player._perform_melee_attack(Vector2.RIGHT, {"damage": 20})
	_check(direct.hits[0].amount == 45, "Original strike applies its own Mark and conditional Damage basis once")
	_check(copied.hits[0].amount == 20, "Echo scales raw amount and conditional coefficient then resolves its unmarked target")
	await _settle()
	_free_world()
