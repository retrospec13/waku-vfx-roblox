--!strict
-- Copy into wakuVFX.Effects and register as described in docs/NEW_EFFECT.md.
local Kit = require(script.Parent.Parent.Kit)
local PulseOrb = { life = 1.2, required = {} }
function PulseOrb.build(ctx: Kit.Ctx): (number) -> ()
	local sphere = Kit.part(ctx, ctx.root, "Pulse", Vector3.one, Kit.col(0.55), Enum.Material.Neon)
	sphere.Shape = Enum.PartType.Ball
	sphere.CFrame = ctx.cf
	return function(t: number)
		local u = math.clamp(t / PulseOrb.life, 0, 1)
		sphere.Size = Vector3.one * (1 + 5 * u) * ctx.opts.scale
		sphere.Transparency = u
		sphere.Color = Kit.col(Kit.hue(ctx, t, 0))
	end
end
return PulseOrb
