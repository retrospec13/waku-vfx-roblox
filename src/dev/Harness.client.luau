--!strict
--[[ wakuVFX dev harness (Studio QA only, not part of the release). Commands arrive through the LocalPlayer
	attribute VFXCmd (driven by Studio MCP); progress is reported in the attribute VFXState.
	  selftest|<nonce>          run waku.SelfTest over all effects -> "stdone|<nonce>|<pass>|<fail>"
	  ptest|<nonce>             EarthRise on the LocalPlayer's own character: hidden + anchored during, restored after
	  step|<fx>|<dt>|<tEnd>|<pre>|<nonce>|<cam>|<tStart>|<stopT>
	                            frame-by-frame capture: freeze the effect clock at every dt of effect time; after each
	                            frame the state is frame|<nonce>|<k>|<t>, and MCP replies next|<nonce>|<k>
	  play|<fx>|<cam>           play once at authored speed
	  mood|dusk|day, label|0|1, cam|<name>
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local waku = require(ReplicatedStorage:WaitForChild("wakuVFX")) :: any
local player = Players.LocalPlayer

local PLACES: { [string]: CFrame } = {
	PrismCleave = CFrame.new(-60, 3, 0), -- caster root, facing -Z
	CrystalBloom = CFrame.new(0, 0, -6),
	StormLance = CFrame.new(60, 0, -6),
	EarthRise = CFrame.new(-16, 0, 112) * CFrame.Angles(0, math.rad(-90), 0),
	-- set 2 (stations along z = -150, facing +X unless noted)
	ChargeAura = CFrame.new(-70, 3, -150),
	HitBurst = CFrame.lookAt(Vector3.new(-46.3, 4.1, -150), Vector3.new(-40, 4.1, -150)),
	ChargeBeam = CFrame.lookAt(Vector3.new(10, 3, -150), Vector3.new(11, 3, -150)),
	GhostDash = CFrame.lookAt(Vector3.new(-25, 3, -150), Vector3.new(-24, 3, -150)),
	ImpactFlash = CFrame.lookAt(Vector3.new(74.7, 4.2, -150), Vector3.new(80, 4.2, -150)),
	-- set 3 (stations along z = -300; the cameras sit at lower z and look back toward the wall)
	QuakeSlam = CFrame.new(-105, 3, -300),
	BlinkStep = CFrame.lookAt(Vector3.new(-62, 3, -300), Vector3.new(-61, 3, -300)),
	RiftGate = CFrame.lookAt(Vector3.new(-5, 9.6, -298), Vector3.new(-6.5, 9.6, -320)),
	WardShell = CFrame.lookAt(Vector3.new(35, 3, -300), Vector3.new(31, 3, -320)),
	Fireball = CFrame.lookAt(Vector3.new(68, 3, -300), Vector3.new(69, 3, -300)),
}
local CAMS: { [string]: { pos: Vector3, look: Vector3 } } = {
	TriSlash = { pos = Vector3.new(-69, 6.5, -16), look = Vector3.new(-60, 2.5, -4) },
	PrismCleave = { pos = Vector3.new(-80, 6, -6), look = Vector3.new(-60, 2.5, -10) },
	PrismCleave_front = { pos = Vector3.new(-66, 5, -30), look = Vector3.new(-60, 3, -6) },
	PrismCleave_tr = { pos = Vector3.new(-71, 7.5, -15), look = Vector3.new(-60, 3, -3) },
	CrystalBloom = { pos = Vector3.new(-13, 7, -27), look = Vector3.new(0, 3.2, -6) },
	CrystalBloom_low = { pos = Vector3.new(-8, 2.5, -21), look = Vector3.new(0, 4.5, -6) },
	StormLance = { pos = Vector3.new(40, 6, -38), look = Vector3.new(57, 9, -3) },
	StormLance_close = { pos = Vector3.new(47, 4, -20), look = Vector3.new(58, 5, -4) },
	EarthRise_close = { pos = Vector3.new(-8.5, 4.4, 106), look = Vector3.new(-15.5, 3.2, 112.3) },
	EarthRise_top = { pos = Vector3.new(-26, 24, 96), look = Vector3.new(2, 0, 113) },
	TriSlash_side = { pos = Vector3.new(-82, 6, -6), look = Vector3.new(-60, 2.5, -4) },
	FrostCrown = { pos = Vector3.new(-12, 10, -30), look = Vector3.new(0, 2.6, -6) },
	FrostCrown_low = { pos = Vector3.new(-9, 3.2, -22), look = Vector3.new(0, 3.5, -6) },
	ForkStorm = { pos = Vector3.new(41, 15, -36), look = Vector3.new(60, 5, -4) },
	ForkStorm_wide = { pos = Vector3.new(42, 9, -48), look = Vector3.new(60, 9, -6) },
	EarthRise = { pos = Vector3.new(-3, 9.5, 86), look = Vector3.new(1, 3.5, 112) },
	ChargeAura = { pos = Vector3.new(-70, 6.5, -173), look = Vector3.new(-70, 5.5, -150) },
	ChargeAura_close = { pos = Vector3.new(-62, 3.5, -163), look = Vector3.new(-70, 4.5, -150) },
	HitBurst = { pos = Vector3.new(-47, 5, -162), look = Vector3.new(-46.5, 4, -150) },
	HitBurst_front = { pos = Vector3.new(-56, 5, -157), look = Vector3.new(-46, 4, -150) },
	ChargeBeam = { pos = Vector3.new(30, 9, -193), look = Vector3.new(31, 5, -150) },
	ChargeBeam_caster = { pos = Vector3.new(6, 5, -166), look = Vector3.new(15, 4, -150) },
	ChargeBeam_end = { pos = Vector3.new(36, 7, -172), look = Vector3.new(50, 5, -150) },
	GhostDash = { pos = Vector3.new(-18, 5.5, -172), look = Vector3.new(-18, 3.5, -150) },
	GhostDash_front = { pos = Vector3.new(-2, 5, -160), look = Vector3.new(-18, 3, -150) },
	ImpactFlash = { pos = Vector3.new(75, 5.5, -167), look = Vector3.new(75, 4, -150) },
	ImpactFlash_side = { pos = Vector3.new(74.5, 4.8, -161), look = Vector3.new(74.5, 4, -150) },
	HitBurst_side = { pos = Vector3.new(-47.3, 4.6, -159), look = Vector3.new(-47.3, 4, -150) },
	ChargeAura_hero = { pos = Vector3.new(-66, 2.2, -160), look = Vector3.new(-70, 5.2, -150) },
	ChargeBeam_wide = { pos = Vector3.new(33, 7, -180), look = Vector3.new(32, 4.5, -150) },
	ImpactFlash_back = { pos = Vector3.new(61, 7.5, -157), look = Vector3.new(76, 4, -150) },
	GhostDash_close = { pos = Vector3.new(-17, 4.5, -162), look = Vector3.new(-17, 3.2, -150) },
	QuakeSlam = { pos = Vector3.new(-105, 10, -352), look = Vector3.new(-105, 9, -300) },
	QuakeSlam_low = { pos = Vector3.new(-88, 2.6, -328), look = Vector3.new(-105, 7, -300) },
	QuakeSlam_top = { pos = Vector3.new(-105, 46, -330), look = Vector3.new(-105, 0, -299) },
	BlinkStep = { pos = Vector3.new(-53, 6.5, -334), look = Vector3.new(-53, 6.5, -300) },
	BlinkStep_arrive = { pos = Vector3.new(-33, 3.2, -318), look = Vector3.new(-45, 7, -300) },
	BlinkStep_leave = { pos = Vector3.new(-68, 4.5, -316), look = Vector3.new(-60, 4, -300) },
	RiftGate = { pos = Vector3.new(-9, 7, -330), look = Vector3.new(-5, 9, -298) },
	RiftGate_close = { pos = Vector3.new(-14, 4, -316), look = Vector3.new(-5, 9.5, -298) },
	RiftGate_side = { pos = Vector3.new(-28, 8, -312), look = Vector3.new(-5, 9, -298) },
	WardShell = { pos = Vector3.new(33, 7, -332), look = Vector3.new(35, 5.5, -300) },
	WardShell_close = { pos = Vector3.new(27, 3.4, -320), look = Vector3.new(35, 5.5, -300) },
	WardShell_hit = { pos = Vector3.new(46, 9, -322), look = Vector3.new(35, 5, -300) },
	Fireball = { pos = Vector3.new(90, 9, -352), look = Vector3.new(90, 7, -300) },
	Fireball_caster = { pos = Vector3.new(60, 5, -313), look = Vector3.new(80, 4.5, -300) },
	Fireball_wall = { pos = Vector3.new(84, 6, -326), look = Vector3.new(110, 7, -300) },
	Fireball_chase = { pos = Vector3.new(58, 7.5, -307), look = Vector3.new(110, 4, -300) },
	EarthRise_hero = { pos = Vector3.new(36, 4.2, 97), look = Vector3.new(-6, 4.5, 114) },
}

local gui = Instance.new("ScreenGui")
gui.Name = "wakuHarness"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
local label = Instance.new("TextLabel")
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.35
label.TextColor3 = Color3.new(1, 1, 1)
label.Font = Enum.Font.Code
label.TextSize = 20
label.TextXAlignment = Enum.TextXAlignment.Left
label.Size = UDim2.fromOffset(640, 30)
label.Position = UDim2.fromOffset(10, 10)
label.Text = " wakuVFX dev"
label.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")
local function setLabel(s: string)
	label.Text = " wakuVFX | " .. s
end
local function setState(s: string)
	player:SetAttribute("VFXState", s)
end

local camName: string? = nil
local current: any = nil -- handle being filmed (for shake)
RunService:BindToRenderStep("wakuHarnessCam", Enum.RenderPriority.Camera.Value + 1, function()
	local c = Workspace.CurrentCamera
	local p = camName and CAMS[camName]
	if c and p then
		c.CameraType = Enum.CameraType.Scriptable
		c.FieldOfView = 55
		local cf = CFrame.lookAt(p.pos, p.look)
		if current and current.alive() then
			cf = cf * CFrame.new(waku.shake(current.name, waku.now() - current.t0) * 0.8)
		end
		c.CFrame = cf
	end
end)

local CASTERS: { [string]: string } = { EarthRise = "Caster_EarthRise", PrismCleave = "Caster_TriSlash", StormLance = "Bystander_ForkStorm",
	ChargeAura = "Caster_Aura", ChargeBeam = "Caster_Beam", GhostDash = "Caster_Dash", ImpactFlash = "Caster_Impact",
	BlinkStep = "Caster_Blink", WardShell = "Caster_Ward", Fireball = "Caster_Fire" }
-- effects whose cf is simply "where the caster stands"
local AT_CASTER: { [string]: boolean } = { GhostDash = true, BlinkStep = true, WardShell = true, Fireball = true }
local function casterFor(name: string): Model?
	local key = CASTERS[name]
	if not key then
		return nil
	end
	local stage = Workspace:FindFirstChild("Stage")
	local m = stage and stage:FindFirstChild(key, true)
	return if m and m:IsA("Model") then m else nil
end

-- GhostDash is visuals only, so the harness plays the game's part: it slides the dummy 14 studs along the dash in a
-- running pose, on the effect clock (so frame-stepping works), and puts it back when the effect ends.
local RUN: { [string]: CFrame } = {
	Root = CFrame.Angles(math.rad(-32), 0, 0), Neck = CFrame.Angles(math.rad(22), 0, 0),
	RightShoulder = CFrame.Angles(math.rad(-70), 0, 0), LeftShoulder = CFrame.Angles(math.rad(55), 0, 0),
	RightElbow = CFrame.Angles(math.rad(60), 0, 0), LeftElbow = CFrame.Angles(math.rad(80), 0, 0),
	RightHip = CFrame.Angles(math.rad(75), 0, 0), LeftHip = CFrame.Angles(math.rad(-45), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-80), 0, 0), LeftKnee = CFrame.Angles(math.rad(-35), 0, 0),
}
local function dashMover(h: any, model: Model)
	local start = model:GetPivot()
	local motors: { [string]: any } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			motors[d.Name] = d
		end
	end
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not h.alive() then
			conn:Disconnect()
			model:PivotTo(start)
			for _, m in motors do
				m.Transform = CFrame.identity
			end
			return
		end
		local t = waku.now() - h.t0
		local u = math.clamp(t / 0.22, 0, 1)
		local back = math.clamp((t - 0.22) / 0.1, 0, 1) -- straighten up on arrival
		model:PivotTo(start * CFrame.new(0, 0, -14 * u * u * (3 - 2 * u)))
		for name, cf in RUN do
			local m = motors[name]
			if m then
				m.Transform = cf:Lerp(CFrame.identity, back)
			end
		end
	end)
