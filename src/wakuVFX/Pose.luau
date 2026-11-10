--!strict
--[[ wakuVFX Pose: procedural R15 posing for effects. Poses a client-local clone of the caster that has no Animator
	(the Humanoid's Animator would reset Joint.Transform every frame), so no animation asset is needed.
	- An NPC original is unparented locally for the duration.
	- A player's character stays in place, so the camera and controls keep working, but it is hidden and anchored
	  locally.
	Everything is restored by the cleanup registered on the effect context. Works with Motor6D and AnimationConstraint
	rigs; AnimationConstraints are set kinematic so Transform is exact.

	  local rig = Pose.rig(ctx, caster)          -- nil when there is no caster
	  rig.apply(Pose.sample(KEYS, t))            -- KEYS = { { t = 0.1, p = { RightShoulder = Pose.arm(80, 40, 0), ... } }, ... }
	  rig.move(CFrame)                            -- move the clone's root (dashes); joints follow
	  rig.fade(0..1)                              -- fade the clone out (1 = invisible) ]]
local CasterState = require(script.Parent.CasterState)
local Kit = require(script.Parent.Kit)

local Pose = {}

local R = math.rad
function Pose.A(x: number, y: number, z: number): CFrame
	return CFrame.Angles(R(x), R(y), R(z))
end
-- yaw after pitch: raise the arm forward first, then swing it inward (mirror yaw/roll for the left arm)
function Pose.arm(pitch: number, yaw: number, roll: number): CFrame
	return CFrame.Angles(0, R(yaw), 0) * CFrame.Angles(R(pitch), 0, 0) * CFrame.Angles(0, 0, R(roll))
end

Pose.JOINTS = { "Root", "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist",
	"LeftWrist", "RightHip", "LeftHip", "RightKnee", "LeftKnee", "RightAnkle", "LeftAnkle" }

export type Key = { t: number, p: { [string]: CFrame } }
-- smooth interpolation between keyframes (missing joints = identity)
function Pose.sample(keys: { Key }, t: number): { [string]: CFrame }
	local out = {}
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b.t or i == #keys - 1 then
			local u = Kit.smooth((t - a.t) / math.max(b.t - a.t, 1e-3))
			for _, j in Pose.JOINTS do
				out[j] = (a.p[j] or CFrame.identity):Lerp(b.p[j] or CFrame.identity, u)
			end
			return out
		end
	end
	return out
end

export type Rig = { clone: Model, root: BasePart?, root0: CFrame?, apply: ({ [string]: CFrame }) -> (), move: (CFrame) -> (), fade: (number) -> () }

function Pose.rig(ctx: Kit.Ctx, caster: Model?): Rig?
	if not caster then
		return nil
	end
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
	local cr = clone:FindFirstChild("HumanoidRootPart")
	local cloneRoot: BasePart? = if cr and cr:IsA("BasePart") then cr else nil
	if cloneRoot then
		cloneRoot.Anchored = true
	end
	clone.Name = "CasterPose"
	clone.Parent = ctx.root

	local motors: { [string]: any } = {}
	for _, d in clone:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		elseif d:IsA("AnimationConstraint") then
			(d :: any).IsKinematic = true
			motors[d.Name] = d
		end
	end
	local base: { [BasePart]: number } = {}
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") and d ~= cloneRoot then
			base[d] = d.Transparency
		end
	end

	table.insert(ctx.cleanups, function()
		for _, m in motors do
			m.Transform = CFrame.identity
		end

	end)

	return {
		clone = clone,
		root = cloneRoot,
		root0 = if cloneRoot then cloneRoot.CFrame else nil,
		apply = function(pose: { [string]: CFrame })
			for name, m in motors do
				local cf = pose[name]
				if cf then
					m.Transform = cf
				end
			end
		end,
		move = function(cf: CFrame)
			if cloneRoot then
				cloneRoot.CFrame = cf
			end
		end,
		fade = function(a: number)
			for p, tr in base do
				p.Transparency = tr + (1 - tr) * math.clamp(a, 0, 1)
			end
		end,
	}
end

return Pose
