local Players = game:GetService("Players")

local limits = {}
local records = {}

local RateLimitService = {}

local function GetRecord(player: Player, key: string)
	records[player] = records[player] or {}

	local record = records[player][key]

	if not record then
		record = { Count = 0, StartTime = os.clock() }
		records[player][key] = record
	end

	return record
end

local function OnPlayerRemoving(player: Player)
	records[player] = nil
end

function RateLimitService:Register(key: string, maxCalls: number, window: number)
	limits[key] = { MaxCalls = maxCalls, Window = window }
end

function RateLimitService:Check(player: Player, key: string): boolean
	local limit = limits[key]

	if not limit then
		warn("Attempted to check an unregistered rate limit key: " .. key)

		return false
	end

	local record = GetRecord(player, key)

	if os.clock() - record.StartTime >= limit.Window then
		record.Count = 0
		record.StartTime = os.clock()
	end

	if record.Count >= limit.MaxCalls then
		return false
	end

	record.Count += 1

	return true
end

function RateLimitService:Init()
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
end

return RateLimitService
