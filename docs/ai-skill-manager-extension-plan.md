# AI Skill Manager Extension Plan

## Goal
Build a VS Code extension that discovers AI skills from multiple configured roots, lets users enable or disable skills per workspace folder, and automatically disables skills based on a versioned declarative rule set.

## Core Decisions
- Support multiple configured skill roots.
- Store root configuration as ordered records, not as a plain path array.
- Give each root entry an opaque persistent `configRootId`.
- Define skill identity as `schemaVersion + configRootId + canonicalRelativePath`.
- Scope manual enable/disable state per workspace folder.
- Keep rule evaluation declarative and versioned.
- Treat duplicate root entries as distinct configuration records.
- Keep duplicate skills from separate roots as independent entries.
- Distinguish `manual-disabled`, `rule-disabled`, `missing/undiscovered`, and `enabled` states in the UI.

## Precedence Model
State resolution should be deterministic:
1. Missing or undiscovered
2. Rule-disabled
3. Manual-disabled
4. Enabled

If multiple rules match, choose the highest priority rule. If priorities tie, use stable declaration order.

## Phases

### Phase 1: Data Model and Storage
- Define the root-entry record shape.
- Add persistent storage for ordered root records.
- Add persistent storage for per-workspace-folder manual state.
- Add storage migration for any older workspace-wide state shape.

### Phase 2: Discovery and Identity
- Scan all configured roots.
- Canonicalize root URIs for filesystem comparison.
- Derive canonical relative paths for discovered skills.
- Keep duplicate roots and duplicate skills separate in the model.
- Add normalization for Windows drive letters, UNC paths, symlinks, and junctions.

### Phase 3: Rule Engine
- Define a versioned JSON rule schema.
- Support match, include, exclude, action, priority, and reason fields.
- Add validation for invalid or conflicting rules.
- Add a deterministic evaluator with clear tie-breaking.

### Phase 4: UI and Commands
- Build a tree view grouped by root.
- Add a flat search or command entry point.
- Add commands for enable, disable, refresh, open location, and root management.
- Show why a skill is disabled.

### Phase 5: Watching and Refresh
- Watch all configured roots.
- Debounce filesystem events.
- Refresh discovery and rule evaluation on config or file changes.
- Cache rule evaluation so the UI stays responsive.

### Phase 6: Validation
- Unit test identity generation.
- Unit test duplicate root handling.
- Unit test precedence and rule tie-breaking.
- Unit test migration and per-workspace-folder scoping.
- Unit test path normalization across platforms.
- Validate the extension in the VS Code Extension Development Host.

## Relevant Files To Create Or Update
- `package.json` for commands, settings, and view contributions.
- `src/extension.ts` for activation and wiring.
- `src/rootConfig.ts` for root-entry storage and migration.
- `src/discovery.ts` for multi-root scanning.
- `src/rules.ts` for schema, validation, and evaluation.
- `src/state.ts` for manual enable/disable persistence.
- `src/pathIdentity.ts` for canonical path handling.
- `src/skillTreeDataProvider.ts` for UI rendering.
- `test/` for identity, precedence, migration, and normalization tests.

## Verification Checklist
- Multiple configured roots load as distinct records.
- Duplicate root entries remain distinct.
- Manual state is isolated per workspace folder.
- Rule-disabled skills explain why they are disabled.
- Path normalization behaves consistently on Windows and non-Windows systems.
- Tests cover the precedence model and migration behavior.

## Non-Goals
- No scripting or executable rule language.
- No upstream changes to VS Code or Copilot skill loading.
- No database or external service for state persistence.