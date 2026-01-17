--[[
	ConfigValidator - Runtime validation for configuration values
	Ensures all config values are valid and safe at startup
]]

local ConfigValidator = {}

-- Validation rules for different types
local function validateNumber(value, min, max, name)
	if type(value) ~= "number" then
		error(`Config validation failed: {name} must be a number, got {type(value)}`)
	end
	if min and value < min then
		error(`Config validation failed: {name} must be >= {min}, got {value}`)
	end
	if max and value > max then
		error(`Config validation failed: {name} must be <= {max}, got {value}`)
	end
	return true
end

local function validateBoolean(value, name)
	if type(value) ~= "boolean" then
		error(`Config validation failed: {name} must be a boolean, got {type(value)}`)
	end
	return true
end

local function validateString(value, name)
	if type(value) ~= "string" then
		error(`Config validation failed: {name} must be a string, got {type(value)}`)
	end
	return true
end

local function validateTable(value, name)
	if type(value) ~= "table" then
		error(`Config validation failed: {name} must be a table, got {type(value)}`)
	end
	return true
end

-- Validation schema for each config section
local VALIDATION_SCHEMA = {
	Gameplay = {
		Cooldowns = {
			Crouch = { type = "number", min = 0, max = 10 },
			Jump = { type = "number", min = 0, max = 10 },
			Slide = { type = "number", min = 0, max = 10 },
		},
		Character = {
			WalkSpeed = { type = "number", min = 1, max = 100 },
			JumpPower = { type = "number", min = 1, max = 200 },
			MovementForce = { type = "number", min = 1, max = 1000 },
			FrictionMultiplier = { type = "number", min = 0, max = 1 },
			AirControlMultiplier = { type = "number", min = 0, max = 1 },
			GroundRayOffset = { type = "number", min = 0, max = 5 },
			GroundRayDistance = { type = "number", min = 0.1, max = 10 },
			MaxWalkableSlopeAngle = { type = "number", min = 0, max = 90 },
			CrouchHeightReduction = { type = "number", min = 0.1, max = 5 },
			CrouchSpeedReduction = { type = "number", min = 0.1, max = 1 },
			HideFromLocalPlayer = { type = "boolean" },
			ShowRigForTesting = { type = "boolean" },
		},
		Sliding = {
			InitialVelocity = { type = "number", min = 10, max = 200 },
			MinVelocity = { type = "number", min = 1, max = 50 },
			MaxVelocity = { type = "number", min = 50, max = 300 },
			FrictionRate = { type = "number", min = 0.1, max = 2 },
		},
	},
	Controls = {
		Input = {
			ShowMobileControls = { type = "boolean" },
			MobileJoystickSize = { type = "number", min = 50, max = 300 },
			MobileButtonSize = { type = "number", min = 30, max = 150 },
		},
		Camera = {
			FieldOfView = { type = "number", min = 30, max = 120 },
			Smoothness = { type = "number", min = 1, max = 100 },
			MouseSensitivity = { type = "number", min = 0.1, max = 10 },
			TouchSensitivity = { type = "number", min = 0.1, max = 10 },
			ControllerSensitivityX = { type = "number", min = 1, max = 20 },
			ControllerSensitivityY = { type = "number", min = 1, max = 20 },
			MinVerticalAngle = { type = "number", min = -90, max = 0 },
			MaxVerticalAngle = { type = "number", min = 0, max = 90 },
			AngleSmoothness = { type = "number", min = 1, max = 100 },
			EnableCrouchTransitionSmoothing = { type = "boolean" },
			CrouchTransitionSpeed = { type = "number", min = 1, max = 50 },
		},
	},
	System = {
		Network = {
			CharacterRespawnTime = { type = "number", min = 1, max = 60 },
			AutoSpawnOnJoin = { type = "boolean" },
			GiveClientNetworkOwnership = { type = "boolean" },
		},
		Server = {
			GCInterval = { type = "number", min = 10, max = 600 },
			GCMaxAge = { type = "number", min = 60, max = 3600 },
			MaxCharactersPerPlayer = { type = "number", min = 1, max = 10 },
			CharacterTimeoutTime = { type = "number", min = 30, max = 1800 },
		},
		Logging = {
			MinLogLevel = { type = "number", min = 1, max = 5 },
			LogToRobloxOutput = { type = "boolean" },
			LogToMemory = { type = "boolean" },
			MaxLogEntries = { type = "number", min = 100, max = 10000 },
			LogPerformanceMetrics = { type = "boolean" },
			PerformanceLogInterval = { type = "number", min = 5, max = 300 },
		},
		Debug = {
			ShowGroundRaycast = { type = "boolean" },
			ShowCharacterBounds = { type = "boolean" },
			ShowPhysicsForces = { type = "boolean" },
			LogMovementInput = { type = "boolean" },
			LogGroundDetection = { type = "boolean" },
			LogPhysicsChanges = { type = "boolean" },
		},
	},
}

local function validateValue(value, rule, path)
	local name = table.concat(path, ".")

	if rule.type == "number" then
		validateNumber(value, rule.min, rule.max, name)
	elseif rule.type == "boolean" then
		validateBoolean(value, name)
	elseif rule.type == "string" then
		validateString(value, name)
	elseif rule.type == "table" then
		validateTable(value, name)
	else
		error(`Config validation failed: Unknown validation type '{rule.type}' for {name}`)
	end
end

local function validateSection(config, schema, path)
	local errors = {}

	for key, rule in pairs(schema) do
		local currentPath = {}
		for _, p in ipairs(path) do
			table.insert(currentPath, p)
		end
		table.insert(currentPath, key)

		local value = config[key]
		if value == nil then
			local pathStr = table.concat(currentPath, ".")
			table.insert(errors, `Missing required value at {pathStr}`)
			continue
		end

		local success, err = pcall(function()
			if type(rule) == "table" and rule.type then
				-- This is a validation rule
				validateValue(value, rule, currentPath)
			elseif type(rule) == "table" then
				-- This is a nested section
				validateSection(value, rule, currentPath)
			end
		end)

		if not success then
			table.insert(errors, err)
		end
	end

	if #errors > 0 then
		error(`Config validation errors:\n  - {table.concat(errors, "\n  - ")}`)
	end
end

function ConfigValidator:ValidateConfig(config)
	local success, err = pcall(function()
		validateSection(config, VALIDATION_SCHEMA, {})
	end)

	if not success then
		error(`Configuration validation failed: {err}`)
	end

	print("[CONFIG] Configuration validation passed successfully")
	return true
end

function ConfigValidator:GetValidationSchema()
	return VALIDATION_SCHEMA
end

return ConfigValidator
