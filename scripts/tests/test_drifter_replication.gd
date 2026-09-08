extends SceneTree

const BROADCASTER := preload("res://scripts/core/enemy_state_sync_broadcaster.gd")

class TestDrifter extends "res://scripts/enemy_drifter.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)

class TestHealth extends RefCounted:
	var current_health: int = 100

class TestTarget extends Node2D:
	var health_state := TestHealth.new()
	var hits: int = 0
	var last_context: Dictionary = {}

	func take_damage(amount: int, context: Dictionary = {}) -> void:
		health_state.current_health -= amount
		hits += 1
		last_context = context

	func is_dead() -> bool:
		return health_state.current_health <= 0

class RingPlayer extends "res://scripts/player.gd":
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)
		_create_health_state()

	func _is_local_control_owner() -> bool:
		# Run real health/resistance logic without audiovisual owner feedback.
		return false

var checks: int = 0
var failures: Array[String] = []
var world: Node2D

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _drifter(remote: bool = false) -> TestDrifter:
	var enemy := TestDrifter.new()
	world.add_child(enemy)
	enemy.set_network_simulation_enabled(not remote)
	return enemy

func _run() -> void:
	world = Node2D.new()
	root.add_child(world)
	_test_geometry_and_merge()
	_test_packet_loss_and_order()
	_test_charge_phase()
	_test_authority_and_damage()
	_test_coop_player_collision()
	await process_frame
	world.free()
	if failures.is_empty():
		print("[DrifterReplication] PASS (%d checks)" % checks)
	else:
		print("[DrifterReplication] FAIL (%d/%d checks)" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func _test_geometry_and_merge() -> void:
	var host := _drifter()
	var remote := _drifter(true)
	_check(host.get_projectile_network_sync_state().is_empty(), "Idle host sends no empty projectile traffic")
	host.global_position = Vector2(180.0, 240.0)
	host.ring_node_count = 10
	host.ring_speed = 190.0
	host.ring_radius_max = 330.0
	host.node_hit_radius = 21.0
	host.wave_interval = 1.0
	host.wave_timer = 1.0
	host._emit_ring()
	host._process_rings(0.2)
	var packet := host.get_projectile_network_sync_state()
	remote.apply_projectile_network_sync_state(packet)
	_check(remote.rings.size() == 1, "Joiner receives an already expanding host ring")
	_check(remote.ring_node_count == 10 and is_equal_approx(remote.ring_speed, 190.0), "Joiner receives host node count and speed")
	_check(is_equal_approx(remote.ring_radius_max, 330.0) and is_equal_approx(remote.node_hit_radius, 21.0), "Joiner receives range and visible hit radius")
	_check(remote.rings[0]["world_pos"] == host.rings[0]["world_pos"], "Ring origin is transmitted in world space")
	_check(is_equal_approx(float(remote.rings[0]["radius"]), 38.0), "A missed spawn packet starts at the current host radius")
	_check(int(remote.rings[0]["gap_index"]) == int(host.rings[0]["gap_index"]), "Safe gap is identical on host and joiner")
	_check(not remote.rings[0].has("damaged"), "Damage bookkeeping stays outside client state")
	for node_index in range(host.ring_node_count):
		_check(remote._get_ring_node_world_position(remote.rings[0], node_index).is_equal_approx(host._get_ring_node_world_position(host.rings[0], node_index)), "Ring node %d has the same visible world position" % node_index)
	var node_position := remote._get_ring_node_world_position(remote.rings[0], 0)
	host.global_position += Vector2(90.0, -120.0)
	remote.global_position = Vector2(-150.0, 700.0)
	_check(remote._get_ring_node_world_position(remote.rings[0], 0) == node_position, "Moving the remote body cannot drag an emitted ring")
	_check(remote.to_global(remote.to_local(node_position)).is_equal_approx(node_position), "Drawing converts the fixed ring origin into current body-local coordinates")
	_check(remote.should_process_remote_visuals_every_frame(), "Active rings request smooth per-frame client animation")
	_check(host.should_force_network_runtime_state_sampling() and is_equal_approx(host.get_priority_network_sync_interval_sec(), 0.03), "Active waves enter the existing attack-priority sync window")
	# Exercise EnemyBase's actual joiner path, which does not call behavior.
	remote._physics_process(0.15)
	_check(is_equal_approx(float(remote.rings[0]["radius"]), 66.5), "EnemyBase remote ticking expands rings between snapshots")
	host._process_rings(0.10)
	remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state())
	_check(is_equal_approx(float(remote.rings[0]["radius"]), 66.5), "Existing ring samples cannot rewind locally animated radius")
	host._emit_ring()
	var overlapping := host.get_projectile_network_sync_state()
	remote.apply_projectile_network_sync_state(overlapping)
	_check(remote.rings.size() == 2, "An overlapping wave is added without replacing the first")
	_check(int(remote.rings[0]["id"]) != int(remote.rings[1]["id"]), "Overlapping rings have stable distinct IDs")
	_check(remote.rings[1]["world_pos"] == host.global_position, "Each wave retains its own emission origin")
	_check(is_equal_approx(float(remote.rings[0]["radius"]), 66.5), "A new wave cannot reset older visible motion")
	var broadcaster := BROADCASTER.new(null)
	_check(broadcaster.estimate_variant_size_bytes({"enemy_id": 1, "payload": overlapping}) + 184 <= 640, "Two simultaneous waves fit the smallest projectile batch budget")
	var fitted := broadcaster._fit_state_to_size_limit({"enemy_id": 1, "position": Vector2.ZERO, "runtime_state_delta": {"custom": host._get_custom_network_runtime_state()}}, 480)
	_check((fitted["runtime_state_delta"] as Dictionary).has("custom"), "Charge cues survive the crowded-room runtime size cap")
	host.free()
	remote.free()

