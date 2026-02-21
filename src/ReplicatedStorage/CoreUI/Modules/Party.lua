local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:FindFirstChild("Configs")
local LobbyData = require(Configs.LobbyData)
local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)

local module = {}
module.__index = module

type ActivePlayerTemplate = Frame & {
	UICorner: UICorner,
	UIGradient: UIGradient,
	UIListLayout: UIListLayout,

	Actions: Frame & {
		UIListLayout: UIListLayout,
		UIPadding: UIPadding,

		Invite: ImageButton & {
			UICorner: UICorner,
			UIGradient: UIGradient,
			UIStroke: UIStroke,
			TextLabel: TextLabel,
		},

		Trade: ImageButton & {
			UICorner: UICorner,
			UIGradient: UIGradient,
			UIStroke: UIStroke,
			TextLabel: TextLabel,
		},
	},

	Template: Frame & {
		UIListLayout: UIListLayout,
		UIPadding: UIPadding,
		UIScale: UIScale,

		Data: Frame & {
			UIListLayout: UIListLayout,
			UIPadding: UIPadding,

			Frame: Frame & {
				UIListLayout: UIListLayout,
				ImageLabel: ImageLabel,
				TextLabel: TextLabel & {
					UIGradient: UIGradient,
				},
			},

			Frame1: Frame & {
				UIListLayout: UIListLayout,
				ImageLabel: ImageLabel,
				TextLabel: TextLabel & {
					UIGradient: UIGradient,
				},
			},

			Plr: Frame & {
				UIGradient: UIGradient,
				UIListLayout: UIListLayout,
				UIPadding: UIPadding,
				TextLabel: TextLabel,
				TextLabel1: TextLabel,
				_: TextLabel,
			},

			PlayerIcon: ImageLabel & {
				UICorner: UICorner,
			},
		},
	},
}

type PartyTemplate = Frame & {
	UICorner: UICorner,
	UIGradient: UIGradient,

	Template: Frame & {
		UIListLayout: UIListLayout,
		UIPadding: UIPadding,
		UIScale: UIScale,

		Data: Frame & {
			UIListLayout: UIListLayout,
			UIPadding: UIPadding,

			Frame: Frame & {
				UIListLayout: UIListLayout,
				ImageLabel: ImageLabel,
				TextLabel: TextLabel & {
					UIGradient: UIGradient,
				},
			},

			Frame1: Frame & {
				UIListLayout: UIListLayout,
				ImageLabel: ImageLabel,
				TextLabel: TextLabel & {
					UIGradient: UIGradient,
				},
			},

			Plr: Frame & {
				UIGradient: UIGradient,
				UIListLayout: UIListLayout,
				UIPadding: UIPadding,
				TextLabel: TextLabel,
				TextLabel1: TextLabel,
				_: TextLabel,
			},

			PlayerIcon: ImageLabel & {
				UICorner: UICorner,
			},
		},
	},
}

type PartyUI = Frame & {
	Frame: Frame & {
		UIListLayout: UIListLayout,
		UIScale: UIScale,

		ActivePlayers: ScrollingFrame & {
			UIListLayout: UIListLayout,
		},

		Interaction: Frame & {
			SearchBar: Frame & {
				UIStroke: UIStroke,

				Bar: Frame & {
					UIGradient: UIGradient,

					Select: Frame & {
						UIGradient: UIGradient,
					},

					TextBox: TextBox,
				},
			},

			CloseButton: ImageButton & {
				UIStroke: UIStroke & {
					UIGradient: UIGradient,
				},
				Flash: ImageLabel,
				ImageLabel: ImageLabel,
				ImageLabel1: ImageLabel,
			},

			Filter: Frame & {
				UIStroke: UIStroke,

				IconHolder: Frame & {
					UIGradient: UIGradient,
					UIListLayout: UIListLayout,
					UIPadding: UIPadding,
					ImageLabel: ImageLabel,
					TextLabel: TextLabel,
				},

				Select: Frame & {
					UIGradient: UIGradient,
				},
			},

			Filters: CanvasGroup & {
				UIListLayout: UIListLayout,
				UIPadding: UIPadding,

				Friends: Frame & {
					UIStroke: UIStroke,

					IconHolder: Frame & {
						UIGradient: UIGradient,
						UIListLayout: UIListLayout,
						UIPadding: UIPadding,
						ImageLabel: ImageLabel,
						TextLabel: TextLabel,
					},

					Select: Frame & {
						UIGradient: UIGradient,
					},
				},

				Lobby: Frame & {
					UIStroke: UIStroke,

					IconHolder: Frame & {
						UIGradient: UIGradient,
						UIListLayout: UIListLayout,
						UIPadding: UIPadding,
						ImageLabel: ImageLabel,
						TextLabel: TextLabel,
					},

					Select: Frame & {
						UIGradient: UIGradient,
					},
				},
			},

			ImageLabel: ImageLabel & {
				UICorner: UICorner,
			},
		},

		Party: CanvasGroup & {
			UIListLayout: UIListLayout,
		},
	},
}

