extends "res://scripts/tests/test_boss_combinations.gd"
## Native attacks plus host-side accepted roots; transport is covered by ENet.
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")

class OathPlayer extends ComboPlayer:
	var local_owner := true
	func _is_local_control_owner() -> bool:
		return local_owner

func _make_world() -> void:
	super._make_world()
	player.upgrade_system.power_registry.free()
	player.free()
	player = OathPlayer.new()
	_add_circle(player, 14.0)
	world.add_child(player)
	player.player_id = 1
	player.damage = 20
	player.attack_range = 78.0
	player.attack_arc_degrees = 130.0
	player.arcana_motion.set_process(false)
	player.boss_combinations.set_process(false)
	player.apply_upgrade("unbroken_oath")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stream = null
	for audio in world.find_children("*", "AudioStreamPlayer2D", true, false):
		(audio as AudioStreamPlayer2D).stream = null

func _prime() -> void:
	player.indomitable_damage_bank = player._get_indomitable_fill_requirement()
	player._indomitable_spirit_primed = true
	player._indomitable_primed_this_attack = false

func _action(source: String = "melee") -> Dictionary:
	return INTERACTIONS.damage_context(player.new_combat_action(source), source).interaction

func _run() -> void:
	for source in ["melee", "blast_drive"]:
		await _test_native_spend_and_echo(source)
		await _test_native_miss(source)
	await _test_remote_start_order()
	await _test_death_owner_cleanup()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[UnbrokenSharedAttack] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_native_spend_and_echo(source: String) -> void:
	_make_world()
	player.apply_upgrade("first_strike")
	player.apply_upgrade("sovereigns_double")
	var first := _enemy(Vector2(40.0, 0.0))
	var second := _enemy(Vector2(45.0, 20.0))
	var echo := _enemy(Vector2(540.0, 0.0))
	await _settle()
	_prime()
	var geometry := player._get_melee_attack_geometry({})
	_check(float(geometry.range) > player.attack_range, source + ": primed geometry is resolved before spending")
	player.boss_combinations.create_shade(Vector2(500.0, 0.0))
	var coefficient := 2.5 if source == "blast_drive" else 1.0
	var raw := int(player.damage * coefficient)
	var ratio := (1.8 + player.indomitable_spirit_damage_reduction * 2.2 + player.INDOMITABLE_OATH_FILL_REQUIREMENT * 0.009) * player.INDOMITABLE_OATH_DAMAGE_SCALE
	var retaliation := int(round(player.damage * ratio))
	var expected_first := int(round(raw + retaliation + 16.0 * (coefficient + ratio)))
	var expected_second := int(round(raw + 16.0 * coefficient))
	var expected_echo := int(round(0.55 * (raw + retaliation + 16.0 * (coefficient + ratio))))
	player._perform_melee_attack(Vector2.RIGHT, {"source": source, "damage": raw, "damage_coefficient": coefficient})
	_check(first.get_current_health() == 10000 - expected_first, source + ": first geometric packet uses the exact Oath Damage coefficient for conditional Boons")
	_check(second.get_current_health() == 10000 - expected_second, source + ": retaliation and its coefficient are spent once across multiple foes")
	_check(echo.get_current_health() == 10000 - expected_echo, source + ": Double inherits the Oath descriptor and applies conditional damage exactly once")
	_check(player.indomitable_damage_bank == 0.0 and not player._indomitable_spirit_primed, source + ": neither the spending Attack's extra targets nor its Echo refill the bank")
	_check(player._indomitable_pending_melee_bonus == 0 and player._indomitable_pending_damage_coefficient == 0.0, source + ": temporary retaliation values clear after delivery")
	_check(player._get_melee_attack_geometry({}).range == player.attack_range, source + ": next unprimed Attack restores ordinary geometry")
	_free_world()

func _test_native_miss(source: String) -> void:
	_make_world()
	_prime()
	_check(not player._perform_melee_attack(Vector2.RIGHT, {"source": source, "damage": 20, "damage_coefficient": 1.0}), source + ": actual empty-room swing is a miss")
	_check(player.indomitable_damage_bank == 0.0 and not player._indomitable_spirit_primed, source + ": a deliberate miss spends the primed bank")
	var target := _enemy(Vector2(40.0, 0.0))
	await _settle()
	player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "damage_coefficient": 1.0})
	_check(target.get_current_health() == 9980, source + ": a later Attack cannot recover the missed retaliation")
	_check(player.indomitable_damage_bank > 0.0, source + ": the later ordinary Attack begins filling a new bank")
	_free_world()

