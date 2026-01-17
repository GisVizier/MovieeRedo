local ReplicationDebugger = {}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)

-- UI Elements
local screenGui = nil
local debugLabel = nil
local hintLabel = nil
local localPlayer = Players.LocalPlayer

function ReplicationDebugger:Init()
	Log:RegisterCategory("REPL_DEBUG", "Replication system debugger UI")

	-- Create debug UI
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ReplicationDebugger"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

	-- Debug info label
	debugLabel = Instance.new("TextLabel")
	debugLabel.Name = "DebugLabel"
	debugLabel.Size = UDim2.fromOffset(0, 0) -- Will be auto-sized
	debugLabel.Position = UDim2.new(1, -10, 0, 10)
	debugLabel.AnchorPoint = Vector2.new(1, 0) -- Anchor to top-right
	debugLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	debugLabel.BackgroundTransparency = 0.3
	debugLabel.BorderSizePixel = 2
	debugLabel.BorderColor3 = Color3.fromRGB(0, 255, 0)
	debugLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
	debugLabel.TextSize = 14
	debugLabel.Font = Enum.Font.Code
	debugLabel.TextXAlignment = Enum.TextXAlignment.Center
	debugLabel.TextYAlignment = Enum.TextYAlignment.Top
	debugLabel.Text = "Replication Debug\nInitializing..."
	debugLabel.AutomaticSize = Enum.AutomaticSize.XY -- Auto-resize width and height to fit content
	debugLabel.Visible = false -- Start hidden until ready
	debugLabel.Parent = screenGui

	-- Add padding for better text layout (equal padding for centered text)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 15)
	padding.PaddingRight = UDim.new(0, 15)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = debugLabel

	-- F4 hint label (below the main panel, centered)
	hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "HintLabel"
	hintLabel.Size = UDim2.fromOffset(0, 0)
	hintLabel.Position = UDim2.new(1, -10, 0, 0) -- Will be positioned relative to debugLabel
	hintLabel.AnchorPoint = Vector2.new(0.5, 0) -- Center anchor point
	hintLabel.BackgroundTransparency = 1 -- No background
	hintLabel.TextColor3 = Color3.fromRGB(150, 150, 150) -- Dimmer gray text
	hintLabel.TextSize = 12
	hintLabel.Font = Enum.Font.Code
	hintLabel.TextXAlignment = Enum.TextXAlignment.Center
	hintLabel.Text = "Press F4 to toggle"
	hintLabel.AutomaticSize = Enum.AutomaticSize.XY
	hintLabel.Visible = false -- Start hidden until positioned correctly
	hintLabel.Parent = screenGui

	-- Update every frame
	RunService.Heartbeat:Connect(function()
		self:UpdateDebugInfo()
		-- Position hint label centered below the debug label
		local panelCenterX = debugLabel.AbsolutePosition.X + (debugLabel.AbsoluteSize.X / 2)
		hintLabel.Position =
			UDim2.fromOffset(panelCenterX, debugLabel.AbsolutePosition.Y + debugLabel.AbsoluteSize.Y + 5)
	end)

	-- Toggle with F4
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F4 then
			if debugLabel and hintLabel then
				local isVisible = not debugLabel.Visible
				debugLabel.Visible = isVisible
				hintLabel.Visible = isVisible
				Log:Debug("REPL_DEBUG", "Toggled visibility", { Visible = isVisible })
			end
		end
	end)

	Log:Info("REPL_DEBUG", "Initialized - Press F4 to toggle")
end