func _test_packet_loss_and_order() -> void:
	var host := _drifter()
	var remote := _drifter(true)
	host._emit_ring()
	var first := host.get_projectile_network_sync_state()
	host._process_rings(0.4)
	var second := host.get_projectile_network_sync_state()
	remote.apply_projectile_network_sync_state(second)
	var radius := float(remote.rings[0]["radius"])
	remote.apply_projectile_network_sync_state(first)
	_check(is_equal_approx(float(remote.rings[0]["radius"]), radius), "Out-of-order unreliable packets cannot rewind rings")
	remote._process_network_visuals(0.1)
	var advanced_radius := float(remote.rings[0]["radius"])
	remote.apply_projectile_network_sync_state(second)
	_check(is_equal_approx(float(remote.rings[0]["radius"]), advanced_radius), "Duplicate packets do not reset or duplicate motion")
	remote._process_network_visuals(3.0)
	_check(remote.rings.is_empty(), "Local expiry removes rings even if the final clear packet is lost")
	remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state())
	_check(remote.rings.is_empty(), "A newer delayed sample cannot resurrect a locally expired ID")
	host._emit_ring()
	remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state())
	_check(remote.rings.size() == 1 and int(remote.rings[0]["id"]) == 2, "A fresh wave remains visible after an earlier wave expires locally")
	host.rings.clear()
	var clear_packet := host.get_projectile_network_sync_state()
	_check(not clear_packet.is_empty() and (clear_packet["r"] as Array).is_empty(), "Host sends a final clear snapshot when the last ring ends")
	remote.apply_projectile_network_sync_state(clear_packet)
	_check(remote.rings.is_empty(), "Authoritative clear removes remaining remote rings")
	remote.apply_projectile_network_sync_state(second)
	_check(remote.rings.is_empty(), "A late pre-clear packet cannot resurrect a ring")
	_check(host.get_projectile_network_sync_state().is_empty(), "An idle host stops sending projectile snapshots after its clear")
	_check(remote.get_projectile_network_sync_state().is_empty(), "A joiner cannot broadcast authoritative projectile state")
	remote._emit_ring()
	_check(remote.rings.is_empty(), "A joiner cannot create its own wave")
	host.free()
	remote.free()

