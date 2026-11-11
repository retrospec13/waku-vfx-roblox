--!strict
--[[ BlinkStep: a combat blink. Gone in a seam of light, back in a thunderclap.
	cf = the leave point (the caster's root CFrame). The arrive point is, in order: opts.to (where the root will be),
	else wherever opts.caster's root is when the gap ends (the game moved it), else 18 studs along cf.LookVector.
	Visuals only: the game moves the character. With opts.caster the body is hidden for the gap and restored on
	arrival (CasterState), and restored by cleanup if the effect is stopped early.

	0.00-0.16  leave: the body whites out and is pulled into a tall, thin seam of light; rings snap shut on the spot
	0.16       the seam pinches closed: one tight star, a small ring of dust. Nothing else is left behind
	0.16-0.31  gap: the caster is hidden; a thin leader of lightning finds the arrive point and a ring closes on it
	0.31       arrive: a pillar of lightning drops out of the sky, white-out flash, shock rings, cracked ground,
	           black lightning; the caster is back, white-hot, and cools over the next quarter second
	0.31-0.85  the pillar thins, the rings roll out, the cracks cool
	No ghost copies and no dash trail: that is GhostDash. ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)
local CasterState = require(script.Parent.Parent.CasterState)

local LEAVE = 0.16
local ARRIVE = 0.31
local UP = Vector3.yAxis

local BlinkStep = {
	life = 0.85,
	required = { "glow_soft", "spark_streak", "spark_glint", "shock_ring", "ground_crack", "bolt_glow", "smoke_puff" },
}

local function seq2(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, math.clamp(a, 0, 1)), NumberSequenceKeypoint.new(1, math.clamp(b, 0, 1)) })
end
local function seq3(a: number, m: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, math.clamp(a, 0, 1)), NumberSequenceKeypoint.new(0.5, math.clamp(m, 0, 1)),
		NumberSequenceKeypoint.new(1, math.clamp(b, 0, 1)) })
end

