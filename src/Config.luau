-- Every tunable for the RDR-style controller. Change the feel here, not in the modules.
return {
	Speeds = { Walk = 6, Jog = 10.5, Sprint = 17 }, -- studs per second; matched to the Rthro strides
	AccelTime = 0.55, -- seconds to ease up to a new speed
	DecelTime = 0.32, -- seconds to ease down; larger means a longer slide when stopping
	StickWalkThreshold = 0.55, -- thumbstick tilt below this walks, above it jogs

	TurnRateWalk = 420, -- degrees per second
	TurnRateSprint = 220, -- slower at speed, so the character arcs through turns
	AimTurnRate = 720,
	AirTurnFactor = 0.3,

	Jump = {
		Height = 3.2, -- studs at the apex, after the extra gravity below
		RiseGravity = 1.25, -- gravity multiplier on the way up (only on this character)
		FallGravity = 1.8, -- heavier on the way down, so the jump drops instead of floating
		Windup = 0.09, -- seconds of crouch before lift-off
		CrouchDip = 0.35, -- studs the pelvis drops during the windup
		Cooldown = 0.55, -- seconds after landing before the next jump
		LandSlowdown = 0.45, -- speed kept after a hard landing (1 = no slowdown)
		SoftLandSpeed = 55, -- fall speeds up to this (a normal hop) keep their momentum
		HardLandSpeed = 90, -- fall speed that counts as a full-hard landing (about a 12-stud drop)
	},
	PivotAngle = 135, -- reversing more than this at jog speed plants and pivots
	PivotBrakeTime = 0.12,
	PivotTurnRate = 900,
	TurnInPlaceAngle = 70, -- aiming while standing: the body steps round past this

	Camera = {
		Offset = Vector3.new(1.7, 2.3, 7.5), -- right, up, back from the root
		AimOffset = Vector3.new(1.5, 1.9, 5.5),
		Fov = 70,
		AimFov = 55,
		AimTime = 0.18,
		SwapTime = 0.22,
		FollowTime = 0.08, -- how far the camera trails the body
		RestPitch = -12, -- degrees
		PitchMin = -70,
		PitchMax = 60,
		MouseSensitivity = 0.0035, -- radians per pixel
		GamepadSensitivity = 4.2, -- radians per second at full tilt
		StickDeadzone = 0.15,
		TouchSensitivity = 0.006,
		CollisionRadius = 0.6,
		PullInTime = 0.03, -- snap in fast when a wall gets close
		EaseOutTime = 0.35, -- ease back out slowly
		RecenterDelay = 2, -- seconds without camera input before it drifts behind
		RecenterTime = 1.2,
		BobAmount = 0.06,
	},

	-- Your own published animation IDs (numbers or "rbxassetid://..."). Leave a slot as "" to use the
	-- avatar's own animation pack. Walk and run play at the native speeds below, so set those to the
	-- ground speed your custom cycles were animated at.
	-- Currently Roblox's Rthro pack (motion-capture style) with the adidas Community pack's idle (bundle 2623795).
	-- Other Roblox packs that load, with their measured native speeds: adidas walk 122150855457006 (4.1) /
	-- run 82598234841035 (7.7); Knight 657552124 (6.9) / 657564596 (8.4); Patrol 1151231493 (7.9) / 1150967949 (8.2);
	-- Werewolf 1083178339 (8.2) / 1083216690 (9.7); default R15 913402848 (6.4) / 913376220 (10.7).
	Animations = {
		idle = "122257458498464", -- adidas
		walk = "2510202577",
		run = "88834817239953", -- RDR Run v4 (R15run.blend): calmer hips, smooth arms, end frame repeats the first so the loop wraps clean
		jog = "100180477501663", -- RDR Jog v2 (R15run.blend), end frame repeats the first; empty: the run clip covers jog speed too
		jump = "2510197830",
		fall = "2510195892",
		climb = "2510192778",
	},

	Anim = {
		WalkNativeSpeed = 6.0, -- speed (on a default-height R15) where the walk cycle plays at 1x with no foot slide
		JogNativeSpeed = 10.1, -- only used once Animations.jog is set
		RunNativeSpeed = 15, -- measured for the RDR Run (Rthro run was 9.1)
		IdleFadeSpeed = 1.5,
		BlendTime = 0.2,
		MinTimewarp = 0.5,
		IdleSpeed = 0.8, -- calmer idle breathing
		StrideScaleMax = 1.0, -- leg swing at full sprint; the cycle slows by the same factor so feet don't slide.
		-- 1.35 suited the short Rthro run; the RDR Run already has a full stride, so stretching it read as lumbering
	},

	Procedural = {
		SmoothTime = 0.2, -- body follow-through; larger feels heavier
		HeadTime = 0.28,
		ArmStrideShare = 0.6, -- arms take this share of the longer stride, so they don't flail
		StepBob = 0, -- studs the pelvis dips on each footfall at full speed. 0: the RDR clips carry their own
		-- bounce, and this one is timed to the Rthro footfalls, so it fought the clip's landings
		TurnLean = 0.075, -- body roll per rad/s of turning once running; zero while walking
		MaxLean = 16, -- degrees
		AccelPitch = 0.0035, -- forward pitch per stud/s² of acceleration
		RunLean = 2, -- the RDR Run is already leaned well forward
		MaxPitch = 9,
		WaistTwist = 0.035,
		MaxTwist = 10,
		ChestShare = 0.3, -- share of the head look the chest takes
		HeadYawMax = 60,
		HeadPitchMax = 35,
		HeadIgnoreAngle = 110, -- camera in front of the face: head stops following
		BreathPeriod = 4,
		BreathAmount = 1.2,
		LandFullSpeed = 90, -- fall speed that gives the full landing dip
		LandDip = 0.9,
		LandRecoverTime = 0.18,
		FootIK = true,
		IKReach = 2,
		IKMaxSpeed = 2, -- foot IK only fades in when nearly standing still
		IKMinStep = 0.2, -- ...and only when the ground under the feet is uneven by at least this much (studs)
		IKMaxCorrection = 1.2, -- a foot needing a bigger lift or drop than this stays on the plain animation
		IKTolerance = 0.3, -- after solving, a foot still floating or sunk past this reverts to the animation...
		IKRetryTime = 1, -- ...and waits this many seconds before trying IK again
	},

	Keys = {
		Sprint = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 }, -- Shift holds; L3 and touch toggle
		Aim = { Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2 },
		Swap = { Enum.KeyCode.Q, Enum.KeyCode.ButtonR3 },
		WalkToggle = { Enum.KeyCode.CapsLock, Enum.KeyCode.DPadDown },
		Jump = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA },
	},

	Debug = false, -- mirrors gear, speed, move, sprint and pivot onto LocalPlayer attributes
}
