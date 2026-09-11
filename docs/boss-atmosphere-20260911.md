# Boss encounter atmosphere

Feedback `FB-e12bfd08ce2f49bd` asks for the main menu's sense of a voice addressing the player during boss encounters. Each boss now has a short personal greeting and final line, authored in the shared identity catalogue. These use the existing survey, boss-reward and victory surfaces.

| Boss | Greeting | Final words |
|---|---|---|
| Warden | Your descent ends at my feet. | Then carry what I could no longer hold. |
| Sovereign | You may kneel now. The room will teach you how. | Take the crown. It has never spared its bearer. |
| Lacuna | I heard you before you had a name. | Go, then. Take the silence with you. |
| Kilnheart | Come closer. Let me see what survives the heat. | Keep it burning. It is all I have left. |
| Glassweaver | Keep moving. You make the pattern for me. | One loose thread. That was enough. |
| The Null Archivist | Hold still. I have almost finished erasing you. | An error, then. I will leave your name. |

The Warden treats the descent as a duty and burden. The Sovereign commands obedience while knowing the cost of its crown. Lacuna speaks as something older than the player's identity. Kilnheart tests what survives; Glassweaver makes the player's movement part of its pattern; the Archivist treats a surviving player as an error in its work.

## Presentation contract

The whole greeting appears during the existing arena-survey readiness period, beneath the boss's name. Its layout reserves the actual HUD columns and wraps at the existing 30/18 font sizes when the window narrows. Movement or Attack can engage immediately. In co-op, a local ready player's waiting message takes priority. Dialogue disappears before active combat, leaving ability callouts and committed danger warnings clear. Existing entrance motifs and synchronized music continue normally.

For the first two acts, attributed final words use the existing narrative slot at the bottom of the reward screen. The final boss speaks through the existing victory subtitle, selected from the authoritative run summary. Older summaries without a recognized final boss retain the generic subtitle. No dialogue is inserted into live combat.

## Player checks

On reaching a boss, pause to read its greeting, then start when ready. Check whether the line and arena create anticipation and whether each boss has a recognizable personality. Make sure the first attack warning remains easy to read. Check final words after victory, including as a co-op joiner, and whether repeated encounters remain quick to start.

## Verification

Production integration is complete. Initial isolated verification compiled 357 scripts and passed contracts plus seven suites/1,437 checks in `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-3b05d3c1816d44fea4d99cfea552a59f`. These cover all six native door/ready/death paths, descent/music continuity, boss selection, results, checkpoint lifecycle, Catalysts and peer departure.

Genuine room-entry ENet passed 581 host and 583 client checks in `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-78e6b7f3ce97440093afd0420bc8cf80`. Visual review found that long greetings overlapped the left HUD at 960 pixels; the corrected layout reserves those columns and passes live 1280-to-960 resize, wrapping and Ready-banner restoration checks.

Final atmosphere verification passes 139 checks with 357-script compilation/contracts in `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-8e25fd3adf9f427b8ca0cc9e311243a9`. The final layout also passed 179 descent checks in `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-ebba508f3c0a4ba3b01f4e1cb79fcf6a`; the other five related-suite results remain applicable from the initial run.

All 18 native frames and 183 checks pass in `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-d90477fa7df548b490741b28b3f78527/boss_atmosphere_frames`. Root and the reviewer inspected all six greetings, four reward epitaphs, two victory subtitles and six initial warnings across this final capture and the equivalent preceding capture `abyssal-gameplay-render-036f3529d59d4e12bae40595560e61f7`. The fixture advances real spawn/reward presentation and the native behavior-to-overlay update before capture, so bodies, cards and the Lacuna warning are visible. The game code did not need changes for those fixture-only corrections. Normal desktop delivery and human atmosphere feedback remain pending.
