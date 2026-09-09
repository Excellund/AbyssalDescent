extends "res://scripts/tests/test_checkpoint_isolation.gd"

const TELEMETRY := preload("res://scripts/run_telemetry_store.gd")
const LEADERBOARD := preload("res://scripts/core/leaderboard_entry_model.gd")
const PROVENANCE := preload("res://scripts/core/run_provenance.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Run provenance requires a disposable project and user profile")
		quit(1)
		return
	var configured_version: Variant = ProjectSettings.get_setting("application/config/version")
	for scenario in [
		{"name": "same release", "versions": ["0.9.0", "0.9.0"], "eligible": true},
		{"name": "dev to release", "versions": ["dev-playtest", "0.9.0"], "eligible": false},
		{"name": "release through dev", "versions": ["0.9.0", "dev-playtest", "0.9.0"], "eligible": false},
		{"name": "mixed releases", "versions": ["0.9.0", "0.10.0"], "eligible": false},
		{"name": "debug origin", "versions": ["0.9.0", "0.9.0"], "debug": true, "eligible": false},
		{"name": "legacy tracker", "versions": ["0.9.0", "0.9.0"], "legacy": "tracker", "eligible": false},
		{"name": "legacy checkpoint", "versions": ["0.9.0", "0.9.0"], "legacy": "all", "eligible": false},
		{"name": "malformed provenance", "versions": ["0.9.0", "0.9.0"], "legacy": "malformed", "eligible": false},
		{"name": "partial provenance", "versions": ["0.9.0", "0.9.0"], "legacy": "partial", "eligible": false},
		{"name": "missing debug evidence", "versions": ["0.9.0", "0.9.0"], "legacy": "debug_missing", "eligible": false}
	]:
		await _test_resume(scenario)
	_test_peer_provenance()
	_test_reused_tracker()
	await _test_debug_bootstrap()
	await _test_joiner_summary()
	ProjectSettings.set_setting("application/config/version", configured_version)
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	HISTORY.clear_all()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await create_timer(0.1).timeout
	print("[OK] Run provenance: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_resume(scenario: Dictionary) -> void:
	var label := String(scenario.name)
	var versions: Array = scenario.versions
	ProjectSettings.set_setting("application/config/version", versions[0])
	_setup("solo")
	var recorder := RECORDER.new(world)
	world.run_summary_recorder = recorder
	recorder.mark_run_start()
	recorder.initialize(not bool(scenario.get("debug", false)))
	world.player.apply_trial_power("returning_crescent")
	recorder.record_damage_dealt(1000)
	var snapshot := world._build_active_run_snapshot()
	check(snapshot.tracker_checkpoint.run_provenance.origin_version == versions[0], label + ": real world snapshot captures the starting build")
	check(snapshot.player_snapshot.trial_power_stacks.get("returning_crescent", 0) == 1, label + ": provenance does not discard learned powers")
	match String(scenario.get("legacy", "")):
		"tracker": snapshot.tracker_checkpoint.erase("run_provenance")
		"all": snapshot.erase("tracker_checkpoint")
		"malformed": snapshot.tracker_checkpoint.run_provenance = "unknown old format"
		"partial": snapshot.tracker_checkpoint.run_provenance = {"origin_known": true, "origin_version": "0.9.0"}
		"debug_missing": snapshot.tracker_checkpoint.run_provenance.erase("is_debug")
	for index in range(1, versions.size()):
		check(RunContext.save_active_run(snapshot), label + ": checkpoint writes through the production save API")
		var loaded := RunContext.load_active_run()
		ProjectSettings.set_setting("application/config/version", versions[index])
		recorder = RECORDER.new(world)
		world.run_summary_recorder = recorder
		recorder.run_started_at_msec = maxi(1, Time.get_ticks_msec())
		recorder.reset_summary_tracker()
		recorder.restore_tracker_items_from_snapshot(loaded)
		recorder.initialize(true)
		snapshot = world._build_active_run_snapshot()
	var provenance: Dictionary = recorder.run_summary_tracker.run_provenance
	var legacy := scenario.has("legacy")
	check(bool(provenance.origin_known) == not legacy, label + ": origin completeness survives restore")
	check(recorder.run_summary_tracker.game_version == ("unknown" if legacy else String(versions[0])), label + ": restore cannot relabel the original build as the current executable")
	check(bool(provenance.is_debug) == bool(scenario.get("debug", false)), label + ": debug eligibility survives a normal resume")
	for version in versions:
		if not legacy:
			check(provenance.versions.has(version), label + ": observed build is retained locally: " + version)
	check(PROVENANCE.is_upload_eligible(provenance) == bool(scenario.eligible), label + ": resume eligibility matches known single-build release provenance")
	if String(scenario.get("legacy", "")) != "all":
		check(recorder.run_summary_tracker.total_damage_dealt == 1000, label + ": prior combat statistics remain intact")
	recorder.run_summary_tracker.player_uuid = "isolated-provenance-player"
	recorder._resumed_elapsed_msec = 600000
	RunContext.meta_progress_profile = {} # This test concerns history/submission, not awarding profile unlocks.
	recorder.finish_run("clear")
	var summary: Dictionary = recorder.latest_run_summary
	check(summary.run_provenance == provenance and summary.game_version == recorder.run_summary_tracker.game_version, label + ": final local summary retains build evidence")
	check(HISTORY.load_all().size() == 1 and HISTORY.load_all()[0].run_provenance == provenance, label + ": local history remains available for excluded resumes")
	check(TELEMETRY.is_upload_payload_eligible(summary) == bool(scenario.eligible), label + ": final telemetry gate preserves resume exclusion")
	if not bool(scenario.get("debug", false)):
		check(LEADERBOARD.is_submission_eligible(summary) == bool(scenario.eligible), label + ": final leaderboard gate preserves resume exclusion")
	if not recorder.telemetry_run_id.is_empty():
		var stored := TELEMETRY.get_run_by_id(recorder.telemetry_run_id)
		check(stored.run_provenance == provenance, label + ": local event store retains build evidence")
		var payload := TELEMETRY.build_upload_payload(recorder.telemetry_run_id)
		check(payload.is_empty() != bool(scenario.eligible), label + ": excluded local telemetry cannot create an upload payload")
		if not payload.is_empty():
			check(not payload.has("run_provenance") and payload.game_version == versions[0], "Eligible upload retains the server schema and correct build")
	await _cleanup()

func _test_peer_provenance() -> void:
	var stable := PROVENANCE.start("0.9.0")
	check(PROVENANCE.is_upload_eligible(PROVENANCE.merge(stable, stable)), "Identical release peers preserve eligibility")
	check(not PROVENANCE.is_upload_eligible(PROVENANCE.merge(stable, PROVENANCE.start("dev-playtest"))), "A dev peer cannot inherit release eligibility from a host summary")
	check(not PROVENANCE.is_upload_eligible(PROVENANCE.merge(stable, null)), "An unknown peer origin cannot inherit release eligibility")
	check(not PROVENANCE.is_upload_eligible(PROVENANCE.merge(stable, PROVENANCE.start("0.9.0", true))), "A debug peer remains excluded even on a matching version")

func _test_reused_tracker() -> void:
	var tracker := preload("res://scripts/core/run_summary_tracker.gd").new()
	tracker.reset_for_run({"game_version": "0.10.0"})
	tracker.restore_run_provenance(PROVENANCE.start("dev-first-save"))
	tracker.restore_run_provenance(PROVENANCE.start("0.9.0"))
	check(tracker.game_version == "0.9.0" and tracker.run_provenance.versions == ["0.9.0", "0.10.0"], "Reusing a tracker observes the actual current executable, independently of the previous save's origin")
	check(not PROVENANCE.is_upload_eligible(tracker.run_provenance), "A second restore cannot hide mixed release versions on a reused tracker")

func _test_joiner_summary() -> void:
	for local_version in ["0.9.0", "dev-joiner"]:
		ProjectSettings.set_setting("application/config/version", local_version)
		_setup("joiner")
		var recorder := RECORDER.new(world)
		world.run_summary_recorder = recorder
		recorder.mark_run_start()
		recorder.initialize(true)
		var host_summary := {"run_id": "isolated-host-clear", "outcome": "clear", "game_version": "0.9.0", "run_provenance": PROVENANCE.start("0.9.0"), "player_uuid": "isolated-host", "duration_seconds": 600, "difficulty_tier": 0}
		RunContext.meta_progress_profile = {}
		recorder.finalize_synced_run_summary_for_joiner(host_summary, "clear")
		var summary: Dictionary = recorder.latest_run_summary
		check(summary.run_provenance.versions.has(local_version), "Production joiner summary retains its local executable version: " + local_version)
		check(LEADERBOARD.is_submission_eligible(summary) == (local_version == "0.9.0"), "Host release summary cannot remove a dev joiner's exclusion")
		check(HISTORY.load_all().size() == 1 and HISTORY.load_all()[0].run_provenance == summary.run_provenance, "Production joiner history preserves version evidence")
		await _cleanup()

func _test_debug_bootstrap() -> void:
	ProjectSettings.set_setting("application/config/version", "0.9.0")
	_setup("solo")
	var recorder := RECORDER.new(world)
	world.run_summary_recorder = recorder
	# Production bootstrap initializes during resume detection, then marks a new
	# run only if no checkpoint was resumed. Debug evidence must survive that reset.
	recorder.reset_summary_tracker()
	recorder.initialize(false)
	recorder.mark_run_start()
	var snapshot := world._build_active_run_snapshot()
	check(recorder._run_is_debug and snapshot.tracker_checkpoint.run_provenance.is_debug, "initialize(debug) -> new-run reset preserves checkpoint debug evidence")
	check(RunContext.save_active_run(snapshot), "Debug bootstrap checkpoint writes through the real save API")
	var resumed := RECORDER.new(world)
	world.run_summary_recorder = resumed
	resumed.reset_summary_tracker()
	resumed.restore_tracker_items_from_snapshot(RunContext.load_active_run())
	resumed.initialize(true)
	check(resumed._run_is_debug and resumed.run_summary_tracker.run_provenance.is_debug, "Normal resume cannot erase debug provenance from the new-run bootstrap")
	check(not resumed.telemetry_enabled and not PROVENANCE.is_upload_eligible(resumed.run_summary_tracker.run_provenance), "Debug bootstrap history remains excluded after resume")
	await _cleanup()
