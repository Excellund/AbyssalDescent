# Combat power roster

The shared catalogue has 15 Boons, 23 Arcana, ten boss rewards and six fixed Mission bonuses. Offers retain equal random odds. Boons remain capped at three picks except Heartstone at two; Arcana have three levels and one eligible Prismatic upgrade; boss rewards have two levels. Existing names below retain their saved IDs; new powers have distinct appended IDs.

## Character passives: starting build rules

Five characters have distinct starting passives; existing saved IDs are unchanged. Character selection, build inspection and the glossary use `scripts/shared/character_passive_catalogue.gd`; its properties also participate in build comparisons. Passive damage can feed damage receivers, but does not perform another Attack or supply a new attack hit.

| Character / passive | Trigger and result / key condition |
|---|---|
| Bastion / Iron Retort | Hold position or move slowly for 0.42s to Brace for 2.4s. Melee/charged Attacks gain 80% damage and 24° arc. First accepted melee, Razor Wind or charged Blast contact spends Brace, releases a 55%-of-empowered-strike-basis Burst and grants 25% resistance for 1.5s. Dash, Recoil and Orbit break Brace; Dash blocks rebuilding for 0.8s. Razor Wind can spend Brace but is not itself empowered. |
| Hexweaver / Sigil Burst | Normal Dash arms one Burst; next accepted melee, Razor Wind or charged Blast contact releases it for 70% of the triggering attack's damage basis. Once per original Attack; repeated Dashes do not bank extra Bursts. Detonates nearby owned Sigil Chain sigils at three times their tick damage: active Fields are consumed, dormant sigils persist until the chain resets. |
| Veilstrider / Veilstep Rhythm | One shard per normal Dash touching foes. Two shards refresh Dash and open a 4s window; the next Dash has no cooldown and ends in a 160%-Damage Burst. The Burst or an unused window's expiry clears shards. Recoil/Orbit do not grant shards. |
| Riftlancer / Farline Focus | Melee/charged Blast damage ×1.70 inside both the outer 98/132–100% range band and Attack aim arc; ×0.70 otherwise. Band scales with Attack range; each target's body overlaps the band and its center lies in the aim arc. Razor Wind and automatic descendants do not make a new check; descendants retain copied source scaling. |
| Effigy Keeper / Effigy Command | With no effigy, a deliberate Attack places one up to 180 range ahead and delivers that deployment strike from the body, even on a miss. Later real Attacks originate at the fixed effigy with normal Damage, reach and arc. Walking and enemy deaths preserve it; normal Dash recalls it. Recoil and Orbit keep the placement. One original Attack retains each power's existing action/victim limits. |

Retort and Sigil descendants carry the unconditioned source basis and scaled Damage coefficient, resolving conditions against each actual victim. Retort, Sigil and Veilstep are Bursts, without Electric, Field or Push properties. Rejected damage does not itself spend Brace or an armed Sigil Burst; subsequent Recoil still breaks Brace. Farline compatibility includes charged Blast but excludes Razor Wind.

Effigy Command relocates the existing Attack instead of generating a secondary damage source. Charged attacks use that origin while Recoil moves the body. Placement clears on room exit, death, character changes and snapshot restoration. The old `threadbinder` character ID, packed Cross Stitch compatibility slots and Mark source ordering remain stable; the old passive is inactive. Effigy Keeper unlocks after a normal Riftlancer clear and uses the ordinary shared reward pools and per-character Bearing progression. See [Effigy Keeper](effigy-keeper.md) for the control contract and verification.

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
| Patient Hunter | +12 conditional Damage basis against already Slowed foes |
| Marked Prey | +12 conditional Damage basis against already Marked foes |
| Farshot | +10 conditional Damage basis against foes at least 160 from your current body when damage lands |

Conditional Damage additions use each source's effective coefficient, including contact time and Echo strength. They do not add their full flat amount to each tiny tick. Conditions are checked against each actual target before damage, once.

Farshot checks current body-to-foe-center distance for all eligible damage, including Fields, Projectiles and Echoes. Moving before impact changes eligibility; an Effigy or Projectile origin does not set range. Its initial +10 tuning is unaccepted balance. See [Farshot](farshot.md).

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
| Static Wake | Normal Dash draws up to two Electric Fields sharing one contact-scaled damage clock. Damage rate is 4.5 times the mapped amount per second (25% lower at every level, including Prismatic). L3 applies Slow after damage. |
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
| Razor Orbit | Hold Dash and aim at an anchor to Orbit and cut; manual Attacks remain available. Release Dash for a 0.25s escape steered by movement input (no input keeps momentum). Expiry and anchor loss use the same escape; it grants no Dash effects, phasing or immunity. |
| Returning Crescent | Attacks throw a returning Projectile; one hit per foe on each leg. |
| Stormbrand | Accepted Electric damage applies Mark once per foe/original action: 10/14/18% for 3/3.5/4s; Prismatic 22.5% for 5s. L3 also Slows an already Marked foe to 75% speed for 1s after damage, respecting global Slow duration. |
| Spark Relay | Accepted Burst damage launches one seeking Electric Projectile from the body per original action. Prefers the struck foe if alive and reachable, otherwise the nearest living reachable foe. Retargets after a hit or target death using the same remaining travel; no target means no bolt. Copies 50/60/70% of the triggering raw descriptor/coefficient; Prismatic 87.5%. Hits at most 1/2/3 foes once each, total travel 440 (Prismatic 528), speed 620, radius 8. Solid cover blocks it; acquisition checks the full projectile width. Host alone selects targets; replicas receive bounded flight snapshots. |

