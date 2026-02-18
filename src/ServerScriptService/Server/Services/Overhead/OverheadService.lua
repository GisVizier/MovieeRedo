--[[
	OverheadService.lua
	Server-side service that manages overhead BillboardGuis.

	Clones the template from ReplicatedStorage.Assets.Overhead and attaches
	it to each player's character while they are in Lobby or Training.

	Displays: player name (with premium/verified badges), platform icon,
	crowns, win count, kill streak, and role badge.
	Uses ProfileStore (Data) + Replica for real player data and live updates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.Parent.Parent.Parent:WaitForChild("Data"):WaitForChild("ProfileHandler"))

local OverheadService = {}

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

local PREMIUM_CHAR = utf8.char(0xE001)
local VERIFIED_CHAR = utf8.char(0xE000)
local GROUP_ID = (game.CreatorType == Enum.CreatorType.Group) and game.CreatorId or 0

local ROLE_TO_BADGE = {
	["lead developer"] = "LEAD",
	admin = "ADM",
	developer = "DEV",
	contributor = "CTB",
}

OverheadService._overheads = {}
OverheadService._replicaListeners = {} -- { [player] = { conn1, conn2, ... } }
OverheadService._template = nil
OverheadService._registry = nil
OverheadService._net = nil

local function shouldShowOverhead(player)
	local state = player:GetAttribute("PlayerState")
	return state == "Lobby" or state == "Training"
end

local function getReplicaData(replica, key)
	if replica and replica.Data then
		return replica.Data[key] or 0
	end
	return 0
end

-- =============================================================================
-- LIFECYCLE
-- =============================================================================

function OverheadService:Init(registry, net)
	self._registry = registry
	self._net = net

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		self._template = assets:FindFirstChild("Overhead")
	end

	self._net:ConnectServer("SetPlatform", function(player, platform)
		self:_onSetPlatform(player, platform)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_removeOverhead(player)
		self:_clearReplicaListeners(player)
	end)
end

function OverheadService:Start()
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
		if shouldShowOverhead(player) then
			self:_tryAttachOverhead(player)
		else
			self:_removeOverhead(player)
			self:_clearReplicaListeners(player)
		end
	end)

	-- Retry when ProfileStore data loads (replica may not exist yet)
	player:GetAttributeChangedSignal("Data_Loaded"):Connect(function()
		if shouldShowOverhead(player) then
			self:_tryAttachOverhead(player)
		end
	end)

	if shouldShowOverhead(player) then
		self:_tryAttachOverhead(player)
	end
end

-- =============================================================================
-- OVERHEAD CREATION
-- =============================================================================

function OverheadService:_tryAttachOverhead(player)
	self:_removeOverhead(player)
	self:_clearReplicaListeners(player)

	if not self._template then return end

	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local replica = Data.GetReplica(player)
	if not replica then return end

	local overhead = self._template:Clone()
	self:_populateOverhead(overhead, player, replica)
	overhead.Adornee = hrp
	overhead.Parent = hrp

	self._overheads[player] = overhead

	-- Replica ListenToChange: live updates when CROWNS/WINS/STREAK change
	self._replicaListeners[player] = {}
	local conn = replica:ListenToChange(function(action, path, _param1, _param2)
		if action ~= "Set" and action ~= "SetValues" then return end
		if not path or #path == 0 then return end
		local key = path[1]
		if key ~= "CROWNS" and key ~= "WINS" and key ~= "STREAK" then return end

		self:_refreshOverheadData(player)
	end)
	table.insert(self._replicaListeners[player], conn)
end

function OverheadService:_clearReplicaListeners(player)
	local listeners = self._replicaListeners[player]
	if listeners then
		for _, conn in ipairs(listeners) do
			if conn and conn.Disconnect then
				conn:Disconnect()
			end
		end
		self._replicaListeners[player] = nil
	end
end

