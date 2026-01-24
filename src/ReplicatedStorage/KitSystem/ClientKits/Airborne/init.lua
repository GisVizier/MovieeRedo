--[[
	Airborne Client Kit
	
	Features:
	- Float passive: Hold jump while airborne to slow fall (drains charge)
	- Ability: Cloudskip (horizontal dash) or Updraft (vertical burst) based on jump state
	- Charge UI: 2 bars that drain/regenerate, shows only when not full
	
	Charge Model (mirrored from server):
	- charges: stored full bars (0, 1, or 2)
	- partial: active bar being drained/filled (0.0 to 1.0)
	- Display: Bar1 = charges>=1 ? 100% : partial, Bar2 = charges>=2 ? 100% : (charges==1 ? partial : 0)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local WallJumpUtils = require(Locations.Game.Movement:WaitForChild("WallJumpUtils"))
local SlidingSystem = require(Locations.Game.Movement:WaitForChild("SlidingSystem"))

-- VFXRep for visual effects
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))

-- Animation IDs
local VM_ANIMS = {
	CloudskipDash = "CloudskipDash",
	Updraft = "Updraft",
}

-- Helper: Get movement input direction
local function getInputDirection()
	local inputController = ServiceRegistry:GetController("Input")
	if not inputController then return nil end
	
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	
	local movement = inputController:GetMovementVector()
	if movement.Magnitude < 0.1 then
		return camera.CFrame.LookVector
	end
	
	local camCF = camera.CFrame
	local forward = camCF.LookVector * movement.Y
	local right = camCF.RightVector * movement.X
	local direction = (forward + right)
	
	if direction.Magnitude > 0.01 then
		return direction.Unit
	end
	
	return camera.CFrame.LookVector
end

--------------------------------------------------------------------------------
-- Kit Module
--------------------------------------------------------------------------------

local Airborne = {}
Airborne.__index = Airborne

Airborne.Ability = {}
Airborne.Ultimate = {}

Airborne._ctx = nil
Airborne._connections = {}
Airborne._chargeConnection = nil

-- Charge state (mirrored from server)
Airborne._chargeState = {
	charges = 2,
	partial = 0,
	maxCharges = 2,
}

-- UI references
Airborne._aangBar = nil
Airborne._bar1Gradient = nil
Airborne._bar2Gradient = nil
Airborne._isBarVisible = false
Airborne._lastBar1Fill = nil
Airborne._lastBar2Fill = nil

-- Float state
Airborne._lastAbilityEndTime = 0  -- Track when ability ended for float buffer

-- Drain animation state
Airborne._isDraining = false  -- True while drain animation is playing
Airborne._drainTargetCharges = nil  -- Target charges to drain to (for queuing)

-- Current active instance (for ability access)
Airborne._activeInstance = nil

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

function Airborne:_createUI()
	local player = Players.LocalPlayer
	if not player then return end
	
	local playerGui = player:WaitForChild("PlayerGui")
	
	if playerGui:FindFirstChild("AangBar") then
		self._aangBar = playerGui.AangBar
		self:_cacheUIRefs()
		return
	end
	
	local template = script:FindFirstChild("AangBar")
	if not template then
		warn("[Airborne Client] AangBar template not found under script!")
		return
	end
	
	local screenGui = template:Clone()
	screenGui.Name = "AangBar"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.Parent = playerGui
	
	self._aangBar = screenGui
	self:_cacheUIRefs()
end

function Airborne:_cacheUIRefs()
	if not self._aangBar then 
		return 
	end
	
	local frame = self._aangBar:FindFirstChild("Frame")
	if not frame then 
		return 
	end
	
	
	local bar1 = frame:FindFirstChild("1")
	local bar2 = frame:FindFirstChild("2")
	
	
	if bar1 then
		local barLabel = bar1:FindFirstChild("Bar")
		if barLabel then
			self._bar1Gradient = barLabel:FindFirstChild("UIGradient")
		end
	end
	
	if bar2 then
		local barLabel = bar2:FindFirstChild("Bar")
		if barLabel then
			self._bar2Gradient = barLabel:FindFirstChild("UIGradient")
		end
	end
	
end

function Airborne:_destroyUI()
	if self._aangBar then
		self._aangBar:Destroy()
		self._aangBar = nil
	end
	self._bar1Gradient = nil
	self._bar2Gradient = nil
end

