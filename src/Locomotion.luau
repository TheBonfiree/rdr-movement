-- Momentum-based movement: eased speed, limited turn rate, pivot turns and turn-in-place.
local Config = require(script.Parent.Config)
local Spring = require(script.Parent.Spring)
local Input = require(script.Parent.Input)

local Locomotion = {
	ready = false,
	speed = 0,
	accel = 0,
	facingYaw = 0,
	turnRate = 0, -- rad/s, positive = turning left
	gear = "Idle",
	grounded = true,
	pivoting = false,
	turningInPlace = false,
	crouchKick = 0, -- pelvis drop requested this frame; ProceduralLayer consumes it
}

local humanoid, root
local speedVel, turnRateVel = 0, 0
local lastDir = Vector3.new(0, 0, -1)
local gravityForce
local windup, cooldown, peakFall = 0, 0, 0

local function yawToVector(yaw)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

function Locomotion.init(character)
	humanoid = character:WaitForChild("Humanoid")
	root = character:WaitForChild("HumanoidRootPart")
	humanoid.AutoRotate = false
	-- JumpHeight assumes normal gravity; scale it so the apex lands on Jump.Height under the extra rise gravity
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = Config.Jump.Height * Config.Jump.RiseGravity
	local attachment = Instance.new("Attachment")
	attachment.Name = "RDR_Gravity"
	attachment.Parent = root
	gravityForce = Instance.new("VectorForce")
	gravityForce.Name = "RDR_Gravity"
	gravityForce.Attachment0 = attachment
	gravityForce.RelativeTo = Enum.ActuatorRelativeTo.World
	gravityForce.ApplyAtCenterOfMass = true
	gravityForce.Force = Vector3.zero
	gravityForce.Parent = root
	windup, cooldown, peakFall = 0, 0, 0
	local look = root.CFrame.LookVector
	Locomotion.facingYaw = math.atan2(-look.X, -look.Z)
	Locomotion.speed, Locomotion.accel, Locomotion.turnRate = 0, 0, 0
	speedVel, turnRateVel = 0, 0
	Locomotion.pivoting, Locomotion.turningInPlace = false, false
	Locomotion.ready = true
end

