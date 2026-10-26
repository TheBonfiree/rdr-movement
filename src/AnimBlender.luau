-- Replaces the default Animate script: speed-weighted idle/walk/jog/run blend with stride-matched playback.
local Config = require(script.Parent.Config)
local Spring = require(script.Parent.Spring)

local AnimBlender = { stridePhase = 0, idleWeight = 1, strideScale = 1 }

local DEFAULTS = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://913402848",
	run = "rbxassetid://913376220",
	jog = "rbxassetid://913376220",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
	climb = "rbxassetid://507765644",
}
-- where each animation lives inside the avatar's own Animate script, so animation packs carry over
local SLOTS = {
	idle = { "idle", "Animation1" },
	walk = { "walk", "WalkAnim" },
	run = { "run", "RunAnim" },
	jog = { "run", "RunAnim" }, -- no jog in Animate packs; an empty jog slot reuses the run
	jump = { "jump", "JumpAnim" },
	fall = { "fall", "FallAnim" },
	climb = { "climb", "ClimbAnim" },
}

local humanoid, root
local tracks = {}
local weights = {}
local conns = {}

local function readId(animate, name)
	local custom = Config.Animations[name]
	if custom and custom ~= "" then
		return tonumber(custom) and "rbxassetid://" .. custom or custom
	end
	local folder = animate and animate:FindFirstChild(SLOTS[name][1])
	local anim = folder and folder:FindFirstChild(SLOTS[name][2])
	if anim and anim:IsA("Animation") and anim.AnimationId ~= "" then
		return anim.AnimationId
	end
	return DEFAULTS[name]
end

local function length(track)
	return track.Length > 0 and track.Length or 1
end

function AnimBlender.init(character)
	for _, conn in conns do
		conn:Disconnect()
	end
	table.clear(conns)
	humanoid = character:WaitForChild("Humanoid")
	root = character:WaitForChild("HumanoidRootPart")
	local animator = humanoid:WaitForChild("Animator")

	local animate = character:FindFirstChild("Animate")
	local ids = {}
	for name in SLOTS do
		ids[name] = readId(animate, name)
	end
	if animate then
		animate.Enabled = false
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop(0)
	end

	table.clear(tracks)
	for name, id in ids do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local track = animator:LoadAnimation(anim)
		local loco = name == "idle" or name == "walk" or name == "jog" or name == "run"
		track.Priority = loco and Enum.AnimationPriority.Core or Enum.AnimationPriority.Movement
		track.Looped = loco or name == "fall" or name == "climb"
		tracks[name] = track
	end
	for _, name in { "idle", "walk", "jog", "run" } do
		weights[name] = Spring.new(name == "idle" and 1 or 0, Config.Anim.BlendTime)
		tracks[name]:Play(0.2, math.max(weights[name].value, 1e-3), name == "idle" and Config.Anim.IdleSpeed or 1)
	end

	local S = Enum.HumanoidStateType
	table.insert(conns, humanoid.StateChanged:Connect(function(_, new)
		if new == S.Jumping then
			tracks.fall:Stop(0.1)
			tracks.jump:Play(0.1)
		elseif new == S.Freefall then
			tracks.fall:Play(0.3)
		elseif new == S.Climbing then
			tracks.climb:Play(0.2)
		else
			if new == S.Landed or new == S.Running or new == S.RunningNoPhysics then
				tracks.jump:Stop(0.15)
				tracks.fall:Stop(0.15)
			end
			if tracks.climb.IsPlaying then
				tracks.climb:Stop(0.2)
			end
		end
	end))
end

function AnimBlender.update(dt, loco)
	if not humanoid or not root.Parent then
		return
	end
	local cfg = Config.Anim
	-- taller avatars take longer strides, so normalise to the default R15 the native speeds were measured on
	local r = loco.speed / math.max(humanoid.HipHeight / 2.19, 0.25)
	local idle = math.clamp(1 - r / cfg.IdleFadeSpeed, 0, 1)
	-- crossfade by gear (walk to jog between walk and jog speed, jog to run between jog and sprint);
	-- native speeds only set playback rate
	local speeds = Config.Speeds
	local jogMix = math.clamp((loco.speed - speeds.Walk) / (speeds.Jog - speeds.Walk), 0, 1)
	local runMix = math.clamp((loco.speed - speeds.Jog) / (speeds.Sprint - speeds.Jog), 0, 1)

	local walk, jog, run = tracks.walk, tracks.jog, tracks.run
	local wasMoving = weights.jog.value + weights.run.value
	local wIdle = weights.idle:update(idle, dt)
	local wWalk = weights.walk:update((1 - idle) * (1 - jogMix), dt)
	local wJog = weights.jog:update((1 - idle) * jogMix * (1 - runMix), dt)
	local wRun = weights.run:update((1 - idle) * jogMix * runMix, dt)
	AnimBlender.idleWeight = wIdle

	-- one shared cycle rate keeps all the legs in phase while they crossfade
	local jogNative = Config.Animations.jog ~= "" and cfg.JogNativeSpeed or cfg.RunNativeSpeed
	local walkRate = math.max(r / cfg.WalkNativeSpeed, cfg.MinTimewarp) / length(walk)
	local jogRate = math.max(r / jogNative, cfg.MinTimewarp) / length(jog)
	local runRate = math.max(r / cfg.RunNativeSpeed, cfg.MinTimewarp) / length(run)
	-- ProceduralLayer lengthens the stride at speed, so the cycle slows by the same factor
	local strideT = math.clamp((loco.speed - speeds.Walk) / (speeds.Sprint - speeds.Walk), 0, 1)
	AnimBlender.strideScale = 1 + (cfg.StrideScaleMax - 1) * strideT
	local stepRate = jogMix < 1 and walkRate + (jogRate - walkRate) * jogMix or jogRate + (runRate - jogRate) * runMix
	local rate = stepRate / AnimBlender.strideScale
	if wasMoving < 0.01 and wJog + wRun >= 0.01 then
		local phase = walk.TimePosition / length(walk)
		jog.TimePosition = phase * length(jog)
		run.TimePosition = phase * length(run)
	end
	walk:AdjustSpeed(rate * length(walk))
	jog:AdjustSpeed(rate * length(jog))
	run:AdjustSpeed(rate * length(run))
	tracks.idle:AdjustWeight(math.max(wIdle, 1e-3), 0)
	walk:AdjustWeight(math.max(wWalk, 1e-3), 0)
	jog:AdjustWeight(math.max(wJog, 1e-3), 0)
	run:AdjustWeight(math.max(wRun, 1e-3), 0)
	AnimBlender.stridePhase = walk.TimePosition / length(walk)

	if tracks.climb.IsPlaying then
		tracks.climb:AdjustSpeed(root.AssemblyLinearVelocity.Y / 5)
	end
end

return AnimBlender
