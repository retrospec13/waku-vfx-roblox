--!strict
-- One pose owner per original caster, shared by Pose, EarthRise and BlinkStep.
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

-- Hide a caster in place for part of an effect (BlinkStep): no clone, no anchoring, no reparenting, so the game can
-- keep moving the character. Takes the same one-owner lock as clone(); returns hide() and restore(). restore() also
-- runs from the effect's cleanup, so a stopped or failed effect never leaves the caster invisible.
function CasterState.hider(ctx: any, caster: Model): (() -> (), () -> ())
	if owners[caster] then
		error("caster already has an active pose; stop the previous handle first")
	end
	local token = {}
	owners[caster] = token
	local hidden: { [Instance]: number } = {}
	local released = false
	local function show()
		for d, tr in hidden do
			if d.Parent then
				(d :: any).Transparency = tr
			end
		end
		table.clear(hidden)
	end
	local function restore()
		show()
		if not released then
			released = true
			if owners[caster] == token then
				owners[caster] = nil
			end
		end
	end
	table.insert(ctx.cleanups, restore)
	local function hide()
		if released or next(hidden) ~= nil then
			return
		end
		for _, d in caster:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				hidden[d] = (d :: any).Transparency;
				(d :: any).Transparency = 1
			end
		end
	end
	return hide, restore
end

return CasterState
