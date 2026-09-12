# Spark Relay: seek living targets

Feedback: Spark Relay commonly launched after its Burst victim died, sending its payoff into empty space.

The bolt now prefers the struck foe while it is alive and reachable. If that foe died, is outside the remaining travel budget, or cannot be reached through open space, acquisition chooses the nearest living reachable foe. While flying, the same bolt follows its target and chooses another candidate after a hit or target death. Higher levels can therefore use their existing two/three-foe allowance without requiring those foes to stand on one line.

Acquisition checks the full eight-pixel projectile radius against solid cover and arena bounds. The bolt still collides with solid cover during flight. Travel is one shared 440-pixel budget (528 Prismatic); turning never replenishes it. No reachable living foe means no bolt, and losing the final candidate retires the active flight. The original action's allowance is spent even when there is no target, so it cannot be banked or recreated by later descendants.

Damage stays at 50/60/70% of the triggering unconditioned descriptor and Damage coefficient, 87.5% Prismatic. Each actual victim resolves its own conditional bonuses. It remains one Electric Projectile per accepted owned Burst action, hits at most 1/2/3 distinct foes once each, and travels at 620 pixels/second. Spark Relay and Shatterwake retain their separate original-action allowances. This buff improves the chance that the existing payoff lands, including lethal triggers and moving crowds.

Only the host selects targets, steers and applies damage. The existing bounded projectile-state protocol carries updated position/direction to replicas; target changes publish a reliable snapshot. No target identity, damage value or new client damage authority was added. Epoch/run/room cancellation, replica leases, monotonic state sequence and malformed/forged packet rejection remain in force.

Reward cards, Build Details, glossary and the combat roster describe seeking and death retargeting. They retain the important once-per-action and cover restrictions.

## Verification

- Isolated shared-keyword (137 checks), lifecycle (48), power rewards (604) and wording (1,778) suites pass. Dedicated cases cover lethal off-axis triggers, a target dying or moving during flight, distinct off-axis victims at level three, target-specific conditional damage, last-enemy kills, no banked allowance, full-width cover acquisition, total travel budget, and wrong-owner/run/room Burst rejection.
- Native ENet: 118 host checks and 25 client checks pass. A joining player's lethal Burst targets a living off-axis foe; another player kills that candidate; the same host-owned bolt redirects, publishes its direction to the owner, lands once with the original owner/root/raw descriptor, and clears reliably. Existing cancellation, observer recovery and forged-state checks also pass.
- Eight native GPU gameplay frames pass on an RTX 4080, including inspected lethal-target acquisition and a visible mid-flight redirect. The existing compact Electric bolt and its trail remain the flight presentation.
- Power descriptions (465 checks), Build inspection (467) and reward selection layout (22,757) pass. Native rewards/Build rendering passes 85 frames with 992 checks; upgrades pass 96 frames with 1,525 checks. Inspected the 960-pixel unowned, Prismatic and expanded Build Rules views. The final metadata wording was rechecked and rerendered. Human balance acceptance remains a playtest decision.

Local evidence under the system temporary directory: `abyssal-validation-7d1ee837803748fcbe5d17e5b98a39de`, `abyssal-validation-6d2e43ba500945ac955e910cfdbee8c7`, final-copy `abyssal-validation-da5df1c1751a461aacbb2b522779be73`, `abyssal-enet-819d36e3ce8d4d9986036b6b810f4acc`, gameplay `abyssal-gameplay-render-85d281a945c643e1bb6ba6715f743032`, final Build `abyssal-gameplay-render-67d71bd77d72442e9bc67e956cce7fb9`, and upgrades `abyssal-gameplay-render-d4b36ac287d94387acb0204485582482`.
