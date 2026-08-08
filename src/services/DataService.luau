local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packages = ReplicatedStorage.Packages
local shared = ReplicatedStorage.Shared

local Signal = require(packages.Signal)
local PlayerData = require(shared.Data.PlayerData)

local CONFIG = {
	DATASTORE_NAME = "PlayerData_v1",
	SAVE_ENABLED = true,
	MAX_RETRIES = 3,
	RETRY_DELAY = 2,
	SESSION_LOCK_TIMEOUT = 30,
	BIND_TO_CLOSE_TIMEOUT = 25,
}

local dataStore = DataStoreService:GetDataStore(CONFIG.DATASTORE_NAME)

local playerData = {}
local savingCount = 0

local DataService = {}

DataService.DataLoaded = Signal.new()
DataService.DataReleasing = Signal.new()

local function GetKey(player: Player): string
	return "Player_" .. player.UserId
end

local function Attempt(fn: () -> any): (boolean, any)
	for i = 1, CONFIG.MAX_RETRIES do
		local success, result = pcall(fn)

		if success then
			return true, result
		end

		if i < CONFIG.MAX_RETRIES then
			task.wait(CONFIG.RETRY_DELAY)
		end
	end

	return false, nil
end

local function ClaimSession(player: Player): (boolean, any)
	local key = GetKey(player)

	return Attempt(function()
		return dataStore:UpdateAsync(key, function(current)
			current = current or {}

			local lock = current.SessionLock

			if lock and lock.JobId ~= game.JobId and os.time() - lock.Time < CONFIG.SESSION_LOCK_TIMEOUT then
				error("Session locked by another server")
			end

			current.SessionLock = {
				JobId = game.JobId,
				Time = os.time(),
			}

			current.Data = current.Data or PlayerData.Default()

			return current
		end)
	end)
end

local function SaveData(player: Player, releaseLock: boolean): boolean
	if not CONFIG.SAVE_ENABLED then
		return true
	end

	local data = playerData[player]

	if not data then
		return false
	end

	local key = GetKey(player)

	local success = Attempt(function()
		dataStore:UpdateAsync(key, function(current)
			current = current or {}
			current.Data = data

			if releaseLock then
				current.SessionLock = nil
			end

			return current
		end)
	end)

	return success
end

local function OnPlayerAdded(player: Player)
	local success, result = ClaimSession(player)

	if not success then
		player:Kick("Failed to load your data, please rejoin")

		return
	end

	playerData[player] = result.Data

	DataService.DataLoaded:Fire(player, playerData[player])
end

local function OnPlayerRemoving(player: Player)
	DataService.DataReleasing:Fire(player, playerData[player])

	SaveData(player, true)

	playerData[player] = nil
end

function DataService:Get(player: Player)
	return playerData[player]
end

function DataService:Set(player: Player, data: any)
	playerData[player] = data
end

function DataService:Init()
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	game:BindToClose(function()
		if not CONFIG.SAVE_ENABLED then
			return
		end

		for player in playerData do
			savingCount += 1

			task.spawn(function()
				SaveData(player, true)

				savingCount -= 1
			end)
		end

		local start = os.clock()

		while savingCount > 0 and os.clock() - start < CONFIG.BIND_TO_CLOSE_TIMEOUT do
			task.wait()
		end
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(OnPlayerAdded, player)
	end
end

return DataService
