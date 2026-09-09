extends SceneTree

const REGISTRY := preload("res://scripts/power_registry.gd")
const UPGRADES := preload("res://scripts/upgrade_system.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const DESCRIPTION_GUARD := preload("res://scripts/shared/description_cap_guard.gd")
const GLOSSARY := preload("res://scripts/shared/glossary_data.gd")

class TestPlayer extends Node:
	var values: Dictionary = {
		"damage": 20, "attack_arc_degrees": 130.0, "attack_cooldown": 0.28,
		"attack_lock_duration": 0.12, "dash_cooldown": 0.42, "max_health": 100
	}

	func _get(property: StringName) -> Variant:
		return values.get(String(property), 0)

	func _set(property: StringName, value: Variant) -> bool:
		values[String(property)] = value
		return true

class TestHealth extends RefCounted:
	var current_health: int = 10

class CardPlayer extends TestPlayer:
	var upgrades: Node
	func get_upgrade_card_desc(power_id: String) -> String:
		return upgrades.get_upgrade_card_description(power_id)

class TestEnemy extends CharacterBody2D:
	signal died
	var health_state := TestHealth.new()
	var reject_damage: bool = false

	func take_damage(amount: int, _context: Dictionary = {}) -> void:
		if reject_damage or health_state.current_health <= 0:
			return
		health_state.current_health = maxi(0, health_state.current_health - amount)
		if health_state.current_health == 0:
			died.emit()

class TestWorld extends Node:
	var damage_total: int = 0
	var damage_events: int = 0
	var impulse_requests: Array[Dictionary] = []

	func record_player_damage_dealt(amount: int, _peer: int = 0, _killed: bool = false, _enemy: int = 0) -> void:
		damage_total += amount
		damage_events += 1

	func request_enemy_impulse_from_client(enemy_id: int, impulse: Vector2, _suppress_launch: bool = false, _interaction: Dictionary = {}) -> void:
		impulse_requests.append({"enemy_id": enemy_id, "impulse": impulse})

class CombatPlayer extends "res://scripts/player.gd":
	var kill_notifications: int = 0

	func _ready() -> void:
		set_physics_process(false)
		_create_health_state()
		var registry := REGISTRY.new()
		add_child(registry)
		upgrade_system = UPGRADES.new()
		add_child(upgrade_system)
		upgrade_system.initialize(self, null, registry)
		player_id = 1
		add_to_group("combat_players")
		_ensure_combat_interactions()
		_ensure_static_wake()

	func notify_enemy_killed(kill_position: Vector2 = Vector2.INF) -> void:
		kill_notifications += 1
		super.notify_enemy_killed(kill_position)

class CombatEnemy extends "res://scripts/enemy_base.gd":
	func _ready() -> void:
		set_physics_process(false)
		max_health = 10000
		_create_health_state()
		add_to_group("enemies")

class KillRecorder extends RefCounted:
	var kills: int = 0
	var peer_kills: int = 0
	var damage_total: int = 0

	func record_enemy_kill_for_tracker() -> void:
		kills += 1

	func record_peer_enemy_kill(_peer_id: int) -> void:
		peer_kills += 1

	func record_damage_dealt(amount: int, _peer_id: int) -> void:
		damage_total += amount

class KillWorld extends "res://scripts/world_generator.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

	func _exit_tree() -> void:
		pass

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _make_upgrades(player: TestPlayer, registry: Node) -> Node:
	var upgrades := UPGRADES.new()
	upgrades.initialize(player, null, registry)
	return upgrades

func _run() -> void:
	var registry := REGISTRY.new()
	_test_all_reward_applications(registry)
	_test_derived_damage_order(registry)
	_test_derived_arc_and_descriptions(registry)
	_test_boss_combination_descriptions(registry)
	_test_killing_hit_attribution()
	_test_enemy_impulses()
	_test_combat_hooks()
	_test_kills_at_arena_origin()
	_test_room_kill_dispatch()
	registry.free()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("Power reward regressions: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_all_reward_applications(registry: Node) -> void:
	for power_id: String in REGISTRY.TRIAL_POWER_POOL_IDS:
		var player := TestPlayer.new()
		var upgrades := _make_upgrades(player, registry)
		var limit: int = registry.get_power_stack_limit(power_id)
		for stack in range(1, limit + 1):
			_check(upgrades.apply_trial_power(power_id), "%s stack %d applies" % [power_id, stack])
			_check(upgrades.get_trial_power_stack_count(power_id) == stack, "%s tracks stack %d" % [power_id, stack])
			_check(bool(player.get(MAPPER.get_reward_flag(power_id))), "%s enables runtime flag" % power_id)
			var current: Dictionary = MAPPER.get_current_values(power_id, player)
			_check(not current.is_empty(), "%s writes runtime parameters" % power_id)
		_check(upgrades.apply_trial_power(power_id), "%s Prismatic applies after cap" % power_id)
		_check(upgrades.has_trial_power_prismatic(power_id), "%s records Prismatic" % power_id)
		_check(upgrades.get_trial_power_stack_count(power_id) == limit, "%s Prismatic preserves stack cap" % power_id)
		_check(not upgrades.apply_trial_power(power_id), "%s rejects repeated Prismatic" % power_id)
		upgrades.free()
		player.free()
	for power_id: String in REGISTRY.BOSS_REWARD_POOL_IDS:
		var player := TestPlayer.new()
		var upgrades := _make_upgrades(player, registry)
		var property: String = registry.get_power_balance(power_id).get("property", "")
		for stack in range(1, registry.get_power_stack_limit(power_id) + 1):
			var before := float(player.get(property))
			_check(upgrades.apply_upgrade(power_id), "%s boss reward stack %d applies" % [power_id, stack])
			_check(float(player.get(property)) > before, "%s changes runtime trigger strength" % power_id)
		_check(not upgrades.apply_upgrade(power_id), "%s rejects over-cap boss reward" % power_id)
		upgrades.free()
		player.free()

func _test_derived_damage_order(registry: Node) -> void:
	for power_id in ["phantom_step", "static_wake"]:
		for prismatic in [false, true]:
			var first := TestPlayer.new()
			var second := TestPlayer.new()
			var first_upgrades := _make_upgrades(first, registry)
			var second_upgrades := _make_upgrades(second, registry)
			var picks := 4 if prismatic else 1
			for _pick in range(picks):
				first_upgrades.apply_trial_power(power_id)
			var cooldown_before: float = first.get("dash_cooldown")
			first_upgrades.apply_upgrade("heavy_blow")
			second_upgrades.apply_upgrade("heavy_blow")
			for _pick in range(picks):
				second_upgrades.apply_trial_power(power_id)
			var property := MAPPER.get_property_name(power_id, "damage")
			_check(first.get(property) == second.get(property), "%s damage is independent of Heavy Blow order (Prismatic=%s)" % [power_id, prismatic])
			_check(is_equal_approx(float(first.get("dash_cooldown")), cooldown_before), "%s refresh does not grant another cooldown reduction" % power_id)
			_check(first_upgrades.get_trial_power_stack_count(power_id) == (3 if prismatic else 1), "%s refresh does not grant another stack" % power_id)
			first_upgrades.free()
			second_upgrades.free()
			first.free()
			second.free()

func _test_derived_arc_and_descriptions(registry: Node) -> void:
	var player := TestPlayer.new()
	var upgrades := _make_upgrades(player, registry)
	for _pick in range(3):
		upgrades.apply_trial_power("razor_wind")
	var cooldown_before: float = player.get("attack_cooldown")
	upgrades.apply_upgrade("wide_arc")
	_check(is_equal_approx(float(player.get("razor_wind_arc_degrees")), float(player.get("attack_arc_degrees"))), "Max-rank Razor Wind follows later Wide Arc")
	_check(is_equal_approx(float(player.get("attack_cooldown")), cooldown_before), "Arc refresh does not reduce attack cooldown again")
	upgrades.apply_trial_power("phantom_step")
	var phantom_text: String = upgrades.get_power_current_description("phantom_step")
	_check(phantom_text.contains(str(player.get("phantom_step_damage"))), "Phantom Step description displays applied damage")
	_check(not phantom_text.contains("0%"), "Phantom Step description does not show missing ratio as zero")
	upgrades.apply_trial_power("static_wake")
	_check(upgrades.get_power_current_description("static_wake").contains("270%"), "Static Wake description displays real ratio")
	upgrades.apply_trial_power("static_wake")
	upgrades.apply_trial_power("static_wake")
	_check(upgrades.get_trial_power_card_description("static_wake").contains("630%"), "Static Wake Prismatic preview includes its damage increase")
	upgrades.apply_trial_power("static_wake")
	_check(upgrades.get_power_current_description("static_wake").contains("630%"), "Static Wake Prismatic current description retains increase")
	upgrades.free()
	player.free()

func _test_boss_combination_descriptions(registry: Node) -> void:
	_check(REGISTRY.BOSS_REWARD_POOL_IDS.size() == 9, "Boss pool contains the seven existing and two new rewards")
	var glossary := GLOSSARY.glossary_bbcode()
	for power_id in ["ruinous_impact", "sovereigns_double"]:
		var player := CardPlayer.new()
		var upgrades := _make_upgrades(player, registry)
		player.upgrades = upgrades
		var balance: Dictionary = registry.get_power_balance(power_id)
		_check(balance.get("kind") == "add_int" and balance.get("property") == power_id + "_stacks" and balance.get("add") == 1, "%s applies one persisted integer stack" % power_id)
		_check(registry.get_power_stack_limit(power_id) == 2, "%s caps at two boss picks" % power_id)
		_check(registry.get_power_display_metadata(power_id).get("category") == REGISTRY.POWER_DISPLAY_CATEGORY_BOSS_REWARD, "%s is presented as a boss reward" % power_id)
		_check(glossary.contains(registry.get_power_display_name(power_id)), "%s has glossary instructions" % power_id)
		_check(not upgrades.get_power_flavor_text(power_id).is_empty(), "%s has shared mechanic text" % power_id)
		for stack in range(3):
			var card: String = upgrades.get_upgrade_card_description(power_id)
			var current: String = upgrades.get_power_current_description(power_id)
			_check(DESCRIPTION_GUARD.visible_length(card) <= 109 and DESCRIPTION_GUARD.visible_length(current) <= 109, "%s level %d complete descriptions fit the visible cap" % [power_id, stack])
			_check(not card.contains("Upgrade your stats") and not current.is_empty(), "%s level %d has specific reward/build text" % [power_id, stack])
			if power_id == "ruinous_impact":
				_check(card.contains("Bosses burst in place") and card.contains("impacts burst"), "Ruinous Impact explains its standalone and boss effects")
				_check(current.contains("140%" if stack == 2 else "100%"), "Ruinous Impact displays the active damage ratio")
				_check(current.contains("95" if stack == 2 else "70"), "Ruinous Impact displays the active radius")
			else:
				var card_text := DESCRIPTION_GUARD.strip_bbcode(card)
				var echo_preview := "1" if stack == 0 else "%d -> %d" % [stack, mini(2, stack + 1)]
				_check(card_text.contains("dash") and card_text.contains("recoil") and card_text.contains("orbit") and card_text.contains("shade echoes next %s attacks" % echo_preview), "Sovereign's Double explains all movement triggers and previews its next attack count")
				_check(card.contains("55%") and current.contains("4s"), "Sovereign's Double preserves echo damage and lifetime")
				_check(DESCRIPTION_GUARD.strip_bbcode(current).contains("next %d attacks" % maxi(1, stack)), "Sovereign's Double displays the active echo count")
			var pool: Array[Dictionary] = registry.get_boss_reward_pool(player)
			for option in pool:
				if option.get("id") == power_id:
					_check(option.get("desc") == card, "%s registry card uses the same description" % power_id)
			if stack < 2:
				upgrades.apply_upgrade(power_id)
		upgrades.free()
		player.free()

func _test_killing_hit_attribution() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	current_scene = world
	var enemy := TestEnemy.new()
	world.add_child(enemy)
	enemy.add_to_group("enemies")
	enemy.set_meta("network_enemy_id", 701)
	EnemyReplicationService.credit_damage(701, 22)
	var observed_killers: Array[int] = []
	enemy.died.connect(func(): observed_killers.append(EnemyReplicationService.killer_peer_for(701)))
	var local_peer: int = DAMAGEABLE._resolve_local_peer_id()
	_check(DAMAGEABLE.apply_damage(enemy, 20), "Killing hit applies")
	_check(observed_killers == [local_peer], "Synchronous death sees current attacker, not previous joiner")
	_check(world.damage_total == 10 and world.damage_events == 1, "Lethal damage records actual health loss exactly once")
	var client_enemy := TestEnemy.new()
	world.add_child(client_enemy)
	client_enemy.add_to_group("enemies")
	client_enemy.set_meta("network_enemy_id", 703)
	EnemyReplicationService.credit_damage(703, local_peer)
	client_enemy.died.connect(func(): observed_killers.append(EnemyReplicationService.killer_peer_for(703)))
	DAMAGEABLE.apply_damage(client_enemy, 20, {}, 29)
	_check(observed_killers == [local_peer, 29], "Host applies authenticated client kill with that client's credit")
	_check(world.damage_total == 20 and world.damage_events == 2, "Client lethal damage is recorded once")
	var blocked := TestEnemy.new()
	world.add_child(blocked)
	blocked.add_to_group("enemies")
	blocked.set_meta("network_enemy_id", 702)
	blocked.reject_damage = true
	EnemyReplicationService.credit_damage(702, 22)
	DAMAGEABLE.apply_damage(blocked, 10)
	_check(EnemyReplicationService.killer_peer_for(702) == 22, "Rejected hit restores previous kill credit")
	_check(world.damage_events == 2, "Rejected hit records no damage")
	EnemyReplicationService.last_damage_peer_by_id.erase(702)
	DAMAGEABLE.apply_damage(blocked, 10)
	_check(not EnemyReplicationService.last_damage_peer_by_id.has(702), "Rejected first hit leaves no kill credit")
	EnemyReplicationService.last_damage_peer_by_id.erase(701)
	EnemyReplicationService.last_damage_peer_by_id.erase(703)
	current_scene = null
	world.free()

func _test_enemy_impulses() -> void:
	var enemy := TestEnemy.new()
	root.add_child(enemy)
	enemy.add_to_group("enemies")
	enemy.velocity = Vector2(10.0, 20.0)
	_check(DAMAGEABLE.apply_impulse(enemy, Vector2(100.0, -50.0)), "Living enemy receives force")
	_check(enemy.velocity == Vector2(110.0, -30.0), "Force adds once without replacing existing velocity")
	_check(not DAMAGEABLE.apply_impulse(enemy, Vector2.INF), "Non-finite force is rejected")
	enemy.health_state.current_health = 0
	_check(not DAMAGEABLE.apply_impulse(enemy, Vector2(400.0, 0.0)), "Dead enemy rejects force")
	_check(enemy.velocity == Vector2(110.0, -30.0), "Rejected forces leave movement unchanged")
	var world := TestWorld.new()
	root.add_child(world)
	current_scene = world
	var was_connected: bool = MultiplayerSessionManager.session_connected
	var was_host: bool = MultiplayerSessionManager.is_host_peer
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = false
	enemy.health_state.current_health = 10
	enemy.set_meta("network_enemy_id", 704)
	_check(DAMAGEABLE.apply_impulse(enemy, Vector2(90.0, 40.0)), "Joiner force is routed to the host")
	_check(world.impulse_requests == [{"enemy_id": 704, "impulse": Vector2(90.0, 40.0)}], "Joiner sends the enemy identity and unchanged force exactly once")
	_check(enemy.velocity == Vector2(110.0, -30.0), "Joiner does not change replica velocity locally")
	MultiplayerSessionManager.session_connected = was_connected
	MultiplayerSessionManager.is_host_peer = was_host
	current_scene = null
	world.free()
	enemy.free()

func _test_combat_hooks() -> void:
	var ids: Array[String] = REGISTRY.TRIAL_POWER_POOL_IDS.duplicate()
	ids.append_array(REGISTRY.BOSS_REWARD_POOL_IDS)
	for power_id in ids:
		var world := TestWorld.new()
		root.add_child(world)
		current_scene = world
		var player := CombatPlayer.new()
		world.add_child(player)
		var enemy := CombatEnemy.new()
		world.add_child(enemy)
		enemy.global_position = Vector2(50.0, 0.0)
		var secondary := CombatEnemy.new()
		world.add_child(secondary)
		secondary.global_position = Vector2(60.0, 0.0)
		_check(player.upgrade_system.apply_power(power_id), "%s applies to production Player" % power_id)
		var before := enemy.get_current_health()
		var secondary_before := secondary.get_current_health()
		var activated := false
		match power_id:
			"razor_wind":
				enemy.global_position = Vector2(95.0, 0.0)
				player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "range": 78.0, "arc_degrees": 130.0})
				activated = enemy.get_current_health() < before
			"execution_edge":
				var context: Dictionary = player.upgrade_system.build_melee_attack_context(20, 78.0, 130.0, true, player.execution_damage_mult)
				player._perform_melee_attack(Vector2.RIGHT, context)
				activated = before - enemy.get_current_health() > 20
			"rupture_wave":
				player._apply_rupture_wave(enemy.global_position, 20)
				activated = secondary.get_current_health() < secondary_before
			"aegis_field":
				player._trigger_aegis_field()
				activated = player.aegis_field_active_left > 0.0 and enemy.is_slowed()
			"hunters_snare":
				player._apply_hunters_snare(enemy)
				activated = enemy.is_slowed() and player._get_hunters_snare_bonus_damage(enemy) > 0
			"phantom_step":
				enemy.global_position = Vector2(20.0, 0.0)
				player._apply_phantom_step_during_dash()
				activated = enemy.get_current_health() < before and enemy.is_slowed()
			"riftpunch":
				player._riftpunch_window_left = player.riftpunch_window_duration
				activated = player._consume_riftpunch_bonus("melee", enemy.global_position, enemy) > 0
			"reaper_step":
				player.dash_cooldown_left = 1.0
				player.notify_enemy_killed(enemy.global_position)
				activated = player.dash_cooldown_left == 0.0
			"static_wake":
				player.static_wake_controller.begin_dash(player.new_combat_action("dash"))
				player.static_wake_controller.append_segment(enemy.global_position - Vector2.RIGHT, enemy.global_position)
				player.static_wake_controller.end_dash()
				player.static_wake_controller.tick(0.25)
				activated = enemy.get_current_health() < before
			"storm_crown":
				player.storm_crown_hit_counter = player.storm_crown_proc_every - 1
				player.DAMAGEABLE.apply_damage(enemy, 20, player.INTERACTION_REGISTRY.damage_context(player.new_combat_action("melee"), "melee"))
				activated = secondary.get_current_health() < secondary_before
			"wraithstep":
				player._apply_wraithstep_marks_during_dash(Vector2.ZERO, enemy.global_position)
				activated = player._consume_wraithstep_mark(enemy, enemy.global_position, 20) > 0
			"voidfire":
				player._gain_void_heat(player.void_heat_cap)
				activated = player._voidfire_lockout_left > 0.0 and enemy.get_current_health() < before
			"dread_resonance":
				player._update_dread_resonance_target(enemy, enemy.get_instance_id())
				player._update_dread_resonance_target(enemy, enemy.get_instance_id())
				activated = player._get_dread_resonance_bonus(enemy) > 0
			"bloodvow":
				player.set_health(10)
				player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "range": 78.0, "arc_degrees": 130.0})
				activated = before - enemy.get_current_health() > 20
			"eclipse_mark":
				player._apply_eclipse_mark(enemy.global_position)
				activated = player._consume_eclipse_mark_bonus(enemy, 20) > 0
			"fracture_field":
				player._apply_fracture_field(enemy.global_position)
				activated = enemy.get_current_health() < before and enemy.is_slowed()
			"farline_volley":
				player._on_farline_volley_outer_hit(enemy)
				activated = player._get_farline_volley_bonus() > 0
			"sigil_chain":
				player._drop_sigil_chain_zone(enemy.global_position)
				player._update_sigil_chain_state(0.1)
				activated = enemy.get_current_health() < before
			"blast_drive":
				player.perform_motion_blast(Vector2.RIGHT, 1.0)
				activated = enemy.get_current_health() < before and enemy.velocity.x > 0.0
			"razor_orbit":
				player._ensure_arcana_motion()
				player.arcana_motion.start_orbit(enemy)
				player.arcana_motion._apply_cut_contacts(player.global_position, player.global_position + Vector2(5.0, 0.0))
				activated = player.arcana_motion.owns_movement() and enemy.get_current_health() < before
			"returning_crescent":
				enemy.global_position = Vector2(150.0, 0.0)
				player._ensure_returning_crescent()
				player.returning_crescent.set_physics_process(false)
				player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "range": 78.0, "arc_degrees": 130.0})
				var missed_by_melee := enemy.get_current_health() == before
				player.returning_crescent.tick(0.25)
				activated = missed_by_melee and enemy.get_current_health() < before
			"wardens_verdict":
				activated = player._get_apex_predator_bonus(enemy, enemy.global_position, 20) > 0
			"lacuna_echo":
				player.notify_enemy_killed(enemy.global_position)
				player._update_void_echo_zones(0.1)
				activated = enemy.get_current_health() < before
			"sovereign_tempo":
				player._register_apex_momentum_hit()
				player._release_apex_momentum_dash_wave(Vector2.ZERO)
				activated = enemy.get_current_health() < before and player.apex_momentum_stacks == 0
			"pillar_convergence":
				for _hit in range(6):
					player._try_apply_convergence_surge(enemy.global_position, 20, enemy.get_instance_id())
				player._update_convergence_window(0.1)
				activated = enemy.get_current_health() < before
			"unbroken_oath":
				for _hit in range(15):
					player._gain_indomitable_oath_from_hit(enemy, "melee")
				player._indomitable_primed_this_attack = false
				activated = player._consume_indomitable_spirit_bonus(enemy.global_position) > 0
			"edict_of_the_court":
				player.notify_enemy_killed(Vector2(40.0, 0.0))
				activated = enemy.velocity.x > 0.0
			"null_corridor":
				player._apply_null_corridor_segment(Vector2(1.0, 0.0), Vector2(100.0, 0.0))
				player._update_null_corridor_segments(0.1)
				activated = enemy.get_current_health() < before and not enemy.velocity.is_zero_approx()
			"ruinous_impact":
				player._ensure_boss_combinations()
				player.boss_combinations.launch_enemy(enemy, Vector2.RIGHT * 400.0, 1)
				var launch = enemy.get_launch_state()
				# Compression exercises the same one-shot burst without test physics.
				launch.compression = true
				launch.step(enemy, 0.4)
				activated = enemy.get_current_health() < before and secondary.get_current_health() < secondary_before
			"sovereigns_double":
				player._ensure_boss_combinations()
				player.boss_combinations.create_shade(Vector2.ZERO)
				player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "range": 78.0, "arc_degrees": 130.0})
				activated = before - enemy.get_current_health() > 20 and player.boss_combinations.shade_hits == 0
		_check(activated, "%s production combat hook produces its advertised effect" % power_id)
		current_scene = null
		world.free()

