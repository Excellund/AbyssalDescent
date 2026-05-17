---
name: roguelike-design-principles
description: "What makes a good roguelike/roguelite. Use when designing new systems, evaluating content additions, or making design decisions about items, upgrades, enemies, levels, or run variety in this game."
argument-hint: "Design question or system being evaluated"
---

# What Makes A Good Roguelike / Roguelite

Reference framework distilled from deep play-testing and design analysis of ~100 roguelikes. Use this as a design gut-check before adding or changing systems.

---

## 1. Uniqueness From The Start

Every run should feel meaningfully different before the first enemy is fought.

- Give the player a meaningful choice at run start: character, weapon, aspect, starting boon, passive, relic.
- These choices should **prioritize a build direction**, not just cosmetically change things.
- Pre-run customization is the single best antidote to the "same loop" feeling on repeat.
- Examples done well: Hades (weapon + aspect + keepsake + heat), Warm Snow (god boon + relic), Ravita (weapon variant + tickets).

**Design gut-check**: Can the player pick something at run start that genuinely tilts how the run will go? If every run starts identically, the genre's identity is diluted.

---

## 2. Risk vs. Reward

Risk vs. reward may be the single most important concept in the genre.

- Players must feel that taking a risk was *their choice*, never the game's fault.
- Cursed / downside items are a classic form: huge power boost, meaningful cost. When the player dies to one, they should feel it was their call.
- Other forms: elite fights for better loot, conserving ammo vs. using it, buying a useless item speculatively for later payoff, spending HP as currency.
- Some games build their entire mechanic around this (Ravita: currency is HP; Blazing Beaks: enemies drop cursed items you trade in).
- **Balance principle**: If players evade all risks, they should not be strong enough to finish the run. Risk-taking must be load-bearing.

**Design gut-check**: Does every major decision in the run have a real cost attached? Are players ever rewarded for playing it safe the whole way through?

---

## 3. Diversity (Run-to-Run Variance)

Runs must feel and play differently. This is the core replayability contract.

- Items, passives, and upgrades should force the player to adapt and discover new builds, not just execute the same optimal strategy.
- Warning sign: a game where the roguelike elements (random items) don't change how the core gameplay plays out is not a roguelike — it is an action game with random dressing.
- The randomness should sometimes push the player *outside their comfort play style*.
- Pre-run customization (see §1) can constrain early variance, but mid-run divergence must still be real.

**Design gut-check**: Compare run start vs. run end — is there a visible difference in how the player plays? Compare two runs side by side — do they feel like different experiences?

---

## 4. Synergies

Synergies are the heart of roguelike excitement. Categorized into three tiers:

### Minor Synergies
Stat changes that are always useful but become *more impactful* given the current build.
- Examples: +headshot crit damage while using a sniper; +fire rate while carrying a poison-on-hit bullet.
- Role: the spice. Keep runs feeling fresh even when the overall build direction is familiar.
- These are the baseline — every item should have at least minor synergy potential.

### Major Synergies
Items/upgrades that are **build-defining** when the build supports them but have minimal value otherwise.
- Examples: combo-focused items in Wizard of Legend; fire elemental damage while using fire weapons.
- Finding one that fits perfectly is one of the most rewarding feelings in the genre.
- **Balance warning**: If too many items require specific archetypes (like wands needing mana stones), players feel cheated opening chests. Non-matching major synergy items should still have *some* baseline utility.
- Fine line: too many hyper-specific items limits player creativity and makes bad drops feel punishing.

### Scripted Synergies
Predetermined coded interactions between specific item pairs.
- Less creative discovery, but delivers a different kind of excitement: the thrill of "I found the pair."
- Works best when the pool is large enough that finding the combo feels lucky, not routine.
- Some games hide the combinations entirely — achievment-hunt style discovery that holds up for hundreds of hours.

### Best Practice
The best roguelikes blend all three, weighted toward minor + major synergies, with scripted synergies as high-excitement peaks. Items should feel useful broadly while having spikes of power in specific builds.

---

## 5. Level Design

Randomly generated levels are not the focus — they are the container for the run. Design accordingly.

### Approaches (all valid depending on scope):
- **Single fixed layout** (Vampire Survivors, Brotato): acceptable when core gameplay carries the experience.
- **Library of rooms** (Enter the Gungeon, Peglin): rooms are pulled from a fixed set and scattered randomly. Works well; players will eventually recognize room patterns, but variety is sufficient.
- **Chunk-based randomization** (Dead Cells): floors are assembled from random fragments stitched together — hides patterns better, more organic feel.

