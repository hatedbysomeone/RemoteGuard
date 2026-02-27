local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Constants = require(script.Parent.constants)
local Logger = require(script.Parent.logger)
local TypeChecker = require(script.Parent.typeChecker)
local PlayerStore = require(script.Parent.playerStore)

local LOG_LEVELS = Constants.LOG_LEVELS
local DEFAULT_COOLDOWN = Constants.DEFAULT_COOLDOWN
local DEFAULT_RATE_LIMIT = Constants.DEFAULT_RATE_LIMIT
local DEFAULT_RATE_WINDOW = Constants.DEFAULT_RATE_WINDOW
local DEFAULT_BAN_DURATION = Constants.DEFAULT_BAN_DURATION
local DEFAULT_PER_SEC_LIMIT = Constants.DEFAULT_PER_SEC_LIMIT

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function purge(list, t, window)
	local fresh = {}
	for _, t0 in ipairs(list) do
		if t - t0 < window then
			fresh[#fresh + 1] = t0
		end
	end
	return fresh
end

local Validator = {}

---Runs every check (ban -> per-second flood -> cooldown -> permission -> arg types -> rate-limit) in order.
---Resolves with no value if all checks pass.
---Rejects with '(reason: string, extra: any?)' on the first failure.
---@param config table
---@param player Player
---@param args table
---@return Promise
function Validator.validate(config, player, args)
	return Promise.new(function(resolve, reject)
		local t = now()
		local ps = PlayerStore.get(player, config.name)

		local window = config.rateWindow or DEFAULT_RATE_WINDOW
		local limit = config.rateLimit or DEFAULT_RATE_LIMIT
		local banTime = config.banDuration or DEFAULT_BAN_DURATION
		local perSecLimit = config.perSecLimit or DEFAULT_PER_SEC_LIMIT

		-- 1. Ban check
		if ps.blocked then
			if t < ps.blockedUntil then
				local left = math.ceil(ps.blockedUntil - t)
				Logger.write(
					LOG_LEVELS.BLOCKED,
					config.name,
					player,
					`Player is banned. {left}s remaining. Stop spamming!`
				)
				return reject("blocked", left)
			end
			ps.blocked = false
			ps.callTimes = {}
			ps.perSecTimes = {}
		end

		-- 2. Per-second flood check - counts every incoming call within the last 1 second.
		-- Triggers ban if the player sends more than perSecLimit calls/sec regardless of validity.
		ps.perSecTimes = purge(ps.perSecTimes or {}, t, 1)
		ps.perSecTimes[#ps.perSecTimes + 1] = t

		if #ps.perSecTimes > perSecLimit then
			ps.blocked = true
			ps.blockedUntil = t + banTime
			Logger.write(
				LOG_LEVELS.SPAM,
				config.name,
				player,
				`FLOOD DETECTED - {#ps.perSecTimes} calls/sec (limit {perSecLimit}). Banned for {banTime}s!`
			)
			return reject("flood", banTime)
		end

		-- 3. Cooldown check
		local cooldown = config.cooldown or DEFAULT_COOLDOWN
		if cooldown > 0 then
			local elapsed = t - ps.lastCall
			if elapsed < cooldown then
				local remaining = math.floor((cooldown - elapsed) * 10) / 10
				Logger.write(LOG_LEVELS.WARN, config.name, player, `Cooldown active. {remaining}s remaining.`)
				return reject("cooldown", remaining)
			end
		end

		-- 4. Permission check
		if config.permission then
			local ok, result = pcall(config.permission, player)
			if not ok then
				Logger.write(LOG_LEVELS.ERROR, config.name, player, `permission() threw: {tostring(result)}`)
				return reject("permission_error")
			end
			if result == false then
				Logger.write(LOG_LEVELS.DENIED, config.name, player, "Permission denied.")
				return reject("no_permission")
			end
		end

		-- 5. Argument type check
		if config.args then
			for i, schema in ipairs(config.args) do
				local value = args[i]
				if value == nil then
					if schema.required ~= false then
						Logger.write(
							LOG_LEVELS.WARN,
							config.name,
							player,
							`Missing required argument #{i} ({tostring(schema.type)})`
						)
						return reject("missing_arg", i)
					end
				else
					local ok, err = TypeChecker.check(value, schema.type, `arg{i}`)
					if not ok then
						Logger.write(LOG_LEVELS.WARN, config.name, player, `Type mismatch: {err}`)
						return reject("bad_type", err)
					end
				end
			end
		end

		-- All checks passed - commit the call to rate-limit window
		ps.callTimes = purge(ps.callTimes, t, window)
		ps.callTimes[#ps.callTimes + 1] = t

		if #ps.callTimes >= limit then
			ps.blocked = true
			ps.blockedUntil = t + banTime
			Logger.write(
				LOG_LEVELS.SPAM,
				config.name,
				player,
				`SPAM DETECTED - {#ps.callTimes} valid calls in {window}s. Banned for {banTime}s!`
			)
			return reject("ratelimit", banTime)
		end

		ps.lastCall = t

		resolve()
	end)
end

return Validator
