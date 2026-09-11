# Character identity and synergy audit — September 11, 2026

## Scope and conclusion

This is a read-only audit of the current local game and a set of **design proposals, not implemented or approved mechanics**. The only file authored by this audit is this document. No gameplay tests, edits to game code, board actions, or branch operations were performed. Numerical values in proposals are prototype starting points, not balance recommendations established by playtesting. External-game research belongs to the accompanying design investigation; this document makes no claims about other games.

The existing four characters already cover holding position, Dash-to-Attack conversion, contact-Dash chaining, and precise attack range. A fifth should introduce a different decision that works against a lone boss, before the player obtains a particular Arcana or boss reward. More thread imagery, another Mark source, or another unconditional Dash-to-Burst conversion does not by itself supply that decision.

Three promising spaces are **approach angle and enemy displacement**, **collecting and spending a spatial combat resource**, and **timed counterplay against enemy actions**. Proposals below explore each without assuming that Threadbinder's name or theme survives.

## Sources checked

- [Character definitions](../scripts/character_registry.gd), [passive catalogue](../scripts/shared/character_passive_catalogue.gd), and the actual passive handlers in [player.gd](../scripts/player.gd).
- [Power registry](../scripts/power_registry.gd), [level-aware reward explanations](../scripts/shared/reward_card_copy.gd), and [combat roster](combat-power-roster.md).
- [Accepted damage boundary](../scripts/shared/damageable.gd), [conditional damage calculation](../scripts/shared/shared_damage_modifiers.gd), [interaction classification](../scripts/shared/combat_interaction_registry.gd), and [shared reaction runtime](../scripts/shared_build_runtime.gd).
- [Combat wording rules](combat-wording.md) and the [implemented Threadbinder specification](threadbinder-character.md).

## What each existing character actually asks the player to do

| Character | Repeated decision | Actual reward and constraint | Meaningful build relationships |
| --- | --- | --- | --- |
| Bastion | Find a safe place to pause between attacks; decide whether preserving Brace is worth delaying movement. | Slow/stationary movement for 0.42s earns Brace for 2.4s. Melee/charged Attacks gain 80% damage; first accepted contact spends Brace for a Burst and 1.5s Guard. Dash/Recoil/Orbit break it; Dash delays rebuilding by 0.8s. | Execution Edge and charged Blast can concentrate an empowered strike. Defensive Slow helps create a pause. Repeated Dash and Orbit conflict with the stance. Razor Wind can spend Brace without receiving the main empowered-strike bonus. |
| Hexweaver | Repeatedly alternate a normal Dash with an accepted attack contact, and choose where the Burst lands. | Dash arms one 70%-of-strike-basis Burst. Another Dash cannot bank a second. Melee, Razor Wind and charged Blast can spend it; misses/automatic damage cannot. | Riftpunch and Wraithstep reinforce the same deliberate rhythm. Sigil Chain adds actual detonation choices; it is a specific implemented connection, not a general Field detonator. A purely automatic-damage build leaves the armed Burst unspent. |
| Veilstrider | Route normal Dashes through enemies, then choose a good landing point for the payoff Dash. | One shard per contact Dash; two refresh Dash and open a four-second window. The next Dash ends in a 160%-Damage Burst and clears the shards. Attack is optional. | Phantom Step, Static Wake, Wraithstep, Blink Dash and kill refreshes reinforce the movement route. Recoil and Orbit do not grant shards. Farline Volley loses stacks on those frequent normal Dashes. |
| Riftlancer | Keep each victim at the edge of reach and inside a narrow aim lane; decide when to abandon that position. | Melee/charged Blast deals ×1.70 within both conditions, ×0.70 outside. The target body's overlap with the outer range band counts; its center must still lie in the aim lane. | Long Reach/Wide Arc change the actual geometry; Farline Volley rewards retaining it. Blast recoil can maintain spacing but can also overshoot. Razor Wind and automatic descendants do not independently earn a fresh Farline bonus. |
| Threadbinder, current | Hit one enemy, preserve it, then hit another while the first remains alive and nearby. | First accepted contact per Attack applies 12% Mark and a four-second thread. A later Attack on another foe produces a radius-48 Burst at the old foe, within 240 range. Same-target attacks refresh without bursting. | Mark prepares Wraithstep L2 and damage-to-Marked Tempo paths. Spread damage can feed Crown under existing action/victim limits. Stronger Wraithstep/Eclipse Marks replace the 12% base Mark contribution. Dread stacks actually survive switching, so Dread is not an automatic anti-synergy. |

