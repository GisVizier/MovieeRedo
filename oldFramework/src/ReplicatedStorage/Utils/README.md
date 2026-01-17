# Utilities

## 🛠️ Helper Functions

This folder contains pure utility functions - no state, just helpers.

## Categories

### Math & Numbers
- **MathUtils.lua** - Math helpers
- **NumberUtils.lua** - Number formatting and utilities

### Data Structures
- **TableUtils.lua** - Table manipulation
- **PathUtils.lua** - Path utilities

### Time & Async
- **TimerUtils.lua** - Timer helpers
- **AsyncUtils.lua** - Async utilities

### Physics & Parts
- **PartUtils.lua** - Part utilities
- **WeldUtils.lua** - Weld utilities
- **CollisionUtils.lua** - Collision helpers
- **WallDetectionUtils.lua** - Wall detection

### Data
- **CompressionUtils.lua** - Data compression
- **ValidationUtils.lua** - Data validation
- **ConfigValidator.lua** - Config validation

### Direction Detection
- **SlideDirectionDetector.lua** - Slide direction
- **WalkDirectionDetector.lua** - Walk direction
- **WallBoostDirectionDetector.lua** - Wall boost direction

### Core Utilities
- **ServiceLoader.lua** - Module loader
- **ServiceRegistry.lua** - Service registry
- **DebugPrint.lua** - Debug printing
- **InputDisplayUtil.lua** - Input display

### Serialization
- **Sera/** - High-performance serialization library
  - **init.lua** - Main Sera module
  - **Schemas.lua** - Serialization schemas

## Usage

All utilities are pure functions - just require and use:

```lua
local MathUtils = require(Locations.Modules.Utils.MathUtils)
local result = MathUtils.Clamp(value, min, max)
```

## Dependencies

- Utils use `Locations` for module paths
- Utils are independent (no dependencies on each other)

