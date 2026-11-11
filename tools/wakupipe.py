#!/usr/bin/env python3
"""wakupipe.py - one script for the whole wakuVFX QA / capture / trailer loop, driven by a set manifest
(tools/sets/<set>.json). Dev tooling only (never shipped with the kit).

  wakupipe.py <set> up                 build the dev place, probe the PC, launch OUR Studio (scheduled task), find its id
  wakupipe.py <set> sync               hot-sync every source file into our Studio and start Play
  wakupipe.py <set> selftest           run waku.SelfTest over every effect, print the PASS/FAIL lines
  wakupipe.py <set> look <fx> [cam] [--dt 0.0667] [--tend T] [--tstart T] [--stop T] [--cols 6] [--sync]
                                       frozen-frame contact sheet of one effect -> build/look_<fx>_<cam>.jpg
  wakupipe.py <set> looks [--sync]     the manifest's "looks" list, one sheet each
  wakupipe.py <set> shots [tag...]     step-capture the trailer shots (all, or the tags named) into captures/<set>/
  wakupipe.py <set> sfx <takes.json>   download + cut picked SFX takes ({name: url-or-path}) into audio/mix with headroom
  wakupipe.py <set> trailer            assemble the silent trailer from the manifest timeline
  wakupipe.py <set> mix                level + mix the audio cues onto it (peak -2 dBFS, never clips)
  wakupipe.py <set> down               close OUR Studio only and remove our task

<set> is a manifest name (set3 -> tools/sets/set3.json) or a path. Adding an effect = one module in
src/wakuVFX/Effects, one line in init.luau, a place/camera in src/dev/Harness.client.luau and entries in the manifest."""
import argparse, base64, glob, json, os, shutil, subprocess, sys, tempfile, urllib.request

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = f"{B}/tools"
KEY = os.path.expanduser(os.environ.get("WAKUVFX_SSH_KEY", "~/.ssh/id_ed25519_win"))
HOST = os.environ.get("WAKUVFX_SSH_HOST", "")
PC = os.environ.get("WAKUVFX_PC_ROOT", "")
PCW = PC.replace("/", "\\")
FPS = 30


def sh(args, **kw):
    return subprocess.run(args, check=kw.pop("check", True), **kw)


def ssh(cmd, check=True):
    if not HOST or not PC:
        sys.exit("Set WAKUVFX_SSH_HOST and WAKUVFX_PC_ROOT before using the Windows capture commands")
    r = subprocess.run(["ssh", "-q", "-i", KEY, HOST, cmd], capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"ssh failed ({r.returncode}): {cmd}\n{r.stdout}\n{r.stderr}")
    return r.stdout


def scp_to(files, remote_dir):
    sh(["scp", "-q", "-i", KEY, *files, f"{HOST}:{remote_dir}/"])


def scp_from(remote_glob, local_dir):
    os.makedirs(local_dir, exist_ok=True)
    sh(["scp", "-q", "-i", KEY, f"{HOST}:{remote_glob}", local_dir + "/"])


def sid():
    return open(f"{T}/STUDIO_ID").read().strip()


def run_plans(named):
    """named = [(name, plan)]: push to the PC, run in order through waku_mcp.js, fetch the logs. Returns {name: log}."""
    os.makedirs(f"{T}/plans", exist_ok=True)
    files = []
    for name, plan in named:
        f = f"{T}/plans/plan_{name}.json"
        json.dump(plan, open(f, "w"))
        files.append(f)
    scp_to(files, f"{PC}/tools")
    cmd = f"cd /d {PCW}\\tools"
    for name, _ in named:
        cmd += f" & node waku_mcp.js plan_{name}.json out_plan_{name}.json & echo {name}=%errorlevel%"
    out = ssh(cmd, check=False)
    logs, bad = {}, []
    for name, _ in named:
        if f"{name}=0" not in out:
            bad.append(name)
        try:
            sh(["scp", "-q", "-i", KEY, f"{HOST}:{PC}/tools/out_plan_{name}.json", f"{T}/plans/"])
            logs[name] = json.load(open(f"{T}/plans/out_plan_{name}.json"))
        except Exception as e:  # noqa
            logs[name] = [{"step": "fetch", "error": str(e)}]
    if bad:
        for name in bad:
            tail = [x for x in logs[name] if x.get("isError") or x.get("ok") is False or x.get("error")]
            print(f"PLAN FAILED {name}:", json.dumps(tail[-2:], indent=1)[:3000])
    return logs, bad


