# Encounter Registry Refactor Summary

## Objective
Centralize all encounter metadata into a single source of truth to eliminate sync bugs when adding or modifying encounters.

## Problem Solved
Previously, adding or renaming an encounter required updates in 8+ separate locations:
1. `DEBUG_ENCOUNTER_MAP` in encounter_contracts.gd
2. `DEBUG_ENCOUNTER_GLOSSARY_LABELS` in encounter_contracts.gd
3. `ENCOUNTER_DOOR_PRESENTATION` in encounter_contracts.gd
4. `DEBUG_OBJECTIVE_DISPLAY_LABELS` in encounter_contracts.gd
5. `BEARING_LABELS` in encounter_profile_builder.gd
6. `_get_bearing_definitions()` in encounter_profile_builder.gd
7. `build_debug_encounter_profile()` dispatch in encounter_profile_builder.gd
8. Identity comments in `_get_hard_pool()` in encounter_profile_builder.gd
9. `_encounter_rows()` in glossary_data.gd

Missing even one update would silently break debug UI, glossary validation, or route generation.

## Solution Implemented

### 1. Centralized Encounter Registry (encounter_contracts.gd)
Created `_build_encounter_registry()` static function containing all encounter definitions with metadata:
- `key`: String identifier (e.g., "crossfire")
- `id`: Debug enum value
- `is_boss`, `is_rest`, `is_objective`: Flags
- `display_label`: For UI display
- `glossary_label`: For glossary entries
- `door_presentation`: Visual presentation data
- `bearing_label`: For bearing encounters
- `identity`: Short description of encounter's gameplay role

### 2. Derived Data Functions (encounter_contracts.gd)
Created helper functions that generate the legacy constants from the registry:
- `_derive_debug_encounter_map()` → replaces hardcoded DEBUG_ENCOUNTER_MAP
- `_derive_door_presentation()` → replaces hardcoded ENCOUNTER_DOOR_PRESENTATION
- `_derive_glossary_labels()` → replaces hardcoded DEBUG_ENCOUNTER_GLOSSARY_LABELS
- `_derive_display_labels()` → replaces hardcoded DEBUG_OBJECTIVE_DISPLAY_LABELS

Legacy constants are now static variables initialized on first use via `_ensure_registry_initialized()`.

### 3. Lazy Initialization Pattern (encounter_contracts.gd)
- `_ensure_registry_initialized()` checks if registry-derived data is initialized
- Called automatically by functions that access the data
- Eliminates module-level initialization ordering problems

### 4. Bearing Label Validation (encounter_profile_builder.gd)
- Added `get_bearing_labels_from_registry()` in encounter_contracts.gd
- Added `validate_bearing_sync()` in encounter_profile_builder.gd
- Validates that BEARING_LABELS stays in sync with registry entries

### 5. Documentation (encounter_profile_builder.gd)
- Added comment explaining the relationship between BEARING_LABELS and registry
- Documents the three steps needed to add a new bearing encounter

## Files Modified
1. **scripts/shared/encounter_contracts.gd**
   - Added `_build_encounter_registry()` with all encounter metadata
   - Added derived data functions
   - Updated constants to be static variables
   - Added lazy initialization logic
   - Updated all functions that access derived data

2. **scripts/encounter_profile_builder.gd**
   - Added validation documentation
   - Added `validate_bearing_sync()` function
   - Added comment explaining BEARING_LABELS sync requirement

## New Workflow: Adding an Encounter

**Step 1:** Add entry to `_build_encounter_registry()` in [encounter_contracts.gd](scripts/shared/encounter_contracts.gd):
```gdscript
{
    "key": "new_encounter_key",
    "id": DEBUG_ENUMS.Encounter.NEW_ENCOUNTER,
    "is_boss": false, "is_rest": false, "is_objective": false,
    "display_label": "Display Name",
    "glossary_label": "Glossary Entry Name",
    "door_presentation": { /* color, icon, etc */ },
    "bearing_label": "New_Encounter",
    "identity": "Short gameplay description."
}
```

**Step 2** (if bearing): Add label to `BEARING_LABELS` in [encounter_profile_builder.gd](scripts/encounter_profile_builder.gd)

**Step 3** (if bearing): Add composition to `_get_bearing_definitions()` in encounter_profile_builder.gd

**Step 4** (if special): Add case to `build_debug_encounter_profile()` match statement if needed

**Step 5** (if glossary): Update `_encounter_rows()` in [glossary_data.gd](scripts/shared/glossary_data.gd) per project guidelines

## Benefits
1. **Single Source of Truth**: All encounter metadata in one registry structure
2. **Reduced Sync Points**: From 8+ to 3-5 locations
3. **Validation**: `validate_bearing_sync()` and `validate_encounter_sync()` catch misconfigurations
4. **Self-Documenting**: Identity comments are tied to encounter definitions
5. **Type-Safe**: Metadata is validated on access, not just at compile time
6. **Maintainable**: Clear documentation of what needs updating when

## Validation Commands
To check for sync issues:
- `ENCOUNTER_CONTRACTS.validate_encounter_sync(glossary_rows)` - checks debug/glossary alignment
- `ENCOUNTER_PROFILE_BUILDER.validate_bearing_sync()` - checks bearing label alignment

## Backward Compatibility
All existing code continues to work. The legacy constants (DEBUG_ENCOUNTER_MAP, ENCOUNTER_DOOR_PRESENTATION, etc.) are still available and accessed the same way—they're just now derived from the registry.
