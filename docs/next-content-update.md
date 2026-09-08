# Keeper and Breach: a support enemy and one encounter

Status: implemented after the September 9 movement playtest. The original three updates are included. This update does not add another control or change Sovereign's Double's proc rules. The checkpoint is delivered as a normal playtest through the same desktop executable.

## Movement fix and remaining playtesting

Razor Orbit chooses its circling direction from the entry dash and retains it until detachment, including its one allowed transfer. Entering and leaving the circle follow the actual travel tangent. Holding or changing a movement key cannot reverse the orbit. First delivered in `dev-debug-orbit-20260908-223654`, this fix is included in the normal checkpoint build. The 197 motion checks, 106 boss combination checks and exported debug startup checks passed for that fix.

The four cover formations and Undertow are already in the game. They need focused human feedback: Undertow appears in Acts 2–3, while the formations share pools with older layouts. A fresh debug Skirmish does not reliably show them. Check whether their firing lanes and escape gaps remain readable while using the movement powers.

## Content milestone

**Keeper** is an ordinary support enemy introduced in **Breach**, an Act 2–3 standard encounter. Current ordinary enemies cover rushes, ranged patterns, hazards and damaging links; protecting another enemy introduces a different target-priority decision.

The Keeper visibly wards up to two ordinary allies within 220 pixels, reducing their damage taken by 30% after a 0.6-second warmup. It remains vulnerable itself. Wards do not heal, grant immunity, protect bosses/Apex enemies/other Keepers, or stack. These are starting values for playtesting.

Players can kill the Keeper, push an ally outside the ward radius, or break the link with cover. A player push of at least 40 pixels/second interrupts both wards for 1.25 seconds before a fresh warmup, giving Ruinous Impact a tactical use. A natural link break leaves that slot empty for at least one second before warming up again; a surviving second link remains active. Damage resolution checks death, distance and cover immediately.

Breach has one Keeper, a small ranged group and light melee pressure, with an open center and side cover. The Keeper prefers a safe position near an ally. Keepers are capped at one after composition modifiers and during spawning, including co-op. Starting populations are:

| Bearing | Keeper | Archer | Chaser |
|---|---:|---:|---:|
| Pilgrim | 1 | 1 | 2 |
| Delver | 1 | 2 | 2 |
| Harbinger | 1 | 2 | 3 |
| Forsworn | 1 | 3 | 4 |

Blast Drive and Razor Orbit help reach or separate targets; Sovereign's Double can cover another attack position. Ordinary attacks, movement and dash must still provide complete answers. Judge the prototype by whether it changes target choice and positioning, rather than simply making a room take longer.

## Implementation and validation

- `EnemyBase` resolves ward reduction before health changes and accepted damage accounting, including the Shielder override. Primary attacks, secondary damage and kill ownership share this boundary.
- The host owns targets, mitigation and interruptions. Compact ordered heartbeats carry stable target IDs; replica links expire after 0.5 seconds without fresh state and never apply damage reduction.
- Encounter contracts, generic peer construction, profiles, biome routing, debug selection and the glossary include Keeper/Breach. Routes and rewards retain the existing behavior.
- Isolated tests cover death, displacement, range, cover, target replacement, packet ordering, room cleanup and save/resume. Profile checks cover all four Bearings, biomes and co-op. Separate two-process ENet and actual GPU fixtures check authority and presentation.
- The normal checkpoint uses the same desktop playtest executable and a unique internal development version. Debug progress remains separate from normal progress. Current delivery details are in [content-updates.md](content-updates.md).

## Other useful directions

The requested follow-up [systems implementation and visual review](systems-and-visual-review.md) covers combat contracts, readability, progression/UI consistency and measured performance in small verified passes.

A new Apex built around baiting a committed charge into a wall would create a clear punish opportunity, but optional encounters are seen less often. Destructible-cover formations would give attacks a new traversal purpose, but require obstacle state, replication and anchor invalidation support. Both remain later possibilities after feedback on the Keeper and the systems/visual review.
