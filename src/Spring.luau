-- Critically damped easing (Unity-style SmoothDamp). Works on numbers and Vector3s.
local Spring = {}

function Spring.damp(current, target, velocity, smoothTime, dt)
	smoothTime = math.max(smoothTime, 1e-4)
	local omega = 2 / smoothTime
	local x = omega * dt
	local decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	local change = current - target
	local temp = (velocity + change * omega) * dt
	return target + (change + temp) * decay, (velocity - temp * omega) * decay
end

-- Shortest signed angle from a to b, in radians.
function Spring.angleDiff(a, b)
	return (b - a + math.pi) % (2 * math.pi) - math.pi
end

local Damped = {}
Damped.__index = Damped

function Spring.new(value, smoothTime)
	return setmetatable({ value = value, velocity = value * 0, smoothTime = smoothTime }, Damped)
end

function Damped:update(target, dt, smoothTime)
	self.value, self.velocity = Spring.damp(self.value, target, self.velocity, smoothTime or self.smoothTime, dt)
	return self.value
end

return Spring
