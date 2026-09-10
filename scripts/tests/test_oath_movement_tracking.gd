extends "res://scripts/tests/test_blast_feedback.gd"
## Accepted local Dash actions and whole-run Bearing evidence for Oaths.

const TRACKER := preload("res://scripts/core/run_summary_tracker.gd")
const RECORDER := preload("res://scripts/core/run_summary_recorder.gd")
const OATH_FIXTURE := preload("res://scripts/tests/test_oath_tracking.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
const EVALUATOR := preload("res://scripts/progression/oaths_evaluator.gd")
const META := preload("res://scripts/meta_progress_store.gd")

class CallbackWorld extends "res://scripts/world_generator.gd":
	func _ready() -> void:
		pass

func _seed(catalysts: Array = [], tier: int = 3) -> Dictionary:
	return {"difficulty_tier": tier, "equipped_catalyst_ids": catalysts}

func _completes_grounded(summary: Dictionary) -> bool:
	return EVALUATOR.evaluate_run(summary, META._get_default_profile()).completed_oath_ids.has("forsworn_grounded")

func _run() -> void:
	var retirement := AUDIO_RETIREMENT.new()
	node_added.connect(retirement.observe_node)
	await _test_accepted_dash()
	_test_checkpoint_evidence()
	_test_minimum_difficulty_evidence()
	_test_joiner_evidence()
	_test_joiner_minimum_difficulty()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Oath movement fixture audio retires")
	print("[OK] Oath movement tracking: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _attempt_dash() -> void:
	# SceneTree.physics_frame is emitted before the physics step; synthesize
	# the edge on an idle frame so Godot reports its current just-pressed edge.
	await process_frame
	Input.action_press("dash")
	player._try_start_dash(Vector2.RIGHT)
	Input.action_release("dash")
	await process_frame
	await physics_frame

func _test_accepted_dash() -> void:
	_make_world(1)
	var callback_world := CallbackWorld.new()
	callback_world.run_summary_recorder = RECORDER.new(callback_world)
	var recorder = callback_world.run_summary_recorder
	recorder.run_summary_tracker.reset_for_run(_seed())
	player.normal_dash_started.connect(callback_world._on_player_normal_dash_started)
	player._try_start_dash(Vector2.RIGHT)
	_check(recorder.run_summary_tracker.dashes_performed == 0, "No Dash input creates no Dash evidence")
	for property in ["encounter_input_frozen", "attack_lock_time_left", "polar_shift_dash_lockout_left", "dash_cooldown_left"]:
		player.set(property, true if property == "encounter_input_frozen" else 1.0)
		await _attempt_dash()
		_check(recorder.run_summary_tracker.dashes_performed == 0 and not player._is_dash_active(), "Rejected Dash does not count: " + property)
		player.set(property, false if property == "encounter_input_frozen" else 0.0)
	player.local_owner = false
	await _attempt_dash()
	_check(recorder.run_summary_tracker.dashes_performed == 0, "Remote replicas never count this device's Dash input")
	player.local_owner = true
	player._combat_actions_awaiting_release.assign([&"dash"])
	await _attempt_dash()
	_check(recorder.run_summary_tracker.dashes_performed == 0, "A held reward-confirmation input cannot count as a Dash")
	player._combat_actions_awaiting_release.clear()
	await _attempt_dash()
	_check(recorder.run_summary_tracker.dashes_performed == 1 and player._is_dash_active(), "A successfully started normal Dash reaches the real World recorder once")
	player._process_active_dash(0.01)
	_check(recorder.run_summary_tracker.dashes_performed == 1, "Movement frames of an active Dash do not add starts")
	player.dash_remaining_distance = 0.0
	player.dash_time_left = 0.0
	player._set_dash_phasing(false)
	player.dash_cooldown_left = 1.0
	player._reaper_stored_dashes = 1
	await _attempt_dash()
	_check(recorder.run_summary_tracker.dashes_performed == 2 and player._reaper_stored_dashes == 0, "Spending a stored Dash still performs and counts one normal Dash")
	player.dash_remaining_distance = 0.0
	player.dash_time_left = 0.0
	player._set_dash_phasing(false)
	player.arcana_motion.release_blast(1.0)
	_check(player.arcana_motion.motion == MOTION.Motion.RECOIL and recorder.run_summary_tracker.dashes_performed == 2, "Actual Blast Recoil does not count as a normal Dash")
	player.arcana_motion.cancel()
	player.apply_trial_power("razor_orbit")
	var target := _enemy(Vector2(80.0, 0.0))
	await physics_frame
	await physics_frame
	player.arcana_motion.start_orbit(target)
	_check(player.arcana_motion.motion == MOTION.Motion.ORBIT and recorder.run_summary_tracker.dashes_performed == 2, "Actual Orbit acquisition does not add another normal Dash")
	callback_world.free()
	_free_world()

func _test_checkpoint_evidence() -> void:
	var tracker := TRACKER.new()
	tracker.reset_for_run(_seed())
	var fresh := tracker.build_summary({})
	_check(fresh.dashes_performed == 0 and fresh.dash_tracking_complete and fresh.oath_min_difficulty_tier == 3 and fresh.oath_difficulty_verified and fresh.catalyst_tracking_complete, "Explicit fresh Forsworn setup starts known counters and equipment evidence")
	tracker.record_normal_dash_started()
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(tracker.build_checkpoint()))
	var restored := TRACKER.new()
	restored.reset_for_run(_seed())
	restored.restore_checkpoint(checkpoint)
	_check(restored.dashes_performed == 1 and restored.dash_tracking_complete and restored.oath_min_difficulty_tier == 3 and restored.oath_difficulty_verified and restored.catalyst_tracking_complete, "Serialized checkpoint preserves Dash and run setup evidence")
	for key in ["dashes_performed", "dash_tracking_complete"]:
		var missing := checkpoint.duplicate(true)
		missing.erase(key)
		restored.reset_for_run(_seed())
		restored.restore_checkpoint(missing)
		_check(not restored.dash_tracking_complete and restored.full_run_tracking_complete, "Old Dash history stays unknown without invalidating other history: " + key)
	for invalid in [null, "0", -1, 0.5, INF, NAN, false]:
		var malformed := checkpoint.duplicate(true)
		malformed.dashes_performed = invalid
		restored.reset_for_run(_seed())
		restored.restore_checkpoint(malformed)
		_check(not restored.dash_tracking_complete, "Malformed Dash history cannot become known zero usage: " + str(invalid))
	for tier in [0, 1, 2, "3", 3.5, null]:
		restored.reset_for_run({"difficulty_tier": tier, "equipped_catalyst_ids": []})
		_check(not restored.oath_difficulty_verified, "Only explicit numeric Forsworn seeds qualify: " + str(tier))
		restored.record_difficulty_applied(3)
		_check(not restored.oath_difficulty_verified, "Changing an easier or unknown start to Forsworn cannot repair its evidence")
	tracker.record_difficulty_applied(0)
	tracker.record_difficulty_applied(3)
	_check(not tracker.oath_difficulty_verified, "A downgrade and return to Forsworn permanently invalidate this run's Oath difficulty proof")
	for key in ["oath_difficulty_verified", "oath_start_difficulty_tier", "catalyst_tracking_complete", "equipped_catalyst_ids"]:
		var missing := checkpoint.duplicate(true)
		missing.erase("oath_min_difficulty_tier")
		missing.erase(key)
		restored.reset_for_run(_seed())
		restored.restore_checkpoint(missing)
		_check(not restored.oath_difficulty_verified if key.begins_with("oath_") else not restored.catalyst_tracking_complete, "Legacy checkpoint cannot invent missing setup proof: " + key)
	var easier := checkpoint.duplicate(true)
	easier.oath_start_difficulty_tier = 0
	restored.reset_for_run(_seed())
	restored.restore_checkpoint(easier)
	_check(not restored.oath_difficulty_verified, "Saved easier-tier history cannot resume as a verified Forsworn run")
	restored.reset_for_run({"difficulty_tier": 0, "equipped_catalyst_ids": []})
	restored.restore_checkpoint(checkpoint)
	_check(not restored.oath_difficulty_verified, "A Forsworn save resumed at an easier tier cannot remain verified")
	tracker.reset_for_run(_seed(["reward_choice_bonus"]))
	restored.reset_for_run(_seed())
	restored.restore_checkpoint(tracker.build_checkpoint())
	_check(not restored.catalyst_tracking_complete, "Changed menu equipment cannot erase a saved equipped Catalyst")
	restored.reset_for_run(_seed(["reward_choice_bonus"]))
	restored.restore_checkpoint(tracker.build_checkpoint())
	_check(restored.catalyst_tracking_complete and restored.equipped_catalyst_ids == ["reward_choice_bonus"], "Restoring the original frozen equipment retains known Catalyst history")
	tracker.reset_for_run({"difficulty_tier": 3})
	_check(not tracker.catalyst_tracking_complete, "Missing equipment seed is unknown, not an explicitly empty loadout")
	var recorder := RECORDER.new(null)
	recorder.run_summary_tracker.reset_for_run(_seed())
	recorder.restore_tracker_items_from_snapshot({})
	_check(not recorder.run_summary_tracker.full_run_tracking_complete and not recorder.run_summary_tracker.dash_tracking_complete and recorder.run_summary_tracker.oath_min_difficulty_tier == -1 and not recorder.run_summary_tracker.oath_difficulty_verified and not recorder.run_summary_tracker.catalyst_tracking_complete, "Legacy snapshot without a checkpoint invalidates all new absence proofs")

func _test_minimum_difficulty_evidence() -> void:
	var tracker := TRACKER.new()
	var restored := TRACKER.new()
	for initial_tier in range(4):
		tracker.reset_for_run(_seed([], initial_tier))
		var summary := tracker.build_summary({"outcome": "clear"})
		_check(summary.oath_min_difficulty_tier == initial_tier and summary.oath_difficulty_verified == (initial_tier == 3), "A fresh run certifies its actual Bearing: " + str(initial_tier))
		_check(_completes_grounded(summary) == (initial_tier >= 1), "Grounded is approachable from Delver, but cannot be farmed on Pilgrim: " + str(initial_tier))
		tracker.record_difficulty_applied(3)
		_check(tracker.oath_min_difficulty_tier == initial_tier, "Applying Forsworn never erases an earlier easier segment: " + str(initial_tier))
		var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(tracker.build_checkpoint()))
		for resume_tier in range(4):
			restored.reset_for_run(_seed([], resume_tier))
			restored.restore_checkpoint(checkpoint)
			var expected: int = mini(initial_tier, resume_tier)
			_check(restored.oath_min_difficulty_tier == expected and restored.oath_difficulty_verified == (expected == 3), "Serialized source and resume Bearings preserve their minimum: %d -> %d" % [initial_tier, resume_tier])
			_check(_completes_grounded(restored.build_summary({"outcome": "clear"})) == (expected >= 1), "Resumed Grounded eligibility includes both saved and current Bearing: %d -> %d" % [initial_tier, resume_tier])
	tracker.reset_for_run(_seed())
	tracker.record_difficulty_applied(2)
	tracker.record_difficulty_applied(1)
	tracker.record_difficulty_applied(3)
	_check(tracker.oath_min_difficulty_tier == 1 and _completes_grounded(tracker.build_summary({"outcome": "clear"})), "A run that never drops below Delver still qualifies for Grounded")
	restored.reset_for_run(_seed([], 2))
	restored.restore_checkpoint(tracker.build_checkpoint())
	_check(restored.oath_min_difficulty_tier == 1, "A prior downgrade survives saving and resuming above that minimum")
	tracker.record_difficulty_applied(0)
	tracker.record_difficulty_applied(3)
	_check(tracker.oath_min_difficulty_tier == 0 and not _completes_grounded(tracker.build_summary({"outcome": "clear"})), "Any Pilgrim segment permanently disqualifies a Delver-minimum Oath")
	for invalid in [null, "3", false, true, -1, 4, 1.5, INF, NAN, [], {}]:
		tracker.reset_for_run({"difficulty_tier": invalid, "equipped_catalyst_ids": []})
		_check(tracker.oath_min_difficulty_tier == -1 and not tracker.oath_difficulty_verified, "A malformed start has unknown Bearing history: " + str(invalid))
		tracker.record_hold_full_control()
		var malformed_summary := tracker.build_summary({"outcome": "clear"})
		_check(malformed_summary.difficulty_tier == -1 and EVALUATOR.evaluate_run(malformed_summary, META._get_default_profile()).completed_oath_ids.is_empty(), "A malformed actual Bearing cannot become Pilgrim and award unrestricted Oaths: " + str(invalid))
		tracker.record_difficulty_applied(3)
		_check(tracker.oath_min_difficulty_tier == -1 and not _completes_grounded(tracker.build_summary({"outcome": "clear"})), "Reapplying a valid Bearing never repairs unknown history: " + str(invalid))
	tracker.reset_for_run(_seed())
	var modern := tracker.build_checkpoint()
	for invalid in [null, "3", false, true, -1, 4, 1.5, INF, NAN, [], {}]:
		var malformed := modern.duplicate(true)
		malformed.oath_min_difficulty_tier = invalid
		restored.reset_for_run(_seed())
		restored.restore_checkpoint(malformed)
		restored.record_difficulty_applied(3)
		_check(restored.oath_min_difficulty_tier == -1 and not restored.oath_difficulty_verified, "Explicit invalid modern minimum cannot fall back to a legacy true flag: " + str(invalid))
	for invalid in [null, "3", false, true, -1, 4, 1.5, INF, NAN]:
		var malformed := modern.duplicate(true)
		malformed.oath_start_difficulty_tier = invalid
		restored.reset_for_run(_seed())
		restored.restore_checkpoint(malformed)
		_check(restored.oath_min_difficulty_tier == -1, "A checkpoint cannot certify history with a malformed source Bearing: " + str(invalid))
	var mismatched := modern.duplicate(true)
	mismatched.oath_start_difficulty_tier = 1
	restored.reset_for_run(_seed())
	restored.restore_checkpoint(mismatched)
	_check(restored.oath_min_difficulty_tier == 1 and not restored.oath_difficulty_verified, "A contradictory easier source Bearing lowers the saved minimum")
	var legacy := modern.duplicate(true)
	legacy.erase("oath_min_difficulty_tier")
	for resume_tier in range(4):
		restored.reset_for_run(_seed([], resume_tier))
		restored.restore_checkpoint(legacy)
		_check(restored.oath_min_difficulty_tier == resume_tier, "Legacy verified Forsworn combines with the actual resume Bearing: " + str(resume_tier))
	for proof in [false, null, "true", 1]:
		var malformed := legacy.duplicate(true)
		malformed.oath_difficulty_verified = proof
		restored.reset_for_run(_seed())
		restored.restore_checkpoint(malformed)
		_check(restored.oath_min_difficulty_tier == -1, "Legacy minimum fallback requires a literal true boolean: " + str(proof))
	legacy.oath_start_difficulty_tier = 1
	restored.reset_for_run(_seed())
	restored.restore_checkpoint(legacy)
	_check(restored.oath_min_difficulty_tier == -1, "The old Forsworn-only flag never certifies unknown lower-tier history")
	modern.erase("oath_difficulty_verified")
	restored.reset_for_run(_seed())
	restored.restore_checkpoint(modern)
	_check(restored.oath_min_difficulty_tier == 3 and restored.oath_difficulty_verified, "A modern valid minimum remains authoritative without the legacy compatibility field")
	tracker.reset_for_run({"equipped_catalyst_ids": []})
	tracker.record_hold_full_control()
	_check(tracker.difficulty_tier == -1 and EVALUATOR.evaluate_run(tracker.build_summary({"outcome": "clear"}), META._get_default_profile()).completed_oath_ids.is_empty(), "A missing actual Bearing stays unknown rather than becoming a Pilgrim completion")

