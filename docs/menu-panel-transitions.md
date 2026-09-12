# Menu panel transition follow-up

The new Enemy Guide and Run History exposed two concrete Menu integration defects. Opening either panel, pressing Escape during its entrance and immediately reopening it let the old exit callback hide the newly reopened panel. Both that panel and the main menu then remained hidden. Separately, resizing the physical window while the fixed 2560×1440 canvas stayed unchanged left their physical scale stale; History became about 1,237 pixels wide at 1280 instead of its intended 980.

Menu now owns each panel's tween, resting position and transition generation. Reopening retires the previous transition before starting the new one. Layout changes retire old targets and complete an intended outgoing hide before centering panels again. A deferred viewport-size notification updates physical sizing even when the logical canvas has not changed. Scene exit also releases transition references. Existing panel styling, focus rules and navigation callbacks remain in place.

## Verification

The default runner includes `test_menu_panel_transitions.gd`: 66 checks use the actual Menu, elapsed animation time, Escape events and physical window resizing. They cover settled navigation, rapid reopen, resizing during entry and exit, settled resizing, character-selection return and an actual Practice roundtrip. They do not manually invoke layout after resizing.

The focused disposable snapshot `abyssal-validation-a70c0f90896642d89261d00c8c1a9fb3` passes 448-script compilation, both guards, those 66 checks, Practice UI 233, checkpoint Menu 72 and panel fit/focus 211. Its fifth suite caught the separate Menu audio handoff failure before the audio owner's final guard correction. That original failure remains retained. The [audio follow-up](menu-music-startup.md) records its final 19 checks and real detach/timeline verification.

Native reproduction used actual Menu callbacks, native Escape input and real process timing with production canvas stretch. The initial 16 frames preserve both disappearing panels and the stale resize geometry. The corrected 16-frame replay keeps both reopened panels visible and restores the expected 1280 bounds: Guide `(24, 24, 1232, 672)` and History `(150, 20, 980, 680)`. Both corrected rapid-reopen images and both settled resize images were visually inspected. The probe deliberately invokes the normal open callbacks directly; it is not evidence of mouse automation or a human playtest.

After the final audio guard landed, the existing actual Menu/Practice native fixture passed all 251 checks and 34 frames at 960×540, 1280×720 and 1920×1080. It exercises normal/Continue/checkpoint-error menus, keyboard scrolling, party denial, Pause, Resume, Retry, staged victory/defeat and return focus. The repeated inspection covered normal Menu at 960/1920, returned Menu at 960 and Practice active/paused/defeat at 960. Earlier [Practice verification](warden-practice-ui.md) records the complete original visual review and distinguishes staged results/warnings from live combat.

## Retained evidence

`.feedback/uncharted-descent-20260912/menu-panel-transitions/` contains:

- `original/`: 16 original diagnostic frames, observations, probe source and raw logs, copied before overlaying the correction.
- `fixed/`: 16 corrected frames, geometry observations, probe source, logs and a hash receipt.
- `focused-logs/`: the complete focused logs, including the separate pre-fix audio failure.
- `practice-followup/`: the 34 final native frames and strict process logs.
- `final-receipt.json`: source/image/log hashes, precise checked snapshots and limits of the repeated visual review.

The focused and corrected-transition snapshots differ from the final Menu only in the audio owner's later `_exit_tree` playback guard and its explanatory comment. The final Practice replay's Menu hash matches current production. No script errors, ObjectDB leaks or resource-in-use warnings appear in the corrected native runs; the helper's known ignored Windows certificate-store diagnostic remains visible. The full integrated gate and corrected normal executable receipt are recorded separately by the workday delivery task.
