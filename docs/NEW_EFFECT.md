# Your first effect: PulseOrb

This optional exercise leaves the four shipped effects unchanged. It needs no
texture upload: it draws a neon sphere. The complete source is
`examples/PulseOrb.luau`.

1. Copy `examples/PulseOrb.luau` to `src/wakuVFX/Effects/PulseOrb.luau`.
   In Studio instead, create a **ModuleScript** named `PulseOrb` inside the
   library's `Effects` folder and paste the example source.
2. Register it in `src/wakuVFX/init.luau` (the top-level ModuleScript in Studio).
   Add to the `waku.Effects` table:
   ```lua
   PulseOrb = require(script.Effects.PulseOrb) :: Spec,
   ```
   Append `"PulseOrb"` to `waku.Order`. Rebuild the demo with
   `rojo build demo.project.json -o wakuVFX_demo.rbxlx`, reopen it and restart Play.
3. Put this LocalScript in StarterPlayerScripts in a disposable test place:
   ```lua
   local Players = game:GetService("Players")
   local waku = require(game.ReplicatedStorage.wakuVFX)
   local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
   local hrp = character:WaitForChild("HumanoidRootPart")
   waku.clear()
   waku.timeScale = 1
   local before = #waku.Errors
   local cf = hrp.CFrame * CFrame.new(0, 1, -6)
   local h = assert(waku.play("PulseOrb", cf))
   local sphere = h.root:FindFirstChild("Pulse")
   assert(sphere and sphere.Transparency < 1)
   task.wait(0.4) -- Watch the expanding, fading sphere in front of you.
   assert(h.alive() and sphere.Size.X > 1)
   task.wait(1.1)
   assert(not h.alive() and h.root.Parent == nil)
   assert(#waku.Errors == before)
   local cancelled = assert(waku.play("PulseOrb", cf))
   cancelled.stop()
   assert(not cancelled.alive() and cancelled.root.Parent == nil)
   print("PulseOrb creation, growth, natural cleanup and cancellation passed")
   ```

Change the lifetime, size multiplier or palette in the example, rebuild and
repeat. Register external-state cleanup before mutating a caster or Lighting.
Geometry parented under `ctx.root` is destroyed automatically, including on an
initial update error. The general SelfTest expects a multi-hue particle effect;
this intentionally tiny single-sphere tutorial uses the targeted test above,
not that suite's rainbow/emitter acceptance rules. Remove PulseOrb from
`waku.Order` when running the standard four-effect SelfTest, or pass
`only={"PrismCleave","CrystalBloom","StormLance","EarthRise"}`.

The offline regression executes the same example with mocks to check its
lifecycle. Seeing it render in Studio remains a recipient integration check.
