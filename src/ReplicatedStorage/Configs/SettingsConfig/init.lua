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

export type SettingConfig = {
	Name: string,
	Description: string,
	Order: number,
	SettingType: "toggle" | "slider" | "keybind" | "divider",
	Image: { string }?,
	Video: string?,
	Options: { SettingOption }?,
	Default: number?,
	Slider: SliderConfig?,
	Action: string?,
	Bind: BindConfig?,
	DefaultBind: BindConfig?,
}

export type SettingsCategory = {
	[string]: SettingConfig,
}

export type CategoryConfig = {
	DisplayName: string,
	Order: number,
	Settings: SettingsCategory,
}

SettingsConfig.Categories = {
	Gameplay = {
		DisplayName = "Gameplay",
		Order = 1,
		Settings = {
			DisableShadows = {
				Name = "Disable Shadows",
				Description = "Remove all shadows in game, reducing lag and improving performance on lower-end devices.",
				Order = 1,
				SettingType = "toggle",
				Image = { "rbxassetid://99447160043691", "rbxassetid://84344867877749" },
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			DisableTextures = {
				Name = "Disable Textures",
				Description = "Remove textures to improve performance.",
				Order = 2,
				SettingType = "toggle",
				Image = { "rbxassetid://118298540523091", "rbxassetid://97170520694267" },
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			DisableOthersWraps = {
				Name = "Disable Others Wraps",
				Description = "Hide weapon wraps from other players.",
				Order = 3,
				SettingType = "toggle",
				Image = { "rbxassetid://108799503900149" },
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			DamageNumbers = {
				Name = "Damage Numbers",
				Description = "Toggle floating damage numbers above enemies when dealing damage.",
				Order = 4,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			DisableEffects = {
				Name = "Hide Effects",
				Description = "Hide visual effects to improve performance.",
				Order = 5,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			Divider1 = {
				Name = "HUD",
				Description = "",
				Order = 10,
				SettingType = "divider",
			},

			HideHud = {
				Name = "Hide Hud",
				Description = "Hide the entire HUD interface.",
				Order = 11,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			HideTeammateDisplay = {
				Name = "Hide Teammate Display",
				Description = "Hide teammate indicators and information.",
				Order = 12,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			DisplayArea = {
				Name = "Display Area",
				Description = "Shrinks the HUD display area.",
				Order = 13,
				SettingType = "slider",
				Slider = {
					Max = 5,
					Min = 0,
					Step = 1,
					Default = 0,
				},
			},

			Divider2 = {
				Name = "CAMERA",
				Description = "",
				Order = 20,
				SettingType = "divider",
			},

			HorizontalSensitivity = {
				Name = "Horizontal Sensitivity",
				Description = "Adjust horizontal camera sensitivity.",
				Order = 21,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 50,
				},
			},

			VerticalSensitivity = {
				Name = "Vertical Sensitivity",
				Description = "Adjust vertical camera sensitivity.",
				Order = 22,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 50,
				},
			},

			ADSSensitivity = {
				Name = "ADS Sensitivity",
				Description = "Adjust aim down sights sensitivity.",
				Order = 23,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 100,
				},
			},

			FieldOfView = {
				Name = "Field Of View",
				Description = "Adjust camera field of view.",
				Order = 24,

				Image = { "rbxassetid://131531757988844" },
				SettingType = "slider",
				Slider = {
					Max = 120,
					Min = 0,
					Step = 1,
					Default = 70,
				},
			},

			FieldOfViewEffects = {
				Name = "Field Of View Effects",
				Description = "Toggle dynamic FOV changes during gameplay.",
				Order = 25,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			ScreenShake = {
				Name = "Screen Shake",
				Description = "Controls the intensity of camera shake effects during combat and explosions.",
				Order = 26,
				SettingType = "slider",
				Slider = {
					Max = 3,
					Min = 0,
					Step = 1,
					Default = 1,
				},
			},

			Divider3 = {
				Name = "COLORS",
				Description = "",
				Order = 30,
				SettingType = "divider",
			},

			TeamColor = {
				Name = "Team Color",
				Description = "Change the color used for teammates.",
				Order = 31,
				SettingType = "toggle",
				Options = {
					{ Display = "Blue", Color = Color3.fromRGB(39, 53, 255), Value = "Blue" },
					{ Display = "Orange", Color = Color3.fromRGB(231, 155, 32), Value = "Orange" },
					{ Display = "Green", Color = Color3.fromRGB(20, 177, 46), Value = "Green" },
					{ Display = "Yellow", Color = Color3.fromRGB(233, 219, 23), Value = "Yellow" },
				},
				Default = 1,
			},

			EnemyColor = {
				Name = "Enemy Color",
				Description = "Change the color used for enemies.",
				Order = 32,
				SettingType = "toggle",
				Options = {
					{ Display = "Red", Color = Color3.fromRGB(255, 0, 4), Value = "Red" },
					{ Display = "Pink", Color = Color3.fromRGB(201, 34, 223), Value = "Pink" },
					{ Display = "Purple", Color = Color3.fromRGB(121, 25, 255), Value = "Purple" },
					{ Display = "Cyan", Color = Color3.fromRGB(27, 177, 247), Value = "Cyan" },
				},
				Default = 1,
			},

			Divider4 = {
				Name = "AUDIO",
				Description = "",
				Order = 40,
				SettingType = "divider",
			},

			MasterVolume = {
				Name = "Master Volume",
				Description = "Controls the overall volume of all game sounds.",
				Order = 41,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 100,
				},
			},

			MusicVolume = {
				Name = "Music Volume",
				Description = "Controls the volume of background music.",
				Order = 42,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 100,
				},
			},

			SFXVolume = {
				Name = "SFX Volume",
				Description = "Controls the volume of sound effects.",
				Order = 43,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 100,
				},
			},

			EmoteVolume = {
				Name = "Emote Volume",
				Description = "Controls the volume of emote sounds.",
				Order = 44,
				SettingType = "slider",
				Slider = {
					Max = 100,
					Min = 0,
					Step = 1,
					Default = 100,
				},
			},
		},
	},

	Controls = {
		DisplayName = "Controls",
		Order = 2,
		Settings = {
			Sprint = {
				Name = "Sprint",
				Description = "Hold to move faster.",
				Order = 11,
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

			Jump = {
				Name = "Jump",
				Description = "Press to jump. Can be used for parkour and dodging.",
				Order = 12,
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

			Crouch = {
				Name = "Crouch",
				Description = "Toggle crouch to reduce visibility and move silently.",
				Order = 13,
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

			Ability = {
				Name = "Use Ability",
				Description = "Activate your kit's primary ability.",
				Order = 14,
				SettingType = "keybind",
				Action = "Ability",
				Bind = {
					PC = Enum.KeyCode.E,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonX,
				},
				DefaultBind = {
					PC = Enum.KeyCode.E,
					PC2 = nil,
					Console = Enum.KeyCode.ButtonX,
				},
			},

			Ultimate = {
				Name = "Use Ultimate",
				Description = "Activate your kit's ultimate ability when fully charged.",
				Order = 15,
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
				Description = "Interact with objects, NPCs, and pickups in the world.",
				Order = 16,
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

			Emotes = {
				Name = "Emote Wheel",
				Description = "Open the emote selection wheel.",
				Order = 17,
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
				Description = "Hold: Release to select. Toggle: Press again to close.",
				Order = 18,
				SettingType = "toggle",
				Options = {
					{ Display = "Hold", Value = "Hold" },
					{ Display = "Toggle", Value = "Toggle" },
				},
				Default = 1,
			},

			Divider2 = {
				Name = "AIM ASSIST",
				Description = "",
				Order = 20,
				SettingType = "divider",
			},

			AutoShootMode = {
				Name = "Auto Shoot Mode",
				Description = "Automatically fire when aiming at enemies.",
				Order = 21,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			AutoShootReactionTime = {
				Name = "Auto Shoot Reaction Time",
				Description = "Delay before auto-shoot activates (milliseconds).",
				Order = 22,
				SettingType = "slider",
				Slider = {
					Max = 125,
					Min = 0,
					Step = 10,
					Default = 25,
				},
			},

			AimAssistStrength = {
				Name = "Aim Assist Strength",
				Description = "Strength of aim assist.",
				Order = 23,
				SettingType = "slider",
				Slider = {
					Max = 1,
					Min = 0,
					Step = 0.1,
					Default = 0.5,
				},
			},

			Divider1 = {
				Name = "Actions",
				Description = "",
				Order = 25,
				SettingType = "divider",
			},

			ToggleAim = {
				Name = "Toggle Aim",
				Description = "Toggle aim down sights instead of holding.",
				Order = 26,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			ScrollEquip = {
				Name = "Scroll Equip",
				Description = "Use scroll wheel to switch weapons.",
				Order = 27,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			ToggleCrouch = {
				Name = "Toggle Crouch",
				Description = "Toggle crouch instead of holding.",
				Order = 28,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			SprintSetting = {
				Name = "Sprint Setting",
				Description = "Choose sprint behavior.",
				Order = 29,
				SettingType = "toggle",
				Options = {
					{ Display = "Hold", Value = "Hold" },
					{ Display = "Toggle", Value = "Toggle" },
					{ Display = "Auto", Value = "Auto" },
					{ Display = "Disabled", Value = "Disabled" },
				},
				Default = 1,
			},
		},
	},

	Crosshair = {
		DisplayName = "Crosshair",
		Order = 3,
		Settings = {
			CrosshairEnabled = {
				Name = "Crosshair Enabled",
				Description = "Toggle the crosshair visibility on or off.",
				Order = 1,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 1,
			},

			CrosshairColor = {
				Name = "Crosshair Color",
				Description = "Change the color of your crosshair.",
				Order = 2,
				SettingType = "toggle",
				Options = {
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
				},
				Default = 1,
			},

			CrosshairSize = {
				Name = "Crosshair Size",
				Description = "Adjust the overall size of your crosshair.",
				Order = 3,
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
				Description = "Adjust the transparency of your crosshair.",
				Order = 4,
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
				Description = "Adjust the center gap of your crosshair.",
				Order = 5,
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
				Description = "Adjust the line thickness of your crosshair.",
				Order = 6,
				SettingType = "slider",
				Slider = {
					Max = 10,
					Min = 1,
					Step = 1,
					Default = 2,
				},
			},
		},
	},
}

SettingsConfig.CategoryOrder = { "Gameplay", "Controls", "Crosshair" }

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
		DamageNumbers = 1,
		DisableEffects = 2,
		HideHud = 2,
		HideTeammateDisplay = 2,
		DisplayArea = 0,
		HorizontalSensitivity = 50,
		VerticalSensitivity = 50,
		ADSSensitivity = 100,
		FieldOfView = 70,
		FieldOfViewEffects = 2,
		ScreenShake = 1,
		TeamColor = 1,
		EnemyColor = 1,
		MasterVolume = 100,
		MusicVolume = 100,
		SFXVolume = 100,
		EmoteVolume = 100,
	},

	Controls = {
		ToggleAim = 2,
		ScrollEquip = 2,
		ToggleCrouch = 2,
		SprintSetting = 1,
		AutoShootMode = 1,
		AutoShootReactionTime = 25,
		AimAssistStrength = 0.5,
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
		Crouch = {
			PC = Enum.KeyCode.LeftControl,
			PC2 = Enum.KeyCode.C,
			Console = Enum.KeyCode.ButtonB,
		},
		Ability = {
			PC = Enum.KeyCode.E,
			PC2 = nil,
			Console = Enum.KeyCode.ButtonX,
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
	},

	Crosshair = {
		CrosshairEnabled = 1,
		CrosshairColor = 1,
		CrosshairSize = 100,
		CrosshairOpacity = 100,
		CrosshairGap = 10,
		CrosshairThickness = 2,
	},
}

SettingsConfig.Templates = {
	Toggle = nil,
	Slider = nil,
	Keybind = nil,
	KeybindDisplay = nil,
	Reset = nil,
	Divider = nil,
}

SettingsConfig._templatesInitialized = false

function SettingsConfig.init()
	if SettingsConfig._templatesInitialized then
		return
	end

	local templatesFolder = game.ReplicatedFirst:WaitForChild("Templates")
	SettingsConfig.Templates.Toggle = templatesFolder:FindFirstChild("Template")
	SettingsConfig.Templates.Slider = templatesFolder:FindFirstChild("TemplateSlider")
	SettingsConfig.Templates.Keybind = templatesFolder:FindFirstChild("TemplateKeybind")
	SettingsConfig.Templates.KeybindDisplay = templatesFolder:FindFirstChild("KeybindDisplay")
	SettingsConfig.Templates.Reset = templatesFolder:FindFirstChild("Reset")
	SettingsConfig.Templates.Divider = templatesFolder:FindFirstChild("Dvdr")

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
	elseif settingType == "slider" then
		return SettingsConfig.Templates.Slider
	elseif settingType == "keybind" then
		return SettingsConfig.Templates.Keybind
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

return SettingsConfig
