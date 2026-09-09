extends "res://scripts/tests/test_boss_combinations.gd"
## Exercise synchronous nested damage, transported kill callbacks and retained
## kill benefits without changing the independent primary/secondary contract.

const TRACKER := preload("res://scripts/core/run_summary_tracker.gd")
const EVALUATOR := preload("res://scripts/progression/oaths_evaluator.gd")
const META := preload("res://scripts/meta_progress_store.gd")

class ScopeTarget extends Node:
	var health_state: Node
	var observed: Array[int] = []
	var observed_secondary: Array[bool] = []
	var contexts: Array[Dictionary] = []
	var nested: ScopeTarget
	func take_damage(_amount: int, context: Dictionary = {}) -> void:
		observed.append(DAMAGEABLE.get_kill_proc_suppression())
		observed_secondary.append(DAMAGEABLE.is_launch_suppressed())
		contexts.append(context.duplicate(true))
		if nested != null:
			DAMAGEABLE.apply_damage(nested, 1, {"kill_proc_suppression": DAMAGEABLE.KILL_PROC_SUPPRESS_ECHO_PULSE})
			observed.append(DAMAGEABLE.get_kill_proc_suppression())

func _run() -> void:
	_test_nested_damage_and_contexts()
	await _test_kill_callback_contract()
	await _test_oath_accounting()
	await _settle()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[KillProcProvenance] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_nested_damage_and_contexts() -> void:
	var target := ScopeTarget.new()
	var nested := ScopeTarget.new()
	target.nested = nested
	var context := {"attack_type": "fracture_fault_line", "kill_proc_suppression": DAMAGEABLE.KILL_PROC_SUPPRESS_FRACTURE}
	var original := context.duplicate(true)
	DAMAGEABLE.apply_damage(target, 1, context)
	_check(target.observed == [1, 1] and nested.observed == [3], "Nested damage inherits and combines narrow kill restrictions, then restores its parent")
	_check(target.observed_secondary == [false] and nested.observed_secondary == [false], "Kill provenance does not silently change primary/secondary classification")
	_check(context == original and int(nested.contexts[0].kill_proc_suppression) == 3, "Inherited restrictions are carried in a fresh damage packet without mutating caller context")
	_check(DAMAGEABLE.get_kill_proc_suppression() == 0, "The outer damage application releases the provenance scope")
	target.nested = null
	target.observed.clear()
	DAMAGEABLE.apply_damage(target, 1, {"secondary": true, "kill_proc_suppression": DAMAGEABLE.KILL_PROC_SUPPRESS_ECHO_PULSE})
	_check(target.observed == [2] and target.observed_secondary.back(), "Secondary classification remains independent alongside a narrow restriction")
	_check(not DAMAGEABLE.is_launch_suppressed() and DAMAGEABLE.get_kill_proc_suppression() == 0, "Secondary and kill-provenance scopes both release after the callback")
	for malformed in ["fracture", Vector2.ZERO, null, 4, 128]:
		target.observed.clear()
		DAMAGEABLE.apply_damage(target, 1, {"kill_proc_suppression": malformed})
		_check(target.observed == [0], "Unknown restriction values never enter the accepted mask")
	var previous := DAMAGEABLE.begin_kill_proc_scope(1)
	_check(not DAMAGEABLE.apply_damage(target, 0, {"kill_proc_suppression": 2}) and DAMAGEABLE.get_kill_proc_suppression() == 1, "Rejected damage cannot replace or leak into its caller's scope")
	DAMAGEABLE.end_kill_proc_scope(previous)
	target.free()
	nested.free()

