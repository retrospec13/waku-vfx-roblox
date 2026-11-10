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
- Use ctx.rng for seeded variation. Animate from effect time t, not frame count.
- Use Kit.part for anchored noncolliding geometry. Keep hot core, rainbow body
  and dark contrast. Register cleanup BEFORE changing anything outside ctx.root.
- Use the keyed casters example in TESTS.md, with timeScale=1 and real R15 rigs.
- timeScale=0 is a screenshot freeze, not a fixed-step API. No capture harness,
  trailer authoring pipeline or dev-harness step command ships with this kit.
- Network gameplay belongs to the recipient. This library is visual only.
