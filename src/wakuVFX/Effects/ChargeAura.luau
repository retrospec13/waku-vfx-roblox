--!strict
--[[ ChargeAura: a power-up aura wrapped round the caster.
	cf = the caster's root CFrame. With opts.caster the aura follows that character's root every frame (walk, jump);
	without one it stays at cf. It never poses, hides or anchors the caster.

	0.00-0.60  charge: rings close in along the ground, light streaks are pulled into the chest, the core swells
	0.60       ignition: flash, a light pillar, a shock ring and a dust push along the ground
	0.60-3.60  hold: a teardrop of flame tongues (dark ink halo, rainbow body, white-hot heart) flickers round the
	           body, embers and streaks rise, pebbles lift, ripples roll out along the ground
	last 0.35  the flames sink back into the ground
	Stop it earlier with handle.stop(). ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)

local CHARGE = 0.6
local HOLD = 3.0
local FADE = 0.35

local ChargeAura = {
	life = CHARGE + HOLD,
	required = { "glow_soft", "spark_streak", "spark_glint", "shock_ring", "ground_disc", "bolt_glow", "smoke_puff" },
}

type Tongue = { a0: Attachment, a1: Attachment, b: Beam, ang: number, r: number, h: number, w: number, lean: number,
	p1: number, p2: number, f1: number, f2: number }

function ChargeAura.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local life = ChargeAura.life
	local caster = ctx.opts.caster
	local hrp = caster and caster:FindFirstChild("HumanoidRootPart")
	local rootPart: BasePart? = if hrp and hrp:IsA("BasePart") then hrp else nil

	-- height of the root above the ground, measured once (so a jump lifts the whole aura with the body)
	local start = if rootPart then rootPart.Position else ctx.cf.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if caster then { ctx.root, caster } :: { Instance } else { ctx.root } :: { Instance }
	local hit = Workspace:Raycast(start, Vector3.new(0, -14 * S, 0), params)
	local drop = if hit then start.Y - hit.Position.Y else 3 * S

	-- flame tongues: curved, tapered ribbons from a ring at the feet to a point above the head
	local function tongues(n: number, name: string, z: number, r: { number }, h: { number }, w: { number }, lean: number, speed: number): { Tongue }
		local list = {}
		for i = 1, n do
			local a0, a1 = Kit.att(ctx), Kit.att(ctx)
			local b = Kit.beam(ctx, a0, a1, "bolt_glow", z)
			b.Name = name
			b.Segments = 14
			b.Width1 = 0
			b.Enabled = false
			table.insert(list, {
				a0 = a0, a1 = a1, b = b,
				ang = (i - 1) / n * math.pi * 2 + rng:NextNumber(-0.25, 0.25),
				r = rng:NextNumber(r[1], r[2]), h = rng:NextNumber(h[1], h[2]), w = rng:NextNumber(w[1], w[2]),
				lean = rng:NextNumber(-lean, lean),
				p1 = rng:NextNumber(0, 6.28), p2 = rng:NextNumber(0, 6.28),
				f1 = rng:NextNumber(13, 19) * speed, f2 = rng:NextNumber(23, 31) * speed,
			})
		end
		return list
	end
	local inkT = tongues(7, "InkTongue", -2, { 1.5, 2.0 }, { 9.0, 11.5 }, { 3.4, 4.4 }, 0.9, 0.8)
	local bodyT = tongues(10, "FlameTongue", 0, { 1.1, 1.6 }, { 6.6, 9.0 }, { 2.4, 3.2 }, 0.6, 1)
	local hotT = tongues(5, "HotTongue", 2, { 0.35, 0.7 }, { 3.6, 5.4 }, { 1.3, 1.8 }, 0.3, 1.5)
	for _, tg in inkT do
		tg.b.LightEmission = 0 -- drawn dark, behind the flame
	end
	-- g = how far the tongue has grown (0..1), a = opacity (0..1)
	local function place(tg: Tongue, base: Vector3, t: number, g: number): number
		local n = 0.5 * math.sin(t * tg.f1 + tg.p1) + 0.5 * math.sin(t * tg.f2 + tg.p2)
		local h = tg.h * S * g * (0.78 + 0.22 * n)
		local ang = tg.ang + 0.3 * math.sin(t * 2.3 + tg.p1)
		local rad = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local p0 = base + rad * tg.r * S * (0.45 + 0.55 * g) + Vector3.new(0, 0.12 * S, 0)
		local sway = Vector3.new(math.sin(t * tg.f1 * 0.45 + tg.p2), 0, math.cos(t * tg.f2 * 0.4 + tg.p1)) * 0.45 * S
		local tip = base + Vector3.new(0, h, 0) + rad * tg.lean * S + sway
		tg.a0.CFrame = Kit.rightTo(p0, rad + Vector3.yAxis * 0.5)
		tg.a1.CFrame = Kit.rightTo(tip, Vector3.yAxis - rad * 0.3)
		tg.b.CurveSize0 = h * 0.42
		tg.b.CurveSize1 = h * 0.4
		tg.b.Width0 = tg.w * S * (0.82 + 0.18 * n) * (0.4 + 0.6 * g)
		return n
	end

	-- white-hot heart and its flare star at the chest
	local core = Kit.sprite(ctx, "Core", "glow_soft", 3)
	local halo = Kit.sprite(ctx, "CoreHalo", "glow_soft", 1)
	local star = Kit.sprite(ctx, "CoreStar", "spark_glint", 4)
	-- ignition pillar
	local pA0, pA1 = Kit.att(ctx), Kit.att(ctx)
	local pillar = Kit.beam(ctx, pA0, pA1, "bolt_glow", 1)
	pillar.Name = "Pillar"
	pillar.Enabled = false
	local pB = Kit.beam(ctx, pA0, pA1, "bolt_glow", 2)
	pB.Name = "PillarCore"
	pB.Enabled = false

	-- ground: a slowly turning rainbow disc, closing charge rings, the ignition shock, rolling ripples
	local disc = Kit.plate(ctx, "GroundDisc", "ground_disc", 0)
	disc.beam.Brightness = 1.4
	local closeRings = { Kit.plate(ctx, "ChargeRing", "shock_ring", 1), Kit.plate(ctx, "ChargeRing", "shock_ring", 1) }
	local shock = Kit.flat(ctx, "IgniteShock", { tex = "shock_ring", life = 0.42, size = { { 0, 3 }, { 0.2, 14 }, { 1, 24 } },
		transp = { { 0, 0 }, { 0.5, 0.35 }, { 1, 1 } }, bright = 2, z = 2 })
	local shockInk = Kit.flat(ctx, "IgniteInk", { tex = "shock_ring", life = 0.5, size = { { 0, 4 }, { 0.2, 16 }, { 1, 27 } },
		transp = { { 0, 0.2 }, { 0.6, 0.5 }, { 1, 1 } }, le = 0, z = 1 })
	local ripples = {}
	for i = 1, 3 do
		ripples[i] = Kit.flat(ctx, "Ripple", { tex = "shock_ring", life = 0.85, size = { { 0, 3.5 }, { 1, 15 } },
			transp = { { 0, 1 }, { 0.15, 0.35 }, { 1, 1 } }, spin = 40, rot = i * 47, bright = 1.3, z = 1 })
	end
	local endRing = Kit.flat(ctx, "EndRing", { tex = "shock_ring", life = 0.34, size = { { 0, 9 }, { 1, 2 } },
		transp = { { 0, 1 }, { 0.3, 0.3 }, { 1, 1 } }, z = 1 })

	-- pebbles lifted off the ground by the pressure
	local pebbles = {}
	for i = 1, 8 do
		local sz = rng:NextNumber(0.22, 0.5) * S
		local p = Kit.part(ctx, ctx.root, "Pebble", Vector3.new(sz, sz * rng:NextNumber(0.6, 1), sz), Kit.ink(i / 8), Enum.Material.Slate)
		pebbles[i] = { part = p, ang = rng:NextNumber(0, 6.28), r = rng:NextNumber(2.2, 4.4), v = rng:NextNumber(1.6, 3.4),
			ph = rng:NextNumber(0, 1), spin = rng:NextNumber(-4, 4), tint = i / 8 }
	end

	-- particles
	local streakIn = Kit.burst(ctx, "StreakIn", { tex = "spark_streak", life = { 0.18, 0.26 }, size = { { 0, 0.5 }, { 0.3, 2.2 }, { 1, 0.3 } },
		transp = { { 0, 1 }, { 0.25, 0 }, { 1, 0.6 } }, speed = { 24, 32 }, rot = { 90 }, vpar = true, bright = 2 })
	local embers = Kit.burst(ctx, "Embers", { tex = "spark_glint", life = { 0.7, 1.25 }, size = { { 0, 0 }, { 0.15, 0.55 }, { 1, 0 } },
		speed = { 5, 10 }, spread = 14, acc = Vector3.new(0, 7 * S, 0), rot = { 0, 360 }, rotSpeed = { -120, 120 }, bright = 2.5 })
	local streakUp = Kit.burst(ctx, "StreakUp", { tex = "spark_streak", life = { 0.26, 0.42 }, size = { { 0, 0.6 }, { 0.3, 2.6 }, { 1, 0.4 } },
		transp = { { 0, 0.2 }, { 0.6, 0.2 }, { 1, 1 } }, speed = { 22, 34 }, spread = 5, rot = { 90 }, vpar = true, bright = 2 })
	local dust = Kit.burst(ctx, "Dust", { tex = "smoke_puff", life = { 0.55, 0.95 }, size = { { 0, 1.6 }, { 1, 5.2 } },
		transp = { { 0, 0.45 }, { 0.5, 0.7 }, { 1, 1 } }, speed = { 16, 28 }, drag = 3.2, rot = { 0, 360 }, rotSpeed = { -60, 60 }, le = 0 })
	local glints = Kit.burst(ctx, "Glints", { tex = "spark_glint", life = { 0.25, 0.45 }, size = { { 0, 0 }, { 0.2, 1.5 }, { 1, 0 } },
		speed = { 14, 30 }, drag = 4, rot = { 0, 360 }, bright = 3 })

	-- body glow (a Highlight owned by the effect model; the caster itself is not modified)
	local glow: Highlight? = nil
	if caster then
		local hl = Instance.new("Highlight")
		hl.Name = "BodyGlow"
		hl.Adornee = caster
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.FillTransparency = 1
		hl.OutlineTransparency = 1
		hl.Parent = ctx.root
		glow = hl
	end

	local lightPart = Kit.part(ctx, ctx.root, "Light", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightPart.Transparency = 1
	local light = Kit.light(ctx, lightPart, 20 * S)

	local once = Kit.once()
	local nIn, nEmber, nStreak = 0, 0, 0
	local UP = Vector3.yAxis

	return function(t: number)
		local rootPos = if rootPart and rootPart.Parent then rootPart.Position else start
		local base = rootPos - Vector3.new(0, drop - 0.06, 0)
		local chest = base + UP * math.min(drop, 3.4 * S)
		local out = Kit.ramp(t, life - FADE, life) -- 0..1 over the fade-out
		local lit = t >= CHARGE
		local hBody = Kit.hue(ctx, t, 0)
		local fl = Kit.slotRng(ctx.opts.seed, t, 1 / 24):NextNumber() -- hot-core flicker, one value per 1/24 s

		-- flames --------------------------------------------------------------------------------------------
		local grow = if lit then Kit.easeOutBack(Kit.ramp(t, CHARGE, CHARGE + 0.22)) * (1 - Kit.easeIn(out)) else 0
		local seed = if lit then 0 else Kit.easeIn(Kit.ramp(t, 0.12, CHARGE)) * 0.3 -- low licks while charging
		local g = math.max(grow, seed)
		for i, tg in bodyT do
			local n = place(tg, base, t, g)
			local h = Kit.hue(ctx, t, i / #bodyT)
			tg.b.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Kit.hot(h)),
				ColorSequenceKeypoint.new(0.3, Kit.col(h, 0.85, 1)),
				ColorSequenceKeypoint.new(1, Kit.col(h + 0.12, 0.95, 1)),
			})
			local a = (0.42 + 0.1 * n) + 0.5 * out
			tg.b.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, math.min(1, a + 0.25)),
				NumberSequenceKeypoint.new(0.2, math.min(1, a)),
				NumberSequenceKeypoint.new(0.75, math.min(1, a + 0.2)),
				NumberSequenceKeypoint.new(1, 1),
			})
			tg.b.Enabled = g > 0.02
		end
		for i, tg in inkT do
			place(tg, base, t, grow)
			tg.b.Color = ColorSequence.new(Kit.ink(Kit.hue(ctx, t, i / #inkT)))
			local a = 0.5 + 0.5 * out
			tg.b.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.25, a),
				NumberSequenceKeypoint.new(0.8, math.min(1, a + 0.15)),
				NumberSequenceKeypoint.new(1, 1),
			})
			tg.b.Enabled = grow > 0.02
		end
		for i, tg in hotT do
			place(tg, base, t, grow * (0.8 + 0.2 * fl))
			tg.b.Color = ColorSequence.new(Kit.hot(Kit.hue(ctx, t, i / #hotT)))
			local a = 0.3 + 0.25 * fl + 0.6 * out
			tg.b.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, math.min(1, a)),
				NumberSequenceKeypoint.new(0.6, math.min(1, a + 0.25)),
				NumberSequenceKeypoint.new(1, 1),
			})
			tg.b.Enabled = grow > 0.02
		end

		-- heart -------------------------------------------------------------------------------------------
		local swell = Kit.easeIn(Kit.ramp(t, 0, CHARGE))
		local flash = if lit then 1 - Kit.ramp(t, CHARGE, CHARGE + 0.09) else 0
		local hold = if lit then 1 - out else 0
		core.beam.Color = ColorSequence.new(Kit.hot(hBody))
		core.set(chest, (0.6 + 2.2 * swell + 5 * flash + (0.5 + 0.9 * fl) * hold) * S, 0.25 + 0.3 * fl * hold + 0.6 * out)
		halo.beam.Color = ColorSequence.new(Kit.col(hBody, 0.8, 1))
		halo.set(chest, (2 + 5 * swell + 9 * flash + 1.2 * fl * hold) * S, 0.62 + 0.12 * fl - 0.3 * flash + 0.4 * out)
		star.beam.Color = ColorSequence.new(Kit.hot(hBody + 0.1))
		local starSize = if lit then 13 * flash else 4.5 * swell * (0.7 + 0.3 * fl)
		star.set(chest, starSize * S, if lit then 0.1 else 0.25, t * 2.2, 1)

		-- ignition pillar -----------------------------------------------------------------------------------
		local pu = Kit.ramp(t, CHARGE, CHARGE + 0.26)
		if lit and pu < 1 then
			pA0.CFrame = CFrame.new(base)
			pA1.CFrame = CFrame.new(base + UP * (8 + 26 * Kit.easeOut(pu)) * S)
			pillar.Width0, pillar.Width1 = 7 * (1 - pu) * S, 3 * (1 - pu) * S
			pillar.Color = Kit.hueSeq(hBody, 0.5, 0.85, 1, 5)
			pillar.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25 + 0.6 * pu), NumberSequenceKeypoint.new(1, 1) })
			pB.Width0, pB.Width1 = 2.6 * (1 - pu) * S, 0.6 * (1 - pu) * S
			pB.Color = ColorSequence.new(Kit.hot(hBody))
			pB.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6 * pu), NumberSequenceKeypoint.new(1, 1) })
			pillar.Enabled, pB.Enabled = true, true
		else
			pillar.Enabled, pB.Enabled = false, false
		end

		-- ground --------------------------------------------------------------------------------------------
		local gp = base + UP * 0.04
		local discSize = if lit then (12.5 + 0.8 * math.sin(t * 5)) * (1 - 0.6 * out) else 5 + 4 * swell
		disc.beam.Color = Kit.hueSeq(hBody, if ctx.opts.rainbow then 0.7 else 0.08, 0.85, 1, 6)
		disc.set(gp, UP, discSize * S, (if lit then 0.52 else 0.9 - 0.3 * swell) + 0.5 * out, t * 0.9)
		for i, ring in closeRings do
			local u = Kit.ramp(t, 0.04 + (i - 1) * 0.24, 0.34 + (i - 1) * 0.24)
			ring.beam.Color = Kit.hueSeq(Kit.hue(ctx, t, i * 0.3), 0.35, 0.8, 1, 4)
			ring.set(gp, UP, (17 - 14 * Kit.easeIn(u)) * S, if u <= 0 or u >= 1 then 1 else 1 - 0.75 * math.sin(u * math.pi) ^ 0.6, i * 1.3 - t * 3)
		end
		if once("shock", t, CHARGE) then
			shock.fire(CHARGE, gp, Kit.hueSeq(hBody, 0.6, 0.6, 1, 5))
			shockInk.fire(CHARGE, gp, ColorSequence.new(Kit.ink(hBody)))
			Kit.spray(ctx, dust, gp + UP * 0.6 * S, 16, ColorSequence.new(Color3.fromHSV(hBody, 0.2, 0.62)), "disc", 2, 0.12)
			Kit.spray(ctx, glints, chest, 16, ColorSequence.new(Kit.hot(hBody), Kit.col(hBody + 0.2)), "sphere", 1)
			streakUp.Color = ColorSequence.new(Kit.hot(hBody), Kit.col(hBody + 0.3))
			for _ = 1, 14 do
				local a = rng:NextNumber(0, 6.28)
				ctx.host.CFrame = Kit.upTo(base + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(0.4, 2.4) * S, UP)
				streakUp:Emit(1)
			end
		end
		shock.update(t)
		shockInk.update(t)
		for i, rp in ripples do
			-- one ripple every 0.5 s, cycling through three cards
			for k = 0, 6 do
				local at = CHARGE + 0.45 + (k * 3 + (i - 1)) * 0.5
				if at < life - 0.7 and once("rip" .. i .. "_" .. k, t, at) then
					rp.fire(at, gp, Kit.hueSeq(Kit.hue(ctx, at, 0.2), 0.4, 0.75, 1, 4))
				end
			end
			rp.update(t)
		end
		if once("end", t, life - FADE) then
			endRing.fire(life - FADE, gp, Kit.hueSeq(hBody, 0.5, 0.7, 1, 4))
		end
		endRing.update(t)

		-- pebbles -------------------------------------------------------------------------------------------
		for _, pb in pebbles do
			local rise = t - CHARGE * 0.5
			local H = 7.5 * S
			local y = ((rise * pb.v * S) / H + pb.ph) % 1
			local vis = if rise > 0 then math.sin(y * math.pi) * (1 - out) else 0
			if vis > 0.05 then
				local a = pb.ang + t * 0.5
				pb.part.CFrame = CFrame.new(base + Vector3.new(math.cos(a) * pb.r * S, y * H, math.sin(a) * pb.r * S))
					* CFrame.Angles(t * pb.spin, t * pb.spin * 0.7, 0)
				pb.part.Transparency = 1 - vis
				pb.part.Color = Kit.ink(hBody + pb.tint * 0.3)
			else
				pb.part.CFrame = Kit.HIDE
			end
		end

		-- particles on fixed slots --------------------------------------------------------------------------
		local wantIn = if t < CHARGE - 0.1 then math.floor(t / 0.035) else nIn
		if wantIn > nIn then
			nIn = wantIn
			streakIn.Color = ColorSequence.new(Kit.col(Kit.hue(ctx, t, rng:NextNumber()), 0.7, 1), Kit.hot(hBody))
			for _ = 1, 3 do
				local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.15, 1), rng:NextNumber(-1, 1))
				d = if d.Magnitude > 1e-3 then d.Unit else UP
				ctx.host.CFrame = Kit.upTo(chest + d * rng:NextNumber(6, 8.5) * S, -d)
				streakIn:Emit(1)
			end
		end
		if lit and t < life - 0.55 then
			local wantE = math.floor((t - CHARGE) / 0.05)
			if wantE > nEmber then
				nEmber = wantE
				local h = Kit.hue(ctx, t, rng:NextNumber())
				embers.Color = ColorSequence.new(Kit.hot(h), Kit.col(h, 0.9, 1))
				for _ = 1, 2 do
					local a = rng:NextNumber(0, 6.28)
					ctx.host.CFrame = Kit.upTo(base + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(0.6, 3) * S + UP * rng:NextNumber(0, 2) * S, UP)
					embers:Emit(1)
				end
			end
			local wantS = math.floor((t - CHARGE) / 0.09)
			if wantS > nStreak then
				nStreak = wantS
				local h = Kit.hue(ctx, t, rng:NextNumber())
				streakUp.Color = ColorSequence.new(Kit.hot(h), Kit.col(h, 0.85, 1))
				for _ = 1, 2 do
					local a = rng:NextNumber(0, 6.28)
					ctx.host.CFrame = Kit.upTo(base + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(0.8, 2.6) * S, UP)
					streakUp:Emit(1)
				end
			end
		end

		-- body glow and light -------------------------------------------------------------------------------
		if glow then
			glow.FillColor = if flash > 0.3 then Kit.hot(hBody) else Kit.col(hBody, 0.75, 1)
			glow.OutlineColor = Kit.hot(hBody)
			local fill = if lit then 0.66 + 0.1 * fl - 0.5 * flash else 1 - 0.3 * swell
			glow.FillTransparency = math.clamp(fill + out * 0.4, 0, 1)
			glow.OutlineTransparency = math.clamp((if lit then 0.15 + 0.2 * fl else 1 - 0.7 * swell) + out, 0, 1)
		end
		lightPart.CFrame = CFrame.new(chest)
		light.Color = Kit.col(hBody, 0.5, 1)
		light.Brightness = (1.2 * swell + (if lit then 2.2 + 0.8 * fl else 0) + 5 * flash) * (1 - out)
	end
end

-- a kick at ignition, then a faint tremble while the aura burns
function ChargeAura.shake(t: number): Vector3
	if t < CHARGE or t > ChargeAura.life - FADE then
		return Vector3.zero
	end
	local k = 0.32 * math.exp(-(t - CHARGE) * 9) + 0.025
	return Vector3.new(math.sin(t * 71) * k, math.cos(t * 83) * k, 0)
end

return ChargeAura
