local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxSoundService = game:GetService("SoundService")

local packages = ReplicatedStorage.Packages
local Net = require(packages.Net)

local ASSET_ID_PREFIX = "rbxassetid://"

local SoundController = {}

local function OnPlayLocalSound(soundId: number, volume: number)
	local sound = Instance.new("Sound")
	sound.SoundId = ASSET_ID_PREFIX .. soundId
	sound.Volume = volume

	RobloxSoundService:PlayLocalSound(sound)

	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

function SoundController:Init()
	Net:Connect("PlayLocalSound", OnPlayLocalSound)
end

return SoundController
