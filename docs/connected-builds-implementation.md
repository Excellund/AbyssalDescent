# Connected builds implementation

Approved scope: retain 12 Boons, 21 Arcana, nine boss rewards and six Mission bonuses; equal random offers and existing upgrade/Prismatic eligibility. Boons increase generic capability, Arcana create builds, bosses convert/peak builds, Missions temporarily amplify builds alongside a permanent Boon.

## Checkpoints

1. Shared authoritative modifiers and Mark/Snare/Dread/Wraith/Eclipse; highlighted authored keywords; renamed powers; build inspection during rewards.
2. Complete producer and boss integration, Field membership, conditional Boons, temporary Missions, save/network compatibility and isolated validation.

Human playtesting judges enjoyment and balance after automated verification. The September 9 autonomous development window authorizes a verified integration checkpoint, commit/push and replacement of the same desktop playtest with a normal dev build. Debug only when requested. Never test against real profiles.

## Approved mechanics

- Attack is deliberate input; attack hit is melee/Razor Wind/charged Blast connecting. All qualifying sources deal damage; generated projectiles, Fields and Echoes do not perform Attacks.
- Keywords: Attack, attack hit, dealing damage, Dash, Recoil, Orbit, Kill, Slow/Slowed, Mark/Marked, Field, Burst, Projectile, Push/Pull, Launch/Impact, Echo, Electric. Damage is the stat. No universal player-facing Hit or charge resource.
- Display-name changes only: Aegis Field -> Aegis Pulse, Fracture Field -> Fracture, Lacuna Echo -> Lacuna Well. Preserve IDs.
- Mark: independent owner/source applications and expiry; strongest active base vulnerability only. All players benefit. Applying a status cannot enhance that same damage event. Damage never consumes Mark.
- Wraithstep: Dash Mark 15/20/25%, existing duration/radius. L2 attack hit on already Marked foe releases Burst once per Attack. L3 propagates through at most three additional Marked foes. One visited set across Burst/propagation prevents repeated Wraith damage per foe/reaction.
- Eclipse: Kill Mark 15/20/25%, duration 4/5/6s, existing radius.
- Dread: attack hit applies 10% Mark for 3s and adds one owner-specific stack per foe/Attack; +2 percentage points per stack to owner's damage against Marked foes, caps 8/10/12. New stack helps subsequent damage. Stacks persist until foe death/room end, regardless of collateral kills, target switches, Mark expiry or inspecting a paused build. Death/removal of the owner and a real checkpoint restore clear that owner's temporary statuses; a live network build update does not.
- Snare: L1 +20% Attack damage against already Slowed; L2 +25% all damage; L3 +30% all damage and existing doubled player Slow duration. Attacks still Slow. Remove old area whitelist.
- Prismatic: Wraith/Eclipse Mark 30%; Dread 2.4 points x15; Snare45%. Preserve other Prismatic changes.
- Preserve accepted Blast/Orbit/Crescent, Wake union cadence and dash-only operation, Crown all-damage contacts/one-discharge-per-origin and Slow hop, Phantom/Reaper, Wind/Execution, Rupture exclusions, Voidfire/Blood Vow attack-specific operation.
- Riftpunch and Sigil Chain accept Razor Wind-only deliberate attack hits. Farline final Burst does not replay attack-hit effects. Fracture fault direction follows killing effect (owner-to-victim fallback), retaining nonrecursive Kill Burst.
- Warden counts each foe once per Attack, four-contact cadence. Tempo spends once on completed Dash/Recoil/Orbit and refunds once after accepted wave damage. Convergence is a moving Field with existing active-window limit. Preserve Oath/Edict/Null/Ruinous mechanics.
- Lacuna Well grants existing bonus once to enemies inside any owned Field: Wake, Sigil Chain, Lacuna, Null or active Convergence. Actual damage geometry, no decorative/pulse membership.
- Double keeps 55%, one shade, one/two copies, actual-target conditions once, no Attack event/resource replay or reopened reaction allowance.
- First Strike/Blood Pact/Severing retain +16/+9/+14 per pick and thresholds, becoming conditional Damage-basis additions for all sources. Effective coefficient includes contact time, descendant scale and Echo55%; no full flat bonus per tick. Carry fractions. Children copy unconditioned descriptors and evaluate their own target once, without double applying offensive bonuses.
- Battle Trance refreshes on any positive accepted owned damage, existing intensity/duration. Other Boons unchanged.
- Missions: same five Fortified/Focus/Combo/Relay/Node effects, consistent eligible sources. Overcharge becomes Attack/Dash cooldown x0.8 for three encounter clears, no kill stacks/nova; no Blast recharge or hold threshold changes. One confirmation awards permanent Boon + fixed temporary effect atomically; Skip declines both.
- Snapshot interpretation 2->3; recompute changed parameters from levels/Prism with legacy fallback. Preserve health/progression/Mission remaining/configuration; clear temporary state. Reject incompatible co-op protocol versions.
- Explicit authored bold+color keyword spans in cards/build/glossary; preserve current->next values and compact card budget. Your Build accessible above rewards with actual levels/boss stacks/Prism, exact pending offer preserved, keyboard/controller/mouse and release-before-rearm.

