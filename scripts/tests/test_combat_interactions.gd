extends SceneTree

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const REGISTRY := preload("res://scripts/shared/combat_interaction_registry.gd")
const CONTROLLER := preload("res://scripts/combat_interaction_controller.gd")

class Feedback extends Node:
	var chains: Array[Dictionary] = []
	var discharges: int = 0
	func play_storm_crown_discharge(_position: Vector2) -> void:
		discharges += 1
	func play_chain_lightning(from: Vector2, to: Vector2, color: Color = Color.WHITE, _life: float = 0.14) -> void:
		chains.append({"from": from, "to": to, "color": color})
	func play_world_ring(_position: Vector2, _radius: float, _color: Color, _life: float) -> void:
		pass

class Actor extends CharacterBody2D:
	var player_id: int = 1
	var visual_facing_direction: Vector2 = Vector2.RIGHT
	var combat_damage_enabled: bool = true
	var _is_alive_state: bool = true
	var encounter_input_frozen: bool = false
	var reward_storm_crown: bool = true
	var storm_crown_stacks: int = 1
	var storm_crown_proc_every: int = 3
	var storm_crown_chain_targets: int = 2
	var storm_crown_chain_radius: float = 192.0
	var storm_crown_damage_ratio: float = 0.6
	var storm_crown_hit_counter: int = 0
	var storm_crown_discharge_flash_left: float = 0.0
	var storm_crown_discharge_flash_duration: float = 0.24
	var combat_interactions: CONTROLLER
	var boss_combinations: Node
	var player_feedback: Feedback
	var local_owner: bool = true
	var snare_bonus: int = 0
	func _ready() -> void:
		add_to_group("combat_players")
		player_feedback = Feedback.new()
		add_child(player_feedback)
		combat_interactions = CONTROLLER.new()
		add_child(combat_interactions)
		combat_interactions.initialize(self)
	func _is_local_control_owner() -> bool:
		return local_owner
	func _apply_objective_mutator_damage_mult(amount: int) -> int:
		return amount
	func _hunters_snare_aoe_bonus_against(target: Object) -> int:
		return snare_bonus if target.is_slowed() else 0

class Enemy extends "res://scripts/enemy_base.gd":
	var hits: Array[Dictionary] = []
	var callback: Callable
	func _ready() -> void:
		set_physics_process(false)
		max_health = 100000
		_create_health_state()
		add_to_group("enemies")
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		var before := get_current_health()
		super.take_damage(amount, context)
		if before > get_current_health():
			hits.append({"amount": before - get_current_health(), "context": context.duplicate(true), "slowed": is_slowed()})
			if callback.is_valid():
				callback.call()
	func _on_health_state_died() -> void:
		died.emit()

class RoomState extends RefCounted:
	var current_room_sync_id: int = 1

class TestWorld extends Node2D:
	var _world_multiplayer_sync_state: RoomState = RoomState.new()
	var recorded: Array[Dictionary] = []
	func record_player_damage_dealt(amount: int, owner: int = 0, killed: bool = false, enemy_id: int = 0) -> void:
		recorded.append({"amount": amount, "owner": owner, "killed": killed, "enemy_id": enemy_id})

