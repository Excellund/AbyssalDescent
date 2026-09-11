extends Node

const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")
const CONTEXT_COMBAT: StringName = &"combat"
const CONTEXT_REST: StringName = &"rest"
const CONTEXT_REWARD: StringName = &"reward"
const CONTEXT_DOORS: StringName = &"doors"
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
var _adaptive_stream: AudioStreamSynchronized
var _score_bpm := 140.0
var _score_weights := Vector4(1.0, 0.0, 0.0, 0.0)
var _score_from := Vector4(1.0, 0.0, 0.0, 0.0)
var _score_target := Vector4(1.0, 0.0, 0.0, 0.0)
var _score_transition_start := -1.0
var _score_transition_duration := 0.0
var _normal_score_variant := 0
var _selected_score_variant := 0

func initialize(normal_music: AudioStream, boss_music: AudioStream, volume_db: float, crossfade_duration: float) -> void:
	_adaptive_stream = null
	_score_transition_start = -1.0
	_normal_score_variant = 0
	_selected_score_variant = 0
	normal_room_music = normal_music
	boss_room_music = boss_music
	music_volume_db = AUDIO_LEVELS.clamp_db(volume_db)
	music_crossfade_duration = crossfade_duration
	music_context = CONTEXT_COMBAT
	_create_music_players()

## A private synchronized resource keeps every layer on the same audio clock,
## even at zero gain. Never change its streams after playback has begun: doing
## so reinstantiates the engine's child playbacks. Only their gains may change.
func configure_adaptive_score(layers: Array[AudioStream], bpm: float) -> bool:
	if layers.size() != 5 or not is_finite(bpm) or bpm <= 0.0 or music_players.size() != 2:
		return false
	var duration := 0.0
	for layer in layers:
		# OGG reports native loop counts. WAV's playback does not, which would
		# make a beat-scheduled transition lose its clock at the first wrap.
		if not layer is AudioStreamOggVorbis:
			return false
		if layer.get_length() <= 0.0:
			return false
		if duration > 0.0 and absf(layer.get_length() - duration) > 1.0 / 48000.0:
			return false
		duration = layer.get_length()
	var synchronized := AudioStreamSynchronized.new()
	synchronized.stream_count = layers.size()
	for index in range(layers.size()):
		var layer := layers[index].duplicate() as AudioStreamOggVorbis
		layer.loop = true
		layer.loop_offset = 0.0
		synchronized.set_sync_stream(index, layer)
	_create_music_players()
	_adaptive_stream = synchronized
	normal_room_music = synchronized
	boss_room_music = synchronized
	_score_bpm = bpm
	_score_transition_start = -1.0
	_score_weights = _weights_for_context(music_context)
	_score_target = _score_weights
	_apply_score_weights(_score_weights)
	return true

func is_adaptive_score() -> bool:
	return _adaptive_stream != null

func get_score_weights() -> Vector4:
	return _score_weights

## Update the chamber identity before requesting its context. This is derived
## from run progress, so Continue and both peers select the same arrangement.
## Selection UI never calls this: its existing music and blend keep running.
func set_run_location(act: int, depth: int, boss_chamber: bool = false) -> void:
	_normal_score_variant = posmod(maxi(depth, 0) + clampi(act, 1, 3) - 1, 3)
	_selected_score_variant = 3 if boss_chamber else _normal_score_variant

func get_selected_score_variant() -> int:
	return _selected_score_variant

func get_normal_score_variant() -> int:
	return _normal_score_variant

func _weights_for_context(context: StringName) -> Vector4:
	if context == CONTEXT_BOSS:
		_selected_score_variant = 3
	elif context in [CONTEXT_COMBAT, CONTEXT_REST]:
		_selected_score_variant = _normal_score_variant
	var result := Vector4.ZERO
	result[_selected_score_variant] = 1.0
	return result

func _score_clock() -> float:
	if active_music_player_index < 0:
		return 0.0
	var player := music_players[active_music_player_index]
	var playback := player.get_stream_playback()
	if playback == null:
		return 0.0
	return playback.get_loop_count() * _adaptive_stream.get_length() + player.get_playback_position()

func _apply_score_weights(weights: Vector4) -> void:
	_score_weights = weights
	_adaptive_stream.set_sync_stream_volume(0, 0.0)
	for index in range(4):
		# -INF is exact silence while the native child stream keeps advancing.
		var db := linear_to_db(weights[index]) if weights[index] > 0.0 else -INF
		_adaptive_stream.set_sync_stream_volume(index + 1, db)

func _process(_delta: float) -> void:
	if _adaptive_stream == null or _score_transition_start < 0.0:
		return
	var elapsed := _score_clock() - _score_transition_start
	if elapsed < 0.0:
		return
	var fraction := clampf(elapsed / _score_transition_duration, 0.0, 1.0)
	var eased := fraction * fraction * (3.0 - 2.0 * fraction)
	_apply_score_weights(_score_from.lerp(_score_target, eased))
	if fraction >= 1.0:
		_score_transition_start = -1.0

func _set_adaptive_context(context: StringName, instant: bool, fade_duration: float) -> void:
	var starting := active_music_player_index < 0
	music_context = context
	var target := _weights_for_context(context)
	# Doors/rewards retain the chamber's target, including a transition already
	# underway. Reopening UI must neither restart a fade nor duck the soundtrack.
	if not starting and target.is_equal_approx(_score_target) and not instant:
		return
	# Retarget from the current mixture. Replacing the pending target cannot
	# reintroduce an earlier context or briefly sum two full-volume additions.
	_process(0.0)
	if starting or instant:
		_score_transition_start = -1.0
		_score_target = target
		_apply_score_weights(target)
	else:
		_score_from = _score_weights
		_score_target = target
		var bar := 4.0 * 60.0 / _score_bpm
		_score_transition_start = ceilf((_score_clock() + 0.02) / bar) * bar
		_score_transition_duration = bar if fade_duration < 0.0 else maxf(0.05, fade_duration)
	if starting:
		active_music_player_index = 0
		var player := music_players[0]
		player.stream = _adaptive_stream
		player.volume_linear = 0.0
		player.play()
		_cancel_transition()
		if not instant:
			var duration := music_crossfade_duration if fade_duration < 0.0 else fade_duration
			_transition_tween = create_tween()
			_transition_tween.tween_property(player, "volume_linear", db_to_linear(_target_music_db()), maxf(0.05, duration))
	if instant:
		_cancel_transition()
		music_players[active_music_player_index].volume_db = _target_music_db()

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

## Adaptive music changes arrangement at chamber entry and bosses. Selection
## contexts preserve it; the legacy two-track path retains its original trims.
func set_context(context: StringName, instant: bool = false, fade_duration: float = -1.0) -> void:
	if context not in [CONTEXT_COMBAT, CONTEXT_REST, CONTEXT_REWARD, CONTEXT_DOORS, CONTEXT_BOSS]:
		return
	if music_players.size() < 2:
		return
	if _adaptive_stream != null:
		_set_adaptive_context(context, instant, fade_duration)
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
	_score_transition_start = -1.0
	for player in music_players:
		if is_instance_valid(player):
			player.stop()

func _crossfade_floor_db() -> float:
	return AUDIO_LEVELS.crossfade_floor_db(_target_music_db())

func _target_music_db() -> float:
	# Every adaptive arrangement is mastered to comparable presence. Opening
	# doors or rewards must never act as an automatic music-volume control.
	var context_trim := QUIET_CONTEXT_TRIM_DB if _adaptive_stream == null and music_context in [CONTEXT_REST, CONTEXT_REWARD, CONTEXT_DOORS] else 0.0
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
