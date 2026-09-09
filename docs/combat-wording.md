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

Capitalize named controls and properties when naming them. Ordinary verbs can remain lowercase: "Dashing leaves..." and "the attack connects...". Reserve **Damage** for the player's base Damage stat; use lowercase **damage** for the amount dealt. A percentage of Damage and a percentage of an attack's resolved damage are different quantities.

Do not use capitalized **Hit** as an umbrella term for all damage, or bare "on hit" when it leaves the source unclear. Normal language such as "a launched enemy hits a wall" is still appropriate. Damage from a dash trail does not perform an Attack. An Echo can deal damage without performing another Attack or replaying every attack effect.

## Describe a rule

Lead with its trigger and result, then include the important limit. A generator says what it produces; a receiver says what property or event it accepts. This makes combinations discoverable without memorizing named pairs.

- **Static Wake:** "Dashing leaves a trail of Electric damage. No attack is needed."
- **Storm Crown:** "Dealing damage charges chain lightning." It currently accepts any damage type; its description must not suggest Electric-only input. Its glossary entry explains one count per foe per original action and one discharge per action.
- **Hunter's Snare:** "Your attacks Slow foes. Already Slowed foes take more damage." Level 1 amplifies Attack damage; level 2 amplifies all qualifying damage. Check Slow before that damage applies any new status.
- **Future Electric-specific receiver, only after implementation:** "When you deal Electric damage, [effect]." Wake then qualifies by property. Do not put "charges Storm Crown" in Wake's description or promise that every lightning-themed power shares a charge resource.

Distinguish using an attack from connecting it: Execution Edge counts attacks, even misses; Riftpunch and Sigil Chain accept deliberate melee, Razor Wind and charged Blast connections. Their automatic descendants are not new attack hits. Farline Volley's level-3 dash Burst deals damage without replaying attack-hit effects.

Specify who owns a trigger (you or a teammate), when a condition is checked, and what is counted: attack, damaged foe, tick, kill or effect activation. A newly applied Slow is not automatically an already-present Slow. A repeated tick does not automatically earn a new reaction allowance. Keep the prominent restriction on the card and the full counting rule in that power's glossary entry; never invent a universal limit to simplify the wording.

Describe scaling separately from activation. An effect based on attack damage does not necessarily require another attack to activate. Verify the actual calculation before calling a value a percentage of Damage or of attack damage. Echo copies retain only their implemented geometry, properties and bonuses; they do not imply copied status applications, resource generation or recursive effects.

## Authoring and verification

Use `scripts/upgrade_system.gd` for shared card/build text and `scripts/shared/glossary_data.gd` for detailed rules. `scripts/shared/combat_keyword_catalogue.gd` owns canonical definitions and bold+color styling. Author a semantic span explicitly, for example `{kw:attack}` or `{kw:slow|Slowed}`, and pass the sentence through `format_text()`. Never highlight by broad string replacement: a power name, flavor word or internal HIT identifier is not evidence of a mechanic. Reward/build descriptions already return formatted BBCode; preserve it when displaying them. Check alternative upgrade-preview paths and summaries when changing a shared sentence. The current roster is in [combat-power-roster.md](combat-power-roster.md); [shared-build-engines.md](shared-build-engines.md) retains the earlier electrical checkpoint for history.

Internal `HIT`, `hit_damage` and related serialized identifiers retain their existing meanings. They are implementation vocabulary, not player-facing wording. Do not rename them or broaden an old power's trigger as part of a copy edit.

For changed descriptions, run the existing isolated power-description and reward-layout checks, including levels and Prismatic. Preserve the 109-character card-body limit without silently clipping essential controls or restrictions. Wording checks verify presentation; mechanic or interaction changes also need their relevant gameplay tests and playtesting.

## Roles and conditional values

Boons increase generic capability. Missions grant a permanent Boon and a temporary increase; Arcana establish the build, while boss rewards extend or convert it. Keep all twelve Boons, six Mission bonuses, twenty-one Arcana and nine boss rewards under their existing equal-random offer rules.

First Strike (+16), Blood Pact (+9) and Severing Edge (+14) add to a qualifying Damage basis per pick, not a full flat amount on every small tick. The effective Damage coefficient includes contact time and copied-effect strength. Child effects carry an unconditioned descriptor and evaluate their actual target once. Battle Trance refreshes on accepted owned damage. Overcharge reduces Attack and Dash cooldowns to 80% for three room clears; it does not change Blast recharge, hold thresholds or create a nova.

Display names are Aegis Pulse, Fracture and Lacuna Well. Their stable save/network IDs remain `aegis_field`, `fracture_field` and `lacuna_echo`.
