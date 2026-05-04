---
name: code-quality
description: "Apply foundational code quality principles that improve readability, safety, and maintainability across the codebase."
argument-hint: "Area of code being reviewed or refactored"
---

# Code Quality

Use this skill for broad, cross-cutting engineering quality decisions. Keep it focused on durable fundamentals, not one-off outcomes from a specific refactor.

## Scope Guard

What belongs here:

- Principles that apply across many systems and domains.
- Reusable guidance that lowers cognitive load for future contributors.
- Refactor patterns that are language- and feature-agnostic.

What does not belong here:

- Encounter-specific, objective-specific, or telemetry-specific tuning rules.
- Single-incident fixes tied to one subsystem.
- Guidance better owned by a domain skill.

If a new learning is domain-bound, update the owning domain skill instead of appending it here.

## Core Principles

### 1. Keep Logic DRY

Avoid duplicated behavior across files and modules.

Why it matters:

- Duplicate code drifts and increases bug surface area.
- Fixes become slower and riskier when applied in multiple places.

How to apply:

- Extract shared behavior into focused helpers.
- Consolidate repeated guard logic and repeated control-flow scaffolding.
- Prefer one canonical implementation per behavior.

### 2. Reduce Cognitive Load

Optimize for code that is easy to read and reason about.

Why it matters:

- Clarity reduces onboarding time and review risk.
- Explicit code paths are easier to debug and evolve.

How to apply:

- Keep methods short and purpose-specific.
- Name methods by intent, not mechanics.
- Make phase ordering explicit in high-churn update loops.

### 3. Keep Responsibilities Narrow

Functions and modules should have one clear reason to change.

Why it matters:

- Mixed responsibilities create hidden coupling.
- Narrow ownership reduces blast radius when changing behavior.

How to apply:

- Split orchestration from implementation details.
- Keep one runtime owner per behavior.
- Remove mirrored or legacy paths after extraction.

### 4. Prefer Explicit Contracts

Use typed, direct contracts for stable internal interactions.

Why it matters:

- String-based dispatch or property-name access hides ownership.
- Runtime introspection weakens refactor safety.

How to apply:

- Prefer direct method calls over dynamic dispatch for internal code.
- Prefer stable actor APIs over ad hoc property string access.
- Keep dynamic boundaries explicit and narrowly scoped.

### 5. Minimize Hidden Shared State

Avoid implicit state coupling across unrelated code paths.

Why it matters:

- Hidden state makes behavior order-dependent and fragile.
- Temporary write-and-restore patterns are easy to break later.

How to apply:

- Pass required context explicitly.
- Centralize mutable state ownership.
- Avoid temporary shared-state swapping to influence helper behavior.

### 6. Refactor Incrementally

Make small, reversible steps that preserve behavior.

Why it matters:

- Incremental changes are easier to review and validate.
- Smaller diffs reduce regression risk.

How to apply:

- Move logic first, then rename or simplify.
- Validate after each step.
- Keep feature changes separate from structural refactors.

## Routing Rule For New Learnings

Before adding any new rule here, run this check:

1. Is the learning broadly reusable across multiple systems?
2. Is it not tied to one feature domain?
3. Would future contributors expect to find it in a general quality skill?

If any answer is no, route the learning to the relevant domain skill instead.

## Done Criteria

- Guidance in this skill remains foundational and cross-domain.
- New additions improve readability, safety, or maintainability for many systems.
- Domain-specific learnings are documented in domain skills, not here.
