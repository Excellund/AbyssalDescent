extends SceneTree

const MOTION := preload("res://scripts/arcana_motion_controller.gd")
const IMPACT := preload("res://scripts/blast_impact_effect.gd")
const CHARACTER := preload("res://scripts/character_registry.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")

class BlastPlayer extends "res://scripts/player.gd":
	var local_owner := true
	var cues: Array[Dictionary] = []
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _is_local_control_owner() -> bool:
		return local_owner
	func _get_mouse_attack_direction() -> Vector2:
		return Vector2.RIGHT
	func _broadcast_cue_event(event_name: String, payload: Dictionary, _reliable: bool = false) -> void:
		cues.append({"name": event_name, "payload": payload.duplicate(true), "frozen": encounter_input_frozen})

class BlastEnemy extends "res://scripts/enemy_base.gd":
	func _ready() -> void:
		set_physics_process(false)
		max_health = 10000
		_create_health_state()
		add_to_group("enemies")

class BlastWorld extends Node2D:
	var damage_recorded := 0
	func record_player_damage_dealt(amount: int, _peer: int = 0, _killed: bool = false, _enemy: int = 0) -> void:
		damage_recorded += amount

var checks := 0
var failures: Array[String] = []
var world: BlastWorld
var player: BlastPlayer

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _make_world(level: int = 1) -> void:
	world = BlastWorld.new()
	root.add_child(world)
	current_scene = world
	player = BlastPlayer.new()
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	(shape.shape as CircleShape2D).radius = 14.0
	player.add_child(shape)
	world.add_child(player)
	player.apply_character_package(CHARACTER.get_character("bastion"))
	for _index in range(level):
		player.apply_trial_power("blast_drive")
	player.arcana_motion.set_process(false)
	player.arcana_motion.hide()
	player.arcana_motion._refresh_capacity()
	player.global_position = Vector2(26.0, -18.0)
	for audio_node in world.find_children("*", "AudioStreamPlayer", true, false):
		(audio_node as AudioStreamPlayer).stream = null
	for audio_node in world.find_children("*", "AudioStreamPlayer2D", true, false):
		(audio_node as AudioStreamPlayer2D).stream = null

func _enemy(offset: Vector2) -> BlastEnemy:
	var enemy := BlastEnemy.new()
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	(shape.shape as CircleShape2D).radius = 13.0
	enemy.add_child(shape)
	world.add_child(enemy)
	enemy.global_position = player.global_position + offset
	return enemy

func _free_world() -> void:
	if is_instance_valid(player.upgrade_system.power_registry):
		player.upgrade_system.power_registry.free()
	current_scene = null
	world.free()
	world = null
	player = null

