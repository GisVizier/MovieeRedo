local Dialogue = {}

export type DialoguePreset = {
	Character: string,
	SoundInstance: Sound | Instance | string?,
	DialogueText: string?,
	Speaker: boolean?,
	Override: boolean?,
	addWait: number?,
	Dialogue: {DialoguePreset}?,
}

export type DialogueEntry = {
	CharactersNeeded: {string}?,
	Override: boolean?,
	Dialogue: {DialoguePreset}?,
}

Dialogue.DialoguesSoundsPath = "ReplicatedStorage/Assets/Dialogues"

Dialogue.Dialogues = {
	Airborne = {
		Ability = {
			upDraft = {
				Updraft_1 = {
					CharactersNeeded = {"Airborne"},
					Dialogue = {
						{
							Character = "Airborne",
							SoundInstance = nil,
							DialogueText = "I'm up then I'm gone.",
							Speaker = true,
						},
					},
				},
				Updraft_2 = {
					CharactersNeeded = {"Airborne"},
					Dialogue = {
						{
							Character = "Airborne",
							SoundInstance = nil,
							DialogueText = "Air's got me!",
							Speaker = true,
						},
					},
				},
			},
			cloudSkip = {
				Dash_1 = {
					CharactersNeeded = {"Airborne"},
					Dialogue = {
						{
							Character = "Airborne",
							SoundInstance = nil,
							DialogueText = "New angle watch this!",
							Speaker = true,
						},
					},
				},
			},
		},
	},

	Aki = {
		RoundStart = {
			Default = {
				Aki_Start_1 = {
					CharactersNeeded = {"Aki"},
					Dialogue = {
						{
							Character = "Aki",
							SoundInstance = 119619711171777,
							DialogueText = "Just do the job. Then we go home.",
							Speaker = true,
						},
					},
				},
				Aki_Start_2 = {
					CharactersNeeded = {"Aki"},
					Dialogue = {
						{
							Character = "Aki",
							SoundInstance = 133525796453138,
							DialogueText = "If this gets messy... it's not my fault.",
							Speaker = true,
						},
					},
				},
				Aki_Start_3 = {
					CharactersNeeded = {"Aki"},
					Dialogue = {
						{
							Character = "Aki",
							SoundInstance = 125486624351386,
							DialogueText = "Stay sharp. I don't want surprises.",
							Speaker = true,
						},
					},
				},
				Aki_Start_4 = {
					CharactersNeeded = {"Aki"},
					Dialogue = {
						{
							Character = "Aki",
							SoundInstance = 128495599593912,
							DialogueText = "I hate fighting before breakfast.",
							Speaker = true,
						},
					},
				},
				Aki_Start_5 = {
					CharactersNeeded = {"Aki"},
					Dialogue = {
						{
							Character = "Aki",
							SoundInstance = 74754199386203,
							DialogueText = "If I look tired, it's because I am.",
							Speaker = true,
						},
					},
				},
				Aki_Start_6 = {
					CharactersNeeded = {"Aki"},
					Dialogue = {
						{
							Character = "Aki",
							SoundInstance = 71787323235599,
							DialogueText = "I'm calm. That's... new.",
							Speaker = true,
						},
					},
				},
				Aki_Start_7 = {
					CharactersNeeded = {"Aki"},
					Dialogue = {
						{
							Character = "Aki",
							SoundInstance = 99732162500154,
							DialogueText = "If this goes wrong, pretend you don't know me.",
							Speaker = true,
						},
					},
				},
				Aki_Start_8 = {
					CharactersNeeded = {"Aki"},
					Dialogue = {
						{
							Character = "Aki",
							SoundInstance = 85122330176177,
							DialogueText = "I don't have time for this.",
							Speaker = true,
						},
					},
				},
			},
		},
	},

	HonoredOne = {
		Ability = {
			Hit = {
				HonoredOne_Hit_1 = {
					CharactersNeeded = {"HonoredOne"},
					Dialogue = {
						{
							Character = "HonoredOne",
							SoundInstance = 123168642237148,
							DialogueText = "Back off.",
							Speaker = true,
						},
					},
				},
			},
		},
		RoundStart = {
			Default = {
				HonoredOne_Start_1 = {
					CharactersNeeded = {"HonoredOne"},
					Dialogue = {
						{
							Character = "HonoredOne",
							SoundInstance = 103048118780606,
							DialogueText = "Try to keep up. I get bored easily.",
							Speaker = true,
						},
					},
				},
				HonoredOne_Start_2 = {
					CharactersNeeded = {"HonoredOne"},
					Dialogue = {
						{
							Character = "HonoredOne",
							SoundInstance = 91060266677915,
							DialogueText = "Alright—try to keep up.",
							Speaker = true,
						},
					},
				},
				HonoredOne_Start_3 = {
					CharactersNeeded = {"HonoredOne"},
					Dialogue = {
						{
							Character = "HonoredOne",
							SoundInstance = 136033932961158,
							DialogueText = "Relax. I'm here.",
							Speaker = true,
						},
					},
				},
				HonoredOne_Start_4 = {
					CharactersNeeded = {"HonoredOne"},
					Dialogue = {
						{
							Character = "HonoredOne",
							SoundInstance = 127616604766426,
							DialogueText = "If this gets boring, I'll make it interesting.",
							Speaker = true,
						},
					},
				},
				HonoredOne_Start_5 = {
					CharactersNeeded = {"HonoredOne"},
					Dialogue = {
						{
							Character = "HonoredOne",
							SoundInstance = 86587884827335,
							DialogueText = "I could end this instantly… but where's the fun?",
							Speaker = true,
						},
					},
				},
				HonoredOne_Start_6 = {
					CharactersNeeded = {"HonoredOne"},
					Dialogue = {
						{
							Character = "HonoredOne",
							SoundInstance = 105668188260399,
							DialogueText = "Let's make this quick—I have plans.",
							Speaker = true,
						},
					},
				},
				HonoredOne_Start_7 = {
					CharactersNeeded = {"HonoredOne"},
					Dialogue = {
						{
							Character = "HonoredOne",
							SoundInstance = 105706230159715,
							DialogueText = "You ever seen someone lose with style?",
							Speaker = true,
						},
					},
				},
				HonoredOne_Start_8 = {
					CharactersNeeded = {"HonoredOne"},
					Dialogue = {
						{
							Character = "HonoredOne",
							SoundInstance = 121319465678027,
							DialogueText = "If you hear screaming, that's normal. For them.",
							Speaker = true,
						},
					},
				},
			},
		},
	},

	ExampleCharacter = {
		RoundStart = {
			Win = {
				Example_Start_1 = {
					CharactersNeeded = {"ExampleCharacter"},
					Dialogue = {
						{
							Character = "ExampleCharacter",
							SoundInstance = nil,
							DialogueText = "Let's do this!",
							Speaker = true,
						},
					},
				},
			},
			Lose = {
				Example_Lose_1 = {
					CharactersNeeded = {"ExampleCharacter"},
					Override = true,
					Dialogue = {
						{
							Character = "ExampleCharacter",
							SoundInstance = nil,
							DialogueText = "We'll get them next time.",
							Speaker = true,
						},
					},
				},
			},
		},
		RoundFinish = {
			Win = {},
			Lose = {},
		},
	},
}

return Dialogue
