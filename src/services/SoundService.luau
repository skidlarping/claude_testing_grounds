local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxSoundService = game:GetService("SoundService")

local packages = ReplicatedStorage.Packages
local Net = require(packages.Net)

local CONFIG = {
	DEFAULT_VOLUME = 1,
	MAX_VOLUME = 10,
	SOUND_LIFETIME = 30,
	ASSET_ID_PREFIX = "rbxassetid://",
}

local playLocalSound = Net:RemoteEvent("PlayLocalSound")

local SoundService = {}

local function IsValidSoundId(soundId: number): boolean
	return typeof(soundId) == "number" and soundId > 0
end

local function BuildSound(soundId: number, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = CONFIG.ASSET_ID_PREFIX .. soundId
	sound.Volume = volume

	return sound
end

local function CleanupSound(sound: Sound)
	sound.Ended:Once(function()
		sound:Destroy()
	end)

	task.delay(CONFIG.SOUND_LIFETIME, function()
		sound:Destroy()
	end)
end

function SoundService:PlayGlobal(soundId: number, volume: number?)
	if not IsValidSoundId(soundId) then
		warn("Attempted to play an invalid global sound id: " .. tostring(soundId))

		return
	end

	local clampedVolume = math.clamp(volume or CONFIG.DEFAULT_VOLUME, 0, CONFIG.MAX_VOLUME)
	local sound = BuildSound(soundId, clampedVolume)

	sound.Parent = RobloxSoundService
	sound:Play()

	CleanupSound(sound)
end

function SoundService:PlayLocal(player: Player, soundId: number, volume: number?)
	if not IsValidSoundId(soundId) then
		warn("Attempted to play an invalid local sound id: " .. tostring(soundId))

		return
	end

	local clampedVolume = math.clamp(volume or CONFIG.DEFAULT_VOLUME, 0, CONFIG.MAX_VOLUME)

	playLocalSound:FireClient(player, soundId, clampedVolume)
end

function SoundService:Init() end

return SoundService