func _test_kills_at_arena_origin() -> void:
	for power_id in ["lacuna_echo", "edict_of_the_court", "eclipse_mark", "fracture_field"]:
		var world := TestWorld.new()
		root.add_child(world)
		current_scene = world
		var player := CombatPlayer.new()
		world.add_child(player)
		var enemy := CombatEnemy.new()
		world.add_child(enemy)
		enemy.global_position = Vector2(1.0, 0.0)
		player.upgrade_system.apply_power(power_id)
		var before := enemy.get_current_health()
		player.notify_enemy_killed()
		_check(player.void_echo_zones.is_empty() and player._eclipse_marked_enemies.is_empty() and enemy.get_current_health() == before and enemy.velocity.is_zero_approx(), "%s no-position notification preserves non-spatial semantics" % power_id)
		player.notify_enemy_killed(Vector2.ZERO)
		var activated := false
		match power_id:
			"lacuna_echo":
				activated = not player.void_echo_zones.is_empty() and player.void_echo_zones[0]["pos"] == Vector2.ZERO
			"edict_of_the_court":
				activated = enemy.velocity.x > 0.0
			"eclipse_mark":
				activated = player._consume_eclipse_mark_bonus(enemy, 20) > 0
			"fracture_field":
				activated = enemy.get_current_health() < before
		_check(activated, "%s kill at arena origin still triggers" % power_id)
		current_scene = null
		world.free()

