# Practice damage recap

> Removed from Practice on September 13, 2026. This page preserves the removed feature's implementation and earlier verification only. Current [Practice](practice-sandbox.md) has no Recent damage tab or recap recording. Normal-run damage recaps remain available.

Warden Practice keeps the six most recent accepted damage events for the current attempt. Pause and the victory/defeat panel show the source, attempt time and actual HP lost, newest first. The actual accepted lethal event is marked as final. Retry starts an empty recap.

This is temporary Practice evidence. It never creates a run summary or writes a checkpoint, profile, History, Oath, telemetry or leaderboard record. The existing Practice isolation and Menu/Continue behavior remain unchanged.

## Capture and wording

`practice_arena.gd` connects the current Player's `health_changed` signal after applying the attempt's base Vessel package (initially Bastion). Player publishes its accepted `last_damage_event` before HealthState emits `health_changed` and `died`. Recording on that health signal makes the fatal entry available to the first defeat presentation; `damage_taken` is emitted later and is not used for this capture.

The scene consumes each positive `damage_sequence` once, accepts it only when its recorded `health_after` matches the observed health, and ignores other actors or pending scene transitions. Healing and direct health changes update the shared recap's ending-health evidence without replaying an earlier source. Retry clears both evidence and the actor sequence.

The existing `DamageRecap` helper validates and bounds entries, calculates HP loss from before/after health, and builds a fresh presentation using `DamageSourceCatalogue`. Warden charge, cleave and nova retain their existing distinct labels. Attempt time is pause-adjusted and no run depth is invented. An incoming amount of 500 against 130 remaining HP displays 130 HP lost; base Bastion's normal armor is likewise reflected in the actual loss. No damage formula, Warden behavior, player protection, shared run recorder or network path changes.

Only accepted damage at zero ending health is called final. A direct terminal health change cannot blame the preceding damage event. Recent rows are a bounded sequence, not a claim to total all damage over the attempt or explain why the player failed to dodge.

## Verification

The focused `test_practice_damage_recap.gd` fixture uses the actual standalone scene and accepted Player damage path. It stages damage and health for source labels, base armor, overkill, synchronous fatal presentation, duplicate notifications, healing/stale contexts, unrelated actors, pending Retry, six-entry eviction, immutable presentation, victory and reset behavior. The inherited real Main checkpoint setup and Menu/Continue flow compare saved file bytes and nonempty progression/launch preferences throughout.

`test_warden_practice_live_combat.gd` separately retains its unchanged base Bastion, active Warden, ordinary movement, Attack and Dash controls. Added assertions check that real accepted combat populates the bounded recap and that its final event matches the actual accepted source and remaining HP. This deterministic smoke is not human balance acceptance.

Run these through the disposable regression helper, together with the existing Practice lifecycle and shared damage-recap fixtures. The UI/native fixture separately checks the modal at actual 960/1280/1920 production canvas sizes, readable 18-pixel text, full six-row and empty states, keyboard Retry/Menu, resize and unchanged arena framing. Exact checked source hashes and logs accompany the prototype receipt.

## Prototype UI and native receipt

The modal presents at most six compact rows, each with the canonical source, actual HP lost, attempt timestamp and before/after HP. The fatal row has an explicit `Final` prefix as well as its accent color. An empty attempt says `No damage recorded this attempt.` The complete six-row modal is 660 pixels wide and 492 high at 960×540, and 500 high at 1280×720/1920×1080. All body text and controls remain at least 18 physical pixels. The existing sidebar, arena framing and action rules are unchanged; no scrolling is needed for six rows.

The UI takes its own deep copy of presentation data and compares recap content before rebuilding labels. Repeated unchanged updates preserve row instances and the user's current keyboard focus. Mode changes retain the original Resume/Retry/Menu focus behavior, and Retry removes stale evidence.

Initial focused UI validation passes 450-script compilation, both guards, 974 recap UI and 233 existing Practice UI checks. After adding the explicit final-row text, final validation passes 451-script compilation/guards and 974 recap UI checks in `abyssal-validation-b55517e377794999a42776ae0622cf0c`. Tests cover 0/1/6 rows in all modal states at 960/1280/1920, exact source/time/loss copy, immutable caller data, repeated presentation, label fit, all actions, inactive stale requests, focus release and unchanged sidebar/gameplay bounds.

The native fixture `render_practice_recap.gd` passes 20 frames and 524 checks in `abyssal-gameplay-render-3c4cf5e771874daea7174a6f096e357d`; all 20 PNGs were visually inspected. It instantiates the actual Practice scene and uses native Escape/Enter/Tab for Pause, Resume, Retry and Menu. Empty active/paused states use no staged damage. The full paused/result pages deliberately stage damage through the real accepted Player boundary, and the manifest explicitly labels that setup. Victory stages the Warden's remaining HP before an accepted player hit; fatal incoming 500 is displayed as only the actual remaining 52 HP lost. These captures establish presentation and boundary integration, not ordinary AI combat or human difficulty. The independent live fixture supplies unstaged combat evidence.

Native checks also cover a live 960→1280→960 resize, fixed Menu focus below all six rows, complete notice and action bounds, Retry's new full-health actors/empty evidence, unchanged arena framing, and saved-data preservation through the actual Menu return. No script, ObjectDB or retained-resource errors occurred. The known ignored Windows certificate-store diagnostic remains in the logs.

Exact source, frame and log hashes are retained in `.feedback/uncharted-descent-20260912/practice-recap-prototype-ui/receipt.json`. Two generated fixture UIDs were copied from the final headless snapshot; the parallel native import generated different UID metadata but ran identical GDScript contents loaded through explicit resource paths. This isolated prototype verification did not change primary source or the desktop executable. The reviewed implementation has since been integrated; subsequent integration and build receipts are recorded in the [workday journal](uncharted-descent-20260912.md).