### What makes level design work in a roguelike:
- Levels should **complement the gameplay** rather than stand alone as puzzles. A sniper build plays a room differently than a shotgun build — the room doesn't need to be complex to be interesting.
- Keep rooms **quick and efficient**. Fast-paced room turnover (Binding of Isaac) means a boring room barely registers — the player is already in the next one.
- Reward clearing rooms consistently (even small rewards) — this pacing loop keeps engagement high.
- Occasional larger, harder rooms break the rhythm and create memorable challenge moments.

**Design gut-check**: Does the level design fight the gameplay or support it? Is pacing fast enough that a weak room doesn't kill momentum?

---

## 6. Enemy Design

Enemies are not just obstacles — they are **playgrounds for the player's build**.

### Core principle: punching bags are load-bearing
- Players will frequently have builds they've never seen before. Simple, easy enemies let them *feel out* the build and feel powerful doing it.
- Even on final floors, include enemies from early floors as cannon fodder. Clearing a room effortlessly is satisfying — it validates the build.
- If every enemy is a challenge, there is no room to enjoy the build.

### Simplicity scales better than complexity in this genre
- Enter the Gungeon: most enemies have one move. Individual enemies are trivial; combinations create the bullet hell experience.
- The player should be able to *learn* patterns even if mastering avoidance takes time.
- When a player gets hit by a predictable enemy, the fault should feel like theirs — not the game's.

### Variety matters
- Players encounter the same enemies across many runs. Variety prevents fatigue.
- Enemy design is game-specific, but the punching-bag / challenge / boss layering is a consistent pattern worth preserving.

---

## 7. Secrets and Unique Encounters

Special rooms, secret rooms, shops, and events keep runs feeling fresh beyond the core combat loop.

- **Shops**: staple. Always offer different options. Give the player agency.
- **Special rooms** (chests, events, shrines): provide choices with known stakes — different from random drops. Use them to help players course-correct a bad run.
- **Secret rooms**: reward attentive players without requiring sacrifice. Provide consistency in a genre of variance.
- **Risk-gated specials** (e.g., spend full HP for a 66% chance at an item): these merge risk/reward with special encounter design — use sparingly but effectively.

**Design gut-check**: Does every floor have at least one moment that isn't just combat? Does the player have agency in how they engage with it?

---

## 8. Mechanic vs. Stat Changes

Two types of upgrades exist. The best roguelikes balance both and lean toward mechanical.

### Number Adjustments (Stat Changes)
+damage, +defense, +speed, +cooldown reduction.
- Easier to design and balance.
- Essential for minor synergies and fine-tuning.
- **Warning**: A run full of only number adjustments feels stagnant quickly. The build doesn't *change*, it only grows.

### Mechanical Adjustments (Rule Changes)
Bullets bounce off walls. Attacks apply poison. On-kill: spawn a companion. Reload triggers an explosion.
- Change *how the player plays*, not just *how well*.
- Combine with number adjustments for compound synergies (fire-rate buff + fire-bullet-chance = more fire procs).
- These are the upgrades players remember and talk about.

### Anti-pattern to avoid
A game where mechanical identity is locked at run start (ability selection) and everything after is pure number adjustments. The run stops evolving; the player goes in circles collecting stat boosts. Excitement peaks at ability selection and slowly decays.

**Target state**: Player starts a fresh run, and by mid-run is playing *differently* than any previous run — because of mechanical adjustments encountered along the way.

---

## 9. Charm, Visuals, and VFX

Artistic execution carries more weight than it gets credit for — especially in a genre with repetition baked in.

### Art direction
- Indie games cannot match AAA production scale. The correct response is to be *distinct*, not to compete on fidelity.
- Pixel art, flat art, cardboard cutouts — all valid when they fit the game's identity.
- Charm (personality, world investment, character likability) can override gameplay criticism. Players who care about the world will tolerate more.

### VFX is the hidden multiplier
- VFX transforms static art into *feeling*. Poor VFX is the most common invisible reason a game "doesn't feel good" but players can't explain why.
- Techniques are often very simple: one-frame sprite flash on hit, brief screen-border flash on damage taken, a few shapes on impact.
- The effect does not need to be complex — it needs to arrive at the *right moment* and be *brief enough* to not clutter the screen.
- A single weapon that feels satisfying to hit with can carry an entire game's feel.

**Design gut-check**: Does every player action have feedback? Does taking damage feel distinct from dealing damage? Is the screen readable under chaos?

---

## 10. Audio

No unique principles separate from general game design, but the stakes are high in this genre:

- Sound design makes actions feel impactful. In a run-based game with thousands of hits, each hit's sound is heard *a lot* — make it feel good.
- Boss music elevates tension in the moments that matter most.
- Soundtrack quality directly affects "want to start another run" feel. A great soundtrack is a retention mechanic.
