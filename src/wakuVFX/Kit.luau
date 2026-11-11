--!strict
-- wakuVFX Kit: the building blocks every effect uses (parts, beams on a world rig, particle bursts, ground cards,
-- lights) plus the rainbow palette and small easing helpers. Every part is Anchored, never collides, queries,
-- touches or casts a shadow.
local Kit = {}

Kit.missing = {} :: { [string]: number }

export type Opts = { rainbow: boolean, hue: number, scale: number, caster: Model?, seed: number, grade: boolean?, to: Vector3? }
export type Ctx = {
	root: Model,
	cf: CFrame,
	opts: Opts,
	assets: { [string]: string },
	rng: Random,
	emitters: { ParticleEmitter },
	cleanups: { () -> () },
	rig: Part,
	host: Part,
	outro: number?, -- set by build: seconds of closing animation handle.stop() should still play (RiftGate, WardShell)
	stopAt: number?, -- set by handle.stop(): effect time the stop was asked for; the effect closes from here
}

Kit.HIDE = CFrame.new(0, -5000, 0)

function Kit.newCtx(root: Model, cf: CFrame, assets: { [string]: string }, opts: Opts): Ctx
	local ctx: Ctx = {
		root = root,
		cf = cf,
		opts = opts,
		assets = assets,
		rng = Random.new(opts.seed),
		emitters = {},
		cleanups = {},
		rig = nil :: any,
		host = nil :: any,
	}
	-- attachments for beams live on one invisible part at the world origin, so Attachment.CFrame = world CFrame
	ctx.rig = Kit.part(ctx, root, "Rig", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	ctx.rig.Transparency = 1
	ctx.rig.CFrame = CFrame.identity
	ctx.host = Kit.part(ctx, root, "EmitHost", Vector3.one * 0.2, Color3.new(), Enum.Material.SmoothPlastic)
	ctx.host.Transparency = 1
	return ctx
end

function Kit.tex(ctx: Ctx, key: string): string
	local id = ctx.assets[key]
	if id == nil or id == "" then
		Kit.missing[key] = (Kit.missing[key] or 0) + 1
		return ""
	end
	return id
end

-- maths ------------------------------------------------------------------------------------------------------
function Kit.clamp01(x: number): number
	return math.clamp(x, 0, 1)
end
function Kit.smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
function Kit.easeOut(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) ^ 3
end
function Kit.easeIn(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x
end
function Kit.easeOutBack(x: number): number
	x = math.clamp(x, 0, 1)
	local c = 1.9
	return 1 + (c + 1) * (x - 1) ^ 3 + c * (x - 1) ^ 2
end
-- 0 before a, ramps to 1 by b
function Kit.ramp(t: number, a: number, b: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end

-- palette ----------------------------------------------------------------------------------------------------
-- hue for a layer: rainbow mode cycles with time; noncycling mode offsets opts.hue; effect layers can still add a full spatial rainbow
function Kit.hue(ctx: Ctx, t: number, phase: number): number
	if ctx.opts.rainbow then
		return (ctx.opts.hue + t * 0.6 + phase) % 1
	end
	return (ctx.opts.hue + phase * 0.06) % 1
end
function Kit.col(h: number, s: number?, v: number?): Color3
	return Color3.fromHSV(h % 1, s or 0.9, v or 1)
end
-- hot core: near white with a faint tint of the hue
function Kit.hot(h: number): Color3
	return Color3.fromHSV(h % 1, 0.14, 1)
end
-- dark ink: deep, saturated, opposite the body hue for contrast
function Kit.ink(h: number): Color3
	return Color3.fromHSV((h + 0.5) % 1, 0.85, 0.28)
end
-- a hue run along a sequence (beam length, particle life)
function Kit.hueSeq(h0: number, span: number, s: number?, v: number?, n: number?): ColorSequence
	local k = n or 4
	local kps = {}
	for i = 0, k - 1 do
		local f = i / (k - 1)
		table.insert(kps, ColorSequenceKeypoint.new(f, Color3.fromHSV((h0 + span * f) % 1, s or 0.9, v or 1)))
	end
	return ColorSequence.new(kps)
end

-- Kit.hueSeq that honours opts.rainbow: the full span in rainbow mode, a narrow run round the hue otherwise
function Kit.seq(ctx: Ctx, h0: number, span: number, s: number?, v: number?, n: number?): ColorSequence
	return Kit.hueSeq(h0, if ctx.opts.rainbow then span else span * 0.12, s, v, n)
end

-- instances --------------------------------------------------------------------------------------------------
function Kit.part(_: Ctx?, parent: Instance, name: string, size: Vector3, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = Kit.HIDE
	p.Parent = parent
	return p
end

function Kit.wedge(parent: Instance, name: string, size: Vector3, color: Color3, mat: Enum.Material, corner: boolean?): BasePart
	local p: BasePart = if corner then Instance.new("CornerWedgePart") else Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = mat
	p.CFrame = Kit.HIDE
	p.Parent = parent
	return p
end

function Kit.att(ctx: Ctx, cf: CFrame?): Attachment
	local a = Instance.new("Attachment")
	a.CFrame = cf or Kit.HIDE
	a.Parent = ctx.rig
	return a
end

-- a camera-facing ribbon between two rig attachments
function Kit.beam(ctx: Ctx, a0: Attachment, a1: Attachment, texKey: string?, z: number?): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.Segments = 12
	b.LightEmission = 1
	b.LightInfluence = 0
	b.TextureMode = Enum.TextureMode.Stretch
	b.TextureLength = 1
	b.TextureSpeed = 0
	b.ZOffset = z or 0
	if texKey then
		b.Texture = Kit.tex(ctx, texKey)
	end
	b.Parent = ctx.rig
	return b
end

-- particle burst source: emitters sit on one hidden host part that is moved to each burst point
function Kit.emitter(ctx: Ctx, name: string, texKey: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.Texture = Kit.tex(ctx, texKey)
	e.LightInfluence = 0
	e.LockedToPart = false
	e.Parent = ctx.host
	table.insert(ctx.emitters, e)
	return e
end
function Kit.emit(ctx: Ctx, e: ParticleEmitter, at: CFrame, n: number)
	ctx.host.CFrame = at
	e:Emit(math.max(1, math.floor(n + 0.5)))
end

-- flat ground card with a top-face decal (shock rings, cracks, frost)
function Kit.card(ctx: Ctx, name: string, texKey: string): (Part, Decal)
	local p = Kit.part(ctx, ctx.root, name, Vector3.new(1, 0.05, 1), Color3.new(), Enum.Material.SmoothPlastic)
	p.Transparency = 1
	local d = Instance.new("Decal")
	d.Face = Enum.NormalId.Top
	d.Texture = Kit.tex(ctx, texKey)
	d.Parent = p
	return p, d
end

function Kit.light(ctx: Ctx, parent: BasePart, range: number): PointLight
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = 0
	l.Shadows = false
	l.Parent = parent
	return l
end

-- deterministic per-slot random (frozen frames repeat exactly)
function Kit.slotRng(seed: number, t: number, period: number): Random
	return Random.new(seed * 7919 + math.floor(t / period))
end

-- fires once when t first passes `at`
function Kit.once(): (string, number, number) -> boolean
	local fired: { [string]: boolean } = {}
	return function(key: string, t: number, at: number): boolean
		if not fired[key] and t >= at then
			fired[key] = true
			return true
		end
		return false
	end
end

-- NumberSequence from (time, value) pairs, sorted, clamped to 0..1 and to the 20-keypoint limit
function Kit.numSeq(pts: { { number } }): NumberSequence
	table.sort(pts, function(a, b)
		return a[1] < b[1]
	end)
	local kps = {}
	local last = -1
	for _, p in pts do
		local x = math.clamp(p[1], 0, 1)
		if x > last + 1e-4 and #kps < 18 then
			table.insert(kps, NumberSequenceKeypoint.new(x, math.clamp(p[2], 0, 1)))
			last = x
		end
	end
	if #kps == 0 or kps[1].Time > 0 then
		table.insert(kps, 1, NumberSequenceKeypoint.new(0, if #kps > 0 then kps[1].Value else 1))
	end
	if kps[#kps].Time < 1 then
		if #kps >= 20 then
			kps[#kps] = NumberSequenceKeypoint.new(1, kps[#kps].Value)
		else
			table.insert(kps, NumberSequenceKeypoint.new(1, kps[#kps].Value))
		end
	end
	return NumberSequence.new(kps)
end

-- palette roles for one hue (rainbow body, white-hot core, deep ink, glow, pale spark, dark debris)
export type Pal = { main: Color3, hot: Color3, dark: Color3, glow: Color3, spark: Color3, debris: Color3 }
function Kit.pal(h: number): Pal
	return {
		main = Color3.fromHSV(h % 1, 0.82, 1),
		hot = Color3.fromHSV(h % 1, 0.1, 1),
		dark = Color3.fromHSV((h + 0.5) % 1, 0.85, 0.22),
		glow = Color3.fromHSV((h + 0.07) % 1, 0.7, 1),
		spark = Color3.fromHSV((h + 0.03) % 1, 0.35, 1),
		debris = Color3.fromHSV((h + 0.5) % 1, 0.6, 0.12),
	}
end

-- NumberSequence from { {t, v}, ... } keypoints (sizes/transparencies over a particle's life)
function Kit.curve(pts: { { number } }): NumberSequence
	local kps = {}
	for _, p in pts do
		table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	if kps[1].Time > 0 then
		table.insert(kps, 1, NumberSequenceKeypoint.new(0, kps[1].Value))
	end
	if kps[#kps].Time < 1 then
		table.insert(kps, NumberSequenceKeypoint.new(1, kps[#kps].Value))
	end
	return NumberSequence.new(kps)
end

export type BurstSpec = {
	tex: string,
	life: { number },
	size: { { number } },
	transp: { { number } }?,
	speed: { number }?,
	spread: number?,
	drag: number?,
	acc: Vector3?,
	rot: { number }?,
	rotSpeed: { number }?,
	le: number?,
	bright: number?,
	zoff: number?,
	flat: boolean?, -- lies flat on the ground (VelocityPerpendicular, emitted straight up at ~0 speed)
	vpar: boolean?, -- streaks along the velocity
}
-- a configured emitter for one burst layer (color is set per emission)
function Kit.burst(ctx: Ctx, name: string, b: BurstSpec): ParticleEmitter
	local e = Kit.emitter(ctx, name, b.tex)
	local S = ctx.opts.scale
	local sz = {}
	for _, p in b.size do
		table.insert(sz, { p[1], p[2] * S })
	end
	e.Size = Kit.curve(sz)
	e.Transparency = if b.transp then Kit.curve(b.transp) else NumberSequence.new(0)
	e.Lifetime = NumberRange.new(b.life[1], b.life[2] or b.life[1])
	if b.flat then
		e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		e.Speed = NumberRange.new(0.05) -- a real (tiny) velocity, so the flat orientation is always defined
		e.SpreadAngle = Vector2.zero
	else
		local sp = b.speed or { 0, 0 }
		e.Speed = NumberRange.new(sp[1] * S, (sp[2] or sp[1]) * S)
		e.SpreadAngle = Vector2.new(b.spread or 0, b.spread or 0)
		if b.vpar then
			e.Orientation = Enum.ParticleOrientation.VelocityParallel
		end
	end
	e.Drag = b.drag or 0
	e.Acceleration = b.acc or Vector3.zero
	if b.rot then
		e.Rotation = NumberRange.new(b.rot[1], b.rot[2] or b.rot[1])
	end
	if b.rotSpeed then
		e.RotSpeed = NumberRange.new(b.rotSpeed[1], b.rotSpeed[2])
	end
	e.LightEmission = b.le or 1
	e.Brightness = b.bright or 1
	e.ZOffset = b.zoff or 0
	return e
end

-- CFrame at p whose UpVector (an emitter's Top face) is d; safe for d straight up or down
function Kit.upTo(p: Vector3, d: Vector3): CFrame
	local u = if d.Magnitude > 1e-6 then d.Unit else Vector3.yAxis
	local r = u:Cross(Vector3.zAxis)
	if r.Magnitude < 1e-3 then
		r = u:Cross(Vector3.xAxis)
	end
	return CFrame.fromMatrix(p, r.Unit, u)
end

-- emit n particles at pos. mode: "point" (emitter's own spread, pointing `dir`), "disc" (outward round the ground,
-- `up` = rise), "sphere" (all directions) ; radius = random start offset.
function Kit.spray(ctx: Ctx, e: ParticleEmitter, pos: Vector3, n: number, color: ColorSequence, mode: string?, radius: number?, up: number?, dir: Vector3?)
	e.Color = color
	local m = mode or "point"
	local r = (radius or 0) * ctx.opts.scale
	local rng = ctx.rng
	if m == "point" then
		ctx.host.CFrame = Kit.upTo(pos, dir or Vector3.yAxis)
		e:Emit(n)
		return
	end
	for _ = 1, n do
		local a = rng:NextNumber(0, math.pi * 2)
		local off = Vector3.new(math.cos(a), 0, math.sin(a))
		local d: Vector3
		if m == "disc" then
			d = (off + Vector3.new(0, up or 0, 0)).Unit
		else
			d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
			d = if d.Magnitude > 1e-3 then d.Unit else Vector3.yAxis
		end
		local p = pos + off * rng:NextNumber(0, 1) * r
		ctx.host.CFrame = Kit.upTo(p, d)
		e:Emit(1)
	end
end

-- temporary client-side scene grade (darken / tint / white-out) owned by one effect; removed by its cleanup.
-- Effects animate it each frame. opts.grade = false disables it (returns nil).
local gradeN = 0
function Kit.grade(ctx: Ctx): ColorCorrectionEffect?
	if (ctx.opts :: any).grade == false then
		return nil
	end
	gradeN += 1
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "wakuVFX_Grade" .. gradeN
	table.insert(ctx.cleanups, function()
		cc:Destroy()
	end)
	cc.Parent = game:GetService("Lighting")
	return cc
end

-- curve value at u (0..1) for { {t, v}, ... } keypoints (linear)
function Kit.evalCurve(pts: { { number } }, u: number): number
	if u <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if u <= b[1] then
			return a[2] + (b[2] - a[2]) * (u - a[1]) / math.max(b[1] - a[1], 1e-6)
		end
	end
	return pts[#pts][2]
end

-- flat textured card lying on the ground: a Beam whose width runs along the attachments' Y axis, laid
-- horizontal. Unlike a flat particle it is driven by the effect clock, so it is exact in frozen frames.
-- fire(t0, pos, color) starts one instance; update(t) animates size / transparency over spec.life.
export type FlatSpec = { tex: string, life: number, size: { { number } }, transp: { { number } }?, rot: number?,
	spin: number?, bright: number?, le: number?, z: number? }
export type Flat = { fire: (number, Vector3, ColorSequence) -> (), update: (number) -> () }
function Kit.flat(ctx: Ctx, name: string, spec: FlatSpec): Flat
	local a0, a1 = Kit.att(ctx), Kit.att(ctx)
	local b = Kit.beam(ctx, a0, a1, spec.tex, spec.z or 0)
	b.Name = name
	b.FaceCamera = false
	b.Segments = 1
	b.Brightness = spec.bright or 1
	b.LightEmission = spec.le or 1
	b.Enabled = false
	local t0: number? = nil
	local pos = Vector3.zero
	return {
		fire = function(t: number, p: Vector3, color: ColorSequence)
			t0 = t
			pos = p
			b.Color = color
		end,
		update = function(t: number)
			if t0 == nil or t < t0 or t > t0 + spec.life then
				b.Enabled = false
				return
			end
			local u = (t - t0) / spec.life
			local size = Kit.evalCurve(spec.size, u) * ctx.opts.scale
			local r = math.rad((spec.rot or 0) + (spec.spin or 0) * (t - t0))
			local x = Vector3.new(math.cos(r), 0, math.sin(r))
			local z = Vector3.new(-math.sin(r), 0, math.cos(r))
			a0.CFrame = CFrame.fromMatrix(pos - x * size / 2, x, z)
			a1.CFrame = CFrame.fromMatrix(pos + x * size / 2, x, z)
			b.Width0, b.Width1 = size, size
			b.Transparency = NumberSequence.new(if spec.transp then Kit.evalCurve(spec.transp, u) else 0)
			b.Enabled = true
		end,
	}
end

-- textured card at any orientation (wall rings, muzzle rings, mid-air shockwaves): a flat Beam like Kit.flat, but
-- the caller drives it every frame. set(pos, normal, size, transparency, rotation?) ; size is in studs (unscaled).
export type Plate = { beam: Beam, set: (Vector3, Vector3, number, number, number?) -> (), hide: () -> () }
function Kit.plate(ctx: Ctx, name: string, texKey: string, z: number?): Plate
	local a0, a1 = Kit.att(ctx), Kit.att(ctx)
	local b = Kit.beam(ctx, a0, a1, texKey, z or 0)
	b.Name = name
	b.FaceCamera = false
	b.Segments = 1
	b.Enabled = false
	return {
		beam = b,
		set = function(pos: Vector3, normal: Vector3, size: number, transp: number, rot: number?)
			if transp >= 0.995 or size <= 0 then
				b.Enabled = false
				return
			end
			local n = if normal.Magnitude > 1e-6 then normal.Unit else Vector3.yAxis
			local x = n:Cross(Vector3.yAxis)
			if x.Magnitude < 1e-3 then
				x = n:Cross(Vector3.xAxis)
			end
			x = x.Unit
			local y = n:Cross(x)
			if rot then
				local c, s = math.cos(rot), math.sin(rot)
				x, y = x * c + y * s, y * c - x * s
			end
			a0.CFrame = CFrame.fromMatrix(pos - x * size / 2, x, y)
			a1.CFrame = CFrame.fromMatrix(pos + x * size / 2, x, y)
			b.Width0, b.Width1 = size, size
			b.Transparency = NumberSequence.new(math.clamp(transp, 0, 1))
			b.Enabled = true
		end,
		hide = function()
			b.Enabled = false
		end,
	}
end

-- camera-facing textured card (glows, flare stars) driven by the effect clock, so it is exact in frozen frames.
-- set(pos, size, transparency, rotation?, stretch?) ; stretch widens the card (1 = square).
export type Sprite = { beam: Beam, set: (Vector3, number, number, number?, number?) -> (), hide: () -> () }
function Kit.sprite(ctx: Ctx, name: string, texKey: string, z: number?): Sprite
	local a0, a1 = Kit.att(ctx), Kit.att(ctx)
	local b = Kit.beam(ctx, a0, a1, texKey, z or 0)
	b.Name = name
	b.Segments = 1
	b.Enabled = false
	return {
		beam = b,
		set = function(pos: Vector3, size: number, transp: number, rot: number?, stretch: number?)
			if transp >= 0.995 or size <= 0 then
				b.Enabled = false
				return
			end
			local cam = workspace.CurrentCamera :: Camera?
			local up = if cam then cam.CFrame.UpVector else Vector3.yAxis
			if rot and cam then
				up = up * math.cos(rot) + cam.CFrame.RightVector * math.sin(rot)
			end
			a0.CFrame = CFrame.new(pos - up * size / 2)
			a1.CFrame = CFrame.new(pos + up * size / 2)
			local w = size * (stretch or 1)
			b.Width0, b.Width1 = w, w
			b.Transparency = NumberSequence.new(math.clamp(transp, 0, 1))
			b.Enabled = true
		end,
		hide = function()
			b.Enabled = false
		end,
	}
end

-- CFrame at p whose RightVector is d (Beam curve handles follow an attachment's X axis)
function Kit.rightTo(p: Vector3, d: Vector3): CFrame
	local u = if d.Magnitude > 1e-6 then d.Unit else Vector3.xAxis
	local r = u:Cross(Vector3.yAxis)
	if r.Magnitude < 1e-3 then
		r = u:Cross(Vector3.xAxis)
	end
	return CFrame.fromMatrix(p, u, r.Unit)
end

-- jagged lightning between two points: n straight segments whose joints are thrown off the line. set(p0, p1, width,
-- jag (fraction of the length), seed, colour, transparency); the same seed always draws the same bolt, so a dark
-- core and its glow can share one path and a frozen frame repeats exactly.
export type Bolt = { beams: { Beam }, set: (Vector3, Vector3, number, number, number, Color3, number) -> (), hide: () -> () }
function Kit.bolt(ctx: Ctx, name: string, n: number, z: number?, le: number?): Bolt
	local atts: { Attachment } = {}
	local beams: { Beam } = {}
	for i = 1, n + 1 do
		atts[i] = Kit.att(ctx)
	end
	for i = 1, n do
		local b = Kit.beam(ctx, atts[i], atts[i + 1], "bolt_glow", z or 0)
		b.Name = name
		b.Segments = 1
		b.LightEmission = le or 1
		b.Enabled = false
		beams[i] = b
	end
	local function hide()
		for _, b in beams do
			b.Enabled = false
		end
	end
	return {
		beams = beams,
		set = function(p0: Vector3, p1: Vector3, width: number, jag: number, seed: number, color: Color3, transp: number)
			local d = p1 - p0
			local len = d.Magnitude
			if transp >= 0.995 or width <= 0 or len < 1e-4 then
				hide()
				return
			end
			local r = Random.new(math.floor(seed))
			local u = d:Cross(Vector3.yAxis)
			if u.Magnitude < 1e-3 then
				u = d:Cross(Vector3.xAxis)
			end
			u = u.Unit
			local v = u:Cross(d.Unit)
			for i = 1, n + 1 do
				local k = if i == 1 or i == n + 1 then 0 else jag * len
				atts[i].CFrame = CFrame.new(p0 + d * ((i - 1) / n) + (u * r:NextNumber(-1, 1) + v * r:NextNumber(-1, 1)) * k)
			end
			local cs = ColorSequence.new(color)
			local ts = NumberSequence.new(math.clamp(transp, 0, 1))
			for i, b in beams do
				b.Width0 = width * (1 - 0.7 * (i - 1) / n)
				b.Width1 = width * (1 - 0.7 * i / n)
				b.Color = cs
				b.Transparency = ts
				b.Enabled = true
			end
		end,
		hide = hide,
	}
end

-- one expanding ring on a Kit.plate: u = 0..1 through its life, size s0 -> s1 (studs), opacity fading from a0
function Kit.pulse(pl: Plate, pos: Vector3, normal: Vector3, u: number, s0: number, s1: number, a0: number?, rot: number?)
	if u <= 0 or u >= 1 then
		pl.hide()
		return
	end
	local a = a0 or 0
	pl.set(pos, normal, s0 + (s1 - s0) * Kit.easeOut(u), a + (1 - a) * u * u, rot)
end

return Kit