--------------------------------------------------------------------------------
-- UI Update
--------------------------------------------------------------------------------

function Airborne:_updateUI()
	local state = self._chargeState
	
	-- Calculate fill percentages
	-- Bar 1 = charges >= 1 ? 100% : partial
	-- Bar 2 = charges >= 2 ? 100% : (charges == 1 ? partial : 0)
	
	local bar1Fill, bar2Fill
	
	if state.charges >= 2 then
		bar1Fill = 1.0
		bar2Fill = 1.0
	elseif state.charges == 1 then
		bar1Fill = 1.0
		bar2Fill = state.partial
	else
		-- charges == 0
		bar1Fill = state.partial
		bar2Fill = 0
	end
	
	-- Update gradients (Offset.X = fillPercent, 1 = full, 0 = empty)
	if self._bar1Gradient then
		local targetOffset = Vector2.new(bar1Fill, 0)
		TweenService:Create(self._bar1Gradient, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Offset = targetOffset
		}):Play()
	end
	
	if self._bar2Gradient then
		local targetOffset = Vector2.new(bar2Fill, 0)
		TweenService:Create(self._bar2Gradient, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Offset = targetOffset
		}):Play()
	end
	
	-- Show bar when not at max capacity
	local isFull = (state.charges >= state.maxCharges)
	local shouldShow = not isFull
	
	self:_setBarVisibility(shouldShow)
	
	-- Callbacks when bars fill
	if bar1Fill >= 1.0 and self._lastBar1Fill and self._lastBar1Fill < 1.0 then
		self:_onBarFilled(1)
	end
	if bar2Fill >= 1.0 and self._lastBar2Fill and self._lastBar2Fill < 1.0 then
		self:_onBarFilled(2)
	end
	
	self._lastBar1Fill = bar1Fill
	self._lastBar2Fill = bar2Fill
end

function Airborne:_setBarVisibility(visible)
	if not self._aangBar then return end
	if self._isBarVisible == visible then return end
	
	self._isBarVisible = visible
	self._aangBar.Enabled = visible
end

function Airborne:_onBarFilled(barIndex)
	-- Could add flash effect or sound here
end

--------------------------------------------------------------------------------
-- Charge State Sync
--------------------------------------------------------------------------------

function Airborne:_syncChargeState()
	local player = Players.LocalPlayer
	if not player then return end
	
	local raw = player:GetAttribute("AirborneCharges")
	if not raw then return end
	
	local success, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	
	if success and type(data) == "table" then
		local newCharges = data.charges or 0
		local newPartial = data.partial or 0
		
		-- Capture OLD values BEFORE updating
		local oldCharges = self._chargeState.charges
		local oldPartial = self._chargeState.partial or 0
		
		-- If already draining, just update target (queue the drain)
		if Airborne._isDraining then
			if newCharges < (Airborne._drainTargetCharges or self._chargeState.charges) then
				Airborne._drainTargetCharges = newCharges
			end
			self._chargeState.charges = newCharges
			self._chargeState.partial = newPartial
			self._chargeState.maxCharges = data.maxCharges or 2
			return
		end
		
		-- Now update to new values
		self._chargeState.charges = newCharges
		self._chargeState.partial = newPartial
		self._chargeState.maxCharges = data.maxCharges or 2
		
		-- If charges decreased, play drain animation with OLD partial
		if newCharges < oldCharges then
			self:_animateDrain(oldCharges, newCharges, oldPartial)
		else
			self:_updateUI()
		end
	end
end

