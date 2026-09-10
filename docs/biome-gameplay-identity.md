# Biome gameplay identity

Feedback **FB-196f4f3b86324f66** asks for biomes that change player decisions, rather than only the arena palette. Implementation lives on `codex/feedback-196f4f3b-biome-identity`, based on committed main `922a4b576165f6af8477f69bc4c41a48f64916b1`.

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
