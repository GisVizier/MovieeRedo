local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")

local Signal = require(ReplicatedStorage:WaitForChild("CoreUI"):WaitForChild("Signal"))
local Configs = ReplicatedStorage:WaitForChild("Configs")
local DialogueConfig = require(Configs:WaitForChild("DialogueConfig"))

local Dialogue = {}
Dialogue.__index = Dialogue

Dialogue._initialized = false
Dialogue._config = nil
Dialogue._soundFolder = nil
Dialogue._soundCache = {}
Dialogue._active = {}
Dialogue._subtitleHandler = nil
Dialogue._soundRouter = nil
Dialogue._voiceEnabled = true
Dialogue._subtitlesEnabled = true

Dialogue.onStart = Signal.new()
Dialogue.onLine = Signal.new()
Dialogue.onStop = Signal.new()
Dialogue.onFinish = Signal.new()

local function resolvePath(path: string): Instance?
	if typeof(path) ~= "string" or path == "" then
		return nil
	end
	local current: Instance = game
	for segment in string.gmatch(path, "[^/.]+") do
		local nextInstance = current:FindFirstChild(segment)
		if not nextInstance then
			return nil
		end
		current = nextInstance
	end
	return current
end

local function getMembersFromTeamData(teamData: {[any]: any}?): {any}
	if typeof(teamData) ~= "table" then
		return {}
	end
	if typeof(teamData.Members) == "table" then
		return teamData.Members
	end
	if typeof(teamData.Players) == "table" then
		return teamData.Players
	end
	if typeof(teamData.Team) == "table" then
		return teamData.Team
	end
	return teamData
end

local function isMemberValid(member: {[any]: any}?): boolean
	if typeof(member) ~= "table" then
		return false
	end
	if member.InGame == false then
		return false
	end
	if member.Alive == false then
		return false
	end
	return member.Character ~= nil
end

local function getMemberCharacter(member: {[any]: any}?): string?
	if typeof(member) ~= "table" then
		return nil
	end
	return member.Character or member.CharacterId or member.CharacterName
end

local function buildCharacterSet(members: {any}): {[string]: boolean}
	local set = {}
	for _, member in members do
		if isMemberValid(member) then
			local character = getMemberCharacter(member)
			if character then
				set[character] = true
			end
		end
	end
	return set
end

local function findMemberByCharacter(members: {any}, character: string?): {[any]: any}?
	if not character then
		return nil
	end
	for _, member in members do
		if isMemberValid(member) and getMemberCharacter(member) == character then
			return member
		end
	end
	return nil
end

local function getMemberKey(member: {[any]: any}?, fallback: string?): string
	if typeof(member) == "table" then
		if member.UserId then
			return tostring(member.UserId)
		end
		if member.Player and member.Player.UserId then
			return tostring(member.Player.UserId)
		end
		if member.Name then
			return tostring(member.Name)
		end
	end
	return fallback or "global"
end

local function resolveSound(soundRef: any, soundFolder: Instance?): Sound?
	if typeof(soundRef) == "Instance" then
		if soundRef:IsA("Sound") then
			return soundRef
		end
		local childSound = soundRef:FindFirstChildWhichIsA("Sound", true)
		if childSound then
			return childSound
		end
		return nil
	end
	if typeof(soundRef) == "number" then
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. tostring(soundRef)
		return sound
	end
	if typeof(soundRef) == "string" then
		if string.match(soundRef, "^rbxassetid://") then
			local sound = Instance.new("Sound")
			sound.SoundId = soundRef
			return sound
		end
		if soundFolder then
			local found = soundFolder:FindFirstChild(soundRef, true)
			if found and found:IsA("Sound") then
				return found
			end
		end
	end
	return nil
end

local function getPositionFromInstance(instance: Instance?): Vector3?
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		local primary = instance.PrimaryPart
		if primary then
			return primary.Position
		end
		local root = instance:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root.Position
		end
	end
	return nil
end