local TEST_FRIENDS = {1, 156, 123721150, 9124290782, 3882191972, 204471960, 1565898941, 1504566816, 343967586, 377433232, 290622415, 698869311, 341579096, 2597075511}

local DEFAULT_PLAYER_DATA = {crowns = 0, streak = 0}

local PARTY_COLORS = {
	[1] = ColorSequence.new(Color3.fromRGB(255, 215, 0)),
	[2] = ColorSequence.new(Color3.fromRGB(192, 192, 192)),
	[3] = ColorSequence.new(Color3.fromRGB(205, 127, 50)),
	[4] = ColorSequence.new(Color3.fromRGB(147, 112, 219)),
	[5] = ColorSequence.new(Color3.fromRGB(100, 149, 237)),
	[6] = ColorSequence.new(Color3.fromRGB(144, 238, 144)),
}

local IN_PARTY_FRAME_COLOR = Color3.fromRGB(68, 68, 68)
local INVITED_STROKE_COLOR = Color3.fromRGB(128, 128, 128)
local IN_PARTY_STROKE_COLOR = Color3.fromRGB(100, 200, 100)

local PARTY_LIMIT = 6
local INVITE_DELAY = 4
local IN_PARTY_LAYOUT_ORDER = -100

local TWEEN_SHOW = TweenInfo.new(0.67, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_HIDE = TweenInfo.new(0.56, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local TWEEN_FILTER = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SELECT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SCALE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_HOVER = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local currentTweens = {}

function module.start(export, ui: PartyUI)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._tween = export.tween
	self._connections = export.connections

	self._activePlayerData = {}
	self._partyData = {}
	self._partyOrder = {}
	self._pendingInvites = {}

	self._filtersOpen = false
	self._friendsFilterActive = false
	self._lobbyFilterActive = false
	self._searchQuery = ""

	self._activePlayerTemplate = script:FindFirstChild("ActivePlayerTemplate")
	self._partyTemplate = script:FindFirstChild("PartyTemplate")

	self._originalUIPosition = self._ui.Position
	self._originalFiltersPosition = nil
	self._originalCloseButtonGradientRotation = nil
	self._initialized = false

	return self
end

function module:_init()
	if self._initialized then
		self:_populateActivePlayers()
		return
	end

	self._initialized = true
	self:_cacheOriginals()
	self:_setupFilters()
	self:_setupSearchBar()
	self:_setupCloseButton()
	self:_setupEventListeners()
	self:_createLocalPlayerParty()
	self:_populateActivePlayers()
end

function module:_cacheOriginals()
	local interaction = self._ui.Frame.Interaction
	local filters = interaction.Filters
	local closeButton = interaction.CloseButton

	self._originalFiltersPosition = filters.Position
	filters.Position = UDim2.new(
		self._originalFiltersPosition.X.Scale - 0.015,
		self._originalFiltersPosition.X.Offset,
		self._originalFiltersPosition.Y.Scale,
		self._originalFiltersPosition.Y.Offset
	)
	filters.GroupTransparency = 1
	filters.Visible = false

	local closeStroke = closeButton:FindFirstChild("UIStroke")
	if closeStroke then
		local strokeGradient = closeStroke:FindFirstChild("UIGradient")
		if strokeGradient then
			self._originalCloseButtonGradientRotation = strokeGradient.Rotation
		end
	end
end

function module:_getPlayers()
	local players = {}

	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			table.insert(players, player.UserId)
		end
	end

	if #players == 0 then
		return LobbyData.getAllPlayerIds()
	end

	return players
end

function module:_getFriends()
	local friends = {}
	local localPlayer = false --Players.LocalPlayer

	if not localPlayer then
		return TEST_FRIENDS
	end

	local success, result = pcall(function()
		local friendPages = Players:GetFriendsAsync(localPlayer.UserId)
		while true do
			for _, friend in friendPages:GetCurrentPage() do
				table.insert(friends, friend.Id)
			end

			if friendPages.IsFinished then
				break
			end

			friendPages:AdvanceToNextPageAsync()
		end
	end)

	if not success or #friends == 0 then
		return TEST_FRIENDS
	end

	return friends
end

function module:_getPlayerData(userId)
	local localUserId = self:_getLocalPlayer()

	if userId == localUserId then
		return {
			crowns = PlayerDataTable.getData("CROWNS") or DEFAULT_PLAYER_DATA.crowns,
			streak = PlayerDataTable.getData("STREAK") or DEFAULT_PLAYER_DATA.streak,
		}
	end

	local lobbyPlayer = LobbyData.getPlayer(userId)
	if lobbyPlayer then
		return {
			crowns = lobbyPlayer.wins or 0,
			streak = lobbyPlayer.streak or 0,
		}
	end

	return {
		crowns = DEFAULT_PLAYER_DATA.crowns,
		streak = DEFAULT_PLAYER_DATA.streak,
	}
end

function module:_getLocalPlayer()
	local localPlayer = Players.LocalPlayer

	if localPlayer then
		return localPlayer.UserId
	end

	for _, player in Players:GetPlayers() do
		return player.UserId
	end

	local lobbyPlayers = LobbyData.getAllPlayerIds()
	return lobbyPlayers[1] or 0
end

function module:_createLocalPlayerParty()
	local localUserId = self:_getLocalPlayer()
	self:_createPartyTemplate(localUserId, true)
end

function module:_createActivePlayerTemplate(userId)
	if self._activePlayerData[userId] then
		return self._activePlayerData[userId].template
	end

	local localUserId = self:_getLocalPlayer()
	if userId == localUserId then
		return nil
	end

	if not self._activePlayerTemplate then
		return nil
	end

	local template: ActivePlayerTemplate = self._activePlayerTemplate:Clone()
	template.Name = "ActivePlayer_" .. userId
	template.Visible = true

	local uiScale = template:FindFirstChild("UIScale")
	if uiScale then
		uiScale.Scale = 0.8
	end

	template.Parent = self._ui.Frame.ActivePlayers

	local isInParty = self._partyData[userId] ~= nil

	self._activePlayerData[userId] = {
		template = template,
		userId = userId,
		displayName = "",
		username = "",
		invited = false,
		inParty = isInParty,
		originalLayoutOrder = template.LayoutOrder,
		originalFrameColor = template.BackgroundColor3,
		originalInviteStrokeColor = nil,
		originalInviteButtonColor = nil,
	}

	if isInParty then
		self:_updateActivePlayerInPartyState(userId, true)
	end

	task.spawn(function()
		local success, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)

		local username = success and name or "Unknown"
		local displayName = username

		local player = Players:GetPlayerByUserId(userId)
		if player then
			displayName = player.DisplayName
		end

		local data = self._activePlayerData[userId]
		if data then
			data.displayName = displayName
			data.username = username
		end

		local plrFrame = template.Template.Data:FindFirstChild("Usernames")
		if plrFrame then
			local nameLabel = plrFrame:FindFirstChild("_name")
			local usernameLabel = plrFrame:FindFirstChild("usernam")

			if nameLabel then
				nameLabel.Text = displayName
			end

			if usernameLabel then
				usernameLabel.Text = "@" .. username
			end
		end
	end)

	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)

		if success and content then
			local playerIcon = template.Template:FindFirstChild("PlayerIcon")
			if playerIcon then
				playerIcon.Image = content
			end
		end
	end)

	local playerData = self:_getPlayerData(userId)
	local dataFrame = template.Template.Data.Data

	local crownsFrame = dataFrame:FindFirstChild("Crowns")
	if crownsFrame then
		local crownsLabel = crownsFrame:FindFirstChild("TextLabel")
		if crownsLabel then
			crownsLabel.Text = tostring(playerData.crowns)
		end
	end

	local streakFrame = dataFrame:FindFirstChild("Streak")
	if streakFrame then
		local streakLabel = streakFrame:FindFirstChild("TextLabel")
		if streakLabel then
			streakLabel.Text = tostring(playerData.streak)
		end
	end

	local inviteButton = template.Actions:FindFirstChild("Invite")
	if inviteButton then
		self._activePlayerData[userId].originalInviteButtonColor = inviteButton.BackgroundColor3

		local inviteStroke = inviteButton:FindFirstChild("UIStroke")
		if inviteStroke then
			self._activePlayerData[userId].originalInviteStrokeColor = inviteStroke.Color
		end
	end
	
	if uiScale then
		local scaleTween = TweenService:Create(uiScale, TWEEN_SCALE, {
			Scale = 1,
		})
		scaleTween:Play()
	end

	self:_setupActivePlayerButtons(template, userId)
	self:_setupActivePlayerHover(template, userId)

	return template
