# Changelog

All notable changes to Vostok Toolkit are documented here.
User-facing only: describe the visible effect, not the implementation (no hook names, files or functions).
Format based on Keep a Changelog; versioning: MAJOR.MINOR.PATCH.

## [4.17.12] - 2026-10-16

### Changed

- Minor performance improvements and internal cleanup.

## [4.17.11] - 2026-10-16

### Fixed

- In a loadout, decreasing ammo with "−" now steps a whole box at a time and clears the ammo from the set when the last box is taken away, instead of jumping to a single round.
- The "Full" button for ammo cells now reads just "Full"; the extra dot and capacity number that made it stick out of the cell are gone.

## [4.17.10] - 2026-10-16

### Changed

- Minor performance improvements and internal cleanup.

## [4.17.9] - 2026-10-16

### Changed

- Minor performance improvements and internal cleanup.

## [4.17.8] - 2026-10-15

### Changed

- Texts the mod draws inside the game's own interface (the deposit button on task cards and notification messages) are now always in English; only the Loadouts window follows the language setting.

### Fixed

- Your saved presets are no longer lost if the game is closed in the middle of saving; a damaged presets file is recovered from a backup instead of silently emptying the list.
- Depositing items toward a task can no longer take them from you without recording the deposit.

## [4.17.7] - 2026-10-15

### Changed

- Minor performance improvements and internal cleanup.

### Fixed

- Using map travel or shelter teleport with a panel open no longer grabs the item under the cursor.
- Restarting after death is more reliable and no longer overrides the run mode the game applies to the new scene.

## [4.17.6] - 2026-10-15

### Fixed

- Map travel and shelter teleport are more reliable across scene changes.

## [4.17.5] - 2026-10-15

### Fixed

- Depositing items into a task is more robust and no longer interferes with the vanilla task flow.

## [4.17.4] - 2026-10-15

### Fixed

- Kill attribution is more reliable for unusual weapon and explosion kills.

## [4.17.3] - 2026-10-15

### Changed

- The magazine Full/Empty toggle is shorter and fits the gear item's cell.
- Attachments now open from a gear icon in the cell's corner.
- The gear count is centered between − and +; click-to-type amount was removed.

### Fixed

- "Only selected" on the Gear tab no longer lists items already worn in equipment.
- Kill stats got a background so they stay readable in daylight.
- The kill feed no longer appends a number suffix to enemy or Nomad names.

## [4.17.2] - 2026-10-14

### Changed

- Minor performance improvements and internal cleanup.

## [4.17.1] - 2026-10-14

### Added

- Ammo is now added to and stepped by a whole box, with a Full button to top up a stack.
- Click a gear item's number to type an exact amount.
- The magazine Full/Empty control sits below the count and is clearly marked when on.

### Fixed

- Items added on the Gear tab now go to the backpack instead of the equipment slots.

## [4.17.0] - 2026-10-14

### Added
- Weapons in a loadout now show their installed attachments on the preview art.
- Equipment slots that hold a nested item (armor plate, NVG) show a small gear mark.

### Changed
- The remove button on equipment slots moved to the top-right corner and is easier to hit.

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