end
-- BlinkStep is visuals only too: the harness teleports the dummy 18 studs ahead inside the gap (the effect finds
-- it there on arrival) and walks it back once the effect is over.
local function blinkMover(h: any, model: Model)
	local start = model:GetPivot()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not h.alive() then
			conn:Disconnect()
			model:PivotTo(start)
			return
		end
		local t = waku.now() - h.t0
		model:PivotTo(if t >= 0.2 then start * CFrame.new(0, 0, -18) else start)
	end)
end
local hits = 0
local extraOpts: { [string]: any } = {}
local function playFx(fx: string): any
	local caster = casterFor(fx)
	local cf = PLACES[fx]
	if AT_CASTER[fx] and caster then
		cf = caster:GetPivot()
	end
	hits += 1
	local o: { [string]: any } = { caster = caster, seed = if fx == "HitBurst" then hits else nil }
	for key, v in extraOpts do -- "rainbow=0,hue=0.03" from the step command: look checks of the non-default options
		o[key] = v
	end
	local h = waku.play(fx, cf, o)
	if h and fx == "GhostDash" and caster then
		dashMover(h, caster)
	elseif h and fx == "BlinkStep" and caster then
		blinkMover(h, caster)
	end
	return h
end

local function waitEffect(t0: number, t: number)
	while waku.now() - t0 < t do
		RunService.Heartbeat:Wait()
	end
