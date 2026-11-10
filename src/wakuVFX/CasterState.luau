--!strict
-- One pose owner per original caster, shared by Pose and EarthRise.
-- A second posed effect fails cleanly instead of snapshotting an already hidden rig.
local Players = game:GetService("Players")
local CasterState = {}
local owners: { [Model]: any } = {}

function CasterState.clone(ctx: any, caster: Model): Model
	if owners[caster] then
		error("caster already has an active pose; stop the previous handle first")
	end
	local token = {}
	owners[caster] = token
	local parent = caster.Parent
	local archivable = caster.Archivable
	local isPlayer = Players:GetPlayerFromCharacter(caster) ~= nil
	local hidden: { [Instance]: number } = {}
	local hrp = caster:FindFirstChild("HumanoidRootPart")
	local root: BasePart? = if hrp and hrp:IsA("BasePart") then hrp else nil
	local anchored = if root then root.Anchored else false
	local changedParent = false
	local changedAnchor = false
	-- Register restoration before cloning or changing any external state.
	table.insert(ctx.cleanups, function()
		if owners[caster] ~= token then
			return
		end
		owners[caster] = nil
		caster.Archivable = archivable
		if changedParent then
			caster.Parent = parent
		end
		for d, tr in hidden do
			if d.Parent then
				(d :: any).Transparency = tr
			end
		end
		if root and changedAnchor then
			root.Anchored = anchored
		end
	end)
	caster.Archivable = true
	local clone = caster:Clone()
	caster.Archivable = archivable
	assert(clone, "caster could not be cloned")
	clone.Parent = ctx.root
	if isPlayer then
		for _, d in caster:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				local visual = d :: any
				hidden[d] = visual.Transparency
				visual.Transparency = 1
			end
		end
		if root then
			changedAnchor = true
			root.Anchored = true
		end
	else
		changedParent = true
		caster.Parent = nil
	end
	return clone
end

return CasterState
