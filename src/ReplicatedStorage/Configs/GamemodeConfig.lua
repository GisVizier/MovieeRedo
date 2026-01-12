local GamemodeConfig = {
	Deathmatch = {
		name = "Deathmatch",
		time = 300,
		rewards = {
			{
				name = "EXP",
				amount = 50,
				imageId = "rbxassetid://6764432293",
				type = "currency",
			},
			{
				name = "Coins",
				amount = 100,
				imageId = "rbxassetid://6764432408",
				type = "currency",
			},
		},
		playerReq = {
			min = 2,
			max = 8,
		},
		teamCount = 2,
		startingLives = 1,
		canRespawn = false,
	},

	TeamDeathmatch = {
		name = "Team Deathmatch",
		time = 600,
		rewards = {
			{
				name = "EXP",
				amount = 75,
				imageId = "rbxassetid://6764432293",
				type = "currency",
			},
			{
				name = "Coins",
				amount = 150,
				imageId = "rbxassetid://6764432408",
				type = "currency",
			},
			{
				name = "Crate",
				amount = 1,
				imageId = "rbxassetid://6764432188",
				type = "item",
			},
		},
		playerReq = {
			min = 4,
			max = 12,
		},
		teamCount = 2,
		startingLives = 3,
		canRespawn = true,
	},

	TwoVTwo = {
		name = "2v2",
		time = 180,
		rewards = {
			{
				name = "EXP",
				amount = 60,
				imageId = "rbxassetid://6764432293",
				type = "currency",
			},
			{
				name = "Coins",
				amount = 120,
				imageId = "rbxassetid://6764432408",
				type = "currency",
			},
		},
		playerReq = {
			min = 4,
			max = 4,
		},
		teamCount = 2,
		startingLives = 2,
		canRespawn = false,
	},

	FourVFour = {
		name = "4v4",
		time = 300,
		rewards = {
			{
				name = "EXP",
				amount = 100,
				imageId = "rbxassetid://6764432293",
				type = "currency",
			},
			{
				name = "Coins",
				amount = 200,
				imageId = "rbxassetid://6764432408",
				type = "currency",
			},
			{
				name = "Crate",
				amount = 2,
				imageId = "rbxassetid://6764432188",
				type = "item",
			},
		},
		playerReq = {
			min = 8,
			max = 8,
		},
		teamCount = 2,
		startingLives = 3,
		canRespawn = false,
	},

	FreeForAll = {
		name = "Free For All",
		time = 300,
		rewards = {
			{
				name = "EXP",
				amount = 40,
				imageId = "rbxassetid://6764432293",
				type = "currency",
			},
			{
				name = "Coins",
				amount = 80,
				imageId = "rbxassetid://6764432408",
				type = "currency",
			},
		},
		playerReq = {
			min = 2,
			max = 8,
		},
		teamCount = 0,
		startingLives = 1,
		canRespawn = true,
	},
}

return GamemodeConfig
