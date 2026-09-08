extends SceneTree

const KEEPER := preload("res://scripts/enemy_keeper.gd")
const DAMAGE := preload("res://scripts/shared/damageable.gd")
const COMBO := preload("res://scripts/tests/test_boss_combinations.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const SHIELDER := preload("res://scripts/enemy_shielder.gd")

class Keeper extends "res://scripts/enemy_keeper.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _process_behavior(_delta: float) -> void:
		pass

class Apex extends "res://scripts/enemy_seamlock.gd":
	func _ready() -> void:
		max_health = 1000
		_create_health_state()
		add_to_group("enemies")
		set_physics_process(false)

class World extends Node2D:
	var events: Array[Dictionary] = []
	func record_player_damage_dealt(amount: int, peer: int = 0, killed: bool = false, enemy_id: int = 0) -> void:
		events.append({"amount": amount, "peer": peer, "killed": killed, "enemy": enemy_id})

var checks := 0
var failures: Array[String] = []
var world: World
var player: COMBO.ComboPlayer

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _circle(body: CollisionObject2D, radius: float = 13.0) -> void:
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	(shape.shape as CircleShape2D).radius = radius
	body.add_child(shape)

func _setup() -> void:
	world = World.new()
	root.add_child(world)
	current_scene = world
	player = COMBO.ComboPlayer.new()
	_circle(player)
	player.player_id = 1
	player.position = Vector2(-500.0, 0.0)
	world.add_child(player)
	player.damage = 100
	player.arcana_motion.set_process(false)
	player.boss_combinations.set_process(false)

func _cleanup() -> void:
	MultiplayerSessionManager.session_connected = false
	MultiplayerSessionManager.is_host_peer = false
	EnemyReplicationService.clear_state()
	player.discard_pending_combat_input()
	if is_instance_valid(player.upgrade_system.power_registry):
		player.upgrade_system.power_registry.free()
	current_scene = null
	world.free()

func _enemy(position: Vector2, id: int = 0) -> COMBO.ComboEnemy:
	var target := COMBO.ComboEnemy.new()
	_circle(target)
	target.position = position
	world.add_child(target)
	target.set_max_health_and_current(1000)
	if id > 0:
		target.set_meta("network_enemy_id", id)
	return target

func _keeper(position: Vector2 = Vector2.ZERO) -> Keeper:
	var keeper := Keeper.new()
	_circle(keeper, 17.0)
	keeper.position = position
	world.add_child(keeper)
	return keeper

func _settle() -> void:
	await physics_frame
	await process_frame

func _arm(keeper: Keeper) -> void:
	keeper._update_wards(0.001)
	keeper._update_wards(0.61)

func _run() -> void:
	await _test_damage_and_accounting()
	await _test_exclusions_and_no_stacking()
	await _test_link_lifecycle()
	await _test_displacement_and_rearm()
	await _test_real_blast_and_shade()
	await _test_replica_authority()
	await _test_wire_order_and_expiry()
	await _test_shielder_override()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[KeeperRuntime] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_damage_and_accounting() -> void:
	_setup()
	var keeper := _keeper()
	var target := _enemy(Vector2(100.0, 0.0), 801)
	await _settle()
	keeper._update_wards(0.001)
	_check(keeper.ward_targets.is_empty() and keeper.ward_warmup_left > 0.0, "A visible warmup precedes protection")
	_check(keeper.get_ward_damage_multiplier_for(target) == 1.0, "Pending links do not reduce damage")
	keeper._update_wards(0.61)
	_check(keeper.ward_targets == [target], "Warmup produces the intended ordinary ally link")
	for context in [{"attack_type": "melee"}, {"attack_type": "blast_drive"}, {"attack_type": "sovereigns_double", "secondary": true}, {"attack_type": "ruinous_impact", "secondary": true}]:
		var health_before := target.get_current_health()
		DAMAGE.apply_damage(target, 100, context, 1)
		_check(health_before - target.get_current_health() == 70, "Actual health takes exactly 70 of 100 from %s" % context.attack_type)
		_check(world.events.back().amount == 70 and world.events.back().peer == 1, "Damage credit records the actual protected health delta")
	_check(EnemyReplicationService.killer_peer_for(801) == 1 and not DAMAGE.is_launch_suppressed(), "Accepted protected damage retains ownership and unwinds secondary scope")
	target.damage_blocked = true
	var count := world.events.size()
	DAMAGE.apply_damage(target, 100, {}, 2)
	_check(world.events.size() == count and EnemyReplicationService.killer_peer_for(801) == 1, "Blocked hits create no phantom damage or replacement kill credit")
	target.damage_blocked = false
	target.set_health(30)
	DAMAGE.apply_damage(target, 100, {"secondary": true}, 2)
	_check(world.events.back().amount == 30 and world.events.back().killed and world.events.back().peer == 2, "Protected lethal damage credits only remaining health to the final owner")
	count = world.events.size()
	DAMAGE.apply_damage(target, 100, {}, 1)
	_check(world.events.size() == count and EnemyReplicationService.killer_peer_for(801) == 2, "Dead targets cannot produce phantom damage or steal kill ownership")
	_check(keeper.get_ward_damage_multiplier_for(target) == 1.0 and not keeper.ward_targets.has(target), "Death invalidates the ward at the damage query boundary")
	_cleanup()

func _test_exclusions_and_no_stacking() -> void:
	_setup()
	var keeper := _keeper()
	var other := _keeper(Vector2(0.0, 60.0))
	var ordinary := _enemy(Vector2(100.0, 0.0))
	var boss := COMBO.ComboBoss.new()
	world.add_child(boss)
	boss.position = Vector2(20.0, 0.0)
	var apex := Apex.new()
	world.add_child(apex)
	apex.position = Vector2(30.0, 0.0)
	await _settle()
	_arm(keeper)
	_arm(other)
	_check(keeper.ward_targets == [ordinary] and other.ward_targets == [ordinary], "Self, another Keeper, Boss and Apex are excluded during selection")
	for excluded in [keeper, other, boss, apex]:
		_check(keeper.get_ward_damage_multiplier_for(excluded) == 1.0, "Excluded bodies can never borrow a Keeper link")
	DAMAGE.apply_damage(ordinary, 100)
	_check(ordinary.get_current_health() == 930, "Two Keepers protecting one ally never stack reduction")
	var before := keeper.get_current_health()
	DAMAGE.apply_damage(keeper, 40)
	_check(before - keeper.get_current_health() == 40, "The supporting Keeper remains directly vulnerable")
	_cleanup()

func _test_link_lifecycle() -> void:
	_setup()
	var keeper := _keeper()
	var targets: Array[COMBO.ComboEnemy] = []
	for index in range(4):
		targets.append(_enemy(Vector2(80.0 + 30.0 * index, 0.0)))
	await _settle()
	_arm(keeper)
	_check(keeper.ward_targets.size() == 2, "A Keeper links at most two allies regardless of party size")
	var linked := keeper.ward_targets[0]
	var survivor := keeper.ward_targets[1]
	linked.position = Vector2(221.0, 0.0)
	_check(keeper.get_ward_damage_multiplier_for(linked) == 1.0 and not keeper.ward_targets.has(linked), "Crossing 220 px breaks protection before the next AI tick")
	_check(keeper.get_ward_damage_multiplier_for(survivor) == 0.7 and keeper.ward_rearm_left > 0.0, "One broken link preserves the other and delays replacement")
	keeper._update_wards(0.5)
	_check(keeper.ward_targets.size() == 1, "The broken slot cannot instantly transfer to a third ally")
	linked.position = Vector2(80.0, 0.0)
	keeper._update_wards(0.6)
	keeper._update_wards(0.61)
	_check(keeper.ward_targets.size() == 2, "A broken slot rearms only after its delay and fresh warmup")
	var freed := keeper.ward_targets[0]
	freed.free()
	_check(keeper.get_ward_damage_multiplier_for(freed) == 1.0, "The public Variant query safely accepts a previously freed target")
	keeper._update_wards(0.0)
	_check(keeper.ward_targets.size() == 1, "Freed targets are pruned without invalid object access")
	var queued := keeper.ward_targets[0]
	queued.queue_free()
	_check(keeper.get_ward_damage_multiplier_for(queued) == 1.0, "Queued targets lose protection before deferred deletion")
	await _settle()
	keeper._update_wards(1.1)
	keeper._update_wards(0.61)
	var target := _enemy(Vector2(-140.0, 0.0))
	await _settle()
	keeper.on_player_displaced(Vector2(100.0, 0.0))
	keeper._update_wards(1.3)
	keeper._update_wards(0.61)
	_check(keeper.get_ward_damage_multiplier_for(target) == 0.7, "Line-of-sight fixture begins with a live protected target")
	var wall := StaticBody2D.new()
	_circle(wall, 25.0)
	wall.position = Vector2(-70.0, 0.0)
	world.add_child(wall)
	await _settle()
	_check(keeper.get_ward_damage_multiplier_for(target) == 1.0, "Solid cover interrupts line of sight at the query boundary")
	keeper.queue_free()
	var before := target.get_current_health()
	DAMAGE.apply_damage(target, 100)
	_check(before - target.get_current_health() == 100, "A Keeper queued for death provides no lingering reduction")
	await _settle()
	_cleanup()

func _test_wire_order_and_expiry() -> void:
	_setup()
	var keeper := _keeper()
	var first := _enemy(Vector2(100.0, 0.0), 901)
	var second := _enemy(Vector2(120.0, 0.0), 902)
	var replica := _keeper(Vector2(0.0, 100.0))
	replica.set_network_simulation_enabled(false)
	await _settle()
	keeper._update_wards(0.001)
	var warming := keeper.get_network_runtime_state()
	replica.apply_network_runtime_state(warming)
	_check(replica.ward_targets.is_empty() and replica._pending_ward_targets.size() == 2 and replica.ward_warmup_left > 0.0, "Replica receives the visible warmup without early active links")
	keeper._update_wards(0.61)
	var active := keeper.get_network_runtime_state()
	_check(var_to_bytes(active.custom).size() < 300, "Two-link custom state stays within its bounded network budget")
	replica.apply_network_runtime_state(active)
	_check(replica.ward_targets.has(first) and replica.ward_targets.has(second), "Replica resolves host target IDs to the correct actual nodes")
	replica.apply_network_runtime_state(warming)
	_check(replica.ward_targets.size() == 2 and replica.ward_warmup_left == 0.0, "Older warmup packets cannot roll back an active link state")
	replica._process_network_visuals(0.30)
	replica.apply_network_runtime_state(active)
	replica._process_network_visuals(0.21)
	_check(replica.ward_targets.is_empty(), "Duplicate packets cannot indefinitely extend an expired visual lease")
	keeper._update_wards(0.13)
	active = keeper.get_network_runtime_state()
	replica.apply_network_runtime_state(active)
	_check(replica.ward_targets.size() == 2, "A newer heartbeat restores current host visuals after packet loss")
	var stable := true
	for _pulse in range(10):
		keeper._update_wards(0.13)
		replica._process_network_visuals(0.13)
		active = keeper.get_network_runtime_state()
		replica.apply_network_runtime_state(active)
		stable = stable and replica.ward_targets.size() == 2
	_check(stable, "Unchanged links remain visible through 1.3 seconds of changing heartbeat revisions")
	keeper.on_player_displaced(Vector2(100.0, 0.0))
	var broken := keeper.get_network_runtime_state()
	replica.apply_network_runtime_state(broken)
	replica.apply_network_runtime_state(active)
	_check(replica.ward_targets.is_empty() and replica.ward_rearm_left > 1.0 and replica._ward_break_flash_left > 0.0, "New break state survives an out-of-order active packet")
	var late_spawn_packet := {"custom": {"q": 999, "a": [903], "p": [], "w": 0.0, "r": 0.0, "b": 0.0}}
	replica.apply_network_runtime_state(late_spawn_packet)
	_check(replica.ward_targets.is_empty(), "A missing spawn never substitutes another nearby ally")
	var late := _enemy(Vector2(150.0, 0.0), 903)
	replica._process_network_visuals(0.01)
	_check(replica.ward_targets == [late], "A late spawn resolves the retained stable ID during the lease")
	late.queue_free()
	replica._process_network_visuals(0.01)
	_check(replica.ward_targets.is_empty(), "Remote queued death clears its link without awaiting a new packet")
	var keeper_count := get_nodes_in_group("keepers").size()
	replica.free()
	_check(get_nodes_in_group("keepers").size() == keeper_count - 1, "Freeing a visual Keeper removes its support registration")
	_cleanup()

func _test_shielder_override() -> void:
	_setup()
	var keeper := _keeper()
	var shield := SHIELDER.new()
	_circle(shield)
	shield.position = Vector2(100.0, 0.0)
	world.add_child(shield)
	shield.set_physics_process(false)
	shield.set_max_health_and_current(1000)
	await _settle()
	_arm(keeper)
	DAMAGE.apply_damage(shield, 100, {"attack_type": "ruinous_impact", "secondary": true, "is_ground_attack": true})
	_check(shield.get_current_health() == 930 and world.events.back().amount == 70, "Shielder's ground-hit override also applies the ward once")
	shield.target = null
	DAMAGE.apply_damage(shield, 100, {"attack_type": "blast_drive"})
	_check(shield.get_current_health() == 860 and world.events.back().amount == 70, "Unblocked direct Shielder damage also uses the shared ward rule")
	shield.damage_blocked = true
	var count := world.events.size()
	DAMAGE.apply_damage(shield, 100, {"is_ground_attack": true})
	_check(shield.get_current_health() == 860 and world.events.size() == count, "Shielder's ground path respects damage blocking and emits no credit")
	keeper.take_damage(99999)
	shield.damage_blocked = false
	DAMAGE.apply_damage(shield, 100, {"is_ground_attack": true})
	_check(shield.get_current_health() == 760, "Lethal Keeper damage removes support before the next hit")
	_cleanup()

func _test_displacement_and_rearm() -> void:
	_setup()
	var keeper := _keeper()
	var target := _enemy(Vector2(100.0, 0.0))
	await _settle()
	_arm(keeper)
	keeper.on_player_displaced(Vector2(10.0, 0.0))
	_check(keeper.get_ward_damage_multiplier_for(target) == 0.7, "Tiny incidental motion does not constantly cancel wards")
	DAMAGE.apply_impulse(keeper, Vector2(100.0, 0.0), 1, true)
	_check(keeper.ward_targets.is_empty() and keeper.ward_rearm_left >= 1.2, "A real player push immediately interrupts both links even with secondary launch suppression")
	keeper._update_wards(1.0)
	_check(keeper.get_ward_damage_multiplier_for(target) == 1.0, "Interrupted Keeper remains uncovered during the rearm delay")
	keeper._update_wards(0.3)
	_check(keeper.ward_targets.is_empty() and keeper.ward_warmup_left > 0.0, "Rearm starts a new readable warmup")
	keeper._update_wards(0.61)
	_check(keeper.get_ward_damage_multiplier_for(target) == 0.7, "A surviving Keeper can reconnect after the complete interruption window")
	player.apply_upgrade("ruinous_impact")
	player.boss_combinations.launch_enemy(keeper, Vector2(540.0, 0.0), 1)
	_check(keeper.get_launch_state().active and keeper.ward_targets.is_empty(), "A directly accepted launch interrupts protection immediately")
	keeper._physics_process(0.02)
	_check(keeper.get_ward_damage_multiplier_for(target) == 1.0, "Host launch stepping cannot skip ward invalidation")
	_cleanup()

func _test_real_blast_and_shade() -> void:
	_setup()
	player.position = Vector2.ZERO
	player.apply_trial_power("blast_drive")
	player.apply_upgrade("sovereigns_double")
	var keeper := _keeper(Vector2(100.0, 150.0))
	var target := _enemy(Vector2(100.0, 0.0))
	await _settle()
	_arm(keeper)
	player.boss_combinations.create_shade(Vector2.ZERO)
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	_check(target.hits.size() == 2 and target.hits[0].type == "blast_drive" and target.hits[1].type == "sovereigns_double", "A real Blast and its Sovereign echo both hit the protected ally")
	if target.hits.size() == 2:
		_check(target.hits[0].amount == 175 and target.hits[1].amount == 97, "The 250 Blast and 55% echo each receive ward mitigation exactly once")
		_check(world.events[0].amount == 175 and world.events[1].amount == 97, "Real primary and echo statistics equal their final health deltas")
	_cleanup()

func _test_replica_authority() -> void:
	_setup()
	var keeper := _keeper()
	var target := _enemy(Vector2(100.0, 0.0))
	await _settle()
	_arm(keeper)
	keeper.network_simulation_enabled = false
	_check(keeper.get_ward_damage_multiplier_for(target) == 1.0, "A visual Keeper replica cannot mitigate even if stale links remain")
	keeper.network_simulation_enabled = true
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = false
	_check(keeper.get_ward_damage_multiplier_for(target) == 1.0, "Client authority gate overrides an accidentally enabled local simulation flag")
	MultiplayerSessionManager.is_host_peer = true
	_check(keeper.get_ward_damage_multiplier_for(target) == 0.7, "The actual host remains authoritative in a co-op session")
	_cleanup()
