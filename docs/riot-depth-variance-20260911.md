# Riot Depth: musical variance without selection ducking

User feedback: keep the changing soundtrack through the run and emphasize boss
battles, but the drop at rewards and door selection sounds like random volume
adjustment. This revision follows the approved industrial/electronic identity.

## Diagnosis and behavior

The original door and reward arrangements were mainly lower-gain combinations
of the same performances. Their full-track measurements were -26.63 and -24.26
LUFS against combat's -18.01 LUFS: reductions of 8.62 and 6.25 LU. Correct
playback synchronization did not make that change read as musical variance.

Rewards and doors now preserve the current arrangement, target and master gain,
including an in-progress blend. New chambers rotate three arrangements using
their existing act/depth. Boss chambers select a dedicated fourth arrangement,
which continues through their rewards/exits until the next chamber. Rest selects
a normal chamber arrangement without ducking. Continue reconstructs the same
selection from the saved presented chamber, including defeated-boss checkpoints.

Five native synchronized streams share one continuous clock: base plus Drive,
Pursuit, Pressure and Boss. Changes begin at the next bar and blend over one bar
at 140 BPM. All gains remain complementary and bounded; the base is included
once. No extra playback owner, independent playhead, runtime synthesizer, volume
normalizer or gameplay RNG is introduced.

## Musical development

- Drive preserves the approved combat Ogg byte for byte, including its composed
  development and phrase breathing.
- Pursuit uses clipped bass attacks and angular midrange replies.
- Pressure uses longer bass gates and heavier, spaced responses.
- Boss alternates faster backbeats with half-time counterattacks and brief
  sustained hooks. Its identity comes from the writing, not a louder master.

The new variants are fully arranged through the old audition's selection
chapters. They use the same 48-bar harmony, original electronic patches and CC0
percussion sources. The base is unchanged. The score and renderer are retained
in `tools/audio/riot_depth_variants.py` and `tools/audio/render_riot_variants.py`.

| Full arrangement | Integrated loudness | True peak |
| --- | ---: | ---: |
| Drive | -18.03 LUFS | -2.90 dBTP |
| Pursuit | -18.07 LUFS | -2.96 dBTP |
| Pressure | -18.08 LUFS | -3.61 dBTP |
| Boss | -18.07 LUFS | -4.76 dBTP |

The 0.05 LU full-track spread is a technical balance check, not a claim that
every musical moment has identical perceived loudness. The user's listening
feedback remains the artistic acceptance test. All encoded additions have
3,949,714 stereo frames at 48 kHz. The source report records hashes and levels.

## Verification and delivery

The isolated production compile gate passed for 348 scripts, followed by the
world-property and multiplayer-config gates. Local tests passed 469 checks:
20 music contexts, 90 adaptive transport/arrangement checks, 179 descent
presentation checks, 28 combat-pause checks, and 152 ownership checks using ten
actual Main instances. The isolated two-process ENet run passed 533 host and
538 client checks (1,071 total).

Coverage includes unchanged arrangement targets and master gain during rewards
and doors; selection during an ongoing blend; bar-quantized chamber changes;
boss persistence; Continue from normal and defeated-boss checkpoints; matching
host/client variants; pause, native loop crossing, and owner cleanup.

Local logs: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-154905dbc30d4f0f9f8116190d4d4856`.
ENet logs: `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-b0ef612b66f846998d41a182bbbabdf9`.
Other combined-branch work is preserved; this revision only changes the
soundtrack, its hooks, tests and notes.

Normal desktop delivery used `.github/scripts/export_playtest.ps1` without
`-DebugRun`, followed by `.github/scripts/test_playtest_executable.ps1` against
the exported package. Import, release export, package policy verification and
all 27 normal package smoke checks passed. The package starts at the regular
menu with no debug powers; the smoke harness used isolated user data.

- Desktop file: `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`
- Build: `dev-20260910-222358990-6be4987f`
- Size: 124,236,816 bytes
- SHA-256: `F6C0D2C190843D9ABBC5DF9A20AC3EF412562B3D85A437C1C682CC9073722ED2`
- Export logs: `C:/Users/mikel/AppData/Local/Temp/abyssal-playtest-export-43fe9079ef914b4bbd5979bef6e134a9`
- Package smoke: `C:/Users/mikel/AppData/Local/Temp/abyssal-executable-smoke-5b2bec2e43514d99b1d1cca5082ac2d2`

The export snapshot's soundtrack code and audio hashes match the verified
revision. Changes are applied to `codex/combined-playtest-20260910`; no commit
or push was requested for this revision.

Audition: `C:/Users/mikel/.codex/worktrees/5908/godot-2026/tools/audio/examples/riot-variants/riot-depth-variants.mp3`.
The preview moves from Drive to Pursuit, Pressure and Boss at roughly 0, 21, 41
and 62 seconds, with one-bar transitions. It demonstrates the arrangements;
in-game changes follow chamber entry and bosses, not this preview schedule.
