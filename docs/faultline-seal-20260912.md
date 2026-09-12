# Faultline Seal

Feedback `FB-dc92d28091274da1`: the player rejected an oversized Field that pulled enemies toward the character and authorized a complete redesign. **Faultline Seal** replaces Pillar Convergence. Its saved/network power ID remains `pillar_convergence`, with the existing two boss-reward upgrade levels and mapped ratio preserved.

The roster already offers Attack-contact Bursts, Projectile-to-Burst and Burst-to-Electric-Projectile conversions. This reward gives owned Field damage a distinct timing payoff: breaking a small, stationary seal early for a stronger Burst. Ordinary Attack hits still make it useful by itself, while Electric damage provides an alternative input without requiring a named pair.

| Rule | Level 1 | Level 2 |
| --- | --- | --- |
| Accepted Attack-hit or Electric actions to plant | 3 | 2 |
| Stationary Burst radius | 76 | 90 |
| Fuse | 0.8 seconds | 0.8 seconds |
| Ordinary Burst | 180% of Damage | 240% of Damage |
| Burst triggered by later owned Field damage inside | 270% of Damage | 360% of Damage |
| Rearm lock after either detonation | 0.6 seconds | 0.6 seconds |

Each original action contributes at most one charge across all targets, ticks and descendants. The last accepted charge plants one seal at the struck foe's hit location, including lethal contacts when combat remains active. It stays there if the foe or player moves. Repeated hits cannot refresh or relocate it. A Field event can plant a seal, but the event itself cannot also detonate it; a subsequent accepted tick from that same persistent Field can. Rejected damage, other owners' damage, non-Field effects and Field damage outside the radius cannot trigger the stronger detonation.

Charging pauses while the seal is armed and during rearm. Qualifying actions accepted in either period spend their opportunity and cannot bank delayed charges afterward. Detonation closes the seal and starts the lock before producing any descendants. Its Burst is a host-only accepted damage reaction, carries the unconditioned Damage basis and coefficient, and resolves conditions once against each actual victim. Solid cover blocks it. The Burst never registers an owned Field, refunds Dash, displaces enemies or enables a Launch by itself. Faultline ancestry survives Relay, Crown, Shatterwake and delayed kill-Field descendants, preventing them from planting another seal.

The compact visual shows four boundary brackets, a rising shard and a fuse arc. The ordinary impact uses pale violet; an early Field detonation uses warm gold. Start, detonation and cancellation use reliable host-authorized cues for both the owning joiner and observers. Run, room, interaction epoch and serial checks reject stale presentation. Replicas render no gameplay fuse or damage. Death, removal, input cancellation, room cleanup, snapshot restoration and accepted owner-epoch replacement synchronously cancel active seals and partial charge. Snapshot restoration keeps the learned reward while retiring its previous action progress. These changes preserve the unrelated Oath bank.

Card explanations, numeric comparisons, Build Details, glossary, power metadata and the current roster describe this identity. The keyword catalogue's authored semantic spans remain the rendering authority: the reward accepts Attack hit, Electric and Field; it produces Burst and damage. This boss reward has two levels and no Prismatic upgrade.

Isolated verification before integration:

- Initial focused run compiled 395 scripts and passed 3,036 assertions across native Field inputs, rewards, wording, owned Field geometry, producers and accepted interactions. Additional actual lifecycle coverage passed 114 Faultline assertions, 115 boss-reward synergy assertions, 211 interaction assertions, 1,090 snapshot assertions and 78 connected-build assertions.
- Real two-process ENet covers joiner-owned ordinary and early Burst damage/credit, owner and observer visuals, cancellation, stale state, finite ancestry, and the updated valid ancestry mask. Final report paths are recorded in the task evidence receipt.
- Four native GPU frames passed on an RTX 4080 and were visually reviewed: armed marker, moving player/target with fixed marker, ordinary detonation and stronger Field detonation. No expired marker remains afterward.

The primary task coordinates final combined regressions, native reward-card rendering and one normal desktop build. Human playtesting still decides whether the compact seal and early Field payoff feel rewarding; these checks do not assert creative acceptance. The older [gathering Field report](pillar-convergence-20260911.md) is retained as history.