end

function module:_removeActivePlayerTemplate(userId)
	local data = self._activePlayerData[userId]
	if not data then
		return false
	end

	self._connections:cleanupGroup("activePlayer_" .. userId)
	self._connections:cleanupGroup("activePlayerHover_" .. userId)

	local template = data.template
	local uiScale = template:FindFirstChild("UIScale")

	template:Destroy()
	self._activePlayerData[userId] = nil

	return true
end

function module:_setupActivePlayerButtons(template: ActivePlayerTemplate, userId)
	local groupName = "activePlayer_" .. userId
	local actions = template.Actions

	local inviteButton = actions:FindFirstChild("Invite")
	local tradeButton = actions:FindFirstChild("Trade")

	if inviteButton then
		self._connections:track(inviteButton, "Activated", function()
			self:_invitePlayer(userId)
		end, groupName)
	end

	if tradeButton then
		self._connections:track(tradeButton, "Activated", function()
			self._export:emit("TradeRequest", userId)
		end, groupName)
	end
end

function module:_setupActivePlayerHover(template: ActivePlayerTemplate, userId)
	local groupName = "activePlayerHover_" .. userId
	local isHovering = false

	local uiStroke = template:FindFirstChild("UIStroke")
	local originalStrokeTransparency = uiStroke and uiStroke.Transparency or 1
	local originalStrokeColor = uiStroke and uiStroke.Color or Color3.new(1, 1, 1)
	local originalBackgroundColor = template.BackgroundColor3

	local hoverBackgroundColor = Color3.new(
		math.min(originalBackgroundColor.R + 0.15, 1),
		math.min(originalBackgroundColor.G + 0.15, 1),
		math.min(originalBackgroundColor.B + 0.15, 1)
	)

	local function onHoverStart()
		if isHovering then
			return
		end

		isHovering = true

		if currentTweens["activeHover_" .. userId] then
			for _, tween in currentTweens["activeHover_" .. userId] do
				tween:Cancel()
			end
		end

		local tweens = {}

		if uiStroke then
			local strokeTween = TweenService:Create(uiStroke, TWEEN_HOVER, {
				Transparency = 0,
			})
			strokeTween:Play()
			table.insert(tweens, strokeTween)
		end

		local colorTween = TweenService:Create(template, TWEEN_HOVER, {
			BackgroundColor3 = hoverBackgroundColor,
		})
		colorTween:Play()
		table.insert(tweens, colorTween)

		currentTweens["activeHover_" .. userId] = tweens
	end

	local function onHoverEnd()
		if not isHovering then
			return
		end

		isHovering = false

		if currentTweens["activeHover_" .. userId] then
			for _, tween in currentTweens["activeHover_" .. userId] do
				tween:Cancel()
			end
		end

		local tweens = {}

		if uiStroke then
			local strokeTween = TweenService:Create(uiStroke, TWEEN_HOVER, {
				Transparency = originalStrokeTransparency,
			})
			strokeTween:Play()
			table.insert(tweens, strokeTween)
		end

		local colorTween = TweenService:Create(template, TWEEN_HOVER, {
			BackgroundColor3 = originalBackgroundColor,
		})
		colorTween:Play()
		table.insert(tweens, colorTween)

		currentTweens["activeHover_" .. userId] = tweens
	end

	self._connections:track(template, "MouseEnter", onHoverStart, groupName)
	self._connections:track(template, "MouseLeave", onHoverEnd, groupName)
	self._connections:track(template, "SelectionGained", onHoverStart, groupName)
	self._connections:track(template, "SelectionLost", onHoverEnd, groupName)
