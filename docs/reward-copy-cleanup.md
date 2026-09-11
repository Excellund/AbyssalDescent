# Reward explanation cleanup

Feedback `FB-d8b5750c4203416f`: remove irrelevant caveats and describe the reward's relevant trigger and result.

The shared, level-aware explanation remains the source for offered cards and owned Build Details. Numerical comparisons, level unlocks, damage calculations and keyword eligibility are unchanged. For example, Phantom Step names normal Dash contact and its once-per-foe limit; it no longer lists Recoil and Orbit as excluded actions. Hunter's Snare names an already Slowed target rather than repeating the same-hit exclusion.

The review also covers Prismatic descriptions, the expanded Rules panel and older flavor fallback strings. Meaningful restrictions remain: Static Wake trails share damage when they overlap; Fracture cannot repeatedly trigger itself; Tempo cannot rebuild from its own Burst; Convergence cannot charge during its active Field; Echoes retain their original resource and reaction limits. The glossary retains the detailed definitions of Dash, Mark and copied effects.

For playtesting, read a new reward and an upgrade before choosing it. Check whether the trigger, result and major limit are clear, and whether Build Details agrees after acquisition. In particular, compare Phantom Step, Hunter's Snare, Execution Edge's Prismatic upgrade and Dread Resonance.

Verified in `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-d257129a39df4027a459292231fe293e`: 350 scripts compile and 24,035 focused wording, description, layout, build and glossary checks pass. Nine shared explanations, six expanded Rules strings and three fallback flavor strings changed. Blood Vow's shared numerical template now says "At … health or below," matching its existing inclusive threshold.

Native verification passed 144 frames and 2,165 checks, covering all unowned and upgraded/Prismatic cards at 960/1280/1920: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-4378469775ac4bebaa2ff17fa366e7d7/reward_build_frames` and `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-93f196bde92940e2895085ffaec02cad/reward_upgrade_frames`. Visual review confirmed shortened Phantom Step, Snare, Dread and Prismatic Execution explanations fit and read clearly. Expanded Blast Rules are captured; the six edited Rules entries are covered by source/headless verification. One pre-existing numerical grammar issue, "Every 1 Attacks," was noted for the upcoming reward catalogue pass.
