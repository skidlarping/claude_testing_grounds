local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")

local services = ServerScriptService.Services
local DataService = require(services.DataService)

local GAMEPASS_HANDLERS = {}

local ownedGamepasses = {}

local GamepassService = {}

local function CheckOwnership(player: Player, gamepassId: number): boolean
	local success, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, gamepassId)

	if not success then
		return false
	end

	return owns
end

local function RunHandler(player: Player, gamepassId: number)
	local handler = GAMEPASS_HANDLERS[gamepassId]

	if not handler then
		return
	end

	ownedGamepasses[player][gamepassId] = true

	pcall(handler, player)
end

local function OnDataLoaded(player: Player, _: any)
	ownedGamepasses[player] = {}

	for gamepassId in GAMEPASS_HANDLERS do
		if not CheckOwnership(player, gamepassId) then
			continue
		end

		RunHandler(player, gamepassId)
	end
end

local function OnPlayerRemoving(player: Player)
	ownedGamepasses[player] = nil
end

local function OnPromptGamePassPurchaseFinished(player: Player, gamepassId: number, purchased: boolean)
	if not purchased then
		return
	end

	ownedGamepasses[player] = ownedGamepasses[player] or {}

	RunHandler(player, gamepassId)
end

function GamepassService:Owns(player: Player, gamepassId: number): boolean
	local owned = ownedGamepasses[player]

	if not owned then
		return false
	end

	return owned[gamepassId] == true
end

function GamepassService:Prompt(player: Player, gamepassId: number)
	MarketplaceService:PromptGamePassPurchase(player, gamepassId)
end

function GamepassService:Init()
	DataService.DataLoaded:Connect(OnDataLoaded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(OnPromptGamePassPurchaseFinished)
end

return GamepassService
