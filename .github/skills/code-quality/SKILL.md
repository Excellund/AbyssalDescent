### 8. Document and Enforce Mutability Contracts

Always document whether a function that returns data (especially Dictionaries or Arrays) returns a deep copy, a shallow copy, or a reference to shared state. Enforce this contract in code and docstrings.

Why it matters:

- Unclear mutability contracts lead to accidental mutation of shared state, subtle bugs, and defensive copying everywhere.
- Clear contracts reduce cognitive load and make code safer to change.

How to apply:

- For any function returning a Dictionary or Array, explicitly state in the docstring whether the result is safe to mutate.
- Prefer returning a deep copy when mutation is expected or possible.
- If returning a reference, document that the result must not be mutated by the caller.
- Audit and update legacy code to clarify and enforce these contracts incrementally.

## Nuance: Defensive copying everywhere is wasteful. Prefer clear contracts and only copy when mutation is required by the caller or likely in the future.

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
- When several functions only differ by event key/limits, route them through one helper and pass the small deltas as explicit parameters.
- For repeated combat or area-hit loops, centralize target selection and on-hit effect/proc resolution so damage packet rules cannot drift between variants.
- For long-lived collaborators that can be unavailable during boot/teardown (for example run recorders, replication services, or session stores), centralize readiness checks and common accessors (latest snapshot, finish/flush) behind one helper API instead of scattering null checks at call sites.
- Prefer one canonical implementation per behavior.

Nuance: DRY targets _true_ duplication of behavior. Do not deduplicate code that merely _looks_ similar but evolves for different reasons — premature consolidation creates coupling that is harder to undo than the duplication.

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
- For repeated pause/start/end combat side effects (damage toggles, lingering-effect cleanup, physics process gating), route through a focused coordinator instead of duplicating world-level branches.
- Remove mirrored or legacy paths after extraction.
- **Extract visual overlays from orchestrators.** If a Node2D orchestrator (e.g., world_generator.gd) grows a `_draw()` method for a specific visual subsystem, extract it to a dedicated `Node2D` overlay script (e.g., `objective_control_overlay.gd`). The overlay owns its own `queue_redraw()` cycle. The orchestrator wires the overlay to the data source and adds it as a child. See `lancer_zone_overlay.gd`, `lacuna_attack_overlay.gd`, `objective_control_overlay.gd` for the established pattern.

Nuance: splitting has a cost. If the split forces readers to jump across many files to follow one straight-line behavior, the original was clearer. Prefer local and obvious code over more files.

### 4. Prefer Explicit Contracts

Use typed, direct contracts for stable internal interactions.

Why it matters:

- String-based dispatch or property-name access hides ownership.
- Runtime introspection weakens refactor safety.
- Reflection guards (`has_method`/`call`/`get(name)`) silently swallow rename and signature drift; the compiler cannot help.

How to apply:

- Prefer direct method calls over dynamic dispatch for internal code.
- Prefer stable actor APIs over ad hoc property string access.
- Keep dynamic boundaries explicit and narrowly scoped.
- **Ban `has_method` / `call(string)` / `get(string)` for internal types.** When a function genuinely receives a Player, an enemy, or any first-party node, preload the script and cast: `var typed := node as PLAYER_SCRIPT`, then call typed methods and read typed properties directly. Use the reflection escape hatch only at true dynamic boundaries (third-party nodes, autoloads with no known script, optional duck-typed plugins).
- When extracting helpers, pass strongly-typed parameters and rely on `as ScriptConst` casts to reach concrete fields/methods rather than `node.get("field")` or `node.call("method")`.
- **When a preload cycle blocks a typed cast, use direct dynamic dispatch — not reflection.** GDScript only forbids string-keyed `has_method`/`call`/`get`. Calling `node.method_name()` directly on a `Node`/`Object`-typed receiver is statically resolved at runtime and is the correct fallback when adding `const X_SCRIPT := preload(...)` would create a cycle (e.g., `player.gd` ↔ `player_replication_service.gd`, `world_generator.gd` ↔ `objective_runtime.gd`). Add a virtual stub on the base class when a subclass-only method needs to be reachable through a base-typed reference.
- **No `typed_X` / `X_typed` aliases.** The strongly-typed binding owns the natural name; if you feel the need to prefix or suffix to disambiguate, the underlying type is the bug. Fix the source: tighten the parameter type (`enemy: ENEMY_BASE_SCRIPT`, not `enemy: CharacterBody2D` + cast), tighten the return type (`spawn_enemy_node_type(...) -> ENEMY_BASE_SCRIPT`), or tighten the field type. Only when a cycle blocks the cast at the source, give the descriptive `_node`/`_body` suffix to the loose parameter and let the typed local own the natural name (e.g., `func is_player_alive(player_node: Node)` with `var player := player_node as PLAYER_SCRIPT`).

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

### 7. Avoid Over-Engineering

A refactor should increase clarity more than it increases abstraction.

Why it matters:

- Over-abstraction hides data flow and inflates cognitive load.
- Generic systems built for hypothetical future needs rarely fit the real future need.
- Excessive splitting fragments straight-line behavior and slows debugging.

How to apply:

- Do not introduce patterns, registries, or indirection before there is concrete, repeated pain.
- Do not deduplicate superficial similarity. Wait for the third occurrence with shared intent.
- Do not extract a helper if the call site is clearer with the logic inline.
- Do not split a module unless responsibilities have actually diverged.
- Prefer deleting or inlining over adding new layers.
- When a change does not make code more obvious, more local, or more predictable, drop it.

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