local function getListenerPosition(options: {[any]: any}?): Vector3?
	if options and typeof(options.listenerPosition) == "Vector3" then
		return options.listenerPosition
	end
	local players = game:GetService("Players")
	local localPlayer = players.LocalPlayer
	if localPlayer and localPlayer.Character then
		return getPositionFromInstance(localPlayer.Character)
	end
	return nil
end

local function getSpeakerPosition(member: {[any]: any}?): Vector3?
	if typeof(member) ~= "table" then
		return nil
	end
	local rig = member.Rig or member.CharacterInstance
	if typeof(rig) == "Instance" then
		return getPositionFromInstance(rig)
	end
	if member.Player and member.Player.Character then
		return getPositionFromInstance(member.Player.Character)
	end
	return nil
end

local function getPreferenceAttribute(name: string, fallback: boolean): boolean
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return fallback
	end
	local value = localPlayer:GetAttribute(name)
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

local function isVoiceEnabled(): boolean
	return getPreferenceAttribute("SettingsDialogueVoiceEnabled", Dialogue._voiceEnabled ~= false)
end

local function areSubtitlesEnabled(): boolean
	return getPreferenceAttribute("SettingsDialogueSubtitlesEnabled", Dialogue._subtitlesEnabled ~= false)
end

local function getSoundParent(member: {[any]: any}?, options: {[any]: any}?): Instance
	if options and options.soundParent and typeof(options.soundParent) == "Instance" then
		return options.soundParent
	end
	if options and options.maxDistance and options.maxDistance > 0 then
		local listenerPos = getListenerPosition(options)
		local speakerPos = getSpeakerPosition(member)
		if listenerPos and speakerPos then
			local distance = (listenerPos - speakerPos).Magnitude
			if distance > options.maxDistance then
				local camera = workspace.CurrentCamera
				if camera then
					return camera
				end
				return SoundService
			end
		end
	end
	if typeof(member) == "table" then
		local rig = member.Rig or member.CharacterInstance
		if typeof(rig) == "Instance" then
			return rig
		end
		if member.Player and member.Player.Character then
			return member.Player.Character
		end
	end
	return SoundService
end

local function getOutcomeTable(eventData: {[any]: any}?, outcome: string?): {[any]: any}?
	if typeof(eventData) ~= "table" then
		return nil
	end
	if outcome == nil or outcome == "" then
		return eventData
	end
	return eventData[outcome]
end

local function collectEntries(dialogues: {[any]: any}, event: string, outcome: string?, characterSet: {[string]: boolean}): {{[string]: any}}
	local entries = {}
	for character, charData in dialogues do
		if typeof(charData) ~= "table" then
			continue
		end
		local eventData = charData[event]
		local outcomeData = getOutcomeTable(eventData, outcome)
		if typeof(outcomeData) ~= "table" then
			continue
		end
		for key, entry in outcomeData do
			if typeof(entry) ~= "table" then
				continue
			end
			local needed = entry.CharactersNeeded
			local valid = true
			if typeof(needed) == "table" then
				for _, neededCharacter in needed do
					if not characterSet[neededCharacter] then
						valid = false
						break
					end
				end
			end
			if valid then
				table.insert(entries, {
					key = key,
					character = character,
					entry = entry,
				})
			end
		end
	end
	return entries
end

local function isSequencePlayable(sequence: {any}, soundFolder: Instance?): boolean
	for _, line in sequence do
		if typeof(line) ~= "table" then
			return false
		end
		local soundRef = line.SoundInstance
		if soundRef == nil then
			soundRef = line.SoundIntance
		end
		if soundRef ~= nil then
			local sound = resolveSound(soundRef, soundFolder)
			if not sound then
				return false
			end
		end
	end
	return true
end

local function getSequenceFromEntry(entry: {[any]: any}): {any}?
	if typeof(entry) ~= "table" then
		return nil
	end
	if typeof(entry.Dialogue) == "table" then
		return entry.Dialogue
	end
	return entry
end

