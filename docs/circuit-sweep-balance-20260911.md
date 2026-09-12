# Circuit Sweep balance — 11 September 2026

Feedback: Circuit is too hard (`FB-6cb9f47a6d0743ff`).

Circuit still asks players to capture three nodes in order, retains its Surge enemies and Relay Boost reward, and enters overtime at its existing deadline. The change gives players room to dodge while capturing and time to move after clearing pursuers.

## Changes

- Capture radius: 100 → 120 pixels. Capture time is unchanged. The physical capture test, objective overlay and biome exclusions all use the same radius.
- Capture lost outside the ring: 0.2 → 0.1 seconds per second. A dodge outside preserves more earned progress.
- Opening roster: fewer chargers and archers, with slower chaser growth. At Delver depth 5 this is 13 → 9 enemies including its Lurker; at depth 12 it is 22 → 17.
- Reinforcements at Delver depth 5: three every 1.80 seconds → two every 2.45 seconds. At depth 12: five every 1.38 seconds → four every 2.10 seconds. The interval now bottoms out at 1.25 rather than 0.80 seconds at great depth. Bearing and party scaling remain.
- Live crowd budget before Bearing scaling: base 8 → 7, growth 0.35 → 0.30 per room, ceiling 18 → 14. The existing minimum and Bearing multiplier remain.
- Removed Circuit's hidden half-second pressure-floor refill. Defeating pursuers now earns the remaining scheduled interval; it no longer immediately floods an emptied arena. Overtime still shortens the interval and adds one enemy to each wave.

## Verification

The isolated `test_circuit_sweep_balance.gd` fixture enters the actual mission, checks all four Bearings across four depths, empties a live crowd and waits for the next scheduled wave, captures from the enlarged outer ring, dodges out and returns, reaches overtime, and finishes all three nodes into the mission reward flow. Existing room-entry and biome-context suites cover objective replication setup, live co-op eligibility and hazard clearance around mandatory node geometry.

Passed: 375-script compile, world/network contract checks, Circuit balance (63 checks), room entry (104 checks), and biome room context (1,246 checks), all with isolated user data.

Human playtesting remains necessary to judge the challenge with a real build; automated checks establish the pacing and capture rules.
