# Biome gameplay identity

The later workday revision extends effects to every combat route. Current room modes, objective-space rules and verification are recorded in [biome-room-coverage-20260911.md](biome-room-coverage-20260911.md). The ordinary-room implementation and its earlier verification below remain historical context.

Feedback **FB-196f4f3b86324f66** asks for biomes that change player decisions, rather than only the arena palette. The September 11 revision develops that feedback on the combined playtest branch under claim `codex/combined-playtest-20260910/revision-20260911`. The earlier terrain-only implementation and its validation remain recorded below for history.

## September 11: ordinary-room rules

Each ordinary combat room has one dependable biome rule alongside its existing terrain and enemy mixture. The current implementation uses a shared room-owned controller in `scripts/core/biome_rule_controller.gd`, plus the existing irreversible cover controller. The character redesign remains research only; these rules do not modify character kits.

| Biome | Visible rule | Player decision |
|---|---|---|
| Crumble | A boulder gap warns before rubble lands at that fixed position. | Change gaps, or lead pursuers into the falling rubble. |
| Haunt | A shadow patch beside cover warns, then Slows occupants to 60% movement speed while they remain inside. | Trade protected positioning for mobility, or lead pursuing foes through the patch. |
| Shatterfield | Three deliberate Attack contacts destroy either cracked inner column in every ordinary room. Outer columns remain permanent. | Preserve arrow protection or open a crossing lane. |
| Grinding Vault | Pressure alternates between the center and a bounded outer ring. | Move into the clearly unlit space before the pulse; both sides of the outer band remain usable. |
| Storm Reach | Lightning marks one living player's position, locks it, then strikes that spot. Successive strikes rotate between living players. | Bait lightning near foes and move out of the marked circle. |
| Hollow | A narrow danger strip alternates between the two fighting lanes. | Step off the marked strip or cross through the spine's gaps. |
| Void Breach | A floor band advances through three positions, preserving a broad gap that changes sides. | Use the visible gap or leave the band before it activates. |
| Maelstrom | A bounded sector advances around the central columns in discrete steps. | Move to the unlit side or outside the sector's outer edge. |
| Convergence | Two opposite gate openings warn and pulse, then the other pair takes its turn. Warnings follow the actual posts in both normal and diagonal layouts. | Use the other pair of gates while the marked openings are active. |

Only one environmental event can exist at a time. The default cycle has 2.5 seconds of recovery, a 1.4-second warning and 0.85 seconds of visible activation. Haunt's active patch lasts three seconds. Timers freeze during survey, modal pauses and inactive combat; warnings and active shapes hide while combat is suspended. Room cleanup discards all pending effects.

Storm and Crumble resolve one impact at the transition from warning to active; their lingering flash cannot hit a second time. Other damage zones can catch an actor entering during their brief active window, at most once per actor and event. Default player damage is 8 before normal armor/resistance, or 10 for Storm; enemy damage is 35, or 50 for Storm. Haunt deals no damage. Its Slow expires within 0.22 seconds of leaving the visible patch and refreshes only while inside; it applies on the owning peer for player movement and on authority for enemy movement.

Warnings outline the exact future collision geometry and show a shrinking timer. The controller uses circles, bounded rings, strips with safe gaps, and sectors; damage never extends beyond the visible arena bounds. Hollow strips are at most 160 units wide, the Vault outer ring is 150 units thick, and Maelstrom sectors reach at most 340 units, retaining walking exits for the slowest starting character without requiring an optional Dash upgrade. Cover and existing enemy warnings remain separate: columns stop arrows, not these floor effects.

Environmental damage uses native enemy protection and player damage boundaries, with explicit environmental context. It has no player Damage coefficient, Attack, Electric generator ownership, Mark application or player power reaction. Environmental kills still advance room and objective progress; they neither award a player's kill nor activate kill-triggered powers. The controller's synchronous environmental-damage guard remains active until enemy damage returns, including a reset triggered by a death callback.

The world configures the controller only for ordinary labels, using the current run token, room ID, selected biome and resolved obstacle layout. Authority publishes committed geometry and phase transitions; replicas do not choose strikes or deal duplicate damage. Snapshots carry `run`, `room`, `revision`, `id`, `phase`, remaining/duration clocks, event number, shape and Slow multiplier. Wrong-run, wrong-room, stale, malformed and backward-event states are rejected. Boundary checkpoints contain no active environmental event, and previously offered cover retains its serialized geometry.

The HUD retains a concise rule and response during ordinary combat, including after survey ends, while inspection supplies the full explanation. Breach, Undertow, Missions, Trials, Apex encounters, tutorials, rest sites and bosses retain their authored arenas and receive no new environmental rule.

### Revision verification

