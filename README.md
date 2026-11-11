# waku-vfx-roblox

**[Set 3: five over-the-top effects](docs/SET-3.md)** · [Set 3 full trailer](media/set-3-trailer.mp4) · **[Set 2: five new effects, SFX and setup](docs/SET-2.md)** · [Set 1 trailer](media/wakuVFX_trailer.mp4)

[![Set 3: five effects in five seconds](media/set-3-preview.gif)](docs/SET-3.md)

[![Set 2 preview](media/set-2-preview.gif)](docs/SET-2.md)

[![Five-second preview: lightning strikes and rising rainbow bricks](media/vfx-preview.gif)](media/wakuVFX_trailer.mp4)

**[Watch the trailer](media/wakuVFX_trailer.mp4)** · [Download the MP4](media/wakuVFX_trailer.mp4?raw=true)

Fourteen editable, client-side Roblox combat effects from **Waku Worldwide**. Built from parts, beams, particles and procedural R15 poses, with no mesh or animation uploads required. GitHub may offer the trailer as a download rather than an inline player.

| Effect | Motion |
|---|---|
| **PrismCleave** | Starburst charge, rainbow rings and a dash-slash |
| **CrystalBloom** | Crystal swirl, star bloom, white-out and shatter |
| **StormLance** | Charged stab and three rainbow lightning pillars |
| **EarthRise** | Clap, ground slam, rising voxel pillars and crumble |
| **ChargeAura** | 0.6 s charge-up, ignition, then a looping body aura with rising sparks, ground ring and flickering core; holds until `handle.stop()` (3 s if left alone) |
| **HitBurst** | 0.3 s basic-attack hit: contact flash, spikes, tight shock ring, sparks. Pass `seed` per hit to vary a combo |
| **ChargeBeam** | 0.45 s gather in the hands, then a 0.6 s thick beam with core, sheath, spiral strands, muzzle flare and end burst |
| **GhostDash** | Five sharp afterimages of the caster's real pose plus a short speed trail. Visuals only: your game moves the character |
| **ImpactFlash** | Two-frame black/white then inverted impact frame (0.07 s), then colour slams back with a shockwave |
| **QuakeSlam** | A falling comet, white-out ground slam, light pillar, a star of glowing cracks, black lightning and thrown rock |
| **BlinkStep** | The caster vanishes into a seam of light and returns under a lightning pillar. Visuals only: your game moves the character |
| **RiftGate** | A standing portal burned into the air, with a swirling interior; holds until `handle.stop()` folds it shut (4.7 s if left alone) |
| **WardShell** | A lattice guard bubble that follows the caster, takes two hits, cracks and shatters; `handle.stop()` bursts it early (3.4 s if left alone) |
| **Fireball** | Charge flare, a house-sized fireball with a flame tail and a fire-dome explosion. `rainbow = false, hue = 0.03` gives plain orange fire |

## Included

