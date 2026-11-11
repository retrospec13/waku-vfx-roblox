# Production pipeline: one script per set

`tools/wakupipe.py <set> <command>` drives the producer's optional process after the effect modules are written: Studio capture, contact
sheets, SFX cutting, the trailer cut and the audio mix. Each set is one manifest, `tools/sets/<set>.json`. A new set
is a new manifest plus the effect modules; nothing else is hand-built.

It needs a Windows capture PC, Rojo, Python with Pillow, numpy and imageio-ffmpeg. Install the pinned
`requirements.txt`, then install `imageio-ffmpeg` for these optional tools. Set
`WAKUVFX_SSH_HOST` (for example `user@host`) and `WAKUVFX_PC_ROOT` (a Windows path with no spaces, using forward
slashes) on the computer running this script. Set `WAKUVFX_SSH_KEY` if the default SSH identity does not work.
These scripts were used on the producer's machine; they have not been tested on a clean machine after the path
changes. The AI camera clips are in `trailer/hf/`, and the raw sound takes are in `audio/raw/`. The Studio capture
frames are not in this repository. You cannot rebuild the supplied trailer from this checkout alone. These
scripts are production tools, not part of the runtime kit.

## Commands

| Command | What it does |
|---|---|
| `up` | Rojo-builds the dev place, checks which Studios are open, copies the place and `tools/pc` to the PC and launches Studio in the console session through a scheduled task. Records its Studio id in `tools/STUDIO_ID` |
| `sync [--wait]` | Hot-syncs every module under `src/wakuVFX` plus the dev Stage and Harness into the running place, presses Play and prints the console |
| `selftest [names]` | Runs `waku.SelfTest` in Studio and prints the result table |
| `look <fx> [cam]` | Fixed-step capture of one effect to a contact sheet, `build/look_<fx>_<cam>.jpg`. `--dt --tstart --tend --stop --opts rainbow=0,hue=0.03 --cols --sync` |
| `looks [fx...]` | Every entry of the manifest's `looks` list |
| `shots [tags...]` | Captures the manifest's trailer shots into `captures/<set>_trl` (re-shooting a tag replaces only that tag) and writes `build/shot_<tag>.jpg` sheets |
| `sfx <takes.json>` | `{name: url-or-path}` to `audio/mix/<name>.mp3` at 0.4 volume, 44.1 kHz |
| `trailer [--dry]` | Cuts the silent trailer from the manifest timeline. `--dry` prints the start time of every shot |
| `mix` | Lays music and cues against those start times, levels each clip by its loudest 400 ms, limits the peak to -2 dBFS and muxes without re-encoding the video |
| `down` | Closes this pipeline's own Studio window and nothing else |

## Manifest

Use the complete [Set 3 manifest](../tools/sets/set3.json) as the working example. `shots` and `looks` are lists,
not maps. Each shot has a `tag`, `fx`, `cam` and optional timing. A `timeline` entry refers to a shot by `tag`.

- A shot steps the effect clock at `speed / 30` s per frame, so `speed: 0.5` is true half-speed slow motion with no
  frame blending. `pre` adds lead-in frames, `stop` calls `handle.stop()` at that effect time.
- Cameras are named in `src/dev/Harness.client.luau`. A new effect needs a camera entry there and a `lives` value.
- `kind` names a shot for the audio cues; `recap` shots are numbered `r0`, `r1`... The `end` entry is padded to
  `total` frames. Cue `at` is a kind or a time in seconds; `until` ends a cue at another shot's start.

## A new set, start to finish

1. Write the effect modules, register them in `init.luau`, add cameras and a manifest.
2. `up`, then `sync --wait` and `selftest`.
3. `looks --sync` after each edit until the sheets look right.
4. `shots`, generate SFX and any AI clips, `sfx takes.json`.
5. Fill `timeline` and `cues`; `trailer --dry`, `trailer`, `mix`.
6. `down`.

The two paid steps (ElevenLabs sound generation and Higgsfield video generation) are deliberately not automated:
each call spends credits, so they are run by hand and their results are handed to `sfx` and the timeline.
