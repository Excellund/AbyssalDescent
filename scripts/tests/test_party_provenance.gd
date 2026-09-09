extends "res://scripts/tests/test_run_provenance.gd"

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	ProjectSettings.set_setting("application/config/version", "0.9.0")
	_setup("host")
	var recorder := RECORDER.new(world)
	world.run_summary_recorder = recorder
	recorder.mark_run_start()
	recorder.initialize(true)
	var tracker = recorder.run_summary_tracker
	check(PROVENANCE.is_upload_eligible(tracker.run_provenance), "Waiting for a peer does not mutate the known live evidence")
	check(not PROVENANCE.is_upload_eligible(tracker.resolved_run_provenance()), "A final copy with an expected but unknown participant is excluded")
	var checkpoint: Dictionary = tracker.build_checkpoint()
	check(not PROVENANCE.is_upload_eligible(checkpoint.run_provenance), "Checkpoint copies preserve unknown participation")
	tracker.record_peer_provenance(2, PROVENANCE.start("0.9.0"))
	check(PROVENANCE.is_upload_eligible(tracker.resolved_run_provenance()), "A late same-release announcement restores complete live evidence")
	check(not PROVENANCE.is_upload_eligible(checkpoint.run_provenance), "Later announcements do not rewrite previously captured snapshots")
	tracker.record_peer_provenance(999, PROVENANCE.start("dev-unregistered"))
	check(PROVENANCE.is_upload_eligible(tracker.resolved_run_provenance()), "Unexpected peer identities cannot change run evidence")
	tracker.record_peer_provenance(2, PROVENANCE.start("dev-joiner"))
	tracker.record_peer_provenance(2, PROVENANCE.start("0.9.0"))
	check(not PROVENANCE.is_upload_eligible(tracker.resolved_run_provenance()) and tracker.run_provenance.versions.has("dev-joiner"), "Newer release claims cannot erase previously observed development participation")
	tracker.record_peer_provenance(2, PROVENANCE.start("0.9.0", true))
	check(tracker.resolved_run_provenance().is_debug, "Debug participation is retained independently of executable version")
	MultiplayerSessionManager.connected_peers.erase(2)
	check(not PROVENANCE.is_upload_eligible(tracker.resolved_run_provenance()), "Disconnecting a participant does not clear their stricter evidence")
	var resumed := preload("res://scripts/core/run_summary_tracker.gd").new()
	resumed.reset_for_run({"game_version": "0.9.0"})
	resumed.restore_checkpoint(tracker.build_checkpoint())
	check(resumed.run_provenance.is_debug and resumed.run_provenance.versions.has("dev-joiner"), "Checkpoint restore retains party development and debug evidence")
	await _cleanup()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[OK] Party provenance: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
