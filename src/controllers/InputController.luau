local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packages = ReplicatedStorage.Packages
local Signal = require(packages.Signal)

local owners = {}
local bindings = {}
local suspendedBy = nil
local suspendedBindings = {}

local InputController = {}

InputController.ActionBound = Signal.new()
InputController.ActionUnbound = Signal.new()

function InputController:Bind(owner: string, actionName: string, handler: (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult?, createTouchButton: boolean, ...: Enum.KeyCode | Enum.UserInputType): boolean
	if suspendedBy and suspendedBy ~= owner then
		warn("InputController: Bind for \"" .. actionName .. "\" denied, input is suspended by \"" .. suspendedBy .. "\"")

		return false
	end

	local existingOwner = owners[actionName]

	if existingOwner then
		warn("InputController: Bind for \"" .. actionName .. "\" denied, \"" .. existingOwner .. "\" already owns it")

		return false
	end

	owners[actionName] = owner
	bindings[actionName] = { Owner = owner, Handler = handler, CreateTouchButton = createTouchButton, Args = table.pack(...) }

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
	bindings[actionName] = nil

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

function InputController:Suspend(owner: string): boolean
	if suspendedBy then
		warn("InputController: Suspend for \"" .. owner .. "\" denied, already suspended by \"" .. suspendedBy .. "\"")

		return false
	end

	suspendedBy = owner
	suspendedBindings = {}

	for actionName, binding in bindings do
		if binding.Owner == owner then
			continue
		end

		table.insert(suspendedBindings, { ActionName = actionName, Binding = binding })

		ContextActionService:UnbindAction(actionName)

		owners[actionName] = nil
		bindings[actionName] = nil
	end

	return true
end

function InputController:Resume(owner: string)
	if suspendedBy ~= owner then
		warn("InputController: Resume from \"" .. owner .. "\" ignored, suspended by \"" .. tostring(suspendedBy) .. "\"")

		return
	end

	for _, entry in suspendedBindings do
		local binding = entry.Binding

		owners[entry.ActionName] = binding.Owner
		bindings[entry.ActionName] = binding

		ContextActionService:BindAction(entry.ActionName, binding.Handler, binding.CreateTouchButton, table.unpack(binding.Args))
	end

	suspendedBindings = {}
	suspendedBy = nil
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
