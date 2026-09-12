extends SceneTree
## Actual accepted damage, descendant descriptors and fractional carry.

const SHARED := preload("res://scripts/tests/test_shared_damage_boundary.gd")
const BASE := preload("res://scripts/tests/test_combat_interactions.gd")
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const REGISTRY := preload("res://scripts/shared/combat_interaction_registry.gd")
var owner: SHARED.SharedActor
var world: BASE.TestWorld
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func setup() -> void:
	world = BASE.TestWorld.new()
	root.add_child(world)
	current_scene = world
	EnemyReplicationService.world_generator = world
	owner = SHARED.SharedActor.new()
	owner.reward_storm_crown = false
	world.add_child(owner)
	owner.farshot_bonus_damage = 10

func teardown() -> void:
	check(DAMAGEABLE.current_interaction_context().is_empty() and DAMAGEABLE._damage_depth == 0 and DAMAGEABLE._pending_interaction_hits.is_empty(), "All accepted-damage scopes retire")
	EnemyReplicationService.world_generator = null
	current_scene = null
	world.free()
	world = null
	owner = null

func enemy(position: Vector2) -> BASE.Enemy:
	var target := BASE.Enemy.new()
	world.add_child(target)
	target.position = position
	return target

func packet(target: BASE.Enemy, raw: float, coefficient: float, source: String = "melee", action: Dictionary = {}) -> bool:
	if action.is_empty():
		action = owner.combat_interactions.begin_action("attack")
	if source == "sovereigns_double":
		action = REGISTRY.damage_context(action, "melee").interaction
	return DAMAGEABLE.apply_damage(target, maxi(0, int(round(raw))), REGISTRY.damage_context(action, source, {"raw_amount": raw, "damage_coefficient": coefficient}), owner.player_id)