function Dialogue.init(configOverride: {[any]: any}?): boolean
	if Dialogue._initialized then
		return true
	end
	Dialogue._initialized = true
	Dialogue._config = configOverride or DialogueConfig
	Dialogue.DialoguesSoundsPath = Dialogue._config.DialoguesSoundsPath
	Dialogue.Dialogues = Dialogue._config.Dialogues or {}
	Dialogue._soundFolder = resolvePath(Dialogue.DialoguesSoundsPath)
	return true
end

function Dialogue.setConfig(configOverride: {[any]: any}): boolean
	Dialogue._initialized = false
	Dialogue._config = configOverride
	return Dialogue.init(configOverride)
end

function Dialogue.getDialogue(character: string, event: string, outcome: string?, key: string?): {[any]: any}?
	Dialogue.init()
	local charData = Dialogue.Dialogues[character]
	if typeof(charData) ~= "table" then
		return nil
	end
	local eventData = charData[event]
	local outcomeData = getOutcomeTable(eventData, outcome)
	if typeof(outcomeData) ~= "table" then
		return nil
	end
	if key == nil then
		return outcomeData
	end
	return outcomeData[key]
end

function Dialogue.getSoundFolder(): Instance?
	Dialogue.init()
	if Dialogue._soundFolder and Dialogue._soundFolder.Parent then
		return Dialogue._soundFolder
	end
	Dialogue._soundFolder = resolvePath(Dialogue.DialoguesSoundsPath)
	return Dialogue._soundFolder
end

function Dialogue.setSubtitleHandler(handler: (({[any]: any}) -> ())?): boolean
	Dialogue._subtitleHandler = handler
	return true
end

function Dialogue.setSoundRouter(handler: ((Sound, {[any]: any}?, {[any]: any}?, {[any]: any}?) -> Sound?)?): boolean
	Dialogue._soundRouter = handler
	return true
end

function Dialogue.setVoiceEnabled(enabled: boolean): boolean
	Dialogue._voiceEnabled = enabled == true
	return true
end

function Dialogue.setSubtitlesEnabled(enabled: boolean): boolean
	Dialogue._subtitlesEnabled = enabled == true
	return true
end

function Dialogue.isVoiceEnabled(): boolean
	return isVoiceEnabled()
end

function Dialogue.areSubtitlesEnabled(): boolean
	return areSubtitlesEnabled()
end

function Dialogue.stopByKey(key: any): boolean
	if not key then
		return false
	end
	if typeof(key) == "Instance" and key:IsA("Player") then
		if key.UserId then
			key = tostring(key.UserId)
		elseif key.Name then
			key = key.Name
		end
	end
	local active = Dialogue._active[key]
	if not active then
		return false
	end
	active.cancelled = true
	if active.sound and active.sound:IsA("Sound") then
		pcall(function()
			active.sound:Stop()
		end)
	end
	Dialogue._active[key] = nil
	Dialogue.onStop:fire({key = key})
	return true
end

function Dialogue.isActive(key: any): boolean
	if not key then
		return false
	end
	if typeof(key) == "Instance" and key:IsA("Player") then
		if key.UserId then
			key = tostring(key.UserId)
		elseif key.Name then
			key = key.Name
		end
	end
	return Dialogue._active[key] ~= nil
end

function Dialogue.stopAll(): boolean
	for key in Dialogue._active do
		Dialogue.stopByKey(key)
	end
	return true
end

local function waitForSound(sound: Sound, token: {[any]: any}?, maxWait: number?)
	if not sound then
		return
	end
	local waited = 0
	local step = 0.05
	while sound.IsPlaying and (not token or not token.cancelled) do
		if maxWait and maxWait > 0 and waited >= maxWait then
			break
		end
		waited += step
		task.wait(step)
	end
end

