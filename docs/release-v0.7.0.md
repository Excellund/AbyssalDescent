# v0.7.0 checkpoint

The player requested committing and pushing the combined playtest, merging it into `main`, and creating the annotated `v0.7.0` release tag on September 11, 2026.

This checkpoint includes the combined biome, fifth-character, alternate-boss and synergy work, followed by the development-queue improvements and the requested Static Wake damage reduction:

- Effigy Keeper replaces the alternating-target passive with a deliberately positioned origin for the player's Attack, preserving the fifth character's existing progression ID.
- Biome rules now extend through special combat routes, with protected objective space and green foe-only effects during boss and Apex encounters.
- New Boons, Arcana and boss rewards connect Electric damage, Mark, Slow, Bursts and Projectiles. Three displacement-heavy boss rewards have revised damage and status payoffs.
- Alternate bosses have stronger warned follow-ups; all six bosses have personal greetings and final words.
- Reward keywords and descriptions, enemy bodies, Pyre death-zone expiry and HUD refresh work improve clarity and responsiveness.
- The separately approved Riot Depth soundtrack integration and arrangement changes are included in the delivered game.
- Static Wake's accrued damage and Damage coefficient are 25% lower at every level, including Prismatic; trail timing, geometry and Slow remain intact.

The [playtest guide](playtest-guide-20260911.md) covers player-facing checks. The [workday journal](workday-development-20260911.md) and [Static Wake revision](static-wake-balance-20260911.md) retain detailed implementation and verification evidence. Feedback-board acceptance remains a separate record from this release checkpoint.

## Verification and delivery

The workday baseline passed all 99 gameplay suites. The subsequent Static Wake revision passed nine focused suites (24,881 checks), 365-script compilation and both contracts. The commit hook runs the required full isolated regression suite for the final checkpoint. Branch validation and the tag-triggered release workflow also require the full suite before Windows publication.

The matching normal desktop playtest is `dev-20260911-150813181-4ec0f6c4`, with regular menu and progression. It passed 27 package checks and 62 headless checks of the actual executable. Delivered SHA256: `58DDEA0164FC7554012AC10BFE7E4FECF74EC94E946B582D3E042597A4CE6251`.

The source retains its development version markers. The existing Windows release workflow derives `0.7.0` from the pushed `v0.7.0` tag, updates both version markers in its export checkout, and publishes the Windows ZIP, checksum and update manifest after validation.
