extends SceneTree

const WAKE := preload("res://scripts/static_wake_controller.gd")
const REGISTRY := preload("res://scripts/shared/combat_interaction_registry.gd")
const UPGRADES := preload("res://scripts/upgrade_system.gd")
const POWERS := preload("res://scripts/power_registry.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")

class TestWorld extends Node2D:
	var damage_total := 0
	func record_player_damage_dealt(amount: int, _peer: int = 0, _killed: bool = false, _enemy: int = 0) -> void:
		damage_total += amount

class CountedWake extends "res://scripts/static_wake_controller.gd":
	var settlement_calls := 0
	func _settle(enemy: Node2D, state: Dictionary) -> void:
		settlement_calls += 1
		super._settle(enemy, state)

class Actor extends "res://scripts/player.gd":
	var local_owner := true
	var cues: Array[Dictionary] = []
	func _ready() -> void:
		set_physics_process(false)
		_create_health_state()
		player_id = 1
		add_to_group("combat_players")
		_ensure_combat_interactions()
		_ensure_static_wake()
		static_wake_controller.set_process(false)
		reward_static_wake = true
		static_wake_damage = 8
		static_wake_trail_radius = 20.0
		static_wake_lifetime = 2.0
	func _is_local_control_owner() -> bool:
		return local_owner
	func _broadcast_cue_event(event_name: String, payload: Dictionary = {}, _reliable: bool = false) -> void:
		cues.append({"event": event_name, "payload": payload.duplicate(true)})

class Target extends "res://scripts/enemy_base.gd":
	var hits: Array[Dictionary] = []
	var cancel_owner: Node
	func _ready() -> void:
		set_physics_process(false)
		max_health = 10000
		_create_health_state()
		add_to_group("enemies")
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		hits.append({"amount": amount, "context": context.duplicate(true)})
		super.take_damage(amount, context)
		if is_instance_valid(cancel_owner):
			cancel_owner.cancel()

var checks := 0
var failures: Array[String] = []
var stage: Node2D

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _actor() -> Actor:
	var actor := Actor.new()
	stage.add_child(actor)
	return actor

func _target(position := Vector2.ZERO) -> Target:
	var target := Target.new()
	stage.add_child(target)
	target.global_position = position
	return target

func _ribbon(actor: Actor, start := Vector2(-30, 0), finish := Vector2(30, 0)) -> Dictionary:
	var context: Dictionary = actor.combat_interactions.begin_action("dash")
	actor.static_wake_controller.begin_dash(context)
	actor.static_wake_controller.append_segment(start, finish)
	actor.static_wake_controller.end_dash()
	return context

func _damage(target: Target) -> int:
	return 10000 - target.health_state.current_health

func _clear() -> void:
	for child in stage.get_children():
		child.free()

