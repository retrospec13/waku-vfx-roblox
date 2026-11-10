--!strict
--[[ ImpactFlash: an impact frame for the big hit.
	cf = the contact point, LookVector = the direction the blow travels. opts.caster (optional) is drawn as a
	silhouette along with any characters within 16 studs of the contact.

	0.000-0.035  frame 1: the scene is thrown to white, fighters are flat black silhouettes, black speed lines
	             and a jagged black star burst from the contact
	0.035-0.070  frame 2: the negative. Black scene, white silhouettes, white lines
	0.070        colour slams back, oversaturated, with a white pop at the contact
	0.070-0.300  a rainbow shock ring face-on to the blow, a ground ring, rainbow streaks and sparks
	0.070-0.450  saturation and contrast settle back to normal
	opts.grade = false keeps the screen untouched (no black and white frames; the burst still plays). ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)

local F1 = 0.035
local FLASH = 0.07

local ImpactFlash = {
	life = 0.45,
	required = { "glow_soft", "spark_glint", "spark_streak", "shock_ring", "bolt_glow" },
}

-- grade values for the two frames (see Kit.grade): the scene is desaturated and pushed past white or black
ImpactFlash.FRAME1 = { brightness = 1, contrast = 1, saturation = -1 }
ImpactFlash.FRAME2 = { brightness = -1, contrast = 1, saturation = -1 }

local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

function ImpactFlash.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local P = ctx.cf.Position
	local dir = ctx.cf.LookVector
	local right, up = ctx.cf.RightVector, ctx.cf.UpVector
	local grade = Kit.grade(ctx)
	local roll = rng:NextNumber(0, math.pi * 2)

	-- silhouettes: the caster and nearby characters
	local marks: { Highlight } = {}
	if grade then
		local seen: { [Model]: boolean } = {}
		local function mark(m: Model)
			if seen[m] or #marks >= 6 then
				return
			end
			seen[m] = true
			local hl = Instance.new("Highlight")
			hl.Name = "Silhouette"
			hl.Adornee = m
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.FillTransparency = 1
			hl.OutlineTransparency = 1
			hl.Parent = ctx.root
			table.insert(marks, hl)
		end
		if ctx.opts.caster then
			mark(ctx.opts.caster)
		end
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		op.FilterDescendantsInstances = { ctx.root }
		local ok, found = pcall(function()
			return Workspace:GetPartBoundsInRadius(P, 16 * S, op)
		end)
		if ok and found then
			for _, part in found :: { BasePart } do
				local m = part:FindFirstAncestorOfClass("Model")
				if m and m:FindFirstChildOfClass("Humanoid") then
					mark(m)
				end
			end
		end
	end

	-- frame art: speed lines converging on the contact, and a jagged star
	local LINES = 26
	local lines = {}
	for i = 1, LINES do
		local a = roll + (i - 1) / LINES * math.pi * 2 + rng:NextNumber(-0.09, 0.09)
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local b = Kit.beam(ctx, a0, a1, "bolt_glow", 6)
		b.Name = "FrameLine"
		b.Segments = 1
		b.LightEmission = 0
		b.Enabled = false
		local r0 = rng:NextNumber(4.5, 11) * S
		lines[i] = { a0 = a0, a1 = a1, b = b, ang = a, r0 = r0, r1 = r0 + rng:NextNumber(9, 26) * S, w = rng:NextNumber(0.35, 1.5) * S }
	end
	local JAGS = 12
	local jags = {}
	for i = 1, JAGS do
		local a = roll + (i - 0.5) / JAGS * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local b = Kit.beam(ctx, a0, a1, nil, 7)
		b.Name = "FrameJag"
		b.Segments = 1
		b.LightEmission = 0
		b.Width1 = 0
		b.Enabled = false
		jags[i] = { a0 = a0, a1 = a1, b = b, ang = a,
			len = (if i % 3 == 0 then rng:NextNumber(5.5, 8) else rng:NextNumber(2.4, 4.5)) * S, w = rng:NextNumber(1.3, 2.2) * S }
	end
	local blot = Kit.part(ctx, ctx.root, "FrameBlot", Vector3.one * 2.6 * S, BLACK, Enum.Material.Neon)
	blot.Shape = Enum.PartType.Ball

	-- colour: streaks, rings, sparks
	local STREAKS = 14
	local streaks = {}
	for i = 1, STREAKS do
		local a = roll + 0.3 + (i - 1) / STREAKS * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local d = (right * math.cos(a) + up * math.sin(a) - dir * rng:NextNumber(0, 0.5)).Unit
		local a0, a1 = Kit.att(ctx), Kit.att(ctx)
		local b = Kit.beam(ctx, a0, a1, "bolt_glow", 3)
		b.Name = "Streak"
		b.Segments = 1
		b.Width1 = 0
		b.Enabled = false
		streaks[i] = { a0 = a0, a1 = a1, b = b, d = d, len = (if i % 4 == 0 then rng:NextNumber(12, 16) else rng:NextNumber(5, 10)) * S,
			w = rng:NextNumber(0.5, 1.1) * S, phase = (i - 1) / STREAKS }
	end
	local ring = Kit.plate(ctx, "Ring", "shock_ring", 2)
	ring.beam.Brightness = 2
	local ring2 = Kit.plate(ctx, "Ring2", "shock_ring", 2)
	local ringInk = Kit.plate(ctx, "RingInk", "shock_ring", 1)
	ringInk.beam.LightEmission = 0
	local popGlow = Kit.sprite(ctx, "Pop", "glow_soft", 4)
	local popHalo = Kit.sprite(ctx, "PopHalo", "glow_soft", 2)
	local popStar = Kit.sprite(ctx, "PopStar", "spark_glint", 5)
	local sparkSpec: Kit.BurstSpec = { tex = "spark_streak", life = { 0.16, 0.34 }, size = { { 0, 0.5 }, { 0.2, 2.2 }, { 1, 0.3 } },
		transp = { { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } }, speed = { 34, 78 }, drag = 4.5, acc = Vector3.new(0, -40 * S, 0), rot = { 90 }, vpar = true, bright = 2.5, spread = 100 }
	local sparks = Kit.burst(ctx, "Sparks", sparkSpec)
	local sparks2 = Kit.burst(ctx, "Sparks2", sparkSpec)
	local bits = Kit.burst(ctx, "Bits", { tex = "spark_glint", life = { 0.18, 0.36 }, size = { { 0, 0 }, { 0.2, 1.3 }, { 1, 0 } },
		speed = { 12, 34 }, drag = 5, rot = { 0, 360 }, rotSpeed = { -200, 200 }, bright = 3 })

	local lightPart = Kit.part(ctx, ctx.root, "Light", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightPart.Transparency = 1
	lightPart.CFrame = CFrame.new(P - dir * S)
	local light = Kit.light(ctx, lightPart, 22 * S)

	local once = Kit.once()

	return function(t: number)
		local h = Kit.hue(ctx, t, 0)
		local inFlash = grade ~= nil and t < FLASH
		local frame1 = t < F1

		-- the screen ----------------------------------------------------------------------------------------
		if grade then
			if inFlash then
				local f = if frame1 then ImpactFlash.FRAME1 else ImpactFlash.FRAME2
				grade.Brightness, grade.Contrast, grade.Saturation = f.brightness, f.contrast, f.saturation
				grade.TintColor = WHITE
			else
				local back = Kit.ramp(t, FLASH, ImpactFlash.life - 0.05)
				local snap = 1 - Kit.ramp(t, FLASH, FLASH + 0.07)
				grade.Brightness = 0.22 * snap
				grade.Contrast = 0.35 * (1 - Kit.easeOut(back))
				grade.Saturation = 0.75 * (1 - Kit.easeOut(back))
				grade.TintColor = WHITE
			end
		end
		local art = if frame1 then BLACK else WHITE -- the frame's drawing colour
		-- the frame art is drawn on the screen, not in the world: it radiates in the camera's plane whatever the angle
		local cam = Workspace.CurrentCamera
		local sx = if cam then cam.CFrame.RightVector else right
		local sy = if cam then cam.CFrame.UpVector else up
		for _, hl in marks do
			hl.FillColor = BLACK -- figures stay black in both frames: on white, then inside the white star
			hl.OutlineColor = art
			hl.FillTransparency = if inFlash then 0 else 1
			hl.OutlineTransparency = if inFlash then 0 else 1
		end
		for i, ln in lines do
			ln.b.Enabled = inFlash
			if inFlash then
				-- frame 2 redraws the lines a little further out, so the two frames do not match
				local push = if frame1 then 0 else 2.2 * S
				local skip = (not frame1) and i % 3 == 0
				local d = sx * math.cos(ln.ang) + sy * math.sin(ln.ang)
				ln.a0.CFrame = CFrame.new(P + d * (ln.r0 + push))
				ln.a1.CFrame = CFrame.new(P + d * (ln.r1 + push * 2))
				ln.b.Width0, ln.b.Width1 = 0, if skip then 0 else ln.w
				ln.b.Color = ColorSequence.new(art)
				ln.b.LightEmission = if frame1 then 0 else 1
				ln.b.Transparency = NumberSequence.new(0)
			end
		end
		for _, j in jags do
			j.b.Enabled = inFlash
			if inFlash then
				local k = if frame1 then 1 else 1.35
				j.a0.CFrame = CFrame.new(P)
				j.a1.CFrame = CFrame.new(P + (sx * math.cos(j.ang) + sy * math.sin(j.ang)) * j.len * k)
				j.b.Width0 = j.w * k
				j.b.Color = ColorSequence.new(art)
				j.b.LightEmission = if frame1 then 0 else 1
				j.b.Transparency = NumberSequence.new(0)
			end
		end
		blot.CFrame = if inFlash then CFrame.new(P) else Kit.HIDE
		blot.Color = art

		-- colour slams back -----------------------------------------------------------------------------------
		local T = if grade then FLASH else 0
		local pu = Kit.ramp(t, T, T + 0.1)
		local showPop = t >= T and pu < 1
		popGlow.beam.Color = ColorSequence.new(Kit.hot(h))
		popGlow.set(P, (9 - 6 * pu) * S, if showPop then pu else 1)
		popHalo.beam.Color = ColorSequence.new(Kit.col(h, 0.8, 1))
		popHalo.set(P, (18 - 8 * pu) * S, if showPop then 0.45 + 0.55 * pu else 1)
		local su = Kit.ramp(t, T, T + 0.2)
		popStar.beam.Color = ColorSequence.new(Kit.hot(h + 0.1))
		popStar.set(P - dir * 0.3 * S, (22 - 14 * su) * S, if t >= T then Kit.easeIn(su) else 1, roll + t * 3, 1)
		for _, s in streaks do
			local head = Kit.easeOut(Kit.ramp(t, T, T + 0.12))
			local tail = Kit.easeOut(Kit.ramp(t, T + 0.06, T + 0.3))
			local vis = t >= T and head - tail > 0.01
			s.b.Enabled = vis
			if vis then
				s.a0.CFrame = CFrame.new(P + s.d * (1.2 * S + s.len * tail))
				s.a1.CFrame = CFrame.new(P + s.d * (1.2 * S + s.len * head))
				s.b.Width0 = s.w * (1 - tail)
				local hs = Kit.hue(ctx, t, s.phase)
				s.b.Color = ColorSequence.new(Kit.hot(hs), Kit.col(hs, 0.9, 1))
				s.b.Transparency = NumberSequence.new(0.5 * tail)
			end
		end
		local span = if ctx.opts.rainbow then 0.7 else 0.07
		local ru = Kit.ramp(t, T, T + 0.26)
		ring.beam.Color = Kit.hueSeq(h, span, 0.6, 1, 5)
		ring.set(P, dir, (3 + 17 * Kit.easeOut(ru)) * S, if t < T or ru >= 1 then 1 else 0.05 + 0.95 * Kit.easeIn(ru), roll)
		local r2 = Kit.ramp(t, T + 0.05, T + 0.34)
		ring2.beam.Color = Kit.hueSeq(h + 0.3, span, 0.8, 1, 5)
		ring2.set(P - dir * 0.8 * S, dir, (2 + 11 * Kit.easeOut(r2)) * S, if r2 <= 0 or r2 >= 1 then 1 else 0.2 + 0.8 * r2, roll + 2)
		local iu = Kit.ramp(t, T + 0.02, T + 0.36)
		ringInk.beam.Color = ColorSequence.new(Kit.ink(h))
		ringInk.set(P + dir * 0.3 * S, dir, (4 + 20 * Kit.easeOut(iu)) * S, if iu <= 0 or iu >= 1 then 1 else 0.2 + 0.8 * iu, roll + 1)

		if once("sparks", t, T) then
			-- one Emit per emitter: particles emitted in the same frame all take the host's final CFrame
			sparks.Color = ColorSequence.new(Kit.hot(h), Kit.col(h, 0.85, 1))
			Kit.emit(ctx, sparks, Kit.upTo(P, -dir), 12)
			sparks2.Color = ColorSequence.new(Kit.hot(h + 0.4), Kit.col(h + 0.4, 0.85, 1))
			Kit.emit(ctx, sparks2, Kit.upTo(P, -dir), 10)
			Kit.spray(ctx, bits, P, 10, ColorSequence.new(Kit.hot(h), Kit.col(h + 0.3, 0.6, 1)), "sphere", 0.6)
		end

		light.Color = Kit.col(h, 0.4, 1)
		light.Brightness = if t < T then 0 else 8 * (1 - Kit.ramp(t, T, T + 0.2))
	end
end

-- nothing moves during the two frames; the kick lands when colour returns
function ImpactFlash.shake(t: number): Vector3
	if t < FLASH then
		return Vector3.zero
	end
	local k = 0.55 * math.exp(-(t - FLASH) * 13)
	return Vector3.new(math.sin(t * 120) * k, math.cos(t * 141) * k, 0)
end

return ImpactFlash
