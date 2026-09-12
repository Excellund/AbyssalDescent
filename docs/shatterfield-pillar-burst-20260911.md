# Shatterfield pillar payoff

Feedback: FB-aafee5dc37e24d37.

Breaking a cracked inner pillar releases a shard Burst: 60 base damage to every foe within radius 160, once per pillar. Players are safe. Each pillar still takes three deliberate Attack contacts, keeps its original cover until destroyed, and opens the original permanent route. Permanent outer columns and cover-free room fragment hazards keep their existing behavior.

The Burst shows its full affected radius immediately, sends mint shards outward, and displays the checked HELP shield for a 0.48-second cosmetic lifetime. The HUD and biome inspection explain the payoff. The glossary distinguishes checked-shield HELP from warning-triangle DANGER.

## Authority and lifecycle

The authoritative Attack boundary records actual transitions from one contact to zero, captures their authored positions, removes collision, and sends the existing cover revision before applying damage. Accepted replica cover-state transitions generate visuals only; duplicate, stale and invalid revisions cannot replay them. Native enemy health replication supplies the result. No effect RPC or client-nominated radius/damage was added.

Damage goes through native enemy protection with empty inherited interaction scope, secondary-damage suppression, and the existing environmental death guard. It supplies no owned damage, attack-hit charges, or player kill reactions. A controller generation change stops remaining targets after synchronous room retirement; room/run identity checks stop later pillar Bursts. Room reset clears visuals; pause freezes their bounded cosmetic lifetime.

## Verification

Disposable Godot import compiled 377 scripts with world-property and multiplayer configuration contracts passing. The new runtime fixture passed 19 checks, including real third-Attack activation, multiple targets, protected/out-of-range foes, players, replay/expiry, two pillars, and synchronous last-enemy cleanup. Brittle-cover regression passed 115 checks; biome clarity 338; real biome-room context 1,246. A final additional assertion learns Pillar Convergence through its proper boss-upgrade path and explicitly checks that shards do not charge it; the combined integration run passed that assertion (20 checks total).

Native two-process ENet passed 108 host and 111 joining-client checks using the production cover request, cover state and enemy health transports. Five RTX 4080 frames cover final crack, impact, spread, late fade with full 960-width inspection, and expiry. The native inspection fits without clipping. Human playtest acceptance remains outstanding; root coordinates combined delivery.