# ---- plans ------------------------------------------------------------------------------------------------
ST = "return tostring(game.Players.LocalPlayer:GetAttribute('VFXState'))"


def cl(code, label):
    return {"tool": "execute_luau", "label": label, "args": {"studio_id": sid(), "datamodel_type": "Client", "code": code}}


def poll(match, timeout, every=0.5):
    return {"poll": {"tool": "execute_luau", "args": {"studio_id": sid(), "datamodel_type": "Client", "code": ST}, "match": match, "timeout": timeout, "every": every}}


def source_map():
    """every file under src/wakuVFX (+ the dev stage and harness) -> (path, parent, name, class). Auto-discovered."""
    m = [("src/wakuVFX/init.luau", "ReplicatedStorage", "wakuVFX", "ModuleScript")]
    root = f"{B}/src/wakuVFX"
    for d, _, fs in sorted(os.walk(root)):
        rel = os.path.relpath(d, root)
        parent = "ReplicatedStorage.wakuVFX" + ("" if rel == "." else "." + rel.replace(os.sep, "."))
        for f in sorted(fs):
            if f.endswith(".luau") and not (rel == "." and f == "init.luau"):
                m.append((os.path.relpath(f"{d}/{f}", B), parent, f[:-5], "ModuleScript"))
    m += [("src/dev/Stage.server.luau", "ServerScriptService", "Stage", "Script"),
          ("src/dev/Harness.client.luau", "StarterPlayer.StarterPlayerScripts", "Harness", "LocalScript")]
    return m


def plan_sync(play_wait=18):
    S = sid()
    plan = [{"tool": "start_stop_play", "allowError": True, "args": {"studio_id": S, "is_start": False}}, {"sleep": 2}]
    for f, parent, name, cls in source_map():
        raw = open(f"{B}/{f}", "rb").read()
        b64 = base64.b64encode(raw).decode()
        segs = parent.split(".")
        code = (f'local E = game:GetService("EncodingService")\nlocal s = buffer.tostring(E:Base64Decode(buffer.fromstring("{b64}")))\n'
                f'local par = game:GetService("{segs[0]}")\n'
                + "".join(f'par = par:FindFirstChild("{x}") or (function() local f = Instance.new("Folder") f.Name = "{x}" f.Parent = par return f end)()\n' for x in segs[1:])
                + f'local inst = par:FindFirstChild("{name}")\nif not inst then inst = Instance.new("{cls}") inst.Name = "{name}" inst.Parent = par end\n'
                f'inst.Source = s\nreturn "{parent}.{name} " .. #inst.Source .. " expect {len(raw)} " .. tostring(#inst.Source == {len(raw)})')
        plan.append({"tool": "execute_luau", "label": "sync " + name, "timeout": 120, "args": {"studio_id": S, "datamodel_type": "Edit", "code": code}})
    plan += [{"tool": "start_stop_play", "args": {"studio_id": S, "is_start": True}}, {"sleep": play_wait},
             {"tool": "get_console_output", "maxText": 60000, "args": {"studio_id": S}}]
    return plan


def plan_mood(mood="dusk", label="0"):
    code = (f"local p = game.Players.LocalPlayer p:SetAttribute('VFXCmd','mood|{mood}') task.wait(0.3) p:SetAttribute('VFXCmd','label|{label}') task.wait(0.3) "
            "return tostring(game.Lighting.ClockTime) .. ' gui=' .. tostring(p.PlayerGui.wakuHarness.Enabled)")
    return [poll("idle", 180), cl(code, "mood")]


