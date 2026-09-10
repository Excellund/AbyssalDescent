extends "res://scripts/tests/test_character_passive_runtime.gd"
## Cross Stitch reacts once to the first accepted contact of each deliberate
## Attack, retaining the new target while its previous target releases damage.

class ThreadAlly extends ComboPlayer:
	func _is_local_control_owner() -> bool:
		return true

func _run() -> void:
	_check(INTERACTIONS.effect_forms("cross_stitch_burst") == ["Burst"], "Cross Stitch damage exposes its Burst form")
	_check(not INTERACTIONS.is_attack_hit("cross_stitch_burst"), "Cross Stitch Burst cannot become another Attack hit")
	await _test_thread_melee_sequence()
	await _test_thread_attack_sources()
	await _test_thread_original_action()
	await _test_thread_target_scaling()
	await _test_thread_lethal_contact()
	await _test_thread_invalidation()
	await _test_thread_reset_and_restore()
	await _test_thread_ownership()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[ThreadbinderRuntime] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _thread_target(owner_player: ComboPlayer = null) -> Node2D:
	if owner_player == null:
		owner_player = player
	var reference: Variant = owner_player.cross_stitch_target
	return reference.get_ref() as Node2D if reference is WeakRef else null

func _thread_mark(target: Node2D, owner_id: int = 1) -> Dictionary:
	var state := DAMAGEABLE._target_status(target)
	return state.marks.get("%d:cross_stitch" % owner_id, {}) if state != null else {}

func _test_thread_melee_sequence() -> void:
	_character("threadbinder")
	var right := _target(Vector2(40.0, 0.0))
	var left := _target(Vector2(-40.0, 0.0))
	await _settle()
	_check(player.passive_cross_stitch and player.active_character_id == "threadbinder", "Threadbinder package enables its own passive")
	_check(player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "damage_coefficient": 1.0}), "A real melee Attack connects")
	_check(right.hits.size() == 1 and right.hits[0].amount == 20, "First contact deals damage before applying Cross Stitch Mark")
	_check(_thread_target() == right and is_equal_approx(player.cross_stitch_window_left, 4.0), "First living contact becomes the four-second pending target")
	var mark := _thread_mark(right)
	_check(not mark.is_empty() and is_equal_approx(float(mark.ratio), 0.12) and is_equal_approx(float(mark.left), 4.0), "Cross Stitch applies its advertised 12% Mark for four seconds")
	var collateral := _target(Vector2(65.0, 35.0))
	player._perform_melee_attack(Vector2.LEFT, {"damage": 20, "damage_coefficient": 1.0})
	_check(_thread_target() == left and _source_hits(right, "cross_stitch_burst").size() == 1, "Switching melee targets releases one Burst at the previous foe")
	_check(left.hits.size() == 1 and left.hits[0].amount == 20, "The new foe's first hit does not borrow the old foe's Mark")
	_check(collateral.hits.size() == 1 and collateral.hits[0].amount == 12, "Unmarked collateral receives 60% of the triggering Attack's damage basis")
	_check(_thread_mark(collateral).is_empty(), "Burst collateral never receives a new Cross Stitch Mark")
	player._update_cross_stitch(0.5)
	DAMAGEABLE._target_status(left).advance(0.5)
	player._perform_melee_attack(Vector2.LEFT, {"damage": 20, "damage_coefficient": 1.0})
	_check(left.hits.back().amount == 22, "A later Attack benefits from the existing shared Mark")
	_check(_thread_target() == left and is_equal_approx(player.cross_stitch_window_left, 4.0) and is_equal_approx(float(_thread_mark(left).left), 4.0), "Repeating the same target refreshes both windows")
	_check(_source_hits(right, "cross_stitch_burst").size() == 1 and _source_hits(left, "cross_stitch_burst").is_empty(), "Repeating the same target does not release another Burst")
	_check(not player._perform_melee_attack(Vector2.DOWN, {"damage": 20, "damage_coefficient": 1.0}), "A deliberate Attack can miss")
	_check(_thread_target() == left and is_equal_approx(player.cross_stitch_window_left, 4.0), "A missed Attack preserves the pending target and timer")
	_free_world()

