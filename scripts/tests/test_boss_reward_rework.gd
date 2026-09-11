extends "res://scripts/tests/test_shared_keyword_synergies.gd"
## Actual accepted kills and native Well/trail producers retain one root and
## prepare surviving foes without moving their committed attack geometry.
const CHARACTERS := preload("res://scripts/character_registry.gd")

class RewardEnemy extends ObservedEnemy:
	func _on_health_state_died() -> void:
		died.emit()

func _reward_enemy(position: Vector2, health: int = 10000) -> RewardEnemy:
	var target := RewardEnemy.new()
	_add_circle(target, 13.0)
	world.add_child(target)
	target.global_position = position
	target.set_max_health_and_current(health)
	target.died.connect(func(): player.notify_enemy_killed(target.global_position))
	return target

func _run() -> void:
	await _test_native_kill_sources()
	await _test_edict_prestate_and_acceptance()
	await _test_edict_root_closure()
	await _test_well_and_corridor()
	await _test_rejected_statuses()
	await _test_saved_levels_and_retirement()
	await _test_effigy_launch_direction()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[BossRewardRework] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_native_kill_sources() -> void:
	for source: String in ["melee", "static_wake", "returning_crescent", "sovereigns_double"]:
		for level in [1, 2]:
			_synergy_world()
			for pick in level: player.apply_upgrade("edict_of_the_court")
			var kill_pos := Vector2(40, 0)
			if source == "static_wake": kill_pos = Vector2(400, 0)
			if source == "returning_crescent": kill_pos = Vector2(145, 0)
			if source == "sovereigns_double": kill_pos = Vector2(340, 0)
			var victim := _reward_enemy(kill_pos, 1)
			var neighbor := _reward_enemy(kill_pos + Vector2(0, 90))
			var extended := _reward_enemy(kill_pos + Vector2(0, 140))
			var outside := _reward_enemy(kill_pos + Vector2(0, 161))
			neighbor.velocity = Vector2(12, -4)
			await _settle()
			match source:
				"melee": _strike()
				"static_wake":
					player.apply_trial_power("static_wake")
					_wake(kill_pos - Vector2(25, 0), kill_pos + Vector2(25, 0))
					player.static_wake_controller.tick(.25)
				"returning_crescent":
					player.apply_trial_power("returning_crescent")
					player.returning_crescent.try_launch(Vector2.RIGHT)
					player.returning_crescent.tick(.3)
				"sovereigns_double":
					player.apply_upgrade("sovereigns_double")
					player.boss_combinations.create_shade(Vector2(300, 0))
					_strike()
			var bursts := _hits_of(neighbor, "edict_court")
			_check(victim.is_dead() and bursts.size() == 1, "%s L%d native kill creates exactly one Edict Burst" % [source, level])
			if not bursts.is_empty():
				var ratio := .8 if level == 1 else 1.2
				_check(bursts[0].amount == int(round(player.damage * ratio)) and is_equal_approx(float(bursts[0].context.raw_amount), player.damage * ratio) and is_equal_approx(float(bursts[0].context.damage_coefficient), ratio), "Edict derives its own raw Damage basis and coefficient at the learned level")
				var root_action: Dictionary = victim.hits[0].context.interaction
				var burst_action: Dictionary = bursts[0].context.interaction
				_check(root_action.epoch == burst_action.epoch and root_action.seq == burst_action.seq and (int(burst_action.ancestry) & INTERACTIONS.EDICT_ANCESTRY) != 0, "Edict preserves the real producer's root and carries its own descendant ancestry")
			_check(neighbor.is_slowed() and is_equal_approx(neighbor.slow_speed_mult, .75) and is_equal_approx(neighbor.slow_time_left, 1.5), "Accepted surviving Edict target receives the advertised Slow")
			_check(neighbor.global_position == kill_pos + Vector2(0, 90) and neighbor.velocity == Vector2(12, -4) and not neighbor.get_launch_state().active, "Edict preserves both target position and its existing velocity")
			_check(_hits_of(outside, "edict_court").is_empty() and not outside.is_slowed(), "Edict cannot reach a target outside either learned radius")
			_check((_hits_of(extended, "edict_court").size() == 1) == (level == 2), "The second learned level extends Edict's actual radius beyond120")
			await _settle()
			_free_world()

