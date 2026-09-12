# Breakwater: returning tide

Historical checkpoint: the user subsequently found this ram/Return Tide loop too easy to circle and defeat. The current fight alternates it with Harbor Gate and a lateral brace step; see [breakwater-harbor-gate-20260912.md](breakwater-harbor-gate-20260912.md) and [apex-breakwater.md](apex-breakwater.md). Timings and verification below describe this earlier implementation.

Feedback `FB-070b57a4a29242b0`; isolated branch `codex/combat-polish-20260911-breakwater-identity`.

The previous charge followed by a static ring did not give Breakwater enough identity. The new fight makes it a bracing sea wall. The old charge lane changes from danger into shelter: after the ram misses terrain, a broad returning crest splits around that now-calm wake. A straight sideways escape from the ram can leave the player in a wave lobe, so the follow-up asks them to re-enter the lane or move beyond the crest. Terrain bait changes the sequence by breaking the brace entirely. The visible water travels and passes, then the plates open into a punish window.

The change preserves base health and damage and the existing single-foe Apex route. It reuses the committed ram, reliable host authority and room lifecycle. The legacy internal `BACKWASH` enum/method now denotes bracing; new `TIDE` is the actual traveling wave. There is no save or roster identifier migration.

Walking fairness: each lobe is 198 units wide, with a 64-unit central wake. The full 1.8-second warning accommodates the slowest base character at 45% speed, reserving 0.25 seconds for Attack lock/acceleration. A calm 24-unit boundary strip prevents wall/corner trapping. Tests independently search body-safe straight walking paths through the published polygons, across center/wall/corner placements and six directions in normal and smaller arenas. Normal Dash is an additional timed crossing through existing contact immunity; it is not the only answer.

Tide damage uses the swept curved crest interval, not the entire forecast. Piecewise-linear curvature is shared with the published polygons, and independent painted-boundary samples check actual damage at its front, back, wake and outer edges. The host applies its existing hit damage once per living player, including long frames and overlapping roster entries. Packed origin/direction/bounds/progress keep replication exact and cancellation stops drawing/sound. Replica timing may move an already-authorized wave visually, but cannot begin it, damage, or preserve it beyond its lease.

## Verification

All automation ran in disposable copies with isolated user data, using Godot 4.6.2. Final production source passed:

- Compilation of 388 GDScript files, world property access and multiplayer configuration contracts.
- Runtime: 2,148 checks, zero failures. Includes 480 independent painted-boundary/contact samples; slow walking escapes across arena sizes, corners and headings; actual Dash immunity; phase order; swept single contact; replica geometry/lease; cancellation and cleanup. Logs: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-9f76aadd586d48f994fbef163034a683`.
- Production encounter selection: 2,397 checks, zero failures. Boss combinations: 29 checks, zero failures. Logs: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-4ec124be164543198d2f6f3949deb2fb`. That run used identical production source; the subsequent runtime run added the 480 curved-contact assertions.
- Real ENet host/client: 47 host and 9 client checks, zero failures. Includes committed brace/tide geometry, authority and owner provenance, contact timing and stale/cancel behavior. Logs: `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-774d638d406544fdb2747c4fa6b86fcb`.
- Native GPU fixture: 12 frames, zero failures, NVIDIA GeForce RTX 4080. Inspected curved crest, calm wake, brace and recovery. Frames: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-b299b3001176409e9ca03998b908b923/breakwater_frames`.
- Native Main scene through a real Apex door: 4 frames, 10 checks, zero failures. Actual arena wall contact cancels the tide and preserves the full terrain-bait recovery. A Bastion at 45% movement speed, with Attack lock and Dash unavailable, walks into the wake and survives the returning wave; the spent boss then provides the full recovery. Frames: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-5cf5bf71fa984cc0a054e34455812202/breakwater_main_frames`.

The Main fixture retains the real HUD, camera, biome and production spawn route. Its local shared callout helper predates the concurrent health-bar anchoring change; primary integration will rerender against that helper. Automated geometry and audio lifecycle checks do not establish subjective fight enjoyment or sound quality. Player acceptance remains pending; this worktree does not export or commit.

## Frozen integration scope

- `scripts/enemy_breakwater.gd`
- `scripts/encounter_profile_builder.gd` (Breakwater route instruction only)
- `scripts/tests/test_breakwater_runtime.gd`
- `scripts/tests/test_breakwater_enet.gd`
- `scripts/tests/render_breakwater.gd`
- `scripts/tests/render_breakwater_main.gd`
- `scripts/tests/render_breakwater_main.gd.uid`
- `docs/apex-breakwater.md`
- `docs/breakwater-return-tide-20260911.md`

No shared callout helper, desktop package, board state or unrelated baseline file belongs to this handoff.
