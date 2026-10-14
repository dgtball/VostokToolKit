# ThermalVTK

**Version:** 1.0.0

Standalone NVG / thermal-vision mod for Road to Vostok. It is the thermal
feature of Vostok Toolkit, packaged on its own.

> **Do not run this together with Vostok Toolkit.** Both mods patch the same
> in-game NVG material and will fight over it. Install one or the other.

## What it does

- Replaces the vanilla NVG overlay shader with an adjustable one (noise,
  brightness).
- Adds a thermal layer on top of NVG: bounty bots glow with a heat signature
  that cools after death, mines light up, and friendly Nomads get a floating
  marker.
- World palettes, bot colour presets, glow distance, and winter auto-dimming.
- A hotkey to turn the thermal layer on and off, with an on-screen
  notification.

## Install

1. Copy `ThermalVTK.vmz` into the game's `mods` folder.
2. Make sure Mod Configuration Menu is installed.
3. Open the MCM menu, set `ThermalVTK` up (bind the toggle hotkey there).

## Build (from the repo)

```powershell
powershell -ExecutionPolicy Bypass -File pack.ps1
```
