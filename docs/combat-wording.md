# Combat wording

This is the authoring convention for power cards, build details, the glossary, tutorials and combat UI. Use the same terms for the same mechanics. Describe the implemented behavior; proposed interactions belong in design documents until they exist.

## Terms

| Term | Meaning | Wording to use |
|---|---|---|
| Attack | The deliberate action performed with the Attack control, left mouse by default. It can miss. | "When you Attack..." or "Every third attack..." |
| Attack hit | An attack connects with a foe. State whether multiple foes count separately. | "On attack hit..."; "Every three connected attacks..." when counted once per attack. |
| Dealing damage | Enemy damage from any eligible source, including attacks, dash effects, projectiles, fields and echoes. | "When you deal damage..." |
| Electric damage | A damage property, independent of the control or effect that produced it. Lightning is its plain-language visual description. | "Deals Electric damage"; "When you deal Electric damage..." for an implemented Electric-specific receiver. |
| Dash | The normal dash action. A power states whether it activates during movement, on contact or at completion. | "Dashing through a foe..." or "After your dash ends..." |
| Slow / Slowed | Reduced enemy movement / a foe currently affected by Slow. | "Applies Slow"; "against an already Slowed foe" when checked before damage. |
| Mark / Marked | Timed shared vulnerability / a foe with an active Mark. Strongest base Mark wins; all players benefit; damage does not consume it. | "Applies Mark"; "against an already Marked foe" for a pre-damage condition. |
| Field / Burst | Persistent area / instant area effect. | Describe the actual shape, cadence and expiry; an expanding visual alone is not a Field. |
| Projectile | An effect that travels through the arena. | State travel, collision and per-leg limits. |
| Push / Pull | Displacement away from / toward a source. | Name its direction; only an explicit converter makes it a Launch. |
| Launch / Impact | Armed displacement / its collision with a foe or geometry. | One Impact Burst per Launch; immovable foes compress in place. |
| Recoil / Orbit | Blast-driven movement / movement around an anchor. Neither is a normal Dash. | Name each accepted movement explicitly. |
| Echo | A copied shape and scaled damage, without another Attack. | Describe preserved properties and original-action limits; no resource or recursive Echo replay. |

Capitalize named controls and properties when naming them. Ordinary verbs can remain lowercase: "Dashing leaves..." and "the attack connects...". Reserve Damage for the player's base Damage stat; use lowercase damage for the amount dealt. Both Damage and "dealing damage" remain plain text, not highlighted keywords or glossary keyword entries. A percentage of Damage and a percentage of an attack's resolved damage are different quantities.

Do not use capitalized **Hit** as an umbrella term for all damage, or bare "on hit" when it leaves the source unclear. Normal language such as "a launched enemy hits a wall" is still appropriate. Damage from a dash trail does not perform an Attack. An Echo can deal damage without performing another Attack or replaying every attack effect.

## Describe a rule

Lead with its trigger and result, then include the important limit. A generator says what it produces; a receiver says what property or event it accepts. This makes combinations discoverable without memorizing named pairs.

- **Static Wake:** "Dashing leaves a Field of Electric damage in your trail."
- **Storm Crown:** "Dealing damage charges chain lightning." It currently accepts any damage type; its description must not suggest Electric-only input. Its glossary entry explains one count per foe per original action and one discharge per action.
- **Hunter's Snare:** "Your attacks Slow foes. Already Slowed foes take more damage." Level 1 amplifies Attack damage; level 2 amplifies all qualifying damage. Check Slow before that damage applies any new status.
- **Pillar Convergence:** "Attack hits or Electric damage charge a pulsing Field that follows you." The two inputs share one charge per original action, and the active Field cannot charge. Actions that qualify while it is active cannot charge later through delayed damage. Electric generators qualify by property; do not advertise a required named pair or shared charge resource.
- **Sovereign Tempo:** "Attack hits or damage to already Marked foes build Tempo once per action." The Mark condition uses the target's status before damage. The movement-completion Burst and its descendants cannot build Tempo; the general damage trigger does not perform another Attack.

Distinguish using an attack from connecting it: Execution Edge counts attacks, even misses; Riftpunch and Sigil Chain accept deliberate melee, Razor Wind and charged Blast connections. Their automatic descendants are not new attack hits. Farline Volley's level-3 dash Burst deals damage without replaying attack-hit effects.

Specify who owns a trigger (you or a teammate), when a condition is checked, and what is counted: attack, damaged foe, tick, kill or effect activation. A newly applied Slow is not automatically an already-present Slow. A repeated tick does not automatically earn a new reaction allowance. Keep the prominent restriction on the card and the full counting rule in that power's glossary entry; never invent a universal limit to simplify the wording.

Explain what a reward does. When the trigger is already precise, omit unrelated exclusions: "Dash through foes to damage and Slow them, once per foe per Dash" does not need to list Recoil and Orbit. Prefer "already Slowed" to repeating that the same hit's new Slow cannot amplify itself. Keep restrictions that materially change the offered payoff, such as shared damage from overlapping trails, one reaction per original action, or a kill effect that cannot trigger itself. Do not remove a limit merely because it contains a negative word.

Describe scaling separately from activation. An effect based on attack damage does not necessarily require another attack to activate. Verify the actual calculation before calling a value a percentage of Damage or of attack damage. Echo copies retain only their implemented geometry, properties and bonuses; they do not imply copied status applications, resource generation or recursive effects.

