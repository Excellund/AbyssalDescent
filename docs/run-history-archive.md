# Run History archive

Run History has outcome and solo/co-op filters. The search input and text matching were removed at the user's request. Filters combine; Reset clears them. The count describes the matching locally retained records, not lifetime totals. The existing 100-record storage cap is unchanged.

Selecting a run shows its final build plus a **Build journey** of rewards and rests in their recorded order. Repeated upgrades remain distinct choices. Starting rewards retain their known depth zero; missing or malformed depths stay unknown. Older records without a timeline say that decisions were not recorded. History does not infer unrecorded room routes, timings or power activations.

Changing filters preserves the selected record when possible and selects the first matching record otherwise. Reopening History selects its newest matching record. Empty results explain how to reset. Filtering and presentation never edit stored history. The shared damage recap also appears in saved runs when that evidence exists.

History fits the available physical screen area under the production 2560×1440 canvas. Short windows scroll the list and details while keeping filters and Back visible. A local MSDF font copy keeps text crisp when the panel compensates for canvas stretch; other screens' fonts are unchanged. This follows [Godot's Control scaling guidance](https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-property-scale).

## Search removal verification

The updated focused fixture passes 26 checks, with 454-script compilation and both contract guards. It checks the absence of a search input while retaining real filter/row signals, selected-record preservation, empty results, recorded depth zero, damage recap and unchanged stored history. The isolated project is `abyssal-validation-daa0c6adc00d45f68f0890bb30350cb1`.

The updated native renderer passes 101 checks across eight frames at actual captured sizes 960×540 and 1280×720. Populated history, scrolled build journey, empty filters and saved damage were visually inspected. The original frame manifest records requested window dimensions; the retained receipt records actual PNG dimensions. Exact logs, images and hashes are in `.feedback/practice-sandbox-20260912/history-evidence/`. No game persistence or History limit changed.

## Original verification before search removal

- `test_run_history_archive.gd`: 26 checks pass for combined queries, co-op detection, neutral endings, known depth zero versus unknown legacy depths, repeated upgrades, native filter/row signals, persisted recap display and persistence preservation. The same snapshot passes existing result identity (127) and menu fit/focus (211), plus whole-project compile and world/network contracts.
- Actual production-canvas Menu rendering: eight frames and 117 checks pass at 960 and 1280 window widths. Covers populated results, scrollable journey, saved final damage and empty search. Actual images were reviewed; the short 960 canvas scrolls content while preserving type size. The existing 16-frame outcome regression passed 315 checks before the final physical layout; final combined verification remains pending.

Final combined headless evidence: `.feedback/uncharted-descent-20260912/combined-tests.log`; isolated project `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-da6f94448f5941e08e2b4f810ff31941`. Production-canvas frames: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-4316d3a753744b5583da1fc109f80542/run_history_archive_frames`.
