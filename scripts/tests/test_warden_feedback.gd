extends "res://scripts/tests/test_connected_build_runtime.gd"
## Accepted gameplay creates presentation; replaying presentation cannot damage.
const VERDICT := preload("res://scripts/warden_verdict_feedback.gd")

class RejectingEnemy extends ComboEnemy:
	func take_damage(_amount: int, _context: Dictionary = {}) -> void:
		pass

func _run() -> void:
	_make_world()
	player.apply_upgrade("wardens_verdict")
	var primary := _enemy(Vector2(40, 0))
	var neighbor := _enemy(Vector2(90, 0))
	var outside := _enemy(Vector2(300, 0))
	var rejected := RejectingEnemy.new()
	world.add_child(rejected)
	rejected.position = Vector2(30, 0)
	_packet(rejected, "melee")
	_check(player.player_feedback.warden_verdict == null, "Rejected damage cannot create a cadence cue")
	var first_action := player.new_combat_action("melee")
	_packet(primary, "melee", 20, 1, first_action)
	var visual: VERDICT = player.player_feedback.warden_verdict
	_check(visual != null and visual.step == 1 and visual.bursts.is_empty(), "Actual first accepted contact lights one step without a Burst")
	_check(visual.contacts.back().position == primary.position, "Accepted contact stamp uses actual hit position")
	_packet(primary, "razor_wind", 20, 1, first_action)
	_check(visual.step == 1 and player._warden_verdict_cue_serial == 1, "Overlapping attack shapes cannot replay the same contact cue")
	for index in range(2):
		_packet(primary, "melee")
	_check(visual.step == 3 and visual.remaining > 0.0 and visual.bursts.is_empty(), "Three accepted contacts show fourth-contact readiness")
	var neighbor_before := neighbor.get_current_health()
	var outside_before := outside.get_current_health()
	_packet(primary, "melee")
	_check(player.apex_predator_combo_hits == 4 and visual.step == 4 and visual.bursts.size() == 1, "Fourth native contact produces exactly one visual Burst")
	_check(visual.bursts[0].radius == player._get_apex_predator_burst_radius(), "Visible Burst boundary equals the gameplay radius")
	_check(neighbor.get_current_health() < neighbor_before and outside.get_current_health() == outside_before, "Unchanged native Burst damages inside its displayed boundary only")
	_check(player.cues.count("warden_verdict") == 4, "Four contacts publish four accepted cues without legacy duplicate FX")
	var health := primary.get_current_health()
	var damage_total := world.damage_total
	var counter := player.apex_predator_combo_hits
	var payload := {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "epoch": player.combat_interactions._epoch, "serial": 100, "step": 4, "position": Vector2(55, 20), "radius": 90.0, "duration": 2.2}
	player.apply_owner_cue_event("warden_verdict", payload)
	_check(visual.bursts.size() == 2 and primary.get_current_health() == health and world.damage_total == damage_total and player.apex_predator_combo_hits == counter, "Native owner cue receiver draws without damage, counters or procs")
	_check(not visual.apply_cue(payload), "Duplicate reliable cue cannot replay impact")
	for key in ["serial", "room", "epoch", "run", "position", "radius"]:
		var invalid := payload.duplicate(true)
		invalid.serial = 101
		match key:
			"serial": invalid.serial = 99
			"room": invalid.room += 1
			"epoch": invalid.epoch -= 1
			"run": invalid.run = "previous-run"
			"position": invalid.position = Vector2.INF
			"radius": invalid.radius = 127.0
		_check(not visual.apply_cue(invalid), "Reject stale or malformed cue: " + key)
	for index in range(20):
		payload.serial += 1
		visual.apply_cue(payload)
	_check(visual.contacts.size() == VERDICT.MAX_CONTACTS and visual.bursts.size() == VERDICT.MAX_BURSTS, "Broad attacks keep presentation queues bounded")
	var left: float = visual.bursts[0].left
	visual._process(0.1)
	_check(visual.bursts[0].left == left, "Direct player pause freezes transient feedback")
	visual.advance(0.5)
	_check(visual.bursts.is_empty() and visual.contacts.is_empty(), "Impact and contact marks expire without retained clutter")
	payload.serial += 1
	payload.step = 3
	visual.apply_cue(payload)
	visual.advance(2.3)
	_check(visual.remaining == 0.0 and not visual.is_processing(), "Readiness disappears when the unchanged combo window expires")
	payload.serial += 1
	visual.apply_cue(payload)
	player.clear_lingering_combat_effects()
	_check(visual.step == 0 and visual.contacts.is_empty() and visual.bursts.is_empty(), "Room cleanup immediately clears all Warden feedback")
	_check(not visual.apply_cue(payload), "Cleanup keeps old-epoch cues rejected")
	player.apply_upgrade("wardens_verdict")
	for index in range(4):
		_packet(primary, "melee")
	_check(visual.bursts.size() == 1 and visual.bursts[0].radius == player._get_apex_predator_burst_radius(), "Second boss pick uses its actual mapped Burst radius")
	var old_epoch := player.combat_interactions._epoch
	player.apply_run_snapshot(player.build_run_snapshot())
	var restored := payload.duplicate(true)
	restored.epoch = old_epoch
	restored.serial = 9999
	_check(not visual.apply_cue(restored), "Restore rejects a stale cue even with a greater serial")
	_packet(primary, "melee")
	_check(visual.step == 1 and visual._epoch > old_epoch, "A legitimate higher-epoch contact works after restore")
	# Same gameplay status, actual small/boss collider sizes, replicated geometry.
	var action := player.new_combat_action("melee")
	player.apply_trial_power("dread_resonance")
	_packet(primary, "melee", 20, 1, action)
	var status: Node = DAMAGEABLE._target_status(primary)
	_check(status.marker_radius() == 24.0, "Small enemy Mark fits outside its real collider")
	var boss := ComboBoss.new()
	_add_circle(boss, 34.0)
	world.add_child(boss)
	var replica_status: Node = DAMAGEABLE._target_status(boss, true)
	replica_status.apply_network_packet(DAMAGEABLE.get_status_network_packet(primary))
	_check(replica_status != null and replica_status.marker_radius() == 45.0, "Same replicated Mark clears the boss collider at actual scale")
	_check(replica_status.marks.size() == status.marks.size() and replica_status.dread == status.dread, "More readable glyph leaves replicated gameplay status unchanged")
	await _settle()
	_free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[WardenFeedback] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