- All fourteen effect modules, shared runtime, R15 pose code and demo controls.
- `wakuVFX_demo.rbxlx`, plus demo and library-only Rojo projects.
- All **16 PNG textures**, their manifest and editable Python generator.
- [A runnable new-effect walkthrough](docs/NEW_EFFECT.md), optional assistant skill and [test instructions](TESTS.md).
- The Set 1, Set 2 and Set 3 trailers and preview GIFs.
- Set 2 ElevenLabs SFX in `audio/`, plus optional `Sounds.luau` playback and demo integration. See [Set 2 audio setup](docs/SET-2.md#elevenlabs-sfx-and-playback).
- Set 3 ElevenLabs source takes (`audio/raw/s3_*.mp3`) and prepared clips (`audio/mix/s3_*.mp3`); see [Set 3](docs/SET-3.md#sfx).
- The optional capture and trailer scripts are described in [docs/PIPELINE.md](docs/PIPELINE.md). The three AI trailer clips are included under `trailer/hf/`. The Studio source captures are not included, so the scripts cannot rebuild the supplied trailer from this repository alone.

## Quick start

1. Open `wakuVFX_demo.rbxlx` in Roblox Studio.
2. **Upload your own copies of the included textures and replace the IDs**, as below.
3. Use an R15 avatar, press **Play**, then **1 / 2 / 3 / 4**. Gamepad: X / Y / B / A. Touch: on-screen buttons. Keys **5 to 9** play ChargeAura (press again to drop it), HitBurst, ChargeBeam, GhostDash and ImpactFlash. Keys **Z X C V B** play QuakeSlam, BlinkStep, RiftGate, WardShell and Fireball (press C or V again to close the gate or burst the shell).

To use the kit in an existing game, copy **the `ReplicatedStorage.wakuVFX` ModuleScript with all its children** from the demo. It is not a plain Folder. Call it from a LocalScript:

```lua
local Players = game:GetService("Players")
local waku = require(game.ReplicatedStorage.wakuVFX)
local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")
local handle = waku.play("PrismCleave", hrp.CFrame, { caster = character })
-- To cancel later (do not stop immediately after play):
-- if handle then handle.stop() end
-- Alternative: waku.play("StormLance", hrp.CFrame, { caster = character })
-- EarthRise expects a ground CFrame facing the eruption direction.
```

One active pose or BlinkStep hide owns each caster. An overlapping call that needs that same lock returns `nil`, warns and records a build error; it does not interrupt the first. Stop the first handle or wait until `handle.alive()` is false before starting the next. Different casters can run concurrently. CrystalBloom does not pose a caster.

These are visuals, not damage, authoritative movement or replication. PrismCleave moves a clone; the real character returns in place. Implement server-validated gameplay and client effect dispatch in your own game.

### Options, without changing the art

| Effect | `scale` | `rainbow` / `hue` | `caster` | `grade=false` |
|---|---|---|---|---|
| PrismCleave | Authored size scaling | Base palette controls | R15 pose | Not used |
| CrystalBloom | Authored size scaling | Base palette controls | Not used | Disables scene tint |
| StormLance | Authored size scaling | Base palette controls | R15 pose | Disables scene tint |
| EarthRise | Ignored | Ignored; always rainbow | R15 pose | Not used |
| ChargeAura | Authored size scaling | Base palette controls | Followed, not posed | Not used |
| HitBurst | Authored size scaling | Base palette controls | Not used | Not used |
| ChargeBeam | Authored size scaling | Base palette controls | R15 pose | Not used |
| GhostDash | Authored size scaling | Base palette controls | Copied for afterimages, not posed | Not used |
| ImpactFlash | Authored size scaling | Base palette controls | Silhouetted, not posed | Skips the black/white frames |
| QuakeSlam | Authored size scaling | Base palette controls | Not used | Not used |
| BlinkStep | Authored size scaling | Base palette controls | Hidden for the gap, not posed | Not used |
| RiftGate | Authored size scaling | Base palette controls | Not used | Not used |
| WardShell | Authored size scaling | Base palette controls | Followed, not posed | Not used |
| Fireball | Authored size scaling | `rainbow=false` gives single-hue fire | Not used | Not used |

`cf` conventions and options for Set 3 are in [docs/SET-3.md](docs/SET-3.md#calling-them). `cf` conventions for the Set 2 five: ChargeAura takes the caster's root CFrame; HitBurst and ImpactFlash take the contact point with LookVector along the blow; ChargeBeam and GhostDash take the caster's root CFrame facing the shot or dash. ChargeBeam raycasts up to 70 studs and ends on what it hits. ImpactFlash's two frame grades are tunable in `ImpactFlash.FRAME1` / `FRAME2`.

`rainbow=false` stops base-hue time cycling; spatial rainbow offsets remain. `hue=0.55` is a palette offset, **not a uniform fixed colour**. Scaling is authored per effect, not a universal character/world transform. `seed` controls seeded variation (default 7). `waku.timeScale` is nil/1 for normal playback, 0.5 for slow motion, 0 for screenshots. There is no shipped fixed-step capture API.

## Upload your textures and replace IDs

The existing IDs are reference values, not a promise of access in your experience. You upload assets yourself; this repository does not upload or change Roblox permissions.

1. Upload every `textures/*.png` under the user/group that owns your target experience using Studio Asset Manager or Creator Hub.
2. Obtain each uploaded **image content ID**, not a decal/container ID. If Roblox creates a Decal, inspect its `Texture` property to get the image URI.
3. Replace the matching named values in `src/wakuVFX/Assets.luau` with `rbxassetid://YOUR_IMAGE_ID`. The manifest pairs texture keys with PNGs; update its ID records too if maintaining your own copy.
4. **Loose files and the built demo are separate copies.** Rebuild the demo with Rojo (below), or directly edit the `Assets` child ModuleScript inside `ReplicatedStorage.wakuVFX` in Studio and save the place. Editing a loose file does not change an already-open demo.
5. Stop and restart Play after edits. Run the client SelfTest in [TESTS.md](TESTS.md) to check your own IDs and caster restoration.

## Build and author

Studio alone is enough to copy and edit modules. For a reproducible file-based workflow, install the **Rojo 7.7.1 CLI** from [Rojo releases](https://github.com/rojo-rbx/rojo/releases/tag/v7.7.1) and the matching Studio plugin following [Rojo installation](https://rojo.space/docs/v7/getting-started/installation/). Put `rojo` on PATH, then run from this folder:

```sh
rojo --version
rojo build demo.project.json -o wakuVFX_demo.rbxlx
rojo build library.project.json -o wakuVFX_library.rbxlx
```

The library project maps only the wakuVFX ModuleScript and children under ReplicatedStorage, preserving unknown instances; its build is a minimal place, not the demo. Alternatively, `rojo serve library.project.json` and connect using the Studio Rojo plugin at localhost:34872; inspect the proposed sync before accepting. **Do not sync `demo.project.json` into an existing game**: it also owns demo controls, Workspace and Lighting. Use the demo mapping only in a disposable demo place.

Texture generation requires Python **3.11+**, NumPy and Pillow. Tested pins are in `requirements.txt`:

```sh
python -m venv .venv
# macOS/Linux:
. .venv/bin/activate
# Windows PowerShell instead: .venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python tools/gen_textures.py textures
```

The generator reproduces all 16 supplied textures. To make your first visible effect, follow [NEW_EFFECT.md](docs/NEW_EFFECT.md). No assistant is required; `skill/wakuvfx/SKILL.md` is optional.

## License

Code and documentation: **[MIT](LICENSE)**, copyright Waku Worldwide.
Owned generated textures in `textures/`: **[CC BY 4.0](LICENSE-TEXTURES.md)**, attribution **“wakuVFX textures by Waku Worldwide”**. You may modify and commercially reuse those licensed files under their respective terms. Roblox accounts, original hosted assets and group access are not transferred.

Included ElevenLabs sound files: [audio reuse grant](LICENSE-AUDIO.md). The trailers are included for preview, separately from the code, texture and standalone audio grants. See [NOTICE.md](NOTICE.md).
