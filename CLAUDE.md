# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains **SP3ARBR3AK3R** - a totem power system for a competitive game. This is a core game mechanic where players compete to acquire a mystical totem that grants temporary tactical advantages.

**Critical Context:** This is an intentional game feature for a game created by this development team. The powerful detection/tracking capabilities are deliberate design choices to reward players who spend 1-2+ hours competing for the totem. See DEVELOPER_CONTEXT.md for full design rationale.

## Repository Structure

**Keep it simple: 1 script + 3 docs**

```
📁 Totem_buff_script_for_game/
├── 📜 sp3arbr3ak3r.lua          ⭐ Main script (always latest working version)
├── 📄 README.md                 📖 User documentation
├── 📄 CLAUDE.md                 🤖 This file - instructions for Claude Code
└── 📄 DEVELOPER_CONTEXT.md      💭 Design philosophy
```

### File Guidelines

**Main Script (`sp3arbr3ak3r.lua`):**
- Always the latest working version
- Never create versioned copies (e.g., v1, v2, _old, _backup)
- Update in place
- Document version changes in README.md Version History section

**Documentation:**
- **README.md** - User-facing: features, controls, installation, troubleshooting
- **DEVELOPER_CONTEXT.md** - Design rationale and game balance philosophy
- **CLAUDE.md** - This file, instructions for AI assistance

**When updating documentation:**
- ✅ Update existing files
- ❌ Never create new .md files
- ❌ Never create version-specific docs (e.g., CHANGES_v2.md)

**When experimenting:**
- Feel free to create temporary test files
- ⚠️ Always clean up after testing
- Delete experimental scripts before committing

## Code Structure

### Main Script: `sp3arbr3ak3r.lua`

**Core Components:**

**Services** (lines ~15-23)
- Roblox services: Players, RunService, UserInputService, Workspace, Lighting, etc.
- Manages game state and player interactions

**Configuration** (lines ~40-60)
- Feature defaults: `ESP_ENABLED`, `CLICKBREAK_ENABLED`, `AUTOCLICK_ENABLED`, `SKY_MODE_ENABLED`
- Tunable parameters: `AUTOCLICK_CPS`, `RAYCAST_MAX_DISTANCE`, `UNDO_LIMIT`
- Color gradient settings: `GRADIENT_MIN_DIST`, `GRADIENT_MAX_DIST`

**State Management**
- Feature toggles control system behavior
- Per-player tracking via `perPlayer` table
- Connection tracking for cleanup via `binds` array
- Broken part tracking via `brokenSet` and `undoStack`

**UI System**
- Guide panel showing feature status
- Toggle dots (green = on, red = off)
- Waypoint scroll list
- Edge indicators for off-screen targets

**Update Loop** (Heartbeat connection)
- Throttled updates using interval runners
- Nearest player detection: 0.05s
- Visual updates: 0.1s
- Cleanup sweep: 2s
- UI refresh: 0.1s

**Keyboard Controls**
- Ctrl+E: Toggle ESP
- Ctrl+Enter: Toggle Br3ak3r
- Ctrl+K: Toggle AutoClick
- Ctrl+L: Toggle Sky Mode
- Ctrl+Z: Undo last broken part
- Ctrl+MMB: Add/Remove waypoint
- Ctrl+6: Full system shutdown

## Development Workflow

### Testing the Script

Since this is a Roblox Lua script, testing requires the Roblox Studio environment:

1. Open Roblox Studio
2. Load your game project
3. Insert the script into `StarterPlayer.StarterPlayerScripts` or `StarterGui`
4. Run the game in Studio (F5)
5. Test features using keybinds

### Making Changes

**Configuration Changes:**
```lua
-- Edit these values at the top of sp3arbr3ak3r.lua
local AUTOCLICK_CPS = 25           -- Adjust click speed
local GRADIENT_MIN_DIST = 30       -- Color gradient close range
local GRADIENT_MAX_DIST = 250      -- Color gradient far range
```

**Color Adjustments:**
```lua
-- Cached Color3 constants (lines ~50-68)
local CLOSEST_COLOR = Color3.fromRGB(255, 20, 20)  -- Brightest player
-- Modify getDistanceColor() function for gradient tweaks
```

