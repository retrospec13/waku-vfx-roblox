--!strict
--[[ EarthRise: alchemy-style earth move for wakuVFX. Clap, palms slam the ground, a glyph circle draws itself,
	and a wave of studded rainbow voxel pillars erupts along the facing direction, holds, then crumbles cube by cube.
	Beats (effect time, seconds):
	  0.00-0.30  wind-up, arms sweep wide, then CLAP (hot flash + rainbow sparks at the hands)
	  0.30-0.62  drop into a crouch, palms slam the ground
	  0.62       slam: shock ring, crack, dust, glyph circle (two rings, hexagram, ticks) draws by angle, rainbow arcs
	  0.66-1.40  8 main pillars + 7 pairs of flanking walls rise as rigid voxel columns (ease-out-back), 2x2 studs on
	             every column top, white-hot flash on emergence, then one hue per pillar along the wave
	  1.40-3.00  hold: hue drifts, arcs fade, glyph fades out
	  3.00-4.70  crumble top-down, each voxel 0.05 s after the one above: drift, spin, shrink, fade
	  4.90       everything destroyed, caster pose reset
	cf = ground point under the caster, LookVector = direction of the wave. opts.caster = R15 model to pose
	(procedural pose on a local clone, no animation asset). Always rainbow (opts.rainbow/hue are ignored).
]]
local CasterState = require(script.Parent.Parent.CasterState)
local Kit = require(script.Parent.Parent.Kit)

local EarthRise = {}
EarthRise.life = 4.9
EarthRise.currentT = nil :: number?

local TAU = math.pi * 2
local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end
local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end
local function easeOutBack(x: number): number
	x = clamp01(x)
	local c1, c3 = 2.2, 3.2
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end
local function rainbow(h: number, s: number?, v: number?): Color3
	return Color3.fromHSV(h % 1, s or 0.9, v or 1)
end

-------------------------------------------------------------------------------
-- caster pose (R15 Motor6D.Transform keyframes)
-------------------------------------------------------------------------------
local R = math.rad
local function A(x: number, y: number, z: number): CFrame
	return CFrame.Angles(R(x), R(y), R(z))
end
-- yaw after pitch: raise the arm forward first, then swing it inward
local function arm(pitch: number, yaw: number, roll: number): CFrame
	return CFrame.Angles(0, R(yaw), 0) * CFrame.Angles(R(pitch), 0, 0) * CFrame.Angles(0, 0, R(roll))
end
local I = CFrame.identity
local KEYS: { { t: number, p: { [string]: CFrame } } } = {
	{ t = 0.0, p = {} },
	{ t = 0.17, p = { -- wind-up: arms flung wide and high, chest open
		Waist = A(12, 0, 0), Neck = A(10, 0, 0),
		RightShoulder = arm(0, 0, 115), LeftShoulder = arm(0, 0, -115),
		RightElbow = A(20, 0, 0), LeftElbow = A(20, 0, 0) } },
	{ t = 0.29, p = { -- CLAP in front of the chest
		Waist = A(-6, 0, 0), Neck = A(-4, 0, 0),
		RightShoulder = arm(82, 38, 0), LeftShoulder = arm(82, -38, 0),
		RightElbow = A(28, 0, 0), LeftElbow = A(28, 0, 0) } },
	{ t = 0.42, p = { -- hold the clap, sink a little
		Root = CFrame.new(0, -0.25, 0), Waist = A(-8, 0, 0), Neck = A(-6, 0, 0),
		RightShoulder = arm(85, 40, 0), LeftShoulder = arm(85, -40, 0),
		RightElbow = A(30, 0, 0), LeftElbow = A(30, 0, 0),
		RightHip = A(14, 0, 0), LeftHip = A(14, 0, 0), RightKnee = A(-22, 0, 0), LeftKnee = A(-22, 0, 0) } },
	{ t = 0.62, p = { -- SLAM: deep crouch, palms flat on the ground in front
		Root = CFrame.new(0, -1.45, 0) * A(-28, 0, 0), Waist = A(-22, 0, 0), Neck = A(18, 0, 0),
		RightShoulder = arm(62, 8, 0), LeftShoulder = arm(62, -8, 0),
		RightElbow = A(6, 0, 0), LeftElbow = A(6, 0, 0),
		RightWrist = A(-55, 0, 0), LeftWrist = A(-55, 0, 0),
		RightHip = A(96, 0, 0), LeftHip = A(70, 0, -8), RightKnee = A(-110, 0, 0), LeftKnee = A(-95, 0, 0) } },
	{ t = 2.75, p = "SAME" :: any },
	{ t = 3.35, p = { -- rise, one arm thrown out toward the wall of stone
		Waist = A(0, -10, 0), Neck = A(0, -12, 0),
		RightShoulder = arm(70, -20, 0), RightElbow = A(5, 0, 0) } },
	{ t = 4.9, p = {} },
}
KEYS[6].p = KEYS[5].p
local JOINTS = { "Root", "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist",
	"LeftWrist", "RightHip", "LeftHip", "RightKnee", "LeftKnee" }

