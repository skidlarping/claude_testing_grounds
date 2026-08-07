local ServerScriptService = game:GetService("ServerScriptService")
local services = ServerScriptService.Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local packages = ReplicatedStorage.Packages

local Net = require(packages.Net)
local ServerLog = Net:RemoteEvent("ServerLog")

local SUCCESS = true

for _, service in services:GetChildren() do
	if not service:IsA("ModuleScript") then
		SUCCESS = false

		ServerLog:FireAllClients(
			service.Name.." is not a ModuleScript",
			"Warn"
		)

		continue
	end

	task.spawn(function()
		local success, err = pcall(function()
			require(service):Init()
		end)

		if not success then
			SUCCESS = false

			ServerLog:FireAllClients(
				err,
				"Warn"
			)
		end
	end)
end

if SUCCESS then
	game:GetService("Players").PlayerAdded:Connect(function(player)
		ServerLog:FireClient(
			player,
			"All Services Initialized",
			"Print"
		)
	end)
end