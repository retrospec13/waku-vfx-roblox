--!strict
--[[ GhostDash: afterimages and a motion trail for a dash. Visuals only: the game moves the character.
	cf = the caster's root CFrame as the dash starts, LookVector = the dash direction. Call it on the frame the
	dash begins and keep moving the character yourself; the effect reads opts.caster's position every frame.

	0.00       launch: a ring face-on to the dash, a kick of dust and sparks thrown back
	0.00-0.22  five ghosts are stamped out of the caster's real pose, one every 0.055 s; each is a sharp, unblurred
	           copy that flashes white-hot, settles into its own rainbow hue and sinks to ink as it fades (0.42 s)
	0.00-0.22  a rainbow ribbon, a white thread and speed lines stretch from the start to the caster
	0.22       arrival: a glint and a small ground ring
	0.22-0.50  the trail's tail catches up with its head; the last ghosts fade out
	A ghost is skipped when the caster has not moved since the last one, so a blocked dash leaves no stack of copies.
	Without opts.caster a simple figure makes a 14-stud dash by itself, to preview the effect. ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)

local DASH = 0.22
local GHOSTS = 5
local GAP = DASH / (GHOSTS - 1)
local GLIFE = 0.42

local GhostDash = {
	life = 0.68,
	required = { "glow_soft", "spark_glint", "spark_streak", "shock_ring", "bolt_glow", "smoke_puff" },
}

type Ghost = { model: Model, parts: { BasePart }, t0: number, hue: number, glow: Highlight }

-- a stand-in runner for previews without a caster: { size, offset from the root, pitch }
local FIGURE = {
	{ Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), -28 },
	{ Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.45, -0.85), -10 },
	{ Vector3.new(0.9, 2, 0.9), Vector3.new(-1.5, 0.1, 0.6), 50 },
	{ Vector3.new(0.9, 2, 0.9), Vector3.new(1.5, 0.3, -1.1), -75 },
	{ Vector3.new(0.9, 2, 0.9), Vector3.new(-0.5, -1.8, -0.9), -55 },
	{ Vector3.new(0.9, 2, 0.9), Vector3.new(0.5, -1.7, 1.3), 40 },
}