func _test_edict_prestate_and_acceptance() -> void:
	_synergy_world()
	player.apply_upgrade("edict_of_the_court")
	player.apply_upgrade("patient_hunter")
	player.apply_upgrade("marked_prey")
	_learn("hunters_snare", 3)
	var victim := _reward_enemy(Vector2(40, 0), 1)
	var fresh := _reward_enemy(Vector2(40, 80))
	var prepared := _reward_enemy(Vector2(40, -80))
	prepared.apply_slow(3.0, .5)
	_mark(prepared)
	await _settle()
	_strike()
	var new_hit := _hits_of(fresh, "edict_court")
	var old_hit := _hits_of(prepared, "edict_court")
	_check(victim.is_dead() and new_hit.size() == 1 and new_hit[0].amount == 16, "The applying Burst cannot borrow the Slow it applies after accepted damage")
	var expected := int(round((16.0 + .8 * 24.0) * 1.15 * 1.30))
	_check(old_hit.size() == 1 and old_hit[0].amount == expected and is_equal_approx(float(old_hit[0].context.raw_amount), 16.0), "Prepared target conditions use Edict's raw coefficient once without inheriting the killing hit's amplified amount")
	_check(is_equal_approx(fresh.slow_time_left, 3.0), "Global Slow duration applies to Edict's survivor Slow")
	var forged := _reward_enemy(Vector2(600, 0))
	var action := player.new_combat_action("melee")
	_packet(forged, "edict_court", 1000, 50, action)
	_check(forged.hits.is_empty() and not forged.is_slowed(), "A submitted Edict source cannot bypass the host-only accepted-Kill producer")
	await _settle()
	_free_world()

func _test_edict_root_closure() -> void:
	_synergy_world()
	for id in ["edict_of_the_court", "shatterwake", "lacuna_echo"]: player.apply_upgrade(id)
	for id in ["spark_relay", "storm_crown", "fracture_field"]: player.apply_trial_power(id)
	player.storm_crown_proc_every = 1
	var witness := _reward_enemy(Vector2(90, 70))
	for position: Vector2 in [Vector2(40, 0), Vector2(70, 0), Vector2(100, 0)]:
		_reward_enemy(position, 1)
	await _settle()
	_strike()
	_step_relay(1.0)
	player._update_void_echo_zones(.1)
	_step_relay(1.0)
	var first_count := _hits_of(witness, "edict_court").size()
	_check(first_count == 1, "Multikill, Edict, Relay, Shatter, Crown and kill-created Field descendants close on one Edict opportunity")
	var total := witness.hits.size()
	_step_relay(3.0)
	player._update_void_echo_zones(3.0)
	_step_relay(3.0)
	_check(_hits_of(witness, "edict_court").size() == first_count and witness.hits.size() <= total + 4, "Retired reaction flights and Field expiry cannot reopen the same Edict root")
	var next := _reward_enemy(Vector2(40, 0), 1)
	_strike()
	_check(next.is_dead() and _hits_of(witness, "edict_court").size() == first_count + 1, "A fresh deliberate action receives its own new Edict opportunity")
	var uncredited := _reward_enemy(Vector2(700, 0), 1)
	var remote_witness := _reward_enemy(Vector2(700, 60))
	uncredited.take_damage(1, {"attack_type": "environment", "source": "environment"})
	_check(remote_witness.hits.is_empty(), "Environmental death without an accepted player action cannot earn Edict")
	await _settle()
	_free_world()

func _test_well_and_corridor() -> void:
	for effect: String in ["lacuna_echo", "null_corridor"]:
		for level in [1, 2]:
			_synergy_world()
			for pick in level: player.apply_upgrade(effect)
			player.apply_upgrade("patient_hunter")
			player.apply_upgrade("marked_prey")
			var target := _reward_enemy(Vector2(300, 0))
			var original := target.global_position
			target.velocity = Vector2(-7, 2)
			if effect == "lacuna_echo":
				player._apply_void_echo(target.global_position)
				player._update_void_echo_zones(.01)
				_check(target.is_slowed() and is_equal_approx(target.slow_time_left, .45) and is_equal_approx(target.slow_speed_mult, .75), "Native Well pulse applies its short survivor Slow after damage")
				var first: Dictionary = target.hits[0]
				var health := target.get_current_health()
				player._update_void_echo_zones(.1)
				_check(target.get_current_health() == health, "Well retains its existing pulse interval")
				player._update_void_echo_zones(.23)
				_check(target.hits.size() == 2 and target.hits[1].amount >= first.amount, "Later Well pulse can use the target's preexisting Slow bonus")
				player._apply_void_echo(Vector2(700, 0))
				_check(player.void_echo_zones.size() == 1 and not player._shared_owned_field_contains(target), "A newer Well replaces the old Field and its damage footprint")
			else:
				player._null_corridor_dash_origin = Vector2(270, 0)
				player._apply_null_corridor_segment(Vector2(270, 0), Vector2(330, 0))
				player._update_null_corridor_segments(.01)
				var ratio := .10 if level == 1 else .15
				_check(is_equal_approx(float(DAMAGEABLE.status_snapshot(target, 1).mark_ratio), ratio), "Native trail applies the mapped timed Mark after accepted damage")
				var first: Dictionary = target.hits[0]
				var health := target.get_current_health()
				player._update_null_corridor_segments(.1)
				_check(target.get_current_health() == health, "Trail keeps its per-target half-second interval")
				player._update_null_corridor_segments(.41)
				_check(target.hits.size() == 2 and target.hits[1].amount > first.amount, "Later trail tick uses preexisting Mark and conditional Damage while applying tick does not")
				_mark(target)
				_check(is_equal_approx(float(DAMAGEABLE.status_snapshot(target, 1).mark_ratio), .15), "Corridor and an independently owned timed Mark use the strongest ratio, never additive stacking")
				DAMAGEABLE._target_status(target).advance(1.01)
				_check(not DAMAGEABLE._target_status(target).marks.has("1:null_corridor"), "Trail's own one-second Mark expires independently of another source")
			_check(target.global_position == original and target.velocity == Vector2(-7, 2) and not target.get_launch_state().active, "Passive reward damage preserves a foe's position, velocity and warning movement")
			await _settle()
			_free_world()