end

function module:_updateActivePlayerInPartyState(userId, inParty)
	local data = self._activePlayerData[userId]
	if not data then
		return
	end

	local template = data.template
	local inviteButton = template.Actions:FindFirstChild("Invite")

	data.inParty = inParty

	if inParty then
		template.LayoutOrder = -3

		TweenService:Create(template, TWEEN_SELECT, {
			BackgroundColor3 = IN_PARTY_FRAME_COLOR,
		}):Play()

		if inviteButton then
			inviteButton.TextLabel.Text = "In Party"

			local inviteGradient = inviteButton:FindFirstChild("UIGradient")
			if inviteGradient then
				inviteGradient.Enabled = false
			end

			TweenService:Create(inviteButton, TWEEN_SELECT, {
				BackgroundColor3 = IN_PARTY_STROKE_COLOR,
			}):Play()

			local inviteStroke = inviteButton:FindFirstChild("UIStroke")
			if inviteStroke then
				TweenService:Create(inviteStroke, TWEEN_SELECT, {
					Color = IN_PARTY_STROKE_COLOR,
				}):Play()
			end
			
			inviteButton.Active = false
		end
	else
		template.LayoutOrder = data.originalLayoutOrder

		if data.originalFrameColor then
			TweenService:Create(template, TWEEN_SELECT, {
				BackgroundColor3 = data.originalFrameColor,
			}):Play()
		end

		if inviteButton then
			inviteButton.TextLabel.Text = "Invite"
			inviteButton.Active = true
			inviteButton.Interactable = true

			local inviteGradient = inviteButton:FindFirstChild("UIGradient")
			if inviteGradient then
				inviteGradient.Enabled = true
			end

			if data.originalInviteButtonColor then
				TweenService:Create(inviteButton, TWEEN_SELECT, {
					BackgroundColor3 = data.originalInviteButtonColor,
				}):Play()
			end

			local inviteStroke = inviteButton:FindFirstChild("UIStroke")
			if inviteStroke and data.originalInviteStrokeColor then
				TweenService:Create(inviteStroke, TWEEN_SELECT, {
					Color = data.originalInviteStrokeColor,
				}):Play()
			end
		end
	end
end

