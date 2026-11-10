--!strict
--[[ StormLance: a stab calls the sky down three times.
	0.00-0.30  the caster (optional) lunges into a stab toward the target; the scene darkens to a deep indigo grade
	0.30       STRIKE 1:
	           - white-out flash, then a thick white-hot energy pillar slams down from the sky onto the target;
	           - its halo runs the rainbow along its height;
	           - thin rainbow zigzag bolts crawl round it;
	           - ground flash, shock ring, sparks, radial ground forks.
	0.78       STRIKE 2, hue shifted a third of the wheel
	1.18       STRIKE 3, the biggest: wider pillar, more bolts, scorch crack and static that linger
	1.50-2.00  static arcs thin out, the crack cools to ink, the grade lifts
	The pillar is camera-facing Beams: a white core (Brightness 8) and a rainbow halo, with width flicker on
	0.035 s slots. The bolts are jagged polylines reseeded per slot from a fixed seed, so frozen frames repeat.
	cf = the target point on the ground. opts.caster = R15 model, posed and placed ~8 studs back facing the target
	(optional). opts.grade = false skips the scene grade. Life 2.0 s. ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)
local Pose = require(script.Parent.Parent.Pose)

local StormLance = {}
StormLance.life = 2.0
StormLance.required = { "bolt_glow", "glow_soft", "shock_ring", "ground_crack", "spark_streak", "spark_glint", "smoke_puff" }

local A, arm = Pose.A, Pose.arm
local KEYS: { Pose.Key } = {
	{ t = 0, p = {} },
	{ t = 0.12, p = { -- draw back
		Root = CFrame.new(0, -0.4, 0) * A(0, 25, 0), Waist = A(0, 20, 0),
		RightShoulder = arm(40, -40, 30), RightElbow = A(70, 0, 0), LeftShoulder = arm(60, -10, 0),
		RightHip = A(25, 0, 0), RightKnee = A(-35, 0, 0), LeftHip = A(10, 0, 0), LeftKnee = A(-15, 0, 0) } },
	{ t = 0.24, p = { -- STAB: lunge, blade arm straight at the target
		Root = CFrame.new(0, -0.9, 0) * A(-14, -12, 0), Waist = A(-6, -10, 0), Neck = A(6, 10, 0),
		RightShoulder = arm(92, 8, 0), RightElbow = A(2, 0, 0), LeftShoulder = arm(-20, 0, -40),
		RightHip = A(70, 0, 0), RightKnee = A(-70, 0, 0), LeftHip = A(-30, 0, 0), LeftKnee = A(-25, 0, 0) } },
	{ t = 1.55, p = "SAME" :: any },
	{ t = 2.0, p = {} },
}
KEYS[4].p = KEYS[3].p

type Bolt = { base: { Vector3 }, amp: { number }, atts: { Attachment }, core: { Beam }, glow: { Beam }, width: number }
type Strike = { t: number, hue: number, scale: number, bolts: { Bolt }, forks: { Bolt } }
local STRIKES = { { t = 0.3, hue = 0.0, scale = 1.0 }, { t = 0.78, hue = 0.33, scale = 1.0 }, { t = 1.18, hue = 0.66, scale = 1.35 } }

function StormLance.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local params = RaycastParams.new()
	local ex: { Instance } = { ctx.root }
	if ctx.opts.caster then
		table.insert(ex, ctx.opts.caster)
	end
	params.FilterDescendantsInstances = ex
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(ctx.cf.Position + Vector3.new(0, 6, 0), Vector3.new(0, -16, 0), params)
	local gy = if hit then hit.Position.Y else ctx.cf.Position.Y
	local c = Vector3.new(ctx.cf.X, gy, ctx.cf.Z)
	local once = Kit.once()
	local grade = Kit.grade(ctx)
	local rig = Pose.rig(ctx, ctx.opts.caster)
	if rig and rig.root0 then
		-- face the target
		local p = rig.root0.Position
		local look = (c - p) * Vector3.new(1, 0, 1)
		if look.Magnitude > 1e-3 then
			rig.root0 = CFrame.lookAt(p, p + look.Unit)
		end
	end

	local function newBolt(pts: { Vector3 }, amps: { number }, width: number): Bolt
		local b: Bolt = { base = pts, amp = amps, atts = {}, core = {}, glow = {}, width = width }
		for i = 1, #pts do
			b.atts[i] = Kit.att(ctx, CFrame.new(pts[i]))
		end
		for i = 1, #pts - 1 do
			local g = Kit.beam(ctx, b.atts[i], b.atts[i + 1], "bolt_glow", 0)
			g.Segments = 1
			g.Brightness = 3
			local k = Kit.beam(ctx, b.atts[i], b.atts[i + 1], "bolt_glow", 1)
			k.Segments = 1
			k.Brightness = 7
			b.glow[i], b.core[i] = g, k
		end
		return b
	end
	local function line(a: Vector3, b: Vector3, n: number, amp: number, flatY: number?): ({ Vector3 }, { number })
		local pts, amps = {}, {}
		local dir = b - a
		local p1 = dir:Cross(Vector3.new(0.3, 1, 0.2)).Unit
		local p2 = dir:Cross(p1).Unit
		for i = 0, n - 1 do
			local f = i / (n - 1)
			local env = math.sin(math.pi * f) ^ 0.6
			local p = a + dir * f + (p1 * rng:NextNumber(-1, 1) + p2 * rng:NextNumber(-1, 1)) * amp * env
			if flatY then
				p = Vector3.new(p.X, flatY, p.Z)
			end
			pts[i + 1] = p
			amps[i + 1] = amp * 0.45 * env
		end
		return pts, amps
	end

	-- per strike: a pillar (two-beam column), zigzag bolts round it, ground forks
	type Pillar = { a0: Attachment, a1: Attachment, am: Attachment, core: { Beam }, halo: { Beam } }
	local pillars: { Pillar } = {}
	local strikes: { Strike } = {}
	for si, sd in STRIKES do
		local a0, am, a1 = Kit.att(ctx), Kit.att(ctx), Kit.att(ctx)
		local core, halo = {}, {}
		for k, pair in { { a0, am }, { am, a1 } } do
			local h = Kit.beam(ctx, pair[1], pair[2], "bolt_glow", 0)
			h.Segments = 1
			h.Brightness = 3.5
			h.Name = "PillarHalo" .. si
			local cr = Kit.beam(ctx, pair[1], pair[2], "bolt_glow", 2)
			cr.Segments = 1
			cr.Brightness = 9
			cr.Name = "PillarCore" .. si
			halo[k], core[k] = h, cr
		end
		table.insert(pillars, { a0 = a0, a1 = a1, am = am, core = core, halo = halo })
		local bolts, forks = {}, {}
		local nb = if sd.scale > 1 then 7 else 5
		for k = 1, nb do
			local ang = k / nb * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local r0 = rng:NextNumber(0.8, 2.2) * S
			local top = c + Vector3.new(math.cos(ang) * r0, rng:NextNumber(14, 26) * S, math.sin(ang) * r0)
			local ang2 = ang + rng:NextNumber(-1.2, 1.2)
			local bot = c + Vector3.new(math.cos(ang2) * rng:NextNumber(1, 3.5) * S, 0.2, math.sin(ang2) * rng:NextNumber(1, 3.5) * S)
			local p, a = line(top, bot, 12, 1.6 * S)
			table.insert(bolts, newBolt(p, a, 0.32 * sd.scale))
		end
		for k = 1, 6 do
			local ang = k / 6 * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
			local d = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local p, a = line(c + d * 0.8 * S, c + d * rng:NextNumber(5, 8.5) * sd.scale * S, 7, 0.9 * S, gy + 0.15)
			table.insert(forks, newBolt(p, a, 0.4 * sd.scale))
		end
		table.insert(strikes, { t = sd.t, hue = sd.hue, scale = sd.scale, bolts = bolts, forks = forks })
	end
	-- lingering static arcs after the last strike
	local statics: { Bolt } = {}
	for _ = 1, 8 do
		local pts, amps = {}, {}
		for i = 1, 5 do
			pts[i] = c
			amps[i] = 0
		end
		table.insert(statics, newBolt(pts, amps, 0.22))
	end

	local whiteout = Kit.burst(ctx, "WhiteOut", { tex = "glow_soft", life = { 0.12 }, size = { { 0, 14 }, { 0.3, 34 }, { 1, 38 } },
		transp = { { 0, 0.05 }, { 0.5, 0.4 }, { 1, 1 } }, bright = 3, zoff = 6 })
	local groundGlows, rings = {}, {}
	for si = 1, 3 do
		groundGlows[si] = Kit.flat(ctx, "GroundGlow", { tex = "glow_soft", life = 0.35, size = { { 0, 6 }, { 0.2, 14 }, { 1, 16 } },
			transp = { { 0, 0 }, { 0.5, 0.4 }, { 1, 1 } }, bright = 3 })
		rings[si] = Kit.flat(ctx, "ShockRing", { tex = "shock_ring", life = 0.4, size = { { 0, 2 }, { 0.15, 12 }, { 0.5, 18 }, { 1, 20 } },
			transp = { { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } }, rot = si * 70, spin = 40, bright = 2.5, z = 1 })
	end
	local crackDark = Kit.flat(ctx, "CrackDark", { tex = "ground_crack", life = 1.0, size = { { 0, 4 }, { 0.1, 13 }, { 1, 14 } },
		transp = { { 0, 0 }, { 0.8, 0.15 }, { 1, 1 } }, rot = 25, le = 0, z = -1 })
	local crackHot = Kit.flat(ctx, "CrackHot", { tex = "ground_crack", life = 0.75, size = { { 0, 4 }, { 0.12, 13 }, { 1, 14 } },
		transp = { { 0, 0 }, { 0.35, 0.3 }, { 1, 1 } }, rot = 25, bright = 3 })
	local sparks = Kit.burst(ctx, "Sparks", { tex = "spark_streak", life = { 0.2, 0.45 }, size = { { 0, 0.8 }, { 1, 0 } },
		speed = { 30, 60 }, spread = 70, drag = 5, acc = Vector3.new(0, -35, 0), vpar = true, bright = 5 })
	local glints = Kit.burst(ctx, "Glints", { tex = "spark_glint", life = { 0.16, 0.26 }, size = { { 0, 0 }, { 0.2, 2.6 }, { 1, 0 } },
		speed = { 0.3, 1 }, spread = 180, bright = 6, zoff = 2 })
	local smoke = Kit.burst(ctx, "Smoke", { tex = "smoke_puff", life = { 0.9, 1.3 }, size = { { 0, 2 }, { 1, 5.5 } },
		transp = { { 0, 1 }, { 0.2, 0.72 }, { 0.6, 0.8 }, { 1, 1 } }, speed = { 1.5, 3.5 }, spread = 40, drag = 1.2,
		acc = Vector3.new(0, 1.2, 0), rot = { 0, 360 }, rotSpeed = { -25, 25 }, le = 0 })
	local lightHost = Kit.part(ctx, ctx.root, "LightHost", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightHost.Transparency = 1
	lightHost.CFrame = CFrame.new(c + Vector3.new(0, 4 * S, 0))
	local light = Kit.light(ctx, lightHost, 30 * S)

	local SLOT = 0.035
	local function setBolt(b: Bolt, vis: number, hue: number, sr: Random, headN: number?)
		for i = 1, #b.base do
			local j = if b.amp[i] > 0 then Vector3.new(sr:NextNumber(-1, 1), sr:NextNumber(-1, 1), sr:NextNumber(-1, 1)) * b.amp[i] else Vector3.zero
			b.atts[i].CFrame = CFrame.new(b.base[i] + j)
		end
		for i = 1, #b.core do
			local on = vis > 0.02 and i < (headN or 999)
			b.core[i].Enabled, b.glow[i].Enabled = on, on
			if on then
				local w = b.width * S * (0.6 + 0.4 * vis)
				b.core[i].Width0, b.core[i].Width1 = w * 0.4, w * 0.4
				b.glow[i].Width0, b.glow[i].Width1 = w * 2.6, w * 2.6
				b.core[i].Color = ColorSequence.new(Kit.hot(hue))
				b.glow[i].Color = ColorSequence.new(Kit.col(hue + i * 0.02, 0.85, 1))
				b.core[i].Transparency = NumberSequence.new(1 - vis)
				b.glow[i].Transparency = NumberSequence.new(1 - vis * 0.8)
			end
		end
	end

	return function(t: number)
		local sr = Kit.slotRng(ctx.opts.seed, t, SLOT)
		local slot = math.floor(t / SLOT)
		local h0 = Kit.hue(ctx, t, 0)
		if rig then
			rig.apply(Pose.sample(KEYS, t))
			if rig.root0 then
				rig.move(rig.root0)
			end
		end
		-- scene grade: sink to indigo, white-out pops on each strike, lift at the end
		local dark = Kit.ramp(t, 0.05, 0.28) * (1 - Kit.ramp(t, 1.6, 2.0))
		local pop = 0
		for _, st in strikes do
			local d = t - st.t
			if d >= -0.03 and d < 0.1 then
				pop = math.max(pop, 1 - math.abs(d + 0.0) / 0.1)
			end
		end
		if grade then
			grade.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(150, 120, 255), dark)
			grade.Brightness = -0.22 * dark + 0.55 * pop
			grade.Contrast = 0.25 * dark
			grade.Saturation = 0.2 * dark - 0.5 * pop
		end

		local lb = 0
		for si, st in strikes do
			local d = t - st.t
			local P = pillars[si]
			local hue = h0 + st.hue
			-- pillar: slams down in 0.03 s, holds with flicker, thins and fades by 0.3 s
			local on = if d >= 0 and d < 0.32 then (1 - Kit.ramp(d, 0.14, 0.32)) else 0
			if on > 0 then
				local slam = Kit.easeOut(d / 0.03)
				local top = c + Vector3.yAxis * 45 * S
				local bottom = top:Lerp(c, slam)
				local flick = if sr:NextNumber() > 0.25 then 1 else 0.7
				local W = (1.7 + 0.5 * flick) * S * st.scale * (0.5 + 0.5 * on)
				P.a0.CFrame = CFrame.new(top)
				P.am.CFrame = CFrame.new(top:Lerp(bottom, 0.6))
				P.a1.CFrame = CFrame.new(bottom)
				for k = 1, 2 do
					P.core[k].Enabled, P.halo[k].Enabled = true, true
					P.core[k].Width0 = W * (if k == 1 then 0.5 else 0.75)
					P.core[k].Width1 = W * (if k == 1 then 0.75 else 1.0)
					P.halo[k].Width0 = W * (if k == 1 then 2.2 else 3.2)
					P.halo[k].Width1 = W * (if k == 1 then 3.2 else 4.2)
					P.core[k].Color = ColorSequence.new(Kit.hot(hue))
					P.halo[k].Color = Kit.hueSeq(hue + (k - 1) * 0.3, 0.3, 0.75, 1, 3)
					P.core[k].Transparency = NumberSequence.new(1 - on)
					P.halo[k].Transparency = NumberSequence.new(1 - on * 0.75)
				end
			else
				for k = 1, 2 do
					P.core[k].Enabled, P.halo[k].Enabled = false, false
				end
			end
			-- zigzag bolts round the pillar (staggered, flickering)
			for bi, b in st.bolts do
				local bd = d - bi * 0.012
				local vis = if bd >= 0 and bd < 0.3 then (if sr:NextNumber() > 0.3 then 1 else 0.35) * (1 - Kit.ramp(bd, 0.15, 0.3)) else 0
				setBolt(b, vis, hue + bi * 0.09, sr, nil)
			end
			-- ground forks crawl outward
			for fi, b in st.forks do
				local fd = d - 0.02
				local vis = if fd >= 0 and fd < 0.4 then (if sr:NextNumber() > 0.25 then 1 else 0.4) * (1 - Kit.ramp(fd, 0.2, 0.4)) else 0
				local headN = math.max(2, math.ceil(#b.base * Kit.easeOut(fd / 0.08)))
				setBolt(b, vis, hue + fi / 6, sr, headN)
			end
			-- impact layers
			if once("hit" .. si, d, 0) then
				Kit.spray(ctx, whiteout, c + Vector3.yAxis * 4 * S, 1, ColorSequence.new(Kit.hot(hue)), "point")
				groundGlows[si].fire(st.t, c + Vector3.yAxis * 0.12, ColorSequence.new(Kit.col(hue, 0.6, 1)))
				rings[si].fire(st.t, c + Vector3.yAxis * 0.14, ColorSequence.new(Kit.col(hue + 0.1, 0.7, 1)))
				Kit.spray(ctx, sparks, c + Vector3.yAxis * 0.5, math.floor(22 * st.scale), Kit.hueSeq(hue, 0.5, 0.5, 1, 3), "point")
				Kit.spray(ctx, glints, c + Vector3.yAxis * 2 * S, 4, ColorSequence.new(Kit.hot(hue)), "sphere", 3.5)
			end
			groundGlows[si].update(t)
			rings[si].update(t)
			if d >= 0 then
				lb = math.max(lb, 9 * st.scale * math.exp(-d * 9))
			end
		end
		-- the last strike leaves a scorch crack, static and smoke
		local tl = t - STRIKES[3].t
		if once("scorch", tl, 0.01) then
			local hue = h0 + STRIKES[3].hue
			crackDark.fire(STRIKES[3].t + 0.01, c + Vector3.yAxis * 0.06, ColorSequence.new(Kit.ink(hue)))
			crackHot.fire(STRIKES[3].t + 0.01, c + Vector3.yAxis * 0.1, Kit.hueSeq(hue, 0.6, 0.7, 1, 3))
		end
		crackDark.update(t)
		crackHot.update(t)
		if once("smoke", tl, 0.12) then
			Kit.spray(ctx, smoke, c + Vector3.yAxis * 0.8, 7, ColorSequence.new(Color3.fromRGB(60, 54, 80)), "disc", 2.5, 1.5)
		end
		local nStatic = math.floor(8 * (1 - Kit.ramp(tl, 0.25, 0.8)) + 0.5)
		for si, b in statics do
			if tl >= 0.1 and si <= nStatic then
				local ang = sr:NextNumber(0, math.pi * 2)
				local rad = sr:NextNumber(0.8, 5.5) * S
				local p0 = c + Vector3.new(math.cos(ang) * rad, 0.15 + sr:NextNumber(0, 1), math.sin(ang) * rad)
				local dir = Vector3.new(sr:NextNumber(-1, 1), sr:NextNumber(-0.2, 0.7), sr:NextNumber(-1, 1)).Unit * sr:NextNumber(1.2, 2.8) * S
				for i = 1, 5 do
					b.base[i] = p0 + dir * ((i - 1) / 4)
					b.amp[i] = if i == 1 or i == 5 then 0 else 0.4 * S
				end
				setBolt(b, if sr:NextNumber() > 0.3 then 0.85 else 0, h0 + si / 8, sr, nil)
			else
				setBolt(b, 0, 0, sr, nil)
			end
		end
		light.Brightness = lb + (if slot % 2 == 0 then 0.6 else 0.3) * (1 - Kit.ramp(tl, 0.2, 0.7)) * (if tl > 0 then 1 else 0)
		light.Color = Kit.col(h0, 0.45, 1)
	end
end

function StormLance.shake(t: number): Vector3
	local a = 0
	for _, s in STRIKES do
		if t >= s.t then
			a = math.max(a, 0.55 * s.scale * math.exp(-(t - s.t) * 10))
		end
	end
	return Vector3.new(math.sin(t * 97) * a, math.sin(t * 71 + 2) * a * 0.7, 0)
end

return StormLance
