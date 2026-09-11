# Pyre death-field visibility

Pyre's death field keeps its orange floor fill and complete boundary visible for its full active lifetime. An inset arc counts down the remaining time; the final 0.8 seconds brighten the boundary slightly instead of fading the danger away. The complete field disappears at expiry, before deferred node deletion.

The outer line follows the actual expanding damage radius. Lifetime, growth, damage, cadence, target selection, owner-death persistence and network authority are unchanged. The host remains responsible for damage; replicated fields remain visual only.

Playtest by defeating a Pyre, watching its field through the final second, and entering after the field disappears. The dangerous area should stay readable until the hard cut, with no faint damaging tail or lingering danger afterward. Repeat as a co-op joiner.

Verification on 11 September 2026: isolated compilation passed for 349 scripts and the Toll/Pyre suite passed 86 checks. Coverage includes a real final damage tick at the exact field radius, constant late visibility, immediate hiding at expiry, and cancellation during room cleanup. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-48d6a9660a6b413786b25aa6fcaca24d`.

The existing real ENet scenario passed 44 host and 34 client checks, including the replicated field's last visible moment and immediate expiry: `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-aaecb5c3276a4f7681d321a61426da03`. Nine GPU frames passed, including pixel comparisons that require the outer floor to remain readable halfway through, during the final second, and immediately before expiry. Those four expiry-sequence frames were visually inspected: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-b883789a50c74e5e839dc14165671f58/toll_pyre_frames`.
