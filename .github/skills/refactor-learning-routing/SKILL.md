---
name: refactor-learning-routing
description: "Classify and document refactor learnings in the correct skill instead of defaulting to code-quality. Use after Refactor Steward or any high-value refactor work."
argument-hint: "Refactor scope and validated learning(s)"
---

# Refactor Learning Routing

Use this skill at the end of refactor work to decide where durable learnings should be documented.

## Goal

Keep the skill system coherent:

- code-quality stays foundational.
- Domain-specific insights live in their domain skills.
- Process rules for completion and synchronization stay in workflow skills.

## Trigger

Run this checkpoint whenever a refactor yields a validated, reusable lesson.

## Routing Heuristic

For each candidate learning, decide ownership:

1. Foundational pattern across domains:

- Owner: code-quality
- Examples: duplicate guard consolidation, SRP boundaries, explicit contract preference.

2. Domain mechanic or balancing rule:

- Owner: domain skill
- Examples: encounter pressure tuning, objective recoverability, boon constraints, telemetry semantics.

3. Process/workflow rule:

- Owner: todo-hygiene or another workflow skill/instruction
- Examples: when to sync plans, when to update command phrases, release procedure checkpoints.

4. Agent customization or instruction behavior:

- Owner: agent-customization or relevant instruction file
- Examples: applyTo scope fixes, instruction precedence, command discoverability behavior.

## Selection Checks

A learning qualifies for skill updates only if all are true:

- Durable: likely to recur beyond this task.
- Validated: confirmed by diagnostics, behavior checks, or accepted by user direction.
- Actionable: can be written as a concise rule with clear "why".

If one-off or uncertain, store in session memory instead of a permanent skill.

## Update Procedure

1. List candidate learnings from the refactor.
2. Map each learning to an owner using the routing heuristic.
3. Update existing skill(s) first; create a new skill only when no owner fits.
4. Keep additions minimal: one rule + short rationale.
5. If command phrase support changed, update .github/command-list.md in the same change.
6. Mention routing decisions in final summary.

## Anti-Patterns

- Dumping all refactor lessons into code-quality.
- Adding subsystem-specific constants or one-file tactics as global rules.
- Creating a new skill when an existing domain skill already fits.
- Writing long narrative history instead of concise reusable guidance.

## Done Criteria

- Each durable refactor learning is documented in the best-fit owner skill.
- code-quality remains focused on cross-domain fundamentals.
- Any required companion docs (for example command list or instructions) are updated in the same change.
