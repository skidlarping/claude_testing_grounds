local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packages = ReplicatedStorage.Packages
local Signal = require(packages.Signal)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local frames = {}
local stack = {}

local UIController = {}

UIController.ScreenOpened = Signal.new()
UIController.ScreenClosed = Signal.new()

function UIController:Open(name: string): boolean
	local frame = frames[name]

	if not frame then
		warn("UIController: Attempted to open unregistered frame \"" .. name .. "\"")

		return false
	end

	if table.find(stack, name) then
		return false
	end

	table.insert(stack, name)

	frame.Visible = true

	self.ScreenOpened:Fire(name)

	return true
end

function UIController:Close(name: string): boolean
	local frame = frames[name]

	if not frame then
		warn("UIController: Attempted to close unregistered frame \"" .. name .. "\"")

		return false
	end

	local index = table.find(stack, name)

	if not index then
		return false
	end

	table.remove(stack, index)

	frame.Visible = false

	self.ScreenClosed:Fire(name)

	return true
end

function UIController:CloseAll()
	for i = #stack, 1, -1 do
		self:Close(stack[i])
	end
end

function UIController:IsOpen(name: string): boolean
	return table.find(stack, name) ~= nil
end

function UIController:GetTopScreen(): string?
	return stack[#stack]
end

function UIController:GetFrame(name: string): Frame?
	return frames[name]
end

function UIController:Init()
	local main = playerGui:WaitForChild("Main")
	local container = main:WaitForChild("Frames")

	for _, frame in container:GetChildren() do
		frames[frame.Name] = frame

		frame.Visible = false
	end
end

return UIController
