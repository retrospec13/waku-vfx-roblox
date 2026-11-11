--!strict
--[[ QuakeSlam: something enormous hits the floor.
	cf = the slam point (or the caster's root: the effect drops to the ground below it). No pose, no caster needed.

	0.00-0.20  wind-up: a comet of pressure falls out of the sky onto the point, rings close in along the ground
	0.20       SLAM: white-out flash, a light pillar punches up through three sky rings, a pressure dome blows out,
	           shock rings and a wall of dust race along the ground
	0.20-0.52  a star of cracks tears outward (dark fissure, white-hot seam, a curtain of light standing in each one),
	           black lightning whips round the crater, dark stone is thrown into the air
	0.52-1.20  the rock tumbles back down (every chunk has landed by 1.2 s), the seams cool
	1.20-1.90  embers drift up out of the cracks, the fissures and the rubble fade
	Not EarthRise: nothing stays standing. ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)

local SLAM = 0.2
local RACE = 0.32 -- the cracks reach full length this long after the slam
local UP = Vector3.yAxis

local QuakeSlam = {
	life = 1.9,
	required = { "glow_soft", "spark_streak", "spark_glint", "shock_ring", "ground_crack", "ground_disc", "bolt_glow", "smoke_puff" },
}

type Seg = { p0: Vector3, p1: Vector3, d0: number, d1: number, a0: Attachment, a1: Attachment, ink: Beam, hot: Beam,
	w0: Attachment?, w1: Attachment?, wall: Beam?, wide0: number, wide1: number, tint: number }
type Crack = { pts: { Vector3 }, dist: { number }, tint: number }
type Chunk = { part: Part, base: Vector3, dir: Vector3, r0: number, run: number, T: number, H: number, delay: number,
	spin: Vector3, tint: number }

function QuakeSlam.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local seed = ctx.opts.seed
	local life = QuakeSlam.life

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex: { Instance } = { ctx.root }
	if ctx.opts.caster then
		table.insert(ex, ctx.opts.caster)
	end
	local folder = Workspace:FindFirstChild("wakuVFX")
	if folder then
		table.insert(ex, folder)
	end
	params.FilterDescendantsInstances = ex
	local hit = Workspace:Raycast(ctx.cf.Position + UP * 4 * S, -UP * 30 * S, params)
	local G = (if hit then hit.Position else ctx.cf.Position) + UP * 0.08

	-- wind-up: the falling comet ------------------------------------------------------------------------------
	local cometGlow = Kit.sprite(ctx, "CometGlow", "glow_soft", 3)
	local cometStar = Kit.sprite(ctx, "CometStar", "spark_glint", 4)
	local cA0, cA1 = Kit.att(ctx), Kit.att(ctx)
	local cometInk = Kit.beam(ctx, cA0, cA1, "bolt_glow", -1)
	cometInk.Name = "CometInk"
	cometInk.LightEmission = 0
	local cometTail = Kit.beam(ctx, cA0, cA1, "bolt_glow", 1)
	cometTail.Name = "CometTail"
	local cometCore = Kit.beam(ctx, cA0, cA1, "bolt_glow", 2)
	cometCore.Name = "CometCore"
	for _, b in { cometInk, cometTail, cometCore } do
		b.Segments = 1
		b.Enabled = false
	end
	local closeRings = { Kit.plate(ctx, "CloseRing", "shock_ring", 1), Kit.plate(ctx, "CloseRing", "shock_ring", 1) }
	local streakDown = Kit.burst(ctx, "StreakDown", { tex = "spark_streak", life = { 0.12, 0.18 }, size = { { 0, 0.6 }, { 0.3, 3.4 }, { 1, 0.4 } },
		transp = { { 0, 1 }, { 0.25, 0 }, { 1, 0.5 } }, speed = { 120, 170 }, rot = { 90 }, vpar = true, bright = 2 })

	-- the slam -------------------------------------------------------------------------------------------------
	local flash = Kit.sprite(ctx, "Flash", "glow_soft", 6)
	local star = Kit.sprite(ctx, "FlashStar", "spark_glint", 7)
	local star2 = Kit.sprite(ctx, "FlashStar2", "spark_glint", 7)
	local pA0, pA1 = Kit.att(ctx), Kit.att(ctx)
	local pillarInk = Kit.beam(ctx, pA0, pA1, "bolt_glow", -1)
	pillarInk.Name = "PillarInk"
	pillarInk.LightEmission = 0
	local pillar = Kit.beam(ctx, pA0, pA1, "bolt_glow", 1)
	pillar.Name = "Pillar"
	local pillarCore = Kit.beam(ctx, pA0, pA1, "bolt_glow", 2)
	pillarCore.Name = "PillarCore"
	pillarCore.Brightness = 3
	for _, b in { pillarInk, pillar, pillarCore } do
		b.Segments = 1
		b.Enabled = false
	end
	local skyRings = { Kit.plate(ctx, "SkyRing", "shock_ring", 2), Kit.plate(ctx, "SkyRing", "shock_ring", 2), Kit.plate(ctx, "SkyRing", "shock_ring", 2) }
	local dome = Kit.part(ctx, ctx.root, "PressureDome", Vector3.one, Color3.new(1, 1, 1), Enum.Material.ForceField)
	dome.Shape = Enum.PartType.Ball
	local shock1 = Kit.flat(ctx, "Shock", { tex = "shock_ring", life = 0.5, size = { { 0, 6 }, { 0.2, 44 }, { 1, 84 } },
		transp = { { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } }, bright = 2.5, z = 2 })
	local shock2 = Kit.flat(ctx, "Shock2", { tex = "shock_ring", life = 0.62, size = { { 0, 4 }, { 0.25, 30 }, { 1, 58 } },
		transp = { { 0, 0.1 }, { 0.5, 0.35 }, { 1, 1 } }, bright = 2, z = 2 })
	local shock3 = Kit.flat(ctx, "Shock3", { tex = "shock_ring", life = 0.7, size = { { 0, 3 }, { 0.3, 20 }, { 1, 40 } },
		transp = { { 0, 0.2 }, { 0.5, 0.4 }, { 1, 1 } }, bright = 1.6, spin = 60, z = 2 })
	local shockInk = Kit.flat(ctx, "ShockInk", { tex = "shock_ring", life = 0.66, size = { { 0, 8 }, { 0.2, 50 }, { 1, 92 } },
		transp = { { 0, 0.1 }, { 0.6, 0.45 }, { 1, 1 } }, le = 0, z = 1 })
	local crater = Kit.flat(ctx, "CraterDark", { tex = "ground_crack", life = life - SLAM, size = { { 0, 6 }, { 0.06, 26 }, { 1, 28 } },
		transp = { { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } }, le = 0, rot = rng:NextNumber(0, 360), z = 0.4 })
	local craterHot = Kit.flat(ctx, "CraterHot", { tex = "ground_crack", life = 1.2, size = { { 0, 6 }, { 0.08, 26 }, { 1, 28 } },
		transp = { { 0, 0 }, { 0.4, 0.25 }, { 1, 1 } }, bright = 3, rot = rng:NextNumber(0, 360), z = 0.8 })
	local glowDisc = Kit.plate(ctx, "GlowDisc", "ground_disc", 0.2)
	glowDisc.beam.Brightness = 1.6

	-- the star of cracks: jagged polylines along the ground, each segment a dark fissure, a hot seam and (on the
	-- main run) a curtain of light standing in it
	local NCRACK = 8
	local segs: { Seg } = {}
	local cracks: { Crack } = {}
	local maxLen = 0
	local function flatBeam(name: string, a0: Attachment, a1: Attachment, z: number, le: number): Beam
		local b = Kit.beam(ctx, a0, a1, "bolt_glow", z)
		b.Name = name
		b.FaceCamera = false
		b.Segments = 1
		b.LightEmission = le
		b.Enabled = false
		return b
	end
	local function addSeg(p0: Vector3, p1: Vector3, d0: number, d1: number, wide0: number, wide1: number, tint: number, wall: boolean)
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local s: Seg = { p0 = p0, p1 = p1, d0 = d0, d1 = d1, a0 = a0, a1 = a1, wide0 = wide0, wide1 = wide1, tint = tint,
			ink = flatBeam("Fissure", a0, a1, 0.3, 0), hot = flatBeam("Seam", a0, a1, 0.7, 1) }
		s.hot.Brightness = 3
		if wall then
			local w0, w1 = Kit.att(ctx), Kit.att(ctx)
			s.w0, s.w1 = w0, w1
			s.wall = flatBeam("SeamLight", w0, w1, 1, 1)
		end
		table.insert(segs, s)
	end
	local function flatDir(a: number): Vector3
		return Vector3.new(math.cos(a), 0, math.sin(a))
	end
	for i = 1, NCRACK do
		local ang = (i - 1) / NCRACK * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local L = rng:NextNumber(21, 33) * S
		local tint = (i - 1) / NCRACK
		local NPT = 5
		local pts = { G + flatDir(ang) * 1.4 * S }
		local dist = { 1.4 * S }
		local a = ang
		for k = 1, NPT do
			a += rng:NextNumber(-0.3, 0.3)
			local step = (L - 1.4 * S) / NPT
			local p1 = pts[k] + flatDir(a) * step
			table.insert(pts, p1)
			table.insert(dist, dist[k] + step)
			addSeg(pts[k], p1, dist[k], dist[k] + step, (2.3 - 1.9 * (k - 1) / NPT) * S, (2.3 - 1.9 * k / NPT) * S, tint, true)
			if k == 2 or k == 4 then -- a fork
				local fa = a + (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(0.55, 0.95)
				local fl = step * rng:NextNumber(0.7, 1.15)
				local w = (2.3 - 1.9 * k / NPT) * S * 0.7
				local f1 = p1 + flatDir(fa) * fl
				addSeg(p1, f1, dist[k + 1], dist[k + 1] + fl, w, w * 0.5, tint + 0.06, false)
				local f2 = f1 + flatDir(fa + rng:NextNumber(-0.5, 0.5)) * fl * 0.7
				addSeg(f1, f2, dist[k + 1] + fl, dist[k + 1] + fl * 1.7, w * 0.5, 0.05 * S, tint + 0.1, false)
			end
		end
		a = ang
		maxLen = math.max(maxLen, L)
		cracks[i] = { pts = pts, dist = dist, tint = tint }
	end
	local function crackPoint(c: Crack, d: number): Vector3
		for k = 2, #c.pts do
			if d <= c.dist[k] then
				return c.pts[k - 1]:Lerp(c.pts[k], math.clamp((d - c.dist[k - 1]) / (c.dist[k] - c.dist[k - 1]), 0, 1))
			end
		end
		return c.pts[#c.pts]
	end

	-- black lightning round the crater: a coloured glow with a black core on the same jagged path
	local bolts = {}
	for i = 1, 7 do
		bolts[i] = { glow = Kit.bolt(ctx, "HakiGlow", 6, 1, 1), core = Kit.bolt(ctx, "HakiCore", 6, 2, 0) }
	end

	-- dark stone thrown up; every chunk flies a fixed arc and has landed by 1.2 s
	local chunks: { Chunk } = {}
	for i = 1, 30 do
		local giant = i <= 5
		local sz = (if giant then rng:NextNumber(3.6, 5.4) else rng:NextNumber(0.9, 2.8)) * S
		local base = Vector3.new(sz * rng:NextNumber(0.7, 1.2), sz * rng:NextNumber(0.5, 1), sz * rng:NextNumber(0.7, 1.2))
		local p = Kit.part(ctx, ctx.root, "Rock", base, Color3.new(), Enum.Material.Slate)
		local T = if giant then rng:NextNumber(0.78, 0.94) else rng:NextNumber(0.5, 0.94)
		chunks[i] = { part = p, base = base, dir = flatDir(rng:NextNumber(0, math.pi * 2)), r0 = rng:NextNumber(1.5, 8) * S,
			run = (if giant then rng:NextNumber(4, 10) else rng:NextNumber(6, 24)) * S, T = T, H = 150 * S * T * T / 8,
			delay = rng:NextNumber(0, 0.05), spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9)),
			tint = rng:NextNumber() }
	end

	-- particles ------------------------------------------------------------------------------------------------
	local dustRing = Kit.burst(ctx, "DustRing", { tex = "smoke_puff", life = { 0.7, 1.25 }, size = { { 0, 3 }, { 1, 12 } },
		transp = { { 0, 0.3 }, { 0.5, 0.62 }, { 1, 1 } }, speed = { 48, 92 }, drag = 3.2, rot = { 0, 360 }, rotSpeed = { -70, 70 }, le = 0 })
	local dustUp = Kit.burst(ctx, "DustUp", { tex = "smoke_puff", life = { 0.8, 1.4 }, size = { { 0, 2.5 }, { 1, 10 } },
		transp = { { 0, 0.4 }, { 0.5, 0.68 }, { 1, 1 } }, speed = { 24, 70 }, spread = 32, drag = 2.6, acc = Vector3.new(0, -12 * S, 0),
		rot = { 0, 360 }, rotSpeed = { -50, 50 }, le = 0 })
	local sparks = Kit.burst(ctx, "Sparks", { tex = "spark_streak", life = { 0.35, 0.75 }, size = { { 0, 0.5 }, { 0.2, 2.6 }, { 1, 0.3 } },
		transp = { { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } }, speed = { 50, 125 }, spread = 62, drag = 2.4, acc = Vector3.new(0, -95 * S, 0),
		rot = { 90 }, vpar = true, bright = 2.5 })
	local lines = Kit.burst(ctx, "SpeedLines", { tex = "spark_streak", life = { 0.14, 0.22 }, size = { { 0, 0.8 }, { 0.3, 5.5 }, { 1, 0.6 } },
		transp = { { 0, 0.1 }, { 0.6, 0.3 }, { 1, 1 } }, speed = { 130, 190 }, rot = { 90 }, vpar = true, bright = 2 })
	local glints = Kit.burst(ctx, "Glints", { tex = "spark_glint", life = { 0.25, 0.55 }, size = { { 0, 0 }, { 0.2, 2 }, { 1, 0 } },
		speed = { 18, 46 }, drag = 3.5, rot = { 0, 360 }, rotSpeed = { -160, 160 }, bright = 3 })
	local embers = Kit.burst(ctx, "Embers", { tex = "spark_glint", life = { 0.6, 1.0 }, size = { { 0, 0 }, { 0.15, 0.7 }, { 1, 0 } },
		speed = { 4, 11 }, spread = 16, acc = Vector3.new(0, 8 * S, 0), rot = { 0, 360 }, rotSpeed = { -120, 120 }, bright = 2.5 })
	local landPuff = Kit.burst(ctx, "LandPuff", { tex = "smoke_puff", life = { 0.4, 0.7 }, size = { { 0, 1.2 }, { 1, 4.5 } },
		transp = { { 0, 0.45 }, { 0.5, 0.7 }, { 1, 1 } }, speed = { 8, 16 }, drag = 3, rot = { 0, 360 }, le = 0 })

	local grade = Kit.grade(ctx)
	local lightPart = Kit.part(ctx, ctx.root, "Light", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightPart.Transparency = 1
	lightPart.CFrame = CFrame.new(G + UP * 4 * S)
	local light = Kit.light(ctx, lightPart, 46 * S)

	local once = Kit.once()
	local nDown, nTip, nEmber = 0, 0, 0

	return function(t: number)
		local h = Kit.hue(ctx, t, 0)
		local ts = t - SLAM -- time since the slam
		local hitNow = ts >= 0

		-- comet --------------------------------------------------------------------------------------------
		if not hitNow then
			local u = Kit.easeIn(t / SLAM)
			local head = G + UP * (58 * (1 - u) + 0.6) * S
			cometGlow.beam.Color = ColorSequence.new(Kit.hot(h))
			cometGlow.set(head, (6 + 7 * u) * S, 0.1)
			cometStar.beam.Color = ColorSequence.new(Kit.hot(h + 0.2))
			cometStar.set(head, (10 + 12 * u) * S, 0.05, t * 9)
			cA0.CFrame = CFrame.new(head)
			cA1.CFrame = CFrame.new(head + UP * (18 + 26 * u) * S)
			cometInk.Width0, cometInk.Width1 = 9 * S, 0
			cometInk.Color = ColorSequence.new(Kit.ink(h))
			cometInk.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
			cometTail.Width0, cometTail.Width1 = 6 * S, 0
			cometTail.Color = Kit.seq(ctx, h, 0.6, 0.85, 1, 5)
			cometTail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			cometCore.Width0, cometCore.Width1 = 2.4 * S, 0
			cometCore.Color = ColorSequence.new(Kit.hot(h))
			cometCore.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
			cometInk.Enabled, cometTail.Enabled, cometCore.Enabled = true, true, true
			for i, ring in closeRings do
				local ru = Kit.ramp(t, (i - 1) * 0.07, SLAM)
				ring.beam.Color = Kit.seq(ctx, Kit.hue(ctx, t, i * 0.3), 0.4, 0.8, 1, 4)
				ring.set(G, UP, (34 - 30 * Kit.easeIn(ru)) * S, if ru <= 0 then 1 else 0.75 - 0.6 * ru, t * 5 + i)
			end
			local want = math.floor(t / 0.02)
			if want > nDown then
				nDown = want
				streakDown.Color = ColorSequence.new(Kit.col(Kit.hue(ctx, t, rng:NextNumber()), 0.6, 1), Kit.hot(h))
				for _ = 1, 3 do
					local off = flatDir(rng:NextNumber(0, 6.28)) * rng:NextNumber(1, 9) * S
					ctx.host.CFrame = Kit.upTo(G + off + UP * rng:NextNumber(20, 30) * S, -UP)
					streakDown:Emit(1)
				end
			end
		else
			cometGlow.hide()
			cometStar.hide()
			cometInk.Enabled, cometTail.Enabled, cometCore.Enabled = false, false, false
			for _, ring in closeRings do
				ring.hide()
			end
		end

		-- slam: one-shot layers ------------------------------------------------------------------------------
		if once("slam", t, SLAM) then
			shock1.fire(SLAM, G, Kit.seq(ctx, h, 0.7, 0.55, 1, 6))
			shockInk.fire(SLAM, G, ColorSequence.new(Kit.ink(h)))
			crater.fire(SLAM, G + UP * 0.02, ColorSequence.new(Color3.fromHSV((h + 0.6) % 1, 0.5, 0.05)))
			craterHot.fire(SLAM, G + UP * 0.03, Kit.seq(ctx, h, 0.8, 0.6, 1, 6))
			local dustCol = ColorSequence.new(Color3.fromHSV(h, 0.16, 0.62), Color3.fromHSV(h, 0.1, 0.4))
			Kit.spray(ctx, dustRing, G + UP * 1.2 * S, 46, dustCol, "disc", 3, 0.08)
			Kit.spray(ctx, dustRing, G + UP * 1.5 * S, 22, dustCol, "disc", 2, 0.5)
			Kit.spray(ctx, dustUp, G + UP * S, 18, dustCol, "point", 0, 0, UP)
			Kit.spray(ctx, sparks, G + UP * 0.5 * S, 60, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.25, 0.8, 1)), "point", 0, 0, UP)
			Kit.spray(ctx, lines, G + UP * 0.7 * S, 40, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.4, 0.7, 1)), "disc", 4, 0.04)
			Kit.spray(ctx, glints, G + UP * 2 * S, 34, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.15)), "sphere", 3)
		end
		if once("shock2", t, SLAM + 0.07) then
			shock2.fire(SLAM + 0.07, G, Kit.seq(ctx, h + 0.3, 0.6, 0.7, 1, 5))
		end
		if once("shock3", t, SLAM + 0.16) then
			shock3.fire(SLAM + 0.16, G, Kit.seq(ctx, h + 0.6, 0.5, 0.75, 1, 5))
		end
		shock1.update(t)
		shock2.update(t)
		shock3.update(t)
		shockInk.update(t)
		crater.update(t)
		craterHot.update(t)

		-- flash, pillar, sky rings, pressure dome ------------------------------------------------------------
		local f = if hitNow then 1 - Kit.ramp(ts, 0, 0.14) else 0
		flash.beam.Color = ColorSequence.new(Kit.hot(h))
		flash.set(G + UP * 2 * S, (24 + 60 * f) * S, 1 - f)
		star.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		star.set(G + UP * 2 * S, 70 * S * f, if f > 0 then 0 else 1, 0.5, 1)
		star2.beam.Color = ColorSequence.new(Kit.hot(h + 0.3))
		star2.set(G + UP * 2 * S, 46 * S * f, if f > 0 then 0.1 else 1, 0.5 + math.pi / 4 + ts * 4, 1)

		local pu = Kit.ramp(ts, 0, 0.5)
		if hitNow and pu < 1 then
			pA0.CFrame = CFrame.new(G)
			pA1.CFrame = CFrame.new(G + UP * (24 + 80 * Kit.easeOut(Kit.ramp(ts, 0, 0.1))) * S)
			local thin = (1 - pu) ^ 1.6
			pillarInk.Width0, pillarInk.Width1 = 20 * thin * S, 9 * thin * S
			pillarInk.Color = ColorSequence.new(Kit.ink(h))
			pillarInk.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2 + 0.5 * pu), NumberSequenceKeypoint.new(1, 1) })
			pillar.Width0, pillar.Width1 = 14 * thin * S, 5 * thin * S
			pillar.Color = Kit.seq(ctx, h, 0.7, 0.85, 1, 6)
			pillar.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1 + 0.5 * pu), NumberSequenceKeypoint.new(1, 1) })
			pillarCore.Width0, pillarCore.Width1 = 5.5 * thin * S, 1.2 * thin * S
			pillarCore.Color = ColorSequence.new(Kit.hot(h))
			pillarCore.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4 * pu), NumberSequenceKeypoint.new(1, 1) })
			pillarInk.Enabled, pillar.Enabled, pillarCore.Enabled = true, true, true
		else
			pillarInk.Enabled, pillar.Enabled, pillarCore.Enabled = false, false, false
		end
		for i, ring in skyRings do
			local u = Kit.ramp(ts, 0.02 + (i - 1) * 0.05, 0.4 + (i - 1) * 0.08)
			ring.beam.Color = Kit.seq(ctx, Kit.hue(ctx, t, i * 0.25), 0.5, 0.7, 1, 5)
			Kit.pulse(ring, G + UP * (9 + 13 * i) * S, UP, u, 5 * S, (52 - 9 * i) * S, 0.1, i * 2)
		end
		local du = Kit.ramp(ts, 0, 0.3)
		if hitNow and du < 1 then
			dome.Size = Vector3.one * (8 + 62 * Kit.easeOut(du)) * S
			dome.CFrame = CFrame.new(G)
			dome.Color = Kit.col(h, 0.5, 1)
			dome.Transparency = du * du
		else
			dome.CFrame = Kit.HIDE
		end
		local dg = if hitNow then 1 - Kit.ramp(ts, 0.15, 1.3) else 0
		glowDisc.beam.Color = Kit.hueSeq(h, if ctx.opts.rainbow then 0.8 else 0.08, 0.85, 1, 6)
		glowDisc.set(G, UP, (30 + 16 * Kit.easeOut(Kit.ramp(ts, 0, 0.3))) * S, 1 - 0.55 * dg, t * 0.6)

		-- cracks ---------------------------------------------------------------------------------------------
		local front = maxLen * Kit.easeOut(Kit.ramp(ts, 0, RACE))
		local cool = Kit.ramp(ts, 0.7, 1.35) -- seams lose their heat
		local gone = Kit.ramp(t, life - 0.4, life)
		local flick = 0.75 + 0.25 * Kit.slotRng(seed, t, 1 / 30):NextNumber()
		local wallH = (1.3 + 9 * math.exp(-math.max(ts, 0) * 6)) * S * (1 - cool)
		for _, s in segs do
			local fr = if hitNow then math.clamp((front - s.d0) / (s.d1 - s.d0), 0, 1) else 0
			if fr <= 0 then
				s.ink.Enabled, s.hot.Enabled = false, false
				if s.wall then
					s.wall.Enabled = false
				end
				continue
			end
			local along = (s.p1 - s.p0).Unit
			local side = along:Cross(UP).Unit
			local pe = s.p0:Lerp(s.p1, fr)
			local we = s.wide0 + (s.wide1 - s.wide0) * fr
			s.a0.CFrame = CFrame.fromMatrix(s.p0, along, side)
			s.a1.CFrame = CFrame.fromMatrix(pe, along, side)
			local hs = Kit.hue(ctx, t, s.tint)
			s.ink.Width0, s.ink.Width1 = s.wide0 * 2.7, we * 2.7
			s.ink.Color = ColorSequence.new(Color3.fromHSV((hs + 0.5) % 1, 0.7, 0.07))
			s.ink.Transparency = NumberSequence.new(0.05 + 0.95 * gone)
			s.hot.Width0, s.hot.Width1 = s.wide0 * (1.25 - 0.5 * cool), we * (1.25 - 0.5 * cool)
			s.hot.Color = ColorSequence.new(Kit.hot(hs):Lerp(Kit.col(hs, 0.9, 1), 0.25 + 0.75 * cool))
			s.hot.Transparency = NumberSequence.new(math.clamp(1 - flick * (1 - 0.85 * cool) + gone, 0, 1))
			s.ink.Enabled, s.hot.Enabled = true, true
			if s.wall and s.w0 and s.w1 then
				if wallH > 0.05 * S then
					s.w0.CFrame = CFrame.fromMatrix(s.p0, along, UP)
					s.w1.CFrame = CFrame.fromMatrix(pe, along, UP)
					local k = math.max(0.25, s.wide0 / (2.3 * S))
					s.wall.Width0, s.wall.Width1 = wallH * 2 * k, wallH * 2 * math.max(0.2, we / (2.3 * S))
					s.wall.Color = ColorSequence.new(Kit.col(hs, 0.75, 1))
					s.wall.Transparency = NumberSequence.new(math.clamp(0.3 + 0.2 * (1 - flick) + 0.7 * cool, 0, 1))
					s.wall.Enabled = true
				else
					s.wall.Enabled = false
				end
			end
		end
		-- sparks thrown off each racing crack tip
		if hitNow and ts < RACE then
			local want = math.floor(ts / 0.035) + 1
			if want > nTip then
				nTip = want
				for _, c in cracks do
					local p = crackPoint(c, front)
					local hs = Kit.hue(ctx, t, c.tint)
					Kit.spray(ctx, glints, p + UP * 0.5 * S, 2, ColorSequence.new(Kit.hot(hs), Kit.col(hs, 0.9, 1)), "sphere", 0.5)
					Kit.spray(ctx, sparks, p + UP * 0.3 * S, 2, ColorSequence.new(Kit.hot(hs), Kit.col(hs + 0.1, 0.9, 1)), "point", 0, 0, UP)
				end
			end
		end
		-- embers drifting out of the seams while they cool
		if ts > 0.3 and ts < 1.25 then
			local want = math.floor((ts - 0.3) / 0.04)
			if want > nEmber then
				nEmber = want
				for _ = 1, 3 do
					local c = cracks[rng:NextInteger(1, #cracks)]
					local hs = Kit.hue(ctx, t, c.tint)
					Kit.spray(ctx, embers, crackPoint(c, rng:NextNumber(2 * S, c.dist[#c.dist])), 1, ColorSequence.new(Kit.hot(hs), Kit.col(hs, 0.9, 1)), "point", 0, 0, UP)
				end
			end
		end

		-- black lightning --------------------------------------------------------------------------------------
		local slot = math.floor(t / 0.05)
		local alive = if hitNow then 1 - Kit.ramp(ts, 0.12, 0.8) else 0
		for i, b in bolts do
			local r = Random.new(seed * 131 + i * 977 + slot * 31)
			if alive > 0 and r:NextNumber() < 0.35 + 0.6 * alive then
				local a = r:NextNumber(0, math.pi * 2)
				local el = r:NextNumber(0.15, 1.25)
				local tip = G + (flatDir(a) * math.cos(el) + UP * math.sin(el)) * r:NextNumber(12, 30) * S
				local from = G + flatDir(a + r:NextNumber(-0.6, 0.6)) * r:NextNumber(0, 5) * S
				local sd = seed * 53 + i * 101 + slot
				b.glow.set(from, tip, 3.4 * S, 0.1, sd, Kit.col(Kit.hue(ctx, t, i / #bolts), 0.9, 1), 0.25)
				b.core.set(from, tip, 1.1 * S, 0.1, sd, Color3.new(0, 0, 0), 0)
			else
				b.glow.hide()
				b.core.hide()
			end
		end

		-- rock ---------------------------------------------------------------------------------------------
		local shrink = 1 - Kit.ramp(t, life - 0.38, life - 0.03)
		for i, c in chunks do
			local tt = ts - c.delay
			if tt < 0 or shrink <= 0.02 then
				c.part.CFrame = Kit.HIDE
				continue
			end
			local u = math.min(tt / c.T, 1)
			local rest = c.base.Y * 0.28 * shrink
			local y = 4 * c.H * u * (1 - u) + rest
			local pos = G + c.dir * (c.r0 + c.run * u) + UP * y
			local sp = math.min(tt, c.T)
			c.part.Size = c.base * shrink
			c.part.CFrame = CFrame.new(pos) * CFrame.Angles(c.spin.X * sp, c.spin.Y * sp, c.spin.Z * sp)
			c.part.Color = Color3.fromHSV((h + 0.5 + c.tint * 0.2) % 1, 0.45, 0.13 + 0.1 * c.tint)
			if once("land" .. i, t, SLAM + c.delay + c.T) and i % 2 == 0 then
				Kit.spray(ctx, landPuff, G + c.dir * (c.r0 + c.run) + UP * 0.6 * S, 3, ColorSequence.new(Color3.fromHSV(h, 0.14, 0.55)), "disc", 1, 0.3)
			end
		end

		-- scene grade and light ------------------------------------------------------------------------------
		if grade then
			local k1 = if hitNow then math.exp(-ts * 22) else 0
			local k2 = if hitNow then math.exp(-ts * 5) else 0
			grade.Brightness = 0.4 * k1
			grade.Contrast = 0.45 * k2
			grade.Saturation = 0.35 * k2
		end
		light.Color = Kit.col(h, 0.45, 1)
		light.Brightness = if hitNow then (9 * math.exp(-ts * 7) + 2.2 * (1 - cool)) * (1 - gone) else 2 * t / SLAM
	end
end

-- a brutal kick on the slam, then the ground keeps rumbling while the rock is in the air
function QuakeSlam.shake(t: number): Vector3
	if t < SLAM or t > 1.3 then
		return Vector3.zero
	end
	local k = 1.2 * math.exp(-(t - SLAM) * 6) + 0.06 * (1 - (t - SLAM) / 1.1)
	return Vector3.new(math.sin(t * 67) * k * 0.6, math.cos(t * 83) * k, 0)
end

return QuakeSlam
