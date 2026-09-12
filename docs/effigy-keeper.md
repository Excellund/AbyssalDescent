# Effigy Keeper

The fifth character manages the location of their Attack. The player establishes one useful position, walks around it while continuing to strike, and decides when a normal Dash is worth recalling that position. Ordinary kills and a lone boss both support this loop.

This implements the spatial-origin candidate from the [identity comparison](fifth-character-direction-20260911.md), following the user's 11 September workday instruction to develop the saved queue. It replaces the alternating-target Cross Stitch passive. The internal character and progression ID remains `threadbinder`, preserving unlocks, saved selection and Bearing progress. The shared reward pools and base stats are unchanged: 90 health, 24 Damage, 96 Attack reach, 75° arc, 0.28s Attack cooldown, 225 movement speed and 0.42s Dash cooldown.

## Controls and combat contract

- With no effigy placed, the next deliberate Attack places one up to 180 range ahead on reachable ground. That deployment Attack still comes from the player's body, including when it misses.
- Subsequent Attacks originate at the fixed effigy. Each input remains one real Attack with the player's normal damage, reach and arc. Its accepted contacts retain the existing Attack-hit powers and their own action/victim limits.
- Walking and enemy deaths leave the effigy in place. Normal Dash recalls it; the next Attack places it again. Recoil and Orbit preserve it.
- Holding Dash to start Orbit still begins with a normal Dash and its recall. Once orbiting, Attack can plant a new effigy that stays in place while the keeper circles.
- Charged Attacks use the same origin rule. Blast Drive keeps its Attack hold/release control and moves the player's body with Recoil.
- The effigy never acts autonomously. It is a delivery position, with no health pool or enemy target required to keep it alive. Room exit, death and build restoration discard the placement.
- If Seamlock's shrinking walls leave the effigy outside the usable arena, it is recalled without moving to another position. A valid anchor stays in place. The next Attack places a new effigy and still strikes from the body; the Attack count is preserved.

The implementation carries an explicit origin through geometry, cover contact and attack visuals. An attack from the effigy still uses the existing accepted-damage boundary; it does not manufacture an extra reaction allowance. Existing Echoes retain their own distinct source and copied-damage limits.

Returning Crescent launches from the Attack origin and still returns to the player's body. The keeper's walking position therefore changes its return route while leaving the effigy in place. Double's temporary shade retains its own position and copies the ordinary supported shapes at reduced strength.

Unbroken Oath's sword also starts at the committed Attack origin, including the body on deployment and the effigy on subsequent melee or charged Attacks. Walking, recall and later network cues cannot change that captured origin. Each original Attack counts its own unique accepted victims for Oath, sharing the count across melee and Razor Wind. The Attack that fills the bank does not spend it; the next deliberate Attack spends it even on a miss, with no refill from that Attack or its descendants.

Seamlock resolves illusion guesses from the host's accepted Attack start: its committed origin, direction, source and reach/arc, including charged Blast and Razor Wind's outer band. First deployment uses the body origin even though an effigy has just appeared; later strikes use the anchor. Live body movement, aim changes and animation cues cannot replace that geometry or repeat the same guess. Owner prediction does not resolve guesses on a client.

## Build choices to explore

Long Reach and Wide Arc change the patch of ground the effigy can cover. Slow helps keep foes within that patch, while Sigil Chain can turn repeated contacts there into a longer-lived area of control. Walking speed can help the keeper move safely without recalling a useful position.

Dash powers support frequent repositioning, but every normal Dash gives up the current placement. Returning Crescent and charged Attacks add different delivery shapes; they must retain the same deliberate placement decision. Sovereign's Double remains a separately placed temporary Echo rather than a second full Attack.

These are intended decisions and test cases, not evidence that the character is balanced. The key human question is whether establishing and changing an origin feels intentional and satisfying during an ordinary run.

## Player checks

1. Start with no required rewards. Attack empty ground, walk to one side, and attack a foe near the effigy. Confirm that the strike's origin and aim are obvious.
2. Kill a foe and fight the next one. The setup should survive; decide whether to keep it or Dash and place it again.
3. Fight a lone boss. Test a stationary placement and then frequent relocations as the boss moves or telegraphs danger.
4. Try Long Reach, Wide Arc or Slow, then a Dash-oriented build. Look for different placement decisions rather than merely higher damage.
5. Try charged Attacks, Returning Crescent, Orbit and Double. Watch the attack origin, projectile path and where your body moves.
6. In co-op, compare host and joiner views, including two Keepers. Each effigy should clearly belong to its player and clear on death or room transition.

