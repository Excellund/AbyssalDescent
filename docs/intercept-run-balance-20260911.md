# Intercept Run balance

Clearing the drone path now earns the full wave interval: the hidden 0.6-second low-enemy refill is removed. Base intervals change from 2.6–0.95 seconds to 3.4–1.8 seconds with depth; base wave batches change from 2–4 to 1–3. The opening has fewer chasers, chargers and shielders, and ordinary wave selection weights chasers more heavily than chargers. Bearing and multiplayer scaling still apply.

Unblocked traversal takes 30–24 seconds instead of 39–30 before existing pressure scaling. Enemies block within 64 pixels instead of 80; spawn exclusion is 124 pixels instead of 120, keeping new enemies out of the smaller block zone. The escort radius remains 240 pixels. Overtime still speeds the drone by 40%, but increases spawning by 15% instead of 30%. Node Shield and the permanent Boon are unchanged.

Playtest a low-damage build: clear a blocker, escort while repositioning, and confirm there is time before reinforcements. Leaving the escort ring and live blockers should still stop the drone. Repeat in co-op with either player escorting.

Verification: isolated compilation of 375 scripts plus world/network contracts, new Intercept balance fixture and existing room-entry suite pass with zero failures. Evidence: `abyssal-validation-7b2fafcee08d489b8e24d217d234797f`.
