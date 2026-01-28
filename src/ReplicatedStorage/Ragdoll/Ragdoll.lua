local Ragdoller = {}

type Dictionary<i, v> = { [i]: v }
type Array<v> = Dictionary<number, v>

local bridgeNet = require(game.ReplicatedStorage.Modules.Shared.BridgeNet2)
local bridges = require(game.ReplicatedStorage.Modules.DatabaseModules.Bridges)

local global = require(game.ReplicatedStorage.Global)

local Callbacks: Dictionary<string, Model> = require(script.Callbacks) :: Dictionary<string, Model>

local disableStates = {
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.RunningNoPhysics,
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.StrafingNoPhysics,
	Enum.HumanoidStateType.PlatformStanding,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
} :: { Enum.HumanoidStateType }

local enableStates = {
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.RunningNoPhysics,
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.StrafingNoPhysics,
	Enum.HumanoidStateType.PlatformStanding,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
} :: { Enum.HumanoidStateType }

function Ragdoller:Setup(Character: Model)
	local Humanoid = Character:WaitForChild("Humanoid") :: Humanoid
	local playerStates: Folder = game.ReplicatedStorage.PlayerStates:FindFirstChild(Character.Name) or Character

	--warn("SET UP RAGDOLL FOR: ",Character.Name)

	local connections = {}
	connections[#connections + 1] = playerStates:GetAttributeChangedSignal("Ragdoll"):Connect(function(val)
		if global.HasState(Character, "Knocked") then
			return
		end
		if playerStates:GetAttribute("Ragdoll") > 0 then
			--if not playerStates:GetAttribute("BeingCarried") and not playerStates:GetAttribute("BeingGripped") then
			Ragdoller:Enable(Character)
			--end
		else
			Ragdoller:Disable(Character)
		end
	end)

	connections[#connections + 1] = playerStates:GetAttributeChangedSignal("Knocked"):Connect(function(val)
		if playerStates:GetAttribute("Knocked") > 0 then
			--if not playerStates:GetAttribute("BeingCarried") and not playerStates:GetAttribute("BeingGripped") then
			Ragdoller:Enable(Character)
			--end
		else
			Ragdoller:Disable(Character)
		end
	end)

	connections[#connections + 1] = playerStates:GetAttributeChangedSignal("Unconscious"):Connect(function(val)
		if playerStates:GetAttribute("Unconscious") > 0 then
			--if not playerStates:GetAttribute("BeingCarried") and not playerStates:GetAttribute("BeingGripped") then
			Ragdoller:Enable(Character)
			--end
		else
			Ragdoller:Disable(Character)
		end
	end)

	connections[#connections + 1] = Humanoid.Died:Connect(function()
		for _, connection: RBXScriptConnection in connections :: { RBXScriptConnection } do
			connection:Disconnect()
		end
		table.clear(connections)
	end)
end

function Ragdoller:Enable(character: Model)
	if character:FindFirstChild(" Ragdoll") then
		return
	end
	if global.HasState(character, "Hyperarmour") then
		return
	end
	if character:GetAttribute("IsHostage") then
		return
	end

	local playerStates: Folder? = game.ReplicatedStorage.PlayerStates:FindFirstChild(character.Name) or character
	if not playerStates then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid

	local Ragdoll = global.NewInstance("BoolValue", { Name = "Ragdoll", Parent = character }) :: BoolValue
	Ragdoll.Name = "Ragdoll"

	playerStates:SetAttribute("NoRotation", 1)

	humanoid.AutoRotate = false
	humanoid.RequiresNeck = false
	humanoid.PlatformStand = true

	for _, state in disableStates do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	if not game.Players:GetPlayerFromCharacter(character) then
		bridges.Client:Fire(
			bridgeNet.AllPlayers(),
			{ Character = character, Module = "ChangeState", State = Enum.HumanoidStateType.Physics }
		)

		bridges.Client:Fire(
			bridgeNet.AllPlayers(),
			{ Character = character, Module = "SetStateEnabled", States = disableStates, Debounce = true }
		)
		bridges.Client:Fire(
			bridgeNet.AllPlayers(),
			{ Character = character, Module = "SetStateEnabled", States = enableStates, Debounce = false }
		)
	end

	if character:FindFirstChild("NoRagdollEffect") == nil then
		for _, v in character:GetDescendants() do
			if character:FindFirstChild(`{character.Name}Stand`) and v:FindFirstAncestor(`{character.Name}Stand`) then
				continue
			end
			if (v:IsA("Motor6D") or v:IsA("Weld")) and v:GetAttribute("C0Position") == nil then
				local X0, Y0, Z0 = v.C0:ToEulerAnglesXYZ()
				local X1, Y1, Z1 = v.C1:ToEulerAnglesXYZ()

				v:SetAttribute("C0Position", vector.create(v.C0.X, v.C0.Y, v.C0.Z))
				v:SetAttribute("C0Angle", vector.create(X0, Y0, Z0))

				v:SetAttribute("C1Position", vector.create(v.C1.X, v.C1.Y, v.C1.Z))
				v:SetAttribute("C1Angle", vector.create(X1, Y1, Z1))
			end

			if v:IsA("Motor6D") then
				local callback: any = Callbacks[v.Name]
				if callback then
					callback(character)
				end
			end
		end
	end