function module:_createPartyTemplate(userId, isLeader)
	if self._partyData[userId] then
		return self._partyData[userId].template
	end

	if not self._partyTemplate then
		return nil
	end

	local template: PartyTemplate = self._partyTemplate:Clone()
	template.Name = "PartyMember_" .. userId
	template.Visible = true

	local partyPosition = #self._partyOrder + 1
	table.insert(self._partyOrder, userId)

	template.LayoutOrder = partyPosition

	local uiScale = template:FindFirstChild("UIScale")
	if uiScale then
		uiScale.Scale = 0.67
	end

	local partyGradient = template:FindFirstChild("UIGradient")
	if partyGradient then
		local colorSequence = PARTY_COLORS[partyPosition] or PARTY_COLORS[6]
		partyGradient.Color = colorSequence
	end

	template.Parent = self._ui.Frame.Party

	self._partyData[userId] = {
		template = template,
		userId = userId,
		displayName = "",
		username = "",
		isLeader = isLeader or false,
		position = partyPosition,
	}

	task.spawn(function()
		local success, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)

		local username = success and name or "Unknown"
		local displayName = username

		local player = Players:GetPlayerByUserId(userId)
		if player then
			displayName = player.DisplayName
		end

		local data = self._partyData[userId]
		if data then
			data.displayName = displayName
			data.username = username
		end

		local plrFrame = template.Template.Data:FindFirstChild("Usernames")
		if plrFrame then
			local nameLabel = plrFrame:FindFirstChild("_name")
			local usernameLabel = plrFrame:FindFirstChild("usernam")

			if nameLabel then
				nameLabel.Text = displayName
			end

			if usernameLabel then
				usernameLabel.Text = "@" .. username
			end
		end
	end)

	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)

		if success and content then
			local playerIcon = template.Template:FindFirstChild("PlayerIcon")
			if playerIcon then
				playerIcon.Image = content
			end
		end
	end)

	local playerData = self:_getPlayerData(userId)
	local dataFrame = template.Template.Data.Data

	local crownsFrame = dataFrame:FindFirstChild("Crowns")
	if crownsFrame then
		local crownsLabel = crownsFrame:FindFirstChild("TextLabel")
		if crownsLabel then
			crownsLabel.Text = tostring(playerData.crowns)
		end
	end

	local streakFrame = dataFrame:FindFirstChild("Streak")
	if streakFrame then
		local streakLabel = streakFrame:FindFirstChild("TextLabel")
		if streakLabel then
			streakLabel.Text = tostring(playerData.streak)
		end
	end

	if uiScale then
		local scaleTween = TweenService:Create(uiScale, TWEEN_SCALE, {
			Scale = 1,
		})
		scaleTween:Play()
	end

	return template
end

function module:_removePartyTemplate(userId)
	local data = self._partyData[userId]
	if not data then
		return false
	end

	local template = data.template
	local uiScale = template.Template:FindFirstChild("UIScale")

	local orderIndex = table.find(self._partyOrder, userId)
	if orderIndex then
		table.remove(self._partyOrder, orderIndex)
	end

	self:_updatePartyColors()

	if uiScale then
		local scaleTween = TweenService:Create(uiScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Scale = 0,
		})
		scaleTween:Play()

		scaleTween.Completed:Once(function()
			template:Destroy()
		end)
	else
		template:Destroy()
	end

	self._partyData[userId] = nil

	if self._activePlayerData[userId] then
		self:_updateActivePlayerInPartyState(userId, false)
	end

	return true
end

function module:_updatePartyColors()
	for i, oderId in self._partyOrder do
		local data = self._partyData[oderId]
		if data then
			data.position = i
			data.template.LayoutOrder = i

			local partyGradient = data.template:FindFirstChild("UIGradient")
			if partyGradient then
				local colorSequence = PARTY_COLORS[i] or PARTY_COLORS[6]
				--TweenService:Create(partyGradient, TWEEN_SELECT, {
				--	Color = colorSequence,
				--}):Play()
			end
		end
	end
end

function module:_getPartyCount()
	local count = 0
	for _ in self._partyData do
		count += 1
	end
	return count
end

function module:getPartyData()
	return self._partyData
end

function module:getPartyOrder()
	return self._partyOrder
end

function module:isInParty(userId)
	return self._partyData[userId] ~= nil
end

function module:_invitePlayer(userId)
	if self._pendingInvites[userId] then
		return
	end

	if self._partyData[userId] then
		return
	end

	if self:_getPartyCount() >= PARTY_LIMIT then
		return
	end

	local activeData = self._activePlayerData[userId]
	if not activeData then
		return
	end

	self._pendingInvites[userId] = true
	activeData.invited = true

	local inviteButton = activeData.template.Actions:FindFirstChild("Invite")
	if inviteButton then
		inviteButton.TextLabel.Text = "Invited"

		local inviteGradient = inviteButton:FindFirstChild("UIGradient")
		if inviteGradient then
			inviteGradient.Enabled = false
		end

		TweenService:Create(inviteButton, TWEEN_SELECT, {
			BackgroundColor3 = INVITED_STROKE_COLOR,
		}):Play()

		local inviteStroke = inviteButton:FindFirstChild("UIStroke")
		if inviteStroke then
			TweenService:Create(inviteStroke, TWEEN_SELECT, {
				Color = INVITED_STROKE_COLOR,
			}):Play()
		end
		
		inviteButton.Active = false
		inviteButton.Interactable = false
	end

	self._export:emit("PartyInviteSend", { targetUserId = userId })
end

function module:_populateActivePlayers()
	for oderId in self._activePlayerData do
		self:_removeActivePlayerTemplate(oderId)
	end

	local players = self:_getPlayers()

	for i, userId in players do
		task.delay((i - 1) * 0.035, function()
			self:_createActivePlayerTemplate(userId)
		end)
	end
