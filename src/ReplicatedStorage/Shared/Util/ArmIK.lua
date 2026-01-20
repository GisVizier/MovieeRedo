--[[
    ArmIK.lua - Universal arm IK for R6 rigs and viewmodels
    
    Auto-detects Motor6D arm joints and provides simple IK solving.
    Works with both first-person viewmodels and third-person character rigs.
]]

local function SolveArmIK(originCF, targetPos, l1, l2)
    local localized = originCF:PointToObjectSpace(targetPos)
    local l3 = localized.Magnitude
    local unit = l3 > 0.001 and localized.Unit or Vector3.new(0, -1, 0)
    
    -- Build plane CFrame oriented toward target
    local axis = Vector3.new(0, 0, -1):Cross(unit)
    local angle = math.acos(math.clamp(-unit.Z, -1, 1))
    local planeCF
    if axis.Magnitude > 0.001 then
        planeCF = originCF * CFrame.fromAxisAngle(axis.Unit, angle)
    else
        planeCF = originCF
    end
    
    -- Clamp to reachable range
    local minR = math.abs(l1 - l2)
    local maxR = l1 + l2
    if l3 < minR then
        return planeCF * CFrame.new(0, 0, minR - l3), -math.pi / 2, math.pi
    end
    if l3 > maxR then
        return planeCF, math.pi / 2, 0
    end
    
    -- Solve triangle using law of cosines
    local l1Sq, l2Sq, l3Sq = l1 * l1, l2 * l2, l3 * l3
    local a1 = -math.acos(math.clamp((-l2Sq + l1Sq + l3Sq) / (2 * l1 * l3), -1, 1))
    local a2 = math.acos(math.clamp((l2Sq - l1Sq + l3Sq) / (2 * l2 * l3), -1, 1))
    return planeCF, a1 + math.pi / 2, a2 - a1
end

local ArmIK = {}
ArmIK.__index = ArmIK

function ArmIK.new(model: Model)
    if not model then
        return nil
    end
    
    local self = setmetatable({}, ArmIK)
    self.Model = model
    self.Motors = {}
    self.OriginalC0 = {}
    self.ArmLengths = { Left = 1, Right = 1 }
    self.Enabled = true
    self._blendTarget = 1
    self._currentBlend = 0
    
    -- Auto-detect Motor6Ds for arms (works for R6 rigs and viewmodels)
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("Motor6D") and desc.Part1 then
            local name = desc.Part1.Name
            if name == "Left Arm" then
                self.Motors["Left"] = desc
                self.OriginalC0["Left"] = desc.C0
                self.ArmLengths["Left"] = desc.Part1.Size.Y * 0.5
            elseif name == "Right Arm" then
                self.Motors["Right"] = desc
                self.OriginalC0["Right"] = desc.C0
                self.ArmLengths["Right"] = desc.Part1.Size.Y * 0.5
            end
        end
    end
    
    -- Check if we found any arm motors
    if not self.Motors["Left"] and not self.Motors["Right"] then
        return nil
    end
    
    return self
end

function ArmIK:SetEnabled(enabled: boolean)
    self._blendTarget = enabled and 1 or 0
end

function ArmIK:SolveArm(side: string, targetPos: Vector3, blend: number?)
    local motor = self.Motors[side]
    if not motor or not motor.Part0 then
        return
    end
    
    blend = blend or self._currentBlend
    if blend < 0.01 then
        return
    end
    
    local l = self.ArmLengths[side]
    local originCF = motor.Part0.CFrame * motor.C0
    
    -- Add slight side offset for more natural arm angle
    local sideOffset = side == "Left" and Vector3.new(0.1, 0, 0) or Vector3.new(-0.1, 0, 0)
    local adjustedTarget = targetPos + sideOffset
    
    local planeCF, shoulderAngle, elbowAngle = SolveArmIK(originCF, adjustedTarget, l, l)
    
    -- Calculate final arm CFrame
    local shoulderCF = planeCF * CFrame.Angles(shoulderAngle, 0, 0)
    local upperArmCF = shoulderCF * CFrame.new(0, -l, 0)
    local elbowCF = upperArmCF * CFrame.Angles(elbowAngle, 0, 0)
    local handCF = elbowCF * CFrame.new(0, -l * 0.5, 0)
    
    -- Convert world CFrame to C0
    local newC0 = motor.Part0.CFrame:Inverse() * handCF * motor.C1
    
    -- Blend between original animation and IK
    motor.C0 = self.OriginalC0[side]:Lerp(newC0, blend)
end

function ArmIK:PointAt(targetPos: Vector3, blend: number?, foregrip: number?)
    if not self.Enabled then
        return
    end
    
    blend = blend or self._currentBlend
    foregrip = foregrip or 0.3 -- How far forward the left hand is (foregrip offset)
    
    -- Right hand goes to main target (grip)
    self:SolveArm("Right", targetPos, blend)
    
    -- Left hand goes to foregrip position (slightly forward and left)
    local forwardOffset = (targetPos - self.Model:GetPivot().Position).Unit * foregrip
    local leftTarget = targetPos + Vector3.new(-0.25, 0.05, 0) + forwardOffset
    self:SolveArm("Left", leftTarget, blend * 0.8) -- Slightly less blend for secondary hand
end

function ArmIK:Update(dt: number)
    -- Smooth blend transition
    local blendSpeed = 8
    self._currentBlend = self._currentBlend + (self._blendTarget - self._currentBlend) * math.min(dt * blendSpeed, 1)
end

function ArmIK:Reset()
    for side, motor in pairs(self.Motors) do
        if motor and self.OriginalC0[side] then
            motor.C0 = self.OriginalC0[side]
        end
    end
    self._currentBlend = 0
end

function ArmIK:Destroy()
    self:Reset()
    self.Motors = {}
    self.OriginalC0 = {}
end

return ArmIK
