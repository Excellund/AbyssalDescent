name: code-quality
description: "Apply core code quality principles: DRY, modularity, single responsibility, data structure selection, minimize globals, and organize project structure for clarity and maintainability."
argument-hint: "Area of code being reviewed or refactored"

---

# Code Quality Best Practices

Use this skill whenever reviewing, refactoring, or writing code to ensure maintainability, clarity, and reduced cognitive load for future contributors.

## Core Principles

### 1. Keep Your Code DRY (Don't Repeat Yourself)

Avoid duplicating logic across functions, classes, or modules.

**Why it matters:**

- Duplication increases bug surface area — fix a bug in one place but forget another.

- Duplication makes refactoring risky and costly.

- Reduces clarity about which version is canonical.

**How to apply:**

- Extract common logic into reusable functions or methods.

- Use inheritance or composition to share behavior between similar classes.

- Identify similar patterns and consolidate them before code diverges further.

- When you find yourself copy-pasting, refactor first.

---

### 2. Use Appropriate Data Structures

Select the right data structure for the problem. Don't use complex structures when simpler ones suffice.

**Why it matters:**

- Complexity hides intent — readers must reason about unnecessary overhead.

- Performance may suffer needlessly.

- Bugs often hide in corner cases of over-engineered structures.

**How to apply:**

- Use arrays/lists for ordered collections with linear access.

- Use dictionaries/maps for fast lookups by key.

- Use sets for membership tests and uniqueness constraints.

- Use structs/records for fixed-shape data; avoid classes if no behavior is needed.

- Favor simple nested data over deeply layered abstractions.

- Document why a complex structure was chosen if one is used.

---

### 3. Keep Your Code Modular

Divide code into smaller, focused units with clear boundaries.

**Why it matters:**

- Smaller modules are easier to test, understand, and reason about.

- Modularity reduces coupling — changes in one module have limited blast radius.

- Reusability improves when modules have clear, narrow contracts.

- Easier to parallelize work across team members.

**How to apply:**

- Aim for functions that do one thing well (see Single Responsibility Principle below).

- Limit file sizes — files over 500 lines often signal multiple responsibilities.

- Use clear file names that signal purpose.

- Group related functionality into modules; avoid "util" dumping grounds.
  - Name shared helpers by their single responsibility, not their type. Prefer `_normalizer`, `_scaler`, `_builder`, `_resolver` over `_utils` or `_helpers`.
  - A file named `_utils` invites unrelated additions over time; a name like `bearing_key_normalizer.gd` signals what it does and keeps scope narrow.

- Expose minimal public surface; keep helpers private.

- Use dependency injection or clear initialization patterns instead of implicit state.

---

### 4. Avoid the Use of Global Variables

Minimize global state as it makes code harder to understand, test, and debug.

**Why it matters:**

- Globals create hidden dependencies — readers can't tell what a function depends on.

- Globals make testing difficult — state can bleed between tests.

- Globals make debugging harder — any code can mutate them at any time.

- Globals reduce modularity — modules that depend on them can't be used independently.

**How to apply:**

- Pass data as function parameters instead of relying on globals.

- Use singletons sparingly, only for truly stateless services (e.g., loggers, config readers).

- Centralize mutable state ownership — one module should own and expose state through clear getters/setters.

- Use dependency injection to provide services to functions that need them.

- If a singleton is necessary, make it immutable or provide thread-safe access.

---

### 5. Follow the Single Responsibility Principle (SRP)

Each function or class should have one well-defined responsibility.

**Why it matters:**

- Single responsibility makes code easier to name, understand, and test.

- Changes to one concern don't ripple through unrelated parts of the code.

- Reduces cognitive load — you only need to reason about one thing at a time.

- Improves reusability — focused units are easier to compose and repurpose.

**How to apply:**

- Ask: "What is this function/class for?" If the answer has "and" in it, it likely violates SRP.

- If you find yourself writing tests that exercise unrelated behaviors together, SRP may be violated.