def plan_step(pcdir, tag, fx, tEnd, dt, pre=0.0, cam="", tStart=0.0, stop=None, opts=""):
    nonce = "st_" + tag
    n = round(pre / dt) + int(tEnd / dt + 1e-9) + 1 - (int(tStart / dt + 0.5) if tStart > 0 else 0)
    S = sid()
    cmd = f"step|{fx}|{dt}|{tEnd}|{pre}|{nonce}|{cam}|{tStart}|{'' if stop is None else stop}|{opts}"
    plan = [poll("idle", 300), cl(f"game.Players.LocalPlayer:SetAttribute('VFXCmd','{cmd}') return 'ok'", "start")]
    for k in range(n):
        plan += [poll(f"frame|{nonce}|{k}|", 30, 0.05),
                 {"tool": "screen_capture", "label": f"f{k}", "args": {"studio_id": S, "capture_id": f"{tag}_{k:04d}"}, "save": f"{pcdir}\\{tag}_{k:04d}.jpg"},
                 cl(f"game.Players.LocalPlayer:SetAttribute('VFXCmd','next|{nonce}|{k}') return 'ok'", f"next{k}")]
    plan.append(poll(f"stepdone|{nonce}", 60, 0.2))
    return plan, n


def console_of(log):
    for x in reversed(log):
        if x.get("step") == "get_console_output":
            return x.get("text", "")
    return ""


def report_console(text, always=False):
    bad = [l for l in text.split("\n") if any(k in l for k in ("ERROR", "FAIL", "error", "attempt to", "Stack Begin", "is not a valid", "expected", "Type Error", "wakuVFX]"))
           and "loadstring" not in l and "MCPPlugin" not in l]
    if bad or always:
        print("\n".join(bad[-60:]))


# ---- commands ---------------------------------------------------------------------------------------------
def cmd_up(M, a):
    place = M.get("place", "wakuvfx_dev.rbxlx")
    os.makedirs(f"{B}/build", exist_ok=True)
    sh(["rojo", "build", f"{B}/{M.get('project', 'dev.project.json')}", "-o", f"{B}/build/{place}"])
    print("probe (other lanes' Studio windows are listed, never touched):")
    print(ssh('wmic process where "name=\'RobloxStudioBeta.exe\'" get ProcessId,CommandLine /format:list', check=False).strip() or "  no Studio running")
    ssh(f'if not exist {PCW}\\build mkdir {PCW}\\build & if not exist {PCW}\\tools mkdir {PCW}\\tools & if not exist {PCW}\\captures mkdir {PCW}\\captures')
    scp_to([f"{B}/build/{place}"], f"{PC}/build")
    scp_to(glob.glob(f"{T}/pc/*"), f"{PC}/tools")
    print(ssh(f"powershell -NoProfile -ExecutionPolicy Bypass -File {PCW}\\tools\\waku_task.ps1 -PlaceName {place}", check=False))
    json.dump([{"sleep": a.wait}, {"tool": "list_roblox_studios", "args": {}}], open(f"{T}/plans/plan_list.json", "w"))
    scp_to([f"{T}/plans/plan_list.json"], f"{PC}/tools")
    ssh(f"cd /d {PCW}\\tools & node waku_mcp.js plan_list.json out_plan_list.json", check=False)
    sh(["scp", "-q", "-i", KEY, f"{HOST}:{PC}/tools/out_plan_list.json", f"{T}/plans/"])
    txt = [x for x in json.load(open(f"{T}/plans/out_plan_list.json")) if x.get("step") == "list_roblox_studios"][0]["text"]
    mine = [s for s in json.loads(txt)["studios"] if s["name"] == place]
    if not mine:
        sys.exit("our Studio is not listed yet: " + txt)
    open(f"{T}/STUDIO_ID", "w").write(mine[0]["id"])
    print("our studio:", mine[0])


