# Boss rewards with a reliable payoff

Feedback `FB-00a0a590b3a64a65`: rewards that primarily displace foes feel less fun; Edict can move a threat toward the player.

Edict formerly dealt no damage and pushed from a corpse in every direction. Redirecting force away from its owner would still risk another co-op player or move an enemy's warning unexpectedly. This change gives the three automatic movement rewards distinct damage/status payoffs without adding a control or toggle.

| Reward | New result | Existing limits retained |
|---|---|---|
| Edict of the Court | A credited Kill releases one Burst per original action for 80/120% of Damage, radius 120/160. Accepted damage Slows survivors to 75% speed for 1.5s. | Two levels; saved `edict_court_push_power` 40/80. The Burst claims its allowance before descendants and cannot restart through a later kill-created Field. |
| Lacuna Well | Accepted pulses Slow surviving foes to 75% speed for 0.45s. | One well, replaced by the next eligible Kill; 2.4s life; 0.32s cadence; existing radius, pulse damage and owned-Field bonus. |
| Null Corridor | Accepted damage Marks surviving foes for 1s at 10/15% vulnerability. | Normal Dash; 0.5s per-foe per-trail cadence; 24/28% Damage, width 39/46 and 3.6/4s duration. |

These Slows use the owner's existing duration bonuses. New Slow and Mark are applied after the damage and cannot retroactively satisfy that damage's conditions. Strongest active Mark wins and benefits all players; sources expire independently. Each trail retains its original Dash reaction allowances. The three rewards no longer displace foes or arm Ruinous through an automatic Push/Pull. Deliberate Attack-hit Launches and aimed Blast Push remain, including immovable compression and Keeper ward interruption.

Edict's damage is based on the owner's Damage with an 80/120% coefficient, independently of how large the killing hit was. Actual-target conditional Boons and shared vulnerability resolve once for each victim. Its Burst can feed Spark Relay, then Electric/Mark reactions, while retaining each receiver's own allowance. Runtime claims and an Edict ancestry flag prevent cycles through both immediate descendants and delayed kill-created Fields. Environmental deaths do not acquire a player owner. Suppressed kill effects retain their existing exclusions.

Stable reward IDs, level properties and save slots are retained. Null Corridor appends its Mark source after all existing serialized source indices. Host acceptance determines lethal events, new statuses and damage; client kill notifications cannot independently create an Edict Burst or forge a Corridor Mark. Pause/room/death/owner cleanup uses the existing interaction and status lifecycles.

The reaction ancestry mask gains bit 4 for Edict; the separate kill-proc suppression mask remains 3. Unknown ancestry bits retain their existing sanitization. Edict requires a registered current action and the accepted-damage descriptor used by current gameplay producers. Anonymous legacy damage remains accepted but does not create a new action merely to trigger Edict. Saved rewards use the current producer path.

Ruinous also corrects Effigy Keeper's direct-hit Launch direction: it uses the canonical Attack origin at the effigy instead of the player's body. Other characters and all Launch force, collision and compression rules retain their existing behavior.

## Verification

363 scripts and project contract checks pass. Twelve local/content suites cover 26,759 distinct checks: reward rework99, boss combinations106, Breakwater29, kill provenance47, native producers136, accepted-damage boundary87, power rewards604, descriptions465, wording1773, layouts22757, Build Details467 and glossary189. The final content pass includes all learned levels and actual Slow-duration bonuses. Lacuna initially clipped in the narrow three-card layout; its final shorter copy fits without losing its trigger, replacement, Field bonus or timing.

- Behavioral evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-b405c53a6f1549098549fee7501b5894`.
- Final description/layout/build/glossary evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-c9b8264639424d919951fc8384126a3a`.

Real ENet exposed a shared transport bug: a second far-enemy cadence gate consumed a runtime delta and then skipped delivery with an already-reset timer. The fix retains the first cadence gate, removes the duplicate gate and samples Slow through its authoritative expiry. It preserves batching, authority and environmental-death handling. All three final ENet snapshots use the final broadcaster SHA256 `C13C92235A1F0476CA152CB9C711D5F75EB3633E2A600C7177454524035BDF85`:

- Keyword/reworked rewards:108 host/23 client checks, including distant Slow receipt and exact authoritative clearing with client clocks held, both Edict levels, remote Damage, ancestry sanitization, Corridor Mark for a late observer, forged effects and lifecycle. `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-120b175ae82748dba875ad8d10e26c04`.
- Existing boss combinations:42 host/11 client checks. `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-fce70b4d50f14664b57388aa4f022cfb`.
- Returning Crescent:18 host/5 client checks. `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-b7c616d4ee854f19a9e783cee71ca6a8`.

Native presentation passes 187 frames and 2,546 checks. Root and reviewer inspected all changed reward pages at 960 width and representative upgrade/effect frames. Edict's Burst, Lacuna's pulse and Corridor's Mark leave the Charger's committed warning in place. Cleanup/replacement captures wait for existing cosmetic tweens to settle; no damaging Field persists afterward.

- All offers:85 frames/992 checks at `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-64e3e8ff0a494725bd6a33b710e76751/reward_build_frames`.
- Upgrades:96 frames/1,525 checks at `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-699199d3200143508881715cb0bd905f/reward_upgrade_frames`.
- Native reward effects:6 frames/29 checks at `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-4f56d45aaa17420095753e5e31b3e5d4/boss_reward_rework_frames`.

No unresolved implementation or verification failure remains. Human playtesting determines whether these new payoffs are enjoyable and suitably strong.

## Player checks

- Take Edict and defeat a foe beside a group. The Burst should feel worthwhile while enemies stay where their movement and attacks put them.
- Try Edict with Spark Relay or other Burst receivers. Check whether the once-per-action payoff is clear during a large multi-kill.
- Try Lacuna with Patient Hunter or Hunter's Snare. Draw foes into the well and compare sustained damage with isolated hits.
- Dash through a group with Null Corridor, then follow up on Marked foes. Try Marked Prey, Sovereign Tempo or another player's damage.
- With Ruinous, deliberately aim Launches toward foes or walls. Check that this remains a satisfying choice, including when attacking from an effigy.
