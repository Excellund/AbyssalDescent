# Mission reward readability

Mission rewards use the same physical-sized content and local font treatment as ordinary rewards and Rest. The temporary bonus now uses 18-pixel text, with an explicit gap below the title. Existing bonus descriptions, duration, offers and grants are unchanged.

The native review covers all six real bonus definitions: Fortified, Overcharge, Hunter's Focus, Relay Boost, Node Shield and Combo Relay. Each is shown with three and four actual catalogue Boons at 960×540, 1280×720 and 1920×1080. At each size, an ordinary keyboard decision also grants the permanent Boon and the displayed three-encounter Combo Relay through World.

## Evidence

- `render_mission_rewards.gd`: 36 native frames, 1,179 checks, zero failures. Actual Main with the production 2560×1440 canvas; the cleared Mission and offer order are staged. This is UI and grant-path evidence, not combat or balance acceptance.
- Final disposable project: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-d267a5054e0b41e19631604126d0ccc8`. Frames, manifest, final log and matching hashes for the six relevant source files are retained in `.feedback/uncharted-descent-20260912/mission-rewards/`.
- Representative native frames inspected: Combo Relay's four-card view at 960 and 1920, Node Shield's three-card view at 1280, and Fortified's three-column view at 960. Complete content, font size, card/title/bonus separation and visible actions are checked in every frame.
- The registered `test_reward_selection_layout.gd` now includes all six bonus headers with three/four cards across its five window-size cases. Its expanded run passes 31,209 checks, alongside 39 Rest UI and 224 Mission bonus checks, 445-script compilation and both guards. Disposable project: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-6bdb987025954995b14561914ce36568`; log: `.feedback/uncharted-descent-20260912/mission-reward-layout-second-tests.log`.

The first native receipt remains in `mission-rewards-native-first.log`: all 36 frames rendered, with twelve assertions identifying a two-pixel title/banner rectangle overlap at 1920. The actual glyphs did not collide in the inspected frame; the explicit spacing removes the ambiguous overlap. The initial focused import separately emitted Unicode surrogate errors despite a zero exit code and was correctly rejected by the strict helper. All 884 source/frozen GDScript files decoded as strict UTF-8; a fresh-copy follow-up imported and compiled cleanly. This does not claim the intermittent engine import diagnostic was fixed.

To repeat native verification, use `.github/scripts/render_gameplay_fixture.ps1` with an isolated validation project, fixture `res://scripts/tests/render_mission_rewards.gd`, frame folder `mission_reward_frames`, `-ExpectedFrames 36 -PreserveProductionCanvas -MaxFrames 10000`. No unattended test uses the player's real profile.
