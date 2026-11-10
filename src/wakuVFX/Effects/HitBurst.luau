--!strict
--[[ HitBurst: a basic-attack (M1) hit. No wind-up; it is over in 0.3 s so the next hit can land on top of it.
	cf = the contact point, LookVector = the direction the blow travels (attacker -> target).

	0.00-0.05  contact flash: a small white-hot orb and a four-point glint
	0.00-0.16  rainbow spikes shoot out across the blow, heads first, tails catching up
	0.02-0.26  a tight shock ring opens face-on to the blow, a dark ink ring just behind it
	0.00-0.30  sparks spit back off the contact and fall away
	Pass a different opts.seed per hit (the combo index works) and every hit in a string gets its own spike layout. ]]
local Kit = require(script.Parent.Parent.Kit)

local HitBurst = {
	life = 0.3,
	required = { "glow_soft", "spark_glint", "spark_streak", "shock_ring", "bolt_glow" },
}

local SPIKES = 11

function HitBurst.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local P = ctx.cf.Position
	local dir = ctx.cf.LookVector
	local right, up = ctx.cf.RightVector, ctx.cf.UpVector
	local roll = rng:NextNumber(0, math.pi * 2)

	local flash = Kit.sprite(ctx, "Flash", "glow_soft", 4)
	local halo = Kit.sprite(ctx, "FlashHalo", "glow_soft", 2)
	local glint = Kit.sprite(ctx, "Glint", "spark_glint", 5)
	local ring = Kit.plate(ctx, "Ring", "shock_ring", 2)
	ring.beam.Brightness = 2
	local ringInk = Kit.plate(ctx, "RingInk", "shock_ring", 1)
	ringInk.beam.LightEmission = 0

	-- spikes: mostly across the blow, tilted a little back toward the attacker; two long ones give it a direction
	local spikes = {}
	for i = 1, SPIKES do
		local a = roll + (i - 1) / SPIKES * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local d = (right * math.cos(a) + up * math.sin(a) - dir * rng:NextNumber(0, 0.45)).Unit
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local b = Kit.beam(ctx, a0, a1, "bolt_glow", 3)
		b.Name = "Spike"
		b.Segments = 1
		b.Enabled = false
		local long = i % 5 == 1
		spikes[i] = { a0 = a0, a1 = a1, b = b, d = d, len = (if long then rng:NextNumber(6.5, 8) else rng:NextNumber(2.6, 5)) * S,
			w = (if long then 0.75 else rng:NextNumber(0.35, 0.6)) * S, phase = (i - 1) / SPIKES, delay = rng:NextNumber(0, 0.02) }
	end

	local sparkSpec: Kit.BurstSpec = { tex = "spark_streak", life = { 0.12, 0.26 }, size = { { 0, 0.35 }, { 0.2, 1.5 }, { 1, 0.2 } },
		transp = { { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } }, speed = { 26, 58 }, drag = 5, acc = Vector3.new(0, -46 * S, 0), rot = { 90 }, vpar = true, bright = 2.5, spread = 80 }
	local sparks = Kit.burst(ctx, "Sparks", sparkSpec)
	local sparks2 = Kit.burst(ctx, "Sparks2", sparkSpec)
	local bits = Kit.burst(ctx, "Bits", { tex = "spark_glint", life = { 0.1, 0.22 }, size = { { 0, 0 }, { 0.25, 0.9 }, { 1, 0 } },
		speed = { 10, 24 }, drag = 6, rot = { 0, 360 }, rotSpeed = { -200, 200 }, bright = 3 })

	local lightPart = Kit.part(ctx, ctx.root, "Light", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightPart.Transparency = 1
	lightPart.CFrame = CFrame.new(P - dir * 0.5 * S)
	local light = Kit.light(ctx, lightPart, 12 * S)

	local once = Kit.once()

	return function(t: number)
		local h = Kit.hue(ctx, t, 0)

		-- contact flash: full size on the very first frame, gone by 0.06
		local f = 1 - Kit.ramp(t, 0.015, 0.06)
		flash.beam.Color = ColorSequence.new(Kit.hot(h))
		flash.set(P, (1.2 + 2.6 * f) * S, 1 - f)
		halo.beam.Color = ColorSequence.new(Kit.col(h, 0.7, 1))
		halo.set(P, (3 + 4.5 * f) * S, 1 - 0.55 * f)
		local gu = Kit.ramp(t, 0, 0.13)
		glint.beam.Color = ColorSequence.new(Kit.hot(h + 0.1))
		glint.set(P - dir * 0.2 * S, (7.5 - 5 * gu) * S, Kit.easeIn(gu), roll + t * 5, 1)

		-- spikes
		for _, s in spikes do
			local head = Kit.easeOut(Kit.ramp(t, s.delay, s.delay + 0.1))
			local tail = Kit.easeOut(Kit.ramp(t, s.delay + 0.045, s.delay + 0.2))
			if head - tail > 0.01 then
				s.a0.CFrame = CFrame.new(P + s.d * (0.5 * S + s.len * tail))
				s.a1.CFrame = CFrame.new(P + s.d * (0.5 * S + s.len * head))
				s.b.Width0 = s.w * (1 - tail)
				s.b.Width1 = 0
				local hs = Kit.hue(ctx, t, s.phase)
				s.b.Color = ColorSequence.new(Kit.hot(hs), Kit.col(hs, 0.9, 1))
				s.b.Transparency = NumberSequence.new(0.6 * tail)
				s.b.Enabled = true
			else
				s.b.Enabled = false
			end
		end

		-- shock ring, face-on to the blow
		local ru = Kit.ramp(t, 0.02, 0.26)
		local rs = (1.4 + 6.2 * Kit.easeOut(ru)) * S
		ring.beam.Color = Kit.hueSeq(h, if ctx.opts.rainbow then 0.5 else 0.06, 0.55, 1, 4)
		ring.set(P, dir, rs, if t < 0.02 then 1 else 0.05 + 0.95 * Kit.easeIn(ru), roll)
		local iu = Kit.ramp(t, 0.04, 0.3)
		ringInk.beam.Color = ColorSequence.new(Kit.ink(h))
		ringInk.set(P + dir * 0.15 * S, dir, (1.8 + 7 * Kit.easeOut(iu)) * S, if t < 0.04 then 1 else 0.25 + 0.75 * iu, roll + 1)

		if once("sparks", t, 0) then
			sparks.Color = ColorSequence.new(Kit.hot(h), Kit.col(h + 0.08, 0.85, 1))
			Kit.emit(ctx, sparks, Kit.upTo(P, -dir), 8)
			sparks2.Color = ColorSequence.new(Kit.hot(h + 0.45), Kit.col(h + 0.45, 0.85, 1))
			Kit.emit(ctx, sparks2, Kit.upTo(P, -dir), 6)
			Kit.spray(ctx, bits, P, 6, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.3, 0.6, 1)), "sphere", 0.3)
		end

		light.Color = Kit.col(h, 0.4, 1)
		light.Brightness = 6 * (1 - Kit.ramp(t, 0, 0.12))
	end
end

function HitBurst.shake(t: number): Vector3
	local k = 0.16 * math.exp(-t * 28)
	return Vector3.new(math.sin(t * 190) * k, math.cos(t * 230) * k, 0)
end

return HitBurst
