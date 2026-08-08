local PlayerScripts = game:GetService("Players").LocalPlayer.PlayerScripts
local controllers = PlayerScripts:WaitForChild("Controllers")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local packages = ReplicatedStorage.Packages

local SUCCESS = true
local SERVER_PREFIX = "[ServerToClient]: "

local Net = require(packages.Net)

Net:RemoteEvent("ServerLog").OnClientEvent:Connect(function(message, messageType)
	if messageType == "Print" then
		print(SERVER_PREFIX..message)
	elseif messageType == "Warn" then
		warn(SERVER_PREFIX..message)
	elseif messageType == "Error" then
		error(SERVER_PREFIX..message)
	end
end)

for _, controller in controllers:GetChildren() do
	if not controller:IsA("ModuleScript") then
		SUCCESS = false

		warn("[Client]: "..controller.Name.." is not a ModuleScript")

		continue
	end

	task.spawn(function()
		local success, err = pcall(function()
			require(controller):Init()
		end)

		if not success then
			SUCCESS = false

			warn("[Client]: "..err)
		end
	end)
end

if SUCCESS then
	print("[Client]: ".."All Controllers Initialized")
end