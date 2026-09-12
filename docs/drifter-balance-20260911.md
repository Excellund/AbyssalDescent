# Drifter balance — 11 September 2026

Feedback: Drifters are too easy to dodge and kill (`FB-1e7db42620014cef`).

Drifters now sustain more pressure and require a new dodge position for successive waves, with a visible missing-spoke opening and bounded damage.

| Value | Before | After |
| --- | --- | --- |
| Intended base maximum health | 68 | 88 |
| Unscaled initial current health | 40, due to initialization order | 88 |
| Movement speed | 72 | 90 |
| Wave interval | 3.4s | 2.8s |
| Wave travel speed | 148 | 176 |
| Maximum wave radius | 280 | 360 |
| Spokes, including the missing spoke | 8 | 12 |
| Pellet damage radius | 17 | 20 |
| Pellet damage | 12 | 12 |

The old `_ready()` set maximum health after the base class created current health and the health bar. An unscaled solo Drifter therefore had only 40 current HP. Non-unit health mutators, co-op durability or Ascension refilled from the old intended maximum of 68 and masked that initialization bug. Maximum health is now set before base initialization. Actual production spawn checks cover unscaled 88 HP, a 1.5 health multiplier giving 132 HP, and an additional 1.2 Ascension multiplier giving 158 HP.

Successive waves offset their spokes by half a step. This closes the preceding wave's incidental spaces between pellets rather than preserving static lanes forever. The existing stable wave ID determines the offset on both host and joiner; the network payload shape is unchanged. Each wave still omits one randomly chosen spoke. Its damage is limited to one pellet request per player per wave, preventing denser pellets from stacking into an instant kill near the origin. Different players have independent allowances, and a later wave restores each player's allowance.

The initial windup remains 60% of the interval (now 1.68s), and an unmodified wave expires after about 2.05s, before the next 2.8s emission. Undertow keeps its existing cap of two Drifters and half-interval stagger. Health, movement and cooldown mutators still use the existing production scaling path. Pellet outlines now follow their exact damage radius.

## Verification

Scoped coverage includes real health initialization and production spawning, alternating collision lanes, explicit gap safety, close-range overlap limits, both party members' independent damage, dead/ghost/protected players, packet loss and ordering, visual lifetime, mutator-adjusted configuration, and Undertow's spawn cap and stagger. A separate native ENet fixture sends both wave orientations and configuration through the production projectile receiver, checks replica authority, smooth local expansion and final clear. Native GPU captures show single waves and two staggered Drifters.

Passed: 376-script compile and world/network contracts; Drifter runtime and replication (87 checks); Undertow and layouts (571 checks); enemy visual profiles (106 checks); native ENet (13 host and 10 joiner checks); and three inspected native GPU frames on an RTX 4080. All gameplay automation used disposable projects and isolated user data.

Human playtesting remains necessary to assess the combined pressure with an actual build.