function Locomotion.update(dt, cam)
	if not humanoid or humanoid.Health <= 0 or not root.Parent or dt <= 0 then
		return
	end
	local speeds = Config.Speeds
	local move = Input.move
	local moving = move.Magnitude > 0.1
	local aiming = Input.aim
	local climbing = humanoid:GetState() == Enum.HumanoidStateType.Climbing
	local wasGrounded = Locomotion.grounded
	Locomotion.grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local jumpCfg = Config.Jump

	-- extra gravity on this character only: a little on the rise, more on the fall
	local vy = root.AssemblyLinearVelocity.Y
	local extra = 0
	if not Locomotion.grounded and not climbing then
		extra = (vy > 0 and jumpCfg.RiseGravity or jumpCfg.FallGravity) - 1
		peakFall = math.max(peakFall, -vy)
	end
	gravityForce.Force = Vector3.new(0, -root.AssemblyMass * workspace.Gravity * extra, 0)

	-- a hard landing costs speed, and the next jump waits for the cooldown
	if Locomotion.grounded and not wasGrounded then
		local impact = math.clamp((peakFall - jumpCfg.SoftLandSpeed) / (jumpCfg.HardLandSpeed - jumpCfg.SoftLandSpeed), 0, 1)
		Locomotion.speed *= 1 - impact * (1 - jumpCfg.LandSlowdown)
		speedVel = 0
		cooldown = jumpCfg.Cooldown
		peakFall = 0
	end
	cooldown = math.max(cooldown - dt, 0)

	local targetSpeed = 0
	if not moving then
		Locomotion.gear = "Idle"
	elseif Input.sprint and not aiming then
		Locomotion.gear, targetSpeed = "Sprint", speeds.Sprint
	elseif Input.walk or aiming or (Input.analog and move.Magnitude < Config.StickWalkThreshold) then
		Locomotion.gear, targetSpeed = "Walk", speeds.Walk
	else
		Locomotion.gear, targetSpeed = "Jog", speeds.Jog
	end

	local inputDir
	if moving then
		inputDir = CFrame.Angles(0, cam.yaw, 0):VectorToWorldSpace(Vector3.new(move.X, 0, -move.Y)).Unit
	else
		Locomotion.pivoting = false
	end

	local wantYaw
	if aiming then
		wantYaw = cam.yaw
	elseif inputDir then
		wantYaw = math.atan2(-inputDir.X, -inputDir.Z)
	end

	local step = 0
	if wantYaw then
		local diff = Spring.angleDiff(Locomotion.facingYaw, wantYaw)
		local absDiff = math.abs(diff)
		if not aiming and not Locomotion.pivoting and absDiff > math.rad(Config.PivotAngle) and Locomotion.speed > speeds.Jog * 0.8 then
			Locomotion.pivoting = true
		end
		-- standing aim: only step round once the camera swings far enough off the body
		if aiming and not moving then
			if absDiff > math.rad(Config.TurnInPlaceAngle) then
				Locomotion.turningInPlace = true
			elseif absDiff < math.rad(4) then
				Locomotion.turningInPlace = false
			end
		else
			Locomotion.turningInPlace = false
		end

		local rate
		if Locomotion.pivoting then
			-- brake first, then swing round once planted
			rate = Locomotion.speed > speeds.Walk and Config.TurnRateSprint * 0.3 or Config.PivotTurnRate
		elseif aiming then
			rate = (moving or Locomotion.turningInPlace) and Config.AimTurnRate or 0
		else
			local t = math.clamp((Locomotion.speed - speeds.Walk) / (speeds.Sprint - speeds.Walk), 0, 1)
			rate = Config.TurnRateWalk + (Config.TurnRateSprint - Config.TurnRateWalk) * t
		end
		if not Locomotion.grounded then
			rate *= Config.AirTurnFactor
		end
		local maxStep = math.rad(rate) * dt
		step = math.clamp(diff, -maxStep, maxStep)
		if Locomotion.pivoting and absDiff < math.rad(20) then
			Locomotion.pivoting = false
		end
	end
	Locomotion.facingYaw += step
	Locomotion.turnRate, turnRateVel = Spring.damp(Locomotion.turnRate, step / dt, turnRateVel, 0.08, dt)

	local smooth = targetSpeed > Locomotion.speed and Config.AccelTime or Config.DecelTime
	if Locomotion.pivoting then
		targetSpeed, smooth = speeds.Walk * 0.4, Config.PivotBrakeTime
	end
	if not Locomotion.grounded then
		targetSpeed = Locomotion.speed -- keep momentum through a jump
	end
	local lastSpeed = Locomotion.speed
	Locomotion.speed, speedVel = Spring.damp(Locomotion.speed, targetSpeed, speedVel, smooth, dt)
	Locomotion.accel = (Locomotion.speed - lastSpeed) / dt

	-- unaimed, the body runs where it faces (so turns arc); aimed, it strafes along the input
	if aiming then
		lastDir = inputDir or lastDir
	else
		lastDir = yawToVector(Locomotion.facingYaw)
	end
	if Locomotion.speed > 0.1 then
		humanoid.WalkSpeed = Locomotion.speed
		humanoid:Move(lastDir)
	else
		humanoid:Move(Vector3.zero)
	end
	-- crouch briefly, then leave the ground
	if Input.consumeJump() and Locomotion.grounded and cooldown <= 0 and windup <= 0 and not climbing then
		windup = jumpCfg.Windup
		Locomotion.crouchKick = jumpCfg.CrouchDip
	end
	if windup > 0 then
		windup -= dt
		if windup <= 0 and Locomotion.grounded then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
	if not climbing then
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, Locomotion.facingYaw, 0)
	end
end

return Locomotion
