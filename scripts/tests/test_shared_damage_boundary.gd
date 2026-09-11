extends "res://scripts/tests/test_combat_interactions.gd"
## Real Damageable/EnemyBase/controller interactions: target conditions belong
## to the host boundary, and only accepted direct contacts commit reactions.

class SharedActor extends Actor:
	var passive_effigy_command: bool = false
	var damage: int = 100
	var max_health: int = 100
	var current_health: int = 100
	var first_strike_bonus_damage: int = 0
	var bloodpact_bonus_damage: int = 0
	var severing_edge_bonus_damage: int = 0
	var reward_hunters_snare: bool = false
	var hunters_snare_stacks: int = 0
	var hunters_snare_bonus_ratio: float = 0.2
	var reward_wraithstep: bool = true
	var wraithstep_mark_bonus_ratio: float = 0.15
	var wraithstep_mark_duration: float = 2.5
	var reward_eclipse_mark: bool = true
	var eclipse_mark_bonus_ratio: float = 0.25
	var eclipse_mark_duration: float = 4.0
	var reward_dread_resonance: bool = true
	var dread_resonance_damage_ratio_per_stack: float = 0.02
	var dread_resonance_max_stacks: int = 8
	var void_echo_damage: int = 0
	var in_owned_field: bool = false
	var mission_multiplier: float = 1.0
	var prepare_bonus: float = 0.0
	var spent_bonus: float = 0.0
	var prepare_calls: int = 0
	var attack_events: Array[Dictionary] = []
	var damage_events: Array[Dictionary] = []
	var apply_dread_on_hit: bool = false
	var child_on_hit: Node2D
	var child_emitted: bool = false
	func get_current_health() -> int:
		return current_health
	func get_max_health() -> int:
		return max_health
	func _shared_owned_field_contains(_target: Node2D) -> bool:
		return in_owned_field
	func _shared_mission_damage_multiplier() -> float:
		return mission_multiplier
	func _prepare_shared_attack_damage(_target: Node2D, descriptor: Dictionary, _action: Dictionary) -> Dictionary:
		prepare_calls += 1
		return {"raw_amount": float(descriptor.raw_amount) + prepare_bonus, "damage_coefficient": float(descriptor.damage_coefficient), "pending_bonuses": {"bonus": prepare_bonus}}
	func _on_shared_attack_hit(event: Dictionary) -> void:
		attack_events.append(event.duplicate(true))
		spent_bonus += float(event.pending_bonuses.get("bonus", 0.0))
		var target: Variant = event.target.get_ref()
		if apply_dread_on_hit and is_instance_valid(target):
			DAMAGEABLE.apply_mark(target, "dread_resonance", 0.1, 3.0, player_id, event.interaction)
			DAMAGEABLE.add_dread_stack(target, player_id, dread_resonance_max_stacks, event.interaction)
		if is_instance_valid(child_on_hit) and not child_emitted:
			child_emitted = true
			DAMAGEABLE.apply_damage(child_on_hit, 10, {"attack_type": "rupture_wave", "raw_amount": 10.0, "damage_coefficient": 0.1}, player_id)
	func _on_shared_damage(event: Dictionary) -> void:
		damage_events.append(event.duplicate(true))

class BlockedEnemy extends Enemy:
	var blocked: bool = true
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		if not blocked:
			super.take_damage(amount, context)

var owner: SharedActor

func setup(level: int = 1) -> void:
	super.setup(level)
	actor.free()
	owner = SharedActor.new()
	owner.reward_storm_crown = false
	world.add_child(owner)
	actor = owner

func packet(target: Enemy, raw: float, coefficient: float, source: String = "melee", action: Dictionary = {}) -> bool:
	if action.is_empty():
		action = owner.combat_interactions.begin_action("attack")
	return DAMAGEABLE.apply_damage(target, maxi(0, int(round(raw))) if is_finite(raw) else 0, REGISTRY.damage_context(action, source, {"raw_amount": raw, "damage_coefficient": coefficient}), owner.player_id)

