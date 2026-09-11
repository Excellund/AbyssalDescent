# A fifth character with a reason to play differently

Research and design comparison — 11 September 2026. No character mechanics were changed. The proposed linked web has not been selected, and the existing name and appearance do not constrain this exploration.

Later that morning, the user authorized developing the full saved queue. The workday implementation selects the persistent origin candidate below, with subsequent Attacks relocated to the effigy. See [Effigy Keeper](effigy-keeper.md) for the current contract, implementation status and playtest questions. This comparison records the earlier research and its alternatives.

## What the comparison changes

The four established characters ask the player to hold position, combine Dash with Attack, route Dashes through enemies, or maintain a precise attack distance. These are different execution styles, but all primarily change how the same actions earn extra damage.

Other games suggest a broader question: what does the character make you manage? Rumble makes resource level change which action is attractive; Necromancer lets a resource support both offence and survival; Mesmer makes a persistent setup something that can be kept or consumed; Orianna gives ability delivery a separate position. Those are design interpretations of the official mechanics linked in the [reference comparison](character-identity-references-20260911.md).

Our rewards already contain several of those ideas in smaller form. Voidfire supplies Heat and overheat. Sigil Chain supplies persistent ground effects. Sovereign's Double supplies a temporary additional attack origin. Ruinous Impact supplies displacement conversion. A new character must make a recurring decision out of its mechanic, rather than simply starting with a renamed reward.

The [complete local audit](character-identity-synergy-audit-20260911.md) checks all 21 Arcana, nine boss rewards and twelve Boons. It supports two leading directions, with a counter specialist as a more demanding alternative.

## 1. Scavenger — fight, collect, aim

**Fantasy:** steal power out of combat and turn it back on the enemy.

Dealing damage through several distinct actions knocks one visible essence shard onto nearby reachable ground. Collecting it loads a piercing shot into the next deliberate Attack. The normal Attack still happens. Only one shard can be on the floor or loaded at a time.

The recurring choice is whether to keep dealing damage from the current position or take a different route to retrieve the shot. Once collected, aim determines whether to spend it on one durable foe or line up several. The resource can come from damaging a lone boss and from a lethal hit, so killing the initial enemy does not erase the mechanic. A new control is unnecessary, and Attack hold remains available for Blast Drive.

Three different builds are possible:

- **Moving skirmisher:** Phantom Step, Wraithstep and Static Wake make the collection route part of the offence. Battle Trance, Fleet Foot and Blink Dash improve access to the shard.
- **Delayed damage:** Returning Crescent or Sigil damage can contribute while the player moves to collect. A return pass or repeated Field tick cannot count as an unlimited stream of new actions.
- **Aimed finisher:** Damage Boons and already-Slowed or already-Marked target conditions improve the piercing payoff. Crown can react when it reaches additional victims, within the same original-action allowances.

The tradeoff is real: a detour can lose Verdict's cadence, and a normal Dash clears Farline Volley stacks. The shot is a separate Projectile; it does not automatically inherit Blood Vow's Attack multiplier or replay Sigil, Oath, Heat and every attack-hit effect.

**Main risk:** collecting a mandatory token may become housekeeping. A prototype should keep the drop close, visible and predictable, allow skipping it without disabling the character, and avoid adding many floor objects. This is the strongest fit with the current damage and reward contracts, but that does not establish that collecting is fun.

There is also roster overlap: Veil Dancer already rewards routing through the fight. Scavenger would need the stored resource and the decision about when to spend it to matter as much as collecting it. If the best play is always to immediately Dash to the shard and fire, the character has gained a chore more than a new identity.

## 2. Effigy keeper — establish an origin, fight around it, move it

**Fantasy:** control a persistent combat presence rather than merely receive another automatic proc.

The meaningful distinction from the rejected web is that the player chooses the location of a persistent object and whether it should stay there. Its value comes from a useful angle or area, not automatic links appearing on whichever enemy is already being attacked.

A concrete control model worth testing: the first Attack establishes one effigy at the aimed point within reach. Later Attacks also command one bounded strike from that origin. A normal Dash recalls it; the next Attack establishes it again. There is never a pet-management menu, several independent units, or an extra hotkey. The player chooses between keeping an established firing angle and using Dash to escape or relocate. Walking remains available without recalling it.

Potential builds differ:

- **Control a patch of ground:** Slow and Sigil Chain encourage keeping enemies where the effigy can reach. The keeper can walk around that patch instead of standing inside it.
- **Two angles:** a separate origin could reach behind a shield or cover a crossing while the player's normal Attack approaches from elsewhere. Ruinous Impact only applies if the eventual strike explicitly produces eligible displacement; placement alone must not promise it.
- **Frequent relocation:** normal Dash powers make moving the effigy valuable, but give up its established coverage. This is different from passively leaving a short-lived Double after every movement action.

It works against one boss because the object does not require enemies to survive as endpoints. It also survives ordinary kills. However, its exact attack contract remains the major unresolved design question: a copied secondary strike must not replay all Attack triggers, while relocating real Attacks would change Blast, Recoil, range checks and Double far more substantially. Establish that contract before promising combinations or implementing it.

**Main risk:** it could become an unattended turret or feel like a permanent Double. The prototype must make placement and relocation consequential enough to justify the extra object. Of the candidates, this offers the stronger change in spatial identity, with greater design and implementation cost.

## 3. Counter specialist — read danger and answer it

Timing a fresh Attack against an incoming enemy strike could catch it and prepare a counter. This makes enemy behaviour the resource, giving a very clear boss-fight identity. It differs from Bastion's proactive bracing.

Execution Edge and prepared attack bonuses could strengthen the answer; defensive Boons could soften mistakes. Waiting for a counter would conflict with sustained Heat and Verdict cadence. The game currently lacks a consistent guardable-enemy-action contract, and normal Dash is not universal ability invulnerability. Body contact, repeated hazard ticks, and attack spam must not become free counter farms.

**Main risk:** introducing a reliable guard across every boss and ordinary enemy is a substantial combat change. It merits consideration if reactive timing is the desired play experience, not as an easy passive replacement.

## Recommendation

Compare **Scavenger** and **Effigy keeper** first. Scavenger has the clearest fit with the current synergy system and smallest control burden. Effigy keeper offers a larger change in how the battlefield is used. Neither should be chosen merely to preserve Threadbinder's art or vocabulary.

Before implementing a full character, the chosen direction should pass a short prototype with no required rewards, a crowded room, and a lone boss. Then test a movement build, an Attack build and an automatic-damage build. The player should be able to describe the repeated decision and notice how rewards change it. Those playtests have not been performed; this is a shortlist for choosing the prototype, not a claim that either design is balanced or proven.