## Verification

Use isolated existing helpers. Cover all producers, four characters, levels/Prism, hit acceptance/shields/immunity/kill ownership, action/victim/reaction limits, damage fractions/cadence/overlap/hitches, restore/transitions, real host/joiner, reward odds/caps/Mission atomicity and 960/1280/1920 three/four-card layouts. Inspect normal-scale rendering and ordinary progression. Exact-version/date-filtered local reports support feedback; historical May and max-debug results do not establish balance.

## Implementation and evidence — September 9

The two checkpoint scopes share the same accepted-damage boundary and are integrated on `codex/shared-build-engines`. Human acceptance remains a playtest step. No new reward entries, offer weighting, input controls or character silhouettes were introduced.

- `CombatTargetStatus` holds independent Mark applications, owner-specific Dread stacks and fractional damage carry. `SharedDamageModifiers` resolves conditional Damage-basis Boons, pre-damage target conditions, owned-Field bonuses and temporary Mission amplification once.
- The existing interaction controller retains action identity and per-power allowances. `SharedBuildRuntime` adapts its accepted events to the existing powers; it does not apply a parallel damage pipeline. Native Field registration validates ownership, source geometry, lifetime and monotonically increasing per-source identities.
- Authored keyword spans use a canonical catalogue; cards, build inspection and glossary share it. Your Build preserves pending rewards and modal input. Mission rewards use one claim for the permanent Boon and fixed temporary effect.
- Snapshot interpretation is version 3. Changed parameters remap from learned levels/Prismatic state, including old snapshots that contain only ownership maps or enabled flags. Co-op rejects incompatible combat protocols before starting.

The full isolated regression runner passes all 68 validation stages, including compilation of 282 GDScript files. A final wording-only polish additionally passes its 308-check UI suite and 636-check wording suite.

Focused validation includes real native combat loops at all three levels and Prismatic; 558 Wake checks with 64 sustained-rate combinations; 895 snapshot checks; 557 Catalyst/Mission checks; 144 Field checks; 64 real-player status lifecycle checks; and 308 reward-inspection checks. The normal regression helper includes the new suites.

Rendered verification used the GPU at 960, 1280 and 1920 widths: 24 reward/build frames with 118 render assertions, plus 19 combat/character/electricity frames with 143 render assertions at normal camera scale. Solo and staged party scenes include shared Mark, Wake, Crown, Orbit and hostile warnings together. These images test presentation; they are distinct from the real two-process ENet tests.

Actual two-process reward availability (99 checks) and room-transition input (135 checks) pass. The shared-combat ENet fixture passes 159 checks (143 host, 16 joiner), including protocol mismatch, owner authentication, status replication, target defenses, descriptor inheritance, owner counters, cumulative refunds and Mission expiry on both machines without an intervening build snapshot. Input cancellation and live build announcements preserve committed Mark/Dread; death clears only that owner, late status packets cannot recreate them, and permitted in-flight kills retain ownership. The existing electricity ENet fixture also passes 58 checks. All automated play uses disposable projects and isolated profiles.

The local analysis workflow was run with exact version `dev-wording-checkpoint-20260909-121004` and UTC window `[2026-09-09, 2026-09-10)`, with separate temporary output. It found no qualifying completed non-debug runs. There is therefore no current balance conclusion from that report; the historical May report was not used for tuning.

## Acceptance playtest

Use regular earned progression to judge the new connections. In particular:

1. Dash-only damage should remain useful with neither manual Attacks nor Crown. Compare ordinary Wake/Phantom damage before and after generic damage Boons.
2. Wraith marks a target; repeated Attacks deepen Dread; Eclipse spreads Mark after kills. Changing target or killing a different foe must not erase the first target's Resonance.
3. Snare first applies Slow, then strengthens eligible subsequent damage. At Level 2, try a Projectile or Field as the payoff.
4. Lacuna Well should strengthen damage inside any owned gameplay Field, once even where Fields overlap. Sovereign's Double should use the copied target's conditions and never replay spending or Attack events.
5. During rewards, inspect Your Build, expand keyword details, return, reroll or claim. The offer must stay intact and closing details must not confirm it. Mission cards should grant the displayed temporary effect together with the selected Boon.

Look for recognizable causes and useful combinations without a required named partner. No claim of player-tested enjoyment or balance follows from passing automated checks. The autonomous checkpoint delivers the integrated work for this playtest; subsequent feedback guides refinement. Focused debug exports replace that same desktop file only when requested.