local function poseAt(t: number): { [string]: CFrame }
	local out = {}
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		if t <= b.t or i == #KEYS - 1 then
			local u = smooth((t - a.t) / (b.t - a.t))
			for _, j in JOINTS do
				out[j] = (a.p[j] or I):Lerp(b.p[j] or I, u)
			end
			return out
		end
	end
	return out
end

-------------------------------------------------------------------------------
-- builders
-------------------------------------------------------------------------------
local function part(parent: Instance, name: string, size: Vector3, color: Color3, mat: Enum.Material): Part
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
	p.Parent = parent
	return p
end

local HIDE = CFrame.new(0, -500, 0)

type Block = { p: Part, j: number, hc: number, size: Vector3, off: CFrame, studs: { { p: Part, off: CFrame } }, spin: Vector3, drift: Vector3 }
type Pillar = { model: Model, base: CFrame, ts: number, tc: number, h: number, height: number, blocks: { Block },
	k: number, main: boolean, glow: PointLight?, fired: boolean, crumbleFired: boolean, debris: { { p: Part, v: Vector3, w: Vector3, p0: Vector3 } } }


EarthRise.required = { "spark_streak", "spark_glint", "glow_soft", "shock_ring", "ground_crack" }

function EarthRise.build(ctx: Kit.Ctx): (number) -> ()
	local caster: Model? = ctx.opts.caster
	local base = ctx.cf
	local rng = Random.new(ctx.opts.seed)
	local root = ctx.root
	local function T(key: string): string
		return Kit.tex(ctx, key)
	end

	local fwd = base.LookVector
	local right = base.RightVector
	local ground = base.Position
	local center = ground + fwd * 2.4 + Vector3.new(0, 0.06, 0)

	-- emitter host (one invisible part, moved before each Emit)
	local host = part(root, "EmitHost", Vector3.one, Color3.new(), Enum.Material.SmoothPlastic)
	host.Transparency = 1
	local att = Instance.new("Attachment")
	att.Parent = host
	local emitters = ctx.emitters
	local function emitter(name: string, texture: string): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.Texture = texture
		e.Enabled = false
		e.Parent = att
		table.insert(emitters, e)
		return e
	end
	local rainbowSeq = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 60)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 255, 110)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 200, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(150, 90, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 210)) })
	local sparks = emitter("Sparks", T("spark_streak"))
	sparks.Color = rainbowSeq
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new(0)
	sparks.Lifetime = NumberRange.new(0.25, 0.6)
	sparks.Speed = NumberRange.new(22, 46)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -40, 0)
	sparks.Drag = 3
	sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	local dust = emitter("Dust", T("glow_soft"))
	dust.Color = ColorSequence.new(Color3.fromRGB(120, 108, 100), Color3.fromRGB(70, 64, 62))
	dust.LightEmission = 0
	dust.LightInfluence = 0.6
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 6.5) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.8, 1.5)
	dust.Speed = NumberRange.new(5, 14)
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Acceleration = Vector3.new(0, 2, 0)
	dust.Drag = 3.5
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-40, 40)
	local glints = emitter("Glints", T("spark_glint"))
	glints.Color = rainbowSeq
	glints.LightEmission = 1
	glints.LightInfluence = 0
	glints.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	glints.Lifetime = NumberRange.new(0.5, 1.1)
	glints.Speed = NumberRange.new(6, 18)
	glints.SpreadAngle = Vector2.new(60, 60)
	glints.Acceleration = Vector3.new(0, -12, 0)
	glints.Rotation = NumberRange.new(0, 360)
	glints.RotSpeed = NumberRange.new(-300, 300)
	local function emitAt(e: ParticleEmitter, pos: Vector3, n: number, up: Vector3?)
		host.CFrame = CFrame.lookAt(pos, pos + (up or Vector3.yAxis)) * CFrame.Angles(-math.pi / 2, 0, 0)
		e:Emit(n)
	end

	-- clap flash + slam shock ring + glyph light
	local clapBall = part(root, "ClapFlash", Vector3.one, Color3.new(1, 1, 1), Enum.Material.Neon)
	clapBall.Shape = Enum.PartType.Ball
	clapBall.CFrame = HIDE
	local clapRing = part(root, "ClapRing", Vector3.new(0.05, 1, 1), Color3.new(1, 1, 1), Enum.Material.Neon)
	clapRing.Shape = Enum.PartType.Cylinder
	clapRing.CFrame = HIDE
	local function decalCard(name: string, texture: string): (Part, Decal)
		local p = part(root, name, Vector3.new(1, 0.05, 1), Color3.new(), Enum.Material.SmoothPlastic)
		p.Transparency = 1
		p.CFrame = HIDE
		local d = Instance.new("Decal")
		d.Face = Enum.NormalId.Top
		d.Texture = texture
		d.Parent = p
		return p, d
	end
	local shock, shockD = decalCard("ShockRing", T("shock_ring"))
	local crack, crackD = decalCard("SlamCrack", T("ground_crack"))
	crackD.Color3 = Color3.fromRGB(14, 10, 22)
	local light = Instance.new("PointLight")
	light.Range = 16
	light.Brightness = 0
	light.Shadows = false
	light.Parent = host

	-- glyph circle: outer double ring, hexagram, inner ring, ticks (all thin Neon bars, drawn by angle)
	type Seg = { p: Part, a: number, cf: CFrame, len: number, w: number, group: string }
	local segs: { Seg } = {}
	local glyph = Instance.new("Folder")
	glyph.Name = "Glyph"
	glyph.Parent = root
	local up = CFrame.new(center) * CFrame.fromMatrix(Vector3.zero, right, Vector3.yAxis, -fwd)
	local function seg(a: Vector3, b: Vector3, w: number, angle: number, group: string)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local cf = up * CFrame.lookAt(mid, b)
		local p = part(glyph, "Seg", Vector3.new(w, 0.07, len + w * 0.6), Color3.new(1, 1, 1), Enum.Material.Neon)
		p.CFrame = HIDE
		table.insert(segs, { p = p, a = angle, cf = cf, len = len, w = w, group = group })
	end
	local function ring(r: number, n: number, w: number, group: string)
		for i = 0, n - 1 do
			local a0, a1 = i / n * TAU, (i + 1) / n * TAU
			seg(Vector3.new(math.cos(a0) * r, 0, math.sin(a0) * r), Vector3.new(math.cos(a1) * r, 0, math.sin(a1) * r), w, (i + 0.5) / n, group)
		end
	end
	ring(6.2, 44, 0.24, "outer")
	ring(5.55, 40, 0.12, "outer2")
	ring(1.9, 18, 0.14, "inner")
	local function vtx(k: number, r: number, rot: number): Vector3
		local a = rot + k / 3 * TAU
		return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	end
	for tri = 0, 1 do
		local rot = -math.pi / 2 + tri * math.pi
		for k = 0, 2 do
			seg(vtx(k, 5.55, rot), vtx(k + 1, 5.55, rot), 0.16, (tri * 3 + k + 0.5) / 6, "hex")
		end
	end
	for k = 0, 11 do
		local a = k / 12 * TAU
		seg(Vector3.new(math.cos(a) * 5.6, 0, math.sin(a) * 5.6), Vector3.new(math.cos(a) * 6.9, 0, math.sin(a) * 6.9), 0.14, k / 12, "tick")
	end

	-- arcs: rainbow alchemy lightning crawling over the ground from the glyph along the pillar path
	local ARCS, ASEG = 9, 7
	local arcParts: { Part } = {}
	for i = 1, ARCS * ASEG do
		local p = part(root, "Arc", Vector3.new(0.13, 0.13, 1), Color3.new(1, 1, 1), Enum.Material.Neon)
		p.CFrame = HIDE
		arcParts[i] = p
	end

	-- pillars: grid-aligned voxel columns (2x2 for the main line, 1x1 for the flanking walls) with real 3D studs on
	-- every column top; main line runs along fwd with a red -> violet gradient
	local pillars: { Pillar } = {}
	local stone = Instance.new("Folder")
	stone.Name = "Stone"
	stone.Parent = root
	local NMAIN = 8
	local V = 1.8 -- voxel edge (studs)
	local INSET = 0.94 -- visible seam between voxels
	local function addPillar(k: number, main: boolean, d: number, side: number, h: number, _size: number, ts: number)
		local m = Instance.new("Model")
		m.Name = if main then "Pillar" .. k else "Wall" .. k
		m.Parent = stone
		local pos = ground + fwd * d + right * side
		-- the whole column assembly leans a little away from the caster (stays a clean grid)
		local lean = CFrame.Angles(R(-5 - rng:NextNumber(0, 6)), R(rng:NextNumber(-8, 8)), R(-side * 1.2))
		local basecf = CFrame.lookAt(pos, pos + fwd) * lean
		local blocks: { Block } = {}
		local n = if main then 2 else 1
		local top = 0
		for cx = 0, n - 1 do
			for cz = 0, n - 1 do
				local hc = math.max(1, h + (if main then rng:NextInteger(-1, 1) else 0))
				top = math.max(top, hc)
				local x = (cx - (n - 1) / 2) * V
				local z = (cz - (n - 1) / 2) * V
				for j = 0, hc - 1 do
					local off = CFrame.new(x, j * V + V / 2, z)
					local sz = Vector3.one * V * INSET
					local p = part(m, "Block" .. j, sz, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
					p.CastShadow = true
					p.Reflectance = 0.04
					p.CFrame = HIDE
					local studs = {}
					if j == hc - 1 then
						for sx = -1, 1, 2 do
							for sz2 = -1, 1, 2 do
								local st = part(m, "Stud", Vector3.new(V * 0.16, V * 0.3, V * 0.3), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
								st.Shape = Enum.PartType.Cylinder
								st.Reflectance = 0.04
								st.CFrame = HIDE
								table.insert(studs, { p = st, off = CFrame.new(sx * V * 0.23, V * INSET / 2 + V * 0.08, sz2 * V * 0.23) * CFrame.Angles(0, 0, math.pi / 2) })
							end
						end
					end
					table.insert(blocks, { p = p, j = j, hc = hc, size = sz, off = off, studs = studs,
						spin = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-4, 4), rng:NextNumber(-6, 6)),
						drift = right * (x / V * 2 + rng:NextNumber(-1.5, 1.5)) + fwd * rng:NextNumber(-1, 3) })
				end
			end
		end
		local y = top * V
		local glow: PointLight? = nil
		if main then
			local gp = part(root, "PillarGlow", Vector3.one, Color3.new(), Enum.Material.SmoothPlastic)
			gp.Transparency = 1
			gp.CFrame = CFrame.new(pos + Vector3.new(0, 2.5, 0) - fwd * 2)
			local pl = Instance.new("PointLight")
			pl.Range = 12
			pl.Brightness = 0
			pl.Shadows = false
			pl.Parent = gp
			glow = pl
		end
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 1
		hl.OutlineColor = Color3.fromRGB(14, 10, 24)
		hl.OutlineTransparency = 0.25
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = m
		local debris = {}
		for _ = 1, if main then 6 else 2 do
			local s = V * rng:NextNumber(0.25, 0.42)
			local dp = part(root, "Debris", Vector3.one * s, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
			dp.CFrame = HIDE
			local dir = (right * rng:NextNumber(-1, 1) + fwd * rng:NextNumber(-0.6, 1)).Unit
			table.insert(debris, { p = dp, v = dir * rng:NextNumber(6, 15) + Vector3.new(0, rng:NextNumber(16, 30), 0),
				w = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12)), p0 = pos + Vector3.new(0, 0.6, 0) })
		end
		table.insert(pillars, { model = m, base = basecf, ts = ts, tc = 3.0 + d * 0.018 + (if main then 0 else 0.05), h = top,
			height = y, blocks = blocks, k = k, main = main, glow = glow, fired = false, crumbleFired = false, debris = debris })
	end
	for k = 1, NMAIN do
		local d = 7.4 + (k - 1) * 3.7
		local side = (if k % 2 == 0 then 1 else -1) * rng:NextNumber(0.2, 1.0)
		local h = 2 + math.floor(k * 0.7)
		addPillar(k, true, d, side, h, 0, 0.66 + (k - 1) * 0.085)
	end
	for k = 1, NMAIN - 1 do
		local d = 9.2 + (k - 1) * 3.7
		for _, sd in { -1, 1 } do
			addPillar(k, false, d, sd * (4.6 + k * 0.35 + rng:NextNumber(-0.3, 0.3)), math.max(1, math.floor(k * 0.45) + 1), 0,
				0.72 + (k - 1) * 0.085 + rng:NextNumber(0, 0.03))
		end
	end

	-- caster: animate a client-local clone without an Animator (the Humanoid's Animator would reset Transform every
	-- frame). An NPC original is unparented locally for the duration; a player's character stays in place (camera and
	-- controls keep working) but is hidden and anchored locally. Both are restored in finish().
	if caster then
		local clone = CasterState.clone(ctx, caster)
		for _, d in clone:GetDescendants() do
			if d:IsA("Animator") or d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			end
		end
		local hum = clone:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		local cloneRoot = clone:FindFirstChild("HumanoidRootPart")
		if cloneRoot and cloneRoot:IsA("BasePart") then
			cloneRoot.Anchored = true
		end
		clone.Name = "CasterPose"
		clone.Parent = root
		caster = clone
	end
	-- joints: classic Motor6D rigs or the newer AnimationConstraint rigs (made kinematic so Transform is exact)
	local motors: { [string]: any } = {}
	if caster then
		for _, d in caster:GetDescendants() do
			if d:IsA("Motor6D") then
				motors[d.Name] = d
			elseif d:IsA("AnimationConstraint") then
				(d :: any).IsKinematic = true
				motors[d.Name] = d
			end
		end
	end
	local hands = caster and { caster:FindFirstChild("LeftHand") :: BasePart?, caster:FindFirstChild("RightHand") :: BasePart? } or {}


	local fired: { [string]: boolean } = {}
	local function once(key: string, t: number, at: number): boolean
		if not fired[key] and t >= at then
			fired[key] = true
			return true
		end
		return false
	end

	local lastArcSlot = -1
	local function finish()
		for _, m in motors do
			m.Transform = CFrame.identity
		end
		EarthRise.currentT = nil
	end

	local function step(t: number)
		EarthRise.currentT = t

		-- pose (RenderStepped/Animator-free rig: Transform persists)
		local pose = poseAt(t)
		for name, m in motors do
			local cf = pose[name]
			if cf then
				m.Transform = cf
			end
		end

		local hue0 = t * 0.35

		-- clap
		local handMid = center + Vector3.new(0, 3.2, 0) - fwd * 1.6
		if hands[1] and hands[2] then
			handMid = ((hands[1] :: BasePart).Position + (hands[2] :: BasePart).Position) / 2
		end
		local tc = t - 0.29
		if tc >= 0 and tc < 0.32 then
			local u = tc / 0.32
			clapBall.Size = Vector3.one * (0.6 + 3.4 * math.sqrt(u))
			clapBall.CFrame = CFrame.new(handMid)
			clapBall.Transparency = u ^ 0.7
			clapBall.Color = Color3.new(1, 1, 1):Lerp(rainbow(hue0 + u * 0.5), u)
			clapRing.Size = Vector3.new(0.05, 1, 1) * Vector3.new(1, 1.5 + 9 * u, 1.5 + 9 * u)
			clapRing.CFrame = CFrame.new(handMid) * CFrame.fromMatrix(Vector3.zero, fwd, Vector3.yAxis) * CFrame.Angles(0, 0, 0)
			clapRing.Transparency = 0.6 + 0.4 * u
			clapRing.Color = rainbow(hue0 + 0.3)
		else
			clapBall.CFrame = HIDE
			clapRing.CFrame = HIDE
		end
		if once("clap", t, 0.29) then
			emitAt(sparks, handMid, 40)
			emitAt(glints, handMid, 14)
		end

		-- slam: shock ring, crack decal, dust
		local tsl = t - 0.62
		if tsl >= 0 and tsl < 0.6 then
			local u = tsl / 0.6
			local r = 3 + 26 * (1 - (1 - u) ^ 3)
			shock.Size = Vector3.new(r, 0.05, r)
			shock.CFrame = CFrame.new(center + Vector3.new(0, 0.04, 0))
			shockD.Transparency = u ^ 1.3
			shockD.Color3 = rainbow(hue0 + u * 0.4)
		else
			shock.CFrame = HIDE
		end
		if tsl >= 0 and t < 3.4 then
			local u = smooth(tsl / 0.12)
			crack.Size = Vector3.new(15 * u + 0.1, 0.05, 15 * u + 0.1)
			crack.CFrame = CFrame.new(center + Vector3.new(0, 0.03, 0))
			crackD.Transparency = 0.05 + 0.95 * smooth((t - 2.8) / 0.6)
		else
			crack.CFrame = HIDE
		end
		if once("slam", t, 0.62) then
			emitAt(dust, center, 26)
			emitAt(sparks, center + Vector3.new(0, 0.4, 0), 50)
		end

		-- glyph: draw on 0.62-0.86 by angle (outer clockwise, hex after, ticks last), glow pulse, fade 2.5-3.1
		local draw = smooth((t - 0.6) / 0.26)
		local fade = smooth((t - 2.5) / 0.6)
		local spin = CFrame.Angles(0, t * 0.6, 0)
		for _, s in segs do
			local gate = if s.group == "hex" then smooth((t - 0.7) / 0.18) elseif s.group == "tick" then smooth((t - 0.8) / 0.12) else draw
			if s.a < gate and fade < 1 then
				local pulse = 0.5 + 0.5 * math.sin(t * 14 - s.a * TAU * 2)
				s.p.CFrame = (if s.group == "outer" or s.group == "tick" then CFrame.new(center) * spin * CFrame.new(-center) else CFrame.identity) * s.cf
				s.p.Transparency = math.clamp(fade + (if t < 1.0 then 0 else 0.15 * pulse), 0, 1)
				local hot = smooth((t - 0.62 - s.a * 0.24) / 0.25)
				s.p.Color = Color3.new(1, 1, 1):Lerp(rainbow(s.a + hue0 + (if s.group == "hex" then 0.5 else 0)), hot)
			else
				s.p.CFrame = HIDE
			end
		end
		light.Brightness = if t > 0.6 and t < 3.0 then (0.9 + 0.6 * math.sin(t * 9)) * (1 - fade) + 2.5 * (1 - smooth(tsl / 0.3)) else 0
		light.Color = rainbow(hue0)
		host.CFrame = CFrame.new(center + Vector3.new(0, 2, 0))

		-- arcs 0.6-2.1: reseed every 0.04 s, crawl outward toward pillar bases
		local arcOn = t >= 0.6 and t < 2.1
		local slot = math.floor(t / 0.04)
		if arcOn and slot ~= lastArcSlot then
			lastArcSlot = slot
			local ar = Random.new(1000 + slot)
			local reach = 6 + 26 * smooth((t - 0.6) / 0.8)
			for a = 0, ARCS - 1 do
				local target = center + fwd * ar:NextNumber(2, reach) + right * ar:NextNumber(-7, 7)
				if a < 3 then
					local ang = ar:NextNumber(0, TAU)
					target = center + (right * math.cos(ang) + fwd * math.sin(ang)) * 6.2
				end
				local from = center + (right * ar:NextNumber(-1, 1) + fwd * ar:NextNumber(-1, 1)) * 1.5
				local prev = from
				local hue = hue0 + a / ARCS
				for sI = 1, ASEG do
					local u = sI / ASEG
					local pt = from:Lerp(target, u)
					if sI < ASEG then
						pt += right * ar:NextNumber(-1.1, 1.1) + fwd * ar:NextNumber(-0.8, 0.8) + Vector3.new(0, ar:NextNumber(0.1, 1.3), 0)
					end
					local p = arcParts[a * ASEG + sI]
					local len = (pt - prev).Magnitude
					p.Size = Vector3.new(0.13, 0.13, len + 0.1)
					p.CFrame = CFrame.lookAt((prev + pt) / 2, pt)
					p.Color = rainbow(hue + u * 0.25, 0.75)
					prev = pt
				end
			end
		elseif not arcOn and lastArcSlot ~= -2 then
			lastArcSlot = -2
			for _, p in arcParts do
				p.CFrame = HIDE
			end
		end
		if arcOn then
			local at = math.clamp(smooth((t - 1.6) / 0.5), 0, 1)
			for _, p in arcParts do
				p.Transparency = at
			end
		end

		-- pillars
		for _, pl in pillars do
			local u = (t - pl.ts) / 0.24
			if u < 0 then
				for _, b in pl.blocks do
					b.p.CFrame = HIDE
					for _, st in b.studs do
						st.p.CFrame = HIDE
					end
				end
				continue
			end
			if not pl.fired then
				pl.fired = true
				local pos = pl.base.Position
				emitAt(dust, pos, if pl.main then 10 else 5)
				emitAt(glints, pos + Vector3.new(0, 1, 0), if pl.main then 8 else 3)
				if pl.main then
					emitAt(sparks, pos + Vector3.new(0, 0.5, 0), 12)
				end
			end
			local rise = easeOutBack(u)
			local sink = (1 - rise) * (pl.height + 1.5)
			local crumbleT = t - pl.tc
			if crumbleT >= 0 and not pl.crumbleFired then
				pl.crumbleFired = true
				emitAt(dust, pl.base.Position + Vector3.new(0, pl.height * 0.5, 0), if pl.main then 9 else 4)
			end
			local frac = pl.k / NMAIN
			local glow = pl.glow
			if glow then
				local on = smooth((t - pl.ts) / 0.15) * (1 - smooth((t - pl.tc) / 0.5))
				glow.Brightness = 0.8 * on + 2.0 * on * math.exp(-(t - pl.ts) * 5)
				glow.Color = rainbow(frac * 0.82 + t * 0.12)
			end
			for _, b in pl.blocks do
				local cf = pl.base * CFrame.new(0, -sink, 0) * b.off
				local hot = smooth((t - pl.ts - 0.06) / 0.28)
				-- gradient: hue by wave position, small step up the column; value shading darker at the base
				local row = b.j / math.max(1, pl.h - 1)
				local hue = frac * 0.82 + b.j * 0.028 + (if pl.main then 0 else 0.06) + t * 0.12
				local col = Color3.new(1, 1, 1):Lerp(rainbow(hue, 0.88, 0.5 + 0.38 * row), hot)
				local studCol = Color3.new(1, 1, 1):Lerp(rainbow(hue + 0.02, 0.82, 0.92), hot)
				local tr = 0
				local scale = 1
				local ct = crumbleT - (b.hc - 1 - b.j) * 0.05
				if ct > 0 then
					local g = ct
					local fall = 0.5 * 52 * g * g
					cf = CFrame.new(cf.Position + b.drift * g - Vector3.new(0, fall, 0))
						* (cf - cf.Position) * CFrame.Angles(b.spin.X * g, b.spin.Y * g, b.spin.Z * g)
					if cf.Position.Y < ground.Y - 1 then
						cf = cf + Vector3.new(0, ground.Y - 1 - cf.Position.Y, 0)
					end
					scale = math.max(0.05, 1 - g / 0.9)
					tr = smooth(g / 0.9)
					col = col:Lerp(Color3.fromRGB(40, 36, 44), smooth(g / 0.5))
					studCol = col
				end
				b.p.Size = b.size * scale
				b.p.CFrame = cf
				b.p.Color = col
				b.p.Transparency = tr
				for _, st in b.studs do
					st.p.Size = Vector3.new(V * 0.16, V * 0.3, V * 0.3) * scale
					st.p.CFrame = cf * CFrame.new(st.off.Position * scale) * (st.off - st.off.Position)
					st.p.Color = studCol
					st.p.Transparency = tr
				end
			end
			-- debris (ballistic from emergence, rests on the ground, fades)
			local dtau = t - pl.ts
			for i, d in pl.debris do
				if dtau > 1.7 then
					d.p.CFrame = HIDE
				else
					local p = d.p0 + d.v * dtau - Vector3.new(0, 0.5 * 60 * dtau * dtau, 0)
					local landed = p.Y < ground.Y + 0.3
					if landed then
						p = Vector3.new(p.X, ground.Y + 0.3, p.Z)
					end
					d.p.CFrame = CFrame.new(p) * CFrame.Angles(d.w.X * dtau, d.w.Y * dtau, d.w.Z * dtau)
					d.p.Color = if i % 2 == 0 then Color3.fromRGB(46, 40, 50) else rainbow(frac * 0.82 + i * 0.07 + t * 0.12, 0.8, 0.95)
					d.p.Transparency = smooth((dtau - 1.1) / 0.6)
				end
			end
		end
	end

	table.insert(ctx.cleanups, finish)
	return step
end

-- camera shake offset for the harness camera (pure function of effect time)
function EarthRise.shake(t: number): Vector3
	local a = 0
	a += 0.55 * math.exp(-(t - 0.62) * 9) * (if t >= 0.62 then 1 else 0)
	if t >= 0.66 and t < 1.6 then
		a += 0.32
	end
	a += 0.25 * math.exp(-(t - 3.0) * 4) * (if t >= 3.0 then 1 else 0)
	a = math.min(a, 0.7)
	return Vector3.new(math.sin(t * 91) * a, math.sin(t * 77 + 1.3) * a * 0.7, math.sin(t * 63 + 2.1) * a * 0.5)
end

return EarthRise
