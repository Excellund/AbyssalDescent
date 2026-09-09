extends Node

const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")
const CONTEXT_COMBAT: StringName = &"combat"
const CONTEXT_REST: StringName = &"rest"
const CONTEXT_REWARD: StringName = &"reward"
const CONTEXT_BOSS: StringName = &"boss"
const QUIET_CONTEXT_TRIM_DB := -6.0

var normal_room_music: AudioStream
var boss_room_music: AudioStream
var music_volume_db: float = -10.0
var music_crossfade_duration: float = 0.75
var music_context: StringName = CONTEXT_COMBAT

var music_players: Array[AudioStreamPlayer] = []
var active_music_player_index: int = -1
var _transition_tween: Tween

func initialize(normal_music: AudioStream, boss_music: AudioStream, volume_db: float, crossfade_duration: float) -> void:
	normal_room_music = normal_music
	boss_room_music = boss_music
	music_volume_db = AUDIO_LEVELS.clamp_db(volume_db)
	music_crossfade_duration = crossfade_duration
	music_context = CONTEXT_COMBAT
	_create_music_players()

func set_music_volume_db(volume_db: float) -> void:
	music_volume_db = AUDIO_LEVELS.clamp_db(volume_db)
	# Settings take effect immediately. An older fade must not restore its old
	# target after a volume change, or stop a player reused by a later context.
	_cancel_transition()
	for index in range(music_players.size()):
		var player := music_players[index]
		if not is_instance_valid(player):
			continue
		if index == active_music_player_index:
			player.volume_db = _target_music_db()
		else:
			player.stop()
			player.volume_db = _crossfade_floor_db()

func play_room_music(is_boss_room: bool, instant: bool = false, fade_duration: float = -1.0) -> void:
	set_context(CONTEXT_BOSS if is_boss_room else CONTEXT_COMBAT, instant, fade_duration)

## Rest and rewards reuse the combat stream, changing only its level. Context
## changes keep existing playback where possible, including a fading-out stream.
func set_context(context: StringName, instant: bool = false, fade_duration: float = -1.0) -> void:
	if context not in [CONTEXT_COMBAT, CONTEXT_REST, CONTEXT_REWARD, CONTEXT_BOSS]:
		return
	if music_players.size() < 2:
		return
	var target_stream: AudioStream = boss_room_music if context == CONTEXT_BOSS else normal_room_music
	if target_stream == null:
		return
	var previous_context := music_context
	var current: AudioStreamPlayer = null
	if active_music_player_index >= 0 and active_music_player_index < music_players.size():
		current = music_players[active_music_player_index]
	if current != null and current.stream == target_stream and current.playing and previous_context == context and not instant:
		return
	_cancel_transition()
	music_context = context
	var next_index := active_music_player_index
	if current == null or current.stream != target_stream or not current.playing:
		next_index = 0 if active_music_player_index != 0 else 1
	var incoming := music_players[next_index]
	# A rapid boss -> combat -> boss change can reuse the outgoing boss stream.
	if incoming.stream != target_stream or not incoming.playing:
		incoming.stop()
		incoming.stream = target_stream
		incoming.volume_db = _crossfade_floor_db()
		incoming.play()
	active_music_player_index = next_index
	if instant:
		incoming.volume_db = _target_music_db()
		_stop_inactive_players()
		return
	var fade_time := music_crossfade_duration if fade_duration < 0.0 else fade_duration
	fade_time = maxf(0.05, fade_time)
	_transition_tween = create_tween()
	_transition_tween.tween_property(incoming, "volume_db", _target_music_db(), fade_time)
	for index in range(music_players.size()):
		var outgoing := music_players[index]
		if index != active_music_player_index and outgoing.playing:
			_transition_tween.parallel().tween_property(outgoing, "volume_db", _crossfade_floor_db(), fade_time)
	_transition_tween.tween_callback(_stop_inactive_players)

func _cancel_transition() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = null

func _stop_inactive_players() -> void:
	for index in range(music_players.size()):
		if index != active_music_player_index and is_instance_valid(music_players[index]):
			music_players[index].stop()

func _create_music_players() -> void:
	_cancel_transition()
	for old_player in music_players:
		if is_instance_valid(old_player):
			old_player.stop()
			remove_child(old_player)
			old_player.queue_free()
	music_players.clear()
	active_music_player_index = -1
	for i in range(2):
		var music_player := AudioStreamPlayer.new()
		music_player.autoplay = false
		music_player.volume_db = _crossfade_floor_db()
		music_player.finished.connect(_on_music_player_finished.bind(i))
		add_child(music_player)
		music_players.append(music_player)

func _exit_tree() -> void:
	_cancel_transition()

func _crossfade_floor_db() -> float:
	return AUDIO_LEVELS.crossfade_floor_db(_target_music_db())

func _target_music_db() -> float:
	var context_trim := QUIET_CONTEXT_TRIM_DB if music_context in [CONTEXT_REST, CONTEXT_REWARD] else 0.0
	return AUDIO_LEVELS.apply_trim_db(AUDIO_LEVELS.gameplay_music_db(music_volume_db), context_trim)

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
