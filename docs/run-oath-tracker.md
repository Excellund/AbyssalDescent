# Current-run Oath tracker

The in-run view explains which existing Oaths this vessel, Bearing and launch setup can attempt. It does not change requirements, complete Oaths, claim rewards or write progress. Broken and unverified attempts remain visible. Already-earned Oaths use the registry's compatibility aliases, including equivalent older Journey completions.

## Reading the states

| State | Meaning |
|---|---|
| Earned | This profile already records the Oath or its equivalent historical completion. |
| Condition achieved | The existing evaluator recognizes the recorded encounter milestone. The award is persisted when this run ends. |
| On track | The existing evaluator would recognize the Oath if this run cleared with the current evidence. A clear is still required. |
| Pending | A requirement can still be completed, such as choosing one Arcana, recording a qualifying boss defeat or completing Hold the Line with full control. |
| Broken | Recorded irreversible evidence violates the requirement: Attack, Dash, damage, a Rest visit, an expired time limit, multiple Arcana, or an earlier lower Bearing. |
| Unavailable | This run uses another vessel, Bearing or launch setup; it is a debug run; or a required clear is no longer possible because the run ended. |
| Unverified | Required earlier history or authoritative evidence is missing. This is not a claim that the player has failed. |

Attack counts the deliberate Attack action, including a miss. Grounded counts accepted normal Dash starts. Damage counters retain accepted health loss through healing and revival. Both Recover and upgrading a Boon at a Rest Site count as visiting that site. Repeated Arcana entries and upgrades do not become additional distinct Arcana.

An empty Arcana build is pending because one Arcana can still be chosen. A missing boss no-hit ID does not prove that another qualifying encounter is impossible. A failed Hold the Line encounter does not mark the entire run broken. Untouched Crowns shows distinct required boss defeats, and still requires a clear.

## Continue, co-op and time

The adapter reads the current recorder and its restored tracker. Modern Continue retains action, damage, Rest, setup and minimum-Bearing evidence, plus elapsed run time. Legacy checkpoints without that evidence remain playable but cannot be presented as zero-use or flawless whole runs. Explicit older Forsworn verification still works through the evaluator. Any-Bearing encounter milestones can still be recorded after an older Continue. A known violation remains broken even if earlier history is unknown; its counter identifies the recorded portion rather than claiming a complete historical total.

Co-op damage uses the local peer's ledger, never the party aggregate. The host uses its local peer's boss no-hit map. Arcana evidence comes from the actual locally owned actor; a missing owner does not substitute an ally or empty build. Attack, Dash and frozen Catalyst/setup evidence remain local to the recorder's input owner.

Joining peers do not receive authoritative completed boss/Hold evidence during the run. Their independent paused clock also does not certify the host's final elapsed duration. These boss, Hold, Crowns and timed-Oath rows say that the host confirms the requirement at run end; they do not show a misleading zero or replica-derived success. Existing terminal outcome delivery still awards using the authoritative peer summary. No new network messages are introduced.

Solo and host elapsed time comes from `get_run_elapsed_seconds()`, including its paused intervals and saved Continue offset. The adapter explicitly preserves zero elapsed seconds rather than allowing the terminal summary builder's wall-clock fallback. Against the Clock follows the existing strict threshold: the recorded integer duration must be below 480 seconds. A joining peer's header time is local elapsed time, not a prediction of the timed award.

## Interfaces and ownership

`scripts/progression/run_oath_presentation.gd` exposes:

```gdscript
static func presentation(summary: Dictionary, profile: Dictionary,
        evidence: Dictionary = {}) -> Array[Dictionary]
```

Each row contains `id`, `label`, `description`, `state`, `detail` and `relevant`. Verified numeric progress may include `current`, `target` and a ready-to-display `progress_text`, such as `Attack actions: 3` or `Elapsed: 7:50 (must be under 8:00)`. Unverified rows omit counters and progress text so restored zeroes cannot look like complete evidence. `relevant` describes the current character/Bearing/launch setup, independently of whether the attempt has since broken. UI can filter by it, then optionally include rows with state `earned`.

The helper evaluates deep copies with the actual outcome and a projected clear using the existing Oath evaluator. It never applies the result. Deep-copying the profile also isolates Meta getters that initialize missing dictionaries. Negative explanations use only known, valid evidence; evaluator failure alone is never treated as a broken attempt.

