extends "res://scripts/tests/test_returning_crescent.gd"

class AudibleCrescent extends "res://scripts/returning_crescent_controller.gd":
	var cues: Array[StringName] = []
	func _play_sound(kind: StringName) -> void:
		cues.append(kind)
		super._play_sound(kind)

func _sound_crescent() -> AudibleCrescent:
	_setup_crescent()
	player.returning_crescent.free()
	var replacement := AudibleCrescent.new()
	player.add_child(replacement)
	replacement.initialize(player)
	replacement.set_physics_process(false)
	player.returning_crescent = replacement
	crescent = replacement
	return replacement

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	var streams: Array[AudioStreamWAV] = []
	for kind: StringName in [&"outbound", &"return", &"bounce"]:
		var sound := CRESCENT.SOUNDS.stream(kind)
		streams.append(sound)
		_check(sound == CRESCENT.SOUNDS.stream(kind), "Crescent reuses its imported recording without synthesizing per cast")
		var peak := 0
		var energy := 0.0
		for index in sound.data.size() / 2:
			var value := sound.data.decode_s16(index * 2)
			peak = maxi(peak, absi(value))
			energy += pow(float(value) / 32767.0, 2.0)
		_check(peak > 3000 and peak < 31000 and energy > 0.1, "Each cue has audible energy and clean headroom")
		_check(absi(sound.data.decode_s16(0)) < 4 and absi(sound.data.decode_s16(sound.data.size() - 2)) < 4, "Each sound begins/ends without a sample discontinuity")
	_check(streams[0].get_length() < .18 and streams[0].get_length() > .08 and streams[1].get_length() < .10 and streams[2].get_length() < .08, "Recorded gestures stay short enough for repeated throws")
	_check(streams[0].data != streams[1].data and streams[1].data != streams[2].data, "Return and ricochet are distinct sounds, not a pitched launch beep")
	_check(CRESCENT.SOUNDS.variants(&"outbound").size() == 3 and CRESCENT.SOUNDS.variants(&"return").size() == 2, "Distinct recordings vary throws without pitch wobble")
	_check(CRESCENT.SOUNDS.trim_db(&"return") <= -8.0, "Return sits behind the main throw instead of becoming a second equally loud effect")
	for kind: StringName in [&"outbound", &"return", &"bounce"]:
		for sample: AudioStreamWAV in CRESCENT.SOUNDS.variants(kind):
			_check(sample.format == AudioStreamWAV.FORMAT_16_BITS and not sample.stereo and sample.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Imported recordings retain mono PCM and never loop")
	var observed := _sound_crescent()
	await _settle()
	observed.try_launch(Vector2.RIGHT)
	var outbound := observed.build_network_state()
	_advance_crescent(0.36)
	_check(observed.cues.count(&"outbound") == 1 and observed.cues.count(&"return") == 1, "Real travel emits one launch swish and one turn swish")
	var blade := observed.blades[0]
	observed._begin_return(blade)
	observed._begin_return(blade)
	_check(observed.cues.count(&"return") == 1, "Repeated phase observations cannot replay return audio")
	var returning := observed.build_network_state()
	observed.cancel()
	_check(observed.blades.is_empty() and observed._sound_left == 0.0, "Cancellation retires blades and sound throttle together")
	_free_world()
	observed = _sound_crescent()
	# Use the real receiver boundary with a remote input owner.
	player.player_id = 2
	observed.apply_network_state(outbound)
	observed.apply_network_state(returning)
	observed.apply_network_state(returning)
	_check(observed.cues.count(&"outbound") == 1 and observed.cues.count(&"return") == 1, "Ordered/duplicate remote snapshots produce the phase cues once")
	_free_world()
	await _settle()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[CrescentSound] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