func _test_thread_attack_sources() -> void:
	for source in ["melee", "razor_wind", "blast_drive"]:
		_character("threadbinder")
		var previous := _target(Vector2(-40.0, 0.0))
		var blocked := BlockedPassiveEnemy.new()
		_add_circle(blocked, 13.0)
		world.add_child(blocked)
		blocked.position = Vector2(130.0 if source == "razor_wind" else 40.0, 0.0)
		if source == "razor_wind":
			player.apply_trial_power("razor_wind")
		await _settle()
		_packet(previous, "melee")
		var context := {"damage": 20, "damage_coefficient": 1.0, "source": "blast_drive" if source == "blast_drive" else "melee"}
		_check(not player._perform_melee_attack(Vector2.RIGHT, context), source + " rejected damage does not connect")
		_check(_thread_target() == previous and _thread_mark(blocked).is_empty() and _source_hits(previous, "cross_stitch_burst").is_empty(), source + " rejection cannot change the thread or release its Burst")
		blocked.blocked = false
		_check(player._perform_melee_attack(Vector2.RIGHT, context), source + " accepted damage connects")
		_check(_source_hits(blocked, source).size() == 1, source + " fixture connects through its actual native damage source")
		_check(_thread_target() == blocked and not _thread_mark(blocked).is_empty() and _source_hits(previous, "cross_stitch_burst").size() == 1, source + " accepted Attack switches the thread exactly once")
		_free_world()
	_character("threadbinder")
	var pending := _target(Vector2(-40.0, 0.0))
	var automatic := _target(Vector2(40.0, 0.0))
	await _settle()
	_packet(pending, "melee")
	for source in ["returning_crescent", "static_wake", "razor_orbit", "sovereigns_double", "cross_stitch_burst"]:
		_packet(automatic, source)
		_check(_thread_target() == pending and _thread_mark(automatic).is_empty() and _source_hits(pending, "cross_stitch_burst").is_empty(), source + " damage cannot switch or consume the pending thread")
	_free_world()

func _test_thread_original_action() -> void:
	_character("threadbinder")
	player.reward_storm_crown = true
	player.storm_crown_proc_every = 999
	var first := _target(Vector2(30.0, 0.0))
	var second := _target(Vector2(40.0, 0.0))
	await _settle()
	var cleave := player.new_combat_action("melee")
	_packet(first, "melee", cleave)
	_packet(second, "razor_wind", cleave)
	_check(_thread_target() == first and _thread_mark(second).is_empty(), "A cleave plus Razor Wind threads only its first accepted foe")
	_check(_source_hits(first, "cross_stitch_burst").is_empty(), "Later contacts in one original Attack cannot switch the thread")
	var switch_action := player.new_combat_action("blast_drive")
	_packet(second, "blast_drive", switch_action)
	_packet(first, "razor_wind", switch_action)
	var bursts := _source_hits(first, "cross_stitch_burst")
	_check(_thread_target() == second and bursts.size() == 1 and _source_hits(second, "cross_stitch_burst").size() == 1, "Switching cleave releases one Burst and keeps the first new target through descendant damage")
	_check(not bursts.is_empty() and bursts[0].interaction.seq == switch_action.seq and bursts[0].interaction.owner == 1, "Burst carries the triggering Attack's original identity and owner")
	_check(player.storm_crown_hit_counter == 4, "Burst and deliberate contacts share one Crown contribution per foe per original Attack")
	_check(player.attack_combo_counter == 0, "Accepted packets and their Burst cannot invent Attack-control inputs")
	_free_world()

