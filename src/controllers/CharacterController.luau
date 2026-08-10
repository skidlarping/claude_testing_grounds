local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packages = ReplicatedStorage.Packages
local Signal = require(packages.Signal)
local Trove = require(packages.Trove)

local DEFAULT_WALK_SPEED = 16
local DEFAULT_JUMP_POWER = 50

local player = Players.LocalPlayer
local characterTrove = Trove.new()

local CharacterController = {}

CharacterController.CharacterAdded = Signal.new()
CharacterController.CharacterRemoving = Signal.new()

local function ApplyDefaults(humanoid: Humanoid)
	humanoid.WalkSpeed = DEFAULT_WALK_SPEED
	humanoid.JumpPower = DEFAULT_JUMP_POWER
end

local function OnCharacterAdded(character: Model)
	characterTrove:Clean()

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	ApplyDefaults(humanoid)

	characterTrove:Connect(humanoid.Died, function()
		CharacterController.CharacterRemoving:Fire(character)
	end)

	CharacterController.CharacterAdded:Fire(character)
end

function CharacterController:GetCharacter(): Model?
	return player.Character
end

function CharacterController:GetHumanoid(): Humanoid?
	local character = player.Character

	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

function CharacterController:GetTrove(): typeof(characterTrove)
	return characterTrove
end

function CharacterController:Init()
	player.CharacterAdded:Connect(OnCharacterAdded)

	if player.Character then
		OnCharacterAdded(player.Character)
	end
end

return CharacterController
