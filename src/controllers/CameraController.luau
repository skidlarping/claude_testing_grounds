local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local packages = ReplicatedStorage.Packages
local Signal = require(packages.Signal)

local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local controllers = playerScripts:WaitForChild("Controllers")
local InputController = require(controllers.InputController)

local DEFAULT_FIELD_OF_VIEW = 70

local camera = workspace.CurrentCamera
local player = Players.LocalPlayer

local currentOwner = nil
local savedState = nil
local renderConnection = nil

local CameraController = {}

CameraController.OwnerChanged = Signal.new()

local function CaptureDefaultState()
	return {
		CameraType = Enum.CameraType.Custom,
		CameraSubject = player.Character,
		FieldOfView = DEFAULT_FIELD_OF_VIEW,
	}
end

local function ApplyState(state)
	camera.CameraType = state.CameraType
	camera.CameraSubject = state.CameraSubject
	camera.FieldOfView = state.FieldOfView
end

local function DisconnectRender()
	if not renderConnection then
		return
	end

	renderConnection:Disconnect()
	renderConnection = nil
end

function CameraController:Request(owner: string): boolean
	if currentOwner then
		warn("CameraController: Request for \"" .. owner .. "\" denied, \"" .. currentOwner .. "\" already holds the camera")

		return false
	end

	currentOwner = owner
	savedState = CaptureDefaultState()

	InputController:Suspend(owner)

	self.OwnerChanged:Fire(currentOwner)

	return true
end

function CameraController:Release(owner: string)
	if currentOwner ~= owner then
		warn("CameraController: Release from \"" .. owner .. "\" ignored, current owner is \"" .. tostring(currentOwner) .. "\"")

		return
	end

	DisconnectRender()

	if savedState then
		ApplyState(savedState)
	end

	InputController:Resume(owner)

	savedState = nil
	currentOwner = nil

	self.OwnerChanged:Fire(nil)
end

function CameraController:SetRenderHandler(owner: string, handler: (number) -> ())
	if currentOwner ~= owner then
		warn("CameraController: SetRenderHandler from \"" .. owner .. "\" ignored, current owner is \"" .. tostring(currentOwner) .. "\"")

		return
	end

	DisconnectRender()

	camera.CameraType = Enum.CameraType.Scriptable

	renderConnection = RunService.RenderStepped:Connect(handler)
end

function CameraController:GetOwner(): string?
	return currentOwner
end

function CameraController:IsLocked(): boolean
	return currentOwner ~= nil
end

function CameraController:Init()
	camera = workspace.CurrentCamera
end

return CameraController
