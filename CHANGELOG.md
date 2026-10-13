# Changelog

All notable changes to Vostok Toolkit are documented here.
Format based on Keep a Changelog; versioning: MAJOR.MINOR.PATCH.

## [4.16.0] - 2026-10-13

Post-audit cleanup (audit Batches 0-2) plus the auto-equip / equipped-slot fixes.

### Added
- Take / Split on an item worn in an equip slot now returns the share to the inventory (vanilla handles grid items only), via the `interface-contexttake` / `interface-contextsplit` replace hooks.
- `VTKEquip.gd`: pure, headless-tested auto-equip helpers (slot choice, split/take shares, merge/space checks).

### Changed
- Auto-equip now triggers on the vanilla pickup event `Pickup.Interact()` instead of a per-frame inventory diff; stackables top up the worn slot and the leftover stays in the inventory.
- The mod version is read from `version.txt` only (no fallback to the shared `mod.txt`).
- Hard-coded node paths are centralised in `VTKPaths.gd`; save-file names are constants.
- Debug `print()`s and the NVG probe log sit behind the `05. Debug` MCM block (off by default); the HUD uses the vanilla theme font.

### Removed
- Batch 0-2 dead code: the legacy `VTKData` write section (~130 lines), dead helpers (`_get_iface` / `_make_step_btn` / `_place_item` / `_load_loadout` / `_slots_of` / `spawn_loadout`), a duplicated NVG block, the no-op `'Deposit'` Loc entry, and the leftover per-frame equip polling.

### Fixed
- Take / Split on a worn item no longer silently does nothing.
- Auto-equip no longer mis-fires when items are merely rearranged in the inventory.

## [4.15.1] - 2026-10-12

### Added
- Initial public release on Vostok Mods
- Loadout presets with hotkey binding
- Auto-equip: items with slots are equipped on pickup (MCM toggle)
- Matches and other stackables top up the equipped slot without extra clicks
- Better Tasks: completed-quest auto-cleanup, partial hand-in, Notes icon rows
- Thermal vision (NVG): world heat glow, mine highlighting, friendly markers
- Kill stats HUD and dynamic killfeed
- Fast travel between maps, shelters and traders
- Ironman Restart button and the Apartments map
- RU / EN interface language switch in MCM