local function playSoundInstance(sound: Sound?, member: {[any]: any}?, options: {[any]: any}?, token: {[any]: any}?): Sound?
	if not sound then
		return nil
	end
	if Dialogue._soundRouter then
		local routed = nil
		local ok, result = pcall(function()
			return Dialogue._soundRouter(sound, member, options, token)
		end)
		if ok then
			routed = result
		end
		if routed then
			if token then
				token.sound = routed
			end
			return routed
		end
	end
	local soundClone = sound:Clone()
	local parent = getSoundParent(member, options)
	soundClone.Parent = parent

	-- Wait for sound asset to load before playing (prevents silent playback)
	if not soundClone.IsLoaded then
		ContentProvider:PreloadAsync({ soundClone })
	end

	pcall(function()
		soundClone:Play()
	end)
	if token then
		token.sound = soundClone
	end
	return soundClone
end

local function fireLineEvent(line: {[any]: any}, member: {[any]: any}?, entry: {[any]: any}?, context: {[any]: any}?)
	if line.NoSubtitle == true or areSubtitlesEnabled() ~= true then
		return
	end
	local audience = "Self"
	if line.Speaker == true then
		audience = "Team"
	end
	Dialogue.onLine:fire({
		character = line.Character,
		text = line.DialogueText,
		speaker = line.Speaker,
		audience = audience,
		member = member,
		entry = entry,
		context = context,
	})
	if Dialogue._subtitleHandler then
		pcall(function()
			Dialogue._subtitleHandler({
				character = line.Character,
				text = line.DialogueText,
				speaker = line.Speaker,
				audience = audience,
				member = member,
				entry = entry,
				context = context,
			})
		end)
	end
end

local function cloneTableShallow(source: {[any]: any}?): {[any]: any}
	if typeof(source) ~= "table" then
		return {}
	end
	local copy = {}
	for key, value in source do
		copy[key] = value
	end
	return copy
end

local function buildLineContext(member: {[any]: any}?, options: {[any]: any}?): {[any]: any}
	local context = cloneTableShallow(options)
	local maxDistance = options and options.maxDistance or nil
	if maxDistance and maxDistance > 0 then
		local listenerPos = getListenerPosition(options)
		local speakerPos = getSpeakerPosition(member)
		if listenerPos and speakerPos then
			local distance = (listenerPos - speakerPos).Magnitude
			context.distance = distance
			context.outOfRange = distance > maxDistance
		end
	end
	return context
end