func _test_charge_phase() -> void:
	var host := _drifter()
	var remote := _drifter(true)
	var initial_timer := host.wave_timer
	host.set_ring_start_offset(host.wave_interval * 0.5)
	_check(is_equal_approx(host.wave_timer, initial_timer + host.wave_interval * 0.5), "Undertow can stagger a Drifter's first wave after ready")
	host.set_ring_start_offset(-10.0)
	_check(is_equal_approx(host.wave_timer, initial_timer + host.wave_interval * 0.5), "A negative start offset cannot accelerate the opening wave")
	remote.apply_network_runtime_state(host.get_network_runtime_state())
	_check(is_equal_approx(remote.wave_timer, host.wave_timer), "Initial charge and stagger delay reach a joiner through the runtime contract")
	remote._physics_process(0.2)
	_check(is_equal_approx(remote.wave_timer, host.wave_timer - 0.2), "Charge phase advances on the client between packets")
	remote.apply_network_runtime_state(host.get_network_runtime_state())
	_check(is_equal_approx(remote.wave_timer, host.wave_timer - 0.2), "Repeated phase samples cannot shake the charge halo backwards")
	var old_phase := host.get_network_runtime_state()
	host._emit_ring()
	host.wave_interval = 1.0
	host.wave_timer = 1.0
	remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state())
	_check(is_equal_approx(remote.wave_timer, 1.0) and is_equal_approx(remote.wave_interval, 1.0), "A new wave resets the cue and carries mutator-adjusted cadence")
	remote.apply_network_runtime_state(old_phase)
	_check(is_equal_approx(remote.wave_timer, 1.0) and is_equal_approx(remote.wave_interval, 1.0), "Late runtime state cannot restore the previous wave's cue")
	remote._process_network_visuals(5.0)
	_check(remote.rings.is_empty(), "Visual ticking never emits a speculative next wave")
	host.rings.clear()
	host.wave_timer = 0.4
	_check(host._is_in_priority_attack_state(), "The final pre-wave cue receives priority sampling")
	host.wave_timer = 0.9
	_check(not host._is_in_priority_attack_state(), "Long idle intervals return to normal sampling")
	host.free()
	remote.free()

func _test_authority_and_damage() -> void:
	var host := _drifter()
	var remote := _drifter(true)
	var victim := TestTarget.new()
	world.add_child(victim)
	host.target = victim
	remote.target = victim
	host._emit_ring()
	var gap := int(host.rings[0]["gap_index"])
	var dangerous_node := (gap + 1) % host.ring_node_count
	victim.global_position = Vector2.RIGHT.rotated(float(dangerous_node) * TAU / float(host.ring_node_count)) * host.ring_speed * 0.5
	remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state())
	remote._physics_process(0.5)
	_check(victim.hits == 0 and victim.health_state.current_health == 100, "A visible remote ring overlapping a player never applies damage")
	host._process_rings(0.5)
	_check(victim.hits == 1 and victim.health_state.current_health == 100 - host.ring_damage, "The matching authoritative ring applies its normal damage")
	_check(victim.last_context.get("ability") == "drifter_ring", "Host ring damage retains its combat attribution")
	host._process_rings(0.0)
	_check(victim.hits == 1, "A host ring node cannot damage the same target repeatedly")
	victim.global_position = Vector2.RIGHT.rotated(float(gap) * TAU / float(host.ring_node_count)) * host.ring_speed * 0.5
	host._process_rings(0.0)
	_check(victim.hits == 1, "The replicated safe gap is also safe in host collision checks")
	var host_ring_count := host.rings.size()
	host.apply_projectile_network_sync_state({"q": 999, "r": [], "c": [2, 1.0, 1.0, 1.0]})
	_check(host.rings.size() == host_ring_count and host.ring_node_count == 8, "Host ignores incoming remote projectile state")
	host.free()
	remote.free()
	victim.free()

func _ring_player(position: Vector2) -> RingPlayer:
	var player := RingPlayer.new()
	world.add_child(player)
	player.global_position = position
	player.set_max_health_and_current(100, 100)
	return player

