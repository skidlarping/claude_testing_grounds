local Workspace = game:GetService("Workspace")

local KILL_BRICK_SIZE = Vector3.new(6, 1, 6)
local KILL_BRICK_POSITION = Vector3.new(0, 1, 0)
local KILL_BRICK_COLOR = Color3.fromRGB(170, 0, 0)

local killBrick = Instance.new("Part")
killBrick.Name = "KillBrick"
killBrick.Size = KILL_BRICK_SIZE
killBrick.Position = KILL_BRICK_POSITION
killBrick.Anchored = true
killBrick.Color = KILL_BRICK_COLOR
killBrick.Parent = Workspace

local touchedConnection = nil

touchedConnection = killBrick.Touched:Connect(function(hit)
	local char = hit.Parent
	local humanoid = char:FindFirstChild("Humanoid")

	if not humanoid then
		return
	end

	humanoid.Health = 0
end)
