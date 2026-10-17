# Dynamic Seasons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Add lightweight dynamic seasons for Dynamic-run new games: cycle spring>summer>autumn>winter by day; winter > real vanilla season=2, others > season=1 with tree/grass tint + lighting tint. Unlock menu Dynamic button.

**Architecture:** Pure VTKSeasons.gd (logic/palettes, headless-testable) + VTKSeasonDriver.gd (scene driver, owns materials/restores/ticks). Tick from VTKHooks._process; detect Dynamic on loader-newgame-post(season). MCM-driven settings. Persistence via TraderSave meta tk_season.

**Tech Stack:** Godot 4.6.3 GDScript, existing VTK modules, modloader hooks.

## Global Constraints
- Tabs for indentation in .gd files.
- UTF-8 files, LF (match VTKHooks).
- Follow VTK conventions: pure modules (RefCounted) where possible, headless tests.
- Don't duplicate version (version lives in loadouts/mod.txt).
- Verify World property names exist before setting (guarded).
- Headless tests added to .check/project/tests/ and referenced in check.ps1.

---
### Task 1: Add headless test for seasons logic

**Files:**
- Create: .check/project/tests/test_seasons.gd
- Modify: .check/project/tests/check.ps1 (add test_seasons to the $tests list in order or by convention)

**Interfaces:**
- Consumes: none
- Produces: public API expectations for VTKSeasons (resolve_index, vanilla_season, is_winter, SEASONS, start_offset_for, maybe start_offset_for_string)

- [ ] **Step 1: Write the failing test**

- [ ] **Step 3:** Add 	est_seasons to $tests in .check/project/tests/check.ps1.

### Task 2: Implement pure logic VTKSeasons.gd

**Files:**
- Create: `loadouts/mods/VTK/VTKSeasons.gd`
- Test: `.check/project/tests/test_seasons.gd`

**Interfaces:**
- Produces: `resolve_index(day, cycle_days, start_offset) -> int`, `vanilla_season(index) -> int`, `is_winter(index) -> bool`, `SEASONS := ["spring","summer","autumn","winter"]`

- [ ] Step 1: Write minimal implementation to pass tests.
- [ ] Step 2: Run tests.
- [ ] Step 3: Commit.
```bash
git add loadouts/mods/VTK/VTKSeasons.gd
git commit -m "feat(vtk): add VTKSeasons pure logic"
```

### Task 3: Add MCM config for Dynamic Seasons

**Files:**
- Modify: `loadouts/mods/VTK/VTKConfig.gd` (add fields: `season_enabled`, `season_start` with defaults)
- Modify: `loadouts/mods/VTK/VTKMCMBridge.gd` (register MCM keys for season_enabled, season_start)

**Notes:**
- Defaults: `season_enabled = true`, `season_start = "summer"` (or 1). Choose string key: "spring","summer","autumn","winter","random" per spec.
- Keep existing style (type-safe fields + read(cfg), MCM registration mirrors existing code).

- [ ] Step 1: Update VTKConfig: add fields, defaults, read() handling.
- [ ] Step 2: Update VTKMCMBridge: add registry entries (name/tooltip/menu_pos) matching existing style.
- [ ] Step 3: Verify no parse errors (check.ps1 will catch). Commit.
```bash
git add loadouts/mods/VTK/VTKConfig.gd loadouts/mods/VTK/VTKMCMBridge.gd
git commit -m "feat(vtk): add MCM settings for dynamic seasons"
```

### Task 4: Implement scene driver VTKSeasonDriver.gd

**Files:**
- Create: `loadouts/mods/VTK/VTKSeasonDriver.gd`

**Purpose:**
- Owns material state (tree/grass tints), lighting tints, restores on disable/reload.
- Exposes `set_season(idx, is_dynamic_run, cfg)` that reads VTKConfig/cfg and applies:
  - winter: set World.season=2, World.winter=true, World.winterValue=1.0 (guarded)
  - others: set World.season=1, World.winter=false, World.winterValue small/0 as appropriate; apply tints (pale/lightweight)
- `_process(delta)` optional tick (or driven externally). Keep minimal per spec.
- `restore()` to return vanilla-like baseline if needed.

- [ ] Step 1: Implement with guards (has_method/get). Use VTKLog.warn_once style if needed.
- [ ] Step 2: Basic sanity (no syntax). Commit.
```bash
git add loadouts/mods/VTK/VTKSeasonDriver.gd
git commit -m "feat(vtk): add VTKSeasonDriver scene driver"
```

### Task 5: Integrate into VTKHooks (detection, tick, lifecycle)

**Files:**
- Modify: `loadouts/mods/VTK/VTKHooks.gd`

