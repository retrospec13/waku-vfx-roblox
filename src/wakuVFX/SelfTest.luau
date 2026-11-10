--!strict
--[[ wakuVFX SelfTest (client, in Play). For every effect it checks:
	  assets    every required texture id is set and ContentProvider fetches it (retries while a fresh upload is
	            still processing, up to 45 s; a real failure stays FAIL)
	  creation  the effect builds, draws its layers (parts, beams, emitters, decals) and records no blank ids
	  rainbow   at mid-life the visible colours span at least 4 of 12 hue buckets
	  playback  it plays without step errors and ends at its documented life (+-0.15 s of effect time)
	  cleanup   1 s after the end: its Model is gone, workspace.wakuVFX is empty, the scheduler is disconnected,
	            no scene grade is left in Lighting, and a posed caster is restored (back in place, joints reset)
	usage: waku.SelfTest.run(waku, { places = { [name] = CFrame }, casters = { [name] = model }?, log = print? }) -> (pass, fail) ]]
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SelfTest = {}

export type RunOpts = { places: { [string]: CFrame }?, casters: { [string]: Model? }?, log: ((string) -> ())?, only: { string }? }

local function waitEffect(waku: any, t: number)
	local deadline = os.clock() + math.max(t, 0) + 10
	local t0 = waku.now()
	while waku.now() - t0 < t do
		assert(os.clock() < deadline, "SelfTest effect clock stalled; use timeScale=1")
		RunService.Heartbeat:Wait()
	end
end

local function hueBuckets(root: Instance): number
	local seen: { [number]: boolean } = {}
	local function add(c: Color3)
		local h, s, v = c:ToHSV()
		if s > 0.3 and v > 0.25 then
			seen[math.floor(h * 12) % 12] = true
		end
	end
	for _, d in root:GetDescendants() do
		if d:IsA("Beam") and d.Enabled then
			for _, k in d.Color.Keypoints do
				add(k.Value)
			end
		elseif d:IsA("BasePart") and d.Transparency < 0.95 and d.CFrame.Y > -400 then
			add(d.Color)
		elseif d:IsA("Decal") and d.Transparency < 0.95 then
			add(d.Color3)
		end
	end
	local n = 0
	for _ in seen do
		n += 1
	end
	return n
end

