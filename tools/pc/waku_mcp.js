// waku_mcp.js - minimal JSONL stdio client for the installed Roblox Studio MCP (mcp.bat), one fresh session per run.
// usage: node waku_mcp.js <plan.json> <out.json>
// plan = [ step, ... ] with step one of:
//   {"tool": "<name>", "args": {...}, "save": "F:/.../x.jpg"?, "label": "..."?}  -> tools/call; images saved to `save`
//   {"sleep": seconds}
//   {"poll": {"tool": "...", "args": {...}, "match": "substring", "timeout": s, "every": s}}  -> repeat until text contains match
//   {"list": true}  -> tools/list (schemas into out.json)
//   {"loop": {"tool": "screen_capture", "args": {...}, "dir": "F:/...", "prefix": "f", "count": N, "seconds": S}} -> capture burst
// Fails the batch (exit 3) when a call returns isError, unless the step has "allowError": true.
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// optional: SERVE_DIR=<dir> serves that folder on http://127.0.0.1:18731/ (localhost only) for upload_image
if (process.env.SERVE_DIR) {
  const http = require('http');
  const root = process.env.SERVE_DIR;
  http.createServer((req, res) => {
    const f = path.join(root, path.basename(decodeURIComponent(req.url.split('?')[0])));
    fs.readFile(f, (err, data) => {
      if (err) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': 'image/png', 'Content-Length': data.length }); res.end(data);
    });
  }).listen(18731, '127.0.0.1');
}
const plan = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const outPath = process.argv[3];
const mcpBat = path.join(process.env.LOCALAPPDATA, 'Roblox', 'mcp.bat');
const child = spawn('cmd.exe', ['/c', mcpBat], { stdio: ['pipe', 'pipe', 'pipe'] });
let buf = '';
const waiting = new Map();
let nextId = 1;
child.stdout.on('data', (d) => {
  buf += d.toString('utf8');
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch (e) { continue; }
    if (msg.id !== undefined && waiting.has(msg.id)) { waiting.get(msg.id)(msg); waiting.delete(msg.id); }
  }
});
child.stderr.on('data', () => {});
function rpc(method, params, timeoutMs = 120000) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => { waiting.delete(id); reject(new Error('timeout ' + method)); }, timeoutMs);
    waiting.set(id, (m) => { clearTimeout(t); resolve(m); });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}
const sleep = (s) => new Promise((r) => setTimeout(r, s * 1000));
function textOf(res) {
  const c = (res.result && res.result.content) || [];
  return c.filter((x) => x.type === 'text').map((x) => x.text).join('\n');
}
function saveImages(res, file) {
  const c = (res.result && res.result.content) || [];
  const imgs = c.filter((x) => x.type === 'image');
  imgs.forEach((im, k) => {
    const f = k === 0 ? file : file.replace(/(\.\w+)$/, `_${k}$1`);
    fs.writeFileSync(f, Buffer.from(im.data, 'base64'));
  });
  return imgs.length;
}

(async () => {
  const log = [];
  let failed = false;
  try {
    const init = await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'lfrv-qa', version: '1' } });
    log.push({ step: 'initialize', server: init.result && init.result.serverInfo });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
    for (const step of plan) {
      if (step.sleep !== undefined) { await sleep(step.sleep); continue; }
      if (step.list) { const r = await rpc('tools/list', {}); log.push({ step: 'list', tools: r.result && r.result.tools }); continue; }
      if (step.poll) {
        const p = step.poll; const t0 = Date.now(); let last = '';
        while (Date.now() - t0 < (p.timeout || 30) * 1000) {
          const r = await rpc('tools/call', { name: p.tool, arguments: p.args });
          last = textOf(r);
          if (last.includes(p.match)) break;
          await sleep(p.every || 0.25);
        }
        const ok = last.includes(p.match);
        log.push({ step: 'poll', match: p.match, ok, last: last.slice(0, 2000), ms: Date.now() - t0 });
        if (!ok && !step.allowError) { failed = true; break; }
        continue;
      }
      if (step.loop) {
        const L = step.loop; const t0 = Date.now(); let n = 0; const times = [];
        while (n < (L.count || 1e9) && Date.now() - t0 < (L.seconds || 1e9) * 1000) {
          const a = Object.assign({}, L.args, { capture_id: `${L.prefix}_${String(n).padStart(4, '0')}` });
          const tc = Date.now();
          const r = await rpc('tools/call', { name: L.tool, arguments: a });
          const f = path.join(L.dir, `${L.prefix}_${String(n).padStart(4, '0')}.jpg`);
          const k = saveImages(r, f);
          times.push({ n, ms: tc - t0, done: Date.now() - t0, images: k, err: !!(r.result && r.result.isError) });
          n++;
        }
        log.push({ step: 'loop', prefix: L.prefix, frames: n, times });
        continue;
      }
      const t0 = Date.now();
      const r = await rpc('tools/call', { name: step.tool, arguments: step.args || {} }, (step.timeout || 120) * 1000);
      const isErr = !!(r.error || (r.result && r.result.isError));
      const entry = { step: step.label || step.tool, ms: Date.now() - t0, isError: isErr, text: textOf(r).slice(0, step.maxText || 20000) };
      if (r.error) entry.error = r.error;
      if (step.save) entry.images = saveImages(r, step.save);
      log.push(entry);
      if (isErr && !step.allowError) { failed = true; break; }
    }
  } catch (e) {
    log.push({ step: 'exception', error: String(e) });
    failed = true;
  }
  fs.writeFileSync(outPath, JSON.stringify(log, null, 1));
  child.stdin.end();
  child.kill();
  process.exit(failed ? 3 : 0);
})();
