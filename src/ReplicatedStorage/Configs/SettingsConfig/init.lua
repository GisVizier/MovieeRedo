local ReplicatedFirst = game:GetService("ReplicatedFirst")

local SettingsConfig = {}

export type ActionButtonTemplate = Frame & {
	UIGradient: UIGradient,
	UIScale: UIScale,
	UIStroke: UIStroke,

	HOLDER: Frame & {
		UIListLayout: UIListLayout,
		TextLabel: TextLabel,
	},

	Select: Frame & {
		BottomBar: Frame,
		Glow: Frame & {
			UIGradient: UIGradient,
		},
	},
}

export type KeybindDisplayTemplate = Frame & {
	UIListLayout: UIListLayout,

	Action: Frame & {
		Action: Frame & {
			UIListLayout: UIListLayout,

			CONSOLE: Frame & {
				UICorner: UICorner,
				UIGradient: UIGradient,
				UIPadding: UIPadding,
			},

			PC: Frame & {
				UICorner: UICorner,
				UIGradient: UIGradient,
				UIPadding: UIPadding,
			},

			PC2: Frame & {
				UICorner: UICorner,
				UIGradient: UIGradient,
				UIPadding: UIPadding,
			},
		},
	},

	Info: Frame & {
		UICorner: UICorner,
		UIGradient: UIGradient,
		UIPadding: UIPadding,
		TextLabel: TextLabel,
	},
}

export type ResetTemplate = Frame & {
	UIListLayout: UIListLayout,
	Action: ActionButtonTemplate,
}

export type SettingTemplate = Frame & {
	UIListLayout: UIListLayout,

	Action: Frame & {
		Action: Frame & {
			UIGradient: UIGradient,
			UIScale: UIScale,
			UIStroke: UIStroke,
		},

		BUTTONS: Frame & {
			UIPadding: UIPadding,

			Left: ImageButton & {
				UIScale: UIScale,
			},

			Right: ImageButton & {
				UIScale: UIScale,
			},
		},

		HOLDER: Frame & {
			UIListLayout: UIListLayout,

			Selected: Frame & {
				UIListLayout: UIListLayout,
				Template: ImageButton,
				Template2: ImageButton?,
			},

			TextLabel: TextLabel,
		},

		Select: Frame & {
			BottomBar: Frame,
			Glow: Frame & {
				UIGradient: UIGradient,
			},
		},
	},

	Info: Frame & {
		UIGradient: UIGradient,
		UIPadding: UIPadding,
		TextLabel: TextLabel,
	},
}

export type KeybindTemplate = Frame & {
	UIListLayout: UIListLayout,

	Action: Frame & {
		Action: Frame & {
			UIListLayout: UIListLayout,

			CONSOLE: ImageButton & {
				UICorner: UICorner,
				UIGradient: UIGradient,
				UIPadding: UIPadding,
			},

			PC: ImageButton & {
				UICorner: UICorner,
				UIGradient: UIGradient,
				UIPadding: UIPadding,
			},

			PC2: ImageButton & {
				UICorner: UICorner,
				UIGradient: UIGradient,
				UIPadding: UIPadding,
			},
		},
	},

	Info: Frame & {
		UICorner: UICorner,
		UIGradient: UIGradient,
		UIPadding: UIPadding,
		TextLabel: TextLabel,
	},
}

export type SliderTemplate = Frame & {
	UIListLayout: UIListLayout,

	Action: Frame & {
		UIScale: UIScale,

		BUTTONS: Frame & {
			UIPadding: UIPadding,

			Left: ImageButton & {
				UIScale: UIScale,
			},

			Right: ImageButton & {
				UIScale: UIScale,
			},
		},

		HOLDER: Frame & {
			UIGradient: UIGradient,

			Drag: Frame & {
				UIDragDetector: UIDragDetector,
				UIPadding: UIPadding,
				UIStroke: UIStroke,
				TextLabel: TextLabel,
			},

			Frame: Frame & {
				UIGradient: UIGradient,
			},

			UIGradient2: UIGradient,
		},

		Select: Frame & {
			BottomBar: Frame,
			Glow: Frame & {
				UIGradient: UIGradient,
			},
		},
	},

	Info: Frame & {
		UIGradient: UIGradient,
		UIPadding: UIPadding,
		TextLabel: TextLabel,
	},
}

export type DividerTemplate = Frame & {
	UIListLayout: UIListLayout,
	Action: Frame,
	Info: Frame & {
		UIGradient: UIGradient,
		UIPadding: UIPadding,
		TextLabel: TextLabel,
	},
}

export type SettingOption = {
	Display: string,
	Color: Color3?,
	Image: string?,
	Value: any?,
}

export type SliderConfig = {
	Max: number,
	Min: number,
	Step: number,
	Default: number,
}

export type BindConfig = {
	PC: Enum.KeyCode?,
	PC2: Enum.KeyCode?,
	Console: Enum.KeyCode?,
}

export type DeviceType = "PC" | "Console" | "Mobile"

export type SettingConfig = {
	Name: string,
	Description: string,
	Order: number,
	SettingType: "toggle" | "slider" | "keybind" | "divider" | "Multile" | "action",
	Icon: string?,
	Image: { string }?,
	Video: string?,
	Options: { SettingOption }?,
	Default: number?,
	Slider: SliderConfig?,
	Action: string?,
	ActionLabel: string?,
	Bind: BindConfig?,
	DefaultBind: BindConfig?,
	Platforms: { DeviceType }?,
	BlockedPlatforms: { DeviceType }?,
}

export type SettingsCategory = {
	[string]: SettingConfig,
}

export type CategoryConfig = {
	DisplayName: string,
	Order: number,
	Settings: SettingsCategory,
}

local function buildCrosshairColorOptions()
	return {
		{ Display = "White", Color = Color3.fromRGB(255, 255, 255), Value = "White" },
		{ Display = "Red", Color = Color3.fromRGB(255, 0, 4), Value = "Red" },
		{ Display = "Pink", Color = Color3.fromRGB(255, 24, 213), Value = "Pink" },
		{ Display = "Purple", Color = Color3.fromRGB(121, 25, 255), Value = "Purple" },
		{ Display = "Blue", Color = Color3.fromRGB(16, 72, 255), Value = "Blue" },
		{ Display = "Cyan", Color = Color3.fromRGB(14, 235, 255), Value = "Cyan" },
		{ Display = "Green", Color = Color3.fromRGB(37, 181, 11), Value = "Green" },
		{ Display = "Yellow", Color = Color3.fromRGB(255, 219, 15), Value = "Yellow" },
		{ Display = "Orange", Color = Color3.fromRGB(255, 125, 12), Value = "Orange" },
		{ Display = "Black", Color = Color3.fromRGB(0, 0, 0), Value = "Black" },
	}
end

