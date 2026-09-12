# Pyre death-field visibility

Pyre keeps its full orange floor and damage boundary readable throughout its active lifetime. The inset arc counts down; the final 0.8 seconds brighten the boundary slightly. After damage ends, the complete floor and boundary dissolve over 0.22 seconds with a smooth fade instead of disappearing instantly. The countdown ends with the damage.

Lifetime, growth, radius, damage cadence, owner-death persistence and authority are unchanged. The fade is cosmetic and cannot damage, even with an overdue tick. Replicated fields use the same fade and remain visual only. Room cleanup still removes the field immediately.

Playtest by defeating a Pyre and watching the last second. The full danger footprint should remain visible, then fade rapidly; entering during the fade should be safe. Repeat as a co-op joiner.

Verification: 374 scripts compile; Toll/Pyre passes 93 checks. Real ENet passes 44 host and 34 client checks including the complete replicated fade. Ten native GPU frames pass; final-active, half-fade and expired frames were inspected. Evidence: `abyssal-validation-4dd3d21e88974c8c917bf1523cf6ae8c`, `abyssal-enet-6bf7f7f4b87f443b8196b0ac75d78136`, `abyssal-gameplay-render-e616a2a70563467c87b1b57e5eff6b12`.