func _run() -> void:
	stage = TestWorld.new()
	root.add_child(stage)
	current_scene = stage
	_test_cadence()
	_test_levels()
	_test_crossing()
	_test_union_and_shape()
	_test_deadlines_and_lifetime()
	_test_empty_gap()
	_test_context_and_slow()
	_test_cancellation()
	_test_replica()
	_clear()
	stage.free()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("Static Wake regressions: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_cadence() -> void:
	for fps in [30, 60, 120]:
		for count in [1, 2]:
			var actor := _actor()
			var target := _target()
			for ignored in range(count):
				_ribbon(actor)
			for ignored in range(fps):
				actor.static_wake_controller.tick(1.0 / fps)
			_check(_damage(target) == 48, "%dfps/%d ribbon union deals exactly 48/sec, not rounded per frame" % [fps, count])
			_check(target.hits.size() == 4, "%dfps/%d ribbon union uses four damage windows" % [fps, count])
			_clear()
	var actor := _actor()
	var target := _target()
	_ribbon(actor)
	for delta in [0.4, 0.37, 0.23]:
		actor.static_wake_controller.tick(delta)
	_check(_damage(target) == 48 and target.hits.size() == 4, "Hitches preserve all scheduled windows and exact total")
	_clear()

func _test_levels() -> void:
	for picks in [1, 2, 3, 4]:
		for fps in [30, 60, 120]:
			var actor := _actor()
			actor.damage = 20
			var registry := POWERS.new()
			actor.add_child(registry)
			var upgrades := UPGRADES.new()
			actor.add_child(upgrades)
			upgrades.initialize(actor, null, registry)
			for pick in range(picks):
				upgrades.apply_trial_power("static_wake")
			var target := _target()
			_ribbon(actor)
			for frame in range(fps):
				actor.static_wake_controller.tick(1.0 / fps)
			_check(_damage(target) == actor.static_wake_damage * 6, "Mapped %d-pick Wake at %dfps retains its actual per-second damage" % [picks, fps])
			_check(target.is_slowed() == (picks >= 3), "Mapped %d-pick Wake at %dfps retains its structural Slow level" % [picks, fps])
			if picks == 4:
				_check(upgrades.has_trial_power_prismatic("static_wake") and not upgrades.apply_trial_power("static_wake"), "Wake retains one Prismatic pick")
			_clear()

func _test_crossing() -> void:
	for fps in [30, 60, 120]:
		var actor := _actor()
		var target := _target(Vector2(0, -100))
		_ribbon(actor)
		for frame in range(1, fps + 1):
			target.global_position = Vector2(0, -100.0 + 200.0 * frame / fps)
			actor.static_wake_controller.tick(1.0 / fps)
		_check(_damage(target) == 9, "%dfps moving target accrues .2s exact contact with fractional carry" % fps)
		_clear()
	var actor := _actor()
	var target := _target(Vector2(0, -100))
	_ribbon(actor)
	target.global_position = Vector2(0, 100)
	actor.static_wake_controller.tick(1.0)
	_check(_damage(target) == 9, "A full crossing within one hitch is detected and lifetime-clipped")
	_check(is_equal_approx(float(actor.static_wake_controller._targets[target.get_instance_id()].fraction), 0.6), "Crossing fractional damage remains for later exposure")
	_clear()
	actor = _actor()
	target = _target(Vector2(0, -96))
	_ribbon(actor)
	target.global_position = Vector2(0, 96)
	actor.static_wake_controller.tick(1.0)
	_check(_damage(target) == 10, "Float64 exposure preserves an exact integer tick across a 192px crossing")
	_clear()

func _test_union_and_shape() -> void:
	var actor := _actor()
	var target := _target(Vector2(30, 30))
	actor.static_wake_trail_radius = 8
	actor.static_wake_controller.begin_dash(actor.combat_interactions.begin_action("dash"))
	actor.static_wake_controller.append_segment(Vector2.ZERO, Vector2(60, 0))
	actor.static_wake_controller.append_segment(Vector2(60, 0), Vector2(60, 60))
	actor.static_wake_controller.end_dash()
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == 0, "A bent traveled path does not become an untraveled diagonal chord")
	target.global_position = Vector2(61, 30)
	actor.static_wake_controller.tick(0.25)
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) > 0, "Actual second path leg damages beside its traveled segment")
	_clear()
	actor = _actor()
	target = _target(Vector2(51, 0))
	_ribbon(actor, Vector2.ZERO, Vector2(30, 0))
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == 0, "A collision-clamped path never extrapolates past its 20px round cap")
	_clear()
	actor = _actor()
	target = _target(Vector2(50, 0))
	_ribbon(actor, Vector2.ZERO, Vector2(30, 0))
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == 12, "Closed radius includes an enemy center exactly on a round cap")
	_clear()

