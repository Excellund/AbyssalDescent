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

func _learn(actor: Actor, power: String, picks: int) -> void:
	if not is_instance_valid(actor.upgrade_system):
		var registry := POWERS.new()
		actor.add_child(registry)
		actor.upgrade_system = UPGRADES.new()
		actor.add_child(actor.upgrade_system)
		actor.upgrade_system.initialize(actor, null, registry)
	for pick in range(picks):
		actor.upgrade_system.apply_trial_power(power)

func _fraction(target: Target, owner: int = 1) -> float:
	var status := target.get_node_or_null("SharedCombatStatus")
	return float(status._remainders.get("%d:static_wake" % owner, 0.0)) if status != null else 0.0

func _clear() -> void:
	for child in stage.get_children():
		child.free()

func _run() -> void:
	stage = TestWorld.new()
	root.add_child(stage)
	current_scene = stage
	_test_cadence()
	_test_sustained_conditions()
	_test_levels()
	_test_analytic_damage_scaling()
	_test_phantom_damage_scaling()
	_test_retort_damage_scaling()
	_test_fixed_farline_damage()
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
			_check(_damage(target) == 36, "%dfps/%d ribbon union deals exactly 36/sec, not rounded per frame" % [fps, count])
			_check(target.hits.size() == 4, "%dfps/%d ribbon union uses four damage windows" % [fps, count])
			_clear()
	var actor := _actor()
	var target := _target()
	_ribbon(actor)
	for delta in [0.4, 0.37, 0.23]:
		actor.static_wake_controller.tick(delta)
	_check(_damage(target) == 36 and target.hits.size() == 4, "Hitches preserve all scheduled windows and exact total")
	_clear()

func _test_levels() -> void:
	for picks in [1, 2, 3, 4]:
		for fps in [30, 60, 120]:
			var actor := _actor()
			actor.damage = 20
			_learn(actor, "static_wake", picks)
			var target := _target()
			_ribbon(actor)
			for frame in range(fps):
				actor.static_wake_controller.tick(1.0 / fps)
			var expected: float = [40.5, 54.0, 67.5, 94.5][picks - 1]
			_check(_damage(target) == int(floor(expected)), "Mapped %d-pick Wake at %dfps applies its reduced per-second damage" % [picks, fps])
			_check(is_equal_approx(_damage(target) + _fraction(target), expected), "Mapped %d-pick Wake at %dfps retains its unspent fractional damage" % [picks, fps])
			_check(target.is_slowed() == (picks >= 3), "Mapped %d-pick Wake at %dfps retains its structural Slow level" % [picks, fps])
			if picks == 4:
				_check(actor.upgrade_system.has_trial_power_prismatic("static_wake") and not actor.upgrade_system.apply_trial_power("static_wake"), "Wake retains one Prismatic pick")
			_clear()

func _test_crossing() -> void:
	for fps in [30, 60, 120]:
		var actor := _actor()
		var target := _target(Vector2(0, -100))
		_ribbon(actor)
		for frame in range(1, fps + 1):
			target.global_position = Vector2(0, -100.0 + 200.0 * frame / fps)
			actor.static_wake_controller.tick(1.0 / fps)
		_check(_damage(target) == 7 and is_equal_approx(_fraction(target), 0.2), "%dfps moving target conserves .2s exposure with Wake floor carry" % fps)
		_clear()


	var actor := _actor()
	var target := _target(Vector2(0, -100))
	_ribbon(actor)
	target.global_position = Vector2(0, 100)
	actor.static_wake_controller.tick(1.0)
	_check(_damage(target) == 7, "A full crossing within one hitch is detected and lifetime-clipped")
	_check(is_equal_approx(_fraction(target), 0.2), "Crossing credit stays on the host target's owner/source ledger")
	_clear()
	actor = _actor()
	target = _target(Vector2(0, -72))
	_ribbon(actor)
	target.global_position = Vector2(0, 72)
	actor.static_wake_controller.tick(1.0)
	_check(_damage(target) == 10, "Float64 exposure preserves an exact integer tick across a 144px crossing")
	_clear()

