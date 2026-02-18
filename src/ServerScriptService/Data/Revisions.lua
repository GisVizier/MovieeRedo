--[[
	Revisions: schema migrations and redaction.
	- IsRedacted(pathKey): return true to strip a key from saved data
	- GetNewName(key, pathKey): return new key name for renames, or key to keep
]]

local Revisions = {}

function Revisions.IsRedacted(key: string, pathKey: string): boolean
	return false
end

function Revisions.GetNewName(key: string, pathKey: string): string
	return key
end

return Revisions