func _test_kill_callback_contract() -> void:
	for mask in [0, DAMAGEABLE.KILL_PROC_SUPPRESS_FRACTURE, DAMAGEABLE.KILL_PROC_SUPPRESS_ECHO_PULSE]:
		_make_world()
		player.apply_trial_power("eclipse_mark")
		player.apply_trial_power("fracture_field")
		player.apply_trial_power("dread_resonance")
		player.apply_trial_power("reaper_step")
		player.apply_upgrade("lacuna_echo")
		player.apply_upgrade("edict_of_the_court")
		var target := _enemy(Vector2(210.0, 0.0))
		player._dread_resonance_target_id = target.get_instance_id()
		player._dread_resonance_target_stacks = 2
		player.dash_cooldown_left = 1.0
		await _settle()
		PlayerReplicationService.register_player(1, player)
		PlayerReplicationService._apply_enemy_killed_local(1, Vector2(200.0, 0.0), true, mask)
		_check(player.dash_cooldown_left == 0.0 and target.velocity.length() > 0.0, "Mask %d retains Reaper and Edict's existing kill benefits" % mask)
		_check(player._eclipse_marked_enemies.has(target.get_instance_id()) == (mask != 2), "Only the Lacuna-pulse restriction prevents a new Eclipse Mark")
		_check(player.void_echo_zones.size() == (0 if mask == 2 else 1), "Fracture provenance preserves Lacuna, while a Lacuna pulse cannot renew itself")
		_check(not target.hits.is_empty() if mask == 0 else target.hits.is_empty(), "Fracture is suppressed only by its own or the existing Lacuna-pulse restriction")
		_check(player._dread_resonance_target_id == (target.get_instance_id() if mask == 2 else -1), "Only Lacuna-pulse suppression preserves Dread's existing target")
		_check(DAMAGEABLE.get_kill_proc_suppression() == 0 and not DAMAGEABLE.is_launch_suppressed(), "Kill notification releases both temporary scopes")
		player.dash_cooldown_left = 1.0
		PlayerReplicationService._apply_enemy_killed_local(1, Vector2(200.0, 0.0))
		_check(player._eclipse_marked_enemies.has(target.get_instance_id()) and player.void_echo_zones.size() == 1 and player.dash_cooldown_left == 0.0, "A later unrelated kill has full ordinary benefits after a restricted callback")
		PlayerReplicationService.player_nodes.clear()
		_free_world()

func _test_oath_accounting() -> void:
	_make_world()
	var tracker := TRACKER.new()
	tracker.reset_for_run({})
	player.primary_attack_fired.connect(tracker.record_primary_attack_fired)
	for power_id in ["execution_edge", "eclipse_mark", "fracture_field", "returning_crescent", "returning_crescent"]:
		player.apply_trial_power(power_id)
	player.returning_crescent.set_physics_process(false)
	player.apply_upgrade("edict_of_the_court")
	player.apply_upgrade("sovereigns_double")
	var victim := _enemy(Vector2(200.0, 0.0))
	victim.health_state.current_health = 10
	victim.died.connect(func():
		tracker.record_enemy_kill()
		player.notify_enemy_killed(victim.global_position)
	)
	var neighbor := _enemy(Vector2(210.0, 0.0))
	await _settle()
	DAMAGEABLE.apply_damage(victim, 20, {"attack_type": "sovereigns_double", "secondary": true}, 1)
	_check(tracker.enemies_killed == 1 and tracker.primary_attacks_fired == 0, "Secondary kill rewards preserve kill evidence without inventing a primary attack")
	_check(player._eclipse_marked_enemies.has(neighbor.get_instance_id()) and neighbor.velocity.length() > 0.0, "Secondary kills retain ordinary Eclipse and Edict benefits")
	_check(EVALUATOR.evaluate_run(tracker.build_summary({"outcome": "clear"}), META._get_default_profile()).completed_oath_ids.has("closed_fist"), "Secondary-only combat does not disqualify Closed Fist")
	player.boss_combinations.create_shade(Vector2.ZERO)
	player._try_execute_attack(Vector2.RIGHT)
	_check(tracker.primary_attacks_fired == 1 and player.attack_combo_counter == 1, "Accepted melee with shade/Crescent records one primary attack and one Execution step")
	player.perform_motion_blast(Vector2.UP, 1.0)
	_check(tracker.primary_attacks_fired == 2 and player.attack_combo_counter == 2, "Charged Blast records exactly one additional primary attack and Execution step")
	player.returning_crescent.tick(1.0)
	_check(tracker.primary_attacks_fired == 2, "Delayed blade hits never advance primary-attack or Execution evidence")
	var restored := TRACKER.new()
	restored.reset_for_run({})
	restored.restore_checkpoint(tracker.build_checkpoint())
	_check(restored.primary_attacks_fired == 2 and restored.enemies_killed == 1, "Checkpoint preserves actual attack and secondary-kill accounting")
	_check(not EVALUATOR.evaluate_run(restored.build_summary({"outcome": "clear"}), META._get_default_profile()).completed_oath_ids.has("closed_fist"), "Resume cannot recover Closed Fist after deliberate attacks")
	_free_world()
