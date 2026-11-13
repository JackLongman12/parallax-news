'use strict';
/* Parallax launch film. Deterministic: window.frame(t) draws the frame at
   time t (seconds). Everything is placed in one 3D world that the camera
   flies through; scene changes land on bars of the song (92.36 BPM). */

const W = 1920, H = 1080, P = 1300;
let D = null, BAR0 = 0.2066, BEAT = 0.64962;
const T = (k) => BAR0 + (SHORT ? warp(k) : k) * 4 * BEAT;   // start of bar k (retimed in the short cut)
const BT = (n) => BAR0 + n * BEAT;      // beat n
let END = 0;
// Flat cut (index.html?flat): solid colour scenes, no glow/gloss/grain/stars, its own camera.
const FLAT = /[?&](flat|short)\b/.test(location.search);
// 1-minute cut (index.html?short): flat look, its own bolder camera; edl.py picks the bars shown.
const SHORT = /[?&]short\b/.test(location.search);
// Short cut retiming: [bar of the full film, bar of the short film]. Holds are
// squeezed, busy moments keep full speed; every big moment still lands on a beat.
const WARP = [[0, 0], [4, 2], [7, 3], [8, 4], [9, 5], [11, 6], [12, 7], [14, 9], [16, 9.5], [17.6, 9.9], [18, 10],
  [22, 13], [24, 13.25], [26, 14.25], [28, 15.75], [31.4, 16], [32, 16.25], [34, 17.25], [35, 18.25], [36, 19],
  [40, 21], [42, 23], [44, 24], [46, 25], [48, 27]];
function warp(k) {
  if (k <= 0) return k;
  for (let i = 1; i < WARP.length; i++) {
    const [a0, b0] = WARP[i - 1], [a1, b1] = WARP[i];
    if (k <= a1) return b0 + ((k - a0) * (b1 - b0)) / (a1 - a0);
  }
  return k - 48 + 27;
}
// the short cut's music starts 4 bars into the song, so the drop lands on "One story"
const songT = (t) => t + (SHORT ? 16 * BEAT : 0);

// ---------- math ----------
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;
const prog = (t, a, b) => clamp((t - a) / (b - a));
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const E = {
  outExpo: (x) => (x >= 1 ? 1 : 1 - Math.pow(2, -10 * x)),
  inExpo: (x) => (x <= 0 ? 0 : Math.pow(2, 10 * x - 10)),
  inOutCubic: (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2),
  outCubic: (x) => 1 - Math.pow(1 - x, 3),
  inCubic: (x) => x * x * x,
  inOutSine: (x) => -(Math.cos(Math.PI * x) - 1) / 2,
  outBack: (x) => { const c1 = 1.6, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
  outQuint: (x) => 1 - Math.pow(1 - x, 5),
};
function rng(seed) { let s = seed >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }
const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const mix = (a, b, t) => { const x = hex(a), y = hex(b); return `rgb(${x.map((v, i) => Math.round(lerp(v, y[i], t))).join(',')})`; };

// ---------- music ----------
function energyAt(t) {
  if (!D) return 0.5;
  const e = D.energy, i = songT(t) * 30, a = Math.floor(i);
  if (a < 0) return e[0];
  if (a >= e.length - 1) return e[e.length - 1];
  return lerp(e[a], e[a + 1], i - a);
}
function bandAt(b, t) {
  if (!D) return 0.5;
  const b0 = Math.floor(clamp(b, 0, 7)), b1 = Math.min(7, b0 + 1), f = clamp(b, 0, 7) - b0;
  const i = Math.min(D.bands[0].length - 1, Math.max(0, Math.round(songT(t) * 30)));
  return lerp(D.bands[b0][i], D.bands[b1][i], f);
}
/** Decaying pulse on every beat (stronger on the bar's first beat). */
function kick(t) {
  const n = Math.floor((t - BAR0) / BEAT);
  if (n < 0) return 0;
  const dt = t - BT(n), down = n % 4 === 0 ? 1 : 0.6;
  return down * Math.exp(-dt / 0.14) * clamp(energyAt(t) * 1.7, 0.2, 1);
}

// ---------- DOM helpers ----------
const cam = document.getElementById('cam');
const ents = [];
function el(html) { const d = document.createElement('div'); d.innerHTML = html.trim(); return d.firstElementChild; }
function add(node, o) {
  const e = Object.assign({ el: node, t0: -1, t1: 1e9, x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0, s: 1, o: 1, upd: null, near: true, ax: 50, ay: 50 }, o);
  e.b = { x: e.x, y: e.y, z: e.z, rx: e.rx, ry: e.ry, rz: e.rz, s: e.s, o: e.o };
  node.style.display = 'none';
  cam.appendChild(node);
  ents.push(e);
  return e;
}
const SVG = (w, h, inner) => `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${-w / 2} ${-h / 2} ${w} ${h}" overflow="visible">${inner}</svg>`;

// ---------- Frutiger Metro motifs ----------
const INK = '#0b0613';
const PAL = {
  purple: [[1, INK], [0.86, '#ffffff'], [0.73, '#7c3aed'], [0.6, INK], [0.47, '#ffffff'], [0.33, INK]],
  target: [[1, INK], [0.87, '#ffffff'], [0.74, INK], [0.61, '#ffffff'], [0.48, INK], [0.33, '#ffffff'], [0.2, INK]],
  violet: [[1, INK], [0.85, '#a26bff'], [0.7, '#ffffff'], [0.55, INK], [0.44, '#ffffff']],
  lime: [[1, INK], [0.85, '#b8f53a'], [0.68, INK], [0.52, '#eaffc4'], [0.36, INK]],
  yellow: [[1, INK], [0.84, '#ffe14d'], [0.66, '#7c3aed'], [0.5, '#ffffff'], [0.34, INK]],
  blue: [[1, INK], [0.85, '#4b3cff'], [0.7, '#ffffff'], [0.56, INK], [0.42, '#4b3cff'], [0.28, '#ffffff']],
};
function starPath(r, inner = 0.45, n = 5) {
  let p = '';
  for (let i = 0; i < n * 2; i++) {
    const a = -Math.PI / 2 + (i * Math.PI) / n, rr = i % 2 ? r * inner : r;
    p += (i ? 'L' : 'M') + (Math.cos(a) * rr).toFixed(1) + ' ' + (Math.sin(a) * rr).toFixed(1);
  }
  return p + 'Z';
}
function disc(R, pal, star) {
  let s = '';
  for (const [f, c] of pal) s += `<circle r="${(R * f).toFixed(1)}" fill="${c}"/>`;
  if (star) s += `<path d="${starPath(R * 0.3)}" fill="${INK}"/>`;
  return s;
}
function clusterSVG(seed, size, palettes) {
  const r = rng(seed);
  let s = '';
  for (let i = 0; i < 34; i++) {           // ink splatter behind
    const a = r() * 6.283, d = size * (0.12 + r() * 0.42), rr = size * (0.006 + r() * r() * 0.07);
    s += `<circle cx="${(Math.cos(a) * d).toFixed(1)}" cy="${(Math.sin(a) * d * 0.8).toFixed(1)}" r="${rr.toFixed(1)}" fill="${INK}"/>`;
  }
  const n = 3 + Math.floor(r() * 3);
  const discs = [];
  for (let i = 0; i < n; i++) {
    const R = size * (0.12 + r() * 0.19);
    discs.push({ R, x: (r() - 0.5) * size * 0.62, y: (r() - 0.5) * size * 0.46, pal: palettes[Math.floor(r() * palettes.length)], star: r() < 0.3, drip: r() < 0.45 });
  }
  discs.sort((a, b) => b.R - a.R);
  for (const d of discs) {
    let g = '';
    if (d.drip) {
      for (let k = 0; k < 2; k++) {
        const dx = (r() - 0.5) * d.R * 1.2, len = d.R * (0.6 + r() * 0.9), w = d.R * (0.08 + r() * 0.07);
        g += `<rect x="${(dx - w / 2).toFixed(1)}" y="0" width="${w.toFixed(1)}" height="${(d.R + len).toFixed(1)}" fill="${INK}"/><circle cx="${dx.toFixed(1)}" cy="${(d.R + len).toFixed(1)}" r="${(w * 0.75).toFixed(1)}" fill="${INK}"/>`;
      }
    }
    s += `<g transform="translate(${d.x.toFixed(1)} ${d.y.toFixed(1)})">${g}${disc(d.R, PAL[d.pal], d.star)}</g>`;
  }
  return SVG(size, size, s);
}
function portalSVG(R, accent = '#7c3aed') {
  const bands = [[1, 0.93, INK], [0.93, 0.87, '#ffffff'], [0.87, 0.81, accent], [0.81, 0.76, INK], [0.76, 0.72, '#ffffff'], [0.72, 0.67, INK], [0.67, 0.64, '#b8f53a'], [0.64, 0.61, INK]];
  let s = '';
  for (const [a, b, c] of bands) s += `<circle r="${(R * (a + b) / 2).toFixed(1)}" fill="none" stroke="${c}" stroke-width="${(R * (a - b) + 1).toFixed(1)}"/>`;
  for (let i = 0; i < 36; i++) {
    const a = (i / 36) * 6.283;
    s += `<circle cx="${(Math.cos(a) * R * 1.06).toFixed(1)}" cy="${(Math.sin(a) * R * 1.06).toFixed(1)}" r="${(R * 0.012).toFixed(1)}" fill="#ffffff"/>`;
  }
  return SVG(R * 2.3, R * 2.3, s);
}
function swirlPath(seed, size) {
  const r = rng(seed), pts = [];
  const turns = 1.6 + r() * 0.8, dir = r() < 0.5 ? 1 : -1, a0 = r() * 6.283;
  // tail: a gentle S-curve that flows into a tightening spiral
  const tailLen = size * 0.55;
  for (let i = 0; i <= 30; i++) {
    const s = i / 30;
    pts.push([-tailLen + s * tailLen, Math.sin(s * Math.PI) * size * 0.12 * dir]);
  }
  const R0 = size * 0.26;
  for (let i = 1; i <= 120; i++) {
    const s = i / 120, th = a0 * 0 + dir * s * turns * 6.283, rr = R0 * Math.pow(1 - s, 1.25);
    pts.push([rr * Math.sin(th) + 0, R0 * dir - rr * Math.cos(th) * dir]);
  }
  return 'M' + pts.map((p) => p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join('L');
}
function swirlSVG(seed, size, color, width) {
  const d = swirlPath(seed, size);
  return SVG(size * 1.6, size * 1.2, `<path class="sw" d="${d}" pathLength="1" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round" stroke-dasharray="1 1" stroke-dashoffset="1"/>`);
}
function eyeOffSVG(S) {
  const k = S / 100;
  return SVG(S * 1.4, S, `<g fill="none" stroke="${FLAT ? '#0b0613' : '#fff'}" stroke-width="${7 * k}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M${-55 * k} 0 Q 0 ${-48 * k} ${55 * k} 0 Q 0 ${48 * k} ${-55 * k} 0Z"/><circle r="${16 * k}"/>
    <path d="M${-48 * k} ${-38 * k} L${48 * k} ${38 * k}" stroke="#e5375a" stroke-width="${9 * k}"/></g>`);
}
let LOGO_N = 0;
function logoSVG(S0) {
  const S = S0, id = ++LOGO_N, r = S * 0.34, dx = S * 0.2;
  return SVG(S * 1.5, S, `<defs><clipPath id="cl${id}"><circle cx="${-dx}" r="${r}"/></clipPath>
    <radialGradient id="gl${id}"><stop offset="0" stop-color="#ffffff" stop-opacity=".55"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient></defs>
    <circle cx="${-dx}" r="${r}" fill="#3f63f5"/><circle cx="${dx}" r="${r}" fill="#e5375a"/>
    <circle cx="${dx}" r="${r}" fill="#7c3aed" clip-path="url(#cl${id})"/>
    <circle cx="${-dx}" r="${r}" fill="none" stroke="#fff" stroke-width="${S * 0.035}"/><circle cx="${dx}" r="${r}" fill="none" stroke="#fff" stroke-width="${S * 0.035}"/>
    ${FLAT ? '' : `<ellipse cx="${-dx * 0.2}" cy="${-r * 0.55}" rx="${r * 1.1}" ry="${r * 0.32}" fill="url(#gl${id})"/>`}`);
}

// ---------- building blocks ----------
function wordsEl(text, cls, size, extra = '') {
  const html = text.split(' ').map((w) => (w === '|' ? '<br>' : `<span class="word">${w}</span>`)).join(' ');
  return el(`<div class="${cls}" style="font-size:${size}px;${extra}">${html}</div>`);
}
function lettersEl(text, cls, size, extra = '') {
  return el(`<div class="${cls} letters" style="font-size:${size}px;${extra}">${[...text].map((c) => `<span class="word">${c}</span>`).join('')}</div>`);
}
/** Each word / letter flies in from depth with blur, one after another. */
function revealSpans(e, t, start, step, dur = 0.55, from = 'up') {
  const spans = e.spans || (e.spans = [...e.el.querySelectorAll('.word')]);
  spans.forEach((sp, i) => {
    const s0 = Array.isArray(start) ? start[i] : start + i * step;
    if (FLAT) {
      const q = E.outQuint(prog(t, s0, s0 + dur * 0.8));
      sp.style.opacity = clamp(q * 3).toFixed(3);
      sp.style.transform = `translateY(${((1 - q) * 0.5).toFixed(3)}em)`;
      return;
    }
    const p = E.outExpo(prog(t, s0, s0 + dur));
    const o = clamp(p * 1.4);
    const dy = from === 'up' ? (1 - p) * 70 : 0, sc = lerp(1.6, 1, p);
    sp.style.opacity = o;
    sp.style.transform = `translateY(${dy.toFixed(1)}px) scale(${sc.toFixed(3)})`;
    sp.style.filter = p < 0.98 ? `blur(${((1 - p) * 16).toFixed(1)}px)` : 'none';
  });
}
function phoneEl(img) {
  return el(`<div class="phone"><div class="screen"><img src="img/${img}"></div><div class="gloss"></div><div class="notch"></div></div>`);
}
const SIDE = { left: ['LEFT', 'var(--left)'], center: ['CENTER', '#8f6cf0'], right: ['RIGHT', 'var(--right)'] };
function cardEl(side, head, src) {
  const [label, col] = SIDE[side];
  return el(`<div class="glass card"><span class="tag" style="background:${col}${FLAT ? '' : ';box-shadow:0 0 24px ' + col}">${label}</span><h3>${head}</h3><div class="src">${src}</div></div>`);
}
function pillEl(text, lineLen = 0, lineSide = 'right') {
  const line = lineLen && FLAT
    ? `<div style="position:absolute;top:50%;${lineSide}:${-lineLen}px;width:${lineLen}px;height:4px;margin-top:-2px;background:var(--fg)"><div style="position:absolute;${lineSide}:-9px;top:-7px;width:18px;height:18px;border-radius:50%;background:var(--fg)"></div></div>`
    : lineLen
    ? `<div style="position:absolute;top:50%;${lineSide}:${-lineLen}px;width:${lineLen}px;height:3px;margin-top:-1.5px;background:linear-gradient(${lineSide === 'right' ? '90deg' : '270deg'},rgba(255,255,255,.9),rgba(184,245,58,.9));box-shadow:0 0 12px rgba(184,245,58,.8)"><div style="position:absolute;${lineSide}:-8px;top:-6.5px;width:16px;height:16px;border-radius:50%;background:#b8f53a;box-shadow:0 0 18px #b8f53a"></div></div>`
    : '';
  return el(`<div class="glass pill" style="overflow:visible"><span class="dot"></span>${text}${line}</div>`);
}
function leanBarEl(w, parts) {
  return el(`<div style="width:${w}px"><div class="bar">${parts.map(([f, c]) => `<div style="width:${f * 100}%;background:${c}"></div>`).join('')}</div>
    <div style="display:flex;justify-content:space-between;margin-top:18px;font-weight:800;font-size:34px">
    <span style="color:${FLAT ? 'var(--fg)' : '#7d97ff'}">Left 40%</span><span style="color:${FLAT ? 'var(--fg)' : '#cdbdff'}">Center 20%</span><span style="color:${FLAT ? 'var(--fg)' : '#ff6f8c'}">Right 40%</span></div></div>`);
}
function tileEl(title, sub, bg, w = 300, h = 210) {
  return el(`<div class="glass tile" style="width:${w}px;height:${h}px;background:${bg};color:#fff"><b>${title}</b><small>${sub}</small>
    <div class="bar" style="height:8px;margin-top:12px;position:relative;box-shadow:none"><div style="width:62%;background:#3f63f5"></div><div style="width:28%;background:#b39bff"></div><div style="width:10%;background:#e5375a"></div></div></div>`);
}
function canvasEl(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; c.style.width = w + 'px'; c.style.height = h + 'px'; return c; }

// Pop-in helper for entities: scale + fade with overshoot at time a.
function popIn(e, t, a, dur = 0.6, from = 0.4) {
  const p = prog(t, a, a + dur);
  e.s = e.b.s * lerp(from, 1, E.outBack(p));
  e.o = e.b.o * clamp(p * 2.5);
}
function fadeOut(e, t, a, dur = 0.5) { e.o *= 1 - E.inOutCubic(prog(t, a, a + dur)); }

// ---------- camera ----------
const KEYS = []; // [t, {x,y,z,rx,ry,rz}]
function key(t, v) { if (!FLAT) KEYS.push([t, v]); }
function fkey(t, v) { KEYS.push([t, v]); }
let CAMF = null;
function buildCamera() {
  KEYS.sort((a, b) => a[0] - b[0]);
  const ch = ['x', 'y', 'z', 'rx', 'ry', 'rz'], last = { x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0 };
  const ts = KEYS.map((k) => k[0]), cols = {};
  for (const c of ch) cols[c] = [];
  for (const [, v] of KEYS) for (const c of ch) { if (v[c] !== undefined) last[c] = v[c]; cols[c].push(last[c]); }
  const fns = {};
  for (const c of ch) fns[c] = monotone(ts, cols[c]);
  CAMF = (t) => { const o = {}; for (const c of ch) o[c] = fns[c](t); return o; };
}
// Monotone cubic interpolation: smooth, no overshoot, eases at ends.
function monotone(ts, ys) {
  const n = ts.length, d = [], m = new Array(n).fill(0);
  for (let i = 0; i < n - 1; i++) d.push((ys[i + 1] - ys[i]) / (ts[i + 1] - ts[i]));
  for (let i = 1; i < n - 1; i++) {
    if (d[i - 1] * d[i] <= 0) m[i] = 0;
    else {
      const h0 = ts[i] - ts[i - 1], h1 = ts[i + 1] - ts[i], w1 = 2 * h1 + h0, w2 = h1 + 2 * h0;
      m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i]);
    }
  }
  return (t) => {
    if (t <= ts[0]) return ys[0];
    if (t >= ts[n - 1]) return ys[n - 1];
    let lo = 0, hi = n - 1;
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (ts[mid] > t) hi = mid; else lo = mid; }
    const h = ts[hi] - ts[lo], s = (t - ts[lo]) / h, s2 = s * s, s3 = s2 * s;
    return (2 * s3 - 3 * s2 + 1) * ys[lo] + (s3 - 2 * s2 + s) * h * m[lo] + (-2 * s3 + 3 * s2) * ys[hi] + (s3 - s2) * h * m[hi];
  };
}
let C = { x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0 };
function camAt(t) {
  const c = CAMF(t);
  if (SHORT) { c.z -= kick(t) * 28; return c; }   // zoom punch on every beat
  if (FLAT) return c;   // locked off: no handheld drift, no beat push
  // Handheld drift + a small dolly push on every beat.
  c.x += Math.sin(t * 0.37) * 10 + Math.sin(t * 0.91) * 4;
  c.y += Math.sin(t * 0.53) * 7;
  c.rz += Math.sin(t * 0.29) * 0.5;
  c.z -= kick(t) * 16;
  return c;
}

