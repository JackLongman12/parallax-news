// Renders index.html frame by frame with headless Edge.
//   node render.js --stills 1,22,50            -> stills/<t>.jpg
//   node render.js --from 0 --to 10 --fps 30 --out part.mp4
// Headless Edge sometimes stops producing frames; when a capture hangs the
// browser is killed and relaunched and the same frame is captured again.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const puppeteer = require('puppeteer-core');

const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
const ROOT = __dirname;
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.ttf': 'font/ttf', '.json': 'application/json' };
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const server = http.createServer((req, res) => {
  const p = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
  if (!p.startsWith(ROOT) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(p)] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
});

const withTimeout = (p, ms, what) => Promise.race([p, sleep(ms).then(() => { throw new Error(what + ' timed out'); })]);

let live = null;   // { edge, browser, page }
function kill() {
  if (!live) return;
  const { edge, browser } = live; live = null;
  try { browser.disconnect(); } catch (_) {}
  // kill the whole Edge process tree, not just the parent
  spawnSync('taskkill', ['/PID', String(edge.pid), '/T', '/F'], { stdio: 'ignore' });
}
process.on('exit', kill);

async function launch(beats) {
  const port = 9300 + Math.floor(Math.random() * 500);
  const edge = spawn(EDGE, [
    '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${path.join(ROOT, 'edgeprof-' + port)}`,
    '--force-device-scale-factor=1', '--hide-scrollbars', '--ignore-gpu-blocklist', '--enable-gpu-rasterization',
    '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows',
    '--no-first-run', 'about:blank'], { stdio: 'ignore' });
  let browser;
  for (let i = 0; i < 80 && !browser; i++) {
    await sleep(250);
    try { browser = await puppeteer.connect({ browserURL: `http://127.0.0.1:${port}`, defaultViewport: null, protocolTimeout: 30000 }); } catch (_) {}
  }
  if (!browser) { spawnSync('taskkill', ['/PID', String(edge.pid), '/T', '/F'], { stdio: 'ignore' }); throw new Error('could not connect to Edge'); }
  live = { edge, browser };
  const page = await browser.newPage();
  live.page = page;
  page.on('console', (m) => { if (!/404/.test(m.text())) console.log('[page]', m.text()); });
  page.on('pageerror', (e) => console.log('[page error]', e.message));
  await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
  const q = arg('short') ? '?short' : arg('flat') ? '?flat' : '';
  await page.goto('http://127.0.0.1:8765/index.html' + q + (arg('debug') ? '#debug' : ''), { waitUntil: 'load' });
  const end = await page.evaluate(async (d) => {
    await Promise.all(['400', '600', '700', '800', '900'].map((w) => document.fonts.load(`${w} 100px Inter`)));
    // a 1px element that changes every frame, so the compositor always has a new frame to hand over
    const n = document.createElement('div');
    n.id = 'nudge'; n.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;background:#000;z-index:99';
    document.body.appendChild(n);
    return window.setup(d);
  }, beats);
  return end;
}

async function shoot(t, k, opts) {
  const page = live.page;
  await withTimeout(page.evaluate((t, k) => { window.frame(t); document.getElementById('nudge').style.opacity = k % 2 ? '0.99' : '1'; }, t, k), 15000, 'frame');
  return withTimeout(page.screenshot(opts), 15000, 'screenshot');
}

(async () => {
  await new Promise((r) => server.listen(8765, '127.0.0.1', r));
  const beats = JSON.parse(fs.readFileSync(path.join(ROOT, 'beats.json'), 'utf8'));
  let end = await launch(beats);
  console.log('video end', end.toFixed(3));

  if (arg('eval')) { console.log(JSON.stringify(await live.page.evaluate((src) => (0, eval)(src), arg('eval')))); }
  const stills = arg('stills');
  if (stills) {
    const dir = path.join(ROOT, arg('stilldir', 'stills'));
    fs.mkdirSync(dir, { recursive: true });
    for (const s of stills.split(',')) {
      const t = parseFloat(s);
      const buf = await shoot(t, 0, { type: 'jpeg', quality: 88 });
      fs.writeFileSync(path.join(dir, `${t.toFixed(2)}.jpg`), buf);
    }
  } else {
    const fps = parseFloat(arg('fps', '30'));
    // --edl a:b,c:d,... (film seconds): render only those stretches, back to back
    const film = [];
    if (arg('edl')) for (const [a, b] of arg('edl').split(',').map((s) => s.split(':').map(Number)))
      for (let f = Math.round(a * fps); f < Math.round(b * fps); f++) film.push(f / fps);
    const total = film.length ? film.length / fps : end + 0.5;
    const from = parseFloat(arg('from', '0'));
    const to = Math.min(parseFloat(arg('to', String(total))), total);
    const i0 = Math.round(from * fps);
    const out = path.join(ROOT, arg('out', 'video.mp4'));
    const restartEvery = parseInt(arg('restart-every', '300'), 10);
    const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
      '-c:v', 'libx264', '-preset', arg('preset', 'medium'), '-crf', arg('crf', '17'), '-pix_fmt', 'yuv420p', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
    const n = Math.round((to - from) * fps);
    const t0 = Date.now();
    let relaunches = 0;
    for (let i = 0; i < n; i++) {
      const t = film.length ? film[i0 + i] : from + i / fps;
      // a fresh browser every few seconds of footage keeps it from bogging down
      if (i > 0 && i % restartEvery === 0) { kill(); await launch(beats); }
      let buf;
      for (let k = 0; ; k++) {
        try { buf = await shoot(t, i, { type: 'jpeg', quality: 94, optimizeForSpeed: true }); break; }
        catch (err) {
          if (k >= 5) throw err;
          relaunches++;
          console.log(`frame ${i}: ${err.message}; relaunching Edge`);
          kill(); await sleep(500); await launch(beats);
        }
      }
      if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
      if (i % 150 === 0) console.log(`frame ${i}/${n}  t=${t.toFixed(2)}  ${((Date.now() - t0) / 1000).toFixed(0)}s`);
    }
    ff.stdin.end();
    const code = await new Promise((r) => ff.on('close', r));
    if (code !== 0) throw new Error('ffmpeg exited ' + code);
    console.log('wrote', out, ((Date.now() - t0) / 1000).toFixed(0) + 's', relaunches + ' relaunches');
  }
  kill();
  server.close();
  process.exit(0);
})().catch((e) => { console.error(e); kill(); process.exit(1); });