**Changes:**
- Preload `VTKSeasons.gd` and `VTKSeasonDriver.gd` if not already (or lazy). Match existing preload style.
- Track per-slot season state via TraderSave meta `vtk_season`: keys `dynamic` (bool), `start_offset` (int 0-3 or string), `start_day`/`day0` or simply compute from world day? Spec states: "start offset fixed at run start". Persist minimal: e.g. `{ "enabled": true, "start_offset": 1, "season": 3, "cycle_days": 30 }` as needed.
- Hook `loader-newgame-post(difficulty, season)` (modloader post hook): if season==3 (Dynamic) and config.season_enabled -> initialize driver/state, set initial season for day1.
- Tick from `_process()` (or hook world sim tick). Compute current season index by world day (Simulation.day or Loader/World day). Apply when index changes.
- Store/restore on unload/restart as appropriate (match existing patterns).

- [ ] Step 1: Add detection + init.
- [ ] Step 2: Add day-based tick (throttle if heavy, but lightweight).
- [ ] Step 3: Verify arity matches hook expectations (void post for newgame? follow existing). Commit.
```bash
git add loadouts/mods/VTK/VTKHooks.gd
git commit -m "feat(vtk): integrate dynamic seasons into hooks (detect+ticker)"
```

### Task 6: Unlock Dynamic in menu (if needed)

**Files:**
- Modify: `loadouts/mods/VTK/VTKUI.gd` (or relevant menu code). Also check `VTKMCMBridge`/menu wiring per spec: "unlock menu Dynamic button".

**Note:**
- Spec says: "Menu: poll Modes/Season/Dynamic/Select (~400ms) to unlock." Implement polling/gate as specified (minimal). Avoid changing layout except necessary.

- [ ] Step 1: Add minimal unlock logic. Guarded (get_node_or_null).
- [ ] Step 2: Commit.
```bash
git add loadouts/mods/VTK/VTKUI.gd
git commit -m "feat(vtk): unlock Dynamic season in menu"
```

### Task 7: Persistence (TraderSave meta vtk_season)

**Files:**
- Modify: `loadouts/mods/VTK/VTKData.gd` (if helpers) and/or `VTKHooks.gd` (read/write). Match existing save pattern (VTKData helpers).

**Notes:**
- Write on start/change? Keep minimal: save at init and on season transition if desired; also on save points consistent with existing.
- Read on load for slot.

- [ ] Step 1: Add read/write helpers (or inline following style). Use existing ResourceSaver/save guards.
- [ ] Step 2: Commit.
```bash
git add loadouts/mods/VTK/VTKData.gd loadouts/mods/VTK/VTKHooks.gd
git commit -m "feat(vtk): persist dynamic season state in TraderSave meta"
```

### Task 8: Expand tests (integration smoke) + fix check.ps1

**Files:**
- Modify: `.check/project/tests/test_seasons.gd` to add start_offset helpers if needed (spec allows start_offset_for_string)
- Modify: `.check/project/tests/check.ps1` - add `test_seasons` to `$tests` array
- Create headless stub if missing (we did). Also ensure test_seasons_headless.gd exists.

- [ ] Step 1: Update test_seasons.gd to cover start_offset string mapping + boundary cases.
- [ ] Step 2: Ensure check.ps1 includes `test_seasons`.
- [ ] Step 3: Run `powershell -NoProfile -ExecutionPolicy Bypass -File .check/check.ps1 -Godot D:\RTVMOD\tools\4.6.3\Godot_v4.6.3-stable_win64_console.exe` — expect green.
- [ ] Step 4: Commit.
```bash
git add .check/project/tests/test_seasons.gd .check/project/tests/check.ps1 .check/project/tests/test_seasons_headless.gd
git commit -m "test(vtk): finalize test_seasons and wire into check"
```

### Task 9: Verification & docs (optional but nice)

- [ ] Step 1: Run layout check: `py -3 .check/layout_check.py` — must pass.
- [ ] Step 2: Run full check.ps1 again — green (14 files + test_seasons).
- [ ] Step 3: Update CHANGELOG.md if user-visible change (unlock Dynamic + dynamic seasons). Follow existing style (keep short). Commit if changed.
```bash
git add CHANGELOG.md
git commit -m "docs: update changelog for dynamic seasons"
```

## Verification (global)

- All headless tests green.
- layout_check.py passes.
- No new SCRIPT ERROR/Parse Error in headless.
- LF for new files (VTKSeasons.gd, VTKSeasonDriver.gd).
- Version not touched.
- No secrets.

## Post-merge/finish
- Use superpowers:finishing-a-development-branch after final review passes.
