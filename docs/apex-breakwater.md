# Apex Breakwater

Current refinement: `FB-070b57a4a29242b0`. The user found the ram/Return Tide loop easy to circle and defeat. The current implementation alternates that loop with **Harbor Gate**, a committed seawall crossing that asks the player to hold an opening before pursuing. Human playtest acceptance remains pending.

Breakwater changes the required movement between its two sequences. Sidestep the ram, using terrain to earn recovery or returning to its calm wake after a miss. On Harbor Gate, stop or move back into the opening shown at the warning's start. Breakwater makes a visible lateral brace step into the neighboring water lane; following it too soon leaves shelter. Once the crest passes, approach through the cleared floor and punish its recovery. Normal Dash offers another crossing through its existing contact immunity.

## Ram and Return Tide

- The ram tracks a living player for 0.35 seconds, then commits its capsule for 0.55 seconds. Its endpoint is 180 units beyond the captured target, bounded to 280–760 total travel and clipped by terrain or the logical arena edge. It moves at 640 units/second, testing player centers against its 38-unit danger radius once.
- Terrain contact skips Return Tide and gives 1.8 seconds of stationary recovery. The actual 1160 by 860 arena boundary and cover still present at contact both count. An inward reset prevents repeated point-blank wall impacts; the next sequence is Harbor Gate, so wall bait does not remove every subsequent threat.
- A miss gives 0.55 seconds of landing recovery and a full 1.8-second brace. Two curved lobes warn the returning path while the vacated ram lane becomes a calm wake.
- Return Tide moves at 310 units/second from 66 units behind the stopped body toward the ram's starting side. Its 24-unit half-depth and curved lobes occupy 32–230 units on each side of the lane. The 64-unit wake, the area beyond those lobes and a 24-unit perimeter inset remain calm during this sequence.
- Only the moving crest deals damage, once per living player. It does not damage the entire warning area at release. The spent tide gives a 1.1-second recovery before the ordinary cooldown and Harbor Gate.

## Harbor Gate

- A 1.2-second warning commits the shore nearest the selected living player, a cardinal crossing direction, the current arena bounds and a 112-unit-wide opening centered at each living player's cross-axis position. Openings never follow later movement. Overlapping openings merge; dead or combat-removed actors do not reserve new ones. Up to four separate openings fit the supported party size.
- The warning paints the full future sweep between the openings. Calm rails and an open shore marker identify shelter. There is no permanently safe perimeter strip for this sequence: the crest reaches the actual arena edges. An opening that starts beside an edge still includes that player's position.
- During the warning, Breakwater commits a lateral brace destination in an adjacent dangerous lane and moves toward it at up to 190 units/second. Its choice prefers space away from the party. The step respects actual body collision and arena bounds, stops when blocked, and neither pushes a player nor deals ram damage. The opening itself stays fixed. This prevents holding Attack beside a stationary boss throughout the crossing; terrain can still pin the step and earn melee access.
- The crest moves shore to shore at 370 units/second, with a 24-unit half-depth. The moving band alone deals the existing hit damage, once per player per gate, with no added Slow, displacement or armor. Foam is contained inside the actual band. A full 1.1-second open recovery and the normal cooldown lead back to the ram sequence.
- Relative-time clipping compares the player's actual movement segment with the moving crest. Fast opposing movement and hitches cannot skip an entire band between sampled endpoints. Explicit player-position reset generations invalidate old movement history; joins seed current positions. The final partial step only checks movement during the gate's remaining lifetime.

Breakwater remains damageable throughout every phase. Its optional Apex route still appears from depth five with equal weight among Apex variants, contains exactly one foe and awards the existing Arcana reward. No additional enemies, build prerequisites or save-ID migrations are introduced.

## Authority and presentation

The host commits both waves. Packed geometry survives generic quantization and remains independent of interpolated enemy body position. Sequence, room and finite-geometry validation reject old or invalid snapshots. A replica predicts only an already-authorized moving crest; warning expiry never releases a client-authored attack. A lost packet lease retires its warning, openings and sound. Cancellation, death, authority changes, changed room bounds or loss of every living participant clear pending/active geometry and movement history. Normal enemy removal owns destruction at room transitions.

Gate packets omit inactive ram/Return Tide geometry and unused base animation fields, retaining active Slow, blocked state and transport completion. A four-opening snapshot with 24 Marks, four Dread owners and Slow measures 779 estimated bytes / 912 encoded bytes and survives the actual 900-byte state fitter. Native host/join verification confirms geometry, status and contact ownership together.

Move names use the existing shared plain warm lettering: `Breakwater / RAM`, `Return Tide / FIND THE WAKE`, and `Harbor Gate / HOLD THE OPENING`. No plates or new callout treatment were added. Existing SFX level, mute and bus behavior remain intact.

## Starting values

| Bearing | Solo health | Ram / tide / gate damage | Cooldown after recovery |
|---|---:|---:|---:|
| Pilgrim | 720 | 12 | 2.025 s |
| Delver | 900 | 16 | 1.5 s |
| Harbinger | 1080 | 18 | 1.275 s |
| Forsworn | 1260 | 20 | 1.05 s |

Co-op health remains `1 + 0.6 * (players - 1)`. Party size does not increase damage or shorten warnings. Existing Ascension/Endless modifiers keep their normal channels.

## Verification and playtest

Current evidence is in [breakwater-harbor-gate-20260912.md](breakwater-harbor-gate-20260912.md). Automated moving pilots compare the previous loop with continuous circling and a delayed opening response; separate close-range Attack pilots measure access during the brace. Corner/cover, normal Dash, movement reset, lifecycle, native multiplayer and GPU checks verify the implementation.

Human playtest should judge the rhythm and excitement of alternating sidestep/hold/pursue decisions, whether the shore cue reads quickly, and whether terrain bait feels rewarding without trivializing the fight. Automation does not establish enjoyment. [breakwater-return-tide-20260911.md](breakwater-return-tide-20260911.md) records the prior ram/Return Tide checkpoint; the still earlier static Backwash lives in the historical development notes.