local function playSequence(sequence: {any}, members: {any}, entry: {[any]: any}?, context: {[any]: any}?, token: {[any]: any}?)
	local soundFolder = Dialogue.getSoundFolder()
	for _, line in sequence do
		if token and token.cancelled then
			return
		end
		if typeof(line) ~= "table" then
			return
		end
		local member = findMemberByCharacter(members, line.Character)
		if line.Character and not member then
			return
		end
		if member and not isMemberValid(member) then
			return
		end
		local soundRef = line.SoundInstance
		if soundRef == nil then
			soundRef = line.SoundIntance
		end
		local sound = resolveSound(soundRef, soundFolder)
		local lineContext = buildLineContext(member, context)
		fireLineEvent(line, member, entry, lineContext)
		local voiceEnabled = isVoiceEnabled()
		local soundClone = nil
		if voiceEnabled then
			soundClone = playSoundInstance(sound, member, lineContext, token)
		end
		if soundClone then
			local maxWait = nil
			if soundClone.Looped then
				if line.addWait and line.addWait > 0 then
					maxWait = line.addWait
				elseif soundClone.TimeLength > 0 then
					maxWait = soundClone.TimeLength
				end
			end
			waitForSound(soundClone, token, maxWait)
			pcall(function()
				soundClone:Stop()
			end)
			pcall(function()
				soundClone:Destroy()
			end)
		elseif not line.addWait or line.addWait <= 0 then
			if voiceEnabled then
				task.wait(5)
			else
				local dialogueText = tostring(line.DialogueText or "")
				local subtitleDuration = math.clamp(#dialogueText * 0.04, 1.2, 3.5)
				task.wait(subtitleDuration)
			end
		end
		if line.addWait and line.addWait > 0 then
			task.wait(line.addWait)
		end
		if line.Dialogue and typeof(line.Dialogue) == "table" then
			playSequence(line.Dialogue, members, entry, context, token)
		end
	end
end

function Dialogue.testRun(sequence: {any}): boolean
	if typeof(sequence) ~= "table" then
		return false
	end
	for _, line in sequence do
		if typeof(line) ~= "table" then
			return false
		end
		local name = line.Character or "Unknown"
		local text = line.DialogueText or ""
		if line.Dialogue and typeof(line.Dialogue) == "table" then
			Dialogue.testRun(line.Dialogue)
		end
	end
	return true
end

function Dialogue.playSequence(sequence: {any}, options: {[any]: any}?): boolean
	Dialogue.init()
	if typeof(sequence) ~= "table" then
		return false
	end
	local members = getMembersFromTeamData(options and options.teamData)
	local fallbackKey = options and options.fallbackKey or "global"
	local speakerKey = getMemberKey(options and options.speakerMember, fallbackKey)
	local override = options and options.override or false
	local active = Dialogue._active[speakerKey]
	if active then
		if override then
			Dialogue.stopByKey(speakerKey)
		else
			return false
		end
	end
	if not isSequencePlayable(sequence, Dialogue.getSoundFolder()) then
		return false
	end
	local token = {cancelled = false, sound = nil}
	Dialogue._active[speakerKey] = token
	Dialogue.onStart:fire({key = speakerKey, sequence = sequence, context = options})
	task.spawn(function()
		playSequence(sequence, members, nil, options, token)
		if not token.cancelled then
			Dialogue.onFinish:fire({key = speakerKey, sequence = sequence, context = options})
		end
		Dialogue._active[speakerKey] = nil
	end)
	return true
end

function Dialogue.playEntry(entry: {[any]: any}, options: {[any]: any}?): boolean
	Dialogue.init()
	local sequence = getSequenceFromEntry(entry)
	if typeof(sequence) ~= "table" then
		return false
	end
	if not isSequencePlayable(sequence, Dialogue.getSoundFolder()) then
		return false
	end
	return Dialogue.playSequence(sequence, options)
end

function Dialogue.play(character: string, event: string, outcome: string?, key: string?, options: {[any]: any}?): boolean
	Dialogue.init()
	local entry = Dialogue.getDialogue(character, event, outcome, key)
	if typeof(entry) ~= "table" then
		return false
	end
	local nextOptions = options or {}
	if typeof(entry) == "table" and entry.Override ~= nil then
		nextOptions.override = entry.Override
	end
	return Dialogue.playEntry(entry, nextOptions)
end

local function buildTeamDataFromCharacter(character: string): {[any]: any}
	return {
		Members = {
			{
				Character = character,
				Alive = true,
				InGame = true,
			},
		},
	}
end

function Dialogue.generate(target: any, event: string, outcome: string?, options: {[any]: any}?): boolean
	Dialogue.init()
	local teamData = nil
	if typeof(target) == "string" then
		teamData = buildTeamDataFromCharacter(target)
	elseif typeof(target) == "table" then
		teamData = target
	else
		return false
	end
	local members = getMembersFromTeamData(teamData)
	local characterSet = buildCharacterSet(members)
	local entries = collectEntries(Dialogue.Dialogues, event, outcome, characterSet)
	if #entries == 0 then
		return false
	end
	local tries = #entries
	while tries > 0 do
		local index = math.random(1, #entries)
		local chosen = entries[index]
		local entry = chosen.entry
		local sequence = getSequenceFromEntry(entry)
		if typeof(sequence) == "table" and isSequencePlayable(sequence, Dialogue.getSoundFolder()) then
			local speakerMember = findMemberByCharacter(members, chosen.character)
			local playOptions = options or {}
			playOptions.teamData = teamData
			playOptions.speakerMember = speakerMember
			playOptions.override = entry.Override == true
			playOptions.fallbackKey = chosen.character
			playOptions.entryKey = chosen.key
			playOptions.event = event
			playOptions.outcome = outcome
			return Dialogue.playEntry(entry, playOptions)
		end
		table.remove(entries, index)
		tries -= 1
	end
	return false
end

return Dialogue