function BlinkStep.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local seed = ctx.opts.seed
	local caster = ctx.opts.caster
	local hrp = caster and caster:FindFirstChild("HumanoidRootPart")
	local rootPart: BasePart? = if hrp and hrp:IsA("BasePart") then hrp else nil

	local hide: (() -> ())? = nil
	local restore: (() -> ())? = nil
	if caster then
		hide, restore = CasterState.hider(ctx, caster)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex: { Instance } = { ctx.root }
	if caster then
		table.insert(ex, caster)
	end
	local folder = Workspace:FindFirstChild("wakuVFX")
	if folder then
		table.insert(ex, folder)
	end
	params.FilterDescendantsInstances = ex

	local A = if rootPart then rootPart.Position else ctx.cf.Position
	local hitA = Workspace:Raycast(A, -UP * 14 * S, params)
	local drop = if hitA then A.Y - hitA.Position.Y else 3 * S
	local GA = A - UP * (drop - 0.08)
	local fallback = A + ctx.cf.LookVector * 18 * S
	local B = ctx.opts.to or fallback -- latched at ARRIVE
	local GB = B - UP * (drop - 0.08)
	local latched = false
	local function target(): Vector3
		if ctx.opts.to then
			return ctx.opts.to
		elseif rootPart and rootPart.Parent then
			return rootPart.Position
		end
		return fallback
	end

	-- the body whites out before it goes, and comes back white-hot
	local glow: Highlight? = nil
	if caster then
		local hl = Instance.new("Highlight")
		hl.Name = "BlinkGlow"
		hl.Adornee = caster
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.FillColor = Color3.new(1, 1, 1)
		hl.FillTransparency = 1
		hl.OutlineTransparency = 1
		hl.Parent = ctx.root
		glow = hl
	end

	-- leave: the seam -------------------------------------------------------------------------------------------
	local sA0, sA1 = Kit.att(ctx), Kit.att(ctx)
	local seamInk = Kit.beam(ctx, sA0, sA1, "bolt_glow", -1)
	seamInk.Name = "SeamInk"
	seamInk.LightEmission = 0
	local seam = Kit.beam(ctx, sA0, sA1, "bolt_glow", 1)
	seam.Name = "Seam"
	local seamCore = Kit.beam(ctx, sA0, sA1, "bolt_glow", 2)
	seamCore.Name = "SeamCore"
	seamCore.Brightness = 3
	for _, b in { seamInk, seam, seamCore } do
		b.Segments = 1
		b.Enabled = false
	end
	local inRings = { Kit.plate(ctx, "InRing", "shock_ring", 1), Kit.plate(ctx, "InRing", "shock_ring", 1) }
	local bodyGlow = Kit.sprite(ctx, "BodyGlow", "glow_soft", 3)
	local pinch = Kit.sprite(ctx, "Pinch", "spark_glint", 5)
	local pinchLine = Kit.sprite(ctx, "PinchLine", "spark_glint", 5)
	local leaveRing = Kit.flat(ctx, "LeaveRing", { tex = "shock_ring", life = 0.2, size = { { 0, 2 }, { 1, 15 } },
		transp = { { 0, 0.1 }, { 1, 1 } }, bright = 2, z = 1 })
	local streakIn = Kit.burst(ctx, "StreakIn", { tex = "spark_streak", life = { 0.07, 0.11 }, size = { { 0, 0.3 }, { 0.4, 2.2 }, { 1, 0.2 } },
		transp = { { 0, 1 }, { 0.3, 0 }, { 1, 0.4 } }, speed = { 70, 110 }, rot = { 90 }, vpar = true, bright = 2.5 })
	local leaveDust = Kit.burst(ctx, "LeaveDust", { tex = "smoke_puff", life = { 0.25, 0.4 }, size = { { 0, 0.8 }, { 1, 3.2 } },
		transp = { { 0, 0.5 }, { 1, 1 } }, speed = { 14, 26 }, drag = 5, rot = { 0, 360 }, le = 0 })

	-- gap: the leader ---------------------------------------------------------------------------------------------
	local leader = Kit.bolt(ctx, "Leader", 8, 2, 1)
	local leaderGlow = Kit.bolt(ctx, "LeaderGlow", 8, 1, 1)
	local preRing = Kit.plate(ctx, "PreRing", "shock_ring", 1)
	local preGlow = Kit.sprite(ctx, "PreGlow", "glow_soft", 3)

	-- arrive ------------------------------------------------------------------------------------------------------
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
	local flash = Kit.sprite(ctx, "Flash", "glow_soft", 6)
	local star = Kit.sprite(ctx, "Star", "spark_glint", 7)
	local star2 = Kit.sprite(ctx, "Star2", "spark_glint", 7)
	local upRings = { Kit.plate(ctx, "UpRing", "shock_ring", 2), Kit.plate(ctx, "UpRing", "shock_ring", 2), Kit.plate(ctx, "UpRing", "shock_ring", 2) }
	local shock1 = Kit.flat(ctx, "Shock", { tex = "shock_ring", life = 0.36, size = { { 0, 3 }, { 0.25, 26 }, { 1, 46 } },
		transp = { { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } }, bright = 2.5, z = 2 })
	local shock2 = Kit.flat(ctx, "Shock2", { tex = "shock_ring", life = 0.42, size = { { 0, 2 }, { 0.3, 17 }, { 1, 30 } },
		transp = { { 0, 0.1 }, { 0.5, 0.35 }, { 1, 1 } }, bright = 2, spin = 90, z = 2 })
	local shockInk = Kit.flat(ctx, "ShockInk", { tex = "shock_ring", life = 0.4, size = { { 0, 4 }, { 0.25, 30 }, { 1, 52 } },
		transp = { { 0, 0.1 }, { 0.6, 0.45 }, { 1, 1 } }, le = 0, z = 1 })
	local crack = Kit.flat(ctx, "CrackDark", { tex = "ground_crack", life = 0.52, size = { { 0, 4 }, { 0.1, 17 }, { 1, 18 } },
		transp = { { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } }, le = 0, rot = rng:NextNumber(0, 360), z = 0.4 })
	local crackHot = Kit.flat(ctx, "CrackHot", { tex = "ground_crack", life = 0.45, size = { { 0, 4 }, { 0.12, 17 }, { 1, 18 } },
		transp = { { 0, 0 }, { 0.4, 0.25 }, { 1, 1 } }, bright = 3, rot = rng:NextNumber(0, 360), z = 0.8 })
	local bolts = {}
	for i = 1, 5 do
		bolts[i] = { glow = Kit.bolt(ctx, "HakiGlow", 5, 1, 1), core = Kit.bolt(ctx, "HakiCore", 5, 2, 0) }
	end
	local dust = Kit.burst(ctx, "Dust", { tex = "smoke_puff", life = { 0.35, 0.55 }, size = { { 0, 1.6 }, { 1, 6.5 } },
		transp = { { 0, 0.35 }, { 0.5, 0.65 }, { 1, 1 } }, speed = { 34, 62 }, drag = 4, rot = { 0, 360 }, rotSpeed = { -80, 80 }, le = 0 })
	local sparks = Kit.burst(ctx, "Sparks", { tex = "spark_streak", life = { 0.2, 0.42 }, size = { { 0, 0.4 }, { 0.2, 2.2 }, { 1, 0.2 } },
		transp = { { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } }, speed = { 45, 105 }, spread = 70, drag = 3, acc = Vector3.new(0, -70 * S, 0),
		rot = { 90 }, vpar = true, bright = 2.5 })
	local lines = Kit.burst(ctx, "SpeedLines", { tex = "spark_streak", life = { 0.1, 0.16 }, size = { { 0, 0.6 }, { 0.3, 4.4 }, { 1, 0.4 } },
		transp = { { 0, 0.1 }, { 0.6, 0.3 }, { 1, 1 } }, speed = { 110, 170 }, rot = { 90 }, vpar = true, bright = 2 })
	local glints = Kit.burst(ctx, "Glints", { tex = "spark_glint", life = { 0.18, 0.4 }, size = { { 0, 0 }, { 0.2, 1.7 }, { 1, 0 } },
		speed = { 14, 40 }, drag = 4, rot = { 0, 360 }, rotSpeed = { -160, 160 }, bright = 3 })

	local grade = Kit.grade(ctx)
	local lightPart = Kit.part(ctx, ctx.root, "Light", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightPart.Transparency = 1
	local light = Kit.light(ctx, lightPart, 36 * S)

	local once = Kit.once()
	local nIn = 0

	return function(t: number)
		local h = Kit.hue(ctx, t, 0)
		local ta = t - ARRIVE

		-- caster: white out, vanish, come back hot ---------------------------------------------------------------
		if once("hide", t, LEAVE) and hide then
			hide()
		end
		if once("latch", t, ARRIVE) then
			B = target()
			local hb = Workspace:Raycast(B, -UP * 14 * S, params)
			GB = if hb then hb.Position + UP * 0.08 else B - UP * (drop - 0.08)
			latched = true
			if restore then
				restore()
			end
		end
		if not latched then
			B = target()
			GB = B - UP * (drop - 0.08)
		end
		if glow then
			if t < LEAVE then
				glow.Enabled = true
				glow.FillColor = Kit.hot(h)
				glow.FillTransparency = 1 - Kit.easeOut(t / (LEAVE * 0.7))
			elseif t < ARRIVE then
				glow.Enabled = false
			else
				glow.Enabled = ta < 0.3
				glow.FillColor = Kit.hot(h)
				glow.FillTransparency = Kit.easeIn(Kit.ramp(ta, 0.04, 0.3))
				glow.OutlineColor = Kit.col(h, 0.7, 1)
				glow.OutlineTransparency = Kit.ramp(ta, 0, 0.3)
			end
		end

		-- leave: the body is drawn into a seam -----------------------------------------------------------------------
		local lu = Kit.ramp(t, 0, LEAVE)
		local fadeS = Kit.ramp(t, LEAVE, LEAVE + 0.11) -- the seam after it pinches shut
		if fadeS < 1 then
			local tall = (5 + 30 * Kit.easeIn(lu) + 26 * fadeS) * S
			local wide = (5.5 * (1 - Kit.easeOut(lu)) + 1.3) * (1 - fadeS) * S
			sA0.CFrame = CFrame.new(A - UP * math.min(drop, tall * 0.3))
			sA1.CFrame = CFrame.new(A + UP * tall)
			local a = 0.85 * (1 - lu) * (1 - lu)
			seamInk.Width0, seamInk.Width1 = wide * 2.6, 0
			seamInk.Color = ColorSequence.new(Kit.ink(h))
			seamInk.Transparency = seq3(0.3 + a, 0.3 + a, 1)
			seam.Width0, seam.Width1 = wide * 1.6, 0
			seam.Color = Kit.seq(ctx, h, 0.7, 0.85, 1, 6)
			seam.Transparency = seq3(a, a, 1)
			seamCore.Width0, seamCore.Width1 = wide * 0.6, 0
			seamCore.Color = ColorSequence.new(Kit.hot(h))
			seamCore.Transparency = seq3(a * 0.6, a * 0.6, 1)
			seamInk.Enabled, seam.Enabled, seamCore.Enabled = true, true, true
		else
			seamInk.Enabled, seam.Enabled, seamCore.Enabled = false, false, false
		end
		for i, ring in inRings do
			local u = Kit.ramp(t, (i - 1) * 0.05, LEAVE)
			ring.beam.Color = Kit.seq(ctx, Kit.hue(ctx, t, i * 0.3), 0.4, 0.8, 1, 4)
			ring.set(GA, UP, (20 - 18.5 * Kit.easeIn(u)) * S, if u <= 0 or t >= LEAVE then 1 else 0.7 - 0.6 * u, t * 7 + i)
		end
		bodyGlow.beam.Color = ColorSequence.new(Kit.hot(h))
		bodyGlow.set(A, (11 - 7 * lu) * S, if t < LEAVE then 0.75 - 0.6 * lu else 1)
		if t < LEAVE - 0.03 then
			local want = math.floor(t / 0.012)
			if want > nIn then
				nIn = want
				streakIn.Color = ColorSequence.new(Kit.col(Kit.hue(ctx, t, rng:NextNumber()), 0.7, 1), Kit.hot(h))
				for _ = 1, 3 do
					local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.9), rng:NextNumber(-1, 1)).Unit
					local p = A + d * rng:NextNumber(7, 10) * S
					ctx.host.CFrame = Kit.upTo(p, A - p)
					streakIn:Emit(1)
				end
			end
		end
		if once("pinch", t, LEAVE) then
			leaveRing.fire(LEAVE, GA, Kit.seq(ctx, h, 0.5, 0.6, 1, 4))
			Kit.spray(ctx, leaveDust, GA + UP * 0.6 * S, 10, ColorSequence.new(Color3.fromHSV(h, 0.14, 0.6)), "disc", 1, 0.1)
			Kit.spray(ctx, glints, A, 6, ColorSequence.new(Kit.hot(h), Kit.col(h)), "sphere", 1)
		end
		leaveRing.update(t)
		local pk = if t >= LEAVE then 1 - Kit.ramp(t, LEAVE, LEAVE + 0.09) else 0
		pinch.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		pinch.set(A, 20 * S * pk, if pk > 0 then 0 else 1, 0.4, 1)
		pinchLine.beam.Color = ColorSequence.new(Kit.hot(h + 0.3))
		pinchLine.set(A, 9 * S * pk, if pk > 0 then 0 else 1, math.pi / 2, 7) -- a wide horizontal cut

		-- gap: a leader finds the arrive point -----------------------------------------------------------------------
		local gu = Kit.ramp(t, LEAVE - 0.02, ARRIVE)
		if gu > 0 and t < ARRIVE then
			local top = B + UP * 110 * S + Vector3.new(14, 0, -9) * S
			local reach = top:Lerp(GB, Kit.easeOut(Kit.ramp(gu, 0, 0.75)))
			local sd = seed * 37 + math.floor(t / 0.035)
			leaderGlow.set(top, reach, 2.4 * S, 0.035, sd, Kit.col(Kit.hue(ctx, t, 0.3), 0.85, 1), 0.3)
			leader.set(top, reach, 0.8 * S, 0.035, sd, Kit.hot(h), 0)
			preRing.beam.Color = Kit.seq(ctx, h, 0.8, 0.85, 1, 6)
			preRing.set(GB, UP, (24 - 21 * Kit.easeIn(gu)) * S, 0.75 - 0.65 * gu, -t * 9)
			preGlow.beam.Color = ColorSequence.new(Kit.col(h + 0.15, 0.5, 1))
			preGlow.set(B, (3 + 9 * gu) * S, 0.8 - 0.6 * gu)
		else
			leader.hide()
			leaderGlow.hide()
			preRing.hide()
			preGlow.hide()
		end

		-- arrive -------------------------------------------------------------------------------------------------------
		if once("arrive", t, ARRIVE) then
			shock1.fire(ARRIVE, GB, Kit.seq(ctx, h, 0.7, 0.55, 1, 6))
			shockInk.fire(ARRIVE, GB, ColorSequence.new(Kit.ink(h)))
			crack.fire(ARRIVE, GB + UP * 0.02, ColorSequence.new(Color3.fromHSV((h + 0.6) % 1, 0.5, 0.05)))
			crackHot.fire(ARRIVE, GB + UP * 0.03, Kit.seq(ctx, h, 0.8, 0.6, 1, 6))
			local dustCol = ColorSequence.new(Color3.fromHSV(h, 0.16, 0.62), Color3.fromHSV(h, 0.1, 0.4))
			Kit.spray(ctx, dust, GB + UP * S, 28, dustCol, "disc", 2, 0.08)
			Kit.spray(ctx, sparks, GB + UP * 0.5 * S, 42, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.25, 0.8, 1)), "point", 0, 0, UP)
			Kit.spray(ctx, lines, GB + UP * 0.7 * S, 26, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.4, 0.7, 1)), "disc", 3, 0.05)
			Kit.spray(ctx, glints, B, 22, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.15)), "sphere", 3)
		end
		if once("shock2", t, ARRIVE + 0.06) then
			shock2.fire(ARRIVE + 0.06, GB, Kit.seq(ctx, h + 0.3, 0.6, 0.7, 1, 5))
		end
		shock1.update(t)
		shock2.update(t)
		shockInk.update(t)
		crack.update(t)
		crackHot.update(t)

		local arrived = ta >= 0
		local f = if arrived then 1 - Kit.ramp(ta, 0, 0.12) else 0
		flash.beam.Color = ColorSequence.new(Kit.hot(h))
		flash.set(B, (16 + 44 * f) * S, 1 - f)
		star.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
		star.set(B, 56 * S * f, if f > 0 then 0 else 1, 0.35, 1)
		star2.beam.Color = ColorSequence.new(Kit.hot(h + 0.3))
		star2.set(B, 36 * S * f, if f > 0 then 0.1 else 1, 0.35 + math.pi / 4 + ta * 5, 1)

		local pu = Kit.ramp(ta, 0, 0.34)
		if arrived and pu < 1 then
			local thin = (1 - pu) ^ 1.8
			pA0.CFrame = CFrame.new(GB)
			pA1.CFrame = CFrame.new(GB + UP * 120 * S)
			pillarInk.Width0, pillarInk.Width1 = 15 * thin * S, 8 * thin * S
			pillarInk.Color = ColorSequence.new(Kit.ink(h))
			pillarInk.Transparency = seq2(0.2 + 0.5 * pu, 0.9)
			pillar.Width0, pillar.Width1 = 10 * thin * S, 5 * thin * S
			pillar.Color = Kit.seq(ctx, h, 0.7, 0.85, 1, 6)
			pillar.Transparency = seq2(0.1 + 0.5 * pu, 0.85)
			pillarCore.Width0, pillarCore.Width1 = 4 * thin * S, 1.6 * thin * S
			pillarCore.Color = ColorSequence.new(Kit.hot(h))
			pillarCore.Transparency = seq2(0.4 * pu, 0.8)
			pillarInk.Enabled, pillar.Enabled, pillarCore.Enabled = true, true, true
		else
			pillarInk.Enabled, pillar.Enabled, pillarCore.Enabled = false, false, false
		end
		for i, ring in upRings do
			local u = Kit.ramp(ta, 0.01 + (i - 1) * 0.04, 0.3 + (i - 1) * 0.07)
			ring.beam.Color = Kit.seq(ctx, Kit.hue(ctx, t, i * 0.25), 0.5, 0.7, 1, 5)
			Kit.pulse(ring, GB + UP * (5 + 10 * i) * S, UP, u, 4 * S, (36 - 7 * i) * S, 0.1, i * 2)
		end

		local slot = math.floor(t / 0.045)
		local alive = if arrived then 1 - Kit.ramp(ta, 0.05, 0.36) else 0
		for i, b in bolts do
			local r = Random.new(seed * 131 + i * 977 + slot * 31)
			if alive > 0 and r:NextNumber() < 0.3 + 0.65 * alive then
				local a = r:NextNumber(0, math.pi * 2)
				local el = r:NextNumber(0.1, 1.2)
				local tip = B + (Vector3.new(math.cos(a), 0, math.sin(a)) * math.cos(el) + UP * math.sin(el)) * r:NextNumber(9, 20) * S
				local sd = seed * 53 + i * 101 + slot
				b.glow.set(B, tip, 2.6 * S, 0.11, sd, Kit.col(Kit.hue(ctx, t, i / #bolts), 0.9, 1), 0.25)
				b.core.set(B, tip, 0.85 * S, 0.11, sd, Color3.new(0, 0, 0), 0)
			else
				b.glow.hide()
				b.core.hide()
			end
		end

		if grade then
			local k1 = if arrived then math.exp(-ta * 24) else 0
			local k2 = if arrived then math.exp(-ta * 7) else 0
			local dim = if t < ARRIVE then Kit.ramp(t, 0, LEAVE) else 0 -- the world dips a little while they are gone
			grade.Brightness = 0.35 * k1 - 0.08 * dim
			grade.Contrast = 0.35 * k2 + 0.1 * dim
			grade.Saturation = 0.3 * k2
		end
		lightPart.CFrame = CFrame.new(if arrived then B else A)
		light.Color = Kit.col(h, 0.4, 1)
		light.Brightness = if arrived then 8 * math.exp(-ta * 8) elseif t < LEAVE then 3 * lu else 3 * (1 - fadeS)
	end
end

-- a tick when the seam shuts, a real kick on arrival
function BlinkStep.shake(t: number): Vector3
	local k = 0
	if t >= ARRIVE then
		k = 0.8 * math.exp(-(t - ARRIVE) * 10)
	elseif t >= LEAVE then
		k = 0.15 * math.exp(-(t - LEAVE) * 25)
	end
	return Vector3.new(math.sin(t * 91) * k * 0.6, math.cos(t * 113) * k, 0)
end

return BlinkStep