func _run() -> void:
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)):
		push_error("Use the isolated regression runner")
		quit(1)
		return
	_test_independent_mark_windows()
	_test_prestate_and_dread()
	_test_boon_coefficients_and_fractions()
	_test_wake_floor()
	_test_conditional_modifiers()
	_test_accepted_attack_boundary()
	_test_child_and_echo_descriptors()
	_test_status_network_order()
	_test_compact_status_and_protocol()
	_test_owner_scope_and_cleanup()
	_test_status_parent_pause()
	_test_read_only_reaction_claims()
	await process_frame
	print("[SharedDamageBoundary] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_independent_mark_windows() -> void:
	setup()
	var target := enemy(Vector2.ZERO)
	var action := owner.combat_interactions.begin_action("dash")
	check(DAMAGEABLE.apply_mark(target, "wraithstep", 9.0, 90.0, 1, action), "Host accepts an owned Mark and resolves mapped values")
	check(is_equal_approx(float(DAMAGEABLE.status_snapshot(target, 1).mark_ratio), 0.15), "Claimed strength/duration cannot replace authoritative mapped Mark values")
	var state := DAMAGEABLE._target_status(target)
	owner.eclipse_mark_duration = 1.0
	check(DAMAGEABLE.apply_mark(target, "eclipse_mark", 0.25, 1.0, 1, action), "Another source keeps an independent Mark window")
	check(is_equal_approx(float(state.snapshot(1).mark_ratio), 0.25), "Only the strongest active Mark amplifies damage")
	state.advance(0.6)
	DAMAGEABLE.apply_mark(target, "wraithstep", 0.15, 2.5, 1, action)
	state.advance(0.5)
	check(is_equal_approx(float(state.snapshot(1).mark_ratio), 0.15), "Refreshing weaker Mark does not extend the stronger source")
	var ally := SharedActor.new()
	ally.player_id = 2
	ally.wraithstep_mark_bonus_ratio = 0.2
	world.add_child(ally)
	var ally_action := ally.combat_interactions.begin_action("dash")
	check(DAMAGEABLE.apply_mark(target, "wraithstep", 0.2, 2.5, 2, ally_action), "Another owner keeps an independent application of the same source")
	check(is_equal_approx(float(state.snapshot(1).mark_ratio), 0.2) and state.marks.size() == 2, "All owners benefit from the shared strongest window without stacking applications")
	owner.combat_interactions.cancel()
	check(not DAMAGEABLE.apply_mark(target, "wraithstep", 0.9, 20.0, 1, action), "Cancelled actions cannot apply a new Mark")
	check(not DAMAGEABLE.apply_mark(target, "wraithstep", 0.15, 2.0, 1, ally_action), "A forged owner cannot apply another participant's Mark")
	teardown()

func _test_prestate_and_dread() -> void:
	setup()
	owner.apply_dread_on_hit = true
	var target := enemy(Vector2.ZERO)
	packet(target, 100.0, 1.0)
	check(target.hits[0].amount == 100 and owner.attack_events[0].pre_mark_ratio == 0.0 and owner.attack_events[0].pre_dread_stacks == 0, "First contact uses pre-Mark/pre-Dread state")
	var shared_action := owner.combat_interactions.begin_action("attack")
	packet(target, 100.0, 1.0, "melee", shared_action)
	packet(target, 100.0, 1.0, "razor_wind", shared_action)
	check(target.hits[1].amount == 112 and target.hits[2].amount == 114, "Later damage sees existing Mark and already-earned Dread")
	check(owner.attack_events.size() == 2 and DAMAGEABLE.status_snapshot(target, 1).dread_stacks == 2, "Melee and Wind cannot grant two Dread stacks on one foe in one Attack")
	var state := DAMAGEABLE._target_status(target)
	state.advance(4.0)
	check(state.snapshot(1).mark_ratio == 0.0 and state.snapshot(1).dread_stacks == 2, "Mark expiry preserves accumulated Dread")
	var another := enemy(Vector2(30, 0))
	packet(another, 100.0, 1.0)
	check(state.snapshot(1).dread_stacks == 2, "Changing attack targets preserves each foe's Dread")
	packet(target, 100.0, 1.0)
	check(target.hits.back().amount == 100 and state.snapshot(1).dread_stacks == 3, "Reapplying Mark does not retroactively amplify the renewing event")
	check(state.snapshot(2).dread_stacks == 0 and is_equal_approx(float(state.snapshot(2).mark_ratio), 0.1), "A teammate receives Mark without borrowing Dread stacks")
	for index in range(20):
		packet(target, 1.0, 0.01)
	check(state.snapshot(1).dread_stacks == 8, "Dread remains bounded at its authoritative mapped cap")
	world._world_multiplayer_sync_state.current_room_sync_id += 1
	check(state.snapshot(1).dread_stacks == 0 and state.snapshot(1).mark_ratio == 0.0, "Room identity changes clear enemy temporary status")
	teardown()

func _test_boon_coefficients_and_fractions() -> void:
	setup()
	owner.first_strike_bonus_damage = 16
	owner.bloodpact_bonus_damage = 9
	owner.current_health = 50
	var whole := enemy(Vector2.ZERO)
	var split := enemy(Vector2(30, 0))
	packet(whole, 10.0, 0.1, "static_wake")
	var action := owner.combat_interactions.begin_action("dash")
	for index in range(20):
		packet(split, 0.5, 0.005, "static_wake", action)
	check(whole.get_current_health() == split.get_current_health() and whole.get_current_health() == 99987, "Conditional Boons scale with coefficient and preserve total fractional split damage")
	var zero := enemy(Vector2(60, 0))
	packet(zero, 0.0, 0.1, "static_wake")
	check(zero.get_current_health() == 99997, "Zero raw damage can resolve positive coefficient-scaled Boon damage without forcing every packet to one")
	owner.first_strike_bonus_damage = 0
	owner.bloodpact_bonus_damage = 0
	var tiny := enemy(Vector2(90, 0))
	for index in range(10):
		packet(tiny, 0.1, 0.001, "static_wake")
	check(tiny.get_current_health() == 99999 and tiny.hits.size() == 1, "Sub-integer continuous packets carry fractions and emit only positive accepted damage")
	check(not packet(tiny, NAN, 1.0) and not packet(tiny, 10.0, INF), "Malformed raw descriptors cannot enter authoritative damage")
	owner.severing_edge_bonus_damage = 14
	var low := enemy(Vector2(120, 0))
	low.health_state.current_health = 54999
	packet(low, 10.0, 0.5, "returning_crescent")
	check(low.get_current_health() == 54982, "Severing applies to projectile coefficient rather than only direct attacks")
	teardown()

func _test_conditional_modifiers() -> void:
	setup()
	owner.reward_hunters_snare = true
	owner.hunters_snare_stacks = 1
	var direct := enemy(Vector2.ZERO)
	var projectile := enemy(Vector2(30, 0))
	direct.apply_slow(5.0, 0.5)
	projectile.apply_slow(5.0, 0.5)
	packet(direct, 100.0, 1.0)
	packet(projectile, 100.0, 1.0, "returning_crescent")
	check(direct.hits[0].amount == 120 and projectile.hits[0].amount == 100, "Snare level one distinguishes Attack damage from generated Projectile damage")
	owner.hunters_snare_stacks = 2
	owner.hunters_snare_bonus_ratio = 0.25
	packet(projectile, 100.0, 1.0, "static_wake")
	check(projectile.hits.back().amount == 125, "Snare level two accepts every qualifying damage source")
	owner.void_echo_damage = 40
	owner.in_owned_field = true
	owner.mission_multiplier = 1.5
	packet(projectile, 100.0, 1.0, "returning_crescent")
	check(projectile.hits.back().amount == 225, "Snare, one owned-Field bonus and Mission multiplier each resolve once")
	owner.in_owned_field = false
	packet(projectile, 100.0, 1.0, "returning_crescent")
	check(projectile.hits.back().amount in [187, 188], "Leaving owned Fields removes Lacuna without changing remaining modifiers")
	teardown()

func _test_accepted_attack_boundary() -> void:
	setup()
	owner.prepare_bonus = 30.0
	var blocked := BlockedEnemy.new()
	world.add_child(blocked)
	var action := owner.combat_interactions.begin_action("attack")
	packet(blocked, 100.0, 1.0, "melee", action)
	check(owner.spent_bonus == 0.0 and owner.attack_events.is_empty() and owner.damage_events.is_empty(), "Blocked damage cannot spend prepared bonuses or emit attack/damage reactions")
	owner.prepare_bonus = 0.0
	packet(blocked, 0.6, 0.006, "static_wake")
	check(DAMAGEABLE._target_status(blocked)._remainders.get("1:static_wake", 0.0) == 0.0, "Rejected positive packet cannot commit its fractional remainder")
	owner.prepare_bonus = 30.0
	check(not owner.combat_interactions.has_attack_hit(action, blocked.get_instance_id()), "Blocked contacts do not claim the accepted victim allowance")
	blocked.blocked = false
	packet(blocked, 100.0, 1.0, "melee", action)
	check(blocked.hits.back().amount == 130 and owner.spent_bonus == 30.0, "First accepted contact commits its prepared bonus once")
	packet(blocked, 100.0, 1.0, "razor_wind", action)
	check(owner.spent_bonus == 30.0 and owner.attack_events.size() == 1 and owner.damage_events.size() == 2, "Repeated foe contacts retain damage without replaying attack-hit reactions")
	var next := enemy(Vector2(30, 0))
	packet(next, 100.0, 1.0, "blast_drive", action)
	check(owner.attack_events.size() == 2 and owner.attack_events[0].first_attack_hit and not owner.attack_events[1].first_attack_hit, "One multi-foe Attack exposes separate victim contacts and one first-contact flag")
	for source in ["farline_volley_burst", "returning_crescent", "razor_orbit", "sovereigns_double"]:
		packet(next, 100.0, 1.0, source)
	check(owner.attack_events.size() == 2 and owner.damage_events.size() == 7, "Burst, Projectile, Orbit and Echo damage do not become attack-hit events")
	teardown()

func _test_child_and_echo_descriptors() -> void:
	setup()
	owner.first_strike_bonus_damage = 16
	owner.prepare_bonus = 30.0
	var parent := enemy(Vector2.ZERO)
	var child := enemy(Vector2(30, 0))
	owner.child_on_hit = child
	var action := owner.combat_interactions.begin_action("attack")
	packet(parent, 100.0, 1.0, "melee", action)
	check(parent.hits[0].amount == 146 and child.hits[0].amount == 12, "Synchronous generated damage resolves its own raw descriptor, not the parent's conditioned amount")
	check(owner.damage_events.size() == 2 and owner.damage_events[1].interaction.seq == action.seq and owner.attack_events.size() == 1, "Generated effects inherit scope without executing another Attack")
	owner.mission_multiplier = 2.0
	var echoed := enemy(Vector2(60, 0))
	var echo_context := REGISTRY.damage_context(REGISTRY.damage_context(action, "melee").interaction, "sovereigns_double", {"raw_amount": 55.0, "damage_coefficient": 0.55})
	DAMAGEABLE.apply_damage(echoed, 55, echo_context, 1)
	check(echoed.hits[0].amount == 161, "Echo copies accepted unconditioned prepared damage then applies its actual target conditions and Mission once")
	check(owner.spent_bonus == 30.0 and owner.prepare_calls == 1, "Echo cannot prepare or spend the original Attack bonus again")
	var missed_action := owner.combat_interactions.begin_action("attack")
	var fallback := enemy(Vector2(90, 0))
	echo_context = REGISTRY.damage_context(REGISTRY.damage_context(missed_action, "melee").interaction, "sovereigns_double", {"raw_amount": 55.0, "damage_coefficient": 0.55})
	DAMAGEABLE.apply_damage(fallback, 55, echo_context, 1)
	check(fallback.hits[0].amount == 128, "An original miss leaves the Echo's own scaled shape descriptor intact")
	check(DAMAGEABLE.current_interaction_context().is_empty(), "Nested callbacks and Echo resolution leave no global scope")
	teardown()

func _test_status_network_order() -> void:
	setup()
	var target := enemy(Vector2.ZERO)
	var state := DAMAGEABLE._target_status(target, true)
	state.apply_mark(1, "wraithstep", 0.2, 3.0)
	state.add_dread(1, 8, {"epoch": 1, "seq": 1})
	var payload: Dictionary = state.network_state()
	var remote := enemy(Vector2(30, 0))
	var mirror := DAMAGEABLE._target_status(remote, true)
	check(mirror.apply_network_state(payload) and mirror.snapshot(1) == state.snapshot(1), "Complete status snapshots preserve independent Mark and owner Dread")
	check(not mirror.apply_network_state(payload), "Equal status packets cannot extend a Mark")
	var invalid := payload.duplicate(true)
	invalid.q += 1
	invalid.m[0][2] = NAN
	check(not mirror.apply_network_state(invalid) and mirror.snapshot(1) == state.snapshot(1), "Malformed status packet rejects atomically before modifying live state")
	invalid = payload.duplicate(true)
	invalid.q += 1
	invalid.r += 1
	check(not mirror.apply_network_state(invalid), "Wrong-room status snapshots cannot revive prior enemy state")
	state.clear()
	check(mirror.apply_network_state(state.network_state()) and mirror.snapshot(1).mark_ratio == 0.0 and mirror.snapshot(1).dread_stacks == 0, "Ordered empty status snapshot clears both gameplay and presentation state")
	check(not mirror.apply_network_state(payload), "Late pre-clear snapshot cannot resurrect status")
	check(not DAMAGEABLE.apply_status_network_state(target, payload), "A host cannot import replica status as authoritative gameplay")
	teardown()

func _test_owner_scope_and_cleanup() -> void:
	setup()
	var ally := SharedActor.new()
	ally.player_id = 2
	ally.reward_storm_crown = false
	world.add_child(ally)
	var first := enemy(Vector2(40, 0))
	var child := enemy(Vector2(70, 0))
	var origin := Vector2(10, 0)
	var scopes: Array[Dictionary] = []
	first.callback = func() -> void:
		scopes.append(DAMAGEABLE.current_interaction_context())
		DAMAGEABLE.apply_damage(child, 10, {"attack_type": "rupture_wave", "raw_amount": 10.0, "damage_coefficient": 0.1})
	var action := ally.combat_interactions.begin_action("attack")
	DAMAGEABLE.apply_damage(first, 100, REGISTRY.damage_context(action, "melee", {"raw_amount": 100.0, "damage_coefficient": 1.0, "attack_origin": origin}), 2)
	check(world.recorded.size() == 2 and int(world.recorded[0].owner) == 2 and int(world.recorded[1].owner) == 2, "Host-created descendants retain the accepted joiner owner when source argument is omitted")
	check(scopes[0].owner == 2 and scopes[0].attack_origin == origin and scopes[0].damage_direction == Vector2.RIGHT, "Synchronous accepted scope carries actual origin/direction for kill effects")
	check(ally.attack_events.size() == 1 and ally.damage_events.size() == 2 and owner.damage_events.is_empty(), "Joiner reactions and accepted damage never migrate to host counters")
	var local_action := owner.combat_interactions.begin_action("dash")
	DAMAGEABLE.apply_mark(first, "wraithstep", 0.15, 2.5, 1, local_action)
	DAMAGEABLE.apply_mark(first, "eclipse_mark", 0.25, 4.0, 2, action)
	var state := DAMAGEABLE._target_status(first)
	state.add_dread(1, 8, {"epoch": 1, "seq": 7})
	state.add_dread(2, 8, {"epoch": 1, "seq": 7})
	DAMAGEABLE.cancel_owner(1)
	check(state.marks.size() == 1 and state.snapshot(1).dread_stacks == 0 and state.snapshot(2).dread_stacks == 1 and is_equal_approx(float(state.snapshot(1).mark_ratio), 0.25), "Owner cleanup removes only departing player's Mark, Dread and fractional state")
	first.health_state.current_health = 0
	state.advance(0.01)
	check(state.marks.is_empty() and state.dread.is_empty(), "Dead target retires all temporary shared status")
	teardown()

func _test_compact_status_and_protocol() -> void:
	setup()
	var state := DAMAGEABLE._target_status(enemy(Vector2.ZERO), true)
	for peer_id in range(1, 5):
		for source in state.MARK_SOURCES:
			state.apply_mark(peer_id, source, 0.15 + peer_id * 0.01, 3.25)
		state.add_dread(peer_id, 15, {"epoch": 1, "seq": 1})
	var bytes: PackedByteArray = state.network_packet()
	var expected_marks: int = 4 * state.MARK_SOURCES.size()
	check(bytes.size() <= 480 and state.marks.size() == expected_marks, "All four owners and all six current/legacy Mark sources fit the compact bounded status packet")
	var replica := DAMAGEABLE._target_status(enemy(Vector2(100, 0)), true)
	check(replica.apply_network_packet(bytes) and replica.marks.size() == expected_marks and replica.dread.size() == 4, "Packed status roundtrip preserves every independent owner/source")
	check(is_equal_approx(float(replica.snapshot(4).mark_ratio), 0.19), "Status precision survives native packed encoding without generic float snapping")
	check(not replica.apply_network_packet(bytes) and not replica.apply_network_packet(bytes.slice(0, bytes.size() - 1)), "Equal and truncated compact snapshots reject atomically")
	var broadcaster := preload("res://scripts/core/enemy_state_sync_broadcaster.gd").new(world)
	check(broadcaster._quantize_runtime_state_for_network({"shared_status": bytes}).get("shared_status") == bytes, "Runtime quantization preserves packed status data byte for byte")
	var full := {"enemy_id": 1234, "position": Vector2(800, 400), "facing_angle": 0.5, "health": 12000, "runtime_state_delta": {"shared_status": bytes, "custom": {"large": "x".repeat(2000)}}}
	var fitted: Dictionary = broadcaster._fit_state_to_size_limit(full, 480)
	check(fitted.runtime_state_delta.get("shared_status") == bytes and not fitted.runtime_state_delta.has("custom"), "Crowded room payload trimming preserves complete status while removing disposable custom visuals")
	check(broadcaster.estimate_variant_size_bytes(bytes) >= bytes.size() and var_to_bytes([fitted]).size() < 1100, "Batch accounting includes actual packed bytes and a full four-owner status stays below the network budget")
	state.clear()
	check(replica.apply_network_packet(state.network_packet()) and replica.marks.is_empty() and replica.dread.is_empty(), "Repeated ordered clear packets remove all mirrored status")
	var lobby := preload("res://scripts/lobby_controller.gd")
	var compatible := {1: {"combat_protocol": lobby.COMBAT_PROTOCOL_VERSION}, 2: {"combat_protocol": lobby.COMBAT_PROTOCOL_VERSION}}
	check(lobby._roster_protocol_matches(compatible, [1, 2]), "Matching combat protocols permit the existing lobby path")
	compatible[2].erase("combat_protocol")
	check(not lobby._roster_protocol_matches(compatible, [1, 2]), "Legacy missing combat protocol cannot launch a revised combat run")
	compatible[2].combat_protocol = lobby.COMBAT_PROTOCOL_VERSION + 1
	check(not lobby._roster_protocol_matches(compatible, [1, 2]), "A different combat protocol cannot enter the revised run")
	compatible[2].combat_protocol = lobby.COMBAT_PROTOCOL_VERSION
	check(not lobby._roster_protocol_matches(compatible, [1, 2, 3]), "Connected but unannounced peers still block launch")
	teardown()

func _test_wake_floor() -> void:
	setup()
	var target := enemy(Vector2.ZERO)
	var action := owner.combat_interactions.begin_action("dash")
	var context := REGISTRY.damage_context(action, "static_wake", {"raw_amount": 9.6, "damage_coefficient": 0.096, "fractional_rounding": "floor"})
	DAMAGEABLE.apply_damage(target, 9, context, 1)
	check(target.get_current_health() == 99991 and is_equal_approx(float(DAMAGEABLE._target_status(target)._remainders.get("1:static_wake")), 0.6), "Wake retains its original floor and positive fractional carry at the shared boundary")
	DAMAGEABLE.apply_damage(target, 9, context, 1)
	check(target.get_current_health() == 99981, "Subsequent Wake packet consumes only its accumulated whole damage")
	var direct := enemy(Vector2(50, 0))
	DAMAGEABLE.apply_damage(direct, 9, REGISTRY.damage_context(action, "melee", {"raw_amount": 9.6, "damage_coefficient": 0.096, "fractional_rounding": "floor"}), 1)
	check(direct.get_current_health() == 99990, "An unrelated source cannot change its established rounding by copying Wake's option")
	var precise := enemy(Vector2(100, 0))
	var tiny := REGISTRY.damage_context(action, "static_wake", {"raw_amount": 0.3, "damage_coefficient": 0.003, "fractional_rounding": "floor"})
	for index in range(10):
		DAMAGEABLE.apply_damage(precise, 0, tiny, 1)
	check(precise.get_current_health() == 99997 and float(DAMAGEABLE._target_status(precise)._remainders.get("1:static_wake")) >= 0.0, "Wake preserves its numerical tolerance at exact accumulated whole damage without a negative carry")
	teardown()

func _test_status_parent_pause() -> void:
	setup()
	var target := enemy(Vector2.ZERO)
	target.set_physics_process(true)
	var status := DAMAGEABLE._target_status(target, true)
	status.apply_mark(1, "wraithstep", 0.15, 2.5)
	status.add_dread(1, 8, {"epoch": 1, "seq": 1})
	status._physics_process(0.25)
	check(is_equal_approx(float(status.marks["1:wraithstep"].left), 2.25), "Live enemy status clock advances with its parent's active combat physics")
	var pause := preload("res://scripts/core/combat_phase_coordinator.gd").new()
	pause.set_combat_paused(null, self, true)
	status._physics_process(4.0)
	check(not target.is_physics_processing() and status.snapshot(1).mark_ratio > 0.0 and is_equal_approx(float(status.marks["1:wraithstep"].left), 2.25), "Actual combat pause freezes child Mark expiry without pausing the whole SceneTree")
	pause.set_combat_paused(null, self, false)
	status._physics_process(2.3)
	check(status.snapshot(1).mark_ratio == 0.0 and status.snapshot(1).dread_stacks == 1, "Restored combat resumes Mark expiry while retaining non-timed Dread stacks")
	target.set_physics_process(false)
	teardown()

func _test_read_only_reaction_claims() -> void:
	setup()
	var action := owner.combat_interactions.begin_action("attack")
	check(not owner.combat_interactions.has_reaction(action, "oath_attack_spent") and owner.combat_interactions._roots.is_empty(), "A reaction query never creates or spends a root allowance")
	check(owner.combat_interactions.claim_reaction(action, "oath_attack_spent") and owner.combat_interactions.has_reaction(action, "oath_attack_spent"), "Read-only reaction query observes an accepted explicit root claim")
	var other := owner.combat_interactions.begin_action("attack")
	check(not owner.combat_interactions.has_reaction(other, "oath_attack_spent"), "An interleaved later attack cannot inherit another root's spent resource")
	owner.combat_interactions.cancel()
	check(not owner.combat_interactions.has_reaction(action, "oath_attack_spent"), "Retired epochs cannot expose prior resource claims")
	teardown()
