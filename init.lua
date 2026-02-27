local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

assert(RunService:IsServer(), "[RemoteGuard] Server-only module!")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Constants = require(script.constants)
local Logger = require(script.logger)
local PlayerStore = require(script.playerStore)
local Validator = require(script.validator)

local LOG_LEVELS = Constants.LOG_LEVELS
local DEFAULT_BAN_DURATION = Constants.DEFAULT_BAN_DURATION
local CLIENT_TIMEOUT = Constants.CLIENT_TIMEOUT

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function resolveRemote(remoteOrName, className)
	if type(remoteOrName) == "string" then
		local found = ReplicatedStorage:FindFirstChild(remoteOrName, true)
		if found then
			assert(found:IsA(className), `[RemoteGuard] '{remoteOrName}' exists but is not a {className}`)
			return found
		end

		local remote = Instance.new(className)
		remote.Name = remoteOrName
		remote.Parent = ReplicatedStorage
		Logger.write(LOG_LEVELS.INFO, remoteOrName, nil, "{className} not found - created in ReplicatedStorage")
		return remote
	end

	return remoteOrName
end

local RemoteGuard = {}

---Wraps a RemoteEvent with full protection (cooldown, rate-limit, permissions, type checks).
---'remote' can be a RemoteEvent instance or a string name - if the remote doesn't exist it will be created in ReplicatedStorage.
---Returns the 'RBXScriptConnection' - disconnect it to stop listening.
---@param remote RemoteEvent | string
---@param config {name: string?, cooldown: number?, rateLimit: number?, rateWindow: number?, banDuration: number?, timeout: number?, permission: (fun(player: Player): boolean)?, args: {type: string, required: boolean?}[]?}
---@param handler fun(player: Player, ...: any)
---@return RBXScriptConnection
function RemoteGuard.wrapEvent(remote, config, handler)
	remote = resolveRemote(remote, "RemoteEvent")
	assert(remote:IsA("RemoteEvent"), "wrapEvent: expected RemoteEvent")
	assert(type(config) == "table", "wrapEvent: expected config table")
	assert(type(handler) == "function", "wrapEvent: expected handler function")

	config.name = config.name or remote.Name

	return remote.OnServerEvent:Connect(function(player, ...)
		local args = { ... }

		Validator.validate(config, player, args)
			:andThen(function()
				local ok, _ = pcall(handler, player, table.unpack(args))
				if not ok then
					Logger.write(LOG_LEVELS.ERROR, config.name, player, "Handler error: {tostring(err)}")
				end
			end)
			:catch(function() end)
	end)
end

---Wraps a RemoteFunction with full protection + automatic timeout.
---'remote' can be a RemoteFunction instance or a string name - if the remote doesn't exist it will be created in ReplicatedStorage.
---If the handler doesn't settle within 'config.timeout' seconds (default 10s), the invoke returns 'nil'.
---@param remote RemoteFunction | string
---@param config {name: string?, cooldown: number?, rateLimit: number?, rateWindow: number?, banDuration: number?, timeout: number?, permission: (fun(player: Player): boolean)?, args: {type: string, required: boolean?}[]?}
---@param handler fun(player: Player, ...: any): any
function RemoteGuard.wrapFunction(remote, config, handler)
	remote = resolveRemote(remote, "RemoteFunction")
	assert(remote:IsA("RemoteFunction"), "wrapFunction: expected RemoteFunction")
	assert(type(config) == "table", "wrapFunction: expected config table")
	assert(type(handler) == "function", "wrapFunction: expected handler function")

	config.name = config.name or remote.Name
	local timeout = config.timeout or CLIENT_TIMEOUT

	remote.OnServerInvoke = function(player, ...)
		local args = { ... }

		local result = Promise.race({
			Validator.validate(config, player, args):andThen(function()
				return Promise.new(function(resolve, reject)
					local ok, value = pcall(handler, player, table.unpack(args))
					if ok then
						resolve(value)
					else
						Logger.write(LOG_LEVELS.ERROR, config.name, player, `Handler error: {tostring(value)}`)
						reject("handler_error", value)
					end
				end)
			end),

			Promise.delay(timeout):andThen(function()
				return Promise.reject("timeout")
			end),
		})

		local ok, value = result:await()

		if not ok then
			if value == "timeout" then
				Logger.write(
					LOG_LEVELS.WARN,
					config.name,
					player,
					"Invoke timed out after {timeout}s - no client response."
				)
			end
			return nil
		end

		return value
	end