Marks are timed shared vulnerabilities: strongest active base Mark applies to all player damage. Damage does not consume them. Dread stacks belong to the owner and enemy; they survive target switching and Mark expiry, clearing with that enemy or room.

## Boss rewards: conversions and peaks

| Reward | Role |
|---|---|
| Warden's Verdict | Consecutive attack contacts build a four-contact damage Burst. |
| Lacuna Well | Kills create one damaging Field for 2.4s, replacing the last. Accepted pulses Slow survivors to 75% speed for 0.45s; Slow-duration bonuses apply. Its existing damage bonus applies once inside any owned Field. |
| Sovereign Tempo | Attack hits or owned damage against already Marked foes build one Tempo stack per original action across all victims and descendants. Up to six stacks, expiring 1.8s after the last accepted stack; Dash/Recoil/Orbit completion spends them in one Burst. Accepted Burst damage refunds 0.12s of Dash cooldown per spent stack once per Burst; the Burst and its descendants cannot build Tempo. |
| Faultline Seal (`pillar_convergence`) | Attack hits or owned Electric damage charge once per original action. Three/two charges plant one stationary seal at the struck foe’s position, including lethal contacts. After 0.8s it releases a Burst for 180/240% of Damage in radius 76/90. Later owned Field damage to a foe inside triggers it early for 270/360%; the planting event cannot also detonate. One seal, no refresh/relocation, no charging while armed or for 0.6s afterward. Qualifying actions spent during either window cannot bank later charges. Its Burst and descendants cannot charge another seal, including delayed kill-Fields. Cover blocks the Burst; it never displaces foes or registers an owned Field. |
| Unbroken Oath | Resistance plus Oath from accepted Attack hits. Each unique victim contributes once per original Attack across melee, charged Blast and Razor Wind, with that Attack's own successive-contact multiplier. A full bank empowers the next deliberate Attack and is spent even on a miss; that spending Attack and its descendants cannot refill it. Retaliation damage and its Damage coefficient apply once across the Attack's victims. The sword uses the committed Attack origin, including body-origin deployment and later effigy-origin Attacks. |
| Edict of the Court | Kills release one Burst per original action for 80/120% of Damage in radius 120/160. Accepted damage Slows survivors to 75% speed for 1.5s, with Slow-duration bonuses. All kills share the root allowance; descendants cannot restart Edict. |
| Null Corridor | Dash leaves a Field dealing 24/28% of Damage per accepted contact, at most once per foe every 0.5s per trail. It then Marks survivors for 1s at 10/15% vulnerability; strongest Mark wins. Width 39/46 and lifetime 3.6/4s are unchanged. |
| Ruinous Impact | Attack hits and eligible Push/Pull effects arm Launches; one Impact Burst, with compression for immovable targets. |
| Sovereign's Double | Completed movement places a shade; one/two Echoes copy 55% of deliberate attack shape and damage without new Attack/resource/reaction allowances. |
| Shatterwake | Accepted Projectile damage releases one Burst per original action, including the primary foe if alive. Copies 60/80% of the raw descriptor/coefficient, radius 100/125. Return legs and descendants share its allowance. No displacement. |

## Missions: permanent Boon plus three-room amplification

| Mission | Fixed temporary increase |
|---|---|
| Last Stand | Fortified:15% damage resistance |
| Relic Recovery | Fortified:15% damage resistance |
| Cut the Signal | Hunter's Focus:25% damage increase |
| Hold the Line | Combo Relay:5% damage and movement per Kill, four stacks, existing 2.8s reset |
| Circuit Sweep | Relay Boost:Kill grants 28% movement speed for 1.4s |
| Pulse Window | Overcharge:Attack and Dash cooldowns ×0.80 |
| Intercept Run | Node Shield:6% resistance per foe within 180, capped 30% |

One confirmation grants the chosen permanent Boon and fixed temporary increase together. Skip declines both. Temporary effects retain three encounter clears; Overcharge does not accelerate Blast recharge or change hold thresholds.

Faultline Seal connects Attack hits and Electric generators to a focused stationary Burst, and gives owned Field damage a stronger early detonation payoff. Sovereign Tempo turns prepared Marks into movement payoffs. Conditional Damage Boons and Battle Trance apply at the accepted-damage boundary. Each receiver keeps its own original-action allowance; neither grants another Attack. Faultline descendants retain their source action and ancestry, with raw Damage basis and coefficient resolved once against each actual Burst victim.

Runtime and networking limits live in the implementations; this roster describes the approved roles, not new universal proc rules. Use [combat-wording.md](combat-wording.md) and the authored keyword catalogue for player-facing text.

Edict, Lacuna Well and Null Corridor no longer force enemy movement. They connect kills to Burst/Slow, persistent Fields to Slow, and Dash Fields to shared Mark. Ruinous retains deliberate Attack-hit Launches, aimed Blast Push, collision Bursts and immovable compression. The former automatic Push/Pull paths from those three rewards are retired. Edict's descendants carry both the original action allowance and persistent ancestry through any kill-created Fields, so delayed reactions cannot restart its Burst chain. See [boss reward control changes](boss-reward-control-20260911.md).

The new converters each claim their own original-action allowance before producing descendants. Burst → Electric Projectile → Burst and Projectile → Burst → Electric Projectile are finite chains; they do not create another Attack, reopen charge limits or reuse conditioned parent damage. Blast Drive's committed cone exposes its already-advertised Burst form. A copied Blast retains Echo and Burst, while copied melee/Razor remain Echo; no new Projectile casts are implied by Echo. See [synergy expansion](synergy-expansion-20260911.md) for contracts and verification.