- Use names that are specific and action-oriented (e.g., `validate_player_health()` not `process()`).

- Separate concerns: data access, business logic, presentation, and configuration should not be mixed.

- If a class has multiple reasons to change, break it into smaller classes.

---

### 6. Proper Project File Structure

Organize code by concern and purpose, not by implementation type.

**Why it matters:**

- Clear structure helps new contributors find code quickly.

- Reduces "where does this belong?" ambiguity.

- Signals intent through organization.

- Easier to understand system boundaries and dependencies.

**How to apply:**

- Organize by feature or domain, not by type (e.g., `enemies/charger/`, `objectives/hold_the_line/` instead of `types/`, `helpers/`).

- Keep related files together:
  - Logic (`.gd` scripts)

  - Scenes (`.tscn` files)

  - Data (config, registries, constants)

  - Tests and validation

- Avoid mixing concerns in the root directory — group into logical folders.

- Use consistent naming: `entity_type.gd`, `entity_type.tscn`, `entity_registry.gd`.

- Separate public interfaces from implementation details through folder structure.

- Add a README or clear comments to top-level folders explaining their purpose.

---

### 7. Avoid String-Based Dynamic Dispatch For Internal Calls

Prefer explicit method calls over wrappers that dispatch via method-name strings (for example helper signatures like `_call(method: String, args: Array)` using `callv`).

**Why it matters:**

- String dispatch hides control flow and weakens editor/language-server navigation.
- Typos become runtime failures instead of obvious code review issues.
- Refactors are riskier because renames do not update string literals safely.
- Call intent is less readable than direct method calls.

**How to apply:**

- Use direct calls (`objective_runtime.update_objective_state(delta)`) behind a normal instance-validity guard.
- Keep lightweight wrapper methods explicit and typed when forwarding behavior.
- Reserve dynamic dispatch (`call`, `callv`) for truly dynamic plugin/mod interfaces, not internal game-runtime wiring.
- If dynamic dispatch is unavoidable, document why and constrain it to one narrow boundary.

---

### 8. Do Not Pass Irrelevant Parameters

Do not pass placeholder or immediately-overwritten values to a function just to satisfy its signature.

**Why it matters:**

- Placeholder arguments (e.g. `0, 0, 0, 0`) obscure which values actually matter.
- A reader cannot tell whether the zeros are intentional constraints or noise.
- The pattern signals a mismatch between the function's signature and its real call contract.

**How to apply:**

---

### 9. Keep One Runtime Owner Per Behavior

When behavior is extracted into a dedicated runtime module, remove mirrored logic from the old host script instead of keeping both paths alive.

**Why it matters:**

- Dual implementations drift over time and silently diverge.
- Readers cannot tell which file is authoritative for bug fixes.
- Every tuning change becomes a multi-file risk.

**How to apply:**

- Choose one owner (for example objective runtime) for each behavior loop and VFX state machine.
- Replace old pass-through wrappers and copied update blocks with a single direct call path.
- Keep host scripts focused on orchestration/state ownership, not duplicated behavior internals.
- After consolidation, grep for removed method names to ensure no stale call sites remain.

---

### 9. Encode Damage Semantics as Data

When gameplay distinguishes flat, scaling, and hybrid damage, store that classification in a shared data source and consume it from UI/runtime code.

**Why it matters:**

- Prevents wording drift between card text, HUD, and runtime behavior.
- Makes balancing safer by separating _what kind of damage_ from per-skill numbers.
- Reduces copy-pasted labels like `[Flat]`/`[Scaling]` across multiple files.

**How to apply:**

- Define a canonical damage model map in a registry (for example: `{kind, scales_with}`).
- Expose small getters (for example `get_damage_model`, `get_damage_model_label`).
- Build UI prefixes/tooltips from those getters rather than hardcoded strings.
- Keep runtime breakdowns explicit (`base`, `flat_bonus`, `final`) for debugging and telemetry sanity checks.

