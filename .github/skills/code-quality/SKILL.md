---
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