func _test_rejected_statuses() -> void:
	for effect: String in ["edict_of_the_court", "lacuna_echo", "null_corridor"]:
		_synergy_world()
		player.apply_upgrade(effect)
		var blocked := _reward_enemy(Vector2(300, 15))
		var lethal := _reward_enemy(Vector2(300, -15), 1)
		blocked.blocked = true
		if effect == "edict_of_the_court":
			var victim := _reward_enemy(Vector2(300, 0), 1)
			_packet(victim, "returning_crescent")
		elif effect == "lacuna_echo":
			player._apply_void_echo(Vector2(300, 0))
			player._update_void_echo_zones(.01)
		else:
			player._null_corridor_dash_origin = Vector2(260, 0)
			player._apply_null_corridor_segment(Vector2(260, 0), Vector2(340, 0))
			player._update_null_corridor_segments(.01)
		_check(blocked.hits.is_empty() and not blocked.is_slowed() and DAMAGEABLE.status_snapshot(blocked, 1).mark_ratio == 0.0, effect + ": blocked damage cannot apply Slow or Mark")
		_check(lethal.is_dead() and not lethal.is_slowed() and DAMAGEABLE.status_snapshot(lethal, 1).mark_ratio == 0.0, effect + ": lethal damage cannot leave a survivor status")
		await _settle()
		_free_world()

func _test_saved_levels_and_retirement() -> void:
	_synergy_world()
	for id in ["edict_of_the_court", "lacuna_echo", "null_corridor"]:
		player.apply_upgrade(id)
		player.apply_upgrade(id)
	var saved := player.build_run_snapshot()
	player.apply_run_snapshot(bytes_to_var(var_to_bytes(saved)))
	_check(player.get_upgrade_stack_count("edict_of_the_court") == 2 and player.get_upgrade_stack_count("lacuna_echo") == 2 and player.get_upgrade_stack_count("null_corridor") == 2, "Existing saved reward IDs and levels restore without new required properties")
	var target := _reward_enemy(Vector2(300, 0))
	player._null_corridor_dash_origin = Vector2(270, 0)
	player._apply_null_corridor_segment(Vector2(270, 0), Vector2(330, 0))
	player._update_null_corridor_segments(.01)
	player._apply_void_echo(target.global_position)
	var before := target.get_current_health()
	player.encounter_input_frozen = true
	player.discard_pending_combat_input()
	player._update_null_corridor_segments(1.0)
	player._update_void_echo_zones(1.0)
	_check(target.get_current_health() == before, "Modal action cancellation rejects delayed damage from both retired Field roots")
	var phases := preload("res://scripts/core/combat_phase_coordinator.gd").new()
	phases.end_combat_phase(player, self)
	_check(player.null_corridor_segments.is_empty() and player.void_echo_zones.is_empty(), "Ending the combat phase clears both Field visuals and damage lifetimes")
	await _settle()
	_free_world()

func _test_effigy_launch_direction() -> void:
	_synergy_world()
	player.apply_character_package(CHARACTERS.get_character("threadbinder"))
	player.apply_upgrade("ruinous_impact")
	_strike()
	var anchor: Vector2 = player.effigy_position
	player.global_position = anchor + Vector2(150, 0)
	var target := _reward_enemy(anchor + Vector2(40, 0))
	await _settle()
	_strike()
	_check(target.get_launch_state().active and target.get_launch_state().launch_velocity.x > 0.0, "Effigy Attack launches from the authenticated effigy strike origin even when the real body stands on the other side")
	await _settle()
	_free_world()
