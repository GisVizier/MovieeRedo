local ConfigCache = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))

ConfigCache.MOVEMENT_FORCE = Config.Gameplay.Character.MovementForce
ConfigCache.WALK_SPEED = Config.Gameplay.Character.WalkSpeed
ConfigCache.JUMP_POWER = Config.Gameplay.Character.JumpPower
ConfigCache.AIR_CONTROL_MULTIPLIER = Config.Gameplay.Character.AirControlMultiplier

ConfigCache.FALL_SPEED_ENABLED = Config.Gameplay.Character.FallSpeed.Enabled
ConfigCache.MAX_FALL_SPEED = Config.Gameplay.Character.FallSpeed.MaxFallSpeed
ConfigCache.FALL_DRAG_MULTIPLIER = Config.Gameplay.Character.FallSpeed.DragMultiplier
ConfigCache.ASCENT_DRAG = Config.Gameplay.Character.FallSpeed.AscentDrag or 0.012
ConfigCache.HANG_TIME_THRESHOLD = Config.Gameplay.Character.FallSpeed.HangTimeThreshold or 8
ConfigCache.HANG_TIME_DRAG = Config.Gameplay.Character.FallSpeed.HangTimeDrag or 0.08
ConfigCache.WORLD_GRAVITY = Config.Gameplay.Cooldowns.WorldGravity or 196.2

ConfigCache.GROUND_RAY_OFFSET = Config.Gameplay.Character.GroundRayOffset
ConfigCache.GROUND_RAY_DISTANCE = Config.Gameplay.Character.GroundRayDistance

ConfigCache.CAMERA_SMOOTHNESS = Config.Camera.Smoothing.AngleSmoothness
ConfigCache.MOUSE_SENSITIVITY = Config.Camera.Sensitivity.Mouse
ConfigCache.TOUCH_SENSITIVITY = Config.Camera.Sensitivity.Touch

ConfigCache.MAX_VERTICAL_ANGLE_RAD = math.rad(Config.Camera.AngleLimits.MaxVertical)
ConfigCache.MIN_VERTICAL_ANGLE_RAD = math.rad(Config.Camera.AngleLimits.MinVertical)

ConfigCache.FRICTION_MULTIPLIER = ConfigCache.MOVEMENT_FORCE * Config.Gameplay.Character.FrictionMultiplier
ConfigCache.DEADZONE_THRESHOLD = 0.5
ConfigCache.MIN_SPEED_THRESHOLD = 0.1
ConfigCache.MAX_FORCE_MULTIPLIER = ConfigCache.MOVEMENT_FORCE * 2

ConfigCache.VECTOR3_ZERO = Vector3.new(0, 0, 0)
ConfigCache.VECTOR3_UP = Vector3.new(0, 1, 0)
ConfigCache.VECTOR3_DOWN = Vector3.new(0, -1, 0)

ConfigCache.CFRAME_IDENTITY = CFrame.new()

ConfigCache.DEBUG_GROUND_DETECTION = Config.System.Debug.LogGroundDetection
ConfigCache.DEBUG_MOVEMENT_INPUT = Config.System.Debug.LogMovementInput
ConfigCache.DEBUG_PHYSICS_CHANGES = Config.System.Debug.LogPhysicsChanges

ConfigCache.CHARACTER_RESPAWN_TIME = Config.System.Network.CharacterRespawnTime
ConfigCache.AUTO_SPAWN_ON_JOIN = Config.System.Network.AutoSpawnOnJoin
ConfigCache.GIVE_CLIENT_NETWORK_OWNERSHIP = Config.System.Network.GiveClientNetworkOwnership

return ConfigCache
