# HUD refresh performance

Feedback `FB-86404149a7854a79` requests better performance without losing visual polish. The candidate area is repeated HUD text formatting and style updates: the current refresh path runs each frame even when the displayed header, stats and build have not changed. Measure that cost before editing production code.

## Baseline and measurement

The frozen pre-optimization HUD is `.feedback/workday-20260911/performance-baseline/world_hud.gd`, captured after the verified boss-atmosphere layout on 11 September at 06:31 UTC. Its SHA256 is `E94CA093DC9DA7701555807190B2D99C588E349000B8A8D84838470757121423`. The file and manifest are local evidence, ignored by Git and excluded from game exports. They are not feedback-board storage.

Use disposable native Main scenes with seeded encounters, ordinary build sizes and real enemies. Warm up before measuring at least 300 frames. Report the time spent refreshing the HUD separately from whole-frame processing; a fixed-60-FPS capture cannot demonstrate higher maximum FPS. Repeat equivalent before/after workloads and retain the frozen source for direct comparison. Inspect representative native output and verify state changes as well as the unchanged case.

## Acceptance conditions

- Reduce measured CPU work for unchanged HUD presentation without lowering animation quality or update rates.
- Health, effective cooldowns, Slow entry/expiry, timers, stacks, character identity and changed biome descriptions update on the next refresh.
- Current objective countdowns and rules, camera-relative layout, window resizing and combat overlap fading retain their current per-frame behavior.
- Font, theme and available-width changes still produce correctly fitted text. A cache cannot keep stale text or panel dimensions after a resize or replacement player.
- Boss introductions, co-op readiness, rewards, Pause and Build Details keep their verified visibility priority.

## Implementation and verification

Initial native profiling measured roughly 512 microseconds per HUD refresh: approximately 115 for the header, 110 for Stats and 107 for the build list. These three sections accounted for about 65% of the measured refresh, supporting a change limited to them. This exploratory fixture used four invalid Boon IDs, which did not grant powers; its definitive baseline is being corrected to assert every acquisition and include real boss rewards. Real health changes also legitimately trigger extra HUD refreshes, so final reports count actual refresh calls rather than assuming exactly one per frame.

The completed change caches the header's input values, a flat copy of ordered build IDs/counts and player instance identity, and the exact displayed Stats values. Stats layout follows native theme/minimum-size notifications and available width. Camera layout, objective/status updates, overlap fading and boss presentation retain their existing cadence. Candidate HUD SHA256: `CEE2301A29F34AF9CCC7A6865727C1468B025B969D29A96D9FECEB3075CC0D2F`.

## Final comparison

The native comparison ran baseline, candidate, candidate, baseline in one isolated process, after all other Godot validation stopped. Each trial used 90 warmup frames and 360 measured frames at 1280×720, 12 real enemies, and four real Boons, four Arcana and two boss rewards acquired through the normal power API. Actors had increased health to retain the test population. All trials made 394 HUD refreshes, including legitimate health-change refreshes.

| Trial | Mean refresh | Median refresh | 95th percentile |
|---|---:|---:|---:|
| Baseline 1 | 551 µs | 480 µs | 1,021 µs |
| Candidate 1 | 330 µs | 271 µs | 752 µs |
| Candidate 2 | 349 µs | 297 µs | 799 µs |
| Baseline 2 | 545 µs | 491 µs | 1,041 µs |

Combined mean refresh time fell from 548 to 339 microseconds: **38.1% less HUD CPU time**, saving approximately 209 microseconds per call. Header work fell from approximately107 to7 microseconds, build work145 to67, and Stats112 to71. Instrumented world-script processing averaged1,285 versus1,063 microseconds, but other callbacks and renderer/GPU costs are outside that measurement. Whole-engine monitors varied, so this is not a claim of a measured FPS gain or a universal hardware result.

The benchmark passed73 checks with four native frames on the RTX4080. Its separate 1280×1080 presentation captures show the entire ten-power build strip; the unchanged strip extends below720pixels in both versions. Actual visible header/status/Stats/passive/chip text, badges, colors and control bounds match across all four snapshots. Root and the reviewer inspected baseline/candidate frames and found no introduced visual defect.

Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-47f28f95ac624bd1a18513350fa1e38f/hud_benchmark_frames/manifest.json`. Reproduce with `.github/scripts/benchmark_hud_refresh.ps1 -ValidationProject <isolated-validation-copy> -Mode Compare`; it checks the frozen baseline hash and uses the existing isolated GPU helper.

Six scoped suites passed694 checks, with359-script compilation and project contracts, in `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-5ebfd6d17cde4c15bb550f95b3ef6817`. These cover54 fresh-input cases, Pulse HUD, overlap fading, boss atmosphere, descent and Mission cooldown/save behavior. The new fixture is registered in the default regression runner. Human testing should compare busy-room smoothness and watch for stale HUD values after rewards, temporary effects and room transitions. Normal desktop delivery remains part of the workday checkpoint.
