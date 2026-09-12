# Move callouts across bosses and Apex trials

Feedback `FB-f54479e18abf4a7a` makes move announcements consistent across Warden, Sovereign, Lacuna, the three alternate bosses, Seamlock, Mirrorline, Toll and Breakwater.

## Presentation and timing

Every owner uses the same warm 18-pixel minimum lettering, with no background plate. This restores the earlier Kilnheart and Glass Weaver presentation identified by the user; see [the historical reference and native comparison](boss-callout-reference-20260912.md). The text's layout bounds normally sit eight physical pixels above the actual health bar, independent of body scale or arena zoom. Viewport bounds and the real status, biome, stats and build HUD can relocate it to keep the name readable. Toll can display its pulse and healing channel together.

Names follow the committed warning and any continuing contact danger. Instant damage clears its name when it resolves, even while impact art remains. Secondary warnings announce their actual phase: Sovereign displays `Echo Dash / 1`, `/ 2` and `/ 3`, `Reposition` for the harmless movement variant, and `Polar Collapse` for the delayed inner strike. Lacuna displays `Null Ring / COLLAPSE` until the pending ring damage resolves. Alternate bosses retain their own distinct follow-up names. Apex trials retain their phase-specific announcements.

Seamlock clears `False Reflections` when its decoys appear so a label cannot reveal the real body. Announcements also clear on recovery, bounded replica expiry, spawn transport and owner removal. Pause uses the existing combat timer ownership. The helper owns no combat timers, triggers or network messages; attack duration, damage and geometry are unchanged.

## Parity diagnosis

The September 11 pass found timing and placement defects in the then-current shared helper. That investigation missed the user's creative reference: the earlier alternative bosses used plain lettering, before the shared helper added a plate. The September 12 correction restores that presentation while retaining the timing fixes below.

The original callouts used the broad attack state timer. During Sovereign's actual second and third dash warnings that timer has already reached zero, while a separate retarget countdown is still live. Those warnings therefore lost their names. The original instant moves also kept their label through a short, already-resolved attack tail. Body-relative offsets placed labels at different distances from differently sized health bars.

The fix reads the real phase countdowns, advances those countdowns on replicas, clears expired Sovereign retarget drawing, and anchors every plate to its actual health bar. Sovereign's precise snapshot now carries the existing reposition-only flag, matching its general runtime snapshot. Receiving either stream cannot mislabel harmless movement as an active contact chain.

The actual Null Ring resolution regression also exposed two existing typed-array fallback errors in `enemy_boss_3.gd`: `_apply_null_ring_hit()` and `_draw_attack_afterglow()` inferred `Array[Vector2]` from the populated branch but selected an untyped singleton when `_locked_null_ring_centers` was empty. Explicit `Array` declarations preserve the exact centers and damage while permitting the existing fallback. The regression checks the single hit at resolution and no repeated damage during afterglow.

## Verification

- Isolated compilation of 389 scripts and world-property/multiplayer configuration contracts passed.
- Scoped gameplay suites passed: phase/damage parity (57), original callouts (463), telegraphs (65), committed charges (402), and alternate bosses (4,842).
- Native loopback ENet passed 123 host and 99 joiner checks, including real Echo Dash legs/retargets, precise-only Reposition, Null Ring pending damage and local expiry without another packet. Replicas retain no damage authority.
- Native Main passed 26 GPU frames and 583 assertions. Comparison captures pair each original boss with its actual factory-created alternate, using the real arena camera, biome and build HUD at 960, 1280 and 1920 widths. They cover every original root move, actual multi-step warnings, a previously drawn replica expiring without manual redraw, resolution, recovery and owner cleanup.

Evidence under `C:/Users/mikel/AppData/Local/Temp/`:

- Scoped suites: `abyssal-validation-add7c2c9c1144549887a0fad332b25b2`.
- Final real damage/phase parity: `abyssal-validation-55c5356e80274feb920ec1230a7210d3`.
- ENet: `abyssal-enet-054cfd1d9b134af79fef3fc0e5b183ce`.
- Native Main: `abyssal-gameplay-render-025631e1b26d4873b4784f59d27fa4d2/boss_callout_parity_frames`. Representative original/newest pairs, third dash warning and expired replica frames were visually reviewed.

Human playtest remains the check of readability while fighting.
