# Playtest balance follow-ups — 11 September 2026

Seven observations were appended to the feedback board in the user's order and developed in separate branches/worktrees. Previous biome clarity, keyword overview, boss callouts and boss-variety work remains included. These changes await human playtest acceptance.

| Feedback | Implemented behavior |
| --- | --- |
| FB-ec75c54759044549 — biome polarity | Checked shields and HELP wording identify player-safe biome effects; warning triangles and DANGER identify harmful ones. HUD, floor markers and inspection agree. |
| FB-6cb9f47a6d0743ff — Circuit | Larger capture radius (100 → 120), half the outside decay, fewer enemies and slower waves. Clearing pursuers earns the remaining wave interval instead of a hidden half-second refill. |
| FB-e22033308d1347bb — Intercept | Shorter base traversal (39–30s → 30–24s), smaller enemy blocking radius (80 → 64), fewer/slower waves and gentler overtime. Removed the hidden 0.6s refill. |
| FB-dc92d28091274da1 — Pillar Convergence | Level 1 activates after three actions instead of four. Wider 158/185 radius, one inward Pull per damaged survivor per activation, and 0.45/0.55s Dash refunds. Existing ownership, charge locks and damage rules remain. |
| FB-aafee5dc37e24d37 — Shatterfield pillars | Breaking a cracked pillar releases a foe-only shard Burst for 60 base damage within radius 160. Players are safe; each pillar releases once, with shared HELP imagery. |
| FB-a7899d552dc44571 — Pyre | Full danger visibility during damage, followed by a rapid 0.22s cosmetic fade. The fade cannot damage players. |
| FB-1e7db42620014cef — Drifter | Correct full 88HP spawn, move speed 90, 2.8s waves, 176 ring speed, radius 360 and twelve alternating spokes. Each wave keeps a missing spoke and is limited to one hit per player. |

Circuit and Intercept keep their mission identity, rewards, Bearing and party scaling. Drifter's old unscaled spawn had only 40 current HP despite 68 max; health multipliers masked that initialization bug by refilling it. Detailed values, rationale and focused evidence are in each feature's accompanying document.

## Combined verification

The final combined source passes compilation for 384 scripts, world-property and multiplayer configuration contracts, and all 21 selected gameplay suites. The suites cover both mission flows, live room entry, brittle cover, shard damage and isolation, biome clarity/rules/identity/context, build keywords, boss reward interactions, owned Fields, shared producers, boss combinations, power copy/layout, Drifter replication, Undertow and enemy visuals.

Combined Shatterfield ENet passes 108 host and 111 joiner checks; five combined GPU frames pass and the 960px inspection was visually reviewed. Earlier native checks on the final feature code passed missions 581/583, Pyre 44/34, Pillar Convergence 65/11 and Drifter 13/10 host/joiner checks. Native reward rendering passed 181 pages, alongside the biome, Pillar, Pyre and Drifter gameplay frames. Tests used disposable projects and isolated profiles.

Combined regression evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-10eab27d0dac41fb96210e6888de4422`. Machine-readable suite results and delivery manifests are retained under `.feedback/balance-20260911/`. Automated checks establish behavior and presentation; the balance changes still need the user's playtest judgment.

## Normal desktop delivery

Build `dev-20260911-204549377-02b4fd35` replaces `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`. It opens the regular menu, grants no debug powers and retains normal progression. The exporter verified its package and final hash. The final delivered hash is `F32731A516E62F4D1CAAE0C15DF3E54C256D592DDAFEDE3A540B7F8334DBD2E4` (124,329,248 bytes).

Package inspection passes 27 checks. An isolated byte-identical copy of the executable passes 62 native checks covering the fresh menu, a normal run, movement, pause, return to menu, reopening and clean shutdown. That automated executable check is headless; native GPU fixtures separately verify the visuals. The player's real profile was not used. Exported gameplay scripts match the verified source; only the intended internal build version differs.

All seven new feedback entries are now `awaiting_playtest`, with their saved order preserved. No commit, push or release tag was created.
