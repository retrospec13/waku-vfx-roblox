--!strict
--[[ ChargeBeam: gather, then fire a thick beam.
	cf = the caster's root CFrame, LookVector = the firing direction (it may point up or down). With opts.caster the
	caster cups both hands in front of the chest and thrusts them forward on the shot.

	0.00-0.45  charge: an orb swells in front of the hands, light rays and rings are drawn into it
	0.45       fire: muzzle star and rings, a kick of dust at the feet; the beam head reaches the target in 0.06 s
	0.45-1.05  blast: white-hot core, rainbow sheath, dark ink edge, two strands winding round the first stretch,
	           pulse rings running down the beam; where it lands, a flickering burst with spikes, sparks and smoke
	1.05-1.20  the beam thins to a thread while its tail races to the far end
	1.20-1.45  afterglow at the impact, the caster relaxes
	The beam stops at the first thing it hits within 70 studs (x scale), otherwise it runs the full length. ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)
local Pose = require(script.Parent.Parent.Pose)

local CHARGE = 0.45
local REACH = 0.06
local BLAST_END = 1.05
local GONE = 1.2

local ChargeBeam = {
	life = 1.45,
	required = { "glow_soft", "spark_glint", "spark_streak", "shock_ring", "bolt_glow", "smoke_puff" },
}

local A, arm = Pose.A, Pose.arm
local KEYS: { Pose.Key } = {
	{ t = 0, p = {} },
	{ t = 0.14, p = { -- hands cupped in front of the chest, knees bent
		Root = CFrame.new(0, -0.35, 0) * A(4, 0, 0), Waist = A(-6, 0, 0),
		RightShoulder = arm(70, 34, 0), LeftShoulder = arm(70, -34, 0), RightElbow = A(48, 0, 0), LeftElbow = A(48, 0, 0),
		RightHip = A(18, 0, -6), LeftHip = A(18, 0, 6), RightKnee = A(-30, 0, 0), LeftKnee = A(-30, 0, 0) } },
	{ t = 0.41, p = { -- sink deeper, lean back from the orb
		Root = CFrame.new(0, -0.55, 0.15) * A(8, 0, 0), Waist = A(-4, 0, 0), Neck = A(-6, 0, 0),
		RightShoulder = arm(66, 36, 0), LeftShoulder = arm(66, -36, 0), RightElbow = A(62, 0, 0), LeftElbow = A(62, 0, 0),
		RightHip = A(26, 0, -8), LeftHip = A(26, 0, 8), RightKnee = A(-44, 0, 0), LeftKnee = A(-44, 0, 0) } },
	{ t = 0.5, p = { -- THRUST: arms straight, palms out, weight thrown forward
		Root = CFrame.new(0, -0.5, -0.35) * A(-12, 0, 0), Waist = A(-8, 0, 0), Neck = A(10, 0, 0),
		RightShoulder = arm(90, 14, 0), LeftShoulder = arm(90, -14, 0), RightElbow = A(4, 0, 0), LeftElbow = A(4, 0, 0),
		RightWrist = A(-50, 0, 0), LeftWrist = A(-50, 0, 0),
		RightHip = A(52, 0, -6), LeftHip = A(-22, 0, 6), RightKnee = A(-58, 0, 0), LeftKnee = A(-20, 0, 0) } },
	{ t = 1.1, p = "SAME" :: any },
	{ t = 1.45, p = {} },
}
KEYS[5].p = KEYS[4].p

function ChargeBeam.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local seed = ctx.opts.seed
	local rainbow = ctx.opts.rainbow
	local dir = ctx.cf.LookVector
	local M = ctx.cf.Position + dir * 3.1 * S + ctx.cf.UpVector * 0.35 * S -- muzzle, just past the hands
	local RANGE = 70 * S
	local E, N, struck = M + dir * RANGE, -dir, false -- end point, surface normal there, did it hit something

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex: { Instance } = { ctx.root }
	if ctx.opts.caster then
		table.insert(ex, ctx.opts.caster)
	end
	params.FilterDescendantsInstances = ex
	local function aim()
		local folder = Workspace:FindFirstChild("wakuVFX")
		if folder then
			params.FilterDescendantsInstances = { folder, table.unpack(ex) } -- other running effects never block the beam
		end
		local hit = Workspace:Raycast(M, dir * RANGE, params)
		if hit then
			E, N, struck = hit.Position, hit.Normal, true
		else
			E, N, struck = M + dir * RANGE, -dir, false
		end
	end
	aim()
	local ground = Workspace:Raycast(ctx.cf.Position, Vector3.new(0, -9 * S, 0), params)

	local rig = Pose.rig(ctx, ctx.opts.caster)

	-- charge ------------------------------------------------------------------------------------------------
	local orb = Kit.part(ctx, ctx.root, "Orb", Vector3.one, Color3.new(1, 1, 1), Enum.Material.Neon)
	orb.Shape = Enum.PartType.Ball
	local orbGlow = Kit.sprite(ctx, "OrbGlow", "glow_soft", 3)
	local orbHalo = Kit.sprite(ctx, "OrbHalo", "glow_soft", 1)
	local star = Kit.sprite(ctx, "MuzzleStar", "spark_glint", 5)
	local star2 = Kit.sprite(ctx, "MuzzleStar2", "spark_glint", 5)
	local rays = {}
	for i = 1, 12 do
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local b = Kit.beam(ctx, a0, a1, "bolt_glow", 2)
		b.Name = "Ray"
		b.Segments = 1
		b.Enabled = false
		rays[i] = { a0 = a0, a1 = a1, b = b, ph = rng:NextNumber(), per = rng:NextNumber(0.16, 0.24) }
	end
	local gather = { Kit.plate(ctx, "GatherRing", "shock_ring", 1), Kit.plate(ctx, "GatherRing", "shock_ring", 1) }
	local streakIn = Kit.burst(ctx, "StreakIn", { tex = "spark_streak", life = { 0.14, 0.2 }, size = { { 0, 0.4 }, { 0.3, 1.8 }, { 1, 0.3 } },
		transp = { { 0, 1 }, { 0.25, 0 }, { 1, 0.5 } }, speed = { 26, 34 }, rot = { 90 }, vpar = true, bright = 2 })

	-- muzzle ------------------------------------------------------------------------------------------------
	local mRings = { Kit.plate(ctx, "MuzzleRing", "shock_ring", 2), Kit.plate(ctx, "MuzzleRing", "shock_ring", 2), Kit.plate(ctx, "MuzzleRing", "shock_ring", 2) }
	local mInk = Kit.plate(ctx, "MuzzleInk", "shock_ring", 1)
	mInk.beam.LightEmission = 0
	local kick = Kit.flat(ctx, "KickRing", { tex = "shock_ring", life = 0.36, size = { { 0, 3 }, { 0.25, 11 }, { 1, 17 } },
		transp = { { 0, 0.1 }, { 0.5, 0.45 }, { 1, 1 } }, z = 1 })
	local dust = Kit.burst(ctx, "Dust", { tex = "smoke_puff", life = { 0.5, 0.85 }, size = { { 0, 1.4 }, { 1, 4.6 } },
		transp = { { 0, 0.45 }, { 0.5, 0.7 }, { 1, 1 } }, speed = { 12, 24 }, drag = 3.2, rot = { 0, 360 }, rotSpeed = { -60, 60 }, le = 0 })

	-- the beam ----------------------------------------------------------------------------------------------
	local b0, b1 = Kit.att(ctx), Kit.att(ctx)
	local function layer(name: string, z: number): Beam
		local b = Kit.beam(ctx, b0, b1, "bolt_glow", z)
		b.Name = name
		b.Segments = 1
		b.Enabled = false
		return b
	end
	local ink = layer("BeamInk", -1)
	ink.LightEmission = 0
	local sheath = layer("BeamSheath", 0)
	local body = layer("BeamBody", 1)
	local core = layer("BeamCore", 2)
	core.Brightness = 3
	local thread = layer("BeamThread", 3)
	thread.Brightness = 4
	local layers = { ink, sheath, body, core, thread }

	-- two strands wound round the first stretch of the beam (smooth: each segment is a curved Beam)
	local HELIX_N, HELIX_STEP = 13, 2.1 * S
	local strands = {}
	for s = 1, 2 do
		local atts, beams = {}, {}
		for i = 1, HELIX_N do
			atts[i] = Kit.att(ctx)
		end
		for i = 1, HELIX_N - 1 do
			local b = Kit.beam(ctx, atts[i], atts[i + 1], "bolt_glow", 3)
			b.Name = "Strand"
			b.Segments = 6
			b.CurveSize0, b.CurveSize1 = HELIX_STEP * 0.42, HELIX_STEP * 0.42
			b.Enabled = false
			beams[i] = b
		end
		strands[s] = { atts = atts, beams = beams, ph = (s - 1) * math.pi }
	end
	-- pulse rings running down the beam
	local pulses = {}
	for i = 1, 5 do
		pulses[i] = Kit.plate(ctx, "Pulse", "shock_ring", 2)
	end

	-- the far end -------------------------------------------------------------------------------------------
	local endGlow = Kit.sprite(ctx, "EndGlow", "glow_soft", 4)
	local endHalo = Kit.sprite(ctx, "EndHalo", "glow_soft", 2)
	local endStar = Kit.sprite(ctx, "EndStar", "spark_glint", 5)
	local endRings = { Kit.plate(ctx, "EndRing", "shock_ring", 2), Kit.plate(ctx, "EndRing", "shock_ring", 2) }
	local endInk = Kit.plate(ctx, "EndInk", "shock_ring", 1)
	endInk.beam.LightEmission = 0
	local endSpikes = {}
	for i = 1, 9 do
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local b = Kit.beam(ctx, a0, a1, "bolt_glow", 3)
		b.Name = "EndSpike"
		b.Segments = 1
		b.Width1 = 0
		b.Enabled = false
		endSpikes[i] = { a0 = a0, a1 = a1, b = b }
	end
	local splash = Kit.burst(ctx, "Splash", { tex = "spark_streak", life = { 0.18, 0.4 }, size = { { 0, 0.5 }, { 0.2, 2.2 }, { 1, 0.3 } },
		transp = { { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } }, speed = { 30, 70 }, drag = 3.5, acc = Vector3.new(0, -40 * S, 0), rot = { 90 }, vpar = true, bright = 2.5 })
	local glints = Kit.burst(ctx, "Glints", { tex = "spark_glint", life = { 0.2, 0.45 }, size = { { 0, 0 }, { 0.2, 1.4 }, { 1, 0 } },
		speed = { 10, 30 }, drag = 4, rot = { 0, 360 }, rotSpeed = { -160, 160 }, bright = 3 })
	local smoke = Kit.burst(ctx, "Smoke", { tex = "smoke_puff", life = { 0.6, 1.0 }, size = { { 0, 1.8 }, { 1, 6 } },
		transp = { { 0, 0.5 }, { 0.5, 0.72 }, { 1, 1 } }, speed = { 5, 14 }, drag = 2, acc = Vector3.new(0, 5 * S, 0), rot = { 0, 360 },
		rotSpeed = { -50, 50 }, le = 0 })

	local lightPart = Kit.part(ctx, ctx.root, "Light", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightPart.Transparency = 1
	local light = Kit.light(ctx, lightPart, 26 * S)

	local once = Kit.once()
	local nIn, nSplash = 0, 0
	-- a stable frame across the beam
	local side = dir:Cross(Vector3.yAxis)
	side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
	local upv = side:Cross(dir).Unit

	return function(t: number)
		if rig then
			rig.apply(Pose.sample(KEYS, t))
			if rig.root0 then
				-- tremble while charging, a shove back on the shot
				local tr = if t < CHARGE then 0.03 * S * Kit.ramp(t, 0.1, CHARGE) * math.sin(t * 95) else 0
				local back = 0.5 * S * (Kit.ramp(t, CHARGE, CHARGE + 0.05) - Kit.smooth(Kit.ramp(t, BLAST_END, ChargeBeam.life)))
				rig.move(rig.root0 * CFrame.new(tr, 0, back))
			end
		end
		local h = Kit.hue(ctx, t, 0)
		local fl = Kit.slotRng(seed, t, 1 / 30):NextNumber()
		local span = if rainbow then 1 else 0.08
		local fired = t >= CHARGE

		-- charge --------------------------------------------------------------------------------------------
		local cu = Kit.ramp(t, 0, CHARGE)
		local swell = Kit.easeIn(cu)
		local squeeze = Kit.ramp(t, CHARGE - 0.05, CHARGE) -- the orb crushes down an instant before the shot
		if not fired then
			local d = (0.35 + 1.75 * swell) * (1 - 0.45 * squeeze) * (0.9 + 0.1 * fl) * S
			orb.Size = Vector3.one * d
			orb.CFrame = CFrame.new(M)
			orb.Color = Kit.hot(h)
			orbGlow.beam.Color = ColorSequence.new(Kit.hot(h))
			orbGlow.set(M, d * 2.6, 0.15 + 0.2 * fl)
			orbHalo.beam.Color = ColorSequence.new(Kit.col(h, 0.85, 1))
			orbHalo.set(M, d * 5.2 + 2 * S * swell, 0.55 - 0.15 * swell + 0.1 * fl)
		else
			-- during the blast the orb is the root of the beam
			local k = 1 - Kit.ramp(t, BLAST_END, BLAST_END + 0.1)
			orb.CFrame = if k > 0 then CFrame.new(M) else Kit.HIDE
			orb.Size = Vector3.one * (2.3 + 0.4 * fl) * k * S
			orb.Color = Kit.hot(h)
			orbGlow.beam.Color = ColorSequence.new(Kit.hot(h))
			orbGlow.set(M, (6.5 + 1.5 * fl) * k * S, 0.1 + 0.2 * fl)
			orbHalo.beam.Color = ColorSequence.new(Kit.col(h, 0.85, 1))
			orbHalo.set(M, (12 + 2 * fl) * k * S, 0.5)
		end
		for i, r in rays do
			if t < CHARGE - 0.03 then
				local cyc = t / r.per + r.ph
				local u = cyc % 1
				local rr = Random.new(seed * 131 + i * 977 + math.floor(cyc))
				local d = Vector3.new(rr:NextNumber(-1, 1), rr:NextNumber(-1, 1), rr:NextNumber(-1, 1))
				d = if d.Magnitude > 1e-3 then d.Unit else Vector3.yAxis
				if d:Dot(dir) < -0.2 then
					d = d - dir * 2 * d:Dot(dir) -- keep rays out of the caster's body
				end
				local R = (7 + 3 * rr:NextNumber()) * S
				local head = R * (1 - Kit.easeIn(u))
				local len = (1.2 + 2.6 * u) * S
				r.a0.CFrame = CFrame.new(M + d * (head + len))
				r.a1.CFrame = CFrame.new(M + d * math.max(head, 0.3 * S))
				r.b.Width0, r.b.Width1 = 0, (0.22 + 0.3 * swell) * S
				local hr = Kit.hue(ctx, t, i / #rays)
				r.b.Color = ColorSequence.new(Kit.col(hr, 0.9, 1), Kit.hot(hr))
				r.b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1 + 0.5 * (1 - u)) })
				r.b.Enabled = true
			else
				r.b.Enabled = false
			end
		end
		for i, g in gather do
			local u = Kit.ramp(t, 0.05 + (i - 1) * 0.17, 0.27 + (i - 1) * 0.17)
			g.beam.Color = Kit.hueSeq(Kit.hue(ctx, t, i * 0.3), 0.4 * span, 0.8, 1, 4)
			g.set(M, dir, (10 - 8.5 * Kit.easeIn(u)) * S, if u <= 0 or u >= 1 then 1 else 1 - 0.8 * math.sin(u * math.pi) ^ 0.6, t * 4 + i)
		end
		local wantIn = if t < CHARGE - 0.08 then math.floor(t / 0.03) else nIn
		if wantIn > nIn then
			nIn = wantIn
			streakIn.Color = ColorSequence.new(Kit.col(Kit.hue(ctx, t, rng:NextNumber()), 0.75, 1), Kit.hot(h))
			for _ = 1, 2 do
				local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
				d = if d.Magnitude > 1e-3 then d.Unit else Vector3.yAxis
				if d:Dot(dir) < 0 then
					d = d - dir * 2 * d:Dot(dir)
				end
				ctx.host.CFrame = Kit.upTo(M + d * rng:NextNumber(4.5, 6) * S, -d)
				streakIn:Emit(1)
			end
		end

		-- fire ----------------------------------------------------------------------------------------------
		if once("fire", t, CHARGE) then
			aim()
			if ground then
				local gp = ground.Position + Vector3.new(0, 0.05, 0)
				kick.fire(CHARGE, gp, Kit.hueSeq(h, 0.5 * span, 0.6, 1, 4))
				Kit.spray(ctx, dust, gp + Vector3.new(0, 0.6 * S, 0), 12, ColorSequence.new(Color3.fromHSV(h, 0.2, 0.6)), "disc", 1.5, 0.15)
			end
			Kit.spray(ctx, glints, M, 14, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.2)), "sphere", 0.5)
		end
		kick.update(t)
		local mu = Kit.ramp(t, CHARGE, CHARGE + 0.12)
		local hold = if fired then 1 - Kit.ramp(t, BLAST_END, BLAST_END + 0.08) else 0
		star.beam.Color = ColorSequence.new(Kit.hot(h))
		star2.beam.Color = ColorSequence.new(Kit.col(h + 0.15, 0.5, 1))
		if fired and hold > 0 then
			star.set(M, (19 * (1 - Kit.easeOut(mu)) + 7 + 2 * fl) * hold * S, 0.05 + 0.25 * fl, t * 1.7, 1)
			star2.set(M, (12 * (1 - mu) + 5 + 1.5 * fl) * hold * S, 0.3, -t * 2.3 + 0.8, 1)
		elseif not fired then
			star.set(M, 5 * swell * (0.7 + 0.3 * fl) * S, 0.3, t * 3, 1)
			star2.hide()
		else
			star.hide()
			star2.hide()
		end
		for i, r in mRings do
			local u = Kit.ramp(t, CHARGE + (i - 1) * 0.05, CHARGE + 0.24 + (i - 1) * 0.05)
			r.beam.Color = Kit.hueSeq(Kit.hue(ctx, t, i * 0.25), 0.5 * span, 0.6, 1, 4)
			r.set(M + dir * (0.4 + (i - 1) * 2.2 * u) * S, dir, (3 + (13 - i * 2) * Kit.easeOut(u)) * S, if u <= 0 or u >= 1 then 1 else 0.05 + 0.95 * Kit.easeIn(u), i * 1.1)
		end
		local iu = Kit.ramp(t, CHARGE + 0.02, CHARGE + 0.32)
		mInk.beam.Color = ColorSequence.new(Kit.ink(h))
		mInk.set(M - dir * 0.2 * S, dir, (4 + 14 * Kit.easeOut(iu)) * S, if iu <= 0 or iu >= 1 then 1 else 0.2 + 0.8 * iu, 2)

		-- the beam ------------------------------------------------------------------------------------------
		local len = (E - M).Magnitude
		local reach = Kit.ramp(t, CHARGE, CHARGE + REACH)
		local thin = Kit.easeOut(Kit.ramp(t, BLAST_END, BLAST_END + 0.07)) -- collapses to a thread
		local tail = Kit.easeIn(Kit.ramp(t, BLAST_END + 0.03, GONE)) -- the tail races to the far end
		local on = fired and t < GONE and reach > 0
		if on then
			local punch = 1 + 0.55 * (1 - Kit.ramp(t, CHARGE, CHARGE + 0.1)) -- fat on the first frames
			local w = (1 - 0.93 * thin) * punch * (0.93 + 0.07 * fl) * S
			b0.CFrame = CFrame.new(M + dir * len * tail)
			b1.CFrame = CFrame.new(M + dir * len * reach)
			local scroll = h - t * 1.6
			ink.Width0, ink.Width1 = 13 * w, 14.5 * w
			ink.Color = ColorSequence.new(Kit.ink(h))
			ink.Transparency = NumberSequence.new(0.35 + 0.5 * thin)
			sheath.Width0, sheath.Width1 = 9.5 * w, 11 * w
			sheath.Color = Kit.hueSeq(scroll, span, 0.95, 1, 7)
			sheath.Transparency = NumberSequence.new(0.35 + 0.2 * fl)
			body.Width0, body.Width1 = 6 * w, 6.8 * w
			body.Color = Kit.hueSeq(scroll + 0.12, span, 0.55, 1, 7)
			body.Transparency = NumberSequence.new(0.15)
			core.Width0, core.Width1 = 3.3 * w, 3.8 * w
			core.Color = ColorSequence.new(Kit.hot(h))
			core.Transparency = NumberSequence.new(0)
			thread.Width0, thread.Width1 = math.max(1.1 * w, 0.3 * S), math.max(1.3 * w, 0.3 * S)
			thread.Color = ColorSequence.new(Color3.new(1, 1, 1))
			thread.Transparency = NumberSequence.new(0.6 * tail)
		end
		for _, b in layers do
			b.Enabled = on
		end

		-- strands and pulse rings
		local live = on and thin < 0.5
		for _, st in strands do
			for i = 1, HELIX_N do
				local d = (i - 1) * HELIX_STEP + 1.5 * S
				local ang = d / (4.2 * S) - t * 22 + st.ph
				local rad = (1.6 + 1.9 * math.min(1, d / (9 * S))) * S * (1 + 0.6 * (1 - Kit.ramp(t, CHARGE, CHARGE + 0.14)))
				local c, s = math.cos(ang), math.sin(ang)
				local p = M + dir * d + (side * c + upv * s) * rad
				local tan = dir * 4.2 * S + (upv * c - side * s) * rad
				st.atts[i].CFrame = Kit.rightTo(p, tan)
			end
			for i, b in st.beams do
				local d = (i - 0.5) * HELIX_STEP + 1.5 * S
				local vis = live and d < len * reach - HELIX_STEP
				b.Enabled = vis
				if vis then
					local f = (i - 1) / (HELIX_N - 1)
					local f2 = i / (HELIX_N - 1)
					local hs = Kit.hue(ctx, t, f * 0.6 + st.ph)
					b.Color = ColorSequence.new(Kit.col(hs, 0.75, 1), Kit.col(hs + 0.05, 0.75, 1))
					b.Width0, b.Width1 = 0.85 * S * (1 - 0.7 * f), 0.85 * S * (1 - 0.7 * f2)
					b.Transparency = NumberSequence.new(0.05 + 0.9 * f * f, 0.05 + 0.9 * f2 * f2)
				end
			end
		end
		for i, p in pulses do
			local u = ((t - CHARGE) * 1.9 + i / #pulses) % 1
			local d = u * math.min(len, 46 * S)
			if live and d < len * reach then
				p.beam.Color = Kit.hueSeq(Kit.hue(ctx, t, i / #pulses), 0.3 * span, 0.7, 1, 4)
				p.set(M + dir * d, dir, (6 + 7 * u) * S, 0.3 + 0.7 * u, i + t * 3)
			else
				p.hide()
			end
		end

		-- the far end ---------------------------------------------------------------------------------------
		local arrived = fired and reach >= 1
		local burn = if arrived then 1 - Kit.ramp(t, BLAST_END + 0.08, GONE + 0.2) else 0
		local pop = if arrived then 1 - Kit.ramp(t, CHARGE + REACH, CHARGE + REACH + 0.1) else 0
		local ep = E + N * 0.35 * S
		if burn > 0 then
			endGlow.beam.Color = ColorSequence.new(Kit.hot(h))
			endGlow.set(ep, (7 + 2.5 * fl + 7 * pop) * burn * S, 0.05 + 0.25 * fl)
			endHalo.beam.Color = ColorSequence.new(Kit.col(h + 0.1, 0.85, 1))
			endHalo.set(ep, (15 + 3 * fl + 10 * pop) * burn * S, 0.5)
			endStar.beam.Color = ColorSequence.new(Kit.hot(h + 0.2))
			endStar.set(ep, (11 + 4 * fl + 14 * pop) * burn * S, 0.1 + 0.3 * fl, -t * 2.1, 1)
		else
			endGlow.hide()
			endHalo.hide()
			endStar.hide()
		end
		for i, r in endRings do
			local u = if arrived and t < BLAST_END + 0.1 then ((t - CHARGE - REACH) / 0.26 + (i - 1) * 0.5) % 1 else 1
			r.beam.Color = Kit.hueSeq(Kit.hue(ctx, t, i * 0.4), 0.5 * span, 0.65, 1, 4)
			r.set(E + N * 0.12 * S, N, (4 + 13 * Kit.easeOut(u)) * S, if u >= 1 then 1 else 0.1 + 0.9 * u, i * 2)
		end
		local eu = if arrived then Kit.ramp(t, CHARGE + REACH, CHARGE + REACH + 0.4) else 0
		endInk.beam.Color = ColorSequence.new(Kit.ink(h))
		endInk.set(E + N * 0.08 * S, N, (6 + 18 * Kit.easeOut(eu)) * S, if eu <= 0 or eu >= 1 then 1 else 0.25 + 0.75 * eu, 1)
		-- spikes that re-roll 30 times a second
		local sr = Kit.slotRng(seed + 31, t, 1 / 30)
		local t1 = N:Cross(Vector3.yAxis)
		t1 = if t1.Magnitude > 1e-3 then t1.Unit else Vector3.xAxis
		local t2 = N:Cross(t1)
		for i, sp in endSpikes do
			local a = (i + sr:NextNumber()) / #endSpikes * math.pi * 2
			local L = sr:NextNumber(4, 10) * S * (1 + pop)
			if arrived and burn > 0.5 and thin < 0.5 then
				local d = (t1 * math.cos(a) + t2 * math.sin(a) + N * sr:NextNumber(0.15, 0.9)).Unit
				sp.a0.CFrame = CFrame.new(ep + d * 1.2 * S)
				sp.a1.CFrame = CFrame.new(ep + d * L)
				sp.b.Width0 = sr:NextNumber(0.5, 1.1) * S
				local hs = Kit.hue(ctx, t, i / #endSpikes)
				sp.b.Color = ColorSequence.new(Kit.hot(hs), Kit.col(hs, 0.9, 1))
				sp.b.Transparency = NumberSequence.new(0.1, 0.5)
				sp.b.Enabled = true
			else
				sp.b.Enabled = false
			end
		end
		if arrived and t < BLAST_END + 0.05 then
			local want = math.floor((t - CHARGE - REACH) / 0.04) + 1
			if want > nSplash then
				local first = nSplash == 0
				nSplash = want
				local hs = Kit.hue(ctx, t, rng:NextNumber())
				splash.Color = ColorSequence.new(Kit.hot(hs), Kit.col(hs, 0.85, 1))
				for _ = 1, if first then 16 else 3 do
					local a = rng:NextNumber(0, math.pi * 2)
					local d = t1 * math.cos(a) + t2 * math.sin(a) + N * rng:NextNumber(0.2, 1.3)
					ctx.host.CFrame = Kit.upTo(ep, d)
					splash:Emit(1)
				end
				if first then
					Kit.spray(ctx, glints, ep, 12, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.3)), "sphere", 1)
				end
				if struck and (first or want % 3 == 0) then
					smoke.Color = ColorSequence.new(Color3.fromHSV((h + 0.5) % 1, 0.35, 0.3))
					local a = rng:NextNumber(0, math.pi * 2)
					ctx.host.CFrame = Kit.upTo(ep + (t1 * math.cos(a) + t2 * math.sin(a)) * 1.5 * S, N + (t1 * math.cos(a) + t2 * math.sin(a)) * 0.8)
					smoke:Emit(if first then 4 else 1)
				end
			end
		end

		-- one light: at the orb while charging, at the far end during the blast
		lightPart.CFrame = CFrame.new(if arrived then ep + N * 1.5 * S else M)
		light.Color = Kit.col(h, 0.45, 1)
		light.Brightness = if fired then (4 + 1.5 * fl + 5 * pop) * math.max(burn, hold) else 3.5 * swell
	end
end

function ChargeBeam.shake(t: number): Vector3
	local k: number
	if t < CHARGE then
		k = 0.05 * Kit.easeIn(t / CHARGE)
	elseif t < BLAST_END then
		k = 0.6 * math.exp(-(t - CHARGE) * 11) + 0.11
	else
		k = 0.11 * (1 - Kit.ramp(t, BLAST_END, GONE))
	end
	return Vector3.new(math.sin(t * 83) * k, math.cos(t * 97) * k, 0)
end

return ChargeBeam