## Authoring and verification

Use `scripts/shared/reward_card_copy.gd` for level-aware card/build explanations, `scripts/upgrade_system.gd` for their actual numerical comparisons, and `scripts/shared/glossary_data.gd` for detailed rules. `scripts/shared/combat_keyword_catalogue.gd` owns canonical definitions and bold+color styling. Author a semantic span explicitly, for example `{kw:attack}` or `{kw:slow|Slowed}`, and pass the sentence through `format_text()`. Never highlight by broad string replacement: a power name, flavor word or internal HIT identifier is not evidence of a mechanic. Reward/build descriptions already return formatted BBCode; preserve it when displaying them. Check alternative upgrade-preview paths and summaries when changing a shared sentence. The current roster is in [combat-power-roster.md](combat-power-roster.md); [shared-build-engines.md](shared-build-engines.md) retains the earlier electrical checkpoint for history.

Internal `HIT`, `hit_damage` and related serialized identifiers retain their existing meanings. They are implementation vocabulary, not player-facing wording. Do not rename them or broaden an old power's trigger as part of a copy edit.

Character passives use `scripts/shared/character_passive_catalogue.gd` for their short selection copy, concise Build Details summaries, full glossary rules and compatibility metadata. Build Details shows one readable paragraph; keep detailed timing and source exceptions in the glossary. Keep their damage basis separate from activation: Sigil Burst needs an accepted attack hit after Dash, while Veilstep Rhythm needs no Attack. Farline Focus accepts melee and charged Blast contacts, not every source with the attack-hit property. Passive Bursts deal damage without creating new attack hits, Electric damage, Fields or Pushes. Render explicit semantic spans through the same keyword catalogue as rewards.

For changed descriptions, run the existing isolated power-description and reward-layout checks, including levels and Prismatic. An Arcana or boss card has a plain-language explanation followed by a separate numerical line: up to 260 visible characters combined, with a 175-character explanation ceiling and a 109-character numerical ceiling. These are ceilings, not targets; the combined budget still applies. Do not compress the mechanic into unexplained shorthand to satisfy a count. Ordinary Boons keep a single clear stat line. Wording checks verify presentation; mechanic or interaction changes also need their relevant gameplay tests and playtesting.

Reward cards explain the offered level's trigger, result and important limit; a first pick must not advertise a later upgrade as already active. Keep numerical current-to-next comparisons separate from that explanation. Retain diamond level indicators and the Prismatic label, with a separate title row so icons do not steal paragraph width. Keywords use the restrained palette below with bold text at the surrounding body's size. These accents are presentation choices, not new gameplay tags. Body text and ordinary stats stay neutral, and only changed next values receive the muted improvement accent. Damage remains plain text. Keep the visible build shortcut as Tab. Full rules belong in inspection, with brief definitions in the glossary. Render every native unowned card as well as all upgrades, three/four offers, and 960/1280/1920 widths. Four choices use a two-by-two grid; body text must remain at least 18 rendered pixels and fit completely. Validate title/icon separation, line wrapping and spatial input as well as character counts.

| Authored terms | Presentation |
|---|---|
| Attack, attack hit, Kill, Projectile, Echo | Warm neutral emphasis |
| Dash, Recoil, Orbit, Slow, Push, Pull, Launch | Muted blue |
| Mark | Muted mauve |
| Electric | Muted gold |
| Field | Muted sage |
| Burst, Impact | Muted peach |

Common combinations such as Electric damage in a Field, a Slowing Burst, or an Attack followed by Recoil should remain easy to scan. Do not introduce a separate bright color for every word, icons beside every occurrence, or a new player-facing legend. The explicitly authored words carry the meaning; color is an additional cue. Selection, reward cards, Build Details and glossary definitions use the same catalogue.

## Roles and conditional values

Boons increase generic capability. Missions grant a permanent Boon and a temporary increase; Arcana establish the build, while boss rewards extend or convert it. The expanded roster has fourteen Boons, six Mission bonuses, twenty-three Arcana and ten boss rewards under the existing equal-random offer rules.

First Strike (+16), Blood Pact (+9) and Severing Edge (+14) add to a qualifying Damage basis per pick, not a full flat amount on every small tick. The effective Damage coefficient includes contact time and copied-effect strength. Child effects carry an unconditioned descriptor and evaluate their actual target once. Battle Trance refreshes on accepted owned damage. Overcharge reduces Attack and Dash cooldowns to 80% for three room clears; it does not change Blast recharge, hold thresholds or create a nova.

Patient Hunter and Marked Prey add +12 to the qualifying Damage basis per pick against already Slowed or already Marked foes. Stormbrand applies Mark after accepted Electric damage, checking its level-3 Slow condition before that damage. Spark Relay and Shatterwake copy a fraction of the triggering source's base damage and Damage coefficient, before conditional bonuses; each actual descendant target resolves its own conditions. Their separate once-per-original-action allowances survive through projectiles, return legs, ticks and Echoes. Describe the accepted property and individual limit, rather than advertising a required named pair.

Display names are Aegis Pulse, Fracture and Lacuna Well. Their stable save/network IDs remain `aegis_field`, `fracture_field` and `lacuna_echo`.