// ---------- background / fx canvases ----------
const bg = document.getElementById('bg').getContext('2d');
const fx = document.getElementById('fx').getContext('2d');
let HALF, VIG, NOISE;
const BOKEH = [], STREAKS = [];
function prerender() {
  HALF = document.createElement('canvas'); HALF.width = 2600; HALF.height = 1500;
  const h = HALF.getContext('2d');
  for (let y = 0; y < 1500; y += 17) {
    for (let x = 0; x < 2600; x += 17) {
      const band = Math.min(y, 1500 - y) / 520;              // dense at top and bottom edges
      const r = 3.6 * clamp(1 - band) * (0.75 + 0.25 * Math.sin(x * 0.01));
      if (r < 0.35) continue;
      h.fillStyle = 'rgba(170,120,255,0.55)';
      h.beginPath(); h.arc(x + (Math.floor(y / 17) % 2) * 8.5, y, r, 0, 6.283); h.fill();
    }
  }
  VIG = document.createElement('canvas'); VIG.width = W; VIG.height = H;
  const v = VIG.getContext('2d');
  const g = v.createRadialGradient(W / 2, H / 2, H * 0.35, W / 2, H / 2, H * 1.05);
  g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(0,0,0,0.72)');
  v.fillStyle = g; v.fillRect(0, 0, W, H);
  NOISE = document.createElement('canvas'); NOISE.width = 512; NOISE.height = 512;
  const n = NOISE.getContext('2d'), id = n.createImageData(512, 512), r = rng(7);
  for (let i = 0; i < id.data.length; i += 4) { const g2 = Math.floor(r() * 255); id.data[i] = id.data[i + 1] = id.data[i + 2] = g2; id.data[i + 3] = 255; }
  n.putImageData(id, 0, 0);
  const rb = rng(11);
  for (let i = 0; i < 26; i++) BOKEH.push({ x: rb() * 2600, y: rb() * 1400, r: 30 + rb() * 120, d: 0.03 + rb() * 0.12, c: ['#a26bff', '#7c3aed', '#ffffff', '#b8f53a', '#ffe14d'][Math.floor(rb() * rb() * 5)], ph: rb() * 6 });
  for (let i = 0; i < 90; i++) STREAKS.push({ a: rb() * 6.283, r0: 120 + rb() * 300, len: 200 + rb() * 700, w: 1 + rb() * 3 });
}
const THEME = [ // [time, core, mid]
  [0, '#3b0f7a', '#14042c'], [21, '#4a14a0', '#1a0640'], [42, '#2c1a8f', '#0e0730'], [63, '#3a0d5c', '#12041f'],
  [83.4, '#2b2280', '#0b0a2a'], [104, '#20103c', '#070310'], [109, '#2d1060', '#0c0420'], [114.5, '#5a19c9', '#1a0645'], [130, '#5a19c9', '#1a0645'],
];
function theme(t) {
  let i = 0; while (i < THEME.length - 2 && THEME[i + 1][0] < t) i++;
  const [t0, a0, b0] = THEME[i], [t1, a1, b1] = THEME[i + 1];
  const f = E.inOutSine(clamp((t - t0) / Math.max(0.01, Math.min(3, t1 - t0))));
  return [mix(a0, a1, f), mix(b0, b1, f)];
}
function drawBG(t) {
  if (FLAT) return drawFlatBG(t);
  const [c1, c2] = theme(t), k = kick(t);
  const cx = W / 2 + C.ry * 14 + Math.sin(t * 0.2) * 40, cy = H * 0.46 - C.rx * 14;
  const g = bg.createRadialGradient(cx, cy, 40, cx, cy, 1400);
  g.addColorStop(0, c1); g.addColorStop(0.45, c2); g.addColorStop(1, '#000');
  bg.fillStyle = g; bg.fillRect(0, 0, W, H);
  // sunburst rays
  bg.save(); bg.translate(cx, cy); bg.rotate(t * 0.05 + (C.rz * Math.PI) / 180);
  const rg = bg.createRadialGradient(0, 0, 60, 0, 0, 1500);
  rg.addColorStop(0, `rgba(190,150,255,${0.16 + k * 0.12})`); rg.addColorStop(1, 'rgba(190,150,255,0)');
  bg.fillStyle = rg;
  const n = 22;
  for (let i = 0; i < n; i++) { const a = (i / n) * 6.283; bg.beginPath(); bg.moveTo(0, 0); bg.arc(0, 0, 2200, a, a + 6.283 / n / 2); bg.closePath(); bg.fill(); }
  bg.restore();
  // halftone (parallax with the camera)
  bg.globalAlpha = 0.5 + k * 0.3;
  const hx = -340 - ((C.x * 0.05 + C.ry * 9) % 340), hy = -210 + C.rx * 4;
  bg.drawImage(HALF, hx, hy);
  bg.globalAlpha = 1;
  // bokeh
  for (const b of BOKEH) {
    const x = ((b.x - C.x * b.d - C.ry * 30 * b.d * 10 + t * 12 * b.d * 10) % 2600 + 2600) % 2600 - 340;
    const y = ((b.y + C.z * b.d * 0.08 + Math.sin(t * 0.4 + b.ph) * 20) % 1400 + 1400) % 1400 - 160;
    const rr = b.r * (1 + k * 0.15);
    const bgr = bg.createRadialGradient(x, y, 0, x, y, rr);
    const [r0, g0, b0] = hex(b.c);
    bgr.addColorStop(0, `rgba(${r0},${g0},${b0},0.22)`); bgr.addColorStop(0.7, `rgba(${r0},${g0},${b0},0.08)`); bgr.addColorStop(1, `rgba(${r0},${g0},${b0},0)`);
    bg.fillStyle = bgr; bg.beginPath(); bg.arc(x, y, rr, 0, 6.283); bg.fill();
  }
}
const FLASHES = []; // [time, strength]
let prevCam = null;
function drawFX(t) {
  fx.clearRect(0, 0, W, H);
  if (FLAT) {
    const bl = Math.max(1 - prog(t, 0, 0.35), E.inOutSine(prog(t, END - 2.2, END)));
    if (bl > 0) { fx.fillStyle = `rgba(0,0,0,${bl})`; fx.fillRect(0, 0, W, H); }
    return;
  }
  // warp streaks when the camera flies fast
  const c0 = camAt(t - 1 / 60), v = Math.hypot(C.z - c0.z, (C.x - c0.x) * 1.5) * 60 + Math.abs(C.ry - c0.ry) * 60 * 60;
  const sv = clamp((v - 900) / 2600);
  if (sv > 0.01) {
    fx.save(); fx.translate(W / 2, H / 2); fx.globalCompositeOperation = 'lighter';
    for (const s of STREAKS) {
      const r0 = s.r0 + ((t * 2200 + s.a * 500) % 900), len = s.len * sv;
      const x0 = Math.cos(s.a) * r0, y0 = Math.sin(s.a) * r0 * 0.75;
      const gr = fx.createLinearGradient(x0, y0, x0 + Math.cos(s.a) * len, y0 + Math.sin(s.a) * len * 0.75);
      gr.addColorStop(0, 'rgba(200,170,255,0)'); gr.addColorStop(1, `rgba(220,200,255,${0.5 * sv})`);
      fx.strokeStyle = gr; fx.lineWidth = s.w; fx.beginPath(); fx.moveTo(x0, y0); fx.lineTo(x0 + Math.cos(s.a) * len, y0 + Math.sin(s.a) * len * 0.75); fx.stroke();
    }
    fx.restore();
  }
  // flashes on the big hits
  let fl = 0;
  for (const [ft, st] of FLASHES) if (t >= ft) fl = Math.max(fl, st * Math.exp(-(t - ft) / 0.2));
  if (fl > 0.005) {
    const g = fx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, 1200);
    g.addColorStop(0, `rgba(255,255,255,${fl})`); g.addColorStop(1, `rgba(200,160,255,${fl * 0.5})`);
    fx.fillStyle = g; fx.fillRect(0, 0, W, H);
  }
  fx.drawImage(VIG, 0, 0);
  fx.globalAlpha = 0.045; fx.globalCompositeOperation = 'overlay';
  const nx = Math.floor((t * 977) % 512), ny = Math.floor((t * 613) % 512);
  for (let x = -nx; x < W; x += 512) for (let y = -ny; y < H; y += 512) fx.drawImage(NOISE, x, y);
  fx.globalAlpha = 1; fx.globalCompositeOperation = 'source-over';
  // fade in / out
  const black = Math.max(1 - prog(t, 0, 0.35), E.inOutSine(prog(t, END - 2.2, END)));
  if (black > 0) { fx.fillStyle = `rgba(0,0,0,${black})`; fx.fillRect(0, 0, W, H); }
}