SettingsConfig.Categories = {
	Gameplay = {
		DisplayName = "Gameplay",
		Order = 1,
		Settings = {
			DividerPerformance = {
				Name = "PERFORMANCE",
				Description = "Performance-focused options that reduce visual load and improve FPS.",
				Order = 1,
				SettingType = "divider",
			},

			DisableShadows = {
				Name = "Disable Shadows",
				Description = "Turns off global lighting shadows and part cast shadows to improve performance.",
				Order = 2,
				SettingType = "toggle",
				Image = { "rbxassetid://79326135346813", "rbxassetid://119385708450116" },
				Options = {
					{ Display = "Enabled", Value = true, Image = "rbxassetid://79326135346813" },
					{ Display = "Disabled", Value = false, Image = "rbxassetid://119385708450116" },
				},
				Default = 2,
			},

			DisableTextures = {
				Name = "Disable Textures",
				Description = "Removes map textures and decals and forces smoother materials for better performance.",
				Order = 3,
				SettingType = "toggle",
				Image = { "rbxassetid://118298540523091", "rbxassetid://97170520694267" },
				Options = {
					{ Display = "Enabled", Value = true, Image = "rbxassetid://100262195669556" },
					{ Display = "Disabled", Value = false, Image = "rbxassetid://103645719222800" },
				},
				Default = 2,
			},

			DisableOthersWraps = {
				Name = "Disable Others Weapon Cosmetics",
				Description = "Hides other players' weapon cosmetics and cosmetic effects to reduce visual clutter.",
				Order = 4,
				SettingType = "toggle",
				BlockedPlatforms = { "PC", "Mobile", "Console" },
				Image = { "rbxassetid://108799503900149" },
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			HideMuzzleFlash = {
				Name = "Hide Muzzle Flash",
				Description = "Disables muzzle flash visuals so firing produces less bright visual effects.",
				Order = 5,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true, Image = "rbxassetid://92723398731557" },
					{ Display = "Disabled", Value = false, Image = "rbxassetid://131413727437208" },
				},
				Default = 2,
			},

			WeaponInking = {
				Name = "Weapon Inking",
				Description = "Sets the highlight style used on your active first-person weapon model.",
				Order = 6,
				SettingType = "Multile",
				Options = {
					{ Display = "Hide", Value = "Hide" },
					{ Display = "Outline", Value = "Outline" },
					{ Display = "Fill", Value = "Fill" },
					{ Display = "Fill And Outline", Value = "FillAndOutline" },
				},
				Default = 4,
			},

			DividerDisplay = {
				Name = "DISPLAY",
				Description = "Display and camera options that affect UI scale, visibility, and camera feel.",
				Order = 10,
				SettingType = "divider",
			},

			DisplayArea = {
				Name = "HUD Size",
				Description = "Scales HUD/UI size up or down across supported on-screen interface elements.",
				Order = 11,
				SettingType = "slider",
				Slider = {
					Max = 150,
					Min = 50,
					Step = 1,
					Default = 100,
				},
			},

			Brightness = {
				Name = "Brightness",
				Description = "Chooses a brightness preset for your client, with an optional bloom-enhanced mode.",
				Order = 12,
				SettingType = "Multile",
				Options = {
					{ Display = "Darker", Value = "Darker" },
					{ Display = "Dark", Value = "Dark" },
					{ Display = "Default", Value = "Default" },
					{ Display = "Bright", Value = "Bright" },
					{ Display = "Bright + Bloom", Value = "BrightBloom" },
				},
				Default = 3,
			},

			FieldOfView = {
				Name = "Field Of View",
				Description = "Sets your base gameplay camera FOV.",
				Order = 13,

				Image = { "rbxassetid://131531757988844" },
				SettingType = "slider",
				Slider = {
					Max = 120,
					Min = 30,
					Step = 1,
					Default = 70,
				},
			},

			FOVZoomStrength = {
				Name = "FOV Zoom Strength",
				Description = "Controls how strong ADS zoom feels, from no zoom to full default zoom.",
				Order = 14,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 100,
				},
			},

			FieldOfViewEffects = {
				Name = "Field Of View Effects",
				Description = "Enables or disables dynamic FOV effects from movement, actions, and gameplay states.",
				Order = 15,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			ScreenShake = {
				Name = "Screen Shake",
				Description = "Adjusts camera shake intensity from fully off (0) up to maximum shake (3).",
				Order = 16,
				SettingType = "slider",
				Slider = {
					Max = 3,
					Min = 0,
					Step = 1,
					Default = 1,
				},
			},

			HideHud = {
				Name = "Disable HUD",
				Description = "Hides most HUD modules and shows the UnHide prompt so you can restore HUD quickly.",
				Order = 17,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true, Image = "rbxassetid://136898318593158" },
					{ Display = "Disabled", Value = false, Image = "rbxassetid://133332591837085" },
				},
				Default = 2,
			},

			DividerTeamVisuals = {
				Name = "TEAM VISUALS",
				Description = "Team and enemy colors plus inking visuals.",
				Order = 17.1,
				SettingType = "divider",
			},

			TeamColor = {
				Name = "Team Color",
				Description = "Sets teammate accent color for map/UI and teammate inking.",
				Order = 17.2,
				SettingType = "Multile",
				Options = {
					{ Display = "Blue", Color = Color3.fromRGB(16, 72, 255), Value = "Blue" },
					{ Display = "Cyan", Color = Color3.fromRGB(14, 235, 255), Value = "Cyan" },
					{ Display = "Green", Color = Color3.fromRGB(37, 181, 11), Value = "Green" },
					{ Display = "Yellow", Color = Color3.fromRGB(255, 219, 15), Value = "Yellow" },
				},
				Default = 1,
			},

			TeamInking = {
				Name = "Teammate Inking",
				Description = "Highlight style for teammates in match.",
				Order = 17.3,
				SettingType = "Multile",
				Options = {
					{ Display = "Hide", Value = "Hide" },
					{ Display = "Outline", Value = "Outline" },
					{ Display = "Fill", Value = "Fill" },
					{ Display = "Fill And Outline", Value = "FillAndOutline" },
				},
				Default = 4,
			},

			TeamInkTransparency = {
				Name = "Teammate Ink Opacity",
				Description = "Opacity intensity for teammate inking.",
				Order = 17.4,
				SettingType = "Multile",
				Options = {
					{ Display = "Low", Value = 0.5 },
					{ Display = "Default", Value = 1 },
					{ Display = "High", Value = 2 },
					{ Display = "Max", Value = 4 },
				},
				Default = 2,
			},

			TeamSeeThroughWalls = {
				Name = "Teammates Through Walls",
				Description = "Allows teammate inking to render through walls.",
				Order = 17.5,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			EnemyColor = {
				Name = "Enemy Color",
				Description = "Sets enemy accent color for map/UI and enemy inking.",
				Order = 17.6,
				SettingType = "Multile",
				Options = {
					{ Display = "Red", Color = Color3.fromRGB(255, 0, 4), Value = "Red" },
					{ Display = "Orange", Color = Color3.fromRGB(255, 125, 12), Value = "Orange" },
					{ Display = "Pink", Color = Color3.fromRGB(255, 24, 213), Value = "Pink" },
					{ Display = "Purple", Color = Color3.fromRGB(121, 25, 255), Value = "Purple" },
				},
				Default = 1,
			},

			EnemyInking = {
				Name = "Enemy Inking",
				Description = "Highlight style for enemies in match.",
				Order = 17.7,
				SettingType = "Multile",
				Options = {
					{ Display = "Hide", Value = "Hide" },
					{ Display = "Outline", Value = "Outline" },
					{ Display = "Fill", Value = "Fill" },
					{ Display = "Fill And Outline", Value = "FillAndOutline" },
				},
				Default = 4,
			},

			EnemyInkTransparency = {
				Name = "Enemy Ink Opacity",
				Description = "Opacity intensity for enemy inking.",
				Order = 17.8,
				SettingType = "Multile",
				Options = {
					{ Display = "Low", Value = 0.5 },
					{ Display = "Default", Value = 1 },
					{ Display = "High", Value = 2 },
					{ Display = "Max", Value = 4 },
				},
				Default = 2,
			},

			DividerGameplay = {
				Name = "GAMEPLAY",
				Description = "Gameplay readability and team presentation options.",
				Order = 18,
				SettingType = "divider",
			},

			DamageNumbers = {
				Name = "Damage Numbers",
				Description = "Choose how hit damage numbers are shown: Disabled, Add, or Stack.",
				Order = 19,
				SettingType = "Multile",
				Options = {
					{ Display = "Disabled", Value = "Disabled" },
					{ Display = "Add", Value = "Add" },
					{ Display = "Stack", Value = "Stacked" },
				},
				Default = 2,
			},

			DisableEffects = {
				Name = "Disable Effects",
				Description = "Reduces non-essential VFX to keep gameplay visuals cleaner.",
				Order = 20,
				SettingType = "toggle",
				BlockedPlatforms = { "PC", "Mobile", "Console" },
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			HideTeammateDisplay = {
				Name = "Hide Teammate Display",
				Description = "Hides teammate overhead display elements for less screen clutter.",
				Order = 21,
				SettingType = "toggle",
				BlockedPlatforms = { "PC", "Mobile", "Console" },
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			DividerSensitivity = {
				Name = "Sensitivity",
				Description = "Sensitivity and camera feel settings.",
				Order = 23.1,
				SettingType = "divider",
			},

			OverallSensitivity = {
				Name = "Sensitivity",
				Description = "Overall baseline sensitivity.",
				Order = 23.2,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 50,
				},
			},

			ControllerSensitivity = {
				Name = "Controler",
				Description = "Controller look sensitivity.",
				Order = 23.3,
				SettingType = "slider",
				BlockedPlatforms = { "PC", "Mobile" },
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 50,
				},
			},

			MobileSensitivity = {
				Name = "Mobile",
				Description = "Mobile touch look sensitivity.",
				Order = 23.4,
				SettingType = "slider",
				BlockedPlatforms = { "PC", "Console" },
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 50,
				},
			},

			ADSSensitivity = {
				Name = "Aiming Sensitivity",
				Description = "Sensitivity while aiming.",
				Order = 23.45,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 75,
				},
			},

			SensX = {
				Name = "Horizontal",
				Description = "Horizontal look sensitivity.",
				Order = 23.5,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 50,
				},
			},

			SensY = {
				Name = "Veritcal",
				Description = "Vertical look sensitivity.",
				Order = 23.6,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 50,
				},
			},

			CameraSmoothing = {
				Name = "Smoothing",
				Description = "Smooths camera movement/response.",
				Order = 23.7,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 0,
				},
			},

			InvertY = {
				Name = "Inverted Y",
				Description = "Inverts vertical look input.",
				Order = 23.8,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			InvertX = {
				Name = "Inverted X",
				Description = "Inverts horizontal look input.",
				Order = 23.9,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			DividerMovemnt = {
				Name = "MOVEMNT",
				Description = "Movement and traversal helper options.",
				Order = 18.1,
				SettingType = "divider",
			},

			ToggleCrouch = {
				Name = "Toggle Crouch",
				Description = "Press crouch once to toggle crouch on or off.",
				Order = 18.2,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			ToggleSprint = {
				Name = "Toggle Sprint",
				Description = "Press sprint once to toggle sprint on or off.",
				Order = 18.3,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			AutoSprint = {
				Name = "Auto Sprint",
				Description = "Automatically sprints while moving when allowed.",
				Order = 18.4,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			AutoSlide = {
				Name = "Auto Slide",
				Description = "Triggers sliding behavior while sprinting and crouching.",
				Order = 18.5,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			WallJumpAssist = {
				Name = "Easy Wall Jump",
				Description = "Adds assist behavior for wall jumping.",
				Order = 18.6,
				SettingType = "toggle",
				BlockedPlatforms = { "PC", "Mobile", "Console" },
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			DividerCombat = {
				Name = "COMBAT",
				Description = "Combat control helpers.",
				Order = 30,
				SettingType = "divider",
			},

			ToggleAim = {
				Name = "Toggle Aim",
				Description = "Press aim once to ADS in and again to ADS out.",
				Order = 31,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			EasyCycle = {
				Name = "Easy Cycle",
				Description = "Use scroll wheel to cycle available weapons.",
				Order = 32,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			AimAssist = {
				Name = "Aim Assist",
				Description = "Aim assist toggle (kept disabled by default for now).",
				Order = 33,
				SettingType = "toggle",
				BlockedPlatforms = { "PC", "Mobile", "Console" },
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			AimAssistStrength = {
				Name = "Aim Assist Strength",
				Description = "Aim assist strength level.",
				Order = 34,
				SettingType = "slider",
				BlockedPlatforms = { "PC", "Mobile", "Console" },
				Slider = {
					Max = 5,
					Min = 1,
					Step = 1,
					Default = 3,
				},
			},

			AutoShoot = {
				Name = "Auto Shoot",
				Description = "Automatically fires when valid target conditions are met.",
				Order = 35,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			DividerAbility = {
				Name = "ABILITY",
				Description = "Ability helper controls.",
				Order = 40,
				SettingType = "divider",
			},

			EasyAbility = {
				Name = "Easy Ability",
				Description = "Ability helper mode (disabled for now).",
				Order = 41,
				SettingType = "toggle",
				BlockedPlatforms = { "PC", "Mobile", "Console" },
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			DividerMobileLayout = {
				Name = "MOBILE LAYOUT",
				Description = "Arrange and reset mobile button positions and sizes.",
				Order = 98,
				SettingType = "divider",
			},

			ArrangeMobileButtons = {
				Name = "Arrange Mobile Buttons",
				Description = "Enter mobile button arrangement mode to move and resize controls.",
				Order = 99,
				SettingType = "toggle",
				BlockedPlatforms = { "PC", "Console" },
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			ResetMobileButtons = {
				Name = "Reset Mobile Buttons",
				Description = "Reset all mobile button positions and sizes to default.",
				Order = 100,
				SettingType = "action",
				BlockedPlatforms = { "PC", "Console" },
				ActionLabel = "RESET",
			},
		},
	},

	Audio = {
		DisplayName = "Audio",
		Order = 4,
		Settings = {
			DividerMix = {
				Name = "MIX",
				Description = "Global mix levels for game audio groups.",
				Order = 1,
				SettingType = "divider",
			},

			MasterVolume = {
				Name = "Master Volume",
				Description = "Controls total game output volume.",
				Order = 2,
				SettingType = "slider",
				Slider = {
					Max = 200,
					Min = 0,
					Step = 5,
					Default = 100,
				},
			},

			SFXVolume = {
				Name = "SFX Volume",
				Description = "Controls sound effects volume.",
				Order = 3,
				SettingType = "slider",
				Slider = {
					Max = 200,
					Min = 0,
					Step = 5,
					Default = 100,
				},
			},

			MusicVolume = {
				Name = "Music Volume",
				Description = "Controls music and ambience volume.",
				Order = 4,
				SettingType = "slider",
				Slider = {
					Max = 200,
					Min = 0,
					Step = 5,
					Default = 40,
				},
			},

			PlayerSounds = {
				Name = "Player Sounds",
				Description = "Controls emote, movement, and gun audio volume.",
				Order = 5,
				SettingType = "slider",
				Slider = {
					Max = 200,
					Min = 0,
					Step = 5,
					Default = 100,
				},
			},

			DividerDialogue = {
				Name = "DIALOGUE",
				Description = "Dialogue subtitle and voice behavior.",
				Order = 10,
				SettingType = "divider",
			},

			DialogueMode = {
				Name = "Dialogue",
				Description = "Choose whether dialogue uses subtitles, voice, or both.",
				Order = 11,
				SettingType = "Multile",
				Options = {
					{ Display = "Disabled", Value = "Disabled" },
					{ Display = "Subtitles + Voice", Value = "SubtitlesVoice" },
					{ Display = "Subtitles", Value = "Subtitles" },
					{ Display = "Voice", Value = "Voice" },
				},
				Default = 2,
			},

			AudioOcclusion = {
				Name = "Audio Occlusion",
				Description = "Enables indoor echo and obstruction processing for sounds.",
				Order = 12,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},
		},
	},

	Controls = {
		DisplayName = "Controls",
		Order = 2,
		Settings = {
			DividerMovement = {
				Name = "MOVEMENT",
				Description = "Movement input bindings.",
				Order = 1,
				SettingType = "divider",
			},

			MoveForward = {
				Name = "Walk Forward",
				Description = "Keybind for moving forward.",
				Order = 2,
				SettingType = "keybind",
				Action = "MoveForward",
				Bind = {
					PC = Enum.KeyCode.W,
					PC2 = nil,
					Console = nil,
				},
				DefaultBind = {
					PC = Enum.KeyCode.W,
					PC2 = nil,
					Console = nil,
				},
			},

			MoveBackward = {
				Name = "Walk Back",
				Description = "Keybind for moving backward.",
				Order = 3,
				SettingType = "keybind",
				Action = "MoveBackward",
				Bind = {
					PC = Enum.KeyCode.S,
					PC2 = nil,
					Console = nil,
				},
				DefaultBind = {
					PC = Enum.KeyCode.S,
					PC2 = nil,
					Console = nil,
				},
			},

			MoveLeft = {
				Name = "Walk Left",
				Description = "Keybind for moving left.",
				Order = 4,
				SettingType = "keybind",
				Action = "MoveLeft",
				Bind = {
					PC = Enum.KeyCode.A,
					PC2 = nil,
					Console = nil,
				},
				DefaultBind = {
					PC = Enum.KeyCode.A,
					PC2 = nil,
					Console = nil,
				},
			},

			MoveRight = {
				Name = "Walk Right",
				Description = "Keybind for moving right.",
				Order = 5,
				SettingType = "keybind",
				Action = "MoveRight",
				Bind = {
					PC = Enum.KeyCode.D,
					PC2 = nil,
					Console = nil,
				},
				DefaultBind = {
					PC = Enum.KeyCode.D,
					PC2 = nil,
					Console = nil,
				},
			},

			Jump = {
				Name = "Jump",
				Description = "Keybind for jumping and movement tech actions.",
				Order = 6,
				SettingType = "keybind",
				Action = "Jump",
				Bind = {
					PC = Enum.KeyCode.Space,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonA,
				},
				DefaultBind = {
					PC = Enum.KeyCode.Space,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonA,
				},
			},

			Slide = {
				Name = "Slide",
				Description = "Keybind for sliding.",
				Order = 7,
				SettingType = "keybind",
				Action = "Slide",
				Bind = {
					PC = Enum.KeyCode.V,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonR3,
				},
				DefaultBind = {
					PC = Enum.KeyCode.V,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonR3,
				},
			},

			Sprint = {
				Name = "Sprint",
				Description = "Keybind for sprinting to move faster while active.",
				Order = 8,
				SettingType = "keybind",
				Action = "Sprint",
				Bind = {
					PC = Enum.KeyCode.LeftShift,
					PC2 = Enum.KeyCode.RightShift,
					Console = Enum.KeyCode.ButtonL3,
				},
				DefaultBind = {
					PC = Enum.KeyCode.LeftShift,
					PC2 = Enum.KeyCode.RightShift,
					Console = Enum.KeyCode.ButtonL3,
				},
			},

			Crouch = {
				Name = "Crouch",
				Description = "Keybind for crouching to lower profile and movement noise.",
				Order = 9,
				SettingType = "keybind",
				Action = "Crouch",
				Bind = {
					PC = Enum.KeyCode.LeftControl,
					PC2 = Enum.KeyCode.C,
					Console = Enum.KeyCode.ButtonB,
				},
				DefaultBind = {
					PC = Enum.KeyCode.LeftControl,
					PC2 = Enum.KeyCode.C,
					Console = Enum.KeyCode.ButtonB,
				},
			},

			DividerCombat = {
				Name = "COMBAT",
				Description = "Combat input bindings.",
				Order = 20,
				SettingType = "divider",
			},

			Fire = {
				Name = "Fire / Attack",
				Description = "Keybind for firing your weapon.",
				Order = 21,
				SettingType = "keybind",
				Action = "Fire",
				Bind = {
					PC = Enum.UserInputType.MouseButton1,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonR2,
				},
				DefaultBind = {
					PC = Enum.UserInputType.MouseButton1,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonR2,
				},
			},

			Special = {
				Name = "ADS / Special",
				Description = "Keybind for aiming down sights and special input.",
				Order = 22,
				SettingType = "keybind",
				Action = "Special",
				Bind = {
					PC = Enum.UserInputType.MouseButton2,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonL2,
				},
				DefaultBind = {
					PC = Enum.UserInputType.MouseButton2,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonL2,
				},
			},

			Reload = {
				Name = "Reload",
				Description = "Keybind for reloading your weapon.",
				Order = 23,
				SettingType = "keybind",
				Action = "Reload",
				Bind = {
					PC = Enum.KeyCode.R,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonX,
				},
				DefaultBind = {
					PC = Enum.KeyCode.R,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonX,
				},
			},

			QuickMelee = {
				Name = "Quick Melee",
				Description = "Keybind for quick melee attacks.",
				Order = 24,
				SettingType = "keybind",
				Action = "QuickMelee",
				Bind = {
					PC = Enum.KeyCode.F,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonY,
				},
				DefaultBind = {
					PC = Enum.KeyCode.F,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonY,
				},
			},

			Inspect = {
				Name = "Inspect Weapon",
				Description = "Keybind for weapon inspect.",
				Order = 25,
				SettingType = "keybind",
				Action = "Inspect",
				Bind = {
					PC = Enum.KeyCode.T,
					PC2 = nil,
					Console = nil,
				},
				DefaultBind = {
					PC = Enum.KeyCode.T,
					PC2 = nil,
					Console = nil,
				},
			},

			Ability = {
				Name = "Use Ability",
				Description = "Keybind for your kit's primary ability.",
				Order = 26,
				SettingType = "keybind",
				Action = "Ability",
				Bind = {
					PC = Enum.KeyCode.E,
					PC2 = nil,
					Console = Enum.KeyCode.DPadRight,
				},
				DefaultBind = {
					PC = Enum.KeyCode.E,
					PC2 = nil,
					Console = Enum.KeyCode.DPadRight,
				},
			},

			Ultimate = {
				Name = "Use Ultimate",
				Description = "Keybind for activating your ultimate ability.",
				Order = 27,
				SettingType = "keybind",
				Action = "Ultimate",
				Bind = {
					PC = Enum.KeyCode.Q,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonY,
				},
				DefaultBind = {
					PC = Enum.KeyCode.Q,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonY,
				},
			},

			Interact = {
				Name = "Interact",
				Description = "Keybind for interacting with world objects and pickups.",
				Order = 28,
				SettingType = "keybind",
				Action = "Interact",
				Bind = {
					PC = Enum.KeyCode.F,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonX,
				},
				DefaultBind = {
					PC = Enum.KeyCode.F,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonX,
				},
			},

			DividerWeapons = {
				Name = "WEAPONS",
				Description = "Weapon slot and cycling bindings.",
				Order = 40,
				SettingType = "divider",
			},

			EquipPrimary = {
				Name = "Equip Primary",
				Description = "Keybind for equipping your primary weapon slot.",
				Order = 41,
				SettingType = "keybind",
				Action = "EquipPrimary",
				Bind = {
					PC = Enum.KeyCode.One,
					PC2 = nil,
					Console = nil,
				},
				DefaultBind = {
					PC = Enum.KeyCode.One,
					PC2 = nil,
					Console = nil,
				},
			},

			EquipSecondary = {
				Name = "Equip Secondary",
				Description = "Keybind for equipping your secondary weapon slot.",
				Order = 42,
				SettingType = "keybind",
				Action = "EquipSecondary",
				Bind = {
					PC = Enum.KeyCode.Two,
					PC2 = nil,
					Console = nil,
				},
				DefaultBind = {
					PC = Enum.KeyCode.Two,
					PC2 = nil,
					Console = nil,
				},
			},

			EquipMelee = {
				Name = "Equip Melee",
				Description = "Keybind for equipping your melee weapon slot.",
				Order = 43,
				SettingType = "keybind",
				Action = "EquipMelee",
				Bind = {
					PC = Enum.KeyCode.Three,
					PC2 = nil,
					Console = nil,
				},
				DefaultBind = {
					PC = Enum.KeyCode.Three,
					PC2 = nil,
					Console = nil,
				},
			},

			CycleWeaponLeft = {
				Name = "Cycle Weapon Left",
				Description = "Keybind for cycling to the previous available weapon.",
				Order = 44,
				SettingType = "keybind",
				Action = "CycleWeaponLeft",
				Bind = {
					PC = nil,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonL1,
				},
				DefaultBind = {
					PC = nil,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonL1,
				},
			},

			CycleWeaponRight = {
				Name = "Cycle Weapon Right",
				Description = "Keybind for cycling to the next available weapon.",
				Order = 45,
				SettingType = "keybind",
				Action = "CycleWeaponRight",
				Bind = {
					PC = nil,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonR1,
				},
				DefaultBind = {
					PC = nil,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonR1,
				},
			},

			DividerSocial = {
				Name = "SOCIAL",
				Description = "Social and wheel controls.",
				Order = 60,
				SettingType = "divider",
			},

			Emotes = {
				Name = "Emote Wheel",
				Description = "Keybind for opening the emote wheel.",
				Order = 61,
				SettingType = "keybind",
				Action = "Emotes",
				Bind = {
					PC = Enum.KeyCode.B,
					PC2 = nil,
					Console = Enum.KeyCode.DPadDown,
				},
				DefaultBind = {
					PC = Enum.KeyCode.B,
					PC2 = nil,
					Console = Enum.KeyCode.DPadDown,
				},
			},

			EmoteWheelMode = {
				Name = "Emote Wheel Mode",
				Description = "Chooses whether emote wheel input is hold-to-open or toggle-on/toggle-off.",
				Order = 62,
				SettingType = "toggle",
				Options = {
					{ Display = "Hold", Value = "Hold" },
					{ Display = "Toggle", Value = "Toggle" },
				},
				Default = 1,
			},
		},
	},

	Crosshair = {
		DisplayName = "Crosshair",
		Order = 3,
		Settings = {
			DividerPreset = {
				Name = "PRESET",
				Description = "Override behavior and visibility controls.",
				Order = 1,
				SettingType = "divider",
			},

			CrosshairDisabled = {
				Name = "Crosshair Disabled",
				Description = "Hides your crosshair when enabled.",
				Order = 2,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			ForceDefaultCrosshair = {
				Name = "Force Default Crosshair",
				Description = "Always use your customized default crosshair instead of weapon-specific presets.",
				Order = 3,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			DisableSlideRotation = {
				Name = "Disable Slide Rotation",
				Description = "Disables crosshair rotation while sliding.",
				Order = 4,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			AdvancedStyleSettings = {
				Name = "Advanced Style Settings",
				Description = "Enable per-part style controls for top, bottom, left, right, and dot.",
				Order = 5,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			DividerVisibility = {
				Name = "VISIBILITY",
				Description = "Turn each crosshair part on or off.",
				Order = 10,
				SettingType = "divider",
			},

			ShowTopLine = {
				Name = "Show Top Line",
				Description = "Toggles the top line.",
				Order = 11,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			ShowBottomLine = {
				Name = "Show Bottom Line",
				Description = "Toggles the bottom line.",
				Order = 12,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			ShowLeftLine = {
				Name = "Show Left Line",
				Description = "Toggles the left line.",
				Order = 13,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			ShowRightLine = {
				Name = "Show Right Line",
				Description = "Toggles the right line.",
				Order = 14,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			ShowDot = {
				Name = "Show Dot",
				Description = "Toggles the center dot.",
				Order = 15,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			DividerBase = {
				Name = "BASE",
				Description = "Core crosshair size, spacing, and rotation.",
				Order = 20,
				SettingType = "divider",
			},

			CrosshairColor = {
				Name = "Crosshair Color",
				Description = "Sets the color preset used by your crosshair.",
				Order = 21,
				SettingType = "Multile",
				Image = {
					"rbxassetid://79026012675606",
					"rbxassetid://103662115936011",
					"rbxassetid://77724131858624",
				},
				Options = buildCrosshairColorOptions(),
				Default = 1,
			},

			CrosshairSize = {
				Name = "Crosshair Size",
				Description = "Adjusts overall crosshair scale.",
				Order = 22,
				SettingType = "slider",
				Slider = {
					Max = 200,
					Min = 50,
					Step = 10,
					Default = 100,
				},
			},

			CrosshairOpacity = {
				Name = "Crosshair Opacity",
				Description = "Adjusts crosshair visibility by changing opacity.",
				Order = 23,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 10,
					Step = 5,
					Default = 100,
				},
			},

			CrosshairGap = {
				Name = "Crosshair Gap",
				Description = "Adjusts the center spacing between crosshair lines.",
				Order = 24,
				SettingType = "slider",
				Slider = {
					Max = 50,
					Min = 0,
					Step = 1,
					Default = 10,
				},
			},

			CrosshairThickness = {
				Name = "Crosshair Thickness",
				Description = "Adjusts how thick each crosshair line is.",
				Order = 25,
				SettingType = "slider",
				Slider = {
					Max = 10,
					Min = 1,
					Step = 1,
					Default = 2,
				},
			},

			CrosshairLineLength = {
				Name = "Crosshair Line Length",
				Description = "Adjusts line length.",
				Order = 26,
				SettingType = "slider",
				Slider = {
					Max = 40,
					Min = 2,
					Step = 1,
					Default = 10,
				},
			},

			CrosshairRoundness = {
				Name = "Crosshair Roundness",
				Description = "Adjusts global line and dot corner roundness.",
				Order = 27,
				SettingType = "slider",
				Slider = {
					Max = 20,
					Min = 0,
					Step = 1,
					Default = 0,
				},
			},

			GlobalRotation = {
				Name = "Global Rotation",
				Description = "Rotates the entire crosshair.",
				Order = 28,
				SettingType = "slider",
				Slider = {
					Max = 180,
					Min = -180,
					Step = 1,
					Default = 0,
				},
			},

			DotSize = {
				Name = "Dot Size",
				Description = "Adjusts center dot size.",
				Order = 29,
				SettingType = "slider",
				Slider = {
					Max = 20,
					Min = 1,
					Step = 1,
					Default = 3,
				},
			},

			DividerOutline = {
				Name = "OUTLINE",
				Description = "Outline style controls.",
				Order = 30,
				SettingType = "divider",
			},

			OutlineColor = {
				Name = "Outline Color",
				Description = "Sets outline color for lines and dot.",
				Order = 31,
				SettingType = "Multile",
				Options = {
					{ Display = "Black", Color = Color3.fromRGB(0, 0, 0), Value = "Black" },
					{ Display = "White", Color = Color3.fromRGB(255, 255, 255), Value = "White" },
					{ Display = "Red", Color = Color3.fromRGB(255, 0, 4), Value = "Red" },
					{ Display = "Blue", Color = Color3.fromRGB(16, 72, 255), Value = "Blue" },
					{ Display = "Green", Color = Color3.fromRGB(37, 181, 11), Value = "Green" },
				},
				Default = 1,
			},

			OutlineThickness = {
				Name = "Outline Thickness",
				Description = "Adjusts outline thickness.",
				Order = 32,
				SettingType = "slider",
				Slider = {
					Max = 6,
					Min = 0,
					Step = 1,
					Default = 0,
				},
			},

			OutlineOpacity = {
				Name = "Outline Opacity",
				Description = "Adjusts outline opacity.",
				Order = 33,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 100,
				},
			},

			DividerSpread = {
				Name = "SPREAD",
				Description = "Dynamic spread behavior multipliers.",
				Order = 40,
				SettingType = "divider",
			},

			DynamicSpreadEnabled = {
				Name = "Dynamic Spread",
				Description = "Enable movement and recoil spread animation.",
				Order = 41,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			MovementSpreadMultiplier = {
				Name = "Movement Spread Multiplier",
				Description = "Scales movement-based spread.",
				Order = 42,
				SettingType = "slider",
				Slider = { Min = 0, Max = 5, Step = 0.1, Default = 1 },
			},

			SprintSpreadMultiplier = {
				Name = "Sprint Spread Multiplier",
				Description = "Scales sprint spread.",
				Order = 43,
				SettingType = "slider",
				Slider = { Min = 0, Max = 5, Step = 0.1, Default = 1 },
			},

			AirSpreadMultiplier = {
				Name = "Air Spread Multiplier",
				Description = "Scales airborne spread.",
				Order = 44,
				SettingType = "slider",
				Slider = { Min = 0, Max = 5, Step = 0.1, Default = 1 },
			},

			CrouchSpreadMultiplier = {
				Name = "Crouch Spread Multiplier",
				Description = "Scales crouch spread.",
				Order = 45,
				SettingType = "slider",
				Slider = { Min = 0, Max = 5, Step = 0.1, Default = 1 },
			},

			RecoilSpreadMultiplier = {
				Name = "Recoil Spread Multiplier",
				Description = "Scales recoil expansion on fire.",
				Order = 46,
				SettingType = "slider",
				Slider = { Min = 0, Max = 5, Step = 0.1, Default = 1 },
			},

			DividerAdvanced = {
				Name = "ADVANCED PART STYLE",
				Description = "Per-part style controls (used when Advanced Style Settings is enabled).",
				Order = 50,
				SettingType = "divider",
			},

			DividerAdvancedTop = {
				Name = "TOP LINE",
				Description = "Advanced style for top line.",
				Order = 51,
				SettingType = "divider",
			},
			TopLineColor = { Name = "Top Line Color", Description = "Top line color.", Order = 52, SettingType = "Multile", Options = buildCrosshairColorOptions(), Default = 1 },
			TopLineOpacity = { Name = "Top Line Opacity", Description = "Top line opacity.", Order = 53, SettingType = "slider", Slider = { Min = 0, Max = 100, Step = 1, Default = 100 } },
			TopLineThickness = { Name = "Top Line Thickness", Description = "Top line thickness.", Order = 54, SettingType = "slider", Slider = { Min = 1, Max = 12, Step = 1, Default = 2 } },
			TopLineLength = { Name = "Top Line Length", Description = "Top line length.", Order = 55, SettingType = "slider", Slider = { Min = 2, Max = 40, Step = 1, Default = 10 } },
			TopLineRoundness = { Name = "Top Line Roundness", Description = "Top line roundness.", Order = 56, SettingType = "slider", Slider = { Min = 0, Max = 20, Step = 1, Default = 0 } },
			TopLineRotation = { Name = "Top Line Rotation", Description = "Top line rotation.", Order = 57, SettingType = "slider", Slider = { Min = -180, Max = 180, Step = 1, Default = 0 } },
			TopLineGap = { Name = "Top Line Gap", Description = "Top line extra gap.", Order = 58, SettingType = "slider", Slider = { Min = -50, Max = 50, Step = 1, Default = 10 } },

			DividerAdvancedBottom = {
				Name = "BOTTOM LINE",
				Description = "Advanced style for bottom line.",
				Order = 59,
				SettingType = "divider",
			},
			BottomLineColor = { Name = "Bottom Line Color", Description = "Bottom line color.", Order = 60, SettingType = "Multile", Options = buildCrosshairColorOptions(), Default = 1 },
			BottomLineOpacity = { Name = "Bottom Line Opacity", Description = "Bottom line opacity.", Order = 61, SettingType = "slider", Slider = { Min = 0, Max = 100, Step = 1, Default = 100 } },
			BottomLineThickness = { Name = "Bottom Line Thickness", Description = "Bottom line thickness.", Order = 62, SettingType = "slider", Slider = { Min = 1, Max = 12, Step = 1, Default = 2 } },
			BottomLineLength = { Name = "Bottom Line Length", Description = "Bottom line length.", Order = 63, SettingType = "slider", Slider = { Min = 2, Max = 40, Step = 1, Default = 10 } },
			BottomLineRoundness = { Name = "Bottom Line Roundness", Description = "Bottom line roundness.", Order = 64, SettingType = "slider", Slider = { Min = 0, Max = 20, Step = 1, Default = 0 } },
			BottomLineRotation = { Name = "Bottom Line Rotation", Description = "Bottom line rotation.", Order = 65, SettingType = "slider", Slider = { Min = -180, Max = 180, Step = 1, Default = 0 } },
			BottomLineGap = { Name = "Bottom Line Gap", Description = "Bottom line extra gap.", Order = 66, SettingType = "slider", Slider = { Min = -50, Max = 50, Step = 1, Default = 10 } },

			DividerAdvancedLeft = {
				Name = "LEFT LINE",
				Description = "Advanced style for left line.",
				Order = 67,
				SettingType = "divider",
			},
			LeftLineColor = { Name = "Left Line Color", Description = "Left line color.", Order = 68, SettingType = "Multile", Options = buildCrosshairColorOptions(), Default = 1 },
			LeftLineOpacity = { Name = "Left Line Opacity", Description = "Left line opacity.", Order = 69, SettingType = "slider", Slider = { Min = 0, Max = 100, Step = 1, Default = 100 } },
			LeftLineThickness = { Name = "Left Line Thickness", Description = "Left line thickness.", Order = 70, SettingType = "slider", Slider = { Min = 1, Max = 12, Step = 1, Default = 2 } },
			LeftLineLength = { Name = "Left Line Length", Description = "Left line length.", Order = 71, SettingType = "slider", Slider = { Min = 2, Max = 40, Step = 1, Default = 10 } },
			LeftLineRoundness = { Name = "Left Line Roundness", Description = "Left line roundness.", Order = 72, SettingType = "slider", Slider = { Min = 0, Max = 20, Step = 1, Default = 0 } },
			LeftLineRotation = { Name = "Left Line Rotation", Description = "Left line rotation.", Order = 73, SettingType = "slider", Slider = { Min = -180, Max = 180, Step = 1, Default = 0 } },
			LeftLineGap = { Name = "Left Line Gap", Description = "Left line extra gap.", Order = 74, SettingType = "slider", Slider = { Min = -50, Max = 50, Step = 1, Default = 10 } },

			DividerAdvancedRight = {
				Name = "RIGHT LINE",
				Description = "Advanced style for right line.",
				Order = 75,
				SettingType = "divider",
			},
			RightLineColor = { Name = "Right Line Color", Description = "Right line color.", Order = 76, SettingType = "Multile", Options = buildCrosshairColorOptions(), Default = 1 },
			RightLineOpacity = { Name = "Right Line Opacity", Description = "Right line opacity.", Order = 77, SettingType = "slider", Slider = { Min = 0, Max = 100, Step = 1, Default = 100 } },
			RightLineThickness = { Name = "Right Line Thickness", Description = "Right line thickness.", Order = 78, SettingType = "slider", Slider = { Min = 1, Max = 12, Step = 1, Default = 2 } },
			RightLineLength = { Name = "Right Line Length", Description = "Right line length.", Order = 79, SettingType = "slider", Slider = { Min = 2, Max = 40, Step = 1, Default = 10 } },
			RightLineRoundness = { Name = "Right Line Roundness", Description = "Right line roundness.", Order = 80, SettingType = "slider", Slider = { Min = 0, Max = 20, Step = 1, Default = 0 } },
			RightLineRotation = { Name = "Right Line Rotation", Description = "Right line rotation.", Order = 81, SettingType = "slider", Slider = { Min = -180, Max = 180, Step = 1, Default = 0 } },
			RightLineGap = { Name = "Right Line Gap", Description = "Right line extra gap.", Order = 82, SettingType = "slider", Slider = { Min = -50, Max = 50, Step = 1, Default = 10 } },

			DividerAdvancedDot = {
				Name = "DOT",
				Description = "Advanced style for center dot.",
				Order = 83,
				SettingType = "divider",
			},
			DotColor = { Name = "Dot Color", Description = "Dot color.", Order = 84, SettingType = "Multile", Options = buildCrosshairColorOptions(), Default = 1 },
			DotOpacity = { Name = "Dot Opacity", Description = "Dot opacity.", Order = 85, SettingType = "slider", Slider = { Min = 0, Max = 100, Step = 1, Default = 100 } },
			DotRoundness = { Name = "Dot Roundness", Description = "Dot roundness.", Order = 86, SettingType = "slider", Slider = { Min = 0, Max = 20, Step = 1, Default = 0 } },
		},
	},
}

SettingsConfig.CategoryOrder = { "Gameplay", "Controls", "Crosshair", "Audio" }

SettingsConfig.BlockedKeys = {
	Enum.KeyCode.Escape,
	Enum.KeyCode.Backspace,
	Enum.KeyCode.Return,
	Enum.KeyCode.Tab,
	Enum.KeyCode.Unknown,
}

SettingsConfig.DefaultSettings = {
	Gameplay = {
		DisableShadows = 2,
		DisableTextures = 2,
		DisableOthersWraps = 2,
		HideMuzzleFlash = 2,
		DamageNumbers = 2,
		DisableEffects = 2,
		HideHud = false,
		WeaponInking = 4,
		HideTeammateDisplay = 2,
		DisplayArea = 100,
		Brightness = 3,
		HorizontalSensitivity = 50,
		VerticalSensitivity = 50,
		ADSSensitivity = 75,
		FieldOfView = 70,
		FOVZoomStrength = 100,
		FieldOfViewEffects = 1,
		ScreenShake = 1,
		TeamColor = 1,
		TeamInking = 4,
		TeamInkTransparency = 2,
		TeamSeeThroughWalls = 1,
		EnemyColor = 1,
		EnemyInking = 4,
		EnemyInkTransparency = 2,
		OverallSensitivity = 50,
		ControllerSensitivity = 50,
		MobileSensitivity = 50,
		SensX = 50,
		SensY = 50,
		CameraSmoothing = 0,
		InvertY = 2,
		InvertX = 2,
		ToggleCrouch = 2,
		ToggleSprint = 2,
		AutoSprint = 1,
		AutoSlide = 2,
		WallJumpAssist = 2,
		ToggleAim = 2,
		EasyCycle = 1,
		AimAssist = 2,
		AimAssistStrength = 3,
		AutoShoot = 2,
		EasyAbility = 2,
		ArrangeMobileButtons = 2,
		ResetMobileButtons = 0,
		MobileButtonLayout = {},
	},

	Audio = {
		MasterVolume = 100,
		SFXVolume = 100,
		MusicVolume = 40,
		PlayerSounds = 100,
		DialogueMode = 2,
		AudioOcclusion = 1,
	},

	Controls = {
		ToggleAim = 2,
		ScrollEquip = 2,
		ToggleCrouch = 2,
		SprintSetting = 1,
		AutoShootMode = 1,
		AutoShootReactionTime = 25,
		AimAssistStrength = 0.5,
		MoveForward = {
			PC = Enum.KeyCode.W,
			PC2 = nil,
			Console = nil,
		},
		MoveBackward = {
			PC = Enum.KeyCode.S,
			PC2 = nil,
			Console = nil,
		},
		MoveLeft = {
			PC = Enum.KeyCode.A,
			PC2 = nil,
			Console = nil,
		},
		MoveRight = {
			PC = Enum.KeyCode.D,
			PC2 = nil,
			Console = nil,
		},
		Sprint = {
			PC = Enum.KeyCode.LeftShift,
			PC2 = Enum.KeyCode.RightShift,
			Console = Enum.KeyCode.ButtonL3,
		},
		Jump = {
			PC = Enum.KeyCode.Space,
			PC2 = nil,
			Console = Enum.KeyCode.ButtonA,
		},
		Slide = {
			PC = Enum.KeyCode.V,
			PC2 = nil,
			Console = Enum.KeyCode.ButtonR3,
		},
		Crouch = {
			PC = Enum.KeyCode.LeftControl,
			PC2 = Enum.KeyCode.C,
			Console = Enum.KeyCode.ButtonB,
		},
		Fire = {
			PC = Enum.UserInputType.MouseButton1,
			PC2 = nil,
			Console = Enum.KeyCode.ButtonR2,
		},
		Special = {
			PC = Enum.UserInputType.MouseButton2,
			PC2 = nil,
			Console = Enum.KeyCode.ButtonL2,
		},
		Reload = {
			PC = Enum.KeyCode.R,
			PC2 = nil,
			Console = Enum.KeyCode.ButtonX,
		},
		QuickMelee = {
			PC = Enum.KeyCode.F,
			PC2 = nil,
			Console = Enum.KeyCode.ButtonY,
		},
		Inspect = {
			PC = Enum.KeyCode.T,
			PC2 = nil,
			Console = nil,
		},
		Ability = {
			PC = Enum.KeyCode.E,
			PC2 = nil,
			Console = Enum.KeyCode.DPadRight,
		},
		Ultimate = {
			PC = Enum.KeyCode.Q,
			PC2 = nil,
			Console = Enum.KeyCode.ButtonY,
		},
		Interact = {
			PC = Enum.KeyCode.F,
			PC2 = nil,
			Console = Enum.KeyCode.ButtonX,
		},
		Emotes = {
			PC = Enum.KeyCode.B,
			PC2 = nil,
			Console = Enum.KeyCode.DPadDown,
		},
		EmoteWheelMode = 1, -- 1 = Hold, 2 = Toggle
		EquipPrimary = {
			PC = Enum.KeyCode.One,
			PC2 = nil,
			Console = nil,
		},
		EquipSecondary = {
			PC = Enum.KeyCode.Two,
			PC2 = nil,
			Console = nil,
		},
		EquipMelee = {
			PC = Enum.KeyCode.Three,
			PC2 = nil,
			Console = nil,
		},
		CycleWeaponLeft = {
			PC = nil,
			PC2 = nil,
			Console = Enum.KeyCode.ButtonL1,
		},
		CycleWeaponRight = {
			PC = nil,
			PC2 = nil,
			Console = Enum.KeyCode.ButtonR1,
		},
	},

	Crosshair = {
		CrosshairDisabled = 2,
		ForceDefaultCrosshair = 2,
		DisableSlideRotation = 2,
		AdvancedStyleSettings = 2,
		ShowTopLine = 1,
		ShowBottomLine = 1,
		ShowLeftLine = 1,
		ShowRightLine = 1,
		ShowDot = 1,
		CrosshairColor = 1,
		CrosshairSize = 100,
		CrosshairOpacity = 100,
		CrosshairGap = 10,
		CrosshairThickness = 2,
		CrosshairLineLength = 10,
		CrosshairRoundness = 0,
		GlobalRotation = 0,
		DotSize = 3,
		OutlineColor = 1,
		OutlineThickness = 0,
		OutlineOpacity = 100,
		DynamicSpreadEnabled = 1,
		MovementSpreadMultiplier = 1,
		SprintSpreadMultiplier = 1,
		AirSpreadMultiplier = 1,
		CrouchSpreadMultiplier = 1,
		RecoilSpreadMultiplier = 1,
		TopLineColor = 1,
		TopLineOpacity = 100,
		TopLineThickness = 2,
		TopLineLength = 10,
		TopLineRoundness = 0,
		TopLineRotation = 0,
		TopLineGap = 10,
		BottomLineColor = 1,
		BottomLineOpacity = 100,
		BottomLineThickness = 2,
		BottomLineLength = 10,
		BottomLineRoundness = 0,
		BottomLineRotation = 0,
		BottomLineGap = 10,
		LeftLineColor = 1,
		LeftLineOpacity = 100,
		LeftLineThickness = 2,
		LeftLineLength = 10,
		LeftLineRoundness = 0,
		LeftLineRotation = 0,
		LeftLineGap = 10,
		RightLineColor = 1,
		RightLineOpacity = 100,
		RightLineThickness = 2,
		RightLineLength = 10,
		RightLineRoundness = 0,
		RightLineRotation = 0,
		RightLineGap = 10,
		DotColor = 1,
		DotOpacity = 100,
		DotRoundness = 0,
	},
}

SettingsConfig.Templates = {
	Toggle = nil,
	Multile = nil,
	Slider = nil,
	Keybind = nil,
	KeybindUnavailable = nil,
	KeybindDisplay = nil,
	Reset = nil,
	Action = nil,
	Divider = nil,
}

SettingsConfig._templatesInitialized = false

local function resolveTemplateRoot(explicitRoot: Instance?): Instance?
	if explicitRoot then
		return explicitRoot
	end

	local legacy = ReplicatedFirst:FindFirstChild("Templates")
	if legacy then
		return legacy
	end

	return nil
end

function SettingsConfig.init(templateRoot: Instance?)
	local templatesFolder = resolveTemplateRoot(templateRoot)
	if not templatesFolder then
		return
	end

	SettingsConfig.Templates.Toggle = templatesFolder:FindFirstChild("ToggleTemplate")
		or templatesFolder:FindFirstChild("TemplateToggle")
	SettingsConfig.Templates.Multile = templatesFolder:FindFirstChild("MultileTemplate")
		or templatesFolder:FindFirstChild("Template")
	SettingsConfig.Templates.Slider = templatesFolder:FindFirstChild("SliderTemplate")
		or templatesFolder:FindFirstChild("TemplateSlider")
	SettingsConfig.Templates.Keybind = templatesFolder:FindFirstChild("ControlTemplate")
		or templatesFolder:FindFirstChild("TemplateKeybind")
	SettingsConfig.Templates.KeybindUnavailable = templatesFolder:FindFirstChild("UnavailableControlTemplate")
	SettingsConfig.Templates.KeybindDisplay = templatesFolder:FindFirstChild("KeybindDisplay")
	SettingsConfig.Templates.Reset = templatesFolder:FindFirstChild("ResetTemplate")
		or templatesFolder:FindFirstChild("Reset")
	SettingsConfig.Templates.Action = templatesFolder:FindFirstChild("ActionTemplate")
		or SettingsConfig.Templates.Reset
	SettingsConfig.Templates.Divider = templatesFolder:FindFirstChild("DividerTemplate")
		or templatesFolder:FindFirstChild("Dvdr")

	SettingsConfig._templatesInitialized = true
end

function SettingsConfig.getSettingsList(categoryKey: string): { { key: string, config: SettingConfig } }
	local category = SettingsConfig.Categories[categoryKey]
	if not category then
		return {}
	end

	local list = {}
	for key, config in category.Settings do
		table.insert(list, { key = key, config = config })
	end

	table.sort(list, function(a, b)
		return (a.config.Order or 999) < (b.config.Order or 999)
	end)

	return list
end

function SettingsConfig.getCategory(categoryKey: string): CategoryConfig?
	return SettingsConfig.Categories[categoryKey]
end

function SettingsConfig.getSetting(categoryKey: string, settingKey: string): SettingConfig?
	local category = SettingsConfig.Categories[categoryKey]
	if not category then
		return nil
	end
	return category.Settings[settingKey]
end

function SettingsConfig.getDefaultValue(categoryKey: string, settingKey: string): any
	local categoryDefaults = SettingsConfig.DefaultSettings[categoryKey]
	if not categoryDefaults then
		return nil
	end
	return categoryDefaults[settingKey]
end

function SettingsConfig.getOptionByIndex(config: SettingConfig, index: number): SettingOption?
	if not config.Options then
		return nil
	end
	return config.Options[index]
end

function SettingsConfig.getOptionCount(config: SettingConfig): number
	if not config.Options then
		return 0
	end
	return #config.Options
end

function SettingsConfig.isKeyBlocked(keyCode: Enum.KeyCode): boolean
	return table.find(SettingsConfig.BlockedKeys, keyCode) ~= nil
end

function SettingsConfig.getTemplate(settingType: string): Instance?
	if settingType == "toggle" then
		return SettingsConfig.Templates.Toggle
	elseif settingType == "Multile" then
		return SettingsConfig.Templates.Multile
	elseif settingType == "slider" then
		return SettingsConfig.Templates.Slider
	elseif settingType == "keybind" then
		return SettingsConfig.Templates.Keybind or SettingsConfig.Templates.KeybindUnavailable
	elseif settingType == "action" then
		return SettingsConfig.Templates.Action or SettingsConfig.Templates.Reset
	elseif settingType == "divider" then
		return SettingsConfig.Templates.Divider
	end
	return nil
end

function SettingsConfig.cloneTemplate(settingType: string): Instance?
	local template = SettingsConfig.getTemplate(settingType)
	if not template then
		return nil
	end
	return template:Clone()
end

function SettingsConfig.cloneUnavailableTemplate(settingType: string): Instance?
	if settingType == "keybind" and SettingsConfig.Templates.KeybindUnavailable then
		return SettingsConfig.Templates.KeybindUnavailable:Clone()
	end
	return nil
end

function SettingsConfig.isSettingAllowedOnDevice(config: SettingConfig, deviceType: DeviceType): boolean
	if config.Platforms and #config.Platforms > 0 then
		return table.find(config.Platforms, deviceType) ~= nil
	end

	if config.BlockedPlatforms and #config.BlockedPlatforms > 0 then
		return table.find(config.BlockedPlatforms, deviceType) == nil
	end

	return true
end

return SettingsConfig