end

function module:_filterActivePlayers()
	local showFriends = self._friendsFilterActive
	local showLobby = self._lobbyFilterActive
	local searchQuery = string.lower(self._searchQuery)

	local friends = showFriends and self:_getFriends() or {}
	local friendsSet = {}
	for _, friendId in friends do
		friendsSet[friendId] = true
	end

	for oderId, data in self._activePlayerData do
		local template = data.template
		local shouldShow = true

		if showFriends and showLobby then
			shouldShow = friendsSet[oderId] ~= nil
		elseif showFriends then
			shouldShow = friendsSet[oderId] ~= nil
		elseif showLobby then
			shouldShow = true
		end

		if shouldShow and searchQuery ~= "" then
			local displayName = string.lower(data.displayName or "")
			local username = string.lower(data.username or "")

			local matchesSearch = string.find(displayName, searchQuery, 1, true) or string.find(username, searchQuery, 1, true)

			shouldShow = matchesSearch ~= nil
		end

		template.Visible = shouldShow
	end
end

function module:_setupFilters()
	local interaction = self._ui.Frame.Interaction
	local filterButton = interaction.Filter
	local filtersFrame = interaction.Filters
	local friendsButton = filtersFrame.Friends
	local lobbyButton = filtersFrame.Lobby

	self._connections:track(filterButton, "InputBegan", function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:_toggleFilters()
		end
	end, "filters")

	self._connections:track(friendsButton, "InputBegan", function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:_toggleFriendsFilter()
		end
	end, "filters")

	self._connections:track(lobbyButton, "InputBegan", function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:_toggleLobbyFilter()
		end
	end, "filters")
end

function module:_toggleFilters()
	local interaction = self._ui.Frame.Interaction
	local filtersFrame = interaction.Filters
	local filterButton = interaction.Filter
	local selectIndicator = filterButton.Select

	self._filtersOpen = not self._filtersOpen

	if currentTweens["filters"] then
		for _, tween in currentTweens["filters"] do
			tween:Cancel()
		end
	end

	if self._filtersOpen then
		filtersFrame.Visible = true

		local slideTween = TweenService:Create(filtersFrame, TWEEN_FILTER, {
			Position = self._originalFiltersPosition,
		})

		local fadeTween = TweenService:Create(filtersFrame, TWEEN_FILTER, {
			GroupTransparency = 0,
		})

		local selectTween = TweenService:Create(selectIndicator, TWEEN_SELECT, {
			BackgroundTransparency = 0,
		})

		slideTween:Play()
		fadeTween:Play()
		selectTween:Play()

		currentTweens["filters"] = {slideTween, fadeTween, selectTween}
	else
		local hiddenPosition = UDim2.new(
			self._originalFiltersPosition.X.Scale - 0.025,
			self._originalFiltersPosition.X.Offset,
			self._originalFiltersPosition.Y.Scale,
			self._originalFiltersPosition.Y.Offset
		)

		local slideTween = TweenService:Create(filtersFrame, TWEEN_FILTER, {
			Position = hiddenPosition,
		})

		local fadeTween = TweenService:Create(filtersFrame, TWEEN_FILTER, {
			GroupTransparency = 1,
		})

		local selectTween = TweenService:Create(selectIndicator, TWEEN_SELECT, {
			BackgroundTransparency = 1,
		})

		slideTween:Play()
		fadeTween:Play()
		selectTween:Play()

		slideTween.Completed:Once(function()
			if not self._filtersOpen then
				filtersFrame.Visible = false
			end
		end)

		currentTweens["filters"] = {slideTween, fadeTween, selectTween}
	end
end

function module:_toggleFriendsFilter()
	local filtersFrame = self._ui.Frame.Interaction.Filters
	local friendsButton = filtersFrame.Friends
	local selectIndicator = friendsButton.Select

	self._friendsFilterActive = not self._friendsFilterActive

	if currentTweens["friendsFilter"] then
		for _, tween in currentTweens["friendsFilter"] do
			tween:Cancel()
		end
	end

	local targetTransparency = self._friendsFilterActive and 0 or 1
	local selectTween = TweenService:Create(selectIndicator, TWEEN_SELECT, {
		BackgroundTransparency = targetTransparency,
	})

	selectTween:Play()
	currentTweens["friendsFilter"] = {selectTween}

	self:_filterActivePlayers()
end

function module:_toggleLobbyFilter()
	local filtersFrame = self._ui.Frame.Interaction.Filters
	local lobbyButton = filtersFrame.Lobby
	local selectIndicator = lobbyButton.Select

	self._lobbyFilterActive = not self._lobbyFilterActive

	if currentTweens["lobbyFilter"] then
		for _, tween in currentTweens["lobbyFilter"] do
			tween:Cancel()
		end
	end

	local targetTransparency = self._lobbyFilterActive and 0 or 1
	local selectTween = TweenService:Create(selectIndicator, TWEEN_SELECT, {
		BackgroundTransparency = targetTransparency,
	})

	selectTween:Play()
	currentTweens["lobbyFilter"] = {selectTween}

	self:_filterActivePlayers()