The isolated `test_biome_rules.gd` fixture exercises geometry, warning-before-damage, committed Storm baiting, per-event hit limits, enemy/player amounts, Haunt ownership, lifecycle and snapshot rejection. It checks walking escape routes around inflated cover across two ordinary room sizes and eight event orientations, as well as Convergence's actual gate centers. Existing identity and native cover fixtures now cover cracked Shatterfield columns in all eleven ordinary encounter labels.

The new `test_biome_rules_enet.gd` fixture uses two native Main instances and actual world RPCs to check all nine configurations, host-owned damage, native health replication, pending next-room warnings, locally owned Slow, stale-state rejection and specialist-room cleanup. Run it through `test_boss_combinations_enet.ps1` with `-FixtureScript res://scripts/tests/test_biome_rules_enet.gd -FixtureTimeoutSeconds 90` and a disposable `-ValidationProject`.

The new `render_biome_rules.gd` fixture captures eighteen production frames: warning and active states for eight timed rules, plus Shatterfield's intact and opened cover. Run it through `render_gameplay_fixture.ps1` with `-FrameFolder biome_rules_frames -ExpectedFrames 18 -MaxFrames 1600`.

Verified September 11, 2026:

- All 349 scripts compiled; world-property and multiplayer-configuration guards passed. Biome rules: 392 checks; identity: 1,182; native cover: 228; descent presentation: 145; glossary readability: 189; combat pause: 36. All passed in `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-afdca77a5fcd4a68abec42215bc24e23`.
- The collision-aware escape matrix sampled 9,982 affected grid positions. Its longest verified walking route was 181.0 units, within the 263.2-unit distance Bastion can walk during the 1.4-second warning. This verifies the authored terrain and hazard geometry; live enemies can still affect a player's chosen route.
- Native two-process ENet passed 235 host and 246 client checks, with no failures. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-dbede7b7b60c4cf19501968cfd5daaf8`.
- RTX 4080 rendering passed 18 frames and 259 checks. Warning/activation pairs retain matching geometry and readable HUD instructions; the rendered Convergence patches align with the actual gate openings. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-60cd06286f2d4a3ea94512e0f888a56d/biome_rules_frames`. The fixture stages frozen actors and manually advances rule phases for inspection, so its retained survey banner does not indicate live hazards during survey; runtime and native Main tests verify that lifecycle boundary separately.

Earlier counts below validate the prior terrain implementation. Human playtesting still determines whether each new rule reads clearly, preserves comfortable routing alongside enemy attacks and remains enjoyable over a full act.

## Earlier terrain implementation

## Acceptance condition

All nine biomes consistently change the terrain of ordinary combat rooms, communicate a useful response on entry and inspection, and retain the encounter's enemies, rewards and specialist rules. The same resolved terrain must reach rendering, collision, Continue and every co-op peer. Human playtesting determines whether those differences are strong enough to influence preferred biomes and build choices.

## Player decisions

| Biome | Dependable terrain | Tactical opportunity |
|---|---|---|
| The Crumble | Four boulders in staggered pairs | Draw melee crowds through gaps for area damage; use nearby impact surfaces with Launch. |
| The Haunt | Four columns along the sides and an open center | Keep a route across the room to sidestep ambushers; Slow separates pursuers. |
| The Shatterfield | Four staggered columns across firing lanes | Approach Archers from cover to cover; continue dodging floor hazards and beams. |
| The Grinding Vault | Six columns in a broken ring | Circle around shield fronts; alternate inner fighting space and outer flanking routes. |
| The Storm Reach | Two distant shelters and open crossings | Relocate around fire and beams while using range to maintain pressure. |
| The Hollow | Three staggered posts along a central spine | Change lanes through gaps; use lingering area damage to guard crossings. |
| The Void Breach | No obstacles | Use uninterrupted movement and long-range attacks; no arrow cover is available. |
| The Maelstrom | Four close columns around a small central pocket | Lead mixed crowds around short turns; area damage and Slow control pursuers. |
| The Convergence | Eight posts forming four porous gates | Keep an alternate exit when hazards close one gate; focus the foe blocking escape. |

The preferred encounter entries now have three selection copies, up from two, while other eligible encounters have one. Act/depth gates and exclusion of the last entered encounter still take precedence. Existing enemy-count multipliers remain; they neither introduce new archetypes nor bypass spawn caps. Removed obsolete Seamlock/Mirror Line multipliers had no effect on ordinary populations and no longer advertise absent common threats.

Terrain and tactics are authored once in `scripts/shared/biome_registry.gd`. The first act-entry banner stays visible for three seconds and points to typical ordinary-room play. The biome hover panel and glossary explain the terrain, useful responses and specialist exceptions. Launch and Slow semantic spans use the combat keyword catalogue. No powers, damage properties or enemy AI were changed.

## Generation and compatibility