// ---------- world ----------
function decorCluster(seed, size, x, y, z, t0, t1, pals = ['purple', 'target', 'violet', 'purple', 'lime', 'yellow', 'blue'], spin = 4) {
  return add(el(clusterSVG(seed, size, pals)), {
    x, y, z, t0, t1,
    upd(t, e) {
      popIn(e, t, t0, 0.8, 0.2);
      e.rz = e.b.rz + (t - t0) * spin * (seed % 2 ? 1 : -1);
      e.s *= 1 + kick(t) * 0.06;
      if (t1 < 1e8) fadeOut(e, t, t1 - 0.6, 0.6);
    },
  });
}
function decorSwirl(seed, size, color, width, x, y, z, a, b, rz = 0) {
  return add(el(swirlSVG(seed, size, color, width)), {
    x, y, z, rz, t0: a, t1: 1e9,
    upd(t, e) {
      const p = E.inOutCubic(prog(t, a, b));
      const path = e.path || (e.path = e.el.querySelector('.sw'));
      path.setAttribute('stroke-dashoffset', (1 - p).toFixed(4));
      e.o = p > 0 ? 1 : 0;
    },
  });
}
function dottedArc(x, y, z, pts, a, b, color = '#ffffff') {
  // pts: quadratic bezier [x0,y0, cx,cy, x1,y1] in local px
  const N = 38;
  let s = '';
  for (let i = 0; i < N; i++) {
    const u = i / (N - 1), q = (p0, p1, p2) => (1 - u) * (1 - u) * p0 + 2 * (1 - u) * u * p1 + u * u * p2;
    const px = q(pts[0], pts[2], pts[4]), py = q(pts[1], pts[3], pts[5]);
    s += `<circle class="dd" cx="${px.toFixed(1)}" cy="${py.toFixed(1)}" r="${(3 + u * 11).toFixed(1)}" fill="${color}" opacity="0"/>`;
  }
  return add(el(SVG(1400, 1000, s)), {
    x, y, z, t0: a, t1: 1e9,
    upd(t, e) {
      const dots = e.dots || (e.dots = [...e.el.querySelectorAll('.dd')]);
      const p = E.outCubic(prog(t, a, b)) * dots.length;
      dots.forEach((d, i) => d.setAttribute('opacity', clamp(p - i).toFixed(2)));
    },
  });
}

