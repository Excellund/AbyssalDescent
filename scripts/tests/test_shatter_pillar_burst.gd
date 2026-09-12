extends "res://scripts/tests/test_biome_room_context.gd"
## Real Attack -> cover contact -> environmental Burst, with lifecycle edges.

const CHASER := preload("res://scripts/enemy_chaser.gd")
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	await _setup_context_world()
	await _test_break_payoff()
	await _test_room_retirement()
	await _dispose_context_world()
	print("[ShatterPillarBurst] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _enter_shatter() -> Vector2:
	await _enter_context("shatterfield", "crossfire")
	_start_context_combat()
	world._tick_biome_rules(.01)
	for enemy in _context_enemies():
		enemy.position = Vector2(900, 900)
	var center: Vector2 = world._arena_cover_bodies[2].global_position
	world.player.global_position = center - Vector2(68, 0)
	return center

func _enemy(at: Vector2, health: int = 500) -> CHASER:
	var enemy := CHASER.new()
	enemy.max_health = health
	world.add_child(enemy)
	enemy.global_position = at
	enemy.spawn_transport_time_left = 0.0
	enemy.set_physics_process(false)
	enemy.set_process(false)
	return enemy

func _swing() -> Dictionary:
	world.player.attack_cooldown_left = 0.0
	world.player.attack_lock_time_left = 0.0
	world.player._try_execute_attack(Vector2.RIGHT)
	var controller: Node = world.player.combat_interactions
	var action := {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "owner": world.player.player_id, "seq": controller._next_sequence, "epoch": controller._epoch, "kind": "melee", "ancestry": 0}
	return INTERACTIONS.damage_context(action, "melee").interaction

func _test_break_payoff() -> void:
	var center := await _enter_shatter()
	world.player.apply_trial_power("storm_crown")
	world.player.apply_upgrade("pillar_convergence")
	world.player.apply_upgrade("edict_of_the_court")
	world.player.apply_upgrade("lacuna_echo")
	var upper := _enemy(center + Vector2(0, -120))
	var lower := _enemy(center + Vector2(0, 120))
	var outside := _enemy(center + Vector2(0, 180))
	var blocked := _enemy(center + Vector2(0, 135))
	blocked.damage_blocked = true
	var victim := _enemy(center + Vector2(0, -140), 1)
	victim.died.connect(func(): world._on_room_enemy_died(center))
	var player_health := world.player.get_current_health()
	var damage_before: int = world.run_summary_recorder.run_summary_tracker.total_damage_dealt
	_swing()
	_swing()
	check(upper.get_current_health() == 500 and lower.get_current_health() == 500 and world._biome_rules.shard_bursts.is_empty(), "First two real Attacks only crack cover; no early Burst")
	var final_action := _swing()
	check(world._arena_cover.contacts_left(2) == 0 and not world._arena_cover_bodies.has(2), "The third real Attack removes the column before releasing shards")
	check(upper.get_current_health() == 440 and lower.get_current_health() == 440 and victim.is_dead(), "Breaking cover damages every nearby foe once for 60 base damage")
	check(outside.get_current_health() == 500 and blocked.get_current_health() == 500, "Radius and native damage protection both remain authoritative")
	check(world.player.get_current_health() == player_health, "Player standing inside the shard Burst is safe")
	check(world.player.storm_crown_hit_counter == 0 and world.player.void_echo_zones.is_empty(), "Environment damage and kills create no owned lightning charges or kill Fields")
	check(world.player.convergence_surge_damage_ratio > 0.0 and world.player.convergence_surge_hit_counter == 0 and world.player.convergence_window_left == 0.0, "Environmental shards cannot charge or activate an owned Pillar Convergence")
	check(world.run_summary_recorder.run_summary_tracker.total_damage_dealt == damage_before, "Shard damage is not attributed as player-owned damage")
	check(world._biome_rules.shard_bursts.size() == 1 and world._biome_rules.phase == "idle" and not world._biome_rules.fragments, "One break gets one visual without starting periodic fragment hazards")
	world.request_brittle_cover_attack(final_action, world.player.global_position, Vector2.RIGHT)
	_swing()
	world._tick_biome_rules(.2)
	check(upper.get_current_health() == 440 and lower.get_current_health() == 440 and world._biome_rules.shard_bursts.size() == 1, "Replayed and new Attacks through rubble plus later effect frames cannot repeat damage")
	world.pause_menu_controller.open()
	var left: float = world._biome_rules.shard_bursts[0].left
	world._tick_biome_rules(5.0)
	check(world._biome_rules.shard_bursts[0].left == left, "Pause freezes the cosmetic Burst")
	world.pause_menu_controller.close()
	world._tick_biome_rules(1.0)
	check(world._biome_rules.shard_bursts.is_empty(), "A shard Burst clears after its bounded cosmetic lifetime")
	var second_center: Vector2 = world._arena_cover_bodies[3].global_position
	upper.global_position = second_center + Vector2(0, -120)
	lower.global_position = Vector2(900, 900)
	world.player.global_position = second_center - Vector2(68, 0)
	for _contact in 3: _swing()
	check(upper.get_current_health() == 380 and world._arena_cover.contacts_left(3) == 0, "The other authored pillar grants its own single Burst")
	world._enter_rest_site()
	check(world._biome_rules.shard_bursts.is_empty() and world._biome_rules.rule_id.is_empty(), "Room retirement clears old shard visuals")

func _test_room_retirement() -> void:
	var center := await _enter_shatter()
	var last_enemy := _enemy(center + Vector2(0, -120), 1)
	var later_target := _enemy(center + Vector2(0, 120), 500)
	last_enemy.died.connect(func():
		world.active_room_enemy_count = 0
		world._on_room_cleared()
	)
	for _contact in 3: _swing()
	check(last_enemy.is_dead() and later_target.get_current_health() == 500, "A synchronous last-enemy clear stops the retired Burst before another target")
	check(world._biome_rules.rule_id.is_empty() and world._biome_rules.shard_bursts.is_empty() and world._cover_run_token.is_empty(), "Synchronous clear leaves no lingering Burst or stale cover identity")
	check(not world._biome_rules.environment_damage_active and world.player.void_echo_zones.is_empty(), "Environmental damage scope unwinds after synchronous cleanup without owned kill reactions")
