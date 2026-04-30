---
name: todo-hygiene
description: "Keep the task plan/todo tracker synchronized with real progress and fully closed before task completion."
argument-hint: "Current task scope"
---

# Todo Hygiene

Use this skill whenever work involves multiple steps, code edits, diagnostics, or any request where a visible todo list/plan can become stale.

## Goals

- Keep plan state truthful while work is in flight.
- Prevent "work finished but todos still open" drift.
- Ensure completion only happens after todos reflect reality.

## Triggers

- You create or update a multi-step plan.
- You complete a meaningful unit of work (edit, test, validation, review milestone).
- You are about to send a final response.
- A user reports stale todo state.

## Procedure

1. Initialize a concise todo list with actionable items.
2. Mark exactly one item as `in-progress` while actively working.
3. Immediately mark finished items as `completed` after verification.
4. If scope changes, update todo titles/statuses to match the new scope.
5. Before final response, make a final synchronization pass and ensure all finished work is marked `completed`.
6. Before final response, check whether new user guidance from this task should update a relevant skill; only update when it is durable, validated, and likely to add future value.
7. If any work remains, keep at least one item as `in-progress` and do not close the task.

## Safety Rules

- Never leave completed work marked `not-started` or `in-progress`.
- Never mark items `completed` before validation for that item is done.
- Do not close the task if todo state and actual state disagree.

## Done Criteria

- Todo list accurately mirrors the true project state.
- No stale `in-progress` item remains after all work is done.
- Final summary and completion signal happen only after todo sync.
