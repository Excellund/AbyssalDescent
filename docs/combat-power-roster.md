# Combat power roster

The shared catalogue has 12 Boons, 21 Arcana, nine boss rewards and six fixed Mission bonuses. Offers retain equal random odds. Boons remain capped at three picks except Heartstone at two; Arcana have three levels and one eligible Prismatic upgrade; boss rewards have two levels. Names below are presentation names; saved IDs remain unchanged.

## Character passives: starting build rules

Passives retain their four character assignments and saved IDs. Character selection, build inspection and the glossary use `scripts/shared/character_passive_catalogue.gd`; its properties also participate in build comparisons. Passive damage can feed damage receivers, but does not perform another Attack or supply a new attack hit.

| Character / passive | Trigger and result / key condition |
|---|---|
| Bastion / Iron Retort | Hold position or move slowly for 0.42s to Brace for 2.4s. Melee/charged Attacks gain 80% damage and 24° arc. First accepted melee, Razor Wind or charged Blast contact spends Brace, releases a 55%-of-empowered-strike-basis Burst and grants 25% resistance for 1.5s. Dash, Recoil and Orbit break Brace; Dash blocks rebuilding for 0.8s. Razor Wind can spend Brace but is not itself empowered. |
| Hexweaver / Sigil Burst | Normal Dash arms one Burst; next accepted melee, Razor Wind or charged Blast contact releases it for 70% of the triggering attack's damage basis. Once per original Attack; repeated Dashes do not bank extra Bursts. Detonates nearby owned Sigil Chain sigils at three times their tick damage: active Fields are consumed, dormant sigils persist until the chain resets. |
| Veilstrider / Veilstep Rhythm | One shard per normal Dash touching foes. Two shards refresh Dash and open a 4s window; the next Dash has no cooldown and ends in a 160%-Damage Burst. The Burst or an unused window's expiry clears shards. Recoil/Orbit do not grant shards. |
| Riftlancer / Farline Focus | Melee/charged Blast damage ×1.70 inside both the outer 98/132–100% range band and Attack aim arc; ×0.70 otherwise. Band scales with Attack range; each target's body overlaps the band and its center lies in the aim arc. Razor Wind and automatic descendants do not make a new check; descendants retain copied source scaling. |

Retort and Sigil descendants carry the unconditioned source basis and scaled Damage coefficient, resolving conditions against each actual victim. Retort, Sigil and Veilstep are Bursts, without Electric, Field or Push properties. Rejected damage does not itself spend Brace or an armed Sigil Burst; subsequent Recoil still breaks Brace. Farline compatibility includes charged Blast but excludes Razor Wind.

## Boons: permanent generic increases

| Boon | Per pick |
|---|---|
| Heavy Blow | +7 Damage |
| Wide Arc | +28° Attack arc, capped at 280° |
| Long Reach | +11 Attack range |
| Fleet Foot | +17 movement speed |
| Blink Dash | Dash cooldown ×0.80, minimum 0.14s |
| Iron Skin | +4 armor |
| Battle Trance | Dealing damage refreshes +22% movement speed per pick for 1.25s |
| Surge Step | +85 Dash speed |
| Heartstone | +10 maximum health and the same increase to current health |
| First Strike | +16 conditional Damage basis against enemies at least 80% HP |
| Blood Pact | +9 conditional Damage basis while at most 50% HP |
| Severing Edge | +14 conditional Damage basis against enemies below 55% HP |

Conditional Damage additions use each source's effective coefficient, including contact time and Echo strength. They do not add their full flat amount to each tiny tick. Conditions are checked against each actual target before damage, once.

## Arcana: build generators and receivers