end

function module:_setupSearchBar()
	local interaction = self._ui.Frame.Interaction
	local searchBar = interaction.SearchBar
	local textBox = searchBar.TextBox

	self._connections:track(textBox, "Changed", function(property)
		if property == "Text" then
			self._searchQuery = textBox.Text
			self:_filterActivePlayers()
		end
	end, "search")

	self._connections:track(textBox, "FocusLost", function()
		self:_filterActivePlayers()
	end, "search")
end

function module:_setupCloseButton()
	local interaction = self._ui.Frame.Interaction
	local closeButton = interaction.CloseButton
	local flash = closeButton:FindFirstChild("Flash")
	local closeStroke = closeButton:FindFirstChild("UIStroke")
	local strokeGradient = closeStroke and closeStroke:FindFirstChild("UIGradient")

	local isHovering = false

	local function onHoverStart()
		if isHovering then
			return
		end

		isHovering = true

		if currentTweens["closeHover"] then
			for _, tween in currentTweens["closeHover"] do
				tween:Cancel()
			end
		end

		local tweens = {}

		if flash then
			local flashTween = TweenService:Create(flash, TWEEN_HOVER, {
				BackgroundTransparency = .75,
			})
			flashTween:Play()
			table.insert(tweens, flashTween)
		end

		if strokeGradient then
			local rotateTween = TweenService:Create(strokeGradient, TWEEN_HOVER, {
				Rotation = 0,
			})
			rotateTween:Play()
			table.insert(tweens, rotateTween)
		end

		currentTweens["closeHover"] = tweens
	end

	local function onHoverEnd()
		if not isHovering then
			return
		end

		isHovering = false

		if currentTweens["closeHover"] then
			for _, tween in currentTweens["closeHover"] do
				tween:Cancel()
			end
		end

		local tweens = {}

		if flash then
			local flashTween = TweenService:Create(flash, TWEEN_HOVER, {
				BackgroundTransparency = 1,
			})
			flashTween:Play()
			table.insert(tweens, flashTween)
		end

		if strokeGradient and self._originalCloseButtonGradientRotation then
			local rotateTween = TweenService:Create(strokeGradient, TWEEN_HOVER, {
				Rotation = self._originalCloseButtonGradientRotation,
			})
			rotateTween:Play()
			table.insert(tweens, rotateTween)
		end

		currentTweens["closeHover"] = tweens
	end

	self._connections:track(closeButton, "MouseEnter", onHoverStart, "close")
	self._connections:track(closeButton, "MouseLeave", onHoverEnd, "close")
	self._connections:track(closeButton, "SelectionGained", onHoverStart, "close")
	self._connections:track(closeButton, "SelectionLost", onHoverEnd, "close")

	self._connections:track(closeButton, "Activated", function()
		local actionsModule = self._export:getModule("Start")
		if actionsModule and actionsModule.showAll then
			actionsModule:showAll()
		end
		--self._export:show("Start", true)
		
		self:hide()	
	end, "close")
end

function module:_setupEventListeners()
	self._export:on("KickPartyMember", function(userId)
		self:_removePartyTemplate(userId)
	end)

	self._export:on("PartyUpdate", function(data)
		if type(data) ~= "table" then
			return
		end
		self:_onPartyUpdate(data)
	end)

	self._export:on("PartyDisbanded", function()
		self:_onPartyDisbanded()
	end)

	self._export:on("PartyKicked", function()
		self:_onPartyDisbanded()
	end)

	self._export:on("PartyInviteDeclined", function(data)
		if type(data) == "table" and data.targetUserId then
			self._pendingInvites[data.targetUserId] = nil
			self:_resetInviteButton(data.targetUserId)
		end
	end)

	self._export:on("PartyInviteBusy", function(data)
		if type(data) == "table" and data.targetUserId then
			self._pendingInvites[data.targetUserId] = nil
			self:_resetInviteButton(data.targetUserId)
		end
	end)
end

function module:_onPartyUpdate(data)
	local localUserId = self:_getLocalPlayer()
	local members = data.members or {}

	local newSet = {}
	for _, uid in ipairs(members) do
		newSet[uid] = true
	end

	for uid in pairs(self._partyData) do
		if not newSet[uid] then
			self:_removePartyTemplate(uid)
		end
	end

	for _, uid in ipairs(members) do
		if not self._partyData[uid] then
			local isLeader = uid == data.leaderId
			self:_createPartyTemplate(uid, isLeader)
			if uid ~= localUserId then
				self:_updateActivePlayerInPartyState(uid, true)
			end
		else
			self._partyData[uid].isLeader = uid == data.leaderId
		end
	end

	for uid in pairs(self._pendingInvites) do
		if newSet[uid] then
			self._pendingInvites[uid] = nil
		end
	end
end

