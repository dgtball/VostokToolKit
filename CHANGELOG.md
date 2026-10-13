# Changelog

All notable changes to Vostok Toolkit are documented here.
User-facing only: describe the visible effect, not the implementation (no hook names, files or functions).
Format based on Keep a Changelog; versioning: MAJOR.MINOR.PATCH.

## [4.16.5] - 2026-10-14

### Added

- Auto-equip now also applies to equipment taken out of containers, however you move it (double-click, context Transfer, or drag into the inventory).

## [4.16.4] - 2026-10-13

### Changed

- Minor performance improvements and internal cleanup.
- Clearer visual marking for selected attachments and quick-assigned weapon attachments in the equipment view.

### Removed

- The "Spawn into inventory"/"Spawn into catalog" button on loadout gear cells.

## [4.16.2] - 2026-10-13

### Changed
- Minor performance improvements and internal cleanup.

## [4.16.1] - 2026-10-13

### Changed
- The item context menu now uses the game's own hold-to-confirm Delete button instead of the previous one-click Delete.

## [4.16.0] - 2026-10-13

### Fixed
- Take/Split now works on items worn in an equip slot.
- Stackables (e.g. Matches) picked up top up the equipped slot instead of bouncing back into the inventory.
- Rearranging items in the inventory no longer slips them into an equip slot.
- Deposit button font now matches the other task buttons.

### Changed
- Kill-stats HUD and killfeed now use the game's own font.
- Minor performance improvements and internal cleanup.

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