`RunSummaryRecorder.get_live_oath_presentation()` returns `character_name`, `difficulty_label`, `elapsed_seconds`, `is_joiner` and `rows`. It snapshots existing facts without finalizing a run, reconciling combat events, initializing peer ledgers or saving a profile. Pause/UI integration owns when the snapshot is refreshed and how earned rows are displayed.

## Verification

The dedicated `test_run_oath_presentation.gd` is registered in the isolated gameplay runner. It checks evaluator parity across every registered Oath and Bearing, relevance, legacy completion aliases, malformed/missing evidence, known violations, future encounter possibilities, joiner authority, input/profile purity, local peer damage and boss attribution, actual owned Arcana, pause-aware zero time and Continue restoration. Existing Oath tracking and movement fixtures verify the underlying award and accepted-input contracts.

Final core validation passed 1,286 projection checks, 1,014 existing Oath tracking checks and 199 accepted-movement checks. All 432 GDScript files compiled and both world/network contract guards passed. The validated helper, recorder and fixture hashes match the source; the new script UID companions were copied from that import. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-f2ebc99c082f4fe8b58ea58656adeb4a`, with the consolidated log at `.feedback/uncharted-descent-20260912/run-oath-projection-complete.log`.

Independent review found that the roster's owned-player lookup can fall back to a living ally. The adapter now requires both the resolved local peer ID and actual local control before projecting that actor's Arcana. The final fixture exercises the real fallback helper, a mismatched peer ID, and a missing owner. No further actionable core findings remained after review.

Pause/UI render receipts are recorded separately with the task's verification evidence. Automation verifies truthfulness and interaction; it does not assess whether the chosen Oaths are satisfying challenges.

## Pause and native presentation

Open Pause, then **Oaths This Run**. The view starts with relevant unearned goals; its checkbox includes already earned goals. Back and Escape return to Pause with the Oaths action focused. A second Escape resumes the run. Tab reaches the filter and individual goals, scrolling the focused card into view; cards have a visible focus border. Viewing and filtering do not award or save anything.

The panel compensates for the production 2560×1440 canvas stretch so its body text remains 18 physical pixels at smaller game resolutions. The main Pause actions also remain 18 pixels and the checkpoint warning wraps within its panel. Options, Glossary and Oaths hide and disable the underlying main actions, then restore their opener's focus. A subsequent [Options readability follow-up](pause-options-readability.md) gives the settings screen matching physical text, a scrolling body and fixed navigation while preserving its callbacks.

The isolated native fixture `scripts/tests/render_run_oath_tracker.gd`, launched through `.github/scripts/render_run_oath_tracker.ps1`, instantiates actual Main and retains World's real recorder provider for the ordinary ongoing-run captures. It drives Escape, Tab, Enter and Space through the game's native GUI input. Additional captures pass explicitly labelled staged broken, earned/achieved, legacy and joining-peer summaries through the real Oath projection. Staged profile data is never saved; the joining presentation is not a live-network test.

Final verification passes **18 native frames and 1,775 checks** at 960×540 and 1280×720 using the production canvas on an NVIDIA GeForce RTX 4080. All 18 frames were inspected. Body copy, headers, the checkpoint notice and focused rows fit; focus borders and both checkbox states are visible. Native navigation reaches the final goal, stays inside the modal, restores focus on Back/Escape, and retains existing Options/Glossary return behavior. The import and GPU logs contain no script errors, ObjectDB leak warnings or resources-in-use errors; only the helper's known ignored Windows certificate-store message appears.

Initial visual review found underlying Pause actions exposed around the legacy Options panel and a card focus StyleBox that PanelContainer did not draw. The final implementation hides/disables the underlying actions and changes the card's actual panel style on focus. The completed filter also received outlined local icons after its initial unchecked state proved too dark. Initial captures remain retained rather than overwritten.

Evidence is retained under `.feedback/uncharted-descent-20260912/run-oath-tracker/`: `run_oath_tracker_frames/`, `final-native-snapshot.json`, `final-native-result.json`, final import/render logs and the initial captures. The consolidated run log is `.feedback/uncharted-descent-20260912/run-oath-native-final.log`. The disposable project is `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-246b904f15d642dd99756505bfa37874`; its Oath UI, Pause controller, shared font, projection, recorder and renderer hashes matched the source at verification. This is presentation and interaction evidence, not the workday's final build-delivery gate.