-- Animate bars draining when charges are consumed
-- Always drains RIGHT to LEFT (bar2 first, then bar1)
function Airborne:_animateDrain(fromCharges, toCharges, oldPartial)
	local DRAIN_TIME = 0.3  -- Time to drain each bar
	
	
	-- Mark as draining (blocks UI updates during animation)
	Airborne._isDraining = true
	Airborne._drainTargetCharges = toCharges
	
	-- Use the OLD partial value (passed in) to determine visual state before drain
	local partial = oldPartial or 0
	
	
	-- Current visual state (before drain):
	-- charges=2: bar1=100%, bar2=100%
	-- charges=1: bar1=100%, bar2=partial (partial shows regenerating 2nd charge)
	-- charges=0: bar1=partial, bar2=0%
	local bar1Current, bar2Current
	if fromCharges >= 2 then
		bar1Current = 1.0
		bar2Current = 1.0
	elseif fromCharges == 1 then
		bar1Current = 1.0
		bar2Current = partial  -- This is the regenerating bar (right side)
	else
		bar1Current = partial
		bar2Current = 0
	end
	
	
	-- Show bars during drain
	self:_setBarVisibility(true)
	
	-- Step 1: Drain bar2 (right) first if it has any content
	local function drainBar2(callback)
		local targetCharges = Airborne._drainTargetCharges or toCharges
		
		-- Calculate what bar2 should be after drain
		local bar2Target = 0  -- Usually drains to 0
		if targetCharges >= 2 then
			bar2Target = 1.0
		elseif targetCharges == 1 then
			bar2Target = 0  -- Will be filled by partial later
		end
		
		
		-- Only drain if bar2 has content and needs to drain
		if bar2Current > bar2Target and self._bar2Gradient then
			local startOffset = Vector2.new(bar2Current, 0)
			local endOffset = Vector2.new(bar2Target, 0)
			
			self._bar2Gradient.Offset = startOffset
			
			local tween = TweenService:Create(self._bar2Gradient, TweenInfo.new(DRAIN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Offset = endOffset
			})
			
			tween:Play()
			tween.Completed:Once(function()
				callback()
			end)
		else
			callback()
		end
	end
	
	-- Step 2: Drain bar1 (left) after bar2
	local function drainBar1(callback)
		local targetCharges = Airborne._drainTargetCharges or toCharges
		
		-- Calculate what bar1 should be after drain
		local bar1Target
		if targetCharges >= 1 then
			bar1Target = 1.0
		else
			bar1Target = 0  -- Will be filled by partial later during regen
		end
		
		
		-- Only drain if bar1 needs to drain
		if bar1Current > bar1Target and self._bar1Gradient then
			local startOffset = Vector2.new(bar1Current, 0)
			local endOffset = Vector2.new(bar1Target, 0)
			
			self._bar1Gradient.Offset = startOffset
			
			local tween = TweenService:Create(self._bar1Gradient, TweenInfo.new(DRAIN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Offset = endOffset
			})
			
			tween:Play()
			tween.Completed:Once(function()
				callback()
			end)
		else
			callback()
		end
	end
	
	-- Execute: bar2 first, then bar1, then wait for regen delay
	drainBar2(function()
		drainBar1(function()
			-- Done draining - wait for regen delay before showing UI
			task.delay(1.5, function()
				Airborne._isDraining = false
				Airborne._drainTargetCharges = nil
				self:_updateUI()
			end)
		end)
	end)
end

function Airborne:_hasAnyCharge(): boolean
	return self._chargeState.charges > 0 or self._chargeState.partial > 0
end

function Airborne:_hasFullCharge(): boolean
	-- Need at least 1 STORED full charge for ability
	return self._chargeState.charges >= 1
end

--------------------------------------------------------------------------------
-- Float Passive - Using YOUR exact structure that works
--------------------------------------------------------------------------------

