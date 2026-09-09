extends SceneTree

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const LAUNCH := preload("res://scripts/enemy_launch_state.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")

class ComboPlayer extends "res://scripts/player.gd":
	var aim: Vector2 = Vector2.RIGHT
	var cues: Array[String] = []

	func _ready() -> void:
		super._ready()
		set_physics_process(false)

	func _get_mouse_attack_direction() -> Vector2:
		return aim

	func _broadcast_cue_event(event_name: String, payload: Dictionary, reliable: bool = false) -> void:
		cues.append(event_name)
		super._broadcast_cue_event(event_name, payload, reliable)

class ComboEnemy extends "res://scripts/enemy_base.gd":
	var hits: Array[Dictionary] = []
	var behavior_ticks: int = 0

	func _ready() -> void:
		set_physics_process(false)
		max_health = 10000
		_create_health_state()
		add_to_group("enemies")
		crowd_separation_strength = 0.0

	func _process_behavior(_delta: float) -> void:
		behavior_ticks += 1

	func take_damage(amount: int, context: Dictionary = {}) -> void:
		var before := get_current_health()
		super.take_damage(amount, context)
		if get_current_health() < before:
			hits.append({"amount": before - get_current_health(), "type": context.get("attack_type", ""), "secondary": context.get("secondary", false)})

	func _on_health_state_died() -> void:
		# Keep the test body available for inspecting accepted lethal hits.
		died.emit()

class ComboBoss extends "res://scripts/enemy_boss_2.gd":
	var behavior_ticks: int = 0

	func _ready() -> void:
		set_physics_process(false)
		max_health = 10000
		_create_health_state()
		add_to_group("enemies")
		crowd_separation_strength = 0.0

	func _process_behavior(_delta: float) -> void:
		behavior_ticks += 1

class ComboWorld extends Node2D:
	var damage_total: int = 0

	func record_player_damage_dealt(amount: int, _peer: int = 0, _killed: bool = false, _enemy_id: int = 0) -> void:
		damage_total += amount

var checks: int = 0
var failures: Array[String] = []
var world: ComboWorld
var player: ComboPlayer

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _make_world() -> void:
	world = ComboWorld.new()
	root.add_child(world)
	current_scene = world
	player = ComboPlayer.new()
	_add_circle(player, 14.0)
	world.add_child(player)
	player.player_id = 1
	player.damage = 20
	player.attack_range = 78.0
	player.attack_arc_degrees = 130.0
	player.arcana_motion.set_process(false)
	player.boss_combinations.set_process(false)
	# Include the lazily created shared impact player in this fixture's audio mute.
	EnemyReplicationService._get_ruinous_feedback()
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stream = null
	for audio in world.find_children("*", "AudioStreamPlayer2D", true, false):
		(audio as AudioStreamPlayer2D).stream = null

func _free_world() -> void:
	player.discard_pending_combat_input()
	if is_instance_valid(player.upgrade_system.power_registry):
		player.upgrade_system.power_registry.free()
	current_scene = null
	world.free()
	world = null
	player = null

func _add_circle(body: CollisionObject2D, radius: float) -> void:
	var collider := CollisionShape2D.new()
	collider.shape = CircleShape2D.new()
	(collider.shape as CircleShape2D).radius = radius
	body.add_child(collider)

func _enemy(position: Vector2) -> ComboEnemy:
	var enemy := ComboEnemy.new()
	_add_circle(enemy, 13.0)
	world.add_child(enemy)
	enemy.global_position = position
	return enemy

func _wall(position: Vector2, radius: float = 20.0) -> StaticBody2D:
	var wall := StaticBody2D.new()
	_add_circle(wall, radius)
	world.add_child(wall)
	wall.global_position = position
	return wall

func _settle() -> void:
	Input.action_release("attack")
	Input.action_release("dash")
	await process_frame
	await physics_frame
	await process_frame
	if is_instance_valid(player):
		player._refresh_combat_input_release()

func _strike() -> void:
	player._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "range": 78.0, "arc_degrees": 130.0})

