--[[
    Hitbox.lua
    
    Hitbox detection utility for finding players and NPCs in areas.
    Non-blocking, runs queries in separate threads when using duration.
    
    API:
        -- Instant sphere check (returns Players only)
        local players = Hitbox.GetEntitiesInSphere(position, radius, exclude?)
        
        -- Instant sphere check (returns character Models - players AND dummies/NPCs)
        local characters = Hitbox.GetCharactersInSphere(position, radius, exclude?)
        
        -- Lingering sphere check (returns handle)
        local handle = Hitbox.GetEntitiesInSphere(position, radius, {
            Exclude = player,
            Duration = 2,
        })
        local hits = handle:GetHits()
        handle:Stop()
        
        -- Instant raycast
        local player, hitPos = Hitbox.Raycast(origin, direction, distance, exclude?)
        
        -- Lingering raycast (returns handle)
        local handle = Hitbox.Raycast(origin, direction, distance, {
            Exclude = player,
            Duration = 0.3,
        })

        -- Instant box check (config table)
        local players = Hitbox.GetEntitiesInBox({
            Position = origin,
            Size = Vector3.new(6, 6, 6),
            Exclude = player,
            Visualize = true,
        })
        
        -- Instant box check returning characters (players AND dummies)
        local characters = Hitbox.GetCharactersInBox({...})
        
        -- SERVER-SIDE: Magnitude-based sphere check using ReplicationService positions
        -- (Use this on server where Collider CanQuery may not be set)
        Hitbox.SetReplicationService(replicationService) -- Call once in Initializer
        local characters = Hitbox.GetCharactersInRadius(position, radius, excludePlayer?)
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Hitbox = {}

local CHECK_INTERVAL = 0.03 -- ~30hz

----------------------------------------------------------------
-- SERVER-SIDE REPLICATION SERVICE INTEGRATION
----------------------------------------------------------------

-- Server-side service reference (set via Hitbox.SetReplicationService)
local _replicationService = nil

--[[
    Set ReplicationService for server-side position lookups.
    Call this from server Initializer after services are loaded.
]]
function Hitbox.SetReplicationService(service)
    _replicationService = service
end

--[[
    Get player position using ReplicationService (server) or Root (fallback).
]]
local function getReplicatedPlayerPosition(player)
    -- Try ReplicationService first (accurate client-replicated position)
    if _replicationService and _replicationService.PlayerStates then
        local state = _replicationService.PlayerStates[player]
        if state and state.LastState and state.LastState.Position then
            return state.LastState.Position
        end
    end
    
    -- Fallback to character Root
    local character = player.Character
    if character then
        local root = character:FindFirstChild("Root") 
            or character:FindFirstChild("HumanoidRootPart")
            or character.PrimaryPart
        if root then
            return root.Position
        end
    end
    
    return nil
end

--[[
    Server-friendly sphere check using magnitude (no CanQuery dependency).
    Uses ReplicationService for accurate player positions.
    
    @param position Vector3 - Center of sphere
    @param radius number - Radius of sphere
    @param excludePlayer Player? - Player to exclude (typically caster)
    @return {Model} - Array of character Models (players AND dummies)
]]
function Hitbox.GetCharactersInRadius(position: Vector3, radius: number, excludePlayer: Player?)
    local found = {}
    local seen = {}
    
    -- Check all players using replicated positions
    for _, player in ipairs(Players:GetPlayers()) do
        if player == excludePlayer then continue end
        
        local character = player.Character
        if not character then continue end
        
        -- Check if character has a valid humanoid
        local humanoid = character:FindFirstChildWhichIsA("Humanoid", true)
        if not humanoid or humanoid.Health <= 0 then continue end
        
        local playerPos = getReplicatedPlayerPosition(player)
        if not playerPos then continue end
        
        local dist = (playerPos - position).Magnitude
        if dist <= radius then
            if not seen[character] then
                seen[character] = true
                table.insert(found, character)
            end
        end
    end
    
    -- Check dummies (tagged as AimAssistTarget, their Root.Position is accurate on server)
    for _, dummy in ipairs(CollectionService:GetTagged("AimAssistTarget")) do
        if not dummy:IsA("Model") then continue end
        if seen[dummy] then continue end
        
        local humanoid = dummy:FindFirstChildWhichIsA("Humanoid", true)
        if not humanoid or humanoid.Health <= 0 then continue end
        
        local root = dummy:FindFirstChild("Root") or dummy.PrimaryPart
        if not root then continue end
        
        local dist = (root.Position - position).Magnitude
        if dist <= radius then
            seen[dummy] = true
            table.insert(found, dummy)
        end
    end
    
    return found
end

----------------------------------------------------------------
-- INTERNAL HELPERS
----------------------------------------------------------------

local function buildExcludeList(exclude)
    local list = {}
    
    if exclude then
        if typeof(exclude) == "Instance" and exclude:IsA("Player") then
            if exclude.Character then
                table.insert(list, exclude.Character)
            end
        elseif typeof(exclude) == "Instance" and exclude:IsA("Model") then
            -- Direct character/model exclusion
            table.insert(list, exclude)
        elseif type(exclude) == "table" then
            -- Could be array of players/characters or config table
            for key, val in exclude do
                if typeof(val) == "Instance" then
                    if val:IsA("Player") and val.Character then
                        table.insert(list, val.Character)
                    elseif val:IsA("Model") then
                        table.insert(list, val)
                    end
                end
            end
        end
    end
    
    -- Always exclude Rigs folder (visual only, not real targets)
    local rigsFolder = Workspace:FindFirstChild("Rigs")
    if rigsFolder then
        table.insert(list, rigsFolder)
    end
    
    return list
end

--[[
    Resolves a hit part to its owning character Model.
    Handles all character structures:
    - Character/Collider/Hitbox/Standing|Crouching/Part (new hitbox structure)
    - Character/Collider/Default|Crouch/Part (legacy collision structure)
    - Dummy/Root/Part (dummy collision parts inside Root)
    - Character/Hitbox/Part (simple hitbox folder)
    
    Returns the character Model (must have Humanoid) or nil.
]]
local function resolveCharacter(part, excludeCharacter)
    if not part then return nil end
    
    local current = part.Parent
    
    -- Handle new Hitbox structure: Character/Collider/Hitbox/Standing|Crouching/Part
    if current and (current.Name == "Standing" or current.Name == "Crouching") then
        local hitboxFolder = current.Parent
        if hitboxFolder and hitboxFolder.Name == "Hitbox" then
            local colliderFolder = hitboxFolder.Parent
            if colliderFolder and colliderFolder.Name == "Collider" then
                current = colliderFolder.Parent
            end
        end
    end
    
    -- Handle legacy Collider structure: Character/Collider/Default|Crouch/Part
    if current and (current.Name == "Default" or current.Name == "Crouch") then
        local colliderFolder = current.Parent
        if colliderFolder and colliderFolder.Name == "Collider" then
            current = colliderFolder.Parent
        end
    end
    
    -- Handle Collider folder directly: Character/Collider/Part
    if current and current.Name == "Collider" then
        current = current.Parent
    end
    
    -- Handle Root (dummies have collision parts inside Root BasePart): Dummy/Root/Body
    if current and current:IsA("BasePart") and current.Name == "Root" then
        current = current.Parent
    end
    
    -- Handle simple Hitbox folder: Character/Hitbox/Part
    if current and current.Name == "Hitbox" and current:IsA("Folder") then
        current = current.Parent
    end
    
    -- Walk up to find character model with Humanoid
    local maxDepth = 5
    local depth = 0
    while current and current ~= Workspace and depth < maxDepth do
        if current:IsA("Model") then
            -- Skip visual Rigs (they don't have Humanoid anyway)
            if current.Name == "Rig" then
                return nil
            end
            -- Valid target: Must have Humanoid and not be excluded
            if current:FindFirstChildOfClass("Humanoid") and current ~= excludeCharacter then
                return current
            end
        end
        current = current.Parent
        depth = depth + 1
    end
    
    return nil
end

-- Legacy: resolves to Player only (for backwards compatibility)
local function resolvePlayer(part)
    if not part then return nil end
    
    local character = resolveCharacter(part, nil)
    if character then
        return Players:GetPlayerFromCharacter(character)
    end
    
    return nil
end

local function parseConfig(config)
    if not config then
        return nil, nil
    end

    if type(config) == "table" then
        return config.Exclude, config.Duration
    end

    return config, nil
end

local function shouldVisualize(config)
    return type(config) == "table" and config.Visualize == true
end

local function getVisualizationOptions(config)
    if type(config) == "table" then
        return config.VisualizeDuration or 0.2, config.VisualizeColor
    end
    return 0.2, nil
end

local function visualizeSphere(position: Vector3, radius: number, duration: number, color: Color3?)
    local part = Instance.new("Part")
    part.Name = "HitboxSphereViz"
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
    part.CFrame = CFrame.new(position)
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Transparency = 0.7
    part.Color = color or Color3.fromRGB(0, 200, 255)
    part.Parent = Workspace
    Debris:AddItem(part, duration)
end

local function visualizeBox(cframe: CFrame, size: Vector3, duration: number, color: Color3?)
    local part = Instance.new("Part")
    part.Name = "HitboxBoxViz"
    part.Size = size
    part.CFrame = cframe
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Transparency = 0.7
    part.Color = color or Color3.fromRGB(0, 200, 255)
    part.Parent = Workspace
    Debris:AddItem(part, duration)
end

----------------------------------------------------------------
-- LINGERING HANDLE
----------------------------------------------------------------

local HitboxHandle = {}
HitboxHandle.__index = HitboxHandle

function HitboxHandle:GetHits(): {Player}
    local result = {}
    for player in self._seen do
        table.insert(result, player)
    end
    return result
end

function HitboxHandle:Stop()
    self._stopped = true
end

function HitboxHandle:IsRunning(): boolean
    return not self._stopped
end

local function createHandle()
    return setmetatable({
        _seen = {},
        _stopped = false,
    }, HitboxHandle)
end

----------------------------------------------------------------
-- SPHERE
----------------------------------------------------------------

function Hitbox.GetEntitiesInSphere(position: Vector3, radius: number, configOrExclude: any?)
    local exclude, duration = parseConfig(configOrExclude)
    local excludeList = buildExcludeList(exclude)
    
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludeList
    
    if shouldVisualize(configOrExclude) then
        local vizDuration, vizColor = getVisualizationOptions(configOrExclude)
        visualizeSphere(position, radius, vizDuration, vizColor)
    end

    -- Instant check (no duration)
    if not duration then
        local parts = Workspace:GetPartBoundsInRadius(position, radius, params)
        
        local seen = {}
        local found = {}
        
        for _, part in parts do
            local player = resolvePlayer(part)
            if player and not seen[player] then
                seen[player] = true
                table.insert(found, player)
            end
        end
        
        return found
    end
    
    -- Lingering check (with duration) - runs in separate thread
    local handle = createHandle()
    
    task.spawn(function()
        local elapsed = 0
        while elapsed < duration and not handle._stopped do
            local parts = Workspace:GetPartBoundsInRadius(position, radius, params)
            for _, part in parts do
                local player = resolvePlayer(part)
                if player then
                    handle._seen[player] = true
                end
            end
            task.wait(CHECK_INTERVAL)
            elapsed += CHECK_INTERVAL
        end
        handle._stopped = true
    end)
    
    return handle
end

----------------------------------------------------------------
-- CHARACTERS IN SPHERE (returns Models, not Players)
----------------------------------------------------------------

--[[
    Returns all character Models (players AND dummies/NPCs) in a sphere.
    Unlike GetEntitiesInSphere which returns Player instances,
    this returns the character Model directly (useful for knockback, damage, etc.)
]]
function Hitbox.GetCharactersInSphere(position: Vector3, radius: number, configOrExclude: any?)
    local exclude, duration = parseConfig(configOrExclude)
    local excludeList = buildExcludeList(exclude)
    
    -- Get the character to exclude (for resolveCharacter check)
    local excludeCharacter = nil
    if exclude then
        if typeof(exclude) == "Instance" and exclude:IsA("Player") then
            excludeCharacter = exclude.Character
        elseif typeof(exclude) == "Instance" and exclude:IsA("Model") then
            excludeCharacter = exclude
        elseif type(exclude) == "table" and exclude.Exclude then
            local e = exclude.Exclude
            if typeof(e) == "Instance" and e:IsA("Player") then
                excludeCharacter = e.Character
            elseif typeof(e) == "Instance" and e:IsA("Model") then
                excludeCharacter = e
            end
        end
    end
    
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludeList
    
    if shouldVisualize(configOrExclude) then
        local vizDuration, vizColor = getVisualizationOptions(configOrExclude)
        visualizeSphere(position, radius, vizDuration, vizColor)
    end

    -- Instant check (no duration)
    if not duration then
        local parts = Workspace:GetPartBoundsInRadius(position, radius, params)
        
        local seen = {}
        local found = {}
        
        for _, part in parts do
            local character = resolveCharacter(part, excludeCharacter)
            if character and not seen[character] then
                seen[character] = true
                table.insert(found, character)
            end
        end
        
        return found
    end
    
    -- Lingering check (with duration) - runs in separate thread
    local handle = createHandle()
    
    task.spawn(function()
        local elapsed = 0
        while elapsed < duration and not handle._stopped do
            local parts = Workspace:GetPartBoundsInRadius(position, radius, params)
            for _, part in parts do
                local character = resolveCharacter(part, excludeCharacter)
                if character then
                    handle._seen[character] = true
                end
            end
            task.wait(CHECK_INTERVAL)
            elapsed += CHECK_INTERVAL
        end
        handle._stopped = true
    end)
    
    return handle
end

----------------------------------------------------------------
-- BOX (SQUARE/RECT)
----------------------------------------------------------------

function Hitbox.GetEntitiesInBox(config: any)
    if type(config) ~= "table" then
        warn("[Hitbox] GetEntitiesInBox expects a config table")
        return {}
    end

    local cframe = config.CFrame
    local boxSize = config.Size
    if not cframe then
        local position = config.Position or config.Center
        if position then
            cframe = CFrame.new(position)
        end
    end

    if not cframe or not boxSize then
        warn("[Hitbox] GetEntitiesInBox missing cframe/size")
        return {}
    end

    local exclude, duration = parseConfig(config)
    local excludeList = buildExcludeList(exclude)

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludeList

    if shouldVisualize(config) then
        local vizDuration, vizColor = getVisualizationOptions(config)
        visualizeBox(cframe, boxSize, vizDuration, vizColor)
    end

    -- Instant check (no duration)
    if not duration then
        local parts = Workspace:GetPartBoundsInBox(cframe, boxSize, params)

        local seen = {}
        local found = {}

        for _, part in parts do
            local player = resolvePlayer(part)
            if player and not seen[player] then
                seen[player] = true
                table.insert(found, player)
            end
        end

        return found
    end

    -- Lingering check (with duration) - runs in separate thread
    local handle = createHandle()

    task.spawn(function()
        local elapsed = 0
        while elapsed < duration and not handle._stopped do
            local parts = Workspace:GetPartBoundsInBox(cframe, boxSize, params)
            for _, part in parts do
                local player = resolvePlayer(part)
                if player then
                    handle._seen[player] = true
                end
            end
            task.wait(CHECK_INTERVAL)
            elapsed += CHECK_INTERVAL
        end
        handle._stopped = true
    end)

    return handle
end

----------------------------------------------------------------
-- CHARACTERS IN BOX (returns Models, not Players)
----------------------------------------------------------------

--[[
    Returns all character Models (players AND dummies/NPCs) in a box.
]]
function Hitbox.GetCharactersInBox(config: any)
    if type(config) ~= "table" then
        warn("[Hitbox] GetCharactersInBox expects a config table")
        return {}
    end

    local cframe = config.CFrame
    local boxSize = config.Size
    if not cframe then
        local position = config.Position or config.Center
        if position then
            cframe = CFrame.new(position)
        end
    end

    if not cframe or not boxSize then
        warn("[Hitbox] GetCharactersInBox missing cframe/size")
        return {}
    end

    local exclude, duration = parseConfig(config)
    local excludeList = buildExcludeList(exclude)
    
    -- Get the character to exclude
    local excludeCharacter = nil
    if config.Exclude then
        local e = config.Exclude
        if typeof(e) == "Instance" and e:IsA("Player") then
            excludeCharacter = e.Character
        elseif typeof(e) == "Instance" and e:IsA("Model") then
            excludeCharacter = e
        end
    end

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludeList

    if shouldVisualize(config) then
        local vizDuration, vizColor = getVisualizationOptions(config)
        visualizeBox(cframe, boxSize, vizDuration, vizColor)
    end

    -- Instant check (no duration)
    if not duration then
        local parts = Workspace:GetPartBoundsInBox(cframe, boxSize, params)

        local seen = {}
        local found = {}

        for _, part in parts do
            local character = resolveCharacter(part, excludeCharacter)
            if character and not seen[character] then
                seen[character] = true
                table.insert(found, character)
            end
        end

        return found
    end

    -- Lingering check (with duration) - runs in separate thread
    local handle = createHandle()

    task.spawn(function()
        local elapsed = 0
        while elapsed < duration and not handle._stopped do
            local parts = Workspace:GetPartBoundsInBox(cframe, boxSize, params)
            for _, part in parts do
                local character = resolveCharacter(part, excludeCharacter)
                if character then
                    handle._seen[character] = true
                end
            end
            task.wait(CHECK_INTERVAL)
            elapsed += CHECK_INTERVAL
        end
        handle._stopped = true
    end)

    return handle
end

----------------------------------------------------------------
-- RAYCAST
----------------------------------------------------------------

function Hitbox.Raycast(origin: Vector3, direction: Vector3, distance: number, configOrExclude: any?)
    local exclude, duration = parseConfig(configOrExclude)
    local excludeList = buildExcludeList(exclude)
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludeList
    
    local dir = direction.Unit * distance

    if shouldVisualize(configOrExclude) then
        local vizDuration, vizColor = getVisualizationOptions(configOrExclude)
        visualizeBox(CFrame.new(origin + (dir / 2), origin + dir), Vector3.new(0.12, 0.12, distance), vizDuration, vizColor)
    end
    
    -- Instant check (no duration)
    if not duration then
        local result = Workspace:Raycast(origin, dir, params)
        if result then
            return resolvePlayer(result.Instance), result.Position
        end
        return nil, nil
    end
    
    -- Lingering check (with duration) - runs in separate thread
    local handle = createHandle()
    
    task.spawn(function()
        local elapsed = 0
        while elapsed < duration and not handle._stopped do
            local result = Workspace:Raycast(origin, dir, params)
            if result then
                local player = resolvePlayer(result.Instance)
                if player then
                    handle._seen[player] = true
                end
            end
            task.wait(CHECK_INTERVAL)
            elapsed += CHECK_INTERVAL
        end
        handle._stopped = true
    end)
    
    return handle
end

return Hitbox