Threadbinder's weakness is structural, not just numerical: a lone boss removes its distinguishing Burst loop, and killing the first enemy removes the intended next payoff. Faster clearing can therefore erase the passive's expression. Increasing its Mark or Burst magnitude would not repair those missing decisions. A wider arc also does not deliberately select the thread target: the first accepted contact still decides. These are inferences from the implemented conditions, not a claim that every player's build has the same experience.

## Shared combat contracts that proposals must respect

1. **Attack and damage are different events.** Only the registered `melee`, `razor_wind`, and `blast_drive` sources supply attack hits. Returning Crescent, Orbit damage, Fields, Echoes, and passive Bursts can deal damage without becoming new attack hits. Keep internal `HIT` compatibility; it is not player-facing permission to rename all damage an Attack.
2. **Each receiver keeps its own allowance.** Crown counts each foe once per original action and discharges at most once for that action. Pillar Convergence uses one charge per original action and cannot bank actions accepted during its active Field. Tempo uses one stack per action; its Burst and descendants cannot rebuild it. A bonus effect touching the same victim does not necessarily add another resource point.
3. **Carry raw damage and its Damage coefficient.** Conditional Boons resolve against the actual victim once. A 0.6-strength copy should carry 0.6 of the source coefficient. A proposal must not multiply already-conditioned damage or award a full +16 First Strike to every tiny tick.
4. **Check conditions before damage.** Applying Slow or Mark in an accepted-contact reaction does not retroactively make that initial hit qualify as damage against an already affected foe. Later descendants may encounter changed status at their own actual damage boundary.
5. **Mark is shared vulnerability, not ammunition.** Strongest base Mark wins, damage does not consume it, and Dread stacks belong to the owner/victim. A new character cannot silently consume another player's Mark to operate.
6. **Ownership is explicit.** A player's resource, target selection, projectile, or counter charge belongs to that player. Descendants retain provenance; no teammate hit, duplicate packet, overlapping shape, or multi-target contact creates extra allowances. Clear temporary state on death, room exit, removal, character change and checkpoint restore as appropriate.
7. **The controls are already occupied.** Attack taps attack immediately; Blast Drive also uses holding and releasing Attack. Normal Dash can continue into Razor Orbit when held. A proposal must not require a new button or secretly reserve either hold gesture. Ordinary Dash currently grants contact protection, not blanket immunity to enemy abilities (`player.take_damage` checks `enemy_contact`).

## Audit of all 21 Arcana

The table distinguishes the actual producer/receiver from the player decision it can enrich. It does not promise that every item should be equally strong on a new character.