func _run() -> void:
	await _test_shade_levels_and_shape()
	await _test_empowered_and_extended_strikes()
	await _test_primed_oath_blast()
	await _test_riftpunch_blast()
	await _test_motion_shades()
	await _test_dash_completion_shades()
	await _test_launch_levels_and_collision()
	await _test_launch_time_and_authority()
	await _test_kill_rewards_and_corridor()
	await _test_snapshot_and_cancellation()
	await _test_kill_callback_cancellation()
	await _test_deferred_void_echo_scope()
	await _settle()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	if failures.is_empty():
		print("[BossCombinations] PASS (%d checks)" % checks)
	else:
		print("[BossCombinations] FAIL (%d/%d checks)" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func _test_shade_levels_and_shape() -> void:
	for level in [1, 2]:
		_make_world()
		for _stack in range(level):
			player.apply_upgrade("sovereigns_double")
		_check(player.sovereigns_double_stacks == level and player.ruinous_impact_stacks == 0, "Sovereign's Double L%d works independently" % level)
		var primary := _enemy(Vector2(50.0, 0.0))
		var echo_target := _enemy(Vector2(350.0, 0.0))
		var behind := _enemy(Vector2(250.0, 0.0))
		player.boss_combinations.create_shade(Vector2(300.0, 0.0))
		_check(player.boss_combinations.shade_hits == level, "L%d movement shade stores its advertised number of strikes" % level)
		for _strike_index in range(level):
			_strike()
		_check(primary.hits.size() == level and int(primary.hits[0]["amount"]) == 20, "The original melee remains unchanged with Double L%d" % level)
		_check(echo_target.hits.size() == level and int(echo_target.hits[0]["amount"]) == 11, "Double L%d repeats a strike at 55 percent from the shade" % level)
		_check(bool(echo_target.hits[0]["secondary"]) and echo_target.hits[0]["type"] == "sovereigns_double", "Shade damage has an explicit secondary cause")
		_check(behind.hits.is_empty(), "The shade repeats the directed cone rather than a full radial hit")
		_check(not echo_target.get_launch_state().active, "A shade alone never launches its target")
		_strike()
		_check(echo_target.hits.size() == level and player.boss_combinations.shade_hits == 0, "L%d shade cannot repeat extra strikes after its charges are used" % level)
		player.boss_combinations.create_shade(Vector2(300.0, 0.0))
		player.boss_combinations.create_shade(Vector2(600.0, 0.0))
		_check(player.boss_combinations.shade_position == Vector2(600.0, 0.0) and player.boss_combinations.shade_hits == level, "New movement replaces the previous shade instead of accumulating copies")
		player.boss_combinations.tick(4.01)
		_check(player.boss_combinations.shade_hits == 0, "Unspent shade expires after its bounded lifetime")
		await _settle()
		_free_world()

func _test_empowered_and_extended_strikes() -> void:
	_make_world()
	player.apply_upgrade("sovereigns_double")
	player.apply_trial_power("execution_edge")
	var primary := _enemy(Vector2(50.0, 0.0))
	var echo_target := _enemy(Vector2(350.0, 0.0))
	player.boss_combinations.create_shade(Vector2(300.0, 0.0))
	player.attack_combo_counter = player.execution_every - 1
	await _settle()
	Input.action_press("attack")
	player._try_attack_input()
	_check(not primary.hits.is_empty() and int(primary.hits[0]["amount"]) > 20, "The real attack input resolves an empowered Execution Edge strike")
	_check(not echo_target.hits.is_empty() and int(echo_target.hits[0]["amount"]) == int(round(float(primary.hits[0]["amount"]) * 0.55)), "Double copies 55 percent of the resolved empowered hit")
	_check(player.attack_combo_counter == player.execution_every, "The secondary echo cannot advance Execution Edge's primary attack count")
	await _settle()
	_free_world()
	_make_world()
	player.apply_upgrade("sovereigns_double")
	player.apply_trial_power("razor_wind")
	var inner := _enemy(Vector2(350.0, 0.0))
	var outer := _enemy(Vector2(300.0 + player.attack_range * player.razor_wind_range_scale - 4.0, 0.0))
	player.boss_combinations.create_shade(Vector2(300.0, 0.0))
	_strike()
	_check(inner.hits.size() == 1 and int(inner.hits[0]["amount"]) == 11, "Razor Wind's shade does not double-hit the inner melee band")
	_check(outer.hits.size() == 1 and outer.hits[0]["type"] == "sovereigns_double", "Razor Wind's outer band is repeated from the shade")
	_check(player.boss_combinations.shade_hits == 0, "A melee plus Razor Wind uses one shade charge")
	await _settle()
	_free_world()

func _test_motion_shades() -> void:
	_make_world()
	player.apply_upgrade("sovereigns_double")
	player.apply_upgrade("ruinous_impact")
	player.apply_trial_power("blast_drive")
	player.apply_trial_power("razor_orbit")
	var distant := _enemy(Vector2(430.0, 0.0))
	player.boss_combinations.create_shade(Vector2(300.0, 0.0))
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	_check(distant.hits.size() == 1 and distant.hits[0]["type"] == "sovereigns_double", "A deliberate Blast repeats its short cone from the shade onto a foe outside the player's reach")
	_check(not distant.get_launch_state().active, "The repeated Blast cannot launch or start another boss-reward chain")
	distant.global_position = Vector2(1000.0, 1000.0)
	player.arcana_motion._refresh_capacity()
	var recoil_origin := player.global_position
	await _settle()
	player.arcana_motion.release_blast(1.0)
	for _step in range(20):
		player.arcana_motion.process_movement(0.025, Vector2.ZERO)
		if not player.arcana_motion.owns_movement():
			break
	_check(player.boss_combinations.shade_position.is_equal_approx(recoil_origin), "A completed whiffed Blast recoil leaves a shade at its movement origin")
	var orbit_target := _enemy(player.global_position + Vector2(60.0, 0.0))
	player.boss_combinations.create_shade(Vector2(700.0, 0.0))
	player.arcana_motion.start_orbit(orbit_target)
	var cut_position := player.global_position + Vector2(5.0, 0.0)
	player.arcana_motion._apply_cut_contacts(player.global_position, cut_position)
	_check(player.boss_combinations.shade_hits == 1, "Automatic Orbit cuts never spend the next deliberate-strike shade")
	_check(not orbit_target.get_launch_state().active, "Automatic Orbit cuts cannot arm Ruinous Impact")
	player.arcana_motion.detach(false)
	_check(player.boss_combinations.shade_position.is_equal_approx(cut_position), "Ending an Orbit uses its last player contact position for the replacement shade")
	player.arcana_motion.start_orbit(orbit_target)
	player.arcana_motion.cancel()
	_check(player.boss_combinations.shade_position.is_equal_approx(cut_position), "Cancelling motion does not create a new shade")
	await _settle()
	_free_world()

func _test_primed_oath_blast() -> void:
	_make_world()
	player.apply_upgrade("sovereigns_double")
	player.apply_upgrade("unbroken_oath")
	player.apply_trial_power("blast_drive")
	var primary := _enemy(Vector2(50.0, 0.0))
	var echo_target := _enemy(Vector2(650.0, 0.0))
	player._indomitable_spirit_primed = true
	player.indomitable_damage_bank = player._get_indomitable_fill_requirement()
	player.boss_combinations.create_shade(Vector2(600.0, 0.0))
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	_check(not primary.hits.is_empty() and int(primary.hits[0]["amount"]) > 50, "A primed Unbroken Oath contributes its stored damage to a deliberate Blast")
	_check(not echo_target.hits.is_empty() and int(echo_target.hits[0]["amount"]) == int(round(float(primary.hits[0]["amount"]) * 0.55)), "The Blast shade includes the already resolved Oath bonus at 55 percent")
	_check(not player._indomitable_spirit_primed and is_zero_approx(player.indomitable_damage_bank), "Oath is spent once and the Blast echo cannot refill or spend the bank again")
	await _settle()
	_free_world()

func _test_riftpunch_blast() -> void:
	_make_world()
	player.apply_upgrade("sovereigns_double")
	player.apply_trial_power("blast_drive")
	player.apply_trial_power("riftpunch")
	var primary := _enemy(Vector2(50.0, 0.0))
	var echo_target := _enemy(Vector2(650.0, 0.0))
	player._riftpunch_window_left = player.riftpunch_window_duration
	player.boss_combinations.create_shade(Vector2(600.0, 0.0))
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	var direct_damage := 0
	for hit in primary.hits:
		if hit["type"] == "blast_drive":
			direct_damage = int(hit["amount"])
	_check(direct_damage > 50 and is_zero_approx(player._riftpunch_window_left), "A deliberate Blast consumes Riftpunch's prepared bonus into its direct strike")
	_check(echo_target.hits.size() == 1 and int(echo_target.hits[0]["amount"]) == int(round(float(direct_damage) * 0.55)), "Double copies the Riftpunch-enhanced Blast without replaying its shockwave or consumption")
	await _settle()
	_free_world()

func _test_launch_levels_and_collision() -> void:
	for level in [1, 2]:
		_make_world()
		for _stack in range(level):
			player.apply_upgrade("ruinous_impact")
		_check(player.ruinous_impact_stacks == level and player.sovereigns_double_stacks == 0, "Ruinous Impact L%d works independently" % level)
		var thrown := _enemy(Vector2(50.0, 0.0))
		_wall(Vector2(110.0, 0.0))
		await _settle()
		_strike()
		_check(thrown.get_launch_state().active, "Accepted primary hit arms Ruinous Impact L%d" % level)
		for _step in range(20):
			thrown._physics_process(0.025)
			if not thrown.get_launch_state().active:
				break
		var impacts: Array[Dictionary] = []
		for hit in thrown.hits:
			if hit["type"] == "ruinous_impact":
				impacts.append(hit)
		_check(impacts.size() == 1 and int(impacts[0]["amount"]) == (20 if level == 1 else 28), "Wall collision produces exactly one L%d impact with advertised scaling" % level)
		_check(not thrown.get_launch_state().active and thrown.global_position.x < 80.0, "Wall collision ends the bounded launch without tunnelling")
		_check(thrown.get_launch_state().cooldown_left > 0.0, "An impact retains the enemy's per-launch cooldown")
		_strike()
		_check(not thrown.get_launch_state().active, "Immediate subsequent primary hits cannot rearm the same enemy")
		await _settle()
		_free_world()
	_make_world()
	player.apply_upgrade("ruinous_impact")
	var thrown := _enemy(Vector2(50.0, 0.0))
	var struck := _enemy(Vector2(120.0, 0.0))
	thrown.collision_mask = 0
	await _settle()
	_strike()
	for _step in range(20):
		thrown._physics_process(0.025)
		if not thrown.get_launch_state().active:
			break
	_check(not struck.hits.is_empty() and struck.hits[0]["type"] == "ruinous_impact", "Swept enemy contact bursts even when enemy collision masks exclude one another")
	_check(not struck.get_launch_state().active, "Impact splash cannot relaunch another enemy")
	await _settle()
	_free_world()
	_make_world()
	player.apply_upgrade("ruinous_impact")
	var fast_thrown := _enemy(Vector2(50.0, 0.0))
	var near_victim := _enemy(Vector2(110.0, 0.0))
	fast_thrown.collision_mask = 0
	await _settle()
	_strike()
	fast_thrown._physics_process(0.5)
	_check(fast_thrown.global_position.distance_to(near_victim.global_position) < 70.0, "A hitch stops enemy collision near the first contact rather than overshooting the burst radius")
	_check(not near_victim.hits.is_empty() and near_victim.hits[0]["type"] == "ruinous_impact", "The enemy struck during a hitch receives the impact burst")
	await _settle()
	_free_world()

func _test_dash_completion_shades() -> void:
	for dash_case in ["whiff", "wall", "phantom"]:
		_make_world()
		player.apply_upgrade("sovereigns_double")
		var phantom_target: ComboEnemy = null
		if dash_case == "wall":
			_wall(Vector2(80.0, 0.0))
		elif dash_case == "phantom":
			player.apply_trial_power("phantom_step")
			phantom_target = _enemy(Vector2(65.0, 0.0))
		await _settle()
		var origin := player.global_position
		Input.action_press("dash")
		player._try_start_dash(Vector2.RIGHT)
		for _step in range(40):
			await physics_frame
			player._process_active_dash(1.0 / 60.0)
			if not player._is_dash_active():
				break
		_check(player.boss_combinations.shade_hits == 1, "%s dash completion creates exactly one shade" % dash_case)
		_check(not player.boss_combinations.dash_origin.is_finite(), "%s completion clears the pending dash origin" % dash_case)
		if dash_case == "phantom":
			_check(not phantom_target.hits.is_empty() and player.boss_combinations.shade_position.x > origin.x, "Phantom Step moves the shade to its actual last dash contact")
		else:
			_check(player.boss_combinations.shade_position.is_equal_approx(origin), "%s dash uses its origin when no attack connects" % dash_case)
		await _settle()
		_free_world()

func _test_launch_time_and_authority() -> void:
	_make_world()
	player.global_position = Vector2(-500.0, 0.0)
	var enemy := _enemy(Vector2.ZERO)
	var bursts: Array[Vector2] = []
	var callback := func(position: Vector2): bursts.append(position)
	var state := enemy.get_launch_state()
	_check(state.arm(Vector2(3000.0, 0.0), false, 1, player.get_instance_id(), callback), "A new explicit launch arms once")
	_check(not state.arm(Vector2.RIGHT, false, 1, player.get_instance_id(), callback), "An active launch cannot be overwritten")
	await _settle()
	state.step(enemy, 3.0)
	_check(enemy.global_position.x <= 240.01 and enemy.global_position.x > 0.0, "A large frame hitch cannot extend a 750-speed launch beyond 0.32 seconds")
	_check(not state.active and bursts.is_empty(), "An unobstructed timeout ends without a free impact explosion")
	state.cooldown_left = 0.0
	state.arm(Vector2(200.0, 0.0), false, 1, player.get_instance_id(), callback)
	enemy.set_network_simulation_enabled(false)
	var remote_position := enemy.global_position
	enemy._physics_process(0.2)
	_check(enemy.global_position == remote_position and is_equal_approx(state.remaining, 0.32), "Remote replicas never simulate authoritative launches")
	state.cancel()
	enemy.set_network_simulation_enabled(true)
	state.cooldown_left = 0.0
	enemy.global_position = Vector2.ZERO
	player.global_position = Vector2(60.0, 0.0)
	player.add_to_group("combat_players")
	await _settle()
	state.arm(Vector2(500.0, 0.0), false, 1, player.get_instance_id(), callback)
	state.step(enemy, 0.2)
	_check(bursts.is_empty() and not state.active, "Colliding with a player ends the launch without an impact burst")
	var boss := ComboBoss.new()
	world.add_child(boss)
	boss.global_position = Vector2(500.0, 500.0)
	_check(DAMAGEABLE.is_displacement_immune(boss), "Actual boss ancestry selects compression instead of displacement")
	player.ruinous_impact_stacks = 1
	player.boss_combinations.launch_enemy(boss, Vector2(700.0, 0.0), 1)
	var boss_origin := boss.global_position
	boss._physics_process(0.10)
	_check(boss.get_launch_state().compression and boss.behavior_ticks == 1 and boss.global_position == boss_origin, "Compression preserves the boss's normal AI tick and position")
	boss._physics_process(0.10)
	_check(boss.behavior_ticks == 2 and not boss.get_launch_state().active and boss.global_position == boss_origin, "Compression resolves once without interrupting subsequent boss behavior")
	await _settle()
	_free_world()

func _test_kill_rewards_and_corridor() -> void:
	_make_world()
	player.apply_upgrade("sovereigns_double")
	player.apply_upgrade("ruinous_impact")
	player.apply_upgrade("edict_of_the_court")
	player.apply_trial_power("reaper_step")
	var echo_target := _enemy(Vector2(350.0, 0.0))
	var neighbor := _enemy(Vector2(410.0, 0.0))
	echo_target.set_health(5)
	echo_target.died.connect(func(): player.notify_enemy_killed(echo_target.global_position))
	player.dash_cooldown_left = 1.0
	player.boss_combinations.create_shade(Vector2(300.0, 0.0))
	_strike()
	_check(echo_target.is_dead() and player.dash_cooldown_left == 0.0, "A shade kill retains Reaper Step's ordinary kill benefit")
	_check(neighbor.velocity.length() > 0.0 and not neighbor.get_launch_state().active, "A shade kill can trigger Edict's push without recursively arming Ruinous Impact")
	_check(player.boss_combinations.shade_hits == 0, "A shade kill cannot replenish its own strike charge")
	await _settle()
	_free_world()
	_make_world()
	player.apply_upgrade("ruinous_impact")
	player.apply_upgrade("null_corridor")
	var corridor_target := _enemy(Vector2(60.0, 0.0))
	player._apply_null_corridor_segment(Vector2(1.0, 0.0), Vector2(100.0, 0.0))
	player._update_null_corridor_segments(0.1)
	_check(corridor_target.get_launch_state().active, "Null Corridor's explicit enemy deflection can arm Ruinous Impact")
	var launch_duration := corridor_target.get_launch_state().remaining
	player._update_null_corridor_segments(0.1)
	_check(is_equal_approx(corridor_target.get_launch_state().remaining, launch_duration), "Repeated corridor checks cannot overwrite an active launch")
	await _settle()
	_free_world()

func _test_snapshot_and_cancellation() -> void:
	_make_world()
	for reward in ["ruinous_impact", "sovereigns_double"]:
		player.apply_upgrade(reward)
		player.apply_upgrade(reward)
	var enemy := _enemy(Vector2(50.0, 0.0))
	var snapshot := player.build_run_snapshot()
	player.boss_combinations.create_shade(Vector2(300.0, 0.0))
	_strike()
	_check(enemy.get_launch_state().active, "Fixture has an active launch before snapshot restore")
	player.apply_run_snapshot(snapshot)
	_check(player.ruinous_impact_stacks == 2 and player.sovereigns_double_stacks == 2, "Save restore retains both boss reward levels")
	_check(player.boss_combinations.shade_hits == 0 and not enemy.get_launch_state().active, "Save restore removes transient shades and owned launches")
	for interruption in ["modal", "focus", "death"]:
		player.set_alive(true)
		player.encounter_input_frozen = false
		enemy.get_launch_state().cooldown_left = 0.0
		player.boss_combinations.create_shade(Vector2(300.0, 0.0))
		player.boss_combinations.launch_enemy(enemy, Vector2(600.0, 0.0), 1)
		match interruption:
			"modal":
				player.encounter_input_frozen = true
				player.discard_pending_combat_input()
			"focus":
				player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"death":
				player.set_alive(false)
		_check(player.boss_combinations.shade_hits == 0 and not enemy.get_launch_state().active, "%s cancellation clears both boss reward transients" % interruption)
	player.set_alive(true)
	player.encounter_input_frozen = false
	player.boss_combinations.apply_shade_visual({"position": Vector2(300.0, 0.0), "hits": 2, "life": 4.0})
	var before := enemy.get_current_health()
	player.boss_combinations.show_echo({"position": enemy.global_position, "direction": Vector2.RIGHT, "range": 80.0, "arc": 130.0, "life": 0.2})
	player.boss_combinations.tick(0.1)
	_check(enemy.get_current_health() == before and not enemy.get_launch_state().active, "Remote shade and strike cues are visual-only")
	await _settle()
	_free_world()

func _test_kill_callback_cancellation() -> void:
	_make_world()
	player.apply_upgrade("sovereigns_double")
	player.apply_upgrade("ruinous_impact")
	var primary := _enemy(Vector2(50.0, 0.0))
	var first_echo := _enemy(Vector2(350.0, 0.0))
	var later_echo := _enemy(Vector2(360.0, 10.0))
	first_echo.set_health(5)
	first_echo.died.connect(func():
		player.encounter_input_frozen = true
		player.discard_pending_combat_input()
	)
	player.boss_combinations.create_shade(Vector2(300.0, 0.0))
	_strike()
	_check(first_echo.is_dead() and later_echo.hits.is_empty(), "A synchronous reward modal during an echo stops the remaining copied hits")
	_check(player.boss_combinations.shade_hits == 0 and not primary.get_launch_state().active, "Kill callback cancellation cannot leave an owned launch or shade running")
	_check(not DAMAGEABLE.is_launch_suppressed(), "Synchronous cancellation releases secondary-damage scope after the interrupted hit")
	await _settle()
	_free_world()

func _test_deferred_void_echo_scope() -> void:
	for kill_cause in ["double", "impact", "primary"]:
		_make_world()
		player.apply_upgrade("sovereigns_double")
		player.apply_upgrade("ruinous_impact")
		player.apply_upgrade("lacuna_echo")
		var kill_position := Vector2(50.0, 0.0) if kill_cause == "primary" else Vector2(350.0, 0.0)
		var victim := _enemy(kill_position)
		victim.set_health(5)
		victim.died.connect(func(): player.notify_enemy_killed(victim.global_position))
		if kill_cause == "double":
			player.boss_combinations.create_shade(Vector2(300.0, 0.0))
			_strike()
		elif kill_cause == "impact":
			player.boss_combinations._impact(kill_position, 20, 70.0, 1, Vector2.RIGHT, player.new_combat_action("melee"))
		else:
			_strike()
		var secondary_origin: bool = kill_cause != "primary"
		_check(victim.is_dead() and player.void_echo_zones.size() == 1, "%s kill retains Lacuna Echo's zone reward" % kill_cause)
		_check(bool(player.void_echo_zones[0].get("suppress_launch", false)) == secondary_origin, "%s zone remembers whether it originated from secondary damage" % kill_cause)
		var neighbor := _enemy(kill_position + Vector2(40.0, 0.0))
		var pulse_victim := _enemy(kill_position + Vector2(45.0, 0.0))
		pulse_victim.set_health(1)
		pulse_victim.died.connect(func(): player.notify_enemy_killed(pulse_victim.global_position))
		var original_life := float(player.void_echo_zones[0]["life"])
		player._update_void_echo_zones(0.1)
		_check(not neighbor.hits.is_empty() and neighbor.velocity.x < 0.0, "%s deferred zone still damages and pulls nearby enemies" % kill_cause)
		_check(neighbor.get_launch_state().active != secondary_origin, "%s zone preserves the correct launch eligibility on its later pulse" % kill_cause)
		_check(pulse_victim.is_dead() and player.void_echo_zones.size() == 1 and float(player.void_echo_zones[0]["life"]) < original_life, "%s zone's own kill cannot renew its zone into a loop" % kill_cause)
		_check(not DAMAGEABLE.is_launch_suppressed() and player._void_echo_pulse_kill_suppression_depth == 0, "%s deferred pulse releases both suppression scopes" % kill_cause)
		if kill_cause == "double":
			var modal_victim := _enemy(kill_position + Vector2(40.0, 0.0))
			modal_victim.set_health(1)
			modal_victim.died.connect(func():
				player.void_echo_zones.clear()
				player.discard_pending_combat_input()
			)
			player._update_void_echo_zones(0.4)
			_check(player.void_echo_zones.is_empty() and not DAMAGEABLE.is_launch_suppressed() and player._void_echo_pulse_kill_suppression_depth == 0, "A modal clearing a secondary zone during its pulse leaves no suppression or stale zone behind")
		await _settle()
		_free_world()
