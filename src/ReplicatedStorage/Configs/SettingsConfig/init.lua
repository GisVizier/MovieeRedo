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
	SettingType: "toggle" | "slider" | "keybind" | "divider" | "Multile",
	Icon: string?,
	Image: { string }?,
	Video: string?,
	Options: { SettingOption }?,
	Default: number?,
	Slider: SliderConfig?,
	Action: string?,
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

SettingsConfig.Categories = {
	Gameplay = {
		DisplayName = "Gameplay",
		Order = 1,
		Settings = {
			DividerPerformance = {
				Name = "PERFORMANCE",
				Description = "",
				Order = 1,
				SettingType = "divider",
			},

			DisableShadows = {
				Name = "Disable Shadows",
				Description = "Remove all shadows in game, reducing lag and improving performance on lower-end devices.",
				Order = 2,
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
				Description = "Hide other players' weapon wraps and cosmetic FX when not spectating.",
				Order = 4,
				SettingType = "toggle",
				Image = { "rbxassetid://108799503900149" },
				Options = {
					{ Display = "Enabled", Value = true },
					{ Display = "Disabled", Value = false },
				},
				Default = 2,
			},

			HideMuzzleFlash = {
				Name = "Hide Muzzle Flash",
				Description = "Hide muzzle flash visuals while firing.",
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
				Description = "Adjust active weapon inking style.",
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
				Description = "",
				Order = 10,
				SettingType = "divider",
			},

			DisplayArea = {
				Name = "HUD Size",
				Description = "Scale the HUD larger or smaller.",
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
				Description = "Increase or decrease client brightness intensity.",
				Order = 12,
				SettingType = "slider",
				Slider = {
					Max = 200,
					Min = 0,
					Step = 1,
					Default = 100,
				},
			},

			FieldOfView = {
				Name = "Field Of View",
				Description = "Adjust camera field of view.",
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
				Description = "Scale ADS FOV change strength from 0 to 100%.",
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
				Description = "Toggle dynamic FOV changes during gameplay.",
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
				Description = "Controls the intensity of camera shake effects during combat and explosions.",
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
				Description = "Hide the HUD and show only the unhide prompt.",
				Order = 17,
				SettingType = "toggle",
				Options = {
					{ Display = "Enabled", Value = true, Image = "rbxassetid://136898318593158" },
					{ Display = "Disabled", Value = false, Image = "rbxassetid://133332591837085" },
				},
				Default = 2,
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

			EquipPrimary = {
				Name = "Equip Primary",
				Description = "Select primary weapon.",
				Order = 19,
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
				Description = "Select secondary weapon.",
				Order = 19.1,
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
				Description = "Select melee weapon.",
				Order = 19.2,
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
				Description = "Cycle to previous weapon.",
				Order = 19.3,
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
				Description = "Cycle to next weapon.",
				Order = 19.4,
				SettingType = "slider",
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
		HideHud = false,
		WeaponInking = 4,
		HideTeammateDisplay = 2,
		DisplayArea = 0,
		HorizontalSensitivity = 50,
		VerticalSensitivity = 50,
		ADSSensitivity = 75,
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
	Multile = nil,
	Slider = nil,
	Keybind = nil,
	KeybindUnavailable = nil,
	KeybindDisplay = nil,
	Reset = nil,
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
