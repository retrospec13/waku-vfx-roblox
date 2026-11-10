--!strict
--[[ PrismCleave: a charged dash-slash, cinematic beat by beat.
	0.00-0.28  CHARGE: arms cross at the chest, a starburst of white-hot spikes with rainbow halos, flash, glints
	0.10-0.80  AURA: soft glow orb plus two rainbow swirl arcs orbiting the caster
	0.30-0.86  WIND-UP: low wide stance, blade arm drawn back; three tilted rainbow crescent rings spin round the
	           caster and tighten, white-hot edge bands on their heads
	0.86       DASH: the caster lunges 14 studs forward in 0.07 s. One long white-hot slash line runs the whole
	           rainbow along the path, with a lens-flare star at the cut and a forward crescent wave.
	0.88-1.70  AFTERMATH: two jagged walls of spray erupt along both sides of the path in a ripple, rainbow from
	           near to far. Plus a glowing ground scar that cools to ink, debris, dust and a hard light kick.
	1.70-2.10  hold, the scar fades, the dash ghost fades out; the caster is restored where it started
	cf = caster root CFrame (LookVector = dash direction). opts.caster = R15 model to pose (optional). Life 2.1 s. ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)
local Pose = require(script.Parent.Parent.Pose)

local PrismCleave = {}
PrismCleave.life = 2.1
PrismCleave.required = { "slash_body", "slash_edge", "bolt_glow", "spark_streak", "spark_glint", "glow_soft", "smoke_puff", "ice_shard" }

local A, arm = Pose.A, Pose.arm
local DASH_T, DASH_END, DASH_D = 0.86, 0.93, 14
local KEYS: { Pose.Key } = {
	{ t = 0.0, p = {} },
	{ t = 0.12, p = { -- charge: blades crossed at the chest, slight crouch
		Root = CFrame.new(0, -0.3, 0), Waist = A(-6, 0, 0), Neck = A(-8, 0, 0),
		RightShoulder = arm(78, 48, 0), LeftShoulder = arm(78, -48, 0), RightElbow = A(62, 0, 0), LeftElbow = A(62, 0, 0),
		RightHip = A(14, 0, 0), LeftHip = A(14, 0, 0), RightKnee = A(-22, 0, 0), LeftKnee = A(-22, 0, 0) } },
	{ t = 0.28, p = "SAME" :: any },
	{ t = 0.45, p = { -- wind-up: low wide stance, torso coiled, blade arm drawn back, guard arm forward
		Root = CFrame.new(0, -0.95, 0) * A(-8, 30, 0), Waist = A(-4, 28, 0), Neck = A(0, -40, 0),
		RightShoulder = arm(20, -50, 75), RightElbow = A(25, 0, 0),
		LeftShoulder = arm(85, 15, 0), LeftElbow = A(10, 0, 0),
		RightHip = A(55, 0, 18), LeftHip = A(20, 0, -22), RightKnee = A(-75, 0, 0), LeftKnee = A(-35, 0, 0) } },
	{ t = 0.84, p = "SAME2" :: any },
	{ t = 0.92, p = { -- the cut: lunged low, blade arm swept through to the front-left, guard arm thrown back
		Root = CFrame.new(0, -1.05, 0) * A(-22, -30, 0), Waist = A(-12, -35, 0), Neck = A(10, 40, 0),
		RightShoulder = arm(88, 70, 0), RightElbow = A(4, 0, 0),
		LeftShoulder = arm(-25, 0, -55), LeftElbow = A(15, 0, 0),
		RightHip = A(75, 0, 0), LeftHip = A(-35, 0, 0), RightKnee = A(-80, 0, 0), LeftKnee = A(-20, 0, 0) } },
	{ t = 1.55, p = "SAME3" :: any },
	{ t = 1.95, p = { Root = CFrame.new(0, -0.3, 0), RightShoulder = arm(30, 30, 0), LeftShoulder = arm(10, 0, -20) } },
	{ t = 2.1, p = "SAME4" :: any },
}
KEYS[3].p = KEYS[2].p
KEYS[5].p = KEYS[4].p
KEYS[7].p = KEYS[6].p
KEYS[9].p = KEYS[8].p

type Arc = { atts: { Attachment }, body: { Beam }, edge: { Beam } }
local NSEG = 12

function PrismCleave.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local cf = ctx.cf
	local fwd = (cf.LookVector * Vector3.new(1, 0, 1)).Unit
	local right = fwd:Cross(Vector3.yAxis).Unit
	local params = RaycastParams.new()
	local ex: { Instance } = { ctx.root }
	if ctx.opts.caster then
		table.insert(ex, ctx.opts.caster)
	end
	params.FilterDescendantsInstances = ex
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(cf.Position, Vector3.new(0, -14, 0), params)
	local gy = if hit then hit.Position.Y else cf.Position.Y - 3
	local ground = Vector3.new(cf.X, gy, cf.Z)
	local chest = cf.Position + Vector3.yAxis * 0.6 * S
	local once = Kit.once()
	local rng = ctx.rng
	local rig = Pose.rig(ctx, ctx.opts.caster)

	------------------------------------------------------------------ helpers
	local function newArc(name: string): Arc
		local atts, body, edge = {}, {}, {}
		for k = 0, NSEG do
			atts[k + 1] = Kit.att(ctx)
		end
		for k = 1, NSEG do
			local b = Kit.beam(ctx, atts[k], atts[k + 1], "slash_body", 0)
			b.Name = name .. "Body"
			b.FaceCamera = false
			b.Segments = 10
			b.LightEmission = 0.8
			b.Brightness = 2
			body[k] = b
			local e = Kit.beam(ctx, atts[k], atts[k + 1], "slash_edge", 1)
			e.Name = name .. "Edge"
			e.FaceCamera = false
			e.Segments = 10
			e.Brightness = 7
			edge[k] = e
		end
		return { atts = atts, body = body, edge = edge }
	end
	local function hideArc(a: Arc)
		for k = 1, NSEG do
			a.body[k].Enabled = false
			a.edge[k].Enabled = false
		end
	end
	-- crescent in the plane (u, v) round centre: from angle th0, `span` long (sign = direction), radius R, thickness
	-- tapering to points; vis(f) = visibility along the arc (f 0 = tail, 1 = head); hue run h0..h0+hs
	local function drawArc(a: Arc, center: Vector3, u: Vector3, v: Vector3, th0: number, span: number, R: number,
		thick: number, vis: (number) -> number, h0: number, hs: number, edgeBand: number)
		local dir = if span >= 0 then 1 else -1
		for k = 0, NSEG do
			local f = k / NSEG
			local w = thick * (0.04 + 0.96 * math.sin(math.pi * f) ^ 0.7)
			local th = th0 + span * f
			local radial = u * math.cos(th) + v * math.sin(th)
			local tang = (u * -math.sin(th) + v * math.cos(th)) * dir
			a.atts[k + 1].CFrame = CFrame.fromMatrix(center + radial * (R - w / 2), tang, radial)
			if k > 0 then
				a.body[k].Width1 = w
				a.edge[k].Width1 = w
			end
			if k < NSEG then
				a.body[k + 1].Width0 = w
				a.edge[k + 1].Width0 = w
			end
		end
		local kc = 4 / 3 * math.tan(math.abs(span) / NSEG / 4) * R
		for k = 1, NSEG do
			local fa, fb = (k - 1) / NSEG, k / NSEG
			local pb, pe = {}, {}
			for q = 0, 4 do
				local f = fa + (fb - fa) * q / 4
				local vv = vis(f)
				table.insert(pb, { q / 4, 1 - vv })
				table.insert(pe, { q / 4, 1 - vv * Kit.smooth((f - (1 - edgeBand)) / edgeBand) })
			end
			local b, e = a.body[k], a.edge[k]
			b.Enabled, e.Enabled = true, true
			b.CurveSize0, b.CurveSize1, e.CurveSize0, e.CurveSize1 = kc, kc, kc, kc
			b.Transparency = Kit.numSeq(pb)
			e.Transparency = Kit.numSeq(pe)
			b.Color = Kit.hueSeq(h0 + hs * fa, hs / NSEG, 0.85, 1, 2)
			e.Color = ColorSequence.new(Kit.hot(h0 + hs * fb))
		end
	end
	-- straight glowing streak: core + halo beams between two points (camera-facing)
	type Streak = { a0: Attachment, a1: Attachment, core: Beam, halo: Beam }
	local function newStreak(name: string): Streak
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local halo = Kit.beam(ctx, a0, a1, "bolt_glow", 0)
		halo.Name = name .. "Halo"
		halo.Segments = 1
		halo.Brightness = 3
		local core = Kit.beam(ctx, a0, a1, "bolt_glow", 1)
		core.Name = name .. "Core"
		core.Segments = 1
		core.Brightness = 6
		return { a0 = a0, a1 = a1, core = core, halo = halo }
	end

	------------------------------------------------------------------ layers
	-- starburst spikes
	type Spike = { s: Streak, dir: Vector3, len: number, hue: number }
	local spikes: { Spike } = {}
	for k = 1, 22 do
		local az = rng:NextNumber(0, math.pi * 2)
		local el = rng:NextNumber(-0.35, 1.1)
		local d = Vector3.new(math.cos(az), el, math.sin(az)).Unit
		table.insert(spikes, { s = newStreak("Spike"), dir = d, len = rng:NextNumber(3.5, 8) * S, hue = k / 22 })
	end
	-- aura swirls and vortex rings
	local swirls = { newArc("Swirl1"), newArc("Swirl2") }
	local rings = { newArc("Ring1"), newArc("Ring2"), newArc("Ring3") }
	local RING_TILT = { 0, math.rad(28), math.rad(-22) }
	local RING_R = { 3.6, 4.4, 5.2 }
	local RING_W = { 13, -11, 9.5 } -- spin, rad/s
	local wave = newArc("Wave")
	-- the cut line along the dash path (bulging width: two halves)
	local cutA, cutB = newStreak("CutA"), newStreak("CutB")
	-- spray walls: jagged spikes along both sides of the path
	type Spray = { s: Streak, d: number, side: number, h: number, hue: number, t0: number, base: Vector3 }
	local sprays: { Spray } = {}
	for i = 0, 15 do
		local d = (2 + i * 1.45) * S
		for _, side in { -1, 1 } do
			for j = 1, 2 do
				local lat = (1.8 + d * 0.06 + rng:NextNumber(-0.3, 0.5)) * side
				local base = ground + fwd * (d + rng:NextNumber(-0.5, 0.5)) + right * lat
				local sk = newStreak("Spray")
				sk.core.Brightness = 3.5
				sk.halo.Brightness = 2.5
				table.insert(sprays, { s = sk, d = d, side = side, h = rng:NextNumber(4, 8) * S * (1 - d / (45 * S)),
					hue = d / (26 * S), t0 = DASH_T + 0.02 + d / S * 0.006 + j * 0.015, base = base })
			end
		end
	end
	-- ground scar: a flat ribbon lying along the path
	local scarA0, scarA1 = Kit.att(ctx), Kit.att(ctx)
	local scar = Kit.beam(ctx, scarA0, scarA1, "slash_edge", -1)
	scar.Name = "Scar"
	scar.FaceCamera = false
	scar.Segments = 1
	scar.TextureMode = Enum.TextureMode.Stretch

	local flash = Kit.burst(ctx, "Flash", { tex = "glow_soft", life = { 0.1 }, size = { { 0, 4 }, { 0.4, 8 }, { 1, 9 } },
		transp = { { 0, 0.2 }, { 0.5, 0.55 }, { 1, 1 } }, bright = 3, zoff = 3 })
	local orb = Kit.burst(ctx, "Orb", { tex = "glow_soft", life = { 0.7 }, size = { { 0, 3 }, { 0.3, 8 }, { 1, 9 } },
		transp = { { 0, 1 }, { 0.2, 0.55 }, { 0.8, 0.65 }, { 1, 1 } }, bright = 2, zoff = 1 })
	local glints = Kit.burst(ctx, "Glints", { tex = "spark_glint", life = { 0.18, 0.3 }, size = { { 0, 0 }, { 0.2, 3 }, { 1, 0 } },
		speed = { 0.5, 2 }, spread = 180, rot = { 0, 30 }, bright = 6, zoff = 2 })
	local star = Kit.burst(ctx, "Star", { tex = "spark_glint", life = { 0.22 }, size = { { 0, 4 }, { 0.15, 16 }, { 1, 0 } },
		rot = { 0, 0 }, bright = 9, zoff = 4 })
	local sparks = Kit.burst(ctx, "Sparks", { tex = "spark_streak", life = { 0.25, 0.5 }, size = { { 0, 1.1 }, { 1, 0 } },
		speed = { 30, 55 }, spread = 22, drag = 3.5, acc = Vector3.new(0, -30, 0), vpar = true, bright = 4 })
	local spray = Kit.burst(ctx, "SprayPuff", { tex = "smoke_puff", life = { 0.45, 0.8 }, size = { { 0, 1.2 }, { 1, 3.6 } },
		transp = { { 0, 0.35 }, { 0.5, 0.6 }, { 1, 1 } }, speed = { 10, 18 }, spread = 20, drag = 3, acc = Vector3.new(0, -6, 0),
		rot = { 0, 360 }, rotSpeed = { -90, 90 }, le = 0.5, bright = 1 })
	local debris = Kit.burst(ctx, "Debris", { tex = "ice_shard", life = { 0.5, 0.9 }, size = { { 0, 1.2 }, { 1, 0.4 } },
		speed = { 14, 28 }, spread = 25, drag = 1.5, acc = Vector3.new(0, -50, 0), rot = { 0, 360 }, rotSpeed = { -500, 500 }, le = 0, bright = 1 })
	local lightHost = Kit.part(ctx, ctx.root, "LightHost", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightHost.Transparency = 1
	local light = Kit.light(ctx, lightHost, 26 * S)

	local function streakSet(s: Streak, p0: Vector3, p1: Vector3, w0: number, w1: number, vis: number, hot: Color3, halo: ColorSequence, haloMul: number)
		s.a0.CFrame = CFrame.new(p0)
		s.a1.CFrame = CFrame.new(p1)
		local on = vis > 0.01
		s.core.Enabled, s.halo.Enabled = on, on
		if on then
			s.core.Width0, s.core.Width1 = w0 * 0.35, w1 * 0.35
			s.halo.Width0, s.halo.Width1 = w0 * haloMul, w1 * haloMul
			s.core.Color = ColorSequence.new(hot)
			s.halo.Color = halo
			s.core.Transparency = NumberSequence.new(1 - vis)
			s.halo.Transparency = NumberSequence.new(1 - vis * 0.8)
		end
	end

	return function(t: number)
		local h = Kit.hue(ctx, t, 0)
		-- caster pose + dash
		local dashD = DASH_D * S * Kit.easeOut(Kit.ramp(t, DASH_T, DASH_END))
		if rig then
			rig.apply(Pose.sample(KEYS, t))
			if rig.root0 then
				rig.move(rig.root0 + fwd * dashD)
			end
			rig.fade(Kit.ramp(t, 1.75, 1.98))
		end
		local casterPos = chest + fwd * dashD

		-- CHARGE starburst
		for _, sp in spikes do
			local g = Kit.easeOut(Kit.ramp(t, 0.0, 0.07))
			local fade = 1 - Kit.ramp(t, 0.1, 0.28)
			local L = sp.len * g * (1 + 0.25 * Kit.ramp(t, 0.07, 0.28))
			local p0 = chest + sp.dir * (0.6 + 0.8 * Kit.ramp(t, 0.07, 0.28)) * S
			streakSet(sp.s, p0, p0 + sp.dir * L, 0.9 * S, 0.02, if t < 0.28 then fade else 0, Kit.hot(h + sp.hue),
				ColorSequence.new(Kit.col(h + sp.hue, 0.85, 1)), 3.2)
		end
		if once("flash", t, 0.02) then
			Kit.spray(ctx, flash, chest, 1, ColorSequence.new(Kit.hot(h)), "point")
			Kit.spray(ctx, glints, chest, 6, ColorSequence.new(Kit.hot(h)), "sphere", 2.5)
		end
		if once("orb", t, 0.1) then
			Kit.spray(ctx, orb, chest, 1, ColorSequence.new(Kit.col(h + 0.55, 0.55, 1)), "point")
		end

		-- AURA swirls (orbiting arcs)
		for i, a in swirls do
			local on = Kit.ramp(t, 0.1, 0.22) * (1 - Kit.ramp(t, 0.62, 0.8))
			if on > 0 then
				local tilt = if i == 1 then math.rad(70) else math.rad(-60)
				local u = fwd
				local v = (right * math.cos(tilt) + Vector3.yAxis * math.sin(tilt)).Unit
				drawArc(a, chest, u, v, t * (if i == 1 then 10 else -12), math.rad(200) * (if i == 1 then 1 else -1), 2.6 * S, 0.9 * S,
					function(f)
						return on * Kit.smooth(f * 3) * 0.85
					end, h + i * 0.4, 0.5, 0.35)
			else
				hideArc(a)
			end
		end

		-- WIND-UP vortex rings: spin, brighten, tighten, collapse into the dash
		for i, a in rings do
			local on = Kit.ramp(t, 0.3 + i * 0.04, 0.42 + i * 0.04) * (1 - Kit.ramp(t, DASH_T - 0.02, DASH_T + 0.05))
			if on > 0 then
				local tilt = RING_TILT[i]
				local u = fwd
				local v = (right * math.cos(tilt) + Vector3.yAxis * math.sin(tilt)).Unit
				local tighten = Kit.easeIn(Kit.ramp(t, 0.45, DASH_T))
				local R = (RING_R[i] - 1.2 * tighten) * S
				drawArc(a, chest - Vector3.yAxis * 0.4 * S, u, v, t * RING_W[i], math.rad(280) * (if RING_W[i] > 0 then 1 else -1), R,
					(1.1 + 0.5 * tighten) * S, function(f)
						return on * Kit.smooth(f * 2.5)
					end, h + i * 0.33, 0.85, 0.3)
			else
				hideArc(a)
			end
		end
		if once("windglint", t, 0.55) then
			Kit.spray(ctx, glints, chest, 5, ColorSequence.new(Kit.hot(h + 0.3)), "sphere", 4)
		end

		-- DASH: forward crescent wave
		local tw = t - DASH_T
		if tw >= 0 and tw < 0.3 then
			local k = tw / 0.3
			local center = chest + fwd * (2 + 18 * Kit.easeOut(k)) * S - fwd * 5 * S
			drawArc(wave, center, fwd, right, -math.rad(75), math.rad(150), 6 * S, 2.4 * S, function(f)
				return (1 - Kit.easeIn(k)) * Kit.smooth((f - k * 0.5) / 0.2 + 0.5)
			end, h + 0.15, 0.6, 0.4)
		else
			hideArc(wave)
		end
		-- the cut line: draws out in 0.04 s, bulges, thins out
		local tc = t - (DASH_T + 0.01)
		if tc >= 0 and tc < 0.45 then
			local grow = Kit.easeOut(tc / 0.04)
			local vis = 1 - Kit.ramp(tc, 0.12, 0.45)
			local thin = 1 - 0.75 * Kit.ramp(tc, 0.04, 0.45)
			local p0 = chest + fwd * 0.5 * S
			local len = 26 * S * grow
			local mid = p0 + fwd * len * 0.45 + Vector3.yAxis * 0.25 * S
			local p1 = p0 + fwd * len + Vector3.yAxis * 0.6 * S
			local W = 1.5 * S * thin
			streakSet(cutA, p0, mid, 0.05, W, vis, Kit.hot(h), Kit.hueSeq(h, 0.45, 0.9, 1, 4), 3)
			streakSet(cutB, mid, p1, W, 0.03, vis, Kit.hot(h + 0.5), Kit.hueSeq(h + 0.45, 0.55, 0.9, 1, 4), 3)
		else
			cutA.core.Enabled, cutA.halo.Enabled, cutB.core.Enabled, cutB.halo.Enabled = false, false, false, false
		end
		if once("star1", t, DASH_T + 0.03) then
			Kit.spray(ctx, star, chest + fwd * 9 * S, 1, ColorSequence.new(Kit.hot(h)), "point")
			Kit.spray(ctx, flash, chest + fwd * 9 * S, 1, ColorSequence.new(Kit.col(h + 0.1, 0.5, 1)), "point")
		end
		if once("star2", t, DASH_T + 0.08) then
			Kit.spray(ctx, star, chest + fwd * 17 * S + Vector3.yAxis * 0.4, 1, ColorSequence.new(Kit.hot(h + 0.5)), "point")
		end
		-- spray walls ripple along the path, rainbow from near to far
		for _, s in sprays do
			local ts = t - s.t0
			if ts >= 0 and ts < 0.85 then
				local rise = Kit.easeOutBack(ts / 0.08)
				local vis = 1 - Kit.ramp(ts, 0.3, 0.85)
				local lean = s.base + right * s.side * 0.8 * S * rise
				local top = lean + Vector3.yAxis * s.h * rise * (1 - 0.35 * Kit.ramp(ts, 0.3, 0.85))
				streakSet(s.s, s.base, top, 2.0 * S, 0.02, vis, Kit.col(h + s.hue, 0.25, 1), Kit.hueSeq(h + s.hue, 0.08, 0.9, 1, 2), 2.0)
				if once(string.format("sp%.2f_%d", s.d, s.side), ts, 0) then
					local out = (right * s.side + Vector3.yAxis * 1.4).Unit
					Kit.spray(ctx, spray, s.base, 1, ColorSequence.new(Kit.col(h + s.hue, 0.75, 1)), "point", 0, 0, out)
					Kit.spray(ctx, sparks, s.base, 2, ColorSequence.new(Kit.col(h + s.hue, 0.7, 1)), "point", 0, 0, out)
				end
			else
				s.s.core.Enabled, s.s.halo.Enabled = false, false
			end
		end
		if once("debris", t, DASH_T + 0.03) then
			for k = 1, 6 do
				Kit.spray(ctx, debris, ground + fwd * (k * 3.5) * S, 4, ColorSequence.new(Kit.pal(h + k * 0.08).debris), "point", 0, 0,
					(Vector3.yAxis * 1.6 + right * (if k % 2 == 0 then 1 else -1) * 0.6).Unit)
			end
		end
		-- ground scar: glows hot, cools to ink, fades
		local tg = t - (DASH_T + 0.02)
		if tg >= 0 then
			local p0 = ground + fwd * 1 * S + Vector3.yAxis * 0.08
			local len = 24 * S * Kit.easeOut(tg / 0.06)
			scarA0.CFrame = CFrame.fromMatrix(p0, fwd, right)
			scarA1.CFrame = CFrame.fromMatrix(p0 + fwd * len, fwd, right)
			scar.Enabled = true
			scar.Width0, scar.Width1 = 0.6 * S, 1.6 * S
			local cool = Kit.ramp(tg, 0.15, 0.9)
			scar.Brightness = 5 * (1 - cool) + 0.5
			scar.LightEmission = 1 - cool
			local c0 = Kit.hueSeq(h, 0.9, 0.85, 1, 5)
			local kps = {}
			for _, kp in c0.Keypoints do
				table.insert(kps, ColorSequenceKeypoint.new(kp.Time, kp.Value:Lerp(Kit.ink(h + kp.Time), cool)))
			end
			scar.Color = ColorSequence.new(kps)
			scar.Transparency = NumberSequence.new(Kit.ramp(tg, 0.7, 1.2))
		else
			scar.Enabled = false
		end
		-- one light: charge glow, hard kick on the cut, following the caster
		lightHost.CFrame = CFrame.new(casterPos + Vector3.yAxis * 2 * S)
		light.Brightness = 3 * (1 - Kit.ramp(t, 0.05, 0.3)) + 1.5 * Kit.ramp(t, 0.4, DASH_T) * (if t < DASH_T then 1 else 0)
			+ (if t >= DASH_T then 7 * math.exp(-(t - DASH_T) * 6) else 0)
		light.Color = Kit.col(h, 0.4, 1)
	end
end

function PrismCleave.shake(t: number): Vector3
	local a = 0.2 * math.exp(-t * 12) + 0.06 * (if t > 0.4 and t < 0.86 then 1 else 0)
		+ (if t >= 0.86 then 0.9 * math.exp(-(t - 0.86) * 7) else 0)
	return Vector3.new(math.sin(t * 95) * a, math.sin(t * 73 + 1) * a * 0.7, math.sin(t * 61) * a * 0.3)
end

return PrismCleave