end

function Ragdoller:Disable(character: Model)
	if not character:FindFirstChild("Ragdoll") then
		return
	end

	local playerStates: Folder? = game.ReplicatedStorage.PlayerStates:FindFirstChild(character.Name) or character
	if not playerStates then
		return
	end

	if character:FindFirstChild("Ragdoll") then
		character.Ragdoll:Destroy()
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local oldRotation: vector = character.HumanoidRootPart.Orientation

	for _, state in enableStates :: { Enum.HumanoidStateType } do
		humanoid:SetStateEnabled(state, true)
	end
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	if not game.Players:GetPlayerFromCharacter(character) then
		bridges.Client:Fire(
			bridgeNet.AllPlayers(),
			{ Character = character, Module = "ChangeState", State = Enum.HumanoidStateType.GettingUp }
		)

		bridges.Client:Fire(
			bridgeNet.AllPlayers(),
			{ Character = character, Module = "SetStateEnabled", States = enableStates, Debounce = true }
		)
		bridges.Client:Fire(
			bridgeNet.AllPlayers(),
			{ Character = character, Module = "SetStateEnabled", States = disableStates, Debounce = false }
		)
	end

	for _, v in character:GetDescendants() do
		if character:FindFirstChild(`{character.Name}Stand`) and v:FindFirstAncestor(`{character.Name}Stand`) then
			continue
		end
		if v:IsA("Motor6D") then
			if
				v.Name == "Right Shoulder"
				or v.Name == "Right Hip"
				or v.Name == "Left Shoulder"
				or v.Name == "Left Hip"
				or v.Name == "Neck"
			then
				v.Part0 = character.Torso
			end
		elseif v.Name == "RagdollAttachment" or v.Name == "ConstraintJoint" or v.Name == "Collision" then
			v:Destroy()
		end
		if (v:IsA("Motor6D") or v:IsA("Weld")) and v:GetAttribute("C0Position") ~= nil then
			local C0Position = v:GetAttribute("C0Position")
			local C1Position = v:GetAttribute("C1Position")
			local C0Angle = v:GetAttribute("C0Angle")
			local C1Angle = v:GetAttribute("C1Angle")

			v.C0 = CFrame.new(C0Position.X, C0Position.Y, C0Position.Z) * CFrame.Angles(C0Angle.X, C0Angle.Y, C0Angle.Z)
			v.C1 = CFrame.new(C1Position.X, C1Position.Y, C1Position.Z) * CFrame.Angles(C1Angle.X, C1Angle.Y, C1Angle.Z)
		end
	end

	humanoid.PlatformStand = false

	task.delay(1, function()
		humanoid.RequiresNeck = true
	end)

	---Fix for a roblox bug, that messes with the character's motor's if they get rebuilt by a script :3
	pcall(function()
		---Roots
		character.HumanoidRootPart.RootJoint.C0 = CFrame.Angles(-math.pi / 2, 0, -math.pi)
		character.HumanoidRootPart["Root Hip"].C0 = CFrame.Angles(-math.pi / 2, 0, -math.pi)
		character.HumanoidRootPart["Root Hip"].C1 = CFrame.Angles(-math.pi / 2, 0, -math.pi)

		---Hips
		character.Torso["Right Hip"].C0 = CFrame.new(1, -1, 0) * CFrame.Angles(0, math.pi / 2, 0)
		character.Torso["Left Hip"].C0 = CFrame.new(-1, -1, 0) * CFrame.Angles(0, -math.pi / 2, 0)

		---Shoulders
		character.Torso["Right Shoulder"].C0 = CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0)
		character.Torso["Left Shoulder"].C0 = CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0)

		---Heads
		character.Torso["Neck"].C0 = CFrame.new(0, 1, 0) * CFrame.Angles(-math.pi / 2, 0, -math.pi)
	end)

	character.HumanoidRootPart.CFrame = CFrame.new(character.HumanoidRootPart.Position + vector.create(0, 1.75, 0))
		* CFrame.Angles(0, math.rad(oldRotation.Y), 0)
	playerStates:SetAttribute("NoRotation", 0)
	--humanoid.AutoRotate = true;
end

return Ragdoller
