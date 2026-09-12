# Farshot

Farshot is an ordinary Boon that adds **10 conditional Damage per pick**, up to **three picks**, against a foe whose center is **at least 160 units from the owning player's current body when damage lands**. The initial +10 value has not been accepted through human balance playtesting.

The choice rewards keeping distance while damage is delivered. It can complement a placed Field, a traveling Projectile, an Echo or an Effigy strike. Moving closer before damage lands removes eligibility; moving away can enable it. Each actual victim has its own distance check. A distant projectile or Effigy origin does not stand in for the player's body.

Long Reach changes Attack geometry. Riftlancer's Farline Focus and Farline Volley concern deliberate attack contacts near the weapon's reach edge. Farshot instead applies through the shared accepted-damage boundary to all eligible owned damage. It adds no Attack, attack hit, property, reaction allowance, new damage source, timer or RPC.

## Damage and compatibility

`scripts/shared/shared_damage_modifiers.gd` adds the Farshot basis alongside existing conditional Boons before existing Mark, Field and Mission multipliers. Both positions must be finite. The inclusive distance uses squared body-to-target-center distance, with a single 160-unit constant.

The source's effective Damage coefficient scales the addition. At one pick, a 10-damage Field packet with coefficient 0.1 receives +1 damage; ten equivalent smaller contacts still receive +1 total under existing fractional carry. A 55% Echo receives 55% of the conditional bonus. Child effects retain their unconditioned damage descriptor and coefficient and resolve their own target once, so neither the parent's distance condition nor its already-conditioned amount can be copied into collateral.

Co-op uses the authenticated owner's host-side Player and its current replicated body position. The owner acquires Farshot through existing capped upgrade mapping, and the ordinary build snapshot carries its value. Enemy damage, player movement, run/room identity, action validation, damage attribution and receiver limits use their existing transports and rules. Network latency means the host evaluates the position it has received at the moment it accepts damage, as with the existing combat boundary.

## Acquisition and persistence

- Stable ID `farshot`, runtime property `farshot_bonus_damage`, ordinary three-pick Boon cap. It joins the shared random Boon pool; there is no guaranteed offer or new reroll rule.
- Normal acquisition adds 10 to the conditional property and leaves unconditional Damage unchanged. Rest can invest in Farshot only when already owned and below its normal cap; it still forgoes healing and rechecks availability at claim.
- Player run and network build snapshots include the new property and stack count. A legacy snapshot missing the property resets it to zero on a reused actor. Existing save and network IDs retain their meanings.
- A resolved Rest checkpoint saves the acquired level with the actual next doors. Continue restores it without repeating either the upgrade or healing.
- Reward cards and current build numerical summaries state the exact distance, body and impact timing. Build metadata and glossary explain source scaling, individual target centers and Effigy/Projectile origins through the existing semantic catalogue.

## Verification

All automation uses disposable source copies and isolated profiles. Fixture staging establishes precise combat conditions; it is not a normal-run balance result.

The final focused snapshot `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-f7ec7519d77b477083c2a33fceb6c65a` passed all 439 script compilations and both structural guards, plus 34 Farshot boundary, 37 Farshot lifecycle, 87 shared damage, 48 keyword lifecycle, 465 power description, 231 glossary, 314 Rest and 68 Effigy runtime checks. The branch receipt is `.feedback/uncharted-descent-20260912/farshot-focused.log`.

The final ENet snapshot `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-08d498ef956e4f27965e621656b059d5` passed 32 host and four client checks through the native loopback transports without fixture diagnostics. The branch receipt is `.feedback/uncharted-descent-20260912/farshot-enet.log`. The driver pauses unrelated combat time and stages owner positions through the existing position transport; it does not claim live-combat or Internet-lobby balance evidence. An initial run passed its gameplay assertions but exposed a fixture-only position pump after disconnect; the final driver checks transport connectivity before pumping.

- `scripts/tests/test_farshot.gd`: accepted-damage threshold directions, player/target movement after launch, body versus source origin, individual collateral, retained raw basis, fractional Fields, Echo coefficient, other eligible sources, existing Mission ordering, owner separation, unowned behavior and rejected damage.
- `scripts/tests/test_farshot_lifecycle.gd`: actual Player acquisition/caps/previews, old/new run and network snapshots, normal Rest investment, encoded save reload and production Continue without repeated resolution.
- `scripts/tests/test_threadbinder_runtime.gd`: real canonical Effigy Attacks before and after body movement, preserving deployment, fixed placement and exact deliberate Attack count.
- `scripts/tests/test_farshot_enet.gd`: two loopback ENet processes, production provenance handshake, owner build snapshots, movement and accepted enemy-damage RPCs. Checks inclusive threshold, movement after a saved launch action, Field and Echo coefficients, near/far collateral, spoof rejection, owner credit and observer state.
- [Native Farshot UI](farshot-native-ui.md): actual Main reward, Build Details and eligible Rest presentations at production canvas scale, with staged levels for inspection.

Use `.github/scripts/run_gameplay_regressions.ps1 -TestScripts @('res://scripts/tests/test_farshot.gd','res://scripts/tests/test_farshot_lifecycle.gd','res://scripts/tests/test_threadbinder_runtime.gd')`, and `.github/scripts/test_farshot_enet.ps1 -ValidationProject <isolated-validation-copy>` for focused reproduction. Native UI has its own scoped render helper. This work does not export a playtest build or change the feedback board.