func _run() -> void:
	await _test_blast_boundaries()
	await _test_resolved_geometry_feedback()
	await _test_world_anchored_remote_feedback()
	await _test_cancel_and_last_kill_feedback()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[BlastFeedback] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_blast_boundaries() -> void:
	var expected_scales: Array[float] = [1.0, 1.15, 1.30, 1.56]
	for level in range(1, 5):
		for strength in [0.0, 1.0]:
			_make_world(level)
			var expected_range := (100.0 if strength == 0.0 else 160.0) * expected_scales[level - 1]
			var center := _enemy(Vector2(expected_range - 2.0, 0.0))
			var beyond_range := _enemy(Vector2(expected_range + 22.0, 0.0))
			var inside_cone := _enemy(Vector2.RIGHT.rotated(deg_to_rad(34.0)) * expected_range * 0.85)
			var old_wide_flank := _enemy(Vector2.RIGHT.rotated(deg_to_rad(48.0)) * expected_range * 0.85)
			var old_far_target := _enemy(Vector2(285.0, 0.0))
			await physics_frame
			var origin := player.global_position
			var expected_damage := maxi(1, int(round(float(player.damage) * (1.5 if strength == 0.0 else 2.5) * expected_scales[level - 1])))
			player.arcana_motion.release_blast(strength)
			var effect := player.arcana_motion._blast_effects.back() as IMPACT
			_check(is_equal_approx(effect.reach, expected_range) and effect.arc_degrees == 70.0, "Blast L%d strength%.1f draws the same compact geometry used by actual hits" % [level, strength])
			_check(center.get_current_health() == 10000 - expected_damage and inside_cone.get_current_health() == 10000 - expected_damage, "Blast L%d strength%.1f retains damage inside the shorter 70-degree cone" % [level, strength])
			_check(beyond_range.get_current_health() == 10000 and old_far_target.get_current_health() == 10000, "Blast L%d strength%.1f cannot reach the former distant area" % [level, strength])
			_check(old_wide_flank.get_current_health() == 10000, "Blast L%d strength%.1f excludes targets only covered by the old 100-degree cone" % [level, strength])
			_check(center.velocity.x > 0.0 and beyond_range.velocity == Vector2.ZERO and old_wide_flank.velocity == Vector2.ZERO and old_far_target.velocity == Vector2.ZERO, "Blast push uses the same reduced hit area as damage")
			player.arcana_motion.process_movement(0.50, Vector2.ZERO)
			_check(absf(origin.distance_to(player.global_position) - (90.0 if strength == 0.0 else 170.0)) < 0.01, "Blast recoil distance remains unchanged while its attack reach shrinks")
			_free_world()

func _latest_cue(event_name: String) -> Dictionary:
	for index in range(player.cues.size() - 1, -1, -1):
		if player.cues[index]["name"] == event_name:
			return player.cues[index]
	return {}

func _test_resolved_geometry_feedback() -> void:
	_make_world()
	# Primed Unbroken Oath increases reach, and Iron Retort adds 24 degrees. These
	# are resolved inside the real melee pipeline after Blast's base geometry.
	player.indomitable_spirit_damage_reduction = 0.1
	player._indomitable_spirit_primed = true
	player.indomitable_damage_bank = player._get_indomitable_fill_requirement()
	player.passive_iron_retort = true
	player.iron_retort_brace_ready = true
	var extended := _enemy(Vector2(175.0, 0.0))
	var widened := _enemy(Vector2.RIGHT.rotated(deg_to_rad(48.0)) * 140.0)
	await physics_frame
	player.arcana_motion.release_blast(1.0)
	var effect := player.arcana_motion._blast_effects.back() as IMPACT
	var payload: Dictionary = _latest_cue("motion_blast")["payload"]
	_check(extended.get_current_health() < 10000 and widened.get_current_health() < 10000, "Existing primed reach and Retort angle bonuses still affect Blast hits")
	_check(effect.reach > 160.0 and effect.arc_degrees == 94.0 and payload["range"] == effect.reach and payload["arc"] == effect.arc_degrees, "Owner and remote feedback carry final modified hit geometry")
	_check(effect.hits.size() == 2, "Only accepted direct hits create impact glints")
	_free_world()