def cmd_down(M, a):
    print(ssh(f"powershell -NoProfile -ExecutionPolicy Bypass -File {PCW}\\tools\\waku_cleanup.ps1", check=False))


def cmd_sync(M, a):
    logs, bad = run_plans([("sync", plan_sync(a.wait))])
    wrong = [x for x in logs["sync"] if str(x.get("step", "")).startswith("sync ") and not x.get("text", "").endswith("true")]
    print("synced", sum(1 for x in logs["sync"] if str(x.get("step", "")).startswith("sync ")), "files; mismatches:", wrong)
    report_console(console_of(logs["sync"]))
    if bad:
        sys.exit(3)


def cmd_selftest(M, a):
    nonce = "p" + str(os.getpid())
    plan = [poll("idle", 120), cl(f"game.Players.LocalPlayer:SetAttribute('VFXCmd','selftest|{nonce}') return 'ok'", "cmd"),
            poll(f"stdone|{nonce}", 600, 1), {"tool": "get_console_output", "maxText": 120000, "args": {"studio_id": sid()}}]
    logs, bad = run_plans([("selftest", plan)])
    text = console_of(logs["selftest"])
    lines = [l for l in text.split("\n") if "[wakuVFX" in l]
    want = a.only or M.get("effects", [])
    for l in lines:
        if "FAIL" in l or "ERROR" in l or any(f" {w} " in l for w in want):
            print(l)
    done = [x for x in logs["selftest"] if x.get("step") == "poll" and str(x.get("match", "")).startswith("stdone")]
    print("result:", done[0]["last"] if done else "no result")
    if bad:
        sys.exit(3)