| Arcana | Actual event/effect | Design opportunity or trap |
| --- | --- | --- |
| Razor Wind | Adds a distant attack-hit arc to Attack; does not hit nearby foes twice. | More target access; can make first-contact target selection less predictable. A broad arc is not deliberate target switching or several original actions. |
| Execution Edge | Empowers periodic Attacks; misses advance the cycle. | Lets a player prepare a deliberate finisher. Do not charge a new passive merely from those preparatory misses unless its stated trigger is Attack use. |
| Rupture Wave | Attack-hit Burst; later Slow and bounded chaining; each victim takes its Rupture damage once per Attack. | Rewards grouping and a carefully chosen primary target. Crowd size does not remove the victim/action cap. |
| Aegis Pulse | Automatic Slow and brief resistance; no damage or persistent Field. | Provides room to reposition or time an action. Cannot generate resources whose trigger is dealing damage, and cannot activate Lacuna Well's Field bonus by itself. |
| Hunter's Snare | Attack-hit Slow; already-Slowed bonus affects Attack at L1, all qualifying damage at L2+. | Creates setup/payoff for secondary damage after L2 and makes positional play easier. L1 is not a universal companion/projectile/field multiplier. |
| Phantom Step | Normal Dash contact deals damage and Slow once per foe per Dash. | Supports crossing a target or collecting something beyond it. Recoil and Orbit are not substitutes for its trigger. |
| Riftpunch | Dash completion primes the next deliberate attack hit, with later Slow/Burst. | Strong for a flank or collection route that returns to an Attack. Merely copying this rhythm produces a second Hexweaver. |
| Reaper Step | Kills refresh Dash; later chain rewards and greater Dash reach/speed. | Extends routing through crowds. Boss independence must come from the character because a lone boss supplies no repeat kill refresh. |
| Static Wake | Normal Dash creates up to two Electric Fields; shared contact clock for overlaps. | Makes a travelled route matter after leaving it. Good for steering enemies through past movement; not a source of a new action per tick. |
| Storm Crown | Owned damage charges Electric chains with its original-action/foe limits. | Broad bridge for any new damage source. More packets on one victim from the same root do not guarantee more charge. |
| Wraithstep | Dash applies shared Mark; L2+ attack hit against already Marked foe releases its bounded Burst. | Makes crossing a target useful before the next Attack; its Mark can also prepare passive damage for Tempo. A stronger Mark does not stack with Threadbinder's 12%. |
| Voidfire | Connected Attacks build Heat; high Heat strengthens Attacks; overheat Bursts and briefly locks Attack. | Rewards sustained pressure but competes with deliberate waiting, long travel, and counter timing. A new passive cannot continue using Attack through its lockout. |
| Dread Resonance | Attack-hit Mark and persistent owner/victim stacks, evaluated while Mark is present. | Supports repeated boss engagement, including circling and temporarily switching targets. A new payoff should not reset Dread stacks. |
| Blood Vow | Attack multiplier at or below 40% HP. | Can reward confident execution; does not make fixed-Damage secondary effects stronger merely because they came from this character. Distinct threshold from Blood Pact's 50%. |
| Eclipse Mark | Kills apply shared Mark nearby. | Feeds a crowd damage engine and Tempo. Supplies no repeated setup in a boss fight without adds; cannot be required for baseline identity. |
| Fracture | Kills release damaging, Slowing fault-line Bursts; its own descendants cannot repeat it. | Rewards steering the location of a kill. No universal kill-explosion recursion or boss-only sustain. |
| Farline Volley | Outer-range contacts build damage/arc stacks; Dash clears them, with a full-stack payoff only at its later level. | Explicit tension with frequent crossing/collection Dashes. A new character should preserve this tradeoff instead of silently retaining stacks. |
| Sigil Chain | Deliberate contacts charge and then place persistent Fields. | Enemy arrangement and revisiting space can improve uptime. Automatic damage does not place/charge more sigils; Hexweaver owns the specific detonation exception. |
| Blast Drive | Attack hold/release gives charged damage and Recoil; tap Attack remains available. | Strong aimed payoff and reposition tool. A new passive must define whether the initial tap, charged release, or accepted contact matters, without assigning another hold action. |
| Razor Orbit | Continue holding Dash to Orbit; manual Attacks remain available; Orbit cuts deal damage. | Can solve angular movement or sweep a collection route while retaining manual attacks. Orbit is neither an additional normal Dash nor repeated attack hits. |
| Returning Crescent | Attack throws a returning Projectile, with one hit per foe per leg. | Player movement changes the return line. Good with spatial routing and damage-driven resources; the blade's contacts cannot charge an attack-hit-only passive. |

## Audit of all nine boss rewards

Only the first two boss clears grant these picks in a normal three-boss run. None is a dependable prerequisite for a starting character's loop.