func _test_analytic_damage_scaling() -> void:
	for picks in [1, 2, 3, 4]:
		for fps in [30, 60, 120, 0]:
			for percentages in [false, true]:
				var actor := _actor()
				actor.damage = 21
				_learn(actor, "static_wake", picks)
				actor.first_strike_bonus_damage = 16
				var target := _target()
				if percentages:
					_learn(actor, "hunters_snare", 2)
					_learn(actor, "eclipse_mark", 1)
					target.apply_slow(10.0, 0.8)
					var action := actor.new_combat_action("melee")
					actor.DAMAGEABLE.apply_mark(target, "eclipse_mark", 0.15, 4.0, 1, action)
				_ribbon(actor)
				if fps > 0:
					for frame in range(fps):
						actor.static_wake_controller.tick(1.0 / fps)
				else:
					for delta in [0.4, 0.37, 0.23]:
						actor.static_wake_controller.tick(delta)
				var base_ratio: float = [0.45, 0.60, 0.75, 0.75][picks - 1]
				var ratio: float = [0.45, 0.60, 0.75, 1.05][picks - 1]
				var raw := int(ceil(21.0 * base_ratio))
				if picks == 4:
					raw = int(raw * 1.4)
				var expected := 4.5 * (raw + 16.0 * ratio) * (1.15 * 1.25 if percentages else 1.0)
				var label := "Learned Wake picks%d %dfps percentages=%s" % [picks, fps, percentages]
				_check(actor.static_wake_damage == raw and is_equal_approx(actor.static_wake_damage_ratio, ratio), label + ": ordinary acquisition retains raw rounding and maps the analytic coefficient separately")
				_check(_damage(target) == int(floor(expected + 0.000000001)), label + ": actual Field damage combines conditional Damage and preexisting Mark/Slow percentages")
				_check(absf(_damage(target) + _fraction(target) - expected) < 0.00002, label + ": fractional carry preserves the exact formula across frame rates")
				_clear()

func _test_phantom_damage_scaling() -> void:
	for picks in [1, 2, 3, 4]:
		for percentages in [false, true]:
			var actor := _actor()
			actor.damage = 21
			_learn(actor, "phantom_step", picks)
			actor.first_strike_bonus_damage = 16
			var target := _target()
			if percentages:
				_learn(actor, "hunters_snare", 2)
				_learn(actor, "eclipse_mark", 1)
				target.apply_slow(10.0, 0.8)
				actor.DAMAGEABLE.apply_mark(target, "eclipse_mark", 0.15, 4.0, 1, actor.new_combat_action("melee"))
			actor._apply_phantom_step_during_dash()
			var base_ratio: float = [0.56, 0.72, 0.88, 0.88][picks - 1]
			var ratio: float = [0.56, 0.72, 0.88, 1.188][picks - 1]
			var raw := int(ceil(21.0 * base_ratio))
			if picks == 4:
				raw = int(raw * 1.35)
			var expected := int(round((raw + 16.0 * ratio) * (1.15 * 1.25 if percentages else 1.0)))
			var label := "Learned Phantom picks%d percentages=%s" % [picks, percentages]
			_check(actor.phantom_step_damage == raw and is_equal_approx(actor.phantom_step_damage_ratio, ratio), label + ": ordinary acquisition preserves ceil/Prismatic rounding")
			_check(_damage(target) == expected, label + ": actual Dash contact scales conditional Boons from its analytic ratio")
			_check(target.is_slowed() and target.hits.size() == 1, label + ": original contact and Slow remain single delivery")
			_check(target.hits.size() == 1 and is_equal_approx(float(target.hits[0].context.damage_coefficient), ratio), label + ": delivered descriptor excludes the raw integer rounding remainder")
			_clear()

func _test_retort_damage_scaling() -> void:
	var actor := _actor()
	actor.damage = 21
	_learn(actor, "static_wake", 1) # Set up the real upgrade system.
	actor.first_strike_bonus_damage = 16
	actor.passive_iron_retort = true
	actor.iron_retort_brace_ready = true
	_target(Vector2(40.0, 0.0))
	var secondary := _target(Vector2(-10.0, 0.0))
	actor._perform_melee_attack(Vector2.RIGHT, {"damage": 29, "damage_coefficient": 1.37})
	var label := "Retort preserves the Attack's analytic coefficient through its rounded shockwave"
	_check(secondary.hits.size() == 1 and secondary.hits[0].context.attack_type == "iron_retort_shockwave", label + ": actual brace releases one wave behind the melee cone")
	if secondary.hits.size() == 1:
		_check(is_equal_approx(float(secondary.hits[0].context.damage_coefficient), 1.37 * 1.8 * 0.55), label)
		_check(_damage(secondary) == int(round(round(round(29.0 * 1.8) * 0.55) + 16.0 * 1.37 * 1.8 * 0.55)), label + ": conditional Damage uses that exact inherited multiplier")
	_clear()