function module:_onPartyDisbanded()
	local uidsToRemove = {}
	for uid in pairs(self._partyData) do
		table.insert(uidsToRemove, uid)
	end

	for _, uid in ipairs(uidsToRemove) do
		local localUserId = self:_getLocalPlayer()
		if uid ~= localUserId then
			self:_removePartyTemplate(uid)
		end
	end

	table.clear(self._pendingInvites)
end

function module:_resetInviteButton(userId)
	local activeData = self._activePlayerData[userId]
	if not activeData then
		return
	end

	activeData.invited = false
	local inviteButton = activeData.template.Actions:FindFirstChild("Invite")
	if inviteButton then
		inviteButton.TextLabel.Text = "Invite"
		inviteButton.Active = true
		inviteButton.Interactable = true

		local inviteGradient = inviteButton:FindFirstChild("UIGradient")
		if inviteGradient then
			inviteGradient.Enabled = true
		end

		if activeData.originalInviteButtonColor then
			TweenService:Create(inviteButton, TWEEN_SELECT, {
				BackgroundColor3 = activeData.originalInviteButtonColor,
			}):Play()
		end

		local inviteStroke = inviteButton:FindFirstChild("UIStroke")
		if inviteStroke and activeData.originalInviteStrokeColor then
			TweenService:Create(inviteStroke, TWEEN_SELECT, {
				Color = activeData.originalInviteStrokeColor,
			}):Play()
		end
	end
end

-- Visual transition for showing (fade in with Black overlay)
function module:transitionIn()
	self._export:show("Black")

	self._ui.Position = UDim2.new(
		self._originalUIPosition.X.Scale,
		self._originalUIPosition.X.Offset,
		self._originalUIPosition.Y.Scale - 0.05,
		self._originalUIPosition.Y.Offset
	)

	local mainCanvas = self._ui
	if mainCanvas then
		mainCanvas.GroupTransparency = 1
	end

	if currentTweens["main"] then
		for _, tween in currentTweens["main"] do
			tween:Cancel()
		end
	end

	local tweens = {}

	if mainCanvas then
		local fadeTween = TweenService:Create(mainCanvas, TWEEN_SHOW, {
			GroupTransparency = 0,
			Position = self._originalUIPosition,
		})
		fadeTween:Play()
		table.insert(tweens, fadeTween)
	end

	currentTweens["main"] = tweens
end

-- Visual transition for hiding (fade out with Black overlay)
function module:transitionOut()
	if currentTweens["main"] then
		for _, tween in currentTweens["main"] do
			tween:Cancel()
		end
	end

	local targetPosition = UDim2.new(
		self._originalUIPosition.X.Scale,
		self._originalUIPosition.X.Offset,
		self._originalUIPosition.Y.Scale - 0.05,
		self._originalUIPosition.Y.Offset
	)

	local tweens = {}

	local mainCanvas = self._ui
	if mainCanvas then
		local fadeTween = TweenService:Create(mainCanvas, TWEEN_HIDE, {
			Position = targetPosition,
			GroupTransparency = 1,
		})
		fadeTween:Play()
		table.insert(tweens, fadeTween)
	end

	currentTweens["main"] = tweens
	self._export:hide("Black")
end

function module:show()
	self._ui.Visible = true
	self:transitionIn()
	self:_init()
	return true
end

function module:hide()
	self:transitionOut()
	return true
end

function module:_cleanup()
	self._initialized = false

	for userId in self._activePlayerData do
		self._connections:cleanupGroup("activePlayer_" .. userId)
		self._connections:cleanupGroup("activePlayerHover_" .. userId)
	end

	self._connections:cleanupGroup("filters")
	self._connections:cleanupGroup("search")
	self._connections:cleanupGroup("close")

	table.clear(self._pendingInvites)
	table.clear(self._activePlayerData)

	self._filtersOpen = false
	self._friendsFilterActive = false
	self._lobbyFilterActive = false
	self._searchQuery = ""

	local interaction = self._ui.Frame.Interaction
	local textBox = interaction.SearchBar.TextBox
	textBox.Text = ""

	local filtersFrame = interaction.Filters
	filtersFrame.Visible = false
	filtersFrame.GroupTransparency = 1
	filtersFrame.Position = UDim2.new(
		self._originalFiltersPosition.X.Scale - 0.015,
		self._originalFiltersPosition.X.Offset,
		self._originalFiltersPosition.Y.Scale,
		self._originalFiltersPosition.Y.Offset
	)

	interaction.Filter.Select.BackgroundTransparency = 1
	filtersFrame.Friends.Select.BackgroundTransparency = 1
	filtersFrame.Lobby.Select.BackgroundTransparency = 1

	local closeButton = interaction.CloseButton
	local flash = closeButton:FindFirstChild("Flash")
	if flash then
		flash.BackgroundTransparency = 1
	end

	local closeStroke = closeButton:FindFirstChild("UIStroke")
	if closeStroke then
		local strokeGradient = closeStroke:FindFirstChild("UIGradient")
		if strokeGradient and self._originalCloseButtonGradientRotation then
			strokeGradient.Rotation = self._originalCloseButtonGradientRotation
		end
	end
end
return module