extends "res://scripts/tests/test_boss_reward_synergies.gd"
## Learned powers enter through real producers and the accepted-damage boundary.

class Bounds extends Node:
	var current_effective_room_size := Vector2(200, 200)

func _run() -> void:
	await _test_condition_boons()
	await _test_stormbrand_prestate()
	await _test_converter_roots()
	await _test_native_producers()
	await _test_relay_geometry()
	await _test_rejected_and_lethal_inputs()
	await _test_seeking_relay()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[SharedKeywordSynergies] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _hits_of(target: ObservedEnemy, source: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hit: Dictionary in target.hits:
		if String(hit.type) == source:
			result.append(hit)
	return result

func _step_relay(seconds: float) -> void:
	if not is_instance_valid(player.spark_relay_controller):
		return
	for _index in range(ceili(seconds * 120.0)):
		player.spark_relay_controller.tick(1.0 / 120.0)

func _mark(target: Node2D) -> void:
	if not player.reward_wraithstep:
		_learn("wraithstep", 1)
	_check(DAMAGEABLE.apply_mark(target, "wraithstep", .15, 2.5, 1, player.new_combat_action("dash")), "Real learned Wraithstep prepares an independent timed Mark")

func _test_condition_boons() -> void:
	_synergy_world()
	for id in ["patient_hunter", "marked_prey"]:
		for pick in range(3):
			_check(player.upgrade_system.apply_upgrade(id), id + ": ordinary Boon acquisition succeeds")
		_check(not player.upgrade_system.apply_upgrade(id), id + ": a fourth pick cannot exceed its three-pick cap")
	_check(player.patient_hunter_bonus_damage == 36 and player.marked_prey_bonus_damage == 36, "Both conditions retain their independently learned Damage-basis bonuses")
	var plain := _observed_enemy(Vector2(40, 0))
	_packet(plain, "returning_crescent", 10, .25)
	_check(plain.hits[0].amount == 10, "Condition Boons leave an unprepared target's damage unchanged")
	var whole := _observed_enemy(Vector2(80, 0))
	var split := _observed_enemy(Vector2(120, 0))
	for target in [whole, split]:
		target.apply_slow(5.0, .5)
		_mark(target)
	_packet(whole, "static_wake", 10, .25)
	var action := player.new_combat_action("dash")
	for _part in range(20):
		_packet(split, "static_wake", .5, .0125, action)
	_check(10000 - whole.get_current_health() == 32 and split.get_current_health() == whole.get_current_health(), "Pre-Slow and pre-Mark bonuses scale the raw coefficient once, including fractional Field ticks")
	_check(is_equal_approx(float(whole.hits[0].context.raw_amount), 10.0) and is_equal_approx(float(whole.hits[0].context.damage_coefficient), .25), "Accepted conditional damage preserves an unconditioned descriptor for descendants")
	await _settle()
	_free_world()
	_synergy_world()
	player.apply_upgrade("patient_hunter")
	player.apply_upgrade("marked_prey")
	_learn("hunters_snare", 1)
	_learn("dread_resonance", 1)
	var applying := _observed_enemy(Vector2(40, 0))
	_packet(applying, "melee", 20, 1)
	_check(applying.hits[0].amount == 20 and applying.is_slowed() and DAMAGEABLE.status_snapshot(applying, 1).mark_ratio > 0.0, "An applying Attack cannot borrow its newly created Slow or Mark")
	_packet(applying, "returning_crescent", 20, 1)
	_check(applying.hits.back().amount == int(round(44.0 * 1.12)), "A later Projectile uses both condition Boons and existing Mark/Dread without borrowing Snare L1's Attack bonus")
	await _settle()
	_free_world()

func _test_stormbrand_prestate() -> void:
	for level in range(1, 5):
		_synergy_world()
		_learn("stormbrand", level)
		player.apply_upgrade("marked_prey")
		player.apply_upgrade("patient_hunter")
		var first := _observed_enemy(Vector2(40, 0))
		var second := _observed_enemy(Vector2(80, 0))
		var action := player.new_combat_action("dash")
		_packet(first, "static_wake", 20, 1, action)
		var status := DAMAGEABLE._target_status(first)
		_check(first.hits[0].amount == 20 and not first.is_slowed(), "Stormbrand L%d applying damage uses the target's previous state" % level)
		_check(is_equal_approx(float(status.snapshot(1).mark_ratio), [0.10, 0.14, 0.18, 0.225][level - 1]), "Stormbrand L%d uses its actual mapped vulnerability" % level)
		status.advance(.25)
		var left: float = float(status.marks["1:stormbrand"].left)
		_packet(first, "static_wake", 20, 1, action)
		_check(is_equal_approx(float(status.marks["1:stormbrand"].left), left) and not first.is_slowed(), "Repeated Electric ticks cannot refresh or upgrade Stormbrand's one victim claim")
		_packet(second, "static_wake", 20, 1, action)
		_check(DAMAGEABLE.status_snapshot(second, 1).mark_ratio > 0.0, "The same root can apply Stormbrand to a different accepted foe")
		_packet(first, "static_wake", 20, 1)
		_check(first.is_slowed() == (level >= 3), "Only a fresh root on an already Marked foe adds the learned L3 Slow")
		_check(is_equal_approx(float(status.marks["1:stormbrand"].left), [3.0, 3.5, 4.0, 5.0][level - 1]), "A fresh Electric root refreshes the mapped Mark lifetime")
		status.advance(player.stormbrand_mark_duration + .01)
		_check(status.snapshot(1).mark_ratio == 0.0, "Stormbrand's timed vulnerability visibly expires")
		await _settle()
		_free_world()
	_synergy_world()
	_learn("stormbrand", 3)
	_learn("hunters_snare", 3)
	var duration_target := _observed_enemy(Vector2(80, 0))
	_packet(duration_target, "static_wake")
	_packet(duration_target, "static_wake")
	_check(is_equal_approx(duration_target.slow_time_left, 2.0) and is_equal_approx(duration_target.slow_speed_mult, .75), "Snare L3 doubles Stormbrand's actual Slow duration without changing its strength")
	await _settle()
	_free_world()

func _test_converter_roots() -> void:
	for first_source in ["rupture_wave", "returning_crescent"]:
		_synergy_world()
		_learn("spark_relay", 3)
		_learn("stormbrand", 1)
		player.apply_upgrade("shatterwake")
		var first := _observed_enemy(Vector2(110, 0))
		var nearby := _observed_enemy(Vector2(155, 0))
		await _settle()
		var action := player.new_combat_action("attack")
		_packet(first, first_source, 100, 5, action)
		_step_relay(1.0)
		_check(_hits_of(first, "spark_relay_projectile").size() == 1 and _hits_of(nearby, "spark_relay_projectile").size() == 1, first_source + ": one Relay reaches each pierced foe once")
		_check(_hits_of(first, "shatterwake_burst").size() == 1 and _hits_of(nearby, "shatterwake_burst").size() == 1, first_source + ": one Shatterwake damages its living primary and nearby foe")
		var first_count := first.hits.size()
		var other_count := nearby.hits.size()
		_packet(first, first_source, 100, 5, action)
		_step_relay(2.0)
		_check(first.hits.size() == first_count + 1 and nearby.hits.size() == other_count, first_source + ": the same root cannot reopen either converter after flight expiry")
		_packet(first, first_source, 100, 5)
		_step_relay(1.0)
		_check(_hits_of(first, "spark_relay_projectile").size() == 2 and _hits_of(first, "shatterwake_burst").size() == 2, first_source + ": a fresh root can perform both conversions again")
		await _settle()
		_free_world()

func _test_native_producers() -> void:
	for echo_only in [false, true]:
		_synergy_world()
		_learn("blast_drive", 1)
		_learn("spark_relay", 1)
		_learn("sigil_chain", 1)
		var target := _observed_enemy(Vector2(430, 0) if echo_only else Vector2(110, 0))
		if echo_only:
			player.apply_upgrade("sovereigns_double")
			player.boss_combinations.create_shade(Vector2(300, 0))
		await _settle()
		var attacks_before := player.attack_combo_counter
		player.perform_motion_blast(Vector2.RIGHT, 1.0)
		var original_source := "sovereigns_double" if echo_only else "blast_drive"
		var original_hits := _hits_of(target, original_source)
		_check(original_hits.size() == 1, "Actual %s supplies the accepted trigger" % original_source)
		_check(is_instance_valid(player.spark_relay_controller) and player.spark_relay_controller.projectiles.size() == 1, "Native accepted Burst commits one Relay before flight")
		if is_instance_valid(player.spark_relay_controller) and not player.spark_relay_controller.projectiles.is_empty():
			_check(player.spark_relay_controller.projectiles[0].position == player.global_position and player.spark_relay_controller.projectiles[0].direction.x > .99, "Relay starts at the real player body and aims toward the accepted foe, including a remote Echo")
		if not original_hits.is_empty():
			var action: Dictionary = INTERACTIONS.validate_action(original_hits[0].context.interaction, 1)
			var forms: Array = INTERACTIONS.action_forms(action)
			_check(forms.has("Burst") and forms.has("Echo") == echo_only, "Native Blast form survives an actual copied Blast while Echo stays secondary")
		_step_relay(1.0)
		_check(_hits_of(target, "spark_relay_projectile").size() == 1, "Accepted %s launches exactly one native Relay" % original_source)
		_check(player.attack_combo_counter == attacks_before + 1 and player._sigil_chain_charge == (0 if echo_only else 1), "Relay and copied Blast cannot perform another Attack or advance Sigil contacts")
		await _settle()
		_free_world()
	_synergy_world()
	_learn("returning_crescent", 1)
	player.apply_upgrade("shatterwake")
	var target := _observed_enemy(Vector2(110, 0))
	var nearby := _observed_enemy(Vector2(155, 0))
	await _settle()
	_check(player.returning_crescent.try_launch(Vector2.RIGHT), "The real learned Crescent launches")
	for _step in range(180):
		player.returning_crescent.tick(1.0 / 120.0)
	_check(_hits_of(target, "returning_crescent").size() == 2 and _hits_of(nearby, "returning_crescent").size() == 2, "Crescent preserves its separate outbound and returning hits")
	_check(_hits_of(target, "shatterwake_burst").size() == 1 and _hits_of(nearby, "shatterwake_burst").size() == 1, "Both real Crescent legs and victims share one Shatterwake root allowance")
	await _settle()
	_free_world()
	_synergy_world()
	_learn("spark_relay", 2)
	player.apply_upgrade("shatterwake")
	player.apply_upgrade("patient_hunter")
	var conditioned := _observed_enemy(Vector2(110, 0))
	var plain := _observed_enemy(Vector2(155, 0))
	conditioned.apply_slow(5.0, .5)
	await _settle()
	_packet(conditioned, "rupture_wave", 20, 1)
	_step_relay(1.0)
	var relay_hits := _hits_of(conditioned, "spark_relay_projectile")
	var shatter_hits := _hits_of(conditioned, "shatterwake_burst")
	_check(relay_hits.size() == 1 and shatter_hits.size() == 1, "The native converter chain creates one descendant at each stage")
	if not relay_hits.is_empty() and not shatter_hits.is_empty():
		_check(is_equal_approx(float(relay_hits[0].context.raw_amount), 12.0) and is_equal_approx(float(relay_hits[0].context.damage_coefficient), .6), "Relay scales original raw damage and coefficient, not the parent's conditioned damage")
		_check(is_equal_approx(float(shatter_hits[0].context.raw_amount), 7.2) and is_equal_approx(float(shatter_hits[0].context.damage_coefficient), .36), "Shatterwake carries the twice-scaled unconditioned descriptor")
		_check(relay_hits[0].amount == 19 and shatter_hits[0].amount == 12, "Each descendant resolves Patient Hunter once against its actual Slowed target")
	var plain_relay := _hits_of(plain, "spark_relay_projectile")
	var plain_shatter := _hits_of(plain, "shatterwake_burst")
	_check(plain_relay.size() == 1 and plain_shatter.size() == 1 and plain_relay[0].amount == 12 and plain_shatter[0].amount == 7, "Nearby unprepared foes never inherit the triggering foe's conditional bonus")
	await _settle()
	_free_world()

func _test_relay_geometry() -> void:
	for level in range(1, 5):
		_synergy_world()
		_learn("spark_relay", level)
		var targets: Array[ObservedEnemy] = []
		for x in [80, 140, 200, 260]:
			targets.append(_observed_enemy(Vector2(x, 0)))
		await _settle()
		_packet(targets[0], "rupture_wave", 100, 5)
		_step_relay(1.0)
		for index in range(targets.size()):
			var relay_hits := _hits_of(targets[index], "spark_relay_projectile")
			_check(relay_hits.size() == (1 if index < [1, 2, 3, 3][level - 1] else 0), "Relay L%d keeps its native accepted victim limit at target %d" % [level, index + 1])
			if not relay_hits.is_empty():
				_check(is_equal_approx(float(relay_hits[0].context.raw_amount), [50.0, 60.0, 70.0, 87.5][level - 1]), "Relay L%d native damage uses its mapped upgrade/Prismatic strength" % level)
		await _settle()
		_free_world()
	for scenario in ["column", "grazing_column", "overlapping_column", "perimeter", "ordinary_range", "prismatic_range"]:
		_synergy_world()
		_learn("spark_relay", 4 if scenario == "prismatic_range" else 1)
		var target := _observed_enemy(Vector2(480, 0) if scenario.ends_with("range") else Vector2(160, 0))
		var bounds: Bounds = null
		match scenario:
			"column": _wall(Vector2(70, 0), 20)
			"grazing_column": _wall(Vector2(70, 25), 20)
			"overlapping_column": _wall(Vector2.ZERO, 20)
			"perimeter":
				bounds = Bounds.new()
				world.add_child(bounds)
				EnemyReplicationService.bind_world(bounds)
		await _settle()
		_packet(target, "rupture_wave", 20, 1)
		if is_instance_valid(player.spark_relay_controller):
			player.spark_relay_controller.tick(2.0)
		_check(_hits_of(target, "spark_relay_projectile").size() == (1 if scenario == "prismatic_range" else 0), scenario + ": actual swept projectile obeys its body radius, terrain, room edge and learned range even during a hitch")
		_check(is_instance_valid(player.spark_relay_controller) and player.spark_relay_controller.projectiles.is_empty(), scenario + ": stopped or expired projectile leaves no damaging flight")
		if is_instance_valid(bounds):
			EnemyReplicationService.unbind_world(bounds)
		await _settle()
		_free_world()
	_synergy_world()
	player.apply_upgrade("shatterwake")
	var primary := _observed_enemy(Vector2(50, 0))
	var behind_cover := _observed_enemy(Vector2(110, 0))
	_wall(Vector2(80, 0), 10)
	await _settle()
	_packet(primary, "returning_crescent", 20, 1)
	_check(_hits_of(primary, "shatterwake_burst").size() == 1 and behind_cover.hits.is_empty(), "Native Shatterwake includes its living primary but cannot Burst through solid cover")
	await _settle()
	_free_world()

func _test_rejected_and_lethal_inputs() -> void:
	_synergy_world()
	_learn("stormbrand", 3)
	_learn("spark_relay", 1)
	player.apply_upgrade("shatterwake")
	var blocked := _observed_enemy(Vector2(110, 0))
	blocked.blocked = true
	var action := player.new_combat_action("attack")
	_packet(blocked, "static_wake", 20, 1, action)
	_packet(blocked, "rupture_wave", 20, 1, action)
	_packet(blocked, "returning_crescent", 20, 1, action)
	_check(blocked.hits.is_empty() and DAMAGEABLE.status_snapshot(blocked, 1).mark_ratio == 0.0, "Rejected damage applies neither Mark nor any converter damage")
	_check(not is_instance_valid(player.spark_relay_controller) or player.spark_relay_controller.projectiles.is_empty(), "Blocked Burst does not create a Relay")
	blocked.blocked = false
	for key in ["owner", "run", "room"]:
		var forged := action.duplicate(true)
		forged[key] = {"owner": 9, "run": "wrong-relay-run", "room": 999}[key]
		_packet(blocked, "rupture_wave", 20, 1, forged)
	_check(blocked.hits.is_empty() and (not is_instance_valid(player.spark_relay_controller) or player.spark_relay_controller.projectiles.is_empty()), "Wrong-owner, wrong-run and wrong-room Burst damage cannot acquire a living Relay target")
	await _settle()
	_packet(blocked, "rupture_wave", 20, 1, action)
	_step_relay(1.0)
	_check(_hits_of(blocked, "spark_relay_projectile").size() == 1 and _hits_of(blocked, "shatterwake_burst").size() == 1, "First accepted retry can still claim both previously blocked converters")
	await _settle()
	_free_world()
	_synergy_world()
	_learn("spark_relay", 1)
	player.apply_upgrade("shatterwake")
	var dying := _observed_enemy(Vector2(110, 0))
	var beyond := _observed_enemy(Vector2(220, 0))
	dying.health_state.current_health = 1
	await _settle()
	_packet(dying, "rupture_wave", 20, 1)
	_step_relay(1.0)
	_check(_hits_of(beyond, "spark_relay_projectile").size() == 1, "A lethal Burst seeks a living foe after the trigger dies")
	_check(_hits_of(beyond, "shatterwake_burst").size() == 1, "The surviving Projectile victim receives its one Shatterwake Burst")
	await _settle()
	_free_world()

func _test_seeking_relay() -> void:
	for scenario in ["lethal", "dies_in_flight", "moves_in_flight"]:
		_synergy_world()
		_learn("spark_relay", 1)
		var trigger := _observed_enemy(Vector2(160, 0))
		var survivor := _observed_enemy(Vector2(60, 125))
		if scenario == "lethal":
			trigger.health_state.current_health = 1
		await _settle()
		_packet(trigger, "rupture_wave", 20, 1)
		var relay := player.spark_relay_controller
		_check(relay.projectiles.size() == 1, scenario + ": accepted Burst launches exactly one seeking bolt")
		if scenario == "lethal":
			_check(relay.projectiles[0].direction.y > .5, "A lethal trigger acquires the off-axis survivor at launch instead of the corpse position")
		else:
			_check(relay.projectiles[0].target.get_ref() == trigger, "A living struck foe keeps target priority over a closer alternative")
			relay.tick(.06)
			if scenario == "dies_in_flight":
				_packet(trigger, "melee", 20000, 1)
			else:
				trigger.position = Vector2(160, -90)
		_step_relay(1.0)
		_check(_hits_of(trigger if scenario == "moves_in_flight" else survivor, "spark_relay_projectile").size() == 1, scenario + ": the actual traveling bolt reaches its living target off the original line")
		_check(relay.projectiles.is_empty(), scenario + ": level-one impact retires the same bolt")
		await _settle()
		_free_world()
	_synergy_world()
	_learn("spark_relay", 3)
	player.apply_upgrade("patient_hunter")
	var first := _observed_enemy(Vector2(80, 0))
	var second := _observed_enemy(Vector2(105, 90))
	var third := _observed_enemy(Vector2(210, 60))
	var fourth := _observed_enemy(Vector2(235, 60))
	second.apply_slow(5.0, .5)
	await _settle()
	_packet(first, "rupture_wave", 20, 1)
	_step_relay(1.0)
	_check(_hits_of(first, "spark_relay_projectile").size() == 1 and _hits_of(second, "spark_relay_projectile").size() == 1 and _hits_of(third, "spark_relay_projectile").size() == 1 and _hits_of(fourth, "spark_relay_projectile").is_empty(), "Level three redirects its single bolt through three different off-axis foes without exceeding its cap")
	var second_hits := _hits_of(second, "spark_relay_projectile")
	var third_hits := _hits_of(third, "spark_relay_projectile")
	if not second_hits.is_empty() and not third_hits.is_empty():
		_check(second_hits[0].amount == 22 and third_hits[0].amount == 14 and is_equal_approx(float(third_hits[0].context.damage_coefficient), .7), "Retargeting preserves the raw descriptor and evaluates each actual target's Slow bonus independently")
	await _settle()
	_free_world()
	_synergy_world()
	_learn("spark_relay", 1)
	var last := _observed_enemy(Vector2(80, 0))
	last.health_state.current_health = 1
	await _settle()
	var action := player.new_combat_action("attack")
	_packet(last, "rupture_wave", 20, 1, action)
	_check(player.spark_relay_controller.projectiles.is_empty() and player.combat_interactions.has_reaction(action, "spark_relay"), "A final-enemy kill spends its action allowance without emitting a pointless bolt")
	var later := _observed_enemy(Vector2(100, 70))
	_packet(later, "rupture_wave", 20, 1, action)
	_check(player.spark_relay_controller.projectiles.is_empty(), "An empty-target activation cannot bank its root allowance for later enemies")
	_packet(later, "rupture_wave", 20, 1)
	_check(player.spark_relay_controller.projectiles.size() == 1, "A fresh accepted root can seek the new living foe")
	_packet(later, "melee", 20000, 1)
	player.spark_relay_controller.tick(.01)
	_check(player.spark_relay_controller.projectiles.is_empty(), "A bolt whose final candidate dies during flight retires immediately")
	await _settle()
	_free_world()
	_synergy_world()
	_learn("spark_relay", 1)
	var dead_trigger := _observed_enemy(Vector2(60, 0))
	dead_trigger.health_state.current_health = 1
	var blocked := _observed_enemy(Vector2(120, 0))
	var reachable := _observed_enemy(Vector2(0, 180))
	_wall(Vector2(85, 0), 20)
	await _settle()
	_packet(dead_trigger, "rupture_wave", 20, 1)
	_step_relay(1.0)
	_check(_hits_of(blocked, "spark_relay_projectile").is_empty() and _hits_of(reachable, "spark_relay_projectile").size() == 1, "Acquisition skips the nearest covered foe for a reachable living foe without bending through the column")
	await _settle()
	_free_world()
	_synergy_world()
	_learn("spark_relay", 3)
	var outward := _observed_enemy(Vector2(290, 0))
	var behind := _observed_enemy(Vector2(-60, 0))
	await _settle()
	_packet(outward, "rupture_wave", 20, 1)
	_step_relay(2.0)
	_check(_hits_of(outward, "spark_relay_projectile").size() == 1 and _hits_of(behind, "spark_relay_projectile").is_empty() and player.spark_relay_controller.projectiles.is_empty(), "Acquisition spends one total travel budget; redirecting cannot reset range for a distant remaining foe")
	await _settle()
	_free_world()
