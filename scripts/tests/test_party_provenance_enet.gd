extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Full production provenance handshake and summary gates on separate peers.

const RECORDER := preload("res://scripts/core/run_summary_recorder.gd")
const PROVENANCE := preload("res://scripts/core/run_provenance.gd")
const HISTORY := preload("res://scripts/core/run_history_store.gd")
const TELEMETRY := preload("res://scripts/run_telemetry_store.gd")
const LEADERBOARD := preload("res://scripts/core/leaderboard_entry_model.gd")

var prior_host_token: String = ""
var prior_peer_token: String = ""
var debug_finish_summary: Dictionary = {}

func _run() -> void:
	ProjectSettings.set_setting("application/config/version", "0.9.0")
	super._run()
	get_multiplayer().peer_disconnected.connect(MultiplayerSessionManager._on_peer_disconnected)

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	RunContext.set_multiplayer_session("provenance-loopback", role == "host")
	RunContext.meta_progress_profile = {}
	world.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(world)
	GameStateReplicationService.initialize(world)
	for id in [1, client_id]:
		var actor := Player.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		world.add_child(actor)
		PlayerReplicationService.register_player(id, actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor

func begin_run(version: String = "0.9.0") -> void:
	ProjectSettings.set_setting("application/config/version", version)
	HISTORY.clear_all()
	world.run_summary_recorder = RECORDER.new(world)
	var recorder = world.run_summary_recorder
	# Actual fresh-world order: initialize while checking resume, then reset.
	recorder.reset_summary_tracker()
	recorder.initialize(true)
	recorder.mark_run_start()
	recorder.run_summary_tracker.player_uuid = "isolated-" + role
	recorder._resumed_elapsed_msec = 600000

func received() -> bool:
	return world.run_summary_recorder.run_summary_tracker._received_provenance_peers.has(joiner_id)

func evidence() -> Dictionary:
	return world.run_summary_recorder.run_summary_tracker.resolved_run_provenance()

func finalize(label: String, eligible: bool) -> Dictionary:
	var recorder = world.run_summary_recorder
	recorder.finish_run("clear")
	var summary: Dictionary = recorder.latest_run_summary
	check(LEADERBOARD.is_submission_eligible(summary) == eligible, label + ": actual leaderboard eligibility agrees")
	check(TELEMETRY.build_upload_payload(recorder.telemetry_run_id).is_empty() != eligible, label + ": actual telemetry payload gate agrees")
	var history := HISTORY.load_all()
	check(history.size() == 1 and history[0].run_provenance == summary.run_provenance, label + ": one local history entry preserves full evidence")
	return summary

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	world.fixture_result_received.connect(_on_result_received)
	begin_run()
	world.fixture_command.rpc_id(client_id, "begin", {"version": "0.9.0", "key": "stable"})
	check(await until(received), "Same-release joiner completes the real run handshake")
	check(PROVENANCE.is_upload_eligible(evidence()), "Same-release peers retain eligibility")
	prior_host_token = GameStateReplicationService._host_run_token
	prior_peer_token = String(GameStateReplicationService._peer_run_tokens.get(client_id, ""))
	world.fixture_command.rpc_id(client_id, "forge", {"host": prior_host_token, "peer": prior_host_token})
	check(await until(func(): return results.has("forged")), "Joiner sends forged identity and stale token probes")
	check(PROVENANCE.is_upload_eligible(evidence()), "Another actor's token and payload peer_id cannot forge provenance ownership")
	var stable := finalize("Release party", true)
	world.fixture_command.rpc_id(client_id, "summary", {"summary": stable, "eligible": true})
	check(await until(func(): return results.has("summary")), "Joiner records the same eligible party clear locally")

	# Client can enter a new world before the host; its previous host token
	# prevents that new recorder from being accepted by the old run.
	world.fixture_command.rpc_id(client_id, "begin", {"version": "dev-joiner", "key": "dev_started"})
	check(await until(func(): return results.has("dev_started")), "Joiner can start its next recorder first")
	check(GameStateReplicationService._peer_run_tokens.get(client_id, "") == prior_peer_token, "A future client recorder cannot rebind the previous host run")
	begin_run()
	check(await until(received), "New host challenge binds the waiting development recorder")
	check(evidence().versions.has("dev-joiner") and not PROVENANCE.is_upload_eligible(evidence()), "Host retains real development joiner evidence")
	finalize("Development party", false)

	begin_run()
	await process_frame
	check(not received(), "Previous client recorder cannot answer a new run challenge")
	world.fixture_command.rpc_id(client_id, "begin", {"version": "0.9.0", "key": "debug_started"})
	check(await until(received), "A fresh matching release run begins cleanly after the development run")
	world.fixture_command.rpc_id(client_id, "replay", {"host": prior_host_token, "peer": prior_peer_token})
	check(await until(func(): return results.has("replayed")), "Previous-run evidence is replayed across actual ENet")
	check(PROVENANCE.is_upload_eligible(evidence()), "Stale evidence cannot change the current run")
	world.fixture_command.rpc_id(client_id, "debug_and_finish")
	check(await until(func(): return not debug_finish_summary.is_empty()), "The next reliable World message finalizes the debug party immediately on receipt")
	check(not LEADERBOARD.is_submission_eligible(debug_finish_summary), "Final eligibility includes debug evidence without waiting for another network round trip")

	begin_run()
	await create_timer(0.1).timeout
	check(not received() and not PROVENANCE.is_upload_eligible(evidence()), "Missing current-run peer evidence excludes only final eligibility")
	finalize("Missing party evidence", false)

	begin_run()
	await process_frame
	check(not PROVENANCE.is_upload_eligible(evidence()), "Current party initially has incomplete evidence")
	world.fixture_command.rpc_id(client_id, "begin", {"version": "0.9.0", "key": "late_started"})
	check(await until(received), "A late legitimate announcement is still accepted")
	check(PROVENANCE.is_upload_eligible(evidence()), "A prior incomplete copy never poisons late same-release evidence")
	finalize("Late release party", true)

	begin_run()
	world.fixture_command.rpc_id(client_id, "begin", {"version": "dev-disconnecting", "key": "disconnect_started"})
	check(await until(received), "Disconnect scenario captures development participation before departure")
	world.fixture_command.rpc_id(client_id, "disconnect")
	check(await until(func(): return not MultiplayerSessionManager.connected_peers.has(client_id)), "The real ENet peer disconnect reaches the production session callback")
	check(evidence().versions.has("dev-disconnecting"), "Disconnected participants' stricter evidence remains in the host run")
	finalize("Disconnected development party", false)
	await finish()

func _on_result_received(key: String, _value: Dictionary) -> void:
	if key == "debug_finish":
		# Polling after a frame would conceal this ordering bug: finalize
		# inside the very next reliable World RPC, as a combat outcome can.
		check(bool(evidence().is_debug), "Debug provenance precedes the joiner's next reliable World message")
		debug_finish_summary = finalize("Debug party", false)

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"begin":
			begin_run(String(payload.version))
			world.fixture_result.rpc_id(1, payload.key, {})
		"forge":
			var forged := PROVENANCE.start("dev-forged")
			forged["peer_id"] = 1
			GameStateReplicationService._receive_run_provenance.rpc_id(1, payload.host, payload.peer, forged)
			world.fixture_result.rpc_id(1, "forged", {})
		"replay":
			GameStateReplicationService._receive_run_provenance.rpc_id(1, payload.host, payload.peer, PROVENANCE.start("dev-stale"))
			world.fixture_result.rpc_id(1, "replayed", {})
		"debug_and_finish":
			world.run_summary_recorder.mark_debug_mode()
			world.fixture_result.rpc_id(1, "debug_finish", {})
		"summary":
			world.run_summary_recorder.finalize_synced_run_summary_for_joiner(payload.summary, "clear")
			var summary: Dictionary = world.run_summary_recorder.latest_run_summary
			check(LEADERBOARD.is_submission_eligible(summary) == bool(payload.eligible), "Joiner retains correct final party eligibility")
			check(HISTORY.load_all().size() == 1 and HISTORY.load_all()[0].run_provenance == summary.run_provenance, "Joiner retains party provenance in local history")
			world.fixture_result.rpc_id(1, "summary", {})
		"disconnect":
			# Leave the RPC stack before freeing its World and let ENet deliver
			# the graceful disconnect while presentation is stopped.
			world.process_mode = Node.PROCESS_MODE_DISABLED
			world.hide()
			await create_timer(0.05).timeout
			peer.disconnect_peer(1)
			await create_timer(0.2).timeout
			await finish()