- Give parameters default values when a sensible default exists and most call sites don't need to override them.
- If a call site overwrites all of a function's outputs immediately after calling it, restructure so the caller passes only what it owns.
- Prefer a narrow, honest signature over a broad one padded with zeros or empty dicts.

---

### 9. Trust Type Contracts; Avoid Runtime Method Introspection

Do not use `.has_method()` to defensively check if a method exists. Instead, establish clear type contracts and trust callers to uphold them.

**Why it matters:**

- Runtime introspection (`has_method`, `has_property`) is a code smell that signals unclear ownership or missing type information.
- Defensive checks hide the real contract — code that appears to handle missing methods may mask a design gap.
- Runtime checks add cognitive load and make refactoring risky (rename a method, forget to update the string check).
- Strong types and clear ownership make code flow easier to trace and reason about.

**How to apply:**

- Establish explicit type contracts: if a subsystem calls `target.take_damage()`, document that `target` must implement `take_damage` or inherit from a base class that does.
- Replace `if obj.has_method("method_name"): obj.method_name()` with direct calls behind instance-validity guards (`if obj != null:`).
- Use typed references and inheritance when possible to enforce contracts at declaration time.
- If a method is optional, make that explicit in the signature (e.g., a callback parameter with null default) rather than hidden runtime checks.
- When integrating with dynamic systems (plugins, data-driven configs), document the boundary explicitly and constrain introspection to that boundary only.

---

### 10. Avoid Temporary Shared-State Swapping

Do not temporarily overwrite shared/module state just to pass context into a helper, then restore it afterward.

---

### 11. Prefer Direct Actor Contracts Over Property Strings

Do not read or mutate known gameplay actor state through `get("...")` and `set("...")` when the actor belongs to a stable internal contract.

**Why it matters:**

- Property-name strings hide ownership and make cross-system dependencies harder to trace.
- Renames become risky because editor-assisted refactors do not update string literals.
- Reaching into nested internals like `health_state` spreads representation details across the codebase.
- Direct actor methods are easier to read and navigate than helper wrappers when the contract is already known.

**How to apply:**

- Add focused methods on the owning script for stable cross-system state such as health, objective data, or progression flags.
- Prefer calls like `enemy.get_max_health()` or `player.set_max_health_and_current(...)` over `get("max_health")`, `set("max_health")`, direct nested state pokes, or helper wrappers around the same contract.
- Introduce a shared helper only when the caller truly needs one abstraction boundary for mixed or dynamic targets.
- Reserve property-string access for genuinely dynamic data or editor-driven configuration where the field name is not known at author time.

**Why it matters:**

- Temporary write/restore logic obscures control flow.
- Later edits can accidentally skip restoration and leak state.
- Helper behavior becomes implicitly coupled to ambient mutable state.

**How to apply:**

- Pass required context as explicit helper parameters.
- Keep shared state writes at clear ownership boundaries (setup/configuration), not mid-operation.
- Treat temporary state swaps as a refactor smell, especially in hot runtime paths.

---

### 11. Capture Durable User Guidance In Skills (Autonomous Checkpoint)

When code changes establish or validate a **durable, reusable practice**, update the relevant skill doc as part of task completion, not as optional follow-up work.

**Why it matters:**

- Prevents repeating the same correction across future tasks.
- Converts one-off feedback into team-scale consistency.
- Keeps skill guidance aligned with real project needs.
- Makes continuous improvement to process guidance an integral part of development, not a side effect.

**How to apply:**

- After code validation (diagnostics-clean, patterns confirmed), ask: "Does this establish a durable practice?"

---

### 12. Prefer Shared Enums Over Integer Constant Ladders

Avoid per-file ladders like `const STATE_X := 0`, `const STATE_Y := 1` for finite state sets.

**Why it matters:**

- Integer ladders obscure intent and make value drift likely when copied across files.
- Enum ownership is unclear when each script invents its own constant set.
- Shared enum modules reduce duplication and make call sites self-documenting.

**How to apply:**

