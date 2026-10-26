-- Wires the RDR-style controller together. Lives in StarterPlayerScripts.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("RDRMovement")
local Config = require(folder.Config)
local Input = require(folder.Input)
local Locomotion = require(folder.Locomotion)
local AnimBlender = require(folder.AnimBlender)
local ProceduralLayer = require(folder.ProceduralLayer)
local CameraRig = require(folder.CameraRig)

local player = Players.LocalPlayer
Input.init(player)

local function onCharacter(character)
	Locomotion.ready = false
	local humanoid = character:WaitForChild("Humanoid")
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn("RDRMovement needs R15 avatars (Game Settings > Avatar). Bone layers are off for this character.")
	end
	AnimBlender.init(character)
	ProceduralLayer.init(character)
	CameraRig.init(character)
	Locomotion.init(character)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- just after Input priority, so this frame's movement uses fresh input
RunService:BindToRenderStep("RDRMovement", Enum.RenderPriority.Input.Value + 1, function(dt)
	if not Locomotion.ready then
		return
	end
	Input.update(dt)
	Locomotion.update(dt, CameraRig)
	AnimBlender.update(dt, Locomotion)
	if Config.Debug then
		player:SetAttribute("RDR_Gear", Locomotion.gear)
		player:SetAttribute("RDR_Speed", Locomotion.speed)
		player:SetAttribute("RDR_Move", Input.move)
		player:SetAttribute("RDR_Sprint", Input.sprint)
		player:SetAttribute("RDR_Pivot", Locomotion.pivoting)
	end
end)

-- after the default camera scripts so nothing overwrites the shoulder view
RunService:BindToRenderStep("RDRCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if Locomotion.ready then
		CameraRig.update(dt, Locomotion, AnimBlender)
	end
end)

RunService.Stepped:Connect(function(_, dt)
	if Locomotion.ready then
		ProceduralLayer.update(dt, Locomotion, CameraRig, AnimBlender)
	end
end)

