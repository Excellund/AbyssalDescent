extends "res://scripts/tests/test_boss_combinations.gd"
## Exercise native producers, not synthetic keyword labels, against Crown.
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")

class HitEnemy extends ComboEnemy:
	var contexts: Array[Dictionary] = []
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		var before := get_current_health()
		super.take_damage(amount, context)
		if get_current_health() < before:
			contexts.append(context.duplicate(true))

func _target(position: Vector2) -> HitEnemy:
	var target := HitEnemy.new()
	_add_circle(target, 13.0)
	world.add_child(target)
	target.position = position
	return target

func _run() -> void:
	for source in INTERACTIONS.EFFECT_TRAITS:
		if source in ["storm_crown", "sovereigns_double"]:
			continue
		await _test_producer(source)
	await _test_slow_producers()
	await _test_double_allowance()
	await _test_snapshot_and_dash_only()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[SharedBuildProducers] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_producer(source: String) -> void:
	_make_world()
	player.reward_storm_crown = true
	player.storm_crown_proc_every = 999
	var target := _target(Vector2(20.0, 0.0))
	await _settle()
	match source:
		"melee": player._perform_melee_attack(Vector2.RIGHT, {"damage": 20})
		"razor_wind":
			target.position.x = 100.0
			player._apply_razor_wind(Vector2.RIGHT, {"damage": 20, "range": 150.0, "arc_degrees": 130.0})
		"blast_drive": player.perform_motion_blast(Vector2.RIGHT, 1.0)
		"farline_volley_burst": player._apply_farline_volley_dash_burst(20)
		"riftpunch_shockwave": player._apply_riftpunch_shockwave(Vector2.ZERO, 20, null)
		"rupture_wave": player._apply_rupture_wave(Vector2.ZERO, 20)
		"wraithstep_chain":
			player.wraithstep_marked_enemy_expiry[target.get_instance_id()] = {"node": target}
			player._apply_wraithstep_chain(Vector2.ZERO, -1, 20)
		"wraithstep_splash": player._apply_wraithstep_splash(Vector2.ZERO, 20, -1)
		"phantom_step": player._apply_phantom_step_during_dash()
		"static_wake":
			player.apply_trial_power("static_wake")
			player.static_wake_controller.begin_dash(player.new_combat_action("dash"))
			player.static_wake_controller.append_segment(Vector2.ZERO, Vector2(20.0, 0.0))
			player.static_wake_controller.end_dash()
			player.static_wake_controller.tick(0.5)
		"veilstep_rhythm_wave": player._release_veilstep_rhythm_wave(Vector2.ZERO)
		"overcharge_discharge": player._fire_overcharge_discharge(Vector2.ZERO)
		"iron_retort_shockwave": player._apply_iron_retort_shockwave(Vector2.ZERO, 20)
		"voidfire_detonate": player._trigger_voidfire_detonation()
		"sigil_chain_zone":
			player._drop_sigil_chain_zone(Vector2.ZERO)
			player._update_sigil_chain_state(0.1)
			player._update_sigil_chain_state(0.5)
		"apex_predator_burst": player._trigger_apex_predator_burst(Vector2.ZERO, -1, 20)
		"apex_momentum_wave":
			player.apply_upgrade("sovereign_tempo")
			player.apex_momentum_stacks = 1
			player._release_apex_momentum_dash_wave(Vector2.ZERO)
		"void_echo_zone":
			player.void_echo_damage = 20
			player._apply_void_echo(Vector2.ZERO)
			player._update_void_echo_zones(0.1)
			player._update_void_echo_zones(0.4)
		"convergence_window":
			player.convergence_surge_damage_ratio = 0.2
			player.convergence_surge_hit_counter = 99
			player._try_apply_convergence_surge(Vector2.ZERO, 20, target.get_instance_id())
			player._update_convergence_window(0.1)
			player._update_convergence_window(0.4)
		"null_corridor_deflect":
			player.null_corridor_strength = 0.2
			player._apply_null_corridor_segment(Vector2(-40.0, 0.0), Vector2(60.0, 0.0))
			player._update_null_corridor_segments(0.1)
			player._update_null_corridor_segments(0.6)
		"fracture_fault_line":
			target.position = Vector2.ZERO
			player._apply_fracture_field(Vector2.ZERO)
		"sigil_burst": player._apply_sigil_burst(Vector2.ZERO, 20)
		"sigil_chain_detonate":
			player.apply_trial_power("sigil_chain")
			player._drop_sigil_chain_zone(Vector2.ZERO)
			player._detonate_sigil_chain_zones_in_burst(Vector2.ZERO, 90.0)
		"returning_crescent":
			target.position.x = 140.0
			player.apply_trial_power("returning_crescent")
			player.returning_crescent.set_physics_process(false)
			player.returning_crescent.try_launch(Vector2.RIGHT)
			player.returning_crescent.tick(0.3)
			player.returning_crescent.tick(0.6)
		"razor_orbit":
			player.apply_trial_power("razor_orbit")
			player.arcana_motion.start_orbit(target)
			player.arcana_motion._apply_cut_contacts(Vector2.ZERO, Vector2(20.0, 0.0))
		"ruinous_impact":
			player.apply_upgrade("ruinous_impact")
			player.boss_combinations.launch_enemy(target, Vector2.RIGHT * 300.0, 1)
			target.get_launch_state()._impact(target.global_position)
	var native_hits := target.contexts.filter(func(context: Dictionary) -> bool: return context.get("attack_type") == source)
	_check(not native_hits.is_empty(), source + " native producer deals damage")
	_check(player.storm_crown_hit_counter == 1, source + " contributes once per action/target, including repeated ticks and return legs")
	for context in native_hits:
		var action := INTERACTIONS.validate_action(context.get("interaction"), 1)
		_check(not action.is_empty(), source + " carries valid originating action and ownership")
	_free_world()

