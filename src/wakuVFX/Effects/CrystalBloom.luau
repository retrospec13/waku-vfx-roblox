--!strict
--[[ CrystalBloom: an icy swirl gathers crystals into a star bloom on a frost dome, which whites out and shatters.
	0.00-1.00  MIST SWIRL: three pale rainbow mist rings spin round the target and tighten, mist streams off them;
	           ten small double-pointed crystal shards ride the spiral inward and vanish into the centre
	0.85-1.75  BLOOM: 12 long crystal blades and 6 short ones fan up and out of a glowing core like a star or
	           crown, each a different rainbow hue round the wheel, with one white outline. A frost ring rushes
	           out, frost cracks spread, and a white frost dome swells underneath.
	1.75       WHITE-OUT: the dome flares, the scene grade pops to white
	1.85       SHATTER: blades and dome burst into tumbling shards and a radial storm of rainbow ice streaks,
	           then glitter and a lingering frost patch
	cf = the target point on the ground. opts.grade = false skips the scene grade. Life 2.6 s. ]]
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.Parent.Kit)

local CrystalBloom = {}
CrystalBloom.life = 2.6
CrystalBloom.required = { "slash_body", "smoke_puff", "frost_ring", "frost_crack", "glow_soft", "ice_shard", "spark_glint", "spark_streak" }

local NSEG = 12
local T_BLOOM, T_WHITE, T_SHATTER = 0.85, 1.75, 1.85

type PartOff = { p: BasePart, off: CFrame }
type Blade = { parts: { PartOff }, dir: CFrame, L: number, w: number, t0: number, hue: number,
	shards: { { p: BasePart, p0: Vector3, v: Vector3, w: Vector3, size: Vector3 } } }