- Define enums in focused shared modules under `scripts/shared/*_enums.gd`.
- In consumer scripts, reference enum members directly at defaults/match sites instead of recreating per-file alias constants.
- Only keep alias constants at explicit compatibility boundaries where external code or serialized content requires a stable legacy symbol.
- Preserve serialized/debug compatibility by keeping exported/default-facing symbols stable (for example pre-commit checks or scene serialization) while sourcing values from shared enums.
- Treat scalar tuning constants (durations, distances, damage values) as normal constants; only migrate finite categorical sets.
- If yes: identify which skill(s) cover this area (e.g., code-quality for patterns, encounter-identity-balance for tuning).
- Check the skill doc: does it reflect this learning, or is the guidance incomplete/outdated?
- If incomplete: update the skill in the same task, before calling task_complete.
- Keep updates minimal and specific: add one clear rule plus brief rationale.
- Do not overfit transient preferences into broad rules; keep one-off choices in session/user memory instead.
- If dynamic behavior remains necessary, document the boundary explicitly.

---

### 13. Centralize Modal Frame Gating In Main Loops

When multiple UI/modal states pause gameplay progression but still require HUD/render refresh, route those checks through a single helper instead of repeating the same refresh-and-return block.

**Why it matters:**

- Main frame loops are high-impact entry points where duplication quickly drifts.
- Consolidation lowers cognitive load by making pause/modal precedence explicit.
- A single refresh helper reduces bug surface area when UI sync behavior changes.

**How to apply:**

- Extract a small `_handle_modal_frame(...) -> bool` helper that owns modal precedence and early-return decisions.
- Extract a single `_refresh_frame_ui()` helper for HUD + renderer synchronization.
- Keep modal behavior unchanged during refactor; only move duplicated control-flow scaffolding.

---

## Procedure: Code Quality Review Checklist

When reviewing or refactoring code, ask these questions in order:

1. **Is logic duplicated?** ✓ Extract to a shared function/method.

2. **Is the data structure overcomplicated?** ✓ Use a simpler one that fits the problem.

3. **Can this code be broken into smaller units?** ✓ Split into focused functions/classes.

4. **Are there hidden global dependencies?** ✓ Make them explicit parameters.

5. **Does this function/class have multiple responsibilities?** ✓ Break it into focused units.

6. **Is the file structure clear and logical?** ✓ Reorganize by feature/domain.

---

## Safety Rules

- **Preserve behavior:** Refactoring for quality should not change observable behavior. Test after changes.

- **Refactor incrementally:** Make one type of improvement at a time. Don't combine structural changes with logic changes.

- **Don't over-engineer:** Simplicity beats clever abstractions. Don't add indirection without evidence it reduces complexity.

- **Document the why:** If a constraint or design decision isn't obvious, explain it in a comment.

---

## Done Criteria

- Code has no obvious duplications that could be consolidated.

- Data structures are appropriate for their use cases.

- Files and functions have clear, single responsibilities.

- No unexpected global state is created or consumed.

- Project structure mirrors the domain, not the implementation type.

- Changes preserve behavior and are easy to review.

# Code Quality Best Practices

## Core Principles

### 1. Keep Your Code DRY (Don't Repeat Yourself)

Avoid duplicating logic across functions, classes, or modules.

**Why it matters:**

- Duplication increases bug surface area — fix a bug in one place but forget another.
- Duplication makes refactoring risky and costly.
- Reduces clarity about which version is canonical.
- Extract common logic into reusable functions or methods.
- Use inheritance or composition to share behavior between similar classes.
- Identify similar patterns and consolidate them before code diverges further.

---

### 2. Use Appropriate Data Structures

**Why it matters:**

**How to apply:**

- Use arrays/lists for ordered collections with linear access.

Divide code into smaller, focused units with clear boundaries.

**Why it matters:**

- Smaller modules are easier to test, understand, and reason about.
- Modularity reduces coupling — changes in one module have limited blast radius.
- Reusability improves when modules have clear, narrow contracts.
- Easier to parallelize work across team members.

**How to apply:**

