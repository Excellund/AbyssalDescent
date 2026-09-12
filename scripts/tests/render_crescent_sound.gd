extends "res://scripts/tests/test_crescent_sound.gd"
## Mix the actual controller voices in an isolated native engine with dummy audio output.

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not DirAccess.dir_exists_absolute("res://validation_fixtures") or not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	var output := ProjectSettings.globalize_path("res://crescent_sound_frames")
	DirAccess.make_dir_recursive_absolute(output)
	var bus := AudioServer.get_bus_index("SFX")
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "SFX")
	var recorder := AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus, recorder)
	# Record before Master; automated verification remains silent to the user.
	AudioServer.set_bus_mute(0, true)
	var observed := _sound_crescent()
	await _settle()
	_check(is_instance_valid(observed._sound) and is_instance_valid(observed._return_sound) and is_instance_valid(observed._bounce_sound), "Native controller creates all three audio voices")
	for voice: AudioStreamPlayer in [observed._sound, observed._return_sound, observed._bounce_sound]:
		_check(voice.bus == "SFX", "Each real cue obeys the SFX bus")
	observed.set_sfx_volume_db(-8.0)
	_check(is_equal_approx(observed._sound.volume_db, observed.SOUND_BASE_DB - 8.0) and is_equal_approx(observed._return_sound.volume_db, observed._sound.volume_db - 8.0), "SFX setting reaches both phases while preserving the quieter return")
	player.player_feedback.sfx_volume_db = 0.0
	recorder.set_recording_active(true)
	observed.try_launch(Vector2.RIGHT)
	_check(observed._sound.playing, "Real launch starts the outbound voice")
	await create_timer(.16).timeout
	_advance_crescent(.36)
	_check(observed._return_sound.playing, "Real turn starts the return voice")
	await create_timer(.24).timeout
	observed._play_sound(&"bounce")
	_check(observed._bounce_sound.playing, "Ricochet uses its own short voice")
	await create_timer(.10).timeout
	# Fast level-two throws overlap without swapping or truncating a voice.
	observed._sound_left = 0.0
	observed._play_sound(&"outbound")
	observed._sound_left = 0.0
	observed._play_sound(&"outbound")
	var launch_voices: Array = observed._sound_voices[&"outbound"]
	_check(launch_voices[1].playing and launch_voices[2].playing and launch_voices[1].stream != launch_voices[2].stream, "Consecutive throws use distinct fixed voices and preserve overlapping tails")
	observed.cancel()
	for voices: Array in observed._sound_voices.values():
		for voice: AudioStreamPlayer in voices:
			_check(not voice.playing, "Cancel stops every recorded variant")
	_check(not observed._sound.playing and not observed._return_sound.playing and not observed._bounce_sound.playing, "Cancellation stops every native voice")
	await create_timer(.08).timeout
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	_check(recording != null and recording.data.size() > 0, "Native mixer returns an actual recording")
	var energy := 0.0
	if recording != null:
		for index in recording.data.size() / 2:
			energy += pow(float(recording.data.decode_s16(index * 2)) / 32767.0, 2.0)
		_check(energy > .01, "Controller routing produces non-silent native mixed audio")
		_check(recording.save_to_wav(output.path_join("crescent_mixed.wav")) == OK, "Actual mixed playback is saved for audition")
	for kind: StringName in [&"outbound", &"return", &"bounce"]:
		_check(CRESCENT.SOUNDS.stream(kind).save_to_wav(output.path_join("crescent_%s.wav" % kind)) == OK, "Individual cached cue saved for audition")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("crescent_audio_fixture.png"))
	FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames": ["crescent_audio_fixture.png"], "checks": checks, "failures": failures, "audio_driver": AudioServer.get_driver_name(), "mixed_energy": energy, "scope": "Actual controller launch, turn, ricochet, SFX routing and cancellation; isolated native audio mix. Subjective sound quality remains a human playtest."}, "\t"))
	_free_world()
	await _settle()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[CrescentAudioNative] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