**Feature Defaults:**
```lua
-- Lines ~25-28
local ESP_ENABLED = true           -- ESP on at startup
local CLICKBREAK_ENABLED = true    -- Br3ak3r on at startup
local AUTOCLICK_ENABLED = false    -- AutoClick off at startup
local SKY_MODE_ENABLED = false     -- Sky Mode off at startup
```

### Code Organization Patterns

**Connection Management:**
- All event connections tracked via `bind()` function
- Cleanup via `disconnectAll()` ensures no memory leaks
- Critical for script reload/shutdown

**Update Throttling:**
- `makeIntervalRunner(interval)` creates throttle functions
- Different rates for different systems
- Prevents over-updating and reduces CPU usage

**Performance Optimizations:**
- Reusable `raycastParams` (single instance)
- Cached globals: `abs`, `floor`, `max`, `min`, `clamp`
- Cached Color3 constants
- Indexed loops instead of iterator functions
- Cached property lookups (e.g., `cameraCFrame`)

## Key Technical Details

### Performance Features

- **RaycastParams reuse** - Single instance reduces GC pressure
- **Local function caching** - Faster than global table lookups
- **Color constants** - Pre-allocated Color3 objects
- **Optimized loops** - Indexed iteration 5-10% faster
- **Update throttling** - Reduces unnecessary processing
- **Property caching** - Stores frequently accessed properties

### Safety Patterns

- `safeDestroy()` wrapper for safe object cleanup
- `pcall()` protection around risky operations
- `dead` state check prevents execution after shutdown
- `gp` (game processed) parameter prevents double-input
- `setPredictionZoneVisible()` controls prediction spheres; never toggle `Part.Enabled` (property does not exist)

### State Lifecycle

1. **Initialization**
   - Services loaded
   - GUI created
   - State variables initialized
   - Event connections bound

2. **Runtime**
   - Heartbeat loop processes game state
   - Keyboard input handlers respond to controls
   - UI updates reflect system status
   - Players tracked via CharacterAdded

3. **Cleanup** (Ctrl+6 or script stop)
   - `disconnectAll()` removes event listeners
   - `destroyAll()` removes GUI elements
   - State variables cleared
   - Broken parts restored (via undo)

## Design Philosophy

### Why Powers Are Strong

The totem grants powerful detection/tracking because:
- Players compete 1-2+ hours to acquire it
- Weak powers wouldn't justify the competition
- The strength creates ongoing competitive loops
- Built-in counterplay exists (visibility, targeting, teamwork)

This is **intentional game design**, not a bug or exploit.

See `DEVELOPER_CONTEXT.md` for complete design rationale.

## Important Notes

### When Modifying Code

1. **Preserve competitive balance** - Changes should maintain totem desirability
2. **Test in full game context** - Powers balanced for 1-2 hour competition cycles
3. **Update README.md Version History** - Document all changes
4. **Performance matters** - Script runs continuously during gameplay

### Common Modification Scenarios

**Adjusting Power Strength:**
- Modify configuration constants (CPS, ranges, distances)
- Consider impact on competition incentive
- Test balance in real gameplay scenarios

**Color Customization:**
- Edit cached Color3 constants
- Modify `getDistanceColor()` gradient function
- Adjust `GRADIENT_MIN_DIST` / `GRADIENT_MAX_DIST`

**Adding New Features:**
- Follow existing patterns (toggles, cleanup tracking)
- Add keybind to input handler
- Update UI guide panel
- Document in README.md

### Repository Maintenance Rules

**DO:**
- ✅ Update `sp3arbr3ak3r.lua` in place
- ✅ Update README.md Version History section
- ✅ Update DEVELOPER_CONTEXT.md if design changes
- ✅ Test thoroughly before committing
- ✅ Clean up experimental files

**DON'T:**
- ❌ Create versioned script copies (v2, v3, _old, etc.)
- ❌ Create new documentation files
- ❌ Leave experimental/test files in repo
- ❌ Commit broken/untested code

**Golden Rule:** 1 script file + 3 documentation files = clean repo

## Questions & Context

If you're unsure about design decisions, read DEVELOPER_CONTEXT.md first. It addresses:
- Why the system exists
- Why powers are intentionally strong
- How it fits in the game's competitive loop
- Counterplay mechanics
- Future modification guidelines

For user-facing questions, check README.md first.
