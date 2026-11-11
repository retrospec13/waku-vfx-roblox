--!strict
-- wakuVFX demo: press 1 PrismCleave, 2 CrystalBloom, 3 StormLance, 4 EarthRise on your own character (gamepad: X/Y/B/A),
-- 5 ChargeAura (press again to drop it), 6 HitBurst, 7 ChargeBeam, 8 GhostDash, 9 ImpactFlash (keyboard only),
-- Z QuakeSlam, X BlinkStep, C RiftGate (press again to close it), V WardShell (press again to burst it), B Fireball.
-- Client-only visuals. For multiplayer, send one RemoteEvent and call waku.play on every client.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local waku = require(ReplicatedStorage:WaitForChild("wakuVFX"))
local player = Players.LocalPlayer
task.spawn(waku.preload)

local BIND = {
	{ fx = "PrismCleave", keys = { Enum.KeyCode.One, Enum.KeyCode.ButtonX }, title = "Slash" },
	{ fx = "CrystalBloom", keys = { Enum.KeyCode.Two, Enum.KeyCode.ButtonY }, title = "Ice" },
	{ fx = "StormLance", keys = { Enum.KeyCode.Three, Enum.KeyCode.ButtonB }, title = "Bolt" },
	{ fx = "EarthRise", keys = { Enum.KeyCode.Four, Enum.KeyCode.ButtonA }, title = "Earth" },
	{ fx = "ChargeAura", keys = { Enum.KeyCode.Five }, title = "Aura" },
	{ fx = "HitBurst", keys = { Enum.KeyCode.Six }, title = "Hit" },
	{ fx = "ChargeBeam", keys = { Enum.KeyCode.Seven }, title = "Beam" },
	{ fx = "GhostDash", keys = { Enum.KeyCode.Eight }, title = "Dash" },
	{ fx = "ImpactFlash", keys = { Enum.KeyCode.Nine }, title = "Impact" },
	{ fx = "QuakeSlam", keys = { Enum.KeyCode.Z }, title = "Quake" },
	{ fx = "BlinkStep", keys = { Enum.KeyCode.X }, title = "Blink" },
	{ fx = "RiftGate", keys = { Enum.KeyCode.C }, title = "Gate" },
	{ fx = "WardShell", keys = { Enum.KeyCode.V }, title = "Ward" },
	{ fx = "Fireball", keys = { Enum.KeyCode.B }, title = "Fire" },
}
local POSED = { PrismCleave = true, StormLance = true, EarthRise = true, ChargeBeam = true } -- one posed clone at a time
local aura: any = nil
local held: { [string]: any } = {} -- RiftGate / WardShell: the second press stops the one that is up
local combo = 0
local busy: { [string]: boolean } = {}

local function groundUnder(char: Model, pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(pos, Vector3.new(0, -20, 0), params)
	return if hit then hit.Position else pos - Vector3.new(0, 3, 0)
end

-- GhostDash is visuals only: the game moves the character. Here the demo slides it 14 studs, stopping short of walls.
local function demoDash(char: Model, hrp: BasePart, look: Vector3)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(hrp.Position, look * 15, params)
	local dist = if hit then math.max(0, (hit.Position - hrp.Position).Magnitude - 2) else 14
	local from, t0 = hrp.CFrame, os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local u = math.clamp((os.clock() - t0) / 0.22, 0, 1)
		hrp.CFrame = from + look * dist * (u * u * (3 - 2 * u))
		hrp.AssemblyLinearVelocity = Vector3.zero
		if u >= 1 then
			conn:Disconnect()
		end
	end)
end