function OverheadService:_populateOverhead(overhead, player, replica)
	local active = overhead:FindFirstChild("Active")
	if not active then return end

	local holder = active:FindFirstChild("Holder")
	if not holder then return end

	self:_setPlayerName(holder, player)
	self:_setPlatformInfo(holder, player)
	self:_setCrowns(holder, replica)
	self:_setWins(holder, replica)
	self:_setStreak(holder, replica)
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
	local prefix = player.MembershipType == Enum.MembershipType.Premium and (PREMIUM_CHAR .. " ") or ""
	local suffix = player.HasVerifiedBadge and (" " .. VERIFIED_CHAR) or ""
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

	if GROUP_ID <= 0 then return end

	local ok, role = pcall(function()
		return player:GetRoleInGroup(GROUP_ID)
	end)
	if not ok or type(role) ~= "string" or role == "" then return end

	local badgeName = ROLE_TO_BADGE[string.lower(role)]
	if badgeName then
		local badgeFrame = infoFrame:FindFirstChild(badgeName)
		if badgeFrame and badgeFrame:IsA("GuiObject") then
			badgeFrame.Visible = true
		end
	end
end

function OverheadService:_setPlatformInfo(holder, player)
	local infoFrame = holder:FindFirstChild("Info")
	if not infoFrame then return end

	local platformFrame = infoFrame:FindFirstChild("Platform")
	if not platformFrame then return end

	local platform = player:GetAttribute("Platform") or "Unknown"
	local imageLabel = platformFrame:FindFirstChildOfClass("ImageLabel")
	if imageLabel then
		imageLabel.Image = PLATFORM_ICONS[platform] or ""
	end
	local textLabel = platformFrame:FindFirstChildOfClass("TextLabel")
	if textLabel then
		textLabel.Text = PLATFORM_LABELS[platform] or "?"
	end
end

function OverheadService:_setCrowns(holder, replica)
	local infoFrame = holder:FindFirstChild("Info")
	if not infoFrame then return end

	local crownsFrame = infoFrame:FindFirstChild("Crowns")
	if not crownsFrame then return end

	local crowns = getReplicaData(replica, "CROWNS")
	local holderFrame = crownsFrame:FindFirstChild("Frame")
	if holderFrame then
		local textLabel = holderFrame:FindFirstChild("TextLabel")
		if textLabel then textLabel.Text = tostring(crowns) end
	else
		local textLabel = crownsFrame:FindFirstChild("TextLabel")
		if textLabel then textLabel.Text = tostring(crowns) end
	end
end

function OverheadService:_setWins(holder, replica)
	local infoFrame = holder:FindFirstChild("Info")
	if not infoFrame then return end

	local winsFrame = infoFrame:FindFirstChild("Wins")
	if not winsFrame then return end

	local wins = getReplicaData(replica, "WINS")
	local holderFrame = winsFrame:FindFirstChild("Frame")
	if holderFrame then
		local textLabel = holderFrame:FindFirstChild("TextLabel")
		if textLabel then textLabel.Text = tostring(wins) end
	else
		local textLabel = winsFrame:FindFirstChild("TextLabel")
		if textLabel then textLabel.Text = tostring(wins) end
	end
end

function OverheadService:_setStreak(holder, replica)
	local streakFrame = holder:FindFirstChild("Streak")
	if not streakFrame then return end

	local streak = getReplicaData(replica, "STREAK")
	if streak > 0 then
		streakFrame.Visible = true
		local innerFrame = streakFrame:FindFirstChild("Frame")
		if innerFrame then
			local textLabel = innerFrame:FindFirstChild("TextLabel")
			if textLabel then textLabel.Text = tostring(streak) end
		end
	else
		streakFrame.Visible = false
	end
end

-- =============================================================================
-- LIVE DATA REFRESH (Replica ListenToChange callback)
-- =============================================================================

function OverheadService:_refreshOverheadData(player)
	local overhead = self._overheads[player]
	if not overhead or not overhead.Parent then return end

	local replica = Data.GetReplica(player)
	if not replica then return end

	local active = overhead:FindFirstChild("Active")
	if not active then return end

	local holder = active:FindFirstChild("Holder")
	if not holder then return end

	self:_setCrowns(holder, replica)
	self:_setWins(holder, replica)
	self:_setStreak(holder, replica)
end

-- =============================================================================
-- PLATFORM REMOTE
-- =============================================================================

function OverheadService:_onSetPlatform(player, platform)
	if type(platform) ~= "string" then return end
	if platform ~= "PC" and platform ~= "Controller" and platform ~= "Mobile" then return end

	player:SetAttribute("Platform", platform)

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