func _test_joiner_evidence() -> void:
	for local_dashes in [0, 1]:
		var peer_world := OATH_FIXTURE.TestWorld.new()
		var recorder := RECORDER.new(peer_world)
		recorder.run_summary_tracker.reset_for_run(_seed())
		for _index in range(local_dashes):
			recorder.record_normal_dash_started()
		var summary := {"run_id": "dash-peer-" + str(local_dashes), "outcome": "death", "difficulty_tier": 3, "oath_difficulty_verified": true, "dashes_performed": 1 - local_dashes, "dash_tracking_complete": true, "catalyst_tracking_complete": true, "equipped_catalyst_ids": ["reward_choice_bonus"]}
		recorder.finalize_synced_run_summary_for_joiner(summary, "death")
		_check(recorder.latest_run_summary.dashes_performed == local_dashes and recorder.latest_run_summary.dash_tracking_complete, "Joiner owns its Dash evidence, regardless of host use")
		_check(recorder.latest_run_summary.equipped_catalyst_ids.is_empty() and recorder.latest_run_summary.catalyst_tracking_complete, "Joiner owns its frozen Catalyst evidence")
		_check(recorder.latest_run_summary.oath_min_difficulty_tier == 3 and recorder.latest_run_summary.oath_difficulty_verified, "Matching host and local Forsworn evidence remains verified")
		peer_world.context.free()
		peer_world.free()

