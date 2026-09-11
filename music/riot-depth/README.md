# Riot Depth — run soundtrack

**2026-09-11 revision:** rewards and doors now keep the current music. Runtime
uses `base.ogg` plus one of `drive.ogg`, `pursuit.ogg`, `pressure.ogg`, or
`boss.ogg`, with changes at chamber entry/bosses on the next bar. Their full-track
loudness differs by only 0.05 LU. Drive and base preserve the approved bytes;
the other three are newly composed performances on the same harmonic timeline.
See [the variance revision](../../docs/riot-depth-variance-20260911.md) and
`variance-report.json`. The original four-file audition information below is
retained as production history; its quiet door/reward exports are no longer
selected by the game.

To render the new arrangements after preparing the original VSCO cache:

```powershell
python tools/audio/render_riot_variants.py
```

## Current playback

The [catalogue](../../scripts/shared/riot_depth_catalogue.gd) supplies five layers
to [the music system](../../scripts/music_system.gd), which creates a private
`AudioStreamSynchronized` per owner. All layers start and loop together; muted
layers continue advancing. The common base plays once while the four additions
use complementary gains. Chamber changes start at the next bar and blend over
one bar (about 1.714 seconds at 140 BPM). Rewards and doors preserve the current
arrangement, its target and master gain, including an ongoing blend. Scene-tree
pause also pauses the musical clock. Menu music remains separate.

The score is 48 bars, D-centered, with distorted mid-bass, clipped electronic
hooks, shaped percussion and sparse noise accents. Each Ogg contains 3,949,714
stereo frames at 48 kHz (82.285708 seconds).

## Original audition (historical)

User-approved on 2026-09-10: "Yooooo this is sick!". The user then requested
replacement of the existing run music on `codex/combined-playtest-20260910`.
The initial integration used the four audition layers below. Its quiet
selection additions and next-beat/two-beat blending were superseded on
2026-09-11; the files remain as production references.

| Original file | Original role |
| --- | --- |
| `base.ogg` | Continuous atmosphere, still used unchanged |
| `combat.ogg` | Combat and boss addition, preserved as current `drive.ogg` |
| `doors.ogg` | Quieter door-selection addition, no longer selected |
| `reward.ogg` | Quieter reward/rest addition, no longer selected |

See the [original integration record](../../docs/riot-depth-integration-20260910.md)
for the earlier behavior and its verification.

## Sources and reproducibility

Composition and synthesized voices are original. Recorded bass drum, snare and
cymbal hits come from [VSCO 2 Community Edition](https://github.com/sgossner/VSCO-2-CE),
revision `440300901dfe9275fd84e0b7763af1f8443ae62e`, released under CC0.
The source license is preserved in [VSCO-CC0-LICENSE.txt](VSCO-CC0-LICENSE.txt).
`render-report.json` lists the ten source recording hashes and mix settings.
No audio from the user's character or soundtrack references is used.

From the repository root, with Python, NumPy and FFmpeg available:

```powershell
python tools/audio/fetch_vsco_samples.py
python tools/audio/render_riot_depth.py
```

The renderer writes a new audition under the ignored `tools/audio/examples`;
it does not overwrite these approved runtime assets. The pinned cache is also
ignored. Earlier rendering helpers are retained because the Riot renderer uses
their sample loading, encoding, WAV-writing and measurement functions.

The final full combat reference measured -18.01 LUFS integrated / -2.89 dBTP;
the guided journey measured -18.20 LUFS / -2.89 dBTP with no clipped samples.
Those are source-level measurements, before the game's volume setting.
The [direction and lessons](../../docs/music-direction.md) records user feedback
and distinguishes technical verification from creative acceptance.