| Boss reward | Actual role | Implication for a new identity |
| --- | --- | --- |
| Warden's Verdict | Consecutive attack contacts advance a four-contact damage sequence; resets after 2.2s without an attack hit. | A meaningful tradeoff for long waits or detours. New passive projectiles/counters must not masquerade as more contact counts. |
| Lacuna Well | Kills create a replacing Pull/damage Field; damage bonus applies once inside any owned Field. | Enemy placement and routes gain value, including via existing Sigil/Wake/Convergence Fields. The killed-enemy well is not guaranteed in a solo boss encounter. |
| Sovereign Tempo | Attack hits or owned damage against already Marked foes build one stack per action; movement completion spends it. | Supports several source types. A new source does not need innate Mark to work with it; existing Marks can supply the setup. Its payoff cannot refill itself. |
| Pillar Convergence | Attack hits or owned Electric damage charge a moving Field; one per action, no charging while active. | Every proposal retains ordinary Attack compatibility. Only genuinely Electric new damage would add the second route; do not tag it Electric just to advertise a pair. |
| Unbroken Oath | Resistance plus Attack-built Oath for an empowered next Attack; misses spend the empowered Attack. | Helps committed offensive actions. Passive damage is not another Oath-building Attack and should not erase the missed-finisher cost. |
| Edict of the Court | Kill-triggered Push with no damage by itself. | Enemy grouping and kill position matter. It may scatter a carefully arranged group; Push is not automatically a damage event. |
| Null Corridor | Normal Dash leaves a damaging Field that Pushes sideways, with its existing half-second victim cadence. | Routes can move enemies into or out of a planned payoff. Extra movement modes must not fabricate normal Dash trails. |
| Ruinous Impact | Attack hits and eligible Push/Pull arm Launch; one Impact Burst; immovable targets compress. | Best existing extension for deliberate displacement. A direct hit plus its child Push is not permission to ignore the Launch's repeat limit. |
| Sovereign's Double | Movement completion leaves one shade for one/two reduced-damage Echoes of manual attack shapes. | Rewards planning the next attack's origin. It does not copy new character resources, parry windows, pickups or additional passive activations unless explicitly implemented. |

## Boon and Mission economics

The twelve shared Boons are capped at three picks, except Heartstone at two. Selection is not a reliable way to repair a character that lacks a starting mechanic. The registry retains the same shared pools across characters. The declared maximum-pick constants are pool-capacity safeguards, not a guarantee that every run will receive that many picks.

| Boon | Per pick | Consequence for character design |
| --- | --- | --- |
| Heavy Blow | +7 Damage | A reliable baseline improvement for every correctly coefficient-scaled new damage source. At the current Threadbinder's 24 Damage, one pick is about +29% of its unconditioned Damage basis. |
| First Strike | +16 conditional basis when victim is at least 80% HP | Rewards opening on fresh enemies. A stronger opener should not systematically kill the target required to express the character's next step. |
| Severing Edge | +14 conditional basis when victim is below 55% HP | Supports committed finishing and boss damage. Must use the secondary effect's actual victim health. |
| Blood Pact | +9 conditional basis while owner is at most 50% HP | A risk option, not an unlimited resource source. Do not add repeated full +9 bonuses to tiny new ticks. |
| Wide Arc | +28 degrees, capped at 280 degrees | Changes manual attack coverage. It does not automatically widen a separate projectile, parry window, or secondary cone. |
| Long Reach | +11 Attack range | Changes access and positional geometry. Whether a new secondary effect scales with it must be explicit. |
| Fleet Foot | +17 movement speed | Improves walking routes without spending Dash or dropping Volley stacks. |
| Blink Dash | Dash cooldown ×0.80, minimum 0.14s | Three picks multiply the original cooldown by 0.512 before the floor. Helps routing without granting extra passive actions from one Dash. |
| Surge Step | +85 Dash speed | Changes how quickly a route is crossed. A speed improvement is not an unconditional range increase. |
| Battle Trance | Dealing damage refreshes +22% movement speed per pick for 1.25s | New owned damage sources should refresh it at the existing accepted-damage boundary. It can bridge offence and movement without requiring attack hits. |
| Iron Skin | +4 armor | Safety for positional or reactive mistakes. Damage still has its existing minimum; it is not a reliable zero-damage trigger. |
| Heartstone | +10 maximum/current HP | A survival pick; it does not change the proposed resource caps or guard timing. |

Missions grant a permanent chosen Boon plus a fixed temporary effect lasting three encounter clears: Fortified resistance, Hunter's Focus damage, Combo Relay kill-driven damage/speed, Relay Boost kill speed, Overcharge Attack/Dash cooldown reduction, or Node Shield nearby-enemy resistance. Overcharge does not speed Blast recharge/hold thresholds. None should be required to reach an essential passive timing window; kill-driven Mission effects remain weaker against a lone boss.

