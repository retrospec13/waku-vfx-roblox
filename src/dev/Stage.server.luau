--!strict
-- wakuVFX dev stage (Studio QA only): neutral dark floor + backdrop per station, R15 dummies for scale and the
-- EarthRise caster, mild bloom. Builds once at server start; no gameplay.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local STATIONS = {
	{ name = "TriSlash", x = -60 },
	{ name = "FrostCrown", x = 0 },
	{ name = "ForkStorm", x = 60 },
}

local stage = Instance.new("Folder")
stage.Name = "Stage"

local function block(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

block("Floor", Vector3.new(240, 2, 120), CFrame.new(0, -1, 0), Color3.fromRGB(62, 66, 78), stage)
for _, s in STATIONS do
	local f = Instance.new("Folder")
	f.Name = s.name
	f.Parent = stage
	-- backdrop behind the caster so the effect reads against a mid-dark wall like the previews
	block("Backdrop", Vector3.new(50, 30, 2), CFrame.new(s.x, 15, 14), Color3.fromRGB(48, 51, 62), f)
	local mark = Instance.new("Part")
	mark.Name = "Origin"
	mark.Anchored = true
	mark.CanCollide = false
	mark.Transparency = 1
	mark.Size = Vector3.one
	mark.CFrame = CFrame.new(s.x, 3, 0)
	mark.Parent = f
end

-- EarthRise station (custom alchemy effect): thick floor so pillars rise out of solid ground, darker backdrop
do
	local f = Instance.new("Folder")
	f.Name = "EarthRise"
	f.Parent = stage
	block("Floor", Vector3.new(120, 12, 70), CFrame.new(0, -6, 115), Color3.fromRGB(58, 60, 70), f)
	block("Backdrop", Vector3.new(90, 40, 2), CFrame.new(4, 20, 138), Color3.fromRGB(36, 38, 50), f)
	block("SideWall", Vector3.new(2, 40, 50), CFrame.new(46, 20, 115), Color3.fromRGB(40, 42, 54), f)
end

-- set 2 (ChargeAura, HitBurst, GhostDash, ChargeBeam, ImpactFlash): one long strip at z = -150 with a wall behind it
-- and a slab for the beam to hit
do
	local f = Instance.new("Folder")
	f.Name = "Set2"
	f.Parent = stage
	block("Floor", Vector3.new(220, 2, 80), CFrame.new(0, -1, -150), Color3.fromRGB(62, 66, 78), f)
	block("Backdrop", Vector3.new(220, 36, 2), CFrame.new(0, 18, -130), Color3.fromRGB(48, 51, 62), f)
	block("BeamWall", Vector3.new(3, 22, 24), CFrame.new(53.5, 11, -150), Color3.fromRGB(74, 78, 92), f)
end

-- set 3 (QuakeSlam, BlinkStep, RiftGate, WardShell, Fireball): a wide strip at z = -300, a tall wall behind it and a
-- slab for the fireball to hit
do
	local f = Instance.new("Folder")
	f.Name = "Set3"
	f.Parent = stage
	block("Floor", Vector3.new(320, 2, 130), CFrame.new(0, -1, -305), Color3.fromRGB(62, 66, 78), f)
	block("Backdrop", Vector3.new(320, 90, 2), CFrame.new(0, 45, -262), Color3.fromRGB(48, 51, 62), f)
	block("FireWall", Vector3.new(3, 30, 40), CFrame.new(113.5, 15, -300), Color3.fromRGB(74, 78, 92), f)
end

local spawn = Instance.new("SpawnLocation")
spawn.Name = "Spawn"
spawn.Anchored = true
spawn.Size = Vector3.new(6, 1, 6)
spawn.CFrame = CFrame.new(0, 0.5, 48)
spawn.Transparency = 1
spawn.CanCollide = true
spawn.Neutral = true
spawn.Parent = stage

stage.Parent = Workspace

-- dim neutral key, bluish ambient, mild bloom for Neon cores
Lighting.ClockTime = 9
Lighting.Brightness = 1.3
Lighting.Ambient = Color3.fromRGB(60, 64, 78)
Lighting.OutdoorAmbient = Color3.fromRGB(85, 90, 105)
Lighting.EnvironmentDiffuseScale = 0.3
Lighting.EnvironmentSpecularScale = 0.2
Lighting.GlobalShadows = true
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.7
bloom.Size = 24
bloom.Threshold = 1.4
bloom.Parent = Lighting
local sky = Instance.new("Sky")
sky.CelestialBodiesShown = false
sky.StarCount = 0
sky.Parent = Lighting

-- dummies (R15 default description). Slash: the caster at the origin facing -Z. Explosions: a bystander beside
-- and behind the blast for scale; the blast centre is 6 studs in front of the origin.
local function dummy(name: string, cf: CFrame, styled: boolean?)
	local desc = Instance.new("HumanoidDescription")
	if styled then
		-- EarthRise caster: pale skin, deep teal tunic, charcoal trousers
		desc.HeadColor = Color3.fromRGB(234, 196, 160)
		desc.LeftArmColor = Color3.fromRGB(28, 120, 128)
		desc.RightArmColor = Color3.fromRGB(28, 120, 128)
		desc.TorsoColor = Color3.fromRGB(22, 96, 104)
		desc.LeftLegColor = Color3.fromRGB(44, 44, 52)
		desc.RightLegColor = Color3.fromRGB(44, 44, 52)
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[wakuVFX dev] dummy failed: " .. tostring(model))
		return
	end
	model.Name = name
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	model.Parent = Workspace
	if root then
		root.Anchored = true
		model:PivotTo(cf)
	end
	model.Parent = stage
end
dummy("Caster_TriSlash", CFrame.new(-60, 3, 0))
dummy("Bystander_FrostCrown", CFrame.new(-7, 3, 3) * CFrame.Angles(0, math.rad(-30), 0))
dummy("Caster_EarthRise", CFrame.new(-16, 3, 112) * CFrame.Angles(0, math.rad(-90), 0), true)
dummy("Bystander_ForkStorm", CFrame.new(53, 3, 3) * CFrame.Angles(0, math.rad(-30), 0))
local function facing(x: number, toX: number): CFrame
	return CFrame.lookAt(Vector3.new(x, 3, -150), Vector3.new(toX, 3, -150))
end
dummy("Caster_Aura", CFrame.new(-70, 3, -150) * CFrame.Angles(0, math.rad(180), 0), true)
dummy("Attacker_Hit", facing(-50, -40))
dummy("Target_Hit", facing(-45, -55))
dummy("Caster_Dash", facing(-25, -10), true)
dummy("Caster_Beam", facing(10, 20), true)
dummy("Caster_Impact", facing(71, 80), true)
dummy("Target_Impact", facing(76, 60))
local function facing3(x: number, z: number, toX: number, toZ: number): CFrame
	return CFrame.lookAt(Vector3.new(x, 3, z), Vector3.new(toX, 3, toZ))
end
dummy("Bystander_Quake", facing3(-121, -294, -105, -300))
dummy("Caster_Blink", facing3(-62, -300, -61, -300), true)
dummy("Bystander_Gate", facing3(-19, -304, -5, -298))
dummy("Caster_Ward", facing3(35, -300, 31, -320), true)
dummy("Caster_Fire", facing3(68, -300, 69, -300), true)
Workspace:SetAttribute("StageReady", true)
print("[wakuVFX dev] stage built")
