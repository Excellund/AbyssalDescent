# Reading biome mechanics during play

Feedback `FB-b1829200f6f647c3` asks for a clearer understanding of biome mechanics.

The persistent HUD now states the current biome phase and who it affects: warning, active damage or Slow, and the pause between patterns. Green assistance explicitly says `FOES ONLY`; ordinary and compact danger says `YOU + FOES`. Survey and modal pauses are identified. Shatterfield instead counts standing cracked columns and reports when their routes are open. These cues follow the existing room controller and cover state without altering gameplay, damage, timings or networking.

Entry advice explicitly names damage or Slow and a useful movement response. The biome header advertises its hover explanation. That explanation uses larger 15-pixel body text and separates the rule, effect amounts, floor timing and useful response. It describes one-time impacts separately from damage windows, gives Haunt's actual movement reduction, and preserves compact objective protection, green boss/Apex assistance and Shatterfield fragments. An already-open explanation updates when a compact room switches to assistance. The glossary uses the same effect descriptions.

## Verification

- Isolated compilation: 366 scripts and world/network contracts.
- Existing scoped checks: 1,246 real room context, 1,182 identity, 228 cover, 498 controller, 54 HUD invalidation and 179 descent presentation checks.
- New real-Main clarity fixture passed 338 checks, comparing every biome's ordinary, compact and Apex description with actual controller timings, damage and Slow. It follows live phases, opened cover, survey/reward/Rest lifecycle and automatic assistance while inspection remains open. The default regression runner includes it. Final glossary readability passed 189 checks and HUD invalidation passed 54.
- RTX 4080: 38 specialist frames / 348 checks, plus 19 ordinary-room and narrow inspection frames / 319 checks. All complete tooltips fit at 960 by 720; phase cues fit alongside current objective text. Representative ordinary Storm, Shatterfield and Void plus compact Haunt, compact Maelstrom and friendly Storm frames were visually inspected.

Evidence under `C:/Users/mikel/AppData/Local/Temp/`:

- `abyssal-validation-9102fcc4a2a240c7a0ccef6941a6e87c`: original scoped regression pass.
- `abyssal-validation-5f57be1f59fc4dd2ace74be0cd656231`: final clarity, glossary and HUD pass.
- `abyssal-gameplay-render-5ab74974c137428885dce7ad52579e98/biome_room_context_frames`: specialist presentation.
- `abyssal-gameplay-render-876c7a43fafa4abd8c186e2635e69b65/biome_identity_frames`: ordinary presentation.

One overlong glossary sentence was caught during the additional readability check, split into authored lines and verified at all three supported inspection widths.

Human playtest should confirm that the phase and target cue makes floor patterns easier to understand during combat. Captures hold actors and committed phases for inspection. Desktop delivery is coordinated by the integrating task.
