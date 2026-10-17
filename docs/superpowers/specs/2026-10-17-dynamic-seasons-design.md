# Dynamic Seasons Design

Status: draft
Date: 2026-10-17

## Goal
Add a lightweight "Dynamic Seasons" feature to Vostok Toolkit (VTK). Only runs for New Game runs started with the Dynamic season chosen in the menu. Cycles 4 seasons over time (spring>summer>autumn>winter), applies full vanilla gameplay change for winter (real winter: snow/cold), and applies lightweight visual tints for all seasons (recolor vanilla tree/grass materials + lighting tint).

## Decisions
- Scope: only Dynamic runs (season==3 from New Game). Master MCM toggle (default on). Menu Dynamic button unlocked.
- Pacing: 30 in-game days per season, order spring>summer>autumn>winter, start season configurable in MCM (Spring/Summer/Autumn/Winter/Random), default Summer.
- Effects: winter > vanilla season=2 + World.winter=true, World.winterValue=1.0; others > vanilla season=1 + tints.
- Visuals: recolor 4 vanilla tree materials (MT_Tree_Branch.tres, MT_Tree_Billboard.tres, MT_Tree_Damaged.tres) and grass material (MT_Grass.tres) via their 	int shader parameter; lighting tint for World.environment + World.sunLight where present. No heavy SES parts (no grass shader replacement, no falling leaves, no LOD overrides, no tree variation arrays).
- Menu unlock: poll menu scene for Modes/Season/Dynamic/Select while in menu; enable if disabled and set text "Select" (~400 ms).
- Detection: on loader-newgame-post(difficulty, season), if season==3 > enable dynamic for this run.
- Persistence: TraderSave meta key tk_season stores {"dynamic": bool, "start_offset": int, "start_choice": String, "anchor_day": int} per slot.
- Driver: ticked from VTKHooks._process().

## Architecture
- Pure logic: VTKSeasons.gd (static RefCounted, headless-testable): resolve_index, vanilla_season, is_winter, SEASONS, palettes, start_offset_for/Random.
- Scene driver: VTKSeasonDriver.gd (RefCounted) owned by FeatureHost; collects vanilla materials, saves/restores tints, applies tints on season change, menu unlock, persistence. Ticked from VTKHooks._process(); newgame-post forwarded.
- Integration: FeatureHost exposes driver or VTKHooks owns it. Newgame detection in VTKHooks._on_newgame_post(difficulty, season) passes to driver.

## Files
- loadouts/mods/VTK/VTKSeasons.gd (new, pure)
- loadouts/mods/VTK/VTKSeasonDriver.gd (new, scene)
- loadouts/mods/VTK/VTKHooks.gd (minor changes)
- loadouts/mods/VTK/VTKMCMBridge.gd (season settings)
- loadouts/mods/VTK/VTKConfig.gd (season fields)
- .check/project/tests/test_seasons.gd (new, headless)
- loadouts/mod.txt — no expected change

## MCM
- season_enabled (Bool, default true)
- season_cycle_days (Int, default 30, 1..365)
- season_start (Dropdown, default "Summer": Spring/Summer/Autumn/Winter/Random)

## Testing
Headless test 	est_seasons.gd covers resolve_index wraparound, bounds, random fallback, vanilla_season mapping. Included in check.ps1 (must add to list).

## Open
- World property names (winter, winterValue, sunLight, environment) — verify via detokenized World.gdc. Driver must guard.
- Lighting tint: env property names may vary; apply conservatively.
- Persistence: TraderSave meta used; ensure it survives slot context as deposits do.