func _test_deadlines_and_lifetime() -> void:
	var actor := _actor()
	var target := _target()
	actor.static_wake_lifetime = 0.1
	_ribbon(actor)
	actor.static_wake_controller.tick(0.1)
	_check(_damage(target) == 0 and actor.static_wake_controller.ribbons.is_empty(), "Expiry retires geometry without inventing an early tick")
	actor.static_wake_controller.tick(0.15)
	_check(_damage(target) == 4, "Pre-expiry .1s exposure settles only at the original .25s deadline")
	_ribbon(actor)
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == 9, "Reentry carries fractional damage rather than rounding every ribbon")
	actor.static_wake_controller.tick(0.75)
	_check(_damage(target) == 9, "Expired ribbons accrue no extra damage in later windows")
	_clear()
	actor = _actor()
	target = _target()
	_ribbon(actor)
	actor.static_wake_controller.tick(0.2)
	_ribbon(actor)
	_ribbon(actor)
	_check(actor.static_wake_controller.ribbons.size() == 2, "A third actual dash replaces only the oldest ribbon")
	actor.static_wake_controller.begin_dash(actor.combat_interactions.begin_action("dash"))
	actor.static_wake_controller.append_segment(Vector2.ZERO, Vector2.ZERO)
	actor.static_wake_controller.end_dash()
	_check(actor.static_wake_controller.ribbons.size() == 2, "Blocked zero-distance dash does not replace traveled ribbons")
	actor.static_wake_controller.tick(0.05)
	_check(_damage(target) == 12, "Replacement and overlapping reentry preserve the first damage deadline")
	_clear()
	actor = _actor()
	target = _target()
	actor.static_wake_lifetime = 0.4
	actor.static_wake_controller.begin_dash(actor.combat_interactions.begin_action("dash"))
	actor.static_wake_controller.append_segment(Vector2(-30, 0), Vector2.ZERO)
	actor.static_wake_controller.tick(0.3)
	actor.static_wake_controller.append_segment(Vector2.ZERO, Vector2(30, 0))
	actor.static_wake_controller.end_dash()
	actor.static_wake_controller.tick(0.2)
	_check(actor.static_wake_controller.ribbons.is_empty(), "Whole-ribbon lifetime begins at first travel; append/end cannot refresh it")
	_check(_damage(target) == 19, "A final partial lifetime accrues .4s even when the last tick spans expiry")
	_clear()

func _test_context_and_slow() -> void:
	var actor := _actor()
	var target := _target()
	actor.static_wake_stacks = 3
	actor.reward_hunters_snare = true
	actor.hunters_snare_stacks = 2
	actor.hunters_snare_bonus_damage = 7
	var action := _ribbon(actor)
	_ribbon(actor)
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == 12 and target.is_slowed(), "First Wake tick uses pre-Slow Snare eligibility, then applies level3 Slow")
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == 31, "Second already-slowed tick adds the Snare bonus once despite overlap")
	var context: Dictionary = target.hits[0].context
	_check(not context.get("secondary", false) and not context.get("is_ground_attack", false), "Wake retains existing primary directional-defense classification")
	_check(int(context.interaction.traits) == (REGISTRY.HIT | REGISTRY.DASH | REGISTRY.ELECTRIC), "Wake hit has Hit, Dash and Electric properties")
	_check(context.interaction.seq == action.seq and target.hits[1].context.interaction.seq == action.seq, "All ticks retain the actual originating Dash identity")
	_check(context.attack_origin == Vector2.ZERO, "Damage origin is the nearest actual traveled path contact")
	_check(actor.combat_interactions._roots.is_empty(), "Wake alone does not enable an unlearned Storm Crown")
	_clear()
	actor = _actor()
	target = _target()
	actor.static_wake_lifetime = 0.01
	actor.static_wake_damage = 1
	actor.reward_hunters_snare = true
	actor.hunters_snare_stacks = 2
	target.apply_slow(2.0, 0.8)
	_ribbon(actor)
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == actor.hunters_snare_bonus_damage, "A qualifying fractional-only exposure permits its one authoritative pre-Slow Snare bonus")
	_clear()

func _test_empty_gap() -> void:
	var actor := _actor()
	actor.static_wake_controller.free()
	var counted := CountedWake.new()
	actor.static_wake_controller = counted
	actor.add_child(counted)
	counted.initialize(actor)
	counted.set_process(false)
	var target := _target()
	_ribbon(actor)
	counted.tick(10000.0)
	_check(_damage(target) == 96, "A huge hitch accrues only the ribbon's actual two-second lifetime")
	_check(counted.settlement_calls == 8, "Expired idle windows fast-forward without thousands of empty callbacks")
	_ribbon(actor)
	counted.tick(0.25)
	_check(_damage(target) == 108, "Arithmetic fast-forward retains the established quarter-second phase on reentry")
	_clear()

