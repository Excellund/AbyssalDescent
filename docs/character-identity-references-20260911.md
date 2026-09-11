# Character identity references — 11 September 2026

Design research, not an implementation specification. The user asked to reconsider the fifth character after finding alternating targets irrelevant, and was not convinced by an automatically linked damage web. The name and thread theme are therefore open questions. This document distinguishes published mechanics from our design interpretations.

## What the reference characters make the player decide

| Reference | Published mechanic | Design interpretation for our game |
|---|---|---|
| Rumble, League of Legends | Casting generates Heat. A middle range strengthens abilities; reaching the maximum strengthens basic attacks while temporarily preventing spellcasting. [Riot's champion description](https://www.leagueoflegends.com/en-us/champions/rumble/) | A resource is interesting when different levels change which action is desirable. Merely filling a bar for another automatic explosion adds little agency. Our version would need a readable reason to maintain, spend, or intentionally exceed a threshold. |
| Necromancer, Guild Wars 2 | Certain weapon attacks and nearby deaths supply life force. Death Shroud spends that resource as a second health pool and supplies another skill set. [ArenaNet's profession description](https://www.guildwars2.com/en/the-game/professions/necromancer/) | The same resource can serve aggression and survival, making timing consequential. An adaptation must generate resources against one boss as well as crowds; kill-only generation repeats Threadbinder's single-target weakness. A second complete control scheme would exceed what a passive alone can communicate. |
| Mesmer, Guild Wars 2 | Illusions attack and distract enemies; the player can shatter them for secondary effects. Their target remaining alive matters to their persistence. [ArenaNet's profession description](https://www.guildwars2.com/en/the-game/professions/mesmer/) | Keeping a useful setup versus consuming it creates a real choice. Target-tied persistence is also a warning: rapidly killing weak enemies can erase the character's payoff. Any construct or echo character here should work before the first reward and should preserve usefulness when its original target dies. |
| Orianna, League of Legends: Wild Rift | Command: Protect moves her Ball to an ally, damages enemies along its path, and shields its recipient. [Riot's ability description](https://wildrift.leagueoflegends.com/en-us/champions/orianna/) | A separately positioned object can make the path and destination of an ability meaningful. Our candidate would need a simple way to place and relocate that origin with existing controls. Copying extra command buttons or requiring management of another party member would not suit the current roster. |

These are observations about the documented mechanics, not claims about current competitive strength or player popularity. The transferable decisions in the last column are our analysis.

## Constraints from this game

- The four established characters already cover bracing between Attacks, converting Dash into an Attack payoff, chaining contact Dashes, and maintaining an outer-range strike position.
- The fifth character should create an identifiable decision before any Arcana is acquired. Its best reward combinations should deepen that decision rather than unlock its basic functionality.
- A character must retain its loop against a lone boss and when ordinary foes die quickly. Multiplayer cannot require monopolizing kills or another player's targets.
- Attack and Dash should remain understandable. Blast Drive already assigns meaning to holding and releasing Attack; a competing hold mechanic needs a deliberate compatibility design.
- Automatic damage is not another attack hit. Damage sharing, summons, resource drops, echoes, and environmental effects cannot silently replay Attack-only powers or bypass an original action's limits.
- Give each candidate several useful reward directions and at least one honest weak interaction. Universal synergy is neither required nor a credible design claim.

## What to evaluate in the candidates

The strongest open spaces are enemy arrangement, spatial resource collection, and reactive defence; resource management and a remote attack origin are also worth comparing. None is selected by this note. The local synergy audit should determine which one can support a coherent base loop and multiple builds without becoming an existing Arcana in character form.

A candidate is ready for a prototype only when we can describe an ordinary room and a lone-boss encounter, name the player's recurring decision, and show how at least three substantially different reward builds change that decision. The test is whether play feels different after a minute, not whether the effect graph has more connections.
