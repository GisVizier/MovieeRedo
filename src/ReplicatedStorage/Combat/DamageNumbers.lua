--[[
	DamageNumbers.lua
	Client-side module for displaying floating damage numbers
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local CombatConfig = require(script.Parent:WaitForChild("CombatConfig"))

local DamageNumbers = {}
DamageNumbers._pool = {} -- Object pool for billboards
DamageNumbers._active = {} -- Currently displayed billboards

local POOL_SIZE = 20

--[[
	Creates a damage number billboard template
	@return BillboardGui
]]
local function createBillboard(): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumbers"
	billboard.Active = true
	billboard.ClipsDescendants = true
	billboard.Size = UDim2.fromScale(2, 2)
	billboard.StudsOffsetWorldSpace = Vector3.new(-3, 3, 0)
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	
	local frame = Instance.new("CanvasGroup")
	frame.Name = "Frame"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = billboard
	
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.BackgroundTransparency = 1
	glow.Image = "rbxassetid://5538771868"
	glow.ImageTransparency = 0.9
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1, 1)
	glow.Parent = frame
	
	local mainText = Instance.new("TextLabel")
	mainText.Name = "MainText"
	mainText.AnchorPoint = Vector2.new(0.5, 0.5)
	mainText.BackgroundTransparency = 1
	mainText.FontFace = Font.new(
		"rbxassetid://12187365977",
		Enum.FontWeight.ExtraBold,
		Enum.FontStyle.Normal
	)
	mainText.Position = UDim2.fromScale(0.5, 0.5)
	mainText.Size = UDim2.fromScale(1, 0.4)
	mainText.Text = "0"
	mainText.TextColor3 = Color3.fromRGB(233, 233, 233)
	mainText.TextScaled = true
	mainText.TextWrapped = true
	mainText.ZIndex = 3
	mainText.Parent = frame
	
	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = 36
	sizeConstraint.Parent = mainText
	
	return billboard
end

--[[
	Initializes the object pool
]]
function DamageNumbers:Init()
	for i = 1, POOL_SIZE do
		local billboard = createBillboard()
		billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		table.insert(self._pool, billboard)
	end
end

--[[
	Gets a billboard from the pool or creates a new one
	@return BillboardGui
]]
function DamageNumbers:_getBillboard(): BillboardGui
	local billboard = table.remove(self._pool)
	
	if not billboard then
		billboard = createBillboard()
		billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end
	
	return billboard
end

--[[
	Returns a billboard to the pool
	@param billboard BillboardGui
]]
function DamageNumbers:_returnBillboard(billboard: BillboardGui)
	billboard.Enabled = false
	billboard.Adornee = nil
	table.insert(self._pool, billboard)
end

--[[
	Shows a damage number at the specified position
	@param position Vector3 - World position
	@param damage number - Damage amount to display
	@param options table? - Display options
]]
function DamageNumbers:Show(position: Vector3, damage: number, options: {
	isHeadshot: boolean?,
	isCritical: boolean?,
	isHeal: boolean?,
	color: Color3?,
}?)
	if not CombatConfig.DamageNumbers.Enabled then
		return
	end
	
	options = options or {}
	
	local billboard = self:_getBillboard()
	local frame = billboard:FindFirstChild("Frame")
	local mainText = frame and frame:FindFirstChild("MainText")
	local glow = frame and frame:FindFirstChild("Glow")
	
	if not mainText then return end
	
	-- Determine color
	local color = options.color
	if not color then
		if options.isHeal then
			color = CombatConfig.DamageNumbers.Colors.Heal
		elseif options.isCritical then
			color = CombatConfig.DamageNumbers.Colors.Critical
		elseif options.isHeadshot then
			color = CombatConfig.DamageNumbers.Colors.Headshot
		else
			color = CombatConfig.DamageNumbers.Colors.Normal
		end
	end
	
	-- Determine scale
	local scale = 1.0
	if options.isCritical then
		scale = CombatConfig.DamageNumbers.CriticalScale
	elseif options.isHeadshot then
		scale = CombatConfig.DamageNumbers.HeadshotScale
	end
	
	-- Format damage text
	local text = options.isHeal and ("+" .. tostring(math.floor(damage))) or tostring(math.floor(damage))
	
	-- Setup billboard
	mainText.Text = text
	mainText.TextColor3 = color
	
	if glow then
		glow.ImageColor3 = color
	end
	
	-- Position - create a part to adorn to
	local anchorPart = Instance.new("Part")
	anchorPart.Name = "DamageNumberAnchor"
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(0.1, 0.1, 0.1)
	anchorPart.Position = position
	anchorPart.Parent = workspace
	
	billboard.Adornee = anchorPart
	billboard.Size = UDim2.fromScale(2 * scale, 2 * scale)
	billboard.Enabled = true
	
	-- Reset frame for animation
	if frame then
		frame.GroupTransparency = 0
	end
	
	-- Random offset for variety
	local randomOffset = Vector3.new(
		(math.random() - 0.5) * 2,
		0,
		(math.random() - 0.5) * 2
	)
	
	-- Animate
	local startPos = position
	local endPos = position + Vector3.new(0, CombatConfig.DamageNumbers.FloatSpeed * CombatConfig.DamageNumbers.FadeTime, 0) + randomOffset
	
	local startTime = os.clock()
	local fadeTime = CombatConfig.DamageNumbers.FadeTime
	local fadeDuration = CombatConfig.DamageNumbers.FadeDuration
	
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		
		if elapsed >= fadeTime + fadeDuration then
			-- Animation complete
			connection:Disconnect()
			anchorPart:Destroy()
			self:_returnBillboard(billboard)
			return
		end
		
		-- Move upward
		local moveProgress = math.min(elapsed / fadeTime, 1)
		anchorPart.Position = startPos:Lerp(endPos, moveProgress)
		
		-- Fade out
		if elapsed >= fadeTime and frame then
			local fadeProgress = (elapsed - fadeTime) / fadeDuration
			frame.GroupTransparency = fadeProgress
		end
	end)
end

--[[
	Shows damage at a character's position
	@param character Model
	@param damage number
	@param options table?
]]
function DamageNumbers:ShowAtCharacter(character: Model, damage: number, options: {
	isHeadshot: boolean?,
	isCritical: boolean?,
	isHeal: boolean?,
	color: Color3?,
}?)
	local head = character:FindFirstChild("Head")
	local position = head and head.Position or (character.PrimaryPart and character.PrimaryPart.Position)
	
	if position then
		-- Offset slightly above head
		position = position + Vector3.new(0, 2, 0)
		self:Show(position, damage, options)
	end
end

return DamageNumbers