function build() {
  // ===== stars along the whole flight path =====
  const rs = rng(3);
  if (FLAT) flatScenes();
  for (let i = 0; i < (FLAT ? 0 : 170); i++) {
    let x = (rs() - 0.5) * 5200, y = (rs() - 0.5) * 2900;
    if (Math.abs(x) < 700 && Math.abs(y) < 420) x += x < 0 ? -700 : 700;
    const z = 700 - rs() * 26000, col = ['#ffffff', '#ffffff', '#c9b6ff', '#a26bff', '#b8f53a', '#ffe14d'][Math.floor(rs() * 6)];
    const sz = 22 + rs() * 50, ph = rs() * 6, spin = (rs() - 0.5) * 60;
    add(el(SVG(sz * 2, sz * 2, `<path d="${starPath(sz * 0.5)}" fill="${col}"/>`)), {
      x, y, z,
      upd(t, e) { e.s = 0.85 + 0.25 * Math.sin(t * 2.2 + ph) + kick(t) * 0.35; e.rz = t * spin; e.o = 0.9 * clamp(t * 1.5); },
    });
  }

  // ===== S0 intro (z = 0) =====
  const shock = add(el(portalSVG(520)), {
    z: -60, t0: T(0) - 0.05, t1: T(0) + 1.6,
    upd(t, e) { const p = prog(t, T(0), T(0) + 1.5); e.s = lerp(0.15, 2.6, E.outExpo(p)); e.o = 1 - E.inCubic(p); e.rz = p * 40; },
  });
  add(el(logoSVG(260)), {
    y: -170, t0: T(0), t1: T(7.6),
    upd(t, e) { popIn(e, t, T(0), 0.9, 0.2); e.s *= 1 + kick(t) * 0.05; e.ry = Math.sin(t * 0.8) * 8; fadeOut(e, t, T(6.6), 1.2); },
  });
  add(lettersEl('parallax', 'big grad', 200), {
    y: 40, t0: T(1) - 0.1, t1: T(7.6),
    upd(t, e) { revealSpans(e, t, T(1), BEAT / 4, 0.7); fadeOut(e, t, T(6.6), 1.2); },
  });
  add(wordsEl('Every side of every story.', 'sub', 66, 'font-weight:800'), {
    y: 215, t0: T(2) - 0.1, t1: T(7.6),
    upd(t, e) { revealSpans(e, t, [T(2), T(2) + BEAT, T(3), T(3) + BEAT, T(3) + BEAT * 2], 0, 0.7); fadeOut(e, t, T(6.6), 1.2); },
  });
  decorCluster(21, 560, -800, -250, -500, T(0) + 0.1, 1e9);
  decorCluster(22, 640, 790, 300, -350, T(0) + 0.3, 1e9);
  decorCluster(23, 320, 560, -360, -900, T(1), 1e9, ['lime', 'purple', 'target']);
  decorCluster(24, 300, -560, 380, -200, T(2), 1e9, ['yellow', 'violet', 'target']);
  decorSwirl(31, 520, '#ffffff', 14, -560, 120, -250, T(2), T(4));
  decorSwirl(32, 460, '#a26bff', 12, 640, -150, -450, T(2.5), T(4.5), 180);
  dottedArc(-120, 60, -150, [-560, 380, -100, -420, 600, -260], T(4), T(5.5));
  dottedArc(120, -40, -300, [560, 380, 200, -380, -500, -330], T(4.5), T(6));
  // a tunnel of rings the camera flies through into the drop
  [[-1500, 820, '#7c3aed', 1], [-2200, 760, '#b8f53a', -1], [-2900, 700, '#ffe14d', 1]].forEach(([z, R, acc, dir], i) =>
    add(el(portalSVG(R, acc)), {
      x: [0, -60, 50][i], y: [0, 30, -20][i], z, t0: T(3.5), t1: T(8) + 0.4,
      upd(t, e) { e.o = smooth(T(6.2 + i * 0.25), T(6.9 + i * 0.25), t); e.rz = (t - T(3.5)) * 12 * dir; e.s = 1 + kick(t) * 0.04; },
    }));
  key(0, { x: 0, y: 0, z: 760, rx: 0, ry: 0, rz: 0 });
  key(T(1), { z: 470 });
  key(T(4), { z: 160, ry: -5 });
  key(T(6), { z: -150, ry: 5, rz: -2 });
  key(T(7), { z: -700, ry: 0, rz: 2 });
  key(T(8) - 0.04, { z: -3350, rz: -5 });
  FLASHES.push([T(0), 0.6], [T(8), 0.75]);

  // ===== S1 drop: one story, three sides (z = -4000) =====
  const Z1 = -4000;
  add(wordsEl('One story.', 'big', 170), {
    y: -70, z: Z1, t0: T(8) - 0.05, t1: T(9) + 0.8,
    upd(t, e) { revealSpans(e, t, T(8), BEAT / 2); e.z = e.b.z - E.inCubic(prog(t, T(9), T(9) + 0.7)) * 900; fadeOut(e, t, T(9), 0.7); },
  });
  add(wordsEl('Three sides.', 'big grad', 170), {
    y: 110, z: Z1, t0: T(8) + BEAT * 2 - 0.05, t1: T(9) + 0.8,
    upd(t, e) { revealSpans(e, t, T(8) + BEAT * 2, BEAT / 2); e.z = e.b.z - E.inCubic(prog(t, T(9), T(9) + 0.7)) * 900; fadeOut(e, t, T(9), 0.7); },
  });
  const cards = [
    ['left', 'Infrastructure budget deal struck after marathon session', 'Harbor Daily', -560, 30],
    ['center', 'Lawmakers reach late-night deal on national infrastructure budget', 'Civic Wire', 0, -10],
    ['right', 'Infrastructure deal passes with bipartisan support', 'Northstar Herald', 560, 30],
  ];
  const barX = [-330, 0, 330];
  cards.forEach(([side, head, src, x, y], i) => {
    const a = T(9) + BEAT * (i + 0.5);
    add(cardEl(side, head, src), {
      x, y, z: Z1, t0: a - 0.05, t1: T(11) + 1.2,
      upd(t, e) {
        const p = E.outExpo(prog(t, a, a + 0.9));
        const dir = i - 1;
        e.x = lerp(e.b.x + dir * 500, e.b.x, p); e.z = lerp(Z1 - 1400, Z1, p);
        e.ry = lerp(-dir * 70, -dir * 12, p) + Math.sin(t * 0.9 + i) * 3; e.rx = lerp(25, 0, p);
        e.o = clamp(p * 2);
        // collapse into the lean bar
        const q = E.inOutCubic(prog(t, T(11), T(11) + 0.9));
        e.x = lerp(e.x, barX[i], q); e.y = lerp(e.b.y, 330, q); e.s = lerp(1, 0.35, q); e.o *= 1 - q;
        e.s *= 1 + kick(t) * 0.025;
      },
    });
  });
  add(wordsEl('Same story. Different headlines.', 'sub', 52, 'font-weight:800'), {
    y: -330, z: Z1, t0: T(10) - 0.05, t1: T(12) + 0.6,
    upd(t, e) { revealSpans(e, t, T(10), BEAT / 3); fadeOut(e, t, T(12), 0.5); },
  });
  add(leanBarEl(1000, [[0.4, '#3f63f5'], [0.2, '#b39bff'], [0.4, '#e5375a']]), {
    y: 300, z: Z1, t0: T(11) + 0.3, t1: T(12) + 0.7,
    upd(t, e) {
      const p = E.outExpo(prog(t, T(11) + 0.4, T(11) + 1.6));
      e.el.firstElementChild.style.clipPath = `inset(0 ${((1 - p) * 100).toFixed(1)}% 0 0 round 99px)`;
      e.o = clamp(p * 3); e.s = 1 + kick(t) * 0.02;
      e.rx = -E.inCubic(prog(t, T(12), T(12) + 0.6)) * 70; fadeOut(e, t, T(12), 0.6);
    },
  });
  add(wordsEl('See how left, center and right cover it.', 'sub', 46), {
    y: 120, z: Z1, t0: T(11) + 0.8, t1: T(12) + 0.6,
    upd(t, e) { revealSpans(e, t, T(11) + BEAT * 2, BEAT / 4); fadeOut(e, t, T(12), 0.5); },
  });
  // feed phones
  const ph1 = add(phoneEl('02_for_you_dark.png'), {
    x: 400, y: 60, z: Z1, ry: -14, t0: T(12) - 0.1, t1: T(16) + 2.5,
    upd(t, e) {
      const p = E.outExpo(prog(t, T(12), T(12) + 1.3));
      e.y = lerp(1100, e.b.y, p); e.rx = lerp(40, 0, p); e.ry = e.b.ry + Math.sin(t * 0.6) * 4;
      e.o = clamp(p * 3);
      fadeOut(e, t, T(16) + 1.2, 1.2);
    },
  });
  add(phoneEl('01_for_you.png'), {
    x: 820, y: 110, z: Z1 - 450, ry: -20, t0: T(12) + 0.2, t1: T(16) + 2.5,
    upd(t, e) {
      const p = E.outExpo(prog(t, T(12) + BEAT, T(12) + BEAT + 1.3));
      e.y = lerp(1300, e.b.y, p); e.o = clamp(p * 3) * 0.9; e.ry = e.b.ry + Math.sin(t * 0.6 + 1) * 4;
      fadeOut(e, t, T(16) + 1.2, 1.2);
    },
  });
  add(wordsEl('Your feed, | with the full picture.', 'big', 74, 'line-height:1.05'), {
    x: -470, y: -400, z: Z1, t0: T(12) + BEAT - 0.05, t1: T(16) + 1.5,
    upd(t, e) { revealSpans(e, t, T(12) + BEAT, BEAT / 3); fadeOut(e, t, T(16), 1); },
  });
  // callouts: screen top = 60 - 394 + 15 = -319; y = top + f * 788
  const scrY = (f, cy = 60) => cy - 394 + 15 + f * 788;
  [['Catch up in one tap', 0.10, SHORT ? T(12) + BEAT * 2 : T(13)], ['Real photos, real outlets', 0.3, SHORT ? T(13) : T(13) + BEAT * 2],
    ['Left, center, right on every story', 0.468, SHORT ? T(13) + BEAT * 2 : T(14)]].forEach(([txt, f, a], i) => {
    const y = scrY(f);
    add(pillEl(txt, 400, 'right'), {
      x: -170, y, z: Z1, ax: 100, t0: a - 0.05, t1: T(16) + 1.5,
      upd(t, e) {
        const p = E.outExpo(prog(t, a, a + 0.7));
        e.x = lerp(-700, e.b.x, p); e.o = clamp(p * 2); e.ry = lerp(30, 0, p);
        const line = e.line || (e.line = e.el.lastElementChild);
        line.style.clipPath = `inset(0 ${((1 - E.outExpo(prog(t, a + 0.3, a + 1))) * 100).toFixed(1)}% 0 0)`;
        fadeOut(e, t, T(16) + 0.2 * i, 1);
      },
    });
  });
  decorCluster(41, 480, -1050, 430, Z1 - 500, T(8), 1e9);
  decorCluster(42, 560, 1100, 420, Z1 - 700, T(8) + 0.4, 1e9, ['target', 'purple', 'lime']);
  decorSwirl(43, 600, '#ffffff', 12, -900, 350, Z1 - 300, T(12), T(14));
  key(T(8) + 0.9, { z: Z1 + 60, rz: 0 });
  key(T(10), { z: Z1, ry: 0 });
  key(T(12), { x: 0, z: Z1 - 30, ry: -3 });
  key(T(14), { x: 60, z: Z1 - 80, ry: 6 });
  key(T(16), { x: 260, z: Z1 - 250, ry: 8 });
  FLASHES.push([T(12), 0.25]);

  // ===== S2/S3 story deep dive (x = 1400, z = -8000) =====
  const X3 = 1400, Z3 = -8000;
  if (!SHORT) add(wordsEl('Open any story.', 'big grad', 130), {
    x: X3, y: -60, z: Z3 + 500, t0: T(16.4), t1: T(18) + 0.7,
    upd(t, e) { revealSpans(e, t, T(16.5), BEAT, 1.4); e.z = e.b.z + E.inExpo(prog(t, T(17.6), T(18) + 0.4)) * 900; fadeOut(e, t, T(17.8), 0.5); },
  });
  add(phoneEl('03_story_coverage.png'), {
    x: X3, y: 60, z: Z3, t0: T(17), t1: T(24) + 0.6,
    upd(t, e) {
      const p = E.outExpo(prog(t, T(17.6), T(18) + 0.5));
      e.y = lerp(900, e.b.y, p); e.ry = lerp(40, 0, p) + Math.sin(t * 0.7) * 5; e.o = clamp(p * 3);
      e.s = 1 + kick(t) * 0.012;
      // make room for the second phone
      const q = SHORT ? 0 : E.inOutCubic(prog(t, T(22), T(22) + 1.2));
      e.x = e.b.x - q * 260; e.ry -= q * 10;
    },
  });
  add(wordsEl('See how each side tells it.', 'big', 84), {
    x: X3, y: -455, z: Z3, t0: T(18) + BEAT - 0.05, t1: T(24) + 0.6,
    upd(t, e) { revealSpans(e, t, T(18) + BEAT, BEAT / 3); fadeOut(e, t, T(23.5), 0.5); },
  });
  const sy = (f) => scrY(f, 60);
  [['Coverage split, measured', 0.39, T(19), -1], ['TL;DR in the outlets’ own words', 0.5, T(20), 1], ['How each side headlined it', 0.68, T(21), -1]].forEach(([txt, f, a, side]) => {
    const y = sy(f);
    const px = side < 0 ? X3 - 330 : X3 + 330;
    add(pillEl(txt, 180, side < 0 ? 'right' : 'left'), {
      x: px, y, z: Z3 + 30, ax: side < 0 ? 100 : 0, t0: a - 0.05, t1: T(22) + 0.6,
      upd(t, e) {
        const p = E.outExpo(prog(t, a, a + 0.7));
        e.x = lerp(px + side * 450, px, p); e.o = clamp(p * 2); e.ry = side * lerp(-30, 0, p);
        const line = e.line || (e.line = e.el.lastElementChild), lp = (1 - E.outExpo(prog(t, a + 0.3, a + 1))) * 100;
        line.style.clipPath = side < 0 ? `inset(0 ${lp.toFixed(1)}% 0 0)` : `inset(0 0 0 ${lp.toFixed(1)}%)`;
        fadeOut(e, t, T(22), 0.5);
      },
    });
  });
  if (!SHORT) add(phoneEl('06_sources.png'), {
    x: X3 + 420, y: 80, z: Z3 - 200, ry: -16, t0: T(22) - 0.1, t1: T(24) + 0.6,
    upd(t, e) { const p = E.outExpo(prog(t, T(22), T(22) + 1.4)); e.x = lerp(X3 + 1500, e.b.x, p); e.o = clamp(p * 3); e.ry = e.b.ry + Math.sin(t * 0.6) * 4; },
  });
  if (!SHORT) add(pillEl('Every outlet rated: lean, factuality, owner', 0), {
    x: X3 + 120, y: 470, z: Z3 + 60, t0: T(22) + BEAT * 2 - 0.05, t1: T(24) + 0.6,
    upd(t, e) { popIn(e, t, T(22) + BEAT * 2, 0.7, 0.5); },
  });
  decorCluster(51, 520, X3 + 1000, -380, Z3 - 500, T(17), 1e9, ['purple', 'violet', 'target']);
  decorCluster(52, 420, X3 - 1050, 420, Z3 - 400, T(18), 1e9, ['lime', 'target', 'purple']);
  decorSwirl(53, 520, '#a26bff', 12, X3 - 900, -330, Z3 - 300, T(18), T(20));
  key(T(17), { x: 900, z: -6300, ry: 14, rz: 3 });
  key(T(18), { x: X3, z: Z3 + 80, ry: 0, rz: 0 });
  key(T(20), { x: X3 - 40, z: Z3, ry: -4 });
  key(T(22), { x: X3 + 60, z: Z3 - 40, ry: 5 });
  key(T(23.5), { x: X3 + 200, z: Z3 - 250, ry: 12 });
  FLASHES.push([T(18), 0.55]);

  // ===== S4 blindspots (z = -12000) =====
  const Z4 = -12000;
  const eye = add(el(eyeOffSVG(240)), {
    y: -190, z: Z4, t0: T(24) - 0.05, t1: T(29) + 0.6,
    upd(t, e) {
      const p = E.outExpo(prog(t, T(24), T(24) + 0.8));
      e.s = lerp(3, 1, p) * (1 + kick(t) * 0.05); e.o = clamp(p * 2); e.rz = (1 - p) * -25;
      const q = E.inOutCubic(prog(t, T(26), T(26) + 0.9));
      e.x = lerp(0, -600, q); e.y = lerp(e.b.y, -330, q); e.s *= lerp(1, 0.5, q);
      fadeOut(e, t, T(29), 0.6);
    },
  });
  add(wordsEl('Blindspots', 'big grad', 210), {
    y: 60, z: Z4, t0: T(24) + BEAT - 0.05, t1: T(29) + 0.6,
    upd(t, e) {
      revealSpans(e, t, T(24) + BEAT, 0.1, 0.6);
      const q = E.inOutCubic(prog(t, T(26), T(26) + 0.9));
      e.x = lerp(0, -470, q); e.y = lerp(e.b.y, -190, q); e.s = lerp(1, 0.48, q);
      fadeOut(e, t, T(29), 0.6);
    },
  });
  add(wordsEl('The stories one side barely covers.', 'sub', 52), {
    y: 220, z: Z4, t0: T(25) - 0.05, t1: T(29) + 0.6,
    upd(t, e) {
      revealSpans(e, t, T(25), BEAT / 3);
      const q = E.inOutCubic(prog(t, T(26), T(26) + 0.9));
      e.x = lerp(0, -470, q); e.y = lerp(e.b.y, -90, q); e.s = lerp(1, 0.72, q);
      fadeOut(e, t, T(29), 0.6);
    },
  });
  add(phoneEl('04_blindspot.png'), {
    x: 430, y: 60, z: Z4, ry: -12, t0: T(26) - 0.1, t1: T(32) + 0.4,
    upd(t, e) { const p = E.outExpo(prog(t, T(26), T(26) + 1.2)); e.y = lerp(1100, e.b.y, p); e.rx = lerp(35, 0, p); e.o = clamp(p * 3); e.ry = e.b.ry + Math.sin(t * 0.7) * 5; },
  });
  [['Blindspots', 'One side barely covers it', FLAT ? '#7c3aed' : 'linear-gradient(160deg,#9b5cff,#4a1aa8)', -330, 160, 380, 230],
    ['Underreported', 'Few outlets, reliable sources', FLAT ? '#0b0613' : 'linear-gradient(160deg,#2a2433,#0b0812)', -660, 430, 300, 200],
    ['Divergent takes', 'Both sides, different framing', FLAT ? '#4c1d95' : 'linear-gradient(160deg,#5b33b0,#26104f)', -320, 430, 300, 200]].forEach(([ti, su, bgc, x, y, w, h], i) => {
    const a = T(27) + i * BEAT;
    add(tileEl(ti, su, bgc, w, h), {
      x, y, z: Z4 + 80, t0: a - 0.05, t1: T(32) + 0.4,
      upd(t, e) {
        const p = E.outBack(prog(t, a, a + 0.8));
        e.x = lerp(430, e.b.x, p); e.y = lerp(60, e.b.y, p); e.s = lerp(0.2, 1, clamp(p)); e.o = clamp(prog(t, a, a + 0.3));
        e.ry = 10 + Math.sin(t * 0.8 + i) * 6; e.rx = Math.sin(t * 0.6 + i) * 4; e.s *= 1 + kick(t) * 0.03;
        // move up once the title leaves
        e.y -= E.inOutCubic(prog(t, T(29), T(29) + 0.8)) * 120;
      },
    });
  });
  if (!SHORT) add(wordsEl('Break out of | your bubble.', 'big', 92, 'line-height:1.02'), {
    x: -480, y: -300, z: Z4, t0: T(29) + 0.3, t1: T(32) + 0.4,
    upd(t, e) { revealSpans(e, t, T(29) + BEAT, BEAT / 3); },
  });
  [[FLAT ? -1320 : -1050, FLAT ? -440 : -350, 61, T(29)], [1050, 380, 62, T(30)], [-1000, 420, 63, T(31)], [1000, -380, 64, T(31) + BEAT * 2]].forEach(([x, y, seed, a]) =>
    add(el(clusterSVG(seed, 520, ['purple', 'target', 'violet', 'yellow'])), {
      x, y, z: Z4 - 300, t0: a - 0.05, t1: 1e9,
      upd(t, e) { const p = prog(t, a, a + 0.7); e.s = lerp(0.1, 1, E.outBack(p)) * (1 + kick(t) * 0.07); e.o = clamp(p * 3); e.rz = (t - a) * 10; },
    }));
  key(T(24) - 0.04, { x: 350, z: Z4 + 450, ry: -20, rz: -6 });
  key(T(24) + 0.6, { x: 0, z: Z4 + 40, ry: -3, rz: 0 });
  key(T(26), { x: 0, z: Z4, ry: 0 });
  key(T(28), { x: -40, z: Z4 - 40, ry: -5, rx: 2 });
  key(T(30), { x: 40, z: Z4 - 80, ry: 5, rx: 0 });
  key(T(31.4), { x: 0, z: Z4 - 500, ry: 0 });
  FLASHES.push([T(24), 0.7]);

  // ===== S5 from the world to your street (z = -16000) =====
  const Z5 = -16000;
  const globe = canvasEl(1000, 1000);
  const G0 = SHORT ? T(31.4) - 0.35 : T(31.4);
  add(globe, {
    z: Z5, t0: G0, t1: T(34) + 1.5,
    upd(t, e) { drawGlobe(globe.getContext('2d'), t); e.o = smooth(G0, T(32), t); e.s = (FLAT ? 0.86 : 1) + kick(t) * 0.03; },
  });
  add(wordsEl('From the world', 'big', 120), {
    y: FLAT ? -428 : -405, z: Z5, t0: T(32) - 0.05, t1: T(34) + 0.6,
    upd(t, e) { revealSpans(e, t, T(32), BEAT / 2); fadeOut(e, t, T(34), 0.4); },
  });
  add(wordsEl('to your street.', 'big grad', 120), {
    y: FLAT ? 432 : 410, z: Z5, t0: T(33) - 0.05, t1: T(34) + 0.6,
    upd(t, e) { revealSpans(e, t, T(33), BEAT / 2); fadeOut(e, t, T(34), 0.4); },
  });
  const gates = [['North America', -16700], ['United States', -17300], ['New York', -17900], ['Brooklyn', -18500]];
  gates.forEach(([name, z], i) => {
    const a = T(34) + BEAT * i;
    add(el(portalSVG(620, ['#7c3aed', '#3f63f5', '#b8f53a', '#ffe14d'][i])), {
      x: (i % 2 ? 1 : -1) * 40, z, t0: T(33), t1: i === 3 ? T(36) + 0.2 : a + BEAT * 1.6,
      upd(t, e) { e.o = smooth(T(33), T(34), t); e.rz = t * 20 * (i % 2 ? 1 : -1); e.s = 1 + kick(t) * 0.04; },
    });
    const reach = T(34) + BEAT * (i + 1);   // when the camera flies through this gate
    add(el(`<div class="glass pill" style="font-size:56px;padding:20px 40px 20px 30px"><span class="dot" style="width:26px;height:26px"></span>${name}</div>`), {
      y: i === 3 ? 0 : -330, z: z + 10, t0: T(33), t1: i === 3 ? T(36) + 0.2 : reach + 0.2,
      upd(t, e) {
        e.o = smooth(T(33), T(34), t) * (i === 3 ? 1 : 1 - smooth(reach - 0.3, reach - 0.05, t)); e.s = 1 + kick(t) * 0.03;
        if (i === 3) { const q = E.inOutCubic(prog(t, T(35) + BEAT * 2, T(35) + BEAT * 3)); e.y = lerp(0, -470, q); e.s *= lerp(1.25, 0.8, q); fadeOut(e, t, T(36) - 0.3, 0.5); }
      },
    });
  });
  add(phoneEl('05_explore.png'), {
    x: -420, y: 60, z: -19000, ry: 10, t0: T(35), t1: T(40) + 0.4,
    upd(t, e) { const p = E.outExpo(prog(t, T(35) + BEAT * 2, T(36) + 0.6)); e.y = lerp(1000, e.b.y, p); e.o = clamp(p * 3); e.ry = e.b.ry + Math.sin(t * 0.6) * 4; },
  });
  add(wordsEl('Real local outlets', 'big', 86), {
    x: 360, y: -150, z: -19000, t0: T(36) - 0.05, t1: T(40) + 0.4,
    upd(t, e) { revealSpans(e, t, T(36), BEAT / 2); },
  });
  add(wordsEl('for any town on earth.', 'big grad', 86), {
    x: 360, y: -40, z: -19000, t0: T(36) + BEAT * 2 - 0.05, t1: T(40) + 0.4,
    upd(t, e) { revealSpans(e, t, T(36) + BEAT * 2, BEAT / 2); },
  });
  [['Papers, radio and TV, found for you', T(37), 150], ['Follow places and topics', T(38), 250], ['Search any place by name', T(38) + BEAT * 2, 350]].forEach(([txt, a, y]) =>
    add(pillEl(txt, 0), {
      x: 360, y: y + 30, z: -19000, t0: a - 0.05, t1: T(40) + 0.4,
      upd(t, e) { const p = E.outExpo(prog(t, a, a + 0.7)); e.y = lerp(e.b.y + 120, e.b.y, p); e.o = clamp(p * 2); e.rx = lerp(-50, 0, p); },
    }));
  decorCluster(71, 520, -1100, -360, -19300, T(35), 1e9, ['lime', 'target', 'purple']);
  decorCluster(72, 560, 1150, 400, -19400, T(35), 1e9, ['yellow', 'purple', 'violet']);
  key(T(32) - 0.06, { x: 0, z: Z5 + 120, ry: 0, rx: 0 });
  key(T(34), { x: 0, z: Z5 - 40 });
  key(T(34) + BEAT, { z: -16700 + 60, x: -40 });
  key(T(34) + BEAT * 2, { z: -17300 + 60, x: 40 });
  key(T(34) + BEAT * 3, { z: -17900 + 60, x: -40 });
  key(T(35), { z: -18500 + 80, x: 0 });
  key(T(36), { x: 0, z: -19000, ry: -2.5 });
  key(T(38), { x: 15, z: -19040, ry: 2.5 });
  key(T(39.5), { x: 0, z: -19500, ry: 0 });
  FLASHES.push([T(32), 0.45]);

  // ===== S6 values (z = -21000) =====
  const Z6 = -21000;
  if (!FLAT) add(el(clusterSVG(81, 1500, ['target', 'purple', 'violet'])), {
    z: Z6 - 700, t0: T(39.5), t1: T(42) + 1,
    upd(t, e) { e.o = 0.55 * smooth(T(39.6), T(40), t); e.rz = t * 6; e.s = 1 + kick(t) * 0.05; fadeOut(e, t, T(42), 0.8); },
  });
  ['No account.', 'No ads.', 'No tracking.', 'No paywall.'].forEach((w, i) => {
    const a = T(40) + BEAT * 2 * i, b = a + BEAT * 2;
    add(el(`<div class="big" style="font-size:230px">${w}<div style="height:16px;border-radius:9px;margin-top:10px;${FLAT ? 'background:var(--fg)' : 'background:#b8f53a;box-shadow:0 0 30px #b8f53a'}"></div></div>`), {
      z: Z6, t0: a - 0.05, t1: i === 3 ? T(42) + 0.6 : b + 0.4,
      upd(t, e) {
        const p = E.outExpo(prog(t, a, a + 0.45));
        e.s = lerp(1.8, 1, p) * (1 + kick(t) * 0.03); e.o = clamp(p * 2); e.rx = lerp(-60, 0, p);
        const line = e.line || (e.line = e.el.lastElementChild);
        line.style.transform = `scaleX(${E.outExpo(prog(t, a + 0.15, a + 0.8)).toFixed(3)})`;
        // the short cut clears each word just before the next lands, so they never overlap
        if (i < 3) { const q = SHORT ? E.inCubic(prog(t, b - 0.24, b + 0.03)) : E.inCubic(prog(t, b - 0.12, b + 0.25)); e.rx += q * 80; e.z = Z6 + q * 500; e.o *= 1 - q; }
        else fadeOut(e, t, T(42), 0.7);
      },
    });
  });
  key(T(40) - 0.05, { x: 0, z: Z6 + 120, ry: 0 });
  key(T(42), { x: 0, z: Z6 - 80 });
  FLASHES.push([T(40), 0.4]);

  // ===== S7 breakdown: open source (z = -22600) =====
  const Z7 = -22600;
  const OS_OUT = SHORT ? T(44) - 0.15 : T(43.6);
  add(el(logoSVG(160)), {
    y: -250, z: Z7, t0: T(42), t1: T(44) + 0.6,
    upd(t, e) { e.o = SHORT ? smooth(T(42), T(42) + 0.6, t) : smooth(T(42) + 0.2, T(42) + 1.4, t); e.ry = Math.sin(t) * 10; fadeOut(e, t, OS_OUT, 0.6); },
  });
  add(wordsEl('Open source.', 'big', 150), {
    y: -40, z: Z7, t0: T(42), t1: T(44) + 0.6,
    upd(t, e) { if (SHORT) revealSpans(e, t, T(42), BEAT / 2, 0.6); else revealSpans(e, t, T(42) + BEAT, BEAT, 1.2); fadeOut(e, t, OS_OUT, 0.6); },
  });
  add(wordsEl('Free, forever.', 'big grad', 150), {
    y: 140, z: Z7, t0: T(43), t1: T(44) + 0.6,
    upd(t, e) { if (SHORT) revealSpans(e, t, T(42) + BEAT * 2, BEAT / 2, 0.6); else revealSpans(e, t, T(43), BEAT, 1.2); fadeOut(e, t, OS_OUT, 0.6); },
  });
  decorSwirl(91, 640, '#ffffff', 12, -720, 60, Z7 - 200, T(42), T(43.5));
  decorSwirl(92, 600, '#b8f53a', 10, 720, -40, Z7 - 250, T(42.3), T(43.8), 180);
  key(T(43), { x: -120, z: Z7 + 60, ry: -5 });
  key(T(43.6), { x: 0, z: Z7 - 200, ry: 0 });

  // ===== S8 finale (z = -24000) =====
  const Z8 = -24000;
  const eq = canvasEl(2000, 440);
  add(eq, {
    y: 250, z: Z8 - 350, t0: T(43.8), t1: 1e9,
    upd(t, e) { drawEQ(eq.getContext('2d'), t, E.outCubic(prog(t, T(44), T(44) + 1.2))); e.o = FLAT ? 1 : 0.6; },
  });
  if (!FLAT) add(el(`<div style="width:1500px;height:700px;border-radius:50%;background:radial-gradient(closest-side,rgba(10,2,26,.75),rgba(10,2,26,0))"></div>`), {
    y: 60, z: Z8 - 60, t0: T(44), t1: 1e9,
    upd(t, e) { e.o = smooth(T(44), T(45), t); },
  });
  add(el(`<div style="width:5200px;height:6px;border-radius:3px;background:#fff;${FLAT ? '' : 'box-shadow:0 0 18px #fff,0 0 50px #a26bff,0 0 120px #7c3aed'}"></div>`), {
    y: 470, z: Z8 - 300, t0: T(44), t1: 1e9,
    upd(t, e) { const p = E.outExpo(prog(t, T(44), T(44) + 1.2)); e.el.style.transform = ''; e.s = 1; e.el.style.clipPath = `inset(0 ${((1 - p) * 50).toFixed(1)}% 0 ${((1 - p) * 50).toFixed(1)}%)`; e.o = p > 0 ? 1 : 0; },
  });
  add(el(logoSVG(240)), {
    y: -350, z: Z8, t0: T(44) - 0.05, t1: 1e9,
    upd(t, e) { popIn(e, t, T(44), 0.9, 0.2); e.s *= 1 + kick(t) * 0.05; e.ry = Math.sin(t * 0.8) * 10; },
  });
  add(lettersEl('parallax', 'big grad', 220), {
    y: -140, z: Z8, t0: T(44) + BEAT - 0.05, t1: 1e9,
    upd(t, e) { revealSpans(e, t, T(44) + BEAT, BEAT / 4, 0.7); e.s = 1 + kick(t) * 0.015; },
  });
  add(wordsEl('Every side of every story.', 'sub', 60, 'font-weight:800'), {
    y: 30, z: Z8, t0: T(45) - 0.05, t1: 1e9,
    upd(t, e) { revealSpans(e, t, T(45), BEAT / 3); },
  });
  add(el(FLAT
    ? `<div style="display:inline-flex;align-items:center;gap:18px;padding:22px 46px;border-radius:99px;background:#b8f53a;color:#0b0613;font-weight:900;font-size:46px;white-space:nowrap">Free on GitHub<span style="width:16px;height:16px;border-radius:50%;background:#0b0613"></span></div>`
    : `<div style="display:inline-flex;align-items:center;gap:18px;padding:22px 46px;border-radius:99px;background:linear-gradient(180deg,#ffffff,#e6dcff);color:#4b16b8;font-weight:900;font-size:46px;white-space:nowrap;box-shadow:0 0 0 2px #fff inset,0 0 60px rgba(184,245,58,.55),0 20px 60px rgba(0,0,0,.5)">Free on GitHub<span style="width:16px;height:16px;border-radius:50%;background:#b8f53a;box-shadow:0 0 16px #b8f53a"></span></div>`), {
    y: 160, z: Z8 + 20, t0: T(46) - 0.05, t1: 1e9,
    upd(t, e) { popIn(e, t, T(46), 0.7, 0.3); e.s *= 1 + kick(t) * 0.025; },
  });
  add(el(`<div class="sub" style="font-size:34px;font-weight:600;opacity:.9">github.com/JackLongman12/parallax-news</div>`), {
    y: 252, z: Z8 + 20, t0: T(46) + BEAT - 0.05, t1: 1e9,
    upd(t, e) { e.o = E.outCubic(prog(t, T(46) + BEAT, T(46) + BEAT + 0.6)); },
  });
  decorCluster(101, 600, -1120, -300, Z8 - 450, T(44), 1e9, ['purple', 'target', 'lime', 'violet']);
  decorCluster(102, 560, 1140, -320, Z8 - 500, T(44) + 0.2, 1e9, ['purple', 'yellow', 'target', 'blue']);
  decorCluster(103, 320, -1250, 330, Z8 - 200, T(45), 1e9, ['lime', 'target']);
  decorCluster(104, 300, 1250, 350, Z8 - 220, T(45) + 0.3, 1e9, ['yellow', 'violet']);
  dottedArc(-200, -60, Z8 - 120, [-640, 360, -300, -480, 520, -420], T(44) + 0.4, T(45.6));
  dottedArc(200, -60, Z8 - 140, [640, 380, 260, -460, -560, -440], T(44) + 0.8, T(46));
  decorSwirl(105, 560, '#ffffff', 12, -860, 330, Z8 - 150, T(45), T(46.5));
  decorSwirl(106, 520, '#a26bff', 12, 870, 330, Z8 - 160, T(45.3), T(46.8), 180);
  key(T(44) - 0.05, { x: 0, z: Z8 + 900, ry: 0, rx: 0, rz: 0 });
  key(T(44) + 0.9, { z: Z8 + 120 });
  key(T(46), { z: Z8 + 40, ry: -3 });
  key(T(48), { z: Z8 - 80, ry: 3 });
  FLASHES.push([T(44), 0.65]);
  if (SHORT) shortCamera();
  else if (FLAT) flatCamera();
  buildCamera();
}

