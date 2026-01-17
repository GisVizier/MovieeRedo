# CoreUI - Declarative UI Framework

CoreUI is a declarative UI system that pairs UI modules with UI elements created in Roblox Studio. Unlike programmatic UI creation (using `:New()`), UI elements are created visually in Studio, and modules control their behavior.

## How It Works

1. **UI Creation**: UI elements are created in Roblox Studio as children of a ScreenGui
2. **Module Discovery**: CoreUI automatically discovers modules in `CoreUI/Modules/`
3. **Name Matching**: Module names must match UI element names exactly
4. **Behavior Control**: Modules control animations, interactions, and state

## Architecture

### Core Components

- **CoreUI (init.lua)**: Main controller that manages modules and UI lifecycle
- **Signal.lua**: Event system for module communication
- **ConnectionManager.lua**: Manages event connections with cleanup
- **TweenLibrary.lua**: Helper library for UI animations

### Module Structure

Each UI module must:
1. Be placed in `ReplicatedStorage/CoreUI/Modules/`
2. Have a name matching a UI element in the ScreenGui
3. Export a `start(export, ui)` function
4. Return a module instance with `show()` and optionally `hide()` methods

## Usage

### Initialization

CoreUI is automatically initialized through `UIManager`:

```lua
local UIManager = require(Locations.Client.UI.UIManager)
local uiManager = UIManager.new()
uiManager:Init()

-- Access CoreUI controller
local coreUIController = uiManager:GetModule("CoreUIController")
```

### Creating a UI Module

1. **Create UI in Studio**:
   - Create a ScreenGui named "CoreUI" in PlayerGui (or it will be auto-created)
   - Add a Frame (or other GuiObject) with the name matching your module

2. **Create Module Script**:
   ```lua
   -- ReplicatedStorage/CoreUI/Modules/MyUI.lua
   local module = {}
   module.__index = module
   
   function module.start(export, ui)
       local self = setmetatable({}, module)
       self._export = export
       self._ui = ui
       self._tween = export.tween
       self._connections = export.connections
       return self
   end
   
   function module:show()
       self._ui.Visible = true
       -- Add animations, setup, etc.
       return true
   end
   
   function module:hide()
       self._ui.Visible = false
       return true
   end
   
   return module
   ```

3. **Show/Hide Modules**:
   ```lua
   local coreUIController = uiManager:GetModule("CoreUIController")
   coreUIController:ShowModule("MyUI")
   coreUIController:HideModule("MyUI")
   ```

## Export API

Each module receives an `export` object with these methods:

### Module Management
- `export:show(name, force)` - Show a module
- `export:hide(name)` - Hide a module
- `export:isOpen(name)` - Check if module is open
- `export:getModule(name)` - Get another module instance

### Events
- `export:on(eventName, callback)` - Listen to events
- `export:emit(eventName, ...)` - Emit events

### UI Property Management
- `export:getOriginals(path)` - Get original property values
- `export:resetToOriginals(path, tweenInfo)` - Reset to original values
- `export:applyToElement(path, properties, tweenInfo)` - Apply properties with tweening
- `export:getInstance(path)` - Get UI instance by path

### Utilities
- `export.tween` - TweenLibrary instance
- `export.connections` - ConnectionManager for this module

## Example: Animated Menu

```lua
local module = {}
module.__index = module

function module.start(export, ui)
    local self = setmetatable({}, module)
    self._export = export
    self._ui = ui
    self._tween = export.tween
    self._connections = export.connections
    
    -- Cache UI elements
    self._menuFrame = ui:FindFirstChild("MenuFrame")
    self._closeButton = ui:FindFirstChild("CloseButton")
    
    -- Setup button
    self._connections:track(self._closeButton, "Activated", function()
        self._export:hide()
    end, "buttons")
    
    return self
end

function module:show()
    self._ui.Visible = true
    
    -- Animate in
    self._tween:fadeIn(self._menuFrame, 0.3, "show")
    self._tween:slideIn(self._menuFrame, "top", 0.4, "show")
    
    return true
end

function module:hide()
    -- Animate out
    self._tween:fadeOut(self._menuFrame, 0.3, "hide")
    
    task.wait(0.3)
    self._ui.Visible = false
    
    return true
end

function module:_cleanup()
    self._connections:cleanupGroup("buttons")
end

return module
```

## Key Features

- **Declarative**: UI created in Studio, not code
- **Automatic Discovery**: Modules are auto-discovered by name
- **Property Capture**: Original UI properties are captured for animations
- **Event System**: Built-in event system for module communication
- **Connection Management**: Automatic cleanup of connections
- **Tweening**: Built-in tween library for smooth animations

## Best Practices

1. **Naming**: Module names must exactly match UI element names
2. **Cleanup**: Always use `export.connections` for event tracking
3. **Animations**: Use `export.tween` for all animations
4. **State Management**: Store state in module instance, not UI elements
5. **Path References**: Use dot notation for nested UI paths (e.g., "Menu.Button")

## See Also

- `Example.lua` - Template for creating new modules
- `TweenLibrary.lua` - Animation helper methods
- `ConnectionManager.lua` - Event connection management
