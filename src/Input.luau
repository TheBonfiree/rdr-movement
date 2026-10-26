-- Merges keyboard/mouse, gamepad and touch into one per-frame input state.
-- Default movement must be off (StarterPlayer.DevComputerMovementMode and DevTouchMovementMode
-- = Scriptable), so this module reads the keys, sticks and touches itself and handles jumping.
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Config = require(script.Parent.Config)

local Input = {
	move = Vector2.zero, -- x = right, y = forward; magnitude 0..1
	look = Vector2.zero, -- radians this frame; x = turn right, y = look down
	analog = false, -- move came from a stick or the touch thumbstick
	touch = false,
	sprint = false,
	walk = false,
	aim = false,
	lastLookTime = 0,
}

local MOVE_KEYS = {
	{ Enum.KeyCode.W, Vector2.new(0, 1) },
	{ Enum.KeyCode.Up, Vector2.new(0, 1) },
	{ Enum.KeyCode.S, Vector2.new(0, -1) },
	{ Enum.KeyCode.Down, Vector2.new(0, -1) },
	{ Enum.KeyCode.A, Vector2.new(-1, 0) },
	{ Enum.KeyCode.Left, Vector2.new(-1, 0) },
	{ Enum.KeyCode.D, Vector2.new(1, 0) },
	{ Enum.KeyCode.Right, Vector2.new(1, 0) },
}
local THUMB_RADIUS = 60 -- pixels of drag for full tilt

local keysDown = {}
local leftStick, rightStick = Vector2.zero, Vector2.zero
local touchDelta = Vector2.zero
local panTouches = {}
local thumbTouch, thumbOrigin, thumbVector = nil, nil, Vector2.zero
local thumbGui, walkTag
local sprintHeld, sprintToggled = false, false
local aimHeld, aimToggled = false, false
local swapQueued, jumpQueued = false, false
local idleTime = 0

local function deadzone(v, dz)
	local m = v.Magnitude
	if m <= dz then
		return Vector2.zero
	end
	return v.Unit * math.min((m - dz) / (1 - dz), 1)
end

local function onSprint(_, state, inputObject)
	if inputObject.UserInputType == Enum.UserInputType.Touch or inputObject.KeyCode == Enum.KeyCode.ButtonL3 then
		if state == Enum.UserInputState.Begin then
			sprintToggled = not sprintToggled
		end
	else
		sprintHeld = state == Enum.UserInputState.Begin
	end
	return Enum.ContextActionResult.Pass
end

local function onAim(_, state, inputObject)
	if inputObject.UserInputType == Enum.UserInputType.Touch then
		if state == Enum.UserInputState.Begin then
			aimToggled = not aimToggled
		end
	else
		aimHeld = state == Enum.UserInputState.Begin
	end
	return Enum.ContextActionResult.Pass
end

local function onPress(flag)
	return function(_, state)
		if state == Enum.UserInputState.Begin then
			if flag == "swap" then
				swapQueued = true
			elseif flag == "jump" then
				jumpQueued = true
			else
				Input.walk = not Input.walk
				if walkTag then
					walkTag.Visible = Input.walk
				end
			end
		end
		return Enum.ContextActionResult.Pass
	end
end

-- Small "WALK" tag so the toggle state is visible.
local function makeWalkTag(player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RDRWalkTag"
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -24)
	label.Size = UDim2.fromOffset(72, 22)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.45
	label.TextColor3 = Color3.fromRGB(235, 225, 205)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.Text = "WALK"
	label.Visible = false
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 4)
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return label
end

