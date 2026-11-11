---
name: wakuvfx
description: Author and integrate client-only wakuVFX effects for Roblox.
---
# wakuVFX

Read README.md for the per-effect options and setup; follow docs/NEW_EFFECT.md
for a complete visible effect and exact registration/test steps.

- Copy the wakuVFX ModuleScript with all children, not a plain folder.
- Upload the local texture PNGs yourself and remap Assets in loose source AND
  rebuild the demo, or edit its embedded Assets ModuleScript directly.
- Pose and EarthRise share a per-caster guard. Stop the previous handle before
  starting another posed move on that caster. Rejected overlap returns nil.
- rainbow=false freezes base hue, not spatial rainbow. EarthRise ignores
  scale/rainbow/hue. Do not silently restyle accepted art to change that.
- ChargeBeam also poses its caster. ChargeAura, GhostDash and ImpactFlash read
  the caster but never pose or modify it. GhostDash does not move anyone.
- QuakeSlam, BlinkStep, RiftGate, WardShell and Fireball never pose or lock the
  caster. BlinkStep hides it for the gap (CasterState) and needs opts.to or the
  game to move the root; it moves nobody itself.
- Long-lived effects with a closing animation set ctx.outro in build and read
  ctx.stopAt in update: handle.stop() then plays the close (RiftGate, WardShell).
- Use Kit.seq(ctx, ...) instead of Kit.hueSeq for any gradient that should turn
  single-hue when rainbow=false (Fireball does this throughout).
- Kit.plate (flat card at any angle), Kit.sprite (camera-facing card) and
  Kit.rightTo (beam curve handles) cover most new layers without new parts.
- Emit each ParticleEmitter once per frame: several Emit(1) calls with the host
  moved in between all take the last host CFrame. Use spread, or two emitters.
- spark_streak is drawn sideways: with vpar = true also pass rot = { 90 }.
- Use ctx.rng for seeded variation. Animate from effect time t, not frame count.
- Use Kit.part for anchored noncolliding geometry. Keep hot core, rainbow body
  and dark contrast. Register cleanup BEFORE changing anything outside ctx.root.
- Use the keyed casters example in TESTS.md, with timeScale=1 and real R15 rigs.
- timeScale=0 is a screenshot freeze, not a fixed-step API. The owner's capture
  and trailer pipeline (tools/wakupipe.py, docs/PIPELINE.md) is separate from
  the runtime and needs the Windows capture PC.
- Network gameplay belongs to the recipient. This library is visual only.
