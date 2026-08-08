local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")

local services = ServerScriptService.Services
local DataService = require(services.DataService)

local PRODUCT_HANDLERS = {}

local ProductService = {}

local function ProcessReceipt(receiptInfo: any)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)

	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not DataService:Get(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local handler = PRODUCT_HANDLERS[receiptInfo.ProductId]

	if not handler then
		warn("No handler registered for product: " .. receiptInfo.ProductId)

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local success = pcall(handler, player)

	if not success then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ProductService:Prompt(player: Player, productId: number)
	MarketplaceService:PromptProductPurchase(player, productId)
end

function ProductService:Init()
	MarketplaceService.ProcessReceipt = ProcessReceipt
end

return ProductService
