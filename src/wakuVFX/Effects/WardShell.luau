--!strict
--[[ WardShell: a guard bubble that takes two hits and then bursts.
	cf = the caster's root CFrame. With opts.caster the shell follows that character's root every frame (like
	ChargeAura); without one it stays at cf. It never poses, hides or anchors the caster.

	0.00-0.30  snaps open: a lattice of light draws itself up round the body, the shell pops out past full size and
	           settles, a ring burns where it meets the ground
	0.30-3.00  hold: a glowing-edged shell (ForceField ball) inside a slowly turning geometric lattice, light running
	           down its edges, its corners glinting
	1.00       first hit: something streaks in and stars against the shell; rings wrap round it from the hit point,
	           the lattice flares, black lightning crawls over the surface, cracks start
	1.80       second hit from another side, harder: the cracks spread and keep creeping
	3.00-3.40  shatter: the shell swells and bursts, the lattice flies apart edge by edge, glass shards tumble out
	handle.stop() plays the shatter from wherever it is; a second stop() removes it at once. ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)

local OPEN = 0.3
local BREAK = 3.0
local SHATTER = 0.4
local HITS = { 1.0, 1.8 }
local UP = Vector3.yAxis
local PHI = (1 + math.sqrt(5)) / 2

local WardShell = {
	life = BREAK + SHATTER,
	required = { "glow_soft", "spark_streak", "spark_glint", "shock_ring", "ground_disc", "bolt_glow", "smoke_puff", "ice_shard" },
}

type Edge = { i: number, j: number, a0: Attachment, a1: Attachment, body: Beam, core: Beam, axis: Vector3, spin: number,
	delay: number, tint: number, fly: number }
type CrackSeg = { d0: Vector3, d1: Vector3, a0: Attachment, a1: Attachment, glow: Beam, core: Beam, at: number, w: number }
type Shard = { part: BasePart, dir: Vector3, speed: number, spin: Vector3, base: Vector3, tint: number }

function WardShell.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local seed = ctx.opts.seed
	local life = WardShell.life
	ctx.outro = SHATTER
	local caster = ctx.opts.caster
	local hrp = caster and caster:FindFirstChild("HumanoidRootPart")
	local rootPart: BasePart? = if hrp and hrp:IsA("BasePart") then hrp else nil
	local R = 8.5 * S

	local start = if rootPart then rootPart.Position else ctx.cf.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if caster then { ctx.root, caster } :: { Instance } else { ctx.root } :: { Instance }
	local hit = Workspace:Raycast(start, Vector3.new(0, -14 * S, 0), params)
	local groundY = if hit then hit.Position.Y + 0.08 else start.Y - 3 * S

	-- where the two hits land (fixed in the world: front and high, then from the side)
	local look, rightV = ctx.cf.LookVector, ctx.cf.RightVector
	local hitDir = { (look * 0.8 + UP * 0.5 + rightV * 0.3).Unit, (-rightV * 0.85 + UP * 0.28 + look * 0.4).Unit }

	-- the shell --------------------------------------------------------------------------------------------------
	local shell = Kit.part(ctx, ctx.root, "Shell", Vector3.one, Color3.new(1, 1, 1), Enum.Material.ForceField)
	shell.Shape = Enum.PartType.Ball
	local shell2 = Kit.part(ctx, ctx.root, "ShellInner", Vector3.one, Color3.new(1, 1, 1), Enum.Material.ForceField)
	shell2.Shape = Enum.PartType.Ball
	local fill = Kit.part(ctx, ctx.root, "ShellFill", Vector3.one, Color3.new(1, 1, 1), Enum.Material.Neon)
	fill.Shape = Enum.PartType.Ball
	fill.Transparency = 1

	-- the lattice: an icosahedron whose edges are bent to lie on the sphere -----------------------------------------
	local verts: { Vector3 } = {}
	for _, s1 in { -1, 1 } do
		for _, s2 in { -1, 1 } do
			table.insert(verts, Vector3.new(0, s1, s2 * PHI).Unit)
			table.insert(verts, Vector3.new(s1, s2 * PHI, 0).Unit)
			table.insert(verts, Vector3.new(s1 * PHI, 0, s2).Unit)
		end
	end
	local edges: { Edge } = {}
	for i = 1, #verts do
		for j = i + 1, #verts do
			if (verts[i] - verts[j]).Magnitude < 1.1 then
				local a0, a1 = Kit.att(ctx), Kit.att(ctx)
				local body = Kit.beam(ctx, a0, a1, "bolt_glow", 0)
				body.Name = "Lattice"
				body.Segments = 6
				body.Enabled = false
				local core = Kit.beam(ctx, a0, a1, "bolt_glow", 1)
				core.Name = "LatticeCore"
				core.Segments = 6
				core.Brightness = 2
				core.Enabled = false
				local ax = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
				table.insert(edges, { i = i, j = j, a0 = a0, a1 = a1, body = body, core = core,
					axis = if ax.Magnitude > 0.01 then ax.Unit else UP, spin = rng:NextNumber(-11, 11),
					delay = (1 + math.min(verts[i].Y, verts[j].Y)) / 2 * 0.14, tint = #edges / 30, fly = rng:NextNumber(1.7, 3.1) })
			end
		end
	end
	local vertGlints = {}
	for i = 1, #verts do
		vertGlints[i] = Kit.sprite(ctx, "Corner", "spark_glint", 2)
	end

	-- cracks: jagged lines walked over the sphere from each hit point; they keep creeping until the shell breaks
	local cracks: { CrackSeg } = {}
	for k, n in hitDir do
		local nC = if k == 1 then 3 else 6
		local nS = if k == 1 then 4 else 7
		local bu = n:Cross(UP).Unit
		local bv = n:Cross(bu)
		for c = 1, nC do
			local a = (c - 1) / nC * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
			local d = n
			local tan = bu * math.cos(a) + bv * math.sin(a)
			for s = 1, nS do
				local st = rng:NextNumber(0.15, 0.27)
				local nd = (d * math.cos(st) + tan * math.sin(st)).Unit
				local ntan = (tan * math.cos(st) - d * math.sin(st)).Unit
				ntan = (ntan + nd:Cross(ntan) * rng:NextNumber(-0.8, 0.8)).Unit
				local a0, a1 = Kit.att(ctx), Kit.att(ctx)
				local glow = Kit.beam(ctx, a0, a1, "bolt_glow", 2)
				glow.Name = "CrackGlow"
				glow.Segments = 1
				glow.Enabled = false
				local core = Kit.beam(ctx, a0, a1, "bolt_glow", 3)
				core.Name = "Crack"
				core.Segments = 1
				core.Brightness = 3
				core.Enabled = false
				table.insert(cracks, { d0 = d, d1 = nd, a0 = a0, a1 = a1, glow = glow, core = core,
					at = HITS[k] + (if s <= 3 then 0.03 * s else 0.09 + (s - 3) * (if k == 1 then 0.5 else 0.22) + rng:NextNumber(-0.05, 0.05)),
					w = 1 - 0.6 * (s - 1) / nS })
				d, tan = nd, ntan
			end
		end
	end

	-- hits ---------------------------------------------------------------------------------------------------------
	local cA0, cA1 = Kit.att(ctx), Kit.att(ctx)
	local cometInk = Kit.beam(ctx, cA0, cA1, "bolt_glow", -1)
	cometInk.Name = "ShotInk"
	cometInk.LightEmission = 0
	local comet = Kit.beam(ctx, cA0, cA1, "bolt_glow", 1)
	comet.Name = "Shot"
	local cometCore = Kit.beam(ctx, cA0, cA1, "bolt_glow", 2)
	cometCore.Name = "ShotCore"
	for _, b in { cometInk, comet, cometCore } do
		b.Segments = 1
		b.Width1 = 0
		b.Enabled = false
	end
	local cometHead = Kit.sprite(ctx, "ShotHead", "glow_soft", 3)
	local hitFlash = Kit.sprite(ctx, "HitFlash", "glow_soft", 5)
	local hitStar = Kit.sprite(ctx, "HitStar", "spark_glint", 6)
	local hitStar2 = Kit.sprite(ctx, "HitStar2", "spark_glint", 6)
	local wraps = { Kit.plate(ctx, "Ripple", "shock_ring", 2), Kit.plate(ctx, "Ripple", "shock_ring", 2), Kit.plate(ctx, "Ripple", "shock_ring", 2) }
	local wrapInk = Kit.plate(ctx, "RippleInk", "shock_ring", 1)
	wrapInk.beam.LightEmission = 0
	local bolts = {}
	for i = 1, 5 do
		bolts[i] = { glow = Kit.bolt(ctx, "HakiGlow", 5, 3, 1), core = Kit.bolt(ctx, "HakiCore", 5, 4, 0) }
	end

	-- open / shatter -----------------------------------------------------------------------------------------------
	local openFlash = Kit.sprite(ctx, "OpenFlash", "glow_soft", 4)
	local openStar = Kit.sprite(ctx, "OpenStar", "spark_glint", 5)
	local groundRing = Kit.plate(ctx, "GroundRing", "shock_ring", 0.6)
	local groundGlow = Kit.plate(ctx, "GroundGlow", "ground_disc", 0.2)
	local openShock = Kit.flat(ctx, "OpenShock", { tex = "shock_ring", life = 0.4, size = { { 0, 4 }, { 0.3, 28 }, { 1, 44 } },
		transp = { { 0, 0.05 }, { 0.5, 0.35 }, { 1, 1 } }, bright = 2, z = 1 })
	local breakShock = Kit.flat(ctx, "BreakShock", { tex = "shock_ring", life = 0.4, size = { { 0, 12 }, { 0.3, 44 }, { 1, 70 } },
		transp = { { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } }, bright = 2.5, z = 1 })
	local breakInk = Kit.flat(ctx, "BreakInk", { tex = "shock_ring", life = 0.4, size = { { 0, 14 }, { 0.3, 50 }, { 1, 78 } },
		transp = { { 0, 0.1 }, { 0.6, 0.45 }, { 1, 1 } }, le = 0, z = 0.5 })
	local breakRing = Kit.sprite(ctx, "BreakRing", "shock_ring", 4)
	local breakFlash = Kit.sprite(ctx, "BreakFlash", "glow_soft", 6)
	local breakStar = Kit.sprite(ctx, "BreakStar", "spark_glint", 7)
	local shards: { Shard } = {}
	for i = 1, 22 do
		local base = Vector3.new(0.22, rng:NextNumber(2.2, 5), rng:NextNumber(1.3, 3.2)) * S
		local p = Kit.wedge(ctx.root, "GlassShard", base, Color3.new(1, 1, 1), Enum.Material.Neon)
		local dv = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.35, 1), rng:NextNumber(-1, 1))
		shards[i] = { part = p, dir = if dv.Magnitude > 0.01 then dv.Unit else UP, speed = rng:NextNumber(38, 80) * S,
			spin = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12)), base = base, tint = rng:NextNumber() }
	end

	local sparks = Kit.burst(ctx, "Sparks", { tex = "spark_streak", life = { 0.25, 0.55 }, size = { { 0, 0.4 }, { 0.2, 2.1 }, { 1, 0.2 } },
		transp = { { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } }, speed = { 40, 95 }, spread = 55, drag = 2.6, acc = Vector3.new(0, -60 * S, 0),
		rot = { 90 }, vpar = true, bright = 2.5 })
	local glints = Kit.burst(ctx, "Glints", { tex = "spark_glint", life = { 0.25, 0.55 }, size = { { 0, 0 }, { 0.2, 1.7 }, { 1, 0 } },
		speed = { 12, 38 }, drag = 3.5, rot = { 0, 360 }, rotSpeed = { -160, 160 }, bright = 3 })
	local chips = Kit.burst(ctx, "Chips", { tex = "ice_shard", life = { 0.35, 0.6 }, size = { { 0, 1.5 }, { 0.6, 1.2 }, { 1, 0 } },
		transp = { { 0, 0.05 }, { 0.7, 0.3 }, { 1, 1 } }, speed = { 40, 90 }, spread = 14, drag = 2.2, acc = Vector3.new(0, -50 * S, 0),
		rot = { 0, 360 }, rotSpeed = { -500, 500 }, bright = 2 })
	local lines = Kit.burst(ctx, "BurstLines", { tex = "spark_streak", life = { 0.12, 0.2 }, size = { { 0, 0.7 }, { 0.3, 5 }, { 1, 0.5 } },
		transp = { { 0, 0.1 }, { 0.6, 0.3 }, { 1, 1 } }, speed = { 120, 180 }, spread = 4, rot = { 90 }, vpar = true, bright = 2 })
	local dust = Kit.burst(ctx, "Dust", { tex = "smoke_puff", life = { 0.4, 0.7 }, size = { { 0, 1.6 }, { 1, 6 } },
		transp = { { 0, 0.4 }, { 0.5, 0.68 }, { 1, 1 } }, speed = { 26, 52 }, drag = 4, rot = { 0, 360 }, rotSpeed = { -70, 70 }, le = 0 })
	local motes = Kit.burst(ctx, "Motes", { tex = "spark_glint", life = { 0.5, 0.9 }, size = { { 0, 0 }, { 0.2, 0.7 }, { 1, 0 } },
		speed = { 2, 6 }, spread = 20, rot = { 0, 360 }, rotSpeed = { -120, 120 }, bright = 2.5 })

	local grade = Kit.grade(ctx)
	local lightPart = Kit.part(ctx, ctx.root, "Light", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightPart.Transparency = 1
	local light = Kit.light(ctx, lightPart, 30 * S)

	local once = Kit.once()
	local nMote = 0
	local W: { Vector3 } = table.create(#verts, Vector3.zero)
	local centre = start

	local function sprayShell(e: ParticleEmitter, n: number, color: ColorSequence, rad: number)
		e.Color = color
		for _ = 1, n do
			local dv = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
			local d = if dv.Magnitude > 0.01 then dv.Unit else UP
			ctx.host.CFrame = Kit.upTo(centre + d * rad, d)
			e:Emit(1)
		end
	end

	return function(t: number)
		local h = Kit.hue(ctx, t, 0)
		local breakAt = ctx.stopAt or (life - SHATTER)
		local ts = t - breakAt
		local broken = ts >= 0
		if rootPart and rootPart.Parent then
			centre = rootPart.Position
		end
		local Cc = centre

		-- which hit is ringing (only hits that land before the shell breaks) ------------------------------------------
		local hk, th = 0, -10
		for k, at in HITS do
			if t >= at and at < breakAt then
				hk, th = k, t - at
			end
		end
		local hn = if hk > 0 then hitDir[hk] else UP
		local punch = if hk > 0 then math.exp(-th * 9) else 0 -- 1 at the moment of a hit
		local power = if hk == 2 then 1.35 else 1

		-- shell ------------------------------------------------------------------------------------------------------
		local grow = Kit.easeOutBack(Kit.ramp(t, 0, OPEN))
		local bulge = 1 + 0.07 * power * punch * math.cos(th * 38)
		local swell = if broken then 1 + 0.55 * Kit.easeOut(Kit.ramp(ts, 0, 0.2)) else 1
		local Rs = R * grow * bulge
		local flick = 0.8 + 0.2 * Kit.slotRng(seed, t, 1 / 30):NextNumber()
		local gone = if broken then Kit.ramp(ts, 0, 0.16) else 0
		if gone < 1 and grow > 0.02 then
			local dsz = 2 * Rs * swell
			shell.Size = Vector3.one * dsz
			shell.CFrame = CFrame.new(Cc) * CFrame.Angles(0, t * 0.8, 0)
			shell.Color = Kit.col(h, 0.75 - 0.6 * punch, 1)
			shell.Transparency = math.clamp(0.12 + 0.2 * (1 - flick) + gone, 0, 1)
			shell2.Size = Vector3.one * dsz * 0.955
			shell2.CFrame = CFrame.new(Cc) * CFrame.Angles(0.5, -t * 1.1, 0.3)
			shell2.Color = Kit.col(h + 0.35, 0.8 - 0.6 * punch, 1)
			shell2.Transparency = math.clamp(0.3 + gone, 0, 1)
			fill.Size = Vector3.one * dsz * 0.985
			fill.CFrame = CFrame.new(Cc)
			fill.Color = Kit.col(h + 0.1, 0.5 - 0.4 * punch, 1)
			fill.Transparency = math.clamp(0.94 - 0.4 * punch * power - 0.5 * (1 - Kit.ramp(t, 0, 0.2)) + (if broken then -0.5 * (1 - gone) + gone else 0), 0.3, 1)
		else
			shell.CFrame, shell2.CFrame, fill.CFrame = Kit.HIDE, Kit.HIDE, Kit.HIDE
		end

		-- lattice ----------------------------------------------------------------------------------------------------
		local rot = CFrame.Angles(0, t * 0.45, 0) * CFrame.Angles(0.32, 0, 0.2)
		for i, v in verts do
			W[i] = rot:VectorToWorldSpace(v)
		end
		local wave = 1.7 * Kit.easeOut(Kit.ramp(th, 0, 0.5)) -- angle the hit ripple has reached
		local waveA = if hk > 0 then 1 - Kit.ramp(th, 0.2, 0.6) else 0
		local Rl = Rs * 1.015
		for _, e in edges do
			local u0, u1 = W[e.i], W[e.j]
			if broken then
				local u = ts / SHATTER
				if u >= 1 then
					e.body.Enabled, e.core.Enabled = false, false
					continue
				end
				local m = (u0 + u1).Unit
				local c = Cc + m * (R + R * e.fly * Kit.easeOut(u)) - UP * 22 * S * ts * ts
				local hv = CFrame.fromAxisAngle(e.axis, e.spin * ts):VectorToWorldSpace((u1 - u0) * R * 0.5)
				e.a0.CFrame = CFrame.new(c - hv)
				e.a1.CFrame = CFrame.new(c + hv)
				e.body.CurveSize0, e.body.CurveSize1, e.core.CurveSize0, e.core.CurveSize1 = 0, 0, 0, 0
				local he = Kit.hue(ctx, t, e.tint)
				e.body.Width0, e.body.Width1 = 1.1 * S, 1.1 * S
				e.body.Color = ColorSequence.new(Kit.col(he, 0.7, 1))
				e.body.Transparency = NumberSequence.new(math.clamp(0.1 + 0.9 * u * u, 0, 1))
				e.core.Width0, e.core.Width1 = 0.4 * S, 0.4 * S
				e.core.Color = ColorSequence.new(Color3.new(1, 1, 1))
				e.core.Transparency = NumberSequence.new(math.clamp(u * u, 0, 1))
				e.body.Enabled, e.core.Enabled = true, true
				continue
			end
			local f = Kit.easeOut(Kit.ramp(t, e.delay, e.delay + 0.14))
			if f < 0.04 then
				e.body.Enabled, e.core.Enabled = false, false
				continue
			end
			local ue = if f < 1 then u0:Lerp(u1, f).Unit else u1
			local cosT = math.clamp(u0:Dot(ue), -1, 1)
			local theta = math.acos(cosT)
			local hl = 4 / 3 * math.tan(theta / 4) * Rl
			e.a0.CFrame = Kit.rightTo(Cc + u0 * Rl, ue - u0 * cosT)
			e.a1.CFrame = Kit.rightTo(Cc + ue * Rl, ue * cosT - u0)
			e.body.CurveSize0, e.body.CurveSize1, e.core.CurveSize0, e.core.CurveSize1 = hl, hl, hl, hl
			local m = (u0 + u1).Unit
			local flare = 0
			if waveA > 0 then
				local ang = math.acos(math.clamp(m:Dot(hn), -1, 1))
				flare = math.exp(-((ang - wave) / 0.42) ^ 2) * waveA * power
			end
			local sh = 0.5 + 0.5 * math.sin(t * 5 - m.Y * 4 + e.tint * 3) -- light running down the lattice
			local he = Kit.hue(ctx, t, e.tint)
			local wd = (0.55 + 0.4 * sh + 1.5 * flare + 1.2 * (1 - Kit.ramp(t, e.delay, e.delay + 0.3))) * S
			e.body.Width0, e.body.Width1 = wd, wd
			e.body.Color = ColorSequence.new(Kit.col(he, 0.85 - 0.7 * math.min(flare, 1), 1), Kit.col(he + 0.12, 0.85 - 0.7 * math.min(flare, 1), 1))
			e.body.Transparency = NumberSequence.new(math.clamp(0.35 - 0.2 * sh - 0.3 * flare, 0, 1))
			e.core.Width0, e.core.Width1 = wd * 0.3, wd * 0.3
			e.core.Color = ColorSequence.new(Color3.new(1, 1, 1))
			e.core.Transparency = NumberSequence.new(math.clamp(0.45 - 0.35 * sh - 0.4 * flare, 0, 1))
			e.body.Enabled, e.core.Enabled = true, true
		end
		for i, sp in vertGlints do
			if broken or t < 0.14 then
				sp.hide()
			else
				local tw = 0.5 + 0.5 * math.sin(t * 6.3 + i * 1.9)
				sp.beam.Color = ColorSequence.new(Kit.hot(Kit.hue(ctx, t, i / 12)))
				sp.set(Cc + W[i] * Rl, (1.6 + 2.6 * tw * tw + 4 * punch) * S, 0.15, t * 1.5 + i)
			end
		end

		-- cracks -------------------------------------------------------------------------------------------------------
		for _, c in cracks do
			if broken or t < c.at or c.at >= breakAt then
				c.glow.Enabled, c.core.Enabled = false, false
				continue
			end
			local pop = 1 + 2.4 * math.exp(-(t - c.at) * 12) -- each new piece of crack flashes as it opens
			c.a0.CFrame = CFrame.new(Cc + c.d0 * Rl * 1.004)
			c.a1.CFrame = CFrame.new(Cc + c.d1 * Rl * 1.004)
			c.glow.Width0, c.glow.Width1 = 1.5 * c.w * pop * S, 1.3 * c.w * pop * S
			c.glow.Color = ColorSequence.new(Kit.col(h + 0.5, 0.7, 1))
			c.glow.Transparency = NumberSequence.new(0.45)
			c.core.Width0, c.core.Width1 = 0.5 * c.w * pop * S, 0.42 * c.w * pop * S
			c.core.Color = ColorSequence.new(Color3.new(1, 1, 1))
			c.core.Transparency = NumberSequence.new(0.05 + 0.2 * (1 - flick))
			c.glow.Enabled, c.core.Enabled = true, true
		end

		-- open ---------------------------------------------------------------------------------------------------------
		local G = Vector3.new(Cc.X, groundY, Cc.Z)
		if once("open", t, 0) then
			openShock.fire(0.05, G, Kit.seq(ctx, h, 0.6, 0.6, 1, 5))
			Kit.spray(ctx, dust, G + UP * 0.8 * S, 18, ColorSequence.new(Color3.fromHSV(h, 0.14, 0.6)), "disc", 2, 0.08)
		end
		if once("openPop", t, OPEN * 0.55) then
			sprayShell(glints, 26, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.2)), R)
		end
		openShock.update(t)
		local of = 1 - Kit.ramp(t, 0, 0.2)
		openFlash.beam.Color = ColorSequence.new(Kit.hot(h))
		openFlash.set(Cc, (10 + 2.6 * R / S * Kit.easeOut(Kit.ramp(t, 0, 0.2))) * S, 1 - 0.8 * of)
		openStar.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		openStar.set(Cc, 30 * S * of, if of > 0 then 0.1 else 1, 0.4, 1)
		local depth = Cc.Y - groundY
		local rg = math.sqrt(math.max(Rs * Rs - depth * depth, 0))
		if rg > 0.5 * S and not broken then
			groundRing.beam.Color = Kit.seq(ctx, h, 0.8, 0.7, 1, 6)
			groundRing.set(G, UP, 2 * rg / 0.86, 0.15 + 0.15 * (1 - flick), t * 1.3)
			groundGlow.beam.Color = Kit.hueSeq(h + 0.2, if ctx.opts.rainbow then 0.6 else 0.08, 0.8, 1, 5)
			groundGlow.set(G, UP, rg * 2.9, 0.55 - 0.25 * punch, -t * 0.6)
		else
			groundRing.hide()
			groundGlow.hide()
		end
		if not broken and t > OPEN then
			local want = math.floor(t / 0.07)
			if want > nMote then
				nMote = want
				sprayShell(motes, 1, ColorSequence.new(Kit.col(Kit.hue(ctx, t, rng:NextNumber()), 0.7, 1), Kit.hot(h)), Rs)
			end
		end

		-- hits ---------------------------------------------------------------------------------------------------------
		local shot = false
		for k, at in HITS do
			if at >= breakAt then
				continue
			end
			local n = hitDir[k]
			local P = Cc + n * Rs
			if t >= at - 0.12 and t < at then
				shot = true
				local u = (t - (at - 0.12)) / 0.12
				local head = P + n * 46 * S * (1 - u)
				cA0.CFrame = CFrame.new(head)
				cA1.CFrame = CFrame.new(head + n * 22 * S)
				local hc = Kit.hue(ctx, t, k * 0.4)
				cometInk.Width0 = 4.4 * S
				cometInk.Color = ColorSequence.new(Kit.ink(hc))
				cometInk.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
				comet.Width0 = 2.8 * S
				comet.Color = Kit.seq(ctx, hc, 0.4, 0.9, 1, 4)
				comet.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
				cometCore.Width0 = 1.1 * S
				cometCore.Color = ColorSequence.new(Kit.hot(hc))
				cometCore.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
				cometHead.beam.Color = ColorSequence.new(Kit.hot(hc))
				cometHead.set(head, 6 * S, 0.1)
			end
			if once("hit" .. k, t, at) then
				local pw = if k == 2 then 1.4 else 1
				Kit.spray(ctx, sparks, P, math.floor(38 * pw), ColorSequence.new(Kit.hot(h), Kit.col(h + 0.25, 0.8, 1)), "point", 0, 0, n)
				Kit.spray(ctx, glints, P + n * S, math.floor(18 * pw), ColorSequence.new(Kit.hot(h), Kit.col(h + 0.15)), "sphere", 2)
				Kit.spray(ctx, chips, P, math.floor(8 * pw), ColorSequence.new(Kit.hot(h), Kit.col(h + 0.4, 0.5, 1)), "point", 0, 0, n)
			end
		end
		cometInk.Enabled, comet.Enabled, cometCore.Enabled = shot, shot, shot
		if not shot then
			cometHead.hide()
		end
		if hk > 0 and not broken then
			local P = Cc + hn * Rs
			local hf = 1 - Kit.ramp(th, 0, 0.14)
			hitFlash.beam.Color = ColorSequence.new(Kit.hot(h))
			hitFlash.set(P, (8 + 22 * hf) * S * power, 1 - hf)
			hitStar.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
			hitStar.set(P, 40 * S * hf * power, if hf > 0 then 0 else 1, 0.4, 1)
			hitStar2.beam.Color = ColorSequence.new(Kit.hot(h + 0.3))
			hitStar2.set(P, 25 * S * hf * power, if hf > 0 then 0.1 else 1, 0.4 + math.pi / 4 + th * 6, 1)
			-- rings wrapping round the shell from the hit point
			for i, pl in wraps do
				local u = Kit.ramp(th, (i - 1) * 0.07, 0.42 + (i - 1) * 0.09)
				local ang = 0.12 + 1.65 * Kit.easeOut(u)
				pl.beam.Color = Kit.seq(ctx, Kit.hue(ctx, t, i * 0.25), 0.6, 0.7, 1, 5)
				pl.set(Cc + hn * Rs * 1.03 * math.cos(ang), hn, 2 * Rs * 1.03 * math.sin(ang) / 0.86, if u <= 0 or u >= 1 then 1 else 0.05 + 0.95 * u * u, i * 2.1)
			end
			local iu = Kit.ramp(th, 0.02, 0.5)
			local iang = 0.12 + 1.65 * Kit.easeOut(iu)
			wrapInk.beam.Color = ColorSequence.new(Kit.ink(h))
			wrapInk.set(Cc + hn * Rs * 1.04 * math.cos(iang), hn, 2 * Rs * 1.1 * math.sin(iang) / 0.86, if iu <= 0 or iu >= 1 then 1 else 0.2 + 0.8 * iu * iu, 1)
		else
			hitFlash.hide()
			hitStar.hide()
			hitStar2.hide()
			for _, pl in wraps do
				pl.hide()
			end
			wrapInk.hide()
		end
		-- black lightning crawling over the surface from the hit point
		local slot = math.floor(t / 0.05)
		local crawl = if hk > 0 and not broken then 1 - Kit.ramp(th, 0.05, 0.42) else 0
		for i, b in bolts do
			local r = Random.new(seed * 131 + i * 977 + slot * 31)
			if crawl > 0 and r:NextNumber() < 0.35 + 0.6 * crawl then
				local bu = hn:Cross(UP).Unit
				local bv = hn:Cross(bu)
				local a = r:NextNumber(0, math.pi * 2)
				local reach = r:NextNumber(0.55, 1.25) * power
				local q = (hn * math.cos(reach) + (bu * math.cos(a) + bv * math.sin(a)) * math.sin(reach)).Unit
				local sd = seed * 53 + i * 101 + slot
				b.glow.set(Cc + hn * Rs * 1.05, Cc + q * Rs * 1.08, 2.2 * S, 0.12, sd, Kit.col(Kit.hue(ctx, t, i / #bolts), 0.9, 1), 0.3)
				b.core.set(Cc + hn * Rs * 1.05, Cc + q * Rs * 1.08, 0.75 * S, 0.12, sd, Color3.new(0, 0, 0), 0)
			else
				b.glow.hide()
				b.core.hide()
			end
		end

		-- shatter ------------------------------------------------------------------------------------------------------
		if broken and once("break", t, breakAt) then
			breakShock.fire(breakAt, G, Kit.seq(ctx, h, 0.7, 0.55, 1, 6))
			breakInk.fire(breakAt, G, ColorSequence.new(Kit.ink(h)))
			sprayShell(chips, 70, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.3, 0.6, 1)), R)
			sprayShell(glints, 44, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.15)), R)
			sprayShell(sparks, 50, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.5, 0.8, 1)), R)
			sprayShell(lines, 36, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.4, 0.7, 1)), R * 0.9)
			Kit.spray(ctx, dust, G + UP * S, 26, ColorSequence.new(Color3.fromHSV(h, 0.14, 0.6)), "disc", 6, 0.08)
		end
		breakShock.update(t)
		breakInk.update(t)
		local bf = if broken then 1 - Kit.ramp(ts, 0, 0.15) else 0
		breakFlash.beam.Color = ColorSequence.new(Kit.hot(h))
		breakFlash.set(Cc, (2.4 * R / S + 34 * bf) * S, 1 - bf)
		breakStar.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		breakStar.set(Cc, 64 * S * bf, if bf > 0 then 0 else 1, 0.5, 1)
		local bu = if broken then Kit.ramp(ts, 0, 0.34) else 0
		breakRing.beam.Color = Kit.seq(ctx, h, 0.8, 0.6, 1, 6)
		breakRing.set(Cc, 2 * R * (1.1 + 2.4 * Kit.easeOut(bu)), if bu <= 0 or bu >= 1 then 1 else 0.05 + 0.95 * bu * bu)
		for _, sd in shards do
			if not broken or ts >= SHATTER then
				sd.part.CFrame = Kit.HIDE
				continue
			end
			local travel = sd.speed * (1 - math.exp(-3.2 * ts)) / 3.2
			local pos = Cc + sd.dir * (R + travel) - UP * 30 * S * ts * ts
			sd.part.Size = sd.base * (1 - 0.5 * Kit.ramp(ts, 0.15, SHATTER))
			sd.part.CFrame = CFrame.new(pos) * CFrame.Angles(sd.spin.X * ts, sd.spin.Y * ts, sd.spin.Z * ts)
			sd.part.Color = Kit.col(Kit.hue(ctx, t, sd.tint), 0.45, 1)
			sd.part.Transparency = 0.15 + 0.85 * Kit.easeIn(Kit.ramp(ts, 0.12, SHATTER - 0.02))
		end

		if grade then
			local k = (if broken then math.exp(-ts * 14) else 0) + 0.5 * punch * power * (if hk > 0 and not broken then 1 else 0)
			grade.Brightness = 0.22 * k
			grade.Contrast = 0.25 * k
			grade.Saturation = 0.2 * k
		end
		lightPart.CFrame = CFrame.new(Cc)
		light.Color = Kit.col(h, 0.45, 1)
		light.Brightness = if broken then 9 * math.exp(-ts * 9) else (1.6 * grow * flick + 5 * punch * power + 4 * of)
	end
end

-- a knock for each hit, a harder one when it bursts
function WardShell.shake(t: number): Vector3
	local k = 0
	if t >= BREAK then
		k = 0.7 * math.exp(-(t - BREAK) * 9)
	elseif t >= HITS[2] then
		k = 0.5 * math.exp(-(t - HITS[2]) * 11)
	elseif t >= HITS[1] then
		k = 0.35 * math.exp(-(t - HITS[1]) * 11)
	end
	return Vector3.new(math.sin(t * 87) * k, math.cos(t * 109) * k, 0)
end

return WardShell
