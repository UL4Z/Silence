# Silence v2 — Universal Auto Parry

**Silence** is a modular, high-precision auto-parry and animation logging tool for Roblox.

## Status
- **Universal**: Supports any game with animation-driven combat.
- **Precision**: Uses Beta-distribution confidence modeling for timing.
- **Visual**: Real-time animation scrubber and builder.

## How to use
Run this script in your favorite high-caliber executor (Potassium, Volt):

```lua
_G.SilenceUser = "UL4Z"
loadstring(game:HttpGet("https://raw.githubusercontent.com/UL4Z/Silence/main/Loader.lua"))()
```

## Setup for UL4Z
If you are first setting up the repo:
1. Create a repository on GitHub named `Silence`.
2. Push these files to the `main` branch.
3. The loader above will automatically fetch all modules.

## Performance
Silence v2 is event-driven and does not rely on heavy frame-by-frame polling, ensuring minimal impact on your FPS even in complex games.