-- BlinkStep is visuals only too. The demo teleports the root 18 studs (short of walls) while the body is hidden.
local function blinkTarget(char: Model, hrp: BasePart, look: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(hrp.Position, look * 19, params)
	return hrp.Position + look * (if hit then math.max(0, (hit.Position - hrp.Position).Magnitude - 2) else 18)
end

local function cast(fx: string)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (char and hrp and hrp:IsA("BasePart")) then
		return
	end
	local look = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	-- moves that pose the caster share one lock (one posed clone at a time)
	local key = if POSED[fx] then "pose" else fx
	if busy[key] then
		return
	end
	local h
	local front = hrp.Position + look * 3.2 + Vector3.new(0, 0.8, 0) -- where a punch would land
	if fx == "ChargeAura" then
		if aura and aura.alive() then
			aura.stop()
			aura = nil
			return
		end
		h = waku.play(fx, hrp.CFrame, { caster = char })
		aura = h
	elseif fx == "RiftGate" or fx == "WardShell" then
		local old = held[fx]
		if old and old.alive() then
			old.stop() -- plays the fold / the shatter
			held[fx] = nil
			return
		end
		if fx == "RiftGate" then
			local g = groundUnder(char, hrp.Position + look * 14)
			local c = g + Vector3.new(0, 8.5, 0)
			h = waku.play(fx, CFrame.lookAt(c, c - look)) -- facing the player
		else
			h = waku.play(fx, hrp.CFrame, { caster = char })
		end
		held[fx] = h
	elseif fx == "QuakeSlam" then
		h = waku.play(fx, CFrame.lookAt(hrp.Position + look * 9, hrp.Position + look * 10))
	elseif fx == "BlinkStep" then
		local to = blinkTarget(char, hrp, look)
		h = waku.play(fx, CFrame.lookAt(hrp.Position, hrp.Position + look), { caster = char, to = to })
		if h then
			task.delay(0.2, function() -- inside the 0.16-0.31 s gap, while the body is hidden
				if hrp.Parent then
					hrp.CFrame = hrp.CFrame.Rotation + to
					hrp.AssemblyLinearVelocity = Vector3.zero
				end
			end)
		end
	elseif fx == "Fireball" then
		h = waku.play(fx, CFrame.lookAt(hrp.Position, hrp.Position + look))
	elseif fx == "HitBurst" then
		combo += 1
		h = waku.play(fx, CFrame.lookAt(front, front + look), { seed = combo })
	elseif fx == "ImpactFlash" then
		h = waku.play(fx, CFrame.lookAt(front, front + look), { caster = char })
	elseif fx == "ChargeBeam" then
		h = waku.play(fx, CFrame.lookAt(hrp.Position, hrp.Position + look), { caster = char })
	elseif fx == "GhostDash" then
		h = waku.play(fx, CFrame.lookAt(hrp.Position, hrp.Position + look), { caster = char })
		if h then
			demoDash(char, hrp, look)
		end
	elseif fx == "PrismCleave" then
		h = waku.play(fx, CFrame.lookAt(hrp.Position, hrp.Position + look), { caster = char })
	elseif fx == "EarthRise" then
		local g = groundUnder(char, hrp.Position)
		h = waku.play(fx, CFrame.lookAt(g, g + look), { caster = char })
	elseif fx == "StormLance" then
		local g = groundUnder(char, hrp.Position + look * 10)
		h = waku.play(fx, CFrame.new(g), { caster = char })
	else
		local g = groundUnder(char, hrp.Position + look * 12)
		h = waku.play(fx, CFrame.new(g))
	end
	if h then
		local sounds = require(ReplicatedStorage.wakuVFX.Sounds)
		sounds.play(fx, hrp, h)
	end
	if h and POSED[fx] then
		busy[key] = true
		task.delay(h.life + 0.1, function()
			busy[key] = nil
		end)
	end
	-- camera shake through the humanoid's CameraOffset
	local hum = char:FindFirstChildOfClass("Humanoid")
	if h and hum then
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			if h.alive() then
				hum.CameraOffset = waku.shake(fx, waku.now() - h.t0)
			else
				hum.CameraOffset = Vector3.zero
				conn:Disconnect()
			end
		end)
	end
end

for _, b in BIND do
	local name = "waku_" .. b.fx
	ContextActionService:BindAction(name, function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			cast(b.fx)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, #b.keys > 1, table.unpack(b.keys)) -- touch buttons for the first four only
	ContextActionService:SetTitle(name, b.title)
end
