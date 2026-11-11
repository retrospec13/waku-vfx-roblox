--!strict
--[[ Fireball: a thrown fireball the size of a small house.
	cf = the caster's root CFrame; the ball flies along cf.LookVector and stops at the first thing it hits within
	60 studs (it bursts in mid-air at full range). It never poses or touches the caster.

	0.00-0.20  charge flare: rings and streaks fall into a point in front of the caster, a star swells there
	0.20       launch: muzzle star, a ring kicked back off the launch, dust
	0.20-~0.8  flight (0.4 s point blank .. 0.65 s at full range): a white-hot core in a burning shell with a dark
	           halo and a turning star, a long tapering flame tail (dark edge, colour body, white heart), two flame
	           ribbons winding round it, sonic rings shed along the path, flame puffs, dark smoke and embers behind
	impact     0.4 s burst: flash and star, a fire dome that swells and thins, a ring of spikes, shock rings on the
	           surface, sparks that fall, black lightning, rolling fire and rising smoke
	..1.60     a scorch ring and glowing cracks cool on whatever it hit, small flames still licking

	Rainbow by default like the rest of the kit; { rainbow = false, hue = 0.05 } is plain orange fire. ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)

local CHARGE = 0.2
local BURST = 0.4
local UP = Vector3.yAxis

local Fireball = {
	life = 1.6,
	required = { "glow_soft", "spark_streak", "spark_glint", "shock_ring", "ground_crack", "ground_disc", "bolt_glow", "smoke_puff", "slash_body" },
}

local lastHit = CHARGE + 0.5 -- when the last cast landed (camera shake reads it)

function Fireball.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local seed = ctx.opts.seed
	local rainbow = ctx.opts.rainbow
	local life = Fireball.life
	local span = if rainbow then 1 else 0.1
	local dir = ctx.cf.LookVector
	local M = ctx.cf.Position + dir * 3 * S + UP * 0.5 * S
	local RANGE = 60 * S

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex: { Instance } = { ctx.root }
	if ctx.opts.caster then
		table.insert(ex, ctx.opts.caster)
	end
	local folder = Workspace:FindFirstChild("wakuVFX")
	if folder then
		table.insert(ex, folder) -- other running effects never block the ball
	end
	params.FilterDescendantsInstances = ex
	local E, N, struck = M + dir * RANGE, -dir, false
	local rc = Workspace:Raycast(M, dir * RANGE, params)
	if rc then
		E, N, struck = rc.Position, rc.Normal, true
	end
	local dist = (E - M).Magnitude
	local flightT = 0.4 + 0.25 * dist / RANGE
	local tHit = CHARGE + flightT
	lastHit = tHit
	local gm = Workspace:Raycast(M, Vector3.new(0, -9 * S, 0), params)
	local ge = Workspace:Raycast(E + N * 0.5, Vector3.new(0, -14 * S, 0), params)
	local side = dir:Cross(UP)
	side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
	local lift = side:Cross(dir)

	local function ink(h: number): Color3
		return if rainbow then Kit.ink(h) else Color3.fromHSV(h % 1, 0.85, 0.16)
	end
	local function fire(h: number, n: number?): ColorSequence -- hot end first
		return Kit.hueSeq(h + (if rainbow then 0.1 else 0.07), if rainbow then 0.5 else -0.07, 0.9, 1, n or 5)
	end
	local SMOKE = ColorSequence.new(Color3.fromRGB(34, 30, 36), Color3.fromRGB(12, 11, 14))

	-- charge ---------------------------------------------------------------------------------------------------
	local gather = { Kit.plate(ctx, "Gather", "shock_ring", 1), Kit.plate(ctx, "Gather", "shock_ring", 1), Kit.plate(ctx, "Gather", "shock_ring", 1) }
	local chargeGlow = Kit.sprite(ctx, "ChargeGlow", "glow_soft", 2)
	local chargeStar = Kit.sprite(ctx, "ChargeStar", "spark_glint", 3)
	local muzzleStar = Kit.sprite(ctx, "MuzzleStar", "spark_glint", 4)
	local muzzleRings = { Kit.plate(ctx, "MuzzleRing", "shock_ring", 1), Kit.plate(ctx, "MuzzleRing", "shock_ring", 1) }
	local muzzleKick = Kit.flat(ctx, "MuzzleKick", { tex = "shock_ring", life = 0.3, size = { { 0, 3 }, { 0.4, 20 }, { 1, 30 } },
		transp = { { 0, 0.1 }, { 0.5, 0.4 }, { 1, 1 } }, bright = 2, z = 0.5 })
	local inward = Kit.burst(ctx, "ChargeIn", { tex = "spark_streak", life = { 0.1, 0.16 }, size = { { 0, 0.5 }, { 0.4, 2.6 }, { 1, 0.3 } },
		transp = { { 0, 0.5 }, { 0.5, 0.05 }, { 1, 0.4 } }, speed = { 70, 95 }, rot = { 90 }, vpar = true, bright = 2.5 })

	-- the ball -------------------------------------------------------------------------------------------------
	local core = Kit.part(ctx, ctx.root, "Core", Vector3.one, Color3.new(1, 1, 1), Enum.Material.Neon)
	core.Shape = Enum.PartType.Ball
	local shellP = Kit.part(ctx, ctx.root, "Shell", Vector3.one, Color3.new(1, 1, 1), Enum.Material.Neon)
	shellP.Shape = Enum.PartType.Ball
	local halo = Kit.sprite(ctx, "Halo", "glow_soft", -2)
	halo.beam.LightEmission = 0
	local glow = Kit.sprite(ctx, "Glow", "glow_soft", 2)
	local star = Kit.sprite(ctx, "Star", "spark_glint", 4)
	local star2 = Kit.sprite(ctx, "Star2", "spark_glint", 4)
	local tA0, tA1 = Kit.att(ctx), Kit.att(ctx)
	local tailInk = Kit.beam(ctx, tA0, tA1, "slash_body", -1)
	tailInk.Name = "TailInk"
	tailInk.LightEmission = 0
	local tail = Kit.beam(ctx, tA0, tA1, "slash_body", 1)
	tail.Name = "Tail"
	tail.Brightness = 2
	local tailHot = Kit.beam(ctx, tA0, tA1, "bolt_glow", 2)
	tailHot.Name = "TailHeart"
	tailHot.Brightness = 3
	for _, b in { tailInk, tail, tailHot } do
		b.Width1 = 0
		b.Enabled = false
	end
	local ribbons = {}
	for i = 1, 2 do
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local b = Kit.beam(ctx, a0, a1, "slash_body", 1.5)
		b.Name = "Ribbon"
		b.Brightness = 2
		b.Width1 = 0
		b.Enabled = false
		local c = Kit.beam(ctx, a0, a1, "bolt_glow", 2.5)
		c.Name = "RibbonCore"
		c.Width1 = 0
		c.Enabled = false
		ribbons[i] = { a0 = a0, a1 = a1, body = b, core = c }
	end
	local sonic = {}
	for i = 1, 5 do
		sonic[i] = Kit.plate(ctx, "Sonic", "shock_ring", 1)
	end
	local flames = Kit.burst(ctx, "Flames", { tex = "smoke_puff", life = { 0.22, 0.4 }, size = { { 0, 5 }, { 0.3, 6.5 }, { 1, 1.2 } },
		transp = { { 0, 0.1 }, { 0.5, 0.4 }, { 1, 1 } }, speed = { 4, 14 }, spread = 40, drag = 2, acc = Vector3.new(0, 14 * S, 0),
		rot = { 0, 360 }, rotSpeed = { -200, 200 }, bright = 2.2 })
	local smoke = Kit.burst(ctx, "Smoke", { tex = "smoke_puff", life = { 0.6, 1 }, size = { { 0, 3.5 }, { 1, 10 } },
		transp = { { 0, 0.35 }, { 0.5, 0.6 }, { 1, 1 } }, speed = { 2, 9 }, spread = 60, drag = 1.5, acc = Vector3.new(0, 9 * S, 0),
		rot = { 0, 360 }, rotSpeed = { -60, 60 }, le = 0, zoff = -1 })
	local embers = Kit.burst(ctx, "Embers", { tex = "spark_glint", life = { 0.35, 0.7 }, size = { { 0, 0 }, { 0.15, 1.3 }, { 1, 0 } },
		speed = { 8, 30 }, spread = 70, drag = 1.5, acc = Vector3.new(0, -26 * S, 0), rot = { 0, 360 }, rotSpeed = { -200, 200 }, bright = 3 })

	-- impact ---------------------------------------------------------------------------------------------------
	local flash = Kit.sprite(ctx, "Flash", "glow_soft", 6)
	local boomStar = Kit.sprite(ctx, "BoomStar", "spark_glint", 7)
	local boomStar2 = Kit.sprite(ctx, "BoomStar2", "spark_glint", 7)
	local boomInk = Kit.sprite(ctx, "BoomInk", "glow_soft", -2)
	boomInk.beam.LightEmission = 0
	local boomRing = Kit.sprite(ctx, "BoomRing", "shock_ring", 3)
	local dome = Kit.part(ctx, ctx.root, "Dome", Vector3.one, Color3.new(1, 1, 1), Enum.Material.Neon)
	dome.Shape = Enum.PartType.Ball
	local domeHot = Kit.part(ctx, ctx.root, "DomeHeart", Vector3.one, Color3.new(1, 1, 1), Enum.Material.Neon)
	domeHot.Shape = Enum.PartType.Ball
	local spikes = {}
	local nb = N:Cross(UP)
	nb = if nb.Magnitude > 1e-3 then nb.Unit else Vector3.xAxis
	local nc = N:Cross(nb)
	for i = 1, 16 do
		local a = (i - 1) / 16 * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local tilt = if i % 2 == 0 then rng:NextNumber(0.1, 0.35) else rng:NextNumber(0.5, 1.1)
		local d = ((nb * math.cos(a) + nc * math.sin(a)) * math.cos(tilt) + N * math.sin(tilt)).Unit
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local inkB = Kit.beam(ctx, a0, a1, "bolt_glow", 0)
		inkB.Name = "SpikeInk"
		inkB.LightEmission = 0
		local b = Kit.beam(ctx, a0, a1, "bolt_glow", 2)
		b.Name = "Spike"
		b.Brightness = 2
		local c = Kit.beam(ctx, a0, a1, "bolt_glow", 3)
		c.Name = "SpikeCore"
		for _, x in { inkB, b, c } do
			x.Segments = 1
			x.Width1 = 0
			x.Enabled = false
		end
		spikes[i] = { d = d, len = rng:NextNumber(26, 44) * S, a0 = a0, a1 = a1, ink = inkB, body = b, core = c, tint = i / 16 }
	end
	local shocks = { Kit.plate(ctx, "Shock", "shock_ring", 2), Kit.plate(ctx, "Shock", "shock_ring", 2), Kit.plate(ctx, "Shock", "shock_ring", 2) }
	local shockInk = Kit.plate(ctx, "ShockInk", "shock_ring", 1)
	shockInk.beam.LightEmission = 0
	local scorch = Kit.plate(ctx, "Scorch", "ground_disc", 0.3)
	scorch.beam.LightEmission = 0
	local scorchCrack = Kit.plate(ctx, "ScorchCrack", "ground_crack", 0.5)
	scorchCrack.beam.LightEmission = 0
	local scorchRing = Kit.plate(ctx, "ScorchRing", "shock_ring", 0.6)
	scorchRing.beam.LightEmission = 0
	local emberCrack = Kit.plate(ctx, "EmberCrack", "ground_crack", 0.8)
	emberCrack.beam.Brightness = 2.5
	local emberRing = Kit.plate(ctx, "EmberRing", "shock_ring", 0.9)
	local groundShock = Kit.flat(ctx, "GroundShock", { tex = "shock_ring", life = 0.45, size = { { 0, 8 }, { 0.3, 46 }, { 1, 74 } },
		transp = { { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } }, bright = 2.5, z = 1 })
	local groundInk = Kit.flat(ctx, "GroundInk", { tex = "shock_ring", life = 0.5, size = { { 0, 10 }, { 0.3, 54 }, { 1, 86 } },
		transp = { { 0, 0.15 }, { 0.6, 0.5 }, { 1, 1 } }, le = 0, z = 0.5 })
	local bolts = {}
	for i = 1, 5 do
		bolts[i] = { glow = Kit.bolt(ctx, "HakiGlow", 5, 3, 1), core = Kit.bolt(ctx, "HakiCore", 5, 4, 0) }
	end
	local sparks = Kit.burst(ctx, "Sparks", { tex = "spark_streak", life = { 0.35, 0.8 }, size = { { 0, 0.5 }, { 0.2, 2.6 }, { 1, 0.2 } },
		transp = { { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } }, speed = { 60, 150 }, spread = 62, drag = 2.2, acc = Vector3.new(0, -90 * S, 0),
		rot = { 90 }, vpar = true, bright = 3 })
	local glints = Kit.burst(ctx, "Glints", { tex = "spark_glint", life = { 0.3, 0.7 }, size = { { 0, 0 }, { 0.2, 2.2 }, { 1, 0 } },
		speed = { 20, 70 }, drag = 3, rot = { 0, 360 }, rotSpeed = { -200, 200 }, bright = 3 })
	local lines = Kit.burst(ctx, "BoomLines", { tex = "spark_streak", life = { 0.12, 0.22 }, size = { { 0, 0.8 }, { 0.3, 6.5 }, { 1, 0.5 } },
		transp = { { 0, 0.1 }, { 0.6, 0.3 }, { 1, 1 } }, speed = { 150, 240 }, spread = 75, rot = { 90 }, vpar = true, bright = 2.5 })
	local roll = Kit.burst(ctx, "FireRoll", { tex = "smoke_puff", life = { 0.3, 0.55 }, size = { { 0, 5 }, { 0.3, 11 }, { 1, 3 } },
		transp = { { 0, 0.05 }, { 0.5, 0.35 }, { 1, 1 } }, speed = { 30, 90 }, spread = 80, drag = 4.5, acc = Vector3.new(0, 20 * S, 0),
		rot = { 0, 360 }, rotSpeed = { -240, 240 }, bright = 2.5 })
	local boomSmoke = Kit.burst(ctx, "BoomSmoke", { tex = "smoke_puff", life = { 0.7, 1.1 }, size = { { 0, 6 }, { 1, 17 } },
		transp = { { 0, 0.3 }, { 0.5, 0.55 }, { 1, 1 } }, speed = { 14, 50 }, spread = 80, drag = 3.5, acc = Vector3.new(0, 16 * S, 0),
		rot = { 0, 360 }, rotSpeed = { -50, 50 }, le = 0, zoff = -1 })
	local licks = Kit.burst(ctx, "Licks", { tex = "smoke_puff", life = { 0.25, 0.45 }, size = { { 0, 2.6 }, { 0.3, 3.4 }, { 1, 0.4 } },
		transp = { { 0, 0.15 }, { 0.6, 0.4 }, { 1, 1 } }, speed = { 8, 18 }, spread = 12, acc = Vector3.new(0, 30 * S, 0),
		rot = { 0, 360 }, rotSpeed = { -160, 160 }, bright = 2.2 })

	local grade = Kit.grade(ctx)
	local lightPart = Kit.part(ctx, ctx.root, "Light", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightPart.Transparency = 1
	local light = Kit.light(ctx, lightPart, 42 * S)

	local once = Kit.once()
	local nTrail, nLick, nIn = 0, 0, 0
	local RB = 4.4 * S -- ball radius

	local function headAt(t: number): Vector3
		local u = math.clamp((t - CHARGE) / flightT, 0, 1)
		return M + dir * dist * u
	end

	return function(t: number)
		local h = Kit.hue(ctx, t, 0)
		local flying = t >= CHARGE and t < tHit
		local tb = t - tHit
		local flick = 0.75 + 0.25 * Kit.slotRng(seed, t, 1 / 30):NextNumber()

		-- charge -------------------------------------------------------------------------------------------------
		if t < CHARGE then
			local u = t / CHARGE
			for i, pl in gather do
				local gu = Kit.ramp(t, (i - 1) * 0.04, CHARGE - 0.02 + (i - 1) * 0.01)
				pl.beam.Color = fire(Kit.hue(ctx, t, i * 0.25), 4)
				pl.set(M + dir * (i - 1) * 0.6 * S, dir, (26 - 23 * Kit.easeIn(gu)) * S, if gu <= 0 or gu >= 1 then 1 else 0.9 - 0.8 * gu, t * 9 + i)
			end
			chargeGlow.beam.Color = ColorSequence.new(Kit.hot(h))
			chargeGlow.set(M, (4 + 16 * Kit.easeIn(u)) * S * flick, 0.25)
			chargeStar.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
			chargeStar.set(M, (6 + 30 * Kit.easeIn(u)) * S, 0.05, t * 14, 1)
			local want = math.floor(t / 0.012)
			while nIn < want do
				nIn += 1
				local dv = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
				local d = if dv.Magnitude > 0.01 then dv.Unit else UP
				inward.Color = ColorSequence.new(Kit.col(Kit.hue(ctx, t, rng:NextNumber()), 0.8, 1), Kit.hot(h))
				ctx.host.CFrame = Kit.upTo(M + d * 11 * S, -d)
				inward:Emit(1)
			end
		else
			for _, pl in gather do
				pl.hide()
			end
			chargeGlow.hide()
			chargeStar.hide()
		end

		-- launch -------------------------------------------------------------------------------------------------
		if once("launch", t, CHARGE) then
			if gm then
				muzzleKick.fire(CHARGE, gm.Position + UP * 0.08, fire(h, 4))
				Kit.spray(ctx, smoke, gm.Position + UP * S, 12, SMOKE, "disc", 2, 0.15)
			end
			Kit.spray(ctx, glints, M, 16, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.1 * span)), "sphere", 1)
			Kit.spray(ctx, embers, M, 20, fire(h, 3), "point", 0, 0, -dir)
		end
		muzzleKick.update(t)
		local mf = if t >= CHARGE then 1 - Kit.ramp(t, CHARGE, CHARGE + 0.14) else 0
		muzzleStar.beam.Color = ColorSequence.new(Kit.hot(h))
		muzzleStar.set(M, 56 * S * mf, if mf > 0 then 0 else 1, 0.5, 1)
		for i, pl in muzzleRings do
			pl.beam.Color = fire(h + i * 0.2 * span, 4)
			Kit.pulse(pl, M - dir * (i - 1) * 2 * S, dir, Kit.ramp(t, CHARGE + (i - 1) * 0.04, CHARGE + 0.28 + (i - 1) * 0.06), 6 * S, (30 + 12 * i) * S, 0.05, i)
		end

		-- the ball -----------------------------------------------------------------------------------------------
		local H = headAt(t)
		if flying then
			local tf = t - CHARGE
			local pop = 1 + 0.5 * math.exp(-tf * 16) -- leaves the hand swollen
			local wob = 1 + 0.08 * math.sin(t * 61)
			core.Size = Vector3.one * RB * 1.25 * pop * wob
			core.CFrame = CFrame.new(H)
			core.Color = Kit.hot(h)
			core.Transparency = 0
			shellP.Size = Vector3.one * RB * 2 * pop * (2 - wob)
			shellP.CFrame = CFrame.new(H)
			shellP.Color = Kit.col(h, 0.9, 1)
			shellP.Transparency = 0.45 + 0.15 * (1 - flick)
			halo.beam.Color = ColorSequence.new(ink(h))
			halo.set(H - dir * 1.5 * S, RB * 5.6 * pop, 0.3)
			glow.beam.Color = ColorSequence.new(Kit.col(h + 0.06 * span, 0.55, 1))
			glow.set(H, RB * 4.6 * pop * flick, 0.15)
			star.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
			star.set(H, RB * 7.5 * (0.8 + 0.2 * flick), 0.05, t * 9, 1)
			star2.beam.Color = ColorSequence.new(Kit.hot(h + 0.3 * span))
			star2.set(H, RB * 5, 0.2, -t * 13 + 0.8, 1)

			local L = math.min((H - M).Magnitude, 34 * S)
			if L > 0.5 then
				local sway = side * math.cos(t * 23) + lift * math.sin(t * 23)
				tA0.CFrame = Kit.rightTo(H, sway)
				tA1.CFrame = Kit.rightTo(H - dir * L, sway)
				local bend = 2.2 * S * math.sin(t * 37)
				for _, b in { tailInk, tail, tailHot } do
					b.CurveSize0, b.CurveSize1 = bend, -bend * 1.6
					b.Enabled = true
				end
				tailInk.Width0 = RB * 3.5
				tailInk.Color = ColorSequence.new(ink(h))
				tailInk.Transparency = Kit.numSeq({ { 0, 0.15 }, { 0.6, 0.45 }, { 1, 1 } })
				tail.Width0 = RB * 2.5 * (2 - wob)
				tail.Color = fire(h, 6)
				tail.Transparency = Kit.numSeq({ { 0, 0 }, { 0.6, 0.25 }, { 1, 1 } })
				tailHot.Width0 = RB * 1.15
				tailHot.Color = ColorSequence.new(Kit.hot(h))
				tailHot.Transparency = Kit.numSeq({ { 0, 0 }, { 0.5, 0.2 }, { 1, 1 } })
				for i, r in ribbons do
					local a = t * 26 + i * math.pi
					local rv = side * math.cos(a) + lift * math.sin(a)
					local Lr = L * 0.75
					r.a0.CFrame = Kit.rightTo(H + rv * RB * 0.7, rv)
					r.a1.CFrame = Kit.rightTo(H - dir * Lr - rv * RB * 0.5, rv)
					local k = RB * 2.4
					r.body.CurveSize0, r.body.CurveSize1, r.core.CurveSize0, r.core.CurveSize1 = k, k, k, k
					r.body.Width0 = RB * 1.1
					r.body.Color = fire(Kit.hue(ctx, t, 0.3 + i * 0.25), 5)
					r.body.Transparency = Kit.numSeq({ { 0, 0.05 }, { 0.7, 0.3 }, { 1, 1 } })
					r.core.Width0 = RB * 0.35
					r.core.Color = ColorSequence.new(Color3.new(1, 1, 1))
					r.core.Transparency = Kit.numSeq({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } })
					r.body.Enabled, r.core.Enabled = true, true
				end
			end
			-- what it leaves behind
			local want = math.floor(tf / 0.011)
			while nTrail < want do
				nTrail += 1
				local P = headAt(CHARGE + nTrail * 0.011) - dir * RB * 0.6
				flames.Color = fire(Kit.hue(ctx, t, rng:NextNumber() * 0.4), 4)
				ctx.host.CFrame = Kit.upTo(P + (side * rng:NextNumber(-1, 1) + lift * rng:NextNumber(-1, 1)) * RB * 0.5, -dir)
				flames:Emit(1)
				if nTrail % 2 == 0 then
					smoke.Color = SMOKE
					ctx.host.CFrame = Kit.upTo(P - dir * RB, -dir + lift * 0.4)
					smoke:Emit(1)
				end
				embers.Color = ColorSequence.new(Kit.hot(h), Kit.col(Kit.hue(ctx, t, rng:NextNumber() * 0.5), 0.9, 1))
				ctx.host.CFrame = Kit.upTo(P, -dir)
				embers:Emit(1)
			end
		else
			core.CFrame, shellP.CFrame = Kit.HIDE, Kit.HIDE
			halo.hide()
			glow.hide()
			star.hide()
			star2.hide()
			tailInk.Enabled, tail.Enabled, tailHot.Enabled = false, false, false
			for _, r in ribbons do
				r.body.Enabled, r.core.Enabled = false, false
			end
		end
		-- sonic rings shed along the path
		for i, pl in sonic do
			local at = CHARGE + flightT * (i - 0.5) / #sonic
			pl.beam.Color = fire(Kit.hue(ctx, at, i * 0.2), 4)
			Kit.pulse(pl, headAt(at), dir, Kit.ramp(t, at, at + 0.26), 5 * S, 30 * S, 0.1, i * 1.3)
		end

		-- impact -------------------------------------------------------------------------------------------------
		local G = if ge then ge.Position + UP * 0.08 else nil
		if once("boom", t, tHit) then
			local out = E + N * 1.5 * S
			Kit.spray(ctx, sparks, out, 90, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.08 * span, 0.9, 1)), "point", 0, 0, N)
			Kit.spray(ctx, lines, out, 46, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.3 * span, 0.7, 1)), "point", 0, 0, N)
			Kit.spray(ctx, glints, out, 40, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.15 * span)), "sphere", 4)
			Kit.spray(ctx, roll, out, 34, fire(h, 5), "point", 0, 0, N)
			Kit.spray(ctx, boomSmoke, out, 22, SMOKE, "point", 0, 0, N)
			Kit.spray(ctx, embers, out, 40, fire(h, 3), "sphere", 3)
			if G then
				groundShock.fire(tHit, G, fire(h, 6))
				groundInk.fire(tHit, G, ColorSequence.new(ink(h)))
				Kit.spray(ctx, boomSmoke, G + UP * S, 14, SMOKE, "disc", 5, 0.2)
			end
		end
		groundShock.update(t)
		groundInk.update(t)
		if tb >= 0 then
			local u = tb / BURST
			local bf = 1 - Kit.ramp(tb, 0, 0.16)
			flash.beam.Color = ColorSequence.new(Kit.hot(h))
			flash.set(E + N * S, (40 + 80 * bf) * S, 1 - bf)
			boomStar.beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
			boomStar.set(E + N * S, 150 * S * bf, if bf > 0 then 0 else 1, 0.4, 1)
			boomStar2.beam.Color = ColorSequence.new(Kit.hot(h + 0.3 * span))
			boomStar2.set(E + N * S, 100 * S * bf, if bf > 0 then 0.05 else 1, 0.4 + math.pi / 4 + tb * 5, 1)
			local iu = Kit.ramp(tb, 0, 0.5)
			boomInk.beam.Color = ColorSequence.new(ink(h))
			boomInk.set(E + N * S, (30 + 60 * Kit.easeOut(iu)) * S, if iu >= 1 then 1 else 0.25 + 0.75 * iu * iu)
			local ru = Kit.ramp(tb, 0.02, 0.38)
			boomRing.beam.Color = fire(h, 6)
			boomRing.set(E + N * S, (14 + 90 * Kit.easeOut(ru)) * S, if ru <= 0 or ru >= 1 then 1 else 0.05 + 0.95 * ru * ru)
			if u < 1 then
				local g = Kit.easeOut(u)
				dome.Size = Vector3.one * (10 + 38 * g) * S
				dome.CFrame = CFrame.new(E)
				dome.Color = Kit.col(h + 0.05 * span * u, 0.9, 1)
				dome.Transparency = math.clamp(0.25 + 0.75 * u ^ 1.5, 0, 1)
				local g2 = Kit.easeOut(Kit.ramp(tb, 0, BURST * 0.7))
				domeHot.Size = Vector3.one * (8 + 22 * g2) * S
				domeHot.CFrame = CFrame.new(E)
				domeHot.Color = Kit.hot(h)
				domeHot.Transparency = math.clamp(g2 ^ 2, 0, 1)
			else
				dome.CFrame, domeHot.CFrame = Kit.HIDE, Kit.HIDE
			end
			for _, sp in spikes do
				local su = Kit.ramp(tb, 0, 0.3)
				if su >= 1 then
					sp.ink.Enabled, sp.body.Enabled, sp.core.Enabled = false, false, false
					continue
				end
				local headD = sp.len * Kit.easeOut(su)
				local tailD = sp.len * Kit.easeOut(Kit.ramp(tb, 0.08, 0.3)) * 0.9
				sp.a0.CFrame = CFrame.new(E + sp.d * headD)
				sp.a1.CFrame = CFrame.new(E + sp.d * tailD)
				local hs = Kit.hue(ctx, t, sp.tint * (if rainbow then 1 else 0.5))
				sp.ink.Width0 = 6.5 * S
				sp.ink.Color = ColorSequence.new(ink(hs))
				sp.ink.Transparency = Kit.numSeq({ { 0, 0.2 }, { 1, 1 } })
				sp.body.Width0 = 4 * S
				sp.body.Color = ColorSequence.new(Kit.col(hs, 0.9, 1))
				sp.body.Transparency = Kit.numSeq({ { 0, 0 }, { 1, 1 } })
				sp.core.Width0 = 1.5 * S
				sp.core.Color = ColorSequence.new(Color3.new(1, 1, 1))
				sp.core.Transparency = Kit.numSeq({ { 0, 0 }, { 1, 1 } })
				sp.ink.Enabled, sp.body.Enabled, sp.core.Enabled = true, true, true
			end
			for i, pl in shocks do
				pl.beam.Color = fire(Kit.hue(ctx, t, i * 0.2), 5)
				Kit.pulse(pl, E + N * (0.3 + (i - 1) * 2.5) * S, N, Kit.ramp(tb, (i - 1) * 0.05, 0.34 + (i - 1) * 0.08), 8 * S, (56 + 16 * i) * S, 0.02, i * 2)
			end
			shockInk.beam.Color = ColorSequence.new(ink(h))
			Kit.pulse(shockInk, E + N * 0.2 * S, N, Kit.ramp(tb, 0, 0.5), 10 * S, 84 * S, 0.2, 1)

			-- black lightning spitting off the burst
			local slot = math.floor(t / 0.05)
			local crawl = 1 - Kit.ramp(tb, 0.04, 0.4)
			for i, b in bolts do
				local r = Random.new(seed * 131 + i * 977 + slot * 31)
				if crawl > 0 and r:NextNumber() < 0.3 + 0.65 * crawl then
					local a = r:NextNumber(0, math.pi * 2)
					local el = r:NextNumber(0.05, 1.2)
					local d = ((nb * math.cos(a) + nc * math.sin(a)) * math.cos(el) + N * math.sin(el)).Unit
					local p0 = E + d * 4 * S
					local p1 = E + d * r:NextNumber(18, 34) * S
					local sd = seed * 53 + i * 101 + slot
					b.glow.set(p0, p1, 3 * S, 0.14, sd, Kit.col(Kit.hue(ctx, t, i / #bolts * span), 0.9, 1), 0.3)
					b.core.set(p0, p1, 1.1 * S, 0.14, sd, Color3.new(0, 0, 0), 0)
				else
					b.glow.hide()
					b.core.hide()
				end
			end

			-- what is left on the surface
			if struck then
				local fadeOut = Kit.ramp(t, life - 0.3, life)
				local stamp = Kit.easeOut(Kit.ramp(tb, 0, 0.12))
				local base = E + N * 0.12
				scorch.beam.Color = ColorSequence.new(Color3.fromRGB(10, 8, 9))
				scorch.set(base, N, 44 * S * stamp, 0.25 + 0.75 * fadeOut, 0.6)
				scorchCrack.beam.Color = ColorSequence.new(Color3.fromRGB(6, 5, 6))
				scorchCrack.set(base + N * 0.02, N, 40 * S * stamp, 0.05 + 0.95 * fadeOut, 1.9)
				scorchRing.beam.Color = ColorSequence.new(Color3.fromRGB(8, 6, 7))
				scorchRing.set(base + N * 0.04, N, 34 * S * stamp, 0.2 + 0.8 * fadeOut, 0.2)
				local cool = Kit.ramp(tb, 0.05, life - tHit - 0.1)
				emberCrack.beam.Color = fire(h, 5)
				emberCrack.set(base + N * 0.06, N, 40 * S * stamp, math.clamp(0.05 + cool * 0.95 + 0.12 * (1 - flick), 0, 1), 1.9)
				emberRing.beam.Color = fire(h + 0.15 * span, 5)
				emberRing.set(base + N * 0.08, N, 34 * S * stamp, math.clamp(0.15 + cool * 0.85, 0, 1), 0.2)
				if cool < 0.75 then
					local want = math.floor(tb / 0.03)
					while nLick < want do
						nLick += 1
						local a = rng:NextNumber(0, math.pi * 2)
						local rr = rng:NextNumber(3, 15) * S
						licks.Color = fire(Kit.hue(ctx, t, rng:NextNumber() * 0.5), 4)
						ctx.host.CFrame = Kit.upTo(E + (nb * math.cos(a) + nc * math.sin(a)) * rr + N * 0.5 * S, (N + UP).Unit)
						licks:Emit(1)
					end
				end
			end
		else
			flash.hide()
			boomStar.hide()
			boomStar2.hide()
			boomInk.hide()
			boomRing.hide()
			dome.CFrame, domeHot.CFrame = Kit.HIDE, Kit.HIDE
			for _, sp in spikes do
				sp.ink.Enabled, sp.body.Enabled, sp.core.Enabled = false, false, false
			end
			for _, pl in shocks do
				pl.hide()
			end
			shockInk.hide()
			for _, b in bolts do
				b.glow.hide()
				b.core.hide()
			end
			scorch.hide()
			scorchCrack.hide()
			scorchRing.hide()
			emberCrack.hide()
			emberRing.hide()
		end

		if grade then
			local k = if tb >= 0 then math.exp(-tb * 12) else 0
			grade.Brightness = 0.3 * k
			grade.Contrast = 0.3 * k
			grade.Saturation = 0.25 * k
			grade.TintColor = Color3.new(1, 1, 1):Lerp(Kit.col(h, 0.25, 1), k)
		end
		lightPart.CFrame = CFrame.new(if tb >= 0 then E + N * 3 * S else (if t < CHARGE then M else H))
		light.Color = Kit.col(h, 0.5, 1)
		light.Brightness = if tb >= 0 then 14 * math.exp(-tb * 5) + 1.5 * (1 - Kit.ramp(t, life - 0.4, life))
			elseif flying then 6 * flick
			else 5 * (t / CHARGE)
	end
end

-- a tick as it leaves the hand, a wallop when it lands
function Fireball.shake(t: number): Vector3
	local k = 0
	if t >= lastHit then
		k = 1.0 * math.exp(-(t - lastHit) * 8)
	elseif t >= CHARGE then
		k = 0.18 * math.exp(-(t - CHARGE) * 14) + 0.04
	end
	return Vector3.new(math.sin(t * 113) * k, math.cos(t * 137) * k, 0)
end

return Fireball