def sheet(out, cols, w, files):
    from PIL import Image, ImageDraw
    ims = [Image.open(f).convert("RGB") for f in files]
    h = int(w * ims[0].height / ims[0].width)
    rows = (len(ims) + cols - 1) // cols
    s = Image.new("RGB", (cols * w, rows * h), (0, 0, 0))
    for i, (f, im) in enumerate(zip(files, ims)):
        t = im.resize((w, h))
        ImageDraw.Draw(t).text((6, 4), os.path.basename(f), fill=(255, 255, 0))
        s.paste(t, ((i % cols) * w, (i // cols) * h))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    s.save(out, quality=88)


def capture(M, group, shots, pre_plans=()):
    """shots = [dict(tag, fx, tEnd, dt, pre, cam, tStart, stop)] -> frames in captures/<set>_<group>/"""
    sub = f"{M['name']}_{group}"
    pcd = f"{PCW}\\captures\\{sub}"
    ssh(f"(if exist {pcd} rmdir /s /q {pcd}) & mkdir {pcd}")
    named = list(pre_plans)
    for s in shots:
        plan, n = plan_step(pcd, s["tag"], s["fx"], s["tEnd"], s["dt"], s.get("pre", 0), s.get("cam", ""), s.get("tStart", 0), s.get("stop"), s.get("opts", ""))
        named.append(("s_" + s["tag"], plan))
        print(f"  {s['tag']:8s} {s['fx']:12s} {n} frames")
    logs, bad = run_plans(named)
    local = f"{B}/captures/{sub}"
    shutil.rmtree(local, ignore_errors=True)
    scp_from(f"{PC}/captures/{sub}/*.jpg", local)
    return local, bad


def look_shot(M, fx, cam=None, dt=None, tend=None, tstart=0.0, stop=None, opts=""):
    life = M.get("lives", {}).get(fx, 2.0)
    cam = cam or fx
    tag = f"L{fx}{cam}{'o' if opts else ''}".replace("_", "")
    return dict(tag=tag, fx=fx, cam=cam, dt=dt or 1 / 15, tEnd=tend if tend is not None else life, pre=0, tStart=tstart, stop=stop, opts=opts, sheet=f"{fx}_{cam}{'_opts' if opts else ''}")


def do_looks(M, shots, sync, cols):
    pre = ([("sync", plan_sync(18))] if sync else []) + [("mood", plan_mood(M.get("mood", "dusk"), "1"))]
    local, bad = capture(M, "look", shots, pre)
    for s in shots:
        fs = sorted(glob.glob(f"{local}/{s['tag']}_*.jpg"))
        if fs:
            out = f"{B}/build/look_{s['sheet']}.jpg"
            sheet(out, cols, 384, fs)
            print(out, len(fs))
    if sync:
        log = json.load(open(f"{T}/plans/out_plan_sync.json"))
        report_console(console_of(log))
    if bad:
        sys.exit(3)


def cmd_look(M, a):
    do_looks(M, [look_shot(M, a.fx, a.cam, a.dt, a.tend, a.tstart, a.stop, a.opts)], a.sync, a.cols)


def cmd_looks(M, a):
    shots = [look_shot(M, **l) for l in M["looks"] if not a.only or l["fx"] in a.only]
    do_looks(M, shots, a.sync, a.cols)


def cmd_shots(M, a):
    shots = []
    for s in M["shots"]:
        if a.only and s["tag"] not in a.only:
            continue
        s = dict(s)
        s["dt"] = (1 / FPS) * s.pop("speed", 1)
        shots.append(s)
    pre = ([("sync", plan_sync(18))] if a.sync else []) + [("mood", plan_mood(M.get("mood", "dusk"), "0"))]
    group = "trl_part" if a.only else "trl"
    local, bad = capture(M, group, shots, pre)
    if a.only:  # merge re-shot tags into the main folder
        main = f"{B}/captures/{M['name']}_trl"
        os.makedirs(main, exist_ok=True)
        for t in a.only:
            for f in glob.glob(f"{main}/{t}_*.jpg"):
                os.remove(f)
        for f in glob.glob(f"{local}/*.jpg"):
            shutil.move(f, main)
        local = main
    for s in shots:
        fs = sorted(glob.glob(f"{local}/{s['tag']}_*.jpg"))
        if fs:
            step = max(1, len(fs) // 18)
            sheet(f"{B}/build/shot_{s['tag']}.jpg", 6, 320, fs[::step])
    print("frames:", len(glob.glob(f"{local}/*.jpg")), "sheets: build/shot_<tag>.jpg")
    if bad:
        sys.exit(3)


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def cmd_sfx(M, a):
    """takes.json = {"s3_quake": "<url or local file>", ...}; writes audio/mix/<name>.mp3 at 0.4 gain (headroom), 44.1 kHz"""
    FF = ffmpeg()
    out = f"{B}/{M['audio']['dir']}"
    os.makedirs(out, exist_ok=True)
    raw = f"{out}/raw"
    os.makedirs(raw, exist_ok=True)
    for name, src in json.load(open(a.takes)).items():
        f = src
        if src.startswith("http"):
            f = f"{raw}/{name}.src"
            urllib.request.urlretrieve(src, f)
        sh([FF, "-y", "-loglevel", "error", "-i", f, "-af", "volume=0.4", "-ar", "44100", "-ac", "2", "-b:a", "192k", f"{out}/{name}.mp3"])
        print("cut", name)


def cmd_trailer(M, a):
    from PIL import Image, ImageEnhance
    FF = ffmpeg()
    Tm = M["trailer"]
    W, H, BAND = 1920, 1080, Tm.get("band", 858)
    TOP = (H - BAND) // 2
    TOTAL = Tm.get("total", 900)
    fr_dir = f"{B}/captures/{M['name']}_trl"
    out = f"{B}/{Tm['out']}"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmpdirs, vcache = [], {}

    def frames(e):
        if "video" in e:
            p = f"{B}/{e['video']}"
            if p not in vcache:
                d = tempfile.mkdtemp(prefix="vf_", dir=os.path.dirname(out))
                tmpdirs.append(d)
                sh([FF, "-y", "-loglevel", "error", "-i", p, "-vf", f"fps={FPS}", f"{d}/f_%04d.png"])
                vcache[p] = sorted(glob.glob(f"{d}/f_*.png"))
            fs = vcache[p]
        else:
            fs = sorted(glob.glob(f"{fr_dir}/{e['shot']}_*.jpg"))
        assert fs, e
        if "take" in e:
            fs = fs[e["take"][0]:e["take"][1]]
        if e.get("every"):
            fs = fs[::e["every"]]
        return fs + [fs[-1]] * e.get("hold", 0)

    shots = []
    for e in Tm["timeline"]:
        if "end" in e:
            used = sum(len(s["paths"]) for s in shots)
            fs = [f for x in e["end"] for f in frames(x)]
            tail = TOTAL - used
            assert tail >= 1, f"timeline is {used} frames, over the {TOTAL} total"
            fs = (fs + [fs[-1]] * tail)[:tail]
            shots.append(dict(paths=fs, kind="end", flash=False))
        else:
            shots.append(dict(paths=frames(e), kind=e["kind"], flash=e.get("flash", True)))
    t = 0
    for s in shots:
        s["start"] = t
        t += len(s["paths"])
    assert t == TOTAL, f"timeline is {t} frames, want {TOTAL} (add an 'end' entry)"
    st, rc = {}, 0
    for s in shots:
        k = s["kind"]
        if k == "recap":
            k = f"r{rc}"
            rc += 1
        st[k] = s["start"] / FPS
        print(f'{k:8s} {s["start"] / FPS:6.2f}s  {len(s["paths"]) / FPS:5.2f}s')
    if a.dry:
        return
    tmp = tempfile.mkdtemp(prefix="trl_", dir=os.path.dirname(out))
    tmpdirs.append(tmp)

    def band(img):
        w, h = img.size
        sc = max(W / w, BAND / h)
        img = img.resize((round(w * sc), round(h * sc)), Image.LANCZOS)
        x, y = (img.width - W) // 2, (img.height - BAND) // 2
        return img.crop((x, y, x + W, y + BAND))

    cache = {}
    for s in shots:
        for i, p in enumerate(s["paths"]):
            gf = s["start"] + i
            canvas = Image.new("RGB", (W, H), (0, 0, 0))
            if p not in cache:
                cache.clear()
                cache[p] = band(Image.open(p).convert("RGB"))
            img = cache[p]
            if s["kind"] == "recap":
                img = ImageEnhance.Contrast(img).enhance(1.08)
            canvas.paste(img, (0, TOP))
            if s["flash"] and i < 3 and s["start"] > 0:
                fl = Image.new("RGB", (W, BAND), (255, 255, 255))
                canvas.paste(Image.blend(canvas.crop((0, TOP, W, TOP + BAND)), fl, 0.6 * (1 - i / 3)), (0, TOP))
            g = min(1.0, gf / 8, (TOTAL - 1 - gf) / (40 if s["kind"] == "end" else 10))
            if g < 1:
                canvas = Image.blend(Image.new("RGB", (W, H), (0, 0, 0)), canvas, max(0.0, g))
            canvas.save(f"{tmp}/c_{gf:04d}.jpg", quality=93)
    json.dump(st, open(out + ".json", "w"), indent=1)
    sh([FF, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", f"{tmp}/c_%04d.jpg", "-c:v", "libx264", "-crf", "17", "-preset", "slow",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", out])
    for d in tmpdirs:
        shutil.rmtree(d, ignore_errors=True)
    print("wrote", out)


def cmd_mix(M, a):
    import numpy as np
    FF = ffmpeg()
    A = M["audio"]
    vin = f"{B}/{M['trailer']['out']}"
    out = f"{B}/{A['out']}"
    st = json.load(open(vin + ".json"))
    SR = 44100
    DUR = M["trailer"].get("total", 900) / FPS
    N = int(DUR * SR)
    dirs = [f"{B}/{A['dir']}"] + [f"{B}/{d}" if not d.startswith("/") else d for d in A.get("more_dirs", [])]

    def load(name):
        f = next((f"{d}/{name}.mp3" for d in dirs if os.path.exists(f"{d}/{name}.mp3")), None)
        assert f, "missing clip " + name
        raw = subprocess.run([FF, "-loglevel", "error", "-i", f, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
        return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)

    def level(x, db):  # level by the loudest 400 ms so short hits and long beds compare fairly
        m = (x ** 2).mean(1)
        w = min(len(m), int(0.4 * SR))
        c = np.cumsum(np.concatenate([[0], m]))
        loud = np.sqrt(((c[w:] - c[:-w]) / w).max())
        return x * (10 ** (db / 20) / max(loud, 1e-6))

    def fade(x, fin=0.0, fout=0.0, dur=None):
        x = x[: int(dur * SR)].copy() if dur else x.copy()
        n = min(len(x), int(fin * SR))
        if n:
            x[:n] *= np.linspace(0, 1, n)[:, None]
        n = min(len(x), int(fout * SR))
        if n:
            x[-n:] *= np.linspace(1, 0, n)[:, None]
        return x

    mix = np.zeros((N, 2))
    mu = A.get("music")
    if mu:
        m = level(load(mu["clip"]), mu.get("db", -24))[:N]
        mix[: len(m)] += m
    for c in A["cues"]:
        at = c["at"]
        t = (st[at] if isinstance(at, str) else float(at)) + c.get("offset", 0.0)
        dur = c.get("dur")
        if c.get("until"):
            dur = st[c["until"]] - t + c.get("until_offset", 0.0)
        x = fade(level(load(c["clip"]), c.get("db", -18)), c.get("fin", 0.0), c.get("fout", 0.0), dur)
        i = int(max(0, t) * SR)
        x = x[: max(0, N - i)]
        mix[i:i + len(x)] += x
    mix = fade(mix, fin=0.25, fout=1.6)
    pk = np.abs(mix).max()
    print("raw peak dBFS", round(20 * np.log10(pk), 1))
    mix *= 10 ** (-2 / 20) / pk
    print("final rms dBFS", round(20 * np.log10(np.sqrt((mix ** 2).mean())), 1), "clipped samples", int((np.abs(mix) > 0.999).sum()))
    subprocess.run([FF, "-y", "-loglevel", "error", "-i", vin, "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-", "-map", "0:v", "-map", "1:a",
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "256k", "-shortest", "-movflags", "+faststart", out], input=mix.astype(np.float32).tobytes(), check=True)
    print("wrote", out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("up"); p.add_argument("--wait", type=float, default=30)
    sub.add_parser("down")
    p = sub.add_parser("sync"); p.add_argument("--wait", type=float, default=18)
    p = sub.add_parser("selftest"); p.add_argument("only", nargs="*")
    p = sub.add_parser("look"); p.add_argument("fx"); p.add_argument("cam", nargs="?")
    p.add_argument("--dt", type=float); p.add_argument("--tend", type=float); p.add_argument("--tstart", type=float, default=0.0)
    p.add_argument("--stop", type=float); p.add_argument("--opts", default=""); p.add_argument("--cols", type=int, default=6); p.add_argument("--sync", action="store_true")
    p = sub.add_parser("looks"); p.add_argument("only", nargs="*"); p.add_argument("--cols", type=int, default=6); p.add_argument("--sync", action="store_true")
    p = sub.add_parser("shots"); p.add_argument("only", nargs="*"); p.add_argument("--sync", action="store_true")
    p = sub.add_parser("sfx"); p.add_argument("takes")
    p = sub.add_parser("trailer"); p.add_argument("--dry", action="store_true")
    sub.add_parser("mix")
    a = ap.parse_args()
    mf = a.set if os.path.exists(a.set) else f"{T}/sets/{a.set}.json"
    M = json.load(open(mf))
    globals()["cmd_" + a.cmd](M, a)


if __name__ == "__main__":
    main()
