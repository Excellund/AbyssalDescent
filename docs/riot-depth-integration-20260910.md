# Riot Depth run music integration

Implemented for `codex/combined-playtest-20260910`, starting from `c953dfa3`.
The user approved the Riot Depth audition and explicitly requested replacing
the existing run music with it. Integration verification completed on 2026-09-11.

Combat and bosses now use the approved combat arrangement; rewards and rest
use the reward arrangement; presented routes use the door arrangement.
`Main.tscn` no longer supplies the old normal/boss tracks. Menu music remains
separate. No composition or mix change was made to the accepted Ogg layers.

## Playback and scene flow

`music_system.gd` creates an owner-local `AudioStreamSynchronized` from four
looping Ogg streams. One active music player owns all four; zero-gain additions
continue advancing. The base stays at unity while the three additions use
complementary amplitude gains. Scene changes retain the same native playback,
start at the next beat and normally blend over two beats using a smooth curve.
Rapid requests replace the pending target from the current mixture. Pause
freezes both playback and blending. Settings change the master level without
cancelling the arrangement transition or applying a second quiet-state trim.

The clock uses native Ogg playback position plus loop count, including fades
across the wrap. Adaptive input is restricted to aligned Ogg layers because
Godot's WAV playback does not supply the required loop count. Invalid adaptive
configuration preserves live legacy playback. The original two-track API is
still available to callers that do not configure an adaptive score.

World setup configures the score before playback. Hooks cover combat, boss and
reward entry, successful host/solo route generation, tutorial exit, accepted
client route payloads, rest and Continue. Co-op reward music stays active while
either player is still choosing; routes take over only once they are presented.
Rest-site routes retain the quieter rest/reward arrangement.

## Verification

All unattended game checks use disposable copies with isolated profile data,
suppressed external services and retained logs. The agent has not listened to
the integrated game; user playtest supplies that final perceptual assessment.

- Final compilation of 345 GDScript files, world-property and multiplayer-configuration gates passed.
- Existing music API: 20 assertions passed.
- Adaptive score: 74 assertions passed, covering native playback, every layer's
  real loop, bounded complementary gains, rapid retargeting, settings, mute,
  pause, loop-boundary transitions, independent owners and resource retirement.
- Room/Continue presentation: 142 assertions passed; combat pause: 28 assertions
  passed. Run-scene ownership and native resource retirement: 152 assertions
  passed across ten actual Main instances.
- Actual ENet host/joiner room flow: 455 host and 460 client assertions passed,
  including ordinary and boss reward-to-door transitions and staggered choices.

The deliberate `AudioStreamPlayer.seek()` in the loop fixture establishes a
fresh native-playback baseline, because Godot implements seeking by stopping
and starting. All production context-change checks require the original native
playback to remain unchanged. No gameplay context hook seeks or restarts music.

ENet logs:
`C:/Users/mikel/AppData/Local/Temp/abyssal-enet-ff85af1402d5479f993ae0398207f9d4`.
Final local fixture logs:
`C:/Users/mikel/AppData/Local/Temp/abyssal-validation-bc57ec1aef954c90a63be95fbeb78f70`.

## Accepted audio identity

All four runtime files match the accepted audition bytes. SHA256:

| Layer | SHA256 |
| --- | --- |
| base | `1384bd30ecf7fae00ff4b3297341f8abfa3cab3db584501d2aefff933fda1da6` |
| combat | `2c9d00dafacaf698cb3313956ac622aea31e1fd2d074558a22f563be9a4b395a` |
| doors | `552ac1defdc084d27499861b05714bf6959054d713e986a3b03699fe4fb5afe8` |
| reward | `f7ed544e7b427d27e3f0400e4f5fa230b2303b2f863c9f1b413cf64cab7408c8` |

[Production notes](../music/riot-depth/README.md) retain the CC0 sample license,
source recording hashes, offline rendering recipe and source loudness metrics.
[Music direction and lessons](music-direction.md) preserves the accepted brief.
Earlier rejected audio/SFX work in the separate audio worktree was not copied
over the combined branch's gameplay changes.

## Normal playtest delivery

Exported from the combined checkout with `.github/scripts/export_playtest.ps1`
without `-DebugRun`. The standard desktop file was replaced only after package
verification. The regular menu and normal progression are retained; debug
starting powers are disabled. The isolated normal package smoke test passed
27 checks. No unattended test launched the player's real profile.

- Executable: `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`
- Build: `dev-20260910-220406798-58327593`
- Size: 119,008,248 bytes
- SHA256: `ECF9BF1FA9BE52C6CAFDF0F7FA877A889D5727126487CFFD0ED33D7526151C32`
- Export logs: `C:/Users/mikel/AppData/Local/Temp/abyssal-playtest-export-8c242d8ba5f0425eb2b221e40b729193`
- Package smoke report: `C:/Users/mikel/AppData/Local/Temp/abyssal-executable-smoke-129171db1286433c8e8a42a0ef04fbad/result.json`

The 416 local gameplay/audio checks, 915 ENet checks and 27 normal package
checks passed. `git diff --check` passed. Changes are in the combined checkout;
this integration did not commit, push or merge the older audio worktree.