end

local running = false

local function cmdSelfTest(nonce: string)
	running = true
	camName = nil
	setLabel("SelfTest")
	local casters: { [string]: Model? } = {}
	for name in CASTERS do
		casters[name] = casterFor(name)
	end
	local pass, fail = waku.SelfTest.run(waku, { places = PLACES, casters = casters })
	for _, e in waku.Errors do
		print("[wakuVFX SelfTest] ERROR " .. tostring(e))
	end
	setState(string.format("stdone|%s|%d|%d", nonce, pass, fail))
	running = false
	task.wait(2)
	if not running then
		setState("idle")
	end
end

-- EarthRise on the local player's own character (the demo path)
local function cmdPlayerTest(nonce: string)
	running = true
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
	local before: { [Instance]: number } = {}
	local hidden = 0
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			before[d] = (d :: any).Transparency
		end
	end
	local anchoredBefore = hrp.Anchored
	local cf = CFrame.lookAt(hrp.Position - Vector3.new(0, 3, 0), hrp.Position - Vector3.new(0, 3, 0) + hrp.CFrame.LookVector * Vector3.new(1, 0, 1))
	local h = waku.play("EarthRise", cf, { caster = char })
	task.wait(1)
	for d in before do
		if (d :: any).Transparency == 1 then
			hidden += 1
		end
	end
	local anchoredDuring = hrp.Anchored
	local stillParented = char.Parent ~= nil
	while h and h.alive() do
		RunService.Heartbeat:Wait()
	end
	task.wait(0.5)
	local restored, total = 0, 0
	for d, tr in before do
		total += 1
		if (d :: any).Transparency == tr then
			restored += 1
		end
	end
	local ok = h ~= nil and hidden >= 10 and anchoredDuring and stillParented and restored == total and hrp.Anchored == anchoredBefore
	print(string.format("[wakuVFX SelfTest] %s EarthRise player-character: hidden during=%d, anchored during=%s, stays parented=%s, restored %d/%d, anchored after=%s",
		if ok then "PASS" else "FAIL", hidden, tostring(anchoredDuring), tostring(stillParented), restored, total, tostring(hrp.Anchored)))
	setState(string.format("ptdone|%s|%s", nonce, if ok then "PASS" else "FAIL"))
	running = false
	task.wait(2)
	if not running then
		setState("idle")
	end
