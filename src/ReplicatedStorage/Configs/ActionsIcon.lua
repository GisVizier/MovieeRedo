local ActionsIcon = {}

ActionsIcon.BindIcons = {
	[Enum.KeyCode.Space] = {
		PC = "rbxassetid://00000001",
		Console = "rbxassetid://00000002",
	},
	[Enum.KeyCode.LeftShift] = {
		PC = "rbxassetid://00000003",
		Console = "rbxassetid://00000004",
	},
	[Enum.KeyCode.RightShift] = {
		PC = "rbxassetid://00000005",
		Console = "rbxassetid://00000006",
	},
	[Enum.KeyCode.LeftControl] = {
		PC = "rbxassetid://00000007",
		Console = "rbxassetid://00000008",
	},
	[Enum.KeyCode.C] = {
		PC = "rbxassetid://00000009",
	},
	[Enum.KeyCode.E] = {
		PC = "rbxassetid://00000010",
	},
	[Enum.KeyCode.Q] = {
		PC = "rbxassetid://00000011",
	},
	[Enum.KeyCode.F] = {
		PC = "rbxassetid://00000012",
	},
	[Enum.KeyCode.ButtonA] = {
		Console = "rbxassetid://00000013",
	},
	[Enum.KeyCode.ButtonB] = {
		Console = "rbxassetid://00000014",
	},
	[Enum.KeyCode.ButtonX] = {
		Console = "rbxassetid://00000015",
	},
	[Enum.KeyCode.ButtonY] = {
		Console = "rbxassetid://00000016",
	},
	[Enum.KeyCode.ButtonL1] = {
		Console = "rbxassetid://00000017",
	},
	[Enum.KeyCode.ButtonR1] = {
		Console = "rbxassetid://00000018",
	},
	[Enum.KeyCode.ButtonL3] = {
		Console = "rbxassetid://00000019",
	},
	[Enum.KeyCode.ButtonR3] = {
		Console = "rbxassetid://00000020",
	},
}

ActionsIcon.ActionIcons = {
	Sprint = "rbxassetid://00000021",
	Jump = "rbxassetid://00000022",
	Crouch = "rbxassetid://00000023",
	Ability = "rbxassetid://00000024",
	Ultimate = "rbxassetid://00000025",
	Interact = "rbxassetid://00000026",
}

ActionsIcon.SpecialIcons = {
	Awaiting = "rbxassetid://00000027",
	None = "rbxassetid://00000028",
	Unknown = "rbxassetid://00000029",
}

function ActionsIcon.getBindIcon(keyCode: Enum.KeyCode?, deviceType: string): string
	if not keyCode then
		return ActionsIcon.SpecialIcons.None
	end

	local bindData = ActionsIcon.BindIcons[keyCode]
	if not bindData then
		return ActionsIcon.SpecialIcons.Unknown
	end

	if deviceType == "Console" then
		return bindData.Console or bindData.PC or ActionsIcon.SpecialIcons.Unknown
	end

	return bindData.PC or ActionsIcon.SpecialIcons.Unknown
end

function ActionsIcon.getActionIcon(actionName: string): string
	return ActionsIcon.ActionIcons[actionName] or ActionsIcon.SpecialIcons.Unknown
end

function ActionsIcon.getAwaitingIcon(): string
	return ActionsIcon.SpecialIcons.Awaiting
end

function ActionsIcon.getNoneIcon(): string
	return ActionsIcon.SpecialIcons.None
end

function ActionsIcon.getKeyDisplayName(keyCode: Enum.KeyCode?): string
	if not keyCode then
		return "NONE"
	end

	local name = keyCode.Name

	local displayNames = {
		LeftShift = "L-SHIFT",
		RightShift = "R-SHIFT",
		LeftControl = "L-CTRL",
		RightControl = "R-CTRL",
		LeftAlt = "L-ALT",
		RightAlt = "R-ALT",
		Space = "SPACE",
		One = "1",
		Two = "2",
		Three = "3",
		Four = "4",
		Five = "5",
		Six = "6",
		Seven = "7",
		Eight = "8",
		Nine = "9",
		Zero = "0",
		ButtonA = "A",
		ButtonB = "B",
		ButtonX = "X",
		ButtonY = "Y",
		ButtonL1 = "LB",
		ButtonR1 = "RB",
		ButtonL2 = "LT",
		ButtonR2 = "RT",
		ButtonL3 = "LS",
		ButtonR3 = "RS",
	}

	return displayNames[name] or name:upper()
end

return ActionsIcon
