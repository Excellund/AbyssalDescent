# Type Inference Safety

## Problem
Godot's type inference (`:=`) fails silently when indexing arrays or dictionaries without an explicit type hint. This creates "Cannot infer the type of X variable" errors that are only caught during script load.

```gdscript
# ❌ ERROR: Cannot infer the type
var config := settings_dict["key"]
var item := array[index]

# ✅ SAFE: Explicit type provided
var config: Dictionary = settings_dict["key"]
var item: Node = array[index]
```

## Rule: Always Annotate Collection Access

When accessing dictionaries, arrays, or other collections with subscript notation (`[]`), **always provide an explicit type annotation**:

### Pattern 1: Dictionary Access
```gdscript
# ❌ WRONG
var power_map := POWER_REGISTRY[power_id]
var param := params[param_name]

# ✅ CORRECT
var power_map: Dictionary = POWER_REGISTRY[power_id]
var param: Dictionary = params[param_name]
```

### Pattern 2: Array Access (when type is not obvious)
```gdscript
# ❌ WRONG
var enemy := enemy_list[index]
var zone := zone_cache[zone_id]

# ✅ CORRECT (if type is known)
var enemy: Node2D = enemy_list[index]
var zone: Area2D = zone_cache[zone_id]

# ✅ ALTERNATIVE (use cast if unsure)
var enemy := enemy_list[index] as Node2D
var zone := zone_cache[zone_id] as Area2D
```

### Exception: Casting with `as`
If you use `as` to cast the value, type inference works:

```gdscript
# ✅ OK: Cast provides type info
var run := runs[i] as Dictionary
var panel := panels[i] as Panel
```

## When to Apply

- **Always** use explicit types for dictionary subscript access
- **Always** use explicit types for array subscript access to non-primitive types
- **Safe to infer** for arithmetic operations: `var sum := x + y`
- **Safe to infer** for function returns with clear types: `var node := get_node("path")`

## Linter Pattern to Catch

Look for this pattern in code review:
```
var <name> := <collection>[<index>]
```

Without an immediate `as` cast or clear type hint, this is a red flag.

## Why This Matters

1. **Early Error Detection** — Type errors appear at script load, not runtime
2. **IDE Autocompletion** — Explicit types enable better tooltips and autocomplete
3. **Code Clarity** — Readers immediately see what type is expected
4. **Future Refactoring** — Changing collection contents won't silently break code

## Example Refactor (from codebase)

**Before:**
```gdscript
var power_map := TRIAL_POWER_PARAM_MAP[power_id]  # ❌ Type unknown
var param_def := parameters[param_name]            # ❌ Type unknown
```

**After:**
```gdscript
var power_map: Dictionary = TRIAL_POWER_PARAM_MAP[power_id]  # ✅ Clear
var param_def: Dictionary = parameters[param_name]           # ✅ Clear
```

## Related
- See [code-quality](../code-quality/SKILL.md) for general type annotation best practices
