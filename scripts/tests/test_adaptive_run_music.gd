extends SceneTree

const MUSIC := preload("res://scripts/music_system.gd")
const SCORE := preload("res://scripts/shared/riot_depth_catalogue.gd")
const LEVELS := preload("res://scripts/shared/audio_levels.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")
const SHORT_OGG := preload("res://sounds/footstep_concrete_000.ogg")
const BEAT := 60.0 / SCORE.BPM
const BAR := BEAT * 4.0
const DRIVE := Vector4(1.0, 0.0, 0.0, 0.0)
const PURSUIT := Vector4(0.0, 1.0, 0.0, 0.0)
const PRESSURE := Vector4(0.0, 0.0, 1.0, 0.0)
const BOSS := Vector4(0.0, 0.0, 0.0, 1.0)

var checks := 0
var failures: Array[String] = []
var retirement := AUDIO.new()

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _wait(seconds: float = 0.06) -> void:
	await create_timer(seconds, true).timeout

func _layers() -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	for layer in SCORE.LAYERS:
		result.append(layer as AudioStream)
	return result

func _legacy_stream() -> AudioStreamWAV:
	var value := AudioStreamWAV.new()
	value.format = AudioStreamWAV.FORMAT_8_BITS
	value.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(22050 * 3)
	bytes.fill(128)
	value.data = bytes
	return value

func _valid_weights(weights: Vector4) -> bool:
	if not weights.is_finite():
		return false
	var total := 0.0
	for index in range(4):
		if weights[index] < -0.0001 or weights[index] > 1.0001:
			return false
		total += weights[index]
	return absf(total - 1.0) < 0.0001

func _observe_fade(music, duration: float, label: String) -> void:
	var valid := true
	var deadline := Time.get_ticks_msec() + int(duration * 1000.0)
	while Time.get_ticks_msec() < deadline:
		valid = valid and _valid_weights(music.get_score_weights())
		var source := music.music_players[music.active_music_player_index].stream as AudioStreamSynchronized
		var native_sum := 0.0
		for index in range(1, 5):
			native_sum += db_to_linear(source.get_sync_stream_volume(index))
		valid = valid and absf(native_sum - 1.0) < 0.0001 and is_zero_approx(source.get_sync_stream_volume(0))
		await _wait(0.025)
	check(valid and _valid_weights(music.get_score_weights()), label)

