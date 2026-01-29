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
