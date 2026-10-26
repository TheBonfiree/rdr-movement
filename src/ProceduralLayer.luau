-- Additive bone layer on top of the animations: turn lean, acceleration pitch, waist twist,
-- head look, breathing, landing dip and foot IK. Runs on Stepped, after the Animator writes Transform.
local Config = require(script.Parent.Config)
local Spring = require(script.Parent.Spring)

local ProceduralLayer = {}

-- joints whose swing gets scaled for longer strides: { part, joint, isArm }
local LIMBS = {
	{ "LeftUpperLeg", "LeftHip", false },
	{ "RightUpperLeg", "RightHip", false },
	{ "LeftLowerLeg", "LeftKnee", false },
	{ "RightLowerLeg", "RightKnee", false },
	{ "LeftUpperArm", "LeftShoulder", true },
	{ "RightUpperArm", "RightShoulder", true },
	{ "LeftLowerArm", "LeftElbow", true },
	{ "RightLowerArm", "RightElbow", true },
}

local humanoid, root, params
local joints = {}
local roll, pitch, twist, headYaw, headPitch, dip, drop
local feet = {}
local peakFall = 0
local clock = 0

function ProceduralLayer.init(character)
	for _, foot in feet do
		foot.control:Destroy()
		foot.target:Destroy()
	end
	table.clear(feet)
	humanoid = character:WaitForChild("Humanoid")
	root = character:WaitForChild("HumanoidRootPart")

	local function motor(partName, jointName)
		local part = character:WaitForChild(partName, 5)
		return part and part:FindFirstChild(jointName)
	end
	joints.root = motor("LowerTorso", "Root")
	joints.waist = motor("UpperTorso", "Waist")
	joints.neck = motor("Head", "Neck")
	joints.limbs = {}
	for _, spec in LIMBS do
		local joint = motor(spec[1], spec[2])
		if joint then
			table.insert(joints.limbs, { joint = joint, arm = spec[3] })
		end
	end

	local cfg = Config.Procedural
	roll, pitch, twist = Spring.new(0, cfg.SmoothTime), Spring.new(0, cfg.SmoothTime), Spring.new(0, cfg.SmoothTime)
	headYaw, headPitch = Spring.new(0, cfg.HeadTime), Spring.new(0, cfg.HeadTime)
	dip, drop = Spring.new(0, cfg.LandRecoverTime), Spring.new(0, 0.1)
	peakFall = 0

	params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	if cfg.FootIK then
		for _, side in { "Left", "Right" } do
			local upper = character:FindFirstChild(side .. "UpperLeg")
			local foot = character:FindFirstChild(side .. "Foot")
			if upper and foot then
				local target = Instance.new("Attachment")
				target.Name = "RDR_" .. side .. "FootTarget"
				target.Parent = workspace.Terrain
				local control = Instance.new("IKControl")
				control.Name = "RDR_" .. side .. "FootIK"
				control.Type = Enum.IKControlType.Transform -- position and rotation, so the foot stays flat
				control.ChainRoot = upper
				control.EndEffector = foot
				control.Target = target
				-- a pole in front of the knee keeps the solver from folding the leg backwards
				local pole = Instance.new("Attachment")
				pole.Name = "RDR_" .. side .. "KneePole"
				pole.Position = Vector3.new(side == "Left" and -0.5 or 0.5, -1.5, -3)
				pole.Parent = root
				control.Pole = pole
				control.Weight = 0
				control.Enabled = false
				control.Parent = humanoid
				table.insert(feet, { part = foot, control = control, target = target, weight = Spring.new(0, 0.15),
					restHeight = foot.Size.Y / 2, retry = 0, bad = 0,
					-- until the idle pose is recorded: under the hip, flat and pointing forward, resting on the ground
					restLocal = CFrame.new(root.CFrame:PointToObjectSpace(foot.Position).X,
						-(humanoid.HipHeight + root.Size.Y / 2) + foot.Size.Y / 2, 0) })
			end
		end
	end
end

-- Raise each foot onto the ground under it and drop the pelvis for the lower one. A foot falls back to the plain
-- animation (its IK weight fades to 0) on flat ground, when the correction would be bigger than IKMaxCorrection,
-- or when the solve leaves it floating or sunk past IKTolerance; a foot that failed waits IKRetryTime first.
local function footIK(dt, loco)
	local cfg = Config.Procedural
	local floor = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	local standing = loco.grounded and loco.speed < cfg.IKMaxSpeed
	local hits, uneven = {}, false
	for i, foot in feet do
		local p = (root.CFrame * foot.restLocal).Position -- where the animation puts this foot, not where IK left it
		hits[i] = workspace:Raycast(Vector3.new(p.X, floor + cfg.IKReach, p.Z), Vector3.new(0, -cfg.IKReach * 2, 0), params)
		if hits[i] and math.abs(hits[i].Position.Y - floor) > cfg.IKMinStep then
			uneven = true
		end
	end
	local lowest, active = 0, 0
	for i, foot in feet do
		local hit = hits[i]
		local p = foot.part.Position
		local delta = hit and hit.Position.Y - floor or 0
		foot.retry = math.max(foot.retry - dt, 0)
		-- on level ground with IK off, remember where the animation holds this foot (relative to the body, and how
		-- high above the ground) so IK keeps that placement instead of chasing its own last result
		if hit and standing and foot.weight.value < 0.01 and math.abs(delta) <= cfg.IKMinStep and not uneven then
			foot.restHeight = math.clamp(p.Y - hit.Position.Y, 0, 0.6)
			foot.restLocal = root.CFrame:ToObjectSpace(foot.part.CFrame)
		end
		local want = standing and uneven and hit ~= nil and math.abs(delta) <= cfg.IKMaxCorrection and foot.retry <= 0
		if want and foot.weight.value > 0.95 then
			local gap = (p.Y - hit.Position.Y) - foot.restHeight
			foot.bad = math.abs(gap) > cfg.IKTolerance and foot.bad + dt or 0
			if foot.bad > 0.25 then
				foot.retry, foot.bad, want = cfg.IKRetryTime, 0, false
			end
		end
		local w = foot.weight:update(want and 1 or 0, dt)
		foot.control.Weight = w
		foot.control.Enabled = w > 0.01
		if hit then
			local placed = root.CFrame * foot.restLocal
			local x, z = placed.Position.X, placed.Position.Z
			foot.target.WorldCFrame = CFrame.new(x, hit.Position.Y + foot.restHeight, z) * placed.Rotation
			lowest = math.min(lowest, delta * w)
		end
		active = math.max(active, w)
	end
	return drop:update(active > 0 and lowest or 0, dt)
