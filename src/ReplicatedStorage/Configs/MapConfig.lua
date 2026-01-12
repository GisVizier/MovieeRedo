local MapConfig = {
	DirtyDepo = {
		name = "Dirty Depo",
		creator = "UiteszeTeam",
		description = "Abandoned industrial warehouse with hazardous terrain and tight corners.",
		imageId = "rbxassetid://93295918336345",
		playerReq = {
			min = 2,
			max = 4,
		},
		instance = nil,
	},

	CrazyConstruct = {
		name = "Crazy Construct",
		creator = "UiteszeTeam",
		description = "Chaotic construction site with vertical gameplay and unstable platforms.",
		imageId = "rbxassetid://107212538193568",
		playerReq = {
			min = 4,
			max = 8,
		},
		instance = nil,
	},

	ApexArena = {
		name = "Apex Arena",
		creator = "UiteszeTeam",
		description = "Premier combat arena built for competitive battles and intense showdowns.",
		imageId = "rbxassetid://122392514179092",
		playerReq = {
			min = 2,
			max = 12,
		},
		instance = nil,
	},
}

function MapConfig.getMapsForPlayerCount(playerCount)
	local validMaps = {}

	for mapId, mapData in MapConfig do
		if type(mapData) == "table" and mapData.playerReq then
			if playerCount >= mapData.playerReq.min and playerCount <= mapData.playerReq.max then
				table.insert(validMaps, {
					id = mapId,
					data = mapData,
				})
			end
		end
	end

	return validMaps
end

function MapConfig.getAllMaps()
	local maps = {}

	for mapId, mapData in MapConfig do
		if type(mapData) == "table" and mapData.name then
			table.insert(maps, {
				id = mapId,
				data = mapData,
			})
		end
	end

	return maps
end

function MapConfig.getMap(mapId)
	return MapConfig[mapId]
end

return MapConfig
