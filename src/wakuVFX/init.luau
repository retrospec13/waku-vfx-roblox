--!strict
--[[
	wakuVFX: rainbow combat VFX for Roblox (client only).

	  local waku = require(ReplicatedStorage.wakuVFX)
	  waku.play("PrismCleave", hrp.CFrame, { caster = character })      -- charged dash-slash
	  waku.play("CrystalBloom", CFrame.new(groundPos))                     -- ice swirl, crystal star bloom, shatter
	  waku.play("StormLance", CFrame.new(targetPos), { caster = character }) -- stab, three rainbow sky pillars
	  waku.play("EarthRise", CFrame.lookAt(groundPos, groundPos + facing), { caster = character })
	  local aura = waku.play("ChargeAura", hrp.CFrame, { caster = character }) -- holds until aura.stop() (3 s if left)
	  waku.play("HitBurst", CFrame.lookAt(contact, contact + blowDir), { seed = comboIndex }) -- M1 hit, 0.3 s
	  waku.play("ChargeBeam", hrp.CFrame, { caster = character })       -- gather, then a thick beam along LookVector
	  waku.play("GhostDash", hrp.CFrame, { caster = character })        -- afterimages + trail; the game moves the caster
	  waku.play("ImpactFlash", CFrame.lookAt(contact, contact + blowDir), { caster = character }) -- B/W impact frame

	Options vary by effect; see README. Same-caster posed overlap returns nil and records a build error.
	Everything runs on ONE Heartbeat connection and one effect clock (waku.now). waku.timeScale: nil = real time,
	0 = freeze every effect (screenshots only, not fixed-step capture), 0.5 = slow motion. Each effect is a Model under
	workspace.wakuVFX, destroyed at its life end; a failing step cleans its effect up.
	Textures: waku.Assets (ids for the PNGs in textures/). A blank id skips that layer and is recorded in waku.Missing.
]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Kit = require(script.Kit)

local waku = {}
waku.Assets = require(script.Assets) :: { [string]: string }
waku.Missing = Kit.missing
waku.Errors = {} :: { string }
waku.timeScale = nil :: number?

-- effect clock -----------------------------------------------------------------------------------------------
local clockT, clockReal = 0, os.clock()
function waku.now(): number
	local real = os.clock()
	local ts = waku.timeScale
	clockT += (real - clockReal) * (if ts == nil then 1 else math.max(ts, 0))
	clockReal = real
	return clockT
end

-- registry ---------------------------------------------------------------------------------------------------
export type Spec = {
	life: number,
	required: { string },
	build: (ctx: Kit.Ctx) -> (number) -> (),
}
waku.Effects = {
	PrismCleave = require(script.Effects.PrismCleave) :: Spec,
	CrystalBloom = require(script.Effects.CrystalBloom) :: Spec,
	StormLance = require(script.Effects.StormLance) :: Spec,
	EarthRise = require(script.Effects.EarthRise) :: Spec,
	ChargeAura = require(script.Effects.ChargeAura) :: Spec,
	HitBurst = require(script.Effects.HitBurst) :: Spec,
	ChargeBeam = require(script.Effects.ChargeBeam) :: Spec,
	GhostDash = require(script.Effects.GhostDash) :: Spec,
	ImpactFlash = require(script.Effects.ImpactFlash) :: Spec,
}
waku.Order = { "PrismCleave", "CrystalBloom", "StormLance", "EarthRise", "ChargeAura", "HitBurst", "ChargeBeam", "GhostDash", "ImpactFlash" }
waku.SelfTest = require(script.SelfTest)

export type Options = { rainbow: boolean?, hue: number?, scale: number?, caster: Model?, seed: number?, grade: boolean? }
export type Handle = { name: string, root: Model, t0: number, life: number, stop: () -> (), alive: () -> boolean }

type Running = { handle: Handle, ctx: Kit.Ctx, update: (number) -> (), ended: boolean }
local running: { Running } = {}
local conn: RBXScriptConnection? = nil

local function container(): Folder
	local f = Workspace:FindFirstChild("wakuVFX")
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "wakuVFX"
	nf.Parent = Workspace
	return nf
end

local function finish(r: Running)
	if r.ended then
		return
	end
	r.ended = true
	for _, fn in r.ctx.cleanups do
		local ok, err = pcall(fn :: any)
		if not ok then
			local msg = "[wakuVFX] cleanup error in " .. r.handle.name .. ": " .. tostring(err)
			table.insert(waku.Errors, msg)
			warn(msg)
		end
	end
	r.handle.root:Destroy()
end

local function step()
	local now = waku.now()
	local ts = waku.timeScale
	local emitScale = if ts == nil then 1 else math.max(ts, 0)
	for i = #running, 1, -1 do
		local r = running[i]
		if not r.ended then
			local t = now - r.handle.t0
			for _, e in r.ctx.emitters do
				e.TimeScale = emitScale
			end
			if t >= r.handle.life then
				finish(r)
			else
				local ok, err = pcall(r.update :: any, t)
				if not ok then
					local msg = "[wakuVFX] " .. r.handle.name .. " step error: " .. tostring(err)
					table.insert(waku.Errors, msg)
					warn(msg)
					finish(r)
				end
			end
		end
		if r.ended then
			table.remove(running, i)
		end
	end
	if #running == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

function waku.play(name: string, cf: CFrame, opts: Options?): Handle?
	local spec = waku.Effects[name]
	if not spec then
		warn("[wakuVFX] unknown effect " .. tostring(name))
		return nil
	end
	local o: Options = opts or {}
	local root = Instance.new("Model")
	root.Name = name
	local t0 = waku.now()
	local ctx = Kit.newCtx(root, cf, waku.Assets, {
		rainbow = if o.rainbow == nil then true else o.rainbow,
		hue = o.hue or 0,
		scale = o.scale or 1,
		caster = o.caster,
		seed = o.seed or 7,
		grade = o.grade,
	})
	local r: Running
	local handle: Handle = {
		name = name,
		root = root,
		t0 = t0,
		life = spec.life,
		stop = function()
			if r then
				finish(r)
			end
		end,
		alive = function()
			return r ~= nil and not r.ended
		end,
	}
	local ok, upd = pcall(spec.build, ctx)
	if not ok then
		local msg = "[wakuVFX] " .. name .. " build error: " .. tostring(upd)
		table.insert(waku.Errors, msg)
		warn(msg)
		for _, fn in ctx.cleanups do
			pcall(fn)
		end
		root:Destroy()
		return nil
	end
	r = { handle = handle, ctx = ctx, update = upd, ended = false }
	root.Parent = container()
	local ok0, err0 = pcall(upd, 0)
	if not ok0 then
		local msg = "[wakuVFX] " .. name .. " step error: " .. tostring(err0)
		table.insert(waku.Errors, msg)
		warn(msg)
		finish(r)
		return nil
	end
	table.insert(running, r)
	if not conn then
		conn = RunService.Heartbeat:Connect(step)
	end
	return handle
end

function waku.activeCount(): number
	return #running
end

function waku.connected(): boolean
	return conn ~= nil
end

function waku.clear()
	for _, r in running do
		finish(r)
	end
	table.clear(running)
	if conn then
		conn:Disconnect()
		conn = nil
	end
end

-- every texture id the effects use (for ContentProvider:PreloadAsync)
function waku.preload()
	local ContentProvider = game:GetService("ContentProvider")
	local list: { Instance } = {}
	for _, id in waku.Assets do
		if id ~= "" then
			local d = Instance.new("Decal")
			d.Texture = id
			table.insert(list, d)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	for _, d in list do
		d:Destroy()
	end
end

-- shake helper for cameras: EarthRise exposes its own curve; the others a short impact kick
function waku.shake(name: string, t: number): Vector3
	local spec = waku.Effects[name] :: any
	if spec and spec.shake then
		return spec.shake(t)
	end
	return Vector3.zero
end

return waku
