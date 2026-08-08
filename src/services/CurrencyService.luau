local ServerScriptService = game:GetService("ServerScriptService")

local services = ServerScriptService.Services
local DataService = require(services.DataService)

local BASE_CASH = 0
local BASE_CASH_MULTIPLIER = 1

local CurrencyService = {}

local function ClampCash(amount: number): number
	return math.max(BASE_CASH, amount)
end

local function ClampMultiplier(amount: number): number
	return math.max(BASE_CASH_MULTIPLIER, amount)
end

local function OnDataLoaded(_: Player, data: any)
	data.Cash = ClampCash(data.Cash or BASE_CASH)
	data.CashMultiplier = ClampMultiplier(data.CashMultiplier or BASE_CASH_MULTIPLIER)
end

function CurrencyService:GetCash(player: Player): number
	local data = DataService:Get(player)

	if not data then
		return BASE_CASH
	end

	return data.Cash
end

function CurrencyService:SetCash(player: Player, amount: number)
	local data = DataService:Get(player)

	if not data then
		warn("Attempted to set cash for a player with no loaded data: " .. player.Name)

		return
	end

	data.Cash = ClampCash(amount)
end

function CurrencyService:AddCash(player: Player, amount: number)
	local data = DataService:Get(player)

	if not data then
		warn("Attempted to add cash for a player with no loaded data: " .. player.Name)

		return
	end

	data.Cash = ClampCash(data.Cash + amount * data.CashMultiplier)
end

function CurrencyService:GetCashMultiplier(player: Player): number
	local data = DataService:Get(player)

	if not data then
		return BASE_CASH_MULTIPLIER
	end

	return data.CashMultiplier
end

function CurrencyService:SetCashMultiplier(player: Player, amount: number)
	local data = DataService:Get(player)

	if not data then
		warn("Attempted to set cash multiplier for a player with no loaded data: " .. player.Name)

		return
	end

	data.CashMultiplier = ClampMultiplier(amount)
end

function CurrencyService:AddCashMultiplier(player: Player, amount: number)
	local data = DataService:Get(player)

	if not data then
		warn("Attempted to add cash multiplier for a player with no loaded data: " .. player.Name)

		return
	end

	data.CashMultiplier = ClampMultiplier(data.CashMultiplier + amount)
end

function CurrencyService:Init()
	DataService.DataLoaded:Connect(OnDataLoaded)
end

return CurrencyService
