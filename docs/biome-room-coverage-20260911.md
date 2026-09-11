# Biomes along every combat route

Feedback `FB-40430c4bc1534099` describes taking special doors through a biome without encountering its systems. This revision separates a room's authored terrain from the biome effect applied during combat. The terrain whitelist and all special arena layouts stay as authored.

## Room behavior

| Context | Biome behavior |
|---|---|
| Ordinary combat | Existing rules, cover layouts, timing and damage. |
| Missions, Trials, Breach and Undertow | Smaller patterns, longer pauses and reserved objective space. |
| Bosses and all Apex rooms | Green biome patterns affect foes only. Enemy ability warnings keep their normal danger. |
| Compact room without enough space | Switch to green assistance before committing the next warning, then retain that allegiance for the room. |
| Shatterfield without cracked cover on entry | Warned fragment falls, using the new smaller patterns. Breaking ordinary cracked columns does not activate fragments. |
| Tutorial, Rest Site, starting/reward state | No active biome event. Survey and modal pauses suspend combat effects. |

Compact rules have a 1.8-second warning, five-second recovery and 0.5-second active window; Haunt remains active for two seconds. Assistance uses six-second recovery. Haunt Slows to 75% movement speed in these modes. Existing damage remains 8 to players / 35 to foes, or 10 / 50 for Storm, with normal damage protection. Assistance excludes players from damage and Slow.

One event exists at a time. The compact families are rockfall, shadow or fragment circles; alternating small crushing discs/rings; a fixed lightning strike; a short eruption strip; two void strips separated by a gap; a turning storm sector; and paired floor pulses. Assistance uses the same family and chooses an enemy's location where available. These are environmental effects: they do not acquire player Attack/Electric ownership or create player kill rewards.

The persistent HUD cue and biome inspection describe the actual current mode, explicitly naming damage or Slow. Assistance keeps a green outline through warning and activation; the tooltip distinguishes these zones from enemy danger. If a compact room switches to assistance, a still-visible biome banner updates its advice without restarting its fade or replacing boss dialogue. The glossary explains ordinary rules and how special rooms vary them.

## Required space and lifecycle

The world passes current effective room bounds and readonly objective geometry to the existing room-owned biome controller. Hold the Line reserves the whole control circle. Circuit Sweep reserves the current circle and every future node. Intercept Run reserves the entire authored drone route as a capsule at the drone radius, leaving a continuous route within the escort zone. Planning adds a conservative 22.63-pixel player footprint and 12 pixels of walking margin. Existing ordinary damage boundaries do not change.

Candidate selection is bounded and avoids both required space and solid cover. If a room cannot fit a pattern, assistance removes its risk to players. A committed warning never slides or shrinks: changed bounds or newly required space cancel an invalid event, begin recovery and require a new full warning. Effective bounds may shrink to the existing Seamlock minimum of 320 by 240. Boss entry resets the prior objective before configuring its biome.

Authority publishes mode, fragment choice, effective bounds and fixed event geometry through the existing reliable state message. Clients do not plan local hazards. A reusable envelope validator runs before future-room caching so malformed higher revisions cannot replace valid pending warnings. Applying a state also checks run/room identity, current configuration, initial bounds ceiling and revision/event ordering. Only compact-to-assistance promotion is permitted; assistance cannot become dangerous midroom. Legacy ordinary packets retain compatibility.

## Verification

Final verification passed 365 scripts and world/network contracts, 1,246 real-Main room checks, 1,182 terrain identity checks, 228 cover checks and 498 controller checks. The final presentation suites passed 189 glossary, 178 descent presentation, 36 combat-pause, 54 HUD invalidation and 139 boss-atmosphere checks. Native review caught and verified the fix for a stale entry banner after assistance promotion. The final gallery contains 38 frames and 272 checks, including all nine compact/assistance families, real boss/Apex warnings and 960-pixel contextual tooltips.

Separate biome ENet processes passed 330 host and 343 joiner checks, covering authoritative geometry/allegiance, objective/bounds context, malformed future states, lifecycle and no player-owned environmental reactions. Related Effigy/Seamlock integration fixes passed 219 scoped checks and an expanded 80-host/16-joiner Keeper test, including real committed illusion guesses and authoritative recall before the joiner's local bounds update; see [effigy-keeper.md](effigy-keeper.md). No further defect was found in the bounded ancestry and committed-warning review.

Evidence under `C:/Users/mikel/AppData/Local/Temp/`:

- `abyssal-validation-5310f767be234bccbcc7a9be84279c2d`: final real-room context, including live banner agreement.
- `abyssal-validation-c90826a6b7f7478199d4546ee1cca814`: unchanged ordinary terrain and cover.
- `abyssal-validation-728a3cf290e84ac897f9ef80052e3749`: controller geometry/lifecycle checks.
- `abyssal-validation-7d3c7180a6f14adf926115d630839721`: final glossary, descent, pause, HUD and boss presentation.
- `abyssal-gameplay-render-fd6955f89fbb4ec38d0e515c3380894d/biome_room_context_frames`: final native gallery and manifest.
- `abyssal-enet-39bc7ecd62114517b313c2049c07604e`: final biome transport.

The feedback item is awaiting human playtest. Final combined regression and normal executable delivery are tracked in [workday-development-20260911.md](workday-development-20260911.md).

## Player checks

- Take mostly special doors. Look for the same biome theme in Missions, Trials, Breach and Undertow.
- In Hold the Line, Circuit Sweep and Intercept Run, check that the required circle or escort route remains usable when a biome warning appears.
- In boss and Apex fights, try drawing foes into green zones. Green biome zones should be safe for you; the boss's own warnings still require a response.
- In Shatterfield, compare cracked cover in ordinary rooms with fragment falls in rooms without it.
- Read the persistent biome cue, then inspect the biome name. Both should explain the room you are currently fighting in.
