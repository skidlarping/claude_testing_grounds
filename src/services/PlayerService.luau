local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local services = ServerScriptService.Services
local DataService = require(services.DataService)

local packages = ReplicatedStorage.Packages
local Signal = require(packages.Signal)

local playerStates = {}

local PlayerService = {}

PlayerService.PlayerReady = Signal.new()
PlayerService.PlayerLeaving = Signal.new()

local function OnDataLoaded(player: Player, data: any)
	playerStates[player] = {
		JoinTime = os.time(),
	}

	PlayerService.PlayerReady:Fire(player, data)
end

local function OnDataReleasing(player: Player, data: any)
	PlayerService.PlayerLeaving:Fire(player, data)

	playerStates[player] = nil
end

function PlayerService:IsReady(player: Player): boolean
	return playerStates[player] ~= nil
end

function PlayerService:GetJoinTime(player: Player): number?
	local state = playerStates[player]

	if not state then
		return nil
	end

	return state.JoinTime
end

function PlayerService:GetSessionLength(player: Player): number?
	local state = playerStates[player]

	if not state then
		return nil
	end

	return os.time() - state.JoinTime
end

function PlayerService:Init()
	DataService.DataLoaded:Connect(OnDataLoaded)
	DataService.DataReleasing:Connect(OnDataReleasing)
end

return PlayerService
