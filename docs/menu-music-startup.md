# Menu music startup and exit

The Menu applies the saved music volume before starting playback. A muted Menu creates no native playback. An unmuted Menu still starts at its saved position; unmuting later still starts at zero. Audio application itself does not write profile, progress or settings files.

The exit callback retains an existing playback's position even after Godot pauses the audio child while removing the scene. Checking for the playback handle preserves the musical handoff when the parent can no longer report that its child is playing.

## Cause and scope

Two full regression snapshots passed all 106 Practice assertions but reported a remaining `AudioStreamPlaybackMP3` and `res://music/msx1.mp3` during process shutdown. The muted fixture exposed an unnecessary start followed by an immediate stop inside the real Menu's startup. Godot's [player implementation](https://raw.githubusercontent.com/godotengine/godot/4.6.2-stable/scene/audio/audio_stream_player_internal.cpp) drops the node's playback handle during stop; its [audio server](https://raw.githubusercontent.com/godotengine/godot/4.6.2-stable/servers/audio/audio_server.cpp) retires the stopped playback through subsequent audio processing. A later tree-exit observer cannot capture that already-detached handle.

The startup correction removes that unnecessary allocation. It does not suppress warnings, unmute the fixture, replace the real Menu, or add a timed shutdown delay. The existing exit-time music-position guard also needed to account for Godot pausing the child before the parent exits; the new actual-scene test exposed this separately.

## Verification

`test_menu_music_startup.gd` deterministically recreates the previous native MP3 allocation and loss of the node's handle. It explicitly observes that deliberately created test playback before stopping it and waits for its retirement. The same fixture then exercises the actual Menu: no muted-start allocation, existing unmute/mute behavior, nonzero initial position, real detach/exit handoff, unchanged profile/settings/progress bytes, and native audio retirement. It is registered in the default regression runner.

The original strict failures remain in the `e305a2fb1ef142a0bc80d77a34e25f93` and `70f6e51fed454cc79a4fd989165ee47b` disposable snapshots and the `full-eight-feature-*` / `full-eight-confirmation-*` receipts. No failed logs or saved-state captures were overwritten. A captured-state run of the old code passed once, consistent with the original failure being intermittent; that run is not presented as a reproduced failure or a fix.

Captured-state replays copy all seven saved input files and verify their hashes before running. Their source comparison covers all 1,066 original inputs. The corrected replay changes only the Menu implementation and preserves the original test, project isolation and verbose strict-exit checks. Its receipts are `.feedback/uncharted-descent-20260912/practice-mp3-{before,after,final}.json` and the accompanying raw-log folders. The final focused test receipt is `menu-music-startup-timeline-final.log`.

Final focused validation in `abyssal-validation-62245b80cf4647edba920eba727fffd6` passes 448 script compilations, both structural guards, all 19 Menu audio checks, all 106 Practice checks, and the existing Menu-helper and run-scene ownership suites. The final captured-state verbose replay in `abyssal-practice-mp3-final-1ae6a371c414487bad13588fb42fc07f` also passes 106 checks with clean shutdown. `menu-music-final-source-manifest.json` records the checked Menu, fixture, UID and runner hashes.

Use the disposable helper for reproduction:

```powershell
& .github/scripts/run_gameplay_regressions.ps1 -TestScripts @(
    'res://scripts/tests/test_menu_music_startup.gd',
    'res://scripts/tests/test_warden_practice.gd',
    'res://scripts/tests/test_menu_helper_ownership.gd',
    'res://scripts/tests/test_run_scene_ownership.gd'
)
```