end

local function parseOpts(str: string?)
	table.clear(extraOpts)
	for key, v in string.gmatch(str or "", "(%w+)=([%w%.%-]+)") do
		extraOpts[key] = if key == "rainbow" then v ~= "0" and v ~= "false" else tonumber(v)
	end
end

local function cmdStep(fx: string, dt: number, tEnd: number, pre: number, nonce: string, cam: string?, tStart: number?, stopT: number?)
	running = true
	camName = cam or fx
	waku.timeScale = 0
	local k = 0
	local function frame(t: number, tag: string)
		setLabel(string.format("%s  %s  t=%+.3f s  frame %d", fx, tag, t, k))
		RunService.Heartbeat:Wait()
		RunService.Heartbeat:Wait()
		setState(string.format("frame|%s|%d|%.3f", nonce, k, t))
		local w = os.clock()
		while player:GetAttribute("VFXCmd") ~= string.format("next|%s|%d", nonce, k) and os.clock() - w < 60 do
			task.wait(0.03)
		end
		k += 1
	end
	for i = math.floor(pre / dt + 0.5), 1, -1 do
		frame(-i * dt, "pre-roll")
	end
	waku.timeScale = 0.25
	local h = playFx(fx)
	current = h
	waku.timeScale = 0
	local t0 = if h then h.t0 else waku.now()
	local life = waku.Effects[fx].life
	local n = if tStart and tStart > 0 then math.floor(tStart / dt + 0.5) else 0
	local stopped = false
	if not h then
		for _, e in waku.Errors do
			print("[wakuVFX harness] ERROR " .. tostring(e))
		end
	end
	while n * dt <= tEnd do
		local target = n * dt
		if h and stopT and not stopped and target >= stopT then
			stopped = true
			h.stop() -- graceful stop: effects with an outro play it from here
		end
		if waku.now() - t0 < target then
			waku.timeScale = 0.25
			waitEffect(t0, target)
			waku.timeScale = 0
		end
		frame(waku.now() - t0, if target < life then "playing" else "ended")
		n += 1
	end
	waku.timeScale = 1
	while h and h.alive() do
		RunService.Heartbeat:Wait()
	end
	waku.timeScale = nil
	current = nil
	setState(string.format("stepdone|%s|%d", nonce, k))
	running = false
	task.wait(2)
	if not running then
		setState("idle")
	end
