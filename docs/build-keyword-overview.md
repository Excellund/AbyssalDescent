# Build keyword overview

Feedback: FB-0fd0a74f41a7491c; refinement FB-ea1ab663ff22453c.

The HUD shows the two leading effect keywords and their owned-source counts in one centered line, with a small Tab shortcut. If no effect keywords are owned, it falls back to action keywords. The full count explanation lives in inspection, so combat does not carry an extra explanatory heading.

Tap Tab (or controller Y) to open Build Details; tap again, press Esc/controller B, or select Close to dismiss it. Releasing Tab leaves it open. Both key releases and repeats are consumed before GUI focus navigation, preventing a held key from cycling buttons and scrolling after a keyword click. Arrow keys and controller navigation remain available.

Build Details starts with a single 42-pixel keyword summary row showing the three leading keywords. Select that row to expand every represented keyword, with actions and triggers grouped below the effects. Select a keyword by mouse or controller to see its definition and contributing powers, separated into producers and users. The collapsed row leaves the passive and owned power list near the top of the view.

One learned power contributes once to each keyword it produces, accepts or checks. The character passive is one source. An Electric Projectile power can count toward both Electric and Projectile; a source that both produces and uses a keyword still counts once. Duplicate Boon picks, Arcana levels and Prismatic do not multiply source counts. Level unlocks add their newly available properties. Temporary Mission bonuses, room rules, inactive offers and other players' powers are excluded. Counts describe the properties represented by the build; they do not measure damage share or promise an interaction.

`scripts/shared/build_keyword_summary.gd` aggregates actual owned levels and the existing producer/receiver metadata in the power and passive catalogues. It never scans prose, so examples and exclusions cannot create owned properties. Labels, colors and definitions come from the combat keyword catalogue. World refreshes the HUD each frame with the current owned-ID lists. The existing ID/level/character/player signature gates both the full inventory scan and summary formatting; a stable build adds no registry scan or text rebuilding. Build Details reads ownership directly when opened.

The display metadata now includes Aegis Pulse's non-damaging Burst and level-2 Slow on Riftpunch, Sigil Chain and Farline Volley. Gameplay behavior is unchanged.

Verification fixtures: `test_build_keyword_overview.gd` covers mixed roles, hybrids, passive exclusions, levels, Prismatic, repeated Boons, actual ownership, temporary bonuses, controller expansion and HUD restoration. `render_build_keyword_overview.gd` captures collapsed hybrid and full-roster builds, expanded counts and contributor inspection, and the compact HUD at 960, 1280 and 1920 widths. The keyword regression dispatches native Tab press, mouse clicks, sixteen repeat events and release through the production World input handler at each width, and verifies stable focus/scroll plus keyboard/controller access. The existing reward inspection, HUD invalidation and overlap-fade regressions remain required.


2026-09-11 refinement verification: isolated compile of 384 scripts and world/network contracts passed, alongside 49 keyword checks, 467 reward inspection checks, 54 HUD invalidation checks and the actual Main HUD overlap suite. Native RTX 4080 captures passed 124 checks across 15 frames at 960, 1280 and 1920 widths. Compact summary, expanded contributors and full-roster layouts were visually reviewed.