func _test_thread_target_scaling() -> void:
	_character("threadbinder")
	player.first_strike_bonus_damage = 16
	player.severing_edge_bonus_damage = 14
	var previous := _target(Vector2(40.0, 0.0))
	var low_trigger := _target(Vector2(-40.0, 0.0))
	var healthy_collateral := _target(Vector2(40.0, 40.0))
	var low_collateral := _target(Vector2(40.0, -40.0))
	var outside := _target(Vector2(40.0, 49.0))
	low_trigger.health_state.current_health = 4500
	low_collateral.health_state.current_health = 4500
	await _settle()
	_packet(previous, "melee")
	var empowered := player.new_combat_action("melee")
	DAMAGEABLE.apply_damage(low_trigger, 40, INTERACTIONS.damage_context(empowered, "melee", {"raw_amount": 40.0, "damage_coefficient": 2.0}), 1)
	_check(low_trigger.hits[0].amount == 68, "The triggering Attack resolves its own doubled Severing Edge coefficient")
	var bursts := _source_hits(healthy_collateral, "cross_stitch_burst")
	_check(bursts.size() == 1 and is_equal_approx(float(bursts[0].raw_amount), 24.0) and is_equal_approx(float(bursts[0].damage_coefficient), 1.2), "Burst copies 60% of unconditioned damage and its effective Damage coefficient")
	_check(healthy_collateral.hits.size() == 1 and healthy_collateral.hits[0].amount == 43, "Healthy collateral resolves its own First Strike once instead of inheriting the trigger's Severing Edge")
	_check(low_collateral.hits.size() == 1 and low_collateral.hits[0].amount == 41, "Low-health collateral independently resolves its own Severing Edge once")
	_check(outside.hits.is_empty(), "Cross Stitch Burst remains within its 48-unit radius")
	_check(_thread_mark(healthy_collateral).is_empty() and _thread_mark(low_collateral).is_empty(), "Conditional Burst damage does not create more Marks")
	_free_world()

func _test_thread_lethal_contact() -> void:
	for has_previous in [false, true]:
		_character("threadbinder")
		var previous := _target(Vector2(40.0, 0.0))
		var lethal := _target(Vector2(-40.0, 0.0))
		var later_contact := _target(Vector2(-50.0, 0.0))
		lethal.health_state.current_health = 1
		await _settle()
		if has_previous:
			_packet(previous, "melee")
		var action := player.new_combat_action("melee")
		_packet(lethal, "melee", action)
		_packet(later_contact, "razor_wind", action)
		_check(lethal.get_current_health() == 0 and _thread_target() == null and is_zero_approx(player.cross_stitch_window_left), "A lethal first contact leaves no pending dead target")
		_check(_thread_mark(lethal).is_empty() and _thread_mark(later_contact).is_empty(), "Lethal first contact consumes the original Attack allowance before later living cleave contacts")
		_check(_source_hits(previous, "cross_stitch_burst").size() == (1 if has_previous else 0), "A lethal switch releases the previous living thread exactly once when one exists")
		_packet(later_contact, "melee")
		_check(_thread_target() == later_contact, "A later distinct Attack can start a fresh living thread after a kill")
		_free_world()

func _test_thread_invalidation() -> void:
	for reason in ["expired", "dead", "distant", "freed"]:
		_character("threadbinder")
		var previous := _target(Vector2(40.0, 0.0))
		var next := _target(Vector2(-40.0, 0.0))
		var collateral := _target(Vector2(40.0, 35.0))
		await _settle()
		_packet(previous, "melee")
		match reason:
			"expired": player._update_cross_stitch(4.01)
			"dead": previous.health_state.current_health = 0
			"distant":
				previous.position = Vector2(241.0, 0.0)
				collateral.position = Vector2(241.0, 35.0)
			"freed": previous.free()
		_packet(next, "melee")
		_check(collateral.hits.is_empty(), reason + " previous target cannot release a Burst")
		_check(_thread_target() == next and is_equal_approx(player.cross_stitch_window_left, 4.0), reason + " previous target does not prevent a new living thread")
		_free_world()