function drawGlobe(ctx, t) {
  const S = 1000, R = 380;
  ctx.clearRect(0, 0, S, S);
  ctx.save(); ctx.translate(S / 2, S / 2);
  if (!FLAT) {
    const g = ctx.createRadialGradient(0, 0, R * 0.1, 0, 0, R * 1.3);
    g.addColorStop(0, 'rgba(124,58,237,0.45)'); g.addColorStop(0.75, 'rgba(90,30,200,0.18)'); g.addColorStop(1, 'rgba(124,58,237,0)');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, R * 1.3, 0, 6.283); ctx.fill();
  }
  const sph = ctx.createRadialGradient(-R * 0.35, -R * 0.4, R * 0.1, 0, 0, R);
  sph.addColorStop(0, '#5b2bc4'); sph.addColorStop(0.6, '#2a0f63'); sph.addColorStop(1, '#12052e');
  ctx.fillStyle = FLAT ? '#0b0613' : sph; ctx.beginPath(); ctx.arc(0, 0, R, 0, 6.283); ctx.fill();
  ctx.strokeStyle = FLAT ? '#ffffff' : 'rgba(200,170,255,0.8)'; ctx.lineWidth = FLAT ? 6 : 3; ctx.shadowColor = '#a26bff'; ctx.shadowBlur = FLAT ? 0 : 30;
  ctx.beginPath(); ctx.arc(0, 0, R, 0, 6.283); ctx.stroke(); ctx.shadowBlur = 0;
  const rot = t * 0.45, tilt = 0.38, k = kick(t);
  for (let lat = -84; lat <= 84; lat += 4.5) {
    const la = (lat * Math.PI) / 180, cnt = Math.max(8, Math.round(96 * Math.cos(la)));
    for (let j = 0; j < cnt; j++) {
      const lo = (j / cnt) * 6.283 + rot;
      const x = Math.cos(la) * Math.sin(lo), y = Math.sin(la), z = Math.cos(la) * Math.cos(lo);
      const y2 = y * Math.cos(tilt) - z * Math.sin(tilt), z2 = y * Math.sin(tilt) + z * Math.cos(tilt);
      // fake continents: density from a smooth noise of lat/lon
      const land = Math.sin(lo * 2.1 + 1.3) * Math.cos(la * 3.1) + Math.sin(lo * 4.3 - la * 2) * 0.5 > 0.35;
      if (z2 > 0) {
        ctx.fillStyle = land ? `rgba(184,245,58,${0.5 + 0.5 * z2})` : `rgba(255,255,255,${0.25 + 0.55 * z2})`;
        if (!land && z2 < 0.15) continue;
        const r = (land ? 3.2 : 1.7) * (0.55 + 0.45 * z2) * (1 + k * 0.3);
        ctx.beginPath(); ctx.arc(x * R, -y2 * R, r, 0, 6.283); ctx.fill();
      }
    }
  }
  ctx.rotate(-0.32);
  ctx.strokeStyle = 'rgba(255,255,255,0.75)'; ctx.lineWidth = 3;
  ctx.beginPath(); ctx.ellipse(0, 0, R * 1.32, R * 0.3, 0, 0, 6.283); ctx.stroke();
  const a = t * 1.6;
  ctx.fillStyle = '#b8f53a'; ctx.shadowColor = '#b8f53a'; ctx.shadowBlur = FLAT ? 0 : 24;
  ctx.beginPath(); ctx.arc(Math.cos(a) * R * 1.32, Math.sin(a) * R * 0.3, 11, 0, 6.283); ctx.fill();
  ctx.restore();
}
function drawEQ(ctx, t, amp) {
  const Wd = 2000, Hd = 620;
  ctx.clearRect(0, 0, Wd, Hd);
  const cols = 30, cw = 50, gap = 16, bh = 16, bgap = 6, x0 = (Wd - cols * (cw + gap)) / 2;
  ctx.shadowColor = 'rgba(162,107,255,0.95)'; ctx.shadowBlur = FLAT ? 0 : 22;
  for (let c = 0; c < cols; c++) {
    const b = (Math.abs(c - (cols - 1) / 2) / ((cols - 1) / 2)) * 7;           // bass in the middle
    let lvl = bandAt(7 - b, t) * 0.75 + energyAt(t) * 0.35 + kick(t) * 0.25 * (1 - b / 9);
    lvl *= 0.75 + 0.25 * Math.sin(c * 1.7 + t * 6);
    const n = Math.floor(clamp(lvl * amp) * (Hd / (bh + bgap)));
    for (let i = 0; i < n; i++) {
      const y = Hd - (i + 1) * (bh + bgap);
      ctx.fillStyle = FLAT ? '#5b21b6' : i === n - 1 ? '#ffffff' : `rgba(255,255,255,${0.55 + 0.45 * (i / n)})`;
      ctx.fillRect(x0 + c * (cw + gap), y, cw, bh);
    }
  }
  ctx.shadowBlur = 0;
}

