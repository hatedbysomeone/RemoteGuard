local Constants = require(script.Parent.constants)
local LOG_LEVELS = Constants.LOG_LEVELS

local WARN_LEVELS = {
	[LOG_LEVELS.ERROR] = true,
	[LOG_LEVELS.SPAM] = true,
	[LOG_LEVELS.BLOCKED] = true,
}

local Logger = {}

---Writes a formatted log line to the output.
---Uses 'warn()' for ERROR / SPAM / BLOCKED, 'print()' for everything else.
---@param level string - one of Constants.LOG_LEVELS
---@param remoteName string
---@param player Player?
---@param msg string
function Logger.write(level, remoteName, player, msg)
	local playerName = player and player.Name or "server"
	local line = `[RemoteGuard][{level}] <{remoteName}> [{playerName}] {msg}`

	if WARN_LEVELS[level] then
		warn(line)
	else
		print(line)
	end
end

return Logger
