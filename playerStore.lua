local Players = game:GetService("Players")

-- store[userId][remoteName] = { lastCall, callTimes, perSecTimes, blocked, blockedUntil }
local store = {}

Players.PlayerRemoving:Connect(function(player)
	store[player.UserId] = nil
end)

local PlayerStore = {}

---Returns (or lazily creates) the state entry for a player + remote pair.
---@param player Player
---@param remoteName string
---@return { lastCall: number, callTimes: { number }, perSecTimes: { number }, blocked: boolean, blockedUntil: number }
function PlayerStore.get(player, remoteName)
	local uid = player.UserId

	if not store[uid] then
		store[uid] = {}
	end

	if not store[uid][remoteName] then
		store[uid][remoteName] = {
			lastCall = 0,
			callTimes = {},
			perSecTimes = {},
			blocked = false,
			blockedUntil = 0,
		}
	end

	return store[uid][remoteName]
end

---Clears the entire state for a player (called automatically on PlayerRemoving).
---@param player Player
function PlayerStore.clear(player)
	store[player.UserId] = nil
end

return PlayerStore