## Proposal A — Flank breaker: cross a foe, then drive through it

**Player sentence:** “Strike a foe, get around it, then strike through it to drive a cutting wave into the enemies behind.”

This combines an underserved decision—attack from a new side—with deliberate enemy displacement. It differs from Riftlancer's distance band: closing distance and crossing the target can be correct. It differs from Veilstrider: Dash contact itself provides no resource, and walking or Orbit can solve the positioning.

**Concrete prototype loop:** the first accepted manual attack contact stores one living foe and the world-space approach direction relative to its center for four seconds. A later Attack on that foe from more than roughly 105 degrees around the stored direction releases one short damaging cone through and behind it, with an eligible Push. Same-side attacks refresh the window without rotating the stored opening; selecting another foe replaces it. On success, the new approach becomes the next opening. The secondary cone includes the primary foe, so immovable bosses still take the payoff without a special kill/add requirement. Use a clear notch or opening marker on that single foe; do not call it Mark.

The cone could initially carry 75% of the qualifying strike's **unconditioned** damage basis and coefficient. That is an exploratory scale. It deals damage and Push; it is not an Attack, Electric damage, a persistent Field, or an innate Launch. Normal Dash remains repositioning. Enemy facing animations do not move the goalposts: the stored geometric approach, not a boss instantly turning to face the player, defines the opening.

**Good paths:** Phantom Step/Wraithstep reward a normal crossing Dash before the flank hit; Riftpunch rewards the subsequent contact. Razor Orbit permits circling plus manual attacks. Slow sources help hold a target in useful space. A carefully aimed wave can drive foes through Wake/Sigil/Corridor Fields, or into other victims for Rupture/Fracture. Ruinous Impact converts eligible displacement into its existing bounded payoff. Charged Blast/Execution Edge can enlarge the source basis of a successful flank payoff.

**Weak paths and costs:** frequent Dash discards Farline Volley stacks; prolonged circling can lose Verdict's 2.2s cadence or a short Riftpunch window. Blast Recoil may move the player away from the intended crossing. Pushing in the wrong direction can eject enemies from owned Fields or break a dense group. First-contact target selection needs a readable priority rule, particularly with Razor Wind/Wide Arc; incidental victims should not make the marker feel arbitrary. Fast kills still remove the current foe before a flank payoff: this proposal fixes the lone-boss problem but retains that part of Threadbinder's weakness. Its usefulness against durable enemies must justify the setup, and the prototype should be rejected if ordinary crowd fights seldom expose the loop.

**Boss viability:** the same living boss supplies both contacts; the secondary damage always includes it. Crossing must still respect real boss ability geometry—ordinary Dash does not ignore all abilities. Mobile bosses can make the route harder; this is the intended skill test, subject to prototype testing.

**Ownership/limits:** one opening per player, first accepted direct contact per original Attack, one payoff per original Attack, one secondary hit/Push per victim. Automatic damage and Echoes do not rotate the opening or create another payoff. Carry the original action through the cone, including reaction ancestry. The primary hit and cone must share existing Crown/Launch/Tempo allowances. No shared Mark is consumed.

## Proposal B — Shard scavenger: create a prize, choose a route, spend the shot

**Player sentence:** “Your damage knocks loose a shard; collect it and fire it through the next pack.”

The missing decision is whether to divert from the safest/current damage position to collect a visible resource. It gives movement a destination other than the enemy or a Dash landing point. It also supports damage-driven builds without declaring their automatic effects to be attack hits.

**Concrete prototype loop:** every three distinct original actions that deal accepted owned damage release one shard from the actual damaged foe, including a lethal hit. It travels a short, predictable distance beyond that foe and rests on reachable floor for six seconds. One shard may exist or be carried per owner; no stockpile. Walking or normal Dash collects it without a new control. The next deliberate Attack spends a carried shard to fire one piercing bolt along the player's aim while performing the ordinary Attack. The bolt can start around 120% Damage and hit each foe once. It is a Projectile, with no innate Electric/Mark/attack-hit property. Damage and geometry values are proposals.

