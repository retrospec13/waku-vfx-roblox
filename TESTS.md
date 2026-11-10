# Verification and recipient tests

## Local checks

Run `python tests/run_regressions.py` with Python 3.11+ and the Luau CLI on PATH.
The harness bundles the actual modules unchanged into a Luau script and runs
explicit data-model mocks. It is logic coverage, NOT Roblox rendering, physics,
asset fetching or a substitute for Studio. The release fixer also rebuilds the
demo/library, compiles sources, regenerates all 16 textures, compares embedded
scripts and checks archive extraction/checksums.

## Studio check (recipient-owned textures)

In a fresh disposable Play session, run this from a LocalScript. Do not trigger
the demo buttons while the sequential suite is running:

```lua
local Players = game:GetService("Players")
local waku = require(game.ReplicatedStorage.wakuVFX)
local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local ground = CFrame.new(root.Position - Vector3.new(0, 3, 0))
waku.clear()
waku.timeScale = 1
local pass, fail = waku.SelfTest.run(waku, {
    places = {
        PrismCleave = root.CFrame,
        CrystalBloom = ground,
        StormLance = ground,
        EarthRise = ground * root.CFrame.Rotation,
    },
    casters = {
        PrismCleave = character,
        StormLance = character,
        EarthRise = character,
    },
})
assert(fail == 0, "Inspect SelfTest output")
```

An R15 NPC can replace `character`. `casters` must be keyed by effect name;
`caster=npc` at the top level is not a supported SelfTest option. Five checks
per standard effect cover assets, creation, rainbow, playback and cleanup.
Cleanup compares original part/decal transparency and anchoring, as well as
parenting, joints, scheduler and scene grades. The registry now contains nine effects. Add Set 2 contact/root CFrames to
`places` and caster entries for ChargeAura, ChargeBeam, GhostDash and
ImpactFlash when testing character-specific behavior. Frozen/slowed clocks
are rejected; playback and effect-clock waits have wall-clock guards.

Also try two same-caster posed calls (second must return nil), stop the first,
then start EarthRise successfully. Repeat EarthRise then PrismCleave. Verify
visible body/decal transparency, NPC parenting and original anchoring after
cancellation and natural completion. In an isolated custom effect, register a
cleanup then throw at t=0: play must return nil and leave no model or pose lock.
The offline regression covers these paths with mocks; perform engine checks
in your own experience when integrating.

## Set 2 packaging checks

The combined kit passes 25 mock logic regressions, including the natural
lifecycle of all nine effects. The mocks now provide the Roblox `workspace`
alias and `OverlapParams` constructor used by Set 2. These are not engine
render checks. The optional sound helper needs uploaded IDs before playback;
blank IDs deliberately produce no sound.

## Limits

The original producer reported successful Studio runs for the older package.
They were not rerun on this corrected candidate. This release preparation did
not use Windows or Studio, upload assets, change permissions or test hosted-ID
access. Existing IDs are not guaranteed: upload the included PNGs yourself.
No mobile/console performance, engine visual or multiplayer proof is claimed.
PrismCleave moves only its local clone. Scene tint is optional for StormLance
and CrystalBloom. See README for accurate palette and scale behavior.
