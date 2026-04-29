extends Node

var normal_room_music: AudioStream
var boss_room_music: AudioStream
var music_volume_db: float = -10.0
var music_crossfade_duration: float = 0.75

var music_players: Array[AudioStreamPlayer] = []
var active_music_player_index: int = -1

func initialize(normal_music: AudioStream, boss_music: AudioStream, volume_db: float, crossfade_duration: float) -> void:
	normal_room_music = normal_music
	boss_room_music = boss_music
	set_music_volume_db(volume_db)
	music_crossfade_duration = crossfade_duration
	_create_music_players()

func set_music_volume_db(volume_db: float) -> void:
	music_volume_db = clampf(volume_db, -80.0, 6.0)
	for index in range(music_players.size()):
		var player := music_players[index]
		if player == null or not player.playing:
			continue
		if index == active_music_player_index:
			player.volume_db = music_volume_db
		else:
			player.volume_db = -60.0

func play_room_music(is_boss_room: bool, instant: bool = false, fade_duration: float = -1.0) -> void:
	if music_players.size() < 2:
		return

	var target_stream: AudioStream = boss_room_music if is_boss_room else normal_room_music
	if target_stream == null:
		return

	if active_music_player_index >= 0 and active_music_player_index < music_players.size():
		var current_player := music_players[active_music_player_index]
		if current_player.stream == target_stream and current_player.playing:
			return

	var next_index := 0 if active_music_player_index != 0 else 1
	var incoming := music_players[next_index]
	var outgoing: AudioStreamPlayer = null
	if active_music_player_index >= 0 and active_music_player_index < music_players.size():
		outgoing = music_players[active_music_player_index]

	incoming.stream = target_stream
	incoming.volume_db = music_volume_db if instant else -60.0
	incoming.play()

	if instant:
		if outgoing != null and outgoing != incoming:
			outgoing.stop()
		active_music_player_index = next_index
		return

	var fade_time := fade_duration
	if fade_time < 0.0:
		fade_time = music_crossfade_duration
	fade_time = maxf(0.05, fade_time)
	var tween := create_tween()
	tween.tween_property(incoming, "volume_db", music_volume_db, fade_time)
	if outgoing != null and outgoing.playing and outgoing != incoming:
		tween.parallel().tween_property(outgoing, "volume_db", -60.0, fade_time)
		tween.tween_callback(outgoing.stop)

	active_music_player_index = next_index

func _create_music_players() -> void:
	music_players.clear()
	for i in range(2):
		var music_player := AudioStreamPlayer.new()
		music_player.autoplay = false
		music_player.volume_db = -60.0
		music_player.finished.connect(_on_music_player_finished.bind(i))
		add_child(music_player)
		music_players.append(music_player)

func _on_music_player_finished(player_index: int) -> void:
	# Guarantee looping even when imported stream assets are not configured to loop.
	if player_index != active_music_player_index:
		return
	if player_index < 0 or player_index >= music_players.size():
		return
	var player := music_players[player_index]
	if player == null or player.stream == null:
		return
	player.play(0.0)
