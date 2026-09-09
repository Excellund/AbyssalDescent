extends SceneTree

const MUSIC := preload("res://scripts/music_system.gd")
const LEVELS := preload("res://scripts/shared/audio_levels.gd")
const AUDIO := preload("res://scripts/tests/fixture_audio_retirement.gd")
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

func stream() -> AudioStreamWAV:
	var value := AudioStreamWAV.new()
	value.format = AudioStreamWAV.FORMAT_8_BITS
	value.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(22050 * 10)
	bytes.fill(128)
	value.data = bytes
	return value

func _wait(seconds: float = 0.12) -> void:
	await create_timer(seconds, true).timeout

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	var music := MUSIC.new()
	root.add_child(music)
	var normal := stream()
	var boss := stream()
	music.initialize(normal, boss, -10.0, 0.75)
	check(music.music_crossfade_duration == 0.75, "Existing default fade duration remains 0.75 seconds")
	music.set_context(&"combat", true)
	var first := music.music_players[music.active_music_player_index]
	check(first.playing and first.stream == normal, "Combat starts existing normal stream")
	check(is_equal_approx(first.volume_db, LEVELS.gameplay_music_db(-10.0)), "Combat retains configured gameplay volume")
	await _wait(0.2)
	var playback := first.get_stream_playback()
	var position := first.get_playback_position()
	music.set_context(&"reward", false, 0.05)
	await _wait()
	check(first == music.music_players[music.active_music_player_index] and first.get_stream_playback() == playback, "Reward context preserves actual stream playback")
	check(first.get_playback_position() >= position, "Reward context never rewinds the music")
	check(is_equal_approx(first.volume_db, -18.0), "Rewards sit 6 dB below configured gameplay music")
	music.set_context(&"rest", false, 0.05)
	await _wait()
	check(first.get_stream_playback() == playback and is_equal_approx(first.volume_db, -18.0), "Rest reuses playback and reward level")
	music.play_room_music(false, false, 0.05)
	await _wait()
	check(first.get_stream_playback() == playback and is_equal_approx(first.volume_db, -12.0), "Compatibility API restores combat without restart")
	music.set_context(&"boss", false, 0.25)
	await _wait(0.06)
	var boss_player := music.music_players[music.active_music_player_index]
	var boss_playback := boss_player.get_stream_playback()
	music.set_context(&"combat", false, 0.25)
	await _wait(0.06)
	music.set_context(&"boss", false, 0.05)
	await _wait(0.35)
	check(boss_player.playing and boss_player.get_stream_playback() == boss_playback, "Rapid transitions reuse the live boss stream and cancel stale stop callbacks")
	check(not first.playing and is_equal_approx(boss_player.volume_db, -12.0), "Only final boss stream remains after rapid crossfades")
	music.set_context(&"reward", false, 0.4)
	music.set_music_volume_db(-26.0)
	await _wait(0.5)
	var active := music.music_players[music.active_music_player_index]
	check(is_equal_approx(active.volume_db, -34.0) and not boss_player.playing, "Settings cancel old fades and retain contextual trim")
	music.set_music_volume_db(-80.0)
	music.set_context(&"boss", false, 0.05)
	await _wait()
	check(is_equal_approx(music.music_players[music.active_music_player_index].volume_db, -80.0), "Context changes preserve mute")
	music.set_music_volume_db(-10.0)
	music.set_context(&"rest", true)
	active = music.music_players[music.active_music_player_index]
	music.set_context(&"combat", false, 0.3)
	await _wait(0.06)
	paused = true
	var paused_volume := active.volume_db
	await _wait(0.16)
	check(is_equal_approx(active.volume_db, paused_volume), "Node-bound fade respects tree pause")
	paused = false
	await _wait(0.4)
	check(is_equal_approx(active.volume_db, -12.0), "Fade completes after unpausing")
	music.set_context(&"invalid", true)
	check(music.music_context == &"combat" and active.playing, "Unknown context preserves playback")
	music.set_context(&"boss", false, 0.4)
	var retiring_ids: Array[int] = []
	for player in music.music_players:
		retiring_ids.append(player.get_instance_id())
	# Release local playback references before asserting native retirement.
	playback = null
	boss_playback = null
	music.initialize(normal, boss, -10.0, 0.75)
	await process_frame
	check(music.get_child_count() == 2 and music.active_music_player_index == -1, "Reinitialization retires the old players and transition")
	for id in retiring_ids:
		check(not is_instance_id_valid(id), "Reinitialized player is actually freed")
	music.set_context(&"boss", false, 0.4)
	var music_id := music.get_instance_id()
	music.queue_free()
	await process_frame
	check(not is_instance_id_valid(music_id), "Music owner frees during an active transition")
	check(await retirement.wait_until_retired(self), "Music fixture native audio retires")
	print("[OK] Music contexts: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