function ReplicationDebugger:UpdateDebugInfo()
	if not debugLabel then
		return
	end

	local ClientReplicator = require(localPlayer.PlayerScripts.Systems.Replication.ClientReplicator)
	local RemoteReplicator = require(localPlayer.PlayerScripts.Systems.Replication.RemoteReplicator)

	local clientStats = ClientReplicator:GetPerformanceStats()
	local remoteStats = RemoteReplicator:GetPerformanceStats()

	-- Verify custom replication is active
	local replicationStatus = "INACTIVE"
	if ClientReplicator.IsActive and ClientReplicator.Character then
		replicationStatus = "ACTIVE"
	elseif ClientReplicator.IsActive then
		replicationStatus = "WAITING"
	end

	-- Calculate FPS
	local fps = math.floor(1 / RunService.Heartbeat:Wait())

	-- Calculate bandwidth usage (client outbound)
	local bytesPerPacket = 41 -- Sera compressed state size (with SequenceNumber)
	local bandwidthOut = (clientStats.PacketsSent * bytesPerPacket) / 1024 -- KB/s
	local bandwidthIn = (remoteStats.StatesReceived * bytesPerPacket * remoteStats.TrackedPlayers) / 1024 -- KB/s (all players)

	-- Calculate efficiency (how many updates we skip via delta compression)
	local totalPossibleUpdates = clientStats.PacketsSent + clientStats.UpdatesSkipped
	local efficiencyPercent = totalPossibleUpdates > 0
			and math.floor((clientStats.UpdatesSkipped / totalPossibleUpdates) * 100)
		or 0

	-- Get ping (if available)
	local ping = localPlayer:GetNetworkPing() * 1000 -- Convert to ms

	-- Get packet loss statistics
	-- NOTE: With UnreliableRemoteEvent, we should see MUCH lower packet loss (~0-5%)
	-- RemoteEvent at 60Hz caused ~24% loss due to Roblox throttling
	-- UnreliableRemoteEvent only has natural network packet loss
	local globalLossRate = remoteStats.GlobalPacketLossRate or 0
	local globalLossPercent = globalLossRate * 100
	local lossStatus = "EXCELLENT"
	if globalLossPercent > 15 then
		lossStatus = "CRITICAL!" -- Severe network issues
	elseif globalLossPercent > 10 then
		lossStatus = "HIGH" -- Poor network quality
	elseif globalLossPercent > 5 then
		lossStatus = "MODERATE" -- Acceptable for some networks
	elseif globalLossPercent > 2 then
		lossStatus = "LOW" -- Normal for unstable connections
	elseif globalLossPercent > 0.5 then
		lossStatus = "GOOD" -- Typical range with UnreliableRemoteEvent
	end

	-- Note: Client-side packet loss calculation was removed as the value was unused
	-- The global packet loss rate (server→client) already provides sufficient network quality metrics

	-- Build debug text with useful metrics (now includes packet loss breakdown)
	local debugText = string.format(
		[[
=== REPLICATION SYSTEM ===

Status: %s | FPS: %d | Ping: %.0fms

CLIENT → SERVER
Sent: %d packets/sec (%.1f KB/s)
Skipped: %d (%d%% efficiency)
Reconciling: %s

SERVER → CLIENT (from other players)
Received: %d packets/sec (%.1f KB/s)
Players: %d
Buffer Health: %s

NETWORK QUALITY
Packet Loss (server→client): %.1f%% (%s)
Lost: %d / Expected: %d
Per-Player Stats: %s

PERFORMANCE
Interpolations/sec: %d
Target Rate: 60 Hz
Delta Efficiency: %d%%]],
		replicationStatus,
		fps,
		ping,
		clientStats.PacketsSent,
		bandwidthOut,
		clientStats.UpdatesSkipped,
		efficiencyPercent,
		clientStats.IsReconciling and "YES" or "NO",
		remoteStats.StatesReceived,
		bandwidthIn,
		remoteStats.TrackedPlayers,
		self:GetBufferHealthStatus(RemoteReplicator),
		globalLossPercent,
		lossStatus,
		remoteStats.PacketsLost or 0,
		(remoteStats.PacketsReceived or 0) + (remoteStats.PacketsLost or 0),
		self:FormatPerPlayerLoss(remoteStats.PlayerLossStats or {}),
		remoteStats.Interpolations,
		efficiencyPercent
	)

	debugLabel.Text = debugText
end

function ReplicationDebugger:FormatPerPlayerLoss(playerStats)
	if #playerStats == 0 then
		return "None"
	end

	local lines = {}
	for _, stat in ipairs(playerStats) do
		local lossPercent = (stat.LossRate or 0) * 100
		table.insert(lines, string.format("%s: %.1f%%", stat.Player, lossPercent))
	end

	return table.concat(lines, ", ")
end

function ReplicationDebugger:GetBufferHealthStatus(RemoteReplicator)
	-- Check buffer health across all tracked players
	local minBufferSize = math.huge
	local avgBufferSize = 0
	local playerCount = 0

	for _userId, remoteData in pairs(RemoteReplicator.RemotePlayers) do
		if remoteData and remoteData.SnapshotBuffer then
			local bufferSize = #remoteData.SnapshotBuffer
			minBufferSize = math.min(minBufferSize, bufferSize)
			avgBufferSize = avgBufferSize + bufferSize
			playerCount = playerCount + 1
		end
	end

	if playerCount == 0 then
		return "N/A"
	end

	avgBufferSize = math.floor(avgBufferSize / playerCount)
	minBufferSize = minBufferSize == math.huge and 0 or minBufferSize

	-- Health assessment
	if minBufferSize >= 5 then
		return string.format("GOOD (min:%d avg:%d)", minBufferSize, avgBufferSize)
	elseif minBufferSize >= 3 then
		return string.format("OK (min:%d avg:%d)", minBufferSize, avgBufferSize)
	else
		return string.format("LOW! (min:%d avg:%d)", minBufferSize, avgBufferSize)
	end
end

return ReplicationDebugger
