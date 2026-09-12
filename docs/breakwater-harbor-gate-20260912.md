# Breakwater: Harbor Gate pressure

Feedback `FB-070b57a4a29242b0`; owner `01a09209-8771-78f3-9df0-b49907c3df66/breakwater-pressure`; isolated branch `codex/oaths-orbit-breakwater-20260912-breakwater-pressure`.

The user found Breakwater easy to circle and defeat after the Return Tide revision. Its permanent outer calm area and terrain bait allowed the same movement throughout the loop. Harbor Gate now alternates with the ram/Return Tide sequence. A full shore-to-shore seawall has committed player-position openings; continuing to circle leaves those openings. Holding or returning to an opening lets the crest pass safely before pursuit. The existing terrain bait remains an earned recovery and skips Return Tide, while the next Harbor Gate still happens.

A stationary first prototype also allowed prolonged melee inside the opening. The final version makes a committed, harmless lateral brace step into the neighboring dangerous lane during the warning. Actual terrain and player collision can block that step. This reduces free stationary melee while allowing terrain positioning to pay off. Health, damage, ordinary cooldown and existing ram/Return Tide timings are preserved.

Final values: warning 1.2 seconds; opening half-width 56; crest half-depth 24; crossing speed 370; brace step speed 190; 1.1-second recovery. All openings and the shore direction commit before warning. Existing normal Dash immunity remains an option. Relative-time player/crest clipping catches fast crossings and accounts for the final partial movement step; explicit position resets clear old travel history.

The current full rules and starting values are in [apex-breakwater.md](apex-breakwater.md). The existing shared plain warm move lettering is preserved; the new warning reads `Harbor Gate / HOLD THE OPENING`.

## Verification

All automation used Godot 4.6.2 in disposable projects with isolated user data.

- Final compilation: 402 GDScript files; world property access and multiplayer configuration checks passed.
- New focused suite: **661 checks, zero failures**. Includes 572 independently published polygon/contact samples over all four shores and actual arena boundaries, four-player/merged/removed openings, moving and reset crossings, real normal Dash activation and immunity, lifecycle retirement, movement pilots and close-range Attack pilots.
- Preserved Breakwater runtime: **2,148 checks**, zero failures; production encounter suite and combinations **29 checks** passed. Final project: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-547ac8bbda13407b98069b20c1dbe865`. Worktree log: `.feedback/harbor-gate-regressions-final.log`.
- Real separate ENet host/join processes: **38 host / 10 client checks**, zero failures. Verifies quantized four-opening geometry, full status replication, one host-authored contact, no replica damage, malformed/stale/expired packets, removal and authority cancellation. The stress state carries four openings plus all 24 supported owner/source Marks, four Dread owners and Slow: **779 estimated / 912 encoded bytes**, with the custom gate retained by the actual 900-byte fitter. Two real network players plus two host-side target probes supply the four opening positions. Final project: `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-84e1a348b5a6436fae69c93083a9d87e`; worktree log `.feedback/harbor-gate-enet-final.log`.
- Native GPU fixture: eleven frames at actual room-fit zoom, covering the route, warning, lateral step, interpolated replica, early/late moving crest, recovery, four openings, merged openings, corner cover and another shore. Final location is recorded in `.feedback/harbor-gate-gpu-final.log`; the primary integration may retain an additional matching-source render.

### Actual moving pilots

Each row aggregates eight 32-second runs: two circle radii (260/350), four starting angles, actual production acceleration and body collision. Base movement uses 220 units/second. The reduced-speed cases use the slowest base character at 188 units/second with a 45% multiplier. The response pilot continues its original motion for 0.35 seconds after noticing a gate, then uses ground movement to return to its committed opening. No Dash is needed for that response.

| Movement speed | Previous loop: total contacts | New loop, continuous circling: total / gate contacts | Opening response: total / gate contacts |
|---|---:|---:|---:|
| Base | 9 | 18 / 15 | 4 / 0 |
| 45% of slowest base | 8 | 28 / 16 | 6 / 0 |

The total includes ordinary ram/Return Tide contacts. All 32 gates encountered by the response pilots were avoided. Eight additional Slowed corner cases, including a smaller arena and real nearby cover, also avoided the gate after moving and returning. Full pilot JSON is retained at `.feedback/harbor-gate-pilots-final.json` and in the final validation project.

An actual repeated Attack pilot held its position next to the boss for the 4.47-second warning/crossing. The stationary prototype took **320 damage**. The final open-floor brace moved **152 units** and took **40 damage**. With two real cover bodies pinning the brace, it moved **30.5 units** and took **320 damage**. In all three cases the player remained in the opening, took no damage and was never moved by the brace. This tests the intended tradeoff: following early leaves shelter, waiting gives later access, and terrain positioning earns access.

## Frozen integration scope

- `scripts/enemy_breakwater.gd`
- `scripts/encounter_profile_builder.gd` — Breakwater banner only
- `scripts/shared/glossary_data.gd` — Apex Breakwater entry only, including the two native-layout sentence breaks
- `scripts/tests/test_breakwater_harbor_gate.gd` and `.gd.uid`
- `scripts/tests/test_breakwater_harbor_gate_enet.gd` and `.gd.uid`
- `scripts/tests/render_breakwater_harbor_gate.gd` and `.gd.uid`
- `docs/apex-breakwater.md`
- `docs/breakwater-return-tide-20260911.md` — explicit historical status
- `docs/breakwater-harbor-gate-20260912.md`

This worktree makes no board, desktop-export, commit or push changes. The primary task owns integration, the combined playtest package and board status. Human acceptance remains pending; movement and network evidence cannot establish subjective excitement or balance for every build.
