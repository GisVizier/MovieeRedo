local AnimationIds = {}

AnimationIds.Enum = {
	IdleStanding = 1,
	IdleCrouching = 2,
	CrouchWalking = 4, -- Deprecated, kept for network compatibility
	SlidingForward = 5,
	SlidingLeft = 6,
	SlidingRight = 7,
	SlidingBackward = 8,
	Jump = 9,
	JumpCancel1 = 10,
	JumpCancel2 = 11,
	JumpCancel3 = 12,
	Falling = 13,
	WalkingForward = 14,
	WalkingLeft = 15,
	WalkingRight = 16,
	WalkingBackward = 17,
	CrouchWalkingForward = 18,
	CrouchWalkingLeft = 19,
	CrouchWalkingRight = 20,
	CrouchWalkingBackward = 21,
	WallBoostForward = 22,
	WallBoostLeft = 23,
	WallBoostRight = 24,
}

AnimationIds.Names = {}
for name, id in pairs(AnimationIds.Enum) do
	AnimationIds.Names[id] = name
end

function AnimationIds:GetId(name)
	return self.Enum[name]
end

function AnimationIds:GetName(id)
	return self.Names[id]
end

return AnimationIds
