extends SceneTree
## Actual Menu startup/settings audio; all files belong to the disposable copy.
const MENU := preload("res://scenes/Menu.tscn")
const MENU_SCRIPT := preload("res://scripts/menu_controller.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const AUDIO := preload("res://scripts/shared/audio_levels.gd")
const RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")

var checks := 0
var failures: Array[String] = []
var retirement := RETIREMENT.new()
var menu: MENU_SCRIPT

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _files() -> Dictionary:
	var files := {}
	for filename: String in DirAccess.get_files_at("user://"):
		if filename.get_extension() in ["save", "json", "cfg"]:
			files[filename] = FileAccess.get_sha256("user://" + filename)
	return files

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-menu-music-startup")
	RunContext.telemetry_upload_enabled = false
	RunContext.telemetry_consent_asked = true
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	RunContext.profile_uuid = String(profile.player_id)
	RunContext.set_profile_name("MusicFixture", true)
	profile.profile_name = "MusicFixture"
	store.save_profile(profile)
	RunContext._persist_settings()
	var baseline := _files()
	await _reproduce_previous_start_order()
	check(_files() == baseline, "Native audio reproduction does not alter the isolated profile")
	RunContext.set_menu_music_resume_position(12.5)
	_open_menu()
	check(not menu.menu_music_player.playing and not menu.menu_music_player.has_stream_playback(), "Actual muted Menu startup creates no native playback")
	check(is_equal_approx(menu.menu_music_player.volume_db, AUDIO.menu_music_db(-80.0)), "Saved mute is applied before any playback can start")
	check(is_zero_approx(RunContext.consume_menu_music_resume_position()), "Muted startup preserves the existing one-use resume handoff")
	check(_files() == baseline, "Actual muted Menu keeps profile and settings bytes unchanged")
	menu._apply_menu_music_volume(-20.0)
	check(menu.menu_music_player.playing and menu.menu_music_player.has_stream_playback(), "The real Menu volume path unmutes normally")
	check(menu.menu_music_player.get_playback_position() < 0.2, "Later unmute retains the existing start-from-zero behavior")
	check(is_equal_approx(menu.menu_music_player.volume_db, AUDIO.menu_music_db(-20.0)), "Unmute uses the existing menu volume trim")
	# This test deliberately stops a live playback before tree exit. Capture its
	# weak handle before stop() releases the node's handle, then verify retirement.
	retirement._capture_playback(menu.menu_music_player)
	menu._apply_menu_music_volume(-80.0)
	check(not menu.menu_music_player.playing and not menu.menu_music_player.has_stream_playback(), "Muting an already playing Menu still stops it")
	await _close_menu()
	check(_files() == baseline, "Mute and unmute audio application do not write settings themselves")
	RunContext.music_volume_db = -20.0
	RunContext.set_menu_music_resume_position(12.5)
	_open_menu()
	check(menu.menu_music_player.playing and menu.menu_music_player.has_stream_playback(), "Actual unmuted Menu startup creates its ordinary playback")
	check(absf(menu.menu_music_player.get_playback_position() - 12.5) < 0.2, "Unmuted startup retains the saved nonzero score position")
	check(is_equal_approx(menu.menu_music_player.volume_db, AUDIO.menu_music_db(-20.0)), "Unmuted startup applies its final volume before play")
	await _close_menu()
	var retained := RunContext.consume_menu_music_resume_position()
	check(retained >= 12.4 and retained < 13.5, "Leaving the actual Menu retains its shared musical timeline (%.3f seconds)" % retained)
	check(_files() == baseline, "Returning from unmuted Menu preserves profile, settings and progress files")
	check(await retirement.wait_until_retired(self), "All observed native audio retires before fixture shutdown")
	print("[OK] Menu music startup: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _reproduce_previous_start_order() -> void:
	var old_player := AudioStreamPlayer.new()
	old_player.stream = MENU_SCRIPT.MENU_MUSIC
	root.add_child(old_player)
	old_player.play(12.5)
	check(old_player.has_stream_playback(), "The previous play-before-mute sequence allocates an actual MP3 playback")
	var playback: WeakRef = weakref(old_player.get_stream_playback())
	retirement._capture_playback(old_player)
	old_player.volume_db = AUDIO.menu_music_db(-80.0)
	old_player.stop()
	check(not old_player.has_stream_playback(), "Synchronous stop removes the handle before a tree-exit observer can see it")
	old_player.queue_free()
	await process_frame
	check(await retirement.wait_until_retired(self) and playback.get_ref() == null, "The old stopped playback retires through native audio processing when explicitly observed")

func _open_menu() -> void:
	menu = MENU.instantiate() as MENU_SCRIPT
	root.add_child(menu)
	current_scene = menu

func _close_menu() -> void:
	current_scene = null
	# Match Menu -> Practice: detach while its playing audio child still exists,
	# allowing the real _exit_tree callback to hand off the score position.
	root.remove_child(menu)
	menu.queue_free()
	menu = null
	await process_frame
	await process_frame