func _test_cancellation() -> void:
	for boundary in ["cancel", "death", "menu", "survey"]:
		var actor := _actor()
		var target := _target()
		_ribbon(actor)
		actor.static_wake_controller.tick(0.2)
		match boundary:
			"cancel": actor.static_wake_controller.cancel()
			"death": actor._is_alive_state = false
			"menu": actor.combat_damage_enabled = false
			"survey": actor.encounter_input_frozen = true
		actor.static_wake_controller.tick(0.2)
		_check(_damage(target) == 0 and actor.static_wake_controller.ribbons.is_empty() and actor.static_wake_controller._targets.is_empty(), "%s drops pending exposure and temporary geometry" % boundary)
		_clear()
	var actor := _actor()
	var first := _target()
	var second := _target()
	first.cancel_owner = actor.static_wake_controller
	_ribbon(actor)
	actor.static_wake_controller.tick(1.0)
	_check(_damage(first) == 12 and _damage(second) == 0, "Damage callback cancellation stops later windows and later targets safely")
	_check(actor.static_wake_controller.ribbons.is_empty(), "Reentrant cancellation is not undone at tick completion")
	_clear()
	actor = _actor()
	_ribbon(actor)
	actor.static_wake_controller.tick(NAN)
	actor.static_wake_controller.tick(INF)
	_check(actor.static_wake_controller.snapshot_visual().segments.size() == 1, "Non-finite ticks do not corrupt geometry lifetime")
	_clear()
	actor = _actor()
	first = _target()
	_ribbon(actor)
	actor.static_wake_controller.tick(0.1)
	first.free()
	actor.static_wake_controller.tick(0.2)
	_check(actor.static_wake_controller._targets.is_empty() and actor.static_wake_controller._positions.is_empty(), "Freed enemies retire pending clocks and motion history safely")
	_clear()

func _test_replica() -> void:
	var actor := _actor()
	_ribbon(actor)
	var payload: Dictionary = actor.cues.back().payload
	var replica := _actor()
	replica.local_owner = false
	var target := _target()
	replica.static_wake_controller.apply_visual_state(payload)
	_check(replica.static_wake_controller.snapshot_visual().segments.size() == 1, "Valid owner geometry reconstructs one replica ribbon")
	replica.static_wake_controller.tick(0.25)
	_check(_damage(target) == 0, "Visual replica never applies local damage")
	replica.static_wake_controller.tick(0.11)
	_check(replica.static_wake_controller.ribbons.is_empty(), "Lost final message expires by bounded visual lease")
	replica.static_wake_controller.apply_visual_state(payload)
	_check(replica.static_wake_controller.ribbons.is_empty(), "Equal/replayed state cannot revive expired geometry")
	var wrong_room := payload.duplicate(true)
	wrong_room.q += 100
	wrong_room.r += 1
	replica.static_wake_controller.apply_visual_state(wrong_room)
	_check(replica.static_wake_controller._received_sequence == payload.q, "Wrong room packet cannot poison sequence acceptance")
	actor.static_wake_controller.tick(0.1)
	var next_payload: Dictionary = actor.cues.back().payload
	replica.static_wake_controller.apply_visual_state(next_payload)
	_check(replica.static_wake_controller.snapshot_visual().segments.size() == 1, "Fresh heartbeat recovers a lost final/lease without stale replay")
	actor.static_wake_controller.cancel()
	replica.static_wake_controller.apply_visual_state(actor.cues.back().payload)
	_check(replica.static_wake_controller.ribbons.is_empty(), "Owner cancel reliably clears replica geometry")
	_check(var_to_str(next_payload).length() <= 640, "Actual ribbon cue fits the existing transport budget")
	var floor_before: int = replica.static_wake_controller._received_sequence
	for key in ["q", "r", "i", "n"]:
		var invalid := next_payload.duplicate(true)
		invalid[key] = []
		replica.static_wake_controller.apply_visual_state(invalid)
		_check(replica.static_wake_controller._received_sequence == floor_before, "Malformed %s rejects before advancing any state" % key)
	var invalid_segment := next_payload.duplicate(true)
	invalid_segment.q += 100
	invalid_segment.s[0][0] = {}
	replica.static_wake_controller.apply_visual_state(invalid_segment)
	_check(replica.static_wake_controller._received_sequence == floor_before, "Malformed segment identity cannot poison sequence floor")
	var partial := next_payload.duplicate(true)
	partial.q = floor_before + 1
	partial.n = 2
	partial.i = 0
	replica.static_wake_controller.apply_visual_state(partial)
	replica.static_wake_controller.cancel()
	partial.i = 1
	replica.static_wake_controller.apply_visual_state(partial)
	partial.i = 0
	replica.static_wake_controller.apply_visual_state(partial)
	_check(replica.static_wake_controller.ribbons.is_empty(), "Cancellation retires an in-flight multipart sequence before delayed chunks arrive")
	_clear()


