extends "res://scripts/tests/test_live_arena_edges.gd"

const DAMAGE := preload("res://scripts/shared/damageable.gd")
const BREAKWATER := preload("res://scripts/enemy_breakwater.gd")

class Breakwater extends "res://scripts/enemy_breakwater.gd":
	var hits: Array[Dictionary] = []
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		var before := get_current_health()
		super.take_damage(amount, context)
		if get_current_health() < before:
			var entry := context.duplicate(true)
			entry["applied"] = before - get_current_health()
			hits.append(entry)

var breakwater: Breakwater

func _setup_combo(position: Vector2 = Vector2(100.0, 0.0)) -> void:
	_setup()
	actor.aim = Vector2.RIGHT
	breakwater = Breakwater.new()
	_circle(breakwater, BREAKWATER.BODY_RADIUS)
	room.add_child(breakwater)
	breakwater.global_position = position
	breakwater.target = actor
	breakwater.target_candidates = [actor]

func _lock() -> void:
	breakwater._begin_tracking()
	breakwater._process_behavior(BREAKWATER.TRACK_TIME)
	_check(breakwater.phase == BREAKWATER.Phase.LOCK, "Real tracking produces a locked charge")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	await _test_blast_and_orbit()
	await _test_orbit_cover_and_anchor_death()
	await _test_double_and_execution()
	await _test_crescent_legs()
	await _test_ruinous_compression()
	await _test_secondary_kill_rewards()
	await _test_target_death_after_lock()
	await _test_modal_cleanup()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Breakwater combinations: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_blast_and_orbit() -> void:
	_setup_combo()
	actor.apply_trial_power("blast_drive")
	actor.arcana_motion.tick(0.0)
	actor.apply_trial_power("razor_orbit")
	await physics_frame
	_lock()
	var origin := breakwater.charge_origin
	var endpoint := breakwater.charge_end
	actor.arcana_motion.start_orbit(breakwater)
	actor.arcana_motion.process_movement(0.03, Vector2.ZERO)
	_check(actor.arcana_motion.anchor == breakwater and actor.arcana_motion.motion == MOTION.Motion.ORBIT, "Breakwater is a valid deliberately selected Orbit anchor")
	actor.arcana_motion.release_blast(1.0)
	_check(actor.arcana_motion.motion == MOTION.Motion.RECOIL and actor.arcana_motion.anchor == null, "Blast release detaches Orbit from Breakwater immediately")
	_check(breakwater.hits.any(func(hit: Dictionary) -> bool: return hit.get("attack_type") == "blast_drive"), "Blast Drive damages the Apex through the normal attack path")
	actor.arcana_motion.process_movement(0.2, Vector2.ZERO)
	_check(actor.global_position.is_finite() and actor.arcana_motion.motion == MOTION.Motion.NONE and actor._dash_damage_immune_left <= 0.0, "Completed recoil remains finite and adds no dash immunity")
	_check(breakwater.charge_origin == origin and breakwater.charge_end == endpoint and breakwater.phase == BREAKWATER.Phase.LOCK, "Orbit and Blast do not rewrite the committed Apex lane")
	_clear()

func _test_orbit_cover_and_anchor_death() -> void:
	_setup_combo(Vector2.ZERO)
	actor.global_position = Vector2(0.0, 100.0)
	actor.apply_trial_power("razor_orbit")
	await physics_frame
	_lock()
	breakwater._process_behavior(BREAKWATER.LOCK_TIME)
	actor.arcana_motion.start_orbit(breakwater)
	var player_start := actor.global_position
	breakwater._process_behavior(0.08)
	actor.arcana_motion.process_movement(0.08, Vector2.ZERO)
	_check(breakwater.global_position.y > 40.0 and actor.global_position.is_finite() and actor.global_position.distance_to(player_start) <= MOTION.ORBIT_SPEED * 0.08 + 0.1, "Orbit follows a moving charge anchor with bounded player motion")
	var wall := StaticBody2D.new()
	_circle(wall, 22.0)
	room.add_child(wall)
	wall.global_position = actor.global_position + actor.arcana_motion.tangent * 30.0
	await physics_frame
	actor.arcana_motion.process_movement(0.15, Vector2.ZERO)
	_check(actor.arcana_motion.motion != MOTION.Motion.ORBIT and actor.arcana_motion.anchor == null, "Terrain collision detaches an orbit around the moving Apex safely")
	wall.queue_free()
	await process_frame
	actor.arcana_motion.start_orbit(breakwater)
	breakwater.queue_free()
	actor.arcana_motion.process_movement(0.02, Vector2.ZERO)
	_check(actor.arcana_motion.motion != MOTION.Motion.ORBIT and actor.arcana_motion.anchor == null, "A disappearing Breakwater cannot leave a stale Orbit anchor")
	_clear()

func _test_double_and_execution() -> void:
	_setup_combo(Vector2(60.0, 0.0))
	actor.apply_trial_power("execution_edge")
	actor.apply_upgrade("sovereigns_double")
	actor.apply_upgrade("ruinous_impact")
	actor.boss_combinations.create_shade(Vector2.ZERO)
	actor.attack_combo_counter = actor.execution_every - 1
	await physics_frame
	actor._try_execute_attack(Vector2.RIGHT)
	var primary: Array = breakwater.hits.filter(func(hit: Dictionary) -> bool: return not bool(hit.get("secondary", false)))
	var secondary: Array = breakwater.hits.filter(func(hit: Dictionary) -> bool: return hit.get("attack_type") == "sovereigns_double")
	_check(primary.size() == 1 and secondary.size() == 1, "One deliberate Execution strike and one Double echo are accepted by Breakwater")
	if primary.size() == 1 and secondary.size() == 1:
		_check(int(secondary[0].applied) == int(round(float(primary[0].applied) * 0.55)), "Double retains the resolved empowered damage at its existing strength")
	_check(actor.attack_combo_counter == actor.execution_every and actor.boss_combinations.shade_hits == 0, "Secondary Apex damage neither advances Execution nor refills a shade")
	_clear()

