--!strict
-- Optional Set 2 audio. Upload audio/mix/s2_*.mp3 under your experience owner,
-- grant the experience access, then fill these IDs. Blank entries stay silent.
local Debris = game:GetService("Debris")
local Sounds = {}
Sounds.IDs = {
	ChargeAura = "", -- s2_aura.mp3
	HitBurst = "", -- s2_hit.mp3
	ChargeBeam = "", -- s2_beam.mp3 (plays after the 0.45 s charge)
	GhostDash = "", -- s2_dash.mp3
	ImpactFlash = "", -- s2_impact.mp3
}

-- parent: a BasePart or Attachment for spatial sound. The effect handle cancels
-- pending beam audio if the effect is stopped before the beam fires.
function Sounds.play(name: string, parent: Instance, handle: any): Sound?
	local id = (Sounds.IDs :: { [string]: string })[name]
	if not id or id == "" then return nil end
	local sound = Instance.new("Sound")
	sound.Name = "waku_" .. name
	sound.SoundId = id
	sound.Volume = 0.65
	sound.RollOffMaxDistance = 80
	sound.Parent = parent
	Debris:AddItem(sound, 10)
	sound.Ended:Once(function() sound:Destroy() end)
	if name == "ChargeBeam" then
		task.delay(0.45, function()
			if sound.Parent and (not handle or handle.alive()) then
				sound:Play()
			else
				sound:Destroy()
			end
		end)
	else
		sound:Play()
	end
	return sound
end
return Sounds
