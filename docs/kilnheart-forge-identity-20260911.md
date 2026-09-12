# Kilnheart forge identity

Feedback: `FB-29a0ac93b00a43f1`. Branch: `codex/refinements-20260911-kilnheart-identity`.

The player found Kilnheart slow, easy to kill, and less distinctive or impactful than Warden. Warden combines directional charge, nova and cleave; Kilnheart now emphasizes a pressure-and-release forge rhythm. Its committed Slam builds pressure, lifts, and accelerates into the already marked landing. Four separately warned **Crucible Vents** then cut across a straight retreat, leaving clear wedges and a small body-clear hub. Halo still alternates OUT/IN and Cinder Pursuit still captures movement ahead of the player. Every root now finishes a two-beat sequence before offering a full recovery.

The previous impact feedback was tied to successfully hurting the player, so dodging could make the boss seem inert. Each observed Kilnheart warning/impact now receives furnace pressure/clank audio and the shell opens, lifts and recoils; resolved vents flash white-hot. Sound respects SFX volume and bus routing and is owned by the boss. These effects happen on successful dodges too, without applying player hurt flashes or extra damage. Cast/phase deduplication prevents replay from repeated or reordered snapshots; client warning expiry remains silent and harmless until an actual host impact arrives. Room/death cancellation stops sound and clears shapes/follow-ups.

## Tuning and guardrails

- HP 1100 → 1320; damage remains 38 (Halo keeps its existing 1.15 multiplier).
- Pursuit speed 122 → 190, preferred spacing 175 → 145, idle 0.68 → 0.44 seconds, initial wait 0.80 → 0.35 seconds.
- Final punish recovery 0.72 → 0.80 seconds. Existing half-health interval reduction remains; no warning shortens at enrage.
- Slam warning remains 1.25 seconds, radius 185, range cap 420, arena margin 205. Body is nonblocking only during its plunge and still accepts player damage.
- Vents use the remembered landing and root direction. They begin after 0.22 seconds with their own 1.05-second warning. Four capsule lanes run from radius 115 to at most 480 with half-width 36, clipped along their rays so capsule caps remain inside the arena floor. Impact remains once per living player/cast, including co-op overlaps and duplicate targets.
- Real spawn audit: `BossStageRegistry.create_boss_node` configures the selected identity before `_ready`; `_ready` loads its profile. `world_generator._apply_boss_difficulty_scaling` then applies Bearing and party health scaling once. The profile increase reaches normal encounters and snapshot reconstruction without changing shared scaling.

Verification results recorded after the final checks below. Human playtest still needs to judge perceived weight, first-encounter readability and the overall difficulty increase.


## Final verification

- Scoped regression runner: 384 GDScript files compile; world-property and multiplayer configuration contracts pass. Alternative combat: 4,842 checks; boss selection/Continue: 254; shared boss callouts: 463. All pass. Disposable evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-bed234a75e8f4047b7625cf6e6a0030b`.
- Native two-process ENet: 432 host checks and 112 client checks pass. The new Slam/Vents sequence travels through production ability RPCs, preserves exact geometry and identity, fits the existing packet budget, applies authoritative player damage once, retains the new warning against old root packets, and cancels across death/room cleanup. Existing direct Attack and Crescent damage during nonblocking Slam still pass. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-e6b9437968fe4b648c0e581ce23ee9a0`.
- RTX 4080 GPU capture: 25 frames, zero fixture failures. Manual inspection of the accelerated Slam silhouette, Crucible Vents warning and resolved impact confirmed fixed danger, clear wedges, floor-contained capsule caps, readable callout, and harmless impact contrast. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-85e275567078459c9a76cde18a1f9afd/alternative_boss_frames`.
- Runtime audio assertions cover non-silent bounded PCM and cue deduplication/lost-packet behavior. GPU execution creates the real audio players; subjective loudness, weight and enjoyment remain playtest questions.

No desktop export or commit was made from this worktree; the coordinating task integrates and delivers the normal build.
