# Practice

Open **Practice** from the main menu to set up a separate solo arena. Setup appears before combat starts. Every Vessel and registered power is available here, including choices you have not unlocked in a normal descent.

## Set up an attempt

- **Encounter:** choose a Vessel, named encounter, floor, Bearing and biome. The encounter description explains its goal; Practice generates its enemies, layout and objective from the selected settings. The list scrolls when the window is small. Choose Empty Arena for movement and build trials.
- **Build:** search by power name or effect, then choose Boons, Arcana, boss powers, Catalysts or Ascension. Numeric controls set stack counts or levels; zero removes a power. A supported Arcana can become Prismatic at its maximum level. **Clear build** removes the draft loadout.
- **Options:** turn enemy AI on or off, and choose whether to take damage. These options take effect with the next attempt.

**Start** creates the configured arena. Press **Escape** or click **Pause** to edit the next setup. **Resume** returns to the current fight with its existing actors and build; **Apply & restart** starts a fresh attempt with all draft changes together. The action buttons remain outside the scrolling tabs. During a Mission, the sidebar shows objective progress and live instructions, including the current Pulse rule or Signal exposure.

## Scope

Practice uses the game's actual player abilities, enemy behaviors, power limits and damage rules. Floor ranges from 1 to 25 and supplies the ordinary act/depth context for the chosen encounter. Combat rooms, Trials, Apex fights, Missions and boss variants use their real encounter rules. Practice runs one encounter at a time without reward drafts or route progression. Some progression choices affect drafts or Rest Sites and therefore have no effect here. These choices are shown as unavailable with a reason. Ascension requires Forsworn, Catalyst equipment keeps its normal slot limit, and incompatible power/Vessel combinations are explained in the editor.

Practice produces no progression, rewards, Oaths or History entries. Your saved descent and normal Vessel/loadout remain unchanged. Leave a multiplayer session before entering.

## Current verification

The retained focused UI suites pass **2,215 assertions** (294 Menu/panel and 1,921 editor), with 459 scripts compiled and both source guards passing. They cover all 37 encounter choices, the complete build catalogue, detached drafts, focus, and long active/paused Mission text at 960×540, 1280×720 and 1920×1080.

The native editor fixture passes **281 assertions across 46 frames** on the final source. It uses actual keyboard/mouse input for full build setup, Crossfire, Relic Recovery, Resume and Apply; it also waits for a real Pulse transition and checks its active and paused instructions. The corrected encounter popup is contained and scrolls to the focused choice at 960×540. A separate native Menu/Practice lifecycle run passes **272 assertions across 37 frames**. All 83 images were inspected.

The focused and Menu receipts preceded the final change that supplied a positive popup-width limit alongside its height limit. Their ordinary controls and lifecycle remain unchanged; the final editor native run and independent popup diagnostic verify that exact correction. These are interface and lifecycle checks. AI is deliberately disabled through the visible training option during editor captures; fatal damage and boss-warning captures are staged, so the images are not a balance result.

All verification uses disposable projects and isolated user data. Raw logs, source comparisons, frame manifests and images are retained in `.feedback/practice-encounters-20260913/ui-final-result.json` and `ui-evidence/`. The [encounter Practice worklog](practice-encounters-worklog-20260913.md) records runtime and normal exported-build verification. Earlier failed receipts remain separate.

## Historical sandbox verification — 12 September 2026

The following receipts document the preceding manual-roster version, including its now-removed Practice damage recap. They do not describe the current interface.

The dedicated UI fixtures pass 3,670 assertions covering setup, detached draft changes, full catalogue limits, keyboard focus, recap retention and physical layouts at 960×540, 1280×720 and 1920×1080. This scoped run compiled 459 scripts and passed both source guards.

Three native fixtures pass 1,122 assertions and produce 100 screenshots: 43 for the full configuration editor, 37 for actual Menu/Practice transitions, and 20 for the six-row damage recap. Every final image was inspected. The editor fixture uses keyboard and mouse events to choose a Vessel, floor, Bearing, mixed roster, Boon stacks, Prismatic Arcana, boss power, Catalyst, Ascension and AI option before Start, then verifies Resume preserves the current attempt and Apply creates the complete new setup. These are control, lifecycle and presentation checks; staged damage and warnings are not a balance result.

All runs use disposable projects with isolated user data. Raw logs, frame manifests, copied images and matching source hashes are retained in `.feedback/practice-sandbox-20260912/ui-final-result.json` and `ui-evidence/`. Earlier failed import/input-driver receipts remain separate. The [sandbox worklog](practice-sandbox-worklog-20260912.md) records the complete runtime, integration and exported-build verification.