function CrystalBloom.build(ctx: Kit.Ctx): (number) -> ()
	local S = ctx.opts.scale
	local rng = ctx.rng
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { ctx.root }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(ctx.cf.Position + Vector3.new(0, 6, 0), Vector3.new(0, -16, 0), params)
	local gy = if hit then hit.Position.Y else ctx.cf.Position.Y
	local c = Vector3.new(ctx.cf.X, gy, ctx.cf.Z)
	local P = c + Vector3.yAxis * 3.2 * S -- bloom centre
	local once = Kit.once()
	local grade = Kit.grade(ctx)

	local crystals = Instance.new("Model")
	crystals.Name = "Crystals"
	crystals.Parent = ctx.root
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(240, 250, 255)
	hl.OutlineTransparency = 0.25
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = crystals
	hl.Parent = crystals

	-- a double-pointed crystal along +Y from its base (0) to its far tip (L): glass body, gabled tips, Neon core
	local function crystal(parent: Instance, L: number, w: number): { PartOff }
		local parts: { PartOff } = {}
		local tipH = math.min(L * 0.28, w * 1.8)
		local bodyH = L - tipH * 1.5
		local body = Kit.part(ctx, parent, "Body", Vector3.new(w, bodyH, w), Color3.new(1, 1, 1), Enum.Material.Glass)
		body.Transparency = 0.15
		body.Reflectance = 0.2
		table.insert(parts, { p = body :: BasePart, off = CFrame.new(0, tipH * 0.5 + bodyH / 2, 0) })
		for _, e in { { tipH * 0.5 + bodyH, tipH, 0 }, { tipH * 0.5, tipH * 0.5, math.pi } } do
			local y, h, flipX = e[1], e[2], e[3]
			for _, rot in { 0, math.pi / 2 } do
				for _, flip in { 0, math.pi } do
					local wd = Kit.wedge(parent, "Tip", Vector3.new(w, h, w / 2), Color3.new(1, 1, 1), Enum.Material.Glass)
					wd.Transparency = 0.15
					wd.Reflectance = 0.2
					local off = CFrame.new(0, y, 0) * CFrame.Angles(flipX, 0, 0) * CFrame.new(0, h / 2, 0)
						* CFrame.Angles(0, rot + flip, 0) * CFrame.new(0, 0, -w / 4)
					table.insert(parts, { p = wd, off = off })
				end
			end
		end
		local core = Kit.part(ctx, parent, "Core", Vector3.new(w * 0.3, bodyH * 0.9, w * 0.3), Color3.new(1, 1, 1), Enum.Material.Neon)
		core.Transparency = 0.25
		table.insert(parts, { p = core :: BasePart, off = CFrame.new(0, tipH * 0.5 + bodyH / 2, 0) })
		return parts
	end

	-- bloom blades: a star/crown fanning up and out
	local blades: { Blade } = {}
	local function addBlade(az: number, el: number, L: number, w: number, t0: number, hue: number)
		local d = Vector3.new(math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el))
		local dir = CFrame.lookAt(P, P + d) * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		local m = Instance.new("Model")
		m.Name = "Blade"
		m.Parent = crystals
		local shards = {}
		for k = 1, 3 do
			local sz = Vector3.new(w * rng:NextNumber(0.5, 0.8), L * rng:NextNumber(0.2, 0.32), w * rng:NextNumber(0.35, 0.55))
			local sp = Kit.wedge(ctx.root, "Shard", sz, Color3.new(1, 1, 1), Enum.Material.Glass)
			sp.Transparency = 0.2
			local p0 = P + d * L * (k - 0.5) / 3
			table.insert(shards, { p = sp, p0 = p0, size = sz,
				v = (d * rng:NextNumber(14, 26) + Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(2, 9), rng:NextNumber(-4, 4))) * S,
				w = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10)) })
		end
		table.insert(blades, { parts = crystal(m, L, w), dir = dir, L = L, w = w, t0 = t0, hue = hue, shards = shards })
	end
	for k = 1, 12 do
		local az = k / 12 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		addBlade(az, math.rad(rng:NextNumber(12, 58)), rng:NextNumber(6, 9) * S, rng:NextNumber(0.95, 1.3) * S,
			T_BLOOM + (k % 4) * 0.03 + k * 0.006, k / 12)
	end
	for k = 1, 6 do
		local az = (k + 0.5) / 6 * math.pi * 2
		addBlade(az, math.rad(rng:NextNumber(65, 85)), rng:NextNumber(3.5, 5) * S, 0.8 * S, T_BLOOM + 0.1 + k * 0.012, k / 6 + 0.04)
	end

	-- swirl riders
	type Rider = { parts: { PartOff }, a0: number, h: number, spin: Vector3, hue: number }
	local riders: { Rider } = {}
	for k = 1, 10 do
		local m = Instance.new("Model")
		m.Name = "Rider"
		m.Parent = crystals
		table.insert(riders, { parts = crystal(m, 1.8 * S, 0.5 * S), a0 = k / 10 * math.pi * 2, h = rng:NextNumber(0.6, 3.4) * S,
			spin = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8)), hue = k / 10 })
	end

	-- mist rings (flat arcs in the horizontal plane)
	type Arc = { atts: { Attachment }, beams: { Beam } }
	local mistRings: { Arc } = {}
	for i = 1, 3 do
		local atts, beams = {}, {}
		for k = 0, NSEG do
			atts[k + 1] = Kit.att(ctx)
		end
		for k = 1, NSEG do
			local b = Kit.beam(ctx, atts[k], atts[k + 1], "slash_body", 0)
			b.Name = "Mist" .. i
			b.FaceCamera = false
			b.Segments = 8
			b.LightEmission = 0.4
			b.Brightness = 1.3
			beams[k] = b
		end
		table.insert(mistRings, { atts = atts, beams = beams })
	end

	-- core, dome
	local core = Kit.part(ctx, ctx.root, "BloomCore", Vector3.one, Color3.new(1, 1, 1), Enum.Material.Neon)
	core.Shape = Enum.PartType.Ball
	local dome = Kit.part(ctx, ctx.root, "Dome", Vector3.one, Color3.new(1, 1, 1), Enum.Material.Glass)
	dome.Shape = Enum.PartType.Ball
	dome.Reflectance = 0.25
	local domeGlow = Kit.part(ctx, ctx.root, "DomeGlow", Vector3.one, Color3.new(1, 1, 1), Enum.Material.Neon)
	domeGlow.Shape = Enum.PartType.Ball

	local mist = Kit.burst(ctx, "Mist", { tex = "smoke_puff", life = { 0.6, 1.0 }, size = { { 0, 2 }, { 1, 5 } },
		transp = { { 0, 1 }, { 0.2, 0.6 }, { 0.7, 0.75 }, { 1, 1 } }, speed = { 6, 11 }, spread = 15, drag = 2, rot = { 0, 360 },
		rotSpeed = { -60, 60 }, le = 0.3, bright = 1.2 })
	local frostRing = Kit.flat(ctx, "FrostRing", { tex = "frost_ring", life = 0.55, size = { { 0, 2 }, { 0.12, 12 }, { 0.3, 18 }, { 0.6, 21 }, { 1, 22 } },
		transp = { { 0, 0 }, { 0.45, 0.2 }, { 1, 1 } }, rot = 30, spin = 25, bright = 2, z = 1 })
	local crackDark = Kit.flat(ctx, "FrostDark", { tex = "frost_crack", life = 1.6, size = { { 0, 3 }, { 0.15, 14 }, { 1, 15 } },
		transp = { { 0, 0.1 }, { 0.8, 0.2 }, { 1, 1 } }, rot = 15, le = 0, z = -1 })
	local crackHot = Kit.flat(ctx, "FrostHot", { tex = "frost_crack", life = 1.1, size = { { 0, 3 }, { 0.2, 14 }, { 1, 15 } },
		transp = { { 0, 0 }, { 0.4, 0.25 }, { 1, 1 } }, rot = 15, bright = 2.4 })
	local whiteout = Kit.burst(ctx, "WhiteOut", { tex = "glow_soft", life = { 0.16 }, size = { { 0, 16 }, { 0.3, 36 }, { 1, 40 } },
		transp = { { 0, 0 }, { 0.5, 0.35 }, { 1, 1 } }, bright = 3, zoff = 6 })
	local storm = Kit.burst(ctx, "ShardStorm", { tex = "ice_shard", life = { 0.35, 0.65 }, size = { { 0, 1.1 }, { 1, 0.25 } },
		speed = { 40, 70 }, spread = 0, drag = 2, vpar = true, le = 0.6, bright = 1.6 })
	local streaks = Kit.burst(ctx, "Streaks", { tex = "spark_streak", life = { 0.25, 0.5 }, size = { { 0, 1.0 }, { 1, 0 } },
		speed = { 50, 90 }, drag = 3, vpar = true, bright = 5 })
	local glitter = Kit.burst(ctx, "Glitter", { tex = "spark_glint", life = { 0.2, 0.32 }, size = { { 0, 0 }, { 0.2, 2.4 }, { 1, 0 } },
		speed = { 0.5, 2 }, spread = 180, bright = 6, zoff = 2 })
	local lightHost = Kit.part(ctx, ctx.root, "LightHost", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	lightHost.Transparency = 1
	lightHost.CFrame = CFrame.new(P + Vector3.yAxis * 2 * S)
	local light = Kit.light(ctx, lightHost, 26 * S)

	local function place(parts: { PartOff }, cf: CFrame?, color: Color3)
		for _, e in parts do
			if cf then
				e.p.CFrame = cf * e.off
				e.p.Color = if e.p.Name == "Core" then Color3.new(1, 1, 1):Lerp(color, 0.25) else color
			else
				e.p.CFrame = Kit.HIDE
			end
		end
	end

	return function(t: number)
		local h0 = Kit.hue(ctx, t, 0)
		-- grade: cool tint while it builds, white pop at the white-out
		if grade then
			local cool = Kit.ramp(t, 0.1, 0.6) * (1 - Kit.ramp(t, 2.0, 2.5))
			local pop = math.max(0, 1 - math.abs(t - T_WHITE - 0.05) / 0.12)
			grade.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(200, 225, 255), cool)
			grade.Brightness = -0.08 * cool + 0.6 * pop
			grade.Saturation = 0.1 * cool - 0.4 * pop
		end
		-- mist rings
		for i, a in ipairs(mistRings) do
			local on = Kit.ramp(t, 0.0 + i * 0.05, 0.2 + i * 0.05) * (1 - Kit.ramp(t, 0.8, 1.15))
			if on <= 0 then
				for _, b in a.beams do
					b.Enabled = false
				end
				continue
			end
			local R = (9 - 4.5 * Kit.easeIn(Kit.ramp(t, 0, 1.0)) - i * 0.6) * S
			local y = (0.3 + (i - 1) * 1.0) * S
			local th0 = t * (5 + i) * (if i == 2 then -1 else 1)
			local span = math.rad(250) * (if i == 2 then -1 else 1)
			local dir = if span >= 0 then 1 else -1
			local thick = (1.6 + 0.4 * i) * S
			for k = 0, NSEG do
				local f = k / NSEG
				local w = thick * (0.05 + 0.95 * math.sin(math.pi * f) ^ 0.8)
				local th = th0 + span * f
				local radial = Vector3.new(math.cos(th), 0, math.sin(th))
				local tang = Vector3.new(-math.sin(th), 0, math.cos(th)) * dir
				a.atts[k + 1].CFrame = CFrame.fromMatrix(c + Vector3.yAxis * y + radial * (R - w / 2), tang, radial)
				if k > 0 then
					a.beams[k].Width1 = w
				end
				if k < NSEG then
					a.beams[k + 1].Width0 = w
				end
			end
			local kc = 4 / 3 * math.tan(math.abs(span) / NSEG / 4) * R
			for k, b in a.beams do
				local fa = (k - 1) / NSEG
				b.Enabled = true
				b.CurveSize0, b.CurveSize1 = kc, kc
				b.Color = Kit.hueSeq(h0 + i * 0.3 + fa * 0.5, 0.5 / NSEG, 0.4, 1, 2)
				b.Transparency = NumberSequence.new(1 - on * 0.75 * Kit.smooth(fa * 3))
			end
		end
		for sl = 0, 8 do
			if once("mist" .. sl, t, 0.05 + sl * 0.1) then
				for k = 1, 3 do
					local th = t * 6 + k * 2.1
					local R = (8 - 4 * Kit.ramp(t, 0, 1)) * S
					local p = c + Vector3.new(math.cos(th) * R, 0.8 * S, math.sin(th) * R)
					local tang = Vector3.new(-math.sin(th), 0.05, math.cos(th))
					Kit.spray(ctx, mist, p, 1, ColorSequence.new(Kit.col(h0 + k * 0.33, 0.25, 1)), "point", 0, 0, tang)
				end
			end
		end
		-- riders spiral inward and vanish into the centre
		for _, r in riders do
			local k = Kit.ramp(t, 0.15, T_BLOOM)
			if t >= 0.15 and t < T_BLOOM then
				local R = (9.5 * (1 - Kit.easeIn(k)) + 0.4) * S
				local th = r.a0 + t * 7
				local p = c + Vector3.new(math.cos(th) * R, r.h + (P.Y - c.Y - r.h) * Kit.easeIn(k), math.sin(th) * R)
				local cf = CFrame.new(p) * CFrame.Angles(r.spin.X * t, r.spin.Y * t, r.spin.Z * t) * CFrame.new(0, -0.9 * S, 0)
				place(r.parts, cf, Kit.col(h0 + r.hue, 0.6, 1))
			else
				place(r.parts, nil, Color3.new())
			end
		end
		-- glowing core
		if t >= 0.5 and t < T_SHATTER then
			local g = Kit.ramp(t, 0.5, T_BLOOM)
			core.Size = Vector3.one * (0.5 + 2.2 * g + 0.4 * math.sin(t * 30) * g) * S
			core.CFrame = CFrame.new(P)
			core.Transparency = 0.15
			core.Color = Kit.hot(h0)
		else
			core.CFrame = Kit.HIDE
		end
		-- blades slide out of the core (ease-out-back), hold, shatter
		for _, b in blades do
			local g = Kit.easeOutBack((t - b.t0) / 0.16)
			if t >= b.t0 and t < T_SHATTER then
				local col = Kit.col(h0 + b.hue, 0.6, 1)
				place(b.parts, b.dir * CFrame.new(0, -b.L * (1 - g), 0), col)
			else
				place(b.parts, nil, Color3.new())
			end
			for _, sh in b.shards do
				local ts = t - T_SHATTER
				if ts < 0 then
					sh.p.CFrame = Kit.HIDE
				else
					local pos = sh.p0 + sh.v * ts + Vector3.new(0, -50, 0) * ts * ts * 0.5
					if pos.Y < gy + 0.2 then
						pos = Vector3.new(pos.X, gy + 0.2, pos.Z)
					end
					sh.p.Size = sh.size * (1 - 0.7 * Kit.ramp(ts, 0.25, 0.65))
					sh.p.CFrame = CFrame.new(pos) * CFrame.Angles(sh.w.X * ts, sh.w.Y * ts, sh.w.Z * ts)
					sh.p.Color = Kit.col(h0 + b.hue, 0.55, 1)
					sh.p.Transparency = 0.2 + 0.8 * Kit.ramp(ts, 0.35, 0.7)
				end
			end
		end
		-- frost dome swells under the bloom and flares at the white-out
		if t >= T_BLOOM and t < T_SHATTER then
			local g = Kit.easeOut(Kit.ramp(t, T_BLOOM, T_WHITE))
			local flare = Kit.ramp(t, T_WHITE - 0.1, T_SHATTER)
			local D = (2.5 + 6.5 * g + 3.5 * flare) * S
			dome.Size = Vector3.one * D
			dome.CFrame = CFrame.new(c)
			dome.Transparency = 0.82 - 0.4 * flare
			dome.Color = Color3.new(1, 1, 1):Lerp(Kit.col(h0 + 0.55, 0.35, 1), 0.5)
			domeGlow.Size = Vector3.one * D * 0.8
			domeGlow.CFrame = CFrame.new(c)
			domeGlow.Transparency = 0.9 - 0.55 * flare
			domeGlow.Color = Kit.hot(h0 + 0.55)
		else
			dome.CFrame = Kit.HIDE
			domeGlow.CFrame = Kit.HIDE
		end
		if once("frost", t, T_BLOOM) then
			frostRing.fire(T_BLOOM, c + Vector3.yAxis * 0.14, ColorSequence.new(Kit.col(h0 + 0.5, 0.35, 1)))
			Kit.spray(ctx, glitter, P, 6, ColorSequence.new(Kit.hot(h0)), "sphere", 4)
		end
		if once("cracks", t, T_BLOOM + 0.05) then
			crackDark.fire(T_BLOOM + 0.05, c + Vector3.yAxis * 0.06, ColorSequence.new(Kit.ink(h0 + 0.5)))
			crackHot.fire(T_BLOOM + 0.05, c + Vector3.yAxis * 0.1, Kit.hueSeq(h0 + 0.5, 0.4, 0.3, 1, 3))
		end
		frostRing.update(t)
		crackDark.update(t)
		crackHot.update(t)
		if once("white", t, T_WHITE) then
			Kit.spray(ctx, whiteout, P, 1, ColorSequence.new(Kit.hot(h0)), "point")
		end
		if once("shatter", t, T_SHATTER) then
			for k = 1, 6 do
				Kit.spray(ctx, storm, P, 10, ColorSequence.new(Kit.col(h0 + k / 6, 0.8, 1)), "sphere")
			end
			Kit.spray(ctx, streaks, P, 24, Kit.hueSeq(h0, 1, 0.75, 1, 6), "sphere")
		end
		if once("glit2", t, T_SHATTER + 0.15) then
			Kit.spray(ctx, glitter, P, 8, ColorSequence.new(Kit.hot(h0 + 0.3)), "sphere", 6)
		end
		light.Brightness = 2 * Kit.ramp(t, 0.5, T_BLOOM) * (if t < T_SHATTER then 1 else 0) + 3 * Kit.ramp(t, T_BLOOM, T_WHITE) * (if t < T_SHATTER then 1 else 0)
			+ (if t >= T_WHITE then 8 * math.exp(-(t - T_WHITE) * 6) else 0)
		light.Color = Kit.col(h0 + 0.55, 0.35, 1)
	end
end

function CrystalBloom.shake(t: number): Vector3
	local a = 0.08 * (if t > 0.85 and t < 1.75 then 1 else 0) + (if t >= 1.85 then 0.7 * math.exp(-(t - 1.85) * 8) else 0)
	return Vector3.new(math.sin(t * 90) * a, math.sin(t * 70 + 1) * a * 0.7, 0)
end

return CrystalBloom
