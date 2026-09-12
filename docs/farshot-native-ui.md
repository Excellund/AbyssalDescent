# Farshot native UI verification

The dedicated native fixture uses the actual Main scene and its reward, Rest and Build Details controllers in a disposable project with isolated profile data. It preserves the production 2560×1440 canvas and resizes the actual game window to 960×540, 1280×720 and 1920×1080. Physical text measurements multiply the control's real canvas transform by the root stretch transform; checking only the configured font size would miss unreadable text under canvas stretching.

For each window, the fixture captures unowned Farshot and both upgrades in three-card and four-card ordinary offers, then the owned level 1/2/3 Build Details with its rules expanded. It also captures the real Rest offer at owned levels 1 and 2. These are 33 Farshot frames. Two additional four-card frames at 960×540 exercise dense existing Arcana and boss descriptions, for 35 frames in total. The ordinary catalogue offer order, prerequisite builds for those dense cards and Rest health are staged to make these views repeatable. Farshot levels themselves are claimed through keyboard confirmation and the actual World reward handler. Combat is idle; these captures demonstrate UI behavior, not combat viability or balance acceptance.

The dense Arcana frame offers Aegis Pulse level 2 and Blast Drive, Razor Orbit and Returning Crescent level 3. The boss frame offers Warden's Verdict, Lacuna Well, Faultline Seal and Shatterwake level 2 with an actual boss epitaph. These views check the shared layout's tightest wrapping and line spacing with mixed bold keywords and ordinary text, beyond Farshot's shorter sentence. The complete headless roster remains the broader combinatorial check.

The assertions check the displayed +10/+20/+30 values, distance 160, current body and damage-impact timing, separate level diamonds, full body wrapping, physical text size of at least 18 pixels, and physical window bounds. Expanded Build rules also retain contact-time and copied-effect scaling and explain that Effigy or Projectile origins do not set the distance. Four-card Right/Down/Left/Up navigation, Tab inspection and Escape return preserve the selected unclaimed offer and native keyboard focus. Keyboard confirmation grants exactly one level, repeated confirmation grants no duplicate, and both ordinary and Rest eligibility exclude a capped Farshot. Real Rest Recover preserves the alternative Farshot level.

The renderer advances reveal timers and finishes the real room-entry banner fade before static inspection captures. It allows 1.01 physical pixels of trailing label padding at the scroll edge because integer scroll offsets acquire rounding under the production canvas transform. Text content and its title are separately checked. Windows can report unstable OS mouse coordinates for the hidden offscreen window, so keyboard return checks use the immediate selection and actual focused card, rather than treating a later mouse-hover sample as evidence of keyboard focus loss. The manifest records those measurements for review.

Run after producing any isolated validation project with the regression helper:

```powershell
& .github/scripts/render_farshot.ps1 -ValidationProject 'C:/Users/mikel/AppData/Local/Temp/abyssal-validation-<id>'
```

The wrapper reuses `render_gameplay_fixture.ps1`, copies current source into another disposable project, imports there, and creates an offscreen native GPU window with dummy audio. It writes `farshot_frames/manifest.json` and PNGs there. The renderer is intentionally separate from the default headless regression batch because it requires native rendering. No desktop playtest executable is replaced.

The final native run on 2026-09-12 passed **35 frames, 1,039 checks, zero failures** on an NVIDIA GeForce RTX 4080. The renderer, reward UI, Build Details, shared font helper and power registry matched the tested source hashes. The renderer's generated UID was copied from that import (`uid://7uvkeffnvhpo`).

| Actual window | Ordinary / Rest body | Build body / rules | Ordinary layout |
|---|---|---|---|
| 960×540 | At least 18 physical pixels | 18 physical pixels | Three columns or a four-card 2×2 grid |
| 1280×720 | At least 18 physical pixels | 18 physical pixels | Three rows or a four-card 2×2 grid |
| 1920×1080 | At least 22 physical pixels | 18 physical pixels | Three rows or a four-card 2×2 grid |

Visual review covered the narrow ordinary offers, Rest upgrades, expanded owned rules, larger layouts and both dense four-card cases. The complete sentences and numerical lines fit; mixed bold keywords and normal text remain readable with the short-window line spacing. Build normal text is crisp at the compensated canvas scale. The Rest title/description gap is now measured from the actual title minimum height. The dense boss epitaph and action share a rectangle boundary; their measured transform intersection is 0.0000305 physical pixels, below the fixture's 0.01-pixel precision tolerance, and their visible text is separated.

The complete native console receipt is `.feedback/uncharted-descent-20260912/farshot-native-complete.log`; the persisted manifest is `.feedback/uncharted-descent-20260912/farshot-native-manifest.json`. All PNGs and native logs are in `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-f06de1723bdd4acbb2972d2af6cc3270/farshot_frames` (native logs are in its parent). Representative frames are `offer_level_1_3_choices_960.png`, `offer_level_2_4_choices_1280.png`, `rest_level_3_1920.png`, `build_level_3_960.png`, `dense_arcana_four_960.png` and `dense_boss_four_960.png`.

The accompanying shared-layout headless run passed 28,419 roster/layout checks, 467 Build inspection checks, 39 Rest UI checks and the reward-input regression. Its receipt is `.feedback/uncharted-descent-20260912/reward-physical-layout-third-tests.log`. Farshot combat boundaries, co-op transport and persistence are documented separately in [Farshot](farshot.md).