end

function ProceduralLayer.update(dt, loco, cam, anim)
	if not humanoid or not joints.root or not root.Parent or humanoid.Health <= 0 then
		return
	end
	local cfg = Config.Procedural
	clock += dt
	local rad = math.rad

	-- jump windup crouch, then a landing dip that scales with how fast the character was falling
	if loco.crouchKick > 0 then
		dip.value -= loco.crouchKick
		loco.crouchKick = 0
	end
	if loco.grounded then
		if peakFall > 0 then
			dip.value -= math.clamp(peakFall / cfg.LandFullSpeed, 0, 1) * cfg.LandDip
			peakFall = 0
		end
	else
		peakFall = math.max(peakFall, -root.AssemblyLinearVelocity.Y)
	end

	local speedT = math.clamp(loco.speed / Config.Speeds.Sprint, 0, 1)
	-- turn lean fades in from walk to jog, so only running banks into direction changes
	local runT = math.clamp((loco.speed - Config.Speeds.Walk) / (Config.Speeds.Jog - Config.Speeds.Walk), 0, 1)
	local r = roll:update(math.clamp(loco.turnRate * cfg.TurnLean * runT, -rad(cfg.MaxLean), rad(cfg.MaxLean)), dt)
	local p = pitch:update(math.clamp(-loco.accel * cfg.AccelPitch - speedT * rad(cfg.RunLean), -rad(cfg.MaxPitch), rad(cfg.MaxPitch)), dt)
	local tw = twist:update(math.clamp(loco.turnRate * cfg.WaistTwist, -rad(cfg.MaxTwist), rad(cfg.MaxTwist)), dt)

	-- the head follows the camera unless the camera is in front of the face
	local lookYaw = Spring.angleDiff(loco.facingYaw, cam.yaw)
	local ignore = math.abs(lookYaw) > rad(cfg.HeadIgnoreAngle)
	local hy = headYaw:update(ignore and 0 or math.clamp(lookYaw, -rad(cfg.HeadYawMax), rad(cfg.HeadYawMax)), dt)
	local hp = headPitch:update(ignore and 0 or math.clamp(cam.pitch, -rad(cfg.HeadPitchMax), rad(cfg.HeadPitchMax)), dt)
	local breath = math.sin(clock * math.pi * 2 / cfg.BreathPeriod) * rad(cfg.BreathAmount) * anim.idleWeight

	-- longer strides at speed; arms take only part of it so they swing loose instead of flailing
	local stride = anim.strideScale
	if stride > 1.001 then
		for _, limb in joints.limbs do
			local t = limb.joint.Transform
			local axis, angle = t:ToAxisAngle()
			local s = limb.arm and 1 + (stride - 1) * cfg.ArmStrideShare or stride
			limb.joint.Transform = CFrame.new(t.Position) * CFrame.fromAxisAngle(axis, angle * s)
		end
	end

	-- weight: the pelvis sinks into each footfall (two per cycle)
	local stepBob = -cfg.StepBob * speedT * (0.5 + 0.5 * math.cos(anim.stridePhase * math.pi * 4)) * (1 - anim.idleWeight)
	local pelvis = dip:update(0, dt) + stepBob + (#feet > 0 and footIK(dt, loco) or 0)
	-- lean around the feet rather than the hips, so the legs stay planted
	local h = humanoid.HipHeight
	local lean = CFrame.new(0, -h, 0) * CFrame.Angles(p, 0, r) * CFrame.new(0, h, 0)
	joints.root.Transform = CFrame.new(0, pelvis, 0) * lean * joints.root.Transform

	local share = cfg.ChestShare
	if joints.waist then
		local aimPitch = cam.pitch * cam.aimBlend * 0.5
		joints.waist.Transform = CFrame.Angles(breath + hp * share + aimPitch, tw + hy * share, 0) * joints.waist.Transform
	end
	if joints.neck then
		joints.neck.Transform = CFrame.Angles(hp * (1 - share), hy * (1 - share), 0) * joints.neck.Transform
	end
end

return ProceduralLayer