func _test_room_kill_dispatch() -> void:
	for mode in ["solo_normal", "solo_boss", "coop_normal", "coop_boss"]:
		var world := KillWorld.new()
		root.add_child(world)
		current_scene = world
		world.is_multiplayer = mode.begins_with("coop")
		world.active_room_enemy_count = 1
		var recorder := KillRecorder.new()
		world.run_summary_recorder = recorder
		world.objective_progress_coordinator = preload("res://scripts/core/objective_progress_coordinator.gd").new()
		var player := CombatPlayer.new()
		world.add_child(player)
		world.player = player
		player.upgrade_system.apply_power("reaper_step")
		player.upgrade_system.apply_power("lacuna_echo")
		player.dash_cooldown_left = 1.0
		var broadcaster := preload("res://scripts/core/enemy_state_sync_broadcaster.gd").new(world)
		var spawner := preload("res://scripts/enemy_spawner.gd").new()
		world.add_child(spawner)
		spawner.spawn_transport_duration = 0.0
		spawner.initialize(world, player, RandomNumberGenerator.new(), {"test": CombatEnemy}, world._on_room_enemy_died)
		var enemy: CombatEnemy
		var registered: bool = world.is_multiplayer or mode.ends_with("boss")
		if mode.ends_with("boss"):
			# Boss setup registers before connecting the room callback.
			enemy = CombatEnemy.new()
			world.add_child(enemy)
			broadcaster.register_enemy(enemy, 705)
			enemy.died.connect(func(): world._on_room_enemy_died(enemy.global_position))
		else:
			# The production spawner connects the room callback before registration.
			enemy = spawner._spawn_enemy_in_current_room(CombatEnemy)
			if registered:
				broadcaster.register_enemy(enemy, 705)
		enemy.global_position = Vector2.ZERO
		var local_peer: int = DAMAGEABLE._resolve_local_peer_id()
		var previous_player: Variant = PlayerReplicationService.player_nodes.get(local_peer)
		PlayerReplicationService.player_nodes[local_peer] = player
		var enemy_health := enemy.get_current_health()
		DAMAGEABLE.apply_damage(enemy, enemy_health)
		_check(player.kill_notifications == 1, "%s death notifies the player exactly once" % mode)
		_check(player.dash_cooldown_left == 0.0, "%s death actually activates Reaper Step" % mode)
		_check(player.void_echo_zones.size() == 1, "%s death activates Lacuna Echo once at the origin" % mode)
		_check(recorder.kills == 1 and world.active_room_enemy_count == 0, "%s records one room kill" % mode)
		_check(recorder.damage_total == enemy_health, "%s records lethal damage once" % mode)
		if registered:
			_check(recorder.peer_kills == 1 and not EnemyReplicationService.enemy_nodes_by_id.has(705) and not EnemyReplicationService.last_damage_peer_by_id.has(705), "%s keeps attribution and clears registered death state" % mode)
		if previous_player == null:
			PlayerReplicationService.player_nodes.erase(local_peer)
		else:
			PlayerReplicationService.player_nodes[local_peer] = previous_player
		current_scene = null
		world.free()
