# Earlier alternative-boss callout presentation

Feedback `FB-f54479e18abf4a7a` was reopened because the intended reference was Kilnheart, Glass Weaver and the other alternative bosses as they appeared when the player first praised their move names. The earlier implementation incorrectly treated the latest shared presentation as that reference.

## Recovered source

The original alternative-boss commit `4025f72` draws a centered move name in `enemy_boss_alternative.gd::_draw()`: fallback font, size 18, `Color(1.0, 0.89, 0.74)`, baseline `(-label_size.x / 2, -100)`. It draws no background rectangle. The same presentation is retained at `d3a82a2`, lines 509–517, including the existing Kilnheart `Furnace Halo / OUT` and `/ IN` suffix. Its body countdown arc is part of that boss's warning art.

The full, unedited `d3a82a2:scripts/enemy_boss_alternative.gd` was extracted for the native comparison. Its SHA-256 is `090CC0B4407AF1C6B0AD876AD8CC95C131E01DD47765120EF5CD4A0E8D5C1049`. The comparison runs that complete historical script in a disposable validation copy, with the current Main scene, camera and HUD. It does not simulate the reference by recoloring a modern label.

## Implementation

The common view now draws the original warm, unboxed lettering for Warden, Sovereign, Lacuna, Kilnheart, Glass Weaver, Null Archivist and all four Apex trials. The dark plate introduced by the later shared helper is removed. This is a presentation change in `scripts/shared/enemy_attack_callout.gd`; no encounter script, damage, geometry, warning duration, recovery or network payload changes.

The current readability improvements remain: at least 18 physical pixels at different room zooms, eight physical pixels between the layout bounds and the actual health bar, viewport clamping, and avoidance of the live biome, status and build HUD. Historical text shrank with world zoom; restoring that shrinkage would make the longer names harder to read. The actual warm color and unboxed style are preserved while retaining the readable size floor.

The earlier timing corrections also remain: each committed secondary warning uses its real countdown, resolving instant damage clears its name, replicas retire expired names locally, Seamlock's illusion split clears the identifying label, and Toll can display both concurrent channels. Existing body countdown arcs and encounter art remain authored by their owners.

## Verification

- Isolated compilation of 394 scripts, world-property and multiplayer-configuration contracts passed.
- The existing callout lifecycle suite passed 463 checks; actual secondary warning/damage parity passed 57 checks.
- Native Main captures pair all three original bosses with their alternatives at 960, 1280 and 1920 widths. They include `Furnace Halo / OUT`, `Polar Shift / PULL` and `Null Ring / COLLAPSE` over real warning art. All four Apex owners are captured through their real doors, including Toll's simultaneous two-line announcement.
- Separate before, historical-reference and corrected runs produced 13 frames each, with 221, 177 and 221 checks respectively. The historical pass intentionally reports the old world-scaled text bounds instead of asserting the modern size floor.
- Representative historical and corrected Warden/Kilnheart, Sovereign/Glass Weaver at 960, Lacuna's longer label, Mirrorline and Toll frames were visually inspected. The final Apex capture positions the actors in the intended screen location and retains Toll at its arena anchor.

Evidence paths are recorded in the accompanying local receipt under `.feedback/queued-20260912/callout-evidence/verification.json`. The native comparison fixture is `scripts/tests/render_callout_reference.gd`; it supports a historical script only in `validation_fixtures`, which the disposable automation creates. Historical source is not included in production.

The gameplay and rendering checks establish functioning, consistent presentation. Player acceptance of the restored appearance remains a playtest decision.