func _test_slow_producers() -> void:
	for source in ["aegis_field", "hunters_snare", "riftpunch", "rupture_wave", "phantom_step", "static_wake", "farline_volley", "sigil_chain", "fracture_field"]:
		_make_world()
		var target := _target(Vector2.ZERO)
		for level in range(3):
			player.apply_trial_power(source)
		await _settle()
		match source:
			"aegis_field": player._trigger_aegis_field()
			"hunters_snare": player._perform_melee_attack(Vector2.RIGHT, {"damage": 20})
			"riftpunch":
				player._riftpunch_window_left = 1.0
				player._perform_melee_attack(Vector2.RIGHT, {"damage": 20})
			"rupture_wave": player._apply_rupture_wave(Vector2.ZERO, 20)
			"phantom_step": player._apply_phantom_step_during_dash()
			"static_wake":
				player.static_wake_controller.begin_dash(player.new_combat_action("dash"))
				player.static_wake_controller.append_segment(Vector2.ZERO, Vector2.RIGHT)
				player.static_wake_controller.end_dash()
				player.static_wake_controller.tick(0.25)
			"farline_volley":
				for contact in range(player.farline_volley_stack_cap):
					player._on_farline_volley_outer_hit(target)
			"sigil_chain":
				player._drop_sigil_chain_zone(Vector2.ZERO)
				player._update_sigil_chain_state(0.1)
			"fracture_field": player._apply_fracture_field(Vector2.ZERO)
		_check(target.is_slowed(), source + " applies authoritative Slow without Crown")
		player.apply_trial_power("storm_crown")
		player.apply_trial_power("storm_crown")
		player.storm_crown_hit_counter = player.storm_crown_proc_every - 1
		var recipients: Array[HitEnemy] = []
		for index in range(5):
			recipients.append(_target(Vector2(50.0 + 30.0 * index, 0.0)))
		DAMAGEABLE.apply_damage(target, 20, INTERACTIONS.damage_context(player.new_combat_action("melee"), "melee"))
		var struck := recipients.filter(func(enemy: HitEnemy) -> bool: return not enemy.contexts.is_empty())
		_check(struck.size() == 4, source + " prepares one additional Crown hop")
		_free_world()

func _test_double_allowance() -> void:
	_make_world()
	player.apply_trial_power("storm_crown")
	player.apply_trial_power("storm_crown")
	player.apply_upgrade("sovereigns_double")
	var direct := _target(Vector2(40.0, 0.0))
	var echo := _target(Vector2(540.0, 0.0))
	var chained := _target(Vector2(640.0, 0.0))
	await _settle()
	player.boss_combinations.create_shade(Vector2(500.0, 0.0))
	player._perform_melee_attack(Vector2.RIGHT, {"damage": 20})
	_check(direct.get_current_health() == 9980 and echo.get_current_health() == 9989, "Double copies resolved damage at55% exactly once")
	_check(chained.contexts.any(func(c: Dictionary) -> bool: return c.get("attack_type") == "storm_crown"), "Echo spends the original strike's remaining Crown contact")
	_check(player.storm_crown_hit_counter == 2, "Direct and echo share one discharge allowance")
	_check(player.boss_combinations.shade_hits == 0, "Echo cannot create another shade")
	_check(echo.contexts[0].interaction.get("echo_source") == "melee", "Native Double carries the copied strike descriptor to the authoritative boundary")
	_free_world()

func _test_snapshot_and_dash_only() -> void:
	for character in ["bastion", "hexweaver", "veilstrider", "riftlancer"]:
		_make_world()
		player.apply_character_package(player.CHARACTER_REGISTRY.get_character(character))
		player.apply_trial_power("static_wake")
		player.apply_trial_power("storm_crown")
		var target := _target(Vector2(30.0, 0.0))
		await _settle()
		Input.action_press("dash")
		player._try_start_dash(Vector2.RIGHT)
		player._process_active_dash(0.05)
		Input.action_release("dash")
		player.static_wake_controller.tick(0.25)
		_check(target.get_current_health() < 10000 and player.attack_combo_counter == 0, character + " deals Wake damage using normal dash with no attack input")
		var snapshot := player.build_run_snapshot()
		_check(snapshot.version == 2, "New snapshots declare interaction interpretation version")
		player.apply_run_snapshot(snapshot)
		_check(player.reward_static_wake and player.static_wake_stacks == 1, "Restore keeps ordinarily learned Wake")
		_check(player.combat_interactions._roots.is_empty(), "Restore discards temporary reaction history")
		snapshot.version = 1
		player.apply_run_snapshot(snapshot)
		_check(player.reward_static_wake and player.reward_storm_crown, "Legacy learned-power snapshot remains playable")
		_free_world()
