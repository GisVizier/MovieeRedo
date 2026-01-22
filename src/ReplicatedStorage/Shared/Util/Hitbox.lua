--[[
    Hitbox.lua
    
    Simple hitbox detection utility for finding players in areas.
    Non-blocking, runs queries in separate threads when using duration.
    
    API:
        -- Instant sphere check
        local players = Hitbox.GetEntitiesInSphere(position, radius, exclude?)
        
        -- Lingering sphere check (returns handle)
        local handle = Hitbox.GetEntitiesInSphere(position, radius, {
            exclude = player,
            duration = 2,
        })
        local hits = handle:GetHits()
        handle:Stop()
        
        -- Instant raycast
        local player, hitPos = Hitbox.Raycast(origin, direction, distance, exclude?)
        
        -- Lingering raycast (returns handle)
        local handle = Hitbox.Raycast(origin, direction, distance, {
            exclude = player,
            duration = 0.3,
        })
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

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

local function parseConfig(configOrExclude)
    if not configOrExclude then
        return nil, nil
    end
    
    -- If it's a player directly, treat as exclude
    if typeof(configOrExclude) == "Instance" and configOrExclude:IsA("Player") then
        return configOrExclude, nil
    end
    
    -- If it's an array of players, treat as exclude list
    if type(configOrExclude) == "table" then
        -- Check if it has duration (config table) or is just an array of players
        if configOrExclude.duration then
            return configOrExclude.exclude, configOrExclude.duration
        else
            -- Assume it's an array of players to exclude
            return configOrExclude, nil
        end
    end
    
    return nil, nil
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
-- RAYCAST
----------------------------------------------------------------

function Hitbox.Raycast(origin: Vector3, direction: Vector3, distance: number, configOrExclude: any?)
    local exclude, duration = parseConfig(configOrExclude)
    local excludeList = buildExcludeList(exclude)
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludeList
    
    local dir = direction.Unit * distance
    
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
