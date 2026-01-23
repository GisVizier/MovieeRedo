--[[
    Hitbox.lua
    
    Simple hitbox detection utility for finding players in areas.
    Non-blocking, runs queries in separate threads when using duration.
    
    API:
        -- Instant sphere check
        local players = Hitbox.GetEntitiesInSphere(position, radius, exclude?)
        
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
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Hitbox = {}

local CHECK_INTERVAL = 0.03 -- ~30hz

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
        elseif type(exclude) == "table" then
            -- Could be array of players or config table
            for key, val in exclude do
                if typeof(val) == "Instance" and val:IsA("Player") and val.Character then
                    table.insert(list, val.Character)
                end
            end
        end
    end
    
    -- Always exclude Rigs folder (not real players)
    local rigsFolder = Workspace:FindFirstChild("Rigs")
    if rigsFolder then
        table.insert(list, rigsFolder)
    end
    
    return list
end

local function resolvePlayer(part)
    if not part then return nil end
    
    local character = part.Parent
    -- Check if part is inside Hitbox folder
    if character and character.Name == "Hitbox" then
        character = character.Parent
    end
    
    return Players:GetPlayerFromCharacter(character)
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
