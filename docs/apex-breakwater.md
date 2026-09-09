# Apex Breakwater

Status: implemented, verified and pushed as checkpoint `31995f5` on `codex/overnight-buildcraft-20260909`. Normal playtest `dev-overnight-breakwater-20260909-0038` replaces the same desktop executable. Delivery is recorded in [overnight-development-20260909.md](overnight-development-20260909.md).

Breakwater is one optional Apex foe built around a positioning decision: bait its committed charge toward the arena edge, leave the marked lane, then attack during its longer recovery. It remains vulnerable throughout the fight. Ordinary movement, dash and attack provide a complete answer; no Arcana is required.

## Attack and response

- Track one living player for 0.35 seconds, then hold a fixed capsule warning for 0.55 seconds. After locking, neither player movement nor a target's death changes the direction.
- At lock, commit to 180 pixels beyond the target's last position, clamped to 280–760 pixels of total travel. Charge along that fixed segment at 640 pixels/second. Cover or the logical arena boundary stops the sweep early. The danger radius is 38 pixels around the actual traveled center segment; each living player's center is tested once per charge. The warning uses that same geometry.
- Wall/cover contact leads to 1.8 seconds of stationary, harmless recovery. A charge that reaches its range limit recovers for 0.55 seconds. Neither outcome adds an explosion or another attack.
- Reposition inward before the next windup so fighting at the perimeter does not cause repeated point-blank wall impacts. Recovery and warning remain identifiable through body posture, outline and restrained effects.

The existing optional Apex route begins at depth 5 and chooses between its variants with equal weight. Breakwater uses the open 1160 × 860 Apex arena and the existing Arcana reward. Exactly one foe is allowed, including after co-op, mutator and Endless processing. No reinforcements, armor gate or additional phase are added.

## Starting values

These are initial playtest values, not conclusions from the historical DB report or the two recent local runs.

| Bearing | Solo health | Charge damage | Cooldown after recovery |
|---|---:|---:|---:|
| Pilgrim | 720 | 12 | 2.025 s |
| Delver | 900 | 16 | 1.5 s |
| Harbinger | 1080 | 18 | 1.275 s |
| Forsworn | 1260 | 20 | 1.05 s |

Co-op multiplies health by `1 + 0.6 × (players − 1)` and preserves damage, movement, warning and recovery. Existing authorized Ascension/Endless stat pressure still applies through the normal mutator channels. Charge speed, reach and warning windows have no mutator mappings.

## Build interactions and verification

Razor Orbit can use Breakwater as a moving anchor; ordinary collision rules still detach the player. Blast Drive offers another way out of the locked lane. Returning Crescent and Sovereign's Double use their existing damage rules, while Ruinous Impact compresses this displacement-immune Apex. Player effects cannot stun or launch it.

Validation passes 2,397 encounter checks across all Bearings, party sizes and biomes, including routes, rewards, normalization, Endless, safe spawning and checkpoint/resume. Runtime tests pass 93 checks, including local SFX volume and mute; build combinations pass 29; separate ENet processes pass 37 host/joiner checks. A separate physics soak exercised 201 charges over 772 simulated seconds, including long frames, corners and player body blocking. Seven real GPU states cover the route door, tracking, locked host/joiner warnings, charge, impact and recovery. Human playtesting must still establish whether baiting the charge feels satisfying and the recovery is easy to recognize.
