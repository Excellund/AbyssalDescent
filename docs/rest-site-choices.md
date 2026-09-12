# Rest Site choices

Implemented on September 12, 2026 during the user-authorized feature session outside the feedback queue.

A Rest Site now offers **Recover**, plus up to two upgrades to Boons the player already owns. Choose one benefit per visit. Recover uses the previous healing formula, including the Bearing multiplier and Pilgrim's Tonic. Investing adds one ordinary permanent Boon level and forgoes that healing. The existing Boon description and level indicators show the actual improvement.

The pool contains only owned, uncapped Boons. Arcana, boss rewards, unowned powers and Riftlancer's unavailable Wide Arc are excluded. Offers do not repeat within a visit, and there are no Rest rerolls or extra Catalyst options. If no eligible upgrade exists, Recover remains available. At full health it explicitly says there is no health to restore and allows the player to continue.

## Why this addition

The previous `_enter_rest_site()` healed immediately and spawned the next doors. It offered no decision inside the site. Rest investment adds a build-dependent tradeoff using the existing capped upgrade system. A wounded player can recover; a healthy player can strengthen an established direction.

Two alternatives were considered. A post-clear **Press On** wave could trade the current Boon for an Arcana, but would need to delay the existing room-clear/progression transaction and establish a shared party decision about extra risk. A **Boon respec** could replace an unwanted upgrade, but the application system has acquisition effects and derived properties without a corresponding safe removal operation. Both expand the implementation and compatibility boundary substantially.

## Lifecycle and ownership

`scripts/core/rest_site_choice.gd` owns the bounded offer list and one resolution. Claims recheck the actual offered ID, ownership, character compatibility and stack limit. A choice invalidated after it appeared is removed without rolling a replacement; Recover remains available. Application goes through the existing player upgrade/healing methods. The visit becomes unavailable before callbacks run, so repeated selections cannot grant a second benefit.

World integration preserves current Rest route eligibility, the guaranteed pre-boss option, `rest_disabled`, progression counts and Rest-visit Oath accounting. Choosing an upgrade still counts as visiting a Rest Site. The normal reward catalogue, Mission bonuses and existing reward phases keep their behavior.

Each living co-op owner chooses independently. A spectator receives no benefit. A local player who dies while choosing has the modal closed and their barrier slot completed automatically; no obsolete card click is needed. Disconnects use the existing party departure path. Rest completion and advancement pass through the existing reward coordinator with the established shared run-provenance token and the entered Rest depth. Old-run, old-visit and mismatched-sender messages cannot resolve a later Rest. Ordinary reward RPC signatures are unchanged.

Doors and the between-room checkpoint wait for resolution. Continue restores the already chosen health/build and exact next doors; it does not reopen the choice or reapply its benefit. No new midroom save model or save-version migration is introduced. The ledger records an actual investment as an additional Boon level, and recovery as a Rest entry with the health restored. Recover never becomes a Boon in the recorded build.

## Presentation

The existing reward surface presents a compact Rest-specific layout: Recover followed by up to two cards titled `Upgrade <Boon>`. The three-card maximum is independent of reward-draft Catalysts. Keyboard/controller navigation and Build Details remain available. Recover is excluded from power comparisons; it shows current and resulting health instead. The door preview and glossary explain the choice before entry.

Rest text uses actual physical pixel sizing on the production 2560×1440 canvas. The later Farshot presentation pass extends that sizing and local font treatment to ordinary rewards. Closing Rest restores normal draft behavior, including Catalyst choices and rerolls; each mode retains its own responsive arrangement.

## Verification

All automation uses disposable projects and isolated profiles. The focused test entry point is `test_rest_site_choice.gd`; native co-op uses `test_rest_site_choice_enet.ps1`; presentation uses `render_rest_site_choices.ps1`.

- Initial gameplay verification: 307 focused Rest checks, 191 descent-presentation checks and existing Catalyst runtime checks passed; 426 scripts compiled and both world/network guards passed. Output: `%LOCALAPPDATA%/Temp/abyssal-validation-34af25d0762c41c299b55cbf1cff6602`.
- UI verification: 467 Build Details checks, 22,757 reward-layout checks and existing input-release checks passed in `%LOCALAPPDATA%/Temp/abyssal-validation-5832faa6d9b84bb485bb5ba2bd718c1f`. Final focused verification passed 39 Rest UI checks, including restored normal-mode Build Details typography, plus 26 archive and 231 glossary checks in `%LOCALAPPDATA%/Temp/abyssal-validation-27b924b4cd004e90908561b19a1641d0`.
- Native presentation: six frames and 160 checks passed at physical game viewports 960×540 and 1280×720, including every Boon's copy fit and actual keyboard selection. All six frames were visually reviewed. Final output: `%LOCALAPPDATA%/Temp/abyssal-gameplay-render-54043e3885e64d51b953da05a38ca4bd/rest_site_choice_frames`; retained copy under `.feedback/uncharted-descent-20260912/rest-site-choices/rest_site_choice_frames`.

- Native co-op: 44 host and 43 joining-owner checks passed in `%LOCALAPPDATA%/Temp/abyssal-enet-a7e2c6da60804564ac7829f761d6d9a3`. The two real Main processes establish the normal shared-run provenance handshake, choose different benefits, observe the exact resulting health/build on both peers, reject stale/spoofed phase messages, retire a late-death spectator without a click, handle an already-fallen owner and complete after a real pending-peer disconnect. The first native run caught joining-player recovery remaining local; both Rest outcomes now use the existing reward-build snapshot before completing the barrier.

- Final core rerun passed 307 Rest and 191 descent-presentation checks plus Catalyst runtime in `%LOCALAPPDATA%/Temp/abyssal-validation-c07423df021b4223a2c47598c4ef5892`. The wider run identified an inherited alternative-boss fixture that entered Rest and began its next test without resolving the new choice. That fixture now confirms Recover through the real UI.
- Remaining Rest-dependent regressions passed in `%LOCALAPPDATA%/Temp/abyssal-validation-0eca67511b2d47f1abc377ed83c4cd75`: 254 alternative-boss selection, 640 biome clarity, 1,246 biome room-context, 139 boss-atmosphere and 20 Shatter Pillar checks. All 427 scripts compiled and both world/network guards passed.
- Existing native room-layout/descent verification passed 602 host and 604 joining-owner checks in `%LOCALAPPDATA%/Temp/abyssal-enet-99a6233fde7d404883e2dc90f3dc097f`. It retains the replicated arena, positioned offer, boss, act/biome and uninterrupted music checks, and now establishes real run provenance and selects Recover on both owners after each boss. The first owner cannot open the waiting owner's next doors; both completed choices release the authoritative routes.

Human playtest should judge whether forgoing healing for one owned Boon level is a compelling tradeoff and whether repeated Rest investments compete fairly with combat routes.