end

---Wraps a RemoteEvent and automatically fires a reply back to the client via 'replyRemote'.
---Both 'remote' and 'replyRemote' can be instances or string names - missing ones will be created in ReplicatedStorage.
---On success fires '(true, result)', on any failure fires '(false, reason, extra)'.
---@param remote RemoteEvent | string
---@param replyRemote RemoteEvent | string
---@param config {name: string?, cooldown: number?, rateLimit: number?, rateWindow: number?, banDuration: number?, permission: (fun(player: Player): boolean)?, args: {type: string, required: boolean?}[]?}
---@param handler fun(player: Player, ...: any): any
---@return RBXScriptConnection
function RemoteGuard.wrapEventWithReply(remote, replyRemote, config, handler)
	remote = resolveRemote(remote, "RemoteEvent")
	replyRemote = resolveRemote(replyRemote, "RemoteEvent")
	assert(remote:IsA("RemoteEvent"), "wrapEventWithReply: expected RemoteEvent (incoming)")
	assert(replyRemote:IsA("RemoteEvent"), "wrapEventWithReply: expected RemoteEvent (reply)")
	assert(type(config) == "table", "wrapEventWithReply: expected config table")
	assert(type(handler) == "function", "wrapEventWithReply: expected handler function")

	config.name = config.name or remote.Name

	return remote.OnServerEvent:Connect(function(player, ...)
		local args = { ... }

		Validator.validate(config, player, args)
			:andThen(function()
				return Promise.new(function(resolve, reject)
					local ok, result = pcall(handler, player, table.unpack(args))
					if ok then
						resolve(result)
					else
						reject("handler_error", result)
					end
				end)
			end)
			:andThen(function(result)
				replyRemote:FireClient(player, true, result)
			end)
			:catch(function(reason, extra)
				replyRemote:FireClient(player, false, reason, extra)
			end)
	end)
end

---Manually bans a player from a specific remote for 'duration' seconds.
---Defaults to 'DEFAULT_BAN_DURATION' (30s) if duration is not provided.
---@param player Player
---@param remoteName string
---@param duration number?
function RemoteGuard.ban(player, remoteName, duration)
	local ps = PlayerStore.get(player, remoteName)
	local d = duration or DEFAULT_BAN_DURATION
	ps.blocked = true
	ps.blockedUntil = now() + d
	Logger.write(LOG_LEVELS.BLOCKED, remoteName, player, "Manually banned for {d}s.")
end

---Removes the ban for a player on a specific remote and clears their call history.
---@param player Player
---@param remoteName string
function RemoteGuard.unban(player, remoteName)
	local ps = PlayerStore.get(player, remoteName)
	ps.blocked = false
	ps.callTimes = {}
	Logger.write(LOG_LEVELS.INFO, remoteName, player, "Manually unbanned.")
end

---Returns whether a player is currently banned on a specific remote.
---If banned, also returns the remaining seconds as a second value.
---@param player Player
---@param remoteName string
---@return boolean isBanned
---@return number? secondsRemaining
function RemoteGuard.isBanned(player, remoteName)
	local ps = PlayerStore.get(player, remoteName)
	if not ps.blocked then
		return false
	end
	local t = now()
	if t >= ps.blockedUntil then
		ps.blocked = false
		return false
	end
	return true, math.ceil(ps.blockedUntil - t)
end

return RemoteGuard