func _test_fixed_farline_damage() -> void:
	for picks in [3, 4]:
		for marked in [false, true]:
			var actor := _actor()
			actor.damage = 21
			_learn(actor, "farline_volley", picks)
			actor.first_strike_bonus_damage = 16
			var target := _target()
			if marked:
				_learn(actor, "eclipse_mark", 1)
				actor.DAMAGEABLE.apply_mark(target, "eclipse_mark", 0.15, 4.0, 1, actor.new_combat_action("melee"))
			actor._farline_volley_current_stacks = actor.farline_volley_stack_cap
			var raw := int(round((3.0 * 8.0 if picks == 4 else 2.0 * 5.0) * 0.45))
			var scope := actor._begin_effect_scope("dash", actor.new_combat_action("dash"))
			actor._consume_or_reset_farline_volley_for_dash()
			actor.DAMAGEABLE.end_interaction_scope(scope)
			var label := "Farline picks%d marked=%s" % [picks, marked]
			_check(_damage(target) == int(round(raw * (1.15 if marked else 1.0))), label + ": fixed Burst ignores conditional Damage additions but retains percentage vulnerability")
			_check(target.hits.size() == 1 and float(target.hits[0].context.damage_coefficient) == 0.0, label + ": actual Dash spender has no invented Damage-stat component")
			_check(actor._farline_volley_current_stacks == 0, label + ": ordinary bank reset remains unchanged")
			_clear()


func _test_sustained_conditions() -> void:
	# Eight seconds includes repeated exits, reentries, dash roots and ribbon
	# replacements. A 120px/s crossing spends exactly 1/3 second inside this
	# 40px-wide Field; the oracle integrates that independently of tick cadence.
	for fps in [30, 60, 120, 0]:
		for overlapping in [1, 2]:
			for snare_picks in [0, 1, 2, 4]:
				for moving in [false, true]:
					var actor := _actor()
					actor.damage = 20
					actor.first_strike_bonus_damage = 5
					if snare_picks > 0:
						_learn(actor, "hunters_snare", snare_picks)
					var target := _target(Vector2(0.0, -60.0) if moving else Vector2.ZERO)
					target.apply_slow(1000.0, 0.8)
					var time := 0.0
					var tick_index := 0
					var contact_seconds := 0.0
					for second in range(8):
						for ribbon in range(overlapping):
							_ribbon(actor)
						var end := float(second + 1)
						while time < end - 0.000000001:
							var delta: float = 1.0 / fps if fps > 0 else [0.4, 0.37, 0.23][tick_index % 3]
							delta = minf(delta, end - time)
							time += delta
							tick_index += 1
							var old_y := float(target.global_position.y)
							if moving:
								var phase := fmod(time, 2.0)
								target.global_position.y = -60.0 + 120.0 * phase if phase <= 1.0 else 180.0 - 120.0 * phase
							contact_seconds += _band_exposure(old_y, float(target.global_position.y), delta)
							actor.static_wake_controller.tick(delta)
					var exposure := 8.0 / 3.0 if moving else 8.0
					var snare_ratio: float = (0.45 if snare_picks == 4 else 0.15 + 0.05 * snare_picks) if snare_picks >= 2 else 0.0
					var expected := 8.0 * 4.5 * contact_seconds * (25.0 / 20.0) * (1.0 + snare_ratio)
					var label := "%dfps/%d overlap/Snare%d/%s" % [fps, overlapping, snare_picks, "reentry" if moving else "stationary"]
					_check(absf(contact_seconds - exposure) < 0.000001, label + ": actual Vector2 trajectory matches the analytical exposure")
					_check(_damage(target) == int(floor(expected + 0.000000001)), "%s: sustained scaled damage is exact (%d vs %.9f)" % [label, _damage(target), expected])
					_check(absf(float(_damage(target)) + _fraction(target) - expected) < 0.00002, label + ": host remainder conserves exposure across repeated Dash roots")
					_check(target.hits.size() == (16 if moving else 32), label + ": one due packet per nonempty damage window")
					_check(actor.static_wake_controller.ribbons.size() <= 2 and target.get_node("SharedCombatStatus")._remainders.size() == 1, label + ": overlapping ribbons share bounded owner/source state")
					_clear()

func _band_exposure(start_y: float, end_y: float, delta: float) -> float:
	# Independent 1D oracle uses the actual float32 actor positions. A hitch
	# endpoint such as 32.4px can be slightly short of the mathematical triangle;
	# its unspent fraction must remain credited rather than being discarded.
	var step := end_y - start_y
	if absf(step) < 0.000000001:
		return delta if absf(start_y) <= 20.0 else 0.0
	var first := (-20.0 - start_y) / step
	var second := (20.0 - start_y) / step
	return delta * maxf(0.0, minf(1.0, maxf(first, second)) - maxf(0.0, minf(first, second)))
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
	_check(_damage(target) == 9, "Closed radius includes an enemy center exactly on a round cap")
	_clear()