## Verification

The 12 September Oath compatibility fix was reproduced before implementation. The ordinary solo four-victim fill/spend/refill cycle already passed. In a separate accepted-contact ordering probe, two interleaved two-victim Attacks incorrectly earned 30.2956 Oath instead of 22.072 because their contact multiplier shared a player counter. Melee and charged sword cues also retained the body origin after deployment. Baseline evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-f40e2db9d4b04dd084a2cb7f1962c6ab`. This identifies a specific stacking failure; it does not establish that every reported solo stacking concern had that cause.

After the fix, 396 scripts compile with both contract gates passing. Oath/Effigy28, existing Unbroken Oath38 and Keeper runtime64 checks pass in `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-df954f03114047c5a3653b1c9079bc77`. The new cases include actual deployment, full-bank cleaves, spend-on-miss, later refill, melee/Razor Wind shared victims, descendant exclusion, cancellation and committed geometry after walking/recall. Real ENet passes 26 host and 5 joiner checks in `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-d257eac7277a403fafaf50f58f674e4f`, including accepted bank reconciliation, an explicit interleaved-contact transport probe, owner/observer sword origins and host charged Attacks. Eight native GPU frames and 31 checks pass at 960 and 1280 widths in `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-c334ff3c11af40179d591abca3fc20d0/oath_effigy_frames`; deployment, displaced Keeper, charged sword and settled views were visually inspected.

Verified 11 September 2026 in disposable projects and isolated profiles:

- The later Seamlock integration passes 365-script compilation and both contract gates, Keeper runtime64/lifecycle57/integration51, and Seamlock bands47. The expanded lifecycle cases use real Attacks, charged Blast and native wall shrink; they check fresh placement and reject retired damage origins even after the arena regrows. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-dcc742384c19427bbfd12f220d43765a`.
- The extended real ENet fixture passes 80 host / 16 client checks. A joiner plants near a future wall, walks away and makes a perpendicular Attack: the native host Seamlock resolves only the false illusion touched from the committed anchor, leaves the body-side decoy intact and rejects a changed-aim duplicate. One shrink preserves the anchor; three steps recall it with its Attack phase unchanged. The owner's accepted host message clears its anchor before local bounds change, then replicated Seamlock state produces matching bounds. Earlier forged/stale requests, damage parity and observer-recovery checks remain covered. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-e5679b09e1f84ed4b0d7ca5691f4911c`.
- All 350 scripts compile; world-property and multiplayer-configuration contracts pass. Runtime64, lifecycle40, stable-ID integration51, combined synergies32, shared wording1443 and power descriptions465 checks all pass. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-f74003c725a24f00a49151495f934329`.
- Real ENet: 57 host and 11 client checks pass. These include actual owner movement and build broadcasts, missed deployment, anchor attacks, kills, recall, forged/stale requests, reconstructed observer state and Execution/Oath parity at modified Damage. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-7795ba071fa7467db70dc7ae4e6a754b`.
- Thirteen GPU frames and 81 checks pass. Visual review confirms distinct owner-colored effigies, the correct deployment/body and subsequent effigy origins, and complete recall. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-bc16726af17e44e3bb4eb269c379d3b1/threadbinder_frames`.
- Character selection, Build Details and full glossary pass 24 GPU frames and 88 checks at 960, 1280 and 1920 widths. Selection passive text was enlarged and given more width after visual review found the previous layout too small. The final 960-width selection and build view were visually inspected. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-6c5f85d86bda427c81fc08e24398fc2b/passive_ui_frames`.
- The menu fit/focus suite passes 211 checks after that readability change, including four viewport sizes and full text containment. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-e7ff3e17ef3344fd92ec8a8ad146a833`.

The tests cover actual solid cover and room boundaries, the real Kilnheart boss, native charged damage, Recoil/Orbit persistence, per-action reaction limits and independent target conditions. Human testing still needs to establish whether placement is intuitive and enjoyable, and whether damage and mobility feel balanced through a normal run.
