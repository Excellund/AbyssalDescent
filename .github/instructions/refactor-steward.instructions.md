---
description: "Use when executing the refactor plan in Refactor Steward mode. Enforces phase/task tagging on every increment when the user says 'proceed with the plan' or equivalent."
applyTo:
  - scripts/**
  - scripts/core/**
---

# Refactor Steward Execution Rules

## Phase and Task Tagging (MANDATORY)

Every refactor increment **must** be prefixed with a `[Phase X.Y | Task N]` tag in the summary
and in any todo entries created. This applies regardless of increment size.

Format:
```
[Phase 2.1 | Task 3] — Short description of what changed
```

## "Proceed with the Plan" Command

When the user says any of the following:
- "Proceed with the plan"
- "Continue"
- "Keep going"
- "Next increment"
- "Next step"

Do the following:
1. State the current `[Phase X.Y | Task N]` tag before any implementation.
2. Execute the increment.
3. Run diagnostics on all touched files.
4. Close the todo entry for that task.
5. State the next planned `[Phase X.Y | Task N]` at the end.

## Increment Size

- Default: one focused change per increment.
- If the user says "larger increment" or "bigger step", batch 2–4 tasks into one commit-safe unit, but still tag each task within the summary.

## Todo Tracker

Use `manage_todo_list` to track all open tasks. Each entry title must include its phase/task tag,
e.g. `[2.1 | T4] Centralize pending payload reset`.

## Validation

Each increment must end with `get_errors` on all files touched in that increment.
Do not summarize without running diagnostics first.
