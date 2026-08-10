local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RobloxAnalyticsService = game:GetService("AnalyticsService")

local funnelSessions = {}

local AnalyticsService = {}

local function OnPlayerRemoving(player: Player)
	funnelSessions[player] = nil
end

function AnalyticsService:LogOnboardingStep(player: Player, step: number, stepName: string?)
	RobloxAnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
end

function AnalyticsService:StartFunnel(player: Player, funnelName: string)
	funnelSessions[player] = funnelSessions[player] or {}
	funnelSessions[player][funnelName] = HttpService:GenerateGUID(false)
end

function AnalyticsService:LogFunnelStep(player: Player, funnelName: string, step: number, stepName: string?)
	local sessions = funnelSessions[player]
	local sessionId = sessions and sessions[funnelName]

	if not sessionId then
		warn("Attempted to log a funnel step before starting the funnel: " .. funnelName)

		return
	end

	RobloxAnalyticsService:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName)
end

function AnalyticsService:LogEconomyEvent(
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType,
	currencyType: string,
	endingBalance: number,
	amount: number,
	transactionType: string,
	itemSku: string?
)
	RobloxAnalyticsService:LogEconomyEvent(player, flowType, currencyType, endingBalance, amount, transactionType, itemSku)
end

function AnalyticsService:LogProgressionStart(player: Player, pathName: string, level: number, levelName: string?)
	RobloxAnalyticsService:LogProgressionStartEvent(player, pathName, level, levelName)
end

function AnalyticsService:LogProgressionComplete(player: Player, pathName: string, level: number, levelName: string?)
	RobloxAnalyticsService:LogProgressionCompleteEvent(player, pathName, level, levelName)
end

function AnalyticsService:LogProgressionFail(player: Player, pathName: string, level: number, levelName: string?)
	RobloxAnalyticsService:LogProgressionFailEvent(player, pathName, level, levelName)
end

function AnalyticsService:Init()
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
end

return AnalyticsService
