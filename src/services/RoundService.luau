local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packages = ReplicatedStorage.Packages
local Signal = require(packages.Signal)

local CONFIG = {
	MIN_PLAYERS = 2,
	INTERMISSION_TIME = 10,
	ROUND_TIME = 120,
	ENDING_TIME = 5,
}

local State = {
	Waiting = "Waiting",
	Intermission = "Intermission",
	InRound = "InRound",
	Ending = "Ending",
}

local currentState = State.Waiting
local currentVersion = 0
local currentTimeLeft = 0

local RoundService = {}

RoundService.State = State
RoundService.StateChanged = Signal.new()
RoundService.RoundStarting = Signal.new()
RoundService.RoundStarted = Signal.new()
RoundService.RoundEnded = Signal.new()
RoundService.Tick = Signal.new()

local function SetState(newState: string)
	local oldState = currentState
	currentState = newState
	currentVersion += 1

	RoundService.StateChanged:Fire(newState, oldState)
end

local function Countdown(duration: number, version: number): boolean
	currentTimeLeft = duration

	while currentTimeLeft > 0 and version == currentVersion do
		RoundService.Tick:Fire(currentState, currentTimeLeft)
		task.wait(1)
		currentTimeLeft -= 1
	end

	return version == currentVersion
end

local EnterWaiting
local EnterIntermission
local EnterInRound
local EnterEnding

EnterWaiting = function()
	SetState(State.Waiting)
end

EnterIntermission = function()
	SetState(State.Intermission)
	RoundService.RoundStarting:Fire()

	local version = currentVersion

	task.spawn(function()
		if not Countdown(CONFIG.INTERMISSION_TIME, version) then
			return
		end

		if #Players:GetPlayers() < CONFIG.MIN_PLAYERS then
			EnterWaiting()

			return
		end

		EnterInRound()
	end)
end

EnterInRound = function()
	SetState(State.InRound)
	RoundService.RoundStarted:Fire()

	local version = currentVersion

	task.spawn(function()
		if not Countdown(CONFIG.ROUND_TIME, version) then
			return
		end

		EnterEnding("TimeUp")
	end)
end

EnterEnding = function(reason: string?)
	SetState(State.Ending)
	RoundService.RoundEnded:Fire(reason)

	local version = currentVersion

	task.spawn(function()
		if not Countdown(CONFIG.ENDING_TIME, version) then
			return
		end

		if #Players:GetPlayers() >= CONFIG.MIN_PLAYERS then
			EnterIntermission()

			return
		end

		EnterWaiting()
	end)
end

local function OnPlayerAdded()
	if currentState ~= State.Waiting then
		return
	end

	if #Players:GetPlayers() < CONFIG.MIN_PLAYERS then
		return
	end

	EnterIntermission()
end

local function OnPlayerRemoving()
	local remaining = #Players:GetPlayers() - 1

	if currentState == State.Intermission and remaining < CONFIG.MIN_PLAYERS then
		EnterWaiting()

		return
	end

	if currentState == State.InRound and remaining <= 0 then
		RoundService:EndRound("Empty")
	end
end

function RoundService:GetState(): string
	return currentState
end

function RoundService:GetTimeLeft(): number
	return currentTimeLeft
end

function RoundService:EndRound(reason: string?)
	if currentState ~= State.InRound then
		return
	end

	EnterEnding(reason)
end

function RoundService:SkipIntermission()
	if currentState ~= State.Intermission then
		return
	end

	EnterInRound()
end

function RoundService:Init()
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	if #Players:GetPlayers() >= CONFIG.MIN_PLAYERS then
		EnterIntermission()
	end
end

return RoundService