func _test_thread_reset_and_restore() -> void:
	_character("threadbinder")
	var target := _target(Vector2(40.0, 0.0))
	await _settle()
	var old_action := player.new_combat_action("melee")
	_packet(target, "melee", old_action)
	player.clear_lingering_combat_effects()
	_check(_thread_target() == null and is_zero_approx(player.cross_stitch_window_left) and _thread_mark(target).is_empty(), "Room cleanup removes the pending thread and its owner's Mark")
	_packet(target, "melee", old_action)
	_check(_thread_target() == null and _thread_mark(target).is_empty(), "A retired room action cannot restore the cleared thread")
	_packet(target, "melee")
	player.apply_trial_power("static_wake")
	var snapshot := player.build_run_snapshot()
	player.apply_run_snapshot(snapshot)
	_check(player.passive_cross_stitch and player.active_character_id == "threadbinder" and player.reward_static_wake, "Run restore retains Threadbinder and its ordinarily learned power")
	_check(_thread_target() == null and is_zero_approx(player.cross_stitch_window_left) and _thread_mark(target).is_empty(), "Run restore discards temporary thread and Mark windows")
	_packet(target, "melee")
	player.apply_character_package(player.CHARACTER_REGISTRY.get_character("bastion"))
	_check(not player.passive_cross_stitch and _thread_target() == null and is_zero_approx(player.cross_stitch_window_left), "Changing character package disables Cross Stitch and discards its pending target")
	_free_world()

func _test_thread_ownership() -> void:
	_character("threadbinder")
	var teammate := ThreadAlly.new()
	_add_circle(teammate, 14.0)
	world.add_child(teammate)
	teammate.player_id = 2
	teammate.apply_character_package(teammate.CHARACTER_REGISTRY.get_character("threadbinder"))
	teammate.arcana_motion.set_process(false)
	teammate.boss_combinations.set_process(false)
	var shared := _target(Vector2(40.0, 0.0))
	var other := _target(Vector2(-40.0, 0.0))
	await _settle()
	_packet(shared, "melee")
	var ally_action := teammate.new_combat_action("melee")
	DAMAGEABLE.apply_damage(shared, 20, INTERACTIONS.damage_context(ally_action, "melee", {"raw_amount": 20.0, "damage_coefficient": 1.0}), 2)
	_check(_thread_target() == shared and _thread_target(teammate) == shared, "Each player independently retains its own pending target")
	_check(not _thread_mark(shared, 1).is_empty() and not _thread_mark(shared, 2).is_empty() and is_equal_approx(float(DAMAGEABLE.status_snapshot(shared, 2).mark_ratio), 0.12), "Two owners' Cross Stitch Marks share the strongest 12% window without stacking")
	_check(shared.hits.size() == 2 and shared.hits[1].amount == 22, "A teammate benefits from the existing shared Mark")
	var mirror := DAMAGEABLE.TARGET_STATUS.new()
	world.add_child(mirror)
	_check(mirror.apply_network_packet(DAMAGEABLE.get_status_network_packet(shared)) and is_equal_approx(float(mirror.snapshot(2).mark_ratio), 0.12), "Cross Stitch Mark survives the native multiplayer status packet encoding")
	mirror.free()
	_packet(other, "melee")
	_check(_thread_target() == other and _thread_target(teammate) == shared, "One player's target switch cannot move the teammate's thread")
	player.set_alive(false)
	_check(_thread_target() == null and _thread_target(teammate) == shared and _thread_mark(shared, 1).is_empty() and not _thread_mark(shared, 2).is_empty(), "Owner death clears only that player's thread and Mark windows")
	if is_instance_valid(teammate.upgrade_system.power_registry):
		teammate.upgrade_system.power_registry.free()
	teammate.free()
	_free_world()
