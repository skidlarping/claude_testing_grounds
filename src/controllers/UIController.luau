local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packages = ReplicatedStorage.Packages
local Signal = require(packages.Signal)

local screens = {}
local stack = {}

local UIController = {}

UIController.ScreenOpened = Signal.new()
UIController.ScreenClosed = Signal.new()

local function SetScreenVisible(screen: ScreenGui | GuiObject, visible: boolean)
	if screen:IsA("ScreenGui") then
		screen.Enabled = visible

		return
	end

	screen.Visible = visible
end

function UIController:Register(name: string, screen: ScreenGui | GuiObject)
	if screens[name] then
		warn("UIController: \"" .. name .. "\" is already registered")

		return
	end

	screens[name] = screen

	SetScreenVisible(screen, false)
end

function UIController:Open(name: string): boolean
	local screen = screens[name]

	if not screen then
		warn("UIController: Attempted to open unregistered screen \"" .. name .. "\"")

		return false
	end

	if table.find(stack, name) then
		return false
	end

	table.insert(stack, name)

	SetScreenVisible(screen, true)

	self.ScreenOpened:Fire(name)

	return true
end

function UIController:Close(name: string): boolean
	local screen = screens[name]

	if not screen then
		warn("UIController: Attempted to close unregistered screen \"" .. name .. "\"")

		return false
	end

	local index = table.find(stack, name)

	if not index then
		return false
	end

	table.remove(stack, index)

	SetScreenVisible(screen, false)

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

function UIController:Init()
end

return UIController