function Airborne:_setupFloatPassive(ctx)
	local character = ctx.character
	local primaryPart = character and character.PrimaryPart
	if not primaryPart then return end

	local inputManager = ServiceRegistry:GetController("Input").Manager
	local kitController = ServiceRegistry:GetController("Kit")
	
	local jumpStart = nil
	local jumpConnection = nil
	local lastFloatTime = 0
	local FLOAT_COOLDOWN = 0.25
	local ABILITY_BUFFER = 0.35  -- Can't float until 0.35s after ability ends

	self._connections.jumpInput = inputManager:ConnectToInput("Jump", function(isJumping)
		if isJumping then
			local isGrounded = MovementStateManager:GetIsGrounded()
			if isGrounded then
				return
			end 

			-- Can't float while ability is active
			if kitController:IsAbilityActive() then
				return
			end
			
			-- Can't float while on cooldown
			if kitController:IsAbilityOnCooldown() then
				return
			end
			
			-- Can't float until 0.35s after ability ends
			if tick() - Airborne._lastAbilityEndTime < ABILITY_BUFFER then
				return
			end

			if tick() - lastFloatTime < FLOAT_COOLDOWN then
				return
			end

			jumpStart = tick()
			lastFloatTime = tick()
			
			jumpConnection = RunService.RenderStepped:Connect(function()
				if not primaryPart or not primaryPart.Parent then
					if jumpConnection then jumpConnection:Disconnect() end
					return
				end

				-- Can't float while ability is active
				if kitController:IsAbilityActive() then
					return
				end
				
				-- Can't float while on cooldown
				if kitController:IsAbilityOnCooldown() then
					return
				end
				
				-- Can't float until 0.35s after ability ends
				if tick() - Airborne._lastAbilityEndTime < ABILITY_BUFFER then
					return
				end

				-- Check if recently wall jumped
				if tick() - WallJumpUtils.LastWallJumpTime < 0.5 then
					return
				end

				-- Check if recently jump cancelled
				if tick() - SlidingSystem.LastJumpCancelTime < 0.5 then
					return
				end

				if tick() - jumpStart > 0.25 then
					local isGrounded = MovementStateManager:GetIsGrounded()
					if isGrounded then
						if jumpConnection then jumpConnection:Disconnect() end
						return
					end

					-- APPLY SLOW FALL (infinite, no charge drain)
					local vel = primaryPart.AssemblyLinearVelocity
					primaryPart.AssemblyLinearVelocity = Vector3.new(vel.X, -8.75, vel.Z)
				end
			end)
		else
			-- Jump released
			if jumpConnection then
				jumpConnection:Disconnect()
				jumpConnection = nil
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Kit Lifecycle
--------------------------------------------------------------------------------

function Airborne:OnEquip(ctx)
	self._ctx = ctx
	
	-- Store active instance so Ability can access it
	Airborne._activeInstance = self
	
	self:_createUI()
	
	local player = Players.LocalPlayer
	if player then
		self._chargeConnection = player:GetAttributeChangedSignal("AirborneCharges"):Connect(function()
			self:_syncChargeState()
		end)
		
		-- Initial sync
		self:_syncChargeState()
	end
	
	self:_setupFloatPassive(ctx)
end

function Airborne:OnUnequip(reason)
	-- Clear active instance
	if Airborne._activeInstance == self then
		Airborne._activeInstance = nil
	end
	
	if self._chargeConnection then
		self._chargeConnection:Disconnect()
		self._chargeConnection = nil
	end
	
	for key, conn in pairs(self._connections) do
		if typeof(conn) == "RBXScriptConnection" then
			conn:Disconnect()
		end
		self._connections[key] = nil
	end
	
	self:_destroyUI()
end

--------------------------------------------------------------------------------
-- Ability: OnStart
--------------------------------------------------------------------------------

function Airborne.Ability:OnStart(abilityRequest)
	local hrp = abilityRequest.humanoidRootPart
	if not hrp then return end
	
	local kitController = ServiceRegistry:GetController("Kit")
	
	if kitController:IsAbilityActive() then
		return
	end
	
	if abilityRequest.IsOnCooldown() then
		return
	end
	
	-- Get the active instance (NOT the module!)
	local instance = Airborne._activeInstance
	if not instance then return end
	
	-- Check if we have a STORED full charge (charges >= 1, not just partial)
	if not instance:_hasFullCharge() then
		return
	end
	
	local ctx = abilityRequest.StartAbility()
	local unlock = kitController:LockWeaponSwitch()
	
	local inputManager = ServiceRegistry:GetController("Input").Manager
	local isHoldingJump = inputManager.IsJumping
	local hasFinished = false
	
	local animation
	local viewmodelAnimator = ctx.viewmodelAnimator
	local Viewmodelrig = abilityRequest.viewmodelController:GetActiveRig()
	
	local actionType
	
	if isHoldingJump then
		actionType = "upDraft"
		animation = viewmodelAnimator:PlayKitAnimation(VM_ANIMS.Updraft, {
			priority = Enum.AnimationPriority.Action4,
			stopOthers = true,
		})
		
		VFXRep:Fire("Me", { Module = "Cloudskip", Function = "User" }, {
			position = hrp.Position,
			ViewModel = Viewmodelrig,
			Action = "upDraft",
			Animation = animation and animation.Name,
		})
	else
		actionType = "cloudSkip"
		animation = viewmodelAnimator:PlayKitAnimation(VM_ANIMS.CloudskipDash, {
			priority = Enum.AnimationPriority.Action4,
			stopOthers = true,
		})
		
		VFXRep:Fire("Me", { Module = "Cloudskip", Function = "User" }, {
			position = hrp.Position,
			ViewModel = Viewmodelrig,
			Action = "cloudSkip",
			Animation = animation and animation.Name,
		})
	end
	
	if not animation then
		unlock()
		return
	end
	
	Viewmodelrig.Model:SetAttribute("PlayingAnimation_" .. animation.Name, true)
	
	local Events = {
		["_finish"] = function()
			if abilityRequest.viewmodelController:GetActiveSlot() ~= "Fists" then
				return
			end
			
			if not abilityRequest.player then
				return
			end
			
			if hrp and hrp.Parent and Viewmodelrig then
				-- Tell server to consume a STORED charge
				abilityRequest.Send({
					useAbility = true,
					action = actionType,
					direction = getInputDirection(),
				})
			end
		end,
		
		["Burst"] = function()
			hrp.AssemblyLinearVelocity = Vector3.new(0, 75, 0)
			
			task.delay(0.3025, function()
				local START, END = 67, -5
				local kpValue = Instance.new("NumberValue")
				kpValue.Value = START
				
				local tweenConn = kpValue.Changed:Connect(function(currentValue)
					if hrp and hrp.Parent then
						hrp.AssemblyLinearVelocity = Vector3.new(
							hrp.AssemblyLinearVelocity.X,
							currentValue,
							hrp.AssemblyLinearVelocity.Z
						)
					end
				end)
				
				local tween = TweenService:Create(
					kpValue,
					TweenInfo.new(0.67, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{ Value = END }
				)
				tween:Play()
				
				tween.Completed:Once(function()
					kpValue:Destroy()
					tweenConn:Disconnect()
				end)
			end)
		end,
		
		["Dash"] = function()
			local direction = getInputDirection() or workspace.CurrentCamera.CFrame.LookVector
			
			local START, END = 380, 15
			local kpValue = Instance.new("NumberValue")
			kpValue.Value = START
			
			local tweenConn = kpValue.Changed:Connect(function(currentValue)
				if hrp and hrp.Parent then
					hrp.AssemblyLinearVelocity = Vector3.new(direction.X, 0, direction.Z) * currentValue
				end
			end)
			
			local tween = TweenService:Create(
				kpValue,
				TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Value = END }
			)
			tween:Play()
			
			tween.Completed:Once(function()
				kpValue:Destroy()
				tweenConn:Disconnect()
			end)
		end,
	}
	
	local animationConnection = animation:GetMarkerReachedSignal("Event"):Connect(function(event)
		if Events[event] then
			Events[event]()
		end
	end)
	
	local stopSignals = {
		animation.Stopped,
		animation.Ended,
		Viewmodelrig.AncestryChanged,
		Viewmodelrig.Destroying,
		hrp.Destroying,
		abilityRequest.player.AncestryChanged,
	}
	
	local connections = { animationConnection }
	
	local function cleanup()
		if hasFinished then return end
		hasFinished = true
		
		if animation and animation.IsPlaying then
			animation:Stop(0)
			if Viewmodelrig and Viewmodelrig:FindFirstChild("Model") then
				Viewmodelrig.Model:SetAttribute("PlayingAnimation_" .. animation.Name, false)
			end
		end
		
		Events["_finish"]()
		unlock()
		
		-- Track when ability ended (for float buffer)
		Airborne._lastAbilityEndTime = tick()
		
		for _, conn in ipairs(connections) do
			if typeof(conn) == "RBXScriptConnection" then
				conn:Disconnect()
			end
		end
	end
	
	for _, signal in ipairs(stopSignals) do
		table.insert(connections, signal:Once(function()
			cleanup()
		end))
	end
end

function Airborne.Ability:OnEnded(abilityRequest)
end

function Airborne.Ability:OnInterrupt(abilityRequest, reason)
end

--------------------------------------------------------------------------------
-- Ultimate
--------------------------------------------------------------------------------

function Airborne.Ultimate:OnStart(abilityRequest)
end

function Airborne.Ultimate:OnEnded(abilityRequest)
end

function Airborne.Ultimate:OnInterrupt(abilityRequest, reason)
end

--------------------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------------------

function Airborne.new(ctx)
	local self = setmetatable({}, Airborne)
	self._ctx = ctx
	self._connections = {}
	self._chargeState = {
		charges = 2,
		partial = 0,
		maxCharges = 2,
	}
	return self
end

function Airborne:Destroy()
	self:OnUnequip("Destroy")
end

return Airborne