Biome terrain applies to Skirmish, Pursuit, Crossfire, Onslaught, Fortress, Blitz, Suppression, Vanguard, Ambush, Convergence and Gauntlet. Most terrain families have two orientations. Breach, Undertow, Missions, Trials, Apex rooms, tutorials and bosses retain their authored arenas. Unknown biome IDs retain the existing layout pools. Obstacles retain the existing circular column/boulder geometry. The Shatterfield's Crossfire rooms preserve the cracked-column pilot: three deliberate Attack contacts break either inner column to open a lane, while the outer columns and other biome terrain stay permanent. The entry banner combines that room-specific guidance with the biome hint.

All layouts preserve a clear 100-pixel center disk for the 80-pixel party arrival formation, at least 70 pixels between obstacles and from the perimeter, and walkable exits in every quadrant. These are separate posts, with no enclosed walls or new pathfinding requirement. Cover blocks Archer arrows; it does not block beams, floor hazards or every enemy ability.

Only host-generated profiles choose terrain. The existing `obstacle_layout` dictionaries carry exact geometry through offered doors, native serialization, collision creation and multiplayer RPCs. The saved biome roster and existing Continue path are unchanged. Previously offered doors keep their resolved geometry, including older layouts; new offers use the updated families. No save schema or network fields were added.

## Verification

Use the existing disposable-copy regression runner for `test_biome_identity.gd`, `test_biome_cover.gd`, descent routes/presentation, room entry, Undertow, Keeper, Breakwater and glossary checks. The new identity and cover tests are also registered in the default suite.

- Identity matrix: nine biomes, ordinary/protected rooms, two room sizes, multiple seeds, all four Bearings and party sizes; population preservation, spawn caps, deterministic geometry, serialization, Endless, preferences and entered-room exclusion.
- Cover runtime: production obstacle creation changes accepted Archer damage and player collision; room cleanup removes the cover.
- `test_room_layout_entry_enet.ps1`: separate host/joiner processes receive all nine resolved biome profiles, collider positions/radii, populations and authoritative identities through actual RPCs, followed by the existing descent flow.
- `render_biome_identity.ps1`: nineteen GPU frames cover all nine production Main entries, all nine narrow-screen tooltips and a staged four-character party. The party image checks presentation; separate ENet checks establish transport.

Verified September 10, 2026:

- Compile validation: all 304 scripts compiled; world property and multiplayer configuration checks passed.
- Biome identity: 984 checks. Actual cover behavior: 84 checks. Final glossary layout: 186 checks at 960, 1280 and 1920 widths. Zero failures after splitting long glossary entries into authored terrain/tactics lines.
- Descent routes: 148 checks; production descent/Continue presentation: 120; real room entry: 62; Undertow/layouts: 571; Keeper profiles: 181; Breakwater encounter matrix: 2,397. Zero failures.
- Final GPU review: 19 frames and 319 checks on RTX 4080. Manual review caught a banner/passive-panel overlap with biome tooltips; tooltips now draw above the HUD and banner. Reviewed captures confirm the fix. Frames stage idle enemies rather than live overlapping attacks.
- Final separate-process ENet run: 369 host checks and 369 joiner checks, zero failures, including all nine biome profiles and the existing descent sequence. Reports: `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-99919262ecc5424cbd0a9f6220a983f9`. The fixture distinguishes combat room IDs from Rest Site transitions, which do not increment a combat room ID.

Retained local evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-07818c2181a8415f8a5df30474e4d393` (broad scoped regression run), `abyssal-validation-301bfd8fd96b405e823ad4864fdeb661` in the same directory (final identity, cover and glossary checks), and `abyssal-gameplay-render-edc25599df8d4a4b8f884944bbdd520c/biome_identity_frames` (final GPU captures and manifest).

The expanded ENet fixture now waits for both processes to finish loading before timing connection checks. Its wrapper allows 60 seconds for the longer room matrix; other ENet fixtures retain their existing timeout defaults. This addresses a measured slow-client-startup failure under parallel validation load without weakening the gameplay RPC checks.

## Integration and playtesting

Likely overlap with parallel boss/character/synergy work is confined to `world_generator.gd`, `world_hud.gd`, `glossary_data.gd`, `encounter_profile_builder.gd`, the regression list and room-entry fixtures. Preserve both branches' changes when integrating. This branch does not import newer primary-checkout work, change boss selection, grant powers, alter progression, or publish a desktop build.

Playtest priorities:

1. Can players recognize the biome's tactical pattern without opening the glossary?
2. Do area/control, range/movement and Launch builds value different places?
3. Are the sparse layouts sufficiently distinct, and do the denser ones remain comfortable for four players?
4. Does a consistent terrain family become repetitive over a full act? Encounter mixtures, two terrain orientations and specialist rooms provide variation, but human feedback should determine whether more variants are needed.
5. Do beginners understand that cover blocks arrows while floor hazards and beams still require movement?

The feedback entry was moved to awaiting playtest using claim owner `queue-01a08c70-FB-196f4f3b86324f66` after verified implementation. It requires user acceptance before becoming done. Changes remain uncommitted in this task's worktree; no shared desktop executable was replaced.
