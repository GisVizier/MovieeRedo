local Airborne = {}

Airborne.Ability = {}

function Airborne.Ability.AbilityActivated(_props)
	-- Hook VFX for Cloudskip start here.
end

function Airborne.Ability.AbilityEnded(_props)
	-- Hook VFX for Cloudskip end here.
end

function Airborne.Ability.AbilityInterrupted(_props)
	-- Hook VFX for Cloudskip cancel here.
end

Airborne.Ultimate = {}

function Airborne.Ultimate.AbilityActivated(_props)
	-- Hook VFX for Hurricane start here.
end

function Airborne.Ultimate.AbilityEnded(_props)
	-- Hook VFX for Hurricane end here.
end

function Airborne.Ultimate.AbilityInterrupted(_props)
	-- Hook VFX for Hurricane cancel here.
end

return Airborne