-- A dynamic thumbstick: touch anywhere in the lower-left of the screen and drag.
local function makeThumbstick(player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RDRThumbstick"
	gui.ResetOnSpawn = false
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(THUMB_RADIUS * 2, THUMB_RADIUS * 2)
	ring.BackgroundColor3 = Color3.new(0, 0, 0)
	ring.BackgroundTransparency = 0.6
	ring.Visible = false
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(44, 44)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BackgroundTransparency = 0.3
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	knob.Parent = ring
	ring.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return ring
end

function Input.init(player)
	local keys = Config.Keys
	ContextActionService:BindAction("RDR_Sprint", onSprint, true, table.unpack(keys.Sprint))
	ContextActionService:BindAction("RDR_Aim", onAim, true, table.unpack(keys.Aim))
	ContextActionService:BindAction("RDR_Swap", onPress("swap"), true, table.unpack(keys.Swap))
	ContextActionService:BindAction("RDR_Jump", onPress("jump"), true, table.unpack(keys.Jump))
	ContextActionService:BindAction("RDR_Walk", onPress("walk"), false, table.unpack(keys.WalkToggle))
	ContextActionService:SetTitle("RDR_Sprint", "Run")
	ContextActionService:SetTitle("RDR_Aim", "Aim")
	ContextActionService:SetTitle("RDR_Swap", "Swap")
	ContextActionService:SetTitle("RDR_Jump", "Jump")
	ContextActionService:SetPosition("RDR_Jump", UDim2.new(1, -110, 1, -110))
	ContextActionService:SetPosition("RDR_Sprint", UDim2.new(1, -190, 1, -100))
	ContextActionService:SetPosition("RDR_Aim", UDim2.new(1, -120, 1, -190))
	ContextActionService:SetPosition("RDR_Swap", UDim2.new(1, -200, 1, -180))
	if UserInputService.TouchEnabled then
		thumbGui = makeThumbstick(player)
	end
	walkTag = makeWalkTag(player)

	-- key state from events, not IsKeyDown, and dropped when the window loses focus so keys never stick
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(keysDown)
	end)
	UserInputService.InputBegan:Connect(function(inputObject, processed)
		-- engine controls can mark WASD as processed even in Scriptable mode, so don't filter on it;
		-- typing in chat is handled by the focused-TextBox check in update
		if inputObject.UserInputType == Enum.UserInputType.Keyboard then
			keysDown[inputObject.KeyCode] = true
		end
		if inputObject.UserInputType ~= Enum.UserInputType.Touch or processed then
			return
		end
		local pos = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
		local view = workspace.CurrentCamera.ViewportSize
		if not thumbTouch and pos.X < view.X * 0.45 and pos.Y > view.Y * 0.4 then
			thumbTouch, thumbOrigin = inputObject, pos
			if thumbGui then
				thumbGui.Position = UDim2.fromOffset(pos.X, pos.Y)
				thumbGui.Knob.Position = UDim2.fromScale(0.5, 0.5)
				thumbGui.Visible = true
			end
		else
			panTouches[inputObject] = true
		end
	end)
	UserInputService.InputChanged:Connect(function(inputObject)
		if inputObject.KeyCode == Enum.KeyCode.Thumbstick1 then
			leftStick = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
		elseif inputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
			rightStick = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
		elseif inputObject == thumbTouch then
			local d = Vector2.new(inputObject.Position.X, inputObject.Position.Y) - thumbOrigin
			if d.Magnitude > THUMB_RADIUS then
				d = d.Unit * THUMB_RADIUS
			end
			thumbVector = Vector2.new(d.X, -d.Y) / THUMB_RADIUS
			if thumbGui then
				thumbGui.Knob.Position = UDim2.new(0.5, d.X, 0.5, d.Y)
			end
		elseif panTouches[inputObject] then
			touchDelta += Vector2.new(inputObject.Delta.X, inputObject.Delta.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(inputObject)
		keysDown[inputObject.KeyCode] = nil
		panTouches[inputObject] = nil
		if inputObject == thumbTouch then
			thumbTouch, thumbVector = nil, Vector2.zero
			if thumbGui then
				thumbGui.Visible = false
			end
		elseif inputObject.KeyCode == Enum.KeyCode.Thumbstick1 then
			leftStick = Vector2.zero
		elseif inputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
			rightStick = Vector2.zero
		end
	end)
end

function Input.update(dt)
	local cam = Config.Camera
	local move = Vector2.zero
	if not UserInputService:GetFocusedTextBox() then
		for _, entry in MOVE_KEYS do
			if keysDown[entry[1]] then
				move += entry[2]
			end
		end
	end
	local analog = false
	if move.Magnitude > 0 then
		move = move.Unit
	else
		local stick = deadzone(leftStick, cam.StickDeadzone)
		if thumbVector.Magnitude > stick.Magnitude then
			stick = deadzone(thumbVector, 0.1)
		end
		move, analog = stick, stick.Magnitude > 0
	end
	Input.move = move
	Input.analog = analog
	Input.touch = UserInputService:GetLastInputType() == Enum.UserInputType.Touch

	local look = Vector2.zero
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		look += UserInputService:GetMouseDelta() * cam.MouseSensitivity
	end
	local s = deadzone(rightStick, cam.StickDeadzone)
	if s.Magnitude > 0 then
		s = s.Unit * s.Magnitude ^ 1.5
		look += Vector2.new(s.X, -s.Y) * cam.GamepadSensitivity * dt
	end
	look += touchDelta * cam.TouchSensitivity
	touchDelta = Vector2.zero
	Input.look = look
	if look.Magnitude > 1e-5 then
		Input.lastLookTime = os.clock()
	end

	-- a toggled sprint drops once the player stops
	idleTime = move.Magnitude < 0.1 and idleTime + dt or 0
	if idleTime > 0.3 then
		sprintToggled = false
	end
	Input.sprint = sprintHeld or sprintToggled
	Input.aim = aimHeld or aimToggled
end

function Input.consumeSwap()
	local queued = swapQueued
	swapQueued = false
	return queued
end

function Input.consumeJump()
	local queued = jumpQueued
	jumpQueued = false
	return queued
end

return Input