// ---------- flat cut ----------
// Each scene: [start, background, text, accent text, pill bg, pill text, dot, wipe]
const FSC = [];
function flatScenes() {
  const K = '#0b0613', PU = '#7c3aed', WH = '#ffffff', PA = '#f4f1fa', YE = '#ffe14d', LI = '#b8f53a';
  FSC.push(
    [0, K, WH, '#a78bfa', WH, K, PU, 'none'],
    [T(8), PU, WH, YE, WH, K, PU, 'iris'],
    [T(12), PA, K, PU, K, WH, LI, 'left'],
    [T(16) + 0.9, K, WH, LI, WH, K, PU, 'right'],
    // the short cut starts these two wipes a moment early so they carry the flight between scenes
    [SHORT ? T(24) - 0.25 : T(24), YE, K, PU, K, WH, LI, 'iris'],
    [SHORT ? T(31.4) - 0.2 : T(31.4), PU, WH, LI, WH, K, PU, 'up'],
    [T(35) + BEAT * 2, PA, K, PU, K, WH, LI, 'down'],
    [T(40), LI, K, PU, K, WH, LI, 'left'],
    [T(42), K, WH, YE, WH, K, PU, 'iris'],
    [T(44), PU, WH, LI, WH, K, PU, 'iris'],
  );
}
let FCUR = -1;
function drawFlatBG(t) {
  let i = 0;
  while (i < FSC.length - 1 && FSC[i + 1][0] <= t) i++;
  const s = FSC[i], prev = FSC[Math.max(0, i - 1)];
  if (i !== FCUR) {
    FCUR = i;
    const st = document.body.style;
    ['--fg', '--acc', '--pill-bg', '--pill-fg', '--dot'].forEach((v, j) => st.setProperty(v, s[2 + j]));
  }
  const p = s[7] === 'none' ? 1 : E.outQuint(prog(t, s[0], s[0] + 0.6));
  bg.fillStyle = p < 1 ? prev[1] : s[1];
  bg.fillRect(0, 0, W, H);
  if (p >= 1) return;
  bg.fillStyle = s[1];
  bg.beginPath();
  const sl = 360;
  if (s[7] === 'iris') bg.arc(W / 2, H / 2, p * 1120, 0, 6.283);
  else if (s[7] === 'left') { const x = p * (W + sl); bg.moveTo(0, 0); bg.lineTo(x, 0); bg.lineTo(x - sl, H); bg.lineTo(0, H); }
  else if (s[7] === 'right') { const x = W - p * (W + sl); bg.moveTo(W, 0); bg.lineTo(x + sl, 0); bg.lineTo(x, H); bg.lineTo(W, H); }
  else if (s[7] === 'up') bg.rect(0, H - p * H, W, p * H);
  else bg.rect(0, 0, W, p * H);
  bg.fill();
}
/* Camera for the flat cut: mostly locked-off shots, hard cuts on the beat,
   and one distinct move per scene (dutch settle, barrel roll, low angle,
   truck, high angle, orbit, crane, stepped roll, overhead tilt, crane down). */
