# Ordered game feedback board

Open **Feedback Board.cmd** in the repository root to use the local browser board. It starts a hidden Python server on this computer and reuses an existing server for the project. The board starts empty. Adding feedback places it at the bottom; drag items or use **Move up** and **Move down** to change the order. Adding or ordering feedback never starts development.

Each item has a stable ID, title, notes, and optional build ID and source link. The board shows the numbered queue, next available item, current development claim, blocked reasons, items awaiting playtest and completed history. You can edit, archive, restore and export feedback. Notes and links are rendered as text.

## Choosing and completing work

The user's saved order is the priority authority. When asked to develop next, continue the existing claim before selecting another item. Otherwise claim the first available queued item, skipping blocked items while preserving their positions. The claim records its owning task; another task cannot take it or start duplicate work. An explicit request can select a named item without changing the saved order. Agents never reorder the queue without an explicit user instruction.

After implementing and verifying a fix, mark it **Awaiting playtest**. The next queued item can then be developed. User acceptance marks it **Done**; reopening returns it to the bottom, where the user can reorder it. An empty queue or a queue with only blocked items reports that no work is available. Historical plans are not automatically imported or selected.

The [project instructions](../../AGENTS.md#ordered-game-feedback) and [development pipeline](../../docs/development-plan.md) retain the existing gameplay verification, checkpoint and normal playtest delivery requirements. Updating the board does not commit, export or publish a game build.

## Running and agent commands

Requires Python 3.10 or newer; the server and CLI use only its standard library. From the repository root:

```powershell
python tools/feedback-board/board.py launch
python tools/feedback-board/board.py list
python tools/feedback-board/board.py next
python tools/feedback-board/board.py add --title "Reward text is hard to read" --notes "Describe what happened and what was expected" --build-id "dev-example"
python tools/feedback-board/board.py claim --owner "task-reference"
python tools/feedback-board/board.py status FB-0123456789abcdef awaiting_playtest --owner "task-reference"
```

Use the actual ID returned by `add` or `list`, and one stable task reference throughout development. `list` and `next` return JSON. `next` inspects selection without claiming or starting work. `add` also accepts `--source-link`. `edit ID` accepts the title, notes, build ID and source link fields. For a specific item explicitly requested by the user, use `claim --owner "task-reference" --id ID`. If your task already owns a different item, first release your own claim with `status CURRENT_ID queued --owner "task-reference"`, then claim the user-selected item. This preserves the saved queue order. Do not release or take another task's claim; report its owner instead.

When the user explicitly requests parallel development, each separate task can claim its assigned queued item with `claim --owner "task-reference" --id ID --parallel`. The flag requires an explicit ID, preserves other claims and queue order, and still allows only one active claim per task and one owner per item. Ordinary claims keep the existing sequential behavior; a task can resume its own active claim even when another active item appears first. `list` includes every claim, while `next` and the priority banner show the first active item in saved order. Blocked items must be unblocked before they can be claimed.

All tasks and the browser server must use the updated board tooling before multiple claims are created. Older copies reject multiple active claims, so restart an already-running browser server after this update. If worktrees have older tooling, invoke the updated `board.py` by its absolute path in the primary checkout until the update reaches those branches.

`status ID STATUS --owner "task-reference"` updates progress. Use `blocked --reason "Waiting for a reproduction"` to record a blocker and release the claim; unblock with `queued`, then claim again before resuming work. Use `--user-override` only for explicit user actions such as accepting (`done`) or reopening (`queued`) an item. `reorder ID... --user-ordered` changes priority only when the user has ordered it and must include every queued and blocked ID exactly once. Mutating commands accept `--revision N` to reject changes since a specific inspected revision. Run `python tools/feedback-board/board.py --help` or add `--help` to a subcommand for its accepted arguments.

Use `--project "C:\path with spaces\checkout"` before the subcommand to address a different checkout. The PowerShell launcher at `tools/feedback-board/start.ps1` accepts `-PythonPath` to select an interpreter and `-NoBrowser` to start or reuse the server without opening a tab. `launch --no-browser` does the same; `serve` runs the server in the foreground. Both server commands accept `--port`; the default `0` chooses an available port. The server binds only to loopback and serves only board assets.

## Local data and recovery

The authoritative file is `.feedback/board.json` in the **primary repository checkout**. Linked Git worktrees resolve the same primary checkout, so branches and tasks share one list. The data is ignored by Git and is not included in game imports or exports. It is local to this computer and is not pushed to GitHub. Use `--data-dir` only for isolated tests, never for ordinary project work.

Browser and CLI changes use the same storage layer. Writes are serialized and atomic, stale revisions are rejected, and save errors remain visible. Refresh after a conflict before retrying; the board must not silently overwrite another task's edit. A recovery backup retains the previous valid state. Do not edit `board.json` directly.

Use the board's JSON export and restore controls for portable backups, or `export --output "feedback-backup.json"` and `restore FILE` in the CLI. Export requires a new output filename; without `--output`, it prints the JSON. Restore validates the file before replacing data. `recover --revision N --yes` restores the retained recovery backup; use the board's current revision for `N`, or `-1` when the current board is corrupt. Restoring a JSON export over a corrupt board also requires `--revision -1`. Inspect/export current data before replacing it when possible. Recovery is an explicit user action; the app reports malformed data and failed saves instead of resetting the list.

## Validation

Run the focused suite from the repository root:

```powershell
python -m unittest discover -s tools/feedback-board -p 'test_*.py'
```

Tests use isolated temporary stores. They cover order and transitions, claim ownership, blocked selection, persistence, concurrent writers, stale revisions, malformed data, failed saves, recovery and shared worktree resolution. For browser validation, start the server with a temporary `--data-dir` and check forms, drag ordering, keyboard move controls, visible save errors, export/restore, and launcher reuse with spaces in the project path. Never point automated tests at the real feedback store or the player's Godot profile. Verify the tooling/data exclusions whenever performing a game export.

Verified September 10, 2026: all 39 Python tests and the JavaScript syntax check passed, including explicit parallel claims, claim ownership, independent completion and release, preserved order, concurrent claim retries, and CLI/HTTP interoperability. Earlier in-app browser checks passed for adding/editing feedback, keyboard and pointer reordering, blocked-item skipping, claims, awaiting playtest, acceptance, reopening, archiving, concurrent-edit rejection with the draft retained, JSON export/restore, and recovery from a deliberately corrupted temporary board. The Windows launcher reused its server from a path containing spaces. The delivered project queue was initialized empty; test feedback stayed in temporary storage. Game package contents remain a check for the next game-export checkpoint.