func _test_world_anchored_remote_feedback() -> void:
	_make_world()
	var target := _enemy(Vector2(130.0, 0.0))
	await physics_frame
	var fire_origin := player.global_position
	player.arcana_motion.release_blast(1.0)
	var owner_effect := player.arcana_motion._blast_effects.back() as IMPACT
	var payload: Dictionary = _latest_cue("motion_blast")["payload"]
	var hit_payload: Dictionary = _latest_cue("motion_blast_hit")["payload"]
	_check(owner_effect.global_position == fire_origin and owner_effect.hits == [target.global_position], "The discharged effect records firing origin and accepted target position")
	var replica := BlastPlayer.new()
	replica.local_owner = false
	world.add_child(replica)
	replica.arcana_motion.set_process(false)
	replica.global_position = Vector2(-250.0, 180.0)
	replica.apply_network_cue_event("motion_blast", payload)
	replica.apply_network_cue_event("motion_blast_hit", hit_payload)
	var remote_effect := replica.arcana_motion._blast_effects.back() as IMPACT
	_check(remote_effect.global_position == fire_origin and remote_effect.reach == owner_effect.reach and remote_effect.arc_degrees == owner_effect.arc_degrees and remote_effect.hits == owner_effect.hits, "A joiner displays the same world-space blast and hit glints")
	player.global_position += Vector2(-120.0, 25.0)
	replica.global_position += Vector2(160.0, -65.0)
	_check(owner_effect.global_position == fire_origin and remote_effect.global_position == fire_origin, "Neither owner recoil nor replicated movement drags the blast across the arena")
	player.discard_pending_combat_input()
	replica.discard_pending_combat_input()
	_check(not owner_effect.is_queued_for_deletion() and not remote_effect.is_queued_for_deletion(), "Input cancellation preserves an already discharged impact on both peers")
	replica.apply_network_cue_event("motion_blast_hit", {"position": Vector2(999.0, 999.0), "serial": int(payload["serial"]) + 1})
	_check(remote_effect.hits.size() == 1, "A hit from another shot cannot attach to the current blast")
	for index in range(20):
		replica.apply_network_cue_event("motion_blast_hit", {"position": Vector2(float(index), 1.0), "serial": int(payload["serial"])})
	_check(remote_effect.hits.size() == 10, "A burst of hit cues has a bounded number of visible glints")
	owner_effect._process(0.30)
	remote_effect._process(0.30)
	_check(not owner_effect.is_queued_for_deletion() and not remote_effect.is_queued_for_deletion(), "Impact feedback stays visible for the readable 300ms portion of its lifetime")
	owner_effect._process(0.04)
	remote_effect._process(0.04)
	_check(owner_effect.is_queued_for_deletion() and remote_effect.is_queued_for_deletion(), "Owner and replica effects expire after 320ms even while input is canceled")
	await process_frame
	replica.apply_network_cue_event("motion_blast_hit", hit_payload)
	_check(not is_instance_valid(remote_effect) and replica.arcana_motion._blast_effects.size() == 1, "A delayed hit cue safely skips an expired effect without creating a replacement")
	if is_instance_valid(replica.upgrade_system.power_registry):
		replica.upgrade_system.power_registry.free()
	_free_world()

func _test_cancel_and_last_kill_feedback() -> void:
	_make_world()
	player.arcana_motion.on_primary_pressed(true)
	player.discard_pending_combat_input()
	player.arcana_motion.tick(0.70)
	_check(player.arcana_motion._blast_effects.is_empty() and _latest_cue("motion_blast").is_empty(), "Canceling an unfired charge never creates a blast visual")
	var victim := _enemy(Vector2(140.0, 0.0))
	victim.health_state.set_health(1)
	var evidence := {"feedback_before_modal": false}
	victim.died.connect(func():
		evidence["feedback_before_modal"] = not _latest_cue("motion_blast").is_empty() and not player.arcana_motion._blast_effects.is_empty()
		player.encounter_input_frozen = true
		player.discard_pending_combat_input()
	)
	await physics_frame
	player.arcana_motion.release_blast(1.0)
	_check(bool(evidence["feedback_before_modal"]) and player.encounter_input_frozen, "The final killing Blast publishes its impact before reward-screen cancellation")
	_check(not player.arcana_motion.owns_movement() and not bool(_latest_cue("motion_blast")["frozen"]), "Opening rewards does not restart recoil or publish a late firing event")
	var effect := player.arcana_motion._blast_effects.back() as IMPACT
	_check(not effect.is_queued_for_deletion() and effect.hits.size() == 1 and effect.process_mode == Node.PROCESS_MODE_ALWAYS, "The final-hit effect remains visible through the modal and can finish its own short lifetime")
	var live_effect: WeakRef = weakref(effect)
	_free_world()
	_check(live_effect.get_ref() == null, "Leaving the player's scene also removes discharged effects")
