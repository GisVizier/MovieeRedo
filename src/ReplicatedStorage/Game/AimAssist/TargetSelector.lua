--[[
	TargetSelector.lua
	
	Handles finding and prioritizing targets for aim assist.
	Supports targeting players and CollectionService-tagged objects.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local AimAssistEnum = require(script.Parent.AimAssistEnum)
local AimAssistConfig = require(script.Parent.AimAssistConfig)

export type SelectTargetResult = {
	instance: PVInstance?,
	positions: { Vector3 },      -- World position of all relevant bones
	weights: { number },         -- Corresponding weight for each bone according to sorting behavior
	bestPosition: Vector3,       -- World position of the closest bone
	distance: number,
	normalizedDistance: number,
	angle: number,
	normalizedAngle: number,
}

export type PointHitResult = {
	hit: boolean,
	angle: number,
	distance: number,
}

export type TargetEntry = {
	instance: PVInstance,
	points: { Vector3 },
}

local localPlayer = Players.LocalPlayer

local TargetSelector = {}
TargetSelector.__index = TargetSelector

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

local function onSameTeam(player1: Player, player2: Player): boolean
	if not player1.Team or not player2.Team then
		return false
	end

	if player1.Team ~= player2.Team then
		return false
	end

	if player1.Neutral or player2.Neutral then
		return false
	end

	return true
end

-- Get the center of the instance's bounding box
local function getCenterPoint(instance: PVInstance): Vector3
	if instance:IsA("Model") then
		local cf, _ = instance:GetBoundingBox()
		return cf.Position
	elseif instance:IsA("BasePart") then
		return instance.CFrame.Position
	else
		warn(`[TargetSelector] Instance {instance.Name} is not a Model or BasePart`)
		return instance:GetPivot().Position
	end
end

-- =============================================================================
-- PRIVATE METHODS
-- =============================================================================

function TargetSelector:_checkLineOfSight(subject: PVInstance, target: PVInstance, toTarget: Vector3): boolean
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { subject, target }
	
	if localPlayer and localPlayer.Character then
		raycastParams:AddToFilter({ localPlayer.Character :: Instance })
	end

	local raycastResult = Workspace:Raycast(subject:GetPivot().Position, toTarget, raycastParams)
	local hasLineOfSight = raycastResult == nil

	return hasLineOfSight
end

function TargetSelector:_checkPointHit(subject: PVInstance, target: PVInstance, point: Vector3): PointHitResult
	local subjectCFrame = subject:GetPivot()
	local subjectPosition = subjectCFrame.Position
	local subjectLook = subjectCFrame.LookVector

	local toTarget = point - subjectPosition
	local distance = toTarget.Magnitude

	-- Calculate angle between look vector and direction to target
	local dotProduct = subjectLook:Dot(toTarget.Unit)
	local angle = math.acos(math.clamp(dotProduct, -1, 1))
	local angleDegrees = math.deg(angle)

	-- Check if within range and FOV
	local hit = distance <= self.range and angleDegrees <= self.fieldOfView / 2
	
	-- Check minimum range (too close = no aim assist)
	if hit and distance < self.minRange then
		hit = false
	end
	
	-- Check line of sight
	if hit and not self.ignoreLineOfSight then
		hit = self:_checkLineOfSight(subject, target, toTarget)
	end

	return {
		hit = hit,
		angle = angleDegrees,
		distance = distance,
	}
end

-- Return the world position of all bones of an instance
function TargetSelector:_getTargetPoints(instance: PVInstance, bones: { string }?): { Vector3 }
	if not bones or #bones == 0 then
		-- Get center of bounding box as sole target point
		local worldPos: Vector3 = getCenterPoint(instance)
		return { worldPos }
	end

	local points = {}

	for _, bone in bones do
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("PVInstance") and CollectionService:HasTag(descendant, bone) then
				local worldPos = getCenterPoint(descendant)
				table.insert(points, worldPos)
			end
		end
	end

	-- Fallback: if no bones found, use center
	if #points == 0 then
		table.insert(points, getCenterPoint(instance))
	end

	return points
end

-- =============================================================================
-- PUBLIC CONFIGURATION METHODS
-- =============================================================================

function TargetSelector:setRange(range: number)
	self.range = range
end

function TargetSelector:setMinRange(minRange: number)
	self.minRange = minRange
end

function TargetSelector:setFieldOfView(fov: number)
	self.fieldOfView = fov
end

function TargetSelector:setSortingBehavior(behavior: AimAssistEnum.AimAssistSortingBehavior)
	self.sortingBehavior = behavior
end

function TargetSelector:setIgnoreLineOfSight(ignore: boolean)
	self.ignoreLineOfSight = ignore
end

function TargetSelector:addTargetTag(tag: string, bones: { string }?)
	self.tags[tag] = true
	self.tagBones[tag] = bones
end

function TargetSelector:removeTargetTag(tag: string)
	self.tags[tag] = nil
	self.tagBones[tag] = nil
end

function TargetSelector:addPlayerTargets(ignoreLocalPlayer: boolean?, ignoreTeammates: boolean?, bones: { string }?)
	self.targetPlayers = true
	self.ignoreLocalPlayer = if ignoreLocalPlayer ~= nil then ignoreLocalPlayer else true
	self.ignoreTeammates = if ignoreTeammates ~= nil then ignoreTeammates else false
	self.playerBones = bones
end

function TargetSelector:removePlayerTargets()
	self.targetPlayers = false
end

-- =============================================================================
-- TARGET SELECTION
-- =============================================================================

-- Returns a table of all instances and their associated target points
function TargetSelector:getAllTargetPoints(): { TargetEntry }
	local targetPointsTable = {}

	-- Process tags
	for tag, _ in self.tags do
		local instances = CollectionService:GetTagged(tag)
		local bones = self.tagBones[tag]

		for _, instance in instances do
			if not instance or not instance:IsA("PVInstance") then
				continue
			end

			local targetPoints: { Vector3 } = self:_getTargetPoints(instance, bones)
			table.insert(targetPointsTable, { instance = instance, points = targetPoints })
		end
	end

	-- Process players
	if localPlayer and self.targetPlayers then
		local bones = self.playerBones

		for _, player in Players:GetPlayers() do
			if self.ignoreLocalPlayer and player == localPlayer then
				continue
			end

			if self.ignoreTeammates and onSameTeam(player, localPlayer) then
				continue
			end

			if not player.Character then
				continue
			end

			local targetPoints: { Vector3 } = self:_getTargetPoints(player.Character, bones)
			table.insert(targetPointsTable, { instance = player.Character :: PVInstance, points = targetPoints })
		end
	end

	return targetPointsTable
end

-- Chooses the best target for the subject
function TargetSelector:selectTarget(subject: PVInstance): SelectTargetResult?
	local result: SelectTargetResult = {
		instance = nil,
		positions = {},
		weights = {},
		bestPosition = Vector3.zero,
		distance = 0,
		normalizedDistance = 0,
		angle = 0,
		normalizedAngle = 0,
	}

	local bestSortMetric = math.huge

	local targetPoints = self:getAllTargetPoints()

	for _, targetEntry in targetPoints do
		local target: PVInstance = targetEntry.instance
		local worldTargetPoints: { Vector3 } = targetEntry.points

		for _, worldPos in worldTargetPoints do
			local hitResult: PointHitResult = self:_checkPointHit(subject, target, worldPos)

			if hitResult.hit then
				local sortMetric = nil

				if self.sortingBehavior == AimAssistEnum.AimAssistSortingBehavior.Angle then
					sortMetric = hitResult.angle
				elseif self.sortingBehavior == AimAssistEnum.AimAssistSortingBehavior.Distance then
					sortMetric = hitResult.distance
				end

				if sortMetric and sortMetric < bestSortMetric then
					bestSortMetric = sortMetric
					result.distance = hitResult.distance
					result.angle = hitResult.angle
					result.instance = target
					result.bestPosition = worldPos
					result.positions = worldTargetPoints
				end
			end
		end
	end

	if not result.instance then
		return nil
	end

	-- Calculate weights for each bone according to sorting behavior
	local weights = {}
	local totalWeight = 0
	for i, point in result.positions do
		local hitResult = self:_checkPointHit(subject, result.instance, point)
		local weight = 0

		if hitResult.hit then
			local EPSILON = 0.001

			if self.sortingBehavior == AimAssistEnum.AimAssistSortingBehavior.Angle then
				weight = 1 / (hitResult.angle + EPSILON)
			elseif self.sortingBehavior == AimAssistEnum.AimAssistSortingBehavior.Distance then
				weight = 1 / (hitResult.distance + EPSILON)
			end
		end

		totalWeight += weight
		weights[i] = weight
	end

	if totalWeight > 0 then
		for i = 1, #weights do
			weights[i] = weights[i] / totalWeight
		end
	end

	result.weights = weights
	result.normalizedDistance = result.distance / self.range
	result.normalizedAngle = result.angle / (self.fieldOfView / 2)

	return result
end

-- =============================================================================
-- CONSTRUCTOR
-- =============================================================================

function TargetSelector.new()
	local defaults = AimAssistConfig.Defaults
	
	local self = {
		range = defaults.Range,
		minRange = defaults.MinRange or 5,
		fieldOfView = defaults.FieldOfView,
		sortingBehavior = defaults.SortingBehavior or AimAssistEnum.AimAssistSortingBehavior.Angle,
		targetPlayers = true,
		ignoreLineOfSight = defaults.IgnoreLineOfSight or false,
		ignoreLocalPlayer = true,
		ignoreTeammates = true,
		playerBones = defaults.TargetBones or {},
		tags = {},
		tagBones = {},
	}

	setmetatable(self, TargetSelector)

	return self
end

return TargetSelector
