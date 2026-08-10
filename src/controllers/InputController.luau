local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packages = ReplicatedStorage.Packages
local Signal = require(packages.Signal)

local owners = {}

local InputController = {}

InputController.ActionBound = Signal.new()
InputController.ActionUnbound = Signal.new()

function InputController:Bind(owner: string, actionName: string, handler: (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult?, createTouchButton: boolean, ...: Enum.KeyCode | Enum.UserInputType): boolean
	local existingOwner = owners[actionName]

	if existingOwner then
		warn("InputController: Bind for \"" .. actionName .. "\" denied, \"" .. existingOwner .. "\" already owns it")

		return false
	end

	owners[actionName] = owner

	ContextActionService:BindAction(actionName, handler, createTouchButton, ...)

	self.ActionBound:Fire(actionName, owner)

	return true
end

function InputController:Unbind(owner: string, actionName: string)
	local existingOwner = owners[actionName]

	if existingOwner ~= owner then
		warn("InputController: Unbind of \"" .. actionName .. "\" from \"" .. owner .. "\" ignored, current owner is \"" .. tostring(existingOwner) .. "\"")

		return
	end

	ContextActionService:UnbindAction(actionName)

	owners[actionName] = nil

	self.ActionUnbound:Fire(actionName, owner)
end

function InputController:UnbindAll(owner: string)
	for actionName, existingOwner in owners do
		if existingOwner ~= owner then
			continue
		end

		self:Unbind(owner, actionName)
	end
end

function InputController:GetOwner(actionName: string): string?
	return owners[actionName]
end

function InputController:IsBound(actionName: string): boolean
	return owners[actionName] ~= nil
end

function InputController:Init()
end

return InputController
