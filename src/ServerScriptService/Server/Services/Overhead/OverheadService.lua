--[[
	OverheadService.lua
	Server-side service that manages lobby overhead BillboardGuis.

	Clones the template from ReplicatedStorage.Assets.Overhead and attaches
	it to each player's character while they are in the lobby.

	Displays: player name (with premium/verified badges), platform icon,
	win count, and kill streak.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LobbyData"))

local OverheadService = {}

-- Platform icon asset IDs
local PLATFORM_ICONS = {
	PC = "rbxassetid://110256329048300",
	Controller = "rbxassetid://85296171032992",
	Mobile = "rbxassetid://90773319506394",
}

local PLATFORM_LABELS = {
	PC = "PC",
	Controller = "CTRL",
	Mobile = "MBL",
}

local PREMIUM_CHAR = utf8.char(0xE002)
local VERIFIED_CHAR = utf8.char(0xE000)
local GROUP_ID = (game.CreatorType == Enum.CreatorType.Group) and game.CreatorId or 0

local ROLE_TO_BADGE = {
	["lead developer"] = "LEAD",
	admin = "ADM",
	developer = "DEV",
	contributor = "CTB",
}

-- State
OverheadService._overheads = {}
OverheadService._template = nil
OverheadService._registry = nil
OverheadService._net = nil

-- =============================================================================
-- LIFECYCLE
-- =============================================================================

function OverheadService:Init(registry, net)
	self._registry = registry
	self._net = net

	-- Cache template
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		self._template = assets:FindFirstChild("Overhead")
	end
	-- Bind platform remote
	self._net:ConnectServer("SetPlatform", function(player, platform)
		self:_onSetPlatform(player, platform)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_removeOverhead(player)
	end)
end

function OverheadService:Start()
	-- Setup listeners for existing and new players
	for _, player in Players:GetPlayers() do
		self:_setupPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_setupPlayer(player)
	end)
end

-- =============================================================================
-- PLAYER SETUP
-- =============================================================================

function OverheadService:_setupPlayer(player)
	player:GetAttributeChangedSignal("PlayerState"):Connect(function()
		local state = player:GetAttribute("PlayerState")
		if state == "Lobby" then
			self:_tryAttachOverhead(player)
		else
			self:_removeOverhead(player)
		end
	end)

	-- Handle player already in lobby
	if player:GetAttribute("PlayerState") == "Lobby" then
		self:_tryAttachOverhead(player)
	end
end

-- =============================================================================
-- OVERHEAD CREATION
-- =============================================================================

function OverheadService:_tryAttachOverhead(player)
	self:_removeOverhead(player)

	if not self._template then return end

	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local overhead = self._template:Clone()
	self:_populateOverhead(overhead, player)
	overhead.Adornee = hrp
	overhead.Parent = hrp

	self._overheads[player] = overhead
end

function OverheadService:_populateOverhead(overhead, player)
	local active = overhead:FindFirstChild("Active")
	if not active then return end

	local holder = active:FindFirstChild("Holder")
	if not holder then return end

	self:_setPlayerName(holder, player)
	self:_setPlatformInfo(holder, player)
	self:_setWins(holder, player)
	self:_setStreak(holder, player)
	self:_setRoleBadge(holder, player)
end

-- =============================================================================
-- POPULATE SECTIONS
-- =============================================================================

function OverheadService:_setPlayerName(holder, player)
	local root = holder:FindFirstChild("PlayerName")
	if not root then return end
	local playerNameFrame = root:FindFirstChild("PlayerName")
	if not playerNameFrame then return end
	local textLabel = playerNameFrame:FindFirstChild("TextLabel")
	if not textLabel then return end

	local displayName = player.DisplayName or player.Name

	local prefix = ""
	local suffix = ""

	if player.MembershipType == Enum.MembershipType.Premium then
		prefix = PREMIUM_CHAR .. " "
	end

	if player.HasVerifiedBadge then
		suffix = " " .. VERIFIED_CHAR
	end

	textLabel.Text = prefix .. displayName .. suffix
end

function OverheadService:_setRoleBadge(holder, player)
	local infoFrame = holder:FindFirstChild("Info")
	if not infoFrame then return end

	for _, badgeName in pairs(ROLE_TO_BADGE) do
		local badgeFrame = infoFrame:FindFirstChild(badgeName)
		if badgeFrame and badgeFrame:IsA("GuiObject") then
			badgeFrame.Visible = false
		end
	end

	if GROUP_ID <= 0 then
		return
	end

	local ok, role = pcall(function()
		return player:GetRoleInGroup(GROUP_ID)
	end)
	if not ok or type(role) ~= "string" or role == "" then
		return
	end

	local badgeName = ROLE_TO_BADGE[string.lower(role)]
	if not badgeName then
		-- No frame for this role (Owner/Tester/Member/Guest/Manager currently).
		return
	end

	local badgeFrame = infoFrame:FindFirstChild(badgeName)
	if badgeFrame and badgeFrame:IsA("GuiObject") then
		badgeFrame.Visible = true
	end
end

function OverheadService:_setPlatformInfo(holder, player)
	local infoFrame = holder:FindFirstChild("Info")
	if not infoFrame then return end

	local platformFrame = infoFrame:FindFirstChild("Platform")
	if not platformFrame then return end

	local platform = player:GetAttribute("Platform") or "Unknown"

	-- Set icon
	local imageLabel = platformFrame:FindFirstChildOfClass("ImageLabel")
	if imageLabel then
		imageLabel.Image = PLATFORM_ICONS[platform] or ""
	end

	-- Set text
	local textLabel = platformFrame:FindFirstChildOfClass("TextLabel")
	if textLabel then
		textLabel.Text = PLATFORM_LABELS[platform] or "?"
	end
end

function OverheadService:_setWins(holder, player)
	local infoFrame = holder:FindFirstChild("Info")
	if not infoFrame then return end

	local winsFrame = infoFrame:FindFirstChild("Wins")
	if not winsFrame then return end

	local wins = LobbyData.getPlayerWins(player.UserId)
	local holderFrame = winsFrame:FindFirstChild("Frame")
	if not holderFrame then return end
	local textLabel = holderFrame:FindFirstChild("TextLabel")
	if not textLabel then return end
	textLabel.Text = tostring(wins)
end

function OverheadService:_setStreak(holder, player)
	local streakFrame = holder:FindFirstChild("Streak")
	if not streakFrame then return end

	local streak = LobbyData.getPlayerStreak(player.UserId)

	if streak > 0 then
		streakFrame.Visible = true
		local innerFrame = streakFrame:FindFirstChild("Frame")
		if innerFrame then
			local textLabel = innerFrame:FindFirstChild("TextLabel")
			if textLabel then
				textLabel.Text = tostring(streak)
			end
		end
	else
		streakFrame.Visible = false
	end
end

-- =============================================================================
-- PLATFORM REMOTE
-- =============================================================================

function OverheadService:_onSetPlatform(player, platform)
	if type(platform) ~= "string" then return end
	if platform ~= "PC" and platform ~= "Controller" and platform ~= "Mobile" then return end

	player:SetAttribute("Platform", platform)

	-- Update existing overhead in-place
	local overhead = self._overheads[player]
	if not overhead then return end

	local active = overhead:FindFirstChild("Active")
	if not active then return end

	local holder = active:FindFirstChild("Holder")
	if not holder then return end

	self:_setPlatformInfo(holder, player)
end

-- =============================================================================
-- CLEANUP
-- =============================================================================

function OverheadService:_removeOverhead(player)
	local overhead = self._overheads[player]
	if overhead then
		overhead:Destroy()
		self._overheads[player] = nil
	end
end

return OverheadService