function flatCamera() {
  const k = fkey, F = 1 / 60, R = 360, R2 = 720;
  // hard cut on the first video frame at or after t
  const cut = (t, v) => { const tc = Math.ceil(t / F - 1e-6) * F; k(tc - F + 0.002, {}); k(tc - 0.002, v); };
  const Z1 = -4000, X3 = 1400, Z3 = -8000, Z4 = -12000, Z5 = -16000, ZE = -19000, Z6 = -21000, Z7 = -22600, Z8 = -24000;

  // S0 intro: opens on a low dutch angle that rights itself, holds, then
  // crash-zooms through the ring tunnel with a full barrel roll.
  k(0, { x: -140, y: 160, z: 760, rx: -12, ry: -16, rz: -12 });
  k(T(2), { x: 0, y: 0, z: 560, rx: 0, ry: 0, rz: 0 });
  k(T(6), { z: 480 });
  k(T(7), { z: 330 });
  k(T(8) - 0.04, { z: -3350, rz: R });

  // S1: low-angle hero on the title, then a lateral truck across the three headlines
  k(T(8) + 0.9, { x: 0, y: 60, z: Z1 + 120, rx: -9, ry: 0 });
  k(T(9), { y: 30, rx: -6 });
  k(T(9) + 0.5, { x: -300, y: 0, z: Z1 + 380, rx: 0, ry: 8 });
  k(T(11) - 0.05, { x: 300, ry: -8 });
  // hard cut to a high angle as the cards drop into the lean bar
  cut(T(11), { x: 0, y: 140, z: Z1 + 260, rx: 14, ry: 0 });
  k(T(12) - 0.1, { y: 170, z: Z1 + 200, rx: 18 });
  // feed: one slow continuous orbit around the phones
  cut(T(12), { x: 120, y: 0, z: Z1 + 330, rx: 0, ry: 26 });
  k(T(16), { x: 140, z: Z1 + 260, ry: -14 });
  // fast dolly across to the story scene
  k(T(16) + 0.9, { x: 200, z: Z1 + 200, ry: -20 });
  k(T(16) + 1.6, { x: X3, y: 0, z: Z3 + 900, rx: 0, ry: 0 });

  // S3: locked-off title, drop to a low angle as the phone rises, slow crane up over the callouts
  k(T(17.6), { z: Z3 + 860 });
  k(T(18) + 0.4, { y: 80, z: Z3 + 260, rx: -8 });
  k(T(22) - 0.1, { y: -100, z: Z3 + 200, rx: 8 });
  // hard cut to a side angle for the second phone
  cut(T(22), { x: X3 + 120, y: 0, z: Z3 + 380, rx: 0, ry: -26 });
  k(T(23.6), { x: X3 + 160, ry: -12 });

  // S4 blindspots: hard cut onto a dutch tilt that straightens when the phone arrives
  cut(T(24), { x: 0, y: 0, z: Z4 + 60, rx: 0, ry: 0, rz: R - 8 });
  k(T(26), { z: Z4, rz: R - 5 });
  k(T(26) + 0.9, { z: Z4 - 10, rz: R });
  k(T(29), { x: -20, z: Z4 - 40, ry: 0 });
  k(T(31), { x: 60, z: Z4 - 160, ry: 10 });

  // S5 world: overhead angle on the globe that tilts down to face it
  cut(T(31.4), { x: 0, y: 0, z: Z5, rx: 60, ry: 0, rz: R });
  k(T(32), { z: Z5 + 160, rx: 0 });
  k(T(34), { z: Z5 - 40 });
  // gates: a quarter roll snapped onto every beat
  const B = BEAT, zAt = (t) => Z5 - 40 - (600 * (t - T(34))) / B;
  for (let i = 0; i < 4; i++) {
    const a = T(34) + B * i;
    if (i) k(a, { z: zAt(a), rz: R + 90 * i });
    k(a + 0.28, { z: zAt(a + 0.28), rz: R + 90 * (i + 1) });
  }
  k(T(35), { z: zAt(T(35)), rz: R2 });
  // explore: locked off
  k(T(35) + B * 2, { x: 0, z: ZE + 200 });
  k(T(36), { z: ZE + 60 });
  k(T(39.5), { z: ZE - 30 });

  // S6 values: a new angle hard-cut on every word
  [{ x: 0, y: 0, z: Z6 + 120, rx: 0, ry: 0, rz: R2 },
    { x: 0, y: 120, z: Z6 + 80, rx: -16, ry: 14, rz: R2 },
    { x: 0, y: -100, z: Z6 + 80, rx: 16, ry: -14, rz: R2 },
    { x: 0, y: 0, z: Z6 + 60, rx: 0, ry: 0, rz: R2 - 6 }].forEach((v, i) => {
    const a = T(40) + B * 2 * i;
    cut(a, v);
    k(a + B * 2 - 0.05, { z: v.z - 40 });
  });

  // S7 open source: slow push, nothing else
  cut(T(42), { x: 0, y: 0, z: Z7 + 520, rx: 0, ry: 0, rz: R2 });
  k(T(43.8), { z: Z7 + 160 });

  // S8 finale: cranes down from a high angle to eye level
  cut(T(44), { x: 0, y: -380, z: Z8 + 420, rx: 28, ry: 0, rz: R2 });
  k(T(45), { y: 0, z: Z8 + 140, rx: 0 });
  k(T(48), { z: Z8 + 60 });
}