func _test_coop_player_collision() -> void:
	var host := _drifter()
	var remote := _drifter(true)
	host._emit_ring()
	host.rings[0]["radius"] = 74.0
	var gap := int(host.rings[0]["gap_index"])
	var dangerous_node := (gap + 1) % host.ring_node_count
	var hit_position := host._get_ring_node_world_position(host.rings[0], dangerous_node)
	var first := _ring_player(hit_position)
	var second := _ring_player(hit_position)
	var gap_player := _ring_player(host._get_ring_node_world_position(host.rings[0], gap))
	var dead_player := _ring_player(hit_position)
	dead_player.set_health(0)
	var ghost_player := _ring_player(hit_position)
	ghost_player.set_combat_removed(true)
	var protected_player := _ring_player(hit_position)
	protected_player.set_combat_damage_enabled(false)
	# Dash phasing/contact i-frames do not grant immunity to ability hazards.
	second.dash_phasing_active = true
	second._dash_damage_immune_left = 0.2
	second.iron_skin_armor = 2
	host.set_target_candidates([first, second, first, gap_player, dead_player, ghost_player, protected_player])
	host.target = first
	remote.set_target_candidates([first, second])
	remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state())
	remote._physics_process(0.0)
	_check(first.get_current_health() == 100 and second.get_current_health() == 100, "A joiner cannot damage either party member while showing the shared ring")
	host._process_rings(0.0)
	_check(first.get_current_health() == 88, "The selected co-op player receives exactly one ring-node hit")
	_check(second.get_current_health() == 90, "The same node independently hits the other player using real armor reduction")
	_check(second.last_damage_event.get("ability") == "drifter_ring", "Non-selected teammate damage uses the normal ability damage contract")
	_check(second.dash_phasing_active and second._dash_damage_immune_left > 0.0, "Ring collision preserves existing dash/contact immunity state")
	_check(gap_player.get_current_health() == 100, "The ring gap protects every party member")
	_check(dead_player.get_current_health() == 0 and dead_player.last_damage_event.is_empty(), "Dead players are excluded from ring damage attempts")
	_check(ghost_player.get_current_health() == 100 and ghost_player.last_damage_event.is_empty(), "Combat-removed ghost players are excluded even if the candidate list is stale")
	_check(protected_player.get_current_health() == 100, "Real player combat-phase protection still rejects ability damage")
	var first_damage_event := first.last_damage_event.duplicate(true)
	host.target = second
	host._process_rings(0.0)
	_check(first.get_current_health() == 88 and second.get_current_health() == 90, "Repeated contact and retargeting cannot reset either player's hit-node cooldown")
	_check(first.last_damage_event == first_damage_event, "Duplicate target candidates cannot issue extra damage events")
	var newcomer := _ring_player(hit_position)
	host.target_candidates.append(newcomer)
	host._process_rings(0.0)
	_check(newcomer.get_current_health() == 88, "An earlier player's hit cannot consume the same ring node for a newly eligible teammate")
	var first_ring_hits := host.rings[0]["damaged"] as Dictionary
	_check(not first_ring_hits.has(dead_player.get_instance_id()) and not first_ring_hits.has(ghost_player.get_instance_id()), "Dead and ghost players do not consume ring hit bookkeeping")
	# A separate wave has its own hit allowance for each living player.
	host._emit_ring()
	host.rings[1]["radius"] = 74.0
	host.rings[1]["gap_index"] = gap
	host._process_rings(0.0)
	_check(first.get_current_health() == 76 and second.get_current_health() == 80, "A new wave restores each player's independent hit allowance")
	# Stale/freed candidates and a vanished chase target cannot hide living peers.
	var stale := _ring_player(Vector2.ZERO)
	host.target_candidates.append(stale)
	stale.free()
	host.target = null
	_check(host._get_ring_damageable_targets().has(first) and host._get_ring_damageable_targets().has(second), "Living candidate players remain eligible without a current chase target")
	host.free()
	remote.free()
	for player in [first, second, gap_player, dead_player, ghost_player, protected_player, newcomer]:
		player.free()