- Aim for functions that do one thing well (see Single Responsibility Principle below).
- Limit file sizes — files over 500 lines often signal multiple responsibilities.
- Use clear file names that signal purpose.
- Group related functionality into modules; avoid "util" dumping grounds.
- Expose minimal public surface; keep helpers private.
- Use dependency injection or clear initialization patterns instead of implicit state.

---

### 4. Avoid the Use of Global Variables

Minimize global state as it makes code harder to understand, test, and debug.

**Why it matters:**

- Globals create hidden dependencies — readers can't tell what a function depends on.
- Globals make testing difficult — state can bleed between tests.
- Globals make debugging harder — any code can mutate them at any time.
- Globals reduce modularity — modules that depend on them can't be used independently.

**How to apply:**

- Pass data as function parameters instead of relying on globals.
- Use singletons sparingly, only for truly stateless services (e.g., loggers, config readers).
- Centralize mutable state ownership — one module should own and expose state through clear getters/setters.
- Use dependency injection to provide services to functions that need them.
- If a singleton is necessary, make it immutable or provide thread-safe access.

---

### 5. Follow the Single Responsibility Principle (SRP)

Each function or class should have one well-defined responsibility.

**Why it matters:**

- Single responsibility makes code easier to name, understand, and test.
- Changes to one concern don't ripple through unrelated parts of the code.
- Reduces cognitive load — you only need to reason about one thing at a time.
- Improves reusability — focused units are easier to compose and repurpose.

**How to apply:**

- Ask: "What is this function/class for?" If the answer has "and" in it, it likely violates SRP.
- If you find yourself writing tests that exercise unrelated behaviors together, SRP may be violated.
- Use names that are specific and action-oriented (e.g., `validate_player_health()` not `process()`).
- Separate concerns: data access, business logic, presentation, and configuration should not be mixed.
- If a class has multiple reasons to change, break it into smaller classes.

---

### 6. Proper Project File Structure

Organize code by concern and purpose, not by implementation type.

**Why it matters:**

- Clear structure helps new contributors find code quickly.
- Reduces "where does this belong?" ambiguity.
- Signals intent through organization.
- Easier to understand system boundaries and dependencies.

**How to apply:**

- Organize by feature or domain, not by type (e.g., `enemies/charger/`, `objectives/hold_the_line/` instead of `types/`, `helpers/`).
- Keep related files together:
  - Logic (`.gd` scripts)
  - Scenes (`.tscn` files)
  - Data (config, registries, constants)
  - Tests and validation
- Avoid mixing concerns in the root directory — group into logical folders.
- Use consistent naming: `entity_type.gd`, `entity_type.tscn`, `entity_registry.gd`.
- Separate public interfaces from implementation details through folder structure.
- Add a README or clear comments to top-level folders explaining their purpose.

---

## Procedure: Code Quality Review Checklist

When reviewing or refactoring code, ask these questions in order:

2. **Is the data structure overcomplicated?** ✓ Use a simpler one that fits the problem.
3. **Can this code be broken into smaller units?** ✓ Split into focused functions/classes.
4. **Are there hidden global dependencies?** ✓ Make them explicit parameters.
5. **Does this function/class have multiple responsibilities?** ✓ Break it into focused units.
6. **Is the file structure clear and logical?** ✓ Reorganize by feature/domain.

---

## Safety Rules

- **Preserve behavior:** Refactoring for quality should not change observable behavior. Test after changes.
- **Refactor incrementally:** Make one type of improvement at a time. Don't combine structural changes with logic changes.
- **Don't over-engineer:** Simplicity beats clever abstractions. Don't add indirection without evidence it reduces complexity.
- **Document the why:** If a constraint or design decision isn't obvious, explain it in a comment.

---

## Done Criteria

- Code has no obvious duplications that could be consolidated.
- Data structures are appropriate for their use cases.
- Files and functions have clear, single responsibilities.
- No unexpected global state is created or consumed.
- Project structure mirrors the domain, not the implementation type.
- Changes preserve behavior and are easy to review.