func _test_deadlines_and_lifetime() -> void:
	var actor := _actor()
	var target := _target()
	actor.static_wake_lifetime = 0.1
	_ribbon(actor)
	actor.static_wake_controller.tick(0.1)
	_check(_damage(target) == 0 and actor.static_wake_controller.ribbons.is_empty(), "Expiry retires geometry without inventing an early tick")
	actor.static_wake_controller.tick(0.15)
	_check(_damage(target) == 3 and is_equal_approx(_fraction(target), 0.6), "Pre-expiry .1s exposure retains Wake floor carry at the original .25s deadline")
	_ribbon(actor)
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == 7 and is_equal_approx(_fraction(target), 0.2), "Reentry carries fractional damage across ribbons")
	actor.static_wake_controller.tick(0.75)
	_check(_damage(target) == 7, "Expired ribbons accrue no extra damage in later windows")
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
	_check(_damage(target) == 9, "Replacement and overlapping reentry preserve the first damage deadline")
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
	_check(_damage(target) == 14 and is_equal_approx(_fraction(target), 0.4), "A final partial lifetime accrues .4s even when the last tick spans expiry")
	_clear()

func _test_context_and_slow() -> void:
	var actor := _actor()
	var target := _target()
	actor.static_wake_stacks = 3
	_learn(actor, "hunters_snare", 2)
	var action := _ribbon(actor)
	_ribbon(actor)
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == 9 and target.is_slowed(), "First Wake tick uses pre-Slow Snare eligibility, then applies level3 Slow")
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == 20 and is_equal_approx(_fraction(target), 0.25), "Mapped level2 Snare multiplies the second already-slowed tick by 1.25 once despite overlap")
	var context: Dictionary = target.hits[0].context
	_check(not context.get("secondary", false) and not context.get("is_ground_attack", false), "Wake retains existing primary directional-defense classification")
	_check(int(context.interaction.traits) == (REGISTRY.HIT | REGISTRY.DASH | REGISTRY.ELECTRIC), "Wake hit has Hit, Dash and Electric properties")
	_check(context.interaction.seq == action.seq and target.hits[1].context.interaction.seq == action.seq, "All ticks retain the actual originating Dash identity")
	_check(context.attack_origin == Vector2.ZERO, "Damage origin is the nearest actual traveled path contact")
	_check(is_equal_approx(float(context.raw_amount), 9.0) and is_equal_approx(float(context.damage_coefficient), 9.0 / actor.damage), "Wake carries reduced raw exposure and its exact Damage coefficient")
	_check(REGISTRY.effect_forms(String(context.interaction.source)) == ["Field"] and not REGISTRY.is_attack_hit(String(context.interaction.source)), "Electric Field damage does not perform a deliberate Attack")
	var ledger: Dictionary = actor.combat_interactions._roots.get(action.seq, {})
	_check(not ledger.is_empty() and not bool(ledger.discharged) and actor.storm_crown_hit_counter == 0, "Shared damage ledger does not enable an unlearned Storm Crown")
	_clear()
	actor = _actor()
	target = _target()
	actor.static_wake_lifetime = 0.01
	actor.static_wake_damage = 1
	_learn(actor, "hunters_snare", 2)
	target.apply_slow(2.0, 0.8)
	_ribbon(actor)
	actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == 0 and is_equal_approx(_fraction(target), 0.05625), "Tiny exposure scales Snare with the packet, not a whole flat bonus")
	for repeat in range(9):
		_ribbon(actor)
		actor.static_wake_controller.tick(0.25)
	_check(_damage(target) == 0 and is_equal_approx(_fraction(target), 0.5625), "Ten tiny exposures conserve their total in the host fractional ledger")
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
	_check(_damage(target) == 72, "A huge hitch accrues only the ribbon's actual two-second lifetime")
	_check(counted.settlement_calls == 8, "Expired idle windows fast-forward without thousands of empty callbacks")
	_ribbon(actor)
	counted.tick(0.25)
	_check(_damage(target) == 81, "Arithmetic fast-forward retains the established quarter-second phase on reentry")
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
	_check(_damage(first) == 9 and _damage(second) == 0, "Damage callback cancellation stops later windows and later targets safely")
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