function SelfTest.run(waku: any, o: RunOpts?): (number, number)
	assert(waku.timeScale == nil or waku.timeScale == 1, "SelfTest requires timeScale=nil or 1")
	local opts: RunOpts = o or {}
	local log: (string) -> () = opts.log or (print :: any)
	local pass, fail = 0, 0
	local function check(ok: boolean, name: string, what: string, detail: string)
		if ok then
			pass += 1
		else
			fail += 1
		end
		log(string.format("[wakuVFX SelfTest] %s %s %s: %s", if ok then "PASS" else "FAIL", name, what, detail))
	end

	-- assets: fetch every id once (shared by the effects), retrying while Roblox still processes a fresh upload
	local status: { [string]: string } = {}
	local pending: { [string]: boolean } = {}
	for key, id in waku.Assets do
		if id ~= "" then
			pending[key] = true
		end
	end
	local deadline = os.clock() + 45
	while next(pending) and os.clock() < deadline do
		local list: { Instance } = {}
		local byId: { [string]: string } = {}
		for key in pending do
			local d = Instance.new("Decal")
			d.Texture = waku.Assets[key]
			byId[waku.Assets[key]] = key
			table.insert(list, d)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list, function(contentId: string, st: Enum.AssetFetchStatus)
				local key = byId[contentId]
				if key then
					status[key] = st.Name
					if st == Enum.AssetFetchStatus.Success then
						pending[key] = nil
					end
				end
			end)
		end)
		for _, d in list do
			d:Destroy()
		end
		if next(pending) then
			task.wait(3)
		end
	end

	local order: { string } = opts.only or waku.Order
	for _, name in order do
		local spec = waku.Effects[name]
		-- assets
		local bad = {}
		for _, key in spec.required do
			local id = waku.Assets[key]
			if id == nil or id == "" then
				table.insert(bad, key .. "=blank")
			elseif status[key] ~= "Success" then
				table.insert(bad, key .. "=" .. tostring(status[key]))
			end
		end
		check(#bad == 0, name, "assets", if #bad == 0 then string.format("%d/%d textures fetched", #spec.required, #spec.required) else table.concat(bad, ", "))

		-- creation
		local missingBefore: { [string]: number } = table.clone(waku.Missing)
		local errBefore = #waku.Errors
		local cf = (opts.places and opts.places[name]) or CFrame.new(0, 3, 0)
		local caster = if opts.casters then opts.casters[name] else nil
		local casterParent = caster and caster.Parent
		local transparency: { [Instance]: number } = {}
		local anchored: { [BasePart]: boolean } = {}
		if caster then
			for _, d in caster:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					transparency[d] = (d :: any).Transparency
				end
				if d:IsA("BasePart") then anchored[d] = d.Anchored end
			end
		end
		local tStart = waku.now()
		local h = waku.play(name, cf, { caster = caster })
		RunService.Heartbeat:Wait()
		local nParts, nBeams, nEmit, nDecal = 0, 0, 0, 0
		if h then
			for _, d in h.root:GetDescendants() do
				if d:IsA("BasePart") then
					nParts += 1
				elseif d:IsA("Beam") then
					nBeams += 1
				elseif d:IsA("ParticleEmitter") then
					nEmit += 1
				elseif d:IsA("Decal") then
					nDecal += 1
				end
			end
		end
		local newMissing = {}
		for k, v in waku.Missing do
			if v > (missingBefore[k] or 0) then
				table.insert(newMissing, k)
			end
		end
		check(h ~= nil and nParts > 0 and nEmit > 0 and #newMissing == 0, name, "creation",
			string.format("parts=%d beams=%d emitters=%d decals=%d blankIds=[%s]", nParts, nBeams, nEmit, nDecal, table.concat(newMissing, ",")))
		if not h then
			continue
		end

		-- rainbow, sampled at mid-life (EarthRise: when the pillars stand)
		local mid = if name == "EarthRise" then 1.6 else spec.life * 0.3
		waitEffect(waku, mid - (waku.now() - tStart))
		local nb = hueBuckets(h.root)
		check(nb >= 4, name, "rainbow", string.format("%d/12 hue buckets visible at t=%.2f s", nb, waku.now() - tStart))

		-- playback
		local playbackDeadline = os.clock() + spec.life + 10
		while h.alive() and os.clock() < playbackDeadline do
			RunService.Heartbeat:Wait()
		end
		local timedOut = h.alive()
		if timedOut then h.stop() end
		local ended = waku.now() - tStart
		local errs = #waku.Errors - errBefore
		check(not timedOut and math.abs(ended - spec.life) <= 0.15 and errs == 0, name, "playback",
			string.format("life %.2f s, ended at %.3f s, step errors %d", spec.life, ended, errs))

		-- cleanup
		task.wait(1)
		local grades = 0
		for _, x in game:GetService("Lighting"):GetChildren() do
			if string.sub(x.Name, 1, 13) == "wakuVFX_Grade" then
				grades += 1
			end
		end
		local folder = Workspace:FindFirstChild("wakuVFX")
		local left = if folder then #folder:GetChildren() else 0
		local casterOk = true
		local posed = 0
		local jointsNote = ""
		if caster then
			casterOk = caster.Parent == casterParent
			-- a player character's own Animator (idle tracks) writes Transform every frame, so identity joints can
			-- only be required of casters with no playing tracks; the effect only ever poses its own clone
			local an = caster:FindFirstChildWhichIsA("Animator", true)
			local tracks = if an then #an:GetPlayingAnimationTracks() else 0
			if tracks > 0 then
				jointsNote = string.format(" (n/a: caster animated by its own Animator, %d tracks)", tracks)
			else
				for _, d in caster:GetDescendants() do
					if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and (d :: any).Transform ~= CFrame.identity then
						posed += 1
					end
				end
			end
			for d, tr in transparency do
				if d.Parent == nil or (d :: any).Transparency ~= tr then casterOk = false end
			end
			for d, value in anchored do
				if d.Parent == nil or d.Anchored ~= value then casterOk = false end
			end
		end
		check(h.root.Parent == nil and left == 0 and waku.activeCount() == 0 and not waku.connected() and casterOk and posed == 0 and grades == 0,
			name, "cleanup", string.format("model gone=%s, wakuVFX children=%d, active=%d, connected=%s, caster restored=%s, joints posed=%d%s, scene grades left=%d",
				tostring(h.root.Parent == nil), left, waku.activeCount(), tostring(waku.connected()), tostring(casterOk), posed, jointsNote, grades))
	end
	log(string.format("[wakuVFX SelfTest] DONE pass=%d fail=%d", pass, fail))
	return pass, fail
end

return SelfTest
