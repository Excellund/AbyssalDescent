# Synergy pieces connecting builds

Feedback `FB-0ca70d18a6c54ae3` requests more pieces across Boons, Arcana and boss rewards that connect existing mechanics. This implementation adds five pieces to the shared equal-random pools. It keeps the existing upgrade limits and all old save IDs.

| Piece | Kind | Trigger and payoff |
|---|---|---|
| Patient Hunter | Boon | +12 conditional Damage basis per pick against already Slowed foes; up to three picks. |
| Marked Prey | Boon | +12 conditional Damage basis per pick against already Marked foes; up to three picks. |
| Stormbrand | Arcana | Electric damage applies a timed Mark, once per foe per original action. Level 3 also Slows foes that were already Marked before that damage. |
| Spark Relay | Arcana | Burst damage fires one seeking Electric Projectile from your body, once per original action. |
| Shatterwake | Boss reward | Projectile damage releases one Burst around the struck foe, once per original action, including that foe if still alive. |

Patient Hunter and Marked Prey deliberately reward a prepared build more than Heavy Blow's unconditional +7. They use the existing coefficient-scaled conditional Boon calculation, including short Field ticks and reduced Echo strength. Applying a new condition with the same damage does not retroactively earn the bonus.

Stormbrand's Mark values are 10/14/18% for 3/3.5/4 seconds; Prismatic is 22.5% for 5 seconds. Its level-3 Slow is 75% movement speed for one second, extended by existing global Slow-duration bonuses. The strongest shared Mark still wins, and all players benefit. Electric Fields can therefore prepare Mark without a Kill or deliberate Attack.

Spark Relay deals 50/60/70% of the triggering Burst's base damage; Prismatic deals 87.5%. It hits at most 1/2/3 distinct foes once each, with three at Prismatic. Travel speed is 620, range 440 (528 Prismatic), radius 8. It now seeks the struck foe while alive and reachable, or the nearest reachable living foe when that target dies. It retargets after each hit using the remaining travel budget and stops at solid cover or the room edge. With no reachable living target it creates no bolt; see [the Spark Relay follow-up](spark-relay-seeking-20260911.md). Effigy Keeper's effigy does not relocate this explicitly body-origin effect.

Shatterwake deals 60/80% of the triggering Projectile's base damage in radius 100/125. Solid cover blocks its Burst, so landing a projectile on the near side of cover does not damage foes on the far side. It adds a direct payoff to Returning Crescent and Spark Relay, including a single boss, without moving enemies toward the player. The later saved displacement-reward feedback remains a separate queued item.

## Interaction and authority contract

- All receivers run from accepted, owned damage. Rejected damage and nondamaging areas cannot trigger them.
- Spark Relay and Shatterwake each claim their own once-per-original-action allowance before creating any descendant. Both possible converter orders terminate; return legs, further victims, delayed ticks and Echoes cannot reopen those allowances.
- Stormbrand has a separate per-foe/original-action allowance. Its new status source is appended to the existing wire catalogue, preserving earlier source indices.
- Descendants retain run, room, owner, epoch, sequence and reaction ancestry. Crown/Tempo exclusions and inherited kill restrictions remain effective.
- Raw damage and the proportional Damage coefficient travel together. Each descendant's actual target evaluates its own conditions once; parent Mark/Slow/health bonuses are not copied as already-conditioned damage.
- The existing Blast Drive cone exposes its advertised Burst form. An Echo of Blast retains Echo + Burst; melee and Razor Wind Echoes retain Echo. Property matching adds no Attack-hit, Oath, resource or movement privileges.
- Spark Relay is simulated by the host. Replicas display bounded, validated projectile state; room changes, death and cancellation invalidate old effects. It creates its controller lazily, avoiding idle processing for players who never trigger it.

## Player checks

Try Static Wake with Stormbrand and watch Electric trail damage prepare Marks. Add Marked Prey or Sovereign Tempo and check whether that setup creates a useful payoff. Try a Burst source with Spark Relay, then Returning Crescent or Spark Relay with Shatterwake. Check both crowd spread and single-boss damage, particularly whether the bolt's body origin and blocked path are understandable. Compare the value of the conditional Boons against a generic Damage pick. In co-op, check that status, projectile travel, damage and kill credit agree for host and joiner.

## Verification

Final isolated verification passed on 11 September 2026. All 355 scripts compile, and project contracts pass. Focused checks cover 116 runtime interactions, 48 lifecycle cases, 87 accepted-damage boundary cases, 133 native producer cases, 603 reward hooks and 189 glossary checks. Earlier content verification also passed 1,772 wording, 465 description, 22,757 reward-layout, 467 Build Details and 949 availability checks.

Evidence directories below are under `C:/Users/mikel/AppData/Local/Temp/`:

- Runtime: `abyssal-validation-5892f4be713246629df03beba3b890e9`; lifecycle: `abyssal-validation-340a74576e4e4f0ca92f8d9863a77640`.
- Boundary and producers: `abyssal-validation-7f8ddec15dd44b3c98e57d3e5d277d92`; reward hooks: `abyssal-validation-796e813a47664a4f979a6f732ebde9b9`; glossary: `abyssal-validation-ef06b4af6c1e4666bd6d77a75fc9e44e`.
- Genuine ENet, 61 host and 13 client checks: `abyssal-enet-9c5d5868e94249a7b7dada21e08eab4b`.
- 85 reward/Build frames and 992 checks: `abyssal-gameplay-render-d7229775af0b4d1193f3ee8d2f69b2d8/reward_build_frames`.
- 96 upgrade frames and 1,525 checks: `abyssal-gameplay-render-062388672c9744c1803ee7f861993d4f/reward_upgrade_frames`.
- Six native combat frames: `abyssal-gameplay-render-13b5e00849f344408da54d350a6c3635/keyword_synergy_frames`.

Visual review covered new cards, levels, Prismatic values, expanded Rules, projectile trails, contact effects and cleanup at 960 and 1280 widths. Lifecycle review fixed character-change retirement while preserving same-package state and preventing a newly constructed actor from clearing another owner's statuses. Final normal desktop delivery remains part of the workday integration checkpoint; balance and enjoyment await human playtest.
