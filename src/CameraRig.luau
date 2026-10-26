-- Over-the-shoulder follow camera: trailing pivot, shoulder swap, aim zoom, soft collision, recentre.
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Config = require(script.Parent.Config)
local Spring = require(script.Parent.Spring)
local Input = require(script.Parent.Input)

local CameraRig = { yaw = 0, pitch = 0, aimBlend = 0 }

local camera, root, params, crosshair
local pivot, aimBlend, side
local sideTarget = 1
local dist, distVel = 0, 0
local bodyParts = {}

local function makeCrosshair()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RDRCrosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BackgroundTransparency = 1
	dot.BorderSizePixel = 0
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	dot.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return dot
end

function CameraRig.init(character)
	local c = Config.Camera
	root = character:WaitForChild("HumanoidRootPart")
	camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable

	local look = root.CFrame.LookVector
	CameraRig.yaw = math.atan2(-look.X, -look.Z)
	CameraRig.pitch = math.rad(c.RestPitch)
	pivot = Spring.new(root.Position, c.FollowTime)
	aimBlend = Spring.new(0, c.AimTime)
	side = Spring.new(sideTarget, c.SwapTime)
	dist, distVel = c.Offset.Magnitude, 0

	params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	table.clear(bodyParts)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(bodyParts, part)
		end
	end
	crosshair = crosshair or makeCrosshair()
end

function CameraRig.update(dt, loco, anim)
	if not root or not root.Parent then
		return
	end
	local c = Config.Camera
	camera.CameraType = Enum.CameraType.Scriptable
	if not Input.touch then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end

	CameraRig.yaw -= Input.look.X
	CameraRig.pitch = math.clamp(CameraRig.pitch - Input.look.Y, math.rad(c.PitchMin), math.rad(c.PitchMax))

	-- drift back behind the character once the player stops steering the camera
	if loco.speed > 1 and not Input.aim and os.clock() - Input.lastLookTime > c.RecenterDelay then
		local k = 1 - math.exp(-dt / c.RecenterTime)
		CameraRig.yaw += Spring.angleDiff(CameraRig.yaw, loco.facingYaw) * k
		CameraRig.pitch += (math.rad(c.RestPitch) - CameraRig.pitch) * k
	end
	if Input.consumeSwap() then
		sideTarget = -sideTarget
	end

	local a = aimBlend:update(Input.aim and 1 or 0, dt)
	CameraRig.aimBlend = a
	local s = side:update(sideTarget, dt)
	local off = c.Offset:Lerp(c.AimOffset, a)
	local stride = math.clamp(loco.speed / Config.Speeds.Sprint, 0, 1)
	local bob = math.sin(anim.stridePhase * math.pi * 4) * c.BobAmount * stride * (1 - a)

	local yawCF = CFrame.Angles(0, CameraRig.yaw, 0)
	local rot = CFrame.fromEulerAnglesYXZ(CameraRig.pitch, CameraRig.yaw, 0)
	local origin = pivot:update(root.Position, dt) + Vector3.new(0, off.Y + bob, 0)
	local focus = origin + yawCF.RightVector * off.X * s
	local toCam = focus - rot.LookVector * off.Z - origin

	-- pull in fast when something blocks the view, ease back out slowly, never sit behind the wall
	local allowed = toCam.Magnitude
	local hit = workspace:Spherecast(origin, c.CollisionRadius, toCam, params)
	if hit then
		allowed = math.max(hit.Distance, 0.3)
	end
	dist, distVel = Spring.damp(dist, allowed, distVel, allowed < dist and c.PullInTime or c.EaseOutTime, dt)
	dist = math.min(dist, allowed)

	camera.CFrame = CFrame.new(origin + toCam.Unit * dist) * rot.Rotation
	camera.Focus = CFrame.new(focus)
	camera.FieldOfView = c.Fov + (c.AimFov - c.Fov) * a

	local fade = math.clamp(1 - (dist - 0.6), 0, 1)
	for _, part in bodyParts do
		part.LocalTransparencyModifier = fade
	end
	crosshair.BackgroundTransparency = 1 - a * 0.85
end

return CameraRig
