# Gadget System

This system scans a map for gadget models and builds server + client gadget instances. Gadgets are server-authoritative for validation, and clients request use through remotes.

## Map Setup
Place gadgets under the map instance:

- `workspace.World`
  - `Gadgets`
    - `Zipline` (Folder)
      - `Zipline_01` (Model)
      - `Zipline_02` (Model)
    - `JumpPad` (Folder)
      - `JumpPad_01` (Model)

Each gadget model should include:

- Attribute `GadgetType` with value `"Zipline"` or `"JumpPad"`
- Optional attribute `GadgetId` (auto-generated if missing)

JumpPad attributes:
- `LaunchSpeed` (number, default 120)
- `UseLookVector` (boolean, default true)
- `LaunchDirection` (Vector3, used when `UseLookVector` is false)
- `UseDistance` (number, default 12)
- `UseCooldown` (number, default 0.5)

JumpPad model parts:
- `BouncePart` (preferred)
- `Root` (fallback if `BouncePart` missing)

## Server Usage
The server automatically scans `workspace.World` at startup:

- `GadgetService:Start()` calls `CreateForMap(workspace.World, nil)`

To scan a different map instance:

```
local gadgetService = registry:TryGet("GadgetService")
if gadgetService then
	gadgetService:CreateForMap(mapInstance, {
		Zipline = {},
		JumpPad = {},
	})
end
```

## Client Flow
Client requests gadget init after local character spawns:

- Client sends `GadgetInitRequest`
- Server replies with `GadgetInit` payload
- Client creates local gadget instances from the payload

## Core Modules

### Gadgets (Registry / Factory)
`src/ReplicatedStorage/Game/Gadgets/init.lua`

Methods:
- `Gadgets.new()`
- `Gadgets:register(typeName, class)`
- `Gadgets:setFallbackClass(class)`
- `Gadgets:getById(id)`
- `Gadgets:createFromModel(typeName, model, data, isServer, mapInstance)`
- `Gadgets:scanMap(mapInstance, dataByType, isServer)`
- `Gadgets:removeById(id)`
- `Gadgets:clear()`

### GadgetBase (Base Class)
`src/ReplicatedStorage/Game/Gadgets/GadgetBase.lua`

Methods:
- `GadgetBase.new(params)`
- `:getId()`
- `:getTypeName()`
- `:getModel()`
- `:getData()`
- `:setData(data)`
- `:onServerCreated()`
- `:onClientCreated()`
- `:onUseRequest(player, payload)`
- `:onUseResponse(approved)`
- `:destroy()`

### GadgetService (Server)
`src/ServerScriptService/Server/Services/Gadgets/GadgetService.lua`

Methods:
- `:Register(typeName, class)`
- `:CreateForMap(mapInstance, dataByType)`
- `:ClearForMap(mapInstance)`
- `:SendInitToPlayer(player)`

### GadgetController (Client)
`src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/Gadgets/GadgetController.lua`

Methods:
- `:RequestUse(gadgetId, payload)`

## Remotes
Defined in `src/ReplicatedStorage/Shared/Net/Remotes.lua`:

- `GadgetInitRequest` (client -> server)
- `GadgetInit` (server -> client)
- `GadgetUseRequest` (client -> server)
- `GadgetUseResponse` (server -> client)