func _run() -> void:
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)):
		quit(1)
		return
	_test_range_boundary()
	_test_impact_positions()
	_test_actual_target_descendants()
	_test_fractional_sources()
	_test_owner_and_rejection()
	await process_frame
	print("[Farshot] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_range_boundary() -> void:
	setup()
	for offset in [Vector2(159.999, 0), Vector2(160, 0), Vector2(160.001, 0), Vector2(-160, 0), Vector2(96, 128), Vector2.ZERO]:
		var target := enemy(offset)
		var qualifies: bool = offset.length_squared() >= 25600.0
		packet(target, 100, 1, "returning_crescent")
		check(target.hits.back().amount == (110 if qualifies else 100), "Body-center distance is inclusive at 160 in every direction: %s" % offset)
	teardown()

func _test_impact_positions() -> void:
	setup()
	var action := owner.combat_interactions.begin_action("attack")
	var target := enemy(Vector2(200, 0))
	var context := REGISTRY.damage_context(action, "returning_crescent", {"raw_amount": 100.0, "damage_coefficient": 1.0, "attack_origin": Vector2.ZERO})
	owner.position = Vector2(100, 0)
	DAMAGEABLE.apply_damage(target, 100, context, 1)
	check(target.hits.back().amount == 100, "Moving closer after launch removes Farshot at impact")
	owner.position = Vector2(400, 0)
	DAMAGEABLE.apply_damage(target, 100, context, 1)
	check(target.hits.back().amount == 110, "Moving away after launch enables Farshot on the same delayed descriptor")
	target.position = Vector2(250, 0)
	DAMAGEABLE.apply_damage(target, 100, context, 1)
	check(target.hits.back().amount == 100, "Target movement is also evaluated at impact")
	owner.position = Vector2.ZERO
	target.position = Vector2(200, 0)
	context = REGISTRY.damage_context(owner.combat_interactions.begin_action("attack"), "melee", {"raw_amount": 100.0, "damage_coefficient": 1.0, "attack_origin": Vector2(195, 0)})
	DAMAGEABLE.apply_damage(target, 100, context, 1)
	check(target.hits.back().amount == 110, "Effigy strike near the foe qualifies from the owning body")
	owner.position = Vector2(195, 0)
	context.attack_origin = Vector2.ZERO
	DAMAGEABLE.apply_damage(target, 100, context, 1)
	check(target.hits.back().amount == 100, "A distant effigy origin cannot substitute for a nearby owning body")
	teardown()

func _test_actual_target_descendants() -> void:
	setup()
	var parent := enemy(Vector2(200, 0))
	var child := enemy(Vector2(100, 0))
	owner.child_on_hit = child
	packet(parent, 100.0, 1.0, "melee")
	check(parent.hits[0].amount == 110 and child.hits[0].amount == 10, "A distant primary cannot lend its condition to nearby collateral")
	check(owner.attack_events.size() == 1 and owner.damage_events.size() == 2, "Farshot creates no extra Attack hit or damage trigger")
	check(is_equal_approx(float(owner.damage_events[0].raw_amount), 100.0), "Accepted event retains the unconditioned primary basis")
	owner.child_emitted = false
	parent.position = Vector2(100, 0)
	child.position = Vector2(200, 0)
	packet(parent, 100.0, 1.0, "melee")
	check(parent.hits.back().amount == 100 and child.hits.back().amount == 11, "Nearby primary collateral independently earns its scaled distant bonus")
	var action := owner.combat_interactions.begin_action("attack")
	for offset in [Vector2(120, 0), Vector2(180, 0)]:
		var collateral := enemy(offset)
		packet(collateral, 60, 0.6, "rupture_wave", action)
		check(collateral.hits.back().amount == (60 if offset.x < 160 else 66), "One Burst evaluates each actual victim once")
	teardown()

func _test_fractional_sources() -> void:
	setup()
	var whole := enemy(Vector2(200, 0))
	var split := enemy(Vector2(220, 0))
	packet(whole, 10.0, 0.1, "static_wake")
	for index in 10:
		packet(split, 1.0, 0.01, "static_wake")
	check(whole.get_current_health() == 99989 and split.get_current_health() == whole.get_current_health(), "Continuous Field splitting preserves 11 total damage rather than adding ten full bonuses")
	var echoed := enemy(Vector2(240, 0))
	packet(echoed, 55.0, 0.55, "sovereigns_double")
	check(echoed.hits.back().amount == 61, "Echo strength scales Farshot to 5.5 before normal fractional rounding")
	for source in ["phantom_step", "razor_orbit", "rupture_wave", "returning_crescent", "static_wake"]:
		var target := enemy(Vector2(250, 0))
		packet(target, 50, 0.5, source)
		check(target.hits.back().amount == 55, "Eligible dealing damage receives source-scaled Farshot: " + source)
	owner.first_strike_bonus_damage = 16
	owner.mission_multiplier = 2.0
	var combined := enemy(Vector2(200, 0))
	packet(combined, 50, 0.5, "static_wake")
	check(combined.hits.back().amount == 126, "Conditional bases add before the existing Mission multiplier, once")
	teardown()

func _test_owner_and_rejection() -> void:
	setup()
	var ally := SHARED.SharedActor.new()
	ally.player_id = 2
	ally.farshot_bonus_damage = 30
	ally.position = Vector2(200, 0)
	ally.reward_storm_crown = false
	world.add_child(ally)
	var target := enemy(Vector2(200, 0))
	packet(target, 100, 1, "static_wake")
	check(target.hits.back().amount == 110, "Distant owner uses its own stack value despite a nearby ally")
	DAMAGEABLE.apply_damage(target, 100, REGISTRY.damage_context(ally.combat_interactions.begin_action("dash"), "static_wake", {"raw_amount": 100.0, "damage_coefficient": 1.0}), 2)
	check(target.hits.back().amount == 100, "Nearby ally cannot borrow the distant owner's body or bonus")
	var blocked := SHARED.BlockedEnemy.new()
	world.add_child(blocked)
	blocked.position = Vector2(200, 0)
	var count_before := owner.damage_events.size()
	packet(blocked, 100, 1, "static_wake")
	check(blocked.hits.is_empty() and owner.damage_events.size() == count_before, "Rejected damage remains rejected with Farshot")
	owner.farshot_bonus_damage = 0
	packet(target, 100, 1, "static_wake")
	check(target.hits.back().amount == 100, "Unowned Farshot preserves the existing damage amount")
	teardown()
