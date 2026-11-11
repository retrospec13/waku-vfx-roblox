--!strict
--[[ RiftGate: a standing portal torn into the air.
	cf = the centre of the gate; cf.LookVector is the way it faces (cf.UpVector is its top, so it can lean or lie flat).
	No caster, no pose.

	0.00-0.26  two spark heads race from the bottom of the rim round both sides to the top, burning it in behind them
	0.26-0.40  they meet: flash, a shock ring in the plane of the gate, the ring snaps out to full size, the inside floods in
	0.40-4.40  hold: a burning rim (dark halo, rainbow running round it, white core) with two comets chasing each other
	           round it, flame tongues licking off it, a deep swirl inside (spiral arms over turning cloud), motes
	           falling inward, sparks shed off the comets, pulse rings, black lightning grounding from the lower rim
	last 0.30  it folds shut sideways into a vertical line of light, the line snaps to a point and pops
	handle.stop() plays the fold from wherever it is; a second stop() removes it at once. ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)

local OPEN = 0.4
local HOLD = 4.0
local CLOSE = 0.3
local MEET = 0.26 -- the spark heads meet at the top
local SPIN = 5 -- comet speed round the rim, rad/s
local N = 24 -- rim segments

local RiftGate = {
	life = OPEN + HOLD + CLOSE,
	required = { "glow_soft", "spark_streak", "spark_glint", "shock_ring", "ground_crack", "ground_disc", "frost_ground", "bolt_glow" },
}

type Tongue = { a0: Attachment, a1: Attachment, b: Beam, ang: number, len: number, w: number, out: number, p1: number, p2: number, f1: number, f2: number }
type Arm = { a0: Attachment, a1: Attachment, b: Beam, ang: number }

function RiftGate.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local seed = ctx.opts.seed
	local life = RiftGate.life
	ctx.outro = CLOSE

	local C = ctx.cf.Position
	local nrm = ctx.cf.LookVector
	local right = ctx.cf.RightVector
	local up = ctx.cf.UpVector
	local R = 7.5 * S
	local dth = math.pi * 2 / N

	-- angle 0 is the bottom of the ring
	local function radial(a: number): Vector3
		return right * math.sin(a) - up * math.cos(a)
	end
	local function tangent(a: number): Vector3
		return right * math.cos(a) + up * math.sin(a)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex: { Instance } = { ctx.root }
	local folder = Workspace:FindFirstChild("wakuVFX")
	if folder then
		table.insert(ex, folder)
	end
	params.FilterDescendantsInstances = ex
	local hit = Workspace:Raycast(C, Vector3.new(0, -R * 3, 0), params)
	local G: Vector3? = if hit then hit.Position + Vector3.yAxis * 0.08 else nil

	-- rim: a closed loop of curved segments, three layers sharing one set of joints -----------------------------
	local rimAtt: { Attachment } = {}
	for i = 1, N do
		rimAtt[i] = Kit.att(ctx)
	end
	local function rimLayer(name: string, z: number, le: number, bright: number): { Beam }
		local list = {}
		for i = 1, N do
			local b = Kit.beam(ctx, rimAtt[i], rimAtt[i % N + 1], "bolt_glow", z)
			b.Name = name
			b.Segments = 4
			b.LightEmission = le
			b.Brightness = bright
			b.Enabled = false
			list[i] = b
		end
		return list
	end
	local rimInk = rimLayer("RimInk", -1, 0, 1)
	local rimBody = rimLayer("Rim", 1, 1, 1.6)
	local rimCore = rimLayer("RimCore", 2, 1, 3)

	-- flame tongues licking off the rim (outward) and into the gate (inward)
	local tongues: { Tongue } = {}
	local function addTongues(n: number, out: number, len: { number }, w: { number })
		for i = 1, n do
			local a0, a1 = Kit.att(ctx), Kit.att(ctx)
			local b = Kit.beam(ctx, a0, a1, "bolt_glow", 0)
			b.Name = if out > 0 then "RimFlame" else "RimFlameIn"
			b.Segments = 8
			b.Width1 = 0
			b.Enabled = false
			table.insert(tongues, { a0 = a0, a1 = a1, b = b, ang = (i - 1) / n * math.pi * 2 + rng:NextNumber(-0.12, 0.12),
				len = rng:NextNumber(len[1], len[2]) * S, w = rng:NextNumber(w[1], w[2]) * S, out = out,
				p1 = rng:NextNumber(0, 6.28), p2 = rng:NextNumber(0, 6.28), f1 = rng:NextNumber(11, 17), f2 = rng:NextNumber(19, 27) })
		end
	end
	addTongues(20, 1, { 2.4, 5.6 }, { 1.5, 2.3 })
	addTongues(12, -1, { 1.4, 2.8 }, { 1.0, 1.5 })

	-- the inside: cards lying in the plane of the gate ----------------------------------------------------------
	local function card(name: string, tex: string, z: number, le: number, bright: number?): (Beam, (number, number, number, number?) -> ())
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local b = Kit.beam(ctx, a0, a1, tex, z)
		b.Name = name
		b.FaceCamera = false
		b.Segments = 1
		b.LightEmission = le
		b.Brightness = bright or 1
		b.Enabled = false
		return b, function(wx: number, wy: number, transp: number, rot: number?)
			if transp >= 0.995 or wx <= 0.02 or wy <= 0.02 then
				b.Enabled = false
				return
			end
			local x, y = right, up
			if rot then
				local c, s = math.cos(rot), math.sin(rot)
				x, y = right * c + up * s, up * c - right * s
			end
			a0.CFrame = CFrame.fromMatrix(C - x * wx / 2, x, y)
			a1.CFrame = CFrame.fromMatrix(C + x * wx / 2, x, y)
			b.Width0, b.Width1 = wy, wy
			b.Transparency = NumberSequence.new(math.clamp(transp, 0, 1))
			b.Enabled = true
		end
	end
	local voidA, setVoidA = card("Void", "ground_disc", -6, 0)
	local voidB, setVoidB = card("Void", "ground_disc", -5.8, 0)
	local cloudA, setCloudA = card("SwirlCloud", "frost_ground", -5, 1)
	local cloudB, setCloudB = card("SwirlCloud2", "frost_ground", -4.6, 1)
	local veins, setVeins = card("SwirlVeins", "ground_crack", -4.2, 1, 2)
	local heart, setHeart = card("Heart", "glow_soft", -3, 1, 2)
	local heartStar, setHeartStar = card("HeartStar", "spark_glint", -2.6, 1, 3)

	local arms: { Arm } = {}
	local arms2: { Arm } = {}
	local function addArms(list: { Arm }, n: number, name: string, z: number)
		for i = 1, n do
			local a0, a1 = Kit.att(ctx), Kit.att(ctx)
			local b = Kit.beam(ctx, a0, a1, "bolt_glow", z)
			b.Name = name
			b.FaceCamera = false
			b.Segments = 14
			b.Enabled = false
			table.insert(list, { a0 = a0, a1 = a1, b = b, ang = (i - 1) / n * math.pi * 2 })
		end
	end
	addArms(arms, 6, "SwirlArm", -3.8)
	addArms(arms2, 4, "SwirlArmHot", -3.4)

	-- camera-facing pieces --------------------------------------------------------------------------------------
	local bloom = Kit.sprite(ctx, "Bloom", "glow_soft", -7)
	local heads = { { glow = Kit.sprite(ctx, "HeadGlow", "glow_soft", 4), star = Kit.sprite(ctx, "HeadStar", "spark_glint", 5) },
		{ glow = Kit.sprite(ctx, "HeadGlow", "glow_soft", 4), star = Kit.sprite(ctx, "HeadStar", "spark_glint", 5) } }
	local meetFlash = Kit.sprite(ctx, "MeetFlash", "glow_soft", 6)
	local meetStar = Kit.sprite(ctx, "MeetStar", "spark_glint", 7)
	local popStar = Kit.sprite(ctx, "PopStar", "spark_glint", 7)
	local popLine = Kit.sprite(ctx, "PopLine", "spark_glint", 7)
	local openRing = Kit.plate(ctx, "OpenRing", "shock_ring", 3)
	local openRing2 = Kit.plate(ctx, "OpenRingInk", "shock_ring", 2)
	openRing2.beam.LightEmission = 0
	local pulses = { Kit.plate(ctx, "Pulse", "shock_ring", -1), Kit.plate(ctx, "Pulse", "shock_ring", -1) }
	local groundGlow = Kit.plate(ctx, "GroundGlow", "ground_disc", 0.2)
	local groundRipple = Kit.plate(ctx, "GroundRipple", "shock_ring", 0.4)
	local bolts = {}
	for i = 1, 3 do
		bolts[i] = { glow = Kit.bolt(ctx, "HakiGlow", 6, 1, 1), core = Kit.bolt(ctx, "HakiCore", 6, 2, 0) }
	end

	local sparks = Kit.burst(ctx, "RimSparks", { tex = "spark_streak", life = { 0.3, 0.65 }, size = { { 0, 0.35 }, { 0.2, 1.7 }, { 1, 0.2 } },
		transp = { { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } }, speed = { 26, 62 }, spread = 28, drag = 2, acc = Vector3.new(0, -62 * S, 0),
		rot = { 90 }, vpar = true, bright = 2.5 })
	local glints = Kit.burst(ctx, "Glints", { tex = "spark_glint", life = { 0.25, 0.5 }, size = { { 0, 0 }, { 0.2, 1.5 }, { 1, 0 } },
		speed = { 10, 30 }, drag = 3.5, rot = { 0, 360 }, rotSpeed = { -160, 160 }, bright = 3 })
	local motes = Kit.burst(ctx, "Motes", { tex = "spark_glint", life = { 0.42, 0.5 }, size = { { 0, 0 }, { 0.25, 0.9 }, { 1, 0 } },
		speed = { 12, 15 }, rot = { 0, 360 }, rotSpeed = { -200, 200 }, bright = 2.5 })
	local moteStreak = Kit.burst(ctx, "MoteStreaks", { tex = "spark_streak", life = { 0.3, 0.4 }, size = { { 0, 0.2 }, { 0.3, 1.5 }, { 1, 0.1 } },
		transp = { { 0, 1 }, { 0.3, 0.1 }, { 1, 0.6 } }, speed = { 15, 20 }, rot = { 90 }, vpar = true, bright = 2 })

	local lightPart = Kit.part(ctx, ctx.root, "Light", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightPart.Transparency = 1
	lightPart.CFrame = CFrame.new(C + nrm * 1.5 * S)
	local light = Kit.light(ctx, lightPart, 34 * S)

	local once = Kit.once()
	local nHead, nShed, nMote = 0, 0, 0
	local kk: { number } = table.create(N + 1, 0)
	local lit: { number } = table.create(N + 1, 0)
	local hh: { number } = table.create(N + 1, 0)
	local hl: { number } = table.create(N + 1, 0)

	return function(t: number)
		local h = Kit.hue(ctx, t, 0)
		local closeAt = ctx.stopAt or (life - CLOSE)
		local tc = t - closeAt
		local closing = tc >= 0

		-- shape of the ring this frame ---------------------------------------------------------------------------
		local g = 0.8 + 0.2 * Kit.easeOutBack(Kit.ramp(t, MEET - 0.08, OPEN))
		local sx, sy = 1, 1
		if closing then
			sx = 1 - 0.985 * Kit.easeIn(Kit.ramp(tc, 0, 0.16))
			sy = (1 + 0.32 * Kit.smooth(Kit.ramp(tc, 0, 0.16))) * (1 - Kit.easeIn(Kit.ramp(tc, 0.14, 0.26)))
		end
		local function point(a: number, rf: number): Vector3
			return C + right * (math.sin(a) * R * rf * g * sx) - up * (math.cos(a) * R * rf * g * sy)
		end
		local burn = (math.pi + 2 * dth) * Kit.ramp(t, 0, MEET) ^ 0.85 -- how far round the rim is lit (overshoots, so the top is fully lit)
		local hd = math.min(burn, math.pi) -- where the two spark heads are
		local inside = Kit.easeOut(Kit.ramp(t, MEET - 0.04, OPEN + 0.08)) * (if closing then 1 - Kit.ramp(tc, 0, 0.13) else 1)
		local rimFade = if closing then Kit.ramp(tc, 0.23, 0.29) else 0
		local flick = 0.86 + 0.14 * Kit.slotRng(seed, t, 1 / 30):NextNumber()

		-- rim ----------------------------------------------------------------------------------------------------
		local kcurve = 4 / 3 * math.tan(dth / 4)
		for i = 1, N do
			local a = -math.pi + (i - 1) * dth
			local tv = right * (math.cos(a) * sx) + up * (math.sin(a) * sy)
			rimAtt[i].CFrame = Kit.rightTo(point(a, 1), tv)
			hl[i] = kcurve * R * g * tv.Magnitude
			kk[i] = (0.5 + 0.5 * math.cos(a - t * SPIN)) ^ 8 + (0.5 + 0.5 * math.cos(a - t * SPIN - math.pi)) ^ 8
			lit[i] = math.clamp((burn - math.abs(a)) / dth + 0.5, 0, 1)
			hh[i] = Kit.hue(ctx, t, (i - 1) / N)
		end
		kk[N + 1], lit[N + 1], hl[N + 1] = kk[1], lit[1], hl[1]
		hh[N + 1] = Kit.hue(ctx, t, 1)
		local squash = if closing then 0.35 + 0.65 * math.max(sx, 0.05) else 1 -- thinner as it folds to a line
		for i = 1, N do
			local l0, l1 = lit[i], lit[i + 1]
			if l0 <= 0 and l1 <= 0 then
				rimInk[i].Enabled, rimBody[i].Enabled, rimCore[i].Enabled = false, false, false
				continue
			end
			local k0, k1 = kk[i], kk[i + 1]
			for _, b in { rimInk[i], rimBody[i], rimCore[i] } do
				b.CurveSize0, b.CurveSize1 = hl[i], hl[i + 1]
				b.Enabled = true
			end
			local function tr(base0: number, base1: number): NumberSequence
				return NumberSequence.new({
					NumberSequenceKeypoint.new(0, math.clamp(1 - (1 - base0) * l0 * (1 - rimFade), 0, 1)),
					NumberSequenceKeypoint.new(1, math.clamp(1 - (1 - base1) * l1 * (1 - rimFade), 0, 1)),
				})
			end
			local ink, body, core = rimInk[i], rimBody[i], rimCore[i]
			ink.Width0, ink.Width1 = (4.2 + 2 * k0) * S * squash, (4.2 + 2 * k1) * S * squash
			ink.Color = ColorSequence.new(Kit.ink(hh[i]), Kit.ink(hh[i + 1]))
			ink.Transparency = tr(0.2, 0.2)
			body.Width0, body.Width1 = (2 + 2.3 * k0) * S * squash * flick, (2 + 2.3 * k1) * S * squash * flick
			body.Color = ColorSequence.new(Kit.col(hh[i], 0.9 - 0.5 * k0, 1), Kit.col(hh[i + 1], 0.9 - 0.5 * k1, 1))
			body.Transparency = tr(0.08, 0.08)
			core.Width0, core.Width1 = (0.6 + 1.3 * k0) * S * squash, (0.6 + 1.3 * k1) * S * squash
			core.Color = ColorSequence.new(Kit.hot(hh[i]), Kit.hot(hh[i + 1]))
			core.Transparency = tr(0.3 - 0.3 * k0, 0.3 - 0.3 * k1)
		end

		-- flame tongues ------------------------------------------------------------------------------------------
		for _, tg in tongues do
			local a = tg.ang + 0.1 * math.sin(t * 1.7 + tg.p1)
			local da = math.abs((a + math.pi) % (2 * math.pi) - math.pi)
			local on = math.clamp((burn - da) / dth, 0, 1) * (1 - rimFade)
			if on <= 0 or (closing and sx < 0.5) then
				tg.b.Enabled = false
				continue
			end
			local nz = 0.5 + 0.25 * math.sin(t * tg.f1 + tg.p1) + 0.25 * math.sin(t * tg.f2 + tg.p2)
			local comet = (0.5 + 0.5 * math.cos(a - t * SPIN)) ^ 6 + (0.5 + 0.5 * math.cos(a - t * SPIN - math.pi)) ^ 6
			local len = tg.len * (0.45 + 0.75 * nz + 0.9 * comet)
			local p0 = point(a, 1)
			local rad = radial(a) * tg.out
			local tip = p0 + rad * len - tangent(a) * len * 0.75 -- swept back against the spin
			tg.a0.CFrame = Kit.rightTo(p0, rad)
			tg.a1.CFrame = Kit.rightTo(tip, -tangent(a) + rad * 0.2)
			tg.b.CurveSize0, tg.b.CurveSize1 = len * 0.55, len * 0.35
			tg.b.Width0 = tg.w * (0.8 + 0.5 * comet)
			local hc = Kit.hue(ctx, t, (a / (2 * math.pi)) % 1)
			tg.b.Color = ColorSequence.new(Kit.hot(hc), Kit.col(hc + 0.08, 0.9, 1))
			tg.b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - 0.85 * on), NumberSequenceKeypoint.new(1, 1) })
			tg.b.Enabled = true
		end

		-- inside ---------------------------------------------------------------------------------------------------
		local d = 2 * R * g
		local voidCol = ColorSequence.new(Color3.fromHSV((h + 0.62) % 1, 0.85, 0.09))
		voidA.Color, voidB.Color = voidCol, voidCol
		local vshow = if closing then 1 - Kit.ramp(tc, 0.12, 0.2) else Kit.ramp(t, MEET - 0.06, OPEN)
		setVoidA(d * 1.06 * sx, d * 1.06 * sy, 1 - vshow)
		setVoidB(d * 0.98 * sx, d * 0.98 * sy, 1 - vshow)
		cloudA.Color = Kit.seq(ctx, h + 0.45, 0.35, 0.8, 0.95, 4)
		setCloudA(d * 0.97 * inside, d * 0.97 * inside, 1 - 0.6 * inside, t * 0.9)
		cloudB.Color = Kit.seq(ctx, h + 0.1, 0.4, 0.7, 1, 4)
		setCloudB(d * 0.74 * inside, d * 0.74 * inside, 1 - 0.55 * inside, -t * 1.5)
		veins.Color = Kit.seq(ctx, h, 0.8, 0.5, 1, 6)
		setVeins(d * 0.66 * inside, d * 0.66 * inside, 1 - 0.55 * inside * flick, t * 2.3)
		local beat = 0.5 + 0.5 * math.sin(t * 7)
		heart.Color = ColorSequence.new(Kit.hot(h))
		setHeart(d * (0.42 + 0.06 * beat) * inside, d * (0.42 + 0.06 * beat) * inside, 1 - 0.8 * inside)
		heartStar.Color = ColorSequence.new(Color3.new(1, 1, 1))
		setHeartStar(d * (0.5 + 0.1 * beat) * inside, d * (0.5 + 0.1 * beat) * inside, 1 - 0.9 * inside, -t * 2.6)

		local function placeArms(list: { Arm }, spin: number, twist: number, r0: number, r1: number, w: number, hot: boolean)
			for j, arm in list do
				if inside <= 0.02 then
					arm.b.Enabled = false
					continue
				end
				local b0 = arm.ang + t * spin
				local b1 = b0 + twist
				local d0 = radial(b0 + twist * 0.35)
				local d1 = tangent(b1) * (if twist > 0 then 1 else -1)
				arm.a0.CFrame = CFrame.fromMatrix(point(b0, r0 * inside), d0, nrm:Cross(d0))
				arm.a1.CFrame = CFrame.fromMatrix(point(b1, r1 * inside), d1, nrm:Cross(d1))
				arm.b.CurveSize0, arm.b.CurveSize1 = R * 0.42 * inside, R * 0.5 * inside
				arm.b.Width0, arm.b.Width1 = w * 0.2 * S, w * S * inside
				local ha = Kit.hue(ctx, t, j / #list)
				arm.b.Color = if hot then ColorSequence.new(Color3.new(1, 1, 1), Kit.hot(ha)) else Kit.seq(ctx, ha, 0.3, 0.85, 1, 4)
				arm.b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - 0.75 * inside),
					NumberSequenceKeypoint.new(0.75, 1 - 0.6 * inside), NumberSequenceKeypoint.new(1, 1) })
				arm.b.Enabled = true
			end
		end
		placeArms(arms, 2.4, 1.9, 0.07, 0.93, 3.4, false)
		placeArms(arms2, -3.4, -1.5, 0.05, 0.7, 1.5, true)

		bloom.beam.Color = ColorSequence.new(Kit.col(h + 0.1, 0.6, 1))
		bloom.set(C, d * 1.9 * math.max(sx, 0.2), 1 - 0.3 * math.max(inside, if closing then 0 else lit[N // 2 + 1] * 0.4) * (1 - rimFade))

		-- opening: the spark heads ---------------------------------------------------------------------------------
		if t < MEET then
			for s, head in heads do
				local a = if s == 1 then hd else -hd
				local p = point(a, 1)
				head.glow.beam.Color = ColorSequence.new(Kit.hot(h))
				head.glow.set(p, 7 * S, 0.15)
				head.star.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
				head.star.set(p, 13 * S, 0, t * 14 * (if s == 1 then 1 else -1))
			end
			local want = math.floor(t / 0.011) + 1
			if want > nHead then
				nHead = want
				for s = 1, 2 do
					local a = if s == 1 then hd else -hd
					local back = tangent(a) * (if s == 1 then -1 else 1)
					Kit.spray(ctx, sparks, point(a, 1), 3, ColorSequence.new(Kit.hot(h), Kit.col(Kit.hue(ctx, t, s * 0.3), 0.9, 1)), "point", 0, 0, back + radial(a) * 0.8)
				end
			end
		else
			-- hold: the two comets ride the rim and shed sparks behind them
			local show = not closing and t >= OPEN
			for s, head in heads do
				local a = t * SPIN + (s - 1) * math.pi
				if show then
					local p = point(a, 1)
					head.glow.beam.Color = ColorSequence.new(Kit.col(Kit.hue(ctx, t, s * 0.5), 0.5, 1))
					head.glow.set(p, 6 * S, 0.3)
					head.star.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
					head.star.set(p, (7 + 1.5 * math.sin(t * 31 + s)) * S, 0, t * 6)
				else
					head.glow.hide()
					head.star.hide()
				end
			end
			if show then
				local want = math.floor((t - OPEN) / 0.028) + 1
				if want > nShed then
					nShed = want
					for s = 1, 2 do
						local a = t * SPIN + (s - 1) * math.pi
						Kit.spray(ctx, sparks, point(a, 1), 2, ColorSequence.new(Kit.hot(h), Kit.col(Kit.hue(ctx, t, a / 6.28), 0.9, 1)), "point", 0, 0, tangent(a) + radial(a) * 0.5)
					end
				end
			end
		end

		-- the heads meet: flash, shock ring, sparks off the whole rim ---------------------------------------------
		if once("meet", t, MEET) then
			for i = 1, N do
				local a = -math.pi + (i - 1) * dth
				Kit.spray(ctx, sparks, point(a, 1), 3, ColorSequence.new(Kit.hot(hh[i]), Kit.col(hh[i], 0.9, 1)), "point", 0, 0, radial(a))
			end
			Kit.spray(ctx, glints, point(math.pi, 1), 16, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.2)), "sphere", 2)
			Kit.spray(ctx, glints, C, 14, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.5)), "sphere", 5)
		end
		local mf = if t >= MEET then 1 - Kit.ramp(t, MEET, MEET + 0.16) else 0
		meetFlash.beam.Color = ColorSequence.new(Kit.hot(h))
		meetFlash.set(C, d * (1.4 + 1.4 * mf), 1 - 0.85 * mf)
		meetStar.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		meetStar.set(point(math.pi, 1), 34 * S * mf, if mf > 0 then 0 else 1, 0.3, 1)
		local ou = Kit.ramp(t, MEET, MEET + 0.42)
		openRing.beam.Color = Kit.seq(ctx, h, 0.8, 0.6, 1, 6)
		Kit.pulse(openRing, C, nrm, ou, d * 1.05, d * 2.9, 0.05, 1)
		openRing2.beam.Color = ColorSequence.new(Kit.ink(h))
		Kit.pulse(openRing2, C, nrm, Kit.ramp(t, MEET + 0.03, MEET + 0.5), d * 1.1, d * 3.2, 0.2, 2)

		-- hold: pulse rings, motes falling in, black lightning to the ground -----------------------------------------
		for k, pl in pulses do
			local u = if t > OPEN and not closing then ((t - OPEN + (k - 1) * 0.6) % 1.2) / 0.75 else 0
			pl.beam.Color = Kit.seq(ctx, Kit.hue(ctx, t, k * 0.4), 0.5, 0.75, 1, 5)
			Kit.pulse(pl, C, nrm, u, d * 1.02, d * 1.95, 0.5, k)
		end
		if t > MEET and not closing then
			local want = math.floor((t - MEET) / 0.035)
			if want > nMote then
				nMote = want
				for q = 1, 2 do
					local a = rng:NextNumber(0, math.pi * 2)
					local p = point(a, 0.96)
					local e = if q == 1 then motes else moteStreak
					e.Color = ColorSequence.new(Kit.col(Kit.hue(ctx, t, a / 6.28), 0.8, 1), Kit.hot(h))
					ctx.host.CFrame = Kit.upTo(p, (C - p) + tangent(a) * R * 0.5)
					e:Emit(1)
				end
			end
		end
		local slot = math.floor(t / 0.06)
		for i, b in bolts do
			local r = Random.new(seed * 131 + i * 977 + slot * 31)
			if t > MEET and not closing and r:NextNumber() < 0.34 then
				local a = r:NextNumber(-1.5, 1.5)
				local from = point(a, 1)
				local to = if G
					then G + right * r:NextNumber(-1.4, 1.4) * R + nrm * r:NextNumber(-0.7, 0.7) * R
					else from + radial(a) * r:NextNumber(0.6, 1.3) * R
				local sd = seed * 53 + i * 101 + slot
				b.glow.set(from, to, 2.4 * S, 0.1, sd, Kit.col(Kit.hue(ctx, t, i / 3), 0.9, 1), 0.3)
				b.core.set(from, to, 0.8 * S, 0.1, sd, Color3.new(0, 0, 0), 0)
			else
				b.glow.hide()
				b.core.hide()
			end
		end
		if G then
			local on = Kit.ramp(t, MEET, OPEN + 0.1) * (if closing then 1 - Kit.ramp(tc, 0, 0.2) else 1)
			groundGlow.beam.Color = Kit.hueSeq(h, if ctx.opts.rainbow then 0.8 else 0.08, 0.85, 1, 6)
			groundGlow.set(G, Vector3.yAxis, R * 3.6, 1 - 0.5 * on * flick, t * 0.7)
			groundRipple.beam.Color = Kit.seq(ctx, h + 0.3, 0.5, 0.7, 1, 5)
			Kit.pulse(groundRipple, G, Vector3.yAxis, if on > 0.5 then ((t - OPEN) % 0.9) / 0.9 else 0, R * 0.6, R * 4.4, 0.4, t)
		end

		-- close: the line snaps to a point and pops ----------------------------------------------------------------
		if closing and once("pop", t, closeAt + 0.22) then
			Kit.spray(ctx, glints, C, 26, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.3)), "sphere", 1)
			Kit.spray(ctx, sparks, C, 30, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.6, 0.9, 1)), "sphere", 1)
		end
		local pk = if closing and tc >= 0.2 then 1 - Kit.ramp(tc, 0.22, CLOSE) else 0
		popStar.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		popStar.set(C, 30 * S * pk, if pk > 0 then 0 else 1, 0, 1)
		popLine.beam.Color = ColorSequence.new(Kit.hot(h + 0.3))
		popLine.set(C, 12 * S * pk, if pk > 0 then 0 else 1, math.pi / 2, 6)

		light.Color = Kit.col(h, 0.5, 1)
		light.Brightness = (2.6 * math.max(inside, 0.3 * hd / math.pi) * flick + 7 * mf + 6 * pk) * (1 - rimFade * (1 - pk))
	end
end

-- a thump when the rim closes its circle
function RiftGate.shake(t: number): Vector3
	if t < MEET or t > MEET + 0.5 then
		return Vector3.zero
	end
	local k = 0.4 * math.exp(-(t - MEET) * 9)
	return Vector3.new(math.sin(t * 79) * k, math.cos(t * 101) * k, 0)
end

return RiftGate