One held-shot cue and one floor token should be sufficient visual state. Attack hold remains Blast Drive's gesture: capture whether a shard is held on the initial Attack action, spend it once, and do not spend again merely because the held Attack produces a charged release. A miss can waste the shot. Drop placement needs bounded, deterministic floor/obstacle handling, especially at arena edges; do not create unreachable mandatory pickups.

**Good paths:** Returning Crescent can generate one charge per original action and its returning line benefits from the collection route. Wake/Orbit damage can contribute once per originating action; fresh Dashes or attacks matter, repeated ticks from the same Field do not. Trance, Fleet Foot, Blink Dash and Reaper Step help collection. Phantom Step/Wraithstep add a reward when the route crosses a foe. A collected piercing shot can feed Crown against new victims, Snare L2 against already Slowed targets, and Tempo against already Marked targets. Heavy Blow and conditional Boons scale the bolt by its declared coefficient.

**Weak paths and costs:** detouring costs attack uptime and may lose Verdict's timer or require a Dash that clears Volley. Aegis Pulse alone produces no damage charge. A damage-only Dash/Field build can create and collect a shard but must still perform an occasional aimed Attack to spend it. The bolt does not build Sigil, Heat, Oath or Verdict, and is not an extra Electric input for Convergence. Fixed-Damage bolt output does not inherit every multiplier on the concurrent manual swing; for example, Blood Vow should not amplify it unless explicitly authored as a copied attack basis. Leaving a shard behind must be a tolerable choice, not an effective character shutdown.

**Boss viability:** no kills or extra enemies are required; three distinct accepted actions against the same boss create the resource. A lethal hit can still create a shard for the next enemy, avoiding Threadbinder's “stronger opener erases the loop” failure. Fixed drop travel should put the token near enough to remain a real boss-fight choice without guaranteeing a safe path.

**Ownership/limits:** owner-only pickup; three counts mean three original actions, not three ticks/victims. Claim qualifying roots even while a shard exists so old lingering damage cannot be banked after collection. The shard bolt and its descendants cannot generate shard charge; a spending action must have an explicit generation policy rather than accidentally funding its own replacement. One pickup claim, one shot per manual action, one bolt hit per victim. Echo does not duplicate the inventory or shot. Clear or deliberately discard tokens at room/owner lifecycle boundaries.

## Proposal C — Counter duelist: time Attack against danger, then answer

**Player sentence:** “Time your Attack as the enemy strikes to catch the blow, then land your counter.”

This is reactive timing, distinct from Bastion earning power by standing still. It can be expressed with normal Attack/Dash controls, but it is the largest implementation change of these options because the game does not yet have a universal parry contract.

**Concrete prototype loop:** a fresh press of Attack opens a short guard window, initially about 0.16s, at most once per one-second guard recovery. Normal attacks remain available during that recovery; holding or automatic attack repeats cannot reopen guard. One eligible discrete incoming enemy strike caught in the window is prevented and arms one counter for four seconds. The next accepted manual attack contact releases a damaging Burst at its victim, initially around 100% Damage, then spends the counter. Another guard cannot bank a second. Normal Dash stays a separate movement response and does not grant a counter automatically.

The guard must have a clear ready cue and success cue. Attack's normal tap and Blast hold/release semantics stay intact: no second guard on charged release. “Eligible strike” must be a consistent, visible category that covers actual boss attacks; silently excluding every alternative boss's ground ability would make this candidate fail its boss requirement. Persistent hazard ticks and body contact must not become repeat counter generators. Do not infer a hostile action's identity or direction from a display name.

**Good paths:** Execution Edge lets the player prepare the answer. Riftpunch can enhance a counter contact after a needed Dash, though its short window remains a constraint. Aegis/armor/health can soften failed attempts; Snare creates space to read upcoming attacks. Dread permits focusing the same boss between guards. Counter damage can feed Crown, and prepared Marks can qualify it for Tempo. The next manual attack still participates normally in Oath/Verdict/Convergence.

**Weak paths and costs:** waiting for a guardable strike may lose Verdict/Heat uptime; overheat can lock Attack exactly when guard is needed. Dash-contact builds are less interested in waiting to counter. Blast hold timing can conflict with a fresh Attack press needed for guard. A fully successful guard does not count as taking damage, so it must not trigger damage-taken effects or manufacture low-health bonuses. Crowd/body contact or persistent floor damage must not become a safe stationary counter farm.