func _test_remote_start_order() -> void:
	_make_world()
	var first := _action()
	var later := _action()
	_prime()
	player.local_owner = false
	_check(player._accept_shared_attack_start(first), "Host accepts a new deliberate owner Attack root")
	_check(player.indomitable_damage_bank == 0.0 and not player._indomitable_spirit_primed, "Host spends its bank even when the accepted Attack misses")
	_check(player.combat_interactions.has_reaction(first, "oath_attack_spent"), "Spent decision is recorded on the originating root")
	_prime()
	_check(not player._accept_shared_attack_start(first) and player._indomitable_spirit_primed, "Duplicate start cannot consume a newer primed bank")
	player.indomitable_damage_bank = 0.0
	player._indomitable_spirit_primed = false
	_check(player._accept_shared_attack_start(later), "A later unprimed Attack starts normally")
	var target := _enemy(Vector2(40.0, 0.0))
	var other := _enemy(Vector2(45.0, 20.0))
	await _settle()
	DAMAGEABLE.apply_damage(target, 20, INTERACTIONS.damage_context(first, "melee", {"damage_coefficient": 1.0}), 1)
	DAMAGEABLE.apply_damage(other, 20, INTERACTIONS.damage_context(first, "melee", {"damage_coefficient": 1.0}), 1)
	_check(player.indomitable_damage_bank == 0.0, "Delayed multi-target packets cannot refill the old spending Attack after a newer start")
	DAMAGEABLE.apply_damage(target, 20, INTERACTIONS.damage_context(later, "melee", {"damage_coefficient": 1.0}), 1)
	_check(player.indomitable_damage_bank > 0.0, "A later unspent Attack still fills the host bank")
	var before_echo := player.indomitable_damage_bank
	DAMAGEABLE.apply_damage(other, 11, INTERACTIONS.damage_context(later, "sovereigns_double", {"damage_coefficient": 0.55, "secondary": true, "is_ground_attack": true}), 1)
	_check(player.indomitable_damage_bank == before_echo, "Host Echo damage cannot count as a fresh Attack hit for Oath")
	var stale := first.duplicate()
	stale.epoch += 1
	_check(not player._accept_shared_attack_start(stale), "Unannounced epoch cannot reset host Attack state")
	var echo_start := first.duplicate()
	echo_start.source = "sovereigns_double"
	_check(not player._accept_shared_attack_start(echo_start), "An Echo cannot announce a deliberate Attack start")
	player.local_owner = true
	_check(not player._accept_shared_attack_start(first), "Host-local owner never mirrors a second spend through the remote entry point")
	_free_world()

func _test_death_owner_cleanup() -> void:
	_make_world()
	player.apply_trial_power("eclipse_mark")
	player.apply_trial_power("dread_resonance")
	player.apply_trial_power("sigil_chain")
	var teammate := OathPlayer.new()
	world.add_child(teammate)
	teammate.player_id = 2
	teammate.apply_trial_power("eclipse_mark")
	var target := _enemy(Vector2(40.0, 0.0))
	await _settle()
	var own := _action()
	var ally_action := INTERACTIONS.damage_context(teammate.new_combat_action("melee"), "melee").interaction as Dictionary
	DAMAGEABLE.apply_mark(target, "eclipse_mark", 0.15, 4.0, 1, own)
	DAMAGEABLE.add_dread_stack(target, 1, 8, own)
	DAMAGEABLE.apply_mark(target, "eclipse_mark", 0.15, 4.0, 2, ally_action)
	player._drop_sigil_chain_zone(target.global_position)
	_check(player.shared_build_runtime.fields.contains_point(target.global_position), "Live owner has an actual Sigil Field before death")
	_check(int(DAMAGEABLE.status_snapshot(target, 1).dread_stacks) == 1, "Live owner has a Dread stack before death")
	player.local_owner = false
	player.set_alive(false)
	_check(player.shared_build_runtime.fields._fields.is_empty(), "Remote-owner death clears Field membership immediately without an independent epoch advance")
	_check(int(DAMAGEABLE.status_snapshot(target, 1).dread_stacks) == 0, "Death clears only the fallen owner's Dread stacks")
	_check(float(DAMAGEABLE.status_snapshot(target, 2).mark_ratio) > 0.0, "Teammate's independently owned Mark survives another player's death")
	teammate.upgrade_system.power_registry.free()
	teammate.free()
	_free_world()