var checks: int = 0
var failures: Array[String] = []
var world: TestWorld
var actor: Actor

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)):
		push_error("Use the isolated regression runner")
		quit(1)
		return
	_test_descriptors()
	_test_levels_and_conduction()
	_test_root_target_budget()
	_test_native_sources_and_echo()
	_test_status_order_and_validation()
	_test_host_snare_tick()
	_test_nested_scope_and_kills()
	_test_cancellation_and_retirement()
	_test_visual_order_and_shape()
	await process_frame
	print("[CombatInteractions] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func setup(level: int = 1) -> void:
	world = TestWorld.new()
	root.add_child(world)
	current_scene = world
	EnemyReplicationService.world_generator = world
	actor = Actor.new()
	world.add_child(actor)
	actor.storm_crown_stacks = level
	actor.storm_crown_proc_every = 4 - level
	actor.storm_crown_chain_targets = 1 + level
	actor.storm_crown_chain_radius = 160.0 + 32.0 * level
	actor.storm_crown_damage_ratio = 0.45 + 0.15 * level

func teardown() -> void:
	check(DAMAGEABLE.current_interaction_context().is_empty() and DAMAGEABLE._damage_depth == 0 and DAMAGEABLE._pending_interaction_hits.is_empty(), "All synchronous scopes and accepted-hit queues retire")
	EnemyReplicationService.world_generator = null
	current_scene = null
	world.free()
	world = null
	actor = null

func enemy(position: Vector2) -> Enemy:
	var node := Enemy.new()
	world.add_child(node)
	node.position = position
	return node

func hit(target: Enemy, action: Dictionary, source: String = "melee", extra: Dictionary = {}, owner: int = 1) -> void:
	DAMAGEABLE.apply_damage(target, 100, REGISTRY.damage_context(action, source, extra), owner)

func chain_count(targets: Array[Enemy]) -> int:
	var count := 0
	for target in targets:
		count += target.hits.filter(func(entry: Dictionary) -> bool: return entry.context.get("attack_type") == "storm_crown").size()
	return count

func row(count: int) -> Array[Enemy]:
	var targets: Array[Enemy] = []
	for index in range(count):
		targets.append(enemy(Vector2(index * 100.0, 0.0)))
	return targets

func _test_descriptors() -> void:
	setup()
	var action := actor.combat_interactions.begin_action("dash")
	var wake := REGISTRY.damage_context(action, "static_wake")
	check(int(wake.interaction.traits) == (REGISTRY.HIT | REGISTRY.DASH | REGISTRY.ELECTRIC), "Wake declares Hit, Dash and Electric")
	var unknown := REGISTRY.damage_context(action, "unknown")
	unknown.interaction.traits = REGISTRY.HIT | REGISTRY.ELECTRIC
	check(int(REGISTRY.validate_action(unknown.interaction, 1).traits) == 0, "Unregistered effects cannot forge supported trait bits")
	var crown := REGISTRY.damage_context(action, "storm_crown")
	crown.interaction.ancestry = 0
	check((int(REGISTRY.validate_action(crown.interaction, 1).ancestry) & REGISTRY.CROWN_ANCESTRY) != 0, "Crown ancestry is derived even when a caller omits it")
	var echo := REGISTRY.damage_context(wake.interaction, "sovereigns_double")
	check((int(REGISTRY.validate_action(echo.interaction, 1).traits) & REGISTRY.ELECTRIC) != 0 and echo.interaction.seq == action.seq, "Echo descriptors copy original properties and preserve the root")
	var validated_wake := REGISTRY.validate_action(wake.interaction, 1)
	check((int(REGISTRY.damage_context(validated_wake, "sovereigns_double").interaction.traits) & REGISTRY.ELECTRIC) != 0, "Echo preserves properties after native metadata normalization")
	var forged := action.duplicate()
	forged.owner = 2
	check(REGISTRY.validate_action(forged, 1).is_empty(), "Claimed owner must match authenticated damage source")
	check(REGISTRY.validate_action({}, 1).is_empty(), "Untracked legacy damage does not invent a root")
	teardown()

func _test_levels_and_conduction() -> void:
	for level in [1, 2, 3]:
		for slowed in [false, true]:
			setup(level)
			var targets := row(8)
			if slowed:
				for target in targets:
					target.apply_slow(2.0, 0.5)
			actor.storm_crown_hit_counter = actor.storm_crown_proc_every - 1
			var action := actor.combat_interactions.begin_action("attack")
			hit(targets[0], action)
			var expected := actor.storm_crown_chain_targets + (1 if slowed and level >= 2 else 0)
			check(chain_count(targets) == expected, "L%d has bounded mapped hops and at most one conduction hop (slow=%s)" % [level, slowed])
			check(targets[0].hits.size() == 1, "Chain cannot revisit its initiating target")
			check(actor.storm_crown_hit_counter == actor.storm_crown_proc_every, "Generated electric chain hits never charge Crown")
			check(actor.player_feedback.chains.size() == expected, "Each actual hop is represented by a single visual link")
			for index in range(1, expected + 1):
				var entry: Dictionary = targets[index].hits[0]
				check(entry.amount == int(round(100.0 * actor.storm_crown_damage_ratio)), "Chain preserves the existing resolved-hit damage ratio")
				check(entry.context.attack_origin == targets[index - 1].position, "Each chain hit carries its actual preceding hop origin")
				check((int(entry.context.interaction.traits) & REGISTRY.ELECTRIC) != 0 and int(entry.context.interaction.ancestry) == REGISTRY.CROWN_ANCESTRY, "Chain keeps Electric and spent Crown ancestry")
			if slowed and level >= 2:
				check(actor.player_feedback.chains.back().color.g == 1.0 and actor.player_feedback.chains.back().color.r < 0.5, "The slow-assisted final hop has a distinct tint")
			teardown()
	setup(3)
	actor.storm_crown_chain_targets = 6
	actor.storm_crown_chain_radius *= 1.2
	actor.storm_crown_damage_ratio *= 1.35
	var targets := row(10)
	targets[1].apply_slow(2.0, 0.5)
	hit(targets[0], actor.combat_interactions.begin_action("attack"))
	check(chain_count(targets) == 7, "Prismatic six-hop Crown gains no more than one conduction hop")
	teardown()

func _test_root_target_budget() -> void:
	setup()
	var target := enemy(Vector2.ZERO)
	var action := actor.combat_interactions.begin_action("dash")
	for source in ["phantom_step", "static_wake", "returning_crescent", "sovereigns_double"]:
		hit(target, action, source, {"secondary": true})
	check(target.hits.size() == 4 and actor.storm_crown_hit_counter == 1, "Overlapping native effects keep their own damage but count a root/target only once")
	hit(target, actor.combat_interactions.begin_action("dash"), "static_wake")
	check(actor.storm_crown_hit_counter == 2, "A new successful dash can count the same target again")
	var other := enemy(Vector2(80.0, 0.0))
	hit(other, action)
	check(actor.storm_crown_hit_counter == 3 and actor.player_feedback.discharges == 1, "Another target in an existing root may complete one discharge")
	hit(enemy(Vector2(160.0, 0.0)), action)
	check(actor.storm_crown_hit_counter == 3 and actor.player_feedback.discharges == 1, "Spent roots cannot bank further charge or create another discharge")
	teardown()

func _test_native_sources_and_echo() -> void:
	for source in REGISTRY.EFFECT_TRAITS:
		if source == "storm_crown":
			continue
		setup(3)
		var targets := row(3)
		hit(targets[0], actor.combat_interactions.begin_action("attack"), source, {"secondary": true})
		check(actor.storm_crown_hit_counter == 1 and chain_count(targets) == 2, "%s participates by its Hit descriptor even when legacy damage is secondary" % source)
		teardown()
	setup(3)
	var targets := row(3)
	var action := actor.combat_interactions.begin_action("attack")
	action.ancestry = REGISTRY.CROWN_ANCESTRY
	hit(targets[0], action, "fracture_fault_line")
	check(actor.storm_crown_hit_counter == 0 and chain_count(targets) == 0, "A different legacy power cannot restart Crown from Crown ancestry")
	teardown()

func _test_status_order_and_validation() -> void:
	setup(2)
	actor.storm_crown_hit_counter = 1
	var targets := row(6)
	var action := actor.combat_interactions.begin_action("attack")
	hit(targets[0], action, "melee", {"slows_on_hit": [{"duration": 0.8, "mult": 0.66}, {"duration": 0.5, "mult": 0.6}]})
	check(targets[0].is_slowed() and is_equal_approx(targets[0].slow_time_left, 0.8) and is_equal_approx(targets[0].slow_speed_mult, 0.6), "Attached Snare/Riftpunch slows preserve maximum duration and strongest multiplier")
	check(targets[0].hits[0].slowed and chain_count(targets) == 3, "Slow applies before damage while conduction uses pre-hit state")
	var blocked := enemy(Vector2(0.0, 500.0))
	blocked.damage_blocked = true
	var before := actor.storm_crown_hit_counter
	hit(blocked, actor.combat_interactions.begin_action("attack"))
	DAMAGEABLE.apply_damage(blocked, 0, REGISTRY.damage_context(action, "melee"))
	check(actor.storm_crown_hit_counter == before and blocked.hits.is_empty(), "Blocked and zero-damage contacts emit no accepted Hit")
	var stale := action.duplicate()
	stale.room += 1
	var clean := enemy(Vector2(0.0, 1000.0))
	hit(clean, stale, "melee", {"slow_on_hit": {"duration": 2.0, "mult": 0.3}})
	check(not clean.is_slowed() and clean.hits.size() == 1, "Stale interaction metadata cannot apply attached slow while legacy base damage stays separate")
	check(not DAMAGEABLE.apply_slow(clean, 2.0, 0.5, 1, stale), "Standalone slow rejects wrong room metadata")
	check(not DAMAGEABLE.apply_slow(clean, NAN, 0.5) and not DAMAGEABLE.apply_slow(clean, 1.0, 0.0), "Nonfinite and invalid slow values are rejected")
	check(DAMAGEABLE.apply_slow(clean, 0.6, 0.8, 1, actor.combat_interactions.begin_action("aegis")) and clean.is_slowed(), "Any authoritative slow source can prepare a target")
	teardown()

func _test_host_snare_tick() -> void:
	setup()
	actor.snare_bonus = 7
	var target := enemy(Vector2.ZERO)
	var action := actor.combat_interactions.begin_action("dash")
	var context := REGISTRY.damage_context(action, "static_wake", {"secondary": true, "hunters_snare_aoe_bonus": true})
	check(not DAMAGEABLE.apply_damage(target, 0, context), "No base damage and no prepared target produces no hit")
	check(actor.storm_crown_hit_counter == 0 and target.hits.is_empty(), "Rejected zero tick cannot charge Crown")
	DAMAGEABLE.apply_slow(target, 1.0, 0.5, 1, action)
	check(DAMAGEABLE.apply_damage(target, 0, context) and target.hits.back().amount == 7, "Host accepts a zero-base tick when actual pre-slow preparation supplies a positive bonus")
	check(actor.storm_crown_hit_counter == 1, "Host-resolved positive bonus contributes exactly one root-target Hit")
	DAMAGEABLE.apply_damage(target, 10, context)
	check(target.hits.back().amount == 17 and actor.storm_crown_hit_counter == 1, "Each scheduled hit adds one bonus without multiplying reaction allowances")
	var wrong_source := REGISTRY.damage_context(action, "melee", {"hunters_snare_aoe_bonus": true})
	check(not DAMAGEABLE.apply_damage(target, 0, wrong_source), "Unrelated descriptors cannot opt into Wake's host bonus")
	actor.combat_interactions.cancel()
	check(not DAMAGEABLE.apply_damage(target, 0, context), "Stale scheduled metadata cannot claim a host bonus")
	teardown()

func _test_nested_scope_and_kills() -> void:
	setup()
	var first := enemy(Vector2.ZERO)
	var nested := enemy(Vector2(100.0, 0.0))
	var observations: Array[Dictionary] = []
	first.callback = func() -> void:
		observations.append(actor.combat_interactions.begin_action("automatic"))
		DAMAGEABLE.apply_damage(nested, 5, {"attack_type": "fracture_fault_line"})
	var action := actor.combat_interactions.begin_action("attack")
	hit(first, action)
	check(observations[0].seq == action.seq and nested.hits[0].context.interaction.seq == action.seq, "Synchronous descendants cannot mint another root")
	check(actor.storm_crown_hit_counter == 2, "Two accepted targets share a root but each may contribute once")
	first.callback = Callable()
	var kill_scope := DAMAGEABLE.begin_kill_proc_scope(DAMAGEABLE.KILL_PROC_SUPPRESS_FRACTURE)
	var previous := DAMAGEABLE.begin_interaction_scope(action)
	DAMAGEABLE.begin_secondary_scope()
	DAMAGEABLE.apply_damage(first, 1, {"attack_type": "static_wake"})
	DAMAGEABLE.end_secondary_scope()
	DAMAGEABLE.end_interaction_scope(previous)
	DAMAGEABLE.end_kill_proc_scope(kill_scope)
	var context: Dictionary = first.hits.back().context
	check(context.secondary and context.kill_proc_suppression == DAMAGEABLE.KILL_PROC_SUPPRESS_FRACTURE, "Semantic scopes retain existing secondary and kill-proc suppression")
	check(not DAMAGEABLE.is_launch_suppressed() and DAMAGEABLE.get_kill_proc_suppression() == 0, "Nested semantic work cannot leak legacy suppression")
	teardown()

func _test_cancellation_and_retirement() -> void:
	setup()
	actor.storm_crown_proc_every = 100000
	var target := enemy(Vector2.ZERO)
	var old := actor.combat_interactions.begin_action("dash")
	hit(target, old, "static_wake")
	actor.local_owner = false
	actor.combat_interactions.cancel()
	hit(target, old, "sovereigns_double", {"secondary": true})
	check(actor.storm_crown_hit_counter == 1 and actor.combat_interactions._accepted_epoch == old.epoch and actor.combat_interactions._roots.size() == 1, "Remote snapshot cancellation retains the authenticated epoch and consumed target allowance")
	actor.local_owner = true
	actor.combat_interactions.cancel()
	hit(target, old, "static_wake", {"slow_on_hit": {"duration": 1.0, "mult": 0.5}})
	check(actor.storm_crown_hit_counter == 1 and not target.is_slowed(), "Cancelled epochs cannot count again or apply attached statuses")
	var first_new := actor.combat_interactions.begin_action("dash")
	hit(target, first_new)
	for index in range(REGISTRY.MAX_ROOTS + 2):
		hit(target, actor.combat_interactions.begin_action("attack"))
	var before := actor.storm_crown_hit_counter
	hit(target, first_new)
	check(actor.combat_interactions._roots.size() == REGISTRY.MAX_ROOTS and actor.storm_crown_hit_counter == before, "Bounded ledger eviction permanently retires old sequences")
	var current := actor.combat_interactions.begin_action("attack")
	world._world_multiplayer_sync_state.current_room_sync_id += 1
	hit(target, current)
	check(actor.storm_crown_hit_counter == before, "Room transitions reject previous-room interactions")
	var fresh := actor.combat_interactions.begin_action("attack")
	hit(target, fresh)
	check(actor.storm_crown_hit_counter == before + 1, "A new room can accept a freshly announced action")
	target.callback = actor.combat_interactions.cancel
	hit(target, actor.combat_interactions.begin_action("attack"))
	check(actor.storm_crown_hit_counter == before + 1, "Synchronous cancellation during damage prevents the pending reaction")
	target.callback = Callable()
	teardown()

func _test_visual_order_and_shape() -> void:
	setup()
	var action := actor.combat_interactions.begin_action("attack")
	var payload := {"run": action.run, "room": action.room, "epoch": action.epoch,
		"serial": 10, "counter": 2, "links": PackedVector2Array([Vector2.ZERO, Vector2(40.0, 0.0)]), "conduction_index": 1}
	actor.combat_interactions.apply_network_state(payload)
	check(actor.player_feedback.chains.size() == 1 and actor.storm_crown_hit_counter == 2, "Resolved presentation carries the owner counter and exact hop")
	actor.combat_interactions.apply_network_state(payload)
	var old := payload.duplicate()
	old.serial = 9
	actor.combat_interactions.apply_network_state(old)
	check(actor.player_feedback.chains.size() == 1, "Repeated and stale visual state cannot replay a discharge")
	for malformed in [PackedVector2Array([Vector2.INF]), PackedVector2Array([Vector2.ZERO, Vector2(NAN, 0.0)])]:
		var invalid := payload.duplicate()
		invalid.serial = 11
		invalid.links = malformed
		actor.combat_interactions.apply_network_state(invalid)
	check(actor.player_feedback.chains.size() == 1, "Nonfinite geometry is rejected before changing visual sequence")
	actor.combat_interactions.cancel()
	payload.serial = 12
	actor.combat_interactions.apply_network_state(payload)
	check(actor.player_feedback.chains.size() == 1, "A late previous-epoch visual cannot resurrect after cancellation")
	actor.local_owner = false
	payload.serial = 13
	actor.combat_interactions.apply_network_state(payload)
	check(actor.player_feedback.chains.size() == 1, "An observer also rejects visual state older than the acknowledged owner epoch")
	teardown()