func _await_blend(music) -> bool:
	var deadline := Time.get_ticks_msec() + int((BAR + 0.35) * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var weights: Vector4 = music.get_score_weights()
		if maxf(maxf(weights.x, weights.y), maxf(weights.z, weights.w)) < 0.995:
			return true
		await _wait(0.015)
	return false

func _active_count(music) -> int:
	var count := 0
	for player in music.music_players:
		if player.playing:
			count += 1
	return count

func _check_native_loop(source: AudioStreamSynchronized) -> void:
	# The native synchronized player does not expose its sub-playback objects.
	# Solo each configured layer in an independent native transport, then mix
	# across the real OGG boundary. This detects a layer silently ending while
	# the other looping layers keep the aggregate player alive.
	var isolated := source.duplicate(true) as AudioStreamSynchronized
	for solo in range(isolated.stream_count):
		for index in range(isolated.stream_count):
			isolated.set_sync_stream_volume(index, 0.0 if index == solo else -INF)
		var layer := isolated.get_sync_stream(solo) as AudioStreamOggVorbis
		check(layer != null and layer.loop, "Native score layer %d is a looping OGG" % solo)
		if layer == null:
			continue
		var native := isolated.instantiate_playback()
		native.start(maxf(0.0, layer.get_length() - 0.04))
		# AudioServer's actual mix rate may differ from the encoded 48 kHz.
		var frames := int(ceil(AudioServer.get_mix_rate() * 0.16))
		var before_and_after := native.mix_audio(1.0, frames)
		var after_wrap := native.mix_audio(1.0, frames)
		var energy := 0.0
		for frame in after_wrap:
			energy += frame.length_squared()
		check(before_and_after.size() == frames and after_wrap.size() == frames,
			"Native score layer %d supplies complete buffers through its loop" % solo)
		check(native.is_playing() and energy > 0.00000001,
			"Native score layer %d remains audible after its loop boundary" % solo)
		native.stop()
		native = null

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Adaptive music fixture requires isolated user data")
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	var layers := _layers()
	var normal := _legacy_stream()
	var boss := _legacy_stream()
	var music := MUSIC.new()
	root.add_child(music)
	music.initialize(normal, boss, -10.0, 0.75)
	music.set_context(&"combat", true)
	var legacy_player: AudioStreamPlayer = music.music_players[music.active_music_player_index]
	var legacy_playback := legacy_player.get_stream_playback()
	var missing: Array[AudioStream] = []
	check(not music.configure_adaptive_score(missing, SCORE.BPM), "Missing layers reject adaptive configuration")
	check(not music.configure_adaptive_score(layers, 0.0), "Zero tempo rejects adaptive configuration")
	var invalid_layers: Array[AudioStream] = layers.duplicate()
	invalid_layers[4] = null
	check(not music.configure_adaptive_score(invalid_layers, SCORE.BPM), "A null variation rejects adaptive configuration")
	invalid_layers[4] = normal
	check(not music.configure_adaptive_score(invalid_layers, SCORE.BPM), "Unsupported WAV layers reject adaptive configuration")
	invalid_layers[4] = SHORT_OGG
	check(not music.configure_adaptive_score(invalid_layers, SCORE.BPM), "An OGG with a mismatched length rejects adaptive configuration")
	check(not music.is_adaptive_score() and legacy_player.playing and legacy_player.stream == normal
		and legacy_player.get_stream_playback() == legacy_playback, "Invalid configuration retains live legacy playback")
	legacy_playback = null
	check(music.configure_adaptive_score(layers, SCORE.BPM), "Five Riot Depth layers configure successfully")
	if not music.is_adaptive_score():
		music.queue_free()
		await process_frame
		await _finish()
		return
	music.set_run_location(1, 0, false)
	music.set_context(&"combat", true)
	var active: AudioStreamPlayer = music.music_players[music.active_music_player_index]
	var synchronized := active.stream as AudioStreamSynchronized
	var playback := active.get_stream_playback()
	check(synchronized != null and playback is AudioStreamPlaybackSynchronized, "The game uses native synchronized stream playback")
	check(_active_count(music) == 1, "One player owns every score variation")
	check(music.get_score_weights().is_equal_approx(DRIVE), "Act I depth zero selects Drive")
	check(music.get_normal_score_variant() == 0 and music.get_selected_score_variant() == 0, "Normal and selected room identities match the entered location")
	check(is_equal_approx(active.volume_db, LEVELS.gameplay_music_db(-10.0)), "Adaptive master uses only the gameplay trim")
	if synchronized == null:
		playback = null
		music.queue_free()
		await process_frame
		await _finish()
		return
	check(synchronized.stream_count == 5, "Native playback contains the bed, three normal variations and distinct boss music")
	var length := layers[0].get_length()
	for index in range(synchronized.stream_count):
		check(absf(synchronized.get_sync_stream(index).get_length() - length) < 0.002,
			"Score layer %d retains the shared musical length" % index)
		check(synchronized.get_sync_stream(index) != layers[index], "Score layer %d receives owner-local loop settings" % index)
	_check_native_loop(synchronized)

	var initial_position := active.get_playback_position()
	music.set_run_location(1, 1, false)
	check(music.get_normal_score_variant() == 1 and music.get_selected_score_variant() == 1, "The next room selects Pursuit deterministically")
	check(music.get_score_weights().is_equal_approx(DRIVE), "Location metadata alone does not jump or fade the live mix")
	music.set_context(&"combat", false, 0.25)
	check(await _await_blend(music), "The same combat context starts a new room's variation after its bar boundary")
	var before_reward := music.get_score_weights()
	var before_selection_volume := active.volume_db
	music.set_context(&"reward")
	check(music.get_score_weights().is_equal_approx(before_reward) and music.get_selected_score_variant() == 1, "Reward selection preserves the in-progress room mixture and its destination")
	check(is_equal_approx(active.volume_db, before_selection_volume), "Reward selection does not duck the master volume")
	music.set_context(&"doors")
	check(music.get_score_weights().is_equal_approx(before_reward) and music.get_selected_score_variant() == 1, "Door selection also leaves the in-progress mixture untouched")
	await _observe_fade(music, 0.38, "A room fade continues through reward and door selection with complementary gains")
	check(music.get_score_weights().is_equal_approx(PURSUIT), "Selection contexts cannot cancel the room variation that was already blending")
	check(active.get_stream_playback() == playback and _active_count(music) == 1, "Entering rooms and opening selections preserve native playback")
	check(active.get_playback_position() >= initial_position, "Room and selection changes do not rewind the score")
	music.set_context(&"reward", true)
	music.set_context(&"doors", true)
	await _wait()
	check(music.get_score_weights().is_equal_approx(PURSUIT) and is_equal_approx(active.volume_db, before_selection_volume), "Settled selection contexts keep the exact music and level even for instant requests")

	music.set_run_location(1, 2, false)
	music.set_context(&"combat", false, 0.25)
	check(await _await_blend(music), "Settings test reaches a live variation blend")
	var before_settings := music.get_score_weights()
	music.set_music_volume_db(-26.0)
	check(music.get_score_weights().is_equal_approx(before_settings), "Volume settings do not jump an in-progress variation")
	await _observe_fade(music, 0.36, "Volume changes preserve native complementary gains")
	check(music.get_score_weights().is_equal_approx(PRESSURE), "A variation finishes after a master setting changes")
	check(is_equal_approx(active.volume_db, LEVELS.gameplay_music_db(-26.0)), "An older variation fade cannot restore an outdated master setting")
	music.set_music_volume_db(-80.0)
	music.set_run_location(2, 4, true)
	check(music.get_normal_score_variant() == 2 and music.get_selected_score_variant() == 3, "Boss location retains the normal slot and selects its separate boss identity")
	music.set_context(&"boss", true)
	check(active.volume_db <= -79.9 and music.get_score_weights().is_equal_approx(BOSS), "Boss music is distinct from normal combat and retains mute")
	music.set_context(&"reward")
	music.set_context(&"doors")
	check(music.get_score_weights().is_equal_approx(BOSS) and music.get_selected_score_variant() == 3, "Boss rewards and exits keep the defeated chamber's boss music")
	check(active.get_stream_playback() == playback, "Mute, boss entry and boss selections preserve native playback")
	music.set_music_volume_db(-10.0)
	check(is_equal_approx(active.volume_db, LEVELS.gameplay_music_db(-10.0)), "Unmuting a selection restores the unchanged gameplay master")
	music.set_context(&"rest", true)
	check(music.get_score_weights().is_equal_approx(PRESSURE), "Rest explicitly selects the normal variation for its location")

	music.set_run_location(1, 0, false)
	music.set_context(&"combat")
	check(music.get_score_weights().is_equal_approx(PRESSURE), "A default room change does not jump immediately")
	await _observe_fade(music, BAR * 2.0 + 0.15, "The default next-bar one-bar fade keeps the sum at unity")
	check(music.get_score_weights().is_equal_approx(DRIVE), "A default room fade completes within its bar wait plus four beats")

	music.set_run_location(1, 1, false)
	music.set_context(&"combat", false, 0.30)
	check(await _await_blend(music), "Rapid room redirect test reaches an audible partial blend")
	var before_redirect := music.get_score_weights()
	music.set_run_location(1, 2, false)
	music.set_context(&"combat", false, 0.30)
	# A native mix block can advance between these two observations.
	check(music.get_score_weights().distance_to(before_redirect) < 0.14, "Redirecting a room transition starts near the current mixture")
	await _wait(0.04)
	music.set_run_location(2, 0, false)
	music.set_context(&"combat", false, 0.30)
	await _wait(0.04)
	music.set_run_location(3, 0, false)
	music.set_context(&"combat", false, 0.30)
	music.set_context(&"combat", false, 0.30)
	await _observe_fade(music, BAR + 0.42, "Rapid same-context room changes keep every native variation gain complementary")
	check(music.get_score_weights().is_equal_approx(PRESSURE) and music.get_selected_score_variant() == 2, "The last entered location wins and stale room targets cannot return")
	check(active.get_stream_playback() == playback, "Rapid room changes never replace native playback")

	music.set_context(&"boss", false, 0.30)
	check(await _await_blend(music), "Pause test reaches a live boss transition")
	paused = true
	await _wait(0.04)
	var paused_weights := music.get_score_weights()
	var paused_position := active.get_playback_position()
	await _wait(0.15)
	check(music.get_score_weights().is_equal_approx(paused_weights), "Tree pause freezes an in-progress variation")
	check(absf(active.get_playback_position() - paused_position) < 0.04, "Tree pause freezes the score clock")
	paused = false
	await _observe_fade(music, 0.40, "The paused variation resumes with complementary gains")
	check(music.get_score_weights().is_equal_approx(BOSS), "The boss variation reaches its target after unpausing")
	check(active.get_stream_playback() == playback, "Pause and resume retain the native playback")
	music.set_context(&"invalid", true)
	check(music.music_context == &"boss" and music.get_score_weights().is_equal_approx(BOSS), "Unknown contexts preserve the current variation")

	music.set_run_location(1, 0, false)
	music.set_context(&"combat", true)
	# AudioStreamPlayer.seek deliberately creates a new native playback.
	# Capture its post-seek baseline before checking automatic loop continuity.
	playback = null
	active.seek(length - 0.16)
	await _wait(0.04)
	playback = active.get_stream_playback()
	music.set_run_location(1, 1, false)
	music.set_context(&"combat", false, 0.10)
	await _observe_fade(music, 0.45, "A bar-quantized room fade stays complementary across the real loop boundary")
	check(active.playing and active.get_stream_playback() == playback and playback.get_loop_count() > 0, "Native score playback loops automatically without a replacement")
	check(active.get_playback_position() < 1.0 and music.get_score_weights().is_equal_approx(PURSUIT), "The clock wraps and a scheduled room transition still completes")

	var other := MUSIC.new()
	root.add_child(other)
	other.initialize(normal, boss, -10.0, 0.75)
	check(other.configure_adaptive_score(layers, SCORE.BPM), "A second owner can use the same score catalogue")
	other.set_run_location(1, 0, false)
	other.set_context(&"combat", true)
	var other_player: AudioStreamPlayer = other.music_players[other.active_music_player_index]
	var other_stream := other_player.stream as AudioStreamSynchronized
	check(other_stream != synchronized, "Each owner receives an independent synchronized resource")
	var other_volume := other_stream.get_sync_stream_volume(1)
	music.set_context(&"boss", true)
	check(other.get_score_weights().is_equal_approx(DRIVE) and is_equal_approx(other_stream.get_sync_stream_volume(1), other_volume), "One owner's boss entry cannot alter another owner's variation")
	check(is_zero_approx(synchronized.get_sync_stream_volume(0)) and is_zero_approx(other_stream.get_sync_stream_volume(0)), "The common bed is mixed exactly once at unity")
	other.queue_free()
	await process_frame
	check(active.playing and active.get_stream_playback() == playback, "Retiring another owner leaves this score running")

	music.set_context(&"combat", false, 0.4)
	var retired_player_ids: Array[int] = []
	for player in music.music_players:
		retired_player_ids.append(player.get_instance_id())
	playback = null
	music.initialize(normal, boss, -10.0, 0.75)
	await process_frame
	check(not music.is_adaptive_score() and music.active_music_player_index == -1, "Reinitialization resets adaptive state and cancels the pending fade")
	for id in retired_player_ids:
		check(not is_instance_id_valid(id), "Reinitialization frees each retired score player")
	music.set_context(&"combat", true)
	check(music.music_players[music.active_music_player_index].stream == normal, "Legacy playback remains available after adaptive reinitialization")
	check(music.configure_adaptive_score(layers, SCORE.BPM), "The reinitialized owner can configure the score again")
	music.set_run_location(1, 0, false)
	music.set_context(&"combat", true)
	music.set_context(&"boss", false, 0.4)
	var owner_id := music.get_instance_id()
	music.queue_free()
	await process_frame
	check(not is_instance_id_valid(owner_id), "A music owner frees during a pending room transition")
	await _finish()

func _finish() -> void:
	check(await retirement.wait_until_retired(self), "Adaptive fixture native audio fully retires")
	print("[OK] Adaptive run music: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