function GhostDash.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local caster = ctx.opts.caster
	local hrp = caster and caster:FindFirstChild("HumanoidRootPart")
	local rootPart: BasePart? = if hrp and hrp:IsA("BasePart") then hrp else nil
	local start = if rootPart then rootPart.Position else ctx.cf.Position
	local dir = ctx.cf.LookVector
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	flatDir = if flatDir.Magnitude > 1e-3 then flatDir.Unit else Vector3.zAxis

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if caster then { ctx.root, caster } :: { Instance } else { ctx.root } :: { Instance }
	local hit = Workspace:Raycast(start, Vector3.new(0, -12 * S, 0), params)
	local drop = if hit then start.Y - hit.Position.Y else 3 * S

	-- ghosts ----------------------------------------------------------------------------------------------
	local ghosts: { Ghost } = {}
	local function shell(name: string): (Model, Highlight)
		local m = Instance.new("Model")
		m.Name = name
		local hl = Instance.new("Highlight")
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.FillTransparency = 1
		hl.OutlineTransparency = 1
		hl.Parent = m
		m.Parent = ctx.root
		return m, hl
	end
	local function dress(p: BasePart)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Material = Enum.Material.Neon
	end
	-- a bare, glowing copy of every visible part of the caster, frozen where it is right now
	local function stamp(t: number, hue: number)
		local model, hl = shell("Ghost")
		local parts: { BasePart } = {}
		if caster then
			for _, d in caster:GetDescendants() do
				if d:IsA("BasePart") and d ~= rootPart and d.Transparency < 0.9 and not d:FindFirstChildOfClass("WrapLayer") then
					local keep = d.Archivable
					d.Archivable = true
					local ok, c = pcall(function()
						return d:Clone()
					end)
					d.Archivable = keep
					if ok and c then
						local copy = c :: BasePart
						for _, ch in copy:GetChildren() do
							if ch:IsA("SpecialMesh") then
								ch.TextureId = ""
							else
								ch:Destroy()
							end
						end
						if copy:IsA("MeshPart") then
							copy.TextureID = ""
						end
						dress(copy)
						copy.CFrame = d.CFrame
						copy.Parent = model
						table.insert(parts, copy)
					end
				end
			end
		end
		table.insert(ghosts, { model = model, parts = parts, t0 = t, hue = hue, glow = hl })
	end
	-- the stand-in figure
	local function stampFigure(t: number, hue: number, at: CFrame)
		local model, hl = shell("Ghost")
		local parts: { BasePart } = {}
		for _, f in FIGURE do
			local p = Kit.part(ctx, model, "Limb", (f[1] :: Vector3) * S, Color3.new(1, 1, 1), Enum.Material.Neon)
			p.CFrame = at * CFrame.new((f[2] :: Vector3) * S) * CFrame.Angles(math.rad(f[3] :: number), 0, 0)
			table.insert(parts, p)
		end
		table.insert(ghosts, { model = model, parts = parts, t0 = t, hue = hue, glow = hl })
	end
	local runner: { BasePart } = {} -- the stand-in itself, visible only while it dashes
	if not caster then
		for _, f in FIGURE do
			table.insert(runner, Kit.part(ctx, ctx.root, "Runner", (f[1] :: Vector3) * S, Color3.fromRGB(60, 62, 76), Enum.Material.SmoothPlastic))
		end
	end

	-- trail -----------------------------------------------------------------------------------------------
	local tA, tB = Kit.att(ctx), Kit.att(ctx)
	local function ribbon(name: string, z: number): Beam
		local b = Kit.beam(ctx, tA, tB, "bolt_glow", z)
		b.Name = name
		b.Segments = 1
		b.Enabled = false
		return b
	end
	local inkR = ribbon("TrailInk", -1)
	inkR.LightEmission = 0
	local bodyR = ribbon("TrailBody", 0)
	local coreR = ribbon("TrailCore", 1)
	coreR.Brightness = 3
	local lines = {}
	for i = 1, 9 do
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local b = Kit.beam(ctx, a0, a1, "bolt_glow", 2)
		b.Name = "SpeedLine"
		b.Segments = 1
		b.Enabled = false
		lines[i] = { a0 = a0, a1 = a1, b = b, x = rng:NextNumber(-1.9, 1.9), y = rng:NextNumber(-2.6, 2.4), u0 = rng:NextNumber(0, 0.5),
			len = rng:NextNumber(0.3, 0.55), w = rng:NextNumber(0.12, 0.3), lag = rng:NextNumber(0, 0.1) }
	end

	local launch = Kit.plate(ctx, "LaunchRing", "shock_ring", 2)
	launch.beam.Brightness = 2
	local launchInk = Kit.plate(ctx, "LaunchInk", "shock_ring", 1)
	launchInk.beam.LightEmission = 0
	local landRing = Kit.flat(ctx, "LandRing", { tex = "shock_ring", life = 0.28, size = { { 0, 2 }, { 0.3, 7 }, { 1, 10 } },
		transp = { { 0, 0.1 }, { 0.5, 0.5 }, { 1, 1 } }, z = 1 })
	local glint = Kit.sprite(ctx, "LandGlint", "spark_glint", 5)
	local pop = Kit.sprite(ctx, "LaunchPop", "glow_soft", 3)

	local dust = Kit.burst(ctx, "Dust", { tex = "smoke_puff", life = { 0.35, 0.6 }, size = { { 0, 1.1 }, { 1, 3.6 } },
		transp = { { 0, 0.45 }, { 0.5, 0.7 }, { 1, 1 } }, speed = { 8, 20 }, spread = 28, drag = 4, rot = { 0, 360 }, rotSpeed = { -70, 70 }, le = 0 })
	local sparks = Kit.burst(ctx, "Sparks", { tex = "spark_streak", life = { 0.12, 0.24 }, size = { { 0, 0.4 }, { 0.3, 1.8 }, { 1, 0.2 } },
		transp = { { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } }, speed = { 22, 46 }, spread = 22, drag = 4, rot = { 90 }, vpar = true, bright = 2.5 })
	local motes = Kit.burst(ctx, "Motes", { tex = "spark_glint", life = { 0.25, 0.45 }, size = { { 0, 0 }, { 0.2, 0.8 }, { 1, 0 } },
		speed = { 1, 4 }, spread = 180, rot = { 0, 360 }, rotSpeed = { -160, 160 }, bright = 3 })

	local lightPart = Kit.part(ctx, ctx.root, "Light", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightPart.Transparency = 1
	local light = Kit.light(ctx, lightPart, 14 * S)

	local once = Kit.once()
	local head = start -- where the caster is (frozen once the dash is over)
	local lastStamp: Vector3? = nil
	local nGhost, nMote = 0, 0
	local FIG_DIST = 14 * S

	return function(t: number)
		-- where is the caster now ---------------------------------------------------------------------------
		local facing = CFrame.lookAt(Vector3.zero, flatDir)
		if t <= DASH + 0.02 then
			if rootPart and rootPart.Parent then
				head = rootPart.Position
				facing = rootPart.CFrame.Rotation
			elseif not caster then
				head = start + flatDir * FIG_DIST * Kit.smooth(t / DASH)
			end
		end
		local dashing = t < DASH
		for i, p in runner do
			local f = FIGURE[i]
			p.CFrame = if dashing or t < 0.02
				then CFrame.new(head) * facing * CFrame.new((f[2] :: Vector3) * S) * CFrame.Angles(math.rad(f[3] :: number), 0, 0)
				else Kit.HIDE
		end

		-- ghosts --------------------------------------------------------------------------------------------
		local want = math.min(GHOSTS, math.floor(math.min(t, DASH) / GAP + 1e-4) + 1)
		while nGhost < want do
			nGhost += 1
			local moved = lastStamp == nil or (head - (lastStamp :: Vector3)).Magnitude > 1.2 * S
			if moved then
				lastStamp = head
				local hue = (ctx.opts.hue + (nGhost - 1) / GHOSTS * (if ctx.opts.rainbow then 0.8 else 0.1)) % 1
				local at = (nGhost - 1) * GAP
				if caster then
					stamp(at, hue)
				else
					stampFigure(at, hue, CFrame.new(head) * facing)
				end
			end
		end
		for _, g in ghosts do
			local u = (t - g.t0) / GLIFE
			if u >= 1 then
				if g.model.Parent then
					g.model:Destroy()
				end
				continue
			end
			-- white-hot for a frame or two, then its own hue, then ink
			local hotK = 1 - Kit.ramp(u, 0, 0.1)
			local inkK = Kit.ramp(u, 0.5, 1)
			local c = Kit.col(g.hue, 0.85, 1):Lerp(Kit.hot(g.hue), hotK):Lerp(Kit.ink(g.hue + 0.5), inkK * 0.8)
			local tr = 0.5 + 0.18 * Kit.ramp(u, 0.1, 0.5) + 0.32 * Kit.easeIn(Kit.ramp(u, 0.5, 1))
			for _, p in g.parts do
				p.Color = c
				p.Transparency = tr
			end
			g.glow.OutlineColor = Kit.hot(g.hue)
			g.glow.OutlineTransparency = math.clamp(1.6 * u - 0.5, 0, 1)
			g.glow.FillColor = Kit.hot(g.hue)
			g.glow.FillTransparency = math.clamp(0.55 + 6 * u, 0, 1)
		end

		-- trail ---------------------------------------------------------------------------------------------
		local h = Kit.hue(ctx, t, 0)
		local path = head - start
		local dist = path.Magnitude
		local pdir = if dist > 0.05 then path.Unit else dir
		local tailU = Kit.easeIn(Kit.ramp(t, DASH * 0.45, DASH + 0.26))
		local fade = Kit.ramp(t, DASH, DASH + 0.28)
		local on = dist > 0.5 * S and tailU < 0.98
		local mid = Vector3.new(0, 0.2 * S, 0)
		if on then
			tA.CFrame = CFrame.new(start + path * tailU + mid)
			tB.CFrame = CFrame.new(head + mid)
			local span = if ctx.opts.rainbow then 0.8 else 0.08
			inkR.Width0, inkR.Width1 = 0, 6.4 * S
			inkR.Color = ColorSequence.new(Kit.ink(h))
			inkR.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.45 + 0.55 * fade) })
			bodyR.Width0, bodyR.Width1 = 0.4 * S, 4.4 * S * (1 - 0.5 * fade)
			bodyR.Color = Kit.hueSeq(h, span, 0.9, 1, 6)
			bodyR.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.55 + 0.45 * fade),
				NumberSequenceKeypoint.new(1, 0.3 + 0.7 * fade) })
			coreR.Width0, coreR.Width1 = 0, 1.1 * S * (1 - fade)
			coreR.Color = ColorSequence.new(Kit.hot(h))
			coreR.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1 + 0.9 * fade) })
		end
		inkR.Enabled, bodyR.Enabled, coreR.Enabled = on, on, on
		local sideV = pdir:Cross(Vector3.yAxis)
		sideV = if sideV.Magnitude > 1e-3 then sideV.Unit else Vector3.xAxis
		local upV = sideV:Cross(pdir)
		for i, ln in lines do
			local a = math.max(tailU, ln.u0 * (1 - fade) + fade * 0.4)
			local b = math.min(1, a + ln.len)
			local vis = on and t > ln.lag and b - a > 0.05
			ln.b.Enabled = vis
			if vis then
				local off = sideV * ln.x * S + upV * ln.y * S
				ln.a0.CFrame = CFrame.new(start + path * a + off)
				ln.a1.CFrame = CFrame.new(start + path * b + off)
				ln.b.Width0, ln.b.Width1 = 0, ln.w * S
				local hl = Kit.hue(ctx, t, i / #lines)
				ln.b.Color = ColorSequence.new(Kit.col(hl, 0.8, 1), Kit.hot(hl))
				ln.b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15 + 0.85 * fade) })
			end
		end

		-- launch and arrival --------------------------------------------------------------------------------
		local lu = Kit.ramp(t, 0, 0.3)
		launch.beam.Color = Kit.hueSeq(h, if ctx.opts.rainbow then 0.7 else 0.08, 0.7, 1, 6)
		launch.set(start, dir, (2.5 + 8.5 * Kit.easeOut(lu)) * S, 0.05 + 0.95 * Kit.easeIn(lu), 0.6)
		local iu = Kit.ramp(t, 0.03, 0.36)
		launchInk.beam.Color = ColorSequence.new(Kit.ink(h))
		launchInk.set(start - dir * 0.3 * S, dir, (3 + 10 * Kit.easeOut(iu)) * S, if iu <= 0 or iu >= 1 then 1 else 0.25 + 0.75 * iu, 1.7)
		pop.beam.Color = ColorSequence.new(Kit.hot(h))
		pop.set(start, 5 * S, Kit.ramp(t, 0, 0.07))
		local feet = Vector3.new(0, drop - 0.08, 0)
		if once("launch", t, 0) then
			dust.Color = ColorSequence.new(Color3.fromHSV(h, 0.18, 0.66))
			Kit.emit(ctx, dust, Kit.upTo(start - feet + Vector3.new(0, 0.5 * S, 0), -flatDir + Vector3.new(0, 0.35, 0)), 8)
			sparks.Color = ColorSequence.new(Kit.hot(h), Kit.col(h + 0.1, 0.85, 1))
			Kit.emit(ctx, sparks, Kit.upTo(start, -dir), 9)
		end
		if once("land", t, DASH) and dist > 1.5 * S then
			landRing.fire(DASH, head - feet, Kit.hueSeq(h, 0.5, 0.65, 1, 4))
			dust.Color = ColorSequence.new(Color3.fromHSV(h, 0.18, 0.66))
			Kit.emit(ctx, dust, Kit.upTo(head - feet + Vector3.new(0, 0.5 * S, 0), pdir + Vector3.new(0, 0.4, 0)), 5)
		end
		landRing.update(t)
		local gu = Kit.ramp(t, DASH, DASH + 0.16)
		glint.beam.Color = ColorSequence.new(Kit.hot(h + 0.2))
		glint.set(head + Vector3.new(0, 0.6 * S, 0), (9 - 6 * gu) * S, if t < DASH or dist < 1.5 * S then 1 else Kit.easeIn(gu), t * 4, 1)

		-- glints shed along the path
		if dashing and dist > 0.5 * S then
			local wantM = math.floor(t / 0.022)
			if wantM > nMote then
				nMote = wantM
				local hm = Kit.hue(ctx, t, rng:NextNumber())
				motes.Color = ColorSequence.new(Kit.hot(hm), Kit.col(hm, 0.85, 1))
				Kit.emit(ctx, motes, CFrame.new(head + Vector3.new(rng:NextNumber(-1.2, 1.2), rng:NextNumber(-2.4, 2), rng:NextNumber(-1.2, 1.2)) * S), 1)
			end
		end

		lightPart.CFrame = CFrame.new(head)
		light.Color = Kit.col(h, 0.5, 1)
		light.Brightness = 3 * (1 - Kit.ramp(t, DASH, DASH + 0.25))
	end
end

function GhostDash.shake(t: number): Vector3
	local k = 0.1 * math.exp(-math.abs(t - DASH) * 30)
	return Vector3.new(math.sin(t * 150) * k, math.cos(t * 170) * k, 0)
end

return GhostDash