| Arcana | Trigger and result / key condition |
|---|---|
| Razor Wind | Attack extends a cutting arc beyond normal melee reach. |
| Execution Edge | Every few Attacks multiply strike damage; misses still count. |
| Rupture Wave | Attack hits create Bursts; later levels Slow and chain within existing limits. |
| Aegis Pulse | Periodic Slow pulse and brief resistance; no persistent Field. |
| Hunter's Snare | Attack hits Slow; L1 +20% Attack damage vs already Slowed, L2 +25% all damage, L3 +30% and double applied Slow duration; Prismatic 45%. |
| Phantom Step | Normal Dash contact damages and Slows. |
| Riftpunch | Dash completion primes the next deliberate attack hit; later levels Slow and release a Burst. |
| Reaper Step | Kills refresh Dash; longer and faster dashes. |
| Static Wake | Normal Dash draws up to two Electric Fields sharing one contact-scaled damage clock. L3 applies Slow after damage. |
| Storm Crown | Dealing damage charges Electric chains; one count per foe and discharge per originating action. L2+ gets one extra jump through already Slowed foes. |
| Wraithstep | Dash applies 15/20/25% Mark. L2 attack hit against already Marked releases one Burst per Attack; L3 visits up to three more Marked foes. Prismatic Mark 30%. |
| Voidfire | Attack hits build Heat; Danger Zone increases Attack damage; overheat releases a Burst and briefly locks Attacks. |
| Dread Resonance | Attack hit applies 10% Mark for 3s and adds one stack per foe/Attack. Each owner-specific stack adds 2 percentage points against that Marked foe; caps 8/10/12. Prismatic 2.4 points, cap 15. |
| Blood Vow | Wounded Attacks deal more damage. |
| Eclipse Mark | Kills apply 15/20/25% Mark nearby for 4/5/6s. Prismatic 30%, retaining its radius/duration improvements. |
| Fracture | Kills release damaging, Slowing fault-line Bursts; own descendants cannot repeat it. |
| Farline Volley | Edge-of-reach attack hits build damage/arc stacks; Dash resets/spends them. Final Burst does not repeat attack-hit effects. |
| Sigil Chain | Deliberate attack hits charge and place persistent Fields. |
| Blast Drive | Hold Attack and release a charged Burst with Recoil. |
| Razor Orbit | Hold Dash and aim at an anchor to Orbit and cut; manual Attacks remain available. |
| Returning Crescent | Attacks throw a returning Projectile; one hit per foe on each leg. |

Marks are timed shared vulnerabilities: strongest active base Mark applies to all player damage. Damage does not consume them. Dread stacks belong to the owner and enemy; they survive target switching and Mark expiry, clearing with that enemy or room.

## Boss rewards: conversions and peaks

| Reward | Role |
|---|---|
| Warden's Verdict | Consecutive attack contacts build a four-contact damage Burst. |
| Lacuna Well | Kills create a pulling damage Field; its existing bonus applies once inside any owned Field. |
| Sovereign Tempo | Attack contacts build Tempo, spent once when Dash/Recoil/Orbit completes; accepted wave damage refunds Dash cooldown. |
| Pillar Convergence | Attack contacts create a moving damage Field for a bounded window. |
| Unbroken Oath | Resistance plus Attack-built Oath that empowers the next Attack. |
| Edict of the Court | Kills Push nearby enemies. |
| Null Corridor | Dash leaves a Field that Pushes and damages at its existing cadence. |
| Ruinous Impact | Attack hits and eligible Push/Pull effects arm Launches; one Impact Burst, with compression for immovable targets. |
| Sovereign's Double | Completed movement places a shade; one/two Echoes copy 55% of deliberate attack shape and damage without new Attack/resource/reaction allowances. |

## Missions: permanent Boon plus three-room amplification

| Mission | Fixed temporary increase |
|---|---|
| Last Stand | Fortified:15% damage resistance |
| Cut the Signal | Hunter's Focus:25% damage increase |
| Hold the Line | Combo Relay:5% damage and movement per Kill, four stacks, existing 2.8s reset |
| Circuit Sweep | Relay Boost:Kill grants 28% movement speed for 1.4s |
| Pulse Window | Overcharge:Attack and Dash cooldowns ×0.80 |
| Intercept Run | Node Shield:6% resistance per foe within 180, capped 30% |

One confirmation grants the chosen permanent Boon and fixed temporary increase together. Skip declines both. Temporary effects retain three encounter clears; Overcharge does not accelerate Blast recharge or change hold thresholds.

Runtime and networking limits live in the implementations; this roster describes the approved roles, not new universal proc rules. Use [combat-wording.md](combat-wording.md) and the authored keyword catalogue for player-facing text.