end

player:GetAttributeChangedSignal("VFXCmd"):Connect(function()
	local cmd = player:GetAttribute("VFXCmd")
	if type(cmd) ~= "string" then
		return
	end
	local p = string.split(cmd, "|")
	if p[1] == "selftest" and not running then
		task.spawn(cmdSelfTest, p[2] or "")
	elseif p[1] == "ptest" and not running then
		task.spawn(cmdPlayerTest, p[2] or "")
	elseif p[1] == "step" and not running then
		parseOpts(p[10])
		task.spawn(cmdStep, p[2], tonumber(p[3]) or 1 / 30, tonumber(p[4]) or 1.5, tonumber(p[5]) or 0.2, p[6] or "",
			if p[7] and p[7] ~= "" then p[7] else nil, tonumber(p[8] or ""), tonumber(p[9] or ""))
	elseif p[1] == "play" and not running then
		camName = if p[3] and p[3] ~= "" then p[3] else p[2]
		current = playFx(p[2])
	elseif p[1] == "cam" then
		camName = p[2]
	elseif p[1] == "label" then
		gui.Enabled = p[2] == "1"
	elseif p[1] == "mood" then
		local L = game:GetService("Lighting")
		if p[2] == "dusk" then
			L.ClockTime = 17.6
			L.Brightness = 1.7
			L.Ambient = Color3.fromRGB(72, 64, 96)
			L.OutdoorAmbient = Color3.fromRGB(112, 98, 136)
			L.ExposureCompensation = 0.15
			local cc = L:FindFirstChild("Grade") :: ColorCorrectionEffect? or Instance.new("ColorCorrectionEffect")
			cc.Name = "Grade"
			cc.Contrast = 0.18
			cc.Saturation = 0.22
			cc.TintColor = Color3.fromRGB(236, 232, 255)
			cc.Parent = L
			local at = L:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
			at.Density = 0.22
			at.Haze = 0.8
			at.Color = Color3.fromRGB(120, 96, 150)
			at.Decay = Color3.fromRGB(60, 40, 90)
			at.Glare = 0.3
			at.Parent = L
			for _, d in Workspace.Stage:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Floor" then
					d.Material = Enum.Material.Concrete
				end
			end
		else
			L.ClockTime = 9
			L.Brightness = 1.3
			L.ExposureCompensation = 0
			local cc = L:FindFirstChild("Grade")
			if cc then
				cc:Destroy()
			end
			local at = L:FindFirstChildOfClass("Atmosphere")
			if at then
				at:Destroy()
			end
		end
	end
end)

while not Workspace:GetAttribute("StageReady") do
	task.wait(0.2)
end
task.spawn(waku.preload)
setState("idle")
