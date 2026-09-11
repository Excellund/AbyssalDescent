# September 11 playtest

The normal [desktop playtest executable](<C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe>) is ready. Internal build: `dev-20260911-150813181-4ec0f6c4`. The ten workday items and the subsequent Static Wake damage reduction are implemented, verified and awaiting your playtest.

The workday baseline passed the full 99-suite run, 365-script compilation and contract checks. The subsequent Static Wake revision passed nine focused suites (24,881 checks), compilation/contracts, 27 exported-package checks, and 62 headless automation checks of the actual executable's menu, first descent, movement, return and reopening. Multiplayer and native visual checks are recorded in the feature documents. Scheduled work remains paused; this later change follows the player's direct request. The game source and Desktop executable match the verified delivery.

Start with a normal run, then try Effigy Keeper and take a mix of ordinary and special doors. Pick the new pieces when offered; there is no need to collect every combination in one run.

| Look at | Try this | What should feel different |
|---|---|---|
| Static Wake damage | Compare sustained damage against a boss and foes crossing your Dash trail. | Damage is 25% lower at every level, including Prismatic. Its Electric Field and level-3 Slow still support builds. |
| Biome identity | Take Missions, Trials, Breach and Undertow as well as ordinary doors. Read the small biome cue during combat. | The biome changes the fight along every route. Required capture circles and the escort route stay usable. |
| Biomes during bosses and Apex encounters | Lure a foe into a green biome zone. Compare it with the enemy's own warning. | Green biome zones affect foes only; enemy warnings still demand movement. The two should be easy to distinguish. |
| Effigy Keeper | Attack to place the effigy, walk away and Attack again. Dash, then establish another position. | Later Attacks come from the effigy. Positioning it should create useful decisions rather than busywork. |
| Effigy combinations | Try Blast Drive, Returning Crescent or Ruinous Impact. | Attack effects use the effigy's position where appropriate; your body and its movement stay clear. Crescent returns to your body. |
| Effigy against Seamlock | Aim at an illusion from the effigy, and watch an outer anchor as the arena shrinks. | Illusion guesses use the real strike's position. An anchor outside the shrinking arena is recalled; the next Attack places a new one from your body. |
| Reward readability | Compare Electric, Field, Burst, Slow and Mark across several cards, including hovered cards and a small window. | Keywords are quicker to recognize without the reward screen becoming a rainbow. Text focuses on trigger, payoff and meaningful limits. |
| Builds using statuses | Try Stormbrand with Electric damage; add Marked Prey or Sovereign Tempo. Try Patient Hunter with a source of Slow. | One piece prepares a condition that another can use. A newly applied status helps later damage. |
| Builds using damage forms | Try Spark Relay with Burst damage, or Shatterwake with Projectile damage. | A Burst can send an Electric bolt from your body; a Projectile can create a Burst. The reactions should be visible and useful against both crowds and a single boss. |
| Revised boss rewards | Take Edict of the Court, Lacuna Well or Null Corridor. | Edict creates a damaging, Slowing Burst on a Kill, once per original action; Lacuna leaves a damaging, Slowing well; Corridor damages and Marks foes along your Dash. Judge whether they help your build without disruptive displacement. |
| Boss personality and pressure | Read the greeting and final words, then replay and engage quickly. Watch the alternate bosses' follow-up attacks. | Each boss should feel like a character addressing you, and its first warning should remain clear. Judge the pressure and fair escape routes, not only damage taken. |
| Enemy readability | Identify enemies in a crowded room, especially Weaver, Drifter and Sentinel. | Their new bodies should be recognizable while their attack warnings, status cues and silhouettes remain readable. |
| Death zones | Defeat a Pyre and watch the full lifetime of its zone. | The damaging area stays visible, then disappears when safe. The inset clock should help you judge the end. |
| Smoothness and HUD | Fight a crowded room, gain a reward stack, let Slow expire, and resize or open Build Details. | Combat should stay smooth and the HUD should reflect health, movement and build changes promptly. |

If playing co-op, also compare a joiner's view of distant Slow/Mark, biome warnings and the Pyre death-zone expiry. Try returning to the menu and continuing between rooms; progression and the chosen biome should remain consistent.

Useful feedback includes the character, biome, room or boss, important powers, and whether you were hosting or joining. For difficulty, describe the move that forced a decision or felt impossible to avoid. For build identity, describe the decision the power encouraged you to make.

## Build receipt

- Normal menu and progression; updated September 11 at 17:13 local with the Static Wake nerf.
- File size: 124,299,072 bytes.
- SHA256: `58DDEA0164FC7554012AC10BFE7E4FECF74EC94E946B582D3E042597A4CE6251`.
- Full regression of the workday baseline: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-70ecaf86751b4df0b649d3a346c4c36e`.
- Focused balance verification: [Static Wake revision](static-wake-balance-20260911.md).
- Executable verification: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-3e5eaab609eb48dfb4658b0e4281c714`.
- Current source/build/verification receipts: `.feedback/static-wake-20260911/`; the original workday receipts remain in `.feedback/workday-20260911/`. The delivered game includes the preserved uncommitted combined work and today's verified changes on `codex/combined-playtest-20260910`.