**Boss viability:** strong in principle because a lone boss repeatedly supplies readable attacks. Unproven until all six bosses have an explicit incoming-action identity and guard eligibility. An alternative boss currently deals `enemy_ability` damage identified by ability text; the new guard needs actual validated provenance and repeat limits, not an expanding list of guessed names. If making ground strikes consistently guardable cannot be communicated fairly, reject this candidate rather than shipping an identity absent from half the boss roster.

**Ownership/limits:** guard and counter charge are per player; host-authoritative prevention occurs before health loss. One prevention/counter grant per hostile action and guard opening, one counter payoff per original Attack. The counter Burst is owned player damage but not another Attack, Electric hit or Mark application. Duplicate network events and repeated ticks cannot grant another charge; stale events after room/death/authority changes must be ignored. Existing save/profile Oath damage evidence must record actual health loss, not a prevented event.

## Comparison and next decision

| Criterion | A: flank breaker | B: shard scavenger | C: counter duelist |
| --- | --- | --- | --- |
| Distinct starting decision | Approach angle and where enemies are driven | Whether/when to retrieve a resource and where to spend it | When to attack relative to enemy damage |
| Lone-boss loop | Same foe supports both contacts | Same foe generates shards through distinct damage actions | Depends on a real guardable boss-action contract |
| Existing systems reused | Accepted attacks, original actions, damage descriptors, Push/Launch | Accepted damage ledger and projectiles; new bounded pickup lifecycle | Attack control and damage boundary; substantial new incoming-action lifecycle |
| Strongest existing build relationships | Orbit, Slow, movement setup, Fields and displacement | Returning paths, mixed damage, Trance and movement economy | Prepared strikes, enemy tells, safe recovery and Marked-damage payoffs |
| Principal design risk | Feels like another positional damage condition; aim/contact priority | Collection becomes a chore or worsens floor clutter | Guard ambiguity, passive attack-spam defence, and boss inconsistency |

For a substantially different fifth-character loop, **B** has the strongest local case: it changes moment-to-moment routing, works through the recent all-damage synergy rules, and does not require the first victim to survive. **A** is the smaller positional prototype and deserves comparison, but its fast-trash weakness remains. **C** has a clear identity but needs the most new combat contracts; it should be selected for its play experience, not treated as a cheap passive swap. Implementation convenience alone is not a reason to choose an identity.

Before choosing any theme or name, the useful comparison is a short normal-control prototype in one crowded encounter and one lone boss, with no required rewards, then one movement build and one automatic-damage build. The questions are whether a player can state their repeated decision, intentionally improve at it, and still recognize the character after random rewards. No such prototype or validation was performed by this audit.

## Relation to the companion reference research

The root investigation's [reference note](character-identity-references-20260911.md) also raises managed resources and a remote damage origin. Both are stronger open spaces than another passive “Dash, then release a Burst” conversion. A heat bar alone is not a new local identity: Voidfire already has building Heat, a stronger middle state, overheat damage and Attack lockout. A replacement character needs a new reason to decide when or where to spend its resource. Proposal B supplies a spatial acquisition cost and an aimed expenditure rather than only another threshold bar.

A deliberately positioned, persistent remote origin is also underrepresented. Sovereign's Double is the nearest existing mechanic, but it is a temporary movement-placed copying shade; Returning Crescent is a travelling object whose return follows the player. Neither offers the full decision to park a useful origin, fight from a different location, and choose when to move it. This could be a stronger character identity than Proposal A or C if the placement/relocation controls are immediately understandable.

Its unresolved local contract is consequential: are normal melee/Blast attacks still performed by the player, with separate remote damage, or are those attack shapes actually relocated? The former must not replay attack-hit-only powers through the object; the latter changes Attack range/arc, Blast Recoil, existing Echo origin rules, and potentially aiming expectations. A remote-origin character should be judged on that concrete control loop before being preferred to B. Automatically connecting damage between enemies does not establish player control over a remote origin, and relying on enemy survival would repeat the rejected target dependency. This audit does not select or specify an additional remote-origin proposal.