func _test_crescent_legs() -> void:
	_setup_combo()
	actor.apply_trial_power("returning_crescent")
	actor.apply_upgrade("ruinous_impact")
	await physics_frame
	_check(actor.returning_crescent.try_launch(Vector2.RIGHT), "A returning blade launches toward the Apex")
	_advance_crescent(1.0)
	_check(breakwater.hits.size() == 2 and breakwater.hits.all(func(hit: Dictionary) -> bool: return hit.get("attack_type") == "returning_crescent" and bool(hit.get("secondary", false))), "Breakwater takes one correctly classified Crescent hit on each leg")
	_check(not breakwater.get_launch_state().active and actor.returning_crescent.blades.is_empty(), "Crescent damage does not recursively arm Ruinous and the caught blade clears")
	_clear()

func _test_ruinous_compression() -> void:
	_setup_combo()
	actor.apply_upgrade("ruinous_impact")
	await physics_frame
	_lock()
	var origin := breakwater.global_position
	var endpoint := breakwater.charge_end
	DAMAGE.apply_damage(breakwater, 20, {"attack_type": "melee"}, 1)
	var state = breakwater.get_launch_state()
	_check(DAMAGE.is_displacement_immune(breakwater) and state.active and state.compression, "Real Apex identity selects Ruinous compression instead of displacement")
	state.step(breakwater, 0.17)
	_check(breakwater.global_position == origin and breakwater.phase == BREAKWATER.Phase.LOCK and breakwater.charge_end == endpoint, "Compression preserves position and locked charge geometry")
	var impacts: Array = breakwater.hits.filter(func(hit: Dictionary) -> bool: return hit.get("attack_type") == "ruinous_impact")
	_check(impacts.size() == 1 and bool(impacts[0].get("secondary", false)) and not state.active, "Compression produces one secondary burst without rearming itself")
	_clear()

func _test_secondary_kill_rewards() -> void:
	_setup_combo()
	actor.global_position = Vector2(-300.0, 200.0)
	actor.apply_upgrade("sovereigns_double")
	actor.apply_upgrade("ruinous_impact")
	actor.apply_upgrade("edict_of_the_court")
	actor.apply_trial_power("reaper_step")
	var neighbor := _enemy(Vector2(150.0, 0.0))
	breakwater.set_max_health_and_current(5)
	breakwater.died.connect(func(): actor.notify_enemy_killed(breakwater.global_position))
	actor.dash_cooldown_left = 1.0
	actor.boss_combinations.create_shade(Vector2(30.0, 0.0))
	await physics_frame
	actor._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "range": 78.0, "arc_degrees": 130.0})
	_check(breakwater.is_dead() and actor.dash_cooldown_left == 0.0, "Secondary Apex kills retain the existing Reaper Step kill benefit")
	_check(neighbor.velocity.length() > 0.0 and not neighbor.get_launch_state().active, "Edict's existing kill push works without recursively arming Ruinous")
	_clear()

func _test_modal_cleanup() -> void:
	_setup_combo()
	actor.apply_trial_power("razor_orbit")
	actor.apply_trial_power("returning_crescent")
	room.combat_phase_coordinator = preload("res://scripts/core/combat_phase_coordinator.gd").new()
	actor.arcana_motion.start_orbit(breakwater)
	actor.returning_crescent.try_launch(Vector2.RIGHT)
	_lock()
	breakwater.set_physics_process(true)
	var remaining := breakwater.phase_left
	room._set_combat_paused(true)
	await physics_frame
	await physics_frame
	_check(not breakwater.is_physics_processing() and breakwater.phase_left == remaining, "A real modal pause freezes the locked Apex instead of advancing an unseen hazard")
	_check(actor.arcana_motion.anchor == null and actor.returning_crescent.blades.is_empty(), "Modal cleanup cancels player motion anchors and active returning blades")
	room._set_combat_paused(false)
	breakwater.set_physics_process(false)
	actor.discard_pending_combat_input()
	_check(actor.arcana_motion.anchor == null and actor.returning_crescent.blades.is_empty(), "Repeated release/focus-style cancellation leaves no player effects attached to the Apex")
	_clear()


func _test_target_death_after_lock() -> void:
	_setup_combo()
	await physics_frame
	_lock()
	var origin := breakwater.charge_origin
	var endpoint := breakwater.charge_end
	actor.set_health(0)
	actor.global_position = Vector2(300.0, 250.0)
	breakwater._process_behavior(BREAKWATER.LOCK_TIME)
	breakwater._process_behavior(0.8)
	_check(breakwater.phase == BREAKWATER.Phase.RECOVER and breakwater.charge_origin == origin and breakwater.charge_end == endpoint, "A target dying after lock cannot cancel or retarget the committed lane")
	_check(breakwater._hit_players.is_empty() and actor.get_current_health() == 0, "A locked charge cannot hit its dead target")
	_clear()