func _test_joiner_minimum_difficulty() -> void:
	# Local seed, later local Bearing (-2 means unchanged), host current Bearing,
	# host tracked minimum, expected shared minimum. Lower and unknown facts on
	# either side survive the joiner's replacement of the displayed setup.
	var cases: Array = [
		[3, -2, 3, 3, 3], [1, -2, 3, 3, 1], [3, -2, 1, 1, 1],
		[2, -2, 3, 1, 1], [3, -2, 1, 3, 1], [3, -2, 0, 3, 0],
		[0, -2, 3, 3, 0], [3, -2, 3, 0, 0], [-1, -2, 3, 3, -1],
		[3, -2, 3, -1, -1], [3, 1, 3, 3, 1], [3, 0, 3, 3, 0],
		[3, -2, 3, "3", -1], [3, -2, 3, true, -1], [3, -2, 3, null, -1],
	]
	for index in range(cases.size()):
		var test_case: Array = cases[index]
		var host_tracker := TRACKER.new()
		host_tracker.reset_for_run(_seed([], test_case[2]))
		var host_summary := host_tracker.build_summary({"run_id": "minimum-peer-" + str(index), "outcome": "clear"})
		host_summary.oath_min_difficulty_tier = test_case[3]
		var peer_world := OATH_FIXTURE.TestWorld.new()
		var recorder := RECORDER.new(peer_world)
		recorder.run_summary_tracker.reset_for_run(_seed([], test_case[0]))
		if test_case[1] != -2:
			recorder.record_difficulty_applied(test_case[1])
		recorder.finalize_synced_run_summary_for_joiner(host_summary, "clear")
		var merged: Dictionary = recorder.latest_run_summary
		var expected: int = test_case[4]
		_check(merged.oath_min_difficulty_tier == expected and merged.oath_difficulty_verified == (expected == 3), "Joiner preserves the lowest known host/local Bearing, or unknown history: " + str(test_case))
		_check(_completes_grounded(merged) == (expected >= 1), "Joiner Grounded eligibility uses combined host/local evidence: " + str(test_case))
		peer_world.context.free()
		peer_world.free()
	var easier_world := OATH_FIXTURE.TestWorld.new()
	var easier_recorder := RECORDER.new(easier_world)
	easier_recorder.run_summary_tracker.reset_for_run(_seed())
	easier_recorder.finalize_synced_run_summary_for_joiner({"run_id": "easier-host", "outcome": "death", "difficulty_tier": 0, "oath_difficulty_verified": true}, "death")
	_check(not easier_recorder.latest_run_summary.oath_difficulty_verified, "Local tier replacement cannot upgrade contradictory easier host evidence")
	easier_world.context.free()
	easier_world.free()
	for host_proof in [false, null, "true"]:
		var peer_world := OATH_FIXTURE.TestWorld.new()
		var recorder := RECORDER.new(peer_world)
		recorder.run_summary_tracker.reset_for_run(_seed())
		recorder.finalize_synced_run_summary_for_joiner({"run_id": "unknown-host", "outcome": "death", "oath_difficulty_verified": host_proof}, "death")
		_check(not recorder.latest_run_summary.oath_difficulty_verified, "Local Forsworn cannot replace absent or invalid host difficulty proof")
		peer_world.context.free()
		peer_world.free()