/* Camera for the 1-minute cut: one continuous flight, no cuts. Times are
   bars of the full film; T() retimes them to the short film. */
function shortCamera() {
  const k = fkey, R = 360, R2 = 720, B = BEAT;
  const Z1 = -4000, X3 = 1400, Z3 = -8000, Z4 = -12000, Z5 = -16000, ZE = -19000, Z6 = -21000, Z7 = -22600, Z8 = -24000;
  // intro: spiral push-in onto the logo, an arc across the wordmark and tagline,
  // then a crash zoom through the rings with a barrel roll into the drop
  k(0, { x: 160, y: -260, z: 1150, rx: 18, ry: 24, rz: -28 });
  k(T(1), { x: 0, y: -60, z: 640, rx: 0, ry: 0, rz: -4 });
  k(T(2), { x: -60, y: 20, z: 560, ry: -10, rz: 0 });
  k(T(4), { x: 60, y: 40, z: 470, ry: 10, rz: 2 });
  k(T(6.6), { x: 0, y: 0, z: 380, ry: 0, rz: 0 });
  k(T(8) - 0.04, { z: -3350, rz: R });
  // one story: orbit sweep over the title, drop low as the headlines fly in,
  // rise to a high angle, crane down onto the lean bar
  k(T(8) + 0.6, { z: Z1 + 150, ry: -18 });
  k(T(9), { z: Z1 + 60, ry: 14 });
  k(T(9) + 0.6, { y: 60, z: Z1 + 420, rx: -8, ry: 0 });
  k(T(11), { y: -120, z: Z1 + 420, rx: 22, ry: -10 });
  k(T(12) - 0.2, { y: 100, z: Z1 + 260, rx: 8, ry: 0 });
  // feed: swing round to the right, then a long orbit back across the phones
  k(T(12) + 0.5, { x: 220, y: 0, z: Z1 + 460, rx: 0, ry: 32 });
  k(T(14), { x: 140, z: Z1 + 330, ry: -4 });
  k(T(16), { x: 180, z: Z1 + 260, ry: -16 });
  // banking turn across to the story page, arriving low
  k(T(17), { x: 900, y: -150, z: -6300, ry: 20, rz: R - 14 });
  k(T(18) + 0.2, { x: X3, y: 220, z: Z3 + 200, rx: -20, ry: -6, rz: R });
  // story page: crane up while orbiting
  k(T(20), { y: 0, z: Z3 + 300, rx: 0, ry: 12 });
  k(T(22), { x: X3 - 60, y: -80, z: Z3 + 340, rx: 10, ry: -10 });
  // linger on the story page, then dive across to blindspots, arriving as the
  // title lands and rolling upright
  k(T(22) + 0.25, { x: X3 - 80, y: -90, z: Z3 + 300, rx: 8, ry: -12 });
  k(T(24), { x: 200, y: -60, z: Z4 + 1100, rx: 0, ry: -8, rz: R - 22 });
  k(T(24) + 0.5, { x: 0, y: -40, z: Z4 + 420, ry: 0, rz: R - 14 });
  k(T(25), { y: 0, z: Z4 + 60, rz: R - 6 });
  // orbit right as the phone rises, then left across the tiles
  k(T(26) + 0.7, { x: 140, y: 40, z: Z4 + 180, ry: -18, rz: R });
  k(T(28), { x: -40, y: 60, z: Z4 + 60, rx: -6, ry: 12 });
  k(T(30), { x: -60, y: 40, z: Z4 + 20, rx: -4, ry: 14 });
  // swoop up and over, diving down onto the globe
  k(T(31.4), { x: 0, y: -520, z: Z5 + 1300, rx: 32, ry: 0 });
  k(T(32) + 0.3, { y: 0, z: Z5 + 380, rx: 0 });
  k(T(34), { z: Z5 - 40 });
  // gates: one smooth barrel roll through all four
  for (let i = 1; i <= 4; i++) k(T(34) + B * i, { z: Z5 - 40 - 600 * i, rz: R + 90 * i });
  // explore: drift left, then orbit right
  k(T(35) + B * 2, { x: 0, z: ZE + 300 });
  k(T(36), { x: -60, z: ZE + 200, ry: -12 });
  k(T(38), { x: 120, z: ZE + 120, ry: 14 });
  k(T(39.5), { x: 60, z: ZE + 60, ry: 6 });
  // hold just short of the explore plane until the first value appears ahead, then rush to it
  k(T(40), { x: 0, z: ZE - 420, ry: 0 });
  // values: the camera swings like a pendulum, landing on each word
  k(T(40) + 0.45, { x: 0, y: 0, z: Z6 + 220, rx: 0, ry: 18, rz: R2 - 12 });
  k(T(40) + B * 2 + 0.3, { y: 60, z: Z6 + 160, rx: -10, ry: -14, rz: R2 + 8 });
  k(T(40) + B * 4 + 0.3, { y: -50, z: Z6 + 140, rx: 10, ry: 16, rz: R2 - 6 });
  k(T(40) + B * 6 + 0.3, { y: 0, z: Z6 + 100, rx: 0, ry: -8, rz: R2 + 8 });
  k(T(42), { ry: 0, rz: R2, z: Z6 + 40 });
  // open source: an arc on the breakdown
  k(T(42) + 0.4, { x: -200, z: Z7 + 600, ry: -20, rz: R2 + 6 });
  k(T(44) - 0.1, { x: 0, z: Z7 + 220, ry: 6, rz: R2 });
  // finale: swoop up and over, then crane down to eye level
  k(T(44) + 0.45, { y: -600, z: Z8 + 760, rx: 40, ry: 0, rz: R2 - 16 });
  k(T(45), { y: 0, z: Z8 + 160, rx: 0, rz: R2 });
  k(T(46.5), { x: -40, z: Z8 + 100, ry: -6 });
  k(T(48), { x: 40, z: Z8 + 20, ry: 6 });
}

// ---------- per-frame ----------
function frame(t) {
  C = camAt(t);
  cam.style.transform = `rotateZ(${(-C.rz).toFixed(3)}deg) rotateX(${(-C.rx).toFixed(3)}deg) rotateY(${(-C.ry).toFixed(3)}deg) translate3d(${(-C.x).toFixed(2)}px,${(-C.y).toFixed(2)}px,${(-C.z).toFixed(2)}px)`;
  drawBG(t);
  for (const e of ents) {
    if (t < e.t0 || t > e.t1) { if (e.vis) { e.el.style.display = 'none'; e.vis = false; } continue; }
    Object.assign(e, e.b);
    if (e.upd) e.upd(t, e);
    const dz = e.z - C.z;
    let o = e.o;
    // fog in the distance, fade out when very close / behind the camera
    o *= 1 - smooth(-3200, -6800, dz);
    // the flat cut pops things out as the camera passes them instead of ghosting them
    if (e.near) o *= SHORT ? 1 - smooth(P * 0.45, P * 0.65, dz) : FLAT ? (dz > P * 0.7 ? 0 : 1) : 1 - smooth(P * 0.55, P * 0.9, dz);
    if (o < 0.004 || dz > P * 0.95) { if (e.vis) { e.el.style.display = 'none'; e.vis = false; } continue; }
    if (!e.vis) { e.el.style.display = ''; e.vis = true; }
    e.el.style.opacity = o.toFixed(3);
    e.el.style.transform = `translate3d(${e.x.toFixed(2)}px,${e.y.toFixed(2)}px,${e.z.toFixed(2)}px) rotateX(${e.rx.toFixed(2)}deg) rotateY(${e.ry.toFixed(2)}deg) rotateZ(${e.rz.toFixed(2)}deg) scale(${e.s.toFixed(4)}) translate(-${e.ax}%,-${e.ay}%)`;
  }
  drawFX(t);
  if (location.hash === '#debug') { fx.fillStyle = '#ff0'; fx.font = '28px monospace'; fx.fillText(`t=${t.toFixed(2)} x=${C.x.toFixed(0)} y=${C.y.toFixed(0)} z=${C.z.toFixed(0)} rx=${C.rx.toFixed(1)} ry=${C.ry.toFixed(1)} rz=${C.rz.toFixed(1)}`, 30, 50); }
}

async function setup(data) {
  D = data; BAR0 = data.bars[0]; BEAT = data.beat;
  if (FLAT) document.body.classList.add('flat');
  END = T(48);
  prerender();
  build();
  await document.fonts.ready;
  await Promise.all([...document.images].map((i) => (i.complete ? null : new Promise((r) => { i.onload = i.onerror = r; }))));
  await Promise.all([...document.images].map((i) => i.decode().catch(() => null)));
  return END;
}
window.setup = setup;
window.frame = frame;
